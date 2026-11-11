const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const lume = @import("lume.zig");
const gen = @import("gen.zig");
const procgen = @import("procgen.zig");
const carve = @import("carve.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
pub const post = @import("../play/post.zig");
pub const raid = @import("../play/raid.zig");
const climate = @import("climate.zig");
const listing = @import("listing.zig");
const atlas_text = @import("atlas_text.zig");
pub const script = @import("script.zig");
pub const section = @import("section.zig");

const P = mathx.P;

pub const MAX_NODES: usize = 32;

pub fn holdsNodes(n: usize, at: usize) bool {
    return n > 0 and n <= MAX_NODES and at < n;
}

pub const MAX_FOES = section.MAX_FOES;
pub const DIR = "maps";
pub const EXT = ".map";
pub const MAIN = mapPath("main");
pub const START = mapPath("start");

pub const plain = script.plain;

pub fn titleOf(name: []const u8, n: usize, buf: *[TITLE_MAX]u8) []const u8 {
    if (name.len > 0) return name;
    return std.fmt.bufPrint(buf, UNNAMED ++ "{d}", .{n}) catch unreachable;
}

pub const PREFIX = DIR ++ "/";

pub fn mapPath(comptime stem: []const u8) []const u8 {
    return PREFIX ++ stem ++ EXT;
}
pub const NAME_MAX: usize = 20;
const UNNAMED = "node ";
pub const TITLE_MAX: usize = @max(NAME_MAX, UNNAMED.len + std.fmt.count("{d}", .{MAX_NODES - 1}));
const GRAPH_COLS: usize = 4;
pub const GRAPH_STEP = P{ .x = 240, .y = 200 };
/// Symmetric graph-coordinate bound that keeps i32 position sums safe.
pub const POS_MAX: u32 = 1 << 24;

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

pub const Foe = section.Foe;

pub const Algo = procgen.Algo;
pub const Floor = procgen.Floor;
pub const Kind = procgen.Kind;
pub const Feature = procgen.Feature;
pub const MAX_FEATURES = procgen.MAX_FEATURES;

/// Doors stay fixed across run rolls.
pub const Procgen = struct {
    pub const COUNTED = .{.{ "feature", "feature_n" }};
    floor: Floor = .{ .rooms = .{} },
    /// Unused slots retain defaults so plans compare by content.
    feature: [MAX_FEATURES]Feature = @splat(Feature.of(FIRST_FEATURE)),
    feature_n: usize = 0,
    foes: pack.Spec = .{},
    sky: climate.Climate = .{},
    post: post.Post = .{},
    raid: raid.Raid = .{},
    section: section.Section = .{},

    pub fn features(self: *const Procgen) []const Feature {
        return self.feature[0..self.feature_n];
    }

    pub fn featuresMut(self: *Procgen) []Feature {
        return self.feature[0..self.feature_n];
    }

    pub fn addFeature(self: *Procgen, k: Kind) bool {
        return mathx.push(Feature, &self.feature, &self.feature_n, Feature.of(k));
    }

    pub fn dropFeature(self: *Procgen, i: usize) void {
        mathx.removeAt(Feature, &self.feature, &self.feature_n, i, Feature.of(FIRST_FEATURE));
    }

    pub fn fit(self: *const Procgen) Procgen {
        var q = self.*;
        q.floor = q.floor.fit();
        for (q.featuresMut()) |*f| f.* = f.fit();
        inline for (std.meta.fields(Procgen)) |f| {
            if (comptime @typeInfo(f.type) == .@"struct" and @hasDecl(f.type, "fit")) @field(q, f.name) = @field(q, f.name).fit();
        }
        return q;
    }

    pub fn valid(self: *const Procgen) bool {
        return std.meta.eql(self.fit(), self.*);
    }
};

pub const FIRST_FEATURE = std.enums.values(Kind)[0];

pub const Bespoke = struct {
    pub const COUNTED = .{.{ "foe", "foe_n" }};
    tile: [grid.CELLS]grid.Tile = [_]grid.Tile{grid.OFF_MAP} ** grid.CELLS,
    barrel: [grid.CELLS]bool = [_]bool{false} ** grid.CELLS,
    torch: grid.Torches = .{},
    foe: [MAX_FOES]Foe = undefined,
    foe_n: usize = 0,

    pub fn tileAt(self: *const Bespoke, p: P) grid.Tile {
        return grid.cellOr(grid.Tile, &self.tile, p, grid.OFF_MAP);
    }

    pub fn floorAt(self: *const Bespoke, p: P) bool {
        return !self.tileAt(p).solid();
    }

    pub fn barrelAt(self: *const Bespoke, p: P) bool {
        return grid.cellOr(bool, &self.barrel, p, false);
    }

    pub fn fill(self: *Bespoke, box: grid.Box, t: grid.Tile) void {
        var cells = box.cells();
        while (cells.next()) |p| self.tile[grid.Level.idx(p)] = t;
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

    pub fn roomAt(self: *const Bespoke, p: P, k: actor.Kind) bool {
        const there = self.foeAt(p) orelse return self.foe_n < MAX_FOES and actor.roomFor(self.bodies(), k);
        return actor.roomFor(self.bodies() - actor.most(self.foe[there].kind), k);
    }

    pub fn addFoe(self: *Bespoke, f: Foe) bool {
        if (self.foeAt(f.at) != null or !self.roomAt(f.at, f.kind)) return false;
        return mathx.push(Foe, &self.foe, &self.foe_n, f);
    }

    pub fn dropFoe(self: *Bespoke, i: usize) void {
        _ = mathx.swapRemove(Foe, &self.foe, &self.foe_n, i);
    }
};

pub const Plan = union(enum) {
    bespoke: Bespoke,
    procgen: Procgen,

    pub fn procgenOf(self: *Plan) ?*Procgen {
        return switch (self.*) {
            .procgen => |*pg| pg,
            .bespoke => null,
        };
    }

    pub fn bespokeOf(self: *Plan) ?*Bespoke {
        return switch (self.*) {
            .bespoke => |*b| b,
            .procgen => null,
        };
    }
};

/// An empty name is none.
pub const Label = struct {
    pub const COUNTED = .{.{ "buf", "n" }};
    buf: [NAME_MAX]u8 = undefined,
    n: usize = 0,

    pub fn text(self: *const Label) []const u8 {
        return self.buf[0..self.n];
    }

    /// Trimmed. Whether it changed; null when refused.
    pub fn set(self: *Label, s: []const u8) ?bool {
        const t = script.fitText(s, NAME_MAX) orelse return null;
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
    pub const COUNTED = .{.{ "door", "door_n" }};
    plan: Plan,
    door: [grid.MAX_DOORS]Door = undefined,
    door_n: usize = 0,
    label: Label = .{},
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

    pub fn sky(self: *const Node) climate.Climate {
        return switch (self.plan) {
            .procgen => |*pg| pg.sky,
            .bespoke => .{},
        };
    }

    pub fn unrolled(self: *const Node) bool {
        return self.plan == .procgen;
    }

    pub fn unlinked(self: *const Node) usize {
        var n: usize = 0;
        for (self.doors()) |d| {
            if (d.to == null) n += 1;
        }
        return n;
    }

    pub fn raidAstray(self: *const Node) bool {
        return switch (self.plan) {
            .procgen => |*pg| pg.raid.raiders > 0 and self.raidDoor() == null,
            .bespoke => false,
        };
    }

    pub fn raidDoor(self: *const Node) ?P {
        return switch (self.plan) {
            .procgen => |*pg| if (pg.raid.raid_door < self.door_n) self.door[pg.raid.raid_door].at else null,
            .bespoke => null,
        };
    }

    pub fn doors(self: *const Node) []const Door {
        return self.door[0..self.door_n];
    }

    fn doorsMut(self: *Node) []Door {
        return self.door[0..self.door_n];
    }

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

    pub fn barrelFits(self: *const Node, b: *const Bespoke, p: P) bool {
        return b.tileAt(p) == grid.BARREL_GROUND and self.doorAt(p) == null;
    }

    pub fn barrelGoes(self: *const Node, b: *const Bespoke, p: P) bool {
        return self.barrelFits(b, p) and b.foeAt(p) == null;
    }

    pub fn takesDoor(self: *const Node, p: P) bool {
        return self.door_n < grid.MAX_DOORS and self.doorAt(p) == null and grid.Level.inside(p);
    }

    pub fn foeFits(self: *const Node, b: *const Bespoke, p: P, k: actor.Kind) bool {
        if (self.doorAt(p) != null or b.barrelAt(p)) return false;
        return actor.groundFits(k, b.tileAt(p));
    }

    pub fn foeGoes(self: *const Node, b: *const Bespoke, p: P, k: actor.Kind) bool {
        return self.foeFits(b, p, k) and b.roomAt(p, k);
    }

    pub fn torchGoes(self: *const Node, b: *const Bespoke, p: P) bool {
        return self.torchFits(b, p) and b.torch.takes(p);
    }

    pub fn pruneAt(self: *const Node, b: *Bespoke, p: P) void {
        for ([_]P{ p, lume.torchWall(p) }) |w| {
            if (grid.Level.inside(w) and !self.torchFits(b, w)) _ = b.torch.remove(w);
        }
        const i = grid.Level.idx(p);
        if (b.barrel[i] and !self.barrelFits(b, p)) b.barrel[i] = false;
        if (b.foeAt(p)) |f| {
            if (!self.foeFits(b, p, b.foe[f].kind)) b.dropFoe(f);
        }
    }

    pub fn doorFits(_: *const Node, b: *const Bespoke, p: P) bool {
        return !b.tileAt(p).pieced();
    }

    pub fn doorCells(self: *const Node, out: *[grid.MAX_DOORS]P) []const P {
        for (self.doors(), 0..) |d, i| out[i] = d.at;
        return out[0..self.door_n];
    }

    /// A procgen node's guards by its carts, then its packs round the hero arriving at `at`, exit packs by its doors.
    pub fn placePacks(self: *const Node, lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, at: P) void {
        self.packsOff(lv, pool, rng, at, &grid.CellSet.initEmpty());
    }

    /// The foes of the section `roll` laid, each on its cell while the pool has room, then `placePacks` with no pack on a painted cell.
    pub fn populate(self: *const Node, lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, at: P, roll: u64) void {
        const laid = self.sectionOn(roll) orelse return self.placePacks(lv, pool, rng, at);
        for (self.plan.procgen.section.foes()) |f| {
            const s = laid.foe(f);
            if (pool.hasRoomFor(s.kind) and actor.dwells(s.kind, lv, s.at)) _ = pool.spawn(lv, actor.Actor.of(s.kind, s.at));
        }
        const painted = laid.cells();
        self.packsOff(lv, pool, rng, at, &painted);
    }

    fn packsOff(self: *const Node, lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, at: P, off: *const grid.CellSet) void {
        post.place(lv, pool, self.plan.procgen.post);
        var buf: [grid.MAX_DOORS]P = undefined;
        pack.placeOff(lv, pool, rng, at, self.doorCells(&buf), &self.plan.procgen.foes, off);
    }

    pub fn sectionOn(self: *const Node, roll: u64) ?section.Placed {
        var buf: [grid.MAX_DOORS]P = undefined;
        return switch (self.plan) {
            .procgen => |*pg| pg.section.lands(roll, self.doorCells(&buf)),
            .bespoke => null,
        };
    }

    /// Where the plan stands its foes on `roll`: a bespoke node's as painted, a procgen node's section's where it landed.
    pub fn placedOn(self: *const Node, roll: u64, buf: *[MAX_FOES]Foe) []const Foe {
        const laid = self.sectionOn(roll) orelse return self.placed();
        const fs = self.plan.procgen.section.foes();
        for (fs, buf[0..fs.len]) |f, *out| out.* = laid.foe(f);
        return buf[0..fs.len];
    }

    pub fn stamp(self: *const Node, lv: *grid.Level, roll: u64) void {
        var buf: [grid.MAX_DOORS]P = undefined;
        const cells = self.doorCells(&buf);
        switch (self.plan) {
            .procgen => |*pg| procgen.rollWith(lv, roll, cells, pg.floor, pg.features(), pg.section.lands(roll, cells)),
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
    pub const COUNTED = .{.{ "node", "node_n" }};
    node: [MAX_NODES]Node = undefined,
    node_n: usize = 0,
    start: Start = .{},
    /// Last: the legacy save reader takes every field before it as the format it was.
    script: script.Script = .{},

    pub fn nodes(self: *Atlas) []Node {
        return self.node[0..self.node_n];
    }

    pub fn npcFits(self: *const Atlas, n: usize, p: P) bool {
        if (n >= self.node_n or !grid.Level.inside(p)) return false;
        const nd = &self.node[n];
        return switch (nd.plan) {
            .bespoke => |*b| b.floorAt(p) and nd.doorAt(p) == null and !b.barrelAt(p) and b.foeAt(p) == null,
            .procgen => false,
        };
    }

    pub fn barrelGoes(self: *const Atlas, n: usize, b: *const Bespoke, p: P) bool {
        return self.node[n].barrelGoes(b, p) and self.script.npcAt(n, p) == null;
    }

    pub fn foeGoes(self: *const Atlas, n: usize, b: *const Bespoke, p: P, k: actor.Kind) bool {
        return self.node[n].foeGoes(b, p, k) and self.script.npcAt(n, p) == null;
    }

    pub fn pruneNpcs(self: *Atlas, n: usize) bool {
        return self.script.dropNpcsWhere(struct {
            map: *const Atlas,
            node: usize,
            pub fn drops(on: @This(), _: usize, npc: *const script.Npc) bool {
                const at = npc.cell() orelse return false;
                return npc.node == on.node and !on.map.npcFits(on.node, at);
            }
        }{ .map = self, .node = n });
    }

    /// Node `n`'s NPCs on its level as stamped by `roll`, off the cells its foes stand on.
    pub fn stampNpcs(self: *const Atlas, n: usize, lv: *grid.Level, roll: u64, stood: *script.Stood, shown: anytype) void {
        lv.clearNpcs();
        var avoid = shown.lying();
        var foes: [MAX_FOES]Foe = undefined;
        for (self.node[n].placedOn(roll, &foes)) |f| avoid.set(grid.Level.idx(f.at));
        for (self.script.npcs(), 0..) |*npc, i| if (npc.node == n) if (self.script.standsAt(i, stood)) |c| avoid.set(grid.Level.idx(c));
        for (self.script.npcs(), 0..) |*npc, i| {
            if (npc.node != n or !shown.shows(i)) continue;
            const at = self.script.standsAt(i, stood) orelse blk: {
                const p = spotFor(lv, npc.spot, &avoid) orelse continue;
                stood[i] = p;
                break :blk p;
            };
            if (lv.vacant(at)) lv.putNpc(at, i);
        }
    }

    pub fn add(self: *Atlas, plan: Plan) ?usize {
        if (!mathx.push(Node, &self.node, &self.node_n, .{ .plan = plan, .pos = self.freeSlot() })) return null;
        return self.node_n - 1;
    }

    pub fn oneRoom(self: *Atlas, room: grid.Box, at: P) usize {
        std.debug.assert(room.holds(at));
        self.* = .{};
        const n = self.add(.{ .bespoke = .{} }).?;
        self.node[n].plan.bespoke.fill(room, .floor);
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
        self.script.dropNode(n);
        mathx.removeAt(Node, &self.node, &self.node_n, n, null);
        self.renumber(.{ .node = n, .door = 0 }, Atlas.pastNode);
        if (script.renumbered(self.start.node, n)) |at| self.start.node = at else self.start = .{};
    }

    pub fn addDoor(self: *Atlas, n: usize, p: P) ?usize {
        const nd = &self.node[n];
        if (!nd.takesDoor(p) or !mathx.push(Door, &nd.door, &nd.door_n, .{ .at = p })) return null;
        return nd.door_n - 1;
    }

    pub fn removeDoor(self: *Atlas, at: Link) void {
        self.unlink(at);
        const nd = &self.node[at.node];
        mathx.removeAt(Door, &nd.door, &nd.door_n, at.door, null);
        if (nd.plan == .procgen) {
            const r = &nd.plan.procgen.raid;
            if (script.renumbered(r.raid_door, at.door)) |door_index| {
                r.raid_door = door_index;
            } else r.* = .{};
        }
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
        l.node = script.renumbered(l.node, gone.node) orelse l.node;
    }

    fn pastDoor(l: *Link, gone: Link) void {
        if (l.node == gone.node) l.door = script.renumbered(l.door, gone.door) orelse l.door;
    }

    fn doorOf(self: *Atlas, at: Link) *Door {
        return &self.node[at.node].door[at.door];
    }

    pub fn door(self: *const Atlas, at: Link) Door {
        return self.node[at.node].door[at.door];
    }

    pub fn linksValid(self: *const Atlas) bool {
        if (self.node_n > self.node.len) return false;
        for (self.node[0..self.node_n]) |*nd| if (nd.door_n > nd.door.len) return false;
        for (self.node[0..self.node_n], 0..) |*nd, n| {
            for (nd.doors(), 0..) |d, k| {
                const to = d.to orelse continue;
                if (to.node >= self.node_n or to.door >= self.node[to.node].door_n) return false;
                const here = Link{ .node = n, .door = k };
                if (to.eq(here)) return false;
                const back = self.door(to).to orelse return false;
                if (!back.eq(here)) return false;
            }
        }
        return true;
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
        var stood: script.Stood = @splat(null);
        self.stampNpcs(from.node, scratch, 0, &stood, EVERY_NPC);
        return landing(scratch, from.at, nd.placed()) != null;
    }
};

pub const EVERY_NPC = struct {
    pub fn shows(_: @This(), _: usize) bool {
        return true;
    }

    pub fn lying(_: @This()) grid.CellSet {
        return grid.CellSet.initEmpty();
    }
}{};

pub fn spotFor(lv: *const grid.Level, spot: script.Spot, avoid: *const grid.CellSet) ?P {
    return switch (spot) {
        .at => |p| p,
        .by => |t| beside(lv, t, avoid),
        .far => farFromDoors(lv, avoid),
    };
}

fn standsFree(lv: *const grid.Level, p: P, avoid: *const grid.CellSet) bool {
    return !grid.Level.onRim(p) and lv.vacant(p) and lv.doorAt(p) == null and !lv.at(p).wet() and !avoid.isSet(grid.Level.idx(p));
}

const Standing = struct {
    lv: *const grid.Level,
    avoid: *const grid.CellSet,

    fn ok(s: Standing, p: P) bool {
        return standsFree(s.lv, p, s.avoid);
    }
};

fn beside(lv: *const grid.Level, t: grid.Tile, avoid: *const grid.CellSet) ?P {
    const standing = Standing{ .lv = lv, .avoid = avoid };
    for (lv.tile, 0..) |here, i| {
        if (here != t) continue;
        if (grid.besideFoot(t.footprint(grid.Level.of(i)), standing, Standing.ok)) |b| return b;
    }
    return null;
}

fn farFromDoors(lv: *const grid.Level, avoid: *const grid.CellSet) ?P {
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var doors: ?grid.Flood = null;
    for (0..grid.CELLS) |i| {
        const d = grid.Level.of(i);
        if (lv.doorAt(d) == null) continue;
        if (doors) |*f| f.seed(d) else doors = grid.Flood.init(lv, d, &dist, &queue);
    }
    var flood = doors orelse grid.Flood.init(lv, lv.firstOpen() orelse return null, &dist, &queue);
    while (flood.next()) |_| {}
    var best: ?P = null;
    var most: i32 = -1;
    for (dist, 0..) |d, i| {
        if (d <= most or !standsFree(lv, grid.Level.of(i), avoid)) continue;
        best = grid.Level.of(i);
        most = d;
    }
    return best;
}

pub const NO_FLOOR = "{s} has no open floor to start on";
pub const NOT_LOADED = "{s} did not load ({s})";
pub const NO_MAPS = "No maps in " ++ DIR ++ " yet";

pub const Error = error{ NoHeader, BadLine, TooMany, NoNodes, NoStart, BadLink };

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

pub fn testAtlas() !*Atlas {
    const a = try std.testing.allocator.create(Atlas);
    a.* = .{};
    return a;
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

test "removing doors preserves the raid entrance or clears its removed reference" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    const n = a.add(.{ .procgen = .{ .raid = .{ .raiders = 3, .raid_door = 1 } } }).?;
    for (0..3) |i| _ = a.addDoor(n, .{ .x = @intCast(5 + i), .y = 5 });
    const entrance = a.node[n].door[1].at;
    a.removeDoor(.{ .node = n, .door = 2 });
    try std.testing.expectEqual(@as(u8, 1), a.node[n].plan.procgen.raid.raid_door);
    a.removeDoor(.{ .node = n, .door = 0 });
    const r = &a.node[n].plan.procgen.raid;
    try std.testing.expectEqual(@as(u8, 0), r.raid_door);
    try std.testing.expectEqual(@as(u8, 3), r.raiders);
    try std.testing.expect(entrance.eq(a.node[n].door[r.raid_door].at));
    a.removeDoor(.{ .node = n, .door = 0 });
    try std.testing.expectEqualDeep(raid.Raid{}, r.*);
    _ = a.addDoor(n, .{ .x = 8, .y = 5 });
    try std.testing.expectEqual(@as(u8, 0), r.raiders);
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
    try std.testing.expect(at.x > 9);
    try std.testing.expectEqual(@as(i32, 2), mathx.dist(door, at));
}

test "the strand: the archer washes up on the beach, trees stand back from the surf, and the exit is reached through them" {
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
    var surf_trees: usize = 0;
    var landward_trees: usize = 0;
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
            try std.testing.expect(carve.nearWater(&lv, p, 14));
            var land = grid.Cells.around(p, 3);
            while (land.next()) |q| {
                const there = lv.at(q);
                if (grid.Level.inside(q) and there != .dirt and there != .swamp_tree and !there.wet()) {
                    landward_trees += 1;
                    break;
                }
            }
            dirt_trees += @intFromBool(@import("../gfx/ground.zig").bedAt(&lv, p, false) == .dirt);
            inland_trees += @intFromBool(p.x > 25);
            var near = grid.Cells.around(p, 7);
            while (near.next()) |q| {
                if (grid.Level.inside(q) and q.x < 4 and lv.at(q) == .water) {
                    surf_trees += 1;
                    break;
                }
            }
            trees += 1;
        }
        try std.testing.expect(trees > 0);
        swamp_trees += trees;
    }
    try std.testing.expect(on_shore * 10 >= RUNS * 9);
    try std.testing.expect(wound / RUNS > 1.05);
    try std.testing.expect(dirt_trees * 10 >= swamp_trees * 8 and inland_trees > 0 and surf_trees * 20 < swamp_trees and landward_trees * 10 >= swamp_trees * 8);
}

test "the strand holds only rats, crossbowmen, pibs, two shamans, two bloats and one beefy pib by the exit" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    try a.load(std.testing.allocator, START);
    var lv: grid.Level = undefined;
    const nd = &a.node[a.start.node];
    const exit = nd.doors()[0].at;
    const allowed = std.EnumSet(actor.Kind).initMany(&.{ .rat, .bandit_crossbowman, .pib, .pib_shaman, .beefy_pib, .bloat });
    var farthest: i32 = 0;
    const RUNS = 50;
    for (0..RUNS) |i| {
        const seed = 0xF0E5 +% i *% grid.TEST_SEED_STRIDE;
        nd.stamp(&lv, seed);
        const at = landing(&lv, a.start.at, &.{}) orelse return error.NoFloor;
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(seed);
        nd.placePacks(&lv, &pool, &rng, at);
        try std.testing.expectEqual(@as(usize, 1), pool.tally(.beefy_pib).total);
        try std.testing.expectEqual(@as(usize, 2), pool.tally(.pib_shaman).total);
        try std.testing.expectEqual(@as(usize, 2), pool.tally(.bloat).total);
        for (pool.slice()) |f| {
            try std.testing.expect(allowed.contains(f.kind));
            if (f.kind == .beefy_pib) farthest = @max(farthest, mathx.dist(f.at, exit));
        }
    }
    try std.testing.expect(farthest <= pack.EXIT_REACH);
}

test "the strand's door leads to a tee: the whole caravan camp walks from where the hero comes in, carts and a stone bridge on every roll" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    try a.load(std.testing.allocator, START);
    const link = a.node[a.start.node].doors()[0].to orelse return error.NoLink;
    const nd = &a.node[link.node];
    try std.testing.expect(nd.plan == .procgen and nd.plan.procgen.floor == .tee);
    const door = nd.doors()[link.door].at;
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var carts: usize = 0;
    var bridges: usize = 0;
    const RUNS = 50;
    for (0..RUNS) |i| {
        nd.stamp(&lv, 0xCA2A +% i *% grid.TEST_SEED_STRIDE);
        try grid.expectAllReached(&lv, door, &dist, &queue);
        carts += carve.count(&lv, .caravan);
        bridges += @intFromBool(carve.count(&lv, .stone_bridge) > 0);
    }
    try std.testing.expect(carts >= RUNS * 2);
    try std.testing.expectEqual(@as(usize, RUNS), bridges);
}

fn besideCart(lv: *const grid.Level, p: P) bool {
    var round = grid.Cells.around(p, 1);
    while (round.next()) |q| {
        if (grid.Level.inside(q) and lv.at(q).whole() == .caravan) return true;
    }
    return false;
}

test "the caravan posts three guards beside its carts, apart from the merchant, and no foe near a cart, on every roll" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    try a.load(std.testing.allocator, START);
    const link = a.node[a.start.node].doors()[0].to orelse return error.NoLink;
    const nd = &a.node[link.node];
    var lv: grid.Level = undefined;
    var fewest: usize = post.GUARDS_MAX;
    var foes: usize = 0;
    const RUNS = 50;
    for (0..RUNS) |i| {
        const seed = 0x6A2D +% i *% grid.TEST_SEED_STRIDE;
        var stood: script.Stood = @splat(null);
        nd.stamp(&lv, seed);
        a.stampNpcs(link.node, &lv, seed, &stood, EVERY_NPC);
        const at = landing(&lv, nd.doors()[link.door].at, &.{}) orelse return error.NoFloor;
        var pool = actor.Pool{};
        _ = pool.spawn(&lv, actor.Actor.of(actor.HERO, at));
        var rng = mathx.Rng.init(seed);
        nd.placePacks(&lv, &pool, &rng, at);
        var guards: usize = 0;
        for (pool.constSlice()) |g| {
            if (g.foe()) {
                var near = grid.Cells.around(g.at, pack.CAMP_GAP - 1);
                while (near.next()) |q| try std.testing.expect(!grid.Level.inside(q) or lv.at(q).whole() != .caravan);
                foes += 1;
            }
            if (g.kind != post.GUARD) continue;
            guards += 1;
            try std.testing.expect(lv.npcAt(g.at) == null);
            try std.testing.expect(besideCart(&lv, g.at));
        }
        fewest = @min(fewest, guards);
    }
    try std.testing.expect(foes > RUNS);
    try std.testing.expectEqual(@as(usize, 3), fewest);
}

