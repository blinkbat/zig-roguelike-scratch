-- params: out=<sheet.aseprite> labels=<ground_labels.py png> tint=r,g,b [replace=yes]
local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local path=assert(app.params.out,'out=<sheet.aseprite>')
local labels_png=assert(app.params.labels,'labels=<png>')
local r,g,b=assert(app.params.tint,'tint=r,g,b'):match('^(%d+),(%d+),(%d+)$')
assert(r,'tint=r,g,b')
local style=app.params.style or 'C:/Users/DavidBennett/Desktop/cave-walls.aseprite'
local work=app.fs.joinPath(app.fs.tempPath,'wall-mocks')..'/'
app.fs.makeAllDirectories(work)
local pc=app.pixelColor
local order=dofile(root..'tools/tile_art/ground_corners.lua')
assert(#order==16)
local W,H,HEAD,CELL,HALF,LINE=512,320,64,64,32,2
local NW,NE,SW,SE=1,2,4,8

for i,m in ipairs(order) do
  local col,row=(i-1)%4,(i-1)//4
  if col<3 then
    local e=order[i+1]
    assert(((m&NE)~=0)==((e&NW)~=0) and ((m&SE)~=0)==((e&SW)~=0),'east seam '..m)
  end
  if row<3 then
    local s=order[i+4]
    assert(((m&SW)~=0)==((s&NW)~=0) and ((m&SE)~=0)==((s&NE)~=0),'south seam '..m)
  end
end

local ref=assert(app.open(style))
local paper,ink
for _,layer in ipairs(ref.layers) do
  if layer.name=='Paper - hide for transparent export' then paper=layer:cel(1).image:getPixel(W-8,H-8) end
  if layer.name:match('^64x64 grid') then
    for it in layer:cel(1).image:pixels() do
      if pc.rgbaA(it())>0 then ink=it() break end
    end
  end
end
ref:close()
assert(paper and ink,'style sheet layers')

local function drawing_of(sprite)
  for _,layer in ipairs(sprite.layers) do
    if layer.name=='Draw here' then return layer end
  end
end

local function blank(image)
  for it in image:pixels() do
    if pc.rgbaA(it())>0 then return false end
  end
  return true
end

if app.fs.isFile(path) then
  assert(app.params.replace=='yes','already exists: '..path..' (replace=yes backs it up and redoes it)')
  local old=assert(app.open(path))
  local d=drawing_of(old)
  assert(not d or not d:cel(1) or blank(d:cel(1).image),'refusing: '..path..' has painting on Draw here')
  local base=path:match('([^/\\]+)%.aseprite$')
  old:saveCopyAs(work..base..'-before-ground-'..os.date('%Y%m%d-%H%M%S')..'.aseprite')
  old:close()
end

local fill=pc.rgba(tonumber(r),tonumber(g),tonumber(b),255)
local edge=pc.rgba(tonumber(r)//2,tonumber(g)//2,tonumber(b)//2,255)

local function quarters(mask,x,y)
  local west=x<HALF
  local north=y<HALF
  return (mask&(north and (west and NW or NE) or (west and SW or SE)))~=0
end

local under=Image(W,H,ColorMode.RGB)
local grid=Image(W,H,ColorMode.RGB)
for i,m in ipairs(order) do
  local ox,oy=((i-1)%4)*CELL,HEAD+((i-1)//4)*CELL
  for y=0,CELL-1 do for x=0,CELL-1 do
    if quarters(m,x,y) then
      local beside=not quarters(m,x<HALF and HALF or HALF-1,y)
      local below=not quarters(m,x,y<HALF and HALF or HALF-1)
      local near_x=x>=HALF-LINE and x<HALF+LINE
      local near_y=y>=HALF-LINE and y<HALF+LINE
      under:putPixel(ox+x,oy+y,((near_x and beside) or (near_y and below)) and edge or fill)
    end
    if x==0 or y==0 or x==CELL-1 or y==CELL-1 then grid:putPixel(ox+x,oy+y,ink) end
    if m==0 and (x==y or x==CELL-1-y) then grid:putPixel(ox+x,oy+y,ink) end
  end end
end
local paper_image=Image(W,H,ColorMode.RGB)
paper_image:clear(paper)

local sprite=Sprite(W,H,ColorMode.RGB)
local function layer(name,image,opacity,visible)
  local l=sprite:newLayer()
  l.name=name
  l.opacity=opacity or 255
  l.isVisible=visible~=false
  sprite:newCel(l,1,image,Point(0,0))
  return l
end
local first=sprite.layers[1]
layer('Paper - hide for transparent export',paper_image)
layer('Underdrawing (25%)',under,64)
layer('Labels - hide before export',Image{fromFile=labels_png})
layer('64x64 grid + X unused - hide before export',grid)
local drawing=layer('Draw here',Image(W,H,ColorMode.RGB))
sprite:deleteLayer(first)
for i,m in ipairs(order) do
  local s=sprite:newSlice(Rectangle(((i-1)%4)*CELL,HEAD+((i-1)//4)*CELL,CELL,CELL))
  s.name='Corners '..m
end
sprite.data='Paint on Draw here. 16 dual-grid 64x64 cells in tools/tile_art/ground_corners.lua order: each sits where four map cells meet, '
  ..'its shaded quarters this terrain (mask NW 1, NE 2, SW 4, SE 8), the clear ones what lies under it. '
  ..'Neighbouring cells share their corners, so paint the block as one picture; 15 is the plain fill and wraps on all four sides. X is unused.'
app.layer=drawing
sprite:saveAs(path)
sprite:close()

local reopened=assert(app.open(path))
local names={}
for _,l in ipairs(reopened.layers) do names[#names+1]=l.name end
assert(table.concat(names,'|')=='Paper - hide for transparent export|Underdrawing (25%)|Labels - hide before export|64x64 grid + X unused - hide before export|Draw here',table.concat(names,'|'))
assert(blank(drawing_of(reopened):cel(1).image))
assert(#reopened.slices==16)
local seen={}
for _,s in ipairs(reopened.slices) do
  local m=assert(tonumber(s.name:match('^Corners (%d+)$')),s.name)
  assert(not seen[m]) seen[m]=true
  local u=reopened.layers[2]:cel(1).image
  for _,q in ipairs({{8,8,NW},{CELL-9,8,NE},{8,CELL-9,SW},{CELL-9,CELL-9,SE}}) do
    local shaded=pc.rgbaA(u:getPixel(s.bounds.x+q[1],s.bounds.y+q[2]))>0
    assert(shaded==((m&q[3])~=0),'quarter '..q[3]..' of '..m)
  end
end
local base=path:match('([^/\\]+)%.aseprite$')
reopened:saveCopyAs(work..base..'-ground-template.png')
reopened:close()
local report=io.open(work..base..'-ground-template.txt','w')
report:write(path..': 16 cells, masks distinct, quarters match, shared corners agree, Draw here empty\n')
report:close()
