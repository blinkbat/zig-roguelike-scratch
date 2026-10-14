const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const lume = @import("lume.zig");
const gen = @import("gen.zig");
const procgen = @import("procgen.zig");
const actor = @import("../play/actor.zig");
const store = @import("../core/store.zig");
const pack = @import("../play/pack.zig");
const climate = @import("climate.zig");

const P = mathx.P;

pub const MAX_NODES: usize = 32;
/// Every placed foe and the archer fit the pool.
pub const MAX_FOES: usize = actor.MAX - 1;
pub const DIR = "worlds";
pub const EXT = ".world";
pub const MAIN = worldPath("main");
/// The world New plays.
pub const START = worldPath("start");

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

pub fn worldPath(comptime stem: []const u8) []const u8 {
    return PREFIX ++ stem ++ EXT;
}
const HEADER = "roguelike-world 1";
const TEXT_CAP: usize = 8 << 20;
const COLS = grid.COLS;
const ROWS = grid.ROWS;
pub const NAME_MAX: usize = 20;
const UNNAMED = "node ";
pub const TITLE_MAX: usize = @max(NAME_MAX, UNNAMED.len + std.fmt.count("{d}", .{MAX_NODES - 1}));
/// A new node's box takes the first free place on a grid of the editor's graph this many boxes wide.
const GRAPH_COLS: usize = 4;
pub const GRAPH_STEP = P{ .x = 240, .y = 200 };
/// A box's place on the graph, either way on either axis; far enough that i32 sums of places never overflow.
pub const POS_MAX: u32 = 1 << 24;
/// A world file's name, `.world` and all.
const FILE_MAX: usize = 64;
/// A world file's name before `.world`, as `pathFor` makes it.
pub const STEM_MAX = FILE_MAX - EXT.len;
/// The folders a listed world lies in below `DIR`, names and '/'s.
const FOLDER_MAX: usize = 64;
pub const PATH_MAX = PREFIX.len + FOLDER_MAX + FILE_MAX;
const ListedPath = [PATH_MAX + 1]u8;

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

