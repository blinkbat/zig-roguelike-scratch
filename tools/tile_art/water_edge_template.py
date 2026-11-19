import argparse
from pathlib import Path
import sys
import tempfile

from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
from art_support import ROOT, SCRIPTS, arial, quote, water_cliff_layout


DESKTOP = Path.home() / 'Desktop'
OUTPUT = DESKTOP / 'water-cliff-edge.aseprite'
WORK = Path(tempfile.mkdtemp(prefix='cistern-water-cliff-'))
SIZE = (512, 512)
CELL = water_cliff_layout()['cell']
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=OUTPUT)
parser.add_argument('--replace-blank', action='store_true')
args = parser.parse_args()
OUTPUT = args.output.resolve()
if OUTPUT.exists() and not args.replace_blank:
    raise SystemExit(f'Refusing to overwrite editable artwork: {OUTPUT}')

paper = Image.new('RGBA', SIZE, 'white')
under = Image.new('RGBA', SIZE)
grid = Image.new('RGBA', SIZE)
labels = Image.new('RGBA', SIZE)
reference = Image.new('RGBA', SIZE)
water_reference = Image.new('RGBA', SIZE)
ud, gd, ld, rd = (ImageDraw.Draw(im) for im in (under, grid, labels, reference))
ink = (55, 55, 55, 255)


def text(x, y, value, size=12, bold=False):
    ld.text((x, y), value, font=arial(size, bold), fill=ink, spacing=4)


def face(draw, x, y, kind, height, fill, lip):
    left = x + (32 if kind == 'left' else 0)
    right = x + (31 if kind == 'right' else 63)
    draw.rectangle((left, y, right, y + height - 1), fill=fill)
    draw.line((left, y, right, y), fill=lip)


text(12, 8, 'WATER CLIFF EDGE', 23, True)
text(12, 39, 'Six separate tiles / 64 x 64 px / paint each depth independently')
kinds = ('left', 'repeat', 'right')
slices = []
for depth, y, height, asset in (('shallow', 104, 12, 'shallows-ground.png'), ('deep', 232, 24, 'water-ground.png')):
    text(12, y - 40, f'{depth.upper()} / {height}px face guide', 13, True)
    text(324, y - 40, 'EXISTING WATER / sample colors', 11, True)
    for index, kind in enumerate(kinds):
        x = 12 + index * 96
        text(x + 3, y - 20, kind.upper(), 11, True)
        face(ud, x, y + 16, kind, height, (120, 109, 94, 255), (49, 43, 37, 255))
        gd.rectangle((x - 1, y - 1, x + 64, y + 64), outline=(160, 160, 160, 255))
        slices.append((f'water_cliff_{depth}_{kind}', x, y))
    with Image.open(ROOT / 'assets/ground' / asset) as source:
        atlas = source.convert('RGBA')
        assert atlas.size == (256, 256)
        for x, edge, crop in ((324, 'NORTH EDGE', (64, 0, 128, 64)), (420, 'SOUTH EDGE', (192, 128, 256, 192))):
            tile = atlas.crop(crop)
            water_reference.paste(tile, (x, y))
            assert water_reference.crop((x, y, x + 64, y + 64)).tobytes() == tile.tobytes()
            text(x, y - 20, edge, 10, True)
            gd.rectangle((x - 1, y - 1, x + 64, y + 64), outline=(160, 160, 160, 255))
            slices.append((f'reference_{depth}_{edge.lower().replace(" ", "_")}', x, y))
text(12, 310, 'Paint the six left-hand boxes on Draw here. References are locked.')
text(12, 330, 'Lip: row 16. Bottom: row 28 shallow / row 40 deep. Rest transparent.')
text(12, 350, 'Repeat joins both sides; ends join inward. Give each depth its own foot.')
text(12, 374, 'ASSEMBLED GUIDES — reference only', 13, True)

for x, height, name in ((12, 12, 'SHALLOW / 12px'), (268, 24, 'DEEP / 24px')):
    text(x, 398, name, 11, True)
    rd.rectangle((x, 418, x + 191, 433), fill=(202, 197, 180, 255))
    rd.rectangle((x, 434, x + 191, 467), fill=(177, 205, 217, 255))
    for index, kind in enumerate(kinds):
        face(rd, x + index * 64, 434, kind, height, (144, 131, 113, 255), (88, 79, 67, 255))
    rd.line((x + 32, 434 + height, x + 159, 434 + height), fill=(222, 237, 239, 255))
text(12, 477, 'Land above / water below / the wall faces the viewer.', 12, True)
text(12, 495, 'Water references retain original pixels and colors. No runtime export.', 11)

