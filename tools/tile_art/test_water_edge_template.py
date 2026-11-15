import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
args, remaining = parser.parse_known_args()


class WaterTemplateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cistern-water-test-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.sheet = self.work / 'water.aseprite'
        self.generate()

    def generate(self, replace=False, expected=0, temporary=None):
        command = [sys.executable, '-B', str(ROOT / 'tools/tile_art/water_edge_template.py'), '--output', str(self.sheet)]
        if replace:
            command.append('--replace-blank')
        env = os.environ.copy()
        env['PYTHONIOENCODING'] = 'utf-8'
        if temporary is not None:
            env.update(TEMP=str(temporary), TMP=str(temporary))
        generated = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', env=env)
        self.assertEqual(0, generated.returncode, generated.stdout + generated.stderr)
        assembly = Path(generated.stdout.strip()) / 'assemble.lua'
        result = subprocess.run([args.aseprite, '--batch', '--script', str(assembly)], capture_output=True, text=True)
        if expected == 0:
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        else:
            self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn('Preserving', result.stdout + result.stderr)

    def test_blank_template_can_be_replaced(self):
        self.generate(replace=True)

    def test_unicode_output_and_temporary_paths(self):
        directory = self.work / 'caf\u00e9-\u6c34'
        directory.mkdir()
        self.sheet = directory / 'water.aseprite'
        self.generate(temporary=directory)
        self.assertTrue(self.sheet.is_file())

    def test_changed_artwork_and_layout_are_preserved(self):
        baseline = self.sheet.read_bytes()
        cases = {
            'reference painting': 's:newCel(s.layers[4],1,paint,Point(0,0))',
            'drawing': 's:newCel(s.layers[7],1,paint,Point(0,0))',
            'extra frame': 's:newFrame(); s:newCel(s.layers[7],2,paint,Point(0,0))',
            'painted group': "s:deleteLayer(s.layers[7]); local g=s:newGroup(); g.name='Draw here'; local l=s:newLayer(); l.parent=g; s:newCel(l,1,paint,Point(0,0))",
            'off-canvas painting': 'local c=s.layers[4]:cel(1); local im=Image(513,512,ColorMode.RGB); im:drawImage(c.image,c.position); im:putPixel(512,0,app.pixelColor.rgba(255,0,0,255)); s:newCel(s.layers[4],1,im,Point(0,0))',
            'guide opacity': 's.layers[4].opacity=128',
            'moved slice': 's.slices[1].bounds=Rectangle(0,0,64,64)',
        }
        for name, change in cases.items():
            with self.subTest(name=name):
                self.sheet.write_bytes(baseline)
                script = self.work / 'edit.lua'
                script.write_text('local s=assert(app.open(app.params.file))\nlocal paint=Image(1,1,ColorMode.RGB)\npaint:clear(app.pixelColor.rgba(255,0,0,255))\n' + change + '\ns:saveAs(app.params.file); s:close()\n', encoding='utf-8')
                result = subprocess.run([args.aseprite, '--batch', '--script-param', 'file=' + str(self.sheet), '--script', str(script)], capture_output=True, text=True)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                before = hashlib.sha256(self.sheet.read_bytes()).digest()
                self.generate(replace=True, expected=1)
                self.assertEqual(before, hashlib.sha256(self.sheet.read_bytes()).digest())


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
