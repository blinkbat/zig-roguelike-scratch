const std = @import("std");
const input = @import("../core/input.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const bow = @import("bow.zig");
const burning = @import("burning.zig");
const damage = @import("damage.zig");
const attrs = @import("attrs.zig");
const glacial = @import("glacial.zig");
const juke = @import("juke.zig");
const blink = @import("blink.zig");
const spark = @import("spark.zig");
const bash = @import("bash.zig");
const cleave = @import("cleave.zig");
const pinning = @import("pinning.zig");
const barbed = @import("barbed.zig");
const nova = @import("nova.zig");
const fireball = @import("fireball.zig");
const chain = @import("chain.zig");
const ward = @import("ward.zig");
const charge = @import("charge.zig");
const hero = @import("hero.zig");
const flask = @import("flask.zig");
const menu = @import("../ui/menu.zig");

const Button = input.Button;

pub const Act = enum {
    shoot,
    wait,
    secondary,
    juke,
    burning_arrow,
    glacial_shot,
    spark,
    blink,
    shield_bash,
    cleave,
    pinning_shot,
    barbed_arrow,
    frost_nova,
    fireball,
    chain_lightning,
    mana_shield,
    charge,
    life_flask,
    mana_flask,

    pub fn name(a: Act) [:0]const u8 {
        return switch (a) {
            .secondary => "Activate " ++ comptime Set.secondary.name(),
            inline else => |t| comptime menu.titled(@tagName(t)),
        };
    }

    pub fn desc(a: Act) [:0]const u8 {
        return switch (a) {
            .shoot => "Aim an arrow at a target in range; confirm to loose it.",
            .wait => "Let a turn pass.",
            .secondary => "Hold to use Skills in your " ++ comptime Set.secondary.name() ++ ". Takes up this slot in both Skill Sets.",
            inline else => |t| comptime module(t).?.DESCRIPTION,
        };
    }

    fn module(comptime a: Act) ?type {
        return SKILLS.get(a).module;
    }

    fn has(comptime a: Act, comptime decl: []const u8) bool {
        const m = module(a) orelse return false;
        return @hasDecl(m, decl);
    }

    /// Bow targets a lit line; leap a landing; swing an adjacent tile; rush a body or empty landing down a running line.
    pub const Reticle = enum { bow, leap, swing, rush };

    pub fn reticle(a: Act) ?Reticle {
        return switch (a) {
            inline else => |t| comptime SKILLS.get(t).reticle,
        };
    }

    /// The style its damage scales by; null for skills that deal none.
    pub fn style(a: Act) ?attrs.Style {
        return switch (a) {
            inline else => |t| comptime SKILLS.get(t).style,
        };
    }

    /// Spends no turn: Juke alone.
    pub fn free(a: Act) bool {
        return switch (a) {
            inline else => |t| if (comptime has(t, "FREE")) module(t).?.FREE else false,
        };
    }

    /// Turns using it spends: none for a free action or the set modifier.
    pub fn turns(a: Act) u8 {
        return @intFromBool(a != .secondary and !a.free());
    }

    /// The flask it drinks.
    pub fn flaskOf(a: Act) ?flask.Kind {
        return switch (a) {
            inline else => |t| if (comptime has(t, "KIND")) module(t).?.KIND else null,
        };
    }

    /// Furthest target in cells; zero for actions without a reticle.
    pub fn reach(a: Act) i32 {
        return switch (a) {
            inline else => |t| if (comptime reticle(t)) |r| switch (r) {
                .bow => bow.RANGE,
                .swing => MELEE_REACH,
                .leap, .rush => module(t).?.RANGE,
            } else 0,
        };
    }

    /// A rush's nearest mark.
    pub fn nearest(a: Act) i32 {
        return switch (a) {
            inline else => |t| if (comptime has(t, "MIN_RANGE")) module(t).?.MIN_RANGE else MELEE_REACH,
        };
    }

    /// A missile's marks, a leap's landings, a swing's or a rush's: what its reticle holds legal.
    pub fn aimable(a: Act, lv: *const grid.Level, from: mathx.P, to: mathx.P) bool {
        return switch (a) {
            inline else => |t| if (comptime reticle(t)) |r| switch (r) {
                .bow => bow.aimable(lv, from, to),
                .leap, .swing, .rush => module(t).?.aimable(lv, from, to),
            } else unreachable,
        };
    }

    /// Not an arrow: what it is called, and it has no arrow's physical hit nor picture.
    pub fn bolt(a: Act) ?[]const u8 {
        return switch (a) {
            inline else => |t| if (comptime has(t, "BOLT")) module(t).?.BOLT else null,
        };
    }

    /// It vanishes and reappears rather than jumps.
    pub fn teleports(a: Act) bool {
        return switch (a) {
            inline else => |t| comptime has(t, "TELEPORTS"),
        };
    }

    /// Its swing strikes an arc round the tile aimed at.
    pub fn sweeps(a: Act) bool {
        return switch (a) {
            inline else => |t| comptime has(t, "arc"),
        };
    }

    pub fn cost(a: Act) i32 {
        return switch (a) {
            inline else => |t| if (comptime has(t, "COST")) module(t).?.COST else 0,
        };
    }

    /// An elemental skill's module: its element, its roll, its chance to afflict, its verb and what is said as it takes.
    pub fn arrow(comptime a: Act) type {
        if (!has(a, "ELEMENT")) @compileError("no element");
        return module(a).?;
    }

    pub fn skill(comptime a: Act) type {
        return module(a) orelse @compileError(@tagName(a) ++ " has no module");
    }

    pub fn element(a: Act) ?damage.Element {
        return switch (a) {
            inline else => |t| if (comptime has(t, "ELEMENT")) module(t).?.ELEMENT else null,
        };
    }

    /// Its physical and elemental rolls before its attribute; an arrow's physical is the bow's.
    pub fn bases(a: Act) Bases {
        return switch (a) {
            inline else => |t| comptime .{
                .physical = if (reticle(t) == .bow and bolt(t) == null) bow.BASE else if (has(t, "BASE") and !has(t, "ELEMENT")) module(t).?.BASE else null,
                .element = if (has(t, "ELEMENT")) module(t).?.BASE else null,
            },
        };
    }

    pub const Bases = struct { physical: ?damage.Base, element: ?damage.Base };

    /// Its missile bursts over an area where it strikes.
    pub fn bursts(a: Act) bool {
        return switch (a) {
            inline else => |t| comptime has(t, "burst"),
        };
    }

    /// Its bolt leaps on from what it strikes to other foes.
    pub fn chains(a: Act) bool {
        return switch (a) {
            inline else => |t| comptime has(t, "JUMPS"),
        };
    }

    /// What it strikes may be afflicted, by its own roll.
    pub fn afflicts(a: Act) bool {
        return switch (a) {
            inline else => |t| comptime has(t, "afflict"),
        };
    }

    /// Cast at once, it strikes the cells round the hero.
    pub fn surrounds(a: Act) bool {
        return switch (a) {
            inline else => |t| comptime has(t, "around"),
        };
    }

    /// Cast at once, it shields the hero.
    pub fn wards(a: Act) bool {
        return switch (a) {
            inline else => |t| comptime has(t, "Ward"),
        };
    }

    /// A body its blow leaves alive is knocked back.
    pub fn knocks(a: Act) bool {
        return switch (a) {
            inline else => |t| comptime has(t, "knocked"),
        };
    }

    /// Turns after it is used before it can be again.
    pub fn cooldown(a: Act) u8 {
        return switch (a) {
            inline else => |t| if (comptime has(t, "COOLDOWN")) module(t).?.COOLDOWN else 0,
        };
    }

    pub fn index(a: Act) usize {
        return std.enums.EnumIndexer(Act).indexOf(a);
    }

    /// Every decl probed by name above, so renaming one in its module fails the build.
    const PROBED = .{ "DESCRIPTION", "FREE", "TELEPORTS", "KIND", "BOLT", "arc", "COST", "ELEMENT", "burst", "JUMPS", "afflict", "around", "Ward", "knocked", "COOLDOWN", "MIN_RANGE", "BASE" };

    comptime {
        @setEvalBranchQuota(10_000);
        for (PROBED) |decl| {
            var found = false;
            for (std.enums.values(Act)) |a| found = found or has(a, decl);
            if (!found) @compileError("skillbar: no skill module declares " ++ decl);
        }
    }
};

pub const ACTS = std.enums.values(Act);
/// A swing's reach, and a rush's nearest mark unless its module says otherwise.
const MELEE_REACH: i32 = 1;

const Skill = struct { module: ?type, reticle: ?Act.Reticle = null, style: ?attrs.Style = null };
const SKILLS = std.EnumArray(Act, Skill).init(.{
    .shoot = .{ .module = null, .reticle = .bow, .style = .ranged },
    .wait = .{ .module = null },
    .secondary = .{ .module = null },
    .juke = .{ .module = juke, .reticle = .leap },
    .burning_arrow = .{ .module = burning, .reticle = .bow, .style = .ranged },
    .glacial_shot = .{ .module = glacial, .reticle = .bow, .style = .ranged },
    .spark = .{ .module = spark, .reticle = .bow, .style = .spell },
    .blink = .{ .module = blink, .reticle = .leap },
    .shield_bash = .{ .module = bash, .reticle = .swing, .style = .melee },
    .cleave = .{ .module = cleave, .reticle = .swing, .style = .melee },
    .pinning_shot = .{ .module = pinning, .reticle = .bow, .style = .ranged },
    .barbed_arrow = .{ .module = barbed, .reticle = .bow, .style = .ranged },
    .frost_nova = .{ .module = nova, .style = .spell },
    .fireball = .{ .module = fireball, .reticle = .bow, .style = .spell },
    .chain_lightning = .{ .module = chain, .reticle = .bow, .style = .spell },
    .mana_shield = .{ .module = ward },
    .charge = .{ .module = charge, .reticle = .rush, .style = .melee },
    .life_flask = .{ .module = flask.Life },
    .mana_flask = .{ .module = flask.Mana },
});

/// The skills a class may bind, in the bind picker's order.
pub fn kit(c: hero.Class) []const Act {
    return switch (c) {
        .archer => &.{ .shoot, .wait, .secondary, .juke, .burning_arrow, .glacial_shot, .pinning_shot, .barbed_arrow, .life_flask, .mana_flask },
        .wizard => &.{ .spark, .wait, .secondary, .blink, .fireball, .chain_lightning, .frost_nova, .mana_shield, .life_flask, .mana_flask },
        .knight => &.{ .cleave, .wait, .secondary, .shield_bash, .charge, .life_flask, .mana_flask },
    };
}

comptime {
    @setEvalBranchQuota(10_000);
    for (ACTS) |a| {
        if ((a.reticle() == .bow or Act.has(a, "BASE")) != (a.style() != null)) @compileError(@tagName(a) ++ ": damage skills must declare their style");
        var n: usize = 0;
        for (hero.CLASSES) |c| {
            if (std.mem.indexOfScalar(Act, kit(c), a) != null) n += 1;
        }
        std.debug.assert(n >= 1);
    }
}

pub const Set = enum {
    primary,
    secondary,

    pub fn name(s: Set) [:0]const u8 {
        return switch (s) {
            .primary => "Primary Skill Set",
            .secondary => "Secondary Skill Set",
        };
    }
};

pub const SETS = std.enums.values(Set);

/// PoE2's bind screen groups, less LT and the d-pad, which lean and move here.
pub const GROUPS = [_][]const Button{ &.{.lb}, &.{ .a, .x, .y, .b }, &.{ .rb, .rt } };

pub const SLOTS = blk: {
    var s: []const Button = &.{};
    for (GROUPS) |g| s = s ++ g;
    break :blk s[0..s.len].*;
};

pub const Slot = struct { set: Set, button: Button };

const Row = std.EnumArray(Button, ?Act);

pub const Bar = struct {
    set: std.EnumArray(Set, Row) = setsOf(hero.DEFAULT),
    modifier: ?Button = .lb,

    /// A fresh hero's of the class.
    pub fn of(c: hero.Class) Bar {
        return .{ .set = setsOf(c) };
    }

    pub fn at(self: Bar, s: Slot) ?Act {
        if (self.modifier == s.button) return .secondary;
        return self.set.get(s.set).get(s.button);
    }

    pub fn buttonOf(self: Bar, s: Set, a: Act) ?Button {
        for (SLOTS) |b| {
            if (self.at(.{ .set = s, .button = b }) == a) return b;
        }
        return null;
    }

    pub fn active(self: Bar, down: std.EnumSet(Button)) Set {
        const m = self.modifier orelse return .primary;
        return if (down.contains(m)) .secondary else .primary;
    }

    /// The secondary set's modifier moves by swapping whole columns; bound with none set, it clears its button's column.
    pub fn bind(self: *Bar, s: Slot, a: Act) void {
        if (a == .secondary) {
            if (self.modifier) |m| {
                self.swapColumns(m, s.button);
            } else {
                for (&self.set.values) |*row| row.set(s.button, null);
            }
            self.modifier = s.button;
            return;
        }
        if (self.modifier == s.button) self.modifier = null;
        self.set.getPtr(s.set).set(s.button, a);
    }

    /// The first slot with nothing bound, primary set first.
    pub fn firstEmpty(self: Bar) ?Slot {
        for (SETS) |set| for (SLOTS) |button| {
            const s = Slot{ .set = set, .button = button };
            if (self.at(s) == null) return s;
        };
        return null;
    }

    pub fn clear(self: *Bar, s: Slot) void {
        if (self.modifier == s.button) {
            self.modifier = null;
            return;
        }
        self.set.getPtr(s.set).set(s.button, null);
    }

    pub fn swap(self: *Bar, from: Slot, to: Slot) void {
        if (from.set == to.set and from.button == to.button) return;
        if (self.modifier == from.button or self.modifier == to.button) {
            const m = self.modifier.?;
            const other = if (m == from.button) to.button else from.button;
            self.swapColumns(m, other);
            self.modifier = other;
            return;
        }
        const a = self.at(from);
        self.set.getPtr(from.set).set(from.button, self.at(to));
        self.set.getPtr(to.set).set(to.button, a);
    }

    fn swapColumns(self: *Bar, p: Button, q: Button) void {
        for (&self.set.values) |*row| {
            const a = row.get(p);
            row.set(p, row.get(q));
            row.set(q, a);
        }
    }
};

/// The flasks on RB and RT in either set, as PoE2 keeps them out of the skill sets.
fn flasks() Row {
    var r = Row.initFill(null);
    r.set(.rb, .life_flask);
    r.set(.rt, .mana_flask);
    return r;
}

fn setsOf(c: hero.Class) std.EnumArray(Set, Row) {
    return .init(.{ .primary = primary(c), .secondary = secondary(c) });
}

fn secondary(c: hero.Class) Row {
    var r = flasks();
    switch (c) {
        .archer => {
            r.set(.x, .glacial_shot);
            r.set(.a, .pinning_shot);
            r.set(.b, .barbed_arrow);
        },
        .wizard => {
            r.set(.x, .chain_lightning);
            r.set(.a, .frost_nova);
            r.set(.b, .mana_shield);
        },
        .knight => {},
    }
    return r;
}

fn primary(c: hero.Class) Row {
    var r = flasks();
    r.set(.y, .wait);
    switch (c) {
        .archer => {
            r.set(.x, .shoot);
            r.set(.b, .juke);
            r.set(.a, .burning_arrow);
        },
        .wizard => {
            r.set(.x, .spark);
            r.set(.b, .blink);
            r.set(.a, .fireball);
        },
        .knight => {
            r.set(.x, .cleave);
            r.set(.b, .charge);
            r.set(.a, .shield_bash);
        },
    }
    return r;
}

test "each class starts with its own skills bound, and only skills of its kit" {
    for (hero.CLASSES) |c| {
        const bar = Bar.of(c);
        var bound: usize = 0;
        for (SETS) |s| for (SLOTS) |b| {
            const a = bar.at(.{ .set = s, .button = b }) orelse continue;
            try std.testing.expect(std.mem.indexOfScalar(Act, kit(c), a) != null);
            bound += 1;
        };
        std.debug.print("{s}: {d} slots bound from a kit of {d}\n", .{ c.title(), bound, kit(c).len });
    }
    try std.testing.expectEqual(@as(?Act, .spark), Bar.of(.wizard).at(.{ .set = .primary, .button = .x }));
    try std.testing.expectEqual(@as(?Act, .charge), Bar.of(.knight).at(.{ .set = .primary, .button = .b }));
}

pub const BINDS = Button.view;
pub const INSPECT = Button.inspect;
const NOT_SLOTS = [_]Button{ BINDS, menu.PAUSE, INSPECT };

comptime {
    if (!std.mem.eql(Button, &SLOTS, &input.SLOT_ORDER)) @compileError("the keyboard numbers the slots out of their order");
    for (std.enums.values(Button)) |b| {
        var n: usize = 0;
        for (SLOTS ++ NOT_SLOTS) |s| {
            if (s == b) n += 1;
        }
        std.debug.assert(n == 1);
    }
}

test "the bar starts with Shoot on X, Juke on B, Wait on Y, the flasks on RB and RT and the secondary set held on LB" {
    const bar = Bar{};
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .primary, .button = .x }));
    try std.testing.expectEqual(@as(?Act, .juke), bar.at(.{ .set = .primary, .button = .b }));
    try std.testing.expectEqual(@as(?Act, .wait), bar.at(.{ .set = .primary, .button = .y }));
    try std.testing.expectEqual(@as(?Act, .burning_arrow), bar.at(.{ .set = .primary, .button = .a }));
    try std.testing.expectEqual(@as(?Act, .glacial_shot), bar.at(.{ .set = .secondary, .button = .x }));
    for (SETS) |s| {
        try std.testing.expectEqual(@as(?Act, .life_flask), bar.at(.{ .set = s, .button = .rb }));
        try std.testing.expectEqual(@as(?Act, .mana_flask), bar.at(.{ .set = s, .button = .rt }));
    }
    try std.testing.expectEqual(@as(?Act, .secondary), bar.at(.{ .set = .secondary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, null), bar.at(.{ .set = .secondary, .button = .y }));
    var down = std.EnumSet(Button).initEmpty();
    try std.testing.expectEqual(Set.primary, bar.active(down));
    down.insert(.lb);
    try std.testing.expectEqual(Set.secondary, bar.active(down));
}

