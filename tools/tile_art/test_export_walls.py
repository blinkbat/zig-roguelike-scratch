import argparse
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
args, remaining = parser.parse_known_args()


class WallExportTests(unittest.TestCase):
    def publish(self, readonly):
        source = (ROOT / 'tools/tile_art/export_walls.lua').read_text(encoding='utf-8')
        publication = source[source.index('exported:saveAs('):]
        with tempfile.TemporaryDirectory(prefix='cistern-wall-export-test-') as temporary:
            root = Path(temporary)
            output = root / 'assets/walls/walls.png'
            output.parent.mkdir(parents=True)
            Image.new('RGBA', (2, 2), (90, 80, 70, 255)).save(output)
            before = output.read_bytes()
            script = root / 'publish.lua'
            script.write_text('''
local root=app.params.root..'/'
local atlas=Image(2,2,ColorMode.RGB)
atlas:clear(app.pixelColor.rgba(10,20,30,255))
local exported=Image(atlas)
''' + publication + '\nprint("PUBLICATION_COMPLETE")\n', encoding='utf-8')
            if readonly:
                output.chmod(stat.S_IREAD)
            try:
                result = subprocess.run(
                    [args.aseprite, '--batch', '--script-param', 'root=' + root.as_posix(),
                     '--script', str(script)], capture_output=True, text=True, timeout=30,
                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
                )
                message = result.stdout + result.stderr
                if readonly:
                    self.assertNotEqual(0, result.returncode, message)
                    self.assertIn('Wall PNG export changed pixels or did not save', message)
                    self.assertNotIn('PUBLICATION_COMPLETE', message)
                    self.assertEqual(before, output.read_bytes())
                else:
                    self.assertEqual(0, result.returncode, message)
                    self.assertIn('PUBLICATION_COMPLETE', message)
                    with Image.open(output) as saved:
                        self.assertEqual(Image.new('RGBA', (2, 2), (10, 20, 30, 255)).tobytes(),
                                         saved.convert('RGBA').tobytes())
            finally:
                output.chmod(stat.S_IWRITE | stat.S_IREAD)

    def test_runtime_png_contains_the_exported_pixels(self):
        self.publish(False)

    @unittest.skipUnless(os.name == 'nt', 'Windows read-only destination behavior')
    def test_failed_png_save_cannot_report_success_with_stale_pixels(self):
        self.publish(True)


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
