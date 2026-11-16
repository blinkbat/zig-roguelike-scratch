import argparse
from pathlib import Path
import subprocess
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
args, remaining = parser.parse_known_args()


class WaterCliffExportTests(unittest.TestCase):
    def test_png_suffixes_keep_atlas_and_auxiliary_outputs_distinct(self):
        with tempfile.TemporaryDirectory(prefix='cistern-cliff-export-test-') as temporary:
            work = Path(temporary)
            source = work / 'source.aseprite'
            fixture = work / 'fixture.lua'
            fixture.write_text('''
local s=Sprite(192,64,ColorMode.RGB)
s.layers[1].name='Paint'
local paint=Image(192,64,ColorMode.RGB)
for y=16,39 do for x=0,191 do
 paint:putPixel(x,y,app.pixelColor.rgba(80,100,120,255))
end end
s:newCel(s.layers[1],1,paint,Point(0,0))
for i,name in ipairs({'left','repeat','right'}) do
 local slice=s:newSlice(Rectangle((i-1)*64,0,64,64))
 slice.name='water_cliff_deep_'..name
end
s:saveAs(app.params.source); s:close()
''', encoding='utf-8')
            self.run_script(fixture, source=source)
            for suffix in ('.png', '.PNG', '.PnG'):
                with self.subTest(suffix=suffix):
                    output = work / ('cliff' + suffix)
                    self.run_script(ROOT / 'tools/tile_art/export_water_cliff.lua',
                                    source=source, depth='deep', layer='Paint', out=output)
                    with Image.open(output) as image:
                        atlas = image.convert('RGBA')
                    self.assertEqual((192, 64), atlas.size)
                    self.assertEqual((80, 100, 120, 255), atlas.getpixel((64, 16)))
                    self.assertEqual(0, atlas.getpixel((64, 0))[3])
                    with Image.open(work / 'cliff-cap.png') as image:
                        self.assertEqual((255, 255, 255, 255), image.convert('RGBA').getpixel((64, 0)))
                    for name, expected in (('foot', 40), ('lip', 16)):
                        values = (work / ('cliff-' + name + '.txt')).read_text().strip().split(',')
                        self.assertEqual([str(expected)] * 192, values)
            output = work / 'cliff.jpg'
            output.write_bytes(b'existing output')
            self.run_script(ROOT / 'tools/tile_art/export_water_cliff.lua', expected=1,
                            source=source, depth='deep', layer='Paint', out=output)
            self.assertEqual(b'existing output', output.read_bytes())

    def run_script(self, script, expected=0, **params):
        command = [args.aseprite, '--batch']
        for key, value in params.items():
            if isinstance(value, Path):
                value = value.as_posix()
            command += ['--script-param', f'{key}={value}']
        result = subprocess.run(command + ['--script', str(script)], capture_output=True,
                                text=True, timeout=30,
                                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if expected == 0:
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        else:
            self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn('out must name a PNG file', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
