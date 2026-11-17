local function bytesOf(file)
  local input=assert(io.open(file,'rb'))
  local bytes,read_error=input:read('*a')
  local closed,close_error=input:close()
  assert(bytes,read_error)
  assert(closed,close_error)
  return bytes
end

local files={read=bytesOf,STAMP='%Y%m%d-%H%M%S'}

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

function files.layer(sprite,name)
  for _,layer in ipairs(sprite.layers) do
    if layer.name==name then return layer end
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
  assert(paint.isImage and paint.name=='Draw here' and blank,'Preserving owner painting: '..label)
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
