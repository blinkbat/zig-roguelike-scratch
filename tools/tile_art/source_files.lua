local function bytesOf(file)
  local input=assert(io.open(file,'rb'))
  local bytes,read_error=input:read('*a')
  local closed,close_error=input:close()
  assert(bytes,read_error)
  assert(closed,close_error)
  return bytes
end

local files={read=bytesOf,STAMP='%Y%m%d-%H%M%S'}
files.DESKTOP=(os.getenv('USERPROFILE') or os.getenv('HOME') or ''):gsub('\\','/')..'/Desktop/'
files.LAYER={
  draw='Draw here',
  under='Underdrawing (25%)',
  ideas='Ideas - hide before export',
  labels='Labels - hide before export',
  paper='Paper - hide for transparent export',
  exact='Exact connection guide (hidden)',
  forest='Forest extensions',
  ported='Extension - ported painted edges',
}

function files.work(folder)
  local work=(folder or app.fs.joinPath(app.fs.tempPath,'wall-mocks'))..'/'
  app.fs.makeAllDirectories(work)
  return work
end

function files.pathKey(path)
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

function files.requireOutside(path,folder)
  local destination=files.pathKey(path)
  local parent=files.pathKey(folder)
  local message='a stand-in must be exported outside assets/'
  assert(destination~=parent and destination:sub(1,#parent+1)~=parent..'/',message)
  local function hex(value)
    return (value:gsub('.',function(c) return ('%02x'):format(c:byte()) end))
  end
  local python=app.fs.pathSeparator=='\\' and 'python' or 'python3'
  local resolve='from pathlib import Path; import sys; '
    ..'path, folder = (Path(bytes.fromhex(x).decode()).resolve() for x in sys.argv[1:]); '
    ..'linked = path.is_file() and path.stat().st_nlink > 1; '
    .."protected = path.is_relative_to(folder) or (linked and any(p.is_file() and p.samefile(path) for p in folder.rglob('*'))); "
    ..'sys.exit(3 if protected else 0)'
  local ok,_,status=os.execute(python..' -c "'..resolve..'" '..hex(path)..' '..hex(folder))
  assert(status~=3,message)
  assert(ok,'Could not resolve the draft path with Python')
end

function files.draft(path,...)
  local destination=files.pathKey(path)
  local occupied=app.fs.isFile(path) and bytesOf(path)
  for _,source in ipairs({...}) do
    assert(destination~=files.pathKey(source),'Draft destination must differ from its source artwork: '..source)
    if occupied and app.fs.isFile(source) and occupied==bytesOf(source) then
      local folder=app.fs.filePath(path)
      local stem=app.fs.fileTitle(path)
      local ext=app.fs.fileExtension(path)
      local i=2
      local candidate
      repeat
        candidate=app.fs.joinPath(folder,stem..'-'..i..'.'..ext)
        i=i+1
      until not app.fs.isFile(candidate) and not app.fs.isDirectory(candidate)
      return candidate
    end
  end
  return path
end

function files.rgb(r,g,b) return app.pixelColor.rgba(r,g,b,255) end

function files.scaleRgb(p,scale,divisor)
  local pc=app.pixelColor
  local function channel(v) return math.floor(v*scale/(divisor or 1)+0.5) end
  return pc.rgba(channel(pc.rgbaR(p)),channel(pc.rgbaG(p)),channel(pc.rgbaB(p)),pc.rgbaA(p))
end

function files.preserve(source,canonical,install)
  if install and app.fs.isFile(canonical) then
    assert(bytesOf(canonical)==bytesOf(source),'Preserving divergent canonical source; inspect owner edits before installing')
  end
end

function files.write(destination,bytes)
  local output=assert(io.open(destination,'wb'))
  local written,write_error=output:write(bytes)
  local closed,close_error=output:close()
  assert(written,write_error)
  assert(closed,close_error)
end

function files.copy(source,destination)
  files.write(destination,bytesOf(source))
end

function files.report(path)
  local parts={}
  return {
    write=function(_,text) parts[#parts+1]=text end,
    close=function() files.write(path,table.concat(parts)) end,
  }
end

function files.keep(path,folder,tag,stamp)
  if app.fs.isFile(path) then
    files.copy(path,app.fs.joinPath(folder,app.fs.fileTitle(path)..'-before-'..tag..'-'..stamp..'.'..app.fs.fileExtension(path)))
  end
end

function files.savePng(image,path,message)
  image:saveAs(path)
  local saved=Image{fromFile=path}
  assert(saved:isEqual(image),message or 'Saved PNG changed: '..path)
  return saved
end

function files.stage(name)
  local staged=app.fs.joinPath(files.work(app.fs.joinPath(app.fs.tempPath,'tile-art-stage')),name)
  os.remove(staged)
  return staged
end

function files.staged(path,staged)
  return {path=path,bytes=bytesOf(staged)}
end

function files.stagePng(image,path,message)
  local staged=files.stage(app.fs.fileName(path))
  files.savePng(image,staged,message)
  return files.staged(path,staged)
end

function files.publish(staged)
  local before={}
  for i,item in ipairs(staged) do before[i]=app.fs.isFile(item.path) and bytesOf(item.path) end
  for i,item in ipairs(staged) do
    local ok,err=pcall(files.write,item.path,item.bytes)
    if not ok then
      for j=i,1,-1 do
        if before[j] then pcall(files.write,staged[j].path,before[j]) else os.remove(staged[j].path) end
      end
      error(err,0)
    end
  end
end

function files.layer(sprite,name)
  for _,layer in ipairs(sprite.layers) do
    if layer.name==name then return layer end
  end
end

function files.hide(sprite,...)
  local names={}
  for _,name in ipairs({...}) do names[name]=true end
  for _,layer in ipairs(sprite.layers) do
    if names[layer.name] then layer.isVisible=false end
  end
end

function files.canvas(sprite,cel)
  local image=Image(sprite.width,sprite.height,ColorMode.RGB)
  image:drawImage(cel.image,cel.position)
  return image
end

function files.checkLayer(sprite,name,image,position)
  local layer=files.layer(sprite,name) or error('Saved artwork layer missing: '..name)
  local cel=assert(layer:cel(1),'Saved artwork cel missing: '..name)
  local expected=Image(sprite.width,sprite.height,ColorMode.RGB)
  expected:drawImage(image,position)
  assert(files.canvas(sprite,cel):isEqual(expected),'Saved artwork layer changed: '..name)
  return layer
end

function files.checkCel(sprite,name,image,position)
  local layer=files.layer(sprite,name) or error('Saved artwork layer missing: '..name)
  local cel=assert(layer:cel(1),'Saved artwork cel missing: '..name)
  assert(cel.image:isEqual(image) and cel.position.x==position.x and cel.position.y==position.y,'Saved artwork cel changed: '..name)
  return cel
end

function files.checkBlankTemplate(old,want,label)
  local pc=app.pixelColor
  assert(old.width==want.width and old.height==want.height and old.colorMode==want.colorMode and #old.frames==1
    and #old.layers==#want.guides+1 and #old.slices==#want.slices,'Preserving changed template: '..label)
  for i,guide in ipairs(want.guides) do
    local l=old.layers[i]
    assert(l.isImage and l.name==guide.name and l.opacity==guide.opacity,'Preserving changed guide: '..l.name)
    local cel=assert(l:cel(1),'Preserving missing guide: '..l.name)
    assert(cel.opacity==255,'Preserving changed guide opacity: '..l.name)
    for pixel in cel.image:pixels() do
      local x,y=pixel.x+cel.position.x,pixel.y+cel.position.y
      assert((x>=0 and x<old.width and y>=0 and y<old.height) or pc.rgbaA(pixel())==0,'Preserving off-canvas guide pixels: '..l.name)
    end
    assert(files.canvas(old,cel):isEqual(guide.image),'Preserving changed guide pixels: '..l.name)
  end
  local paint=old.layers[#old.layers]
  local blank=true
  if paint.isImage and paint:cel(1) then
    for pixel in paint:cel(1).image:pixels() do
      if pc.rgbaA(pixel())>0 then blank=false break end
    end
  end
  assert(paint.isImage and paint.name==files.LAYER.draw and blank,'Preserving owner painting: '..label)
  local bounds={}
  for _,slice in ipairs(want.slices) do bounds[slice.name]=slice.bounds end
  for _,slice in ipairs(old.slices) do
    local b,expected=slice.bounds,bounds[slice.name]
    assert(expected,'Preserving unknown slice: '..slice.name)
    assert(b.x==expected.x and b.y==expected.y and b.width==expected.width and b.height==expected.height,'Preserving changed slice: '..slice.name)
    bounds[slice.name]=nil
  end
end

return files
