local root=app.params.root or assert(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*)tools/[^/]+/[^/]+$'),'root=<repo with trailing slash>')
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local groundPort=dofile(root..'tools/tile_art/ground_port.lua')
local shallow_name,deep_name=groundPort.source('shallows'),groundPort.source('water')
local extension=groundPort.extension(shallow_name)
local source=app.params.source or sourceFiles.DESKTOP..shallow_name..'.aseprite'
local desktop=app.params.out or sourceFiles.DESKTOP..deep_name..'.aseprite'
local canonical=root..'assets/source/'..deep_name..'.aseprite'
local work=sourceFiles.work(app.params.work)
assert(app.params.percent==nil or tonumber(app.params.percent),'percent must be a number')
local percent=tonumber(app.params.percent) or 60
assert(percent>0 and percent<100,'percent must be between 0 and 100')
local install=app.params.install=='yes'
local pc=app.pixelColor
if install then
  assert(not app.fs.isFile(canonical),'Inspect the existing deep-water source before regenerating')
  assert(not app.fs.isFile(desktop),'Preserving existing deep-water artwork; choose a new out= path')
end
local s=assert(app.open(source))
assert(s.width==groundPort.W and s.height==groundPort.H and #s.frames==1 and #s.slices==groundPort.COLS*groundPort.COLS)
local labels=Image{fromFile=assert(app.params.labels,'labels=<ground_labels.py PNG>')}
assert(labels.width==s.width and labels.height==s.height)
local snapshots={}
local size=groundPort.SIZE
local shallow=Image(size,size,ColorMode.RGB)
local deep=Image(size,size,ColorMode.RGB)
local changed=0
local function toned(p)
  if pc.rgbaA(p)==0 then return p end
  return sourceFiles.scaleRgb(p,percent,100)
end
for _,l in ipairs(s.layers) do
  local cel=l:cel(1)
  if l.name=='Draw here' or l.name==extension then
    assert(cel and l.opacity==255 and cel.opacity==255)
    local original=Image(cel.image)
    local image=Image(original)
    for it in image:pixels() do
      local p=it()
      if pc.rgbaA(p)>0 then changed=changed+1 end
      it(toned(p))
    end
    local position=Point(cel.position.x,cel.position.y)
    snapshots[l.name]={original=original,toned=image,position=position}
    shallow:drawImage(original,Point(position.x,position.y-groundPort.HEAD))
    deep:drawImage(image,Point(position.x,position.y-groundPort.HEAD))
    cel.image=image
  elseif l.name=='Labels - hide before export' then
    assert(cel)
    cel.image=Image(labels)
    cel.position=Point(0,0)
  end
end
assert(snapshots['Draw here'] and snapshots[extension] and changed>0)
local path=install and desktop or work..'deep-water-draft.aseprite'
s:saveAs(path)
s:close()
local back=assert(app.open(path))
for name,expected in pairs(snapshots) do
  local cel=sourceFiles.checkCel(back,name,expected.toned,expected.position)
  for y=0,cel.image.height-1 do for x=0,cel.image.width-1 do
    assert(cel.image:getPixel(x,y)==toned(expected.original:getPixel(x,y)),'Wrong tone or alpha')
  end end
end
back:close()
if install then sourceFiles.copy(path,canonical) end
shallow:saveAs(work..'shallows-atlas.png')
deep:saveAs(work..'deep-water-atlas.png')
local preview=Image(2*size,size,ColorMode.RGB)
preview:drawImage(shallow,Point(0,0))
preview:drawImage(deep,Point(size,0))
preview:resize(4*size,2*size)
preview:saveAs(work..'water-depth-comparison.png')
local report=sourceFiles.report(work..'water-depth-validation.txt')
report:write(string.format('%d art pixels derived at %g%% RGB; alpha and cel positions unchanged.\n',changed,percent))
report:write('Source left unchanged: '..source..'\nSaved and reopened: '..path..'\n')
report:write('Shallows export: assets/ground/shallows-ground.png from water.aseprite. Deep export: assets/ground/water-ground.png from deep-water.aseprite.\n')
report:close()
