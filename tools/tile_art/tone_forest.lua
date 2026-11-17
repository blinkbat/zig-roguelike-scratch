local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local source=root..'assets/source/forest-tree-walls.aseprite'
local desktop='C:/Users/DavidBennett/Desktop/forest-tree-walls.aseprite'
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local stamp=os.date(sourceFiles.STAMP)
local pc=app.pixelColor
local function rgb(r,g,b) return pc.rgba(r,g,b,255) end
local colours={
  [rgb(107,185,112)]=rgb(82,143,86),
  [rgb(158,215,106)]=rgb(122,166,82),
  [rgb(56,92,59)]=rgb(45,74,47),
  [rgb(27,66,30)]=rgb(23,55,25),
}
assert(sourceFiles.read(source)==sourceFiles.read(desktop),'Desktop has different edits; reconcile before toning')
local sprite=assert(app.open(source))
local changed=0
local tonedLayers={}
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Draw here' or layer.name=='Forest extensions' then
    local cel=assert(layer:cel(1))
    local image=Image(cel.image)
    for pixel in image:pixels() do
      local toned=colours[pixel()]
      if toned then pixel(toned); changed=changed+1 end
    end
    cel.image=image
    tonedLayers[layer.name]={image=image,position=Point(cel.position.x,cel.position.y)}
  end
end
assert(changed>0,'Forest palette already toned or owner palette changed')
sourceFiles.copy(source,root..'assets/backup/forest-tree-walls-before-tone.'..stamp..'.aseprite')
sourceFiles.copy(root..'assets/walls/forest-tree-walls.png',root..'assets/backup/forest-tree-walls-before-tone.'..stamp..'.png')
sourceFiles.copy(root..'assets/ground/grass.png',root..'assets/backup/grass.'..stamp..'.png')
sprite:saveAs(source)
sprite:close()
local reopened=assert(app.open(source))
for name,expected in pairs(tonedLayers) do sourceFiles.checkCel(reopened,name,expected.image,expected.position) end
reopened:close()
sourceFiles.copy(source,desktop)
local grass=Image{fromFile=root..'assets/ground/grass.png'}
for pixel in grass:pixels() do
  local p=pixel()
  pixel(pc.rgba(math.floor(pc.rgbaR(p)*0.85+0.5),math.floor(pc.rgbaG(p)*0.85+0.5),math.floor(pc.rgbaB(p)*0.85+0.5),pc.rgbaA(p)))
end
sourceFiles.savePng(grass,root..'assets/ground/grass.png')
dofile(root..'tools/tile_art/export_forest.lua')
local report=sourceFiles.report(app.fs.joinPath(app.fs.tempPath,'wall-mocks/forest-tone.txt'))
report:write(('%d foliage pixels darkened; trunks and alpha unchanged. Grass RGB reduced 15%%, alpha unchanged.\n'):format(changed))
report:write('Sources and previous PNGs backed up in assets/backup/; Desktop and assets/source sources updated.\n')
report:close()
