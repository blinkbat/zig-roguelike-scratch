const std = @import("std");
const store = @import("core/store.zig");
const mathx = @import("core/mathx.zig");
const game = @import("game.zig");
const atlas = @import("world/atlas.zig");
const grid = @import("world/grid.zig");
const actor = @import("play/actor.zig");
const hero = @import("play/hero.zig");
const skillbar = @import("play/skillbar.zig");

// A run frozen whole: the world it is played in, every node visited as it was left, the one being played as it is.

pub const SLOTS: usize = 3;
pub const DIR = "saves";
const EXT = ".save";
const TMP_EXT = ".tmp";
const MAGIC = "roguelike-save\n";
const FILE_CAP: usize = 64 << 20;
const PATH_MAX: usize = 64;
/// Seconds between saves while turns are taken; the last turn's is written once they stop.
pub const GAP_S: f32 = 1;

const Visited = std.StaticBitSet(atlas.MAX_NODES);
const Facings = [actor.MAX]game.Facing;

/// What the slot list shows of a run, read without the rest of it.
pub const Summary = struct {
    name: hero.Name,
    hp: i32,
    max: i32,
    gold: i32,
    kills: usize,
    /// Null on a generated floor.
    node: ?usize,
    place: [atlas.NAME_MAX]u8 = undefined,
    place_n: usize = 0,

    pub fn line(self: *const Summary, buf: []u8) [:0]const u8 {
        var at: [atlas.NAME_MAX + 16]u8 = undefined;
        const where = if (self.node) |n|
            (if (self.place_n > 0) self.place[0..self.place_n] else std.fmt.bufPrint(&at, "node {d}", .{n}) catch "")
        else
            "a generated floor";
        return std.fmt.bufPrintZ(buf, "{s}   HP {d}/{d}   Gold {d}   {s}", .{ self.name.text(), @max(0, self.hp), self.max, self.gold, where }) catch "";
    }
};

pub const Slot = union(enum) { empty, unreadable, run: Summary };

const FINGERPRINT = store.fingerprint(.{
    Summary, u64,       bool,  atlas.Atlas, usize,    Visited,      game.Visit, grid.Level, actor.Pool,
    u16,     mathx.Rng, usize, i32,         game.Log, skillbar.Bar, Facings,    hero.Name,
});
const HEAD = MAGIC.len + @sizeOf(u64);

/// What follows the visited nodes: the node being played and the run round it.
const TAIL = @sizeOf(grid.Level) + @sizeOf(actor.Pool) + @sizeOf(u16) + @sizeOf(mathx.Rng) + @sizeOf(usize) +
    @sizeOf(i32) + @sizeOf(game.Log) + @sizeOf(skillbar.Bar) + @sizeOf(Facings) + @sizeOf(hero.Name);

pub const Error = error{ NotASave, OtherBuild, Short };

fn summaryOf(g: *game.Game) Summary {
    const h = g.pool.items[actor.Pool.slot(g.hero)];
    var s = Summary{ .name = g.name, .hp = h.hp, .max = h.max, .gold = g.gold, .kills = g.kills, .node = null };
    if (g.world) |w| {
        s.node = g.node;
        const nm = w.node[g.node].name();
        @memcpy(s.place[0..nm.len], nm);
        s.place_n = nm.len;
    }
    return s;
}

pub fn write(g: *game.Game, w: anytype) !void {
    try w.writeAll(MAGIC);
    try store.put(w, &FINGERPRINT);
    try store.put(w, &summaryOf(g));
    try store.put(w, &g.seed);
    const has_world = g.world != null;
    try store.put(w, &has_world);
    if (g.world) |a| try store.put(w, a);
    try store.put(w, &g.node);
    try store.put(w, &g.visited);
    var it = g.visited.iterator(.{});
    while (it.next()) |n| try store.put(w, &g.visits[n]);
    try store.put(w, &g.lv);
    try store.put(w, &g.pool);
    try store.put(w, &g.hero);
    try store.put(w, &g.rng);
    try store.put(w, &g.kills);
    try store.put(w, &g.gold);
    try store.put(w, &g.log);
    try store.put(w, &g.bar);
    try store.put(w, &g.facing);
    try store.put(w, &g.name);
}

fn header(bytes: *[]const u8) Error!void {
    if (bytes.len < HEAD or !std.mem.eql(u8, bytes.*[0..MAGIC.len], MAGIC)) return error.NotASave;
    if (std.mem.readInt(u64, bytes.*[MAGIC.len..HEAD], @import("builtin").cpu.arch.endian()) != FINGERPRINT) return error.OtherBuild;
    bytes.* = bytes.*[HEAD..];
}

