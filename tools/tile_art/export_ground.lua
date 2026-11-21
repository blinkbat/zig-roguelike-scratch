-- A ground template's painting, its 4x4 block alone, as the game's sheet: assets/ground/<name>-ground.png, which src/gfx/ground.zig reads.
-- params: name=grass|cobble|dirt|water|shallows|bridge [source=<sheet.aseprite>] [out=<png>] [from=underdrawing, a stand-in, only with out=]
local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local groundPort=dofile(root..'tools/tile_art/ground_port.lua')
local name=assert(app.params.name,'name=grass|cobble|dirt|water|shallows|bridge')
local source_name=groundPort.source(name)
local source=app.params.source or (sourceFiles.DESKTOP..source_name..'.aseprite')
local stand_in=app.params.from=='underdrawing'
assert(app.params.from==nil or stand_in,'from=underdrawing or nothing')
assert(not stand_in or app.params.out,'a stand-in never goes into assets/: give out=')
local out=app.params.out or (root..'assets/ground/'..name..'-ground.png')
if stand_in then
  local function normalized(path)
    local windows=app.fs.pathSeparator=='\\'
    local value=path:gsub('\\','/')
    local cwd=app.fs.currentPath:gsub('\\','/')
    if windows then
      assert(not value:match('^%a:') or value:match('^%a:/'),'Use an absolute path instead of a drive-relative path')
      if value:sub(1,1)=='/' and value:sub(1,2)~='//' then
        value=assert(cwd:match('^%a:'),'Current directory has no drive')..value
      elseif not value:match('^%a:/') and value:sub(1,2)~='//' then value=app.fs.joinPath(cwd,value) end
    elseif value:sub(1,1)~='/' then value=app.fs.joinPath(cwd,value) end
    value=app.fs.normalizePath(value):gsub('\\','/'):gsub('/+$','')
    return windows and value:lower() or value
  end
  local destination=normalized(out)
  local assets=normalized(app.fs.joinPath(root,'assets'))
  assert(destination~=assets and destination:sub(1,#assets+1)~=assets..'/','a stand-in must be exported outside assets/')
end
local HEAD,SIZE,COLS=groundPort.HEAD,groundPort.SIZE,groundPort.COLS
local order=dofile(root..'tools/tile_art/ground_corners.lua')
assert(#order==COLS*COLS)

local sprite=assert(app.open(source))
assert(sprite.width==groundPort.W and sprite.height==groundPort.H,'not a ground template: '..source)
assert(#sprite.slices==COLS*COLS,'not a ground template: '..source)
for i,m in ipairs(order) do groundPort.checkSlice(sprite,i,m) end
local want=stand_in and sourceFiles.LAYER.under or sourceFiles.LAYER.draw
local extension=groundPort.extension(source_name)
local found=false
local sheet=Image(SIZE,SIZE,ColorMode.RGB)
for _,l in ipairs(sprite.layers) do
  if l.name==want then found=true end
  if (l.name==want and (stand_in or l.isVisible)) or (not stand_in and l.name==extension) then
    local cel=assert(l:cel(1),'no cel on '..l.name)
    assert(stand_in or (l.opacity==255 and cel.opacity==255),'Art layer opacity: '..l.name)
    sheet:drawImage(cel.image,Point(cel.position.x,cel.position.y-HEAD))
  end
end
assert(found,'no '..want..' in '..source)
local painted=0
for it in sheet:pixels() do
  if app.pixelColor.rgbaA(it())>0 then painted=painted+1 end
end
assert(painted>0,source..': nothing painted on '..want)
if name=='bridge' and not stand_in then
  local pc=app.pixelColor
  for it in sheet:pixels() do
    local v=it()
    if pc.rgbaA(v)>0 then
      v=sourceFiles.scaleRgb(v,0.70)
      if pc.rgbaR(v)==0 and pc.rgbaG(v)==0 and pc.rgbaB(v)==0 then v=pc.rgba(42,33,25,pc.rgbaA(v)) end
      it(v)
    end
  end
end
sprite:close()
sourceFiles.savePng(sheet,out,'reread '..out)
