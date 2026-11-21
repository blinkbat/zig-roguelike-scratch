local pc=app.pixelColor
return function(image,position,masks)
  local source=Image(masks.W,masks.SHEET_H,ColorMode.RGB)
  source:drawImage(image,position)
  local wall={source=source,tan=source:getPixel(30,87)}
  assert(wall.tan==pc.rgba(202,158,106,255))
  function wall.sample(x,y) return source:getPixel(x,y) end
  wall.EDGE,wall.CAP,wall.FACE_TOP=4,6,99
  function wall.brick(x,row) return source:getPixel(154+x%32,row) end
  function wall.faceEdge(east,d,row) return source:getPixel(east and 43-d or 18+d,row) end
  function wall.side(east,d,row) return source:getPixel(east and 108-d or 83+d,row) end
  function wall.capTop(x,dy) return source:getPixel(160+x%32,83+dy) end
  function wall.capCorner(east,d,dy) return wall.faceEdge(east,d,83+dy) end
  function wall.sideRow(y)
    if y==0 or y==masks.CELL-1 then return 80 end
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
