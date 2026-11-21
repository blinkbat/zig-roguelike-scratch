local root=assert(app.params.root,'root=<repo with trailing slash>')
local work=assert(app.params.work,'work=<backup folder with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local layout=dofile(root..'tools/tile_art/water_cliff_layout.lua')
local names=dofile(root..'tools/tile_art/water_cliff_names.lua')
local stamp=os.date(sourceFiles.STAMP)
local HALF_HEIGHT='Shallow cliff - half height'
local PAINTED=8
local function unpinched(name) return 'Before shallow pinch'..names.SEP..name end
if app.params.shots then
 local shots=app.params.shots
 local block=Point(layout.x,layout.y)
 local s=assert(app.open(work..'water-cliff-connections.aseprite'))
 local replacements={}
 local function replace(name,im,at)
  local old=assert(sourceFiles.layer(s,name),'Missing original layer '..name)
  old.name=unpinched(name)
  old.isVisible=false
  local l=s:newLayer(); l.name=name
  s:newCel(l,1,im,at)
  replacements[name]={image=im,position=at}
 end
 for _,tag in ipairs({'bare','faces','caps'}) do
  replace(names.layer(names.LAND_SHALLOWS,tag),Image{fromFile=shots..'template-0-'..tag..'.png'},block)
 end
 local edits=sourceFiles.layer(s,names.owner)
 local owner=edits and sourceFiles.canvas(s,assert(edits:cel(1))) or Image(s.width,s.height,ColorMode.RGB)
 for y=block.y,block.y+layout.block-1 do for x=block.x,block.x+layout.block-1 do owner:putPixel(x,y,0) end end
 owner:drawImage(Image{fromFile=shots..'template-0-edges.png'},block)
 replace(names.owner,owner,Point(0,0))
 local preview=work..'updated-template.png'
 local width,height=s.width,s.height
 sourceFiles.keep(root..'assets/source/water-cliff-connections.aseprite',work,'pinch',stamp)
 s:saveAs(root..'assets/source/water-cliff-connections.aseprite')
 s:close()
 local saved=assert(app.open(root..'assets/source/water-cliff-connections.aseprite'))
 assert(saved.width==width and saved.height==height,'Saved sheet dimensions changed')
 for name,expected in pairs(replacements) do
  sourceFiles.checkLayer(saved,name,expected.image,expected.position)
  for _,layer in ipairs(saved.layers) do
   if layer.name==unpinched(name) then assert(not layer.isVisible,'Original layer was not hidden') end
  end
 end
 saved:saveCopyAs(preview)
 saved:close()
 local after=Image{fromFile=preview}
 local before=Image{fromFile=work..'desktop-before.png'}
 local expected=Image{fromFile=shots..'template-0.png'}
 for y=0,after.height-1 do for x=0,after.width-1 do
  local inside=x>=block.x and x<block.x+layout.block and y>=block.y and y<block.y+layout.block
  local p=inside and expected:getPixel(x-block.x,y-block.y) or before:getPixel(x,y)
  assert(after:getPixel(x,y)==p,'Unexpected connected-template change')
 end end
 return
end
local faces=Image{fromFile=assert(app.params.faces,'faces=<previous template-0-faces.png>')}
local pc=app.pixelColor
local function span(im,x,y0,height)
 local first,last
 for y=y0,y0+height-1 do
  if pc.rgbaA(im:getPixel(x,y))>0 then first=first or y; last=y end
 end
 return first,last
end
local function sample(top,foot,y)
 local height=foot-top+1
 local short=math.ceil(height/2)
 if y<top or y>=top+short then return nil end
 return short==1 and top or top+math.floor((y-top)*(height-1)/(short-1)+0.5)
end
local s=assert(app.open(work..'water-cliff-edge.aseprite'))
assert(not sourceFiles.layer(s,HALF_HEIGHT),'Already pinched; use the original backup')
local paint=sourceFiles.canvas(s,assert(s.layers[PAINTED]:cel(1)))
local compressed=Image(s.width,s.height,ColorMode.RGB)
local columns=0
for _,slice in ipairs(s.slices) do
 if slice.name:find(names.slice('shallow',''),1,true)==1 then
  local b=slice.bounds
  for x=b.x,b.x+b.width-1 do
   local top,foot=span(paint,x,b.y,b.height)
   if top then
    columns=columns+1
    for y=top,foot do
     local sy=sample(top,foot,y)
     if sy then compressed:putPixel(x,y,paint:getPixel(x,sy)) end
    end
   end
  end
 end
end
assert(columns>0)
local edges_png=names.edge_files[names.LAND_SHALLOWS]..'.png'
local old=Image{fromFile=work..edges_png}
local bands=#dofile(root..'tools/tile_art/water_cliff_materials.lua').bands
assert(faces.width==layout.block and faces.height==layout.block and old.width==bands*layout.block)
s.layers[PAINTED].isVisible=false
local l=s:newLayer(); l.name=HALF_HEIGHT
s:newCel(l,1,compressed,Point(0,0))
local width,height=s.width,s.height
sourceFiles.keep(root..'assets/source/water-cliff-edge.aseprite',work,'pinch',stamp)
s:saveAs(root..'assets/source/water-cliff-edge.aseprite')
s:close()
local saved=assert(app.open(root..'assets/source/water-cliff-edge.aseprite'))
assert(saved.width==width and saved.height==height,'Saved sheet dimensions changed')
sourceFiles.checkLayer(saved,HALF_HEIGHT,compressed,Point(0,0))
assert(not saved.layers[PAINTED].isVisible,'Original layer was not hidden')
saved:close()
local edges=Image(old)
for row=0,layout.block//layout.cell-1 do for x=0,layout.block-1 do
 local top,foot=span(faces,x,row*layout.cell,layout.cell)
 if top then
  for band=0,bands-1 do for y=top,foot do
   local sy=sample(top,foot,y)
   edges:putPixel(band*layout.block+x,y,sy and old:getPixel(band*layout.block+x,sy) or 0)
  end end
 end
end end
sourceFiles.keep(root..'assets/water/'..edges_png,work,'pinch',stamp)
sourceFiles.savePng(edges,root..'assets/water/'..edges_png)
local report=sourceFiles.report(work..'pinch.txt')
report:write(string.format('%d painted columns compressed to ceil(height/2), lip row and width preserved; endpoints sampled without smoothing. Original layer retained hidden. Matching face-span border edits compressed identically.\n',columns))
report:close()
