from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).parent
patterns = json.loads((root / 'connections.json').read_text(encoding='utf-8'))['patterns']
assert len(patterns) == len({p['neighbor_mask'] for p in patterns}) == 47
title_font = ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 23)
body_font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 12)
id_font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 10)
grid = Image.new('RGBA',(512,448))
g = ImageDraw.Draw(grid)
for x in range(0,512,64):
    g.line((x,64,x,447),fill=(125,125,125,255))
for y in range(64,448,64):
    g.line((0,y,511,y),fill=(125,125,125,255))
g.line((511,64,511,447),fill=(125,125,125,255))
g.line((0,447,511,447),fill=(125,125,125,255))
g.line((458,394,501,437),fill=(125,125,125,255),width=2)
g.line((501,394,458,437),fill=(125,125,125,255),width=2)
grid.save(root/'edit-grid.png')
for name,title in [('regular-walls','REGULAR WALLS'),('forest-tree-walls','FOREST TREE WALLS'),('cave-walls','CAVE WALLS')]:
    labels = Image.new('RGBA',(512,448))
    d = ImageDraw.Draw(labels)
    d.text((12,8),title,font=title_font,fill=(50,50,50,255))
    d.text((12,40),'64 x 64 px | 47 unique patterns | X = unused',font=body_font,fill=(100,100,100,255))
    for i in range(47):
        d.text((4+(i%8)*64,68+(i//8)*64),f'{i+1:02}',font=id_font,fill=(125,125,125,255))
    labels.save(root/(name+'-edit-labels.png'))
manifest = {
    'purpose':'Import the user-painted Draw here layer after editing; never import the grid, labels, guide or underdrawing.',
    'files':['regular-walls.aseprite','forest-tree-walls.aseprite','cave-walls.aseprite'],
    'canvas':[512,448], 'cell_size':[64,64], 'grid_origin':[0,64],
    'art_layer':'Draw here', 'unused_cells':[[448,384,64,64]],
    'neighbor_bits':{'N':1,'E':2,'S':4,'W':8,'NE':16,'SE':32,'SW':64,'NW':128},
    'tiles':[{'id':p['id'],'neighbor_mask':p['neighbor_mask'],'rect':[((p['id']-1)%8)*64,64+((p['id']-1)//8)*64,64,64]} for p in patterns],
    'note':'Every neighbor mask occurs once. Similar silhouettes at different offsets represent distinct connections. This is an editing template, not a currently integrated or seam-validated game atlas.'
}
(root/'wall-import-map.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print('47 unique cells; one unused cell crossed out; import mapping saved.')
