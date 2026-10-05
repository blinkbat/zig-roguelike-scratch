local root='C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local work=root..'output/wall-mocks/'
local sprite=app.open('C:/Users/DavidBennett/Desktop/regular-walls-extrapolated.aseprite')
assert(sprite and sprite.width==512 and sprite.height==448)
local art=Image(512,448,ColorMode.RGB)
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Layer 1' or layer.name=='Draw here' or layer.name=='Extrapolated walls - your 7-color palette' then
    local cel=layer:cel(1)
    if cel then art:drawImage(cel.image,cel.position) end
  end
end
local rows={
  {'corner_tl',45,0,0,15,false},{'top',23,1,0,11,true},{'corner_tr',43,2,0,15,false},
  {'left',27,0,1,13,false},{'right',19,2,1,7,false},
  {'corner_bl',46,0,2,15,false},{'bottom',31,1,2,14,false},{'corner_br',39,2,2,15,false},
  {'block_tl',10,5,1,6,false},{'block_tr',15,6,1,12,false},
  {'block_bl',7,5,2,3,true},{'block_br',12,6,2,9,true},{'post',2,8,1,1,true},{'solid',47,9,1,15,false}
}
local pc=app.pixelColor
local base=pc.rgba(202,158,106,255)
local function opaque(pixel) return pc.rgbaA(pixel)>0 end
local function brick(pixel)
  local r,g,b=pc.rgbaR(pixel),pc.rgbaG(pixel),pc.rgbaB(pixel)
  return opaque(pixel) and ((r==149 and g==109 and b==100) or (r==215 and g==123 and b==103) or (r==119 and g==68 and b==57))
end
local function topInk(pixel)
  return opaque(pixel) and pc.rgbaG(pixel)>120 and pc.rgbaR(pixel)>180
end
local sheet=Image(640,256,ColorMode.RGB)
local report=assert(io.open(work..'game-wall-export.txt','w'))
for _,row in ipairs(rows) do
  local index=row[2]-1
  local raw=Image(art,Rectangle((index%8)*64,64+math.floor(index/8)*64,64,64))
  local minx,miny,maxx,maxy=64,64,-1,-1
  for y=0,63 do for x=0,63 do
    if opaque(raw:getPixel(x,y)) then minx=math.min(minx,x); miny=math.min(miny,y); maxx=math.max(maxx,x); maxy=math.max(maxy,y) end
  end end
  assert(maxx>=minx)
  local tile=Image(raw,Rectangle(minx,miny,maxx-minx+1,maxy-miny+1))
  if row[1]=='solid' then
    tile=Image(64,64,ColorMode.RGB)
    for y=0,63 do for x=0,63 do
      local sampled=raw:getPixel(12+x%36,5+y%19)
      tile:putPixel(x,y,topInk(sampled) and sampled or base)
    end end
  elseif row[6] then
    local faceFrom=tile.height
    for y=0,tile.height-1 do
      local red=0
      for x=0,tile.width-1 do if brick(tile:getPixel(x,y)) then red=red+1 end end
      if red>tile.width/4 then faceFrom=y; break end
    end
    assert(faceFrom>0 and faceFrom<tile.height)
    local cap=Image(tile,Rectangle(0,0,tile.width,faceFrom))
    local face=Image(tile,Rectangle(0,faceFrom,tile.width,tile.height-faceFrom))
    cap:resize(64,38)
    face:resize(64,26)
    tile=Image(64,64,ColorMode.RGB)
    tile:drawImage(cap,Point(0,0))
    tile:drawImage(face,Point(0,38))
  else
    for x=0,tile.width-1 do
      local faceFrom=tile.height
      for y=0,tile.height-1 do
        for nearby=math.max(0,x-2),math.min(tile.width-1,x+2) do
          if brick(tile:getPixel(nearby,y)) then faceFrom=y; break end
        end
        if faceFrom<tile.height then break end
      end
      if faceFrom<tile.height then
        local fill=base
        for y=math.max(0,faceFrom-3),0,-1 do
          local sample=tile:getPixel(x,y)
          if topInk(sample) then fill=sample; break end
        end
        for y=math.max(0,faceFrom-4),tile.height-1 do
          if opaque(tile:getPixel(x,y)) then tile:putPixel(x,y,fill) end
        end
      end
    end
    tile:resize(64,64)
  end
  local before=Image(tile)
  local neighbors=row[5]
  for y=0,63 do for x=0,63 do
    local sx,sy=x,y
    if (neighbors & 8)~=0 and x<8 then sx=8 end
    if (neighbors & 2)~=0 and x>55 then sx=55 end
    if (neighbors & 1)~=0 and y<8 then sy=8 end
    if (neighbors & 4)~=0 and y>55 then sy=55 end
    if sx~=x or sy~=y then
      local sample=before:getPixel(sx,sy)
      tile:putPixel(x,y,opaque(sample) and sample or base)
    elseif neighbors==15 and not opaque(before:getPixel(x,y)) then
      tile:putPixel(x,y,base)
    end
  end end
  sheet:drawImage(tile,Point(row[3]*64,row[4]*64))
  report:write(row[1]..' <- authored cell '..row[2]..' at '..row[3]..','..row[4]..'\n')
end
sheet:saveAs(root..'assets/walls.png')
report:close()
sprite:close()
