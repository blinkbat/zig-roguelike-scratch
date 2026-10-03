const std = @import("std");
const store = @import("core/store.zig");
const game = @import("game.zig");
const atlas = @import("world/atlas.zig");
const grid = @import("world/grid.zig");
const actor = @import("play/actor.zig");
const hero = @import("play/hero.zig");
const menu = @import("ui/menu.zig");

pub const SLOTS: usize = 3;
const DIR = "saves";
const EXT = ".save";
const MAGIC = "roguelike-save\n";
const FILE_CAP: usize = 64 << 20;
const PATH_MAX: usize = 64;
/// Seconds between saves while turns are taken; the last turn's is written once they stop.
const GAP_S: f32 = 1;

const Seed = @FieldType(game.Game, "seed");
const Node = @FieldType(game.Game, "node");
const Visited = @FieldType(game.Game, "visited");
/// What follows the visited nodes, in this order: the node being played and the run round it.
const TAIL_FIELDS = .{ "lv", "pool", "hero", "rng", "kills", "gold", "log", "bar", "facing", "name", "clock" };
const TAIL_TYPES = blk: {
    var ts: [TAIL_FIELDS.len]type = undefined;
    for (TAIL_FIELDS, 0..) |f, i| ts[i] = @FieldType(game.Game, f);
    break :blk ts;
};
const TAIL = blk: {
    var n: usize = 0;
    for (TAIL_TYPES) |T| n += @sizeOf(T);
    break :blk n;
};

