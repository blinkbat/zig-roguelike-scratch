const std = @import("std");
const mathx = @import("../core/mathx.zig");

const P = mathx.P;

pub const W: i32 = 96;
pub const H: i32 = 64;
pub const CELLS: usize = @intCast(W * H);
/// One bit a cell, by `Level.idx`.
pub const CellSet = std.StaticBitSet(CELLS);
pub const COLS: usize = @intCast(W);
pub const ROWS: usize = @intCast(H);
/// The points where cells meet, the map's edges included.
pub const CORNERS_W: usize = COLS + 1;
pub const CORNERS_H: usize = ROWS + 1;
pub const SIZE = P{ .x = W, .y = H };
pub const MIDDLE = P{ .x = @divTrunc(W, 2), .y = @divTrunc(H, 2) };

pub const NO_ONE: u16 = 0;
pub const MAX_TORCHES: usize = 32;
/// Only the first this many glowing tiles give light (`Level.glowing`).
pub const MAX_GLOWS: usize = 64;
pub const MAX_DOORS: usize = 16;
pub const NO_DOOR: u8 = 0;
pub const NO_NPC: u8 = 0;

pub const Tile = enum(u8) {
    /// Built, and shaped by `gen.shapeWalls`.
    wall,
    floor,
    grass,
    shrub,
    /// Natural stone: a cave's walls, a cliff, a crag.
    rock,
    dirt,
    sand,
    snow,
    water,
    shallows,
    bridge,
    reeds,
    rubble,
    fence,
    lava,
    fungus,
    chasm,
    ice,
    grave,
    crop,
    tiny_shrub,
    boulder,
    tall_grass,
    shrooms,
    chest,
    chest_open,
    swamp_tree,
    large_tree,
    glow_plant,
    /// Stands on its cell and the `.caravan_part` right of it, its picture rising into the row above.
    caravan,
    caravan_part,
    stone_bridge,

    pub fn solid(t: Tile) bool {
        return TERRAIN.getPtrConst(t).solid;
    }

    pub fn blind(t: Tile) bool {
        return TERRAIN.getPtrConst(t).blind;
    }

    /// What lies under it: drawn first, beneath its own picture.
    pub fn ground(t: Tile) ?Tile {
        return TERRAIN.getPtrConst(t).ground;
    }

    /// Water, lava or a chasm, which a trail crosses by a bridge.
    pub fn liquid(t: Tile) bool {
        return TERRAIN.getPtrConst(t).liquid;
    }

    /// The bridge over liquid `t`: `span` over water, stone over lava or a chasm, which a burnt bridge must not leave as water.
    pub fn spannedBy(t: Tile, span: Tile) Tile {
        std.debug.assert(t.liquid() and span.spans());
        return if (t.wet()) span else .stone_bridge;
    }

    /// Deep water or shallows.
    pub fn wet(t: Tile) bool {
        return TERRAIN.getPtrConst(t).wet;
    }

    pub fn upright(t: Tile) bool {
        return t.solid() and !t.liquid();
    }

    /// Seen past, but stops a missile.
    pub fn halts(t: Tile) bool {
        return TERRAIN.getPtrConst(t).halts;
    }

    /// Plain dry ground a chest or barrel may be placed on.
    pub fn rewards(t: Tile) bool {
        return TERRAIN.getPtrConst(t).rewards;
    }

    pub fn opened(t: Tile) ?Tile {
        return TERRAIN.getPtrConst(t).opens;
    }

    /// Lights the cells round it as a torch does.
    pub fn glows(t: Tile) bool {
        return TERRAIN.getPtrConst(t).glows;
    }

    /// Bursts into healing gas when stepped into or struck, leaving its ground.
    pub fn bursts(t: Tile) bool {
        return TERRAIN.getPtrConst(t).bursts;
    }

    /// Catches fire, and burns down to its `fire.ashOf`.
    pub fn burns(t: Tile) bool {
        return TERRAIN.getPtrConst(t).burns;
    }

    /// Catches from any fire beside it, without cooling that fire.
    pub fn tinder(t: Tile) bool {
        return TERRAIN.getPtrConst(t).tinder;
    }

    /// A bridge: walked over a liquid.
    pub fn spans(t: Tile) bool {
        return TERRAIN.getPtrConst(t).spans;
    }

    pub fn isChest(t: Tile) bool {
        return t == .chest or t == .chest_open;
    }

    /// What another tile becomes when opened, never placed as it is.
    pub fn isOpened(t: Tile) bool {
        return OPENED.contains(t);
    }

    /// Given a `WallShape` by `gen.shapeWalls`, joining its own kind.
    pub fn shaped(t: Tile) bool {
        return TERRAIN.getPtrConst(t).shaped;
    }

    /// Cells from its own rightward that it stands on.
    pub fn wide(t: Tile) i32 {
        return TERRAIN.getPtrConst(t).wide;
    }

    /// The rest of a wider prop's footprint, drawn by the prop.
    pub fn isPart(t: Tile) bool {
        return TERRAIN.getPtrConst(t).part;
    }

    pub fn partOf(t: Tile) ?Tile {
        return TERRAIN.getPtrConst(t).piece;
    }

    /// A wider prop or a part of one.
    pub fn pieced(t: Tile) bool {
        return t.wide() > 1 or t.isPart();
    }

    /// What is left when it goes: its ground, or bare floor.
    pub fn bare(t: Tile) Tile {
        return t.ground() orelse .floor;
    }

    /// Upright and pictured for itself, not as the rest of a wider prop.
    pub fn uprightWhole(t: Tile) bool {
        return t.upright() and !t.isPart();
    }

    /// The cells it stands on from `p`.
    pub fn footprint(t: Tile, p: P) Box {
        return Box.sized(p, t.wide(), 1);
    }

    /// Chosen for a cell on its own: by the palette or a generator; never one opened or a piece of a wider prop.
    pub fn single(t: Tile) bool {
        return !t.isOpened() and !t.pieced();
    }

    pub fn letter(t: Tile) u8 {
        return switch (t) {
            .wall => '#',
            .floor => '.',
            .grass => '"',
            .shrub => '&',
            .rock => '%',
            .dirt => ',',
            .sand => ':',
            .snow => '*',
            .water => '~',
            .shallows => '-',
            .bridge => '=',
            .reeds => '|',
            .rubble => ';',
            .fence => '+',
            .lava => '!',
            .fungus => 'T',
            .chasm => 'v',
            .ice => 'i',
            .grave => 't',
            .crop => 'w',
            .tiny_shrub => '\'',
            .boulder => 'o',
            .tall_grass => 'y',
            .shrooms => 'm',
            .chest => 'C',
            .chest_open => 'O',
            .swamp_tree => 'S',
            .large_tree => 'L',
            .glow_plant => 'p',
            .caravan => 'H',
            .caravan_part => 'h',
            .stone_bridge => 'B',
        };
    }

    pub fn ofLetter(c: u8) ?Tile {
        for (std.enums.values(Tile)) |t| {
            if (t.letter() == c) return t;
        }
        return null;
    }
};

