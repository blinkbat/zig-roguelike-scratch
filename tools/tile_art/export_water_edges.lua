local source=assert(app.params.source,'source=<edited template PNG>')
local original=assert(app.params.original,'original=<canonical Aseprite>')
local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local layout=dofile(root..'tools/tile_art/water_cliff_layout.lua')
local names=dofile(root..'tools/tile_art/water_cliff_names.lua')
local CELL=layout.cell
local BANK_LIFT=8
local report=assert(app.params.report,'report=<validation text>')
local s=assert(app.open(original))
assert(s.width==layout.width and s.height==layout.height and #s.frames==1,'Expected connected water template')
local baseline=Image(s.width,s.height,ColorMode.RGB)
local pc=app.pixelColor
local mask=Image{fromFile=root..'assets/water/water-cliff-cap.png'}
local water=Image{fromFile=root..'assets/ground/shallows-ground.png'}
assert(mask.width==3*CELL and mask.height==CELL and water.width==layout.block and water.height==layout.block,'Unexpected cap or water atlas dimensions')
local cap=Image(mask.width,mask.height,ColorMode.RGB)
for y=0,mask.height-1 do
 for x=0,mask.width-1 do
  if pc.rgbaA(mask:getPixel(x,y))>0 then cap:putPixel(x,y,water:getPixel(CELL+x%CELL,CELL+(y+CELL//2-BANK_LIFT)%CELL)) end
 end
end
local edges=' - '..names.label('edges')
for _,l in ipairs(s.layers) do
 if l.isVisible and l.name~=names.owner and l.name~=names.extended and l.name:sub(-#edges)~=edges then
  local c=l:cel(1)
  if c then baseline:drawImage(c.image,c.position,l.opacity) end
 end
end
local edited=Image{fromFile=source}
assert(edited.width==layout.width and edited.height==layout.height)
local materials=dofile(root..'tools/tile_art/water_cliff_materials.lua')
local bands=materials.band
local counts={}
local outputs={{image=cap,path=root..'assets/water/shallows-water-cap.png'}}
for n,name in ipairs(names.edge_files) do
 local atlas=Image(#materials.bands*water.width,water.height,ColorMode.RGB)
 local x0=layout.x+(n-1)*layout.stride
 local count=0
 for y=0,layout.block-1 do
  for x=0,layout.block-1 do
   local p=edited:getPixel(x0+x,layout.y+y)
   if p~=baseline:getPixel(x0+x,layout.y+y) then
    local band
    if n<3 and materials.dry[p] then band=bands.dry
    elseif n==1 and materials.shallow_face[p] then band=bands.shallow_face
    elseif n>1 and materials.deep_face[p] then band=bands.deep_face
    elseif materials.shallow[p] then band=bands.shallow
    elseif materials.deep[p] then band=bands.deep
    else error(string.format('Unclassified edited color at (%d,%d); assign its terrain material before export',x0+x,layout.y+y)) end
    atlas:putPixel(x+band*water.width,y,p)
    count=count+1
   end
  end
 end
 assert(count>0,'Missing edits for '..name)
 local out=root..'assets/water/'..name..'.png'
 outputs[#outputs+1]={image=atlas,path=out}
 counts[#counts+1]=name..': '..count..' changed pixels'
end
s:close()
for _,out in ipairs(outputs) do sourceFiles.savePng(out.image,out.path,'Export altered pixels') end
sourceFiles.write(report,table.concat(counts,'\n')..'\nNative '..CELL..'px masks; five material bands: dry, shallow surface, deep surface, shallow face, deep face. Original runtime terrain remains beneath unchanged pixels.\n')
