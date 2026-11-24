local source=assert(app.params.source,'source=<edited template PNG>')
local original=assert(app.params.original,'original=<canonical Aseprite>')
local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local layout=dofile(root..'tools/tile_art/water_cliff_layout.lua')
local names=dofile(root..'tools/tile_art/water_cliff_names.lua')
local groundPort=dofile(root..'tools/tile_art/ground_port.lua')
local CELL=layout.cell
local BANK_LIFT=8
local report=assert(app.params.report,'report=<validation text>')
local s=assert(app.open(original))
assert(s.width==layout.width and s.height==layout.height and #s.frames==1,'Expected connected water template')
local baseline=Image(s.width,s.height,ColorMode.RGB)
local pc=app.pixelColor
local mask=Image{fromFile=root..'assets/water/'..names.faceFile('deep')..'-cap.png'}
local water=Image{fromFile=root..groundPort.png('shallows')}
assert(mask.width==#names.pieces*CELL and mask.height==CELL and water.width==layout.block and water.height==layout.block,'Unexpected cap or water atlas dimensions')
local fillX,fillY=groundPort.fill(dofile(root..'tools/tile_art/ground_corners.lua'))
local cap=Image(mask.width,mask.height,ColorMode.RGB)
for y=0,mask.height-1 do
 for x=0,mask.width-1 do
  if pc.rgbaA(mask:getPixel(x,y))>0 then cap:putPixel(x,y,water:getPixel(fillX+x%CELL,fillY+(y+CELL//2-BANK_LIFT)%CELL)) end
 end
end
local edges=names.SEP..names.label('edges')
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
 local face=names.face[n]
 local count=0
 for y=0,layout.block-1 do
  for x=0,layout.block-1 do
   local p=edited:getPixel(x0+x,layout.y+y)
   if p~=baseline:getPixel(x0+x,layout.y+y) then
    local band
    if names.dry[n] and materials.dry[p] then band=bands.dry
    elseif materials[face][p] then band=bands[face]
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
local staged={}
for _,out in ipairs(outputs) do staged[#staged+1]=sourceFiles.stagePng(out.image,out.path,'Export altered pixels') end
staged[#staged+1]={path=report,bytes=table.concat(counts,'\n')..'\nNative '..CELL..'px masks; five material bands: dry, shallow surface, deep surface, shallow face, deep face. Original runtime terrain remains beneath unchanged pixels.\n'}
sourceFiles.publish(staged)
