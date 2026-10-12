local template=app.params.template or 'C:/Users/DavidBennett/Desktop/cave-walls.aseprite'
local path=assert(app.params.out,'out=<new sheet.aseprite>')
local title=Image{fromFile=assert(app.params.title,'title=<header png>')}
assert(not app.fs.isFile(path),'already exists: '..path)
local sprite=assert(app.open(template))
local labels,drawing,ideas
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Labels - hide before export' then labels=layer end
  if layer.name=='Draw here' then drawing=layer end
  if layer.name=='Ideas - hide before export' then ideas=layer end
end
assert(labels and drawing)
local image=Image(labels:cel(1).image)
local at=labels:cel(1).position
for y=0,34 do for x=0,511 do image:putPixel(x-at.x,y-at.y,app.pixelColor.rgba(0,0,0,0)) end end
for y=0,34 do for x=0,511 do
  local p=title:getPixel(x,y)
  if app.pixelColor.rgbaA(p)>0 then image:putPixel(x-at.x,y-at.y,p) end
end end
labels:cel(1).image=image
labels:cel(1).position=at
if ideas then sprite:deleteLayer(ideas) end
drawing:cel(1).image=Image(sprite.width,sprite.height,ColorMode.RGB)
drawing:cel(1).position=Point(0,0)
sprite:saveAs(path)
sprite:close()
