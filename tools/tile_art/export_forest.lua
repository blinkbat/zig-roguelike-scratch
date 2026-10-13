local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local path=app.params.source or root..'assets/source/forest-tree-walls.aseprite'
local work=app.fs.joinPath(app.fs.tempPath,'wall-mocks')..'/'
app.fs.makeAllDirectories(work)
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
local sprite=assert(app.open(path))
assert(sprite.width==512 and sprite.height==448 and #sprite.frames==1 and #sprite.slices==47)
local combined=Image(512,448,ColorMode.RGB)
local layers=0
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Draw here' or layer.name=='Forest extensions' then
    local cel=assert(layer:cel(1))
    assert(layer.opacity==255 and cel.opacity==255)
    combined:drawImage(cel.image,cel.position)
    layers=layers+1
  end
end
assert(layers==2,'Expected the original painting and its extensions')
local atlas=Image(combined,Rectangle(0,64,512,384))
local pixels=0
for i,mask in ipairs(masks) do
  local x,y=((i-1)%8)*64,math.floor((i-1)/8)*64
  local count=0
  for yy=0,63 do for xx=0,63 do
    local a=app.pixelColor.rgbaA(atlas:getPixel(x+xx,y+yy))
    assert(a==0 or a==255,'Partial alpha in mask '..mask)
    if a>0 then count=count+1 end
  end end
  assert(count>0,'Empty mask '..mask)
  pixels=pixels+count
end
for y=320,383 do for x=448,511 do assert(app.pixelColor.rgbaA(atlas:getPixel(x,y))==0,'Unused cell painted') end end
atlas:saveAs(root..'assets/forest-tree-walls.png')
sprite:close()
local check=Image{fromFile=root..'assets/forest-tree-walls.png'}
assert(check:isEqual(atlas),'Export changed the visible artwork')
local report=assert(io.open(work..'forest-tree-walls-export.txt','w'))
report:write(('47 cells exported, 64x64 each, %d opaque pixels; unused cell clear.\n'):format(pixels))
report:write('Only Draw here and Forest extensions; PNG pixels verified after reopening.\nSource: '..path..'\n')
report:close()
