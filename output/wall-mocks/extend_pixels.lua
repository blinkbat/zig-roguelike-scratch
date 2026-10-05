local root='C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local work=root..'output/wall-mocks/'
local desktop='C:/Users/DavidBennett/Desktop/'
local sprite=app.open(desktop..'regular-walls.aseprite')
assert(sprite and sprite.width==512 and sprite.height==448)
local authored
for _,layer in ipairs(sprite.layers) do if layer.name=='Layer 1' then authored=layer end end
assert(authored)
local original=Image(authored:cel(1).image)
local originalPosition=Point(authored:cel(1).position)
local source=Image(512,448,ColorMode.RGB)
source:drawImage(original,originalPosition)
local pc=app.pixelColor
local TAN=pc.rgba(202,158,106,255)
local DARK=pc.rgba(84,15,0,255)
local LIGHT=pc.rgba(233,224,150,255)
local CHIP=pc.rgba(145,103,54,255)
local palette={}
for it in original:pixels() do if pc.rgbaA(it())>0 then palette[it()]=true end end
assert(palette[TAN] and palette[DARK] and palette[LIGHT] and palette[CHIP])
local motif={}
for y=87,96 do for x=24,33 do
  local pixel=source:getPixel(x,y)
  if pixel==LIGHT or pixel==CHIP then motif[#motif+1]={x-24,y-87,pixel} end
end end
assert(#motif>0)
local function bricks(x,y)
  local pixel=source:getPixel(154+x%32,99+y)
  assert(pc.rgbaA(pixel)==255 and palette[pixel])
  return pixel
end
local function chips(image,inside,offsets)
  for _,offset in ipairs(offsets) do
    for _,point in ipairs(motif) do
      local x,y=offset[1]+point[1],offset[2]+point[2]
      if x>=0 and y>=0 and x<64 and y<64 and inside(x,y) then image:putPixel(x,y,point[3]) end
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
  for y=0,63 do for x=0,63 do
    if inside(x,y) then
      local bottom=low[x]
      local pixel=TAN
      if bottom<63 and y>bottom-11 then pixel=bricks(x,y-bottom+10) end
      if x>0 and not inside(x-1,y) then pixel=DARK
      elseif x>1 and not inside(x-2,y) and pixel==TAN then pixel=LIGHT end
      if x<63 and not inside(x+1,y) then pixel=DARK end
      if y>0 and not inside(x,y-1) then pixel=DARK
      elseif y>1 and not inside(x,y-2) and pixel==TAN then pixel=LIGHT end
      image:putPixel(x,y,pixel)
    end
  end end
  chips(image,function(x,y) return inside(x,y) and x>3 and x<60 and y>3 and y<low[x]-14 and image:getPixel(x,y)==TAN end,{{24,23},{5,7},{43,7},{8,43},{41,44}})
  return image
end
local completed=Image(512,448,ColorMode.RGB)
for i=4,47 do completed:drawImage(blob(masks[i]),Point(((i-1)%8)*64,64+math.floor((i-1)/8)*64)) end
local extended=sprite:newLayer()
extended.name='Pixel extension - copied colors, chips and bricks'
sprite:newCel(extended,1,completed,Point(0,0))
extended.stackIndex=4
local drawing
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Underdrawing (25%)' or layer.name=='Exact connection guide (hidden)' then layer.isVisible=false end
  if layer.name=='Draw here' then drawing=layer end
end
drawing.stackIndex=#sprite.layers
app.layer=drawing
sprite.data='Native pixel extension from the user Layer 1 only. No image generation, scaling, smoothing or palette conversion. Original first three cells preserved. Brick runs and chip motifs copied at 1:1. Cell IDs and slices retain the original 47-pattern import map. Runtime wall variants are adapted at native pixel size in assets/walls.png.'
local destination=desktop..'regular-walls-pixel.aseprite'
assert(not app.fs.isFile(destination))
sprite:saveAs(destination)
sprite:saveCopyAs(work..'regular-walls-pixel-preview.png')
assert(authored:cel(1).image:isEqual(original) and authored:cel(1).position==originalPosition)
local rows={
 {'corner_tl',0,0,0,false,3},{'top',1,0,4,true},{'corner_tr',2,0,0,false,2},
 {'left',0,1,2,false},{'right',2,1,8,false},
 {'corner_bl',0,2,0,false,1},{'bottom',1,2,1,false},{'corner_br',2,2,0,false,0},
 {'block_tl',5,1,9,false},{'block_tr',6,1,3,false},
 {'block_bl',5,2,12,true},{'block_br',6,2,6,true},{'post',8,1,14,true},{'solid',9,1,0,false}
}
local gameSheet=Image(640,256,ColorMode.RGB)
local tiles={}
for _,row in ipairs(rows) do
  local image=Image(64,64,ColorMode.RGB)
  image:clear(TAN)
  local open=row[4]
  if row[5] then
    for y=53,63 do for x=0,63 do image:putPixel(x,y,bricks(x,y-53)) end end
  end
  chips(image,function(x,y) return x>4 and x<59 and y>4 and y<(row[5] and 49 or 59) end,{{10,11},{40,31},{17,43}})
  for i=0,63 do
    if (open & 1)~=0 then image:putPixel(i,0,DARK); image:putPixel(i,1,LIGHT) end
    if (open & 8)~=0 then image:putPixel(0,i,DARK); if not row[5] or i<53 then image:putPixel(1,i,LIGHT) end end
    if (open & 2)~=0 then image:putPixel(63,i,DARK) end
  end
  if row[6] then
    local corner=row[6]
    local x=(corner%2==1) and 63 or 0
    local y=corner>=2 and 63 or 0
    image:putPixel(x,y,DARK)
  end
  for it in image:pixels() do assert(pc.rgbaA(it())==255 and palette[it()]) end
  gameSheet:drawImage(image,Point(row[2]*64,row[3]*64))
  tiles[row[1]]=image
end
for y=0,63 do
  assert(tiles.top:getPixel(0,y)==tiles.top:getPixel(32,y))
  assert(tiles.top:getPixel(31,y)==tiles.top:getPixel(63,y))
end
for x=0,63 do
  assert(tiles.left:getPixel(x,0)==tiles.left:getPixel(x,63))
  assert(tiles.right:getPixel(x,0)==tiles.right:getPixel(x,63))
end
gameSheet:saveAs(work..'walls-native-candidate.png')
local report=assert(io.open(work..'native-pixel-validation.txt','w'))
report:write(destination..'\nOriginal painted layer unchanged. 44 native-pixel connection extensions. 14 fully opaque 64x64 runtime wall pieces, using only the seven user colors. Brick strips are copied 1:1, 11px high. Horizontal brick repetition and vertical side joins verified.\n')
report:close()
sprite:close()
