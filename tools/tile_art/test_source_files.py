import argparse
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
parser.add_argument('--scripts-dir', type=Path, default=ROOT / 'tools/tile_art')
args, remaining = parser.parse_known_args()


class SourceFileTests(unittest.TestCase):
    def run_lua(self, code, **params):
        with tempfile.TemporaryDirectory(prefix='cistern-source-files-test-') as temporary:
            script = Path(temporary) / 'probe.lua'
            script.write_text(code, encoding='utf-8')
            command = [args.aseprite, '--batch']
            params['module'] = (args.scripts_dir / 'source_files.lua').as_posix()
            for key, value in params.items():
                command += ['--script-param', f'{key}={value}']
            result = subprocess.run(
                command + ['--script', str(script)],
                capture_output=True, text=True, timeout=30,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
            )
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def check_failure(self, failure):
        self.run_lua('''
local failure=app.params.failure
local input_closed,output_closed,output_opened,written=0,0,0,0
local bytes='owner'..string.char(0,255)..'artwork'
local input={
 read=function(_,format)
  assert(format=='*a')
  if failure=='read' then return nil,'injected read failure' end
  return bytes
 end,
 close=function()
  input_closed=input_closed+1
  if failure=='input_close' then return nil,'injected input_close failure' end
  return true
 end,
}
local output={
 write=function(_,actual)
  assert(actual==bytes,'Backup contents changed')
  written=written+1
  if failure=='write' then return nil,'injected write failure' end
  return true
 end,
 close=function()
  output_closed=output_closed+1
  if failure=='output_close' then return nil,'injected output_close failure' end
  return true
 end,
}
local env=setmetatable({io={open=function(path,mode)
 if mode=='rb' then
  assert(path=='source')
  if failure=='input_open' then return nil,'injected input_open failure' end
  return input
 end
 assert(path=='destination' and mode=='wb')
 assert(input_closed==1,'Input handle still open')
 output_opened=output_opened+1
 if failure=='output_open' then return nil,'injected output_open failure' end
 return output
end}}, {__index=_G})
local files=assert(loadfile(app.params.module,'t',env))()
local ok,err=pcall(files.copy,'source','destination')
assert(not ok,'Copy accepted failed '..failure)
assert(tostring(err):find('injected '..failure..' failure',1,true),tostring(err))
assert(input_closed==(failure=='input_open' and 0 or 1),'Input handle not closed exactly once')
local read_failed=failure=='input_open' or failure=='read' or failure=='input_close'
assert(output_opened==(read_failed and 0 or 1),'Destination opened after failed input')
local got_output=not read_failed and failure~='output_open'
assert(output_closed==(got_output and 1 or 0),'Output handle not closed exactly once')
assert(written==(got_output and 1 or 0),'Unexpected backup write')
''', failure=failure)

    def test_input_open_failure_stops_before_destination(self):
        self.check_failure('input_open')

    def test_read_failure_closes_input_and_stops_before_destination(self):
        self.check_failure('read')

    def test_input_close_failure_stops_before_destination(self):
        self.check_failure('input_close')

    def test_output_open_failure_propagates_after_input_closes(self):
        self.check_failure('output_open')

    def test_write_failure_closes_output_and_propagates(self):
        self.check_failure('write')

    def test_output_close_failure_propagates(self):
        self.check_failure('output_close')

    def test_success_copies_exact_binary_bytes(self):
        with tempfile.TemporaryDirectory(prefix='cistern-source-files-bytes-') as temporary:
            source = Path(temporary) / 'source.aseprite'
            destination = Path(temporary) / 'backup.aseprite'
            data = bytes(range(256)) * 300 + b'\x00owner artwork\r\n'
            source.write_bytes(data)
            destination.write_bytes(b'previous backup')
            self.run_lua('''
local files=dofile(app.params.module)
files.copy(app.params.source,app.params.destination)
''', source=source.as_posix(), destination=destination.as_posix())
            self.assertEqual(data, source.read_bytes())
            self.assertEqual(data, destination.read_bytes())


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
