local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local path=app.params.source or 'C:/Users/DavidBennett/Desktop/forest-tree-walls.aseprite'
local work=app.fs.joinPath(app.fs.tempPath,'wall-mocks')..'/'
app.fs.makeAllDirectories(work)
local backups=root..'assets/backup/'
app.fs.makeAllDirectories(backups)
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
local pc=app.pixelColor
local sprite=assert(app.open(path))
assert(sprite.width==512 and sprite.height==448 and #sprite.frames==1 and #sprite.slices==47)
local drawing
for _,layer in ipairs(sprite.layers) do
  assert(layer.name~='Forest extensions','Inspect existing extensions for owner edits before regenerating')
  if layer.name=='Draw here' then drawing=layer end
end
assert(drawing)
local original=assert(drawing:cel(1))
local saved=Image(original.image)
local position=Point(original.position.x,original.position.y)
local painted=Image(512,448,ColorMode.RGB)
painted:drawImage(saved,position)
local source=Image(painted,Rectangle(0,64,64,64))
local palette={}
local count=0
for y=0,447 do for x=0,511 do
  local p=painted:getPixel(x,y)
  if pc.rgbaA(p)>0 then
    assert(x<64 and y>=64 and y<128,'New source painting outside cell 01; inspect before porting')
    palette[p]=true
    count=count+1
  end
end end
assert(count>0)
local canopy=Image(source,Rectangle(0,0,64,50))
local cells={}
local sheet=Image(512,448,ColorMode.RGB)
local atlas=Image(512,384,ColorMode.RGB)
local function has(mask,bit) return (mask&bit)~=0 end
for i,mask in ipairs(masks) do
  local n,e,s,w=has(mask,1),has(mask,2),has(mask,4),has(mask,8)
  local pieces={
    {-32,-32,n and w and has(mask,128)}, {0,-32,n}, {32,-32,n and e and has(mask,16)},
    {-32,0,w}, {0,0,true}, {32,0,e},
    {-32,32,s and w and has(mask,64)}, {0,32,s}, {32,32,s and e and has(mask,32)},
  }
  local tile=Image(64,64,ColorMode.RGB)
  for _,piece in ipairs(pieces) do
    if piece[3] then
      tile:drawImage(piece[2]==0 and not s and source or canopy,Point(piece[1],piece[2]))
    end
  end
  if mask==0 then assert(tile:isEqual(source),'Original cell changed') end
  for y=0,63 do for x=0,63 do
    local p=tile:getPixel(x,y)
    assert(pc.rgbaA(p)==0 or palette[p],'Colour outside source palette')
    if e and x==63 and y>=8 and y<=40 then assert(pc.rgbaA(p)==255,'East gap '..mask) end
    if w and x==0 and y>=8 and y<=40 then assert(pc.rgbaA(p)==255,'West gap '..mask) end
    if n and y==0 and x>=8 and x<=55 then assert(pc.rgbaA(p)==255,'North gap '..mask) end
    if s and y==63 and x>=8 and x<=55 then assert(pc.rgbaA(p)==255,'South gap '..mask) end
  end end
  for other,cell in pairs(cells) do assert(not tile:isEqual(cell),'Duplicate masks '..mask..' and '..other) end
  cells[mask]=tile
  local x,y=((i-1)%8)*64,math.floor((i-1)/8)*64
  atlas:drawImage(tile,Point(x,y))
  if i>1 then sheet:drawImage(tile,Point(x,y+64)) end
end
local backup=backups..'forest-tree-walls.'..os.date('%Y%m%d-%H%M%S')..'.aseprite'
sprite:saveCopyAs(backup)
local extension=sprite:newLayer()
extension.name='Forest extensions'
sprite:newCel(extension,1,sheet,Point(0,0))
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Underdrawing (25%)' or layer.name=='Ideas - hide before export' then layer.isVisible=false end
end
drawing.stackIndex=#sprite.layers
app.layer=extension
local destination=app.params.install=='yes' and path or work..'forest-tree-walls-draft.aseprite'
sprite:saveAs(destination)
if app.params.install=='yes' then sprite:saveCopyAs(root..'assets/source/forest-tree-walls.aseprite') end
sprite:saveCopyAs(work..'forest-tree-walls-sheet.png')
sprite:close()
local reopened=assert(app.open(destination))
for _,layer in ipairs(reopened.layers) do
  if layer.name=='Draw here' then
    local cel=assert(layer:cel(1))
    assert(cel.image:isEqual(saved),'Original painting changed after saving')
    assert(cel.position.x==position.x and cel.position.y==position.y,'Original painting moved')
  end
  if layer.name=='Forest extensions' then
    local actual=Image(512,448,ColorMode.RGB)
    local cel=assert(layer:cel(1))
    actual:drawImage(cel.image,cel.position)
    assert(actual:isEqual(sheet),'Extensions changed after saving')
  end
end
reopened:close()
atlas:saveAs(work..'forest-tree-walls-art.png')
source:saveAs(work..'forest-tree-walls-original.png')
local map={
  '...................',
  '.#######....#......',
  '............#..#...',
  '.###...###..#......',
  '.###...#....###....',
  '.###...###..#......',
  '............#..#...',
  '.#####.........#...',
  '.#...#...##...###..',
  '.#...#...##....#...',
  '.#####............',
  '...................',
}
local function wall(x,y)
  return y>=1 and y<=#map and x>=1 and x<=#map[y] and map[y]:sub(x,x)=='#'
end
local preview=Image(19*64,#map*64,ColorMode.RGB)
preview:clear(pc.rgba(104,112,77,255))
for y=1,#map do for x=1,19 do
  if wall(x,y) then
    local n,e,s,w=wall(x,y-1),wall(x+1,y),wall(x,y+1),wall(x-1,y)
    local m=(n and 1 or 0)|(e and 2 or 0)|(s and 4 or 0)|(w and 8 or 0)
    if n and e and wall(x+1,y-1) then m=m|16 end
    if s and e and wall(x+1,y+1) then m=m|32 end
    if s and w and wall(x-1,y+1) then m=m|64 end
    if n and w and wall(x-1,y-1) then m=m|128 end
    preview:drawImage(assert(cells[m]),Point((x-1)*64,(y-1)*64))
  end
end end
preview:saveAs(work..'forest-tree-walls-connected.png')
local report=assert(io.open(work..'forest-tree-walls-validation.txt','w'))
report:write('Source: '..path..'\nSaved: '..destination..'\nBackup: '..backup..'\n')
report:write('47 distinct 64x64 cells. Original Draw here pixels and position verified after reopen.\n')
report:write('Source: cell 01 at sheet (0,64), 64x64; canopy crop (0,64), 64x50.\n')
report:write('Whole pieces translated by 32 pixels, painted north-to-south and west-to-east. No scaling, rotation, palette changes or hand-drawn repairs.\n')
report:write('N/E/S/W bridge copies require their neighbour. Diagonal copies require both cardinals and their diagonal.\n')
report:write('Trunks retained only on south-exposed cells. North/south bridge copies use the canopy crop.\n')
report:write('All connected edge cores opaque. All colours from the painted cell. Original cell unchanged.\n')
report:write('Unused cell and header empty on extension; guides and ideas hidden.\n')
report:close()
