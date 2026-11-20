local names={
blocks={'Land to shallows','Land to deep water','Shallows to deep water'},
parts={{'bare','Ground'},{'faces','Cliff faces'},{'caps','Lip and cap fill'},{'edges','Authored border edits'}},
owner='Owner flat border edits',
extended='Deep border extensions from shallow edits',
}
function names.label(tag)
  for _,part in ipairs(names.parts) do if part[1]==tag then return part[2] end end
  error('No water cliff part '..tag)
end
function names.layer(block,tag) return names.blocks[block]..' - '..names.label(tag) end
return names
