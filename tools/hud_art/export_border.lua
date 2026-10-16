local root = app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local source = app.params.source or 'C:/Users/DavidBennett/Desktop/border.aseprite'
local work = app.fs.joinPath(app.fs.tempPath, 'hud-border-export')
app.fs.makeAllDirectories(work)

local W=73
local H=55
local CUT=9
local RAIL=3

local sprite = assert(app.open(source))
assert(sprite.width == 128 and sprite.height == 128 and #sprite.frames == 1)
local layer = assert(sprite.layers[1])
assert(#sprite.layers == 1 and layer.name == 'Layer 1' and layer.opacity == 255)
local cel = assert(layer:cel(1))
assert(cel.opacity == 255 and cel.position.x == 1 and cel.position.y == 1)
assert(cel.image.width == W and cel.image.height == H)
local painted = Image(cel.image)
local art = Image(128, 128, ColorMode.RGB)
art:drawImage(cel.image, cel.position)
local border = Image(art, Rectangle(1, 1, W, H))
for y = CUT, H - CUT - 1 do
  for x = CUT, W - CUT - 1 do
    assert(app.pixelColor.rgbaA(border:getPixel(x, y)) == 0, 'Border center must stay clear')
  end
end

local base = border:getPixel(CUT, RAIL)
local shine = border:getPixel(14, RAIL)
local function rail(x, y)
  local pixel = border:getPixel(x, y)
  assert(pixel == base or pixel == shine, 'Dark corner transition included in a repeating rail')
end
for x = CUT, W - CUT - 1 do rail(x, RAIL); rail(x, H - 1 - RAIL) end
for y = CUT, H - CUT - 1 do rail(RAIL, y); rail(W - 1 - RAIL, y) end

local png = root .. 'assets/hud-border.png'
local canonical = root .. 'assets/source/hud-border.aseprite'
for _, path in ipairs({source, canonical, png}) do
  local input = io.open(path, 'rb')
  if input then
    local backup = assert(io.open(app.fs.joinPath(work, os.date('%Y%m%d-%H%M%S-') .. app.fs.fileName(path)), 'wb'))
    backup:write(input:read('*a'))
    backup:close()
    input:close()
  end
end
border:saveAs(png)
sprite:saveCopyAs(canonical)
local check = Image{fromFile=png}
assert(check:isEqual(border), 'Export changed the painted pixels')
sprite:close()
local saved = assert(app.open(canonical))
local original = assert(saved.layers[1]:cel(1))
assert(original.position.x == 1 and original.position.y == 1 and original.image:isEqual(painted))
saved:close()
local report = assert(io.open(app.fs.joinPath(work, 'validation.txt'), 'w'))
report:write(string.format('%dx%d native border exported from Layer 1 at (1,1); %dpx corner cuts.\n', W, H, CUT))
report:write('PNG pixels and canonical painted cel verified after reopening; center clear and repeated rails unbroken.\n')
report:write('Runtime repeats edge pixels, clips final repeats, and retains all four original corners.\n')
report:close()
