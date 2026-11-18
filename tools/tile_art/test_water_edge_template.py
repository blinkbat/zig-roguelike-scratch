import hashlib
from pathlib import Path

from art_support import WorkTest, arguments, aseprite, generate, main


args, remaining = arguments()


class WaterTemplateTests(WorkTest):
    def setUp(self):
        super().setUp()
        self.sheet = self.work / 'water.aseprite'
        self.generate()

    def generate(self, replace=False, expected=0, temporary=None):
        generated = generate(args.scripts_dir / 'water_edge_template.py', '--output', self.sheet,
                             *(['--replace-blank'] if replace else []), temp=temporary or self.work)
        self.assertEqual(0, generated.returncode, generated.stdout + generated.stderr)
        assembly = Path(generated.stdout.strip()) / 'assemble.lua'
        result = aseprite(args.aseprite, assembly, timeout=None)
        if expected == 0:
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        else:
            self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn('Preserving', result.stdout + result.stderr)

    def test_blank_template_can_be_replaced(self):
        self.generate(replace=True)

    def test_unicode_output_and_temporary_paths(self):
        directory = self.work / 'caf\u00e9-\u6c34'
        directory.mkdir()
        self.sheet = directory / 'water.aseprite'
        self.generate(temporary=directory)
        self.assertTrue(self.sheet.is_file())

    def test_changed_artwork_and_layout_are_preserved(self):
        baseline = self.sheet.read_bytes()
        cases = {
            'reference painting': 's:newCel(s.layers[4],1,paint,Point(0,0))',
            'drawing': 's:newCel(s.layers[7],1,paint,Point(0,0))',
            'extra frame': 's:newFrame(); s:newCel(s.layers[7],2,paint,Point(0,0))',
            'painted group': "s:deleteLayer(s.layers[7]); local g=s:newGroup(); g.name='Draw here'; local l=s:newLayer(); l.parent=g; s:newCel(l,1,paint,Point(0,0))",
            'off-canvas painting': 'local c=s.layers[4]:cel(1); local im=Image(513,512,ColorMode.RGB); im:drawImage(c.image,c.position); im:putPixel(512,0,app.pixelColor.rgba(255,0,0,255)); s:newCel(s.layers[4],1,im,Point(0,0))',
            'guide opacity': 's.layers[4].opacity=128',
            'moved slice': 's.slices[1].bounds=Rectangle(0,0,64,64)',
        }
        for name, change in cases.items():
            with self.subTest(name=name):
                self.sheet.write_bytes(baseline)
                script = self.work / 'edit.lua'
                script.write_text('local s=assert(app.open(app.params.file))\nlocal paint=Image(1,1,ColorMode.RGB)\npaint:clear(app.pixelColor.rgba(255,0,0,255))\n' + change + '\ns:saveAs(app.params.file); s:close()\n', encoding='utf-8')
                result = aseprite(args.aseprite, script, {'file': str(self.sheet)}, timeout=None)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                before = hashlib.sha256(self.sheet.read_bytes()).digest()
                self.generate(replace=True, expected=1)
                self.assertEqual(before, hashlib.sha256(self.sheet.read_bytes()).digest())


if __name__ == '__main__':
    main(remaining)
