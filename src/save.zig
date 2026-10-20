const std = @import("std");
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
const DIR = "saves";
const EXT = ".save";
const MAGIC = "roguelike-save\n";
const FILE_CAP: usize = 64 << 20;
const PATH_FMT = DIR ++ "/slot{d}" ++ EXT;
const PATH_MAX: usize = std.fmt.count(PATH_FMT, .{SLOTS});
const GAP_S: f32 = 1;

/// Written before the tail, by hand, in this order: the map behind a flag, then each visited node's visit.
const Header = struct {
    seed: @FieldType(game.Game, "seed"),
    map: std.meta.Child(std.meta.Child(@FieldType(game.Game, "map"))),
    node: @FieldType(game.Game, "node"),
    visited: @FieldType(game.Game, "visited"),
    visits: std.meta.Elem(@FieldType(game.Game, "visits")),
};
const Seed = @FieldType(Header, "seed");
const Map = @FieldType(Header, "map");
const Node = @FieldType(Header, "node");
const Visited = @FieldType(Header, "visited");
const Visit = @FieldType(Header, "visits");
const HEAD_FIELDS = std.meta.fieldNames(Header);
/// Written after the visited nodes, in this order.
const TAIL_FIELDS = .{ "lv", "pool", "hero", "rng", "kills", "gold", "log", "bar", "facing", "name", "clock", "mana", "flasks", "cooldown", "stepped", "class", "inventory", "growth", "ground", "loot_rng" };
/// Not saved: the picture, the input, what the app sets on whatever it plays, and what `game.resumeRun` rebuilds.
const UNSAVED = .{
    "character",
    "nearby",
    "pause_page",
    "mode",
    "pause_menu",
    "back",
    "exit",
    "permadeath",
    "outdoors",
    "hour_shown",
    "unkillable",
    "unsaved",
    "travel",
    "st",
    "binds",
    "aim_by",
    "aim_act",
    "aim_set",
    "mark",
    "cam",
    "screen",
    "framebuffer",
    "shot",
    "glide",
    "turning",
    "order",
    "order_n",
    "busy",
    "pending",
    "lead",
    "owed",
    "ran",
    "pictured",
    "seq",
    "split_from",
    "fx",
    "vignette",
    "cinema",
    "mini",
    "sprites",
    "face",
    "light",
    "cloud",
    "flowed",
    "flow",
    "queue",
    "graphics_ready",
    "art_ready",
    "rain",
    "flasks_shown",
    "mana_held",
    "inspecting",
    "displaced",
    "gold_taken",
    "xp_aim",
    "xp_shown",
    "life_fill",
    "mana_fill",
    "growth_shown",
    "gold_shown",
};

comptime {
    @setEvalBranchQuota(100_000);
    for (std.meta.fields(game.Game)) |f| {
        var n: usize = 0;
        for (TAIL_FIELDS ++ UNSAVED) |name| {
            if (std.mem.eql(u8, f.name, name)) n += 1;
        }
        for (HEAD_FIELDS) |name| {
            if (std.mem.eql(u8, f.name, name)) n += 1;
        }
        if (n != 1) @compileError("save.zig: say whether game.Game." ++ f.name ++ " is saved");
    }
    for (TAIL_FIELDS ++ UNSAVED) |name| {
        if (!@hasField(game.Game, name)) @compileError("save.zig: game.Game has no field " ++ name);
    }
    for (HEAD_FIELDS) |name| {
        if (!@hasField(game.Game, name)) @compileError("save.zig: game.Game has no field " ++ name);
    }
}

