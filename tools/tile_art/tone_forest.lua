local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local source=root..'assets/source/forest-tree-walls.aseprite'
local desktop='C:/Users/DavidBennett/Desktop/forest-tree-walls.aseprite'
local stamp=os.date('%Y%m%d-%H%M%S')
local pc=app.pixelColor
local function rgb(r,g,b) return pc.rgba(r,g,b,255) end
local colours={
  [rgb(107,185,112)]=rgb(82,143,86),
  [rgb(158,215,106)]=rgb(122,166,82),
  [rgb(56,92,59)]=rgb(45,74,47),
  [rgb(27,66,30)]=rgb(23,55,25),
}
local function copy(from,to)
  local f=assert(io.open(from,'rb'))
  local bytes=f:read('*a')
  f:close()
  local out=assert(io.open(to,'wb'))
  out:write(bytes)
  out:close()
end
local function contents(path)
  local f=assert(io.open(path,'rb'))
  local bytes=f:read('*a')
  f:close()
  return bytes
end
assert(contents(source)==contents(desktop),'Desktop has different edits; reconcile before toning')
local sprite=assert(app.open(source))
local changed=0
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Draw here' or layer.name=='Forest extensions' then
    local cel=assert(layer:cel(1))
    local image=Image(cel.image)
    for pixel in image:pixels() do
      local toned=colours[pixel()]
      if toned then pixel(toned); changed=changed+1 end
    end
    cel.image=image
  end
end
assert(changed>0,'Forest palette already toned or owner palette changed')
copy(source,root..'assets/backup/forest-tree-walls-before-tone.'..stamp..'.aseprite')
copy(root..'assets/forest-tree-walls.png',root..'assets/backup/forest-tree-walls-before-tone.'..stamp..'.png')
copy(root..'assets/grass.png',root..'assets/backup/grass.'..stamp..'.png')
sprite:saveAs(source)
sprite:saveCopyAs(desktop)
sprite:close()
local grass=Image{fromFile=root..'assets/grass.png'}
for pixel in grass:pixels() do
  local p=pixel()
  pixel(pc.rgba(math.floor(pc.rgbaR(p)*0.85+0.5),math.floor(pc.rgbaG(p)*0.85+0.5),math.floor(pc.rgbaB(p)*0.85+0.5),pc.rgbaA(p)))
end
grass:saveAs(root..'assets/grass.png')
local check=Image{fromFile=root..'assets/grass.png'}
assert(check:isEqual(grass))
dofile(root..'tools/tile_art/export_forest.lua')
local report=assert(io.open(app.fs.joinPath(app.fs.tempPath,'wall-mocks/forest-tone.txt'),'w'))
report:write(('%d foliage pixels darkened; trunks and alpha unchanged. Grass RGB reduced 15%%, alpha unchanged.\n'):format(changed))
report:write('Sources and previous PNGs backed up in assets/backup/; Desktop and assets/source sources updated.\n')
report:close()
