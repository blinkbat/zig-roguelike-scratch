local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local source=root..'assets/source/forest-tree-walls.aseprite'
local desktop=sourceFiles.DESKTOP..'forest-tree-walls.aseprite'
local png=root..'assets/walls/forest-tree-walls.png'
local grass_png=root..'assets/ground/grass.png'
local stamp=os.date(sourceFiles.STAMP)
local rgb=sourceFiles.rgb
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
  if layer.name==sourceFiles.LAYER.draw or layer.name==sourceFiles.LAYER.forest then
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
sourceFiles.copy(png,root..'assets/backup/forest-tree-walls-before-tone.'..stamp..'.png')
sourceFiles.copy(grass_png,root..'assets/backup/grass.'..stamp..'.png')
local staged=sourceFiles.stage('forest-tree-walls.aseprite')
sprite:saveAs(staged)
sprite:close()
local reopened=assert(app.open(staged))
for name,expected in pairs(tonedLayers) do sourceFiles.checkCel(reopened,name,expected.image,expected.position) end
local atlas=dofile(root..'tools/tile_art/forest_atlas.lua')(sourceFiles,dofile(root..'tools/tile_art/wall_masks.lua'),reopened)
reopened:close()
local grass=Image{fromFile=grass_png}
for pixel in grass:pixels() do pixel(sourceFiles.scaleRgb(pixel(),0.85)) end
sourceFiles.publish({
  sourceFiles.staged(source,staged),
  sourceFiles.staged(desktop,staged),
  sourceFiles.stagePng(grass,grass_png),
  sourceFiles.stagePng(atlas,png,'Export changed the visible artwork'),
})
local report=sourceFiles.report(sourceFiles.work()..'forest-tone.txt')
report:write(('%d foliage pixels darkened; trunks and alpha unchanged. Grass RGB reduced 15%%, alpha unchanged.\n'):format(changed))
report:write('Sources and previous PNGs backed up in assets/backup/; Desktop and assets/source sources updated.\n')
report:close()
