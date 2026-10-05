local root = 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/output/wall-mocks/'
local sprite = app.open('C:/Users/DavidBennett/Desktop/regular-walls.aseprite')
assert(sprite)
local report = assert(io.open(root .. 'user-walls-inspection.txt','w'))
report:write(string.format('Canvas %dx%d; %d layers; %d frames\n',sprite.width,sprite.height,#sprite.layers,#sprite.frames))
sprite:saveCopyAs(root .. 'user-walls-composite.png')
local drawings = {}
for i,layer in ipairs(sprite.layers) do
  report:write(string.format('%d: %s; visible=%s; opacity=%d\n',i,layer.name,tostring(layer.isVisible),layer.opacity))
  if layer.name=='Draw here' or layer.name=='Layer 1' then
    local canvas = Image(sprite.width,sprite.height,ColorMode.RGB)
    local cel = layer:cel(1)
    if cel then canvas:drawImage(cel.image,cel.position) end
    canvas:saveAs(root .. 'user-walls-drawing-' .. i .. '.png')
    if layer.name=='Layer 1' then
      local reference = Image(canvas,Rectangle(0,64,192,64))
      reference:resize(1536,512)
      reference:saveAs(root .. 'user-walls-style-reference.png')
    end
    for id=0,46 do
      local ink = 0
      for y=64+math.floor(id/8)*64,127+math.floor(id/8)*64 do
        for x=(id%8)*64,63+(id%8)*64 do
          if app.pixelColor.rgbaA(canvas:getPixel(x,y))>0 then ink=ink+1 end
        end
      end
      if ink>0 then report:write(string.format('Cell %02d: %d painted pixels\n',id+1,ink)) end
    end
  end
end
report:close()
sprite:close()
