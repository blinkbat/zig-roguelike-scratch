local root = 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/output/wall-mocks/'
local desktop = 'C:/Users/DavidBennett/Desktop/'
local sets = {{'regular-walls','regular-connections.png'},{'forest-tree-walls','forest-connections.png'},{'cave-walls','cave-connections.png'}}
local function compact(source)
  local result = Image(512,448,ColorMode.RGB)
  for i=0,46 do
    local col,row = i%8,math.floor(i/8)
    local piece = Image(source,Rectangle(48+col*192,102+row*148,96,96))
    piece:resize{width=64,height=64,method='bilinear'}
    result:drawImage(piece,Point(col*64,64+row*64))
  end
  return result
end
local function add(sprite,name,image,visible)
  local layer = sprite:newLayer()
  layer.name = name
  if image then sprite:newCel(layer,1,image,Point(0,0)) end
  layer.isVisible = visible
  layer.isEditable = false
  return layer
end
local report = assert(io.open(root .. 'edit-template-validation.txt','w'))
local guideImage = compact(Image{fromFile=root .. 'connections-guide.png'})
for _,item in ipairs(sets) do
  local name,sourceName = item[1],item[2]
  local destination = desktop .. name .. '.aseprite'
  local previous = app.open(destination)
  assert(previous)
  previous:saveCopyAs(root .. name .. '-before-edit-template.aseprite')
  previous:close()
  local sprite = Sprite(512,448,ColorMode.RGB)
  sprite.gridBounds = Rectangle(0,64,64,64)
  local background = Image(512,448,ColorMode.RGB)
  background:clear(app.pixelColor.rgba(255,255,255,255))
  sprite.layers[1].name = 'Paper - hide for transparent export'
  sprite.layers[1].isEditable = false
  sprite:newCel(sprite.layers[1],1,background,Point(0,0))
  local under = add(sprite,'Underdrawing (25%)',compact(Image{fromFile=root .. sourceName}),true)
  under.opacity = 64
  local guide = add(sprite,'Exact connection guide (hidden)',guideImage,false)
  guide.opacity = 64
  add(sprite,'Labels - hide before export',Image{fromFile=root .. name .. '-edit-labels.png'},true)
  add(sprite,'64x64 grid + X unused - hide before export',Image{fromFile=root .. 'edit-grid.png'},true)
  local drawing = add(sprite,'Draw here',Image(512,448,ColorMode.RGB),true)
  drawing.isEditable = true
  for i=0,46 do
    local slice = sprite:newSlice(Rectangle((i%8)*64,64+math.floor(i/8)*64,64,64))
    slice.name = string.format('Connection %02d',i+1)
  end
  sprite.data = 'Paint on Draw here. 47 unique connection masks, each exactly 64x64; cells adjoin. X is unused. Grid and drawing references are separate locked layers. Underdrawing is 25% opacity. The import map is output/wall-mocks/wall-import-map.json. Export only Draw here; keep the canvas, named slices, and positions unchanged. The faint art is a guide, not a seam-validated production tileset.'
  app.layer = drawing
  sprite:saveAs(destination)
  sprite:close()
  local check = app.open(destination)
  assert(check.width==512 and check.height==448 and #check.layers==6)
  assert(check.gridBounds==Rectangle(0,64,64,64) and #check.slices==47)
  assert(check.layers[2].opacity==64 and check.layers[2].isVisible)
  assert(check.layers[5].isVisible and not check.layers[5].isEditable)
  assert(check.layers[6].name=='Draw here' and check.layers[6].isEditable)
  local drawCel = check.layers[6]:cel(1)
  assert(not drawCel or drawCel.image:isEmpty())
  for _,slice in ipairs(check.slices) do
    assert(slice.bounds.width==64 and slice.bounds.height==64)
  end
  app.layer = check.layers[6]
  check:saveAs(destination)
  check:saveCopyAs(root .. name .. '-edit-preview.png')
  report:write(name .. ': 47 64x64 slices; 25% underdrawing; grid above; empty editable Draw here on top; X unused\n')
  report:flush()
  check:close()
end
report:close()
