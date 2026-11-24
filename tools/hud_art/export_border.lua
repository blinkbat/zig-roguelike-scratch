local root = app.params.root or assert(debug.getinfo(1, 'S').source:gsub('\\', '/'):match('^@(.*)tools/[^/]+/[^/]+$'), 'root=<repo with trailing slash>')
local sourceFiles = dofile(root .. 'tools/tile_art/source_files.lua')
local source = app.params.source or sourceFiles.DESKTOP .. 'border.aseprite'
local work = sourceFiles.work(app.fs.joinPath(app.fs.tempPath, 'hud-border-export'))

local W=73
local H=55
local CUT=9
local RAIL=3

local sprite = assert(app.open(source))
assert(sprite.width == 128 and sprite.height == 128 and #sprite.frames == 1)
local layer = assert(sprite.layers[1])
assert(#sprite.layers == 1 and layer.name == sourceFiles.LAYER.original and layer.opacity == 255)
local cel = assert(layer:cel(1))
assert(cel.opacity == 255 and cel.position.x == 1 and cel.position.y == 1)
assert(cel.image.width == W and cel.image.height == H)
local painted = Image(cel.image)
local border = Image(sourceFiles.canvas(sprite, cel), Rectangle(1, 1, W, H))
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

local png = root .. 'assets/ui/hud-border.png'
local canonical = root .. 'assets/source/hud-border.aseprite'
for _, path in ipairs({source, canonical, png}) do
  if app.fs.isFile(path) then
    sourceFiles.copy(path, app.fs.joinPath(work, os.date(sourceFiles.STAMP) .. '-' .. app.fs.fileName(path)))
  end
end
local exported = sourceFiles.stagePng(border, png, 'Export changed the painted pixels')
local staged = sourceFiles.stage(app.fs.fileName(canonical))
sprite:saveCopyAs(staged)
sprite:close()
local saved = assert(app.open(staged))
local original = assert(saved.layers[1]:cel(1))
assert(original.position.x == 1 and original.position.y == 1 and original.image:isEqual(painted))
saved:close()
sourceFiles.publish({exported, sourceFiles.staged(canonical, staged)})
local report = sourceFiles.report(app.fs.joinPath(work, 'validation.txt'))
report:write(string.format('%dx%d native border exported from %s at (1,1); %dpx corner cuts.\n', W, H, sourceFiles.LAYER.original, CUT))
report:write('PNG pixels and canonical painted cel verified after reopening; center clear and repeated rails unbroken.\n')
report:write('Runtime repeats edge pixels, clips final repeats, and retains all four original corners.\n')
report:close()
