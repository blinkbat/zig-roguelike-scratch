local source=assert(app.params.source,'source=<owner edited PNG>')
local baseline=assert(app.params.baseline,'baseline=<unedited flattened PNG>')
local original=assert(app.params.original,'original=<layered template>')
local output=assert(app.params.output,'output=<updated Aseprite>')
local preview=assert(app.params.preview,'preview=<updated PNG>')
local report=assert(app.params.report,'report=<validation text>')
local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local owner=Image{fromFile=source}
local before=Image{fromFile=baseline}
assert(owner.width==960 and owner.height==640)
assert(before.width==owner.width and before.height==owner.height)
local pc=app.pixelColor
local rgba=pc.rgba
local palette=dofile(root..'tools/tile_art/water_cliff_materials.lua').darken
local s=assert(app.open(original))
assert(s.width==owner.width and s.height==owner.height and #s.frames==1 and #s.slices==54,'Expected connected water template')
local flattened=Image(s.width,s.height,ColorMode.RGB)
flattened:drawSprite(s,1)
assert(flattened:isEqual(before),'Baseline differs from layered template')
local edits=Image(owner.width,owner.height,ColorMode.RGB)
local extrapolated=Image(owner.width,owner.height,ColorMode.RGB)
local final=Image(owner)
local changed,derived,extended=0,0,0
for y=0,owner.height-1 do
 for x=0,owner.width-1 do
  local p=owner:getPixel(x,y)
  if p~=before:getPixel(x,y) then edits:putPixel(x,y,p); changed=changed+1 end
 end
end
for y=104,359 do
 for x=32,287 do
  local p=owner:getPixel(x,y)
  if p~=before:getPixel(x,y) then
   local dx=x+320
   assert(owner:getPixel(dx,y)==before:getPixel(dx,y),'Preserve owner edits in middle set')
   local deep=palette[p] or p
   extrapolated:putPixel(dx,y,deep)
   final:putPixel(dx,y,deep)
   derived=derived+1
  end
 end
end
local function canvas(name)
 for _,l in ipairs(s.layers) do
  if l.name==name then
   local im=Image(s.width,s.height,ColorMode.RGB)
   local c=assert(l:cel(1)); im:drawImage(c.image,c.position)
   return im
  end
 end
 error('Missing source layer '..name)
end
local shallow=canvas('Land to shallows - Cliff faces')
local deep=canvas('Land to deep water - Cliff faces')
local surface=rgba(119,146,185,255)
for band=0,3 do
 for x=32,287 do
  local foot=nil
  for y=104+band*64,167+band*64 do
   if pc.rgbaA(shallow:getPixel(x,y))>0 then foot=y end
  end
  if foot and owner:getPixel(x,foot)==surface and before:getPixel(x,foot)~=surface then
   for y=foot+1,math.min(foot+16,359) do
    if pc.rgbaA(deep:getPixel(x+320,y))==0 then break end
    assert(owner:getPixel(x+320,y)==before:getPixel(x+320,y),'Preserve owner edits in middle set')
    local p=palette[surface]
    extrapolated:putPixel(x+320,y,p); final:putPixel(x+320,y,p)
    extended=extended+1
   end
  end
 end
end
for _,part in ipairs({{name='Owner flat border edits',image=edits},{name='Deep border extensions from shallow edits',image=extrapolated}}) do
 local l=s:newLayer(); l.name=part.name
 s:newCel(l,1,part.image,Point(0,0))
end
app.layer=s.layers[#s.layers]
local actual=Image(s.width,s.height,ColorMode.RGB)
actual:drawSprite(s,1)
assert(actual:isEqual(final),'Layered composite cannot preserve these pixel edits')
local outside=0
for y=0,owner.height-1 do
 for x=0,owner.width-1 do
  if x<352 or x>=608 or y<104 or y>=360 then
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
s:saveAs(output)
s:close()
local saved=assert(app.open(output))
assert(#saved.slices==54,'Slice layout changed')
assert(#saved.layers==layerCount,'Saved artwork layers changed')
for _,slice in ipairs(saved.slices) do
 local expected=assert(slices[slice.name],'Saved slice name changed')
 local bounds=slice.bounds
 assert(bounds.x==expected.x and bounds.y==expected.y and bounds.width==expected.width and bounds.height==expected.height,'Saved slice bounds changed')
end
local savedComposite=Image(saved.width,saved.height,ColorMode.RGB)
savedComposite:drawSprite(saved,1)
assert(savedComposite:isEqual(final),'Saved layered source differs from expected pixel edits')
saved:saveCopyAs(preview)
assert(Image{fromFile=preview}:isEqual(final),'Saved composite differs from expected pixel edits')
saved:close()
local f=assert(io.open(report,'w'))
f:write(string.format('Owner edit pixels preserved: %d; shallow edits transferred: %d; deep end pixels extended: %d; outside-middle pixels unchanged: %d. 54 slices retained.\n',changed,derived,extended,outside))
f:close()
