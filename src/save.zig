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
const FILE_CAP: usize = 64 << 20;
const PATH_FMT = DIR ++ "/slot{d}" ++ EXT;
const PATH_MAX: usize = std.fmt.count(PATH_FMT, .{SLOTS});
const GAP_S: f32 = 1;

/// Where in the game a saved field lives, `game` or its field of that name; the file names it by its field name alone.
const Part = enum { game, sim, pic };

fn Of(comptime p: Part) type {
    return if (p == .game) game.Game else @FieldType(game.Game, @tagName(p));
}

fn part(g: *game.Game, comptime p: Part) *Of(p) {
    return if (p == .game) g else &@field(g, @tagName(p));
}

const HEAD_PART: Part = .sim;
const Run = Of(HEAD_PART);

/// Written before the tail, by hand, in this order: the map behind a flag, then each visited node's visit.
const Header = struct {
    seed: @FieldType(Run, "seed"),
    map: std.meta.Child(std.meta.Child(@FieldType(Run, "map"))),
    node: @FieldType(Run, "node"),
    visited: @FieldType(Run, "visited"),
    visits: std.meta.Elem(@FieldType(Run, "visits")),
};
const Seed = @FieldType(Header, "seed");
const Map = @FieldType(Header, "map");
const Node = @FieldType(Header, "node");
const Visited = @FieldType(Header, "visited");
const Visit = @FieldType(Header, "visits");
const HEAD_FIELDS = std.meta.fieldNames(Header);

comptime {
    const by_hand = .{ "seed", "map", "node", "visited", "visits" };
    std.debug.assert(HEAD_FIELDS.len == by_hand.len);
    for (HEAD_FIELDS, by_hand) |f, h| {
        if (!std.mem.eql(u8, f, h)) @compileError("save.Header: write, inspect and read take " ++ h ++ " here by hand, not " ++ f);
    }
}
/// Written after the visited nodes, in this order.
const TAIL_FIELDS = .{
    .{ .sim, "lv" },
    .{ .sim, "pool" },
    .{ .sim, "hero" },
    .{ .sim, "rng" },
    .{ .sim, "kills" },
    .{ .sim, "gold" },
    .{ .sim, "log" },
    .{ .game, "bar" },
    .{ .pic, "facing" },
    .{ .sim, "name" },
    .{ .sim, "clock" },
    .{ .sim, "mana" },
    .{ .sim, "mana_recovery" },
    .{ .sim, "flasks" },
    .{ .sim, "cooldown" },
    .{ .sim, "stepped" },
    .{ .sim, "class" },
    .{ .sim, "inventory" },
    .{ .sim, "growth" },
    .{ .sim, "ground" },
    .{ .sim, "loot_rng" },
};
/// Not saved: the picture, the input, what the app sets on whatever it plays, and what `game.resumeRun` rebuilds.
const UNSAVED = .{
    .game = .{
        "character",
        "nearby",
        "pause_page",
        "debug",
        "mode",
        "died_in",
        "pause_menu",
        "back",
        "exit",
        "permadeath",
        "hall",
        "epitaph",
        "st",
        "binds",
        "target",
        "cam",
        "screen",
        "framebuffer",
        "pending",
        "mouse",
        "vignette",
        "cinema",
        "mini",
        "sprites",
        "face",
        "light",
        "cloud",
        "graphics_ready",
        "art",
        "rain",
        "inspecting",
        "inspect_scroll",
        "perf",
    },
    .sim = .{
        "outdoors",
        "unkillable",
        "unsaved",
        "travel",
        "chronicle",
        "displaced",
        "order",
        "order_n",
        "ran",
        "flowed",
        "flow",
        "queue",
    },
    .pic = .{
        "occlusion",
        "glide",
        "turning",
        "pictured",
        "seq",
        "split_from",
        "dropped_gold",
        "owed",
        "shot",
        "foe_shots",
        "busy",
        "lead",
        "fx",
        "gold_taken",
        "mana_held",
        "flasks_shown",
        "xp_aim",
        "xp_shown",
        "life_fill",
        "mana_fill",
        "growth_shown",
        "gold_shown",
        "hour_shown",
    },
};

