local pc=app.pixelColor
local port=dofile(debug.getinfo(1,'S').source:gsub('\\','/'):match('^@(.*/)[^/]*$')..'ground_layout.lua')
local NW,NE,SW,SE=port.NW,port.NE,port.SW,port.SE
port.FULL=NW|NE|SW|SE
port.SIZE=port.COLS*port.CELL
port.H=port.HEAD+port.SIZE
port.QUARTERS={{bit=NW,x=8,y=8},{bit=NE,x=48,y=8},{bit=SW,x=8,y=48},{bit=SE,x=48,y=48}}
port.SOURCE={shallows='water',water='deep-water'}
port.EXTENSION={['deep-water']='Water extensions'}
port.CORNER='Corners '

function port.source(material) return port.SOURCE[material] or material end
function port.extension(source) return port.EXTENSION[source] or source:gsub('^%l',string.upper)..' extensions' end
function port.png(material) return 'assets/ground/'..material..'-ground.png' end
function port.fill(order)
  for i,m in ipairs(order) do
    if m==port.FULL then
      local x,y=port.at(i)
      return x,y-port.HEAD
    end
  end
end

function port.at(i) return ((i-1)%port.COLS)*port.CELL,port.HEAD+(i-1)//port.COLS*port.CELL end

function port.corner(sprite,m)
  local found
  for _,slice in ipairs(sprite.slices) do
    if slice.name==port.CORNER..m then found=slice end
  end
  return found
end

function port.bit(m,b) return (m&b)~=0 end

function port.opaque(v) return pc.rgbaA(v)>0 end
local opaque=port.opaque

function port.reader(image)
  return function(x,y)
    if x<0 or y<0 or x>=image.width or y>=image.height then return 0 end
    return image:getPixel(x,y)
  end
end

function port.painting(cel,pixels)
  local original=Image(cel.image)
  local position=Point(cel.position.x,cel.position.y)
  local painted=Image(port.W,port.H,ColorMode.RGB)
  painted:drawImage(original,position)
  local palette,count={},0
  for it in painted:pixels() do
    if pc.rgbaA(it())>0 then
      assert(pc.rgbaA(it())==255,'Partial alpha in source')
      palette[it()]=true
      count=count+1
    end
  end
  assert(count==pixels,'Source painting changed; inspect the crops before porting')
  return original,position,painted,palette,count
end

function port.checkSlice(sprite,i,m,sized)
  local slice=assert(port.corner(sprite,m),'Slice missing: '..m)
  local x,y=port.at(i)
  local b=slice.bounds
  assert(b.x==x and b.y==y and (not sized or (b.width==port.CELL and b.height==port.CELL)),'Slice moved: '..m)
end

function port.checkCells(sprite,order,cells)
  for i,m in ipairs(order) do
    port.checkSlice(sprite,i,m,true)
    for _,q in ipairs(port.QUARTERS) do
      for y=q.y,q.y+7 do for x=q.x,q.x+7 do
        assert(opaque(cells[m]:getPixel(x,y))==port.bit(m,q.bit),'Wrong quarter in mask '..m)
      end end
    end
    for it in cells[m]:pixels() do
      if m==0 then assert(not opaque(it()),'Unused cell painted') end
      if m==port.FULL then assert(opaque(it()),'Fill has a hole') end
    end
  end
end

function port.checkJoins(cells)
  local bit=port.bit
  local last=port.CELL-1
  local joins=0
  for a=0,port.FULL do for b=0,port.FULL do
    if bit(a,NE)==bit(b,NW) and bit(a,SE)==bit(b,SW) then
      for _,span in ipairs({{8,23,NE},{40,55,SE}}) do
        for y=span[1],span[2] do
          assert(opaque(cells[a]:getPixel(last,y))==bit(a,span[3]),'East gap')
          assert(opaque(cells[b]:getPixel(0,y))==bit(a,span[3]),'West gap')
        end
      end
      joins=joins+1
    end
    if bit(a,SW)==bit(b,NW) and bit(a,SE)==bit(b,NE) then
      for _,span in ipairs({{8,23,SW},{40,55,SE}}) do
        for x=span[1],span[2] do
          assert(opaque(cells[a]:getPixel(x,last))==bit(a,span[3]),'South gap')
          assert(opaque(cells[b]:getPixel(x,0))==bit(a,span[3]),'North gap in '..b..' at '..x)
        end
      end
      joins=joins+1
    end
  end end
  assert(joins==128)
end

local MAP={
  '..................',
  '..#######.........',
  '..#######..#......',
  '..##..###..#......',
  '..##..###..####...',
  '..#######....#....',
  '.............#....',
  '..###..#..#..#....',
  '..#.#...##........',
  '..###...##..####..',
  '............####..',
  '..................',
}

function port.preview(cells,background,path)
  local function filled(x,y)
    return y>=1 and y<=#MAP and x>=1 and x<=#MAP[y] and MAP[y]:sub(x,x)=='#'
  end
  local cell,half=port.CELL,port.CELL//2
  local preview=Image(#MAP[1]*cell,#MAP*cell,ColorMode.RGB)
  preview:clear(background)
  for y=1,#MAP+1 do for x=1,#MAP[1]+1 do
    local m=(filled(x-1,y-1) and NW or 0)|(filled(x,y-1) and NE or 0)|(filled(x-1,y) and SW or 0)|(filled(x,y) and SE or 0)
    preview:drawImage(cells[m],Point((x-1)*cell-half,(y-1)*cell-half))
  end end
  preview:saveAs(path)
end

return port
