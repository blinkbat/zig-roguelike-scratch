from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).parent
FONT = 'C:/Windows/Fonts/arial.ttf'
diagonals = [(1, 2, 16), (2, 4, 32), (4, 8, 64), (8, 1, 128)]
masks = []
for cardinal in range(16):
    valid = [bit for a, b, bit in diagonals if cardinal & a and cardinal & b]
    for subset in range(1 << len(valid)):
        masks.append(cardinal | sum(bit for i, bit in enumerate(valid) if subset & (1 << i)))
masks.sort(key=lambda m: ((m & 15).bit_count(), m & 15, m >> 4))
assert len(masks) == len(set(masks)) == 47
im = Image.new('RGB', (1536, 1024), 'white')
draw = ImageDraw.Draw(im)
draw.text((768, 24), '47 WALL CONNECTIONS', font=ImageFont.truetype(FONT, 36), fill=(32, 32, 32), anchor='mt')
positions = [(1, 0, 1), (2, 1, 2), (1, 2, 4), (0, 1, 8), (2, 0, 16), (2, 2, 32), (0, 2, 64), (0, 0, 128)]
manifest = []
for index, mask in enumerate(masks):
    x, y = 48 + (index % 8) * 192, 102 + (index // 8) * 148
    cells = {(1, 1)} | {(cx, cy) for cx, cy, bit in positions if mask & bit}
    for cx, cy in cells:
        draw.rectangle((x + cx*32, y + cy*32, x + cx*32 + 31, y + cy*32 + 31), fill=(155,155,155))
    for cx, cy in cells:
        x0, y0 = x + cx*32, y + cy*32
        for dx, dy, line in [(0,-1,(x0,y0,x0+32,y0)),(1,0,(x0+32,y0,x0+32,y0+32)),(0,1,(x0,y0+32,x0+32,y0+32)),(-1,0,(x0,y0,x0,y0+32))]:
            if (cx+dx,cy+dy) not in cells:
                draw.line(line, fill=(32,32,32), width=3)
    draw.text((x+48,y+107), f'{index+1:02}', font=ImageFont.truetype(FONT,20), fill=(32,32,32), anchor='mt')
    manifest.append({'id': index+1, 'neighbor_mask':mask, 'bounds':[x,y,96,96]})
im.save(ROOT / 'connections-guide.png')
(ROOT / 'connections.json').write_text(json.dumps({'bits':{'N':1,'E':2,'S':4,'W':8,'NE':16,'SE':32,'SW':64,'NW':128},'patterns':manifest},indent=2)+'\n', encoding='utf-8')
print('Created and verified 47 unique connection patterns.')
