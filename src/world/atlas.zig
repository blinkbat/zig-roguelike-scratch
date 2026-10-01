const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const gen = @import("gen.zig");
const actor = @import("../play/actor.zig");

const P = mathx.P;

pub const MAX_NODES: usize = 32;
/// Every placed foe and the archer fit the pool; a slime that finds it full does not split.
pub const MAX_FOES: usize = actor.MAX - 1;
pub const DIR = "worlds";
pub const EXT = ".world";
pub const MAIN = worldPath("main");

/// `DIR/<stem>.world`.
pub fn worldPath(comptime stem: []const u8) []const u8 {
    return DIR ++ "/" ++ stem ++ EXT;
}
const TMP_EXT = ".tmp";
const HEADER = "roguelike-world 1";
const TEXT_CAP: usize = 8 << 20;
const COLS: usize = @intCast(grid.W);
const ROWS: usize = @intCast(grid.H);
pub const NAME_MAX: usize = 20;
/// Where a new node's box sits on the editor's graph, by its index.
const GRAPH_COLS: usize = 4;
pub const GRAPH_STEP = P{ .x = 240, .y = 200 };
/// A box's place on the graph, either way on either axis; far enough that i32 sums of places never overflow.
pub const POS_MAX: u32 = 1 << 24;
const MAX_LISTED: usize = 64;
/// A world file's name, `.world` and all.
const FILE_MAX: usize = 64;
const ListedPath = [DIR.len + 1 + FILE_MAX]u8;

pub const Link = struct { node: usize, door: usize };

pub const Door = struct { at: P, to: ?Link = null };

pub const Foe = struct { kind: actor.Kind, at: P };

/// `gen.around` is the only one.
pub const Algo = enum { rooms };

/// Its floor is rolled round its doors each run, so a world plays differently every time.
pub const Procgen = struct { algo: Algo = .rooms };

pub const Bespoke = struct {
    tile: [grid.CELLS]grid.Tile = [_]grid.Tile{.wall} ** grid.CELLS,
    barrel: [grid.CELLS]bool = [_]bool{false} ** grid.CELLS,
    torch: [grid.MAX_TORCHES]P = undefined,
    torch_n: usize = 0,
    foe: [MAX_FOES]Foe = undefined,
    foe_n: usize = 0,

    pub fn torches(self: *const Bespoke) []const P {
        return self.torch[0..self.torch_n];
    }

    pub fn foes(self: *const Bespoke) []const Foe {
        return self.foe[0..self.foe_n];
    }

    pub fn torchAt(self: *const Bespoke, p: P) ?usize {
        for (self.torches(), 0..) |t, i| {
            if (t.eq(p)) return i;
        }
        return null;
    }

    pub fn foeAt(self: *const Bespoke, p: P) ?usize {
        for (self.foes(), 0..) |f, i| {
            if (f.at.eq(p)) return i;
        }
        return null;
    }

    pub fn addTorch(self: *Bespoke, p: P) bool {
        if (self.torch_n == grid.MAX_TORCHES or self.torchAt(p) != null) return false;
        self.torch[self.torch_n] = p;
        self.torch_n += 1;
        return true;
    }

    pub fn addFoe(self: *Bespoke, f: Foe) bool {
        if (self.foe_n == MAX_FOES or self.foeAt(f.at) != null) return false;
        self.foe[self.foe_n] = f;
        self.foe_n += 1;
        return true;
    }

    pub fn dropTorch(self: *Bespoke, i: usize) void {
        self.torch_n -= 1;
        self.torch[i] = self.torch[self.torch_n];
    }

    pub fn dropFoe(self: *Bespoke, i: usize) void {
        self.foe_n -= 1;
        self.foe[i] = self.foe[self.foe_n];
    }
};

pub const Plan = union(enum) { bespoke: Bespoke, procgen: Procgen };

