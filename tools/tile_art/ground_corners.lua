-- Row-major 4x4 dual-grid masks: NW 1, NE 2, SW 4, SE 8; shared corners match, mask 0 is empty.
return {
  9, 12, 4, 8,
  10, 15, 13, 14,
  6, 11, 7, 3,
  5, 2, 1, 0,
}
