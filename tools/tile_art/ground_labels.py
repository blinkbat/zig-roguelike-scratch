import re
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out, title = sys.argv[1], sys.argv[2]
order = [int(n) for n in re.findall(r'\d+', (Path(__file__).parent / 'ground_corners.lua').read_text().split('return', 1)[1])]
assert sorted(order) == list(range(16))

INK = (50, 50, 50, 255)
W, H, HEAD, CELL = 512, 320, 64, 64
image = Image.new('RGBA', (W, H))
draw = ImageDraw.Draw(image)
draw.text((12, 8), title, font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 23), fill=INK)
small = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 11)
for i, mask in enumerate(order):
    x, y = (i % 4) * CELL, HEAD + (i // 4) * CELL
    if mask:
        draw.text((x + 3, y + 2), str(mask), font=small, fill=INK)
notes = [
    'Each cell sits where four map',
    'cells meet; shaded quarters are',
    'this terrain, clear ones what',
    'lies under it.',
    '',
    'Mask: NW 1, NE 2, SW 4, SE 8.',
    '',
    'Neighbouring cells share their',
    'corners: paint across the grid',
    'as one picture. The edge wanders',
    'about the quarter lines.',
    '',
    '15 is the plain fill: its four',
    'sides must wrap. X is unused.',
]
for k, line in enumerate(notes):
    draw.text((272, HEAD + 4 + k * 17), line, font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 13), fill=INK)
image.save(out)