/// Named as well as typed, so two fields of one type swapped change the fingerprint.
const Tail = blk: {
    var fs: [TAIL_FIELDS.len]std.builtin.Type.StructField = undefined;
    for (TAIL_FIELDS, 0..) |f, i| {
        const T = @FieldType(game.Game, f);
        fs[i] = .{ .name = f, .type = T, .default_value_ptr = null, .is_comptime = false, .alignment = @alignOf(T) };
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

    pub fn line(self: *const Summary, buf: []u8) [:0]const u8 {
        var at: [atlas.TITLE_MAX]u8 = undefined;
        const where = if (self.node) |n| atlas.titleOf(self.place.text(), n, &at) else "a generated floor";
        return std.fmt.bufPrintZ(buf, "{s}" ++ menu.SEP ++ hero.HP_FMT ++ menu.SEP ++ hero.GOLD_FMT ++ menu.SEP ++ "{s}", .{ self.name.text(), self.hp, self.max, self.gold, where }) catch "";
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

const FINGERPRINT = blk: {
    const head = std.meta.fields(Header);
    var types: [head.len + 3]type = undefined;
    types[0] = Summary;
    types[1] = head[0].type;
    types[2] = bool;
    for (head[1..], 3..) |f, i| types[i] = f.type;
    types[types.len - 1] = Tail;
    break :blk store.fingerprint(types) ^ TREE;
};
/// The passive tree's layout, which saved allocations index by node.
const TREE = blk: {
    @setEvalBranchQuota(100_000);
    var h = std.hash.Wyhash.init(0);
    for (progress.NODES, 0..) |n, i| {
        h.update(n.name);
        h.update(&.{ @intFromEnum(n.arm), if (n.branch) |v| @intFromEnum(v) else 255, if (n.seam) |v| @intFromEnum(v) else 255, n.ring, n.slot, @intFromEnum(n.tier), @intFromEnum(n.grant.kind) });
        h.update(&std.mem.toBytes(n.grant.amount));
        h.update(&.{if (n.bump) |g| @intFromEnum(g.kind) else 255});
        if (n.bump) |g| h.update(&std.mem.toBytes(g.amount));
        var buf: [progress.passives.MAX_FEED]usize = undefined;
        const fs = progress.passives.feeders(i, &buf);
        h.update(&std.mem.toBytes(fs.len));
        for (fs) |f| h.update(&std.mem.toBytes(f));
    }
    for (hero.CLASSES) |c| h.update(&std.mem.toBytes(progress.start(c)));
    break :blk h.final();
};
const Print = @TypeOf(FINGERPRINT);
const HEAD = MAGIC.len + @sizeOf(Print);
/// A trailing payload hash rejects damaged or truncated files before loading.
const SUM = @sizeOf(u64);

pub const Error = error{ NotASave, OtherBuild, Short, Damaged };

fn summaryOf(g: *game.Game) Summary {
    const i = game.heroSlot(g).?;
    const h = g.pool.items[i];
    var s = Summary{ .name = g.name, .hp = h.hp, .max = h.max, .gold = g.gold, .node = null };
    if (g.map) |a| {
        s.node = g.node;
        s.place = a.node[g.node].label;
    }
    return s;
}

/// Into an empty `out`, all but the sum `seal` ends it with.
fn write(g: *game.Game, out: *std.ArrayList(u8)) !void {
    std.debug.assert(out.items.len == 0);
    const w = out.writer();
    try w.writeAll(MAGIC);
    try store.put(w, &FINGERPRINT);
    try store.put(w, &summaryOf(g));
    try store.put(w, &g.seed);
    const has_map = g.map != null;
    try store.put(w, &has_map);
    if (g.map) |a| try store.put(w, a);
    try store.put(w, &g.node);
    try store.put(w, &g.visited);
    var it = g.visited.iterator(.{});
    while (it.next()) |n| try store.put(w, &g.visits[n]);
    inline for (TAIL_FIELDS) |f| try store.put(w, &@field(g, f));
    try out.ensureUnusedCapacity(SUM);
}

/// Ends a file `write` began in `out` with its sum, in the room `write` kept, so it may run off the frame.
fn seal(out: *std.ArrayList(u8)) void {
    const sum = sumOf(out.items[HEAD..]);
    out.appendSliceAssumeCapacity(std.mem.asBytes(&sum));
}

fn sumOf(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

fn header(bytes: *[]const u8) Error!void {
    if (bytes.len < HEAD or !std.mem.eql(u8, bytes.*[0..MAGIC.len], MAGIC)) return error.NotASave;
    var b = bytes.*[MAGIC.len..];
    var print: Print = undefined;
    _ = store.take(&b, &print);
    if (print != FINGERPRINT) return error.OtherBuild;
    bytes.* = b;
}

fn payload(bytes: []const u8) Error![]const u8 {
    var b = bytes;
    try header(&b);
    if (b.len < SUM) return error.Short;
    var tail = b[b.len - SUM ..];
    var sum: u64 = undefined;
    _ = store.take(&tail, &sum);
    b = b[0 .. b.len - SUM];
    if (sum != sumOf(b)) return error.Damaged;
    return b;
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
    const at_visited = @as(usize, if (has_map) @sizeOf(Map) else 0) + @sizeOf(Node);
    if (b.len < at_visited + @sizeOf(Visited)) return error.Short;
    var visited: Visited = undefined;
    var vb = b[at_visited..];
    _ = store.take(&vb, &visited);
    if (b.len != at_visited + @sizeOf(Visited) + visited.count() * @sizeOf(Visit) + TAIL) return error.Short;
    return .{ .summary = s, .seed = seed, .has_map = has_map, .body = b };
}

/// All of it is measured before any of it reaches `g`, so a file that does not read leaves the game as it was.
fn read(bytes: []const u8, g: *game.Game, map: *Map) Error!void {
    const c = try inspect(bytes);
    var b = c.body;
    if (c.has_map) _ = store.take(&b, map);
    g.map = if (c.has_map) map else null;
    g.seed = c.seed;
    _ = store.take(&b, &g.node);
    _ = store.take(&b, &g.visited);
    var it = g.visited.iterator(.{});
    while (it.next()) |n| _ = store.take(&b, &g.visits[n]);
    inline for (TAIL_FIELDS) |f| _ = store.take(&b, &@field(g, f));
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
        if (self.failed != null) g.unsaved = true;
        if (!g.unsaved or self.since < GAP_S or g.travel != null or !game.quiet(g)) return;
        self.flush(g);
    }

    pub fn flush(self: *Autosave, g: *game.Game) void {
        self.wait();
        if (self.failed) |e| {
            if (self.reported == null or self.reported.? != e) g.log.say(NOT_WRITTEN ++ ".", .{@errorName(e)});
            self.reported = e;
            self.failed = null;
            g.unsaved = true;
        } else self.reported = null;
        if (!g.unsaved) return;
        self.bytes.clearRetainingCapacity();
        self.since = 0;
        g.unsaved = false;
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
    try std.testing.expect(g.unsaved);
    try std.testing.expectEqual(@as(?anyerror, null), a.failed);
    try std.testing.expectEqual(@as(usize, 0), a.bytes.items.len);
    try std.testing.expectEqual(GAP_S * 2, a.since);
    const deferred = a.since;

    a.finished.store(true, .release);
    a.step(g, 0);
    try std.testing.expectEqual(@as(?anyerror, error.OutOfMemory), a.failed);
    a.step(g, 0);
    try std.testing.expect(g.unsaved);
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
    g.unsaved = false;
    a.step(g, 0);
    try std.testing.expect(g.unsaved);
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
    const said = g.log.n;
    const RETRIES = 6;
    for (0..RETRIES) |_| a.step(g, GAP_S);
    try std.testing.expectEqual(said + 1, g.log.n);
    std.debug.print("a save failing {d} retries in a row: {d} log line\n", .{ RETRIES, g.log.n - said });
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
    g.name = hero.Name.of("Arwen");
    try std.testing.expect(g.inventory.add(.{ .kind = .ring, .mods = .{ .{ .kind = .intelligence, .value = 2 }, null } }));
    try g.inventory.equip(0, .right_ring, g.growth.attributes(g.class));
    try std.testing.expect(g.inventory.add(.{ .kind = .sword }));
    _ = g.growth.gain(100);
    try std.testing.expect(g.growth.learn(g.class, .burning_arrow));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .boots }, .at = g.heroActor().?.at }));
    try std.testing.expect(g.ground.gold(g.heroActor().?.at, 12));
    g.gold = 17;
    g.mana = 37;
    g.cooldown.set(.juke, 2);
    g.heroActor().?.resists.set(.fire, 50);
    g.heroActor().?.resists.set(.cold, 25);
    g.heroActor().?.burn = .{ .turns = 2 };
    g.heroActor().?.chill = .{ .turns = 2, .phase = 1 };
    if (g.pool.n > 1) g.pool.items[1].chill = .{ .turns = 1, .phase = 2 };
    _ = g.pool.damage(&g.lv, g.hero, 5);
    g.travel = .{ .node = 1, .door = 0 };
    g.busy = 0;
    game.update(g, 0);
    g.log.say("A line to keep.", .{});
    g.stepped = true;
    const forest = grid.Level.idx(.{ .x = 70, .y = 50 });
    for ([_]*grid.Level{ &g.lv, &g.visits[0].lv }) |lv| {
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
    try std.testing.expectEqual(@as(?*const Map, null), back.map);
    try read(buf.items, back, into);
    try std.testing.expectEqualStrings("Arwen", back.name.text());
    try std.testing.expectEqual(g.growth, back.growth);
    try std.testing.expectEqual(g.inventory.gear, back.inventory.gear);
    try std.testing.expectEqualSlices(@import("play/items.zig").Item, g.inventory.bag[0..g.inventory.n], back.inventory.bag[0..back.inventory.n]);
    try std.testing.expectEqual(@as(usize, 1), back.visits[0].ground.n);
    try std.testing.expectEqual(@as(i32, 12), back.visits[0].ground.coins[0].amount);
    try std.testing.expectEqual(g.loot_rng, back.loot_rng);
    try std.testing.expectEqual(@as(usize, 1), back.node);
    try std.testing.expectEqual(g.heroActor().?.at, back.heroActor().?.at);
    try std.testing.expectEqual(g.heroActor().?.hp, back.heroActor().?.hp);
    try std.testing.expectEqual(@as(i32, 37), back.mana);
    try std.testing.expectEqual(@as(u8, 2), back.cooldown.get(.juke));
    try std.testing.expect(back.stepped);
    try std.testing.expectEqual(@as(i16, 50), back.heroActor().?.resists.get(.fire));
    try std.testing.expectEqual(@as(i16, 25), back.heroActor().?.resists.get(.cold));
    try std.testing.expectEqual(@as(u8, 2), back.heroActor().?.burn.turns);
    try std.testing.expectEqual(@as(u8, 2), back.heroActor().?.chill.turns);
    try std.testing.expectEqual(@as(u8, 1), back.heroActor().?.chill.phase);
    for (g.visits[0].pool.slice(), back.visits[0].pool.slice()) |before, after| try std.testing.expectEqual(before.chill, after.chill);
    try std.testing.expectEqual(g.pool.n, back.pool.n);
    try std.testing.expectEqualSlices(grid.Tile, &g.lv.tile, &back.lv.tile);
    try std.testing.expectEqualSlices(grid.Tile, &g.visits[0].lv.tile, &back.visits[0].lv.tile);
    var restored: usize = 0;
    for ([_]*const grid.Level{ &back.lv, &back.visits[0].lv }) |lv| {
        try std.testing.expectEqual(@as(u8, 2), lv.shape[forest].?.mask());
        try std.testing.expectEqual(@as(u8, 8), lv.shape[forest + 1].?.mask());
        restored += 2;
    }
    std.debug.print("save reload restored {d} absent forest shapes across the active and visited nodes\n", .{restored});
    std.debug.print("closed and opened chests preserved on both active and visited nodes\n", .{});
    try std.testing.expectEqualStrings("A line to keep.", back.log.line(0).?);
    const s = try peek(buf.items);
    var line: [128]u8 = undefined;
    try std.testing.expectEqualStrings("Arwen" ++ menu.SEP ++ comptime std.fmt.comptimePrint(hero.HP_FMT, .{ 19, actor.row(actor.HERO).hp }) ++ menu.SEP ++ "Gold 17" ++ menu.SEP ++ "The Warrens", s.line(&line));
    const at = HEAD + @offsetOf(Summary, "node");
    buf.items[at + @sizeOf(usize)] +%= 2;
    try std.testing.expectError(error.Damaged, peek(buf.items));
    buf.items[at + @sizeOf(usize)] -%= 2;
    const far: ?usize = atlas.MAX_NODES;
    @memcpy(buf.items[at..][0..@sizeOf(?usize)], std.mem.asBytes(&far));
    buf.shrinkRetainingCapacity(buf.items.len - SUM);
    seal(&buf);
    try std.testing.expectError(error.Damaged, peek(buf.items));
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
    const hp = g.heroActor().?.hp;
    const seed = g.seed;
    const cuts = [_]usize{ HEAD + @sizeOf(Summary), HEAD + @sizeOf(Summary) + @sizeOf(Seed) + @sizeOf(bool), full.len - 1 };
    for (cuts) |cut| {
        buf.clearRetainingCapacity();
        try buf.appendSlice(full[0..cut]);
        seal(&buf);
        try std.testing.expectError(error.Short, peek(buf.items));
        try std.testing.expectError(error.Short, read(buf.items, g, map));
        try std.testing.expectEqual(hp, g.heroActor().?.hp);
        try std.testing.expectEqual(seed, g.seed);
    }
    buf.clearRetainingCapacity();
    try buf.appendSlice(full);
    buf.items[HEAD + @sizeOf(Summary) + @sizeOf(Seed)] = 2;
    seal(&buf);
    try std.testing.expectError(error.Damaged, peek(buf.items));
    try std.testing.expectError(error.Damaged, read(buf.items, g, map));
    std.debug.print("{d} checksummed incomplete saves and an invalid map flag refused before loading\n", .{cuts.len});
}
