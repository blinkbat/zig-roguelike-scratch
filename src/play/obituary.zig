const std = @import("std");
const actor = @import("actor.zig");
const heroes = @import("hero.zig");
const chronicle = @import("chronicle.zig");
const skillbar = @import("skillbar.zig");
const gas = @import("../map/gas.zig");
const menu = @import("../ui/menu.zig");
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

pub const Contributor = struct {
    weight: f32,
    what: What,
};

pub const What = union(enum) {
    source: Source,
    stun: struct { by: actor.Kind, turn: u32 },
    starved,
    outnumbered,
    cornered,
    torn,
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

/// Some turn a ready defence (with life low, if `low`) went unused, with harm still to come.
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
    var sums: [SOURCES_MAX]i32 = undefined;
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
            for (sources[0..ns], sums[0..ns]) |s, *sum| {
                if (std.meta.eql(s, h.by)) {
                    sum.* += h.dmg;
                    break;
                }
            } else {
                sources[ns] = h.by;
                sums[ns] = h.dmg;
                ns += 1;
            }
        },
        .stunned => |k| if (stun == null) {
            stun = .{ .turn = ti, .event = ei, .by = k };
        },
        .missed => misses += 1,
        else => {},
    };
    for (sources[0..ns], sums[0..ns]) |s, sum| {
        if (sum <= 0) continue;
        all[n] = .{ .weight = @as(f32, @floatFromInt(sum)) / total, .what = .{ .source = s } };
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
    for (ctx.turns, 0..) |*turn, i| {
        if (turn.start.starved and hurtIn(turn) and !used(ctx, i, chronicle.WARD)) starved += 1;
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
        all[n] = .{ .weight = @as(f32, @floatFromInt(torn)) / total, .what = .torn };
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
    while (n > 0 and all[n - 1].weight <= 0) n -= 1;
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

fn done(k: actor.Kind) ?[]const u8 {
    return switch (actor.row(k).blow) {
        .strike => |s| s.slain,
        .burst => null,
    };
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

/// A few plain sentences on how the hero died, each from something that happened; a sentence that does not fit is left out whole.
pub fn write(ctx: *const Context) Report {
    var r = Report{};
    var stream = std.io.fixedBufferStream(&r.buf);
    const w = stream.writer();
    const top = contributors(ctx);
    const tagged = tags(ctx, &top);
    const deed = lastDeed(ctx, tagged);
    var said = Tags.initEmpty();
    const a = stream.pos;
    cause(ctx, tagged, w) catch {
        stream.pos = a;
    };
    const b = stream.pos;
    if (deed) |d| lastGasp(ctx, d, w) catch {
        stream.pos = b;
    };
    const c = stream.pos;
    how(ctx, &top, tagged, deed, &said, w) catch {
        stream.pos = c;
    };
    const d = stream.pos;
    aftertaste(ctx, tagged, said, w) catch {
        stream.pos = d;
    };
    r.n = stream.pos;
    return r;
}

fn article(word: []const u8, capital: bool) []const u8 {
    const vowel = word.len > 0 and std.mem.indexOfScalar(u8, "aeiou", word[0]) != null;
    if (capital) return if (vowel) "An" else "A";
    return if (vowel) "an" else "a";
}

/// "a rat", or "An ox" when `capital`.
const Indefinite = struct {
    word: []const u8,
    capital: bool = false,

    pub fn format(self: Indefinite, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.print("{s} {s}", .{ article(self.word, self.capital), self.word });
    }
};

/// "Arwen the archer", or only the name when it is the class's own.
pub const Titled = struct {
    name: []const u8,
    class: heroes.Class,

    pub fn format(self: Titled, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.writeAll(self.name);
        if (std.ascii.eqlIgnoreCase(self.name, self.class.title()) or std.ascii.indexOfIgnoreCase(self.name, " the ") != null) return;
        try w.print(" the {s}", .{menu.word(self.class)});
    }
};

fn cause(ctx: *const Context, tagged: Tags, w: Writer) !void {
    const dark = if (ctx.night) " after dark" else "";
    const who = Titled{ .name = ctx.name, .class = ctx.class };
    switch (ctx.killer.by) {
        .foe => |k| {
            const foe = actor.row(k).name;
            try w.print("{}", .{who});
            const mere = if (tagged.contains(.by_trash)) "mere " else "";
            try w.print(" was {s} by {s} {s}{s} {s}{s}.", .{ done(k) orelse "killed", article(if (mere.len > 0) mere else foe, false), mere, foe, ctx.place, dark });
        },
        .gas => if (tagged.contains(.own_goal))
            try w.print("{} burst a bloat {s}{s}, then died in its gas.", .{ who, ctx.place, dark })
        else if (tagged.contains(.burst_beside))
            try w.print("{} died in gas from a bloat that burst nearby {s}{s}.", .{ who, ctx.place, dark })
        else
            try w.print("{} choked on {s} {s}{s}.", .{ who, sourceName(.gas), ctx.place, dark }),
        .burn => try w.print("{} burned to death {s}{s}.", .{ who, ctx.place, dark }),
        .bleed => try w.print("{} bled to death {s}{s}{s}.", .{ who, ctx.place, dark, if (ctx.killer.torn) " after moving" else "" }),
    }
}

fn sourceName(by: Source) []const u8 {
    return switch (by) {
        .foe => |k| actor.row(k).name,
        .gas => gas.NAME,
        .burn => "fire",
        .bleed => "bleeding",
    };
}

/// What the hero did with its own last action, in the turn it died.
const Deed = struct {
    with: ?skillbar.Act,
    what: union(enum) { felled: actor.Kind, struck: actor.Kind, missed, used: skillbar.Act },
};

fn lastDeed(ctx: *const Context, tagged: Tags) ?Deed {
    var with: ?skillbar.Act = null;
    var felled: ?actor.Kind = null;
    var struck: ?actor.Kind = null;
    var missed = false;
    for (ctx.last().slice()) |e| switch (e) {
        .used => |a| with = a,
        .dealt => |d| if (d.killed) {
            felled = d.to;
        } else {
            struck = d.to;
        },
        .missed => missed = true,
        else => {},
    };
    if (felled) |k| return if (tagged.contains(.own_goal) and k.bursts()) null else .{ .with = with, .what = .{ .felled = k } };
    if (struck) |k| return .{ .with = with, .what = .{ .struck = k } };
    if (missed) return .{ .with = with, .what = .missed };
    return .{ .with = with, .what = .{ .used = with orelse return null } };
}

fn missile(with: ?skillbar.Act) []const u8 {
    const a = with orelse return "blow";
    if (a.isArrow()) return "arrow";
    return a.bolt() orelse "blow";
}

fn lastGasp(ctx: *const Context, deed: Deed, w: Writer) !void {
    const name = ctx.name;
    const with = missile(deed.with);
    switch (deed.what) {
        .felled => |k| {
            const foe = Indefinite{ .word = actor.row(k).name };
            return w.print(" {s}'s last {s} killed {}.", .{ name, with, foe });
        },
        .struck => |k| {
            const foe = Indefinite{ .word = actor.row(k).name };
            return w.print(" {s}'s last {s} hit {} without killing it.", .{ name, with, foe });
        },
        .missed => return w.print(" {s}'s last {s} missed.", .{ name, with }),
        .used => |a| switch (a) {
            chronicle.FLASK => try w.print(" {s} drank a life flask on the final turn.", .{name}),
            chronicle.WARD => try w.print(" {s} cast " ++ WARD_NAME ++ " on the final turn.", .{name}),
            .wait => try w.print(" {s} waited.", .{name}),
            else => if (a.flaskOf() == .mana)
                try w.print(" {s}'s last act was to drink a mana flask.", .{name})
            else if (a.reticle() == .leap) {
                if (a.teleports()) return w.print(" {s}'s last move was a blink.", .{name});
                try w.print(" {s}'s last move was a leap.", .{name});
            },
        },
    }
}

fn how(ctx: *const Context, top: *const Top, tagged: Tags, deed: ?Deed, said: *Tags, w: Writer) !void {
    const k = ctx.killer;
    if (tagged.contains(.one_shot)) return w.print(" {s} died from full life in one hit.", .{ctx.name});
    if (tagged.contains(.overkill)) return w.print(" The last blow would have killed {s} twice over.", .{ctx.name});
    if (tagged.contains(.chip)) return w.print(" {s} took one small wound after another.", .{ctx.name});
    for (top.slice()) |c| switch (c.what) {
        .source => |s| if (!std.meta.eql(s, k.by)) {
            const what = sourceName(s);
            if (s == .foe) return w.print(" The {s} had already wounded {s}.", .{ what, ctx.name });
            return w.print(" {c}{s} had already wounded {s}.", .{ std.ascii.toUpper(what[0]), what[1..], ctx.name });
        },
        .stun => |s| {
            const foe = Indefinite{ .word = actor.row(s.by).name, .capital = true };
            if (ctx.since(s.turn) == 0) return w.print(" {} stunned {s} on that turn.", .{ foe, ctx.name });
            return w.print(" {} had stunned {s}.", .{ foe, ctx.name });
        },
        .starved => return w.print(" {s} had too little mana for " ++ WARD_NAME ++ ".", .{ctx.name}),
        .outnumbered => return w.print(" {s} was surrounded.", .{ctx.name}),
        .cornered => return w.writeAll(" There was nowhere left to step."),
        .torn => return w.writeAll(" Moving made the bleeding worse."),
        .flask => {
            said.insert(.flask_unused);
            return w.print(FLASK_LEFT, .{ctx.name});
        },
        .ward => {
            said.insert(.ward_unused);
            return w.writeAll(WARD_LEFT);
        },
        .best_roll => return w.print(" It was the hardest blow {} can strike.", .{Indefinite{ .word = sourceName(k.by) }}),
        .missed => |n| if (deed == null or deed.?.what != .missed) {
            if (n == 1) return w.print(" {s} had missed a shot.", .{ctx.name});
            return w.print(" {s} had missed {d} shots.", .{ ctx.name, n });
        },
    };
}

const WARD_NAME = chronicle.WARD.name();
const FLASK_LEFT = " {s} had a life flask ready but did not drink it.";
const WARD_LEFT = " " ++ WARD_NAME ++ " was ready but unused.";

fn aftertaste(ctx: *const Context, tagged: Tags, said: Tags, w: Writer) !void {
    if (tagged.contains(.flask_unused) and !said.contains(.flask_unused)) return w.print(FLASK_LEFT, .{ctx.name});
    if (tagged.contains(.ward_unused) and !said.contains(.ward_unused)) return w.writeAll(WARD_LEFT);
    if (tagged.contains(.just_levelled)) {
        if (ctx.since(ctx.milestone.?.turn) == 0) return w.print(" {s} had gained a level that turn.", .{ctx.name});
        return w.print(" {s} had recently gained a level.", .{ctx.name});
    }
    if (tagged.contains(.almost_levelled)) return w.print(" {s} was close to the next level.", .{ctx.name});
    if (tagged.contains(.unspent)) return w.print(" {s} died with unspent points.", .{ctx.name});
    const m = ctx.milestone orelse return;
    const n = ctx.since(m.turn);
    if (n == 0 or n > RECENT_MILESTONE) return;
    switch (m.what) {
        .cleared => |k| try w.print(" {s} had recently killed the last {s}.", .{ ctx.name, actor.row(k).name }),
        .chest => try w.print(" {s} had recently opened a chest.", .{ctx.name}),
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
    try std.testing.expectEqualStrings("Arwen the archer was bitten to death by a mere rat in the Warrens. Arwen took one small wound after another. Arwen had a life flask ready but did not drink it.", r.text());
}

test "an arrow answered by a bolt past the last of life names the hero's last shot" {
    const bolt = chronicle.Event{ .hurt = .{ .by = .{ .foe = .bandit_crossbowman }, .dmg = 7, .before = 2, .best = true } };
    const pummel = chronicle.Event{ .hurt = .{ .by = .{ .foe = .beefy_pib }, .dmg = 5, .before = 7 } };
    const turns = [_]Turn{
        turnOf(8, 12, &.{ pummel, .{ .stunned = .beefy_pib } }),
        turnOf(9, 7, &.{ rat(3, 7), rat(2, 4) }),
        turnOf(10, 2, &.{ .{ .used = .shoot }, .{ .dealt = .{ .to = .bandit_crossbowman, .killed = false } }, bolt }),
    };
    var ctx = testContext(&turns);
    ctx.night = true;
    ctx.points = 2;
    const r = write(&ctx);
    std.debug.print("overkill: {s}\n", .{r.text()});
    try std.testing.expectEqualStrings("Arwen the archer was shot dead by a bandit crossbowman in the Warrens after dark. Arwen's last arrow hit a bandit crossbowman without killing it. The last blow would have killed Arwen twice over. Arwen died with unspent points.", r.text());
    const top = contributors(&ctx);
    try std.testing.expectEqual(@as(usize, TOP), top.n);
    try std.testing.expect(ctx.unlucky());
}

test "gas from a bloat the hero burst is the hero's own doing, and the foe that wore the hero down is named" {
    const choke = chronicle.Event{ .hurt = .{ .by = .gas, .dmg = 2, .before = 2 } };
    const turns = [_]Turn{
        turnOf(3, 10, &.{.{ .dealt = .{ .to = .bloat, .killed = true } }}),
        turnOf(4, 10, &.{ .{ .hurt = .{ .by = .{ .foe = .pib }, .dmg = 3, .before = 10 } }, .{ .stunned = .pib } }),
        turnOf(5, 7, &.{ .{ .hurt = .{ .by = .{ .foe = .pib }, .dmg = 3, .before = 7 } }, .{ .hurt = .{ .by = .gas, .dmg = 2, .before = 4 } } }),
        turnOf(6, 2, &.{choke}),
    };
    var ctx = testContext(&turns);
    ctx.milestone = .{ .turn = 3, .what = .{ .cleared = .bloat } };
    const r = write(&ctx);
    std.debug.print("own goal: {s}\n", .{r.text()});
    try std.testing.expectEqualStrings("Arwen the archer burst a bloat in the Warrens, then died in its gas. The pib had already wounded Arwen. Arwen had recently killed the last bloat.", r.text());
}

test "the hero's own last act in the turn it died is its last gasp" {
    const late = [_]Turn{
        turnOf(7, 6, &.{rat(3, 6)}),
        turnOf(8, 4, &.{ .{ .used = .life_flask }, rat(5, 4) }),
    };
    const flask_ctx = testContext(&late);
    const drank = write(&flask_ctx);
    std.debug.print("last gasp: {s}\n", .{drank.text()});
    try std.testing.expectEqualStrings("Arwen the archer was bitten to death by a rat in the Warrens. Arwen drank a life flask on the final turn.", drank.text());
    const fought = [_]Turn{
        turnOf(7, 6, &.{rat(3, 6)}),
        turnOf(8, 4, &.{ .{ .dealt = .{ .to = .rat, .killed = true } }, rat(5, 4) }),
    };
    var ctx = testContext(&fought);
    ctx.name = "Arwen the Bold";
    const felled = write(&ctx);
    std.debug.print("last gasp: {s}\n", .{felled.text()});
    try std.testing.expectEqualStrings("Arwen the Bold was bitten to death by a rat in the Warrens. Arwen the Bold's last blow killed a rat.", felled.text());
}

test "bites a shield took whole wore nobody down, and a shield cast in time was not starved" {
    const pib = chronicle.Event{ .hurt = .{ .by = .{ .foe = .pib }, .dmg = 6, .before = 5 } };
    var turns = [_]Turn{
        turnOf(7, 5, &.{ rat(0, 5), rat(0, 5) }),
        turnOf(8, 5, &.{ .{ .used = chronicle.WARD }, rat(0, 5), pib }),
    };
    turns[1].start.starved = true;
    const ctx = testContext(&turns);
    const top = contributors(&ctx);
    try std.testing.expectEqual(@as(usize, 1), top.n);
    const r = write(&ctx);
    std.debug.print("shielded: {s}\n", .{r.text()});
    try std.testing.expectEqualStrings("Arwen the archer was stabbed to death by a pib in the Warrens. Arwen cast " ++ WARD_NAME ++ " on the final turn.", r.text());
}

test "a report too long for its room drops whole sentences" {
    const turns = [_]Turn{turnOf(8, 4, &.{ .{ .used = .shoot }, .missed, rat(5, 4) })};
    var ctx = testContext(&turns);
    ctx.place = "in " ++ "a" ** (REPORT_MAX - 60);
    const r = write(&ctx);
    try std.testing.expect(std.mem.endsWith(u8, r.text(), "."));
    try std.testing.expect(std.mem.indexOf(u8, r.text(), "last arrow") == null);
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
