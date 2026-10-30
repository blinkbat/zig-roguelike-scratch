const std = @import("std");
const items = @import("play/items.zig");
const store = @import("core/store.zig");
const game = @import("game.zig");
const atlas = @import("map/atlas.zig");
const grid = @import("map/grid.zig");
const actor = @import("play/actor.zig");
const hero = @import("play/hero.zig");
const progress = @import("play/progress.zig");
const menu = @import("ui/menu.zig");

pub const SLOTS: usize = 3;
pub const NOT_WRITTEN = "The last save did not write ({s})";
pub const NOT_DELETED = "The dead run's save did not delete ({s})";
const DIR = store.DIR;
const EXT = ".save";
const MAGIC = "roguelike-save\n";
const FILE_CAP: usize = format.FILE_CAP;
const PATH_FMT = DIR ++ "/slot{d}" ++ EXT;
const PATH_MAX: usize = std.fmt.count(PATH_FMT, .{SLOTS});
const GAP_S: f32 = 1;

const data = @import("save_data.zig");
const format = @import("save_format.zig");

const part = data.part;
const Header = data.LegacyHeader;
const Seed = data.Seed;
const Map = data.Map;
const RawMap = data.LegacyMap;
const Node = data.Node;
const Visited = data.Visited;
const RawVisit = data.LegacyVisit;
const RawLevel = data.LegacyLevel;
const TAIL_FIELDS = data.TAIL_FIELDS;
const Tail = data.LegacyTail;
const TAIL = data.TAIL;
pub const Summary = data.Summary;

pub const Unreadable = enum {
    other_build,
    damaged,

    pub fn caption(u: Unreadable) []const u8 {
        return switch (u) {
            .other_build => "From another build of the game",
            .damaged => "Damaged",
        };
    }
};

pub const Slot = union(enum) { empty, unreadable: Unreadable, run: Summary };

/// The file's types in order: the summary, the header with the map's flag before it, then the tail.
const FINGERPRINT = blk: {
    const head = std.meta.fields(Header);
    var types: [head.len + 3]type = undefined;
    types[0] = Summary;
    var i: usize = 1;
    for (head) |f| {
        if (std.mem.eql(u8, f.name, "map")) {
            types[i] = bool;
            i += 1;
        }
        types[i] = f.type;
        i += 1;
    }
    types[i] = Tail;
    std.debug.assert(i + 1 == types.len);
    break :blk store.legacy.fingerprint(types) ^ TREE;
};
/// What the tree's hash takes for a node's missing branch, seam or rider.
const NO_PART: u8 = 255;
/// The passive tree's layout, which saved allocations index by node.
const TREE = blk: {
    @setEvalBranchQuota(100_000);
    var h = std.hash.Wyhash.init(0);
    for (progress.NODES, 0..) |n, i| {
        h.update(n.name);
        h.update(&.{ @intFromEnum(n.arm), if (n.branch) |v| @intFromEnum(v) else NO_PART, if (n.seam) |v| @intFromEnum(v) else NO_PART, n.ring, n.slot, @intFromEnum(n.tier), @intFromEnum(n.grant.kind) });
        h.update(&std.mem.toBytes(n.grant.amount));
        h.update(&.{if (n.bump) |g| @intFromEnum(g.kind) else NO_PART});
        if (n.bump) |g| h.update(&std.mem.toBytes(g.amount));
        var buf: [progress.passives.MAX_FEED]usize = undefined;
        const fs = progress.passives.feeders(i, &buf);
        h.update(&std.mem.toBytes(fs.len));
        for (fs) |f| h.update(&std.mem.toBytes(f));
    }
    for (hero.CLASSES) |c| h.update(&std.mem.toBytes(progress.start(c)));
    break :blk h.final();
};

comptime {
    for (.{
        .{ progress.passives.Node, .{ "arm", "branch", "seam", "ring", "slot", "name", "tier", "grant", "bump" } },
        .{ progress.passives.Grant, .{ "kind", "amount" } },
    }) |pair| {
        const fields = std.meta.fields(pair[0]);
        if (fields.len != pair[1].len) @compileError("save.TREE hashes a different field list than " ++ @typeName(pair[0]));
        for (fields) |f| {
            for (pair[1]) |name| {
                if (std.mem.eql(u8, f.name, name)) break;
            } else @compileError("save.TREE does not hash " ++ @typeName(pair[0]) ++ "." ++ f.name);
        }
    }
}
const Print = @TypeOf(FINGERPRINT);
const HEAD = store.head(MAGIC);
const Raw = struct { map: RawMap, visit: RawVisit, lv: RawLevel };

pub const Error = error{ NotASave, OtherBuild, Short, Damaged };

/// Into an empty `out`, all but the sum `seal` ends it with.
fn writeLegacy(g: *game.Game, out: *std.ArrayList(u8)) !void {
    std.debug.assert(out.items.len == 0);
    const w = out.writer();
    try store.begin(w, MAGIC, FINGERPRINT);
    try store.legacy.put(w, &(Summary.of(g) orelse return error.Damaged));
    try store.legacy.put(w, &g.sim.seed);
    const has_map = g.sim.map != null;
    try store.legacy.put(w, &has_map);
    const raw = try std.heap.page_allocator.create(Raw);
    defer std.heap.page_allocator.destroy(raw);
    if (g.sim.map) |a| {
        data.convert(&raw.map, a);
        try store.legacy.put(w, &raw.map);
    }
    try store.legacy.put(w, &g.sim.node);
    try store.legacy.put(w, &g.sim.visited);
    var it = g.sim.visited.iterator(.{});
    while (it.next()) |n| {
        data.convert(&raw.visit, &g.sim.visits[n]);
        try store.legacy.put(w, &raw.visit);
    }
    inline for (TAIL_FIELDS) |f| {
        const value = &@field(part(g, f[0]), f[1]);
        if (comptime @TypeOf(value.*) == @FieldType(Tail, f[1])) {
            try store.legacy.put(w, value);
        } else {
            data.convert(&raw.lv, value);
            try store.legacy.put(w, &raw.lv);
        }
    }
    try out.ensureUnusedCapacity(store.SUM);
}

