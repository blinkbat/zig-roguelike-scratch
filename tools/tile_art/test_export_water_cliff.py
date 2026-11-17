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
    def test_profile_write_and_close_failures_close_handles_and_abort_export(self):
        with tempfile.TemporaryDirectory(prefix='cistern-cliff-profile-failure-') as temporary:
            work = Path(temporary)
            probe = work / 'probe.lua'
            probe.write_text('''
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
local realio=io
local opened,written,closed=0,0,0
local customio=setmetatable({open=function(path,mode)
 local file,err=realio.open(path,mode)
 if not file or path~=app.params.failed then return file,err end
 assert(mode=='wb')
 opened=opened+1
 return {
  write=function(_,bytes)
   written=written+1
   if app.params.failure=='write' then return nil,'injected profile write failure' end
   return file:write(bytes)
  end,
  close=function()
   closed=closed+1
   local ok,close_error=file:close()
   if app.params.failure=='close' then return nil,'injected profile close failure' end
   return ok,close_error
  end,
 }
end},{__index=realio})
local env
env=setmetatable({io=customio,dofile=function(path)
 return assert(loadfile(path,'t',env))()
end},{__index=_G})
local ok,err=pcall(assert(loadfile(app.params.exporter,'t',env)))
assert(not ok,'Exporter accepted failed profile publication')
assert(tostring(err):find('injected profile '..app.params.failure..' failure',1,true),tostring(err))
assert(opened==1 and written==1 and closed==1,'Profile handle was not closed exactly once')
print('EXPECTED_PROFILE_FAILURE')
''', encoding='utf-8')
            for profile in ('foot', 'lip'):
                for failure in ('write', 'close'):
                    with self.subTest(profile=profile, failure=failure):
                        command = [args.aseprite, '--batch']
                        params = dict(source=work / 'source.aseprite', out=work / 'cliff.png',
                                      depth='deep', layer='Paint', failure=failure,
                                      failed=work / f'cliff-{profile}.txt',
                                      root=ROOT.as_posix() + '/',
                                      exporter=ROOT / 'tools/tile_art/export_water_cliff.lua')
                        for key, value in params.items():
                            if isinstance(value, Path):
                                value = value.as_posix()
                            command += ['--script-param', f'{key}={value}']
                        result = subprocess.run(command + ['--script', str(probe)],
                                                capture_output=True, text=True, timeout=30,
                                                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
                        output = result.stdout + result.stderr
                        self.assertEqual(0, result.returncode, output)
                        self.assertIn('EXPECTED_PROFILE_FAILURE', output)
                        self.assertNotIn('Verified deep cliff', output)

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
