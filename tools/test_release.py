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
        print('release lock and build.zig.zon both pin Zig', lock['zig_version'])


if __name__ == '__main__':
    unittest.main()