pub fn peek(bytes: []const u8) Error!Summary {
    var b = bytes;
    try header(&b);
    var s: Summary = undefined;
    if (!store.take(&b, &s)) return error.Short;
    return s;
}

/// All of it is measured before any of it reaches `g`, so a file that does not read leaves the game as it was.
pub fn read(bytes: []const u8, g: *game.Game, world: *atlas.Atlas) Error!void {
    var b = bytes;
    try header(&b);
    var s: Summary = undefined;
    var seed: u64 = undefined;
    var has_world: bool = undefined;
    if (!store.take(&b, &s) or !store.take(&b, &seed) or !store.take(&b, &has_world)) return error.Short;
    const at_visited = @as(usize, if (has_world) @sizeOf(atlas.Atlas) else 0) + @sizeOf(usize);
    if (b.len < at_visited + @sizeOf(Visited)) return error.Short;
    var visited: Visited = undefined;
    var vb = b[at_visited..];
    _ = store.take(&vb, &visited);
    if (b.len != at_visited + @sizeOf(Visited) + visited.count() * @sizeOf(game.Visit) + TAIL) return error.Short;

    if (has_world) _ = store.take(&b, world);
    g.world = if (has_world) world else null;
    g.seed = seed;
    _ = store.take(&b, &g.node);
    _ = store.take(&b, &g.visited);
    var it = g.visited.iterator(.{});
    while (it.next()) |n| _ = store.take(&b, &g.visits[n]);
    _ = store.take(&b, &g.lv);
    _ = store.take(&b, &g.pool);
    _ = store.take(&b, &g.hero);
    _ = store.take(&b, &g.rng);
    _ = store.take(&b, &g.kills);
    _ = store.take(&b, &g.gold);
    _ = store.take(&b, &g.log);
    _ = store.take(&b, &g.bar);
    _ = store.take(&b, &g.facing);
    _ = store.take(&b, &g.name);
    game.resumeRun(g);
}

pub fn path(buf: []u8, slot: usize) []const u8 {
    return std.fmt.bufPrint(buf, DIR ++ "/slot{d}" ++ EXT, .{slot + 1}) catch unreachable;
}

/// Written beside itself and renamed over it, so a write that fails part-way leaves the last save standing.
fn writeFile(bytes: []const u8, slot: usize) !void {
    try std.fs.cwd().makePath(DIR);
    var buf: [PATH_MAX]u8 = undefined;
    var tmp_buf: [PATH_MAX]u8 = undefined;
    const p = path(&buf, slot);
    const tmp = try std.fmt.bufPrint(&tmp_buf, "{s}" ++ TMP_EXT, .{p});
    {
        var f = try std.fs.cwd().createFile(tmp, .{});
        defer f.close();
        try f.writeAll(bytes);
        try f.sync();
    }
    try std.fs.cwd().rename(tmp, p);
}

pub fn load(alloc: std.mem.Allocator, slot: usize, g: *game.Game, world: *atlas.Atlas) !void {
    var buf: [PATH_MAX]u8 = undefined;
    const bytes = try std.fs.cwd().readFileAlloc(alloc, path(&buf, slot), FILE_CAP);
    defer alloc.free(bytes);
    try read(bytes, g, world);
}

pub fn remove(slot: usize) void {
    var buf: [PATH_MAX]u8 = undefined;
    std.fs.cwd().deleteFile(path(&buf, slot)) catch {};
}

pub fn slots() [SLOTS]Slot {
    var out: [SLOTS]Slot = undefined;
    for (&out, 0..) |*s, i| s.* = slotAt(i);
    return out;
}

fn slotAt(i: usize) Slot {
    var buf: [PATH_MAX]u8 = undefined;
    var f = std.fs.cwd().openFile(path(&buf, i), .{}) catch |e| return if (e == error.FileNotFound) .empty else .unreadable;
    defer f.close();
    var head: [HEAD + @sizeOf(Summary)]u8 = undefined;
    const n = f.readAll(&head) catch return .unreadable;
    return .{ .run = peek(head[0..n]) catch return .unreadable };
}

/// The first slot with no run in it.
pub fn free(list: *const [SLOTS]Slot) ?usize {
    for (list, 0..) |s, i| {
        if (s == .empty) return i;
    }
    return null;
}