/// Ends a file `write` began in `out` with its sum, in the room `write` kept, so it may run off the frame.
fn seal(out: *std.ArrayList(u8)) void {
    store.sealReserved(out, if (std.mem.startsWith(u8, out.items, format.MAGIC)) store.head(format.MAGIC) else HEAD);
}

fn payload(bytes: []const u8) Error![]const u8 {
    return store.open(bytes, MAGIC, FINGERPRINT) catch |e| switch (e) {
        error.Foreign => error.NotASave,
        else => |other| other,
    };
}

fn peekLegacy(bytes: []const u8) !Summary {
    const snapshot = try parseLegacy(bytes);
    defer std.heap.page_allocator.destroy(snapshot);
    return snapshot.summary;
}

const Contents = struct { summary: Summary, seed: Seed, has_map: bool, body: []const u8 };

fn inspect(bytes: []const u8) Error!Contents {
    var b = try payload(bytes);
    var s: Summary = undefined;
    if (!store.legacy.take(&b, &s)) return error.Short;
    if (!store.legacy.valid(format.Policy, &s)) return error.Damaged;
    if (!s.name.valid() or !s.place.valid()) return error.Damaged;
    if (s.node) |n| {
        if (n >= atlas.MAX_NODES) return error.Damaged;
    }
    var seed: Seed = undefined;
    var map_flag: u8 = undefined;
    comptime std.debug.assert(@sizeOf(bool) == @sizeOf(u8));
    if (!store.legacy.take(&b, &seed) or !store.legacy.take(&b, &map_flag)) return error.Short;
    if (map_flag > 1) return error.Damaged;
    const has_map = map_flag != 0;
    const at_node: usize = if (has_map) @sizeOf(RawMap) else 0;
    const at_visited = at_node + @sizeOf(Node);
    if (b.len < at_visited + @sizeOf(Visited)) return error.Short;
    var node: Node = undefined;
    var visited: Visited = undefined;
    var navigation = b[at_node..];
    _ = store.legacy.take(&navigation, &node);
    _ = store.legacy.take(&navigation, &visited);
    if (b.len != at_visited + @sizeOf(Visited) + visited.count() * @sizeOf(RawVisit) + TAIL) return error.Short;
    if (has_map) {
        var node_count: @FieldType(RawMap, "node_n") = undefined;
        var count_bytes = b[@offsetOf(RawMap, "node_n")..];
        _ = store.legacy.take(&count_bytes, &node_count);
        if (node_count == 0 or node_count > atlas.MAX_NODES or node >= node_count) return error.Damaged;
        var it = visited.iterator(.{});
        while (it.next()) |n| if (n >= node_count) return error.Damaged;
        if (s.node != node) return error.Damaged;
    } else if (node != 0 or visited.count() != 0 or s.node != null) return error.Damaged;
    return .{ .summary = s, .seed = seed, .has_map = has_map, .body = b };
}

/// All of it is measured before any of it reaches `g`, so a file that does not read leaves the game as it was.
fn parseLegacy(bytes: []const u8) !*format.Snapshot {
    const c = try inspect(bytes);
    const snapshot = try std.heap.page_allocator.create(format.Snapshot);
    errdefer std.heap.page_allocator.destroy(snapshot);
    snapshot.summary = c.summary;
    snapshot.seed = c.seed;
    snapshot.map = null;
    snapshot.visits = @splat(null);
    snapshot.portable = .{};
    const raw = try std.heap.page_allocator.create(Raw);
    defer std.heap.page_allocator.destroy(raw);
    var b = c.body;
    if (c.has_map) {
        _ = store.legacy.take(&b, &raw.map);
        if (!store.legacy.valid(format.Policy, &raw.map)) return error.Damaged;
        snapshot.map = @as(Map, undefined);
        data.convert(&snapshot.map.?, &raw.map);
    }
    _ = store.legacy.take(&b, &snapshot.node);
    var visited: Visited = undefined;
    _ = store.legacy.take(&b, &visited);
    var it = visited.iterator(.{});
    while (it.next()) |n| {
        _ = store.legacy.take(&b, &raw.visit);
        if (!store.legacy.valid(format.Policy, &raw.visit)) return error.Damaged;
        snapshot.visits[n] = @as(data.Visit, undefined);
        data.convert(&snapshot.visits[n].?, &raw.visit);
    }
    inline for (TAIL_FIELDS) |field| {
        const into = &@field(snapshot.run, field[1]);
        if (comptime @TypeOf(into.*) == @FieldType(Tail, field[1])) {
            _ = store.legacy.take(&b, into);
        } else {
            _ = store.legacy.take(&b, &raw.lv);
            if (!store.legacy.valid(format.Policy, &raw.lv)) return error.Damaged;
            data.convert(into, &raw.lv);
        }
    }
    if (!store.legacy.valid(format.Policy, snapshot)) return error.Damaged;
    try format.validate(snapshot);
    return snapshot;
}

fn readLegacy(bytes: []const u8, g: *game.Game, map: *Map) !void {
    const snapshot = try parseLegacy(bytes);
    defer std.heap.page_allocator.destroy(snapshot);
    format.apply(snapshot, g, map);
}