comptime {
    @setEvalBranchQuota(100_000);
    for (std.enums.values(Part)) |p| {
        const T = Of(p);
        const unsaved = @field(UNSAVED, @tagName(p));
        for (std.meta.fields(T)) |f| {
            var n: usize = 0;
            if (p == HEAD_PART) for (HEAD_FIELDS) |name| {
                if (std.mem.eql(u8, f.name, name)) n += 1;
            };
            for (TAIL_FIELDS) |t| {
                if (t[0] == p and std.mem.eql(u8, f.name, t[1])) n += 1;
            }
            for (unsaved) |name| {
                if (std.mem.eql(u8, f.name, name)) n += 1;
            }
            if (p == .game) for (std.enums.values(Part)) |q| {
                if (q != .game and std.mem.eql(u8, f.name, @tagName(q))) n += 1;
            };
            if (n != 1) @compileError("save.zig: say whether " ++ @typeName(T) ++ "." ++ f.name ++ " is saved");
        }
        for (unsaved) |name| {
            if (!@hasField(T, name)) @compileError("save.zig: " ++ @typeName(T) ++ " has no field " ++ name);
        }
    }
    for (TAIL_FIELDS) |t| {
        if (!@hasField(Of(t[0]), t[1])) @compileError("save.zig: " ++ @typeName(Of(t[0])) ++ " has no field " ++ t[1]);
    }
}

/// Named as well as typed, so two fields of one type swapped change the fingerprint.
const Tail = blk: {
    var fs: [TAIL_FIELDS.len]std.builtin.Type.StructField = undefined;
    for (TAIL_FIELDS, 0..) |f, i| {
        const T = @FieldType(Of(f[0]), f[1]);
        fs[i] = .{ .name = f[1], .type = T, .default_value_ptr = null, .is_comptime = false, .alignment = @alignOf(T) };
    }
    break :blk @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &fs, .decls = &.{}, .is_tuple = false } });
};
const TAIL = blk: {
    var n: usize = 0;
    for (std.meta.fields(Tail)) |f| n += @sizeOf(f.type);
    break :blk n;
};

pub const Summary = struct {
    name: hero.Name,
    hp: i32,
    max: i32,
    gold: i32,
    /// Null on a generated floor.
    node: ?usize,
    place: atlas.Label = .{},

    pub fn details(self: *const Summary, buf: []u8) [:0]const u8 {
        var at: [atlas.TITLE_MAX]u8 = undefined;
        const where = if (self.node) |n| atlas.titleOf(self.place.text(), n, &at) else "a generated floor";
        return std.fmt.bufPrintZ(buf, hero.HP_FMT ++ menu.SEP ++ hero.GOLD_FMT ++ menu.SEP ++ "{s}", .{ self.hp, self.max, self.gold, where }) catch "";
    }
};

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
    break :blk store.fingerprint(types) ^ TREE;
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

pub const Error = error{ NotASave, OtherBuild, Short, Damaged };

fn summaryOf(g: *game.Game) Summary {
    const h = g.sim.heroActor().?;
    var s = Summary{ .name = g.sim.name, .hp = h.hp, .max = h.max, .gold = g.sim.gold, .node = null };
    if (g.sim.map) |a| {
        s.node = g.sim.node;
        s.place = a.node[g.sim.node].label;
    }
    return s;
}

/// Into an empty `out`, all but the sum `seal` ends it with.
fn write(g: *game.Game, out: *std.ArrayList(u8)) !void {
    std.debug.assert(out.items.len == 0);
    const w = out.writer();
    try store.begin(w, MAGIC, FINGERPRINT);
    try store.put(w, &summaryOf(g));
    try store.put(w, &g.sim.seed);
    const has_map = g.sim.map != null;
    try store.put(w, &has_map);
    if (g.sim.map) |a| try store.put(w, a);
    try store.put(w, &g.sim.node);
    try store.put(w, &g.sim.visited);
    var it = g.sim.visited.iterator(.{});
    while (it.next()) |n| try store.put(w, &g.sim.visits[n]);
    inline for (TAIL_FIELDS) |f| try store.put(w, &@field(part(g, f[0]), f[1]));
    try out.ensureUnusedCapacity(store.SUM);
}

/// Ends a file `write` began in `out` with its sum, in the room `write` kept, so it may run off the frame.
fn seal(out: *std.ArrayList(u8)) void {
    const sum = store.sum(out.items[HEAD..]);
    out.appendSliceAssumeCapacity(std.mem.asBytes(&sum));
}

fn payload(bytes: []const u8) Error![]const u8 {
    return store.open(bytes, MAGIC, FINGERPRINT) catch |e| switch (e) {
        error.Foreign => error.NotASave,
        else => |other| other,
    };
}

fn peek(bytes: []const u8) Error!Summary {
    return (try inspect(bytes)).summary;
}

const Contents = struct { summary: Summary, seed: Seed, has_map: bool, body: []const u8 };