test "the caravan's merchant stands beside a cart, and the stolen baby pib far up the goblin camp, on every roll" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    try a.load(std.testing.allocator, START);
    const caravan = (a.node[a.start.node].doors()[0].to orelse return error.NoLink).node;
    const north = a.node[caravan].doors()[1].to orelse return error.NoLink;
    const s = &a.script;
    const merchant = for (s.npcs(), 0..) |f, i| {
        if (f.node == caravan and std.mem.eql(u8, f.called(), "Merchant")) break i;
    } else return error.NoMerchant;
    const baby = for (s.npcs(), 0..) |f, i| {
        if (f.node == north.node) break i;
    } else return error.NoBabyPib;
    try std.testing.expect(s.findQuest("stolen_pib") != null);
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var nearest_walk: i32 = grid.CELLS;
    const door = a.node[north.node].doors()[north.door].at;
    const RUNS = 50;
    for (0..RUNS) |i| {
        const seed = 0xFA2 +% i *% grid.TEST_SEED_STRIDE;
        var stood: script.Stood = @splat(null);
        a.node[caravan].stamp(&lv, seed);
        a.stampNpcs(caravan, &lv, seed, &stood, EVERY_NPC);
        const at = stood[merchant] orelse return error.NoPlace;
        try std.testing.expectEqual(@as(?usize, merchant), lv.npcAt(at));
        try std.testing.expect(besideCart(&lv, at));
        a.node[north.node].stamp(&lv, seed);
        a.stampNpcs(north.node, &lv, seed, &stood, EVERY_NPC);
        const pib = stood[baby] orelse return error.NoPlace;
        _ = grid.distances(&lv, door, &dist, &queue);
        const walk = dist[grid.Level.idx(pib)];
        try std.testing.expect(walk > 0);
        nearest_walk = @min(nearest_walk, walk);
    }
    try std.testing.expect(nearest_walk >= grid.H / 2);
}