fn write(g: *game.Game, out: *std.ArrayList(u8)) !void {
    try format.write(g, out);
}

fn read(bytes: []const u8, g: *game.Game, map: *Map) !void {
    if (std.mem.startsWith(u8, bytes, format.MAGIC)) return format.read(bytes, g, map);
    try readLegacy(bytes, g, map);
    g.sim.unsaved = true;
}

fn peek(bytes: []const u8) !Summary {
    if (std.mem.startsWith(u8, bytes, format.MAGIC)) return format.peek(bytes);
    return peekLegacy(bytes);
}

pub fn number(slot: usize) usize {
    return slot + 1;
}

fn path(buf: []u8, slot: usize) []const u8 {
    return std.fmt.bufPrint(buf, PATH_FMT, .{number(slot)}) catch unreachable;
}

fn writeFile(bytes: []const u8, slot: usize) !void {
    var buf: [PATH_MAX]u8 = undefined;
    try store.replace(path(&buf, slot), bytes);
}

fn readSlot(alloc: std.mem.Allocator, slot: usize) ![]u8 {
    var buf: [PATH_MAX]u8 = undefined;
    return std.fs.cwd().readFileAlloc(alloc, path(&buf, slot), FILE_CAP);
}

pub fn load(alloc: std.mem.Allocator, slot: usize, g: *game.Game, map: *Map) !void {
    const bytes = try readSlot(alloc, slot);
    defer alloc.free(bytes);
    try read(bytes, g, map);
}

pub fn remove(slot: usize) !void {
    var buf: [PATH_MAX]u8 = undefined;
    std.fs.cwd().deleteFile(path(&buf, slot)) catch |e| if (e != error.FileNotFound) return e;
}

pub fn slots(alloc: std.mem.Allocator) [SLOTS]Slot {
    var out: [SLOTS]Slot = undefined;
    for (&out, 0..) |*s, i| s.* = slotAt(alloc, i);
    return out;
}

/// Read whole, so a slot listed as a run is one `load` will take.
fn slotAt(alloc: std.mem.Allocator, i: usize) Slot {
    const bytes = readSlot(alloc, i) catch |e| return if (e == error.FileNotFound) .empty else .{ .unreadable = .damaged };
    defer alloc.free(bytes);
    if (bytes.len == 0) return .empty;
    const s = peek(bytes) catch |e| return .{ .unreadable = if (e == error.OtherBuild) .other_build else .damaged };
    return .{ .run = s };
}

pub fn free(list: *const [SLOTS]Slot) ?usize {
    for (list, 0..) |s, i| {
        if (s == .empty) return i;
    }
    return null;
}

/// Must not move while a write is under way.
pub const Autosave = struct {
    slot: usize,
    bytes: std.ArrayList(u8),
    snapshot: ?*format.Snapshot = null,
    since: f32 = GAP_S,
    /// Copy the run on the frame, then write the snapshot off-thread.
    writer: ?std.Thread = null,
    finished: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),
    failed: ?anyerror = null,
    reported: ?anyerror = null,

    pub fn init(alloc: std.mem.Allocator, slot: usize) Autosave {
        return .{ .slot = slot, .bytes = std.ArrayList(u8).init(alloc) };
    }

    pub fn deinit(self: *Autosave) void {
        self.wait();
        if (self.snapshot) |snapshot| self.bytes.allocator.destroy(snapshot);
        self.bytes.deinit();
    }

    pub fn close(self: *Autosave, g: *game.Game) ?anyerror {
        self.flush(g);
        self.deinit();
        return self.failed;
    }

    /// Not mid-door, mid-turn or mid loot visit: a foe's turn to face the hero is only in `facing` once it is drawn, and a visit's turn is spent as it closes.
    pub fn step(self: *Autosave, g: *game.Game, dt: f32) void {
        self.since += dt;
        if (!self.finished.load(.acquire)) return;
        self.wait();
        if (self.failed != null) g.sim.unsaved = true;
        if (!g.sim.unsaved or self.since < GAP_S or g.sim.travel != null or g.looted or !g.pic.quiet()) return;
        self.flush(g);
    }

    pub fn flush(self: *Autosave, g: *game.Game) void {
        self.wait();
        if (self.failed) |e| {
            if (self.reported == null or self.reported.? != e) g.sim.log.say(NOT_WRITTEN ++ ".", .{@errorName(e)});
            self.reported = e;
            self.failed = null;
            g.sim.unsaved = true;
        } else self.reported = null;
        if (!g.sim.unsaved) return;
        self.bytes.clearRetainingCapacity();
        self.since = 0;
        g.sim.unsaved = false;
        if (self.snapshot == null) {
            self.snapshot = self.bytes.allocator.create(format.Snapshot) catch |e| {
                self.failed = e;
                return;
            };
        }
        format.capture(g, self.snapshot.?) catch |e| {
            self.failed = e;
            return;
        };
        self.finished.store(false, .release);
        self.writer = std.Thread.spawn(.{}, writeOff, .{self}) catch blk: {
            writeOff(self);
            break :blk null;
        };
    }

    fn writeOff(self: *Autosave) void {
        defer self.finished.store(true, .release);
        format.writeSnapshot(self.snapshot.?, &self.bytes) catch |e| {
            self.failed = e;
            return;
        };
        seal(&self.bytes);
        writeFile(self.bytes.items, self.slot) catch |e| {
            self.failed = e;
        };
    }

    pub fn wait(self: *Autosave) void {
        const t = self.writer orelse return;
        t.join();
        self.writer = null;
    }

    /// A slot that will not delete is emptied, so it holds no run that would load.
    pub fn end(self: *Autosave) ?anyerror {
        self.wait();
        remove(self.slot) catch |e| {
            writeFile("", self.slot) catch return e;
        };
        return null;
    }
};

