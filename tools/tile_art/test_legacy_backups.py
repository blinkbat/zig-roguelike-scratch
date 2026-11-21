from pathlib import Path
import re

from art_support import WorkTest, arguments, generate, main, quote, run_lua, sheet_sizes_lua


args, remaining = arguments()
SIZES = sheet_sizes_lua(args.scripts_dir)

BACKUPS = {
    'guide_walls.lua': "'full-cell'",
    'idea_walls.lua': "'ideas'",
    'port_walls.lua': 'before-ported-edges-',
    'port_forest.lua': '(path,backup)',
    'ground_sheet.lua': "'ground'",
}


class LegacyBackupTests(WorkTest):
    def run_lua(self, code, **params):
        return run_lua(args.aseprite, self.work / 'probe.lua', code, params)

    def backup_calls(self):
        calls = {}
        for filename, marker in BACKUPS.items():
            source = (args.scripts_dir / filename).read_text(encoding='utf-8')
            candidates = [line.strip() for line in source.splitlines()
                          if marker in line and ('sourceFiles.copy(' in line or 'sourceFiles.keep(' in line
                                                 or ':saveCopyAs(' in line)]
            if filename == 'port_forest.lua' and not candidates:
                candidates = [line.strip() for line in source.splitlines()
                              if re.fullmatch(r'\s*\w+:saveCopyAs\(backup\)\s*', line)]
            self.assertEqual(1, len(candidates), filename)
            calls[filename] = candidates[0]
        output = self.work / 'water.aseprite'
        generated = generate(args.scripts_dir / 'water_edge_template.py', '--output', output, '--replace-blank',
                             temp=self.work)
        self.assertEqual(0, generated.returncode, generated.stdout + generated.stderr)
        assembly = Path(generated.stdout.strip()) / 'assemble.lua'
        candidates = [line.strip() for line in assembly.read_text(encoding='utf-8').splitlines()
                      if 'previous-template.aseprite' in line]
        self.assertEqual(1, len(candidates))
        calls['water_edge_template.py'] = candidates[0]
        return output, calls

    def test_each_backup_boundary_stops_before_source_write_on_io_failure(self):
        # Exercise each real backup call independently of its historical pixel sampler.
        source, calls = self.backup_calls()
        original = b'owner\x00original\xfflayers'
        for filename, call in calls.items():
            for failure in ('input_open', 'read', 'input_close', 'output_open', 'write', 'output_close'):
                with self.subTest(script=filename, failure=failure):
                    source.write_bytes(original)
                    code = '''
local realio=io
local failure=app.params.failure
local function bad() return nil,'injected '..failure..' failure' end
local env=setmetatable({io={open=function(path,mode)
 local input=mode=='rb'
 if (input and failure=='input_open') or (not input and failure=='output_open') then return bad() end
 local file,err=realio.open(path,mode)
 if not file then return nil,err end
 return {
  read=function(_,format) if failure=='read' then return bad() end; return file:read(format) end,
  write=function(_,bytes) if failure=='write' then return bad() end; return file:write(bytes) end,
  close=function()
   local ok,err=file:close()
   if (input and failure=='input_close') or (not input and failure=='output_close') then return bad() end
   return ok,err
  end,
 }
end}}, {__index=_G})
local sourceFiles=assert(loadfile(app.params.helper,'t',env))()
local path=app.params.source
local work=app.params.work..'/'
local base='source'
local backup=work..'forest-backup.aseprite'
local sprite={saveCopyAs=function() return true end}
local old=sprite
''' + call + '''
local destination=assert(realio.open(path,'wb'))
assert(destination:write('SOURCE_OVERWRITTEN'))
assert(destination:close())
error('UNSAFE_SOURCE_WRITE')
'''
                    result = self.run_lua(code, source=source.as_posix(), work=self.work.as_posix(),
                                          failure=failure,
                                          helper=(args.scripts_dir / 'source_files.lua').as_posix())
                    output = result.stdout + result.stderr
                    self.assertNotEqual(0, result.returncode, output)
                    self.assertIn('injected ' + failure + ' failure', output)
                    self.assertNotIn('UNSAFE_SOURCE_WRITE', output)
                    self.assertEqual(original, source.read_bytes(), output)

    def test_real_guide_script_preserves_source_when_backup_destination_is_blocked(self):
        source = self.work / 'guide.aseprite'
        fixture = SIZES + '''
local s=Sprite(WALL_W,WALL_H,ColorMode.RGB)
s.layers[1].name='Underdrawing (25%)'
local im=Image(1,1,ColorMode.RGB)
im:clear(app.pixelColor.rgba(10,20,30,255))
s:newCel(s.layers[1],1,im,Point(0,0))
for _,name in ipairs({'Exact connection guide (hidden)','Draw here'}) do
 local layer=s:newLayer(); layer.name=name; s:newCel(layer,1,im,Point(0,0))
end
for i=1,47 do
 local slice=s:newSlice(Rectangle(((i-1)%8)*64,64+((i-1)//8)*64,64,64))
 slice.name='Connection '..i
end
s:saveAs(app.params.source); s:close()
'''
        result = self.run_lua(fixture, source=source.as_posix())
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        original = source.read_bytes()
        blocked = self.work / 'wall-mocks/guide-before-full-cell-fixed.aseprite'
        blocked.mkdir(parents=True)
        wrapper = '''
local realapp=app
local env
env=setmetatable({
 app={params=realapp.params,pixelColor=realapp.pixelColor,open=realapp.open,
  fs=setmetatable({tempPath=realapp.params.work},{__index=realapp.fs})},
 os=setmetatable({date=function() return 'fixed' end},{__index=os}),
 dofile=function(path) return assert(loadfile(path,'t',env))() end,
},{__index=_G})
assert(loadfile(realapp.params.script,'t',env))()
print('GUIDE_SCRIPT_COMPLETED')
'''
        result = self.run_lua(wrapper, source=source.as_posix(), work=self.work.as_posix(),
                              root=args.root.as_posix() + '/',
                              script=(args.scripts_dir / 'guide_walls.lua').as_posix())
        output = result.stdout + result.stderr
        self.assertNotEqual(0, result.returncode, output)
        self.assertNotIn('GUIDE_SCRIPT_COMPLETED', output)
        self.assertEqual(original, source.read_bytes(), output)
        self.assertTrue(blocked.is_dir())
        self.assertFalse((blocked.parent / 'guide-full-cell.png').exists())

    def test_each_backup_copies_exact_source_bytes_before_continuing(self):
        source, calls = self.backup_calls()
        original = bytes(range(256)) * 4 + b'owner artwork'
        for filename, call in calls.items():
            with self.subTest(script=filename):
                source.write_bytes(original)
                code = f'''
local sourceFiles=dofile({quote(args.scripts_dir / 'source_files.lua')})
local path={quote(source)}
local work={quote(self.work.as_posix() + '/')}
local base='source'
local backup=work..'forest-backup.aseprite'
local sprite={{saveCopyAs=function() return true end}}
local old=sprite
local copied
local copy=sourceFiles.copy
sourceFiles.copy=function(input,output)
 copy(input,output)
 assert(sourceFiles.read(input)==sourceFiles.read(output),'Backup bytes changed')
 copied=output
end
{call}
assert(copied,'No checked backup before source replacement')
print('BACKUP_VERIFIED')
'''
                result = self.run_lua(code)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertIn('BACKUP_VERIFIED', result.stdout)
                self.assertEqual(original, source.read_bytes())


if __name__ == '__main__':
    main(remaining)
