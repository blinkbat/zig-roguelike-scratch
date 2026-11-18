-- The 47 joined wall shapes in sheet order, as src/gfx/sprite_assets.zig's WALL_MASKS; `bit` is grid.WallShape's bit for each side and corner.
local N,E,S,W,NE,SE,SW,NW=1,2,4,8,16,32,64,128
local masks={0,1,2,4,8,3,19,5,6,38,9,137,10,12,76,7,23,39,55,11,27,139,155,13,77,141,205,14,46,78,110,15,31,47,63,79,95,111,127,143,159,175,191,207,223,239,255}
masks.bit={n=N,e=E,s=S,w=W,ne=NE,se=SE,sw=SW,nw=NW}
masks.CELL,masks.COLS=64,8
masks.HEAD=64
masks.W,masks.H=masks.COLS*masks.CELL,math.ceil(#masks/masks.COLS)*masks.CELL
masks.SHEET_H=masks.HEAD+masks.H
function masks.at(i) return ((i-1)%masks.COLS)*masks.CELL,(i-1)//masks.COLS*masks.CELL end
function masks.sides(mask)
  return (mask&N)~=0,(mask&E)~=0,(mask&S)~=0,(mask&W)~=0,(mask&NE)~=0,(mask&SE)~=0,(mask&SW)~=0,(mask&NW)~=0
end
function masks.of(filled,x,y)
  local n,e,s,w=filled(x,y-1),filled(x+1,y),filled(x,y+1),filled(x-1,y)
  local m=(n and N or 0)|(e and E or 0)|(s and S or 0)|(w and W or 0)
  if n and e and filled(x+1,y-1) then m=m|NE end
  if s and e and filled(x+1,y+1) then m=m|SE end
  if s and w and filled(x-1,y+1) then m=m|SW end
  if n and w and filled(x-1,y-1) then m=m|NW end
  return m
end
return masks
