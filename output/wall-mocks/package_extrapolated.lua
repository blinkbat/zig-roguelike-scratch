local root = 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/output/wall-mocks/'
local desktop = 'C:/Users/DavidBennett/Desktop/'
local sprite = app.open(desktop .. 'regular-walls.aseprite')
assert(sprite and sprite.width==512 and sprite.height==448)
local userLayer,drawLayer
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Layer 1' then userLayer=layer end
  if layer.name=='Draw here' then drawLayer=layer end
end
assert(userLayer and drawLayer)
local userCel = userLayer:cel(1)
local original = Image(userCel.image)
local originalPosition = Point(userCel.position)
local pc = app.pixelColor
local palette,seen = {},{}
for it in original:pixels() do
  local pixel=it()
  if pc.rgbaA(pixel)>0 and not seen[pixel] then
    seen[pixel]=true
    palette[#palette+1]={pixel,pc.rgbaR(pixel),pc.rgbaG(pixel),pc.rgbaB(pixel)}
  end
end
assert(#palette==7)
local generated=Image{fromFile=root .. 'regular-walls-extrapolated-source.png'}
generated:resize{width=512,height=448,method='nearest-neighbor'}
local cache={}
local occupied={}
for y=0,447 do
  for x=0,511 do
    local cell=math.floor(x/64)+8*math.floor((y-64)/64)+1
    local pixel=generated:getPixel(x,y)
    if y<64 or cell<=3 or cell>47 or pc.rgbaA(pixel)<160 then
      generated:putPixel(x,y,0)
    else
      local replacement=cache[pixel]
      if not replacement then
        local r,g,b=pc.rgbaR(pixel),pc.rgbaG(pixel),pc.rgbaB(pixel)
        local best=math.huge
        for _,color in ipairs(palette) do
          local distance=(r-color[2])^2+(g-color[3])^2+(b-color[4])^2
          if distance<best then best=distance; replacement=color[1] end
        end
        cache[pixel]=replacement
      end
      generated:putPixel(x,y,replacement)
      occupied[cell]=(occupied[cell] or 0)+1
    end
  end
end
for id=4,47 do assert(occupied[id] and occupied[id]>100,'Missing cell '..id) end
local layer=sprite:newLayer()
layer.name='Extrapolated walls - your 7-color palette'
sprite:newCel(layer,1,generated,Point(0,0))
layer.stackIndex=4
for _,existing in ipairs(sprite.layers) do
  if existing.name=='Underdrawing (25%)' or existing.name=='Exact connection guide (hidden)' then existing.isVisible=false end
end
drawLayer.stackIndex=#sprite.layers
app.layer=drawLayer
sprite.data=sprite.data .. '\nExtrapolated 44 remaining cells from the user-painted first three. User Layer 1 is preserved pixel-for-pixel. New work is on its own layer and uses the exact 7 original colors. Draw here remains empty on top. Review seams before game import.'
local destination=desktop .. 'regular-walls-extrapolated.aseprite'
local version=2
while app.fs.isFile(destination) do
  destination=desktop .. 'regular-walls-extrapolated-' .. version .. '.aseprite'
  version=version+1
end
sprite:saveAs(destination)
sprite:close()
local check=app.open(destination)
assert(check and check.width==512 and check.height==448 and #check.slices==47)
local checkedUser,checkedGenerated
for _,existing in ipairs(check.layers) do
  if existing.name=='Layer 1' then checkedUser=existing end
  if existing.name=='Extrapolated walls - your 7-color palette' then checkedGenerated=existing end
end
assert(checkedUser:cel(1).image:isEqual(original))
assert(checkedUser:cel(1).position==originalPosition)
local actual=Image(512,448,ColorMode.RGB)
actual:drawImage(checkedGenerated:cel(1).image,checkedGenerated:cel(1).position)
assert(actual:isEqual(generated))
assert(check.layers[#check.layers].name=='Draw here')
for _,slice in ipairs(check.slices) do assert(slice.bounds.width==64 and slice.bounds.height==64) end
check:saveCopyAs(root .. 'regular-walls-extrapolated-preview.png')
local report=assert(io.open(root .. 'extrapolated-validation.txt','w'))
report:write(destination .. '\nReopened successfully. 47 exact 64x64 slices. 44 new painted cells. Seven original colors. User pixels and their position unchanged. Separate new-art layer; Draw here is on top.\n')
report:close()
check:close()
