local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local source=app.params.source or 'C:/Users/DavidBennett/Desktop/water.aseprite'
local desktop=app.params.out or 'C:/Users/DavidBennett/Desktop/deep-water.aseprite'
local canonical=root..'assets/source/deep-water.aseprite'
local sourceFiles=dofile(root..'tools/tile_art/source_files.lua')
local work=(app.params.work or app.fs.joinPath(app.fs.tempPath,'wall-mocks'))..'/'
app.fs.makeAllDirectories(work)
local percent=tonumber(app.params.percent) or 60
assert(percent and percent>0 and percent<100,'percent must be between 0 and 100')
local install=app.params.install=='yes'
local pc=app.pixelColor
if install then
  assert(not app.fs.isFile(canonical),'Inspect the existing deep-water source before regenerating')
  assert(not app.fs.isFile(desktop),'Preserving existing deep-water artwork; choose a new out= path')
end
local s=assert(app.open(source))
assert(s.width==512 and s.height==320 and #s.frames==1 and #s.slices==16)
local labels=Image{fromFile=assert(app.params.labels,'labels=<ground_labels.py PNG>')}
assert(labels.width==s.width and labels.height==s.height)
local snapshots={}
local shallow=Image(256,256,ColorMode.RGB)
local deep=Image(256,256,ColorMode.RGB)
local changed=0
local function toned(p)
  if pc.rgbaA(p)==0 then return p end
  local function channel(v) return math.floor(v*percent/100+0.5) end
  return pc.rgba(channel(pc.rgbaR(p)),channel(pc.rgbaG(p)),channel(pc.rgbaB(p)),pc.rgbaA(p))
end
for _,l in ipairs(s.layers) do
  local cel=l:cel(1)
  if l.name=='Draw here' or l.name=='Water extensions' then
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
    shallow:drawImage(original,Point(position.x,position.y-64))
    deep:drawImage(image,Point(position.x,position.y-64))
    cel.image=image
  elseif l.name=='Labels - hide before export' then
    assert(cel)
    cel.image=Image(labels)
    cel.position=Point(0,0)
  end
end
assert(snapshots['Draw here'] and snapshots['Water extensions'] and changed>0)
local path=install and desktop or work..'deep-water-draft.aseprite'
s:saveAs(path)
s:close()
local back=assert(app.open(path))
local verified={}
for _,l in ipairs(back.layers) do
  local expected=snapshots[l.name]
  if expected then
    local cel=assert(l:cel(1))
    assert(cel.position.x==expected.position.x and cel.position.y==expected.position.y,'Cel moved')
    assert(cel.image:isEqual(expected.toned),'Saved pixels changed')
    for y=0,cel.image.height-1 do for x=0,cel.image.width-1 do
      assert(cel.image:getPixel(x,y)==toned(expected.original:getPixel(x,y)),'Wrong tone or alpha')
    end end
    verified[l.name]=true
  end
end
for name in pairs(snapshots) do assert(verified[name],'Saved source is missing artwork layers') end
back:close()
if install then sourceFiles.copy(path,canonical) end
shallow:saveAs(work..'shallows-atlas.png')
deep:saveAs(work..'deep-water-atlas.png')
local preview=Image(512,256,ColorMode.RGB)
preview:drawImage(shallow,Point(0,0))
preview:drawImage(deep,Point(256,0))
preview:resize(1024,512)
preview:saveAs(work..'water-depth-comparison.png')
local report=assert(io.open(work..'water-depth-validation.txt','w'))
report:write(string.format('%d art pixels derived at %g%% RGB; alpha and cel positions unchanged.\n',changed,percent))
report:write('Source left unchanged: '..source..'\nSaved and reopened: '..path..'\n')
report:write('Shallows export: assets/ground/shallows-ground.png from water.aseprite. Deep export: assets/ground/water-ground.png from deep-water.aseprite.\n')
report:close()
