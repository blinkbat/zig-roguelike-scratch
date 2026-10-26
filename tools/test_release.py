import contextlib
import io
import json
import pathlib
import re
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import release


class ReleaseTests(unittest.TestCase):
    def test_packages_preserve_all_map_folders(self):
        maps = release.map_paths()
        expected = {path.relative_to(release.ROOT).as_posix(): path.read_bytes() for path in maps}
        self.assertTrue(any(path.parent != release.MAPS for path in maps))
        with tempfile.TemporaryDirectory(prefix='cistern-release-test-') as temporary:
            root = pathlib.Path(temporary)
            binary = root / release.EXE
            binary.write_bytes(b'test executable')
            for platform in ('linux', 'macos'):
                with self.subTest(platform=platform), contextlib.redirect_stdout(io.StringIO()):
                    release.package(binary, root, {}, platform, 'x86_64')
                    name = release.archive_name(platform, 'x86_64')
                    with tarfile.open(root / (name + '.tar.gz')) as archive:
                        actual = {
                            entry.name.removeprefix(name + '/'): archive.extractfile(entry).read()
                            for entry in archive if entry.name.startswith(name + '/maps/')
                        }
                        metadata = json.load(archive.extractfile(name + '/build-info.json'))
                        for license_name in ('Balthazar-OFL.txt', 'SourceSans3-OFL.txt', 'gamecontrollerdb-LICENSE'):
                            self.assertEqual((release.ASSETS / license_name).read_bytes(), archive.extractfile(name + '/licenses/' + license_name).read())
                    self.assertEqual(expected, actual)
                    for path, data in expected.items():
                        self.assertEqual(release.sha256(data), metadata['files'][path])
        print('release packages: both platforms preserve all', len(maps), 'maps and their hashes')

    def test_failed_publish_leaves_only_the_old_file(self):
        with tempfile.TemporaryDirectory(prefix='cistern-release-test-') as temporary:
            root = pathlib.Path(temporary)
            dest = root / 'out.bin'
            dest.write_bytes(b'old')

            def refuse(path):
                raise ValueError('mismatch')

            with self.assertRaises(ValueError):
                release.publish(dest, lambda stream: stream.write(b'new'), refuse)
            self.assertEqual([dest], list(root.iterdir()))
            self.assertEqual(b'old', dest.read_bytes())
            release.publish(dest, lambda stream: stream.write(b'new'))
            self.assertEqual([dest], list(root.iterdir()))
            self.assertEqual(b'new', dest.read_bytes())

    def test_partial_write_failure_preserves_old_file_and_removes_temporary(self):
        with tempfile.TemporaryDirectory(prefix='cistern-release-test-') as temporary:
            root = pathlib.Path(temporary)
            dest = root / 'out.bin'
            dest.write_bytes(b'old')

            def fail(stream):
                stream.write(b'partial replacement')
                raise OSError('write failed')

            with self.assertRaisesRegex(OSError, 'write failed'):
                release.publish(dest, fail)
            self.assertEqual(b'old', dest.read_bytes())
            self.assertEqual([dest], list(root.iterdir()))
        print('release publication: partial write failure preserves the old file and cleans temporary output')

    def test_download_checks_cache_and_rejects_bad_mirror_before_failover(self):
        good = b'verified dependency'
        record = {'name': 'fixture', 'sha256': release.sha256(good), 'urls': ['https://bad.invalid', 'https://good.invalid']}
        with tempfile.TemporaryDirectory(prefix='cistern-release-test-') as temporary:
            root = pathlib.Path(temporary)
            dest = root / 'downloads' / record['sha256']
            dest.parent.mkdir()
            dest.write_bytes(good)
            with patch.object(release.urllib.request, 'urlopen') as request:
                self.assertEqual(dest, release.download(record, root))
                request.assert_not_called()
            dest.write_bytes(b'corrupt cache')
            with patch.object(release.urllib.request, 'urlopen', side_effect=[io.BytesIO(b'bad mirror'), io.BytesIO(good)]) as request:
                self.assertEqual(dest, release.download(record, root))
                self.assertEqual(record['urls'], [call.args[0] for call in request.call_args_list])
            self.assertEqual(good, dest.read_bytes())
            self.assertEqual([dest], list(dest.parent.iterdir()))
        print('release downloads: valid cache avoids network; corrupt cache and bad mirror rejected before verified fallback')

    def test_failed_download_never_publishes_unverified_bytes(self):
        record = {'name': 'fixture', 'sha256': release.sha256(b'expected'), 'urls': ['https://offline.invalid', 'https://bad.invalid']}
        with tempfile.TemporaryDirectory(prefix='cistern-release-test-') as temporary:
            root = pathlib.Path(temporary)
            with patch.object(release.urllib.request, 'urlopen', side_effect=[OSError('offline'), io.BytesIO(b'wrong')]):
                with self.assertRaisesRegex(RuntimeError, 'Download failed for fixture'):
                    release.download(record, root)
            self.assertEqual([], list(root.rglob('*')))
        print('release downloads: exhausted mirrors leave no unverified files')

    def test_packages_are_reproducible_and_every_member_matches_its_manifest(self):
        with tempfile.TemporaryDirectory(prefix='cistern-release-test-') as temporary:
            root = pathlib.Path(temporary)
            binary = root / release.EXE
            binary.write_bytes(b'test executable')
            for platform, arch in (('linux', 'x86_64'), ('macos', 'x86_64'), ('macos', 'arm64')):
                with self.subTest(platform=platform, arch=arch), contextlib.redirect_stdout(io.StringIO()):
                    release.package(binary, root, {'target': arch}, platform, arch)
                    name = release.archive_name(platform, arch)
                    archive_path = root / (name + '.tar.gz')
                    first = archive_path.read_bytes()
                    release.package(binary, root, {'target': arch}, platform, arch)
                    self.assertEqual(first, archive_path.read_bytes())
                    checksum = archive_path.with_suffix(archive_path.suffix + '.sha256').read_text(encoding='ascii')
                    self.assertEqual(release.sha256(first) + '  ' + archive_path.name + '\n', checksum)
                    with tarfile.open(archive_path) as archive:
                        members = archive.getmembers()
                        names = [entry.name for entry in members]
                        self.assertEqual(len(names), len(set(names)))
                        metadata = json.load(archive.extractfile(name + '/build-info.json'))
                        self.assertEqual(arch, metadata['target'])
                        self.assertEqual(len(members) - 1, len(metadata['files']))
                        for entry in members:
                            relative = entry.name.removeprefix(name + '/')
                            self.assertTrue(entry.name.startswith(name + '/'))
                            self.assertTrue(entry.isfile())
                            self.assertNotIn('..', pathlib.PurePosixPath(relative).parts)
                            self.assertFalse(relative.startswith('saves/'))
                            self.assertEqual(0, entry.mtime)
                            executable = relative in (release.EXE, 'run.sh', 'run.command')
                            self.assertEqual(0o755 if executable else 0o644, entry.mode)
                            if relative != 'build-info.json':
                                self.assertEqual(metadata['files'][relative], release.sha256(archive.extractfile(entry).read()))
                        launcher = release.LINUX_LAUNCHER if platform == 'linux' else release.LAUNCHER
                        self.assertEqual(launcher, archive.extractfile(name + '/run.sh').read())
                        self.assertEqual(platform == 'macos', name + '/run.command' in names)
        print('release archives: 3 targets reproduce byte-for-byte; all member hashes, modes, timestamps, launchers and checksums verified')

    def test_nested_map_changes_affect_source_hash(self):
        nested = next(path for path in release.map_paths() if path.parent != release.MAPS)
        before = release.source_hash()
        read_bytes = pathlib.Path.read_bytes

        def changed(path):
            data = read_bytes(path)
            return data + b'\n' if path == nested else data

        with patch.object(pathlib.Path, 'read_bytes', changed):
            self.assertNotEqual(before, release.source_hash())
        print('release source hash detects a nested map change without writing it')

    def test_source_hash_embeds_what_build_zig_embeds(self):
        build = (release.ROOT / 'build.zig').read_text(encoding='utf-8')
        listed = re.search(r'^const EMBEDDED = \[_\]\[\]const u8\{(.*)\};$', build, re.M)
        self.assertIsNotNone(listed)
        self.assertEqual(release.EMBEDDED, tuple(re.findall(r'"([^"]+)"', listed.group(1))))
        print('release source hash covers build.zig\'s', len(release.EMBEDDED), 'embedded extensions')

    def test_packages_the_executable_build_zig_names(self):
        build = (release.ROOT / 'build.zig').read_text(encoding='utf-8')
        named = re.search(r'b\.addExecutable\(\.\{ \.name = "([^"]+)"', build)
        self.assertIsNotNone(named)
        self.assertEqual(named.group(1), release.EXE)
        toolchain = (release.ROOT / '_zig.cmd').read_text(encoding='utf-8')
        self.assertIn('set "EXE=' + release.EXE + '.exe"', toolchain)

    def test_lock_pins_the_zig_build_zig_zon_requires(self):
        zon = (release.ROOT / 'build.zig.zon').read_text(encoding='utf-8')
        wanted = re.search(r'\.minimum_zig_version = "([^"]+)"', zon)
        self.assertIsNotNone(wanted)
        lock = json.loads(release.LOCK_PATH.read_text(encoding='utf-8'))
        self.assertEqual(wanted.group(1), lock['zig_version'])
        toolchain = (release.ROOT / '_zig.cmd').read_text(encoding='utf-8')
        self.assertIn('set "ZIG_VERSION=' + lock['zig_version'] + '"', toolchain)
        print('release lock, Windows wrapper and build.zig.zon all pin Zig', lock['zig_version'])


if __name__ == '__main__':
    unittest.main()