fn inspect(bytes: []const u8) Error!Contents {
    var b = try payload(bytes);
    var s: Summary = undefined;
    if (!store.take(&b, &s)) return error.Short;
    if (!s.name.valid() or !s.place.valid()) return error.Damaged;
    if (s.node) |n| {
        if (n >= atlas.MAX_NODES) return error.Damaged;
    }
    var seed: Seed = undefined;
    var map_flag: u8 = undefined;
    comptime std.debug.assert(@sizeOf(bool) == @sizeOf(u8));
    if (!store.take(&b, &seed) or !store.take(&b, &map_flag)) return error.Short;
    if (map_flag > 1) return error.Damaged;
    const has_map = map_flag != 0;
    const at_node: usize = if (has_map) @sizeOf(Map) else 0;
    const at_visited = at_node + @sizeOf(Node);
    if (b.len < at_visited + @sizeOf(Visited)) return error.Short;
    var node: Node = undefined;
    var visited: Visited = undefined;
    var navigation = b[at_node..];
    _ = store.take(&navigation, &node);
    _ = store.take(&navigation, &visited);
    if (b.len != at_visited + @sizeOf(Visited) + visited.count() * @sizeOf(Visit) + TAIL) return error.Short;
    if (has_map) {
        var node_count: @FieldType(Map, "node_n") = undefined;
        var count_bytes = b[@offsetOf(Map, "node_n")..];
        _ = store.take(&count_bytes, &node_count);
        if (node_count == 0 or node_count > atlas.MAX_NODES or node >= node_count) return error.Damaged;
        var it = visited.iterator(.{});
        while (it.next()) |n| if (n >= node_count) return error.Damaged;
        if (s.node != node) return error.Damaged;
    } else if (node != 0 or visited.count() != 0 or s.node != null) return error.Damaged;
    return .{ .summary = s, .seed = seed, .has_map = has_map, .body = b };
}