/// What the slot list shows of a run, read without the rest of it.
pub const Summary = struct {
    name: hero.Name,
    hp: i32,
    max: i32,
    gold: i32,
    /// Null on a generated floor.
    node: ?usize,
    place: [atlas.NAME_MAX]u8 = undefined,
    place_n: usize = 0,

    pub fn line(self: *const Summary, buf: []u8) [:0]const u8 {
        var at: [atlas.TITLE_MAX]u8 = undefined;
        const where = if (self.node) |n| atlas.titleOf(self.place[0..self.place_n], n, &at) else "a generated floor";
        return std.fmt.bufPrintZ(buf, "{s}" ++ menu.SEP ++ "HP {d}/{d}" ++ menu.SEP ++ "Gold {d}" ++ menu.SEP ++ "{s}", .{ self.name.text(), @max(0, self.hp), self.max, self.gold, where }) catch "";
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

const FINGERPRINT = store.fingerprint([_]type{ Summary, Seed, bool, atlas.Atlas, Node, Visited, game.Visit } ++ TAIL_TYPES);
const HEAD = MAGIC.len + @sizeOf(u64);
/// The payload's hash ends the file, so a file damaged or cut short is refused before any of it is believed.
const SUM = @sizeOf(u64);


pub const Error = error{ NotASave, OtherBuild, Short, Damaged };

fn summaryOf(g: *game.Game) Summary {
    const i = actor.Pool.slot(g.hero);
    const h = g.pool.items[i];
    var s = Summary{ .name = g.name, .hp = h.hp, .max = h.max, .gold = g.gold, .node = null };
    if (g.world) |w| {
        s.node = g.node;
        const nm = w.node[g.node].name();
        @memcpy(s.place[0..nm.len], nm);
        s.place_n = nm.len;
    }
    return s;
}

fn write(g: *game.Game, out: *std.ArrayList(u8)) !void {
    const from = out.items.len;
    const w = out.writer();
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
    inline for (TAIL_FIELDS) |f| try store.put(w, &@field(g, f));
    try store.put(w, &std.hash.Wyhash.hash(0, out.items[from + HEAD ..]));
}

fn header(bytes: *[]const u8) Error!void {
    if (bytes.len < HEAD or !std.mem.eql(u8, bytes.*[0..MAGIC.len], MAGIC)) return error.NotASave;
    var b = bytes.*[MAGIC.len..];
    var print: u64 = undefined;
    _ = store.take(&b, &print);
    if (print != FINGERPRINT) return error.OtherBuild;
    bytes.* = b;
}

fn peek(bytes: []const u8) Error!Summary {
    var b = bytes;
    try header(&b);
    var s: Summary = undefined;
    if (!store.take(&b, &s)) return error.Short;
    if (s.name.n > hero.Name.MAX or s.place_n > atlas.NAME_MAX) return error.Damaged;
    if (!atlas.plain(s.name.text()) or !atlas.plain(s.place[0..s.place_n])) return error.Damaged;
    if (s.node) |n| {
        if (n >= atlas.MAX_NODES) return error.Damaged;
    }
    return s;
}

/// All of it is measured before any of it reaches `g`, so a file that does not read leaves the game as it was.
fn read(bytes: []const u8, g: *game.Game, world: *atlas.Atlas) Error!void {
    var b = bytes;
    try header(&b);
    if (b.len < SUM) return error.Short;
    var tail = b[b.len - SUM ..];
    var sum: u64 = undefined;
    _ = store.take(&tail, &sum);
    b = b[0 .. b.len - SUM];
    if (sum != std.hash.Wyhash.hash(0, b)) return error.Damaged;
    var s: Summary = undefined;
    var seed: Seed = undefined;
    var has_world: bool = undefined;
    if (!store.take(&b, &s) or !store.take(&b, &seed) or !store.take(&b, &has_world)) return error.Short;
    const at_visited = @as(usize, if (has_world) @sizeOf(atlas.Atlas) else 0) + @sizeOf(Node);
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
    inline for (TAIL_FIELDS) |f| _ = store.take(&b, &@field(g, f));
    game.resumeRun(g);
}

/// The slot as the player and its file name count it.
pub fn number(slot: usize) usize {
    return slot + 1;
}

fn path(buf: []u8, slot: usize) []const u8 {
    return std.fmt.bufPrint(buf, DIR ++ "/slot{d}" ++ EXT, .{number(slot)}) catch unreachable;
}

fn writeFile(bytes: []const u8, slot: usize) !void {
    var buf: [PATH_MAX]u8 = undefined;
    try store.replace(path(&buf, slot), bytes);
}

pub fn load(alloc: std.mem.Allocator, slot: usize, g: *game.Game, world: *atlas.Atlas) !void {
    var buf: [PATH_MAX]u8 = undefined;
    const bytes = try std.fs.cwd().readFileAlloc(alloc, path(&buf, slot), FILE_CAP);
    defer alloc.free(bytes);
    try read(bytes, g, world);
}

pub fn remove(slot: usize) !void {
    var buf: [PATH_MAX]u8 = undefined;
    std.fs.cwd().deleteFile(path(&buf, slot)) catch |e| if (e != error.FileNotFound) return e;
}

pub fn slots() [SLOTS]Slot {
    var out: [SLOTS]Slot = undefined;
    for (&out, 0..) |*s, i| s.* = slotAt(i);
    return out;
}

fn slotAt(i: usize) Slot {
    var buf: [PATH_MAX]u8 = undefined;
    var f = std.fs.cwd().openFile(path(&buf, i), .{}) catch |e| return if (e == error.FileNotFound) .empty else .{ .unreadable = .damaged };
    defer f.close();
    var head: [HEAD + @sizeOf(Summary)]u8 = undefined;
    const n = f.readAll(&head) catch return .{ .unreadable = .damaged };
    const s = peek(head[0..n]) catch |e| return .{ .unreadable = if (e == error.OtherBuild) .other_build else .damaged };
    return .{ .run = s };
}

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

    /// The run's last write on disk, and why it did not write if it did not.
    pub fn close(self: *Autosave, g: *game.Game) ?anyerror {
        self.flush(g);
        self.deinit();
        return self.failed;
    }

    /// Not mid-door, nor mid-turn: a foe's turn to face the archer is only in `facing` once it is drawn.
    pub fn step(self: *Autosave, g: *game.Game, dt: f32) void {
        self.since += dt;
        if (!g.unsaved or self.since < GAP_S or g.travel != null or !game.quiet(g)) return;
        self.flush(g);
    }

    /// A write that failed is written again.
    pub fn flush(self: *Autosave, g: *game.Game) void {
        self.wait();
        if (self.failed) |e| {
            g.log.say("The last save did not write ({s}).", .{@errorName(e)});
            self.failed = null;
            g.unsaved = true;
        }
        if (!g.unsaved) return;
        self.bytes.clearRetainingCapacity();
        self.since = 0;
        write(g, &self.bytes) catch |e| {
            self.failed = e;
            return;
        };
        g.unsaved = false;
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

    /// The run is lost, and its save with it: a slot that will not delete is emptied of a run that would load.
    pub fn end(self: *Autosave, g: *game.Game) void {
        self.wait();
        remove(self.slot) catch |e| {
            writeFile("", self.slot) catch g.log.say("The save did not delete ({s}).", .{@errorName(e)});
        };
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
    try write(g, &buf);
    std.debug.print("a run of two nodes, one left behind: {d} KB saved\n", .{buf.items.len / 1024});

    const back = try game.boot(alloc);
    defer game.shut(alloc, back);
    const into = try alloc.create(atlas.Atlas);
    defer alloc.destroy(into);
    game.begin(back, 1);
    try std.testing.expectError(error.Damaged, read(buf.items[0 .. buf.items.len - 1], back, into));
    try std.testing.expectError(error.NotASave, read("not a save", back, into));
    buf.items[buf.items.len / 2] +%= 1;
    try std.testing.expectError(error.Damaged, read(buf.items, back, into));
    buf.items[buf.items.len / 2] -%= 1;
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
    const s = try peek(buf.items);
    var line: [128]u8 = undefined;
    try std.testing.expectEqualStrings("Arwen" ++ menu.SEP ++ "HP 19/24" ++ menu.SEP ++ "Gold 17" ++ menu.SEP ++ "The Warrens", s.line(&line));
    const far: ?usize = atlas.MAX_NODES;
    const at = HEAD + @offsetOf(Summary, "node");
    @memcpy(buf.items[at..][0..@sizeOf(?usize)], std.mem.asBytes(&far));
    try std.testing.expectError(error.Damaged, peek(buf.items));
}
