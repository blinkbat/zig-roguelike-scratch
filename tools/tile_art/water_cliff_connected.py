import argparse
from pathlib import Path
import sys
import tempfile

from PIL import Image, ImageDraw
sys.dont_write_bytecode = True
from art_support import (DESKTOP, ROOT, SCRIPTS, arial, corner_order, ground_layout, layer_names, quote as q,
                         water_cliff_layer, water_cliff_layout, water_cliff_names, water_cliff_slice)


parser = argparse.ArgumentParser()
parser.add_argument('shots', type=Path)
parser.add_argument('--output', type=Path, default=DESKTOP / 'water-cliff-connections.aseprite')
parser.add_argument('--replace', action='store_true')
args = parser.parse_args()
args.output, args.shots = args.output.resolve(), args.shots.resolve()
if args.output.suffix.lower() != '.aseprite':
    raise SystemExit('--output must be an .aseprite file; its .png preview is written beside it.')
if not args.replace and (args.output.exists() or args.output.with_suffix('.png').exists()):
    raise SystemExit('Preserving existing connected template; choose a new --output.')
work = Path(tempfile.mkdtemp(prefix='cistern-connected-cliffs-'))
layout = water_cliff_layout()
size = (layout['width'], layout['height'])
block_x, block_y, stride, block, cell = (layout[key] for key in ('x', 'y', 'stride', 'block', 'cell'))
cols = block // cell
faces_y = 496
corners = ground_layout()
labels = Image.new('RGBA', size)
guides = Image.new('RGBA', size)
ld, gd = ImageDraw.Draw(labels), ImageDraw.Draw(guides)
order = corner_order()
assert len(order) == cols * cols and block == cols * cell


def text(x, y, value, px=14, bold=False):
    ld.text((x, y), value, font=arial(px, bold), fill=(45, 48, 52, 255), spacing=5)


