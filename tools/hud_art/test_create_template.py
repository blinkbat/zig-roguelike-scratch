import json
from pathlib import Path
import sys
import tempfile
import unittest

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/tile_art'))
from art_support import generate


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


if __name__ == '__main__':
    unittest.main()