pub const Node = struct {
    plan: Plan,
    door: [grid.MAX_DOORS]Door = undefined,
    door_n: usize = 0,
    label: [NAME_MAX]u8 = undefined,
    label_n: usize = 0,
    /// Its box's top-left on the editor's graph.
    pos: P = .{ .x = 0, .y = 0 },

    pub fn name(self: *const Node) []const u8 {
        return self.label[0..self.label_n];
    }

    /// Printable ascii, trimmed, `NAME_MAX` at most; an empty name is none.
    pub fn rename(self: *Node, s: []const u8) bool {
        const t = std.mem.trim(u8, s, " ");
        if (t.len > NAME_MAX) return false;
        for (t) |c| {
            if (!std.ascii.isPrint(c)) return false;
        }
        @memcpy(self.label[0..t.len], t);
        self.label_n = t.len;
        return true;
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

    pub fn doorAt(self: *const Node, p: P) ?usize {
        for (self.doors(), 0..) |d, i| {
            if (d.at.eq(p)) return i;
        }
        return null;
    }

    /// Floor, or a door, which opens its cell.
    pub fn opens(self: *const Node, b: *const Bespoke, p: P) bool {
        if (!grid.Level.inside(p)) return false;
        const i = grid.Level.idx(p);
        return b.tile[i] == .floor or self.doorAt(p) != null;
    }

    /// On a wall with open ground below it, so its flame lights the ground.
    pub fn torchFits(self: *const Node, b: *const Bespoke, p: P) bool {
        return grid.Level.inside(p) and !self.opens(b, p) and self.opens(b, p.add(mathx.Dir.s.delta()));
    }

    /// On floor, and not in a doorway.
    pub fn barrelFits(self: *const Node, b: *const Bespoke, p: P) bool {
        if (!grid.Level.inside(p)) return false;
        const i = grid.Level.idx(p);
        return b.tile[i] == .floor and self.doorAt(p) == null;
    }

    /// Procgen, the floor is rolled from `roll` round the doors; bespoke, each door opens the cell it hangs in.
    pub fn stamp(self: *const Node, lv: *grid.Level, roll: u64) void {
        var cells: [grid.MAX_DOORS]P = undefined;
        for (self.doors(), 0..) |d, i| cells[i] = d.at;
        switch (self.plan) {
            .procgen => |pg| switch (pg.algo) {
                .rooms => {
                    _ = gen.around(lv, roll, cells[0..self.door_n]);
                },
            },
            .bespoke => |*b| {
                lv.* = grid.Level.blank();
                lv.tile = b.tile;
                for (cells[0..self.door_n], 0..) |p, i| lv.putDoor(p, i);
                gen.shapeWalls(lv);
                for (b.torches()) |t| {
                    if (self.torchFits(b, t)) lv.addTorch(t);
                }
                for (0..grid.CELLS) |i| {
                    if (b.barrel[i] and self.barrelFits(b, grid.Level.of(i))) lv.barrel[i] = true;
                }
            },
        }
    }

    /// What can be known of it before play: bespoke, as it plays; procgen, its doors alone, in rock.
    pub fn sketch(self: *const Node, lv: *grid.Level) void {
        switch (self.plan) {
            .bespoke => self.stamp(lv, 0),
            .procgen => {
                lv.* = grid.Level.blank();
                for (self.doors(), 0..) |d, i| lv.putDoor(d.at, i);
            },
        }
    }
};

pub const Start = struct { node: usize = 0, at: P = .{ .x = grid.W / 2, .y = grid.H / 2 } };

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

    /// The first graph slot no node's box lies over.
    fn freeSlot(self: *Atlas) P {
        const cols: i32 = @intCast(GRAPH_COLS);
        var i: i32 = 0;
        while (true) : (i += 1) {
            const p = P{ .x = @mod(i, cols) * GRAPH_STEP.x, .y = @divTrunc(i, cols) * GRAPH_STEP.y };
            const clear = for (self.nodes()) |nd| {
                if (@abs(nd.pos.x - p.x) < GRAPH_STEP.x and @abs(nd.pos.y - p.y) < GRAPH_STEP.y) break false;
            } else true;
            if (clear) return p;
        }
    }

    /// Every door that led into it is left unlinked, and the start moves to the first node if it was here.
    pub fn remove(self: *Atlas, n: usize) void {
        for (self.node[n].doors(), 0..) |_, k| self.unlink(.{ .node = n, .door = k });
        std.mem.copyForwards(Node, self.node[n .. self.node_n - 1], self.node[n + 1 .. self.node_n]);
        self.node_n -= 1;
        for (self.nodes()) |*nd| {
            for (nd.door[0..nd.door_n]) |*d| {
                if (d.to) |*l| {
                    if (l.node > n) l.node -= 1;
                }
            }
        }
        if (self.start.node == n) self.start = .{} else if (self.start.node > n) self.start.node -= 1;
    }

    pub fn addDoor(self: *Atlas, n: usize, p: P) ?usize {
        const nd = &self.node[n];
        if (nd.door_n == grid.MAX_DOORS or nd.doorAt(p) != null or !grid.Level.inside(p)) return null;
        nd.door[nd.door_n] = .{ .at = p };
        nd.door_n += 1;
        return nd.door_n - 1;
    }

    pub fn removeDoor(self: *Atlas, at: Link) void {
        self.unlink(at);
        const nd = &self.node[at.node];
        std.mem.copyForwards(Door, nd.door[at.door .. nd.door_n - 1], nd.door[at.door + 1 .. nd.door_n]);
        nd.door_n -= 1;
        for (self.nodes()) |*other| {
            for (other.door[0..other.door_n]) |*d| {
                if (d.to) |*l| {
                    if (l.node == at.node and l.door > at.door) l.door -= 1;
                }
            }
        }
    }

    fn doorOf(self: *Atlas, at: Link) *Door {
        return &self.node[at.node].door[at.door];
    }

    /// Both ways: a door leads to the one it came through. Whatever either led to is unlinked first.
    pub fn link(self: *Atlas, a: Link, b: Link) void {
        self.unlink(a);
        self.unlink(b);
        if (a.node == b.node and a.door == b.door) return;
        self.doorOf(a).to = b;
        self.doorOf(b).to = a;
    }

    pub fn unlink(self: *Atlas, a: Link) void {
        const to = self.doorOf(a).to orelse return;
        self.doorOf(a).to = null;
        self.doorOf(to).to = null;
    }

    pub fn save(self: *Atlas, path: []const u8) !void {
        if (std.fs.path.dirname(path)) |d| try std.fs.cwd().makePath(d);
        var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
        const tmp = try std.fmt.bufPrint(&tmp_buf, "{s}" ++ TMP_EXT, .{path});
        {
            var f = try std.fs.cwd().createFile(tmp, .{});
            defer f.close();
            var bw = std.io.bufferedWriter(f.writer());
            try self.write(bw.writer());
            try bw.flush();
            try f.sync();
        }
        // Written beside itself and renamed over it, so a write that fails part-way leaves the old world standing.
        try std.fs.cwd().rename(tmp, path);
    }

    pub fn write(self: *Atlas, w: anytype) !void {
        try w.print(HEADER ++ "\nstart {d} {d} {d}\n", .{ self.start.node, self.start.at.x, self.start.at.y });
        for (self.nodes()) |*nd| {
            switch (nd.plan) {
                .procgen => |pg| try w.print("node procgen {s}\n", .{@tagName(pg.algo)}),
                .bespoke => |*b| {
                    try w.writeAll("node bespoke\n");
                    for (0..ROWS) |y| {
                        try w.writeAll("row ");
                        for (0..COLS) |x| {
                            const i = y * COLS + x;
                            try w.writeByte(if (b.barrel[i]) BARREL_CH else tileCh(b.tile[i]));
                        }
                        try w.writeByte('\n');
                    }
                    for (b.torches()) |t| try w.print("torch {d} {d}\n", .{ t.x, t.y });
                    for (b.foes()) |f| try w.print("foe {s} {d} {d}\n", .{ @tagName(f.kind), f.at.x, f.at.y });
                },
            }
            if (nd.label_n > 0) try w.print("name {s}\n", .{nd.name()});
            try w.print("at {d} {d}\n", .{ nd.pos.x, nd.pos.y });
            for (nd.doors()) |d| {
                try w.print("door {d} {d}", .{ d.at.x, d.at.y });
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
        while (lines.next()) |raw| {
            const line = std.mem.trimRight(u8, raw, "\r");
            var f = std.mem.tokenizeScalar(u8, line, ' ');
            const word = f.next() orelse continue;
            if (std.mem.eql(u8, word, "start")) {
                self.start = .{ .node = try int(usize, &f), .at = try cell(&f) };
            } else if (std.mem.eql(u8, word, "node")) {
                const kind = std.meta.stringToEnum(std.meta.Tag(Plan), f.next() orelse return error.BadLine) orelse return error.BadLine;
                const plan: Plan = switch (kind) {
                    .procgen => blk: {
                        const algo = std.meta.stringToEnum(Algo, f.next() orelse return error.BadLine) orelse return error.BadLine;
                        // Written before procgen nodes were rolled each run: the seed they kept is let go.
                        if (f.peek() != null) _ = try int(u64, &f);
                        break :blk .{ .procgen = .{ .algo = algo } };
                    },
                    .bespoke => .{ .bespoke = .{} },
                };
                try self.painted(row);
                _ = self.add(plan) orelse return error.TooMany;
                row = 0;
            } else if (std.mem.eql(u8, word, "name")) {
                if (!(try self.last()).rename(f.rest())) return error.BadLine;
                continue;
            } else if (std.mem.eql(u8, word, "at")) {
                const pos = P{ .x = try int(i32, &f), .y = try int(i32, &f) };
                if (@abs(pos.x) > POS_MAX or @abs(pos.y) > POS_MAX) return error.BadLine;
                (try self.last()).pos = pos;
            } else if (std.mem.eql(u8, word, "door")) {
                const nd = try self.last();
                const at = try cell(&f);
                const k = self.addDoor(self.node_n - 1, at) orelse return error.TooMany;
                if (f.peek() != null) nd.door[k].to = .{ .node = try int(usize, &f), .door = try int(usize, &f) };
            } else {
                const b = try self.bespoke();
                if (std.mem.eql(u8, word, "row")) {
                    const cells = f.next() orelse return error.BadLine;
                    if (cells.len != COLS or row == ROWS) return error.BadLine;
                    for (cells, 0..) |c, x| {
                        const i = row * COLS + x;
                        b.barrel[i] = c == BARREL_CH;
                        b.tile[i] = if (c == BARREL_CH) .floor else chTile(c) orelse return error.BadLine;
                    }
                    row += 1;
                } else if (std.mem.eql(u8, word, "torch")) {
                    if (!b.addTorch(try cell(&f))) return error.TooMany;
                } else if (std.mem.eql(u8, word, "foe")) {
                    const k = std.meta.stringToEnum(actor.Kind, f.next() orelse return error.BadLine) orelse return error.BadLine;
                    if (!k.foe() or !b.addFoe(.{ .kind = k, .at = try cell(&f) })) return error.BadLine;
                } else return error.BadLine;
            }
            if (f.next() != null) return error.BadLine;
        }
        try self.painted(row);
        if (self.node_n == 0) return error.NoNodes;
        for (self.nodes(), 0..) |*nd, n| {
            for (nd.doors(), 0..) |d, k| {
                const l = d.to orelse continue;
                if (l.node >= self.node_n or l.door >= self.node[l.node].door_n) return error.BadLink;
                if (l.node == n and l.door == k) return error.BadLink;
                const back = self.node[l.node].door[l.door].to orelse return error.BadLink;
                if (back.node != n or back.door != k) return error.BadLink;
            }
        }
        if (self.start.node >= self.node_n) return error.BadLink;
    }

    /// A bespoke node is written whole: every row of it.
    fn painted(self: *Atlas, rows: usize) Error!void {
        if (self.node_n > 0 and self.node[self.node_n - 1].plan == .bespoke and rows != ROWS) return error.BadLine;
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

pub const Error = error{ NoHeader, BadLine, TooMany, NoNodes, BadLink };

const BARREL_CH = '0';

fn tileCh(t: grid.Tile) u8 {
    return switch (t) {
        .wall => '#',
        .floor => '.',
    };
}

fn chTile(c: u8) ?grid.Tile {
    for (std.enums.values(grid.Tile)) |t| {
        if (tileCh(t) == c) return t;
    }
    return null;
}

fn int(comptime T: type, f: *std.mem.TokenIterator(u8, .scalar)) Error!T {
    return std.fmt.parseInt(T, f.next() orelse return error.BadLine, 10) catch error.BadLine;
}

fn cell(f: *std.mem.TokenIterator(u8, .scalar)) Error!P {
    const p = P{ .x = try int(i32, f), .y = try int(i32, f) };
    return if (grid.Level.inside(p)) p else error.BadLine;
}

/// `DIR/<name>.world`, the name lowered to letters, digits and underscores; null when nothing is left of it.
pub fn pathFor(buf: []u8, name: []const u8) ?[]const u8 {
    var stem: [FILE_MAX - EXT.len]u8 = undefined;
    var n: usize = 0;
    for (std.mem.trim(u8, name, " ")) |c| {
        if (n == stem.len) break;
        const k = std.ascii.toLower(c);
        if (!std.ascii.isAlphanumeric(k) and k != '_' and k != ' ') continue;
        stem[n] = if (k == ' ') '_' else k;
        n += 1;
    }
    if (n == 0) return null;
    return std.fmt.bufPrint(buf, DIR ++ "/{s}" ++ EXT, .{stem[0..n]}) catch null;
}

/// The world files in `DIR`, sorted.
pub const Listing = struct {
    path: [MAX_LISTED]ListedPath = undefined,
    len: [MAX_LISTED]usize = undefined,
    n: usize = 0,

    pub fn at(self: *const Listing, i: usize) []const u8 {
        return self.path[i][0..self.len[i]];
    }

    pub fn scan(self: *Listing) void {
        self.n = 0;
        var dir = std.fs.cwd().openDir(DIR, .{ .iterate = true }) catch return;
        defer dir.close();
        var it = dir.iterate();
        while (it.next() catch null) |e| {
            if (self.n == MAX_LISTED) break;
            if (e.kind != .file or !std.mem.endsWith(u8, e.name, EXT) or e.name.len > FILE_MAX) continue;
            const s = std.fmt.bufPrint(&self.path[self.n], DIR ++ "/{s}", .{e.name}) catch continue;
            self.len[self.n] = s.len;
            self.n += 1;
        }
        var i: usize = 1;
        while (i < self.n) : (i += 1) {
            var j = i;
            while (j > 0 and std.mem.lessThan(u8, self.at(j), self.at(j - 1))) : (j -= 1) {
                std.mem.swap(ListedPath, &self.path[j], &self.path[j - 1]);
                std.mem.swap(usize, &self.len[j], &self.len[j - 1]);
            }
        }
    }
};

/// Where a body arriving at `p` stands: `p`, or the open cell no one holds, nor `foes` are to, fewest steps from it.
pub fn landing(lv: *const grid.Level, p: P, foes: []const Foe) ?P {
    if (!lv.walkable(p)) return nearest(lv, p, foes);
    var seen = std.StaticBitSet(grid.CELLS).initEmpty();
    var queue: [grid.CELLS]u32 = undefined;
    var head: usize = 0;
    var tail: usize = 1;
    queue[0] = @intCast(grid.Level.idx(p));
    seen.set(queue[0]);
    while (head < tail) : (head += 1) {
        const q = grid.Level.of(queue[head]);
        if (free(lv, q, foes)) return q;
        for (mathx.ALL_DIRS) |d| {
            if (!lv.passOk(q, d)) continue;
            const k = grid.Level.idx(q.add(d.delta()));
            if (seen.isSet(k)) continue;
            seen.set(k);
            queue[tail] = @intCast(k);
            tail += 1;
        }
    }
    return nearest(lv, p, foes);
}

fn free(lv: *const grid.Level, q: P, foes: []const Foe) bool {
    if (!lv.walkable(q) or lv.taken(q)) return false;
    for (foes) |f| {
        if (f.at.eq(q)) return false;
    }
    return true;
}

/// From a cell no one can stand on: the nearest open one, through rock.
fn nearest(lv: *const grid.Level, p: P, foes: []const Foe) ?P {
    var ring: i32 = 0;
    while (ring < @max(grid.W, grid.H)) : (ring += 1) {
        var best: ?P = null;
        var y = p.y - ring;
        while (y <= p.y + ring) : (y += 1) {
            var x = p.x - ring;
            while (x <= p.x + ring) : (x += 1) {
                const q = P{ .x = x, .y = y };
                if (mathx.dist(q, p) != ring or !free(lv, q, foes)) continue;
                if (best == null) best = q;
            }
        }
        if (best) |q| return q;
    }
    return null;
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
    const b = &a.node[room].plan.bespoke;
    var y: i32 = 3;
    while (y < 9) : (y += 1) {
        var x: i32 = 3;
        while (x < 12) : (x += 1) b.tile[grid.Level.idx(.{ .x = x, .y = y })] = .floor;
    }
    b.barrel[grid.Level.idx(.{ .x = 4, .y = 4 })] = true;
    _ = b.addTorch(.{ .x = 6, .y = 2 });
    _ = b.addFoe(.{ .kind = .slime, .at = .{ .x = 9, .y = 6 } });
    const d0 = a.addDoor(room, .{ .x = 11, .y = 5 }).?;
    const d1 = a.addDoor(cave, .{ .x = 0, .y = 30 }).?;
    a.link(.{ .node = room, .door = d0 }, .{ .node = cave, .door = d1 });
    a.start = .{ .node = room, .at = .{ .x = 5, .y = 5 } };
    try std.testing.expect(a.node[cave].rename("  The Deep Cave "));
    try std.testing.expect(!a.node[room].rename("a name far too long to keep"));
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
    try std.testing.expect(back.node[cave].plan == .procgen);
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
    };
    for (bad) |t| try std.testing.expect(std.meta.isError(a.parse(t)));
    try a.parse(head ++ "node procgen rooms 1790812916605\n");
    try a.parse(head ++ "node procgen rooms\n  name  Deep  Cave\n");
    try std.testing.expectEqualStrings("Deep  Cave", a.node[0].name());
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
    _ = b.addTorch(.{ .x = 5, .y = 4 });
    _ = b.addTorch(.{ .x = 20, .y = 20 });
    _ = a.addDoor(n, .{ .x = 5, .y = 6 });
    var lv: grid.Level = undefined;
    a.node[n].stamp(&lv, 0);
    try std.testing.expect(lv.walkable(.{ .x = 5, .y = 6 }));
    try std.testing.expectEqual(@as(?usize, 0), lv.doorAt(.{ .x = 5, .y = 6 }));
    try std.testing.expectEqual(@as(usize, 1), lv.torch_n);
    try std.testing.expectEqual(grid.WallShape.top, lv.wallShape(.{ .x = 5, .y = 4 }).?);
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
    try std.testing.expectEqualStrings(DIR ++ "/the_deepcave2" ++ EXT, pathFor(&buf, " The Deep/Cave2! ").?);
    try std.testing.expectEqual(@as(?[]const u8, null), pathFor(&buf, "../"));
}
