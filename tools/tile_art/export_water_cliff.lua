local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local CELL=dofile(root..'tools/tile_art/water_cliff_layout.lua').cell
local source=app.params.source or sourceFiles.DESKTOP..'water-cliff-edge.aseprite'
local depth=app.params.depth or 'shallow'
assert(depth=='shallow' or depth=='deep','depth=shallow|deep')
local out=app.params.out or root..'assets/water/'..(depth=='shallow' and 'shallows' or 'water')..'-cliff.png'
assert(out:lower():match('%.png$'),'out must name a PNG file')
local stem=out:sub(1,-5)
local layer_name=assert(app.params.layer,'layer=<painted layer index or name>')
local s=assert(app.open(source))
local layer=assert(s.layers[tonumber(layer_name) or 0] or sourceFiles.layer(s,layer_name),'painted layer missing')
local cel=assert(layer:cel(1),'painted cel missing')
assert(layer.opacity==255 and cel.opacity==255,'paint must be full opacity')
local paint=Image(s.width,s.height,ColorMode.RGB)
paint:drawImage(cel.image,cel.position)
local names={'left','repeat','right'}
local atlas=Image(#names*CELL,CELL,ColorMode.RGB)
local pieces={}
for i,name in ipairs(names) do
 local bounds
 for _,slice in ipairs(s.slices) do
  if slice.name=='water_cliff_'..depth..'_'..name then bounds=slice.bounds end
 end
 assert(bounds and bounds.width==CELL and bounds.height==CELL,CELL..'px '..depth..' slice missing: '..name)
 local tile=Image(paint,bounds)
 assert(not tile:isEmpty(),'unpainted '..depth..' tile: '..name)
 atlas:drawImage(tile,Point((i-1)*CELL,0))
 pieces[i]=tile
end
local cap=Image(atlas.width,atlas.height,ColorMode.RGB)
local pc=app.pixelColor
for x=0,191 do
 for y=0,63 do
  if pc.rgbaA(atlas:getPixel(x,y))>0 then
   for above=0,y-1 do cap:putPixel(x,above,pc.rgba(255,255,255,255)) end
   break
  end
 end
end
local taper=depth=='shallow' and 4 or 8
for _,piece in ipairs({{x=0,left=true},{x=128,left=false}}) do
 local head,start,foot,tip
 for y=0,63 do
  local edge
  for step=0,63 do
   local x=piece.left and step or 63-step
   if pc.rgbaA(atlas:getPixel(piece.x+x,y))>0 then edge=x break end
  end
  if edge then
   edge=piece.left and math.min(edge,32) or math.max(edge,31)
   if not head then head,start=y,edge end
   foot,tip=y,edge
   local first=piece.left and 0 or edge+1
   local last=piece.left and edge-1 or 63
   for x=first,last do cap:putPixel(piece.x+x,y,pc.rgba(255,255,255,255)) end
  end
 end
 for y=0,head-1 do
  local first=piece.left and 0 or start+1
  local last=piece.left and start-1 or 63
  for x=first,last do cap:putPixel(piece.x+x,y,pc.rgba(255,255,255,255)) end
 end
 for step=1,taper do
  local y=foot+step
  if y<64 then
   local edge=piece.left and tip-step or tip+step
   local first=piece.left and 0 or edge+1
   local last=piece.left and edge-1 or 63
   for x=math.max(0,first),math.min(63,last) do cap:putPixel(piece.x+x,y,pc.rgba(255,255,255,255)) end
  end
 end
end
local feet={}
local lips={}
for x=0,191 do
 local foot=0
 local lip=0
 for y=0,63 do
  if pc.rgbaA(atlas:getPixel(x,y))>0 then
   if foot==0 then lip=y end
   foot=y+1
  end
 end
 feet[#feet+1]=tostring(foot)
 lips[#lips+1]=tostring(lip)
end
sourceFiles.write(stem..'-foot.txt',table.concat(feet,',')..'\n')
sourceFiles.write(stem..'-lip.txt',table.concat(lips,',')..'\n')
sourceFiles.savePng(cap,stem..'-cap.png','cap mask changed')
local back=sourceFiles.savePng(atlas,out,'export changed pixels')
for i,tile in ipairs(pieces) do
 assert(Image(back,Rectangle((i-1)*CELL,0,CELL,CELL)):isEqual(tile),'source tile changed')
end
s:close()
print('Verified '..depth..' cliff: three original 64px crops, unchanged RGBA, no guides or reference tiles')
