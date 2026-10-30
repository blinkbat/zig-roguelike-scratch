-- A ground template's painting, its 4x4 block alone, as the game's sheet: assets/<name>-ground.png, which src/gfx/ground.zig reads.
-- params: name=grass|cobble|dirt|water|shallows|bridge [source=<sheet.aseprite>] [out=<png>] [from=underdrawing, a stand-in, only with out=]
local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local name=assert(app.params.name,'name=grass|cobble|dirt|water|shallows|bridge')
local source_name=({water='deep-water',shallows='water'})[name] or name
local source=app.params.source or ('C:/Users/DavidBennett/Desktop/'..source_name..'.aseprite')
local stand_in=app.params.from=='underdrawing'
assert(app.params.from==nil or stand_in,'from=underdrawing or nothing')
assert(not stand_in or app.params.out,'a stand-in never goes into assets/: give out=')
local out=app.params.out or (root..'assets/'..name..'-ground.png')
local HEAD,CELL,COLS=64,64,4
local order=dofile(root..'tools/tile_art/ground_corners.lua')
assert(#order==COLS*COLS)

local sprite=assert(app.open(source))
assert(sprite.width==512 and sprite.height==HEAD+COLS*CELL,'not a ground template: '..source)
assert(#sprite.slices==COLS*COLS,'not a ground template: '..source)
for i,m in ipairs(order) do
  local s
  for _,sl in ipairs(sprite.slices) do
    if sl.name=='Corners '..m then s=sl end
  end
  assert(s,'no slice for mask '..m)
  assert(s.bounds.x==((i-1)%COLS)*CELL and s.bounds.y==HEAD+((i-1)//COLS)*CELL,'slice '..m..' moved')
end
local want=stand_in and 'Underdrawing (25%)' or 'Draw here'
local extension=(name=='water' or name=='shallows') and 'Water extensions' or name:gsub('^%l',string.upper)..' extensions'
local found=false
local sheet=Image(COLS*CELL,COLS*CELL,ColorMode.RGB)
for _,l in ipairs(sprite.layers) do
  if l.name==want then found=true end
  if (l.name==want and (stand_in or l.isVisible)) or (not stand_in and l.name==extension) then
    local cel=assert(l:cel(1),'no cel on '..l.name)
    assert(stand_in or (l.opacity==255 and cel.opacity==255),'Art layer opacity: '..l.name)
    sheet:drawImage(cel.image,Point(cel.position.x,cel.position.y-HEAD))
  end
end
assert(found,'no '..want..' in '..source)
local painted=0
for it in sheet:pixels() do
  if app.pixelColor.rgbaA(it())>0 then painted=painted+1 end
end
assert(painted>0,source..': nothing painted on '..want)
if name=='bridge' and not stand_in then
  local pc=app.pixelColor
  for it in sheet:pixels() do
    local v=it()
    if pc.rgbaA(v)>0 then
      it(pc.rgba(math.floor(pc.rgbaR(v)*0.70+0.5),math.floor(pc.rgbaG(v)*0.70+0.5),math.floor(pc.rgbaB(v)*0.70+0.5),pc.rgbaA(v)))
    end
  end
end
sprite:close()
sheet:saveAs(out)
local back=Image{fromFile=out}
assert(back.width==COLS*CELL and back.height==COLS*CELL and back:isEqual(sheet),'reread '..out)
