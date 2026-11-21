import sys
from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
from art_support import SHEET_INK as INK, arial, corner_order, ground_layout, sheet_title

out, title = sys.argv[1], sys.argv[2]
order = corner_order()
layout = ground_layout()

W, H, HEAD, CELL, COLS = layout['W'], layout['H'], layout['HEAD'], layout['CELL'], layout['COLS']
image = Image.new('RGBA', (W, H))
draw = ImageDraw.Draw(image)
sheet_title(draw, title)
small = arial(11)
for i, mask in enumerate(order):
    x, y = (i % COLS) * CELL, HEAD + (i // COLS) * CELL
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
    draw.text((272, HEAD + 4 + k * 17), line, font=arial(13), fill=INK)
image.save(out)