/// All of it is measured before any of it reaches `g`, so a file that does not read leaves the game as it was.
fn read(bytes: []const u8, g: *game.Game, map: *Map) Error!void {
    const c = try inspect(bytes);
    var b = c.body;
    if (c.has_map) _ = store.take(&b, map);
    g.sim.map = if (c.has_map) map else null;
    g.sim.seed = c.seed;
    _ = store.take(&b, &g.sim.node);
    _ = store.take(&b, &g.sim.visited);
    var it = g.sim.visited.iterator(.{});
    while (it.next()) |n| _ = store.take(&b, &g.sim.visits[n]);
    inline for (TAIL_FIELDS) |f| _ = store.take(&b, &@field(part(g, f[0]), f[1]));
    game.resumeRun(g);
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
        self.bytes.deinit();
    }

    pub fn close(self: *Autosave, g: *game.Game) ?anyerror {
        self.flush(g);
        self.deinit();
        return self.failed;
    }

    /// Not mid-door, nor mid-turn: a foe's turn to face the hero is only in `facing` once it is drawn.
    pub fn step(self: *Autosave, g: *game.Game, dt: f32) void {
        self.since += dt;
        if (!self.finished.load(.acquire)) return;
        self.wait();
        if (self.failed != null) g.sim.unsaved = true;
        if (!g.sim.unsaved or self.since < GAP_S or g.sim.travel != null or !g.pic.quiet()) return;
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
        write(g, &self.bytes) catch |e| {
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
    const at = HEAD + @offsetOf(Summary, "node");
    buf.items[at + @sizeOf(usize)] +%= 2;
    try std.testing.expectError(error.Damaged, peek(buf.items));
    buf.items[at + @sizeOf(usize)] -%= 2;
    const far: ?usize = atlas.MAX_NODES;
    @memcpy(buf.items[at..][0..@sizeOf(?usize)], std.mem.asBytes(&far));
    buf.shrinkRetainingCapacity(buf.items.len - store.SUM);
    seal(&buf);
    try std.testing.expectError(error.Damaged, peek(buf.items));
}

/// Changes only when the saved types, their names or order, the passive tree or Zig's version do; old saves then stop loading.
const RECORDED_FINGERPRINT: Print = 0x2d1c39b5a4cbd50b;

fn fixture(g: *game.Game, w: *const Map) !void {
    game.beginMapAt(g, w, w.start, 7);
    g.sim.name = hero.Name.of("Fixture");
    try std.testing.expect(g.sim.inventory.add(.{ .kind = .sword }));
    g.pic.facing[0] = .left;
    g.sim.travel = .{ .node = 1, .door = 0 };
    game.update(g, 0);
}

test "the save layout is the recorded one, and a run saves the bytes it loads from" {
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
    g.sim.heroActor().?.tactics = .{ .steady = 2, .guard = 1, .unyielding = true, .overwatch = .e };
    const at = g.sim.heroActor().?.at.add(.{ .x = 2, .y = 0 });
    g.sim.lv.barrier[grid.Level.idx(at)] = 3;
    g.sim.lv.caltrops[grid.Level.idx(at)] = .{ .turns = 4, .rank = 2 };
    var first = std.ArrayList(u8).init(alloc);
    defer first.deinit();
    try write(g, &first);
    seal(&first);

    const back = try game.boot(alloc);
    defer game.shut(alloc, back);
    const into = try alloc.create(Map);
    defer alloc.destroy(into);
    game.begin(back, 1);
    try read(first.items, back, into);
    try std.testing.expectEqualDeep(g.sim.inventory.gear, back.sim.inventory.gear);
    try std.testing.expectEqualDeep(g.sim.inventory.bag[1], back.sim.inventory.bag[1]);
    try std.testing.expectEqualDeep(g.sim.ground.drops[0].item, back.sim.ground.drops[0].item);
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
    const run = first.items[HEAD + @sizeOf(Summary) .. first.items.len - store.SUM];
    try std.testing.expectEqualSlices(u8, run, again.items[HEAD + @sizeOf(Summary) .. again.items.len - store.SUM]);
    std.debug.print("fingerprint 0x{x:0>16}; fixture run of {d} bytes rewritten identically after loading\n", .{ FINGERPRINT, run.len });
    try std.testing.expectEqual(RECORDED_FINGERPRINT, FINGERPRINT);
}

test "a listed save must have the complete run that loading requires" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.begin(g, 1);
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try write(g, &buf);
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
        try std.testing.expectError(error.Short, peek(buf.items));
        try std.testing.expectError(error.Short, read(buf.items, g, map));
        try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
        try std.testing.expectEqual(seed, g.sim.seed);
    }
    buf.clearRetainingCapacity();
    try buf.appendSlice(full);
    buf.items[HEAD + @sizeOf(Summary) + @sizeOf(Seed)] = 2;
    seal(&buf);
    try std.testing.expectError(error.Damaged, peek(buf.items));
    try std.testing.expectError(error.Damaged, read(buf.items, g, map));
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
    std.debug.print("autosave: 4 independent gates preserve dirty state; each released gate attempts capture without filesystem writes\n", .{});
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
    try write(g, &full);
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
    try write(back, &before);
    const map_at = HEAD + @sizeOf(Summary) + @sizeOf(Seed) + @sizeOf(bool);
    const visits_at = map_at + @sizeOf(Map) + @sizeOf(Node) + @sizeOf(Visited);
    const cuts = [_]usize{
        HEAD,
        HEAD + @sizeOf(Summary) - 1,
        map_at - 1,
        map_at,
        map_at + @sizeOf(Map) - 1,
        visits_at - 1,
        visits_at,
        visits_at + @sizeOf(Visit) - 1,
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
        try std.testing.expectError(error.Short, peek(damaged.items));
        try std.testing.expectError(error.Short, read(damaged.items, back, into));
        after.clearRetainingCapacity();
        try write(back, &after);
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
        const node_at = map_at + @sizeOf(Map);
        switch (case) {
            .node_capacity => Patch.value(damaged.items, node_at, @as(Node, atlas.MAX_NODES)),
            .node_count => {
                Patch.value(damaged.items, node_at, @as(Node, w.node_n));
                Patch.value(damaged.items, HEAD + @offsetOf(Summary, "node"), @as(?usize, w.node_n));
            },
            .empty_map => Patch.value(damaged.items, map_at + @offsetOf(Map, "node_n"), @as(usize, 0)),
            .oversized_map => Patch.value(damaged.items, map_at + @offsetOf(Map, "node_n"), @as(usize, atlas.MAX_NODES + 1)),
            .visited_node => {
                var visited = Visited.initEmpty();
                visited.set(w.node_n);
                try std.testing.expectEqual(g.sim.visited.count(), visited.count());
                Patch.value(damaged.items, node_at + @sizeOf(Node), visited);
            },
            .summary_node => Patch.value(damaged.items, HEAD + @offsetOf(Summary, "node"), @as(?usize, 0)),
        }
        seal(&damaged);
        try std.testing.expectError(error.Damaged, peek(damaged.items));
        try std.testing.expectError(error.Damaged, read(damaged.items, back, into));
        after.clearRetainingCapacity();
        try write(back, &after);
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
