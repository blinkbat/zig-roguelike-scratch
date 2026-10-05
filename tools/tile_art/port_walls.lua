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
local masks={0,1,2,4,8,3,19,5,6,38,9,137,10,12,76,7,23,39,55,11,27,139,155,13,77,141,205,14,46,78,110,15,31,47,63,79,95,111,127,143,159,175,191,207,223,239,255}
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
local rows={
 {'corner_tl',0,0,0,false,3},{'top',1,0,4,true},{'corner_tr',2,0,0,false,2},
 {'left',0,1,2,false},{'right',2,1,8,false},
 {'corner_bl',0,2,0,false,1},{'bottom',1,2,1,false},{'corner_br',2,2,0,false,0},
 {'block_tl',5,1,9,false},{'block_tr',6,1,3,false},
 {'block_bl',5,2,12,true},{'block_br',6,2,6,true},{'post',8,1,14,true},{'solid',9,1,0,false}
}
local atlas=Image(640,256,ColorMode.RGB)
local tiles={}
for _,row in ipairs(rows) do
  local image=Image(64,64,ColorMode.RGB)
  local open,face=row[4],row[5]
  for y=0,63 do for x=0,63 do
    local pixel=tan
    if face and y>=53 then
      pixel=brick(x,y-53)
      if (open & 8)~=0 and x<4 then pixel=sample(18+x,99+y-53) end
      if (open & 2)~=0 and x>=60 then pixel=sample(40+x-60,99+y-53) end
    else
      if (open & 1)~=0 and y<6 then pixel=sample(160+x%32,83+y) end
      if (open & 8)~=0 and x<4 then pixel=sample(83+x,sideRow(y)) end
      if (open & 2)~=0 and x>=60 then pixel=sample(105+x-60,sideRow(y)) end
      if (open & 1)~=0 and y<6 and (open & 8)~=0 and x<6 then pixel=sample(18+x,83+y) end
      if (open & 1)~=0 and y<6 and (open & 2)~=0 and x>=58 then pixel=sample(38+x-58,83+y) end
    end
    image:putPixel(x,y,pixel)
  end end
  decorate(image,function(x,y) return x>5 and x<58 and y>5 and y<(face and 50 or 58) end,{{10,11},{40,31},{17,43}})
  if row[6] then
    local corner=row[6]
    local east=corner%2==1
    local south=corner>=2
    local sx=east and 105 or 83
    local dx=east and 60 or 0
    local dy=south and 62 or 0
    for y=0,1 do for x=0,3 do
      local pixel=sample(sx+x,80+y)
      if pc.rgbaA(pixel)>0 then image:putPixel(dx+x,dy+y,pixel) end
    end end
  end
  for it in image:pixels() do
    assert(pc.rgbaA(it())==0 or (pc.rgbaA(it())==255 and palette[it()]),'palette or alpha changed')
  end
  for y=6,52 do for x=6,57 do assert(pc.rgbaA(image:getPixel(x,y))==255,'interior hole') end end
  atlas:drawImage(image,Point(row[2]*64,row[3]*64))
  tiles[row[1]]=image
end
for y=0,63 do
  assert(pc.rgbaA(tiles.top:getPixel(0,y))==255 and pc.rgbaA(tiles.top:getPixel(63,y))==255)
  assert(tiles.top:getPixel(0,y)==tiles.top:getPixel(32,y))
  assert(tiles.top:getPixel(31,y)==tiles.top:getPixel(63,y))
end
for x=0,63 do
  assert(tiles.left:getPixel(x,0)==tiles.left:getPixel(x,63))
  assert(tiles.right:getPixel(x,0)==tiles.right:getPixel(x,63))
end
for x=6,57 do assert(pc.rgbaA(tiles.solid:getPixel(x,0))==255) end
atlas:saveAs(work..'walls-ported-candidate.png')
local preview=Image(320,320,ColorMode.RGB)
local scene={
 {'corner_tl','top','top','top','corner_tr'},
 {'left',false,false,false,'right'},
 {'left',false,'post',false,'right'},
 {'left',false,false,false,'right'},
 {'corner_bl','bottom','bottom','bottom','corner_br'}
}
for y,line in ipairs(scene) do for x,name in ipairs(line) do
  if name then preview:drawImage(tiles[name],Point((x-1)*64,(y-1)*64)) end
end end
preview:saveAs(work..'walls-ported-room.png')
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
local runtime=Sprite(640,256,ColorMode.RGB)
runtime.layers[1].name='Runtime walls - copied native pixels'
runtime:newCel(runtime.layers[1],1,atlas,Point(0,0))
runtime.data='Derived from Desktop regular-walls.aseprite Layer 1 by tools/tile_art/port_walls.lua. Native copied strips; no resizing. Export this art layer to assets/walls.png. See docs/TILE_ART_WORKFLOW.md.'
for _,row in ipairs(rows) do
  local slice=runtime:newSlice(Rectangle(row[2]*64,row[3]*64,64,64))
  slice.name=row[1]
end
runtime:saveAs(root..'assets/source/walls.aseprite')
runtime:close()
local check=assert(app.open(root..'assets/source/walls.aseprite'))
local exported=Image(640,256,ColorMode.RGB)
exported:drawImage(check.layers[1]:cel(1).image,check.layers[1]:cel(1).position)
assert(exported:isEqual(atlas))
exported:saveAs(root..'assets/walls.png')
check:close()
local report=assert(io.open(work..'ported-pixel-validation.txt','w'))
report:write('Original painted layer and position unchanged after reopening.\n47 distinct authoring cells; 44 extensions use copied uneven edge strips.\nAll declared cardinal connections have continuous opaque central coverage.\nCell 02 north boundary repaired with a copy of its first painted row beneath the original layer.\n14 runtime shapes; seven source colours; binary alpha; opaque interiors.\nHorizontal brick phase and vertical edge endpoints checked.\nRuntime Aseprite reopened; exported pixels equal the constructed atlas.\nNo resampling, rotation, mirroring or image generation.\n')
report:close()
