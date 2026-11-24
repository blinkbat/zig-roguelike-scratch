local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local path=app.params.source or sourceFiles.DESKTOP..'forest-tree-walls.aseprite'
local canonical=root..'assets/source/forest-tree-walls.aseprite'
local install=app.params.install=='yes'
sourceFiles.preserve(path,canonical,install)
local work=sourceFiles.work()
local backups=root..'assets/backup/'
app.fs.makeAllDirectories(backups)
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
local bit=masks.bit
local W,H,CELL,HEAD=masks.W,masks.SHEET_H,masks.CELL,masks.HEAD
local pc=app.pixelColor
local sprite=assert(app.open(path))
assert(sprite.width==W and sprite.height==H and #sprite.frames==1 and #sprite.slices==#masks)
assert(not sourceFiles.layer(sprite,sourceFiles.LAYER.forest),'Inspect existing extensions for owner edits before regenerating')
local drawing=assert(sourceFiles.layer(sprite,sourceFiles.LAYER.draw))
local original=assert(drawing:cel(1))
local saved=Image(original.image)
local position=Point(original.position.x,original.position.y)
local painted=sourceFiles.canvas(sprite,original)
local source=Image(painted,Rectangle(0,HEAD,CELL,CELL))
local palette={}
local count=0
for y=0,H-1 do for x=0,W-1 do
  local p=painted:getPixel(x,y)
  if pc.rgbaA(p)>0 then
    assert(x<CELL and y>=HEAD and y<HEAD+CELL,'New source painting outside cell 01; inspect before porting')
    palette[p]=true
    count=count+1
  end
end end
assert(count>0)
local CANOPY=50
local canopy=Image(source,Rectangle(0,0,CELL,CANOPY))
local cells={}
local sheet=Image(W,H,ColorMode.RGB)
local atlas=Image(masks.W,masks.H,ColorMode.RGB)
local function has(mask,b) return (mask&b)~=0 end
for i,mask in ipairs(masks) do
  local n,e,s,w=has(mask,bit.n),has(mask,bit.e),has(mask,bit.s),has(mask,bit.w)
  local pieces={
    {-32,-32,n and w and has(mask,bit.nw)}, {0,-32,n}, {32,-32,n and e and has(mask,bit.ne)},
    {-32,0,w}, {0,0,true}, {32,0,e},
    {-32,32,s and w and has(mask,bit.sw)}, {0,32,s}, {32,32,s and e and has(mask,bit.se)},
  }
  local tile=Image(CELL,CELL,ColorMode.RGB)
  for _,piece in ipairs(pieces) do
    if piece[3] then
      tile:drawImage(piece[2]==0 and not s and source or canopy,Point(piece[1],piece[2]))
    end
  end
  if mask==0 then assert(tile:isEqual(source),'Original cell changed') end
  for it in tile:pixels() do assert(pc.rgbaA(it())==0 or palette[it()],'Colour outside source palette') end
  masks.checkJoined(tile,mask,8,40,bit.e|bit.w)
  masks.checkJoined(tile,mask,8,55,bit.n|bit.s)
  for other,cell in pairs(cells) do assert(not tile:isEqual(cell),'Duplicate masks '..mask..' and '..other) end
  cells[mask]=tile
  atlas:drawImage(tile,Point(masks.at(i)))
  if i>1 then sheet:drawImage(tile,Point(masks.sheetAt(i))) end
end
local backup=(install and backups or work)..'forest-tree-walls.'..os.date(sourceFiles.STAMP)..'.aseprite'
sourceFiles.copy(path,backup)
local extension=sprite:newLayer()
extension.name=sourceFiles.LAYER.forest
sprite:newCel(extension,1,sheet,Point(0,0))
sourceFiles.hide(sprite,sourceFiles.LAYER.under,sourceFiles.LAYER.ideas)
drawing.stackIndex=#sprite.layers
app.layer=extension
local destination=install and path or sourceFiles.draft(work..'forest-tree-walls-draft.aseprite',path)
local staged=sourceFiles.stage(app.fs.fileName(destination))
sprite:saveAs(staged)
sprite:saveCopyAs(work..'forest-tree-walls-sheet.png')
sprite:close()
local reopened=assert(app.open(staged))
sourceFiles.checkCel(reopened,sourceFiles.LAYER.draw,saved,position)
sourceFiles.checkLayer(reopened,sourceFiles.LAYER.forest,sheet,Point(0,0))
reopened:close()
sourceFiles.publishTo(staged,destination,install and canonical or nil)
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
masks.preview(cells,pc.rgba(104,112,77,255),work..'forest-tree-walls-connected.png',map)
local report=sourceFiles.report(work..'forest-tree-walls-validation.txt')
report:write('Source: '..path..'\nSaved: '..destination..'\nBackup: '..backup..'\n')
report:write(('%d distinct %dx%d cells. Original Draw here pixels and position verified after reopen.\n'):format(#masks,CELL,CELL))
report:write(('Source: cell 01 at sheet (0,%d), %dx%d; canopy crop (0,%d), %dx%d.\n'):format(HEAD,CELL,CELL,HEAD,CELL,CANOPY))
report:write('Whole pieces translated by 32 pixels, painted north-to-south and west-to-east. No scaling, rotation, palette changes or hand-drawn repairs.\n')
report:write('N/E/S/W bridge copies require their neighbour. Diagonal copies require both cardinals and their diagonal.\n')
report:write('Trunks retained only on south-exposed cells. North/south bridge copies use the canopy crop.\n')
report:write('All connected edge cores opaque. All colours from the painted cell. Original cell unchanged.\n')
report:write('Unused cell and header empty on extension; guides and ideas hidden.\n')
report:close()