/// `BARREL_GROUND` with a barrel on it.
pub const BARREL_LETTER = '0';
pub const BARREL_GROUND: Tile = .floor;

pub fn groundOf(c: u8) ?Tile {
    return if (c == BARREL_LETTER) BARREL_GROUND else Tile.ofLetter(c);
}

/// Every wider prop has its parts beside it, and every part its prop.
pub fn propsWhole(tile: *const [CELLS]Tile) bool {
    for (0..CELLS) |i| {
        if (!propWhole(tile, i)) return false;
    }
    return true;
}

fn propWhole(tile: *const [CELLS]Tile, i: usize) bool {
    const t = tile[i];
    if (t.isPart()) return headOf(tile, i) != null;
    if (Level.of(i).x + t.wide() > W) return false;
    for (1..@intCast(t.wide())) |k| {
        if (!tile[i + k].isPart()) return false;
    }
    return true;
}

/// The wider prop whose footprint holds `i`: `i` itself, or the prop the parts left of it lead back to.
pub fn headOf(tile: *const [CELLS]Tile, i: usize) ?usize {
    var lo = i;
    while (tile[lo].isPart() and Level.of(lo).x > 0) lo -= 1;
    const wide: usize = @intCast(tile[lo].wide());
    return if (wide > 1 and lo + wide > i) lo else null;
}

/// Every wider prop cut short and every part without its prop, back to its ground.
pub fn mendProps(tile: *[CELLS]Tile) void {
    for (0..CELLS) |i| {
        if (!propWhole(tile, i)) tile[i] = tile[i].bare();
    }
}

/// The cells of the wider prop covering `i`, its head to the end of its parts.
pub fn propSpan(tile: *const [CELLS]Tile, i: usize) ?struct { head: usize, end: usize } {
    const head = headOf(tile, i) orelse return null;
    var end = head + 1;
    while (end < head + @as(usize, @intCast(tile[head].wide())) and Level.of(end).x > 0 and tile[end].isPart()) end += 1;
    return .{ .head = head, .end = end };
}

pub fn layProp(tile: *[CELLS]Tile, p: P, t: Tile) void {
    var k: i32 = 0;
    while (k < t.wide()) : (k += 1) {
        const q = p.add(.{ .x = k, .y = 0 });
        if (Level.inside(q)) tile[Level.idx(q)] = if (k == 0) t else t.partOf().?;
    }
}

/// The whole wider prop covering `i`, if one does, back to its ground.
pub fn unprop(tile: *[CELLS]Tile, i: usize) void {
    const span = propSpan(tile, i) orelse return;
    for (tile[span.head..span.end]) |*t| t.* = t.bare();
}

comptime {
    @setEvalBranchQuota(100_000);
    std.debug.assert(Tile.ofLetter(BARREL_LETTER) == null);
    for (std.enums.values(Tile), 0..) |a, i| {
        std.debug.assert(std.ascii.isPrint(a.letter()) and a.letter() != ' ');
        std.debug.assert(!a.liquid() or a.solid());
        std.debug.assert(!a.bursts() or a.ground() != null);
        std.debug.assert(a.wide() >= 1 and !(a.isPart() and a.wide() > 1));
        std.debug.assert((a.wide() > 1) == (a.partOf() != null));
        if (a.partOf()) |q| std.debug.assert(q.isPart());
        for (std.enums.values(Tile)[0..i]) |b| std.debug.assert(a.letter() != b.letter());
    }
}

const Terrain = struct {
    solid: bool,
    blind: bool,
    ground: ?Tile = null,
    liquid: bool = false,
    halts: bool = false,
    rewards: bool = false,
    litter: bool = false,
    wet: bool = false,
    shaped: bool = false,
    opens: ?Tile = null,
    glows: bool = false,
    bursts: bool = false,
    burns: bool = false,
    tinder: bool = false,
    spans: bool = false,
    wide: u8 = 1,
    part: bool = false,
    piece: ?Tile = null,
};
const OPEN = Terrain{ .solid = false, .blind = false };
const BARE = Terrain{ .solid = false, .blind = false, .rewards = true };
const KINDLING = Terrain{ .solid = false, .blind = false, .rewards = true, .burns = true };
const LITTER = Terrain{ .solid = false, .blind = false, .ground = .grass, .rewards = true, .litter = true, .burns = true };
const SHUT = Terrain{ .solid = true, .blind = true };
const MOAT = Terrain{ .solid = true, .blind = false };
const LIQUID = Terrain{ .solid = true, .blind = false, .liquid = true };
const DECOR = Terrain{ .solid = false, .blind = false, .ground = .grass };
const TALL_PROP = Terrain{ .solid = true, .blind = true, .ground = .grass };
const LOW_PROP = Terrain{ .solid = true, .blind = false, .ground = .grass };
const CART = Terrain{ .solid = true, .blind = true, .ground = .grass, .wide = 2, .piece = .caravan_part };
const CART_PART = Terrain{ .solid = true, .blind = true, .ground = .grass, .part = true };

