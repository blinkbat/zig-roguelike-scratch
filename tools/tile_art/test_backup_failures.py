from pathlib import Path
import tempfile
import unittest

from art_support import arguments, aseprite, main


args, remaining = arguments()

WRAPPER = r'''
local realapp,realio=app,io
local p=realapp.params
local root=p.root
local reads={}
local function injected(operation)
 return nil,'injected '..operation..' failure'
end
local customio={open=function(path,mode)
 local input=mode=='rb'
 if input then reads[path]=(reads[path] or 0)+1 end
 local selected=input and path==p.fault_path and reads[path]==tonumber(p.occurrence)
 if p.failure=='equality_reads' then selected=input and reads[path]==1 and (path==p.fault_path or path==p.desktop) end
 if selected and p.failure=='input_open' then return injected(p.failure) end
 if not input and p.failure=='output_open' then return injected(p.failure) end
 local file,err=realio.open(path,mode)
 if not file then return nil,err end
 return {
  read=function(_,format)
   if selected and (p.failure=='read' or p.failure=='equality_reads') then return injected(p.failure) end
   return file:read(format)
  end,
  write=function(_,bytes)
   if p.failure=='write' then return injected(p.failure) end
   return file:write(bytes)
  end,
  close=function()
   local ok,close_error=file:close()
   if (selected and p.failure=='input_close') or (not input and p.failure=='output_close') then return injected(p.failure) end
   return ok,close_error
  end,
 }
end}
local function mutation() error('UNSAFE_DESTINATION_WRITE') end
local image=Image(p.kind=='border' and 73 or 1,p.kind=='border' and 55 or 1,ColorMode.RGB)
image:putPixel(0,0,realapp.pixelColor.rgba(107,185,112,255))
if p.kind=='border' then image:putPixel(72,54,realapp.pixelColor.rgba(107,185,112,255)) end
local cel={image=image,position=Point(1,1),opacity=255}
local layer={name=p.kind=='border' and 'Layer 1' or 'Draw here',opacity=255,cel=function() return cel end}
local sprite={width=128,height=128,frames={1},layers={layer},saveAs=mutation,saveCopyAs=mutation,close=function() end}
local env
env=setmetatable({
 io=customio,
 app={params=p,pixelColor=realapp.pixelColor,open=function() return sprite end,
  fs={tempPath=p.work,joinPath=realapp.fs.joinPath,fileName=realapp.fs.fileName,
   makeAllDirectories=realapp.fs.makeAllDirectories,isFile=realapp.fs.isFile}},
 dofile=function(path)
  assert(path==root..'tools/tile_art/source_files.lua','Unexpected script: '..path)
  local files=assert(loadfile(p.helper,'t',env))()
  files.DESKTOP=p.desktop_dir
  return files
 end,
},{__index=_G})
assert(loadfile(p.script,'t',env))()
'''


class BackupFailureTests(unittest.TestCase):
    def check_failure(self, kind, failure, destination='source', occurrence=1):
        with tempfile.TemporaryDirectory(prefix='cistern-backup-failure-') as temporary:
            work = Path(temporary)
            root = work / 'root'
            files = {
                'source': root / ('input.aseprite' if kind == 'border' else 'assets/source/forest-tree-walls.aseprite'),
                'canonical': root / 'assets/source/hud-border.aseprite',
                'png': root / ('assets/ui/hud-border.png' if kind == 'border' else 'assets/walls/forest-tree-walls.png'),
                'grass': root / 'assets/ground/grass.png',
                'desktop': work / 'desktop/forest-tree-walls.aseprite',
            }
            for path in files.values():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'owner\x00original\xffartwork')
            (root / 'assets/backup').mkdir()
            (work / 'scratch').mkdir()
            if failure == 'missing_desktop':
                files['desktop'].unlink()
            if failure == 'missing_border_destinations':
                files['canonical'].unlink()
                files['png'].unlink()
            before = {path: path.read_bytes() if path.exists() else None for path in files.values()}
            wrapper = work / 'probe.lua'
            wrapper.write_text(WRAPPER, encoding='utf-8')
            script = args.root / 'tools/hud_art/export_border.lua' if kind == 'border' else args.scripts_dir / 'tone_forest.lua'
            params = dict(root=root.as_posix() + '/', work=(work / 'scratch').as_posix(),
                          source=files['source'].as_posix(), desktop=files['desktop'].as_posix(),
                          desktop_dir=files['desktop'].parent.as_posix() + '/',
                          script=script.as_posix(), helper=(args.scripts_dir / 'source_files.lua').as_posix(),
                          kind=kind, failure=failure, fault_path=files[destination].as_posix(), occurrence=occurrence)
            result = aseprite(args.aseprite, wrapper, params)
            output = result.stdout + result.stderr
            self.assertNotEqual(0, result.returncode, output)
            if failure in ('none', 'missing_border_destinations'):
                self.assertIn('UNSAFE_DESTINATION_WRITE', output)
                if kind == 'border':
                    self.assertTrue(files['png'].read_bytes().startswith(b'\x89PNG\r\n\x1a\n'))
                backups = list((root / 'assets/backup' if kind == 'tone' else work / 'scratch/hud-border-export').iterdir())
                self.assertEqual(1 if failure == 'missing_border_destinations' else 3, len(backups))
                for backup in backups:
                    self.assertEqual(b'owner\x00original\xffartwork', backup.read_bytes())
                return
            self.assertNotIn('UNSAFE_DESTINATION_WRITE', output)
            if failure != 'missing_desktop':
                self.assertIn('injected ' + failure + ' failure', output)
            after = {path: path.read_bytes() if path.exists() else None for path in files.values()}
            self.assertEqual(before, after, output)

    def test_border_backup_failures_abort_before_any_export(self):
        for destination in ('source', 'canonical', 'png'):
            for failure in ('input_open', 'read', 'input_close'):
                with self.subTest(destination=destination, failure=failure):
                    self.check_failure('border', failure, destination)
        for failure in ('output_open', 'write', 'output_close'):
            with self.subTest(failure=failure):
                self.check_failure('border', failure)

    def test_tone_backup_failures_abort_before_any_export(self):
        for destination, occurrence in (('source', 2), ('png', 1), ('grass', 1)):
            for failure in ('input_open', 'read', 'input_close'):
                with self.subTest(destination=destination, failure=failure):
                    self.check_failure('tone', failure, destination, occurrence)
        for failure in ('output_open', 'write', 'output_close'):
            with self.subTest(failure=failure):
                self.check_failure('tone', failure)

    def test_tone_source_comparison_checks_reads_and_closes(self):
        for destination in ('source', 'desktop'):
            for failure in ('input_open', 'read', 'input_close'):
                with self.subTest(destination=destination, failure=failure):
                    self.check_failure('tone', failure, destination)
        self.check_failure('tone', 'equality_reads')
        self.check_failure('tone', 'missing_desktop')

    def test_successful_backups_reach_export_with_exact_original_bytes(self):
        for kind in ('border', 'tone'):
            with self.subTest(kind=kind):
                self.check_failure(kind, 'none')

    def test_border_allows_genuinely_absent_destinations(self):
        self.check_failure('border', 'missing_border_destinations')


if __name__ == '__main__':
    main(remaining)