test "an unfinished autosave defers the next snapshot without consuming dirty state" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.begin(g, 1);
    var a = Autosave.init(std.testing.failing_allocator, 0);
    defer a.deinit();
    a.finished.store(false, .release);
    a.since = GAP_S;
    a.step(g, GAP_S);
    try std.testing.expect(g.sim.unsaved);
    try std.testing.expectEqual(@as(?anyerror, null), a.failed);
    try std.testing.expectEqual(@as(usize, 0), a.bytes.items.len);
    try std.testing.expectEqual(GAP_S * 2, a.since);
    const deferred = a.since;

    a.finished.store(true, .release);
    a.step(g, 0);
    try std.testing.expectEqual(@as(?anyerror, error.OutOfMemory), a.failed);
    a.step(g, 0);
    try std.testing.expect(g.sim.unsaved);
    std.debug.print("autosave deferred {d:.1} s; completion resumes capture and failure rearms it\n", .{deferred});
}

test "autosave waits out an open loot visit, whose pickups are paid for as it closes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.begin(g, 1);
    var a = Autosave.init(std.testing.failing_allocator, 0);
    defer a.deinit();
    g.looted = true;
    a.step(g, GAP_S);
    try std.testing.expectEqual(@as(?anyerror, null), a.failed);
    try std.testing.expect(g.sim.unsaved);
    g.looted = false;
    a.step(g, 0);
    try std.testing.expectEqual(@as(?anyerror, error.OutOfMemory), a.failed);
}

test "a failed autosave marks an idle run dirty again without another turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.begin(g, 1);
    var a = Autosave.init(std.testing.allocator, 0);
    defer a.deinit();
    a.since = 0;
    a.failed = error.AccessDenied;
    g.sim.unsaved = false;
    a.step(g, 0);
    try std.testing.expect(g.sim.unsaved);
    try std.testing.expectEqual(@as(?anyerror, error.AccessDenied), a.failed);
    try std.testing.expectEqual(@as(usize, 0), a.bytes.items.len);
    std.debug.print("failed autosave rearmed with no turn taken; retry remains throttled\n", .{});
}

test "a save that keeps failing is said once, not once a retry" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.begin(g, 1);
    var a = Autosave.init(std.testing.failing_allocator, 0);
    defer a.deinit();
    const said = g.sim.log.n;
    const RETRIES = 6;
    for (0..RETRIES) |_| a.step(g, GAP_S);
    try std.testing.expectEqual(said + 1, g.sim.log.n);
    std.debug.print("a save failing {d} retries in a row: {d} log line\n", .{ RETRIES, g.sim.log.n - said });
}

fn testMap() !*Map {
    const m = try std.testing.allocator.create(Map);
    m.* = .{};
    const a = m.add(.{ .procgen = .{} }).?;
    const b = m.add(.{ .procgen = .{} }).?;
    const da = m.addDoor(a, .{ .x = 30, .y = 30 }).?;
    const db = m.addDoor(b, .{ .x = 40, .y = 20 }).?;
    m.link(.{ .node = a, .door = da }, .{ .node = b, .door = db });
    _ = m.node[b].rename("The Warrens");
    m.start = .{ .node = a, .at = .{ .x = 30, .y = 30 } };
    return m;
}

