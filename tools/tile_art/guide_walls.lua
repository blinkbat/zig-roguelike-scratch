local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local path=assert(app.params.source,'source=<sheet.aseprite>')
local work=sourceFiles.work()
local rgb=sourceFiles.rgb
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
local bit=masks.bit
-- Walls face south, a liquid's bank north.
local FACE=tonumber(app.params.rows) or masks.FACE
local NORTH=app.params.face=='north'
assert(NORTH or (app.params.face or 'south')=='south')
local LINE=2
local CELL,LAST,NOTCH=masks.CELL,masks.CELL-1,4
local outline=rgb(34,34,34)
local cap=rgb(152,152,152)
local face=rgb(96,96,96)
local sprite=assert(app.open(path))
assert(sprite.width==masks.W and sprite.height==masks.SHEET_H and #sprite.slices==#masks)
local under=sourceFiles.layer(sprite,sourceFiles.LAYER.under)
local exact=sourceFiles.layer(sprite,sourceFiles.LAYER.exact)
local drawing=sourceFiles.layer(sprite,sourceFiles.LAYER.draw)
assert(under and exact and drawing)
local drawn=Image(drawing:cel(1).image)
local drawnAt=Point(drawing:cel(1).position)
local function tile(mask,faced)
  local n,e,s,w,ne,se,sw,nw=masks.sides(mask)
  local image=Image(CELL,CELL,ColorMode.RGB)
  local foot=(s or not faced) and CELL or CELL-FACE
  for y=0,LAST do for x=0,LAST do
    local pixel=y>=foot and face or cap
    if not n and y<LINE then pixel=outline end
    if not s and y>=CELL-LINE then pixel=outline end
    if not w and x<LINE then pixel=outline end
    if not e and x>=CELL-LINE then pixel=outline end
    if y>=foot and y<foot+LINE then pixel=outline end
    if n and w and not nw and x<NOTCH and y<NOTCH and (x<LINE or y<LINE) then pixel=outline end
    if n and e and not ne and x>=CELL-NOTCH and y<NOTCH and (x>=CELL-LINE or y<LINE) then pixel=outline end
    if s and w and not sw and x<LINE and y>=(faced and CELL-FACE or CELL-NOTCH) then pixel=outline end
    if s and e and not se and x>=CELL-LINE and y>=(faced and CELL-FACE or CELL-NOTCH) then pixel=outline end
    if not faced and s and w and not sw and x<NOTCH and y>=CELL-LINE then pixel=outline end
    if not faced and s and e and not se and x>=CELL-NOTCH and y>=CELL-LINE then pixel=outline end
    image:putPixel(x,y,pixel)
  end end
  return image
end
local function sheet(faced)
  local image=Image(masks.W,masks.SHEET_H,ColorMode.RGB)
  local cells={}
  for i,mask in ipairs(masks) do
    local m=mask
    if NORTH then
      m=0
      for from,to in pairs({[bit.n]=bit.s,[bit.s]=bit.n,[bit.e]=bit.e,[bit.w]=bit.w,[bit.ne]=bit.se,[bit.se]=bit.ne,[bit.sw]=bit.nw,[bit.nw]=bit.sw}) do
        if (mask&from)~=0 then m=m|to end
      end
    end
    local cell=tile(m,faced)
    for a=0,LAST do
      if (m&bit.n)~=0 then assert(cell:getPixel(a,0)~=outline or a<NOTCH or a>=CELL-NOTCH,'north seam '..mask) end
      if (m&bit.w)~=0 then assert(cell:getPixel(0,a)~=outline or a<NOTCH or a>=CELL-FACE,'west seam '..mask) end
    end
    if NORTH then cell:flip(FlipType.VERTICAL) end
    for _,other in ipairs(cells) do assert(not cell:isEqual(other),'duplicate cell '..mask) end
    cells[#cells+1]=cell
    image:drawImage(cell,Point(masks.sheetAt(i)))
  end
  return image
end
for _,slice in ipairs(sprite.slices) do
  local i=assert(tonumber(slice.name:match('^Connection (%d+)$')),slice.name)
  local b=slice.bounds
  local x,y=masks.sheetAt(i)
  assert(b.x==x and b.y==y and b.width==masks.CELL and b.height==masks.CELL,slice.name)
end
local base=app.fs.fileTitle(path)
sourceFiles.keep(path,work,'full-cell',os.date(sourceFiles.STAMP))
under:cel(1).image=sheet(true)
under:cel(1).position=Point(0,0)
exact:cel(1).image=sheet(false)
exact:cel(1).position=Point(0,0)
sprite.data='Paint on Draw here. '..#masks..' full '..masks.CELL..'x'..masks.CELL..' cells in tools/tile_art/wall_masks.lua order, the runtime wall rules: an outline on each side a cell does not join, a notch at a corner it does not, and a '..FACE..'-row '..(NORTH and 'bank where nothing joins it from the north' or 'face where nothing joins it from the south')..'. Exact connection guide is the same without it. X is unused.'
drawing.stackIndex=#sprite.layers
app.layer=drawing
sprite:saveAs(path)
sprite:close()
local reopened=assert(app.open(path))
assert(reopened.width==masks.W and reopened.height==masks.SHEET_H,'Saved sheet dimensions changed')
sourceFiles.checkLayer(reopened,sourceFiles.LAYER.under,sheet(true),Point(0,0))
sourceFiles.checkLayer(reopened,sourceFiles.LAYER.exact,sheet(false),Point(0,0))
sourceFiles.checkCel(reopened,sourceFiles.LAYER.draw,drawn,drawnAt)
reopened:saveCopyAs(work..base..'-full-cell.png')
reopened:close()