/// The run in one slot, written once a turn has changed it and the last write is `GAP_S` old. Must not move while
/// a write is under way.
pub const Autosave = struct {
    slot: usize,
    bytes: std.ArrayList(u8),
    since: f32 = GAP_S,
    /// A write takes milliseconds of disk, so it is done off the frame; the run is copied into `bytes` first.
    writer: ?std.Thread = null,
    failed: ?anyerror = null,

    pub fn init(alloc: std.mem.Allocator, slot: usize) Autosave {
        return .{ .slot = slot, .bytes = std.ArrayList(u8).init(alloc) };
    }

    pub fn deinit(self: *Autosave) void {
        self.wait();
        self.bytes.deinit();
    }

    /// Not mid-door: the turn that stepped onto it is written once it is gone through.
    pub fn step(self: *Autosave, g: *game.Game, dt: f32) void {
        self.since += dt;
        if (!g.unsaved or self.since < GAP_S or g.travel != null) return;
        self.flush(g);
    }

    pub fn flush(self: *Autosave, g: *game.Game) void {
        if (!g.unsaved) return;
        self.wait();
        if (self.failed) |e| g.log.say("The last save did not write ({s}).", .{@errorName(e)});
        self.failed = null;
        self.bytes.clearRetainingCapacity();
        write(g, self.bytes.writer()) catch |e| return g.log.say("The save did not write ({s}).", .{@errorName(e)});
        g.unsaved = false;
        self.since = 0;
        self.writer = std.Thread.spawn(.{}, writeOff, .{self}) catch blk: {
            writeOff(self);
            break :blk null;
        };
    }

    fn writeOff(self: *Autosave) void {
        writeFile(self.bytes.items, self.slot) catch |e| {
            self.failed = e;
        };
    }

    /// Until the write under way, if one is, is on disk.
    pub fn wait(self: *Autosave) void {
        const t = self.writer orelse return;
        t.join();
        self.writer = null;
    }

    /// The run is lost, and its save with it.
    pub fn end(self: *Autosave) void {
        self.wait();
        remove(self.slot);
    }
};

fn testWorld() !*atlas.Atlas {
    const w = try std.testing.allocator.create(atlas.Atlas);
    w.* = .{};
    const a = w.add(.{ .procgen = .{} }).?;
    const b = w.add(.{ .procgen = .{} }).?;
    const da = w.addDoor(a, .{ .x = 30, .y = 30 }).?;
    const db = w.addDoor(b, .{ .x = 40, .y = 20 }).?;
    w.link(.{ .node = a, .door = da }, .{ .node = b, .door = db });
    _ = w.node[b].rename("The Warrens");
    w.start = .{ .node = a, .at = .{ .x = 30, .y = 30 } };
    return w;
}

test "a run reads back as it was written, and a short or foreign file leaves the game alone" {
    const alloc = std.testing.allocator;
    const w = try testWorld();
    defer alloc.destroy(w);
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    game.beginWorld(g, w);
    g.name = hero.Name.of("Arwen");
    g.gold = 17;
    _ = g.pool.damage(&g.lv, g.hero, 5);
    g.travel = .{ .node = 1, .door = 0 };
    g.busy = 0;
    game.update(g, 0);
    g.log.say("A line to keep.", .{});

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    try write(g, buf.writer());
    std.debug.print("a run of two nodes, one left behind: {d} KB saved\n", .{buf.items.len / 1024});

    const back = try game.boot(alloc);
    defer game.shut(alloc, back);
    const into = try alloc.create(atlas.Atlas);
    defer alloc.destroy(into);
    game.begin(back, 1);
    try std.testing.expectError(error.Short, read(buf.items[0 .. buf.items.len - 1], back, into));
    try std.testing.expectError(error.NotASave, read("not a save", back, into));
    try std.testing.expectEqual(@as(?*const atlas.Atlas, null), back.world);
    try read(buf.items, back, into);
    try std.testing.expectEqualStrings("Arwen", back.name.text());
    try std.testing.expectEqual(@as(usize, 1), back.node);
    try std.testing.expectEqual(g.archer().?.at, back.archer().?.at);
    try std.testing.expectEqual(g.archer().?.hp, back.archer().?.hp);
    try std.testing.expectEqual(g.pool.n, back.pool.n);
    try std.testing.expectEqualSlices(grid.Tile, &g.lv.tile, &back.lv.tile);
    try std.testing.expectEqualSlices(grid.Tile, &g.visits[0].lv.tile, &back.visits[0].lv.tile);
    try std.testing.expectEqualStrings("A line to keep.", back.log.line(0).?);
    try std.testing.expect(back.permadeath);
    const s = try peek(buf.items);
    var line: [128]u8 = undefined;
    try std.testing.expectEqualStrings("Arwen   HP 19/24   Gold 17   The Warrens", s.line(&line));
}
