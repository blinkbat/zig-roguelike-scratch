const std = @import("std");
const mathx = @import("../core/mathx.zig");
const actor = @import("actor.zig");
const heroes = @import("hero.zig");
const chronicle = @import("chronicle.zig");
const skillbar = @import("skillbar.zig");
const Source = chronicle.Source;
const Turn = chronicle.Turn;
const Hurt = chronicle.Hurt;

/// The run as it stood when the hero died.
pub const Context = struct {
    name: []const u8,
    class: heroes.Class,
    killer: Hurt,
    /// Preposition first: "in the Warrens".
    place: []const u8,
    night: bool = false,
    level: u16,
    /// Experience still wanted for the next level, of `needed`.
    short: u64,
    needed: u64,
    points: u16 = 0,
    /// Foes beside the hero at the end, and cells a step could still have taken.
    beside: usize = 0,
    open: usize = 0,
    /// Oldest first; the last is the turn the hero died in.
    turns: []const Turn,
    milestone: ?chronicle.Milestone = null,

    fn last(self: *const Context) *const Turn {
        return &self.turns[self.turns.len - 1];
    }

    /// Turns from `turn` to the death.
    fn since(self: *const Context, turn: u32) u32 {
        return self.last().number - turn;
    }

    fn outnumbered(self: *const Context) bool {
        return self.beside >= OUTNUMBERED_AT;
    }

    fn cornered(self: *const Context) bool {
        return self.open == 0 and self.beside > 0;
    }

    /// The killing blow was the best its foe can roll.
    fn unlucky(self: *const Context) bool {
        return self.killer.best and self.killer.by == .foe;
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

pub const Contributor = struct {
    weight: f32,
    what: What,
};

pub const What = union(enum) {
    source: struct { by: Source, amount: i32 },
    stun: struct { by: actor.Kind, turn: u32 },
    starved,
    outnumbered,
    cornered,
    torn: i32,
    flask,
    ward,
    best_roll,
    missed: usize,
};

pub const Tag = enum {
    overkill,
    chip,
    one_shot,
    by_trash,
    own_goal,
    burst_beside,
    flask_unused,
    ward_unused,
    unspent,
    almost_levelled,
    just_levelled,
};
pub const Tags = std.EnumSet(Tag);

/// Every foe kind, and every other source.
const SOURCES_MAX = std.enums.values(actor.Kind).len + std.meta.fields(Source).len - 1;
/// A damage contributor per source, and at most one of each other kind of contributor.
const CONTRIBUTORS_MAX = SOURCES_MAX + std.meta.fields(What).len - 1;

/// Most contributors a report weighs.
pub const TOP: usize = 3;
pub const Top = struct {
    items: [TOP]Contributor = undefined,
    n: usize = 0,

    pub fn slice(self: *const Top) []const Contributor {
        return self.items[0..self.n];
    }
};

/// A stun's weight is this share of the damage taken from it on.
const ENABLER: f32 = 0.6;
const STARVED: f32 = 0.3;
const CORNERED: f32 = 0.3;
const PER_FOE_BESIDE: f32 = 0.1;
const OUTNUMBERED_AT: usize = 3;
const FLASK_UNUSED: f32 = 0.5;
const WARD_UNUSED: f32 = 0.3;
const LOW_SHARE: i32 = 2;
const BEST_ROLL: f32 = 0.15;
const PER_MISS: f32 = 0.05;
/// The killing blow did at least this much past the life left, and at least as much again.
const OVERKILL_MIN: i32 = 3;
const CHIP_HITS: usize = 5;
/// No chip hit took more than this share of full life.
const CHIP_SHARE: i32 = 6;
/// Foes this frail are beneath a hero of `TRASH_LEVEL`.
const TRASH_HP: i32 = 6;
const TRASH_LEVEL: u16 = 3;
/// Within this share of the next level.
const ALMOST_SHARE: u64 = 5;
const RECENT_MILESTONE: u32 = 10;

const Taken = struct { total: i32 = 0, hits: usize = 0, biggest: i32 = 0 };

fn taken(ctx: *const Context) Taken {
    var t = Taken{};
    for (ctx.turns) |*turn| for (turn.slice()) |e| switch (e) {
        .hurt => |h| if (h.dmg > 0) {
            t.total += h.dmg;
            t.hits += 1;
            t.biggest = @max(t.biggest, h.dmg);
        },
        else => {},
    };
    return t;
}

fn used(ctx: *const Context, from: usize, act: skillbar.Act) bool {
    for (ctx.turns[from..]) |*turn| for (turn.slice()) |e| {
        if (e == .used and e.used == act) return true;
    };
    return false;
}

fn hurtFrom(ctx: *const Context, from: usize) bool {
    for (ctx.turns[from..]) |*turn| {
        if (hurtIn(turn)) return true;
    }
    return false;
}

/// The first turn a ready defence went unused through harm to the end.
fn unused(ctx: *const Context, comptime field: std.meta.FieldEnum(chronicle.Start), act: skillbar.Act, comptime low: bool) bool {
    for (ctx.turns, 0..) |*turn, i| {
        const s = turn.start;
        if (!@field(s, @tagName(field)) or (low and s.hp * LOW_SHARE > s.max)) continue;
        if (!used(ctx, i, act) and hurtFrom(ctx, i)) return true;
    }
    return false;
}

/// What killed the hero, ranked: the top `TOP`, weights summing to 1.
pub fn contributors(ctx: *const Context) Top {
    var all: [CONTRIBUTORS_MAX]Contributor = undefined;
    var n: usize = 0;
    const t = taken(ctx);
    const total: f32 = @floatFromInt(@max(1, t.total));
    var sources: [SOURCES_MAX]Source = undefined;
    var ns: usize = 0;
    var torn: i32 = 0;
    var tore = false;
    var misses: usize = 0;
    var stun: ?struct { turn: usize, event: usize, by: actor.Kind } = null;
    for (ctx.turns, 0..) |*turn, ti| for (turn.slice(), 0..) |e, ei| switch (e) {
        .hurt => |h| {
            if (h.torn) {
                torn += h.dmg;
                tore = true;
            }
            for (sources[0..ns]) |s| {
                if (std.meta.eql(s, h.by)) break;
            } else {
                sources[ns] = h.by;
                ns += 1;
            }
        },
        .stunned => |k| if (stun == null) {
            stun = .{ .turn = ti, .event = ei, .by = k };
        },
        .missed => misses += 1,
        else => {},
    };
    for (sources[0..ns]) |s| {
        var sum: i32 = 0;
        for (ctx.turns) |*turn| for (turn.slice()) |e| {
            if (e == .hurt and std.meta.eql(e.hurt.by, s)) sum += e.hurt.dmg;
        };
        all[n] = .{ .weight = @as(f32, @floatFromInt(sum)) / total, .what = .{ .source = .{ .by = s, .amount = sum } } };
        n += 1;
    }
    if (stun) |s| {
        var after: i32 = 0;
        for (ctx.turns[s.turn..], s.turn..) |*turn, ti| for (turn.slice(), 0..) |e, ei| {
            if (e == .hurt and (ti > s.turn or ei > s.event)) after += e.hurt.dmg;
        };
        all[n] = .{ .weight = ENABLER * @as(f32, @floatFromInt(after)) / total, .what = .{ .stun = .{ .by = s.by, .turn = ctx.turns[s.turn].number } } };
        n += 1;
    }
    var starved: usize = 0;
    for (ctx.turns) |*turn| {
        if (turn.start.starved and hurtIn(turn)) starved += 1;
    }
    if (starved > 0) {
        all[n] = .{ .weight = STARVED * @as(f32, @floatFromInt(starved)) / @as(f32, @floatFromInt(ctx.turns.len)), .what = .starved };
        n += 1;
    }
    if (ctx.outnumbered()) {
        all[n] = .{ .weight = PER_FOE_BESIDE * @as(f32, @floatFromInt(ctx.beside)), .what = .outnumbered };
        n += 1;
    }
    if (ctx.cornered()) {
        all[n] = .{ .weight = CORNERED, .what = .cornered };
        n += 1;
    }
    if (tore) {
        all[n] = .{ .weight = @as(f32, @floatFromInt(torn)) / total, .what = .{ .torn = torn } };
        n += 1;
    }
    if (unused(ctx, .flask, chronicle.FLASK, true)) {
        all[n] = .{ .weight = FLASK_UNUSED, .what = .flask };
        n += 1;
    }
    if (unused(ctx, .ward, chronicle.WARD, false)) {
        all[n] = .{ .weight = WARD_UNUSED, .what = .ward };
        n += 1;
    }
    if (ctx.unlucky()) {
        all[n] = .{ .weight = BEST_ROLL, .what = .best_roll };
        n += 1;
    }
    if (misses > 0) {
        all[n] = .{ .weight = PER_MISS * @as(f32, @floatFromInt(misses)), .what = .{ .missed = misses } };
        n += 1;
    }
    std.mem.sort(Contributor, all[0..n], {}, heavier);
    var top = Top{ .n = @min(TOP, n) };
    var sum: f32 = 0;
    for (all[0..top.n]) |c| sum += c.weight;
    for (all[0..top.n], top.items[0..top.n]) |c, *out| {
        out.* = c;
        out.weight = if (sum > 0) c.weight / sum else 0;
    }
    return top;
}

fn heavier(_: void, a: Contributor, b: Contributor) bool {
    return a.weight > b.weight;
}

fn hurtIn(turn: *const Turn) bool {
    for (turn.slice()) |e| {
        if (e == .hurt and e.hurt.dmg > 0) return true;
    }
    return false;
}

/// What kind of death it was.
pub fn tags(ctx: *const Context, top: *const Top) Tags {
    var out = Tags.initEmpty();
    const k = ctx.killer;
    const t = taken(ctx);
    if (k.dmg - k.before >= @max(OVERKILL_MIN, k.before)) out.insert(.overkill);
    if (k.before >= ctx.last().start.max) out.insert(.one_shot);
    if (t.hits >= CHIP_HITS and t.biggest * CHIP_SHARE <= ctx.last().start.max) out.insert(.chip);
    if (k.by == .foe and actor.row(k.by.foe).hp <= TRASH_HP and ctx.level >= TRASH_LEVEL) out.insert(.by_trash);
    var gassed_by: ?Tag = null;
    for (ctx.turns) |*turn| for (turn.slice()) |e| switch (e) {
        .dealt => |d| if (d.killed and d.to.bursts()) {
            gassed_by = .own_goal;
        },
        .burst => gassed_by = .burst_beside,
        else => {},
    };
    if (k.by == .gas) if (gassed_by) |g| out.insert(g);
    for (top.slice()) |c| switch (c.what) {
        .flask => out.insert(.flask_unused),
        .ward => out.insert(.ward_unused),
        else => {},
    };
    if (ctx.points > 0) out.insert(.unspent);
    if (ctx.short * ALMOST_SHARE <= ctx.needed) out.insert(.almost_levelled);
    if (ctx.milestone) |m| {
        if (m.what == .level and ctx.since(m.turn) <= RECENT_MILESTONE) out.insert(.just_levelled);
    }
    return out;
}

/// How a foe family's blow kills, said after "was".
const DONE = blk: {
    var t = std.EnumArray(actor.Kind, ?[]const u8).initFill(null);
    t.set(.rat, "bitten to death");
    t.set(.slime, "crushed");
    t.set(.pib, "stabbed to death");
    t.set(.beefy_pib, "beaten to death");
    t.set(.bandit_crossbowman, "shot dead");
    break :blk t;
};

fn done(k: actor.Kind) ?[]const u8 {
    return DONE.get(k.family());
}

comptime {
    for (std.enums.values(actor.Kind)) |k| {
        if (k.foe() and actor.row(k).blow == .strike and done(k) == null) @compileError("obituary: how does a " ++ @tagName(k) ++ " kill?");
    }
}

pub const REPORT_MAX: usize = 480;

pub const Report = struct {
    buf: [REPORT_MAX]u8 = undefined,
    n: usize = 0,

    pub fn text(self: *const Report) []const u8 {
        return self.buf[0..self.n];
    }
};

const Writer = std.io.FixedBufferStream([]u8).Writer;

/// A few plain sentences on how the hero died, each from something that happened.
pub fn write(ctx: *const Context) Report {
    var r = Report{};
    var stream = std.io.fixedBufferStream(&r.buf);
    const w = stream.writer();
    const top = contributors(ctx);
    const tagged = tags(ctx, &top);
    cause(ctx, tagged, w) catch {};
    var said = Tags.initEmpty();
    how(ctx, &top, tagged, &said, w) catch {};
    aftertaste(ctx, tagged, said, w) catch {};
    r.n = stream.pos;
    return r;
}

fn article(word: []const u8, capital: bool) []const u8 {
    const vowel = word.len > 0 and std.mem.indexOfScalar(u8, "aeiou", word[0]) != null;
    if (capital) return if (vowel) "An" else "A";
    return if (vowel) "an" else "a";
}

/// "Arwen the archer", or only the name when it is the class's own.
pub const Titled = struct {
    name: []const u8,
    class: heroes.Class,

    pub fn format(self: Titled, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.writeAll(self.name);
        if (!std.ascii.eqlIgnoreCase(self.name, self.class.title())) try w.print(" the {s}", .{@tagName(self.class)});
    }
};

fn cause(ctx: *const Context, tagged: Tags, w: Writer) !void {
    const dark = if (ctx.night) " after dark" else "";
    const who = Titled{ .name = ctx.name, .class = ctx.class };
    switch (ctx.killer.by) {
        .foe => |k| {
            const foe = actor.row(k).name;
            try w.print("{}", .{who});
            if (tagged.contains(.by_trash)) try w.print(", level {d},", .{ctx.level});
            try w.print(" was {s} by {s} {s} {s}{s}.", .{ done(k) orelse "killed", article(foe, false), foe, ctx.place, dark });
        },
        .gas => if (tagged.contains(.own_goal))
            try w.print("{} burst a bloat {s}{s}, then died in its gas.", .{ who, ctx.place, dark })
        else if (tagged.contains(.burst_beside))
            try w.print("A bloat burst beside {} {s}{s}, and its gas did the rest.", .{ who, ctx.place, dark })
        else
            try w.print("{} choked on {s} {s}{s}.", .{ who, sourceName(.gas), ctx.place, dark }),
        .burn => try w.print("{} burned to death {s}{s}.", .{ who, ctx.place, dark }),
        .bleed => try w.print("{} bled to death {s}{s}{s}.", .{ who, ctx.place, dark, if (ctx.killer.torn) ", still walking" else "" }),
    }
}

fn sourceName(by: Source) []const u8 {
    return switch (by) {
        .foe => |k| actor.row(k).name,
        .gas => "caustic gas",
        .burn => "fire",
        .bleed => "bleeding",
    };
}

const Turns = struct {
    n: usize,

    pub fn format(self: Turns, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.print("{d} turn{s}", .{ self.n, mathx.plural(self.n) });
    }
};

fn how(ctx: *const Context, top: *const Top, tagged: Tags, said: *Tags, w: Writer) !void {
    const k = ctx.killer;
    if (tagged.contains(.one_shot)) return w.writeAll(" It took one blow, from full life.");
    if (tagged.contains(.overkill)) return w.print(" The last blow did {d} damage; {s} had {d} life left.", .{ k.dmg, ctx.name, k.before });
    const t = taken(ctx);
    const span = Turns{ .n = ctx.turns.len };
    if (tagged.contains(.chip)) return w.print(" No hit did more than {d}, but there were {d} of them in {}.", .{ t.biggest, t.hits, span });
    for (top.slice()) |c| switch (c.what) {
        .source => |s| if (!std.meta.eql(s.by, k.by)) {
            const the = if (s.by == .foe) "the " else "";
            return w.print(" Over the last {} {s} took {d} damage, {d} of it from {s}{s}.", .{ span, ctx.name, t.total, s.amount, the, sourceName(s.by) });
        },
        .stun => |s| {
            const foe = actor.row(s.by).name;
            const n = ctx.since(s.turn);
            if (n == 0) return w.print(" {s} {s} had stunned {s} that same turn.", .{ article(foe, true), foe, ctx.name });
            return w.print(" {s} {s} had stunned {s} {} before.", .{ article(foe, true), foe, ctx.name, Turns{ .n = n } });
        },
        .starved => return w.print(" " ++ WARD_NAME ++ " was bound, but {s} lacked the mana to cast it.", .{ctx.name}),
        .outnumbered => return w.print(" {d} foes stood next to {s} at the end.", .{ ctx.beside, ctx.name }),
        .cornered => return w.print(" {s} had no free cell left to step into.", .{ctx.name}),
        .torn => |n| return w.print(" Walking with an open wound cost {s} {d} life.", .{ ctx.name, n }),
        .flask => {
            said.insert(.flask_unused);
            return w.print(FLASK_LEFT, .{ctx.name});
        },
        .ward => {
            said.insert(.ward_unused);
            return w.writeAll(WARD_LEFT);
        },
        .best_roll => {
            const foe = sourceName(k.by);
            return w.print(" The last blow was the best {s} {s} can roll.", .{ article(foe, false), foe });
        },
        .missed => |n| return w.print(" {d} of {s}'s shots found nothing.", .{ n, ctx.name }),
    };
}

const WARD_NAME = chronicle.WARD.name();
const FLASK_LEFT = " {s} died with a life flask ready to drink.";
const WARD_LEFT = " " ++ WARD_NAME ++ " was ready, with the mana to cast it, and never cast.";

fn aftertaste(ctx: *const Context, tagged: Tags, said: Tags, w: Writer) !void {
    if (tagged.contains(.flask_unused) and !said.contains(.flask_unused)) return w.print(FLASK_LEFT, .{ctx.name});
    if (tagged.contains(.ward_unused) and !said.contains(.ward_unused)) return w.writeAll(WARD_LEFT);
    if (tagged.contains(.just_levelled)) {
        const n = ctx.since(ctx.milestone.?.turn);
        if (n == 0) return w.print(" {s} had reached level {d} that same turn.", .{ ctx.name, ctx.level });
        return w.print(" {s} had reached level {d} {} earlier.", .{ ctx.name, ctx.level, Turns{ .n = n } });
    }
    if (tagged.contains(.almost_levelled)) return w.print(" {s} was {d} experience short of level {d}.", .{ ctx.name, ctx.short, ctx.level + 1 });
    if (tagged.contains(.unspent)) return w.print(" {s} left {d} point{s} unspent.", .{ ctx.name, ctx.points, mathx.plural(ctx.points) });
    const m = ctx.milestone orelse return;
    const n = ctx.since(m.turn);
    if (n == 0 or n > RECENT_MILESTONE) return;
    const ago = Turns{ .n = n };
    switch (m.what) {
        .cleared => |k| try w.print(" {s} had killed the last {s} {} earlier.", .{ ctx.name, actor.row(k).name, ago }),
        .chest => try w.print(" {s} had opened a chest {} earlier.", .{ ctx.name, ago }),
        .level => {},
    }
}

fn turnOf(number: u32, hp: i32, events: []const chronicle.Event) Turn {
    var t = Turn{ .number = number, .start = .{ .hp = hp, .max = 20 } };
    for (events) |e| {
        t.events[t.n] = e;
        t.n += 1;
    }
    return t;
}

fn rat(dmg: i32, before: i32) chronicle.Event {
    return .{ .hurt = .{ .by = .{ .foe = .rat }, .dmg = dmg, .before = before } };
}

fn testContext(turns: []const Turn) Context {
    return .{ .name = "Arwen", .class = .archer, .killer = turns[turns.len - 1].lastHurt().?, .place = "in the Warrens", .level = 1, .short = 30, .needed = 40, .turns = turns };
}

test "a death by many small bites, a flask left full, reads as plain sentences" {
    var turns: [5]Turn = undefined;
    var hp: i32 = 12;
    for (&turns, 0..) |*t, i| {
        t.* = turnOf(@intCast(20 + i), hp, &.{ rat(2, hp), rat(1, hp - 2) });
        hp -= 3;
        t.start.flask = true;
    }
    turns[4] = turnOf(24, 2, &.{rat(2, 2)});
    turns[4].start.flask = true;
    var ctx = testContext(&turns);
    ctx.level = 4;
    const top = contributors(&ctx);
    var sum: f32 = 0;
    for (top.slice()) |c| sum += c.weight;
    try std.testing.expectApproxEqAbs(@as(f32, 1), sum, 1e-5);
    try std.testing.expect(top.items[0].what == .source);
    try std.testing.expect(top.items[1].what == .flask);
    const t = tags(&ctx, &top);
    try std.testing.expect(t.contains(.chip) and t.contains(.by_trash) and t.contains(.flask_unused) and !t.contains(.one_shot));
    const r = write(&ctx);
    std.debug.print("chip death: {s}\n", .{r.text()});
    try std.testing.expectEqualStrings("Arwen the archer, level 4, was bitten to death by a rat in the Warrens. No hit did more than 2, but there were 9 of them in 5 turns. Arwen died with a life flask ready to drink.", r.text());
}

test "a crossbow bolt past the last of life, after a stun, says both" {
    const bolt = chronicle.Event{ .hurt = .{ .by = .{ .foe = .bandit_crossbowman }, .dmg = 7, .before = 2, .best = true } };
    const pummel = chronicle.Event{ .hurt = .{ .by = .{ .foe = .beefy_pib }, .dmg = 5, .before = 7 } };
    const turns = [_]Turn{
        turnOf(8, 12, &.{ pummel, .{ .stunned = .beefy_pib } }),
        turnOf(9, 7, &.{ rat(3, 7), rat(2, 4) }),
        turnOf(10, 2, &.{bolt}),
    };
    var ctx = testContext(&turns);
    ctx.night = true;
    ctx.points = 2;
    const r = write(&ctx);
    std.debug.print("overkill: {s}\n", .{r.text()});
    try std.testing.expectEqualStrings("Arwen the archer was shot dead by a bandit crossbowman in the Warrens after dark. The last blow did 7 damage; Arwen had 2 life left. Arwen left 2 points unspent.", r.text());
    const top = contributors(&ctx);
    try std.testing.expectEqual(@as(usize, TOP), top.n);
    try std.testing.expect(ctx.unlucky());
}

test "gas from a bloat the hero burst is the hero's own doing, and a stun is named with its turn" {
    const gas = chronicle.Event{ .hurt = .{ .by = .gas, .dmg = 2, .before = 2 } };
    const turns = [_]Turn{
        turnOf(3, 10, &.{.{ .dealt = .{ .to = .bloat, .killed = true } }}),
        turnOf(4, 10, &.{ .{ .hurt = .{ .by = .{ .foe = .pib }, .dmg = 3, .before = 10 } }, .{ .stunned = .pib } }),
        turnOf(5, 7, &.{ .{ .hurt = .{ .by = .{ .foe = .pib }, .dmg = 3, .before = 7 } }, .{ .hurt = .{ .by = .gas, .dmg = 2, .before = 4 } } }),
        turnOf(6, 2, &.{gas}),
    };
    var ctx = testContext(&turns);
    ctx.milestone = .{ .turn = 3, .what = .{ .cleared = .bloat } };
    const r = write(&ctx);
    std.debug.print("own goal: {s}\n", .{r.text()});
    try std.testing.expectEqualStrings("Arwen the archer burst a bloat in the Warrens, then died in its gas. Over the last 4 turns Arwen took 10 damage, 6 of it from the pib. Arwen had killed the last bloat 3 turns earlier.", r.text());
}

test "gas from a bloat that burst beside the hero after one the hero shot is the later bloat's" {
    const turns = [_]Turn{
        turnOf(3, 10, &.{.{ .dealt = .{ .to = .bloat, .killed = true } }}),
        turnOf(4, 10, &.{.burst}),
        turnOf(5, 2, &.{.{ .hurt = .{ .by = .gas, .dmg = 2, .before = 2 } }}),
    };
    const ctx = testContext(&turns);
    const t = tags(&ctx, &contributors(&ctx));
    try std.testing.expect(t.contains(.burst_beside) and !t.contains(.own_goal));
}
