local pc=app.pixelColor
local port={}
port.CELL,port.COLS=64,4
port.HEAD=64
port.SIZE=port.COLS*port.CELL
port.W,port.H=512,port.HEAD+port.SIZE

function port.at(i) return ((i-1)%port.COLS)*port.CELL,port.HEAD+(i-1)//port.COLS*port.CELL end

function port.corner(sprite,m)
  local found
  for _,slice in ipairs(sprite.slices) do
    if slice.name=='Corners '..m then found=slice end
  end
  return found
end

function port.bit(m,b) return (m&b)~=0 end

function port.opaque(v) return pc.rgbaA(v)>0 end
local opaque=port.opaque

function port.checkJoins(cells)
  local bit=port.bit
  local joins=0
  for a=0,15 do for b=0,15 do
    if bit(a,2)==bit(b,1) and bit(a,8)==bit(b,4) then
      for _,span in ipairs({{8,23,2},{40,55,8}}) do
        for y=span[1],span[2] do
          assert(opaque(cells[a]:getPixel(63,y))==bit(a,span[3]),'East gap')
          assert(opaque(cells[b]:getPixel(0,y))==bit(a,span[3]),'West gap')
        end
      end
      joins=joins+1
    end
    if bit(a,4)==bit(b,1) and bit(a,8)==bit(b,2) then
      for _,span in ipairs({{8,23,4},{40,55,8}}) do
        for x=span[1],span[2] do
          assert(opaque(cells[a]:getPixel(x,63))==bit(a,span[3]),'South gap')
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
  local preview=Image(#MAP[1]*64,#MAP*64,ColorMode.RGB)
  preview:clear(background)
  for y=1,#MAP+1 do for x=1,#MAP[1]+1 do
    local m=(filled(x-1,y-1) and 1 or 0)|(filled(x,y-1) and 2 or 0)|(filled(x-1,y) and 4 or 0)|(filled(x,y) and 8 or 0)
    preview:drawImage(cells[m],Point((x-1)*64-32,(y-1)*64-32))
  end end
  preview:saveAs(path)
end

return port