layers = [
    ('Paper - hide for transparent export', paper, 255),
    ('Underdrawing (25%) - hide before export', under, 64),
    ('Assembled guides - hide before export', reference, 160),
    ('Existing water colors - reference only - hide before export', water_reference, 255),
    ('Labels - hide before export', labels, 255),
    ('64x64 grid - hide before export', grid, 180),
]
lua =[f'local sourceFiles=dofile({quote(SCRIPTS / "source_files.lua")})',
      f'local s=Sprite({SIZE[0]},{SIZE[1]},ColorMode.RGB)', 'local initial=s.layers[1]', 'local expected={}']
for index, (name, image, opacity) in enumerate(layers):
    path = WORK / f'layer-{index}.png'
    image.save(path)
    lua.extend([
        'do', f'local im=Image{{fromFile={quote(path)}}}', 'local l=s:newLayer()',
        f'l.name={quote(name)}', f'l.opacity={opacity}', 'l.isEditable=false',
        's:newCel(l,1,im,Point(0,0))',
        'expected[#expected+1]={name=l.name,opacity=l.opacity,image=im}', 'end',
    ])
lua.extend(['s:deleteLayer(initial)', 'local paint=s:newLayer()', 'paint.name="Draw here"', 'app.layer=paint'])
for name, x, y in slices:
    lua.extend(['do', f'local slice=s:newSlice(Rectangle({x},{y},{CELL},{CELL}))',
                f'slice.name={quote(name)}', 'end'])
if args.replace_blank:
    lua.extend([
        f'if app.fs.isFile({quote(OUTPUT)}) then',
        f'local old=assert(app.open({quote(OUTPUT)}))',
        f'sourceFiles.checkBlankTemplate(old,{{width=s.width,height=s.height,colorMode=s.colorMode,guides=expected,slices=s.slices}},{quote(OUTPUT)})',
        f'sourceFiles.copy({quote(OUTPUT)},{quote(WORK / "previous-template.aseprite")})', 'old:close()', 'end',
    ])
else:
    lua.append(f'assert(not app.fs.isFile({quote(OUTPUT)}),"Refusing to overwrite editable artwork")')
lua.extend([
    's.data="Six independent 64px water cliff tiles: left, repeat, right at x12/108/204; shallow y104, deep y232. Lip at local y16; bottom y28 shallow, y40 deep (exclusive). Paint both depths on Draw here. Locked water references at x324/420 are unchanged 64px crops of runtime shallows-ground.png and water-ground.png, masks 12 and 3. No runtime integration."',
    f's:saveAs({quote(OUTPUT)})', 's:close()', f'local saved=assert(app.open({quote(OUTPUT)}))',
    f'assert(saved.width=={SIZE[0]} and saved.height=={SIZE[1]} and #saved.frames==1)',
    f'assert(#saved.layers=={len(layers) + 1} and #saved.slices=={len(slices)})',
    'for i,want in ipairs(expected) do', 'local l=saved.layers[i]',
    'assert(l.name==want.name and l.opacity==want.opacity and not l.isEditable)',
    'local im=Image(saved.width,saved.height,ColorMode.RGB)',
    'local cel=assert(l:cel(1)); im:drawImage(cel.image,cel.position)',
    'assert(im:isEqual(want.image),"Guide pixels changed")', 'end',
    f'local p=saved.layers[{len(layers) + 1}]', 'assert(p.name=="Draw here" and p.isEditable and p.isVisible)',
    'assert(not p:cel(1) or p:cel(1).image:isEmpty())',
    'local names={' + ','.join(f'[{quote(name)}]={{{x},{y}}}' for name, x, y in slices) + '}',
    'for _,slice in ipairs(saved.slices) do',
    'local want=assert(names[slice.name])',
    f'assert(want[1]==slice.bounds.x and want[2]==slice.bounds.y and slice.bounds.width=={CELL} and slice.bounds.height=={CELL})',
    'names[slice.name]=nil', 'end', 'assert(next(names)==nil)',
    f'saved:saveCopyAs({quote(WORK / "preview.png")})', 'saved:close()',
    f'sourceFiles.write({quote(WORK / "validation.txt")},"Verified saved Aseprite: {SIZE[0]}x{SIZE[1]}, six paint slices and four water reference slices, six locked guide/reference layers preserved pixel-for-pixel, water references at full opacity, blank editable Draw here. No runtime assets exported.\\n")',
])
(WORK / 'assemble.lua').write_text('\n'.join(lua), encoding='utf-8')
print(WORK)
