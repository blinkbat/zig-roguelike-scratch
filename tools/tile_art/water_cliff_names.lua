local names={
blocks={'Land to shallows','Land to deep water','Shallows to deep water'},
edge_files={'dirt-shallows-edges','dirt-water-edges','shallows-water-edges'},
parts={{'bare','Ground'},{'faces','Cliff faces'},{'caps','Lip and cap fill'},{'edges','Authored border edits'}},
depths={'shallow','deep'},
face_files={'shallows-cliff','water-cliff'},
pieces={'left','repeat','right'},
owner='Owner flat border edits',
extended='Deep border extensions from shallow edits',
SEP=' - ',
slice_format='water_cliff_%s_%s',
}
names.LAND_SHALLOWS,names.LAND_DEEP,names.SHALLOWS_DEEP=1,2,3
names.dry={[names.LAND_SHALLOWS]=true,[names.LAND_DEEP]=true}
names.face={[names.LAND_SHALLOWS]='shallow_face',[names.LAND_DEEP]='deep_face',[names.SHALLOWS_DEEP]='deep_face'}
function names.label(tag)
  for _,part in ipairs(names.parts) do if part[1]==tag then return part[2] end end
  error('No water cliff part '..tag)
end
function names.layer(block,tag) return names.blocks[block]..names.SEP..names.label(tag) end
function names.slice(depth,piece) return names.slice_format:format(depth,piece) end
function names.faceFile(depth)
  for i,d in ipairs(names.depths) do if d==depth then return names.face_files[i] end end
  error('No water cliff depth '..depth)
end
return names
