local rgba=app.pixelColor.rgba
local bands={'dry','shallow','deep','shallow_face','deep_face'}
local out={dry={},shallow={},deep={},shallow_face={},deep_face={},darken={},bands=bands,band={}}
for i,name in ipairs(bands) do out.band[name]=i-1 end
for _,rgb in ipairs({{128,115,84},{97,73,68},{189,166,107},{149,126,105},{97,78,62},{62,40,22},{211,166,127}}) do
 out.dry[rgba(rgb[1],rgb[2],rgb[3],255)]=true
end
for _,pair in ipairs({
 {{119,146,185},{71,88,111}},
 {{166,197,242},{100,118,145}},
 {{54,75,106},{32,45,64},face=true},
 {{88,111,145},{52,69,92},face=true},
 {{255,255,255},{153,153,153}},
}) do
 local shallow=rgba(pair[1][1],pair[1][2],pair[1][3],255)
 local deep=rgba(pair[2][1],pair[2][2],pair[2][3],255)
 out.shallow[shallow],out.deep[deep],out.darken[shallow]=true,true,deep
 if pair.face then out.shallow_face[shallow],out.deep_face[deep]=true,true end
end
return out