const TERRAIN = std.EnumArray(Tile, Terrain).init(.{
    .wall = .{ .solid = true, .blind = true, .shaped = true },
    .floor = BARE,
    .grass = KINDLING,
    .shrub = .{ .solid = true, .blind = true, .ground = .grass, .shaped = true },
    .rock = SHUT,
    .dirt = BARE,
    .sand = BARE,
    .snow = OPEN,
    .water = .{ .solid = true, .blind = false, .liquid = true, .wet = true },
    .shallows = .{ .solid = false, .blind = false, .wet = true },
    .bridge = .{ .solid = false, .blind = false, .burns = true, .spans = true },
    .reeds = .{ .solid = false, .blind = true, .ground = .grass, .burns = true, .tinder = true },
    .rubble = BARE,
    .fence = MOAT,
    .lava = LIQUID,
    .fungus = .{ .solid = true, .blind = true, .ground = .dirt },
    .chasm = LIQUID,
    .ice = OPEN,
    .grave = LOW_PROP,
    .crop = .{ .solid = false, .blind = true, .burns = true },
    .tiny_shrub = LITTER,
    .boulder = TALL_PROP,
    .tall_grass = LITTER,
    .shrooms = LITTER,
    .chest = .{ .solid = true, .blind = false, .ground = .grass, .halts = true, .opens = .chest_open },
    .chest_open = DECOR,
    .swamp_tree = .{ .solid = true, .blind = true, .ground = .dirt },
    .large_tree = TALL_PROP,
    .glow_plant = .{ .solid = true, .blind = false, .ground = .grass, .glows = true, .bursts = true },
    .caravan = CART,
    .caravan_part = CART_PART,
    .stone_bridge = .{ .solid = false, .blind = false, .spans = true },
});

/// The most cells any prop stands on.
pub const WIDEST: i32 = blk: {
    var most: i32 = 1;
    for (TERRAIN.values) |r| most = @max(most, r.wide);
    break :blk most;
};

fn tilesWhere(comptime has: fn (Tile) bool) std.EnumSet(Tile) {
    @setEvalBranchQuota(10_000);
    var set = std.EnumSet(Tile).initEmpty();
    for (std.enums.values(Tile)) |t| set.setPresent(t, has(t));
    return set;
}

const OPENED = tilesWhere(struct {
    fn of(t: Tile) bool {
        for (TERRAIN.values) |r| {
            if (r.opens == t) return true;
        }
        return false;
    }
}.of);

/// Small plants strewn over grass, stepped through.
pub const LITTER_TILES = tilesWhere(struct {
    fn of(t: Tile) bool {
        return TERRAIN.getPtrConst(t).litter;
    }
}.of);

/// Every `single` tile, in order: the palette's choices.
pub const SINGLES = blk: {
    var out: []const Tile = &.{};
    for (std.enums.values(Tile)) |t| {
        if (t.single()) out = out ++ &[_]Tile{t};
    }
    break :blk out;
};

/// A generator knob of type `T` may hold `v`: any value but a tile that is not `single`.
pub fn knobbable(comptime T: type, v: T) bool {
    if (T != Tile) return true;
    return v.single();
}

/// Same-material neighbours, stamped by `gen.shapeWalls`; its bits are the wall sheets' masks.
pub const WallShape = packed struct(u8) {
    n: bool = false,
    e: bool = false,
    s: bool = false,
    w: bool = false,
    ne: bool = false,
    se: bool = false,
    sw: bool = false,
    nw: bool = false,

    /// A corner joins only where both sides beside it do, which leaves 47 shapes of the 256.
    pub fn joined(raw: WallShape) WallShape {
        var j = raw;
        j.ne = raw.ne and raw.n and raw.e;
        j.se = raw.se and raw.s and raw.e;
        j.sw = raw.sw and raw.s and raw.w;
        j.nw = raw.nw and raw.n and raw.w;
        return j;
    }

    pub fn mask(shape: WallShape) u8 {
        return @bitCast(shape);
    }

    /// No wall below it, so its brick face shows.
    pub fn faced(shape: WallShape) bool {
        return !shape.s;
    }

    pub fn solid(shape: WallShape) bool {
        return shape.mask() == 0xFF;
    }
};

pub const Torches = struct {
    at: [MAX_TORCHES]P = undefined,
    n: usize = 0,

    pub const COUNTED = .{.{ "at", "n" }};

    pub fn slice(self: *const Torches) []const P {
        return self.at[0..self.n];
    }

    fn find(self: *const Torches, p: P) ?usize {
        for (self.slice(), 0..) |t, i| {
            if (t.eq(p)) return i;
        }
        return null;
    }

    pub fn has(self: *const Torches, p: P) bool {
        return self.find(p) != null;
    }

    pub fn takes(self: *const Torches, p: P) bool {
        return self.n < MAX_TORCHES and self.find(p) == null;
    }

    pub fn add(self: *Torches, p: P) bool {
        return self.takes(p) and mathx.push(P, &self.at, &self.n, p);
    }

    pub fn remove(self: *Torches, p: P) bool {
        _ = mathx.swapRemove(P, &self.at, &self.n, self.find(p) orelse return false);
        return true;
    }

    pub fn keep(self: *Torches, ctx: anytype, comptime fits: fn (@TypeOf(ctx), P) bool) void {
        var kept: usize = 0;
        for (self.slice()) |t| {
            if (!fits(ctx, t)) continue;
            self.at[kept] = t;
            kept += 1;
        }
        self.n = kept;
    }
};

pub const Gas = enum {
    caustic,
    healing,
    steam,
    smoke,

    pub fn harms(self: Gas) bool {
        return switch (self) {
            .caustic, .steam => true,
            .healing, .smoke => false,
        };
    }
};

/// Smoke at least this thick hides what lies beyond its cell; thinner wisps are seen through.
pub const SMOKE_THICK: u16 = 20;

