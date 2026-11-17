import argparse
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
args, remaining = parser.parse_known_args()

WRAPPER = r'''
local nativeApp=app
local function opened(path)
 local native=assert(nativeApp.open(path))
 return setmetatable({}, {
  __index=function(_,key)
   if key=='saveAs' and nativeApp.params.blocked=='yes' then
    return function() print('INJECTED_SAVE_NOOP') end
   end
   local value=native[key]
   if type(value)=='function' then return function(_,...) return value(native,...) end end
   return value
  end,
  __newindex=function(_,key,value) native[key]=value end,
 })
end
local customApp=setmetatable({open=opened},{__index=nativeApp,
 __newindex=function(_,key,value) nativeApp[key]=value end})
local env
env=setmetatable({app=customApp,dofile=function(path)
 if path:match('/export_walls%.lua$') then print('EXPORT_REACHED'); return end
 return assert(loadfile(path,'t',env))()
end},{__index=_G})
assert(loadfile(app.params.body,'t',env))()
print('PUBLICATION_COMPLETE')
'''

WALL_FIXTURE = r'''
local s=Sprite(512,448,ColorMode.RGB)
local function layer(name)
 local l=s:newLayer(); l.name=name
 local im=Image(2,2,ColorMode.RGB)
 im:clear(app.pixelColor.rgba(91,122,153,255))
 s:newCel(l,1,im,Point(3,67))
 return l
end
s:deleteLayer(s.layers[1])
layer('Layer 1')
layer('Underdrawing (25%)')
layer('Exact connection guide (hidden)')
layer('Pixel extension - copied colors, chips and bricks')
if app.params.existing=='yes' then layer('Ideas - hide before export') end
layer('Draw here')
for i=1,47 do
 local slice=s:newSlice(Rectangle(((i-1)%8)*64,64+math.floor((i-1)/8)*64,64,64))
 slice.name='Connection '..i
end
s:saveAs(app.params.source); s:close()
'''

WALL_SETUP = r'''
local root=app.params.root
local path=app.params.source
local work=app.params.work
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local sprite=assert(app.open(path))
local under,exact,drawing,authored,extension,ideas
for _,l in ipairs(sprite.layers) do
 if l.name=='Layer 1' then authored=l end
 if l.name=='Underdrawing (25%)' then under=l end
 if l.name=='Exact connection guide (hidden)' then exact=l end
 if l.name=='Draw here' then drawing=l end
 if l.name=='Pixel extension - copied colors, chips and bricks' then extension=l end
 if l.name=='Ideas - hide before export' then ideas=l end
end
local drawn=Image(drawing:cel(1).image)
local original=Image(authored:cel(1).image)
local position=Point(authored:cel(1).position)
local function generated(color)
 local im=Image(512,448,ColorMode.RGB)
 im:putPixel(0,0,color); im:putPixel(511,447,color)
 im:putPixel(70,130,color)
 return im
end
local FACE,NORTH=23,false
local faced=generated(app.pixelColor.rgba(17,43,81,255))
local flat=generated(app.pixelColor.rgba(19,47,89,255))
local completed=Image(faced)
'''

PINCH_FIXTURE = r'''
local work,root=app.params.work,app.params.root
local pc=app.pixelColor
if app.params.shots then
 local s=Sprite(320,400,ColorMode.RGB)
 s:deleteLayer(s.layers[1])
 for _,name in ipairs({'Ground','Cliff faces','Lip and cap fill'}) do
  local l=s:newLayer(); l.name='Land to shallows - '..name
  s:newCel(l,1,Image(1,1,ColorMode.RGB),Point(32,104))
 end
 local owner=s:newLayer(); owner.name='Owner flat border edits'
 local im=Image(320,400,ColorMode.RGB)
 im:clear(pc.rgba(91,122,153,255))
 s:newCel(owner,1,im,Point(0,0))
 s:saveAs(work..'water-cliff-connections.aseprite')
 s:saveCopyAs(root..'assets/source/water-cliff-connections.aseprite')
 s:saveCopyAs(work..'desktop-before.png'); s:close()
 local full=Image(256,256,ColorMode.RGB)
 for i=1,4 do
  local part=Image(256,256,ColorMode.RGB)
  part:putPixel(i*10,i*12,pc.rgba(10*i,20*i,30*i,255))
  part:saveAs(app.params.shots..'template-0-layer-'..i..'.png')
  full:drawImage(part,Point(0,0))
 end
 full:saveAs(app.params.shots..'template-0.png')
else
 local s=Sprite(192,64,ColorMode.RGB)
 for i=2,8 do s:newLayer() end
 local im=Image(64,8,ColorMode.RGB)
 im:clear(pc.rgba(91,122,153,255))
 s:newCel(s.layers[8],1,im,Point(0,8))
 local slice=s:newSlice(Rectangle(0,0,64,64)); slice.name='water_cliff_shallow_test'
 s:saveAs(work..'water-cliff-edge.aseprite')
 s:saveCopyAs(root..'assets/source/water-cliff-edge.aseprite'); s:close()
 local faces=Image(256,256,ColorMode.RGB)
 for y=8,15 do for x=0,63 do faces:putPixel(x,y,pc.rgba(30,50,70,255)) end end
 faces:saveAs(app.params.faces)
 local edges=Image(1280,256,ColorMode.RGB)
 edges:clear(pc.rgba(110,130,150,255))
 edges:saveAs(work..'dirt-shallows-edges.png')
end
'''


