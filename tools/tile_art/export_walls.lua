local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local path=app.params.source or sourceFiles.DESKTOP..'regular-walls.aseprite'
local pc=app.pixelColor
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
assert(#masks==47)
local W,H=masks.W,masks.H
local CELL=masks.CELL
local LAST=CELL-1
-- Brick courses under the cap's lower edge: 7 courses over the face's rows.
local FACE=masks.FACE
local sprite=assert(app.open(path))
assert(sprite.width==W and sprite.height==masks.SHEET_H)
local painted=sourceFiles.layer(sprite,'Layer 1')
local wall=dofile(root..'tools/tile_art/wall_strips.lua')(assert(painted,'no Layer 1'):cel(1).image,painted:cel(1).position,masks)
sprite:close()
local source,tan,sideRow,decorate=wall.source,wall.tan,wall.sideRow,wall.decorate
local brick,faceEdge,side,capTop,capCorner=wall.brick,wall.faceEdge,wall.side,wall.capTop,wall.capCorner
local EDGE,CAP=wall.EDGE,wall.CAP
local palette={}
for it in source:pixels() do if pc.rgbaA(it())>0 then palette[it()]=true end end
local dark=pc.rgba(84,15,0,255)
assert(palette[dark])
-- Face row by -> painted row: the cap's edge, the top mortar, courses alternating A (101) and B (104), the last C (107) with the foot.
local faceRows={99,100}
for k=1,6 do local s=(k%2==1) and 101 or 104; faceRows[#faceRows+1]=s; faceRows[#faceRows+1]=s+1; faceRows[#faceRows+1]=s+2 end
for _,r in ipairs({107,108,109}) do faceRows[#faceRows+1]=r end
assert(#faceRows==FACE)
local function tile(mask)
  local n,e,s,w,ne,se,sw,nw=masks.sides(mask)
  local image=Image(CELL,CELL,ColorMode.RGB)
  local foot=s and CELL or CELL-FACE
  for y=0,LAST do for x=0,LAST do
    local pixel=tan
    local d=LAST-x
    if y>=foot then
      local row=faceRows[y-foot+1]
      pixel=brick(x,row)
      if not w and x<EDGE then pixel=faceEdge(false,x,row) end
      if not e and d<EDGE then pixel=faceEdge(true,d,row) end
    else
      if not n and y<CAP then pixel=capTop(x,y) end
      if not w and x<EDGE then pixel=side(false,x,sideRow(y)) end
      if not e and d<EDGE then pixel=side(true,d,sideRow(y)) end
      if not n and y<CAP and not w and x<CAP then pixel=capCorner(false,x,y) end
      if not n and y<CAP and not e and d<CAP then pixel=capCorner(true,d,y) end
      -- Hand repair: the face beside a missing south corner meets this cap along an unbroken outline.
      if s and w and not sw and x==0 and y>=CELL-FACE-1 then pixel=dark end
      if s and e and not se and x==LAST and y>=CELL-FACE-1 then pixel=dark end
    end
    image:putPixel(x,y,pixel)
  end end
  decorate(image,function(x,y) return x>5 and x<58 and y>5 and y<foot-6 end,{{10,11},{40,13},{17,30},{44,36}})
  local function notch(east)
    for y=0,1 do for d=0,EDGE-1 do
      local pixel=side(east,d,80+y)
      if pc.rgbaA(pixel)>0 then image:putPixel(east and LAST-d or d,y,pixel) end
    end end
  end
  if n and w and not nw then notch(false) end
  if n and e and not ne then notch(true) end
  for it in image:pixels() do
    assert(pc.rgbaA(it())==0 or (pc.rgbaA(it())==255 and palette[it()]),'palette or alpha changed '..mask)
  end
  return image
end
local atlas=Image(W,H,ColorMode.RGB)
local cells={}
for i,mask in ipairs(masks) do
  local image=tile(mask)
  masks.checkJoined(image,mask,8,55)
  for _,other in ipairs(cells) do assert(not image:isEqual(other),'duplicate cell '..mask) end
  cells[#cells+1]=image
  atlas:drawImage(image,Point(masks.at(i)))
end
local runtime=Sprite(W,H,ColorMode.RGB)
runtime.layers[1].name='Runtime walls'
runtime:newCel(runtime.layers[1],1,atlas,Point(0,0))
runtime.data='Full-cell walls built from Desktop regular-walls.aseprite Layer 1 strips by tools/tile_art/export_walls.lua; cell i is mask i of wall_masks.lua.'
for i,mask in ipairs(masks) do
  local x,y=masks.at(i)
  local slice=runtime:newSlice(Rectangle(x,y,CELL,CELL))
  slice.name='mask '..mask
end
local png=sourceFiles.stagePng(atlas,root..'assets/walls/walls.png','Wall PNG export changed pixels or did not save')
local canonical=root..'assets/source/walls.aseprite'
local staged=sourceFiles.stage(app.fs.fileName(canonical))
runtime:saveAs(staged)
runtime:close()
local check=assert(app.open(staged))
sourceFiles.checkLayer(check,'Runtime walls',atlas,Point(0,0))
check:close()
sourceFiles.keep(canonical,sourceFiles.work(),'export',os.date(sourceFiles.STAMP))
sourceFiles.publish({sourceFiles.staged(canonical,staged),png})
