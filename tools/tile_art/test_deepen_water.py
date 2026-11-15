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


class DeepenWaterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cistern-deepen-test-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.source = self.work / 'source.aseprite'
        self.output = self.work / 'deep.aseprite'
        self.canonical = self.work / 'assets/source/deep-water.aseprite'
        self.canonical.parent.mkdir(parents=True)
        self.run_lua('''
local s=Sprite(512,320,ColorMode.RGB)
s.layers[1].name='Draw here'
local paint=Image(2,2,ColorMode.RGB)
paint:putPixel(0,0,app.pixelColor.rgba(91,122,153,255))
paint:putPixel(1,1,app.pixelColor.rgba(17,43,81,128))
s:newCel(s.layers[1],1,paint,Point(3,67))
local extension=s:newLayer(); extension.name='Water extensions'
s:newCel(extension,1,paint,Point(70,130))
local labels=s:newLayer(); labels.name='Labels - hide before export'
s:newCel(labels,1,paint,Point(12,8))
for i=1,16 do
 local slice=s:newSlice(Rectangle(((i-1)%4)*64,64+((i-1)//4)*64,64,64))
 slice.name='Corners '..(i-1)
end
s:saveAs(app.params.source); s:close()
local labels=Image(512,320,ColorMode.RGB)
labels:putPixel(12,8,app.pixelColor.rgba(40,50,60,255))
labels:saveAs(app.params.labels)
''')

    def command(self, script):
        command = [args.aseprite, '--batch']
        for value in (
            'root=' + self.work.as_posix() + '/',
            'work=' + self.work.as_posix(),
            'source=' + self.source.as_posix(),
            'out=' + self.output.as_posix(),
            'labels=' + (self.work / 'labels.png').as_posix(),
            'install=yes',
        ):
            command += ['--script-param', value]
        return subprocess.run(command + ['--script', str(script)], capture_output=True, text=True)

    def run_lua(self, source):
        script = self.work / 'fixture.lua'
        script.write_text(source, encoding='utf-8')
        result = self.command(script)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_existing_reference_paint_is_preserved_without_installing(self):
        self.run_lua('''
local s=Sprite(512,320,ColorMode.RGB)
s.layers[1].name='Draw here'
local reference=s:newLayer(); reference.name='Owner painted reference'
local paint=Image(1,1,ColorMode.RGB)
paint:clear(app.pixelColor.rgba(255,0,0,255))
s:newCel(reference,1,paint,Point(10,10))
s:saveAs(app.params.out); s:close()
''')
        before = hashlib.sha256(self.output.read_bytes()).digest()
        source_before = self.source.read_bytes()
        result = self.command(ROOT / 'tools/tile_art/deepen_water.lua')
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('Preserving existing deep-water artwork', result.stdout + result.stderr)
        self.assertEqual(before, hashlib.sha256(self.output.read_bytes()).digest())
        self.assertEqual(source_before, self.source.read_bytes())
        self.assertFalse(self.canonical.exists())

    def test_fresh_destination_installs_toned_pixels_and_preserves_source(self):
        source_before = self.source.read_bytes()
        result = self.command(ROOT / 'tools/tile_art/deepen_water.lua')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertTrue(self.output.is_file())
        self.assertTrue(self.canonical.is_file())
        self.assertEqual(source_before, self.source.read_bytes())
        self.run_lua('''
local pc=app.pixelColor
local source=assert(app.open(app.params.source))
for _,path in ipairs({app.params.out,app.params.root..'assets/source/deep-water.aseprite'}) do
 local saved=assert(app.open(path))
 assert(saved.width==source.width and saved.height==source.height and #saved.frames==1)
 assert(#saved.layers==#source.layers and #saved.slices==#source.slices)
 for i,original in ipairs(source.layers) do
  local layer=saved.layers[i]
  assert(layer.name==original.name)
  if original.name=='Draw here' or original.name=='Water extensions' then
   local before,after=assert(original:cel(1)),assert(layer:cel(1))
   assert(after.position.x==before.position.x and after.position.y==before.position.y)
   assert(after.image.width==before.image.width and after.image.height==before.image.height)
   for pixel in before.image:pixels() do
    local p=pixel()
    local actual=after.image:getPixel(pixel.x,pixel.y)
    assert(pc.rgbaA(actual)==pc.rgbaA(p),'Alpha changed')
    if pc.rgbaA(p)>0 then
     assert(pc.rgbaR(actual)==math.floor(pc.rgbaR(p)*0.6+0.5),'Wrong red')
     assert(pc.rgbaG(actual)==math.floor(pc.rgbaG(p)*0.6+0.5),'Wrong green')
     assert(pc.rgbaB(actual)==math.floor(pc.rgbaB(p)*0.6+0.5),'Wrong blue')
    end
   end
  end
 end
 local slices={}
 for _,slice in ipairs(saved.slices) do slices[slice.name]=slice end
 for _,original in ipairs(source.slices) do
  local slice=assert(slices[original.name])
  local a,b=original.bounds,slice.bounds
  assert(slice.name==original.name and a.x==b.x and a.y==b.y and a.width==b.width and a.height==b.height)
 end
 saved:close()
end
source:close()
''')


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
