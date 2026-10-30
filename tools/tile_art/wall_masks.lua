-- The 47 joined wall shapes in sheet order, as src/gfx/look.zig's WALL_MASKS; `bit` is grid.WallShape's bit for each side and corner.
local N,E,S,W,NE,SE,SW,NW=1,2,4,8,16,32,64,128
local masks={0,1,2,4,8,3,19,5,6,38,9,137,10,12,76,7,23,39,55,11,27,139,155,13,77,141,205,14,46,78,110,15,31,47,63,79,95,111,127,143,159,175,191,207,223,239,255}
masks.bit={n=N,e=E,s=S,w=W,ne=NE,se=SE,sw=SW,nw=NW}
return masks
