const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const lume = @import("lume.zig");
const gen = @import("gen.zig");
const procgen = @import("procgen.zig");
const carve = @import("carve.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
const climate = @import("climate.zig");
const listing = @import("listing.zig");
const atlas_text = @import("atlas_text.zig");

const P = mathx.P;

pub const MAX_NODES: usize = 32;
/// Every placed foe and the hero fit the pool.
pub const MAX_FOES: usize = actor.MAX - actor.most(actor.HERO);
pub const DIR = "maps";
pub const EXT = ".map";
pub const MAIN = mapPath("main");
/// The map New plays.
pub const START = mapPath("start");

/// Printable ascii, as every drawn string is.
pub fn plain(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isPrint(c)) return false;
    }
    return true;
}

pub fn titleOf(name: []const u8, n: usize, buf: *[TITLE_MAX]u8) []const u8 {
    if (name.len > 0) return name;
    return std.fmt.bufPrint(buf, UNNAMED ++ "{d}", .{n}) catch unreachable;
}

pub const PREFIX = DIR ++ "/";

pub fn mapPath(comptime stem: []const u8) []const u8 {
    return PREFIX ++ stem ++ EXT;
}
const COLS = grid.COLS;
const ROWS = grid.ROWS;
pub const NAME_MAX: usize = 20;
const UNNAMED = "node ";
pub const TITLE_MAX: usize = @max(NAME_MAX, UNNAMED.len + std.fmt.count("{d}", .{MAX_NODES - 1}));
const GRAPH_COLS: usize = 4;
pub const GRAPH_STEP = P{ .x = 240, .y = 200 };
/// Symmetric graph-coordinate bound that keeps i32 position sums safe.
pub const POS_MAX: u32 = 1 << 24;

/// `p` brought within `POS_MAX` either way on each axis.
pub fn clampPos(p: P) P {
    const lim: i32 = @intCast(POS_MAX);
    return .{ .x = std.math.clamp(p.x, -lim, lim), .y = std.math.clamp(p.y, -lim, lim) };
}

pub const Link = struct {
    node: usize,
    door: usize,

    pub fn eq(a: Link, b: Link) bool {
        return a.node == b.node and a.door == b.door;
    }
};

pub const Door = struct { at: P, to: ?Link = null };

pub const Foe = struct { kind: actor.Kind, at: P };

pub const Algo = procgen.Algo;
pub const Floor = procgen.Floor;
pub const Kind = procgen.Kind;
pub const Feature = procgen.Feature;
pub const MAX_FEATURES = procgen.MAX_FEATURES;

/// Base generation precedes ordered features; doors stay fixed across run rolls.
pub const Procgen = struct {
    floor: Floor = .{ .rooms = .{} },
    /// Unused slots retain defaults so plans compare by content.
    feature: [MAX_FEATURES]Feature = @splat(Feature.of(FIRST_FEATURE)),
    feature_n: usize = 0,
    foes: pack.Spec = .{},
    sky: climate.Climate = .{},

    pub fn features(self: *const Procgen) []const Feature {
        return self.feature[0..self.feature_n];
    }

    pub fn featuresMut(self: *Procgen) []Feature {
        return self.feature[0..self.feature_n];
    }

    pub fn addFeature(self: *Procgen, k: Kind) bool {
        if (self.feature_n == MAX_FEATURES) return false;
        self.feature[self.feature_n] = Feature.of(k);
        self.feature_n += 1;
        return true;
    }

    pub fn dropFeature(self: *Procgen, i: usize) void {
        mathx.removeAt(Feature, &self.feature, &self.feature_n, i, Feature.of(FIRST_FEATURE));
    }

    pub fn fit(self: *const Procgen) Procgen {
        var q = self.*;
        q.floor = q.floor.fit();
        for (q.featuresMut()) |*f| f.* = f.fit();
        q.foes = q.foes.fit();
        return q;
    }

    pub fn valid(self: *const Procgen) bool {
        return std.meta.eql(self.fit(), self.*);
    }
};

pub const FIRST_FEATURE = std.enums.values(Kind)[0];

