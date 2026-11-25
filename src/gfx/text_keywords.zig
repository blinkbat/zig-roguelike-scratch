const std = @import("std");
const rl = @import("raylib");
const look = @import("look.zig");
const sky = @import("sky.zig");
const wording = @import("../core/wording.zig");
const resilience = @import("../play/resilience.zig");
const damage = @import("../play/damage.zig");

pub const Tone = enum {
    physical,
    mental,
    fire,
    cold,
    lightning,

    fn ink(tone: Tone) rl.Color {
        return switch (tone) {
            .physical => look.KEYWORD_PHYSICAL,
            .mental => look.KEYWORD_MENTAL,
            inline .fire, .cold, .lightning => |t| look.elementInk(@field(damage.Element, @tagName(t))),
        };
    }

    pub fn on(tone: Tone, base: rl.Color) rl.Color {
        if (look.sameRgb(base, look.LOSS)) return base;
        const hue = tone.ink();
        const target = luminance(base) * LUMA_SHARE;
        const light = luminance(hue);
        var out = if (target > light)
            look.mixed(hue, rl.Color.white, (target - light) / (255 - light))
        else
            look.mixed(rl.Color.black, hue, target / @max(light, 1));
        out.a = base.a;
        return out;
    }
};

const LUMA_SHARE: f32 = 0.94;

fn luminance(c: rl.Color) f32 {
    return sky.luma(.{ @floatFromInt(c.r), @floatFromInt(c.g), @floatFromInt(c.b) });
}

const Group = struct { tone: Tone, words: []const u8 };
const GROUPS = [_]Group{
    .{ .tone = .physical, .words = "physical|damage|armour|armor|bleeds|bleeding|bled|wound|wounds|stunned|stunning|pinned|pinning|sundered|sundering|maimed|maiming|enfeebled|enfeeblement|weapon damage|physical damage reduction|critical damage|critical strike damage|critical damage multiplier" },
    .{ .tone = .mental, .words = "mental|blinded|blindness|confused|confuse|frightened|fear" },
    .{ .tone = .fire, .words = "burns|burning|burned|ignite|ignites|ignited|igniting|ignition" },
    .{ .tone = .cold, .words = "freeze|freezes|freezing|frozen|chills|chilled|chilling" },
    .{ .tone = .lightning, .words = "shocks|shocked|shocking" },
};

const Entry = struct { word: []const u8, tone: Tone };
const ENTRIES = blk: {
    @setEvalBranchQuota(100_000);
    var result: []const Entry = &.{};
    for (GROUPS) |group| {
        var words = std.mem.splitScalar(u8, group.words, '|');
        while (words.next()) |word| result = result ++ [_]Entry{.{ .word = word, .tone = group.tone }};
    }
    for (std.enums.values(resilience.Kind)) |value| {
        const tone: Tone = switch (resilience.primaryTag(value)) {
            .wounds, .slows => .physical,
            .mental => .mental,
            .elemental => switch (value) {
                .burn => .fire,
                .chill => .cold,
                .shock => .lightning,
                else => @compileError("Missing elemental tone for " ++ @tagName(value)),
            },
        };
        result = result ++ [_]Entry{.{ .word = wording.named(value), .tone = tone }};
    }
    for (std.enums.values(damage.Element)) |value| {
        const tone: Tone = if (value == .chaos) .mental else @field(Tone, @tagName(value));
        result = result ++ [_]Entry{.{ .word = wording.named(value), .tone = tone }};
    }
    break :blk result;
};

const BY_INITIAL = blk: {
    @setEvalBranchQuota(100_000);
    var result: [26][]const Entry = @splat(&.{});
    for (ENTRIES) |entry| {
        const first = std.ascii.toLower(entry.word[0]);
        if (first >= 'a' and first <= 'z') result[first - 'a'] = result[first - 'a'] ++ [_]Entry{entry};
    }
    break :blk result;
};

const Match = struct { end: usize, tone: Tone };

pub fn wordByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c >= 128;
}

fn phrase(body: []const u8, from: usize, word: []const u8) ?usize {
    var at = from;
    for (word) |c| {
        if (at == body.len) return null;
        if (c == ' ') {
            if (!std.ascii.isWhitespace(body[at])) return null;
            while (at < body.len and std.ascii.isWhitespace(body[at])) : (at += 1) {}
        } else {
            if (std.ascii.toLower(body[at]) != std.ascii.toLower(c)) return null;
            at += 1;
        }
    }
    if (at < body.len and wordByte(body[at])) return null;
    return at;
}

