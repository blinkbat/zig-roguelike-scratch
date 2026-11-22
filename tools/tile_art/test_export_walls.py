import os
from pathlib import Path
import stat
import tempfile
import unittest

from PIL import Image

from art_support import arguments, aseprite, main


args, remaining = arguments()


class WallExportTests(unittest.TestCase):
    def publish(self, readonly):
        source = (args.scripts_dir / 'export_walls.lua').read_text(encoding='utf-8')
        publication = source[source.index('local png=sourceFiles.stagePng(atlas'):]
        with tempfile.TemporaryDirectory(prefix='cistern-wall-export-test-') as temporary:
            root = Path(temporary)
            output = root / 'assets/walls/walls.png'
            output.parent.mkdir(parents=True)
            Image.new('RGBA', (2, 2), (90, 80, 70, 255)).save(output)
            before = output.read_bytes()
            layered = root / 'assets/source/walls.aseprite'
            layered.parent.mkdir(parents=True)
            layered.write_bytes(b'owner\x00layered\xffsource')
            layered_before = layered.read_bytes()
            script = root / 'publish.lua'
            script.write_text('''
local root=app.params.root..'/'
local sourceFiles=dofile(app.params.helper)
local atlas=Image(2,2,ColorMode.RGB)
atlas:clear(app.pixelColor.rgba(10,20,30,255))
local runtime=Sprite(2,2,ColorMode.RGB)
runtime.layers[1].name='Runtime walls'
runtime:newCel(runtime.layers[1],1,atlas,Point(0,0))
''' + publication + '\nprint("PUBLICATION_COMPLETE")\n', encoding='utf-8')
            if readonly:
                output.chmod(stat.S_IREAD)
            try:
                result = aseprite(args.aseprite, script,
                                  {'root': root, 'helper': args.scripts_dir / 'source_files.lua'})
                message = result.stdout + result.stderr
                if readonly:
                    self.assertNotEqual(0, result.returncode, message)
                    self.assertIn('Permission denied', message)
                    self.assertNotIn('PUBLICATION_COMPLETE', message)
                    self.assertEqual(before, output.read_bytes())
                    self.assertEqual(layered_before, layered.read_bytes())
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
    main(remaining)