pub const Level = struct {
    pub const WAS = .{.{ "npc", "folk" }};
    barrier: [CELLS]u8 = @splat(0),
    caltrops: [CELLS]struct { turns: u8 = 0, rank: u8 = 0 } = @splat(.{}),
    flames: [CELLS]u8 = @splat(0),
    tile: [CELLS]Tile,
    /// Null on anything that is neither a wall nor a forest tile.
    shape: [CELLS]?WallShape,
    seen: [CELLS]bool,
    /// In the hero's sight: in its line of sight and light enough to see.
    lit: [CELLS]bool,
    /// In the hero's line of sight, light or dark.
    los: [CELLS]bool,
    /// 1-based into the actor pool; `NO_ONE` is empty.
    occupant: [CELLS]u16,
    barrel: [CELLS]bool,
    /// Each seen cell's barrel as the hero last saw it.
    barrel_seen: [CELLS]bool,
    /// 1-based into the map's doors; `NO_DOOR` is none.
    door: [CELLS]u8,
    /// Caustic gas, Brogue's volume.
    gas: [CELLS]u16,
    torch: Torches,
    /// 1-based into the map's NPCs; `NO_NPC` is none. The legacy save reader takes the fields before it.
    npc: [CELLS]u8 = @splat(NO_NPC),
    /// Healing gas, Brogue's volume.
    healing: [CELLS]u16 = @splat(0),
    /// Steam boiled off water by fire, Qud's.
    steam: [CELLS]u16 = @splat(0),
    /// Smoke, Brogue's: it hides what lies past it.
    smoke: [CELLS]u16 = @splat(0),
    /// How many more cells a burning cell's fire may leap on.
    heat: [CELLS]u8 = @splat(0),
    /// Turns until frozen shallows thaw; 0 on ice that never does.
    thaw: [CELLS]u8 = @splat(0),

    pub fn blank() Level {
        return .{
            .tile = [_]Tile{.wall} ** CELLS,
            .shape = [_]?WallShape{null} ** CELLS,
            .seen = [_]bool{false} ** CELLS,
            .lit = [_]bool{false} ** CELLS,
            .los = [_]bool{false} ** CELLS,
            .occupant = [_]u16{NO_ONE} ** CELLS,
            .barrel = [_]bool{false} ** CELLS,
            .barrel_seen = [_]bool{false} ** CELLS,
            .door = [_]u8{NO_DOOR} ** CELLS,
            .gas = [_]u16{0} ** CELLS,
            .torch = .{},
        };
    }

    pub fn torches(self: *const Level) []const P {
        return self.torch.slice();
    }

    /// The glowing tiles that give light: the first `MAX_GLOWS` in reading order.
    pub fn glowing(self: *const Level) Glowing {
        return .{ .lv = self };
    }

    pub const Glowing = struct {
        lv: *const Level,
        i: usize = 0,
        n: usize = 0,

        pub fn next(self: *Glowing) ?P {
            while (self.n < MAX_GLOWS and self.i < CELLS) {
                const i = self.i;
                self.i += 1;
                if (!self.lv.tile[i].glows()) continue;
                self.n += 1;
                return Level.of(i);
            }
            return null;
        }
    };

    pub fn addTorch(self: *Level, p: P) void {
        _ = self.torch.add(p);
    }

    pub fn wallShape(self: *const Level, p: P) ?WallShape {
        if (self.at(p) != .wall) return null;
        return self.tileShape(p);
    }

    pub fn tileShape(self: *const Level, p: P) ?WallShape {
        return cellOr(?WallShape, &self.shape, p, null);
    }

    /// Its shape's mask, 0 for a cell with none.
    pub fn tileMask(self: *const Level, p: P) u8 {
        return (self.tileShape(p) orelse WallShape{}).mask();
    }

    pub fn inside(p: P) bool {
        return p.x >= 0 and p.y >= 0 and p.x < W and p.y < H;
    }

    pub fn clamp(p: P) P {
        return Box.inMap(0).clamp(p);
    }

    /// The nearest cell off the map's edge.
    pub fn inset(p: P) P {
        return Box.inMap(1).clamp(p);
    }

    /// Cells in from the nearest edge: 0 on the rim.
    pub fn edgeDist(p: P) i32 {
        return Box.inMap(0).edgeDist(p);
    }

    pub fn firstOpen(self: *const Level) ?P {
        for (&self.tile, 0..) |t, i| {
            if (!t.solid()) return of(i);
        }
        return null;
    }

    pub fn openCount(self: *const Level) usize {
        var n: usize = 0;
        for (self.tile) |t| n += @intFromBool(!t.solid());
        return n;
    }

    pub fn onRim(p: P) bool {
        return !inset(p).eq(p);
    }

    /// Bind the index before reading: Zig 0.14 copies the array in `self.tile[idx(p)]` to preserve call order.
    pub fn idx(p: P) usize {
        std.debug.assert(inside(p));
        return @intCast(p.y * W + p.x);
    }

    pub fn of(i: usize) P {
        return mathx.unslot(i, COLS);
    }

    pub fn at(self: *const Level, p: P) Tile {
        return cellOr(Tile, &self.tile, p, .wall);
    }

    pub fn set(self: *Level, p: P, t: Tile) void {
        if (!inside(p)) return;
        self.tile[idx(p)] = t;
    }

    pub fn putProp(self: *Level, p: P, t: Tile) void {
        layProp(&self.tile, p, t);
    }

    pub fn who(self: *const Level, p: P) u16 {
        return cellOr(u16, &self.occupant, p, NO_ONE);
    }

    pub fn stand(self: *Level, p: P, id: u16) void {
        self.occupant[idx(p)] = id;
    }

    pub fn clear(self: *Level, p: P) void {
        self.occupant[idx(p)] = NO_ONE;
    }

    pub fn hasBarrel(self: *const Level, p: P) bool {
        return cellOr(bool, &self.barrel, p, false);
    }

    pub fn putBarrel(self: *Level, p: P) void {
        self.barrel[idx(p)] = true;
    }

    pub fn breakBarrel(self: *Level, p: P) bool {
        if (!self.hasBarrel(p)) return false;
        self.barrel[idx(p)] = false;
        return true;
    }

    pub fn wallBarrels(self: *Level) void {
        for (self.barrel, 0..) |on, i| {
            if (on) self.tile[i] = .wall;
        }
    }

    pub fn doorAt(self: *const Level, p: P) ?usize {
        const d = cellOr(u8, &self.door, p, NO_DOOR);
        return if (d == NO_DOOR) null else d - 1;
    }

    pub fn putDoor(self: *Level, p: P, i: usize) void {
        if (!inside(p)) return;
        const k = idx(p);
        self.tile[k] = .floor;
        self.door[k] = @intCast(i + 1);
    }

    /// Mutable through a mutable level.
    pub fn volumes(self: anytype, kind: Gas) @TypeOf(&self.gas) {
        return switch (kind) {
            .caustic => &self.gas,
            .healing => &self.healing,
            .steam => &self.steam,
            .smoke => &self.smoke,
        };
    }

    /// Nothing past `p` is seen through it: an opaque tile, or smoke thick enough.
    pub fn hidesBeyond(self: *const Level, p: P) bool {
        return self.at(p).blind() or self.volumeAt(.smoke, p) >= SMOKE_THICK;
    }

    pub fn volumeAt(self: *const Level, kind: Gas, p: P) u16 {
        return cellOr(u16, self.volumes(kind), p, 0);
    }

    pub fn gasAt(self: *const Level, p: P) u16 {
        return self.volumeAt(.caustic, p);
    }

    pub fn gassy(self: *const Level, p: P) bool {
        return self.gasAt(p) > 0;
    }

    pub fn scalding(self: *const Level, p: P) bool {
        return self.volumeAt(.steam, p) > 0;
    }

    pub fn harmful(self: *const Level, p: P) bool {
        return for (std.enums.values(Gas)) |kind| {
            if (kind.harms() and self.volumeAt(kind, p) > 0) break true;
        } else false;
    }

    /// Nothing stands up from it: open ground or a liquid, which gas drifts and a drop flies over.
    pub fn flat(self: *const Level, p: P) bool {
        return inside(p) and !self.at(p).upright();
    }

    pub fn addGas(self: *Level, p: P, volume: u16) void {
        self.release(.caustic, p, volume);
    }

    pub fn release(self: *Level, kind: Gas, p: P, volume: u16) void {
        if (!self.flat(p)) return;
        self.volumes(kind)[idx(p)] +|= volume;
    }

    pub fn npcAt(self: *const Level, p: P) ?usize {
        const f = cellOr(u8, &self.npc, p, NO_NPC);
        return if (f == NO_NPC) null else f - 1;
    }

    pub fn putNpc(self: *Level, p: P, i: usize) void {
        self.npc[idx(p)] = @intCast(i + 1);
    }

    pub fn clearNpcs(self: *Level) void {
        self.npc = @splat(NO_NPC);
    }

    /// A body or barrel; NPCs are no target, so not counted.
    pub fn taken(self: *const Level, p: P) bool {
        return self.who(p) != NO_ONE or self.hasBarrel(p);
    }

    /// A body, barrel or NPC stands there.
    pub fn held(self: *const Level, p: P) bool {
        return self.taken(p) or self.npcAt(p) != null;
    }

    pub fn vacant(self: *const Level, p: P) bool {
        return self.walkable(p) and !self.held(p);
    }

    pub fn lightless(self: *Level) void {
        self.lit = [_]bool{false} ** CELLS;
    }

    pub fn light(self: *Level, p: P) void {
        if (!inside(p)) return;
        const i = idx(p);
        self.lit[i] = true;
        self.seen[i] = true;
    }

    pub fn strikeable(self: *const Level, p: P) bool {
        if (!inside(p) or self.hasBarrier(p)) return false;
        const t = self.at(p);
        return !t.solid() or (t.wet() and self.who(p) != NO_ONE);
    }

    /// The cells one step from `from` along `dirs` that a melee blow could reach, in their order.
    pub fn reachable(self: *const Level, comptime N: usize, from: P, dirs: [N]mathx.Dir) Bounded(P, N) {
        var out = Bounded(P, N){};
        for (dirs) |d| {
            const p = from.add(d.delta());
            if (self.strikeable(p)) out.push(p);
        }
        return out;
    }

    pub fn barrelSeen(self: *const Level, p: P) bool {
        return cellOr(bool, &self.barrel_seen, p, false);
    }

    pub fn isLit(self: *const Level, p: P) bool {
        return cellOr(bool, &self.lit, p, false);
    }

    pub fn inLos(self: *const Level, p: P) bool {
        return cellOr(bool, &self.los, p, false);
    }

    pub fn isSeen(self: *const Level, p: P) bool {
        return cellOr(bool, &self.seen, p, false);
    }

    pub fn walkable(self: *const Level, p: P) bool {
        return inside(p) and self.openAt(idx(p));
    }

    /// `walkable`, for a cell known to be inside.
    pub fn openAt(self: *const Level, i: usize) bool {
        return !self.tile[i].solid() and self.barrier[i] == 0;
    }

    pub fn hasBarrier(self: *const Level, p: P) bool {
        return cellOr(u8, &self.barrier, p, 0) > 0;
    }

    pub fn burning(self: *const Level, p: P) bool {
        return cellOr(u8, &self.flames, p, 0) > 0;
    }

    /// Shallows frozen to ice that will thaw back.
    pub fn frozen(self: *const Level, p: P) bool {
        return self.at(p) == .ice and cellOr(u8, &self.thaw, p, 0) > 0;
    }

    /// Terrain only.
    pub fn passOk(self: *const Level, from: P, d: mathx.Dir) bool {
        return self.walkable(from.add(d.delta()));
    }

    /// `ignore` is the mover's own id.
    pub fn stepOk(self: *const Level, from: P, d: mathx.Dir, ignore: u16) bool {
        if (!self.passOk(from, d)) return false;
        const to = from.add(d.delta());
        if (self.hasBarrel(to) or self.npcAt(to) != null) return false;
        const w = self.who(to);
        return w == NO_ONE or w == ignore;
    }
};

