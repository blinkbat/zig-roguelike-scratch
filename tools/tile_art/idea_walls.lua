local root=app.params.root or 'C:/Users/DavidBennett/Desktop/projects/tests/zig-roguelike-scratch/'
local path=assert(app.params.source,'source=<sheet.aseprite>')
local kind=assert(app.params.kind,'kind=cave|forest|water|deep')
local LIQUID=kind=='water' or kind=='deep'
assert(kind=='cave' or kind=='forest' or LIQUID)
local work=app.fs.joinPath(app.fs.tempPath,'wall-mocks')..'/'
app.fs.makeAllDirectories(work)
local pc=app.pixelColor
local masks=dofile(root..'tools/tile_art/wall_masks.lua')
local FACE=23
local TOP=64-FACE
local function rgb(r,g,b) return pc.rgba(r,g,b,255) end
local P=kind=='water' and {
  foam=rgb(226,238,234),shallow=rgb(92,164,196),m=rgb(52,118,176),d=rgb(38,92,150),hi=rgb(150,206,226),
  shade=rgb(30,70,120),lip=rgb(62,46,32),bank=rgb(120,92,62),bankd=rgb(88,66,44),bankl=rgb(150,118,80),ground=rgb(104,124,70),
} or kind=='deep' and {
  foam=rgb(196,218,228),shallow=rgb(72,136,184),m=rgb(40,92,152),d=rgb(22,52,106),dd=rgb(14,34,78),hi=rgb(62,112,170),
  shade=rgb(12,30,68),lip=rgb(62,46,32),bank=rgb(120,92,62),bankd=rgb(88,66,44),bankl=rgb(150,118,80),ground=rgb(104,124,70),
} or kind=='cave' and {
  out=rgb(30,26,34),crev=rgb(52,48,58),d=rgb(74,70,80),m=rgb(104,100,108),l=rgb(138,134,140),h=rgb(172,168,170),
  fd=rgb(56,50,58),fm=rgb(82,76,84),fl=rgb(110,104,110),ground=rgb(70,60,50),
} or {
  out=rgb(14,26,18),crev=rgb(24,48,30),d=rgb(36,72,40),m=rgb(54,104,50),l=rgb(82,138,60),h=rgb(128,174,80),
  under=rgb(26,54,32),td=rgb(58,38,26),tm=rgb(88,60,38),tl=rgb(118,84,52),ground=rgb(96,124,62),
}
local function hash(i,j,s)
  local h=(i*374761393+j*668265263+s*1442695041)&0xffffffff
  h=((h~(h>>13))*1274126177)&0xffffffff
  h=h~(h>>16)
  return (h&0xffff)/65536
end
local function noise(x,step,seed)
  local n=64//step
  local k=x//step
  local t=(x%step)/step
  t=t*t*(3-2*t)
  local a,b=hash(k%n,0,seed),hash((k+1)%n,0,seed)
  return a+(b-a)*t
