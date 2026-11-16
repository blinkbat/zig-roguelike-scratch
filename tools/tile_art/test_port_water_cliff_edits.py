import argparse
from pathlib import Path
import subprocess
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
parser.add_argument('--scripts-dir', type=Path, default=ROOT / 'tools/tile_art')
args, remaining = parser.parse_known_args()


class WaterCliffPortTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cistern-water-port-test-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.original = self.work / 'original.aseprite'
        self.baseline = self.work / 'baseline.png'
        self.owner = self.work / 'owner.png'
        self.output = self.work / 'output.aseprite'
        self.preview = self.work / 'preview.png'
        self.report = self.work / 'report.txt'
        fixture = self.work / 'fixture.lua'
        fixture.write_text('''
local w=app.params.work
local s=Sprite(960,640,ColorMode.RGB)
s.layers[1].name='Base'
local image=Image(960,640,ColorMode.RGB)
image:putPixel(10,10,app.pixelColor.rgba(20,30,40,255))
image:putPixel(40,110,app.pixelColor.rgba(50,60,70,255))
image:putPixel(360,110,app.pixelColor.rgba(30,36,42,255))
s:newCel(s.layers[1],1,image,Point(0,0))
for _,name in ipairs({'Land to shallows - Cliff faces','Land to deep water - Cliff faces'}) do
 local layer=s:newLayer()
 layer.name=name
 local face=Image(960,640,ColorMode.RGB)
 if name=='Land to shallows - Cliff faces' then
  face:putPixel(50,115,app.pixelColor.rgba(50,60,70,255))
 else
  for y=115,120 do face:putPixel(370,y,app.pixelColor.rgba(30,36,42,255)) end
 end
 s:newCel(layer,1,face,Point(0,0))
end
for i=1,54 do
 local slice=s:newSlice(Rectangle(i,1,1,1))
 slice.name='slice'..i
end
s:saveAs(w..'/original.aseprite')
s:saveCopyAs(w..'/baseline.png')
s:close()
''', encoding='utf-8')
        result = self.run_lua(fixture, work=self.work.as_posix())
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        with Image.open(self.baseline) as baseline:
            baseline.save(self.owner)

    def run_lua(self, script, **params):
        command = [args.aseprite, '--batch']
        for key, value in params.items():
            command += ['--script-param', f'{key}={value}']
        return subprocess.run(
            command + ['--script', str(script)],
            capture_output=True, text=True, timeout=30,
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
        )

    def port(self, output=None):
        return self.run_lua(
            args.scripts_dir / 'port_water_cliff_edits.lua',
            source=self.owner.as_posix(), baseline=self.baseline.as_posix(),
            original=self.original.as_posix(),
            output=(output or self.output).as_posix(),
            preview=self.preview.as_posix(), report=self.report.as_posix(),
            root=ROOT.as_posix() + '/',
        )

    def paint(self, at, color):
        with Image.open(self.owner) as source:
            edited = source.convert('RGBA')
        edited.putpixel(at, color)
        edited.save(self.owner)

    def expect_refused_without_writes(self, output=None):
        if output != self.original:
            self.output.write_bytes(b'previous owner output')
        self.preview.write_bytes(b'previous owner preview')
        self.report.write_bytes(b'previous validation report')
        before = {path: path.read_bytes() for path in self.work.iterdir() if path.is_file()}
        result = self.port(output)
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        after = {path: path.read_bytes() for path in self.work.iterdir() if path.is_file()}
        self.assertEqual(before, after, result.stdout + result.stderr)

    def test_erasure_refused_before_existing_destinations_change(self):
        self.paint((10, 10), (0, 0, 0, 0))
        self.expect_refused_without_writes()

    def test_erasure_refused_when_output_is_original(self):
        self.paint((10, 10), (0, 0, 0, 0))
        self.expect_refused_without_writes(self.original)

    def test_partial_alpha_refused_before_existing_destinations_change(self):
        self.paint((10, 10), (100, 110, 120, 128))
        self.expect_refused_without_writes()

    def test_mismatched_baseline_refused_before_existing_destinations_change(self):
        with Image.open(self.baseline) as source:
            edited = source.convert('RGBA')
        edited.putpixel((10, 10), (100, 110, 120, 255))
        edited.save(self.baseline)
        self.expect_refused_without_writes()

    def test_extension_refuses_to_overwrite_owner_deep_edit(self):
        self.paint((50, 115), (119, 146, 185, 255))
        self.paint((370, 116), (100, 110, 120, 255))
        self.expect_refused_without_writes()

    def test_surface_edit_extends_into_unmodified_deep_face(self):
        self.paint((50, 115), (119, 146, 185, 255))
        result = self.port()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        with Image.open(self.owner) as source:
            expected = source.convert('RGBA')
        for y in range(115, 121):
            expected.putpixel((370, y), (71, 88, 111, 255))
        with Image.open(self.preview) as actual:
            self.assertEqual(expected.tobytes(), actual.convert('RGBA').tobytes())

    def test_opaque_edits_preserved_and_transferred(self):
        self.paint((10, 10), (100, 110, 120, 255))
        self.paint((40, 110), (12, 34, 56, 255))
        original = self.original.read_bytes()
        result = self.port()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(original, self.original.read_bytes())
        self.assertTrue(self.output.is_file())
        self.assertIn('54 slices retained', self.report.read_text(encoding='utf-8'))
        with Image.open(self.owner) as source:
            expected = source.convert('RGBA')
        expected.putpixel((360, 110), (12, 34, 56, 255))
        with Image.open(self.preview) as actual:
            self.assertEqual(expected.tobytes(), actual.convert('RGBA').tobytes())


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
