import hashlib
import os
import unittest

from art_support import WorkTest, arguments, aseprite, install_scripts, main, run_lua, sheet_sizes_lua


args, remaining = arguments()
SIZES = sheet_sizes_lua(args.scripts_dir)


class GroundSheetTests(WorkTest):
    def setUp(self):
        super().setUp()
        self.sheet = self.work / 'ground.aseprite'
        self.run_lua('''
local s=Sprite(WALL_W,WALL_H,ColorMode.RGB)
s.layers[1].name='Paper - hide for transparent export'
local paper=Image(WALL_W,WALL_H,ColorMode.RGB)
paper:clear(app.pixelColor.rgba(240,240,240,255))
s:newCel(s.layers[1],1,paper,Point(0,0))
local l=s:newLayer(); l.name='64x64 grid'
local grid=Image(1,1,ColorMode.RGB)
grid:clear(app.pixelColor.rgba(40,40,40,255))
s:newCel(l,1,grid,Point(0,0))
s:saveAs(app.params.style); s:close()
local labels=Image(GROUND_W,GROUND_H,ColorMode.RGB)
labels:putPixel(12,8,app.pixelColor.rgba(50,50,50,255))
labels:saveAs(app.params.labels)
''')
        self.generate()

    def params(self, **parameters):
        return {
            'root': args.root.as_posix() + '/',
            'out': self.sheet,
            'style': self.work / 'style.aseprite',
            'labels': self.work / 'labels.png',
            'tint': '100,120,140',
            **parameters,
        }

    def command(self, script, **parameters):
        return aseprite(args.aseprite, script, self.params(**parameters), timeout=None, temp=self.work)

    def run_lua(self, source):
        result = run_lua(args.aseprite, self.work / 'fixture.lua', SIZES + source, self.params(), timeout=None, temp=self.work)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def generate(self, replace=False):
        result = self.command(args.scripts_dir / 'ground_sheet.lua', **({'replace': 'yes'} if replace else {}))
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_unchanged_blank_template_can_be_replaced(self):
        self.generate(replace=True)

    def test_underdrawing_checks_the_resolved_assets_directory(self):
        install_scripts(self.work, ('source_files.lua', 'ground_port.lua', 'ground_layout.lua', 'ground_corners.lua'),
                        args.scripts_dir)
        assets = self.work / 'assets/ground'
        assets.mkdir(parents=True)
        root = self.work.resolve().as_posix() + '/'
        script = args.scripts_dir / 'export_ground.lua'
        params = {'root': root, 'source': self.sheet, 'name': 'grass', 'from': 'underdrawing'}
        protected = assets / 'grass-ground.png'
        result = self.command(script, out=protected, **params)
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('must be exported outside assets/', result.stdout + result.stderr)
        self.assertFalse(protected.exists())
        protected.write_bytes(b'owner artwork')
        alias = self.work / 'alias.png'
        os.link(protected, alias)
        result = self.command(script, out=alias, **params)
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('must be exported outside assets/', result.stdout + result.stderr)
        self.assertEqual(b'owner artwork', protected.read_bytes())
        safe = self.work / 'draft.png'
        result = self.command(script, out=safe, **params)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertTrue(safe.is_file())

    def test_modified_templates_are_refused_without_changing_the_file(self):
        baseline = self.sheet.read_bytes()
        cases = {
            'extra painted layer': "local l=s:newLayer(); l.name='Owner art'; s:newCel(l,1,paint,Point(0,0))",
            'extra painted frame': "s:newFrame(); s:newCel(s.layers[5],2,paint,Point(0,0))",
            'painted group': "s:deleteLayer(s.layers[5]); local group=s:newGroup(); group.name='Draw here'; local l=s:newLayer(); l.parent=group; s:newCel(l,1,paint,Point(0,0))",
            'missing paint layer': 's:deleteLayer(s.layers[5])',
            'painted drawing': 's:newCel(s.layers[5],1,paint,Point(0,0))',
            'painted guide': 's:newCel(s.layers[2],1,paint,Point(0,0))',
            'off-canvas guide painting': 'local c=s.layers[2]:cel(1); local im=Image(GROUND_W+1,GROUND_H,ColorMode.RGB); im:drawImage(c.image,c.position); im:putPixel(GROUND_W,0,app.pixelColor.rgba(255,0,0,255)); s:newCel(s.layers[2],1,im,Point(0,0))',
            'changed guide opacity': 's.layers[2].opacity=128',
            'moved slice': 's.slices[1].bounds=Rectangle(1,64,64,64)',
        }
        for name, change in cases.items():
            with self.subTest(name=name):
                self.sheet.write_bytes(baseline)
                self.run_lua('''
local s=assert(app.open(app.params.out))
local paint=Image(1,1,ColorMode.RGB)
paint:clear(app.pixelColor.rgba(255,0,0,255))
''' + change + '\ns:saveAs(app.params.out); s:close()\n')
                before = hashlib.sha256(self.sheet.read_bytes()).digest()
                result = self.command(args.scripts_dir / 'ground_sheet.lua', replace='yes')
                self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertIn('Preserving', result.stdout + result.stderr)
                self.assertEqual(before, hashlib.sha256(self.sheet.read_bytes()).digest())


if __name__ == '__main__':
    main(remaining)
