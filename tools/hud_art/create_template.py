import argparse
import json
import math
from pathlib import Path
import re
import tempfile
import sys

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
DESKTOP = Path.home() / 'Desktop'
OUTPUT = DESKTOP / 'hud-elements.aseprite'
SOURCE = ROOT / 'assets/source/hud-elements.aseprite'
WORK = Path(tempfile.gettempdir()) / 'hud-template'
SIZE = (1024, 1024)
parser = argparse.ArgumentParser()
parser.add_argument('--guides-only', action='store_true')
args = parser.parse_args()
if not args.guides_only:
    for destination in (OUTPUT, SOURCE):
        if destination.exists():
            raise SystemExit(f'Refusing to overwrite editable artwork: {destination}')
WORK.mkdir(parents=True, exist_ok=True)

paper = Image.new('RGBA', SIZE, (28, 30, 34, 255))
under = Image.new('RGBA', SIZE)
guides = Image.new('RGBA', SIZE)
labels = Image.new('RGBA', SIZE)
ud = ImageDraw.Draw(under)
gd = ImageDraw.Draw(guides)
ld = ImageDraw.Draw(labels)
INK = (232, 221, 198, 255)
CYAN = (112, 218, 237, 255)
FONT = 'C:/Windows/Fonts/arial.ttf'
BOLD = 'C:/Windows/Fonts/arialbd.ttf'
slices = []


def text(x, y, value, size=13, bold=False):
    ld.text((x, y), value, font=ImageFont.truetype(BOLD if bold else FONT, size), fill=INK)


def section(y, title):
    ld.line((24, y - 16, 1000, y - 16), fill=INK)
    text(24, y, title, 16, True)


def dotted(x0, y0, x1, y1):
    distance = max(abs(x1 - x0), abs(y1 - y0))
    for step in range(distance + 1):
        if step % 6 < 3:
            t = step / max(1, distance)
            gd.point((round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t)), fill=CYAN)


def cell(name, x, y, w, h, description, center=None):
    item = dict(name=name, x=x, y=y, w=w, h=h, description=description)
    if center:
        item['center'] = center
    slices.append(item)
    gd.rectangle((x - 1, y - 1, x + w, y + h), outline=CYAN)
    return x, y