class SavedLayerTests(unittest.TestCase):
    def run_lua(self, script, **params):
        command = [args.aseprite, '--batch']
        for key, value in params.items():
            if isinstance(value, Path):
                value = value.as_posix()
            command += ['--script-param', f'{key}={value}']
        return subprocess.run(command + ['--script', str(script)], capture_output=True,
                              text=True, timeout=30,
                              creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))

    def fixture(self, directory, body, **params):
        script = directory / 'fixture.lua'
        script.write_text(body, encoding='utf-8')
        result = self.run_lua(script, **params)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def publication(self, directory, body, destination, blocked, **params):
        before = destination.read_bytes()
        script = directory / 'publication.lua'
        script.write_text(body, encoding='utf-8')
        wrapper = directory / 'wrapper.lua'
        wrapper.write_text(WRAPPER, encoding='utf-8')
        result = self.run_lua(wrapper, body=script, blocked='yes' if blocked else 'no', **params)
        output = result.stdout + result.stderr
        if blocked:
            self.assertIn('INJECTED_SAVE_NOOP', output)
            self.assertNotEqual(0, result.returncode, output)
            self.assertIn('Saved artwork layer', output)
            self.assertNotIn('PUBLICATION_COMPLETE', output)
            self.assertNotIn('EXPORT_REACHED', output)
            self.assertEqual(before, destination.read_bytes())
        else:
            self.assertEqual(0, result.returncode, output)
            self.assertIn('PUBLICATION_COMPLETE', output)
            self.assertNotEqual(before, destination.read_bytes())

    def wall(self, filename, blocked, existing=False):
        source = (ROOT / 'tools/tile_art' / filename).read_text(encoding='utf-8')
        if filename == 'port_walls.lua':
            body = source[source.index('sourceFiles.copy(path,work'):]
            generated = ''
        else:
            body = source[source.index('local base=path'):]
            if filename == 'idea_walls.lua':
                body = body[:body.index('local map={')]
                generated = 'local sheet=Image(faced)\n'
            else:
                generated = 'local function sheet(withFace) return Image(withFace and faced or flat) end\n'
        with tempfile.TemporaryDirectory(prefix='cistern-saved-wall-test-') as temporary:
            work = Path(temporary)
            destination = work / 'sheet.aseprite'
            params = dict(source=destination, work=work.as_posix() + '/',
                          root=ROOT.as_posix() + '/')
            self.fixture(work, WALL_FIXTURE, source=destination,
                         existing='yes' if existing else 'no')
            self.publication(work, WALL_SETUP + generated + body, destination, blocked, **params)
            self.assertTrue(list(work.glob('*before-*.aseprite')))
            if blocked:
                self.assertFalse((work / 'ported-pixel-validation.txt').exists())

    def test_wall_generated_layers_are_saved(self):
        for filename in ('guide_walls.lua', 'idea_walls.lua', 'port_walls.lua'):
            for existing in ((False, True) if filename == 'idea_walls.lua' else (False,)):
                with self.subTest(script=filename, existing=existing):
                    self.wall(filename, blocked=False, existing=existing)

    def test_wall_stale_sources_are_rejected(self):
        for filename in ('guide_walls.lua', 'idea_walls.lua', 'port_walls.lua'):
            for existing in ((False, True) if filename == 'idea_walls.lua' else (False,)):
                with self.subTest(script=filename, existing=existing):
                    self.wall(filename, blocked=True, existing=existing)

    def pinch(self, shots, blocked):
        with tempfile.TemporaryDirectory(prefix='cistern-saved-pinch-test-') as temporary:
            work = Path(temporary)
            for folder in ('assets/source', 'assets/water', 'shots', 'tools/tile_art'):
                (work / folder).mkdir(parents=True)
            (work / 'tools/tile_art/source_files.lua').write_bytes(
                (ROOT / 'tools/tile_art/source_files.lua').read_bytes())
            params = dict(work=work.as_posix() + '/', root=work.as_posix() + '/',
                          faces=work / 'faces.png')
            if shots:
                params['shots'] = (work / 'shots').as_posix() + '/'
            self.fixture(work, PINCH_FIXTURE, **params)
            name = 'water-cliff-connections' if shots else 'water-cliff-edge'
            destination = work / 'assets/source' / (name + '.aseprite')
            body = (ROOT / 'tools/tile_art/pinch_shallow_cliff.lua').read_text(encoding='utf-8')
            self.publication(work, body, destination, blocked, **params)
            if blocked:
                self.assertFalse((work / 'pinch.txt').exists())
                self.assertFalse((work / 'assets/water/dirt-shallows-edges.png').exists())

    def test_both_pinch_branches_save_generated_layers(self):
        for shots in (False, True):
            with self.subTest(shots=shots):
                self.pinch(shots, blocked=False)

    def test_both_pinch_branches_reject_stale_sources(self):
        for shots in (False, True):
            with self.subTest(shots=shots):
                self.pinch(shots, blocked=True)


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