test "moving the secondary set's modifier carries off whatever sat on its new button, in both sets" {
    var bar = Bar{};
    bar.bind(.{ .set = .secondary, .button = .rb }, .shoot);
    bar.bind(.{ .set = .primary, .button = .rb }, .wait);
    bar.bind(.{ .set = .primary, .button = .rb }, .secondary);
    try std.testing.expectEqual(@as(?Button, .rb), bar.modifier);
    try std.testing.expectEqual(@as(?Act, .wait), bar.at(.{ .set = .primary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .secondary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .secondary), bar.at(.{ .set = .secondary, .button = .rb }));
}

test "a skill bound over the modifier unbinds it, and removing a slot empties it" {
    var bar = Bar{};
    bar.bind(.{ .set = .primary, .button = .lb }, .shoot);
    try std.testing.expectEqual(@as(?Button, null), bar.modifier);
    try std.testing.expectEqual(Set.primary, bar.active(std.EnumSet(Button).initFull()));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .primary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .primary, .button = .x }));
    bar.clear(.{ .set = .primary, .button = .x });
    try std.testing.expectEqual(@as(?Act, null), bar.at(.{ .set = .primary, .button = .x }));
}

test "picking a slot up and putting it down on another swaps the two, across sets too" {
    var bar = Bar{};
    bar.swap(.{ .set = .primary, .button = .x }, .{ .set = .secondary, .button = .b });
    try std.testing.expectEqual(@as(?Act, .barbed_arrow), bar.at(.{ .set = .primary, .button = .x }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .secondary, .button = .b }));
    bar.swap(.{ .set = .primary, .button = .lb }, .{ .set = .secondary, .button = .b });
    try std.testing.expectEqual(@as(?Button, .b), bar.modifier);
    try std.testing.expectEqual(@as(?Act, .juke), bar.at(.{ .set = .primary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .secondary, .button = .lb }));
}