test "a run reads back as it was written, and a short or foreign file leaves the game alone" {
    const alloc = std.testing.allocator;
    const w = try testMap();
    defer alloc.destroy(w);
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    game.beginMap(g, w);
    g.sim.name = hero.Name.of("Arwen");
    try std.testing.expect(g.sim.inventory.add(.{ .kind = .ring, .mods = .{ .{ .kind = .intelligence, .value = 2 }, null, null, null } }));
    try g.sim.inventory.equip(0, .right_ring, g.sim.growth.attributes(g.sim.class));
    try std.testing.expect(g.sim.inventory.add(.{ .kind = .sword }));
    _ = g.sim.growth.gain(100);
    try std.testing.expect(g.sim.growth.learn(g.sim.class, .burning_arrow));
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .boots }, .at = g.sim.heroActor().?.at }));
    try std.testing.expect(g.sim.ground.gold(g.sim.heroActor().?.at, 12));
    g.sim.gold = 17;
    g.sim.mana = 7;
    g.sim.mana_recovery = 3;
    g.sim.flasks.getPtr(.life).drink(12);
    _ = g.sim.flasks.getPtr(.life).tick();
    g.sim.cooldown.set(.juke, 2);
    g.sim.heroActor().?.resists.set(.fire, 50);
    g.sim.heroActor().?.resists.set(.cold, 25);
    g.sim.heroActor().?.burn = .{ .turns = 2 };
    g.sim.heroActor().?.resilience.meters.set(.burn, .{ .percent = 50, .turns = 4 });
    g.sim.heroActor().?.bleed = .{ .turns = 3, .amount = 2 };
    g.sim.heroActor().?.chill = .{ .turns = 2, .phase = 1 };
    if (g.sim.pool.n > 1) g.sim.pool.items[1].chill = .{ .turns = 1, .phase = 2 };
    _ = g.sim.pool.damage(&g.sim.lv, g.sim.hero, 5);
    g.sim.travel = .{ .node = 1, .door = 0 };
    g.pic.busy = 0;
    game.update(g, 0);
    g.sim.log.say("A line to keep.", .{});
    g.sim.stepped = true;
    const forest = grid.Level.idx(.{ .x = 70, .y = 50 });
    for ([_]*grid.Level{ &g.sim.lv, &g.sim.visits[0].lv }) |lv| {
        var cells = (grid.Box{ .lo = .{ .x = 69, .y = 49 }, .hi = .{ .x = 73, .y = 52 } }).cells();
        while (cells.next()) |p| lv.set(p, .grass);
        lv.set(.{ .x = 72, .y = 49 }, .chest);
        lv.set(.{ .x = 72, .y = 51 }, .chest_open);
        for (forest..forest + 2) |i| {
            lv.tile[i] = .shrub;
            lv.shape[i] = null;
        }
    }

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    try write(g, &buf);
    seal(&buf);
    std.debug.print("a run of two nodes, one left behind: {d} KB saved\n", .{buf.items.len / 1024});

    const back = try game.boot(alloc);
    defer game.shut(alloc, back);
    const into = try alloc.create(Map);
    defer alloc.destroy(into);
    game.begin(back, 1);
    try std.testing.expectError(error.Damaged, read(buf.items[0 .. buf.items.len - 1], back, into));
    try std.testing.expectError(error.NotASave, read("not a save", back, into));
    buf.items[buf.items.len / 2] +%= 1;
    try std.testing.expectError(error.Damaged, read(buf.items, back, into));
    buf.items[buf.items.len / 2] -%= 1;
    try std.testing.expectEqual(@as(?*const Map, null), back.sim.map);
    try read(buf.items, back, into);
    try std.testing.expectEqualStrings("Arwen", back.sim.name.text());
    try std.testing.expectEqual(g.sim.growth, back.sim.growth);
    try std.testing.expectEqual(g.sim.inventory.gear, back.sim.inventory.gear);
    try std.testing.expectEqualSlices(@import("play/items.zig").Item, g.sim.inventory.bag[0..g.sim.inventory.n], back.sim.inventory.bag[0..back.sim.inventory.n]);
    try std.testing.expectEqual(@as(usize, 1), back.sim.visits[0].ground.n);
    try std.testing.expectEqual(@as(i32, 12), back.sim.visits[0].ground.coins[0].amount);
    try std.testing.expectEqual(g.sim.loot_rng, back.sim.loot_rng);
    try std.testing.expectEqual(@as(usize, 1), back.sim.node);
    try std.testing.expectEqual(g.sim.heroActor().?.at, back.sim.heroActor().?.at);
    try std.testing.expectEqual(g.sim.heroActor().?.hp, back.sim.heroActor().?.hp);
    try std.testing.expectEqual(@as(i32, 7), back.sim.mana);
    try std.testing.expectEqual(@as(i32, 3), back.sim.mana_recovery);
    try std.testing.expectEqualDeep(g.sim.flasks, back.sim.flasks);
    try std.testing.expectEqual(@as(u8, 2), back.sim.cooldown.get(.juke));
    try std.testing.expect(back.sim.stepped);
    try std.testing.expectEqual(@as(i16, 50), back.sim.heroActor().?.resists.get(.fire));
    try std.testing.expectEqual(@as(i16, 25), back.sim.heroActor().?.resists.get(.cold));
    try std.testing.expectEqual(@as(u8, 2), back.sim.heroActor().?.burn.turns);
    try std.testing.expectEqualDeep(g.sim.heroActor().?.resilience, back.sim.heroActor().?.resilience);
    try std.testing.expectEqualDeep(g.sim.heroActor().?.bleed, back.sim.heroActor().?.bleed);
    try std.testing.expectEqual(@as(u8, 2), back.sim.heroActor().?.chill.turns);
    try std.testing.expectEqual(@as(u8, 1), back.sim.heroActor().?.chill.phase);
    for (g.sim.visits[0].pool.slice(), back.sim.visits[0].pool.slice()) |before, after| try std.testing.expectEqual(before.chill, after.chill);
    try std.testing.expectEqual(g.sim.pool.n, back.sim.pool.n);
    try std.testing.expectEqualSlices(grid.Tile, &g.sim.lv.tile, &back.sim.lv.tile);
    try std.testing.expectEqualSlices(grid.Tile, &g.sim.visits[0].lv.tile, &back.sim.visits[0].lv.tile);
    var restored: usize = 0;
    for ([_]*const grid.Level{ &back.sim.lv, &back.sim.visits[0].lv }) |lv| {
        try std.testing.expectEqual(@as(u8, 2), lv.shape[forest].?.mask());
        try std.testing.expectEqual(@as(u8, 8), lv.shape[forest + 1].?.mask());
        restored += 2;
    }
    std.debug.print("save reload restored {d} absent forest shapes across the active and visited nodes\n", .{restored});
    std.debug.print("closed and opened chests preserved on both active and visited nodes\n", .{});
    try std.testing.expectEqualStrings("A line to keep.", back.sim.log.line(0).?);
    const s = try peek(buf.items);
    var line: [menu.NOTE_MAX]u8 = undefined;
    try std.testing.expectEqualStrings(comptime std.fmt.comptimePrint(hero.HP_FMT, .{ 19, actor.row(actor.HERO).hp }) ++ menu.SEP ++ "Gold 17" ++ menu.SEP ++ "The Warrens", s.details(&line));
}

/// The raw legacy schema accepted by this migration reader.
const RECORDED_FINGERPRINT: Print = 0xe27fed80f5e3dff6;

fn fixture(g: *game.Game, w: *const Map) !void {
    game.beginMapAt(g, w, w.start, 7);
    g.sim.name = hero.Name.of("Fixture");
    try std.testing.expect(g.sim.inventory.add(.{ .kind = .sword }));
    g.pic.facing[0] = .left;
    g.sim.travel = .{ .node = 1, .door = 0 };
    game.update(g, 0);
}

