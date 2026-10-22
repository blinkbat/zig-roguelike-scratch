import contextlib
import io
import json
import pathlib
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import release


class ReleaseTests(unittest.TestCase):
    def test_packages_preserve_all_map_folders(self):
        maps = release.map_paths()
        expected = {path.relative_to(release.ROOT).as_posix(): path.read_bytes() for path in maps}
        self.assertTrue(any(path.parent != release.ROOT / 'maps' for path in maps))
        with tempfile.TemporaryDirectory(prefix='cistern-release-test-') as temporary:
            root = pathlib.Path(temporary)
            binary = root / 'cistern'
            binary.write_bytes(b'test executable')
            for platform in ('linux', 'macos'):
                with self.subTest(platform=platform), contextlib.redirect_stdout(io.StringIO()):
                    release.package(binary, root, {}, platform, 'x86_64')
                    name = 'cistern-' + platform + '-x86_64'
                    with tarfile.open(root / (name + '.tar.gz')) as archive:
                        actual = {
                            entry.name.removeprefix(name + '/'): archive.extractfile(entry).read()
                            for entry in archive if entry.name.startswith(name + '/maps/')
                        }
                        metadata = json.load(archive.extractfile(name + '/build-info.json'))
                    self.assertEqual(expected, actual)
                    for path, data in expected.items():
                        self.assertEqual(release.sha256(data), metadata['files'][path])
        print('release packages: both platforms preserve all', len(maps), 'maps and their hashes')

    def test_nested_map_changes_affect_source_hash(self):
        nested = next(path for path in release.map_paths() if path.parent != release.ROOT / 'maps')
        before = release.source_hash()
        read_bytes = pathlib.Path.read_bytes

        def changed(path):
            data = read_bytes(path)
            return data + b'\n' if path == nested else data

        with patch.object(pathlib.Path, 'read_bytes', changed):
            self.assertNotEqual(before, release.source_hash())
        print('release source hash detects a nested map change without writing it')


if __name__ == '__main__':
    unittest.main()