pub const Bespoke = struct {
    tile: [grid.CELLS]grid.Tile = [_]grid.Tile{.wall} ** grid.CELLS,
    barrel: [grid.CELLS]bool = [_]bool{false} ** grid.CELLS,
    torch: grid.Torches = .{},
    foe: [MAX_FOES]Foe = undefined,
    foe_n: usize = 0,

    pub fn tileAt(self: *const Bespoke, p: P) grid.Tile {
        return grid.cellOr(grid.Tile, &self.tile, p, .wall);
    }

    pub fn floorAt(self: *const Bespoke, p: P) bool {
        return !self.tileAt(p).solid();
    }

    pub fn torches(self: *const Bespoke) []const P {
        return self.torch.slice();
    }

    pub fn foes(self: *const Bespoke) []const Foe {
        return self.foe[0..self.foe_n];
    }

    pub fn foeAt(self: *const Bespoke, p: P) ?usize {
        for (self.foes(), 0..) |f, i| {
            if (f.at.eq(p)) return i;
        }
        return null;
    }

    pub fn bodies(self: *const Bespoke) usize {
        var n = actor.most(actor.HERO);
        for (self.foes()) |f| n += actor.most(f.kind);
        return n;
    }

    /// Whether `k` may stand at `p`, in place of any foe there, within the pool's room.
    pub fn roomAt(self: *const Bespoke, p: P, k: actor.Kind) bool {
        const there = self.foeAt(p) orelse return self.foe_n < MAX_FOES and actor.roomFor(self.bodies(), k);
        return actor.roomFor(self.bodies() - actor.most(self.foe[there].kind), k);
    }

    pub fn addFoe(self: *Bespoke, f: Foe) bool {
        if (self.foeAt(f.at) != null or !self.roomAt(f.at, f.kind)) return false;
        self.foe[self.foe_n] = f;
        self.foe_n += 1;
        return true;
    }

    pub fn dropFoe(self: *Bespoke, i: usize) void {
        _ = mathx.swapRemove(Foe, &self.foe, &self.foe_n, i);
    }
};

pub const Plan = union(enum) { bespoke: Bespoke, procgen: Procgen };

/// A node's name: printable ascii, `NAME_MAX` at most; an empty name is none.
pub const Label = struct {
    buf: [NAME_MAX]u8 = undefined,
    n: usize = 0,

    pub fn text(self: *const Label) []const u8 {
        return self.buf[0..self.n];
    }

    /// Trimmed. Whether it changed; null when refused.
    pub fn set(self: *Label, s: []const u8) ?bool {
        const t = std.mem.trim(u8, s, " ");
        if (t.len > NAME_MAX or !plain(t)) return null;
        if (std.mem.eql(u8, t, self.text())) return false;
        @memcpy(self.buf[0..t.len], t);
        self.n = t.len;
        return true;
    }

    pub fn valid(self: *const Label) bool {
        return self.n <= NAME_MAX and plain(self.text());
    }
};

pub const Node = struct {
    plan: Plan,
    door: [grid.MAX_DOORS]Door = undefined,
    door_n: usize = 0,
    label: Label = .{},
    /// Its box's top-left on the editor's graph.
    pos: P = .{ .x = 0, .y = 0 },

    pub fn name(self: *const Node) []const u8 {
        return self.label.text();
    }

    pub fn rename(self: *Node, s: []const u8) ?bool {
        return self.label.set(s);
    }

    pub fn title(self: *const Node, n: usize, buf: *[TITLE_MAX]u8) []const u8 {
        return titleOf(self.name(), n, buf);
    }

    pub fn outdoor(self: *const Node) bool {
        return switch (self.plan) {
            .procgen => |*pg| pg.floor.outdoor(),
            .bespoke => false,
        };
    }

    /// A bespoke node keeps the default sky; it is under a roof, so none of it shows.
    pub fn sky(self: *const Node) climate.Climate {
        return switch (self.plan) {
            .procgen => |*pg| pg.sky,
            .bespoke => .{},
        };
    }

    pub fn unrolled(self: *const Node) bool {
        return switch (self.plan) {
            .procgen => true,
            .bespoke => false,
        };
    }

    pub fn unlinked(self: *const Node) usize {
        var n: usize = 0;
        for (self.doors()) |d| {
            if (d.to == null) n += 1;
        }
        return n;
    }

    pub fn doors(self: *const Node) []const Door {
        return self.door[0..self.door_n];
    }

    fn doorsMut(self: *Node) []Door {
        return self.door[0..self.door_n];
    }

    /// The foes placed on it, where the hero never lands; a procgen node's are rolled in play.
    pub fn placed(self: *const Node) []const Foe {
        return switch (self.plan) {
            .bespoke => |*b| b.foes(),
            .procgen => &.{},
        };
    }

    pub fn doorAt(self: *const Node, p: P) ?usize {
        for (self.doors(), 0..) |d, i| {
            if (d.at.eq(p)) return i;
        }
        return null;
    }

    pub fn opens(self: *const Node, b: *const Bespoke, p: P) bool {
        return b.floorAt(p) or self.doorAt(p) != null;
    }

    pub fn torchFits(self: *const Node, b: *const Bespoke, p: P) bool {
        return b.tileAt(p) == .wall and self.doorAt(p) == null and self.opens(b, lume.torchFloor(p));
    }

    /// Only `grid.BARREL_GROUND`: the one ground a row's `grid.BARREL_LETTER` stands on.
    pub fn barrelFits(self: *const Node, b: *const Bespoke, p: P) bool {
        return b.tileAt(p) == grid.BARREL_GROUND and self.doorAt(p) == null;
    }

    /// Where a barrel may be laid: it fits, and no foe stands there.
    pub fn barrelGoes(self: *const Node, b: *const Bespoke, p: P) bool {
        return self.barrelFits(b, p) and b.foeAt(p) == null;
    }

    pub fn takesDoor(self: *const Node, p: P) bool {
        return self.door_n < grid.MAX_DOORS and self.doorAt(p) == null and grid.Level.inside(p);
    }

    pub fn foeFits(self: *const Node, b: *const Bespoke, p: P) bool {
        return b.floorAt(p) and self.doorAt(p) == null and !grid.cellOr(bool, &b.barrel, p, false);
    }

    /// Where a `k` may be laid: it fits, and the node has room for it there.
    pub fn foeGoes(self: *const Node, b: *const Bespoke, p: P, k: actor.Kind) bool {
        return self.foeFits(b, p) and b.roomAt(p, k);
    }

    /// Where a torch may be hung: it fits, and the wall and the node have room for it.
    pub fn torchGoes(self: *const Node, b: *const Bespoke, p: P) bool {
        return self.torchFits(b, p) and b.torch.takes(p);
    }

    /// After `p`'s tile or door changed: takes away the torch, barrel and foe it no longer fits, as `parse` would refuse them.
    pub fn pruneAt(self: *const Node, b: *Bespoke, p: P) void {
        for ([_]P{ p, lume.torchWall(p) }) |w| {
            if (grid.Level.inside(w) and !self.torchFits(b, w)) _ = b.torch.remove(w);
        }
        const i = grid.Level.idx(p);
        if (b.barrel[i] and !self.barrelFits(b, p)) b.barrel[i] = false;
        if (b.foeAt(p)) |f| {
            if (!self.foeFits(b, p)) b.dropFoe(f);
        }
    }

    pub fn doorCells(self: *const Node, out: *[grid.MAX_DOORS]P) []const P {
        for (self.doors(), 0..) |d, i| out[i] = d.at;
        return out[0..self.door_n];
    }

    pub fn stamp(self: *const Node, lv: *grid.Level, roll: u64) void {
        var buf: [grid.MAX_DOORS]P = undefined;
        const cells = self.doorCells(&buf);
        switch (self.plan) {
            .procgen => |*pg| procgen.roll(lv, roll, cells, pg.floor, pg.features()),
            .bespoke => |*b| {
                lv.* = grid.Level.blank();
                lv.tile = b.tile;
                self.markDoors(lv);
                lv.torch = b.torch;
                procgen.reshape(lv);
                for (0..grid.CELLS) |i| {
                    if (b.barrel[i] and self.barrelFits(b, grid.Level.of(i))) lv.barrel[i] = true;
                }
            },
        }
    }

    pub fn sketch(self: *const Node, lv: *grid.Level) void {
        switch (self.plan) {
            .bespoke => self.stamp(lv, 0),
            .procgen => {
                lv.* = grid.Level.blank();
                self.markDoors(lv);
            },
        }
    }

    fn markDoors(self: *const Node, lv: *grid.Level) void {
        for (self.doors(), 0..) |d, i| lv.putDoor(d.at, i);
    }
};

