import os
from pathlib import Path
import shutil
import unittest

from PIL import Image

from art_support import WorkTest, arguments, aseprite, generate, main, read_locked, water_cliff_layout


args, remaining = arguments()
SURFACE = (119, 146, 185, 255)
LAYOUT = water_cliff_layout(args.scripts_dir)


def block_crop(layout, n):
    x, y = layout['x'] + n * layout['stride'], layout['y']
    return (x, y, x + layout['block'], y + layout['block'])


class ConnectedTemplateTests(WorkTest):
    def setUp(self):
        super().setUp()
        self.shots = self.work / 'shots'
        self.shots.mkdir()
        self.output = self.work / 'connected.aseprite'
        self.preview = self.output.with_suffix('.png')
        self.before = {self.output: b'owner\x00layered\xffsource', self.preview: b'owner\x00preview\xffpixels'}
        for path, content in self.before.items():
            path.write_bytes(content)
        block = (LAYOUT['block'], LAYOUT['block'])
        for n in range(3):
            combined = Image.new('RGBA', block)
            for part in range(1, 5):
                pixels = Image.new('RGBA', block,(40 + n * 20, 50, 60, 255) if part == 1 else (0, 0, 0, 0))
                pixels.putpixel((part * 7, part * 11), SURFACE if part == 4 else (60 + part * 20, 100 + n * 20, 120, 255))
                pixels.save(self.shots / f'template-{n}-layer-{part}.png')
                combined = Image.alpha_composite(combined, pixels)
            combined.save(self.shots / f'template-{n}.png')
        self.inputs = {path: path.read_bytes() for path in self.shots.iterdir()}

    def generate(self, root=args.root):
        result = generate(root / 'tools/tile_art/water_cliff_connected.py', self.shots, '--output', self.output,
                          '--replace', temp=self.work)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return Path(result.stdout.strip()) / 'assemble.lua'

    def assemble(self, script, **params):
        return aseprite(args.aseprite, script, params)

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
        self.assertIn(f'{LAYOUT["slices"]} named slices, 18 layers', (assembly.parent / 'validation.txt').read_text(encoding='utf-8'))
        self.assertNotEqual(self.before[self.output], self.output.read_bytes())
        with Image.open(self.preview) as preview:
            self.assertEqual((LAYOUT['width'], LAYOUT['height']), preview.size)
            for n in range(3):
                with Image.open(self.shots / f'template-{n}.png') as expected:
                    self.assertEqual(expected.convert('RGBA').tobytes(),
                                     preview.crop(block_crop(LAYOUT, n)).convert('RGBA').tobytes())
        self.assertEqual(self.inputs, {p: p.read_bytes() for p in self.inputs})

    def test_assembly_and_edge_export_follow_a_shifted_shared_layout(self):
        root = self.work / 'project'
        scripts = root / 'tools/tile_art'
        scripts.mkdir(parents=True)
        for name in ('water_cliff_connected.py', 'art_support.py', 'source_files.lua', 'ground_corners.lua',
                     'ground_layout.lua', 'water_cliff_materials.lua', 'export_water_edges.lua'):
            shutil.copyfile(args.scripts_dir / name, scripts / name)
        shifted = dict(LAYOUT, x=LAYOUT['x'] + 8, y=LAYOUT['y'] + 8, stride=LAYOUT['stride'] - 8)
        (scripts / 'water_cliff_layout.lua').write_text(
            'return {' + ','.join(f'{key}={value}' for key, value in shifted.items()) + '}\n', encoding='utf-8')
        for name in ('water/shallows-cliff.png', 'water/water-cliff.png',
                     'water/water-cliff-cap.png', 'ground/shallows-ground.png'):
            target = root / 'assets' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(args.root / 'assets' / name, target)
        assembly = self.generate(root)
        result = self.assemble(assembly)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        with Image.open(self.preview) as preview:
            for n in range(3):
                with Image.open(self.shots / f'template-{n}.png') as expected:
                    self.assertEqual(expected.convert('RGBA').tobytes(),
                                     preview.crop(block_crop(shifted, n)).convert('RGBA').tobytes())
        probe = self.work / 'export-shifted.lua'
        probe.write_text('''
local root=app.params.root
local layout=dofile(root..'tools/tile_art/water_cliff_layout.lua')
local materials=dofile(root..'tools/tile_art/water_cliff_materials.lua')
local edited=Image{fromFile=app.params.source}
local ink=materials.surface
for n=0,2 do edited:putPixel(layout.x+n*layout.stride+1,layout.y+1,ink) end
edited:saveAs(app.params.source)
dofile(root..'tools/tile_art/export_water_edges.lua')
local expected=Image(#materials.bands*layout.block,layout.block,ColorMode.RGB)
expected:putPixel(materials.band.shallow*layout.block+1,1,ink)
expected:putPixel(materials.band.shallow*layout.block+28,44,ink)
for _,name in ipairs({'dirt-shallows-edges','dirt-water-edges','shallows-water-edges'}) do
 assert(Image{fromFile=root..'assets/water/'..name..'.png'}:isEqual(expected),'Wrong shifted crop: '..name)
end
''', encoding='utf-8')
        result = self.assemble(probe, root=root.as_posix() + '/', source=self.preview,
                               original=self.output, report=self.work / 'export.txt')
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(self.inputs, {p: p.read_bytes() for p in self.inputs})

    @unittest.skipUnless(os.name == 'nt', 'Windows file sharing failure')
    def test_locked_stale_preview_cannot_report_success(self):
        Image.new('RGBA', (LAYOUT['width'], LAYOUT['height']), (190, 20, 130, 255)).save(self.preview)
        before = self.preview.read_bytes()
        assembly = self.generate()
        with read_locked(self.preview):
            result = self.assemble(assembly)
        output = result.stdout + result.stderr
        self.assertNotEqual(0, result.returncode, output)
        self.assertIn('Saved preview differs from the assembled template', output)
        self.assertEqual(before, self.preview.read_bytes())
        self.assertFalse((assembly.parent / 'validation.txt').exists())
        self.assertEqual(self.inputs, {p: p.read_bytes() for p in self.inputs})


if __name__ == '__main__':
    main(remaining)
