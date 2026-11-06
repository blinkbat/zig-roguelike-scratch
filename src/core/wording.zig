const std = @import("std");

const ASSET = "player-labels.txt";
pub const FILE = "assets/data/" ++ ASSET;
const Case = enum { sentence, title, word };
const Registration = struct { name: []const u8, saved_name: ?[]const u8 = null, casing: Case = .sentence, except: []const []const u8 = &.{}, only: ?[]const []const u8 = null };
pub const TYPES = [_]Registration{
    .{ .name = "app.MainRow", .except = &.{"ossuary"} },
    .{ .name = "app.OptionRow" },
    .{ .name = "game.PauseRow", .only = &.{ "debug", "quit" } },
    .{ .name = "game.debug.Page", .except = &.{"main"} },
    .{ .name = "game.debug.Row", .casing = .title, .except = &.{ "vsync", "frame_limit" } },
    .{ .name = "play.hero.Class" },
    .{ .name = "play.skillbar.Act", .casing = .title, .except = &.{"secondary"} },
    .{ .name = "play.items.Kind" },
    .{ .name = "play.attrs.Attr" },
    .{ .name = "play.damage.Element" },
    .{ .name = "play.resilience.Kind" },
    .{ .name = "play.flask.Kind", .casing = .word },
    .{ .name = "play.consumable.Kind" },
    .{ .name = "play.actor.FoeType" },
    .{ .name = "play.actor.Movement" },
    .{ .name = "ui.character_view.Page", .saved_name = "ui.book.Page" },
    .{ .name = "ui.trees.SkillState" },
    .{ .name = "edit.editor.View" },
    .{ .name = "edit.tool_catalog.Family" },
    .{ .name = "edit.editor.Inspect" },
    .{ .name = "map.grid.Tile" },
};

fn registration(name: []const u8) ?Registration {
    for (TYPES) |row| {
        if (std.mem.eql(u8, row.name, name) or std.mem.eql(u8, row.saved_name orelse row.name, name)) return row;
    }
    return null;
}

fn savedName(name: []const u8) []const u8 {
    return if (registration(name)) |row| row.saved_name orelse row.name else name;
}

fn contains(values: []const []const u8, value: []const u8) bool {
    for (values) |v| if (std.mem.eql(u8, v, value)) return true;
    return false;
}

pub fn allowed(name: []const u8, field: []const u8) bool {
    const row = registration(name) orelse return false;
    if (row.only) |fields| return contains(fields, field);
    return !contains(row.except, field);
}

pub fn casing(name: []const u8) Case {
    return if (registration(name)) |row| row.casing else .sentence;
}

pub fn format(bytes: []u8, style: Case) void {
    if (style == .word) return;
    var initial = true;
    for (bytes) |*c| {
        const boundary = c.* == '_';
        if (boundary) c.* = ' ' else if (initial) c.* = std.ascii.toUpper(c.*);
        initial = style == .title and boundary;
    }
}

pub fn keyAlloc(alloc: std.mem.Allocator, name: []const u8, field: []const u8) ![]u8 {
    return std.fmt.allocPrint(alloc, "{s}.{s}", .{ savedName(name), field });
}

pub const Record = struct { key: []const u8, text: []const u8 };

pub fn parse(raw: []const u8) ?Record {
    const line = std.mem.trimRight(u8, raw, "\r");
    const tab = std.mem.indexOfScalar(u8, line, '\t') orelse return null;
    return .{ .key = line[0..tab], .text = line[tab + 1 ..] };
}

pub fn lookup(labels: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, labels, '\n');
    while (lines.next()) |raw| {
        const record = parse(raw) orelse continue;
        if (std.mem.eql(u8, record.key, key)) return record.text;
    }
    return null;
}

pub fn replace(alloc: std.mem.Allocator, labels: []const u8, key: []const u8, text: []const u8) ![]u8 {
    var output = std.ArrayList(u8).init(alloc);
    errdefer output.deinit();
    var lines = std.mem.splitScalar(u8, labels, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (parse(line)) |record| if (std.mem.eql(u8, record.key, key)) continue;
        try output.appendSlice(line);
        try output.append('\n');
    }
    try output.writer().print("{s}\t{s}\n", .{ key, text });
    return output.toOwnedSlice();
}

fn formatted(comptime text: [:0]const u8, comptime style: Case) [:0]const u8 {
    comptime var bytes: [text.len:0]u8 = text[0..text.len].*;
    comptime format(&bytes, style);
    const out = bytes;
    return &out;
}

