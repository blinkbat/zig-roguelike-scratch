import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
args, remaining = parser.parse_known_args()


class GroundSheetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cistern-ground-test-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.sheet = self.work / 'ground.aseprite'
        self.run_lua('''
local s=Sprite(512,448,ColorMode.RGB)
s.layers[1].name='Paper - hide for transparent export'
local paper=Image(512,448,ColorMode.RGB)
paper:clear(app.pixelColor.rgba(240,240,240,255))
s:newCel(s.layers[1],1,paper,Point(0,0))
local l=s:newLayer(); l.name='64x64 grid'
local grid=Image(1,1,ColorMode.RGB)
grid:clear(app.pixelColor.rgba(40,40,40,255))
s:newCel(l,1,grid,Point(0,0))
s:saveAs(app.params.style); s:close()
local labels=Image(512,320,ColorMode.RGB)
labels:putPixel(12,8,app.pixelColor.rgba(50,50,50,255))
labels:saveAs(app.params.labels)
''')
        self.generate()

    def command(self, script, *parameters):
        command = [args.aseprite, '--batch']
        for value in (
            'root=' + ROOT.as_posix() + '/',
            'out=' + self.sheet.as_posix(),
            'style=' + (self.work / 'style.aseprite').as_posix(),
            'labels=' + (self.work / 'labels.png').as_posix(),
            'tint=100,120,140',
            *parameters,
        ):
            command += ['--script-param', value]
        return subprocess.run(command + ['--script', str(script)], capture_output=True, text=True)

    def run_lua(self, source):
        script = self.work / 'fixture.lua'
        script.write_text(source, encoding='utf-8')
        result = self.command(script)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def generate(self, replace=False):
        result = self.command(ROOT / 'tools/tile_art/ground_sheet.lua', *(['replace=yes'] if replace else []))
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_unchanged_blank_template_can_be_replaced(self):
        self.generate(replace=True)

    def test_modified_templates_are_refused_without_changing_the_file(self):
        baseline = self.sheet.read_bytes()
        cases = {
            'extra painted layer': "local l=s:newLayer(); l.name='Owner art'; s:newCel(l,1,paint,Point(0,0))",
            'extra painted frame': "s:newFrame(); s:newCel(s.layers[5],2,paint,Point(0,0))",
            'painted group': "s:deleteLayer(s.layers[5]); local group=s:newGroup(); group.name='Draw here'; local l=s:newLayer(); l.parent=group; s:newCel(l,1,paint,Point(0,0))",
            'missing paint layer': 's:deleteLayer(s.layers[5])',
            'painted drawing': 's:newCel(s.layers[5],1,paint,Point(0,0))',
            'painted guide': 's:newCel(s.layers[2],1,paint,Point(0,0))',
            'off-canvas guide painting': 'local c=s.layers[2]:cel(1); local im=Image(513,320,ColorMode.RGB); im:drawImage(c.image,c.position); im:putPixel(512,0,app.pixelColor.rgba(255,0,0,255)); s:newCel(s.layers[2],1,im,Point(0,0))',
            'changed guide opacity': 's.layers[2].opacity=128',
            'moved slice': 's.slices[1].bounds=Rectangle(1,64,64,64)',
        }
        for name, change in cases.items():
            with self.subTest(name=name):
                self.sheet.write_bytes(baseline)
                self.run_lua('''
local s=assert(app.open(app.params.out))
local paint=Image(1,1,ColorMode.RGB)
paint:clear(app.pixelColor.rgba(255,0,0,255))
''' + change + '\ns:saveAs(app.params.out); s:close()\n')
                before = hashlib.sha256(self.sheet.read_bytes()).digest()
                result = self.command(ROOT / 'tools/tile_art/ground_sheet.lua', 'replace=yes')
                self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertIn('Preserving', result.stdout + result.stderr)
                self.assertEqual(before, hashlib.sha256(self.sheet.read_bytes()).digest())


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
