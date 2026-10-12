import sys
from PIL import Image, ImageDraw, ImageFont

# The wall sheets' header: Arial Bold 23 at (12, 8), matched pixel for pixel against cave-walls.aseprite.
out, title = sys.argv[1], sys.argv[2]
image = Image.new('RGBA', (512, 64))
ImageDraw.Draw(image).text((12, 8), title, font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 23), fill=(50, 50, 50, 255))
image.save(out)
