import sys
from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
from art_support import arial, corner_order, ground_layout

out, title = sys.argv[1], sys.argv[2]
order = corner_order()
layout = ground_layout()

INK = (50, 50, 50, 255)
W, HEAD, CELL, COLS = layout['W'], layout['HEAD'], layout['CELL'], layout['COLS']
H = HEAD + COLS * CELL
image = Image.new('RGBA', (W, H))
draw = ImageDraw.Draw(image)
draw.text((12, 8), title, font=arial(23, True), fill=INK)
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