end
local function wrap(d) return (d+32)%64-32 end
local blobs={}
do
  local step=16
  for j=0,3 do for i=0,3 do
    local s=kind=='cave' and 1 or 2
    local cx=i*step+8+math.floor(hash(i,j,s)*9)-4
    local cy=j*step+8+math.floor(hash(i,j,s+10)*9)-4
    local r=kind=='cave' and 8+math.floor(hash(i,j,s+20)*4) or 9+math.floor(hash(i,j,s+20)*4)
    blobs[#blobs+1]={cx=cx,cy=cy,r=r,o=hash(i,j,s+30)}
  end end
  table.sort(blobs,function(a,b) return a.o<b.o end)
end
local L={-0.45,-0.55,0.7}
do local n=math.sqrt(L[1]^2+L[2]^2+L[3]^2); L={L[1]/n,L[2]/n,L[3]/n} end
local function top(x,y)
  local hit
  for _,b in ipairs(blobs) do
    local dx,dy=wrap(x-b.cx),wrap(y-b.cy)
    if dx*dx+dy*dy<=b.r*b.r then hit={b=b,dx=dx,dy=dy} end
  end
  if not hit then return P.crev end
  local b,dx,dy=hit.b,hit.dx,hit.dy
  local d=math.sqrt(dx*dx+dy*dy)
  if d>b.r-1.2 then return kind=='cave' and P.crev or P.out end
  local nx,ny=dx/b.r,dy/b.r
  local nz=math.sqrt(math.max(0,1-nx*nx-ny*ny))
  local dot=nx*L[1]+ny*L[2]+nz*L[3]
  if kind=='forest' then dot=dot+(hash(x,y,9)-0.5)*0.35 end
  if kind=='cave' and hash(x,y,11)<0.05 then return P.d end
  if dot<0.15 then return P.d elseif dot<0.5 then return P.m elseif dot<0.82 then return P.l end
  return P.h
end
local function edge(t,seed)
  if kind=='cave' then return 1+math.floor(noise(t,8,seed)*3.99)+math.floor(noise(t,4,seed+50)*1.99) end
  local u=((t+8)%16-8)/8
  return 1+math.floor(5*(1-math.sqrt(math.max(0,1-u*u))))
end
local function faceTop(x) return kind=='cave' and TOP-1+math.floor(noise(x,8,7)*3.99) or TOP end
local function canopyFoot(x) return TOP+11-edge(x,0) end
local function trunk(x) return (x%32)-11 end
local function cell(mask)
  local bit=masks.bit
  local n,e,s,w=(mask&bit.n)~=0,(mask&bit.e)~=0,(mask&bit.s)~=0,(mask&bit.w)~=0
  local ne,se,sw,nw=(mask&bit.ne)~=0,(mask&bit.se)~=0,(mask&bit.sw)~=0,(mask&bit.nw)~=0
  local R=kind=='cave' and 6 or 10
  local B=kind=='cave' and 4 or 6
  local function within(x,y)
    if x<0 or x>63 or y<0 or y>63 then
      local wx,wy=x<0 and w or x>63 and e or true,y<0 and n or y>63 and s or true
      if x<0 and y<0 then return n and w and nw end
      if x>63 and y<0 then return n and e and ne end
      if x<0 and y>63 then return s and w and sw end
      if x>63 and y>63 then return s and e and se end
      return wx and wy
    end
    if not n and y<edge(x,1) then return false end
    if not w and x<edge(y,2) then return false end
    if not e and x>63-edge(y,3) then return false end
    if not s then
      if kind=='cave' then
        if y>63-edge(x,4) then return false end
      elseif y>=canopyFoot(x) then
        local t=trunk(x)
        local flare=y>=60 and 1 or 0
        if t<-flare or t>7+flare or y>62 then return false end
      end
    end
    local function round(cx,cy,r) local dx,dy=x-cx,y-cy; return dx*dx+dy*dy>r*r end
    if not n and not w and x<R and y<R and round(R,R,R) then return false end
    if not n and not e and x>63-R and y<R and round(63-R,R,R) then return false end
    if kind=='cave' and not s and not w and x<R and y>63-R and round(R,63-R,R) then return false end
    if kind=='cave' and not s and not e and x>63-R and y>63-R and round(63-R,63-R,R) then return false end
    local function bite(cx,cy) local dx,dy=x-cx,y-cy; return dx*dx+dy*dy<B*B end
    if n and w and not nw and bite(-0.5,-0.5) then return false end
    if n and e and not ne and bite(63.5,-0.5) then return false end
    if s and w and not sw and bite(-0.5,63.5) then return false end
    if s and e and not se and bite(63.5,63.5) then return false end
    return true
  end
  local image=Image(64,64,ColorMode.RGB)
  for y=0,63 do for x=0,63 do
    if within(x,y) then
      local pixel
      if not (within(x-1,y) and within(x+1,y) and within(x,y-1) and within(x,y+1)) then
        pixel=P.out
      elseif kind=='cave' and not s and y>=faceTop(x) then
        local ft=faceTop(x)
        local r=y-ft
        if r==0 then pixel=P.out
        else
          local band=math.min(2,(r-1)//7)
          local by=r-1-band*7
          local xx=(x+({0,9,4})[band+1])%64
          local lx=xx%16
          local last=band==2 and y>=62-edge(x,4)
          if lx==0 or (by==0 and band>0) then pixel=P.out
          elseif lx==1 or by==1 then pixel=P.fl
          elseif lx==15 or by==6 or last then pixel=P.fd
          elseif hash(x,y,13)<0.06 then pixel=P.fd
          else pixel=P.fm end
        end
      elseif kind=='cave' and not s and y==faceTop(x)-1 then
        pixel=P.l
      elseif kind=='forest' and not s and y>=canopyFoot(x) then
        local t=trunk(x)
        if y<canopyFoot(x)+2 then pixel=P.td
        elseif t<=1 then pixel=P.tl
        elseif t<=4 then pixel=(hash(x//2,y//3,17)<0.2) and P.td or P.tm
        else pixel=P.td end
      elseif kind=='forest' and not s and y>=TOP then
        pixel=y>=canopyFoot(x)-3 and P.under or (top(x,y)==P.h and P.l or top(x,y))
        if pixel==P.h or pixel==P.l then pixel=P.m end
      else
        pixel=top(x,y)
      end
      image:putPixel(x,y,pixel)
    end
  end end
  return image
end
local BANK=tonumber(app.params.rows) or 10
local function noise2(x,y,step,seed)
  local n=64//step
  local i,j=x//step,y//step
  local tx,ty=(x%step)/step,(y%step)/step
  tx,ty=tx*tx*(3-2*tx),ty*ty*(3-2*ty)
  local a,b=hash(i%n,j%n,seed),hash((i+1)%n,j%n,seed)
  local c,d=hash(i%n,(j+1)%n,seed),hash((i+1)%n,(j+1)%n,seed)
  local top_,low=a+(b-a)*tx,c+(d-c)*tx
  return top_+(low-top_)*ty
end
local function shore(t,seed) return 1+math.floor(noise(t,8,seed)*2.99)+math.floor(noise(t,4,seed+50)*1.99) end
local function liquidCell(mask)
  local bit=masks.bit
  local n,e,s,w=(mask&bit.n)~=0,(mask&bit.e)~=0,(mask&bit.s)~=0,(mask&bit.w)~=0
  local ne,se,sw,nw=(mask&bit.ne)~=0,(mask&bit.se)~=0,(mask&bit.sw)~=0,(mask&bit.nw)~=0
  local R,B=8,5
  local function bankFoot(x) return shore(x,1)+BANK+math.floor(noise(x,8,21)*1.99) end
  local function within(x,y)
    if x<0 or x>63 or y<0 or y>63 then
      if x<0 and y<0 then return n and w and nw end
      if x>63 and y<0 then return n and e and ne end
      if x<0 and y>63 then return s and w and sw end
      if x>63 and y>63 then return s and e and se end
      if x<0 then return w elseif x>63 then return e elseif y<0 then return n end
      return s
    end
    if not n and y<shore(x,1) then return false end
    if not w and x<shore(y,2) then return false end
    if not e and x>63-shore(y,3) then return false end
    if not s and y>63-shore(x,4) then return false end
    local function round(cx,cy) local dx,dy=x-cx,y-cy; return dx*dx+dy*dy>R*R end
    if not n and not w and x<R and y<R and round(R,R) then return false end
    if not n and not e and x>63-R and y<R and round(63-R,R) then return false end
    if not s and not w and x<R and y>63-R and round(R,63-R) then return false end
    if not s and not e and x>63-R and y>63-R and round(63-R,63-R) then return false end
    local function bite(cx,cy) local dx,dy=x-cx,y-cy; return dx*dx+dy*dy<B*B end
    if n and w and not nw and bite(-0.5,-0.5) then return false end
    if n and e and not ne and bite(63.5,-0.5) then return false end
    if s and w and not sw and bite(-0.5,63.5) then return false end
    if s and e and not se and bite(63.5,63.5) then return false end
    return true
  end
  local function depth(x,y)
    local d=99
    if not n then d=math.min(d,y-bankFoot(x)) end
    if not w then d=math.min(d,x-shore(y,2)) end
    if not e then d=math.min(d,63-shore(y,3)-x) end
    if not s then d=math.min(d,63-shore(x,4)-y) end
    local function from(cx,cy) return math.sqrt((x-cx)^2+(y-cy)^2)-B end
    if n and w and not nw then d=math.min(d,from(-0.5,-0.5)) end
    if n and e and not ne then d=math.min(d,from(63.5,-0.5)) end
    if s and w and not sw then d=math.min(d,from(-0.5,63.5)) end
    if s and e and not se then d=math.min(d,from(63.5,63.5)) end
    return d
  end
  local function bankAt(x,y)
    local top_=shore(x,1)
    local r=y-top_
    if r<=0 then return P.lip end
    if y==bankFoot(x)-1 then return P.bankd end
    local band=(r+math.floor(noise(x,8,23)*2.99))//3
    if hash(x,y,25)<0.07 then return P.bankl end
    return band%2==0 and P.bank or P.bankd
  end
  local function body(x,y)
    if kind=='water' then
      local wave=(x+(y//8)*5+math.floor(noise2(x,y,16,27)*6))%16
      if y%8==3 and wave<5 then return P.hi end
      if y%8==4 and wave>=1 and wave<6 then return P.d end
      return noise2(x,y,16,29)>0.68 and P.d or P.m
    end
    local wave=(x+(y//12)*7+math.floor(noise2(x,y,32,27)*8))%32
    if y%12==5 and wave<4 then return P.hi end
    return noise2(x,y,16,29)>0.6 and P.dd or P.d
  end
  local image=Image(64,64,ColorMode.RGB)
  for y=0,63 do for x=0,63 do
    if within(x,y) then
      local pixel
      if not n and y<bankFoot(x) then
        pixel=bankAt(x,y)
      elseif not (within(x-1,y) and within(x+1,y) and within(x,y-1) and within(x,y+1)) then
        pixel=P.foam
      elseif not n and y==bankFoot(x) then
        pixel=P.foam
      else
        local d=depth(x,y)
        if not n and y<=bankFoot(x)+3 and d>1 then pixel=P.shade
        elseif kind=='water' then
          if d<=2 then pixel=P.shallow
          elseif d<=4 then pixel=((x+y)%2==0) and P.shallow or body(x,y)
          else pixel=body(x,y) end
        else
          if d<=1 then pixel=P.foam
          elseif d<=3 then pixel=P.shallow
          elseif d<=6 then pixel=P.m
          elseif d<=9 then pixel=((x+y)%2==0) and P.m or body(x,y)
          else pixel=body(x,y) end
        end
      end
      image:putPixel(x,y,pixel)
    end
  end end
  for _,corner in ipairs({{n and w and not nw,0},{n and e and not ne,1}}) do
    if corner[1] then
      for y=0,BANK+1 do for x=0,3 do
        local cx=corner[2]==0 and x or 63-x
        local dx=x+0.5
        if dx*dx+(y+0.5)^2>=B*B and pc.rgbaA(image:getPixel(cx,y))>0 then
          image:putPixel(cx,y,(x==3 or y==BANK+1) and P.foam or (x==0 and P.lip or P.bankd))
        end
      end end
    end
  end
  return image
end
if LIQUID then cell=liquidCell end
local sprite=assert(app.open(path))
assert(sprite.width==512 and sprite.height==448)
local under,drawing,ideas
for _,layer in ipairs(sprite.layers) do
  if layer.name=='Underdrawing (25%)' then under=layer end
  if layer.name=='Draw here' then drawing=layer end
  if layer.name=='Ideas - hide before export' then ideas=layer end
end
assert(under and drawing)
local drawn=Image(drawing:cel(1).image)
local sheet=Image(512,448,ColorMode.RGB)
local byMask={}
for i,mask in ipairs(masks) do
  local image=cell(mask)
  byMask[mask]=image
  sheet:drawImage(image,Point(((i-1)%8)*64,64+math.floor((i-1)/8)*64))
end
for _,a in ipairs(masks) do for _,b in ipairs(masks) do
  if (a&2)~=0 and (b&8)~=0 then
    for y=8,TOP-8 do
      assert(pc.rgbaA(byMask[a]:getPixel(63,y))==255 and pc.rgbaA(byMask[b]:getPixel(0,y))==255,'east-west seam '..a..' '..b)
    end
  end
end end
local base=path:match('([^/\\]+)%.aseprite$')
sprite:saveCopyAs(work..base..'-before-ideas-'..os.date('%Y%m%d-%H%M%S')..'.aseprite')
if not ideas then
  ideas=sprite:newLayer()
  ideas.name='Ideas - hide before export'
  sprite:newCel(ideas,1,sheet,Point(0,0))
else
  ideas:cel(1).image=sheet
  ideas:cel(1).position=Point(0,0)
end
ideas.stackIndex=under.stackIndex+1
drawing.stackIndex=#sprite.layers
app.layer=drawing
sprite:saveAs(path)
sprite:close()
local reopened=assert(app.open(path))
for _,layer in ipairs(reopened.layers) do
  if layer.name=='Draw here' then assert(layer:cel(1).image:isEqual(drawn)) end
end
reopened:close()
local map={
  '##############',
  '#......#.....#',
  '#.##...#..#..#',
  '#.##.......#.#',
  '#....###.....#',
  '#.#..#.#..##.#',
  '#....###..##.#',
  '#.........#..#',
  '###..##......#',
  '##############',
}
local function wall(x,y)
  if y<1 or y>#map or x<1 or x>#map[1] then return true end
  return map[y]:sub(x,x)=='#'
end
local preview=Image(#map[1]*64,#map*64,ColorMode.RGB)
for y=1,#map do for x=1,#map[1] do
  local px,py=(x-1)*64,(y-1)*64
  for yy=0,63 do for xx=0,63 do preview:putPixel(px+xx,py+yy,P.ground) end end
end end
for y=1,#map do for x=1,#map[1] do
  if wall(x,y) then
    local N,E,S,W=wall(x,y-1),wall(x+1,y),wall(x,y+1),wall(x-1,y)
    local m=(N and 1 or 0)|(E and 2 or 0)|(S and 4 or 0)|(W and 8 or 0)
    if N and E and wall(x+1,y-1) then m=m|16 end
    if S and E and wall(x+1,y+1) then m=m|32 end
    if S and W and wall(x-1,y+1) then m=m|64 end
    if N and W and wall(x-1,y-1) then m=m|128 end
    local image=assert(byMask[m],'mask '..m)
    for yy=0,63 do for xx=0,63 do
      local p=image:getPixel(xx,yy)
      if pc.rgbaA(p)>0 then preview:putPixel((x-1)*64+xx,(y-1)*64+yy,p) end
    end end
  end
end end
preview:saveAs(work..base..'-ideas-preview.png')