test "the strand grows a few glowing plants on every roll" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    try a.load(std.testing.allocator, START);
    var lv: grid.Level = undefined;
    const nd = &a.node[a.start.node];
    var least: usize = grid.CELLS;
    var most: usize = 0;
    var total: usize = 0;
    const RUNS = 50;
    for (0..RUNS) |i| {
        nd.stamp(&lv, 0x6C0E +% i *% grid.TEST_SEED_STRIDE);
        const n = carve.count(&lv, .glow_plant);
        least = @min(least, n);
        most = @max(most, n);
        total += n;
    }
    try std.testing.expect(least >= 1 and most <= 14 and total >= RUNS * 3);
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
    }
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
}

test "a section's foes stand on their cells wherever it lands, packs keep off its cells, and the pool never overfills" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    const n = a.add(.{ .procgen = .{ .floor = procgen.Floor.of(.open), .foes = .{ .packs = 12 } } }).?;
    const door = P{ .x = 0, .y = 30 };
    _ = a.addDoor(n, door);
    const nd = &a.node[n];
    const s = &nd.plan.procgen.section;
    s.anchor = .roams;
    var it = grid.Box.sized(.{ .x = 10, .y = 10 }, 9, 6).cells();
    while (it.next()) |p| _ = s.paint(p, .floor);
    for (0..4) |k| try std.testing.expect(s.addFoe(.{ .kind = .slime, .at = .{ .x = @intCast(11 + k * 2), .y = 12 } }));
    try std.testing.expect(s.addFoe(.{ .kind = .rat, .at = .{ .x = 14, .y = 14 } }));
    var lv: grid.Level = undefined;
    var buf: [MAX_FOES]Foe = undefined;
    var corners = grid.CellSet.initEmpty();
    var moved: usize = 0;
    var packed_foes: usize = 0;
    var astray: usize = 0;
    const RUNS = 50;
    for (0..RUNS) |i| {
        const roll = 0xF0E +% i *% grid.TEST_SEED_STRIDE;
        nd.stamp(&lv, roll);
        const placed = nd.placedOn(roll, &buf);
        try std.testing.expectEqual(s.foe_n, placed.len);
        const at = landing(&lv, door, placed) orelse return error.NoFloor;
        var pool = actor.Pool{};
        _ = pool.spawn(&lv, actor.Actor.of(actor.HERO, at));
        var rng = mathx.Rng.init(roll);
        nd.populate(&lv, &pool, &rng, at, roll);
        try std.testing.expect(pool.eventual() <= actor.MAX);
        const laid = nd.sectionOn(roll).?;
        const k = grid.Level.idx(laid.area.lo);
        if (!corners.isSet(k)) moved += 1;
        corners.set(k);
        const painted = laid.cells();
        for (placed) |f| {
            const id = lv.who(f.at);
            try std.testing.expect(id != grid.NO_ONE);
            try std.testing.expectEqual(f.kind, pool.items[actor.Pool.slot(id)].kind);
        }
        for (pool.constSlice()) |b| {
            if (!b.foe() or (for (placed) |f| {
                if (f.at.eq(b.at)) break true;
            } else false)) continue;
            packed_foes += 1;
            if (painted.isSet(grid.Level.idx(b.at))) astray += 1;
        }
    }
    try std.testing.expect(moved * 2 > RUNS and packed_foes > RUNS);
    try std.testing.expectEqual(@as(usize, 0), astray);
}
