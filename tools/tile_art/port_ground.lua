local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local name=app.params.name or 'grass'
local material=assert(({grass={pixels=9375,ne=true,west_y=98},dirt={pixels=8314,ne=false,west_y=101}})[name],'name=grass|dirt')
local title=name:gsub('^%l',string.upper)
local path=app.params.source or ('C:/Users/DavidBennett/Desktop/'..name..'.aseprite')
local art_path=app.params.art or path
local work=(app.params.work or app.fs.joinPath(app.fs.tempPath,'wall-mocks'))..'/'
app.fs.makeAllDirectories(work)
local order=dofile(root..'tools/tile_art/ground_corners.lua')
local pc=app.pixelColor
local s=assert(app.open(path))
assert(s.width==512 and s.height==320 and #s.frames==1 and #s.slices==16)
local drawing
for _,l in ipairs(s.layers) do
  assert(l.name~=title..' extensions','Inspect owner edits before regenerating '..title..' extensions')
  if l.name=='Draw here' then drawing=l end
end
local c=assert(drawing:cel(1))
if art_path~=path then
  for it in c.image:pixels() do assert(pc.rgbaA(it())==0,'Destination already painted; inspect before importing') end
  local art=assert(app.open(art_path))
  assert(art.width==512 and art.height==320 and #art.frames==1)
  local source
  for _,l in ipairs(art.layers) do if l.name=='Draw here' then source=l:cel(1) end end
  assert(source,'No Draw here on art source')
  c.image=Image(source.image)
  c.position=Point(source.position.x,source.position.y)
  art:close()
end
local original=Image(c.image)
local position=Point(c.position.x,c.position.y)
local painted=Image(512,320,ColorMode.RGB)
painted:drawImage(original,position)
local palette={}
local painted_count=0
for it in painted:pixels() do
  if pc.rgbaA(it())>0 then
    assert(pc.rgbaA(it())==255,'Partial alpha in source')
    palette[it()]=true
    painted_count=painted_count+1
  end
end
assert(painted_count==material.pixels,'Source painting changed; inspect the crops before porting')
local function pixel(x,y)
  if x<0 or y<0 or x>=512 or y>=320 then return 0 end
  return painted:getPixel(x,y)
end
local function opaque(v) return pc.rgbaA(v)>0 end
local fill=Image(painted,Rectangle(64,128,64,64))
for it in fill:pixels() do assert(pc.rgbaA(it())==255,'Fill cell is incomplete') end
local function texture(x,y) return fill:getPixel(x%64,y%64) end
local function north(x,y)
  if y<16 then return 0 end
  if y>44 then return texture(x,y) end
  return pixel(64+x,64+y)
end
local function south(x,y)
  if y>40 then return 0 end
  if y<22 then return texture(x,y) end
  local sx=x%24
  return pixel(sx,64+y)
end
local function east(x,y)
  if x>40 then return 0 end
  if x<20 then return texture(x,y) end
  return pixel(x,64+y%24)
end
local function west(x,y)
  if x<24 then return 0 end
  if x>46 then return texture(x,y) end
  return pixel(x,material.west_y+y%24)
end
local function component(x,y,w,h,seedx,seedy)
  local out=Image(64,64,ColorMode.RGB)
  local todo={{seedx,seedy}}
  local seen={}
  while #todo>0 do
    local at=table.remove(todo)
    local xx,yy=at[1],at[2]
    local key=yy*64+xx
    if xx>=x and xx<x+w and yy>=y and yy<y+h and not seen[key] then
      seen[key]=true
      if opaque(pixel(xx,64+yy)) then
        out:putPixel(xx,yy,pixel(xx,64+yy))
        for _,d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do todo[#todo+1]={xx+d[1],yy+d[2]} end
      end
    end
  end
  return out
end
local outer_nw=component(0,0,40,40,2,2)
local outer_se=component(24,20,40,44,60,60)
local outer_ne=Image(painted,Rectangle(0,192,64,64))
local corners={
  {bit=1,h=2,v=4,x=0,y=0,outer=outer_nw},
  {bit=2,h=1,v=8,x=32,y=0,outer=material.ne and outer_ne or nil},
  {bit=4,h=8,v=1,x=0,y=32},
  {bit=8,h=4,v=2,x=32,y=32,outer=outer_se},
}
local cells={}
local extension=Image(512,320,ColorMode.RGB)
local atlas=Image(256,256,ColorMode.RGB)
for i,m in ipairs(order) do
  local tile=Image(64,64,ColorMode.RGB)
  if m==9 or m==12 or m==15 then
    tile=Image(painted,Rectangle(((i-1)%4)*64,64+((i-1)//4)*64,64,64))
  else
    for _,q in ipairs(corners) do
      if (m&q.bit)~=0 then
        local h=(m&q.h)~=0
        local v=(m&q.v)~=0
        if not h and not v and q.outer then
          tile:drawImage(q.outer,Point(0,0))
        else
          for y=0,63 do for x=0,63 do
            local inx=x>=q.x and x<q.x+32
            local iny=y>=q.y and y<q.y+32
            local a=h and texture(x,y) or (q.x==0 and east(x,y) or west(x,y))
            local b=v and texture(x,y) or (q.y==0 and south(x,y) or north(x,y))
            if (not h or inx) and (not v or iny) and opaque(a) and opaque(b) then
              local value=texture(x,y)
              local dx=math.abs(x-32)
              local dy=math.abs(y-32)
              if not h and dx<12 and (v or dx<=dy) then value=a
              elseif not v and dy<16 then value=b end
              tile:putPixel(x,y,value)
            end
          end end
        end
      end
    end
    if m==6 and material.ne then
      for y=0,39 do for x=24,63 do
        tile:putPixel(x,y,outer_ne:getPixel(x,y))
      end end
    end
  end
  local ox,oy=((i-1)%4)*64,64+((i-1)//4)*64
  for y=0,63 do for x=0,63 do
    local p=pixel(ox+x,oy+y)
    if opaque(p) then tile:putPixel(x,y,p) end
  end end
  for it in tile:pixels() do assert(not opaque(it()) or palette[it()],'New colour') end
  cells[m]=tile
  atlas:drawImage(tile,Point(ox,oy-64))
  if m~=9 and m~=12 and m~=15 then
    for y=0,63 do for x=0,63 do
      if not opaque(pixel(ox+x,oy+y)) then extension:putPixel(ox+x,oy+y,tile:getPixel(x,y)) end
    end end
  end
end
local function bit(m,b) return (m&b)~=0 end
for i,m in ipairs(order) do
  local sl
  for _,slice in ipairs(s.slices) do if slice.name=='Corners '..m then sl=slice end end
  assert(sl and sl.bounds.x==((i-1)%4)*64 and sl.bounds.y==64+((i-1)//4)*64
    and sl.bounds.width==64 and sl.bounds.height==64,'Slice moved: '..m)
  for _,q in ipairs(corners) do
    local cx,cy=q.x==0 and 8 or 48,q.y==0 and 8 or 48
    for y=cy,cy+7 do for x=cx,cx+7 do
      assert(opaque(cells[m]:getPixel(x,y))==bit(m,q.bit),'Wrong quarter in mask '..m)
    end end
  end
  for it in cells[m]:pixels() do
    assert(pc.rgbaA(it())==0 or pc.rgbaA(it())==255,'Partial alpha')
    if m==0 then assert(not opaque(it()),'Unused cell painted') end
    if m==15 then assert(opaque(it()),'Fill has a hole') end
  end
end
local joins=0
for a=0,15 do for b=0,15 do
  if bit(a,2)==bit(b,1) and bit(a,8)==bit(b,4) then
    for _,span in ipairs({{8,23,2},{40,55,8}}) do
      for y=span[1],span[2] do
        assert(opaque(cells[a]:getPixel(63,y))==bit(a,span[3]),'East gap')
        assert(opaque(cells[b]:getPixel(0,y))==bit(a,span[3]),'West gap')
      end
    end
    joins=joins+1
  end
  if bit(a,4)==bit(b,1) and bit(a,8)==bit(b,2) then
    for _,span in ipairs({{8,23,4},{40,55,8}}) do
      for x=span[1],span[2] do
        assert(opaque(cells[a]:getPixel(x,63))==bit(a,span[3]),'South gap')
        assert(opaque(cells[b]:getPixel(x,0))==bit(a,span[3]),'North gap in '..b..' at '..x)
      end
    end
    joins=joins+1
  end
end end
assert(joins==128)
local stamp=os.date('%Y%m%d-%H%M%S')
local backup=work..name..'-before-'..stamp..'.aseprite'
local function copy(from,to)
  local input=assert(io.open(from,'rb'))
  local bytes=input:read('*a')
  input:close()
  local output=assert(io.open(to,'wb'))
  output:write(bytes)
  output:close()
end
copy(path,backup)
if art_path~=path then copy(art_path,work..name..'-painting-before-'..stamp..'.aseprite') end
local l=s:newLayer()
l.name=title..' extensions'
s:newCel(l,1,extension,Point(0,0))
for _,layer in ipairs(s.layers) do if layer.name=='Underdrawing (25%)' then layer.isVisible=false end end
drawing.stackIndex=#s.layers
app.layer=l
local dest=app.params.install=='yes' and path or work..name..'-draft.aseprite'
s:saveAs(dest)
if app.params.install=='yes' then s:saveCopyAs(root..'assets/source/'..name..'.aseprite') end
s:saveCopyAs(work..name..'-sheet.png')
s:close()
local back=assert(app.open(dest))
for _,layer in ipairs(back.layers) do
  if layer.name=='Draw here' then
    local cel=assert(layer:cel(1))
    assert(cel.image:isEqual(original) and cel.position.x==position.x and cel.position.y==position.y,'Original altered')
  end
  if layer.name==title..' extensions' then
    local cel=assert(layer:cel(1))
    local img=Image(512,320,ColorMode.RGB)
    img:drawImage(cel.image,cel.position)
    assert(img:isEqual(extension),'Extension changed')
  end
end
back:close()
atlas:saveAs(work..name..'-atlas.png')
local zoom=Image(atlas)
zoom:resize(768,768)
zoom:saveAs(work..name..'-atlas-3x.png')
local map={
  '..................',
  '..#######.........',
  '..#######..#......',
  '..##..###..#......',
  '..##..###..####...',
  '..#######....#....',
  '.............#....',
  '..###..#..#..#....',
  '..#.#...##........',
  '..###...##..####..',
  '............####..',
  '..................',
}
local function grass(x,y)
  return y>=1 and y<=#map and x>=1 and x<=#map[y] and map[y]:sub(x,x)=='#'
end
local preview=Image(#map[1]*64,#map*64,ColorMode.RGB)
preview:clear(pc.rgba(146,122,93,255))
for y=1,#map+1 do for x=1,#map[1]+1 do
  local m=(grass(x-1,y-1) and 1 or 0)|(grass(x,y-1) and 2 or 0)|(grass(x-1,y) and 4 or 0)|(grass(x,y) and 8 or 0)
  preview:drawImage(cells[m],Point((x-1)*64-32,(y-1)*64-32))
end end
preview:saveAs(work..name..'-connected.png')
local report=assert(io.open(work..name..'-validation.txt','w'))
report:write('Source: '..path..'\nPainting: '..art_path..'\nSaved: '..dest..'\nBackup: '..backup..'\nOriginal image and position verified after reopening. Source palette retained.\n')
report:write('15 painted 64x64 cells; mask 0 empty; mask 15 fully opaque. All 128 legal adjacent pairs checked at their quarter cores.\n')
report:write('Finished source cells 9, 12, 15 retained. Original '..painted_count..' pixels and cel position untouched.\n')
report:write('Fill: (64,128,64,64). NW/SE corners: isolated components of cell 9.\n')
report:write(material.ne and 'NE corner: (0,192,64,64).\n' or 'NE corner intersects the west/south strips.\n')
report:write('North: cell 12 rows 16..44. South: source x 0..23, y 86..104. East: x 20..40, y 64..87. West: x 24..46, y '..material.west_y..'..'..(material.west_y+23)..'.\n')
report:write('Strips repeat at native scale; the missing SW corner intersects the north/east strips. No rotation, mirroring, recolouring, smoothing or scaling.\n')
report:write('Preview: '..name..'-connected.png. Art: '..name..'-atlas.png. Guides excluded; only the art layers export.\n')
report:close()