pub const Start = struct { node: usize = 0, at: P = grid.MIDDLE };

pub const Atlas = struct {
    node: [MAX_NODES]Node = undefined,
    node_n: usize = 0,
    start: Start = .{},

    pub fn nodes(self: *Atlas) []Node {
        return self.node[0..self.node_n];
    }

    pub fn add(self: *Atlas, plan: Plan) ?usize {
        if (self.node_n == MAX_NODES) return null;
        self.node[self.node_n] = .{ .plan = plan, .pos = self.freeSlot() };
        self.node_n += 1;
        return self.node_n - 1;
    }

    /// Replaced by one bespoke node floored over `room`, starting at `at`; returns that node.
    pub fn oneRoom(self: *Atlas, room: grid.Box, at: P) usize {
        std.debug.assert(room.holds(at));
        self.* = .{};
        const n = self.add(.{ .bespoke = .{} }).?;
        const b = &self.node[n].plan.bespoke;
        var cells = room.cells();
        while (cells.next()) |p| b.tile[grid.Level.idx(p)] = .floor;
        self.start = .{ .node = n, .at = at };
        return n;
    }

    fn freeSlot(self: *Atlas) P {
        var i: usize = 0;
        while (true) : (i += 1) {
            const s = mathx.unslot(i, GRAPH_COLS);
            const p = P{ .x = s.x * GRAPH_STEP.x, .y = s.y * GRAPH_STEP.y };
            const clear = for (self.nodes()) |*nd| {
                if (@abs(nd.pos.x - p.x) < GRAPH_STEP.x and @abs(nd.pos.y - p.y) < GRAPH_STEP.y) break false;
            } else true;
            if (clear) return p;
        }
    }

    pub fn remove(self: *Atlas, n: usize) void {
        for (self.node[n].doors(), 0..) |_, k| self.unlink(.{ .node = n, .door = k });
        mathx.removeAt(Node, &self.node, &self.node_n, n, null);
        self.renumber(.{ .node = n, .door = 0 }, Atlas.pastNode);
        if (self.start.node == n) self.start = .{} else if (self.start.node > n) self.start.node -= 1;
    }

    pub fn addDoor(self: *Atlas, n: usize, p: P) ?usize {
        const nd = &self.node[n];
        if (!nd.takesDoor(p)) return null;
        nd.door[nd.door_n] = .{ .at = p };
        nd.door_n += 1;
        return nd.door_n - 1;
    }

    pub fn removeDoor(self: *Atlas, at: Link) void {
        self.unlink(at);
        const nd = &self.node[at.node];
        mathx.removeAt(Door, &nd.door, &nd.door_n, at.door, null);
        self.renumber(at, Atlas.pastDoor);
    }

    fn renumber(self: *Atlas, gone: Link, comptime past: fn (*Link, Link) void) void {
        for (self.nodes()) |*nd| {
            for (nd.doorsMut()) |*d| {
                if (d.to) |*l| past(l, gone);
            }
        }
    }

    fn pastNode(l: *Link, gone: Link) void {
        if (l.node > gone.node) l.node -= 1;
    }

    fn pastDoor(l: *Link, gone: Link) void {
        if (l.node == gone.node and l.door > gone.door) l.door -= 1;
    }

    fn doorOf(self: *Atlas, at: Link) *Door {
        return &self.node[at.node].door[at.door];
    }

    pub fn door(self: *const Atlas, at: Link) Door {
        return self.node[at.node].door[at.door];
    }

    pub fn link(self: *Atlas, a: Link, b: Link) void {
        self.unlink(a);
        self.unlink(b);
        if (a.eq(b)) return;
        self.doorOf(a).to = b;
        self.doorOf(b).to = a;
    }

    pub fn unlink(self: *Atlas, a: Link) void {
        const to = self.doorOf(a).to orelse return;
        self.doorOf(a).to = null;
        self.doorOf(to).to = null;
    }
    pub const save = atlas_text.save;
    pub const write = atlas_text.write;
    pub const load = atlas_text.load;
    pub const parse = atlas_text.parse;

    pub fn standable(self: *const Atlas, from: Start, scratch: *grid.Level) bool {
        const nd = &self.node[from.node];
        if (nd.unrolled()) return true;
        nd.sketch(scratch);
        return landing(scratch, from.at, nd.placed()) != null;
    }
};

