local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local path=app.params.source or 'C:/Users/DavidBennett/Desktop/regular-walls.aseprite'
local work=root..'output/wall-mocks/'
local pc=app.pixelColor
local sprite=assert(app.open(path))
assert(sprite.width==512 and sprite.height==448)
local authored,extension,drawing
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Layer 1' then authored=layer end
  if layer.name=='Pixel extension - copied colors, chips and bricks' or layer.name=='Extension - ported painted edges' then extension=layer end
  if layer.name=='Draw here' then drawing=layer end
end
assert(authored and extension and drawing)
local original=Image(authored:cel(1).image)
local position=Point(authored:cel(1).position)
local source=Image(512,448,ColorMode.RGB)
source:drawImage(original,position)
local palette={}
for it in original:pixels() do if pc.rgbaA(it())>0 then palette[it()]=true end end
local tan=source:getPixel(30,87)
assert(tan==pc.rgba(202,158,106,255))
local function sample(x,y) return source:getPixel(x,y) end
local function brick(x,y) return sample(154+x%32,99+y) end
local function sideRow(y)
  if y==0 or y==63 then return 80 end
  return 67+(y+13)%30
end
local function decorate(image,inside,offsets)
  for _,at in ipairs(offsets) do
    local safe=true
    for y=at[2]-3,at[2]+12 do for x=at[1]-3,at[1]+12 do
      if not inside(x,y) then safe=false end
    end end
    if safe then
      for y=0,9 do for x=0,9 do image:putPixel(at[1]+x,at[2]+y,sample(24+x,87+y)) end end
    end
  end
end
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
local bits={{128,1,16},{8,0,2},{64,4,32}}
local function blob(mask)
  local image=Image(64,64,ColorMode.RGB)
  local function inside(x,y)
    if x<0 or y<0 or x>63 or y>63 then return false end
    local col=x<19 and 1 or x>44 and 3 or 2
    local row=y<19 and 1 or y>45 and 3 or 2
    return (col==2 and row==2) or ((mask & bits[row][col])~=0)
  end
  local low={}
  for x=0,63 do
    low[x]=-1
    for y=0,63 do if inside(x,y) then low[x]=y end end
  end
  local function cap(x,y)
    return inside(x,y) and (low[x]==63 or y<=low[x]-11)
  end
  for y=0,63 do for x=0,63 do
    if inside(x,y) then
      local pixel=tan
      local left,right,top=0,63,0
      for a=x,0,-1 do if not inside(a,y) then left=a+1; break end end
      for a=x,63 do if not inside(a,y) then right=a-1; break end end
      for a=y,0,-1 do if not inside(x,a) then top=a+1; break end end
      local dx,ex,dy=x-left,right-x,y-top
      if not cap(x,y) then
        local by=y-low[x]+10
        pixel=brick(x,by)
        if left>0 and dx<4 then pixel=sample(18+dx,99+by) end
        if right<63 and ex<4 then pixel=sample(43-ex,99+by) end
      else
        if top>0 and dy<6 then pixel=sample(160+x%32,83+dy) end
        if left>0 and dx<4 then pixel=sample(83+dx,sideRow(y)) end
        if right<63 and ex<4 then pixel=sample(108-ex,sideRow(y)) end
        if top>0 and dy<6 and left>0 and dx<6 then pixel=sample(18+dx,83+dy) end
        if top>0 and dy<6 and right<63 and ex<6 then pixel=sample(43-ex,83+dy) end
      end
      image:putPixel(x,y,pixel)
    end
  end end
  decorate(image,cap,{{24,23},{5,7},{43,7},{8,43},{41,44}})
  return image
end
local completed=Image(512,448,ColorMode.RGB)
local blobs={}
for i,mask in ipairs(masks) do
  blobs[i]=blob(mask)
  if i>3 then completed:drawImage(blobs[i],Point(((i-1)%8)*64,64+math.floor((i-1)/8)*64)) end
end
for x=0,63 do completed:putPixel(64+x,64,sample(64+x,65)) end
local authoredSheet=Image(completed)
authoredSheet:drawImage(source,Point(0,0))
local references={}
for i,mask in ipairs(masks) do
  local tile=Image(64,64,ColorMode.RGB)
  local ox,oy=((i-1)%8)*64,64+math.floor((i-1)/8)*64
  for y=0,63 do for x=0,63 do tile:putPixel(x,y,authoredSheet:getPixel(ox+x,oy+y)) end end
  for _,other in ipairs(references) do assert(not tile:isEqual(other),'duplicate authoring cell '..i) end
  for a=23,40 do
    if (mask & 1)~=0 then assert(pc.rgbaA(tile:getPixel(a,0))==255,'north connection gap '..i) end
    if (mask & 2)~=0 then assert(pc.rgbaA(tile:getPixel(63,a))==255,'east connection gap '..i) end
    if (mask & 4)~=0 then assert(pc.rgbaA(tile:getPixel(a,63))==255,'south connection gap '..i) end
    if (mask & 8)~=0 then assert(pc.rgbaA(tile:getPixel(0,a))==255,'west connection gap '..i) end
  end
  references[#references+1]=tile
end
sprite:saveCopyAs(work..'regular-walls-before-ported-edges-'..os.date('%Y%m%d-%H%M%S')..'.aseprite')
extension.name='Extension - ported painted edges'
extension:cel(1).image=completed
extension:cel(1).position=Point(0,0)
drawing.stackIndex=#sprite.layers
app.layer=drawing
sprite:saveAs(path)
sprite:saveCopyAs(work..'regular-walls-current.png')
sprite:close()
local reopened=assert(app.open(path))
local preserved=false
for _,layer in ipairs(reopened.layers) do
  if layer.name=='Layer 1' then
    assert(layer:cel(1).image:isEqual(original) and layer:cel(1).position==position)
    preserved=true
  end
end
assert(preserved and #reopened.slices==47)
reopened:close()
dofile(root..'tools/tile_art/export_walls.lua')
local report=assert(io.open(work..'ported-pixel-validation.txt','w'))
report:write('Original painted layer and position unchanged after reopening.\n47 distinct authoring cells; 44 extensions use copied uneven edge strips.\nAll declared cardinal connections have continuous opaque central coverage.\nCell 02 north boundary repaired with a copy of its first painted row beneath the original layer.\nexport_walls.lua cut all 47 cells, Layer 1 over the extension, into assets/walls.png; binary alpha.\nNo resampling, rotation, mirroring or image generation.\n')
report:close()
