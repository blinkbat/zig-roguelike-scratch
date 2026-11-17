local pc=app.pixelColor
return function(image,position)
  local source=Image(512,448,ColorMode.RGB)
  source:drawImage(image,position)
  local wall={source=source,tan=source:getPixel(30,87)}
  assert(wall.tan==pc.rgba(202,158,106,255))
  function wall.sample(x,y) return source:getPixel(x,y) end
  function wall.sideRow(y)
    if y==0 or y==63 then return 80 end
    return 67+(y+13)%30
  end
  function wall.decorate(target,inside,offsets)
    for _,at in ipairs(offsets) do
      local safe=true
      for y=at[2]-3,at[2]+12 do for x=at[1]-3,at[1]+12 do
        if not inside(x,y) then safe=false end
      end end
      if safe then
        for y=0,9 do for x=0,9 do target:putPixel(at[1]+x,at[2]+y,source:getPixel(24+x,87+y)) end end
      end
    end
  end
  return wall
end