test "portable saves retain the recorded gameplay values and rewrite canonically" {
    const alloc = std.testing.allocator;
    const w = try testMap();
    defer alloc.destroy(w);
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    try fixture(g, w);
    g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, null, null, null } });
    g.sim.inventory.gear.slots.set(.left_ring, .{ .kind = .ring, .rare_name = .{ .first = .Void, .last = .Maw }, .mods = .{ .{ .kind = .spoils, .value = 25 }, .{ .kind = .strength, .value = 1 }, .{ .kind = .resistance, .value = 10, .element = .cold }, .{ .kind = .life, .value = 2 } } });
    const rare = items.Item{ .kind = .robes, .rare_name = .{ .first = .Magus, .last = .Fold }, .mods = .{ .{ .kind = .intelligence, .value = 3 }, .{ .kind = .armour, .value = 4 }, .{ .kind = .mana, .value = 3 }, .{ .kind = .life, .value = 6 } } };
    try std.testing.expect(g.sim.inventory.add(rare));
    try std.testing.expect(g.sim.ground.add(.{ .item = rare, .at = g.sim.heroActor().?.at }));
    try std.testing.expect(g.sim.ground.addSupply(.{ .kind = .smelling_salts, .at = g.sim.heroActor().?.at }));
    g.sim.inventory.stacks.set(.frost_vial, 3);
    g.sim.heroActor().?.tactics = .{ .steady = 2, .guard = 1, .unyielding = true, .overwatch = .e };
    const at = g.sim.heroActor().?.at.add(.{ .x = 2, .y = 0 });
    g.sim.lv.barrier[grid.Level.idx(at)] = 3;
    g.sim.lv.caltrops[grid.Level.idx(at)] = .{ .turns = 4, .rank = 2 };
    var first = std.ArrayList(u8).init(alloc);
    defer first.deinit();
    const snapshot = try alloc.create(format.Snapshot);
    defer alloc.destroy(snapshot);
    var timer = try std.time.Timer.start();
    try format.capture(g, snapshot);
    const capture_ns = timer.read();
    timer.reset();
    try write(g, &first);
    const encode_ns = timer.read();
    seal(&first);

    const back = try game.boot(alloc);
    defer game.shut(alloc, back);
    const into = try alloc.create(Map);
    defer alloc.destroy(into);
    game.begin(back, 1);
    timer.reset();
    try read(first.items, back, into);
    const parse_ns = timer.read();
    try std.testing.expectEqualDeep(g.sim.inventory.gear, back.sim.inventory.gear);
    try std.testing.expectEqualDeep(g.sim.inventory.bag[1], back.sim.inventory.bag[1]);
    try std.testing.expectEqualDeep(g.sim.ground.drops[0].item, back.sim.ground.drops[0].item);
    try std.testing.expectEqualDeep(g.sim.ground.supplies[0], back.sim.ground.supplies[0]);
    try std.testing.expectEqualDeep(g.sim.inventory.stacks, back.sim.inventory.stacks);
    var rare_buf: [items.NAME_MAX]u8 = undefined;
    try std.testing.expectEqualStrings("Magus Fold", back.sim.inventory.bag[1].name(&rare_buf));
    try std.testing.expectEqual(@as(i32, 2), back.sim.heroAttrs().thorns);
    try std.testing.expectEqual(@as(i32, 25), back.sim.heroAttrs().gold_find);
    try std.testing.expectEqual(@as(i32, 25), back.sim.heroAttrs().item_rarity);
    try std.testing.expectEqualDeep(g.sim.heroActor().?.tactics, back.sim.heroActor().?.tactics);
    try std.testing.expectEqual(@as(u8, 3), back.sim.lv.barrier[grid.Level.idx(at)]);
    try std.testing.expectEqual(@as(u8, 2), back.sim.lv.caltrops[grid.Level.idx(at)].rank);
    var again = std.ArrayList(u8).init(alloc);
    defer again.deinit();
    try write(back, &again);
    seal(&again);
    try std.testing.expectEqualDeep(try peek(first.items), try peek(again.items));
    try std.testing.expectEqualSlices(u8, first.items, again.items);
    std.debug.print("portable save version {d}: {d} bytes, canonical rewrite and all equipment/status fields retained\n", .{ format.VERSION, first.items.len });
    std.debug.print("portable save timing: {d:.2} ms capture, {d:.2} ms encoding off-frame, {d:.2} ms validated load (two-node fixture)\n", .{ @as(f64, @floatFromInt(capture_ns)) / std.time.ns_per_ms, @as(f64, @floatFromInt(encode_ns)) / std.time.ns_per_ms, @as(f64, @floatFromInt(parse_ns)) / std.time.ns_per_ms });
    try std.testing.expectEqual(RECORDED_FINGERPRINT, FINGERPRINT);
}

