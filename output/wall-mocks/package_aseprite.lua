local root = 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/output/wall-mocks/'
local desktop = 'C:/Users/DavidBennett/Desktop/'
local sets = {
  {name='regular-walls', image='regular-connections.png', reference='regular-walls-mock.png'},
  {name='forest-tree-walls', image='forest-connections.png', reference='forest-walls-mock.png'},
  {name='cave-walls', image='cave-connections.png'}
}
local report = assert(io.open(root .. 'aseprite-validation.txt', 'w'))
for _, item in ipairs(sets) do
  local sprite = app.open(root .. item.image)
  assert(sprite and sprite.width == 1536 and sprite.height == 1024)
  local art = sprite.layers[1]
  art.name = 'Artwork - 47 connection mocks'
  local guide = sprite:newLayer()
  guide.name = 'Exact connection guide (hidden)'
  sprite:newCel(guide, 1, Image{fromFile=root .. 'connections-guide.png'}, Point(0,0))
  guide.isVisible = false
  if item.reference then
    local reference = sprite:newLayer()
    reference.name = 'Assembled wall reference (hidden)'
    sprite:newCel(reference, 1, Image{fromFile=root .. item.reference}, Point(0,0))
    reference.isVisible = false
  end
  for index=0,46 do
    local slice = sprite:newSlice(Rectangle((index % 8)*192, 90+math.floor(index/8)*148, 192,148))
    slice.name = string.format('Connection %02d',index+1)
  end
  sprite.data = 'Grayscale outlined concept mocks generated with image_gen. 47 patterns: 1 isolated, 4 ends, 2 straights, 8 corner variants, 16 T variants, 16 four-way variants. Guide layer preserves exact topology. These are concept sheets, not seam-validated production tile atlases.'
  app.layer = art
  local destination = desktop .. item.name .. '.aseprite'
  assert(not app.fs.isFile(destination), 'Destination already exists: ' .. destination)
  sprite:saveAs(destination)
  sprite:close()
  local reopened = app.open(destination)
  assert(reopened and reopened.width == 1536 and reopened.height == 1024)
  assert(#reopened.slices == 47)
  assert(#reopened.layers == (item.reference and 3 or 2))
  assert(reopened.layers[1].isVisible)
  assert(not reopened.layers[2].isVisible)
  reopened:saveCopyAs(root .. item.name .. '-verified.png')
  report:write(item.name .. '.aseprite: reopened successfully; 47 named slices; ' .. #reopened.layers .. ' layers; 1536x1024\n')
  report:flush()
  reopened:close()
end
report:close()
