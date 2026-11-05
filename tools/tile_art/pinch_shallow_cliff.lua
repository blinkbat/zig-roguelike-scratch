local root=assert(app.params.root,'root=<repo with trailing slash>')
local work=assert(app.params.work,'work=<backup folder with trailing slash>')
if app.params.shots then
 local shots=app.params.shots
 local s=assert(app.open(work..'water-cliff-connections.aseprite'))
 local function replace(name,im,at)
  local old
  for _,l in ipairs(s.layers) do if l.name==name then old=l break end end
  assert(old,'Missing original layer '..name)
  old.name='Before shallow pinch - '..name
  old.isVisible=false
  local l=s:newLayer(); l.name=name
  s:newCel(l,1,im,at)
 end
 for i,name in ipairs({'Ground','Cliff faces','Lip and cap fill'}) do
  replace('Land to shallows - '..name,Image{fromFile=shots..'template-0-layer-'..i..'.png'},Point(32,104))
 end
 local owner=Image(s.width,s.height,ColorMode.RGB)
 for _,l in ipairs(s.layers) do
  if l.name=='Owner flat border edits' then
   local c=assert(l:cel(1)); owner:drawImage(c.image,c.position)
  end
 end
 for y=104,359 do for x=32,287 do owner:putPixel(x,y,0) end end
 owner:drawImage(Image{fromFile=shots..'template-0-layer-4.png'},Point(32,104))
 replace('Owner flat border edits',owner,Point(0,0))
 local preview=work..'updated-template.png'
 s:saveAs(root..'assets/source/water-cliff-connections.aseprite')
 s:saveCopyAs(preview)
 s:close()
 local after=Image{fromFile=preview}
 local before=Image{fromFile=work..'desktop-before.png'}
 local expected=Image{fromFile=shots..'template-0.png'}
 for y=0,after.height-1 do for x=0,after.width-1 do
  local p=x>=32 and x<288 and y>=104 and y<360 and expected:getPixel(x-32,y-104) or before:getPixel(x,y)
  assert(after:getPixel(x,y)==p,'Unexpected connected-template change')
 end end
 return
end
local faces=Image{fromFile=assert(app.params.faces,'faces=<previous template-0-layer-2.png>')}
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
for _,l in ipairs(s.layers) do assert(l.name~='Shallow cliff - half height','Already pinched; use the original backup') end
local source=assert(s.layers[8]:cel(1))
local paint=Image(s.width,s.height,ColorMode.RGB)
paint:drawImage(source.image,source.position)
local compressed=Image(s.width,s.height,ColorMode.RGB)
local columns=0
for _,slice in ipairs(s.slices) do
 if slice.name:match('^water_cliff_shallow_') then
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
s.layers[8].isVisible=false
local l=s:newLayer(); l.name='Shallow cliff - half height'
s:newCel(l,1,compressed,Point(0,0))
s:saveAs(root..'assets/source/water-cliff-edge.aseprite')
s:close()
local old=Image{fromFile=work..'dirt-shallows-edges.png'}
local edges=Image(old)
assert(faces.width==256 and faces.height==256 and old.width==1280)
for row=0,3 do for x=0,255 do
 local top,foot=span(faces,x,row*64,64)
 if top then
  for band=0,4 do for y=top,foot do
   local sy=sample(top,foot,y)
   edges:putPixel(band*256+x,y,sy and old:getPixel(band*256+x,sy) or 0)
  end end
 end
end end
edges:saveAs(root..'assets/water/dirt-shallows-edges.png')
assert(Image{fromFile=root..'assets/water/dirt-shallows-edges.png'}:isEqual(edges))
local report=assert(io.open(work..'pinch.txt','w'))
report:write(string.format('%d painted columns compressed to ceil(height/2), lip row and width preserved; endpoints sampled without smoothing. Original layer retained hidden. Matching face-span border edits compressed identically.\n',columns))
report:close()
