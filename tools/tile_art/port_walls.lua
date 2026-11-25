local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local path=app.params.source or sourceFiles.DESKTOP..'regular-walls.aseprite'
local work=sourceFiles.work()
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
local bit=masks.bit
local CELL,LAST=masks.CELL,masks.CELL-1
local sprite=assert(app.open(path))
assert(sprite.width==masks.W and sprite.height==masks.SHEET_H)
local authored=sourceFiles.layer(sprite,sourceFiles.LAYER.original)
local extension=sourceFiles.layer(sprite,'Pixel extension - copied colors, chips and bricks') or sourceFiles.layer(sprite,sourceFiles.LAYER.ported)
local drawing=sourceFiles.layer(sprite,sourceFiles.LAYER.draw)
assert(authored and extension and drawing)
local original=Image(authored:cel(1).image)
local position=Point(authored:cel(1).position)
local wall=dofile(root..'tools/tile_art/wall_strips.lua')(original,position,masks)
local source,tan,sample,sideRow,decorate=wall.source,wall.tan,wall.sample,wall.sideRow,wall.decorate
local brick,faceEdge,side,capTop,capCorner=wall.brick,wall.faceEdge,wall.side,wall.capTop,wall.capCorner
local EDGE,CAP=wall.EDGE,wall.CAP
local bits={{bit.nw,bit.n,bit.ne},{bit.w,0,bit.e},{bit.sw,bit.s,bit.se}}
local function blob(mask)
  local image=Image(CELL,CELL,ColorMode.RGB)
  local function inside(x,y)
    if x<0 or y<0 or x>LAST or y>LAST then return false end
    local col=x<19 and 1 or x>44 and 3 or 2
    local row=y<19 and 1 or y>45 and 3 or 2
    return (col==2 and row==2) or ((mask & bits[row][col])~=0)
  end
  local low={}
  for x=0,LAST do
    low[x]=-1
    for y=0,LAST do if inside(x,y) then low[x]=y end end
  end
  local function cap(x,y)
    return inside(x,y) and (low[x]==LAST or y<=low[x]-11)
  end
  for y=0,LAST do for x=0,LAST do
    if inside(x,y) then
      local pixel=tan
      local left,right,top=0,LAST,0
      for a=x,0,-1 do if not inside(a,y) then left=a+1; break end end
      for a=x,LAST do if not inside(a,y) then right=a-1; break end end
      for a=y,0,-1 do if not inside(x,a) then top=a+1; break end end
      local dx,ex,dy=x-left,right-x,y-top
      if not cap(x,y) then
        local row=wall.FACE_TOP+y-low[x]+10
        pixel=brick(x,row)
        if left>0 and dx<EDGE then pixel=faceEdge(false,dx,row) end
        if right<LAST and ex<EDGE then pixel=faceEdge(true,ex,row) end
      else
        if top>0 and dy<CAP then pixel=capTop(x,dy) end
        if left>0 and dx<EDGE then pixel=side(false,dx,sideRow(y)) end
        if right<LAST and ex<EDGE then pixel=side(true,ex,sideRow(y)) end
        if top>0 and dy<CAP and left>0 and dx<CAP then pixel=capCorner(false,dx,dy) end
        if top>0 and dy<CAP and right<LAST and ex<CAP then pixel=capCorner(true,ex,dy) end
      end
      image:putPixel(x,y,pixel)
    end
  end end
  decorate(image,cap,{{24,23},{5,7},{43,7},{8,43},{41,44}})
  return image
end
local completed=Image(masks.W,masks.SHEET_H,ColorMode.RGB)
local blobs={}
for i,mask in ipairs(masks) do
  blobs[i]=blob(mask)
  if i>3 then completed:drawImage(blobs[i],Point(masks.sheetAt(i))) end
end
local repairX,repairY=masks.sheetAt(2)
for x=0,LAST do completed:putPixel(repairX+x,repairY,sample(64+x,65)) end
local authoredSheet=Image(completed)
authoredSheet:drawImage(source,Point(0,0))
local references={}
for i,mask in ipairs(masks) do
  local tile=Image(CELL,CELL,ColorMode.RGB)
  local ox,oy=masks.sheetAt(i)
  for y=0,LAST do for x=0,LAST do tile:putPixel(x,y,authoredSheet:getPixel(ox+x,oy+y)) end end
  for _,other in ipairs(references) do assert(not tile:isEqual(other),'duplicate authoring cell '..i) end
  masks.checkJoined(tile,mask,23,40)
  references[#references+1]=tile
end
sourceFiles.backup(path,work..'regular-walls-before-ported-edges-'..os.date(sourceFiles.STAMP)..'.aseprite')
extension.name=sourceFiles.LAYER.ported
extension:cel(1).image=completed
extension:cel(1).position=Point(0,0)
drawing.stackIndex=#sprite.layers
app.layer=drawing
sprite:saveAs(path)
sprite:saveCopyAs(work..'regular-walls-current.png')
sprite:close()
local reopened=assert(app.open(path))
assert(reopened.width==masks.W and reopened.height==masks.SHEET_H,'Saved sheet dimensions changed')
sourceFiles.checkLayer(reopened,sourceFiles.LAYER.ported,completed,Point(0,0))
sourceFiles.checkCel(reopened,sourceFiles.LAYER.original,original,position)
assert(#reopened.slices==#masks)
reopened:close()
dofile(root..'tools/tile_art/export_walls.lua')
local report=sourceFiles.report(work..'ported-pixel-validation.txt')
report:write('Original painted layer and position unchanged after reopening.\n47 distinct authoring cells; 44 extensions use copied uneven edge strips.\nAll declared cardinal connections have continuous opaque central coverage.\nCell 02 north boundary repaired with a copy of its first painted row beneath the original layer.\nexport_walls.lua built all 47 cells from Layer 1 strips into assets/walls/walls.png; binary alpha.\nNo resampling, rotation, mirroring or image generation.\n')
report:close()
