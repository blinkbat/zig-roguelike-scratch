const std = @import("std");
const heroes = @import("hero.zig");
const obituary = @import("obituary.zig");
const store = @import("../core/store.zig");
const wire = @import("../core/wire.zig");

/// Said at the end of a death report whose hero is entombed.
pub const ENTOMBED = "The hero's remains were entombed in the Revered Ossuary.";
const BURIED = " " ++ ENTOMBED;
pub const MAX: usize = 20;
pub const SUMMARY_MAX: usize = obituary.REPORT_MAX + BURIED.len;

/// One hero's bones: who they were and how they died.
pub const Entry = struct {
    name: heroes.Name,
    class: heroes.Class,
    level: u16,
    kills: u32,
    gold: i32,
    renown: u32,
    seed: u64,
    summary: [SUMMARY_MAX]u8 = @splat(0),
    summary_n: u16 = 0,

    pub fn text(self: *const Entry) []const u8 {
        return self.summary[0..self.summary_n];
    }

    pub fn say(self: *Entry, s: []const u8) void {
        const n = @min(s.len, SUMMARY_MAX);
        @memcpy(self.summary[0..n], s[0..n]);
        self.summary_n = @intCast(n);
    }

    pub fn sayEntombed(self: *Entry) void {
        const n = @min(self.summary_n, SUMMARY_MAX - BURIED.len);
        @memcpy(self.summary[n..][0..BURIED.len], BURIED);
        self.summary_n = @intCast(n + BURIED.len);
    }
};

/// What a run did that history counts.
pub const Deeds = struct { kills: usize, level: u16, gold: i32, places: usize };

const RENOWN_PER_KILL: u32 = 10;
const RENOWN_PER_LEVEL: u32 = 100;
const RENOWN_PER_PLACE: u32 = 25;
const GOLD_PER_RENOWN: u32 = 5;

pub fn renown(d: Deeds) u32 {
    const kills: u32 = @intCast(@min(d.kills, std.math.maxInt(u32) / RENOWN_PER_KILL / 4));
    const places: u32 = @intCast(@min(d.places, std.math.maxInt(u32) / RENOWN_PER_PLACE / 4));
    const gold: u32 = @intCast(@max(0, d.gold));
    return kills * RENOWN_PER_KILL +| (@as(u32, d.level) -| 1) * RENOWN_PER_LEVEL +| places * RENOWN_PER_PLACE +| gold / GOLD_PER_RENOWN;
}

test "renown counts kills, levels past the first, places and gold" {
    try std.testing.expectEqual(@as(u32, 25), renown(.{ .kills = 0, .level = 1, .gold = 4, .places = 1 }));
    try std.testing.expectEqual(@as(u32, 230 + 300 + 75 + 28), renown(.{ .kills = 23, .level = 4, .gold = 140, .places = 3 }));
}

/// The `MAX` most renowned deaths, most renowned first; a tie keeps the earlier death above.
pub const Hall = struct {
    entries: [MAX]Entry = undefined,
    n: usize = 0,
    /// Changed since it was last written.
    dirty: bool = false,

    pub fn slice(self: *const Hall) []const Entry {
        return self.entries[0..self.n];
    }

    pub fn qualifies(self: *const Hall, worth: u32) bool {
        return self.n < MAX or worth > self.entries[MAX - 1].renown;
    }

    /// Where it now lies, or null when it falls short.
    pub fn entomb(self: *Hall, e: Entry) ?usize {
        if (!self.qualifies(e.renown)) return null;
        var at: usize = 0;
        while (at < self.n and self.entries[at].renown >= e.renown) at += 1;
        const n = @min(self.n + 1, MAX);
        var i = n - 1;
        while (i > at) : (i -= 1) self.entries[i] = self.entries[i - 1];
        self.entries[at] = e;
        self.n = n;
        self.dirty = true;
        return at;
    }
};

