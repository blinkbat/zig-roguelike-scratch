-- A ground sheet's 16 dual-grid cells, read across its 4x4 block: each is drawn where four map cells meet, and its
-- mask says which of them hold the terrain (NW 1, NE 2, SW 4, SE 8). Neighbouring cells agree on the corners they
-- share, so the block paints as one continuous shape; mask 0 holds nothing.
return {
  9, 12, 4, 8,
  10, 15, 13, 14,
  6, 11, 7, 3,
  5, 2, 1, 0,
}