/// Of the cells `set.has` takes, the nearest `from`, the first of any tie.
pub fn nearest(from: P, set: anytype) ?P {
    const far: i32 = @intCast(@max(@abs(from.x), @abs(W - 1 - from.x), @abs(from.y), @abs(H - 1 - from.y)));
    var r: i32 = 0;
    while (r <= far) : (r += 1) {
        var ring = mathx.Ring.init(from, r);
        while (ring.next()) |q| {
            if (Level.inside(q) and set.has(Level.idx(q))) return q;
        }
    }
    return null;
}

/// The nearest cell offered within `reach`, by steps and then by the straighter line.
pub const Nearest = struct {
    from: P,
    reach: i32 = std.math.maxInt(i32),
    best: ?P = null,
    best_d: i32 = std.math.maxInt(i32),
    best_line: f32 = std.math.floatMax(f32),

    pub fn offer(n: *Nearest, p: P) void {
        const d = mathx.dist(n.from, p);
        const line = mathx.distEuclid(n.from, p);
        if (d > n.reach or d > n.best_d or (d == n.best_d and line >= n.best_line)) return;
        n.best_d = d;
        n.best_line = line;
        n.best = p;
    }
};

/// Up to `N` of `T`.
pub fn Bounded(comptime T: type, comptime N: usize) type {
    return struct {
        items: [N]T = undefined,
        n: usize = 0,

        pub fn slice(self: *const @This()) []const T {
            return self.items[0..self.n];
        }

        pub fn push(self: *@This(), x: T) void {
            self.items[self.n] = x;
            self.n += 1;
        }

        pub fn has(self: *const @This(), x: T) bool {
            for (self.slice()) |c| {
                if (std.meta.eql(c, x)) return true;
            }
            return false;
        }
    };
}

