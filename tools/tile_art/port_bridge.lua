local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local path=app.params.source or 'C:/Users/DavidBennett/Desktop/bridge.aseprite'
local work=(app.params.work or app.fs.joinPath(app.fs.tempPath,'wall-mocks'))..'/'
app.fs.makeAllDirectories(work)
local order=dofile(root..'tools/tile_art/ground_corners.lua')
local pc=app.pixelColor
local s=assert(app.open(path))
assert(s.width==512 and s.height==320 and #s.frames==1 and #s.slices==16)
local drawing,previous
for _,l in ipairs(s.layers) do
  if l.name=='Bridge extensions' then previous=l end
  if l.name=='Draw here' then drawing=l end
end
if previous then
  local old=assert(app.open(assert(app.params.previous,'Inspect owner edits; previous=<validated source> required')))
  local expected
  for _,l in ipairs(old.layers) do if l.name=='Bridge extensions' then expected=l:cel(1) end end
  local actual=previous:cel(1)
  assert(expected and actual.image:isEqual(expected.image) and actual.position==expected.position,'Extension has later edits')
  old:close()
end
local c=assert(drawing:cel(1))
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
assert(painted_count==10837,'Source painting changed; inspect the crops before porting')
local O=pc.rgba(128,104,78,255)
local K=pc.rgba(0,0,0,255)
assert(palette[O] and palette[K])
local function px(x,y)
  if x<0 or y<0 or x>=512 or y>=320 then return 0 end
  return painted:getPixel(x,y)
end
local function opaque(v) return pc.rgbaA(v)>0 end
local function dark(v) return v==O or v==K end

-- Left quarters read x 64..95, right quarters x 32..63, so the west edge is his and the cut between them is the east edge.
local WEST,DX,D,RMAX=36,5,25,20
local function X(lx) return lx<32 and lx+64 or lx end
local function shifted(lx) return lx>=11 and lx<32 end
local function lower(lx,ly) return px(X(lx),64+ly) end
local function upper(lx,ly) return px(X(lx),128+ly) end
local function spliced(lx,ly)
  if shifted(lx) then return px(X(lx)+DX,192+ly-D) end
  return px(X(lx),192+ly)
end

local function joint_cost(lx,r)
  return (spliced(lx,r)==upper(lx,r) or dark(upper(lx,r-1))) and 0 or 1
end
local function pair_cost(lx,rx,ry)
  local nx=(lx+1)%64
  local n=0
  for ly=math.min(rx,ry),math.max(rx,ry)-1 do
    local a=ly<rx and upper(lx,ly) or spliced(lx,ly)
    local b=ly<ry and upper(nx,ly) or spliced(nx,ly)
    if opaque(a) and opaque(b) and not dark(a) and not dark(b) then n=n+1 end
  end
  return n
end
local cols={}
for lx=WEST,63 do cols[#cols+1]=lx end
for lx=0,31 do cols[#cols+1]=lx end
local best,splice
for r0=1,RMAX do
  local cost={}
  local back={}
  for r=1,RMAX do cost[r]=r==r0 and joint_cost(cols[1],r) or math.huge end
  for i=2,#cols do
    local nxt={}
    back[i]={}
    for r=1,RMAX do
      local bc,bq=math.huge,nil
      for q=1,RMAX do
        if cost[q]<math.huge then
          local cq=cost[q]+pair_cost(cols[i-1],q,r)
          if cq<bc then bc,bq=cq,q end
        end
      end
      nxt[r]=bc+joint_cost(cols[i],r)
      back[i][r]=bq
    end
    cost=nxt
  end
  for r=1,RMAX do
    local total=cost[r]+pair_cost(cols[#cols],r,r0)
    if not best or total<best then
      best=total
      splice={}
      local q=r
      for i=#cols,2,-1 do
        splice[cols[i]]=q
        q=back[i][q]
      end
      splice[cols[1]]=q
      assert(q==r0)
    end
  end
end
for lx=32,WEST-1 do splice[lx]=splice[WEST] end

local top,bottom={},{}
for lx=0,63 do
  local at=(lx>=32 and lx<WEST) and WEST or lx
  local t=127
  assert(opaque(lower(at,63)))
  while t>60 and opaque(px(X(at),t-1)) do t=t-1 end
  top[lx]=t-64
  local b=splice[lx]-1
  for ly=splice[lx],63 do
    if not opaque(spliced(at,ly)) then break end
    b=ly
  end
  bottom[lx]=b
end

local function family(lx,ly,kind)
  if kind~='up' and ly>=top[lx] then return 'lo' end
  if kind~='lo' and ly<=bottom[lx] then
    if ly<splice[lx] then return 'up' end
    return shifted(lx) and 'shift' or 'splice'
  end
  if kind=='both' then return 'up' end
end
local function source(lx,ly,f)
  if f=='lo' then return lower(lx,ly) end
  if f=='up' then return upper(lx,ly) end
  return spliced(lx,ly)
end
local function compose(kind)
  local f,fam={},{}
  for ly=0,63 do
    f[ly],fam[ly]={},{}
    for lx=0,63 do
      local k=family(lx,ly,kind)
      fam[ly][lx]=k
      f[ly][lx]=k and source(lx,ly,k) or 0
    end
  end
  for lx=0,63 do
    local r=splice[lx]
    if fam[r-1][lx]=='up' and (fam[r][lx]=='shift' or fam[r][lx]=='splice') and joint_cost(lx,r)>0 then f[r-1][lx]=O end
  end
  for ly=0,63 do
    for lx=0,63 do
      local nx=(lx+1)%64
      local a,b=fam[ly][lx],fam[ly][nx]
      local p,q=f[ly][lx],f[ly][nx]
      if a and b and a~=b and opaque(p) and opaque(q) and not dark(p) and not dark(q) then f[ly][lx]=O end
    end
    if opaque(f[ly][31]) and not dark(f[ly][31]) then f[ly][31]=O end
  end
  if kind=='both' then
    for lx=0,63 do
      local above=(top[lx]-1)%64
      local p=f[above][lx]
      if fam[above][lx]~='lo' and opaque(p) and not dark(p) then f[above][lx]=O end
    end
  end
  return f
end
local layers={both=compose('both'),lo=compose('lo'),up=compose('up')}
local east_shadow={}
for y=97,168 do if px(128,y)==K then east_shadow[y%64]=true end end

local function edged(mask)
  local tile=Image(64,64,ColorMode.RGB)
  for ly=0,63 do
    for lx=0,63 do
      local side=lx>=32 and 1 or 0
      local lo=(mask&(4<<side))~=0
      local up=(mask&(1<<side))~=0
      local kind=(lo and up and 'both') or (lo and 'lo') or (up and 'up')
      if kind then tile:putPixel(lx,ly,layers[kind][ly][lx]) end
    end
    if opaque(tile:getPixel(31,ly)) then
      for lx=WEST-1,32,-1 do
        if not opaque(tile:getPixel(lx,ly)) and opaque(tile:getPixel(lx+1,ly)) then tile:putPixel(lx,ly,tile:getPixel(lx+1,ly)) end
      end
      if not opaque(tile:getPixel(32,ly)) and east_shadow[ly] then tile:putPixel(32,ly,K) end
    end
  end
  return tile
end

local function fill_x(lx) return lx<36 and lx+64 or lx end
local function fill_pixel(lx,ly,lower_half)
  return px(fill_x(lx),(lower_half and 64 or 128)+ly)
end
local function difference(a,b)
  if not opaque(a) or not opaque(b) then return 100000 end
  local function square(v) return v*v end
  return square(pc.rgbaR(a)-pc.rgbaR(b))+square(pc.rgbaG(a)-pc.rgbaG(b))+square(pc.rgbaB(a)-pc.rgbaB(b))
end
local function cut_cost(lx,r)
  local cost=0
  for y=r-1,r+1 do cost=cost+difference(fill_pixel(lx,y,false),fill_pixel(lx,y,true)) end
  return cost
end
local fill_cols={}
for lx=36,63 do fill_cols[#fill_cols+1]=lx end
for lx=0,35 do fill_cols[#fill_cols+1]=lx end
local fill_best,fill_cut
for first=40,59 do
  local costs,back={},{}
  for r=40,59 do costs[r]=r==first and cut_cost(fill_cols[1],r) or math.huge end
  for i=2,#fill_cols do
    local next_cost={}
    back[i]={}
    for r=40,59 do
      local best_cost,best_row=math.huge,nil
      for q=math.max(40,r-1),math.min(59,r+1) do
        local value=costs[q]+math.abs(q-r)
        if value<best_cost then best_cost,best_row=value,q end
      end
      next_cost[r]=best_cost+cut_cost(fill_cols[i],r)
      back[i][r]=best_row
    end
    costs=next_cost
  end
  for last=math.max(40,first-1),math.min(59,first+1) do
    if not fill_best or costs[last]<fill_best then
      fill_best=costs[last]
      fill_cut={}
      local q=last
      for i=#fill_cols,2,-1 do
        fill_cut[fill_cols[i]]=q
        q=back[i][q]
      end
      fill_cut[fill_cols[1]]=q
    end
  end
end
local fill=Image(64,64,ColorMode.RGB)
for ly=0,63 do for lx=0,63 do
  local v=fill_pixel(lx,ly,ly>=fill_cut[lx])
  assert(opaque(v),'Hole in continuous plank field')
  fill:putPixel(lx,ly,v)
end end

local function piece(mask)
  local edge=edged(mask)
  local tile=Image(edge)
  for ly=0,63 do for lx=0,63 do
    if opaque(edge:getPixel(lx,ly)) then
      local side=lx>=32 and 1 or 0
      local lo=(mask&(4<<side))~=0
      local up=(mask&(1<<side))~=0
      local cap=(lo and not up and ly<top[lx]+5) or (up and not lo and ly>bottom[lx]-5)
      local east=lx>=28 and lx<=32 and opaque(edge:getPixel(31,ly)) and not opaque(edge:getPixel(36,ly))
      local west=lx>=32 and lx<=39 and not opaque(edge:getPixel(31,ly)) and opaque(edge:getPixel(36,ly))
      if not cap and not east and not west then tile:putPixel(lx,ly,fill:getPixel(lx,ly)) end
    end
  end end
  return tile
end

local cells={}
local extension=Image(512,320,ColorMode.RGB)
local atlas=Image(256,256,ColorMode.RGB)
for i,m in ipairs(order) do
  local tile=piece(m)
  for it in tile:pixels() do
    local v=it()
    assert(pc.rgbaA(v)==0 or (pc.rgbaA(v)==255 and palette[v]),'New colour or partial alpha in mask '..m)
  end
  cells[m]=tile
  local ox,oy=((i-1)%4)*64,64+((i-1)//4)*64
  extension:drawImage(tile,Point(ox,oy))
  atlas:drawImage(tile,Point(ox,oy-64))
end

local function bit(m,b) return (m&b)~=0 end
for i,m in ipairs(order) do
  local sl
  for _,slice in ipairs(s.slices) do if slice.name=='Corners '..m then sl=slice end end
  assert(sl and sl.bounds.x==((i-1)%4)*64 and sl.bounds.y==64+((i-1)//4)*64,'Slice moved: '..m)
  for _,q in ipairs({{1,8,8},{2,48,8},{4,8,48},{8,48,48}}) do
    for y=q[3],q[3]+7 do for x=q[2],q[2]+7 do
      assert(opaque(cells[m]:getPixel(x,y))==bit(m,q[1]),'Wrong quarter in mask '..m)
    end end
  end
  for it in cells[m]:pixels() do
    if m==0 then assert(not opaque(it()),'Unused cell painted') end
    if m==15 then assert(opaque(it()),'Fill has a hole') end
  end
end
local edges={{x=63,bits=2|8},{x=0,bits=1|4},{y=63,bits=4|8},{y=0,bits=1|2}}
for a=0,15 do for b=0,15 do
  for _,e in ipairs(edges) do
    if (a&e.bits)==(b&e.bits) then
      for i=0,63 do
        local x,y=e.x or i,e.y or i
        assert(cells[a]:getPixel(x,y)==cells[b]:getPixel(x,y),'Edge '..(e.x and 'x' or 'y')..' of '..a..' differs from '..b)
      end
    end
  end
end end
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
        assert(opaque(cells[b]:getPixel(x,0))==bit(a,span[3]),'North gap')
      end
    end
    joins=joins+1
  end
end end
assert(joins==128)

local stamp=os.date('%Y%m%d-%H%M%S')
local backup=work..'bridge-before-'..stamp..'.aseprite'
local function copy(from,to)
  local input=assert(io.open(from,'rb'))
  local bytes=input:read('*a')
  input:close()
  local output=assert(io.open(to,'wb'))
  output:write(bytes)
  output:close()
end
copy(path,backup)
if previous then s:deleteLayer(previous) end
local l=s:newLayer()
l.name='Bridge extensions'
s:newCel(l,1,extension,Point(0,0))
drawing.isVisible=false
for _,layer in ipairs(s.layers) do if layer.name=='Underdrawing (25%)' then layer.isVisible=false end end
app.layer=l
local dest=app.params.install=='yes' and path or work..'bridge-draft.aseprite'
s:saveAs(dest)
if app.params.install=='yes' then s:saveCopyAs(root..'assets/source/bridge.aseprite') end
s:close()
local back=assert(app.open(dest))
for _,layer in ipairs(back.layers) do
  if layer.name=='Draw here' then
    local cel=assert(layer:cel(1))
    assert(cel.image:isEqual(original) and cel.position.x==position.x and cel.position.y==position.y,'Original altered')
  end
  if layer.name=='Bridge extensions' then
    local cel=assert(layer:cel(1))
    local img=Image(512,320,ColorMode.RGB)
    img:drawImage(cel.image,cel.position)
    assert(img:isEqual(extension),'Extension changed')
  end
end
back:close()
atlas:saveAs(work..'bridge-atlas.png')
local zoom=Image(atlas)
zoom:resize(1024,1024)
zoom:saveAs(work..'bridge-atlas-4x.png')
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
local function deck(x,y)
  return y>=1 and y<=#map and x>=1 and x<=#map[y] and map[y]:sub(x,x)=='#'
end
local preview=Image(#map[1]*64,#map*64,ColorMode.RGB)
preview:clear(pc.rgba(54,75,106,255))
for y=1,#map+1 do for x=1,#map[1]+1 do
  local m=(deck(x-1,y-1) and 1 or 0)|(deck(x,y-1) and 2 or 0)|(deck(x-1,y) and 4 or 0)|(deck(x,y) and 8 or 0)
  preview:drawImage(cells[m],Point((x-1)*64-32,(y-1)*64-32))
end end
preview:saveAs(work..'bridge-connected.png')
local report=assert(io.open(work..'bridge-validation.txt','w'))
report:write('Source: '..path..'\nSaved: '..dest..'\nBackup: '..backup..'\n')
report:write('Draw here unchanged ('..painted_count..' pixels), hidden; Bridge extensions holds all 15 cells.\n')
report:write('Splice rows by column: ')
for lx=0,63 do report:write(splice[lx]..(lx<63 and ',' or '\n')) end
report:write('Splice repairs: '..best..'. Palette and alpha unchanged; quarter cores and all 128 legal pairs checked; each edge strip depends only on the quarters touching it.\n')
report:write('Interior fill copies source rows 128..191 then 64..127 across a minimum-difference cut; vertical wraps retain adjacent original rows 127/128. Original caps stay on exposed edges only.\n')
report:close()