pub const PATH = store.DIR ++ "/ossuary.bones";
pub const NOT_WRITTEN = "The Revered Ossuary did not write ({s})";
pub const NOT_READ = "The Revered Ossuary could not be read ({s}); no hero will be entombed";
const OLD_MAGIC = "cistern-ossuary\n";
const MAGIC = "cistern-ossuary-v1\n";
const VERSION = 1;
const Count = u8;
const PRINT = store.legacy.fingerprint(.{ Count, Entry });
const HEAD = store.head(MAGIC);
const Bones = struct { entries: [MAX]Entry = undefined, n: usize = 0 };
pub const FILE_MAX = HEAD + wire.maxSize(Bones) + store.SUM;
const Code = wire.Codec(struct {
    pub fn countField(comptime T: type, comptime field: []const u8) ?[]const u8 {
        const COUNT_FIELDS = .{
            .{ Bones, "entries", "n" },
            .{ heroes.Name, "buf", "n" },
            .{ Entry, "summary", "summary_n" },
        };
        inline for (COUNT_FIELDS) |entry| {
            if (T == entry[0] and std.mem.eql(u8, field, entry[1])) return entry[2];
        }
        return null;
    }
});
const ClassRaw = std.meta.Int(.unsigned, 8 * @sizeOf(heroes.Class));

comptime {
    std.debug.assert(MAX <= std.math.maxInt(Count));
}

pub const Error = error{ NotOssuary, OtherBuild, Short, Damaged };

pub fn encode(hall: *const Hall, buf: *[FILE_MAX]u8) []const u8 {
    var allocator = std.heap.FixedBufferAllocator.init(buf);
    var out = std.ArrayList(u8).initCapacity(allocator.allocator(), FILE_MAX) catch unreachable;
    store.begin(out.writer(), MAGIC, VERSION) catch unreachable;
    const bones = Bones{ .entries = hall.entries, .n = hall.n };
    Code.write(&out, &bones) catch unreachable;
    store.seal(out.writer(), out.items[HEAD..]) catch unreachable;
    return out.items;
}

pub fn decode(bytes: []const u8) Error!Hall {
    if (std.mem.startsWith(u8, bytes, OLD_MAGIC)) return decodeLegacy(bytes);
    const body = store.open(bytes, MAGIC, VERSION) catch |e| return switch (e) {
        error.Foreign => error.NotOssuary,
        else => |other| other,
    };
    var bones: Bones = undefined;
    try Code.read(body, &bones);
    const hall = Hall{ .entries = bones.entries, .n = bones.n };
    try validate(&hall);
    return hall;
}

fn validate(hall: *const Hall) Error!void {
    for (hall.slice(), 0..) |*entry, index| {
        if (!entry.name.valid() or entry.summary_n > SUMMARY_MAX or entry.level == 0 or entry.gold < 0) return error.Damaged;
        if (index > 0 and hall.entries[index - 1].renown < entry.renown) return error.Damaged;
    }
}

fn decodeLegacy(bytes: []const u8) Error!Hall {
    var b = store.open(bytes, OLD_MAGIC, PRINT) catch |e| return switch (e) {
        error.Foreign => error.NotOssuary,
        else => |other| other,
    };
    var n: Count = undefined;
    if (!store.legacy.take(&b, &n)) return error.Short;
    if (n > MAX) return error.Damaged;
    if (b.len != @as(usize, n) * @sizeOf(Entry)) return error.Short;
    var hall = Hall{ .n = n, .dirty = true };
    for (hall.entries[0..n], 0..) |*e, i| {
        const class = std.mem.bytesToValue(ClassRaw, b[@offsetOf(Entry, "class")..][0..@sizeOf(ClassRaw)]);
        _ = std.meta.intToEnum(heroes.Class, class) catch return error.Damaged;
        _ = store.legacy.take(&b, e);
        if (!e.name.valid() or e.summary_n > SUMMARY_MAX) return error.Damaged;
        if (i > 0 and hall.entries[i - 1].renown < e.renown) return error.Damaged;
    }
    try validate(&hall);
    return hall;
}

/// Empty when there is no file yet.
pub fn load() !Hall {
    var buf: [FILE_MAX + 1]u8 = undefined;
    const bytes = std.fs.cwd().readFile(PATH, &buf) catch |e| return if (e == error.FileNotFound) .{} else e;
    return decode(bytes);
}

pub fn write(hall: *Hall) !void {
    var buf: [FILE_MAX]u8 = undefined;
    try store.replace(PATH, encode(hall, &buf));
    hall.dirty = false;
}

fn testEntry(worth: u32) Entry {
    return .{ .name = heroes.Name.of("Bones"), .class = .knight, .level = 1, .kills = 0, .gold = 0, .renown = worth, .seed = worth };
}

