local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local path=app.params.source or root..'assets/source/forest-tree-walls.aseprite'
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local work=sourceFiles.work()
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
local sprite=assert(app.open(path))
assert(sprite.width==masks.W and sprite.height==masks.SHEET_H and #sprite.frames==1 and #sprite.slices==#masks)
local combined=Image(masks.W,masks.SHEET_H,ColorMode.RGB)
local layers=0
for _,layer in ipairs(sprite.layers) do
  if layer.name==sourceFiles.LAYER.draw or layer.name==sourceFiles.LAYER.forest then
    local cel=assert(layer:cel(1))
    assert(layer.opacity==255 and cel.opacity==255)
    combined:drawImage(cel.image,cel.position)
    layers=layers+1
  end
end
assert(layers==2,'Expected the original painting and its extensions')
local atlas=Image(combined,Rectangle(0,masks.HEAD,masks.W,masks.H))
local pixels=0
for i,mask in ipairs(masks) do
  local x,y=masks.at(i)
  local count=0
  for yy=0,masks.CELL-1 do for xx=0,masks.CELL-1 do
    local a=app.pixelColor.rgbaA(atlas:getPixel(x+xx,y+yy))
    assert(a==0 or a==255,'Partial alpha in mask '..mask)
    if a>0 then count=count+1 end
  end end
  assert(count>0,'Empty mask '..mask)
  pixels=pixels+count
end
local unusedX,unusedY=masks.at(#masks+1)
for y=unusedY,unusedY+masks.CELL-1 do for x=unusedX,unusedX+masks.CELL-1 do assert(app.pixelColor.rgbaA(atlas:getPixel(x,y))==0,'Unused cell painted') end end
sourceFiles.publish({sourceFiles.stagePng(atlas,root..'assets/walls/forest-tree-walls.png','Export changed the visible artwork')})
sprite:close()
local report=sourceFiles.report(work..'forest-tree-walls-export.txt')
report:write(('%d cells exported, %dx%d each, %d opaque pixels; unused cell clear.\n'):format(#masks,masks.CELL,masks.CELL,pixels))
report:write('Only Draw here and Forest extensions; PNG pixels verified after reopening.\nSource: '..path..'\n')
report:close()