test "legacy saves convert on load and reject invalid native tags before changing the run" {
    const alloc = std.testing.allocator;
    const world = try testMap();
    defer alloc.destroy(world);
    const source = try game.boot(alloc);
    defer game.shut(alloc, source);
    try fixture(source, world);
    const target = try game.boot(alloc);
    defer game.shut(alloc, target);
    const into = try alloc.create(Map);
    defer alloc.destroy(into);
    var old = std.ArrayList(u8).init(alloc);
    defer old.deinit();
    try writeLegacy(source, &old);
    seal(&old);
    try read(old.items, target, into);
    try std.testing.expect(target.sim.unsaved);
    try std.testing.expectEqualStrings(source.sim.name.text(), target.sim.name.text());
    try std.testing.expectEqualDeep(source.sim.growth, target.sim.growth);
    try std.testing.expectEqualDeep(source.sim.rng, target.sim.rng);
    var fresh = std.ArrayList(u8).init(alloc);
    defer fresh.deinit();
    try write(target, &fresh);
    seal(&fresh);
    try std.testing.expect(std.mem.startsWith(u8, fresh.items, format.MAGIC));
    _ = try peek(fresh.items);

    const tail_at = HEAD + @sizeOf(Summary) + @sizeOf(Seed) + 1 + @sizeOf(RawMap) + @sizeOf(Node) + @sizeOf(Visited) + source.sim.visited.count() * @sizeOf(RawVisit);
    const actor_at = tail_at + @sizeOf(RawLevel) + @offsetOf(actor.Pool, "items");
    const offsets = [_]usize{ actor_at + @offsetOf(actor.Actor, "kind"), actor_at + @offsetOf(actor.Actor, "alive") };
    const map_hash = store.sum(std.mem.asBytes(into));
    for (offsets) |offset| {
        const previous = old.items[offset];
        old.items[offset] = 255;
        old.shrinkRetainingCapacity(old.items.len - store.SUM);
        seal(&old);
        try std.testing.expectError(error.Damaged, read(old.items, target, into));
        try std.testing.expectEqual(map_hash, store.sum(std.mem.asBytes(into)));
        try std.testing.expectEqualStrings(source.sim.name.text(), target.sim.name.text());
        old.items[offset] = previous;
    }
    std.debug.print("legacy conversion: visited map, progress and RNG retained; native enum/bool corruption rejected without mutation\n", .{});
}

test "a listed save must have the complete run that loading requires" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.begin(g, 1);
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try writeLegacy(g, &buf);
    const full = try std.testing.allocator.dupe(u8, buf.items);
    defer std.testing.allocator.free(full);
    const map = try std.testing.allocator.create(Map);
    defer std.testing.allocator.destroy(map);
    const hp = g.sim.heroActor().?.hp;
    const seed = g.sim.seed;
    const cuts = [_]usize{ HEAD + @sizeOf(Summary), HEAD + @sizeOf(Summary) + @sizeOf(Seed) + @sizeOf(bool), full.len - 1 };
    for (cuts) |cut| {
        buf.clearRetainingCapacity();
        try buf.appendSlice(full[0..cut]);
        seal(&buf);
        try std.testing.expectError(error.Short, peekLegacy(buf.items));
        try std.testing.expectError(error.Short, readLegacy(buf.items, g, map));
        try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
        try std.testing.expectEqual(seed, g.sim.seed);
    }
    buf.clearRetainingCapacity();
    try buf.appendSlice(full);
    buf.items[HEAD + @sizeOf(Summary) + @sizeOf(Seed)] = 2;
    seal(&buf);
    try std.testing.expectError(error.Damaged, peekLegacy(buf.items));
    try std.testing.expectError(error.Damaged, readLegacy(buf.items, g, map));
    std.debug.print("{d} checksummed incomplete saves and an invalid map flag refused before loading\n", .{cuts.len});
}

test "autosave gates retain dirty state until the interval turn and door are complete" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const Gate = enum { clean, interval, busy, travel };
    for (std.enums.values(Gate)) |gate| {
        game.begin(g, 1);
        var a = Autosave.init(std.testing.failing_allocator, 0);
        defer a.deinit();
        a.since = if (gate == .interval) GAP_S / 2 else GAP_S;
        g.sim.unsaved = gate != .clean;
        if (gate == .busy) g.pic.busy = 0.25;
        if (gate == .travel) g.sim.travel = .{ .node = 0, .door = 0 };
        a.step(g, 0);
        try std.testing.expectEqual(gate != .clean, g.sim.unsaved);
        try std.testing.expectEqual(@as(?anyerror, null), a.failed);
        try std.testing.expectEqual(@as(usize, 0), a.bytes.items.len);
        try std.testing.expect(a.writer == null);
        g.sim.unsaved = true;
        g.sim.travel = null;
        g.pic.busy = 0;
        a.since = GAP_S;
        a.step(g, 0);
        try std.testing.expectEqual(@as(?anyerror, error.OutOfMemory), a.failed);
        try std.testing.expect(a.writer == null);
        a.step(g, 0);
        try std.testing.expect(g.sim.unsaved);
    }
    std.debug.print("autosave: {d} independent gates preserve dirty state; each released gate attempts capture without filesystem writes\n", .{std.enums.values(Gate).len});
}