def ring(x, y, size=104):
    ud.ellipse((x, y, x + size - 1, y + size - 1), outline=INK, width=2)
    ud.ellipse((x + 5, y + 5, x + size - 6, y + size - 6), outline=INK)
    dotted(x + size // 2, y - 5, x + size // 2, y + size + 4)
    dotted(x - 5, y + size // 2, x + size + 4, y + size // 2)


def reservoir(x, y, core, edge, size=88):
    tile = Image.new('RGBA', (size, size))
    radius = size / 2
    for yy in range(size):
        for xx in range(size):
            distance = math.hypot(xx + .5 - radius, yy + .5 - radius) / radius
            if distance <= 1:
                tile.putpixel((xx, yy), tuple(round(a + (b - a) * distance) for a, b in zip(core, edge)) + (255,))
    under.alpha_composite(tile, (x, y))


skill_source = (ROOT / 'src/gfx/look.zig').read_text(encoding='utf-8')
skill_source = skill_source.split('fn skillLines(', 1)[1].split('pub fn arrowInk', 1)[0]
skill_lines = {}
for name, body in re.findall(r'\.(\w+)\s*=>\s*&\.\{(.*?)\n        \},', skill_source, re.S):
    skill_lines[name] = [tuple(map(float, row)) for row in re.findall(r'\.\{\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\s*\}', body)]
assert len(skill_lines) == 6
hud_source = (ROOT / 'src/ui/hud.zig').read_text(encoding='utf-8')


def hud_rgb(name):
    hex_ = re.search(rf'const {name} = look\.rgb\(0x([0-9a-fA-F]{{6}})\)', hud_source).group(1)
    return tuple(int(hex_[i:i + 2], 16) for i in (0, 2, 4))


LIFE = (hud_rgb('LIFE_CORE'), hud_rgb('LIFE_EDGE'))
MANA = (hud_rgb('MANA_CORE'), hud_rgb('MANA_EDGE'))
PLATE = hud_rgb('PLATE')
WELL = hud_rgb('WELL')


def skill(name, x, y):
    for ax, ay, bx, by in skill_lines[name]:
        ud.line((x + round(ax * 1.25), y + round(ay * 1.25), x + round(bx * 1.25), y + round(by * 1.25)), fill=INK, width=2)


text(24, 16, 'HUD ELEMENTS / PAINT TEMPLATE', 24, True)
text(24, 51, 'Paint on DRAW HERE. Faint locked layers are guides only. All component sizes are native game pixels.', 14)
text(24, 84, '01  ASSEMBLED REFERENCE / 744 x 172', 16, True)
ox, oy = cell('REFERENCE_ONLY_assembled', 24, 112, 744, 172, 'Guide only. Do not export as artwork.')
ud.rectangle((ox + 64, oy + 66, ox + 679, oy + 153), fill=PLATE, outline=INK, width=2)
for cx, core, edge in ((ox + 64, *LIFE), (ox + 680, *MANA)):
    ud.ellipse((cx - 52, oy + 52, cx + 51, oy + 155), fill=WELL, outline=INK, width=2)
    reservoir(cx - 44, oy + 60, core, edge)
for dx, act in zip((0, 76, 138, 200, 262, 338, 400), ('secondary', None, 'shoot', 'wait', 'juke', 'burning_arrow', 'glacial_shot')):
    x, y = ox + 144 + dx, oy + 76
    ud.rectangle((x, y, x + 55, y + 55), outline=INK, width=2)
    if act:
        skill(act, x + 8, y + 8)
for y, line in enumerate(('Actual size / 1:1', 'One continuous base', '104px orb frames', '88px fill aperture', '56px skill slots', 'Text stays in code')):
    text(800, 124 + y * 24, line)

section(324, '02  PANEL + SLOT PARTS')
panels = ((24, 'PANEL BORDER', '48 x 48 / 16px cuts'), (224, 'SEAMLESS BACKGROUND', '32 x 32 / wraps X + Y'), (424, 'SKILL FRAME', '56 x 56 / 40px icon'), (624, 'ACTIVE SKILL FRAME', '56 x 56 / same inset'), (824, 'AILMENT FRAME', '32 x 32 / turns in code'))
for x, title, note in panels:
    text(x, 356, title, 13, True)
    text(x, 376, note, 12)

x, y = cell('hud_border_9slice', 24, 406, 48, 48, '16px corners; repeat edge strips. Keep the center transparent.', [16, 16, 16, 16])
ud.rectangle((x, y, x + 47, y + 47), outline=INK, width=2)
for offset in (16, 32):
    dotted(x + offset, y, x + offset, y + 47)
    dotted(x, y + offset, x + 47, y + offset)
text(24, 474, 'Corners stay fixed.', 12)
text(24, 492, 'Edges repeat; center clear.', 12)
x, y = cell('hud_background_tile', 224, 406, 32, 32, 'Repeat seamlessly on all four edges. No border or lighting gradient.')
ud.rectangle((x, y, x + 31, y + 31), fill=(128, 128, 128), outline=INK)
text(224, 474, 'Match opposite edges.', 12)
text(224, 492, 'Paint only this 32px tile.', 12)
for name, x in (('skill_frame', 424), ('skill_frame_active', 624)):
    _, y = cell(name, x, 406, 56, 56, '40px icon at inset 8; transparent inside. Labels and cooldowns stay in code.')
    ud.rectangle((x, y, x + 55, y + 55), outline=INK, width=2 if name == 'skill_frame' else 3)
    gd.rectangle((x + 8, y + 8, x + 47, y + 47), outline=CYAN)
    text(x, 474, 'Cyan box = icon space.', 12)
    text(x, 492, 'Keep the middle clear.', 12)
x, y = cell('ailment_frame', 824, 406, 32, 32, 'Transparent center. The game adds a 24px icon and remaining turns.')
ud.rectangle((x, y, x + 31, y + 31), outline=INK)
text(824, 474, 'Bottom right = turn count.', 12)
text(824, 492, 'No text in painted art.', 12)

section(546, '03  ORBS / FRAME + WELL + FULL FILL + OPTIONAL GLASS')
orbs = ((24, 'LIFE FRAME', 'orb_frame_life', 104), (184, 'MANA FRAME', 'orb_frame_mana', 104), (344, 'EMPTY WELL', 'orb_well', 88), (504, 'LIFE FILL', 'orb_fill_life', 88), (664, 'MANA FILL', 'orb_fill_mana', 88), (824, 'GLASS / GLINT', 'orb_glass', 104))
for x, title, name, size in orbs:
    text(x, 582, title, 13, True)
    text(x, 602, f'{size} x {size}', 12)
    cell(name, x, 626, size, size, 'Centered 88px circular aperture at inset 8.' if size == 104 else '88px circular reservoir. Keep pixels outside the circle transparent.')
    if 'frame' in name:
        ring(x, 626)
        gd.ellipse((x + 8, 634, x + 95, 721), outline=CYAN)
    elif name == 'orb_glass':
        gd.ellipse((x + 8, 634, x + 95, 721), outline=CYAN)
        ud.ellipse((x + 29, 648, x + 34, 659), fill=INK)
    else:
        colours = LIFE if name == 'orb_fill_life' else MANA if name == 'orb_fill_mana' else ((54, 60, 75), (24, 29, 40))
        reservoir(x, 626, *colours)
        gd.ellipse((x, 626, x + 87, 713), outline=CYAN)
text(24, 750, 'Frames: keep the cyan opening clear. Fills: paint FULL orbs; the game clips the fill height as life or mana changes.', 13)
text(24, 771, 'Glass: optional transparent highlight overlay. No numbers, labels or baked half-empty states.', 13)

section(821, '04  SKILL ICONS / 40 x 40')
text(764, 821, 'AILMENT ICONS / 24 x 24', 14, True)
for x, title, name in ((24, 'SHOOT', 'shoot'), (144, 'WAIT', 'wait'), (264, 'SECOND SET', 'secondary'), (384, 'JUKE', 'juke'), (504, 'BURNING', 'burning_arrow'), (624, 'GLACIAL', 'glacial_shot')):
    text(x, 856, title, 12, True)
    cell('skill_' + name, x, 884, 40, 40, '40px ability icon. Transparent outside the drawing.')
    skill(name, x, 884)
for x, title, name in ((764, 'BLEED', 'bleeding'), (844, 'BURN', 'burning'), (924, 'CHILL', 'chilled')):
    text(x, 856, title, 12, True)
    cell('ailment_' + name, x, 884, 24, 24, '24px ailment icon. Turn count stays in code.')
    cx, cy = x + 12, 896
    if name in ('bleeding', 'burning'):
        ud.ellipse((cx - 5, cy - 1, cx + 5, cy + 9), fill=INK)
        ud.polygon(((cx + (2 if name == 'burning' else 0), cy - 8), (cx - 5, cy + 4), (cx + 5, cy + 4)), fill=INK)
    else:
        for ax, ay, bx, by in ((0, -8, 0, 8), (-7, -4, 7, 4), (-7, 4, 7, -4)):
            ud.line((cx + ax, cy + ay, cx + bx, cy + by), fill=INK)

ld.line((24, 956, 1000, 956), fill=INK)
text(24, 970, 'DRAW HERE = your artwork. Hide PAPER and all GUIDE layers before exporting named component slices.', 13, True)
text(24, 993, 'Underdrawing 25%  /  alignment 22%  /  labels + separators 45%  /  paint 100%. Save this .aseprite to keep layers.', 12)

for name, image in (('paper', paper), ('under', under), ('guides', guides), ('labels', labels)):
    image.save(WORK / (name + '.png'))
(WORK / 'slices.json').write_text(json.dumps(slices, indent=2), encoding='utf-8')
if args.guides_only:
    print(f'Prepared guide PNGs only in {WORK}; editable sources unchanged.')
    sys.exit(0)


def quote(value):
    return json.dumps(str(value).replace('\\', '/'))


lua = [f'local sprite=Sprite({SIZE[0]},{SIZE[1]},ColorMode.RGB)', 'local expected={}']
layers = [('PAPER - hide before export', 'paper', 255), ('GUIDE - underdrawing 25%', 'under', 64), ('GUIDE - alignment 22%', 'guides', 56), ('GUIDE - labels and separators 45%', 'labels', 115)]
for index, (name, file, opacity) in enumerate(layers):
    lua.extend(['do', 'local layer=' + ('sprite.layers[1]' if index == 0 else 'sprite:newLayer()'), f'layer.name={quote(name)}', f'layer.opacity={opacity}', f'local img=Image{{fromFile={quote(WORK / (file + ".png"))}}}', 'sprite:newCel(layer,1,img,Point(0,0))', 'layer.isEditable=false', 'expected[#expected+1]={name=layer.name,opacity=layer.opacity,image=img}', 'end'])
lua.extend(['local paint=sprite:newLayer()', 'paint.name="Draw here"', 'sprite:newCel(paint,1,Image(sprite.width,sprite.height,ColorMode.RGB),Point(0,0))', 'app.layer=paint'])
for s in slices:
    lua.extend(['do', f'local slice=sprite:newSlice(Rectangle({s["x"]},{s["y"]},{s["w"]},{s["h"]}))', f'slice.name={quote(s["name"])}', f'slice.data={quote(s["description"])}'])
    if s.get('center'):
        lua.append('slice.center=Rectangle(' + ','.join(map(str, s['center'])) + ')')
    lua.append('end')
lua.extend([f'sprite.data={quote("HUD component template. Native pixels; only Draw here is artwork. See docs/HUD_LAYOUT.md. Named slices exclude labels. Assembled reference is not an export.")}', f'sprite:saveAs({quote(OUTPUT)})', f'sprite:saveCopyAs({quote(SOURCE)})', f'sprite:saveCopyAs({quote(WORK / "hud-elements-preview.png")})', 'sprite:close()'])
lua.extend([f'for _,path in ipairs({{{quote(OUTPUT)},{quote(SOURCE)}}}) do', 'local saved=assert(app.open(path))', f'assert(saved.width=={SIZE[0]} and saved.height=={SIZE[1]} and #saved.frames==1)', f'assert(#saved.layers=={len(layers) + 1} and #saved.slices=={len(slices)})', 'for i,want in ipairs(expected) do', 'local layer=saved.layers[i]', 'assert(layer.name==want.name and layer.opacity==want.opacity and not layer.isEditable)', 'local image=Image(saved.width,saved.height,ColorMode.RGB)', 'local cel=assert(layer:cel(1))', 'image:drawImage(cel.image,cel.position)', 'assert(image:isEqual(want.image),"Guide pixels changed on save")', 'end', f'local paint=saved.layers[{len(layers) + 1}]', 'assert(paint.name=="Draw here" and paint.opacity==255 and paint.isEditable)', 'if paint:cel(1) then assert(paint:cel(1).image:isEmpty(),"Paint layer is not blank") end', 'local borders=0', 'for _,slice in ipairs(saved.slices) do', f'assert(slice.bounds.x>=0 and slice.bounds.y>=0 and slice.bounds.x+slice.bounds.width<={SIZE[0]} and slice.bounds.y+slice.bounds.height<={SIZE[1]})', 'if slice.name=="hud_border_9slice" then assert(slice.center.x==16 and slice.center.y==16 and slice.center.width==16 and slice.center.height==16); borders=borders+1 end', 'end', 'assert(borders==1)', 'saved:close()', 'end', f'local report=assert(io.open({quote(WORK / "validation.txt")},"w"))', f'report:write("Verified both Aseprite files after reopening: {SIZE[0]}x{SIZE[1]}, {len(layers) + 1} layers, {len(slices) - 1} component slices plus 1 reference; 16px nine-slice center; faint guides locked, paint layer blank and editable. Guide pixels unchanged.\\n")', 'report:close()'])
(WORK / 'assemble.lua').write_text('\n'.join(lua) + '\n', encoding='utf-8')
print(f'Prepared {len(slices) - 1} component guides and native Aseprite assembly: {WORK / "assemble.lua"}')
