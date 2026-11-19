import sys
from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
from art_support import sheet_title

out, title = sys.argv[1], sys.argv[2]
image = Image.new('RGBA', (512, 64))
sheet_title(ImageDraw.Draw(image), title)
image.save(out)