pub const NO_FLOOR = "{s} has no open floor to start on";
pub const NOT_LOADED = "{s} did not load ({s})";
pub const NO_MAPS = "No maps in " ++ DIR ++ " yet";

pub const Error = error{ NoHeader, BadLine, TooMany, NoNodes, NoStart, BadLink };

/// Where a body arriving at `p` stands: `p`, or the open cell no one holds, nor `foes` are to, fewest steps from it; nearest as the crow flies when no step reaches one.
pub fn landing(lv: *const grid.Level, p: P, foes: []const Foe) ?P {
    if (!lv.walkable(p)) return nearest(lv, p, foes);
    if (free(lv, p, foes)) return p;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var flood = grid.Flood.init(lv, p, &dist, &queue);
    while (flood.next()) |q| {
        if (free(lv, q, foes)) return q;
    }
    return nearest(lv, p, foes);
}

fn free(lv: *const grid.Level, q: P, foes: []const Foe) bool {
    if (!lv.vacant(q)) return false;
    for (foes) |f| {
        if (f.at.eq(q)) return false;
    }
    return true;
}

fn nearest(lv: *const grid.Level, p: P, foes: []const Foe) ?P {
    const Free = struct {
        lv: *const grid.Level,
        foes: []const Foe,

        pub fn has(f: @This(), i: usize) bool {
            return free(f.lv, grid.Level.of(i), f.foes);
        }
    };
    return grid.nearest(p, Free{ .lv = lv, .foes = foes });
}

fn testAtlas() !*Atlas {
    const a = try std.testing.allocator.create(Atlas);
    a.* = .{};
    return a;
}