pub const Box = struct {
    lo: P,
    hi: P,

    pub fn sized(lo: P, w: i32, h: i32) Box {
        return .{ .lo = lo, .hi = lo.add(.{ .x = w, .y = h }) };
    }

    pub fn sizedP(lo: P, size: P) Box {
        return sized(lo, size.x, size.y);
    }

    /// The cells from `a` to `b`, both included, whichever corners they are.
    pub fn between(a: P, b: P) Box {
        return .{ .lo = a.min(b), .hi = a.max(b).add(.{ .x = 1, .y = 1 }) };
    }

    /// Every cell within `r` of `c`, on the map or off it.
    pub fn around(c: P, r: i32) Box {
        return .{ .lo = c.sub(.{ .x = r, .y = r }), .hi = c.add(.{ .x = r + 1, .y = r + 1 }) };
    }

    pub fn inMap(m: i32) Box {
        return .{ .lo = .{ .x = m, .y = m }, .hi = .{ .x = W - m, .y = H - m } };
    }

    pub fn centred(w: i32, h: i32) Box {
        return inMap(0).centredIn(w, h);
    }

    pub fn centredIn(outer: Box, w: i32, h: i32) Box {
        return sized(outer.lo.add(.{ .x = @divTrunc(outer.width() - w, 2), .y = @divTrunc(outer.height() - h, 2) }), w, h);
    }

    /// x is drawn before y.
    pub fn roll(b: Box, rng: *mathx.Rng) P {
        return b.rollFor(rng, 1, 1);
    }

    /// The corner of a `w` by `h` box that lies inside this one; x is drawn before y.
    pub fn rollFor(b: Box, rng: *mathx.Rng, w: i32, h: i32) P {
        const x = rng.range(b.lo.x, b.hi.x - w);
        return .{ .x = x, .y = rng.range(b.lo.y, b.hi.y - h) };
    }

    pub fn rollWhere(b: Box, rng: *mathx.Rng, tries: usize, ctx: anytype, comptime ok: fn (@TypeOf(ctx), P) bool) ?P {
        return b.rollForWhere(rng, 1, 1, tries, ctx, ok);
    }

    pub fn rollForWhere(b: Box, rng: *mathx.Rng, w: i32, h: i32, tries: usize, ctx: anytype, comptime ok: fn (@TypeOf(ctx), P) bool) ?P {
        for (0..tries) |_| {
            const p = b.rollFor(rng, w, h);
            if (ok(ctx, p)) return p;
        }
        return null;
    }

    pub fn width(b: Box) i32 {
        return b.hi.x - b.lo.x;
    }

    pub fn height(b: Box) i32 {
        return b.hi.y - b.lo.y;
    }

    pub fn centre(b: Box) P {
        return b.lo.add(.{ .x = @divTrunc(b.width(), 2), .y = @divTrunc(b.height(), 2) });
    }

    pub fn holds(b: Box, p: P) bool {
        return p.x >= b.lo.x and p.x < b.hi.x and p.y >= b.lo.y and p.y < b.hi.y;
    }

    pub fn cells(b: Box) Cells {
        return Cells.of(b.lo, b.hi);
    }

    pub fn inner(b: Box) Box {
        return b.shrunk(1);
    }

    pub fn shrunk(b: Box, by: i32) Box {
        return .{ .lo = b.lo.add(.{ .x = by, .y = by }), .hi = b.hi.sub(.{ .x = by, .y = by }) };
    }

    pub fn grown(b: Box, by: i32) Box {
        return .{
            .lo = .{ .x = @max(0, b.lo.x - by), .y = @max(0, b.lo.y - by) },
            .hi = .{ .x = @min(W, b.hi.x + by), .y = @min(H, b.hi.y + by) },
        };
    }

    pub fn overlaps(b: Box, o: Box, pad: i32) bool {
        return b.lo.x - pad < o.hi.x and b.hi.x + pad > o.lo.x and b.lo.y - pad < o.hi.y and b.hi.y + pad > o.lo.y;
    }

    /// Cells in from its nearest edge: 0 on it, negative outside.
    pub fn edgeDist(b: Box, p: P) i32 {
        return @min(@min(p.x - b.lo.x, b.hi.x - 1 - p.x), @min(p.y - b.lo.y, b.hi.y - 1 - p.y));
    }

    pub fn onEdge(b: Box, p: P) bool {
        return b.holds(p) and (p.x == b.lo.x or p.y == b.lo.y or p.x == b.hi.x - 1 or p.y == b.hi.y - 1);
    }

    /// Its cell nearest `p`.
    pub fn clamp(b: Box, p: P) P {
        return .{ .x = std.math.clamp(p.x, b.lo.x, b.hi.x - 1), .y = std.math.clamp(p.y, b.lo.y, b.hi.y - 1) };
    }

    pub fn slot(b: Box, p: P) ?usize {
        return mathx.slot(p.x - b.lo.x, p.y - b.lo.y, @intCast(b.width()), @intCast(b.height()));
    }
};

/// `hi` exclusive, row by row.
pub const Cells = struct {
    lo: P,
    hi: P,
    at: P,

    pub fn of(lo: P, hi: P) Cells {
        return .{ .lo = lo, .hi = hi, .at = if (lo.x < hi.x) lo else .{ .x = lo.x, .y = hi.y } };
    }

    pub fn span(r: i32) i32 {
        return r * 2 + 1;
    }

    /// How many cells `around` a cell `r` out walks.
    pub fn square(r: i32) i32 {
        return span(r) * span(r);
    }

    pub fn around(c: P, r: i32) Cells {
        return Box.around(c, r).cells();
    }

    pub fn next(self: *Cells) ?P {
        if (self.at.y >= self.hi.y) return null;
        const p = self.at;
        self.at.x += 1;
        if (self.at.x == self.hi.x) self.at = .{ .x = self.lo.x, .y = p.y + 1 };
        return p;
    }
};

pub fn cellOr(comptime T: type, cells: *const [CELLS]T, p: P, outside: T) T {
    if (!Level.inside(p)) return outside;
    const i = Level.idx(p);
    return cells[i];
}

/// Terrain only; -1 where nothing reaches. How many cells it reached.
pub fn distances(lv: *const Level, from: P, out: *[CELLS]i32, queue: *[CELLS]u32) usize {
    var flood = Flood.init(lv, from, out, queue);
    while (flood.next()) |_| {}
    return flood.tail;
}

pub const TEST_SEED_STRIDE = 7919;

pub fn expectAllReached(lv: *const Level, from: P, out: *[CELLS]i32, queue: *[CELLS]u32) !void {
    try std.testing.expectEqual(lv.openCount(), distances(lv, from, out, queue));
}