test "checksummed save structure failures preserve both the live run and destination map" {
    const alloc = std.testing.allocator;
    const w = try testMap();
    defer alloc.destroy(w);
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    try fixture(g, w);
    var full = std.ArrayList(u8).init(alloc);
    defer full.deinit();
    try writeLegacy(g, &full);
    seal(&full);

    const back = try game.boot(alloc);
    defer game.shut(alloc, back);
    game.begin(back, 19);
    back.sim.name = hero.Name.of("Untouched");
    back.sim.gold = 41;
    const into = try testMap();
    defer alloc.destroy(into);
    const map_hash = store.sum(std.mem.asBytes(into));
    var before = std.ArrayList(u8).init(alloc);
    defer before.deinit();
    try writeLegacy(back, &before);
    const map_at = HEAD + @sizeOf(Summary) + @sizeOf(Seed) + @sizeOf(bool);
    const visits_at = map_at + @sizeOf(RawMap) + @sizeOf(Node) + @sizeOf(Visited);
    const cuts = [_]usize{
        HEAD,
        HEAD + @sizeOf(Summary) - 1,
        map_at - 1,
        map_at,
        map_at + @sizeOf(RawMap) - 1,
        visits_at - 1,
        visits_at,
        visits_at + @sizeOf(RawVisit) - 1,
        full.items.len - store.SUM - 1,
        full.items.len - store.SUM,
    };
    var damaged = std.ArrayList(u8).init(alloc);
    defer damaged.deinit();
    var after = std.ArrayList(u8).init(alloc);
    defer after.deinit();
    for (cuts, 0..) |cut, i| {
        damaged.clearRetainingCapacity();
        try damaged.appendSlice(full.items[0..cut]);
        if (i == cuts.len - 1) try damaged.append(0);
        seal(&damaged);
        try std.testing.expectError(error.Short, peekLegacy(damaged.items));
        try std.testing.expectError(error.Short, readLegacy(damaged.items, back, into));
        after.clearRetainingCapacity();
        try writeLegacy(back, &after);
        try std.testing.expectEqualSlices(u8, before.items, after.items);
        try std.testing.expectEqual(map_hash, store.sum(std.mem.asBytes(into)));
    }
    const Navigation = enum { node_capacity, node_count, empty_map, oversized_map, visited_node, summary_node };
    const Patch = struct {
        fn value(bytes: []u8, at: usize, v: anytype) void {
            @memcpy(bytes[at..][0..@sizeOf(@TypeOf(v))], std.mem.asBytes(&v));
        }
    };
    for (std.enums.values(Navigation)) |case| {
        damaged.clearRetainingCapacity();
        try damaged.appendSlice(full.items[0 .. full.items.len - store.SUM]);
        const node_at = map_at + @sizeOf(RawMap);
        switch (case) {
            .node_capacity => Patch.value(damaged.items, node_at, @as(Node, atlas.MAX_NODES)),
            .node_count => {
                Patch.value(damaged.items, node_at, @as(Node, w.node_n));
                Patch.value(damaged.items, HEAD + @offsetOf(Summary, "node"), @as(?usize, w.node_n));
            },
            .empty_map => Patch.value(damaged.items, map_at + @offsetOf(RawMap, "node_n"), @as(usize, 0)),
            .oversized_map => Patch.value(damaged.items, map_at + @offsetOf(RawMap, "node_n"), @as(usize, atlas.MAX_NODES + 1)),
            .visited_node => {
                var visited = Visited.initEmpty();
                visited.set(w.node_n);
                try std.testing.expectEqual(g.sim.visited.count(), visited.count());
                Patch.value(damaged.items, node_at + @sizeOf(Node), visited);
            },
            .summary_node => Patch.value(damaged.items, HEAD + @offsetOf(Summary, "node"), @as(?usize, 0)),
        }
        seal(&damaged);
        try std.testing.expectError(error.Damaged, peekLegacy(damaged.items));
        try std.testing.expectError(error.Damaged, readLegacy(damaged.items, back, into));
        after.clearRetainingCapacity();
        try writeLegacy(back, &after);
        try std.testing.expectEqualSlices(u8, before.items, after.items);
        try std.testing.expectEqual(map_hash, store.sum(std.mem.asBytes(into)));
    }
    std.debug.print("save validation: {d} length and {d} navigation failures preserve the complete run and destination map\n", .{ cuts.len, std.enums.values(Navigation).len });
}

test "a generated run reloads every class without retaining the previous run's transient state" {
    const alloc = std.testing.allocator;
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    const back = try game.boot(alloc);
    defer game.shut(alloc, back);
    const into = try testMap();
    defer alloc.destroy(into);
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    for (hero.CLASSES) |class| {
        g.sim.class = class;
        game.begin(g, 29);
        g.sim.name = hero.Name.of("Generated");
        g.sim.gold = 31;
        g.sim.mana = 2;
        _ = g.sim.growth.gain(100);
        _ = g.sim.pool.damage(&g.sim.lv, g.sim.hero, 3);
        const map_hash = store.sum(std.mem.asBytes(into));
        buf.clearRetainingCapacity();
        try write(g, &buf);
        seal(&buf);
        try fixture(back, into);
        back.mode = .{ .aim = game.Aim.of(.x, .shoot, .{ .x = 20, .y = 20 }) };
        back.exit = .quit;
        back.target = 2;
        back.pending = .interact;
        back.sim.travel = .{ .node = 0, .door = 0 };
        back.pic.busy = 0.5;
        try read(buf.items, back, into);
        try std.testing.expect(back.sim.map == null);
        try std.testing.expectEqual(map_hash, store.sum(std.mem.asBytes(into)));
        try std.testing.expectEqual(class, back.sim.class);
        try std.testing.expectEqualStrings("Generated", back.sim.name.text());
        try std.testing.expectEqualDeep(g.sim.growth, back.sim.growth);
        try std.testing.expectEqualDeep(g.sim.rng, back.sim.rng);
        try std.testing.expectEqualDeep(g.sim.loot_rng, back.sim.loot_rng);
        try std.testing.expectEqualDeep(g.bar, back.bar);
        try std.testing.expectEqual(@as(i32, 31), back.sim.gold);
        try std.testing.expectEqual(@as(i32, 2), back.sim.mana);
        try std.testing.expectEqual(g.sim.heroActor().?.hp, back.sim.heroActor().?.hp);
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(back.mode));
        try std.testing.expect(back.exit == null and back.target == null and back.pending == null and back.sim.travel == null);
        try std.testing.expect(back.pic.quiet());
        try std.testing.expectEqual(back.sim.heroActor().?.hp, back.pic.heroShown(&back.sim).?.hp);
        try std.testing.expectEqual(back.sim.gold, back.pic.gold_shown);
        try std.testing.expectEqualDeep(back.sim.growth, back.pic.growth_shown);
        try std.testing.expectEqual(@as(f32, 0), back.pic.fx.level_up.life);
    }
    std.debug.print("save reload: {d} generated class runs restore resources, RNG and HUD; clear pending aim, travel and effects without touching the destination map\n", .{hero.CLASSES.len});
}