test "a map saves and loads back the same" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    const room = a.add(.{ .bespoke = .{} }).?;
    const cave = a.add(.{ .procgen = .{} }).?;
    const pg = &a.node[cave].plan.procgen;
    pg.floor.rooms.size = .{ .x = 50, .y = 40 };
    pg.floor.rooms.torches = 20;
    const wood = a.add(.{ .procgen = .{ .floor = .{ .wilds = .{ .thicket = 30, .strays = 7 } } } }).?;
    const wpg = &a.node[wood].plan.procgen;
    _ = wpg.addFeature(.river);
    wpg.feature[0].river.fill = .lava;
    wpg.feature[0].river.width = 5;
    _ = wpg.addFeature(.setpiece);
    wpg.feature[1].setpiece.piece = .graveyard;
    pg.foes.apart = 6;
    pg.foes.makeup_n = 2;
    pg.foes.makeup[1] = pack.Makeup.of(&.{ .bloat, .rat });
    pg.foes.makeup[1].weight = 3;
    const b = &a.node[room].plan.bespoke;
    var floor = grid.Box.sized(.{ .x = 3, .y = 3 }, 9, 6).cells();
    while (floor.next()) |p| b.tile[grid.Level.idx(p)] = .floor;
    b.barrel[grid.Level.idx(.{ .x = 4, .y = 4 })] = true;
    _ = b.torch.add(.{ .x = 6, .y = 2 });
    _ = b.addFoe(.{ .kind = .slime, .at = .{ .x = 9, .y = 6 } });
    const d0 = a.addDoor(room, .{ .x = 11, .y = 5 }).?;
    const d1 = a.addDoor(cave, .{ .x = 0, .y = 30 }).?;
    a.link(.{ .node = room, .door = d0 }, .{ .node = cave, .door = d1 });
    a.start = .{ .node = room, .at = .{ .x = 5, .y = 5 } };
    try std.testing.expectEqual(@as(?bool, true), a.node[cave].rename("  The Deep Cave "));
    try std.testing.expectEqual(@as(?bool, false), a.node[cave].rename("The Deep Cave"));
    try std.testing.expectEqual(@as(?bool, null), a.node[room].rename("a name far too long to keep"));
    a.node[room].pos = .{ .x = -40, .y = 310 };

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try a.write(buf.writer());
    const back = try testAtlas();
    defer std.testing.allocator.destroy(back);
    try back.parse(buf.items);
    var again = std.ArrayList(u8).init(std.testing.allocator);
    defer again.deinit();
    try back.write(again.writer());
    std.debug.print("a two-node map is {d} bytes of text\n", .{buf.items.len});
    try std.testing.expectEqualStrings(buf.items, again.items);
    try std.testing.expectEqual(@as(?Link, .{ .node = cave, .door = d1 }), back.node[room].door[d0].to);
    const bpg = &back.node[cave].plan.procgen;
    try std.testing.expect(std.meta.eql(pg.floor, bpg.floor));
    try std.testing.expect(std.meta.eql(a.node[wood].plan.procgen, back.node[wood].plan.procgen));
    try std.testing.expectEqual(grid.Tile.lava, back.node[wood].plan.procgen.feature[0].river.fill);
    try std.testing.expectEqual(@as(i32, 6), bpg.foes.apart);
    try std.testing.expectEqual(@as(usize, 2), bpg.foes.makeup_n);
    try std.testing.expectEqual(@as(u8, 3), bpg.foes.makeup[1].weight);
    try std.testing.expectEqualSlices(actor.Kind, &.{ .bloat, .rat }, bpg.foes.makeup[1].kinds());
    try std.testing.expectEqualStrings("The Deep Cave", back.node[cave].name());
    try std.testing.expectEqual(P{ .x = -40, .y = 310 }, back.node[room].pos);
    try std.testing.expectEqual(GRAPH_STEP.x, back.node[cave].pos.x);
}

test "a map file with a one-way link, a door linked to itself, a stray word or a far box is refused" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    const head = atlas_text.HEADER ++ "\nstart 0 5 5\n";
    const bad = [_][]const u8{
        head ++ "node procgen rooms\ndoor 5 5 1 0\nnode procgen rooms\ndoor 5 5\n",
        head ++ "node procgen rooms\ndoor 5 5 0 0\n",
        head ++ "node procgen rooms 1 2\n",
        head ++ "node procgen rooms deep\n",
        head ++ "node procgen rooms\nat 0 0\nnode procgen rooms\nat -2147483648 0\nnode procgen rooms\n",
        head ++ "node bespoke\nrow " ++ "#" ** COLS ++ "\n",
        head ++ "node procgen rooms\nsize 20 20\nroom_w 5 30\n",
        head ++ "node procgen rooms\nmakeup 0 rat\n",
        head ++ "node procgen rooms\nmakeup 1 slime_half\n",
        head ++ "node procgen rooms\nmakeup 1\n",
        head ++ "node procgen rooms\napart 99\n",
        head ++ "node bespoke\n" ++ ("row " ++ "#" ** COLS ++ "\n") ** ROWS ++ "foe rat 3 3\n",
        head ++ "node bespoke\n" ++ ("row " ++ "." ** COLS ++ "\n") ** ROWS ++ "foe slime_half 3 3\n",
        head ++ "node bespoke\n" ++ ("row " ++ "#" ** COLS ++ "\n") ** ROWS ++ "torch 3 3\n",
        head ++ "node bespoke\n" ++ ("row " ++ "." ** COLS ++ "\n") ** ROWS ++ "torch 3 3\n",
        head ++ "node bespoke\n" ++ ("row " ++ "0" ** COLS ++ "\n") ** ROWS ++ "door 3 3\n",
        head ++ "start 0 6 6\nnode procgen rooms\n",
        head ++ "node procgen rooms\nname A\nname B\n",
        head ++ "node procgen rooms\nname   \n",
        head ++ "node procgen rooms\nat 0 0\nat 1 1\n",
        head ++ "node procgen rooms\napart 4\napart 5\n",
        head ++ "node procgen wilds\nrooms 4\n",
        head ++ "node procgen rooms\nthicket 40\n",
        head ++ "node procgen wilds\nthicket 99\n",
        head ++ "node procgen wilds\nfeature river\nthicket 40\n",
        head ++ "node procgen wilds\nfeature river\nwidth 3\nwidth 4\n",
        head ++ "node procgen wilds\nfeature river\nmakeup 1 rat\n",
        head ++ "node procgen wilds\nfeature canal\n",
        head ++ "node procgen wilds\nfeature river\nfill moss\n",
        atlas_text.HEADER ++ "\nnode procgen rooms\n",
    };
    for (bad) |t| try std.testing.expect(std.meta.isError(a.parse(t)));
    try a.parse(head ++ "node procgen rooms 1790812916605\n");
    try a.parse(head ++ "node bespoke\n" ++ ("row " ++ "#" ** COLS ++ "\n") ** 4 ++ "row " ++ "." ** COLS ++ "\n" ++ ("row " ++ "#" ** COLS ++ "\n") ** (ROWS - 5) ++ "torch 3 3\n");
    try std.testing.expectEqual(@as(usize, 1), a.node[0].plan.bespoke.torch.n);
    try a.parse(head ++ "node procgen rooms\n  name  Deep  Cave\n");
    try std.testing.expectEqualStrings("Deep  Cave", a.node[0].name());
    try a.parse(head ++ "node procgen rooms\nat 0 0\napart 4\nnode procgen rooms\nat 1 1\napart 5\n");
    try a.parse(head ++ "node procgen wilds\nthicket 50\nsmooth 2\nstrays 0\npacks 4\n");
    try std.testing.expectEqual(50, a.node[0].plan.procgen.floor.wilds.thicket);
    try a.parse(head ++ "node procgen caves\nfill 50\nfeature lake\nfill lava\ncount 2\nfeature river\nwidth 2\n");
    const pg = &a.node[0].plan.procgen;
    try std.testing.expectEqual(@as(usize, 2), pg.feature_n);
    try std.testing.expectEqual(grid.Tile.lava, pg.feature[0].lake.fill);
    try std.testing.expectEqual(@as(u8, 2), pg.feature[1].river.width);
}

