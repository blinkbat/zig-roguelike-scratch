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

PORTS = {
    'port_ground.lua': 'grass.aseprite',
    'port_forest.lua': 'forest-tree-walls.aseprite',
    'port_bridge.lua': 'bridge.aseprite',
}
BOUNDARY = 'PORT_SOURCE_OPEN_BOUNDARY'
REFUSAL = 'Preserving divergent canonical source'
ORIGINAL = b'owner\x00original\xffpaint'
DIVERGENT = b'owner\x00different\xffpaint'


class PortSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cistern-port-source-test-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.wrapper = self.work / 'preflight.lua'
        self.wrapper.write_text('''
local realapp=app
local env=setmetatable({app={
  params=realapp.params,
  pixelColor=realapp.pixelColor,
  fs={
    tempPath=realapp.params.work,
    joinPath=realapp.fs.joinPath,
    makeAllDirectories=realapp.fs.makeAllDirectories,
    isFile=realapp.fs.isFile,
  },
  open=function(path)
    assert(path==realapp.params.source,'Wrong input source')
    error('PORT_SOURCE_OPEN_BOUNDARY')
  end,
},dofile=function(path)
  local helper=path:match('/tools/tile_art/([^/]+)$')
  assert(helper=='ground_corners.lua' or helper=='wall_masks.lua')
  return dofile(realapp.params.helpers..'/'..helper)
end},{__index=_G})
assert(loadfile(realapp.params.script,'t',env))()
''', encoding='utf-8')

    def check_case(self, case, allowed):
        for script, filename in PORTS.items():
            with self.subTest(script=script):
                root = self.work / script
                canonical = root / 'assets/source' / filename
                canonical.parent.mkdir(parents=True)
                source = canonical if case == 'same_path' else root / 'input.aseprite'
                if case != 'missing_input':
                    source.write_bytes(ORIGINAL)
                if case in ('divergent', 'draft_divergent'):
                    canonical.write_bytes(DIVERGENT)
                elif case in ('identical', 'missing_input'):
                    canonical.write_bytes(ORIGINAL)
                before = {p: p.read_bytes() for p in root.rglob('*') if p.is_file()}
                command = [args.aseprite, '--batch']
                for value in (
                    'root=' + root.as_posix() + '/',
                    'source=' + source.as_posix(),
                    'name=grass',
                    'work=' + (root / 'work').as_posix(),
                    'install=' + ('no' if case == 'draft_divergent' else 'yes'),
                    'script=' + (args.scripts_dir / script).resolve().as_posix(),
                    'helpers=' + (ROOT / 'tools/tile_art').as_posix(),
                ):
                    command += ['--script-param', value]
                result = subprocess.run(
                    command + ['--script', str(self.wrapper)],
                    capture_output=True, text=True, timeout=30,
                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
                )
                output = result.stdout + result.stderr
                self.assertNotEqual(0, result.returncode, output)
                if allowed:
                    self.assertIn(BOUNDARY, output)
                else:
                    self.assertNotIn(BOUNDARY, output)
                    if case == 'divergent':
                        self.assertIn(REFUSAL, output)
                after = {p: p.read_bytes() for p in root.rglob('*') if p.is_file()}
                self.assertEqual(before, after, output)

    def test_divergent_canonical_refused_before_opening_or_writing(self):
        self.check_case('divergent', allowed=False)

    def test_identical_separate_canonical_allowed(self):
        self.check_case('identical', allowed=True)

    def test_absent_canonical_allowed(self):
        self.check_case('absent', allowed=True)

    def test_canonical_input_itself_allowed(self):
        self.check_case('same_path', allowed=True)

    def test_draft_ignores_divergent_canonical(self):
        self.check_case('draft_divergent', allowed=True)

    def test_unreadable_input_refused_before_opening_canonical(self):
        self.check_case('missing_input', allowed=False)


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