/// `dist` fills as it goes.
pub const Flood = struct {
    lv: *const Level,
    dist: *[CELLS]i32,
    queue: *[CELLS]u32,
    head: usize = 0,
    tail: usize = 0,

    pub fn init(lv: *const Level, from: P, dist: *[CELLS]i32, queue: *[CELLS]u32) Flood {
        @memset(dist, -1);
        var f = Flood{ .lv = lv, .dist = dist, .queue = queue };
        f.seed(from);
        return f;
    }

    /// Another cell the flood starts from, unless it already reached it.
    pub fn seed(self: *Flood, from: P) void {
        const s = Level.idx(from);
        if (self.dist[s] >= 0) return;
        self.dist[s] = 0;
        self.queue[self.tail] = @intCast(s);
        self.tail += 1;
    }

    pub fn next(self: *Flood) ?P {
        if (self.head == self.tail) return null;
        const i = self.queue[self.head];
        self.head += 1;
        const here = Level.of(i);
        for (STEPS) |d| {
            const q = here.add(d);
            if (!Level.inside(q)) continue;
            const qi = Level.idx(q);
            if (self.dist[qi] >= 0 or !self.lv.openAt(qi)) continue;
            self.dist[qi] = self.dist[i] + 1;
            self.queue[self.tail] = @intCast(qi);
            self.tail += 1;
        }
        return here;
    }
};

/// Every neighbour's offset, in `mathx.ALL_DIRS` order.
pub const STEPS = blk: {
    var out: [mathx.ALL_DIRS.len]P = undefined;
    for (mathx.ALL_DIRS, &out) |d, *s| s.* = d.delta();
    break :blk out;
};

/// Breadth first from its seeds over the cells `steps` join that `ok` takes; a cell's neighbours are looked at only once `next` has given it.
pub fn Spread(comptime Ctx: type, comptime ok: fn (Ctx, P) bool) type {
    return struct {
        ctx: Ctx,
        steps: []const P,
        seen: *CellSet,
        queue: *[CELLS]u32,
        head: usize = 0,
        tail: usize = 0,
        given: bool = false,

        pub fn seed(self: *@This(), p: P) void {
            const i = Level.idx(p);
            if (self.seen.isSet(i)) return;
            self.seen.set(i);
            self.queue[self.tail] = @intCast(i);
            self.tail += 1;
        }

        pub fn next(self: *@This()) ?P {
            if (self.given) {
                self.given = false;
                const here = Level.of(self.queue[self.head - 1]);
                for (self.steps) |d| {
                    const q = here.add(d);
                    if (!Level.inside(q) or self.seen.isSet(Level.idx(q)) or !ok(self.ctx, q)) continue;
                    self.seed(q);
                }
            }
            if (self.head == self.tail) return null;
            self.head += 1;
            self.given = true;
            return Level.of(self.queue[self.head - 1]);
        }
    };
}

/// Bresenham from the cell after `from` up to and including `to`.
pub const Ray = struct {
    x: i32,
    y: i32,
    tx: i32,
    ty: i32,
    dx: i32,
    dy: i32,
    sx: i32,
    sy: i32,
    err: i32,
    done: bool,

    pub fn init(from: P, to: P) Ray {
        const dx: i32 = @intCast(@abs(to.x - from.x));
        const dy: i32 = @intCast(@abs(to.y - from.y));
        return .{
            .x = from.x,
            .y = from.y,
            .tx = to.x,
            .ty = to.y,
            .dx = dx,
            .dy = dy,
            .sx = if (to.x > from.x) 1 else -1,
            .sy = if (to.y > from.y) 1 else -1,
            .err = dx - dy,
            .done = from.eq(to),
        };
    }

    pub fn next(self: *Ray) ?P {
        if (self.done) return null;
        const e2 = self.err * 2;
        if (e2 > -self.dy) {
            self.err -= self.dy;
            self.x += self.sx;
        }
        if (e2 < self.dx) {
            self.err += self.dx;
            self.y += self.sy;
        }
        if (self.x == self.tx and self.y == self.ty) self.done = true;
        return .{ .x = self.x, .y = self.y };
    }
};

/// The target's own cell may be opaque.
pub fn clearLine(lv: *const Level, from: P, to: P) bool {
    return lineOk(lv, from, to, .{});
}

/// `clearLine` for eyes: thick smoke hides what lies past it too.
pub fn sightLine(lv: *const Level, from: P, to: P) bool {
    return lineOk(lv, from, to, .{ .smoke = true });
}

pub fn projectileLine(lv: *const Level, from: P, to: P) bool {
    return lineOk(lv, from, to, .{ .projectiles = true });
}

/// `projectileLine`, and every cell on it lit, the target's too.
pub fn litLine(lv: *const Level, from: P, to: P) bool {
    return lineOk(lv, from, to, .{ .lit = true, .projectiles = true });
}

const LineRule = struct { lit: bool = false, projectiles: bool = false, smoke: bool = false };

fn lineOk(lv: *const Level, from: P, to: P, comptime rule: LineRule) bool {
    var ray = Ray.init(from, to);
    while (ray.next()) |c| {
        if (rule.lit and !lv.isLit(c)) return false;
        if (rule.projectiles and lv.hasBarrier(c)) return false;
        if (c.eq(to)) return true;
        if (if (rule.smoke) lv.hidesBeyond(c) else lv.at(c).blind()) return false;
    }
    return true;
}

pub fn openFloor() Level {
    var lv = Level.blank();
    for (0..CELLS) |i| {
        const p = Level.of(i);
        if (!Level.onRim(p)) lv.tile[i] = .floor;
    }
    return lv;
}

test "an index round-trips" {
    for ([_]P{ .{ .x = 0, .y = 0 }, .{ .x = W - 1, .y = H - 1 }, .{ .x = 37, .y = 41 } }) |p| {
        try std.testing.expectEqual(p, Level.of(Level.idx(p)));
    }
    try std.testing.expect(!Level.inside(.{ .x = -1, .y = 0 }));
    try std.testing.expect(!Level.inside(.{ .x = W, .y = 0 }));
}