test "removing a node unlinks the doors into it and renumbers the rest" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    for (0..3) |_| _ = a.add(.{ .procgen = .{} });
    for (0..3) |n| _ = a.addDoor(n, .{ .x = 5, .y = 5 });
    _ = a.addDoor(2, .{ .x = 6, .y = 5 });
    a.link(.{ .node = 0, .door = 0 }, .{ .node = 1, .door = 0 });
    a.link(.{ .node = 2, .door = 1 }, .{ .node = 1, .door = 0 });
    try std.testing.expectEqual(@as(?Link, null), a.node[0].door[0].to);
    a.link(.{ .node = 0, .door = 0 }, .{ .node = 2, .door = 0 });
    a.start.node = 2;
    a.remove(1);
    try std.testing.expectEqual(@as(usize, 2), a.node_n);
    try std.testing.expectEqual(@as(?Link, .{ .node = 1, .door = 0 }), a.node[0].door[0].to);
    try std.testing.expectEqual(@as(?Link, .{ .node = 0, .door = 0 }), a.node[1].door[0].to);
    try std.testing.expectEqual(@as(?Link, null), a.node[1].door[1].to);
    try std.testing.expectEqual(@as(usize, 1), a.start.node);
    a.removeDoor(.{ .node = 1, .door = 0 });
    try std.testing.expectEqual(@as(?Link, null), a.node[0].door[0].to);
}

test "a bespoke node's doors open their cells and a torch hangs only over floor" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    const n = a.add(.{ .bespoke = .{} }).?;
    const b = &a.node[n].plan.bespoke;
    b.tile[grid.Level.idx(.{ .x = 5, .y = 5 })] = .floor;
    _ = b.torch.add(.{ .x = 5, .y = 4 });
    _ = b.torch.add(.{ .x = 20, .y = 20 });
    _ = a.addDoor(n, .{ .x = 5, .y = 6 });
    var lv: grid.Level = undefined;
    a.node[n].stamp(&lv, 0);
    try std.testing.expect(lv.walkable(.{ .x = 5, .y = 6 }));
    try std.testing.expectEqual(@as(?usize, 0), lv.doorAt(.{ .x = 5, .y = 6 }));
    try std.testing.expectEqual(@as(usize, 1), lv.torch.n);
    try std.testing.expect(gen.bearsTorch(&lv, .{ .x = 5, .y = 4 }));
}

test "a bespoke node takes no more slimes than the pool holds once every one has split to quarters" {
    var b = Bespoke{};
    var slimes: usize = 0;
    while (b.addFoe(.{ .kind = .slime, .at = .{ .x = @intCast(1 + slimes), .y = 1 } })) slimes += 1;
    try std.testing.expectEqual((actor.MAX - 1) / actor.most(.slime), slimes);
    try std.testing.expect(b.bodies() <= actor.MAX);
}

