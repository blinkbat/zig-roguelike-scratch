local source=assert(app.params.source,'source=<owner edited PNG>')
local baseline=assert(app.params.baseline,'baseline=<unedited flattened PNG>')
local original=assert(app.params.original,'original=<layered template>')
local output=assert(app.params.output,'output=<updated Aseprite>')
local preview=assert(app.params.preview,'preview=<updated PNG>')
local report=assert(app.params.report,'report=<validation text>')
local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local layout=dofile(root..'tools/tile_art/water_cliff_layout.lua')
local names=dofile(root..'tools/tile_art/water_cliff_names.lua')
local owner=Image{fromFile=source}
local before=Image{fromFile=baseline}
assert(owner.width==layout.width and owner.height==layout.height)
assert(before.width==owner.width and before.height==owner.height)
local pc=app.pixelColor
local materials=dofile(root..'tools/tile_art/water_cliff_materials.lua')
local palette=materials.darken
local s=assert(app.open(original))
assert(s.width==owner.width and s.height==owner.height and #s.frames==1 and #s.slices==layout.slices,'Expected connected water template')
local flattened=Image(s.width,s.height,ColorMode.RGB)
flattened:drawSprite(s,1)
assert(flattened:isEqual(before),'Baseline differs from layered template')
local edits=Image(owner.width,owner.height,ColorMode.RGB)
local extrapolated=Image(owner.width,owner.height,ColorMode.RGB)
local final=Image(owner)
local changed,derived,extended=0,0,0
local top,bottom=layout.y,layout.y+layout.block-1
local left,right=layout.x,layout.x+layout.block-1
for y=0,owner.height-1 do
 for x=0,owner.width-1 do
  local p=owner:getPixel(x,y)
  if p~=before:getPixel(x,y) then edits:putPixel(x,y,p); changed=changed+1 end
 end
end
for y=top,bottom do
 for x=left,right do
  local p=owner:getPixel(x,y)
  if p~=before:getPixel(x,y) then
   local dx=x+layout.stride
   assert(owner:getPixel(dx,y)==before:getPixel(dx,y),'Preserve owner edits in middle set')
   local deep=palette[p] or p
   extrapolated:putPixel(dx,y,deep)
   final:putPixel(dx,y,deep)
   derived=derived+1
  end
 end
end
local function canvas(name)
 local layer=sourceFiles.layer(s,name) or error('Missing source layer '..name)
 return sourceFiles.canvas(s,assert(layer:cel(1)))
end
local shallow=canvas(names.layer(names.LAND_SHALLOWS,'faces'))
local deep=canvas(names.layer(names.LAND_DEEP,'faces'))
local surface=materials.surface
for band=0,layout.block//layout.cell-1 do
 for x=left,right do
  local foot=nil
  for y=top+band*layout.cell,top+band*layout.cell+layout.cell-1 do
   if pc.rgbaA(shallow:getPixel(x,y))>0 then foot=y end
  end
  if foot and owner:getPixel(x,foot)==surface and before:getPixel(x,foot)~=surface then
   local dx=x+layout.stride
   for y=foot+1,math.min(foot+16,bottom) do
    if pc.rgbaA(deep:getPixel(dx,y))==0 then break end
    assert(owner:getPixel(dx,y)==before:getPixel(dx,y),'Preserve owner edits in middle set')
    local p=palette[surface]
    extrapolated:putPixel(dx,y,p); final:putPixel(dx,y,p)
    extended=extended+1
   end
  end
 end
end
for _,part in ipairs({{name=names.owner,image=edits},{name=names.extended,image=extrapolated}}) do
 local l=s:newLayer(); l.name=part.name
 s:newCel(l,1,part.image,Point(0,0))
end
app.layer=s.layers[#s.layers]
local actual=Image(s.width,s.height,ColorMode.RGB)
actual:drawSprite(s,1)
assert(actual:isEqual(final),'Layered composite cannot preserve these pixel edits')
local outside=0
local middle=left+layout.stride
for y=0,owner.height-1 do
 for x=0,owner.width-1 do
  if x<middle or x>=middle+layout.block or y<top or y>bottom then
   assert(actual:getPixel(x,y)==owner:getPixel(x,y),'Changed outside middle set')
   outside=outside+1
  end
 end
end
local layerCount=#s.layers
local slices={}
for _,slice in ipairs(s.slices) do
 slices[slice.name]={x=slice.bounds.x,y=slice.bounds.y,width=slice.bounds.width,height=slice.bounds.height}
end
local stagedOutput=sourceFiles.stage(app.fs.fileName(output))
local stagedPreview=sourceFiles.stage('preview-'..app.fs.fileName(preview))
s:saveAs(stagedOutput)
s:close()
local saved=assert(app.open(stagedOutput))
assert(#saved.slices==layout.slices,'Slice layout changed')
assert(#saved.layers==layerCount,'Saved artwork layers changed')
for _,slice in ipairs(saved.slices) do
 local expected=assert(slices[slice.name],'Saved slice name changed')
 local bounds=slice.bounds
 assert(bounds.x==expected.x and bounds.y==expected.y and bounds.width==expected.width and bounds.height==expected.height,'Saved slice bounds changed')
end
local savedComposite=Image(saved.width,saved.height,ColorMode.RGB)
savedComposite:drawSprite(saved,1)
assert(savedComposite:isEqual(final),'Saved layered source differs from expected pixel edits')
saved:saveCopyAs(stagedPreview)
assert(Image{fromFile=stagedPreview}:isEqual(final),'Saved composite differs from expected pixel edits')
saved:close()
sourceFiles.keep(output,sourceFiles.work(),'edits',os.date(sourceFiles.STAMP))
sourceFiles.publish({sourceFiles.staged(output,stagedOutput),sourceFiles.staged(preview,stagedPreview)})
sourceFiles.write(report,string.format('Owner edit pixels preserved: %d; shallow edits transferred: %d; deep end pixels extended: %d; outside-middle pixels unchanged: %d. %d slices retained.\n',changed,derived,extended,outside,layout.slices))
