import sys
from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
from art_support import sheet_title, wall_layout

out, title = sys.argv[1], sys.argv[2]
layout = wall_layout()
image = Image.new('RGBA', (layout['W'], layout['HEAD']))
sheet_title(ImageDraw.Draw(image), title)
image.save(out)
