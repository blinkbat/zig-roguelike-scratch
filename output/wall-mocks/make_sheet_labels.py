from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).parent
patterns = json.loads((root / 'connections.json').read_text(encoding='utf-8'))['patterns']
title_font = ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 28)
body_font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 15)
label_font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 12)
grid = Image.new('RGBA', (1024, 864))
g = ImageDraw.Draw(grid)
for pattern in patterns:
    i = pattern['id'] - 1
    x, y = 32 + (i % 8) * 128, 96 + (i // 8) * 128
    g.rectangle((x, y, x+63, y+63), outline=(140,140,140,255), width=1)
grid.save(root / 'spaced-grid.png')
for name, title in [('regular-walls','REGULAR WALLS'),('forest-tree-walls','FOREST TREE WALLS'),('cave-walls','CAVE WALLS')]:
    image = Image.new('RGBA', (1024,864))
    draw = ImageDraw.Draw(image)
    draw.text((32,22),title,font=title_font,fill=(35,35,35,255))
    draw.text((32,58),'47 connection mocks | Each outlined cell is 64 x 64 pixels',font=body_font,fill=(85,85,85,255))
    for pattern in patterns:
        i, mask = pattern['id'] - 1, pattern['neighbor_mask']
        cardinal = mask & 15
        count = cardinal.bit_count()
        kind = 'ISOLATED' if count == 0 else 'END' if count == 1 else 'STRAIGHT' if cardinal in (5,10) else 'CORNER' if count == 2 else 'T-JUNCTION' if count == 3 else 'SOLID' if mask == 255 else 'CROSS'
        x, y = 64+(i%8)*128, 168+(i//8)*128
        draw.text((x,y),f'{i+1:02}  {kind}',font=label_font,fill=(45,45,45,255),anchor='mt')
    image.save(root / (name+'-labels.png'))
print('Created 47 labels and exact 64x64 cell outlines for each sheet.')