fn match(body: []const u8, from: usize) ?Match {
    if (from >= body.len or (from > 0 and wordByte(body[from - 1]))) return null;
    const initial = std.ascii.toLower(body[from]);
    if (initial < 'a' or initial > 'z') return null;
    var best: ?Match = null;
    for (BY_INITIAL[initial - 'a']) |entry| {
        const end = phrase(body, from, entry.word) orelse continue;
        if (best == null or end > best.?.end) best = .{ .end = end, .tone = entry.tone };
    }
    var found = best orelse return null;
    for ([_][]const u8{ " resistance", " resistances", " damage", " damage bonus" }) |suffix| {
        if (phrase(body, found.end, suffix)) |end| best.?.end = @max(best.?.end, end);
    }
    found.end = best.?.end;
    return found;
}

pub const Flow = struct {
    body: []const u8,
    offset: usize = 0,
    active: ?Match = null,

    pub fn next(self: *Flow, c: u8) ?Tone {
        if (!std.ascii.isWhitespace(c)) {
            while (self.offset < self.body.len and std.ascii.isWhitespace(self.body[self.offset])) : (self.offset += 1) {}
        }
        if (self.offset >= self.body.len) return null;
        if (self.active == null or self.offset >= self.active.?.end) self.active = match(self.body, self.offset);
        self.offset += 1;
        return if (self.active) |active| active.tone else null;
    }

    pub fn skip(self: *Flow, line: []const u8) void {
        for (line) |c| _ = self.next(c);
    }
};

test "keyword phrases use longest whole words and consistent inflections" {
    try std.testing.expectEqual(Tone.fire, match("FIRE Resistance", 0).?.tone);
    try std.testing.expectEqual(@as(usize, 15), match("FIRE Resistance", 0).?.end);
    try std.testing.expectEqual(Tone.physical, match("Physical damage reduction", 0).?.tone);
    try std.testing.expectEqual(Tone.physical, match("Critical damage multiplier", 0).?.tone);
    for ([_][]const u8{ "ignition", "Ignited", "igniting" }) |word| try std.testing.expectEqual(Tone.fire, match(word, 0).?.tone);
    for ([_][]const u8{ "freezing", "Frozen", "freeze" }) |word| try std.testing.expectEqual(Tone.cold, match(word, 0).?.tone);
    for ([_][]const u8{ "fireplace", "lifetime", "turnstone", "rangefinder", "bleeding_edge" }) |word| try std.testing.expect(match(word, 0) == null);
    try std.testing.expect(match("backfire", 4) == null);
    for ([_][]const u8{ "life", "mana", "strength", "cooldown", "turns", "range", "gold", "recovery", "projectiles", "duration", "resistance", "chance" }) |word| try std.testing.expect(match(word, 0) == null);
    try std.testing.expectEqual(Tone.physical, match("(bleeding).", 1).?.tone);
    inline for (.{ resilience.Kind, damage.Element }) |T| {
        inline for (comptime std.enums.values(T)) |value| try std.testing.expect(match(wording.named(value), 0) != null);
    }
}

test "keyword flow keeps phrase colors through wrapping collapsed spaces and scrolling" {
    var flow = Flow{ .body = "Take fire   resistance\nand bleeding damage." };
    flow.skip("Take fire");
    for ("resistance") |c| try std.testing.expectEqual(Tone.fire, flow.next(c).?);
    flow.skip("and ");
    for ("bleeding damage") |c| try std.testing.expectEqual(Tone.physical, flow.next(c).?);
    try std.testing.expect(flow.next('.') == null);
}

test "keyword flow follows tooltip columns blank lines separators and UTF8 boundaries" {
    var flow = Flow{ .body = "Fire resistance\t25%\n\n---\nBleeding damage\t3\nFrozen" };
    for ("Fire resistance") |c| try std.testing.expectEqual(Tone.fire, flow.next(c).?);
    flow.skip("\t25%---");
    for ("Bleeding damage") |c| try std.testing.expectEqual(Tone.physical, flow.next(c).?);
    flow.skip("\t3");
    for ("Frozen") |c| try std.testing.expectEqual(Tone.cold, flow.next(c).?);
    try std.testing.expect(match("\xc3\xa9fire", 2) == null);
    try std.testing.expect(match("fire\xc3\xa9", 0) == null);
}

test "keyword colors preserve paragraph brightness opacity and blockers" {
    for (std.enums.values(Tone)) |tone| {
        for ([_]rl.Color{ look.TEXT, look.DIM, look.UI_FOCUS, look.MAGIC, look.fade(look.DIM, 0.3) }) |base| {
            const col = tone.on(base);
            try std.testing.expectEqual(base.a, col.a);
            try std.testing.expectApproxEqAbs(luminance(base) * LUMA_SHARE, luminance(col), 1.1);
        }
        try std.testing.expectEqual(look.LOSS, tone.on(look.LOSS));
    }
}
