-- params: out=<sheet.aseprite> labels=<ground_labels.py png> tint=r,g,b [replace=yes]
local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local groundPort=dofile(root..'tools/tile_art/ground_port.lua')
local path=assert(app.params.out,'out=<sheet.aseprite>')
local labels_png=assert(app.params.labels,'labels=<png>')
local r,g,b=assert(app.params.tint,'tint=r,g,b'):match('^(%d+),(%d+),(%d+)$')
assert(r,'tint=r,g,b')
local style=app.params.style or sourceFiles.DESKTOP..'cave-walls.aseprite'
local work=sourceFiles.work()
local pc=app.pixelColor
local order=dofile(root..'tools/tile_art/ground_corners.lua')
local COLS=groundPort.COLS
assert(#order==COLS*COLS)
local W,H,HEAD,CELL,HALF,LINE=groundPort.W,groundPort.H,groundPort.HEAD,groundPort.CELL,groundPort.CELL//2,2
local NW,NE,SW,SE=groundPort.NW,groundPort.NE,groundPort.SW,groundPort.SE
local LAYER=sourceFiles.LAYER

for i,m in ipairs(order) do
  local col,row=(i-1)%COLS,(i-1)//COLS
  if col<COLS-1 then
    local e=order[i+1]
    assert(((m&NE)~=0)==((e&NW)~=0) and ((m&SE)~=0)==((e&SW)~=0),'east seam '..m)
  end
  if row<COLS-1 then
    local s=order[i+COLS]
    assert(((m&SW)~=0)==((s&NW)~=0) and ((m&SE)~=0)==((s&NE)~=0),'south seam '..m)
  end
end

local ref=assert(app.open(style))
local paper,ink
for _,layer in ipairs(ref.layers) do
  if layer.name==LAYER.paper then paper=layer:cel(1).image:getPixel(W-8,H-8) end
  if layer.name:match('^64x64 grid') then
    for it in layer:cel(1).image:pixels() do
      if pc.rgbaA(it())>0 then ink=it() break end
    end
  end
end
ref:close()
assert(paper and ink,'style sheet layers')

local function blank(image)
  for it in image:pixels() do
    if pc.rgbaA(it())>0 then return false end
  end
  return true
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
  local ox,oy=groundPort.at(i)
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
local labels_image=Image{fromFile=labels_png}
local guides={
  {name=LAYER.paper,image=paper_image,opacity=255},
  {name=LAYER.under,image=under,opacity=64},
  {name=LAYER.labels,image=labels_image,opacity=255},
  {name='64x64 grid + X unused - hide before export',image=grid,opacity=255},
}

if app.fs.isFile(path) then
  assert(app.params.replace=='yes','already exists: '..path..' (replace=yes only replaces an unchanged blank template)')
  local old=assert(app.open(path))
  local slices={}
  for i,m in ipairs(order) do
    local x,y=groundPort.at(i)
    slices[#slices+1]={name='Corners '..m,bounds=Rectangle(x,y,CELL,CELL)}
  end
  sourceFiles.checkBlankTemplate(old,{width=W,height=H,colorMode=ColorMode.RGB,guides=guides,slices=slices},path)
  sourceFiles.keep(path,work,'ground',os.date(sourceFiles.STAMP))
  old:close()
end

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
for _,guide in ipairs(guides) do layer(guide.name,guide.image,guide.opacity) end
local drawing=layer(LAYER.draw,Image(W,H,ColorMode.RGB))
sprite:deleteLayer(first)
for i,m in ipairs(order) do
  local x,y=groundPort.at(i)
  local s=sprite:newSlice(Rectangle(x,y,CELL,CELL))
  s.name='Corners '..m
end
sprite.data='Paint on Draw here. 16 dual-grid 64x64 cells in tools/tile_art/ground_corners.lua order: each sits where four map cells meet, '
  ..'its shaded quarters this terrain (mask NW 1, NE 2, SW 4, SE 8), the clear ones what lies under it. '
  ..'Neighbouring cells share their corners, so paint the block as one picture; 15 is the plain fill and wraps on all four sides. X is unused.'
app.layer=drawing
sprite:saveAs(path)
sprite:close()

local reopened=assert(app.open(path))
local names,expected={},{}
for _,l in ipairs(reopened.layers) do names[#names+1]=l.name end
for _,guide in ipairs(guides) do expected[#expected+1]=guide.name end
expected[#expected+1]=LAYER.draw
assert(table.concat(names,'|')==table.concat(expected,'|'),table.concat(names,'|'))
assert(blank(sourceFiles.layer(reopened,LAYER.draw):cel(1).image))
assert(#reopened.slices==#order)
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
local base=app.fs.fileTitle(path)
reopened:saveCopyAs(work..base..'-ground-template.png')
reopened:close()
sourceFiles.write(work..base..'-ground-template.txt',path..': 16 cells, masks distinct, quarters match, shared corners agree, Draw here empty\n')
