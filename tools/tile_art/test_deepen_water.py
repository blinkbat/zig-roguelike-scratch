import hashlib
import os
from pathlib import Path
import tempfile
import unittest

from art_support import ROOT, arguments, aseprite, main, read_locked


args, remaining = arguments()


class DeepenWaterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cistern-deepen-test-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.source = self.work / 'source.aseprite'
        self.output = self.work / 'deep.aseprite'
        self.canonical = self.work / 'assets/source/deep-water.aseprite'
        self.canonical.parent.mkdir(parents=True)
        helper = self.work / 'tools/tile_art/source_files.lua'
        helper.parent.mkdir(parents=True)
        helper.write_bytes((ROOT / 'tools/tile_art/source_files.lua').read_bytes())
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

    def command(self, script, install='yes'):
        return aseprite(args.aseprite, script, {
            'root': self.work.as_posix() + '/',
            'work': self.work,
            'source': self.source,
            'out': self.output,
            'labels': self.work / 'labels.png',
            'install': install,
        }, timeout=None)

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
        self.assertEqual(self.output.read_bytes(), self.canonical.read_bytes())
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

    def test_blocked_canonical_destination_fails_without_success_report(self):
        self.canonical.mkdir()
        source_before = self.source.read_bytes()
        result = self.command(ROOT / 'tools/tile_art/deepen_water.lua')
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(source_before, self.source.read_bytes())
        self.assertTrue(self.canonical.is_dir())
        self.assertTrue(self.output.is_file())
        self.assertFalse((self.work / 'water-depth-validation.txt').exists())

    @unittest.skipUnless(os.name == 'nt', 'Windows file sharing failure')
    def test_locked_stale_draft_with_missing_artwork_cannot_pass_validation(self):
        self.run_lua('''
local s=Sprite(512,320,ColorMode.RGB)
s.layers[1].name='Unrelated old draft'
s:saveAs(app.params.work..'/deep-water-draft.aseprite'); s:close()
''')
        draft = self.work / 'deep-water-draft.aseprite'
        before = draft.read_bytes()
        with read_locked(draft):
            result = self.command(ROOT / 'tools/tile_art/deepen_water.lua', install='no')
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(before, draft.read_bytes())
        self.assertFalse(self.canonical.exists())
        self.assertFalse((self.work / 'water-depth-validation.txt').exists())


if __name__ == '__main__':
    main(remaining)
