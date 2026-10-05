local root = 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/output/wall-mocks/'
local desktop = 'C:/Users/DavidBennett/Desktop/'
local names = {'regular-walls', 'forest-tree-walls', 'cave-walls'}
local rgba = app.pixelColor.rgba
local function pack(source)
  local result = Image(512,384,ColorMode.RGB)
  result:clear(rgba(255,255,255,255))
  for i=0,46 do
    local col,row = i%8,math.floor(i/8)
    local piece = Image(source,Rectangle(36+col*192,88+row*148,120,120))
    piece:resize{width=64,height=64,method='bilinear'}
    result:drawImage(piece,Point(col*64,row*64))
  end
  return result
end
local grid = Image(512,384,ColorMode.RGB)
local line = rgba(120,120,120,255)
for x=0,511,64 do
  for y=0,383 do grid:putPixel(x,y,line) end
end
for y=0,383,64 do
  for x=0,511 do grid:putPixel(x,y,line) end
end
for x=0,511 do grid:putPixel(x,383,line) end
for y=0,383 do grid:putPixel(511,y,line) end
local guideImage = pack(Image{fromFile=root .. 'connections-guide.png'})
local report = assert(io.open(root .. 'grid-64-validation.txt','w'))
local stamp = os.date('%Y%m%d-%H%M%S')
for _,name in ipairs(names) do
  local destination = desktop .. name .. '.aseprite'
  local original = app.open(destination)
  assert(original and original.width==1536 and original.height==1024)
  original:saveCopyAs(root .. name .. '-before-grid-' .. stamp .. '.aseprite')
  local source = Image(1536,1024,ColorMode.RGB)
  source:clear(rgba(255,255,255,255))
  local cel = original.layers[1]:cel(1)
  source:drawImage(cel.image,cel.position)
  original:close()
  local artImage = pack(source)
  local sprite = Sprite(512,384,ColorMode.RGB)
  sprite.gridBounds = Rectangle(0,0,64,64)
  local art = sprite.layers[1]
  art.name = 'Artwork - 47 pieces in 64x64 cells'
  sprite:newCel(art,1,artImage,Point(0,0))
  local guide = sprite:newLayer()
  guide.name = 'Connection guide (hidden)'
  sprite:newCel(guide,1,guideImage,Point(0,0))
  guide.isVisible = false
  local gridLayer = sprite:newLayer()
  gridLayer.name = '64x64 grid - hide for clean artwork'
  sprite:newCel(gridLayer,1,grid,Point(0,0))
  gridLayer.isEditable = false
  for i=0,46 do
    local slice = sprite:newSlice(Rectangle((i%8)*64,math.floor(i/8)*64,64,64))
    slice.name = string.format('Connection %02d',i+1)
  end
  sprite.data = '47 grayscale wall connection mocks in exact 64x64 cells. Sheet: 8 columns x 6 rows, final cell unused. Grid is a separate visible layer. These remain concept mocks, not seam-validated autotiles. Original full-resolution files backed up in output/wall-mocks.'
  app.layer = art
  sprite:saveAs(destination)
  sprite:close()
  local check = app.open(destination)
  assert(check.width==512 and check.height==384)
  assert(check.gridBounds==Rectangle(0,0,64,64))
  assert(#check.slices==47 and #check.layers==3)
  for _,slice in ipairs(check.slices) do
    assert(slice.bounds.width==64 and slice.bounds.height==64)
    assert(slice.bounds.x%64==0 and slice.bounds.y%64==0)
  end
  assert(check.layers[1]:cel(1).image:isEqual(artImage))
  assert(check.layers[3].isVisible and not check.layers[2].isVisible)
  check:saveCopyAs(root .. name .. '-64-grid.png')
  report:write(name .. ': reopened; 512x384; 47 exact 64x64 slices; grid 64x64; artwork pixels match\n')
  report:flush()
  check:close()
end
report:close()
