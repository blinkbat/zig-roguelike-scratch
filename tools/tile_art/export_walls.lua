local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local path=app.params.source or 'C:/Users/DavidBennett/Desktop/regular-walls.aseprite'
local pc=app.pixelColor
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
assert(#masks==47)
-- Brick courses under the cap's lower edge: 7 courses, 23 rows; src/gfx/look.zig's WALL_FACE_PX.
local FACE=23
local sprite=assert(app.open(path))
assert(sprite.width==512 and sprite.height==448)
local painted
for _,layer in ipairs(sprite.layers) do if layer.name=='Layer 1' then painted=layer end end
local source=Image(512,448,ColorMode.RGB)
source:drawImage(assert(painted,'no Layer 1'):cel(1).image,painted:cel(1).position)
sprite:close()
local palette={}
for it in source:pixels() do if pc.rgbaA(it())>0 then palette[it()]=true end end
local tan=source:getPixel(30,87)
assert(tan==pc.rgba(202,158,106,255))
local dark=pc.rgba(84,15,0,255)
assert(palette[dark])
local function sample(x,y) return source:getPixel(x,y) end
-- Face row by -> painted row: the cap's edge, the top mortar, courses alternating A (101) and B (104), the last C (107) with the foot.
local faceRows={99,100}
for k=1,6 do local s=(k%2==1) and 101 or 104; faceRows[#faceRows+1]=s; faceRows[#faceRows+1]=s+1; faceRows[#faceRows+1]=s+2 end
for _,r in ipairs({107,108,109}) do faceRows[#faceRows+1]=r end
assert(#faceRows==FACE)
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
local function tile(mask)
  local n,e,s,w=(mask&1)~=0,(mask&2)~=0,(mask&4)~=0,(mask&8)~=0
  local ne,se,sw,nw=(mask&16)~=0,(mask&32)~=0,(mask&64)~=0,(mask&128)~=0
  local image=Image(64,64,ColorMode.RGB)
  local foot=s and 64 or 64-FACE
  for y=0,63 do for x=0,63 do
    local pixel=tan
    if y>=foot then
      local row=faceRows[y-foot+1]
      pixel=sample(154+x%32,row)
      if not w and x<4 then pixel=sample(18+x,row) end
      if not e and x>=60 then pixel=sample(40+x-60,row) end
    else
      if not n and y<6 then pixel=sample(160+x%32,83+y) end
      if not w and x<4 then pixel=sample(83+x,sideRow(y)) end
      if not e and x>=60 then pixel=sample(105+x-60,sideRow(y)) end
      if not n and y<6 and not w and x<6 then pixel=sample(18+x,83+y) end
      if not n and y<6 and not e and x>=58 then pixel=sample(38+x-58,83+y) end
      -- Hand repair: the face beside a missing south corner meets this cap along an unbroken outline.
      if s and w and not sw and x==0 and y>=64-FACE-1 then pixel=dark end
      if s and e and not se and x==63 and y>=64-FACE-1 then pixel=dark end
    end
    image:putPixel(x,y,pixel)
  end end
  decorate(image,function(x,y) return x>5 and x<58 and y>5 and y<foot-6 end,{{10,11},{40,13},{17,30},{44,36}})
  local function notch(east,south)
    local sx,dx,dy=east and 105 or 83,east and 60 or 0,south and 62 or 0
    for y=0,1 do for x=0,3 do
      local pixel=sample(sx+x,80+y)
      if pc.rgbaA(pixel)>0 then image:putPixel(dx+x,dy+y,pixel) end
    end end
  end
  if n and w and not nw then notch(false,false) end
  if n and e and not ne then notch(true,false) end
  for it in image:pixels() do
    assert(pc.rgbaA(it())==0 or (pc.rgbaA(it())==255 and palette[it()]),'palette or alpha changed '..mask)
  end
  return image
end
local atlas=Image(512,384,ColorMode.RGB)
local cells={}
for i,mask in ipairs(masks) do
  local image=tile(mask)
  for a=8,55 do
    if (mask&1)~=0 then assert(pc.rgbaA(image:getPixel(a,0))==255,'north gap '..mask) end
    if (mask&2)~=0 then assert(pc.rgbaA(image:getPixel(63,a))==255,'east gap '..mask) end
    if (mask&4)~=0 then assert(pc.rgbaA(image:getPixel(a,63))==255,'south gap '..mask) end
    if (mask&8)~=0 then assert(pc.rgbaA(image:getPixel(0,a))==255,'west gap '..mask) end
  end
  for _,other in ipairs(cells) do assert(not image:isEqual(other),'duplicate cell '..mask) end
  cells[#cells+1]=image
  atlas:drawImage(image,Point(((i-1)%8)*64,math.floor((i-1)/8)*64))
end
local runtime=Sprite(512,384,ColorMode.RGB)
runtime.layers[1].name='Runtime walls'
runtime:newCel(runtime.layers[1],1,atlas,Point(0,0))
runtime.data='Full-cell walls built from Desktop regular-walls.aseprite Layer 1 strips by tools/tile_art/export_walls.lua; cell i is mask i of wall_masks.lua.'
for i,mask in ipairs(masks) do
  local slice=runtime:newSlice(Rectangle(((i-1)%8)*64,math.floor((i-1)/8)*64,64,64))
  slice.name='mask '..mask
end
runtime:saveAs(root..'assets/source/walls.aseprite')
runtime:close()
local check=assert(app.open(root..'assets/source/walls.aseprite'))
local exported=Image(512,384,ColorMode.RGB)
exported:drawImage(check.layers[1]:cel(1).image,check.layers[1]:cel(1).position)
check:close()
assert(exported:isEqual(atlas))
exported:saveAs(root..'assets/walls.png')
