local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local source=app.params.source or 'C:/Users/DavidBennett/Desktop/water.aseprite'
local desktop='C:/Users/DavidBennett/Desktop/deep-water.aseprite'
local canonical=root..'assets/source/deep-water.aseprite'
local work=(app.params.work or app.fs.joinPath(app.fs.tempPath,'wall-mocks'))..'/'
app.fs.makeAllDirectories(work)
local percent=tonumber(app.params.percent or '60')
assert(percent and percent>0 and percent<100,'percent must be between 0 and 100')
local install=app.params.install=='yes'
local pc=app.pixelColor
local function copy(from,to)
  local f=assert(io.open(from,'rb'))
  local bytes=f:read('*a')
  f:close()
  local out=assert(io.open(to,'wb'))
  out:write(bytes)
  out:close()
end
local stamp=os.date('%Y%m%d-%H%M%S')
if install then
  assert(not app.fs.isFile(canonical),'Inspect the existing deep-water source before regenerating')
  local old=assert(app.open(desktop))
  local found=false
  for _,l in ipairs(old.layers) do
    if l.name=='Draw here' then
      found=true
      for _,cel in ipairs(l.cels) do
        for it in cel.image:pixels() do assert(pc.rgbaA(it())==0,'Deep water has owner artwork; inspect before replacing') end
      end
    end
  end
  assert(found,'No Draw here in the old deep-water template')
  old:close()
  copy(desktop,work..'deep-water-before-'..stamp..'.aseprite')
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
if install then s:saveCopyAs(canonical) end
s:close()
local back=assert(app.open(path))
for _,l in ipairs(back.layers) do
  local expected=snapshots[l.name]
  if expected then
    local cel=assert(l:cel(1))
    assert(cel.position.x==expected.position.x and cel.position.y==expected.position.y,'Cel moved')
    assert(cel.image:isEqual(expected.toned),'Saved pixels changed')
    for y=0,cel.image.height-1 do for x=0,cel.image.width-1 do
      assert(cel.image:getPixel(x,y)==toned(expected.original:getPixel(x,y)),'Wrong tone or alpha')
    end end
  end
end
back:close()
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
report:write('Shallows export: assets/shallows-ground.png from water.aseprite. Deep export: assets/water-ground.png from deep-water.aseprite.\n')
report:close()