text(32, 18, 'WATER CLIFF CONNECTIONS', 26, True)
text(32, 52, 'Native 64px tiles. Each 4 x 4 block connects in place. Rendered directly by the game; lighting is not baked.')
cliff_names = water_cliff_names()
names = cliff_names['blocks']
for n, name in enumerate(names):
    x = block_x + n * stride
    text(x, block_y - 27, name, 17, True)
    for i in range(cols + 1):
        gd.line((x + i * cell, block_y, x + i * cell, block_y + block - 1), fill=(255, 90, 120, 155))
        gd.line((x, block_y + i * cell, x + block - 1, block_y + i * cell), fill=(255, 90, 120, 155))
    text(x, block_y + block + 13, 'HIGH-GROUND MASKS / same tile order', 11, True)
    for i, mask in enumerate(order):
        cx, cy = x + (i % cols) * cell, block_y + block + 36 + (i // cols) * 12
        text(cx, cy, f'{mask:02d}', 10)
        for bit, dx, dy in ((corners['NW'], 0, 0), (corners['NE'], 1, 0), (corners['SW'], 0, 1), (corners['SE'], 1, 1)):
            ld.rectangle((cx + 20 + dx * 5, cy + dy * 5, cx + 23 + dx * 5, cy + 3 + dy * 5),
                         fill=(92, 83, 63, 255) if mask & bit else (96, 151, 175, 255))
text(block_x, 466, 'SHALLOW FACE / left - repeat - right', 13, True)
text(block_x + stride, 466, 'DEEP FACE / left - repeat - right', 13, True)
text(block_x + 2 * stride, 466, 'CONNECTION KEY', 13, True)
text(block_x + 2 * stride, 490, 'NW = 1   NE = 2\nSW = 4   SE = 8\nBrown = upper surface\nBlue = lower water', 13)
text(32, 576, 'Ground, cliff faces, and lip/cap fill are separate editable layers. Pink grid is hidden.', 14)
text(32, 600, 'Original face pieces below are unchanged RGBA. Lip shadows fall on the cliff AND water at runtime.', 14)
labels.save(work / 'labels.png')
guides.save(work / 'grid.png')
lua = [f'local sourceFiles=dofile({q(SCRIPTS / "source_files.lua")})']
lua.append(f'for _,path in ipairs({{{q(args.output)},{q(args.output.with_suffix(".png"))}}}) do')
if args.replace:
    lua.extend([
        'if app.fs.isFile(path) then', 'local backup', 'local n=0', 'repeat',
        'n=n+1', f'backup=app.fs.joinPath({q(work)},"before-assembly-"..n.."-"..app.fs.fileName(path))',
        'until not app.fs.isFile(backup)', 'sourceFiles.copy(path,backup)', 'end',
    ])
else:
    lua.append('assert(not app.fs.isFile(path),"Refusing to overwrite editable artwork: "..path)')
lua.extend(['end', f'local s=Sprite({size[0]},{size[1]},ColorMode.RGB)', 'local first=s.layers[1]', 'local expected={}'])


def layer(name, path, x=0, y=0, editable=True, visible=True):
    lua.extend([
        'do', f'local im=Image{{fromFile={q(path)}}}', 'local l=s:newLayer()',
        f'l.name={q(name)}', f'l.isEditable={str(editable).lower()}', f'l.isVisible={str(visible).lower()}',
        f's:newCel(l,1,im,Point({x},{y}))',
        f'expected[#expected+1]={{name=l.name,image=im,x={x},y={y}}}', 'end',
    ])


paper = Image.new('RGBA', size, (236, 234, 224, 255))
paper.save(work / 'paper.png')
layer(layer_names()['paper'], work / 'paper.png', editable=False)
layer('Labels and connection keys', work / 'labels.png', editable=False)
for n, name in enumerate(names):
    source = args.shots / f'template-{n}.png'
    with Image.open(source) as im:
        assert im.size == (block, block)
    combined = None
    for part, label in cliff_names['parts']:
        part_source = args.shots / f'template-{n}-{part}.png'
        with Image.open(part_source) as im:
            pixels = im.convert('RGBA')
            assert pixels.getbbox(), f'Missing {label}'
            combined = pixels.copy() if combined is None else Image.alpha_composite(combined, pixels)
        layer(water_cliff_layer(cliff_names, name, label), part_source, block_x + n * stride, block_y)
    with Image.open(source) as im:
        assert combined.tobytes() == im.convert('RGBA').tobytes(), 'Layers differ from runtime assembly'
    for i, mask in enumerate(order):
        lua.extend([
            f'local slice=s:newSlice(Rectangle({block_x+n*stride+(i%cols)*cell},{block_y+(i//cols)*cell},{cell},{cell}))',
            f'slice.name={q(f"transition_{n}_mask_{mask:02d}")}',
        ])
for n, (depth, asset) in enumerate(zip(cliff_names['depths'], cliff_names['face_files'])):
    layer(water_cliff_layer(cliff_names, depth.capitalize(), 'original faces'), ROOT / 'assets/water' / f'{asset}.png',
          block_x + n * stride, faces_y)
    for i, piece in enumerate(cliff_names['pieces']):
        lua.extend([
            f'local slice=s:newSlice(Rectangle({block_x+n*stride+i*cell},{faces_y},{cell},{cell}))',
            f'slice.name={q(water_cliff_slice(cliff_names, depth, piece))}',
        ])
layer('64px grid - toggle while painting', work / 'grid.png', editable=False, visible=False)
lua.extend([
    's:deleteLayer(first)', 'local paint=s:newLayer()', 'paint.name="Touch-ups"', 'app.layer=paint',
    f's.gridBounds=Rectangle({block_x},{block_y},{cell},{cell})',
    's.data="Native game renders, no lighting baked. Three connected 16-mask sets, NW1 NE2 SW4 SE8. Original face strips unchanged. Rendered tiles are a new painting template, not automatically imported runtime atlases."',
    'local preview=Image(s.spec)', 'preview:drawSprite(s,1)',
    f's:saveAs({q(work / "staged.aseprite")})', f's:saveCopyAs({q(work / "staged.png")})', 's:close()',
    f'local savedPreview=Image{{fromFile={q(work / "staged.png")}}}',
    'assert(savedPreview:isEqual(preview),"Saved preview differs from the assembled template")',
    f'local saved=assert(app.open({q(work / "staged.aseprite")}))', f'assert(#saved.slices=={layout["slices"]} and #saved.layers==#expected+1)',
    'for i,want in ipairs(expected) do', 'local l=saved.layers[i]', 'assert(l.name==want.name)',
    'local actual=Image(want.image.width,want.image.height,ColorMode.RGB)',
    'local c=assert(l:cel(1))', 'actual:drawImage(c.image,Point(c.position.x-want.x,c.position.y-want.y))',
    'assert(actual:isEqual(want.image),"Layer pixels changed: "..want.name)', 'end',
    'saved:close()',
    f'sourceFiles.publish({{sourceFiles.staged({q(args.output)},{q(work / "staged.aseprite")}),'
    f'sourceFiles.staged({q(args.output.with_suffix(".png"))},{q(work / "staged.png")})}})',
    f'sourceFiles.write({q(work / "validation.txt")},"Verified {size[0]}x{size[1]} Aseprite, {layout["slices"]} named slices, "..(#expected+1).." layers; art layers preserved pixel-for-pixel and recombine exactly to runtime assembly. Grid hidden, Touch-ups editable.\\n")',
])
(work / 'assemble.lua').write_text('\n'.join(lua), encoding='utf-8')
print(work)