test "legacy ossuary converts records and marks them for a portable rewrite" {
    var old = std.ArrayList(u8).init(std.testing.allocator);
    defer old.deinit();
    try store.begin(old.writer(), OLD_MAGIC, PRINT);
    try store.legacy.put(old.writer(), &@as(Count, 1));
    var entry = testEntry(123);
    entry.say("A remembered hero.");
    try store.legacy.put(old.writer(), &entry);
    try store.seal(old.writer(), old.items[store.head(OLD_MAGIC)..]);
    const recovered = try decode(old.items);
    try std.testing.expect(recovered.dirty);
    try std.testing.expectEqualStrings(entry.text(), recovered.entries[0].text());
    var bytes: [FILE_MAX]u8 = undefined;
    const portable = encode(&recovered, &bytes);
    try std.testing.expect(std.mem.startsWith(u8, portable, MAGIC));
    try std.testing.expectEqual(entry.renown, (try decode(portable)).entries[0].renown);
    std.debug.print("legacy ossuary: name, report and renown survive conversion and canonical rewrite\n", .{});
}
test "the ossuary keeps the most renowned deaths, earlier first on a tie, and refuses the rest once full" {
    var h = Hall{};
    for (0..MAX) |i| try std.testing.expect(h.entomb(testEntry(@intCast(i % 7))) != null);
    try std.testing.expectEqual(MAX, h.n);
    for (h.slice()[0 .. MAX - 1], h.slice()[1..]) |a, b| try std.testing.expect(a.renown >= b.renown);
    try std.testing.expect(!h.qualifies(0));
    try std.testing.expectEqual(@as(?usize, null), h.entomb(testEntry(0)));
    const first_six = h.entries[0].seed;
    try std.testing.expectEqual(@as(?usize, 2), h.entomb(testEntry(6)));
    try std.testing.expectEqual(first_six, h.entries[0].seed);
    try std.testing.expectEqual(@as(u32, 0), h.entries[MAX - 1].renown);
    var e = testEntry(9);
    e.say("A long story. " ++ ENTOMBED);
    try std.testing.expectEqual(@as(?usize, 0), h.entomb(e));
    try std.testing.expect(std.mem.endsWith(u8, h.entries[0].text(), ENTOMBED));
    std.debug.print("ossuary: {d} kept, lowest renown {d}, a tie entombed below its elders\n", .{ h.n, h.entries[MAX - 1].renown });
}

test "the ossuary file round-trips, and a damaged, cut, foreign or reordered one is refused" {
    var h = Hall{};
    for (0..5) |i| {
        var e = testEntry(@intCast(10 * i));
        e.class = @enumFromInt(i % 3);
        e.say("Slain by a rat. " ++ ENTOMBED);
        _ = h.entomb(e);
    }
    var buf: [FILE_MAX]u8 = undefined;
    const bytes = encode(&h, &buf);
    const back = try decode(bytes);
    try std.testing.expectEqual(h.n, back.n);
    for (h.slice(), back.slice()) |a, b| {
        try std.testing.expectEqualStrings(a.name.text(), b.name.text());
        try std.testing.expectEqual(a.class, b.class);
        try std.testing.expectEqual(a.renown, b.renown);
        try std.testing.expectEqualStrings(a.text(), b.text());
    }
    try std.testing.expect(!back.dirty);
    const empty = try decode(encode(&Hall{}, &buf));
    try std.testing.expectEqual(@as(usize, 0), empty.n);
    var copy: [FILE_MAX]u8 = undefined;
    const fresh = encode(&h, &buf);
    @memcpy(copy[0..fresh.len], fresh);
    copy[HEAD + 3] ^= 0x40;
    try std.testing.expectError(error.Damaged, decode(copy[0..fresh.len]));
    try std.testing.expectError(error.Damaged, decode(fresh[0 .. fresh.len - 1]));
    try std.testing.expectError(error.NotOssuary, decode("roguelike-save\n"));
    try std.testing.expectError(error.NotOssuary, decode(""));
    @memcpy(copy[0..fresh.len], fresh);
    copy[MAGIC.len] ^= 1;
    try std.testing.expectError(error.OtherBuild, decode(copy[0..fresh.len]));
    var swapped = h;
    std.mem.swap(Entry, &swapped.entries[0], &swapped.entries[1]);
    try std.testing.expectError(error.Damaged, decode(encode(&swapped, &buf)));
    var odd = h;
    odd.entries[0].name.buf[0] = '!';
    try std.testing.expectError(error.Damaged, decode(encode(&odd, &buf)));
    std.debug.print("ossuary file: {d} bones in {d} bytes round-trip; 6 bad files refused\n", .{ h.n, bytes.len });
}