pub fn spoken(comptime text: [:0]const u8) [:0]const u8 {
    return formatted(text, .sentence);
}

fn titled(comptime text: [:0]const u8) [:0]const u8 {
    return formatted(text, .title);
}

const Recase = enum { title, lower };
/// Words a title leaves lower case past its first.
const MINOR_WORDS = [_][]const u8{ "of", "the", "and", "a", "an" };

/// Recases `text` in place when it lies in `buf`; a fallback literal is returned as it is.
pub fn recased(buf: []u8, text: [:0]const u8, how: Recase) [:0]const u8 {
    const at = @intFromPtr(text.ptr);
    if (at < @intFromPtr(buf.ptr) or at + text.len > @intFromPtr(buf.ptr) + buf.len) return text;
    const bytes = buf[at - @intFromPtr(buf.ptr) ..][0..text.len];
    var start: usize = 0;
    while (start < bytes.len) {
        const end = std.mem.indexOfScalarPos(u8, bytes, start, ' ') orelse bytes.len;
        const w = bytes[start..end];
        switch (how) {
            .lower => for (w) |*c| {
                c.* = std.ascii.toLower(c.*);
            },
            .title => {
                const minor = start > 0 and for (MINOR_WORDS) |m| {
                    if (std.ascii.eqlIgnoreCase(w, m)) break true;
                } else false;
                if (w.len > 0) w[0] = if (minor) std.ascii.toLower(w[0]) else std.ascii.toUpper(w[0]);
            },
        }
        start = end + 1;
    }
    return text;
}

pub fn displayAliasIn(comptime labels: []const u8, comptime name: []const u8, comptime tag: []const u8) ?[:0]const u8 {
    @setEvalBranchQuota(100_000);
    const value = lookup(labels, savedName(name) ++ "." ++ tag) orelse return null;
    return std.fmt.comptimePrint("{s}", .{value});
}

fn displayAlias(comptime name: []const u8, comptime tag: []const u8) ?[:0]const u8 {
    return displayAliasIn(@embedFile(ASSET), name, tag);
}

fn aliasOr(e: anytype, comptime style: Case) [:0]const u8 {
    return switch (e) {
        inline else => |t| comptime displayAlias(@typeName(@TypeOf(e)), @tagName(t)) orelse formatted(@tagName(t), style),
    };
}

pub fn named(e: anytype) [:0]const u8 {
    return aliasOr(e, .sentence);
}

pub fn namedOr(e: anytype, fallback: [:0]const u8) [:0]const u8 {
    return switch (e) {
        inline else => |t| (comptime displayAlias(@typeName(@TypeOf(e)), @tagName(t))) orelse fallback,
    };
}

pub fn titleOf(e: anytype) [:0]const u8 {
    return aliasOr(e, .title);
}

pub fn word(e: anytype) [:0]const u8 {
    return aliasOr(e, .word);
}

test "wording aliases share record replacement lookup and display casing" {
    const a = std.testing.allocator;
    const key = try keyAlloc(a, "play.hero.Class", "archer");
    defer a.free(key);
    const bytes = try replace(a, "Other.field\tOther\r\nplay.hero.Class.archer\tOld\r\nplay.hero.Class.archer\tDuplicate\n", key, "Wayfarer");
    defer a.free(bytes);
    try std.testing.expectEqualStrings("Wayfarer", lookup(bytes, key).?);
    try std.testing.expectEqualStrings("Other", lookup(bytes, "Other.field").?);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, key));
    try std.testing.expectEqualStrings("Wayfarer", comptime displayAliasIn("play.hero.Class.archer\tWayfarer\r\n", "play.hero.Class", "archer").?);
    var label = "burning_arrow".*;
    format(&label, casing("play.skillbar.Act"));
    try std.testing.expectEqualStrings(titled("burning_arrow"), &label);
    try std.testing.expect(allowed("play.skillbar.Act", "shoot"));
    try std.testing.expect(!allowed("play.skillbar.Act", "secondary"));
    try std.testing.expect(allowed("game.PauseRow", "quit"));
    try std.testing.expect(!allowed("game.PauseRow", "resume"));
    try std.testing.expect(!allowed("internal.Kind", "any"));
    std.debug.print("wording aliases: shared CRLF codec, duplicate replacement, casing and display registration checked\n", .{});
}

test "a tag is titled word by word" {
    try std.testing.expectEqualStrings("Chain Lightning", comptime titled("chain_lightning"));
    try std.testing.expectEqualStrings("Fireball", comptime titled("fireball"));
}