test "a caravan stands whole on its cell and the part beside it, blocking both" {
    var tile: [CELLS]Tile = @splat(.grass);
    try std.testing.expect(propsWhole(&tile));
    tile[Level.idx(.{ .x = 4, .y = 3 })] = .caravan;
    try std.testing.expect(!propsWhole(&tile));
    tile[Level.idx(.{ .x = 5, .y = 3 })] = .caravan_part;
    try std.testing.expect(propsWhole(&tile));
    tile[Level.idx(.{ .x = 6, .y = 3 })] = .caravan_part;
    try std.testing.expect(!propsWhole(&tile));
    tile[Level.idx(.{ .x = 6, .y = 3 })] = .grass;
    tile[Level.idx(.{ .x = W - 1, .y = 8 })] = .caravan;
    try std.testing.expect(!propsWhole(&tile));
    tile[Level.idx(.{ .x = W - 1, .y = 8 })] = .grass;
    tile[Level.idx(.{ .x = 0, .y = 9 })] = .caravan_part;
    try std.testing.expect(!propsWhole(&tile));
    for ([_]Tile{ .caravan, .caravan_part }) |t| try std.testing.expect(t.solid() and t.blind() and !t.single());
}

test "breaking or cutting a caravan short leaves its ground, never half a cart" {
    var tile: [CELLS]Tile = @splat(.dirt);
    const head = Level.idx(.{ .x = 4, .y = 3 });
    var broken: usize = 0;
    for ([_]usize{ head, head + 1 }) |i| {
        tile[head] = .caravan;
        tile[head + 1] = .caravan_part;
        unprop(&tile, i);
        try std.testing.expectEqual(Tile.grass, tile[head]);
        try std.testing.expectEqual(Tile.grass, tile[head + 1]);
        try std.testing.expectEqual(Tile.dirt, tile[head + 2]);
        broken += 1;
    }
    unprop(&tile, head + 2);
    try std.testing.expectEqual(Tile.dirt, tile[head + 2]);
    tile[Level.idx(.{ .x = W - 1, .y = 8 })] = .caravan;
    tile[Level.idx(.{ .x = 0, .y = 9 })] = .caravan_part;
    tile[head] = .caravan;
    tile[head + 1] = .caravan_part;
    mendProps(&tile);
    try std.testing.expect(propsWhole(&tile));
    try std.testing.expectEqual(Tile.caravan, tile[head]);
    try std.testing.expectEqual(Tile.grass, tile[Level.idx(.{ .x = W - 1, .y = 8 })]);
    std.debug.print("caravan footprint: broken from either cell {d} times to grass; a cart cut off at the rim and a part at the left edge mended\n", .{broken});
}

test "outside the map reads as wall" {
    var lv = Level.blank();
    lv.set(.{ .x = -3, .y = 2 }, .floor);
    try std.testing.expectEqual(Tile.wall, lv.at(.{ .x = -3, .y = 2 }));
}

test "tight diagonals ignore both side cells but still require an open destination" {
    const from = P{ .x = 10, .y = 10 };
    for ([_]mathx.Dir{ .ne, .se, .sw, .nw }) |d| {
        var lv = openFloor();
        const to = from.add(d.delta());
        lv.set(.{ .x = to.x, .y = from.y }, .wall);
        try std.testing.expect(lv.stepOk(from, d, NO_ONE));
        lv.set(.{ .x = from.x, .y = to.y }, .wall);
        try std.testing.expect(lv.stepOk(from, d, NO_ONE));
        try std.testing.expect(lv.stepOk(to, d.opposite(), NO_ONE));
        lv.set(to, .wall);
        try std.testing.expect(!lv.stepOk(from, d, NO_ONE));
        lv.set(to, .floor);
        lv.putBarrel(to);
        try std.testing.expect(!lv.stepOk(from, d, NO_ONE));
        _ = lv.breakBarrel(to);
        lv.stand(to, 7);
        try std.testing.expect(!lv.stepOk(from, d, NO_ONE));
    }
}

test "a body blocks a step but never itself" {
    var lv = openFloor();
    lv.stand(.{ .x = 6, .y = 5 }, 7);
    try std.testing.expect(!lv.stepOk(.{ .x = 5, .y = 5 }, .e, 3));
    try std.testing.expect(lv.stepOk(.{ .x = 5, .y = 5 }, .e, 7));
}

test "a barrel blocks a step until it breaks" {
    var lv = openFloor();
    const p = P{ .x = 6, .y = 5 };
    lv.putBarrel(p);
    try std.testing.expect(!lv.stepOk(.{ .x = 5, .y = 5 }, .e, NO_ONE));
    try std.testing.expect(lv.breakBarrel(p));
    try std.testing.expect(!lv.breakBarrel(p));
    try std.testing.expect(lv.stepOk(.{ .x = 5, .y = 5 }, .e, NO_ONE));
}

test "a ray reaches its mark in chebyshev steps and a wall blocks the line" {
    var lv = openFloor();
    const a = P{ .x = 4, .y = 9 };
    const b = P{ .x = 17, .y = 14 };
    var ray = Ray.init(a, b);
    var last = a;
    var n: i32 = 0;
    while (ray.next()) |c| {
        last = c;
        n += 1;
    }
    try std.testing.expectEqual(b, last);
    try std.testing.expectEqual(mathx.dist(a, b), n);
    try std.testing.expect(clearLine(&lv, a, b));
    var y: i32 = 5;
    while (y < 20) : (y += 1) lv.set(.{ .x = 10, .y = y }, .wall);
    try std.testing.expect(!clearLine(&lv, a, b));
}

test "thick smoke cuts a sight line but not a clear one, and never hides its own cell" {
    var lv = openFloor();
    const a = P{ .x = 4, .y = 9 };
    const b = P{ .x = 12, .y = 9 };
    lv.smoke[Level.idx(.{ .x = 8, .y = 9 })] = SMOKE_THICK;
    try std.testing.expect(!sightLine(&lv, a, b));
    try std.testing.expect(clearLine(&lv, a, b));
    try std.testing.expect(sightLine(&lv, a, .{ .x = 8, .y = 9 }));
    lv.smoke[Level.idx(.{ .x = 8, .y = 9 })] = SMOKE_THICK - 1;
    try std.testing.expect(sightLine(&lv, a, b));
}

test "distances walk round a wall rather than through it" {
    var lv = openFloor();
    var y: i32 = 1;
    while (y < 20) : (y += 1) lv.set(.{ .x = 10, .y = y }, .wall);
    var out: [CELLS]i32 = undefined;
    var queue: [CELLS]u32 = undefined;
    _ = distances(&lv, .{ .x = 9, .y = 5 }, &out, &queue);
    const across = out[Level.idx(.{ .x = 11, .y = 5 })];
    std.debug.print("two cells apart through a wall: {d} steps walked\n", .{across});
    try std.testing.expect(across > 20);
}
