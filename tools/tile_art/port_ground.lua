local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local name=app.params.name or 'grass'
local material=assert(({
  grass={pixels=9375,ne=true,west_y=98},
  dirt={pixels=8314,ne=false,west_y=101},
  water={pixels=15304,ne=true,west_y=128,west_h=64,complete={[4]=true,[6]=true,[10]=true,[11]=true}},
})[name],'name=grass|dirt|water')
local title=name:gsub('^%l',string.upper)
local path=app.params.source or (sourceFiles.DESKTOP..name..'.aseprite')
local canonical=root..'assets/source/'..name..'.aseprite'
local install=app.params.install=='yes'
sourceFiles.preserve(path,canonical,install)
local art_path=app.params.art or path
local work=sourceFiles.work(app.params.work)
local order=dofile(root..'tools/tile_art/ground_corners.lua')
local groundPort=dofile(root..'tools/tile_art/ground_port.lua')
local pc=app.pixelColor
local W,H=groundPort.W,groundPort.H
local s=assert(app.open(path))
assert(s.width==W and s.height==H and #s.frames==1 and #s.slices==#order)
assert(not sourceFiles.layer(s,title..' extensions'),'Inspect owner edits before regenerating '..title..' extensions')
local drawing=sourceFiles.layer(s,'Draw here')
local c=assert(drawing:cel(1))
if art_path~=path then
  for it in c.image:pixels() do assert(pc.rgbaA(it())==0,'Destination already painted; inspect before importing') end
  local art=assert(app.open(art_path))
  assert(art.width==W and art.height==H and #art.frames==1)
  local layer=sourceFiles.layer(art,'Draw here')
  local source=assert(layer and layer:cel(1),'No Draw here on art source')
  c.image=Image(source.image)
  c.position=Point(source.position.x,source.position.y)
  art:close()
end
local original=Image(c.image)
local position=Point(c.position.x,c.position.y)
local painted=Image(W,H,ColorMode.RGB)
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
  if x<0 or y<0 or x>=W or y>=H then return 0 end
  return painted:getPixel(x,y)
end
local opaque=groundPort.opaque
local fill=Image(painted,Rectangle(64,128,64,64))
if name=='water' then
  assert(not opaque(fill:getPixel(63,1)),'Water fill repair changed')
  fill:putPixel(63,1,pixel(126,129))
end
for it in fill:pixels() do assert(pc.rgbaA(it())==255,'Fill cell is incomplete') end
local function texture(x,y) return fill:getPixel(x%64,y%64) end
local function north(x,y)
  if y<(name=='water' and 24 or 16) then return 0 end
  if y>44 then return texture(x,y) end
  return pixel(64+x,64+y)
end
local function south(x,y)
  if y>40 then return 0 end
  if y<22 then return texture(x,y) end
  if name=='water' then return pixel(64+x%24,192+y) end
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
  return pixel(x,material.west_y+y%(material.west_h or 24))
end
local function component(x,y,w,h,seedx,seedy,row)
  local out=Image(64,64,ColorMode.RGB)
  local todo={{seedx,seedy}}
  local seen={}
  while #todo>0 do
    local at=table.remove(todo)
    local xx,yy=at[1],at[2]
    local key=yy*64+xx
    if xx>=x and xx<x+w and yy>=y and yy<y+h and not seen[key] then
      seen[key]=true
      if opaque(pixel(xx,(row or 64)+yy)) then
        out:putPixel(xx,yy,pixel(xx,(row or 64)+yy))
        for _,d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do todo[#todo+1]={xx+d[1],yy+d[2]} end
      end
    end
  end
  return out
end
local outer_nw=component(0,0,40,40,2,2)
local outer_se=component(24,20,40,44,60,60)
local outer_ne=Image(painted,Rectangle(0,192,64,64))
local outer_sw
if name=='water' then
  outer_ne=component(24,0,40,40,60,2,192)
  outer_sw=Image(painted,Rectangle(128,64,64,64))
end
local corners={
  {bit=1,h=2,v=4,x=0,y=0,outer=outer_nw},
  {bit=2,h=1,v=8,x=32,y=0,outer=material.ne and outer_ne or nil},
  {bit=4,h=8,v=1,x=0,y=32,outer=outer_sw},
  {bit=8,h=4,v=2,x=32,y=32,outer=outer_se},
}
local cells={}
local extension=Image(W,H,ColorMode.RGB)
local atlas=Image(groundPort.SIZE,groundPort.SIZE,ColorMode.RGB)
for i,m in ipairs(order) do
  local tile=Image(64,64,ColorMode.RGB)
  local ox,oy=groundPort.at(i)
  if m==15 then
    tile=Image(fill)
  elseif m==9 or m==12 or (material.complete and material.complete[m]) then
    tile=Image(painted,Rectangle(ox,oy,64,64))
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
  for y=0,63 do for x=0,63 do
    local p=pixel(ox+x,oy+y)
    if opaque(p) then tile:putPixel(x,y,p) end
  end end
  for it in tile:pixels() do assert(not opaque(it()) or palette[it()],'New colour') end
  cells[m]=tile
  atlas:drawImage(tile,Point(ox,oy-groundPort.HEAD))
  for y=0,63 do for x=0,63 do
    if not opaque(pixel(ox+x,oy+y)) then extension:putPixel(ox+x,oy+y,tile:getPixel(x,y)) end
  end end
end
local bit=groundPort.bit
for i,m in ipairs(order) do
  local sl=groundPort.corner(s,m)
  local x,y=groundPort.at(i)
  assert(sl and sl.bounds.x==x and sl.bounds.y==y
    and sl.bounds.width==groundPort.CELL and sl.bounds.height==groundPort.CELL,'Slice moved: '..m)
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
groundPort.checkJoins(cells)
local stamp=os.date(sourceFiles.STAMP)
local backup=work..name..'-before-'..stamp..'.aseprite'
sourceFiles.copy(path,backup)
if art_path~=path then sourceFiles.copy(art_path,work..name..'-painting-before-'..stamp..'.aseprite') end
local l=s:newLayer()
l.name=title..' extensions'
s:newCel(l,1,extension,Point(0,0))
for _,layer in ipairs(s.layers) do if layer.name=='Underdrawing (25%)' then layer.isVisible=false end end
drawing.stackIndex=#s.layers
app.layer=l
local dest=install and path or work..name..'-draft.aseprite'
s:saveAs(dest)
s:saveCopyAs(work..name..'-sheet.png')
s:close()
local back=assert(app.open(dest))
sourceFiles.checkCel(back,'Draw here',original,position)
sourceFiles.checkLayer(back,title..' extensions',extension,Point(0,0))
back:close()
if install then sourceFiles.copy(dest,canonical) end
atlas:saveAs(work..name..'-atlas.png')
local zoom=Image(atlas)
zoom:resize(768,768)
zoom:saveAs(work..name..'-atlas-3x.png')
groundPort.preview(cells,pc.rgba(146,122,93,255),work..name..'-connected.png')
local report=sourceFiles.report(work..name..'-validation.txt')
report:write('Source: '..path..'\nPainting: '..art_path..'\nSaved: '..dest..'\nBackup: '..backup..'\nOriginal image and position verified after reopening. Source palette retained.\n')
report:write('15 painted 64x64 cells; mask 0 empty; mask 15 fully opaque. All 128 legal adjacent pairs checked at their quarter cores.\n')
report:write('Original '..painted_count..' pixels and cel position untouched.\n')
report:write('Fill: (64,128,64,64). NW/SE corners: isolated components of cell 9.\n')
if name=='water' then
  report:write('Complete source cells 4, 6, 9, 10, 11, 12 retained. Fill hole at (127,129) completed beneath the original with (126,129).\n')
  report:write('NE corner: isolated upper-right component of cell 6. SW corner: cell 4.\n')
  report:write('North: cell 12 rows 24..44. South: source x 64..87, y 214..232. East: x 20..40, y 64..87. West: x 24..46, y 128..191.\n')
  report:write('Strips repeat at native scale. No rotation, mirroring, recolouring, smoothing or scaling.\n')
else
  report:write('Finished source cells 9, 12, 15 retained.\n')
  report:write(material.ne and 'NE corner: (0,192,64,64).\n' or 'NE corner intersects the west/south strips.\n')
  report:write('North: cell 12 rows 16..44. South: source x 0..23, y 86..104. East: x 20..40, y 64..87. West: x 24..46, y '..material.west_y..'..'..(material.west_y+23)..'.\n')
  report:write('Strips repeat at native scale; the missing SW corner intersects the north/east strips. No rotation, mirroring, recolouring, smoothing or scaling.\n')
end
report:write('Preview: '..name..'-connected.png. Art: '..name..'-atlas.png. Guides excluded; only the art layers export.\n')
report:close()
