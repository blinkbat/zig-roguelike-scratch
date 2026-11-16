local function bytesOf(file)
  local input=assert(io.open(file,'rb'))
  local bytes,read_error=input:read('*a')
  local closed,close_error=input:close()
  assert(bytes,read_error)
  assert(closed,close_error)
  return bytes
end

local files={}

function files.preserve(source,canonical,install)
  if install and app.fs.isFile(canonical) then
    assert(bytesOf(canonical)==bytesOf(source),'Preserving divergent canonical source; inspect owner edits before installing')
  end
end

function files.copy(source,destination)
  local bytes=bytesOf(source)
  local output=assert(io.open(destination,'wb'))
  local written,write_error=output:write(bytes)
  local closed,close_error=output:close()
  assert(written,write_error)
  assert(closed,close_error)
end

return files