/// Rolled round its doors each run: its base, then each of its features over it, in order.
pub const Procgen = struct {
    floor: Floor = .{ .rooms = .{} },
    /// Past `feature_n`, each slot as `Feature.of` leaves it, so two plans compare by what they hold.
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
        if (self.foe_n == MAX_FOES or self.foeAt(f.at) != null or !actor.roomFor(self.bodies(), f.kind)) return false;
        self.foe[self.foe_n] = f;
        self.foe_n += 1;
        return true;
    }

    pub fn dropFoe(self: *Bespoke, i: usize) void {
        self.foe_n -= 1;
        self.foe[i] = self.foe[self.foe_n];
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

    /// The foes placed on it, where the archer never lands; a procgen node's are rolled in play.
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
        return self.door_n < grid.MAX_DOORS and self.doorAt(p) == null and grid.Level.inside(p) and !grid.Level.cornered(p);
    }

    pub fn foeFits(self: *const Node, b: *const Bespoke, p: P) bool {
        return b.floorAt(p) and self.doorAt(p) == null and !grid.cellOr(bool, &b.barrel, p, false);
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

    pub fn stamp(self: *const Node, lv: *grid.Level, roll: u64) void {
        var cells: [grid.MAX_DOORS]P = undefined;
        for (self.doors(), 0..) |d, i| cells[i] = d.at;
        switch (self.plan) {
            .procgen => |*pg| procgen.roll(lv, roll, cells[0..self.door_n], pg.floor, pg.features()),
            .bespoke => |*b| {
                lv.* = grid.Level.blank();
                lv.tile = b.tile;
                self.openDoors(lv);
                gen.shapeWalls(lv);
                lv.torch = b.torch;
                gen.keepTorches(lv);
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
                self.openDoors(lv);
            },
        }
    }

    fn openDoors(self: *const Node, lv: *grid.Level) void {
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

    fn freeSlot(self: *Atlas) P {
        const cols: i32 = @intCast(GRAPH_COLS);
        var i: i32 = 0;
        while (true) : (i += 1) {
            const p = P{ .x = @mod(i, cols) * GRAPH_STEP.x, .y = @divTrunc(i, cols) * GRAPH_STEP.y };
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

    /// Every link, once `gone` is taken away.
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

    pub fn save(self: *Atlas, alloc: std.mem.Allocator, path: []const u8) !void {
        var text = std.ArrayList(u8).init(alloc);
        defer text.deinit();
        try self.write(text.writer());
        try store.replace(path, text.items);
    }

    pub fn write(self: *Atlas, w: anytype) !void {
        try w.print(HEADER ++ "\n" ++ says(.start) ++ "{d} {d} {d}\n", .{ self.start.node, self.start.at.x, self.start.at.y });
        for (self.nodes()) |*nd| {
            switch (nd.plan) {
                .procgen => |*pg| {
                    try w.print(says(.node) ++ "{s} {s}\n", .{ @tagName(nd.plan), @tagName(pg.floor) });
                    try putArm(w, &pg.floor);
                    inline for (GROUPS) |grp| {
                        inline for (grp.knobs) |k| try putKnob(w, k, @field(@field(pg, grp.field), k));
                    }
                    for (pg.foes.makeups()) |*m| {
                        try w.print(says(.makeup) ++ "{d}", .{m.weight});
                        for (m.kinds()) |k| try w.print(" {s}", .{@tagName(k)});
                        try w.writeByte('\n');
                    }
                    for (pg.features()) |*ft| {
                        try w.print(says(.feature) ++ "{s}\n", .{@tagName(ft.*)});
                        try putArm(w, ft);
                    }
                },
                .bespoke => |*b| {
                    try w.print(says(.node) ++ "{s}\n", .{@tagName(nd.plan)});
                    for (0..ROWS) |y| {
                        try w.writeAll(says(.row));
                        for (0..COLS) |x| {
                            const i = grid.Level.idx(.{ .x = @intCast(x), .y = @intCast(y) });
                            try w.writeByte(if (b.barrel[i]) grid.BARREL_LETTER else b.tile[i].letter());
                        }
                        try w.writeByte('\n');
                    }
                    for (b.torches()) |t| try w.print(says(.torch) ++ "{d} {d}\n", .{ t.x, t.y });
                    for (b.foes()) |f| try w.print(says(.foe) ++ "{s} {d} {d}\n", .{ @tagName(f.kind), f.at.x, f.at.y });
                },
            }
            if (nd.label.n > 0) try w.print(says(.name) ++ "{s}\n", .{nd.name()});
            try w.print(says(.at) ++ "{d} {d}\n", .{ nd.pos.x, nd.pos.y });
            for (nd.doors()) |d| {
                try w.print(says(.door) ++ "{d} {d}", .{ d.at.x, d.at.y });
                if (d.to) |l| try w.print(" {d} {d}", .{ l.node, l.door });
                try w.writeByte('\n');
            }
        }
    }

    pub fn load(self: *Atlas, alloc: std.mem.Allocator, path: []const u8) !void {
        const text = try std.fs.cwd().readFileAlloc(alloc, path, TEXT_CAP);
        defer alloc.free(text);
        try self.parse(text);
    }

    pub fn parse(self: *Atlas, text: []const u8) Error!void {
        self.* = .{};
        var lines = std.mem.splitScalar(u8, text, '\n');
        const head = std.mem.trimRight(u8, lines.next() orelse return error.NoHeader, "\r");
        if (!std.mem.eql(u8, head, HEADER)) return error.NoHeader;
        var row: usize = 0;
        var own_makeups = false;
        var seen = std.EnumSet(Word).initEmpty();
        var knobbed = KnobSet.initEmpty();
        var featured = FeatureKnobSet.initEmpty();
        while (lines.next()) |raw| {
            const line = std.mem.trimRight(u8, raw, "\r");
            var f = std.mem.tokenizeScalar(u8, line, ' ');
            const word = f.next() orelse continue;
            const said = std.meta.stringToEnum(Word, word) orelse {
                const pg = try self.procgen();
                if (pg.feature_n > 0) {
                    try takeFeatureKnob(&pg.feature[pg.feature_n - 1], word, &f, &featured);
                } else try takeKnob(pg, word, &f, &knobbed);
                if (f.next() != null) return error.BadLine;
                continue;
            };
            if (ONCE.contains(said)) {
                if (seen.contains(said)) return error.BadLine;
                seen.insert(said);
            }
            switch (said) {
                .start => self.start = .{ .node = try int(usize, &f), .at = try cell(&f) },
                .node => {
                    const kind = try takeValue(std.meta.Tag(Plan), &f);
                    const plan: Plan = switch (kind) {
                        .procgen => blk: {
                            const algo = try takeValue(Algo, &f);
                            // Written before procgen nodes were rolled each run: the seed they kept is let go.
                            if (f.peek() != null) _ = try int(u64, &f);
                            break :blk .{ .procgen = .{ .floor = Floor.of(algo) } };
                        },
                        .bespoke => .{ .bespoke = .{} },
                    };
                    try self.finished(row);
                    _ = self.add(plan) orelse return error.TooMany;
                    row = 0;
                    own_makeups = false;
                    seen = seen.intersectWith(ONCE_FILE);
                    knobbed = KnobSet.initEmpty();
                },
                .name => {
                    _ = (try self.last()).rename(f.rest()) orelse return error.BadLine;
                    continue;
                },
                .at => {
                    const pos = P{ .x = try int(i32, &f), .y = try int(i32, &f) };
                    if (@abs(pos.x) > POS_MAX or @abs(pos.y) > POS_MAX) return error.BadLine;
                    (try self.last()).pos = pos;
                },
                .door => {
                    const nd = try self.last();
                    const at = try cell(&f);
                    const k = self.addDoor(self.node_n - 1, at) orelse return error.TooMany;
                    if (f.peek() != null) nd.door[k].to = .{ .node = try int(usize, &f), .door = try int(usize, &f) };
                },
                .feature => {
                    const pg = try self.procgen();
                    const k = try takeValue(Kind, &f);
                    if (!pg.addFeature(k)) return error.TooMany;
                    featured = FeatureKnobSet.initEmpty();
                },
                .makeup => {
                    const pg = try self.procgen();
                    if (pg.feature_n > 0) return error.BadLine;
                    const fo = &pg.foes;
                    if (!own_makeups) fo.makeup_n = 0;
                    own_makeups = true;
                    if (!fo.addMakeup()) return error.TooMany;
                    const m = &fo.makeup[fo.makeup_n - 1];
                    m.* = .{ .weight = try int(u8, &f), .n = 0 };
                    while (f.next()) |name| {
                        const k = std.meta.stringToEnum(actor.Kind, name) orelse return error.BadLine;
                        if (!m.grow()) return error.BadLine;
                        m.kind[m.n - 1] = k;
                    }
                },
                .row => {
                    const b = try self.bespoke();
                    const cells = f.next() orelse return error.BadLine;
                    if (cells.len != COLS or row == ROWS) return error.BadLine;
                    for (cells, 0..) |c, x| {
                        const i = grid.Level.idx(.{ .x = @intCast(x), .y = @intCast(row) });
                        b.barrel[i] = c == grid.BARREL_LETTER;
                        b.tile[i] = grid.groundOf(c) orelse return error.BadLine;
                    }
                    row += 1;
                },
                .torch => if (!(try self.bespoke()).torch.add(try cell(&f))) return error.TooMany,
                .foe => {
                    const b = try self.bespoke();
                    const k = try takeValue(actor.Kind, &f);
                    if (!k.stocked() or !b.addFoe(.{ .kind = k, .at = try cell(&f) })) return error.BadLine;
                },
            }
            if (f.next() != null) return error.BadLine;
        }
        try self.finished(row);
        if (self.node_n == 0) return error.NoNodes;
        if (!seen.contains(.start)) return error.NoStart;
        for (self.nodes(), 0..) |*nd, n| {
            for (nd.doors(), 0..) |d, k| {
                const l = d.to orelse continue;
                if (l.node >= self.node_n or l.door >= self.node[l.node].door_n) return error.BadLink;
                const here = Link{ .node = n, .door = k };
                if (l.eq(here)) return error.BadLink;
                const back = self.door(l).to orelse return error.BadLink;
                if (!back.eq(here)) return error.BadLink;
            }
        }
        if (self.start.node >= self.node_n) return error.BadLink;
    }

    fn finished(self: *Atlas, rows: usize) Error!void {
        if (self.node_n == 0) return;
        const nd = &self.node[self.node_n - 1];
        switch (nd.plan) {
            .bespoke => |*b| {
                if (rows != ROWS) return error.BadLine;
                for (b.foes()) |f| {
                    if (!nd.foeFits(b, f.at)) return error.BadLine;
                }
                for (b.torches()) |t| {
                    if (!nd.torchFits(b, t)) return error.BadLine;
                }
                for (b.barrel, 0..) |on, i| {
                    if (on and !nd.barrelFits(b, grid.Level.of(i))) return error.BadLine;
                }
            },
            .procgen => |*pg| if (!pg.valid()) return error.BadLine,
        }
    }

    pub fn standable(self: *const Atlas, from: Start, scratch: *grid.Level) bool {
        const nd = &self.node[from.node];
        if (nd.unrolled()) return true;
        nd.sketch(scratch);
        return landing(scratch, from.at, nd.placed()) != null;
    }

    fn procgen(self: *Atlas) Error!*Procgen {
        return switch ((try self.last()).plan) {
            .procgen => |*pg| pg,
            .bespoke => error.BadLine,
        };
    }

    fn last(self: *Atlas) Error!*Node {
        if (self.node_n == 0) return error.BadLine;
        return &self.node[self.node_n - 1];
    }

    fn bespoke(self: *Atlas) Error!*Bespoke {
        return switch ((try self.last()).plan) {
            .bespoke => |*b| b,
            .procgen => error.BadLine,
        };
    }
};

pub const NO_FLOOR = "{s} has no open floor to start on";
pub const NOT_LOADED = "{s} did not load ({s})";
pub const NO_WORLDS = "No worlds in " ++ DIR ++ " yet";

pub const Error = error{ NoHeader, BadLine, TooMany, NoNodes, NoStart, BadLink };

/// A procgen node's base lines: each named for, and holding, a field of its floor; the foes' are `FOE_KNOBS`.
pub fn floorKnobs(comptime a: Algo) []const []const u8 {
    return armKnobs(Floor, a);
}
const FLOOR_KNOBS_MAX = mostKnobs(Floor);
pub const FOE_KNOBS = knobsOf(pack.Spec, MAKEUP_FIELDS);
/// Its sky's lines, `climate.Climate`'s fields.
pub const SKY_KNOBS = knobsOf(climate.Climate, &.{});
/// Every other line's first word, which no knob may take.
const Word = enum { start, node, name, at, door, makeup, feature, row, torch, foe };
const ONCE_FILE = std.EnumSet(Word).initOne(.start);
const ONCE_NODE = std.EnumSet(Word).initMany(&.{ .name, .at });
const ONCE = ONCE_FILE.unionWith(ONCE_NODE);
/// A feature's lines after its own: each named for, and holding, a field of it.
pub fn featureKnobs(comptime k: Kind) []const []const u8 {
    return armKnobs(Feature, k);
}
const FEATURE_KNOBS_MAX = mostKnobs(Feature);
const FeatureKnobSet = std.StaticBitSet(FEATURE_KNOBS_MAX);
/// A procgen node's other knobs, each group a field of `Procgen`.
const GROUPS = [_]struct { field: []const u8, knobs: []const []const u8 }{
    .{ .field = "foes", .knobs = FOE_KNOBS },
    .{ .field = "sky", .knobs = SKY_KNOBS },
};
const GROUP_KNOBS = blk: {
    var all: []const []const u8 = &.{};
    for (GROUPS) |grp| all = all ++ grp.knobs;
    break :blk all;
};
/// An algorithm's knobs by place, then each group's in turn after `FLOOR_KNOBS_MAX`.
const KnobSet = std.StaticBitSet(groupBase(GROUPS.len));
const MAKEUP = @tagName(Word.makeup);
/// `pack.Spec`'s makeups, which are lines of their own.
const MAKEUP_FIELDS: []const []const u8 = &.{ MAKEUP, MAKEUP ++ "_n" };

fn says(comptime w: Word) []const u8 {
    return @tagName(w) ++ " ";
}

comptime {
    @setEvalBranchQuota(1_000_000);
    for (MAKEUP_FIELDS) |m| std.debug.assert(@hasField(pack.Spec, m));
    for (std.enums.values(Algo)) |algo| distinct(floorKnobs(algo) ++ GROUP_KNOBS ++ knobsOf(Word, &.{}));
    for (std.enums.values(Kind)) |kind| distinct(featureKnobs(kind) ++ knobsOf(Word, &.{}));
}

fn distinct(comptime names: []const []const u8) void {
    for (names, 0..) |a, i| {
        for (names[0..i]) |b| std.debug.assert(!std.mem.eql(u8, a, b));
    }
}

fn armKnobs(comptime U: type, comptime tag: std.meta.Tag(U)) []const []const u8 {
    return knobsOf(@FieldType(U, @tagName(tag)), &.{});
}

fn mostKnobs(comptime U: type) usize {
    var most: usize = 0;
    for (std.enums.values(std.meta.Tag(U))) |t| most = @max(most, armKnobs(U, t).len);
    return most;
}

fn knobsOf(comptime T: type, comptime skip: []const []const u8) []const []const u8 {
    @setEvalBranchQuota(100_000);
    comptime var out: []const []const u8 = &.{};
    inline for (std.meta.fields(T)) |f| {
        const skipped = for (skip) |s| {
            if (std.mem.eql(u8, s, f.name)) break true;
        } else false;
        if (!skipped) out = out ++ &[_][]const u8{f.name};
    }
    return out;
}

fn takeKnob(pg: *Procgen, word: []const u8, f: *std.mem.TokenIterator(u8, .scalar), knobbed: *KnobSet) Error!void {
    if (try takeArm(&pg.floor, word, f, knobbed)) return;
    inline for (GROUPS, 0..) |grp, g| {
        inline for (grp.knobs, 0..) |k, i| {
            if (std.mem.eql(u8, word, k)) return takeOnce(&@field(pg, grp.field), k, comptime groupBase(g) + i, f, knobbed);
        }
    }
    return error.BadLine;
}

fn groupBase(comptime g: usize) usize {
    var at = FLOOR_KNOBS_MAX;
    for (GROUPS[0..g]) |grp| at += grp.knobs.len;
    return at;
}

fn takeFeatureKnob(ft: *Feature, word: []const u8, f: *std.mem.TokenIterator(u8, .scalar), set: *FeatureKnobSet) Error!void {
    if (!try takeArm(ft, word, f, set)) return error.BadLine;
}

/// The knob named `word` of the union's arm, if it has one.
fn takeArm(u: anytype, word: []const u8, f: *std.mem.TokenIterator(u8, .scalar), knobbed: anytype) Error!bool {
    switch (u.*) {
        inline else => |*p, t| inline for (comptime armKnobs(@TypeOf(u.*), t), 0..) |k, i| {
            if (std.mem.eql(u8, word, k)) {
                try takeOnce(p, k, i, f, knobbed);
                return true;
            }
        },
    }
    return false;
}

fn putArm(w: anytype, u: anytype) !void {
    switch (u.*) {
        inline else => |*p, t| inline for (comptime armKnobs(@TypeOf(u.*), t)) |k| try putKnob(w, k, @field(p.*, k)),
    }
}

fn takeOnce(owner: anytype, comptime k: []const u8, i: usize, f: *std.mem.TokenIterator(u8, .scalar), knobbed: anytype) Error!void {
    if (knobbed.isSet(i)) return error.BadLine;
    knobbed.set(i);
    @field(owner.*, k) = try takeValue(@TypeOf(@field(owner.*, k)), f);
}

fn putKnob(w: anytype, comptime name: []const u8, v: anytype) !void {
    try w.writeAll(name);
    try putValue(w, v);
    try w.writeByte('\n');
}

/// How many numbers a knob of type `T` holds on its line.
pub fn knobNumbers(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .int, .@"enum" => 1,
        .array => |a| a.len,
        .@"struct" => |s| s.fields.len,
        else => @compileError(@typeName(T) ++ " is no knob"),
    };
}

fn putValue(w: anytype, v: anytype) !void {
    const T = @TypeOf(v);
    switch (@typeInfo(T)) {
        .int => try w.print(" {d}", .{v}),
        .@"enum" => try w.print(" {s}", .{@tagName(v)}),
        .array => for (v) |x| try putValue(w, x),
        .@"struct" => inline for (std.meta.fields(T)) |f| try putValue(w, @field(v, f.name)),
        else => @compileError(@typeName(T) ++ " is no knob"),
    }
}

fn takeValue(comptime T: type, f: *std.mem.TokenIterator(u8, .scalar)) Error!T {
    switch (@typeInfo(T)) {
        .int => return int(T, f),
        .@"enum" => return std.meta.stringToEnum(T, f.next() orelse return error.BadLine) orelse error.BadLine,
        .array => |a| {
            var out: T = undefined;
            for (&out) |*x| x.* = try takeValue(a.child, f);
            return out;
        },
        .@"struct" => {
            var out: T = undefined;
            inline for (std.meta.fields(T)) |fl| @field(out, fl.name) = try takeValue(fl.type, f);
            return out;
        },
        else => @compileError(@typeName(T) ++ " is no knob"),
    }
}

fn int(comptime T: type, f: *std.mem.TokenIterator(u8, .scalar)) Error!T {
    return std.fmt.parseInt(T, f.next() orelse return error.BadLine, 10) catch error.BadLine;
}

fn cell(f: *std.mem.TokenIterator(u8, .scalar)) Error!P {
    const p = P{ .x = try int(i32, f), .y = try int(i32, f) };
    return if (grid.Level.inside(p)) p else error.BadLine;
}

/// The folder below `DIR` a world's path lies in, its '/' kept; none for a path outside `DIR`.
pub fn folderOf(path: []const u8) []const u8 {
    if (!std.mem.startsWith(u8, path, PREFIX)) return "";
    const rest = path[PREFIX.len..];
    const end = std.mem.lastIndexOfScalar(u8, rest, '/') orelse return "";
    return rest[0 .. end + 1];
}

/// In `folder`, as `folderOf` gives it.
pub fn pathFor(buf: []u8, folder: []const u8, name: []const u8) ?[]const u8 {
    var stem: [STEM_MAX]u8 = undefined;
    var n: usize = 0;
    for (std.mem.trim(u8, name, " ")) |c| {
        if (n == stem.len) break;
        const k = std.ascii.toLower(c);
        if (!std.ascii.isAlphanumeric(k) and k != '_' and k != ' ') continue;
        stem[n] = if (k == ' ') '_' else k;
        n += 1;
    }
    if (n == 0 or folder.len > FOLDER_MAX) return null;
    return std.fmt.bufPrint(buf, PREFIX ++ "{s}{s}" ++ EXT, .{ folder, stem[0..n] }) catch null;
}

/// One folder of `DIR` at a time: below `DIR` the way back up first, then its folders, then its worlds, each sorted;
/// past `MAX`, the first `MAX` of them.
pub const Listing = struct {
    pub const MAX: usize = 128;
    pub const UP = "..";
    /// Folders below `DIR` a walk of every world goes, at most.
    const DEPTH_MAX: usize = 8;
    file: [MAX]Listed = undefined,
    n: usize = 0,
    /// The folder listed, below `DIR`: each folder's name and a '/', none at `DIR` itself.
    folder: [FOLDER_MAX]u8 = undefined,
    folder_n: usize = 0,

    pub const Entry = enum { up, folder, world };

    const Listed = struct {
        buf: ListedPath,
        n: usize,
        entry: Entry,

        fn text(l: *const Listed) [:0]const u8 {
            return l.buf[0..l.n :0];
        }

        fn before(_: void, a: Listed, b: Listed) bool {
            if (a.entry != b.entry) return @intFromEnum(a.entry) < @intFromEnum(b.entry);
            return std.mem.lessThan(u8, a.text(), b.text());
        }
    };

    /// A world's file, a folder's path and its '/', or `UP`.
    pub fn at(self: *const Listing, i: usize) [:0]const u8 {
        return self.file[i].text();
    }

    pub fn entry(self: *const Listing, i: usize) Entry {
        return self.file[i].entry;
    }

    /// What its row shows: a world's stem, a folder's name and its '/', or `UP`.
    pub fn label(self: *const Listing, i: usize) []const u8 {
        const p = self.at(i);
        return switch (self.entry(i)) {
            .up => p,
            .folder => p[PREFIX.len + self.folder_n ..],
            .world => self.stem(i),
        };
    }

    /// A world's file name before `EXT`.
    pub fn stem(self: *const Listing, i: usize) []const u8 {
        const p = self.at(i);
        const from = if (std.mem.lastIndexOfScalar(u8, p, '/')) |k| k + 1 else 0;
        return p[from .. p.len - EXT.len];
    }

    /// The folder listed, below `DIR`.
    pub fn here(self: *const Listing) []const u8 {
        return self.folder[0..self.folder_n];
    }

    /// Into the folder at `i`, or up from `UP`; false for a world.
    pub fn open(self: *Listing, i: usize) bool {
        switch (self.entry(i)) {
            .world => return false,
            .up => _ = self.up(),
            .folder => {
                const name = self.label(i);
                _ = self.enter(name[0 .. name.len - 1]);
                self.scan();
            },
        }
        return true;
    }

    /// To the folder above; false at `DIR` itself.
    pub fn up(self: *Listing) bool {
        if (self.folder_n == 0) return false;
        const inner = self.folder[0 .. self.folder_n - 1];
        self.folder_n = if (std.mem.lastIndexOfScalar(u8, inner, '/')) |k| k + 1 else 0;
        self.scan();
        return true;
    }

    /// `folder`, as `folderOf` gives it; `DIR` itself if it is not there.
    pub fn scanAt(self: *Listing, folder: []const u8) void {
        self.folder_n = 0;
        if (folder.len <= FOLDER_MAX) {
            @memcpy(self.folder[0..folder.len], folder);
            self.folder_n = folder.len;
        }
        self.scan();
    }

    /// The folder listed; `DIR` itself if that folder is gone.
    pub fn scan(self: *Listing) void {
        self.n = 0;
        if (self.folder_n > 0) self.add(.up, "{s}", .{UP});
        if (!self.gather(null)) {
            if (self.folder_n == 0) return;
            self.folder_n = 0;
            return self.scan();
        }
        self.sort();
    }

    /// Every world in every folder of `DIR`, by path.
    pub fn scanAll(self: *Listing) void {
        self.n = 0;
        self.folder_n = 0;
        _ = self.gather(0);
        self.sort();
    }

    fn fits(self: *const Listing, name: []const u8) bool {
        return self.folder_n + name.len + 1 <= FOLDER_MAX;
    }

    /// Below the listed folder into `name`; false, and still here, when the path would not fit.
    fn enter(self: *Listing, name: []const u8) bool {
        if (!self.fits(name)) return false;
        @memcpy(self.folder[self.folder_n..][0..name.len], name);
        self.folder[self.folder_n + name.len] = '/';
        self.folder_n += name.len + 1;
        return true;
    }

    /// The listed folder's own entries; walking from `depth`, its worlds and those of the folders below it to `DEPTH_MAX` instead. False when it will not open.
    fn gather(self: *Listing, walking: ?usize) bool {
        var buf: [PATH_MAX]u8 = undefined;
        var dir = std.fs.cwd().openDir(self.dirPath(&buf), .{ .iterate = true }) catch return false;
        defer dir.close();
        var it = dir.iterate();
        while (it.next() catch null) |e| {
            if (!shown(e.name)) continue;
            switch (e.kind) {
                .directory => if (walking) |depth| {
                    const was = self.folder_n;
                    if (depth < DEPTH_MAX and self.enter(e.name)) _ = self.gather(depth + 1);
                    self.folder_n = was;
                } else if (self.fits(e.name)) self.add(.folder, PREFIX ++ "{s}{s}/", .{ self.here(), e.name }),
                .file => if (std.mem.endsWith(u8, e.name, EXT) and e.name.len <= FILE_MAX) self.add(.world, PREFIX ++ "{s}{s}", .{ self.here(), e.name }),
                else => {},
            }
        }
        return true;
    }

    fn dirPath(self: *const Listing, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, PREFIX ++ "{s}", .{self.here()}) catch DIR;
    }

    fn shown(name: []const u8) bool {
        return name.len > 0 and name[0] != '.' and plain(name);
    }

    fn add(self: *Listing, e: Entry, comptime fmt: []const u8, args: anytype) void {
        var l: Listed = undefined;
        l.entry = e;
        l.n = (std.fmt.bufPrintZ(&l.buf, fmt, args) catch return).len;
        if (self.n < MAX) {
            self.file[self.n] = l;
            self.n += 1;
            return;
        }
        var last: usize = 0;
        for (self.file[1..], 1..) |*o, i| {
            if (Listed.before({}, self.file[last], o.*)) last = i;
        }
        if (Listed.before({}, l, self.file[last])) self.file[last] = l;
    }

    fn sort(self: *Listing) void {
        std.sort.insertion(Listed, self.file[0..self.n], {}, Listed.before);
    }
};

/// Where a body arriving at `p` stands: `p`, or the open cell no one holds, nor `foes` are to, fewest steps from it.
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

/// From a cell no one can stand on: the nearest open one, through rock.
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

test "a world saves and loads back the same" {
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
    var y: i32 = 3;
    while (y < 9) : (y += 1) {
        var x: i32 = 3;
        while (x < 12) : (x += 1) b.tile[grid.Level.idx(.{ .x = x, .y = y })] = .floor;
    }
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
    std.debug.print("a two-node world is {d} bytes of text\n", .{buf.items.len});
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

test "a world file with a one-way link, a door linked to itself, a stray word or a far box is refused" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    const head = HEADER ++ "\nstart 0 5 5\n";
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
        HEADER ++ "\nnode procgen rooms\n",
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

test "no door goes in a map corner, which no step reaches" {
    const a = try testAtlas();
    defer std.testing.allocator.destroy(a);
    const n = a.add(.{ .procgen = .{} }).?;
    for ([_]P{ .{ .x = 0, .y = 0 }, .{ .x = grid.W - 1, .y = 0 }, .{ .x = 0, .y = grid.H - 1 }, .{ .x = grid.W - 1, .y = grid.H - 1 } }) |p| {
        try std.testing.expectEqual(@as(?usize, null), a.addDoor(n, p));
    }
    try std.testing.expect(a.addDoor(n, .{ .x = 1, .y = 0 }) != null);
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

test "a world file is named from anything typed, and nothing left of it is no name" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings(DIR ++ "/the_deepcave2" ++ EXT, pathFor(&buf, "", " The Deep/Cave2! ").?);
    try std.testing.expectEqual(@as(?[]const u8, null), pathFor(&buf, "", "../"));
    try std.testing.expectEqualStrings("qud/", folderOf(DIR ++ "/qud/qud_strata" ++ EXT));
    try std.testing.expectEqualStrings("", folderOf(MAIN));
    try std.testing.expectEqualStrings(DIR ++ "/qud/bog" ++ EXT, pathFor(&buf, folderOf(DIR ++ "/qud/qud_strata" ++ EXT), "Bog").?);
}

test "the worlds folder lists its folders before its worlds, and a folder opens with the way back up first" {
    var list = Listing{};
    list.scan();
    try std.testing.expect(list.n > 0 and list.entry(0) == .folder);
    const qud = for (0..list.n) |i| {
        if (std.mem.eql(u8, list.label(i), "qud/")) break i;
    } else return error.NoFolder;
    const top = list.n;
    try std.testing.expect(list.open(qud));
    try std.testing.expectEqualStrings("qud/", list.here());
    try std.testing.expectEqual(Listing.Entry.up, list.entry(0));
    try std.testing.expectEqual(Listing.Entry.world, list.entry(1));
    try std.testing.expect(std.mem.startsWith(u8, list.at(1), DIR ++ "/qud/qud_"));
    try std.testing.expect(std.mem.startsWith(u8, list.label(1), "qud_"));
    try std.testing.expect(!list.open(1));
    const inside = list.n;
    try std.testing.expect(list.open(0));
    try std.testing.expectEqual(@as(usize, 0), list.here().len);
    try std.testing.expect(!list.up());
    var all = Listing{};
    all.scanAll();
    std.debug.print("{d} rows in {s}, {d} in qud/ with the way up, {d} worlds in all\n", .{ top, DIR, inside, all.n });
    try std.testing.expect(all.n > top);
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
    const RUNS = 50;
    for (0..RUNS) |i| {
        nd.stamp(&lv, 0x57A2D +% i *% 7919);
        const at = landing(&lv, a.start.at, &.{}) orelse return error.NoFloor;
        if (lv.at(at) == .dirt or lv.at(at) == .shallows) on_shore += 1;
        try std.testing.expect(std.mem.indexOfScalar(grid.Tile, &lv.tile, .sand) == null);
        try std.testing.expectEqual(lv.openCount(), grid.distances(&lv, at, &dist, &queue));
        const walked = dist[grid.Level.idx(exit)];
        try std.testing.expect(walked > 0);
        wound += @as(f32, @floatFromInt(walked)) / @as(f32, @floatFromInt(mathx.dist(at, exit)));
    }
    std.debug.print("the strand over {d} rolls: {d} land on the dirt shore, no sand; the exit walks {d:.2} times the straight line\n", .{ RUNS, on_shore, wound / RUNS });
    try std.testing.expect(on_shore * 10 >= RUNS * 9);
    try std.testing.expect(wound / RUNS > 1.1);
}

test "every world in the worlds folder parses, and each procgen node rolls its ground whole" {
    var list = Listing{};
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
    std.debug.print("{d} worlds parsed, {d} procgen nodes rolled whole\n", .{ list.n, rolled });
}
