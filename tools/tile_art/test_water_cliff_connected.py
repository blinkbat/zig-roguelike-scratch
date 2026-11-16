import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
args, remaining = parser.parse_known_args()


class ConnectedTemplateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cistern-connected-test-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.shots = self.work / 'shots'
        self.shots.mkdir()
        self.output = self.work / 'connected.aseprite'
        self.preview = self.output.with_suffix('.png')
        self.before = {self.output: b'owner\x00layered\xffsource', self.preview: b'owner\x00preview\xffpixels'}
        for path, content in self.before.items():
            path.write_bytes(content)
        for n in range(3):
            combined = Image.new('RGBA', (256, 256))
            for part in range(1, 5):
                pixels = Image.new('RGBA', (256, 256), (40 + n * 20, 50, 60, 255) if part == 1 else (0, 0, 0, 0))
                pixels.putpixel((part * 7, part * 11), (60 + part * 20, 100 + n * 20, 120, 255))
                pixels.save(self.shots / f'template-{n}-layer-{part}.png')
                combined = Image.alpha_composite(combined, pixels)
            combined.save(self.shots / f'template-{n}.png')
        self.inputs = {path: path.read_bytes() for path in self.shots.iterdir()}

    def generate(self):
        env = dict(os.environ, TEMP=str(self.work), TMP=str(self.work), PYTHONIOENCODING='utf-8')
        result = subprocess.run(
            [sys.executable, '-B', str(ROOT / 'tools/tile_art/water_cliff_connected.py'),
             str(self.shots), '--output', str(self.output), '--replace'],
            env=env, capture_output=True, text=True, encoding='utf-8', timeout=30,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return Path(result.stdout.strip()) / 'assemble.lua'

    def assemble(self, script, **params):
        command = [args.aseprite, '--batch']
        for key, value in params.items():
            command += ['--script-param', f'{key}={value}']
        return subprocess.run(command + ['--script', str(script)], capture_output=True, text=True,
                              timeout=30, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))

    def test_input_close_failure_preserves_both_destinations(self):
        assembly = self.generate()
        wrapper = self.work / 'fail-close.lua'
        wrapper.write_text('''
local realio=io
local target=app.params.target
local env
env=setmetatable({io=setmetatable({open=function(path,mode)
 local file,err=realio.open(path,mode)
 if not file or path~=target or mode~='rb' then return file,err end
 return {
  read=function(_,format) return file:read(format) end,
  close=function() assert(file:close()); return nil,'injected input close failure' end,
 }
end},{__index=realio}),dofile=function(path)
 return assert(loadfile(path,'t',env))()
end},{__index=_G})
assert(loadfile(app.params.assembly,'t',env))()
''', encoding='utf-8')
        for path in self.before:
            with self.subTest(target=path.name):
                result = self.assemble(wrapper, target=path.as_posix(), assembly=assembly.as_posix())
                self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertIn('injected input close failure', result.stdout + result.stderr)
                self.assertEqual(self.before, {p: p.read_bytes() for p in self.before})
                self.assertFalse((assembly.parent / 'validation.txt').exists())
        self.assertEqual(self.inputs, {p: p.read_bytes() for p in self.inputs})

    def test_replacement_keeps_unique_backups_and_preserves_layer_pixels(self):
        assembly = self.generate()
        existing = assembly.parent / ('before-assembly-1-' + self.output.name)
        existing.write_bytes(b'previous backup')
        result = self.assemble(assembly)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(b'previous backup', existing.read_bytes())
        self.assertEqual(self.before[self.output], (assembly.parent / ('before-assembly-2-' + self.output.name)).read_bytes())
        self.assertEqual(self.before[self.preview], (assembly.parent / ('before-assembly-1-' + self.preview.name)).read_bytes())
        self.assertIn('54 named slices, 18 layers', (assembly.parent / 'validation.txt').read_text(encoding='utf-8'))
        self.assertNotEqual(self.before[self.output], self.output.read_bytes())
        with Image.open(self.preview) as preview:
            self.assertEqual((960, 640), preview.size)
            for n in range(3):
                with Image.open(self.shots / f'template-{n}.png') as expected:
                    self.assertEqual(expected.convert('RGBA').tobytes(),
                                     preview.crop((32 + n * 320, 104, 288 + n * 320, 360)).convert('RGBA').tobytes())
        self.assertEqual(self.inputs, {p: p.read_bytes() for p in self.inputs})


if __name__ == '__main__':
    unittest.main(argv=[__file__, *remaining])