test "tight diagonals reach doors in all four map corners" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    const n = a.add(.{ .procgen = .{} }).?;
    for ([_]P{ .{ .x = 0, .y = 0 }, .{ .x = grid.W - 1, .y = 0 }, .{ .x = 0, .y = grid.H - 1 }, .{ .x = grid.W - 1, .y = grid.H - 1 } }) |p| {
        try std.testing.expect(a.addDoor(n, p) != null);
    }
    for (std.enums.values(procgen.Algo)) |base| {
        a.node[n].plan.procgen.floor = procgen.Floor.of(base);
        var lv: grid.Level = undefined;
        a.node[n].stamp(&lv, 0xD1A6);
        var dist: [grid.CELLS]i32 = undefined;
        var queue: [grid.CELLS]u32 = undefined;
        _ = grid.distances(&lv, lv.firstOpen().?, &dist, &queue);
        for (a.node[n].doors()) |door| {
            const inside = grid.Level.inset(door.at);
            try std.testing.expect(lv.stepOk(inside, mathx.dirTo(inside, door.at).?, grid.NO_ONE));
            try std.testing.expect(dist[grid.Level.idx(door.at)] >= 0);
        }
        try std.testing.expectEqual(@as(usize, 0), carve.leaks(&lv));
    }
}

test "a body lands on the nearest open cell no one holds" {
    var lv = grid.openFloor();
    const p = P{ .x = 10, .y = 10 };
    try std.testing.expectEqual(p, landing(&lv, p, &.{}).?);
    lv.putBarrel(p);
    try std.testing.expectEqual(@as(i32, 1), mathx.dist(p, landing(&lv, p, &.{}).?));
    try std.testing.expectEqual(@as(i32, 1), mathx.dist(.{ .x = 0, .y = 0 }, landing(&lv, .{ .x = 0, .y = 0 }, &.{}).?));
    const foe = [_]Foe{.{ .kind = .rat, .at = .{ .x = 11, .y = 11 } }};
    lv = grid.openFloor();
    try std.testing.expect(!landing(&lv, foe[0].at, &foe).?.eq(foe[0].at));
}

test "a body lands on the side of a wall it arrived on, however near the far side is" {
    var lv = grid.openFloor();
    var y: i32 = 0;
    while (y < grid.H) : (y += 1) lv.set(.{ .x = 9, .y = y }, .wall);
    const door = P{ .x = 10, .y = 10 };
    lv.putBarrel(door);
    for ([_]P{ .{ .x = 10, .y = 9 }, .{ .x = 11, .y = 9 }, .{ .x = 11, .y = 10 }, .{ .x = 11, .y = 11 }, .{ .x = 10, .y = 11 } }) |b| lv.putBarrel(b);
    const at = landing(&lv, door, &.{}).?;
    std.debug.print("a door walled on its left, its right ringed by barrels: lands at {d},{d}\n", .{ at.x, at.y });
    try std.testing.expect(at.x > 9);
    try std.testing.expectEqual(@as(i32, 2), mathx.dist(door, at));
}

test "the strand: the archer washes up on the beach, and the exit is reached through the trees" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    try a.load(std.testing.allocator, START);
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const nd = &a.node[a.start.node];
    const exit = nd.doors()[0].at;
    var on_shore: usize = 0;
    var wound: f32 = 0;
    var swamp_trees: usize = 0;
    var dirt_trees: usize = 0;
    var inland_trees: usize = 0;
    const RUNS = 50;
    for (0..RUNS) |i| {
        nd.stamp(&lv, 0x57A2D +% i *% grid.TEST_SEED_STRIDE);
        const at = landing(&lv, a.start.at, &.{}) orelse return error.NoFloor;
        if (lv.at(at) == .dirt or lv.at(at) == .shallows) on_shore += 1;
        try std.testing.expect(std.mem.indexOfScalar(grid.Tile, &lv.tile, .sand) == null);
        try grid.expectAllReached(&lv, at, &dist, &queue);
        const walked = dist[grid.Level.idx(exit)];
        try std.testing.expect(walked > 0);
        wound += @as(f32, @floatFromInt(walked)) / @as(f32, @floatFromInt(mathx.dist(at, exit)));
        var trees: usize = 0;
        for (lv.tile, 0..) |t, k| {
            if (t != .swamp_tree) continue;
            const p = grid.Level.of(k);
            try std.testing.expect(carve.nearWater(&lv, p, 4));
            dirt_trees += @intFromBool(@import("../gfx/ground.zig").bedAt(&lv, p, false) == .dirt);
            inland_trees += @intFromBool(p.x > 20);
            trees += 1;
        }
        try std.testing.expect(trees > 0);
        swamp_trees += trees;
    }
    std.debug.print("the strand over {d} rolls: {d} land on the dirt shore, no sand; the exit walks {d:.2} times the straight line\n", .{ RUNS, on_shore, wound / RUNS });
    try std.testing.expect(on_shore * 10 >= RUNS * 9);
    try std.testing.expect(wound / RUNS > 1.1);
    std.debug.print("the strand: {d} swamp trees near water, {d} on dirt, {d} at inland ponds across {d} rolls\n", .{ swamp_trees, dirt_trees, inland_trees, RUNS });
    try std.testing.expect(dirt_trees * 10 >= swamp_trees * 8 and inland_trees > 0);
}

