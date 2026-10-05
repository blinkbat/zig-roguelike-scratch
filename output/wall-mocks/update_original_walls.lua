local root='C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/output/wall-mocks/'
local path='C:/Users/DavidBennett/Desktop/regular-walls.aseprite'
local corrected=app.open('C:/Users/DavidBennett/Desktop/regular-walls-pixel.aseprite')
local patch
for _,layer in ipairs(corrected.layers) do
  if layer.name=='Pixel extension - copied colors, chips and bricks' then
    patch=Image(512,448,ColorMode.RGB)
    patch:drawImage(layer:cel(1).image,layer:cel(1).position)
  end
end
assert(patch)
corrected:close()
local sprite=app.open(path)
assert(sprite and sprite.width==512 and sprite.height==448)
sprite:saveCopyAs(root..'regular-walls-before-pixel-extension-'..os.date('%Y%m%d-%H%M%S')..'.aseprite')
local authored,drawing
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Layer 1' then authored=layer end
  if layer.name=='Draw here' then drawing=layer end
end
assert(authored and drawing)
local before=Image(authored:cel(1).image)
local at=Point(authored:cel(1).position)
local extension=sprite:newLayer()
extension.name='Pixel extension - copied colors, chips and bricks'
sprite:newCel(extension,1,patch,Point(0,0))
extension.stackIndex=4
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Underdrawing (25%)' or layer.name=='Exact connection guide (hidden)' then layer.isVisible=false end
end
drawing.stackIndex=#sprite.layers
app.layer=drawing
sprite.data='Native pixel extension from your painted Layer 1. No generated artwork, resizing, antialiasing or palette conversion. Your original layer remains unchanged; the extension is on its own layer. Grid and labels are separate. 47 64x64 cells.'
sprite:saveAs(path)
sprite:close()
local check=app.open(path)
local count=0
for _,layer in ipairs(check.layers) do
  if layer.name=='Layer 1' then assert(layer:cel(1).image:isEqual(before) and layer:cel(1).position==at) end
  if layer.name=='Pixel extension - copied colors, chips and bricks' then count=count+1 end
end
assert(count==1 and #check.slices==47)
check:saveCopyAs(root..'regular-walls-current.png')
local report=assert(io.open(root..'original-updated.txt','w'))
report:write('Updated '..path..'\nReopened and verified: original painted layer unchanged; native pixel extension present; 47 slices.\n')
report:close()
check:close()
