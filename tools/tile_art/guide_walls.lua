local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local path=assert(app.params.source,'source=<sheet.aseprite>')
local work=app.fs.joinPath(app.fs.tempPath,'wall-mocks')..'/'
app.fs.makeAllDirectories(work)
local pc=app.pixelColor
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
assert(#masks==47)
-- Walls: export_walls.lua's FACE and src/gfx/look.zig's WALL_FACE_PX, facing south. A liquid's bank faces north.
local FACE=tonumber(app.params.rows) or 23
local NORTH=app.params.face=='north'
assert(NORTH or (app.params.face or 'south')=='south')
local LINE=2
local outline=pc.rgba(34,34,34,255)
local cap=pc.rgba(152,152,152,255)
local face=pc.rgba(96,96,96,255)
local sprite=assert(app.open(path))
assert(sprite.width==512 and sprite.height==448 and #sprite.slices==47)
local under,exact,drawing
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Underdrawing (25%)' then under=layer end
  if layer.name=='Exact connection guide (hidden)' then exact=layer end
  if layer.name=='Draw here' then drawing=layer end
end
assert(under and exact and drawing)
local drawn=Image(drawing:cel(1).image)
local function tile(mask,faced)
  local n,e,s,w=(mask&1)~=0,(mask&2)~=0,(mask&4)~=0,(mask&8)~=0
  local ne,se,sw,nw=(mask&16)~=0,(mask&32)~=0,(mask&64)~=0,(mask&128)~=0
  local image=Image(64,64,ColorMode.RGB)
  local foot=(s or not faced) and 64 or 64-FACE
  for y=0,63 do for x=0,63 do
    local pixel=y>=foot and face or cap
    if not n and y<LINE then pixel=outline end
    if not s and y>=64-LINE then pixel=outline end
    if not w and x<LINE then pixel=outline end
    if not e and x>=64-LINE then pixel=outline end
    if y>=foot and y<foot+LINE then pixel=outline end
    if n and w and not nw and x<4 and y<4 and (x<LINE or y<LINE) then pixel=outline end
    if n and e and not ne and x>=60 and y<4 and (x>=64-LINE or y<LINE) then pixel=outline end
    if s and w and not sw and x<LINE and y>=(faced and 64-FACE or 60) then pixel=outline end
    if s and e and not se and x>=64-LINE and y>=(faced and 64-FACE or 60) then pixel=outline end
    if not faced and s and w and not sw and x<4 and y>=64-LINE then pixel=outline end
    if not faced and s and e and not se and x>=60 and y>=64-LINE then pixel=outline end
    image:putPixel(x,y,pixel)
  end end
  return image
end
local function sheet(faced)
  local image=Image(512,448,ColorMode.RGB)
  local cells={}
  for i,mask in ipairs(masks) do
    local m=mask
    if NORTH then
      m=0
      for from,to in pairs({[1]=4,[4]=1,[2]=2,[8]=8,[16]=32,[32]=16,[64]=128,[128]=64}) do
        if (mask&from)~=0 then m=m|to end
      end
    end
    local cell=tile(m,faced)
    for a=0,63 do
      if (m&1)~=0 then assert(cell:getPixel(a,0)~=outline or a<4 or a>=60,'north seam '..mask) end
      if (m&8)~=0 then assert(cell:getPixel(0,a)~=outline or a<4 or a>=64-FACE,'west seam '..mask) end
    end
    if NORTH then cell:flip(FlipType.VERTICAL) end
    for _,other in ipairs(cells) do assert(not cell:isEqual(other),'duplicate cell '..mask) end
    cells[#cells+1]=cell
    image:drawImage(cell,Point(((i-1)%8)*64,64+math.floor((i-1)/8)*64))
  end
  return image
end
for _,slice in ipairs(sprite.slices) do
  local i=assert(tonumber(slice.name:match('^Connection (%d+)$')),slice.name)
  local b=slice.bounds
  assert(b.x==((i-1)%8)*64 and b.y==64+math.floor((i-1)/8)*64 and b.width==64 and b.height==64,slice.name)
end
local base=path:match('([^/\\]+)%.aseprite$')
sprite:saveCopyAs(work..base..'-before-full-cell-'..os.date('%Y%m%d-%H%M%S')..'.aseprite')
under:cel(1).image=sheet(true)
under:cel(1).position=Point(0,0)
exact:cel(1).image=sheet(false)
exact:cel(1).position=Point(0,0)
sprite.data='Paint on Draw here. 47 full 64x64 cells in tools/tile_art/wall_masks.lua order, the runtime wall rules: an outline on each side a cell does not join, a notch at a corner it does not, and a '..FACE..'-row '..(NORTH and 'bank where nothing joins it from the north' or 'face where nothing joins it from the south')..'. Exact connection guide is the same without it. X is unused.'
drawing.stackIndex=#sprite.layers
app.layer=drawing
sprite:saveAs(path)
sprite:close()
local reopened=assert(app.open(path))
for _,layer in ipairs(reopened.layers) do
  if layer.name=='Draw here' then assert(layer:cel(1).image:isEqual(drawn)) end
end
reopened:saveCopyAs(work..base..'-full-cell.png')
reopened:close()