test "the strand reconnects side paths and reliably supplies reachable chests and barrels" {
    const branches = @import("branches.zig");
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    try a.load(std.testing.allocator, START);
    const nd = &a.node[a.start.node];
    const settings = nd.plan.procgen.floor.wilds;
    var buf: [grid.MAX_DOORS]P = undefined;
    const doors = nd.doorCells(&buf);
    var lv: grid.Level = undefined;
    var expected: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var loops: usize = 0;
    var chests: usize = 0;
    var barrels: usize = 0;
    var least: usize = grid.CELLS;
    var most: usize = 0;
    var barrel_least: usize = grid.CELLS;
    var barrel_most: usize = 0;
    var farthest_first: i32 = 0;
    const RUNS = 128;
    for (0..RUNS) |i| {
        const seed = 0xC4E57 +% i *% grid.TEST_SEED_STRIDE;
        nd.stamp(&expected, seed);
        nd.plan.procgen.floor.wilds.loops = 0;
        nd.plan.procgen.floor.wilds.rewards = .none;
        nd.stamp(&lv, seed);
        nd.plan.procgen.floor.wilds = settings;
        const result = branches.improve(&lv, seed, doors, settings);
        try std.testing.expectEqualSlices(grid.Tile, &expected.tile, &lv.tile);
        try std.testing.expectEqualSlices(bool, &expected.barrel, &lv.barrel);
        var blocked = lv;
        blocked.wallBarrels();
        const start = landing(&lv, a.start.at, &.{}) orelse return error.NoFloor;
        try grid.expectAllReached(&blocked, start, &dist, &queue);
        for (doors) |door| try std.testing.expect(dist[grid.Level.idx(door)] >= 0);
        try std.testing.expect(std.mem.indexOfScalar(grid.Tile, &lv.tile, .chest_open) == null);
        var counted_chests: usize = 0;
        var counted_barrels: usize = 0;
        var first_barrel: i32 = grid.CELLS;
        for (lv.tile, 0..) |t, k| {
            if (t != .chest and !lv.barrel[k]) continue;
            counted_chests += @intFromBool(t == .chest);
            counted_barrels += @intFromBool(lv.barrel[k]);
            const p = grid.Level.of(k);
            try std.testing.expect(lv.doorAt(p) == null and !grid.Level.onRim(p));
            try std.testing.expect(!lv.torch.has(lume.torchWall(p)));
            var reachable = false;
            for (mathx.ALL_DIRS) |d| {
                const q = p.add(d.delta());
                if (grid.Level.inside(q) and dist[grid.Level.idx(q)] >= 0) {
                    reachable = true;
                    if (lv.barrel[k]) first_barrel = @min(first_barrel, dist[grid.Level.idx(q)] + 1);
                }
            }
            try std.testing.expect(reachable);
        }
        try std.testing.expectEqual(result.chests, counted_chests);
        try std.testing.expectEqual(result.barrels, counted_barrels);
        try std.testing.expect(counted_chests >= branches.Reward.chest.rule().total);
        try std.testing.expect(counted_barrels >= branches.Reward.barrel.rule().total / 2);
        loops += result.loops;
        chests += result.chests;
        barrels += result.barrels;
        least = @min(least, result.chests);
        most = @max(most, result.chests);
        barrel_least = @min(barrel_least, result.barrels);
        barrel_most = @max(barrel_most, result.barrels);
        farthest_first = @max(farthest_first, first_barrel);
    }
    std.debug.print("the strand over {d} rolls: {d} paths rejoined, {d} closed chests ({d} to {d}), {d} barrels ({d} to {d}); first barrel within {d} steps; every reward and exit reachable without breaking barrels\n", .{ RUNS, loops, chests, least, most, barrels, barrel_least, barrel_most, farthest_first });
    try std.testing.expect(loops > RUNS);
    try std.testing.expect(chests > 0);
}

test "every map in the maps folder parses, and each procgen node rolls its ground whole" {
    var list = listing.Listing{};
    list.scanAll();
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var rolled: usize = 0;
    for (0..list.n) |i| {
        a.load(std.testing.allocator, list.at(i)) catch |e| {
            std.debug.print("{s}: {s}\n", .{ list.at(i), @errorName(e) });
            return e;
        };
        for (a.nodes(), 0..) |*nd, n| {
            if (!nd.unrolled()) continue;
            nd.stamp(&lv, 0x5EED +% n);
            const at = landing(&lv, if (a.start.node == n) a.start.at else grid.MIDDLE, &.{}) orelse return error.NoFloor;
            const open = lv.openCount();
            const reached = grid.distances(&lv, at, &dist, &queue);
            if (reached != open) std.debug.print("{s} node {d}: {d} open, {d} reached from {d},{d}\n", .{ list.at(i), n, open, reached, at.x, at.y });
            try std.testing.expectEqual(open, reached);
            rolled += 1;
        }
    }
    std.debug.print("{d} maps parsed, {d} procgen nodes rolled whole\n", .{ list.n, rolled });
}
