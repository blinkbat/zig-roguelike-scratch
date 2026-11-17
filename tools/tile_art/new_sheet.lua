local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local template=app.params.template or sourceFiles.DESKTOP..'cave-walls.aseprite'
local path=assert(app.params.out,'out=<new sheet.aseprite>')
local title=Image{fromFile=assert(app.params.title,'title=<header png>')}
assert(not app.fs.isFile(path),'already exists: '..path)
local sprite=assert(app.open(template))
local labels=sourceFiles.layer(sprite,'Labels - hide before export')
local drawing=sourceFiles.layer(sprite,'Draw here')
local ideas=sourceFiles.layer(sprite,'Ideas - hide before export')
assert(labels and drawing)
local image=Image(sprite.width,sprite.height,ColorMode.RGB)
local cel=assert(labels:cel(1))
image:drawImage(cel.image,cel.position)
for y=0,34 do for x=0,511 do image:putPixel(x,y,app.pixelColor.rgba(0,0,0,0)) end end
for y=0,34 do for x=0,511 do
  local p=title:getPixel(x,y)
  if app.pixelColor.rgbaA(p)>0 then image:putPixel(x,y,p) end
end end
labels:cel(1).image=image
labels:cel(1).position=Point(0,0)
if ideas then sprite:deleteLayer(ideas) end
drawing:cel(1).image=Image(sprite.width,sprite.height,ColorMode.RGB)
drawing:cel(1).position=Point(0,0)
sprite:saveAs(path)
sprite:close()
local saved=assert(app.open(path),'New sheet was not saved')
local saved_labels=sourceFiles.layer(saved,'Labels - hide before export')
local saved_cel=assert(saved_labels and saved_labels:cel(1),'New sheet labels missing')
local actual=Image(saved.width,saved.height,ColorMode.RGB)
actual:drawImage(saved_cel.image,saved_cel.position)
assert(actual:isEqual(image),'New sheet labels changed')
saved:close()
