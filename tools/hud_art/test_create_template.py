import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/tile_art'))
from art_support import ROOT, WorkTest, aseprite, generate, install_scripts, main


ASEPRITE = None


class TemplateTests(unittest.TestCase):
    def test_guides_generate_from_current_runtime_sources(self):
        script = Path(__file__).with_name('create_template.py')
        with tempfile.TemporaryDirectory(prefix='cistern-hud-template-test-') as temporary:
            result = generate(script, '--guides-only', temp=temporary)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            work = Path(temporary) / 'hud-template'
            for name in ('paper', 'under', 'guides', 'labels'):
                with Image.open(work / (name + '.png')) as image:
                    self.assertEqual((1024, 1024), image.size)
                    self.assertEqual('RGBA', image.mode)
                    self.assertIsNotNone(image.getbbox())
            slices = json.loads((work / 'slices.json').read_text(encoding='utf-8'))
            self.assertEqual(21, len(slices))
            self.assertEqual(len(slices), len({item['name'] for item in slices}))
            for item in slices:
                self.assertGreater(item['w'], 0)
                self.assertGreater(item['h'], 0)
                self.assertGreaterEqual(item['x'], 0)
                self.assertGreaterEqual(item['y'], 0)
                self.assertLessEqual(item['x'] + item['w'], 1024)
                self.assertLessEqual(item['y'] + item['h'], 1024)
            self.assertFalse((work / 'assemble.lua').exists())


class NativeTemplateTests(WorkTest):
    def test_second_destination_failure_rolls_back_and_allows_retry(self):
        if not ASEPRITE:
            self.skipTest('Supply --aseprite for native template verification')
        root = self.work / 'project'
        install_scripts(root, ('art_support.py', 'source_files.lua'))
        for name in ('tools/hud_art/create_template.py', 'src/gfx/line_icons.zig',
                     'src/ui/hud.zig', 'src/gfx/look.zig'):
            destination = root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        desktop = self.work / 'Desktop'
        desktop.mkdir()
        with patch.dict(os.environ, {'USERPROFILE': str(self.work), 'HOME': str(self.work)}):
            generated = generate(root / 'tools/hud_art/create_template.py', temp=self.work)
        self.assertEqual(0, generated.returncode, generated.stdout + generated.stderr)
        assembly = self.work / 'hud-template' / 'assemble.lua'
        output = desktop / 'hud-elements.aseprite'
        source = root / 'assets/source/hud-elements.aseprite'
        report = assembly.parent / 'validation.txt'
        result = aseprite(ASEPRITE, assembly, temp=self.work)
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('hud-elements.aseprite', result.stdout + result.stderr)
        self.assertFalse(output.exists())
        self.assertFalse(source.exists())
        self.assertFalse(report.exists())

        source.parent.mkdir(parents=True)
        result = aseprite(ASEPRITE, assembly, temp=self.work)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        before = output.read_bytes()
        self.assertTrue(before)
        self.assertEqual(before, source.read_bytes())
        self.assertIn('Published identical copies', report.read_text(encoding='utf-8'))

        result = aseprite(ASEPRITE, assembly, temp=self.work)
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn('Refusing to overwrite', result.stdout + result.stderr)
        self.assertEqual(before, output.read_bytes())
        self.assertEqual(before, source.read_bytes())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--aseprite')
    args, remaining = parser.parse_known_args()
    ASEPRITE = args.aseprite
    main(remaining)
