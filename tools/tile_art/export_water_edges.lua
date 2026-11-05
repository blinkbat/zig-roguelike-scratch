local source=assert(app.params.source,'source=<edited template PNG>')
local original=assert(app.params.original,'original=<canonical Aseprite>')
local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local BANK_LIFT=8
local report=assert(app.params.report,'report=<validation text>')
local s=assert(app.open(original))
assert(s.width==960 and s.height==640 and #s.frames==1,'Expected connected water template')
local baseline=Image(s.width,s.height,ColorMode.RGB)
local pc=app.pixelColor
local mask=Image{fromFile=root..'assets/water-cliff-cap.png'}
local water=Image{fromFile=root..'assets/shallows-ground.png'}
assert(mask.width==192 and mask.height==64 and water.width==256 and water.height==256,'Unexpected cap or water atlas dimensions')
local cap=Image(mask.width,mask.height,ColorMode.RGB)
for y=0,63 do
 for x=0,191 do
  if pc.rgbaA(mask:getPixel(x,y))>0 then cap:putPixel(x,y,water:getPixel(64+x%64,64+(y+32-BANK_LIFT)%64)) end
 end
end
for _,l in ipairs(s.layers) do
 if l.isVisible and l.name~='Owner flat border edits' and l.name~='Deep border extensions from shallow edits' then
  local c=l:cel(1)
  if c then baseline:drawImage(c.image,c.position,l.opacity) end
 end
end
local edited=Image{fromFile=source}
assert(edited.width==960 and edited.height==640)
local materials=dofile(root..'tools/tile_art/water_cliff_materials.lua')
local bands=materials.band
local names={'dirt-shallows-edges','dirt-water-edges','shallows-water-edges'}
local counts={}
local outputs={{image=cap,path=root..'assets/shallows-water-cap.png'}}
for n,name in ipairs(names) do
 local atlas=Image(#materials.bands*water.width,water.height,ColorMode.RGB)
 local x0=32+(n-1)*320
 local count=0
 for y=0,255 do
  for x=0,255 do
   local p=edited:getPixel(x0+x,104+y)
   if p~=baseline:getPixel(x0+x,104+y) then
    local band
    if n<3 and materials.dry[p] then band=bands.dry
    elseif n==1 and materials.shallow_face[p] then band=bands.shallow_face
    elseif n>1 and materials.deep_face[p] then band=bands.deep_face
    elseif materials.shallow[p] then band=bands.shallow
    elseif materials.deep[p] then band=bands.deep
    else error(string.format('Unclassified edited color at (%d,%d); assign its terrain material before export',x0+x,104+y)) end
    atlas:putPixel(x+band*water.width,y,p)
    count=count+1
   end
  end
 end
 assert(count>0,'Missing edits for '..name)
 local out=root..'assets/'..name..'.png'
 outputs[#outputs+1]={image=atlas,path=out}
 counts[#counts+1]=name..': '..count..' changed pixels'
end
s:close()
for _,out in ipairs(outputs) do
 out.image:saveAs(out.path)
 assert(Image{fromFile=out.path}:isEqual(out.image),'Export altered pixels')
end
local f=assert(io.open(report,'w'))
f:write(table.concat(counts,'\n')..'\nNative 64px masks; five material bands: dry, shallow surface, deep surface, shallow face, deep face. Original runtime terrain remains beneath unchanged pixels.\n')
f:close()
