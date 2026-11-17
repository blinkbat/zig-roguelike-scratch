local function bytesOf(file)
  local input=assert(io.open(file,'rb'))
  local bytes,read_error=input:read('*a')
  local closed,close_error=input:close()
  assert(bytes,read_error)
  assert(closed,close_error)
  return bytes
end

local files={read=bytesOf}

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

function files.checkLayer(sprite,name,image,position)
  for _,layer in ipairs(sprite.layers) do
    if layer.name==name then
      local cel=assert(layer:cel(1),'Saved artwork cel missing: '..name)
      local actual=Image(sprite.width,sprite.height,ColorMode.RGB)
      actual:drawImage(cel.image,cel.position)
      local expected=Image(sprite.width,sprite.height,ColorMode.RGB)
      expected:drawImage(image,position)
      assert(actual:isEqual(expected),'Saved artwork layer changed: '..name)
      return layer
    end
  end
  error('Saved artwork layer missing: '..name)
end

return files
