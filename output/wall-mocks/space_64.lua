local root = 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/output/wall-mocks/'
local desktop = 'C:/Users/DavidBennett/Desktop/'
local names = {'regular-walls','forest-tree-walls','cave-walls'}
local function spread(image)
  local result = Image(1024,864,ColorMode.RGB)
  for i=0,46 do
    local col,row = i%8,math.floor(i/8)
    result:drawImage(Image(image,Rectangle(col*64,row*64,64,64)),Point(32+col*128,96+row*128))
  end
  return result
end
local function add(sprite,name,image,visible)
  local layer = sprite:newLayer()
  layer.name = name
  sprite:newCel(layer,1,image,Point(0,0))
  layer.isVisible = visible
  return layer
end
local report = assert(io.open(root .. 'spaced-64-validation.txt','w'))
for _,name in ipairs(names) do
  local destination = desktop .. name .. '.aseprite'
  local original = app.open(destination)
  assert(original.width==512 and original.height==384)
  local artImage = spread(original.layers[1]:cel(1).image)
  local guideImage = spread(original.layers[2]:cel(1).image)
  original:close()
  local sprite = Sprite(1024,864,ColorMode.RGB)
  sprite.gridBounds = Rectangle(32,96,64,64)
  sprite.layers[1].name = 'White background'
  local background = Image(1024,864,ColorMode.RGB)
  background:clear(app.pixelColor.rgba(255,255,255,255))
  sprite:newCel(sprite.layers[1],1,background,Point(0,0))
  local art = add(sprite,'Artwork - 47 pieces, 64x64 each',artImage,true)
  add(sprite,'Connection guide (hidden)',guideImage,false)
  add(sprite,'64x64 outlines - hide for clean artwork',Image{fromFile=root .. 'spaced-grid.png'},true)
  add(sprite,'Labels - outside the tile cells',Image{fromFile=root .. name .. '-labels.png'},true)
  for i=0,46 do
    local slice = sprite:newSlice(Rectangle(32+(i%8)*128,96+math.floor(i/8)*128,64,64))
    slice.name = string.format('Connection %02d',i+1)
  end
  sprite.data = '47 grayscale connection mocks, 64x64 per slice, spaced on 128px centers. Visible cell outlines and labels have separate layers. 1024x864 presentation canvas. Concept mocks, not seam-validated production autotiles. Full resolution originals backed up in output/wall-mocks.'
  app.layer = art
  sprite:saveAs(destination)
  sprite:close()
  local check = app.open(destination)
  assert(check.width==1024 and check.height==864 and #check.slices==47)
  assert(check.gridBounds==Rectangle(32,96,64,64))
  assert(#check.layers==5 and not check.layers[3].isVisible)
  assert(check.layers[2]:cel(1).image:isEqual(artImage))
  for _,slice in ipairs(check.slices) do
    assert(slice.bounds.width==64 and slice.bounds.height==64)
  end
  check:saveCopyAs(root .. name .. '-spaced-64.png')
  report:write(name .. ': reopened; 47 slices at 64x64; 5 layers; pixels preserved; labels outside cells\n')
  report:flush()
  check:close()
end
report:close()
