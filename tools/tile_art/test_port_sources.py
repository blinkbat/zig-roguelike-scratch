from pathlib import Path
import tempfile
import unittest

from art_support import ROOT, arguments, aseprite, main


args, remaining = arguments()

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
  assert(helper=='ground_corners.lua' or helper=='ground_port.lua' or helper=='wall_masks.lua' or helper=='source_files.lua')
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
                result = aseprite(args.aseprite, self.wrapper, {
                    'root': root.as_posix() + '/',
                    'source': source,
                    'name': 'grass',
                    'work': root / 'work',
                    'install': 'no' if case == 'draft_divergent' else 'yes',
                    'script': (args.scripts_dir / script).resolve(),
                    'helpers': ROOT / 'tools/tile_art',
                })
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

    def test_unreadable_input_refused_before_opening_sprite(self):
        self.check_case('missing_input', allowed=False)


if __name__ == '__main__':
    main(remaining)
