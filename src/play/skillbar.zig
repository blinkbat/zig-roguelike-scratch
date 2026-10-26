const std = @import("std");
const input = @import("../core/input.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const bow = @import("bow.zig");
const burning = @import("burning.zig");
const damage = @import("damage.zig");
const attrs = @import("attrs.zig");
const items = @import("items.zig");
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
const contracts = @import("skill_contract.zig");
const passives = @import("passives.zig");
const wording = @import("../core/wording.zig");
const tactics = @import("tactics.zig");

const Button = input.Button;

pub const EquippedBases = struct {
    skill: ?damage.Base,
    weapon: ?damage.Base = null,
    element: ?damage.Base,

    /// Each physical source, in roll order.
    pub fn parts(b: EquippedBases) [2]?damage.Base {
        return .{ b.skill, b.weapon };
    }

    pub fn physical(b: EquippedBases) damage.Base {
        var out = damage.Base{ .lo = 0, .hi = 0 };
        for (b.parts()) |maybe| if (maybe) |p| {
            out.lo += p.lo;
            out.hi += p.hi;
        };
        return out;
    }
};

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
    caltrops,
    overwatch,
    steady_aim,
    gravity_well,
    combustion,
    arcane_barrier,
    guard,
    whirlwind,
    unyielding,
    life_flask,
    mana_flask,

    pub fn name(a: Act) [:0]const u8 {
        return switch (a) {
            .secondary => "Activate " ++ comptime Set.secondary.name(),
            inline else => |t| comptime wording.titleOf(t),
        };
    }

    pub fn desc(a: Act) [:0]const u8 {
        return switch (a) {
            .shoot => "Shoot an arrow.",
            .wait => "Let a turn pass.",
            .secondary => "Hold to use Skills in your " ++ comptime Set.secondary.name() ++ ". Takes up this slot in both Skill Sets.",
            inline else => |t| comptime module(t).?.DESCRIPTION,
        };
    }

    /// Its description as the passives `perks` change it.
    pub fn describe(a: Act, w: anytype, perks: passives.Perks) void {
        switch (a) {
            inline else => |t| if (comptime has(t, "describe")) module(t).?.describe(w, perks) else w.writeAll(t.desc()) catch {},
        }
    }

    pub fn flavor(a: Act) ?[:0]const u8 {
        return switch (a) {
            .shoot => "Every arrow is a promise kept at a distance.",
            .wait => "The dark is patient. So can you be.",
            .secondary => null,
            inline else => |t| comptime module(t).?.FLAVOR,
        };
    }

    fn module(comptime a: Act) ?type {
        return SKILLS.get(a).module;
    }

    fn has(comptime a: Act, comptime decl: []const u8) bool {
        return CONTRACTS.get(a).has(decl);
    }

    pub const Reticle = contracts.Reticle;

    pub fn contract(a: Act) *const contracts.Contract {
        return CONTRACTS.getPtrConst(a);
    }

    pub fn reticle(a: Act) ?Reticle {
        return a.contract().reticle;
    }

    pub fn defaultStyle(a: Act) ?attrs.Style {
        return (a.attack() orelse return null).defaultStyle();
    }

    pub fn attack(a: Act) ?attrs.Attack {
        return a.contract().delivery;
    }

    /// Loosed from the bow, with the bow's physical hit.
    pub fn isArrow(a: Act) bool {
        return a.contract().source == .arrow;
    }

    fn declares(a: Act, comptime decl: []const u8) bool {
        return a.contract().has(decl);
    }

    pub fn free(a: Act) bool {
        return a.contract().free;
    }

    /// Turns using it spends: none for a free action or the set modifier.
    pub fn turns(a: Act) u8 {
        return @intFromBool(a != .secondary and !a.free());
    }

    /// The flask it drinks.
    pub fn flaskOf(a: Act) ?flask.Kind {
        return a.contract().flask_kind;
    }

    /// Furthest target in cells; zero for actions without a reticle.
    pub fn reach(a: Act) i32 {
        return a.contract().reach;
    }

    /// A rush's nearest mark.
    pub fn nearest(a: Act) i32 {
        return a.contract().nearest;
    }

    /// A missile's marks, a leap's landings, a swing's or a rush's: what its reticle holds legal.
    pub fn aimable(a: Act, lv: *const grid.Level, from: mathx.P, to: mathx.P) bool {
        return switch (a) {
            inline else => |t| if (comptime reticle(t)) |r| switch (r) {
                .bow => bow.aimable(lv, from, to),
                .leap, .swing, .rush => module(t).?.aimable(lv, from, to),
                .ground => grid.Level.inside(to) and mathx.dist(from, to) <= t.reach() and lv.walkable(to) and lv.isLit(to) and grid.litLine(lv, from, to),
            } else unreachable,
        };
    }

    /// Not an arrow: what it is called, and it has no arrow's physical hit nor picture.
    pub fn bolt(a: Act) ?[]const u8 {
        return a.contract().bolt;
    }

    /// It vanishes and reappears rather than jumps.
    pub fn teleports(a: Act) bool {
        return a.declares("TELEPORTS");
    }

    /// Its swing strikes an arc round the tile aimed at.
    pub fn sweeps(a: Act) bool {
        return a.declares("arc");
    }

    pub fn cost(a: Act) i32 {
        return a.contract().cost;
    }

    /// An elemental skill's module: its element, its roll, its chance to afflict, its verb and what is said as it takes.
    pub fn elemental(comptime a: Act) type {
        if (!has(a, "ELEMENT")) @compileError("no element");
        return module(a).?;
    }

    pub fn skill(comptime a: Act) type {
        return module(a) orelse @compileError(@tagName(a) ++ " has no module");
    }

    pub fn element(a: Act) ?damage.Element {
        return a.contract().element;
    }

    /// What the log says the hero did, when no blow or barrel says it.
    pub fn done(a: Act) ?[]const u8 {
        return a.contract().done;
    }

    /// Its physical and elemental rolls before its attribute; an arrow's physical is the bow's.
    pub fn bases(a: Act) Bases {
        return a.contract().bases;
    }

    pub const Bases = contracts.Bases;

    pub fn equippedBases(a: Act, gear: items.Gear) EquippedBases {
        const b = a.bases();
        var out = EquippedBases{ .skill = b.physical, .element = b.element };
        const attack_ = a.attack() orelse return out;
        if (gear.weapon(attack_)) |weapon| {
            if (attack_ == .ranged) out.skill = weapon else out.weapon = weapon;
        }
        return out;
    }

    /// Its missile bursts over an area where it strikes.
    pub fn bursts(a: Act) bool {
        return a.declares("burst");
    }

    /// Its bolt leaps on from what it strikes to other foes.
    pub fn chains(a: Act) bool {
        return a.declares("JUMPS");
    }

    /// What it strikes may be afflicted, by its own roll.
    pub fn afflicts(a: Act) bool {
        return a.declares("afflict");
    }

    /// What it afflicts and how often against no resistance.
    pub fn ailment(a: Act) ?Ailment {
        return a.contract().ailment;
    }

    pub const Ailment = contracts.Ailment;

    /// Cast at once, it strikes the cells round the hero.
    pub fn surrounds(a: Act) bool {
        return a.declares("around");
    }

    /// Cast at once, it shields the hero.
    pub fn wards(a: Act) bool {
        return a.declares("Ward");
    }

    /// A body its blow leaves alive is knocked back.
    pub fn knocks(a: Act) bool {
        return a.declares("knocked");
    }

    /// Turns after it is used before it can be again.
    pub fn cooldown(a: Act) u8 {
        return a.contract().cooldown;
    }

    pub fn index(a: Act) usize {
        return std.enums.EnumIndexer(Act).indexOf(a);
    }
};

pub const ACTS = std.enums.values(Act);
pub const KitBuf = [ACTS.len]Act;

const Skill = contracts.Definition;
const SKILLS = std.EnumArray(Act, Skill).init(.{
    .shoot = .{ .module = null, .reticle = .bow, .delivery = .ranged },
    .wait = .{ .module = null },
    .secondary = .{ .module = null },
    .juke = .{ .module = juke, .reticle = .leap },
    .burning_arrow = .{ .module = burning, .reticle = .bow, .delivery = .ranged },
    .glacial_shot = .{ .module = glacial, .reticle = .bow, .delivery = .ranged },
    .spark = .{ .module = spark, .reticle = .bow, .delivery = .spell },
    .blink = .{ .module = blink, .reticle = .leap },
    .shield_bash = .{ .module = bash, .reticle = .swing, .delivery = .melee },
    .cleave = .{ .module = cleave, .reticle = .swing, .delivery = .melee },
    .pinning_shot = .{ .module = pinning, .reticle = .bow, .delivery = .ranged },
    .barbed_arrow = .{ .module = barbed, .reticle = .bow, .delivery = .ranged },
    .frost_nova = .{ .module = nova, .delivery = .spell },
    .fireball = .{ .module = fireball, .reticle = .bow, .delivery = .spell },
    .chain_lightning = .{ .module = chain, .reticle = .bow, .delivery = .spell },
    .mana_shield = .{ .module = ward },
    .charge = .{ .module = charge, .reticle = .rush, .delivery = .melee },
    .caltrops = .{ .module = tactics.Caltrops, .reticle = .ground },
    .overwatch = .{ .module = tactics.Overwatch, .reticle = .ground, .delivery = .ranged },
    .steady_aim = .{ .module = tactics.SteadyAim },
    .gravity_well = .{ .module = tactics.GravityWell, .reticle = .ground },
    .combustion = .{ .module = tactics.Combustion, .reticle = .ground, .delivery = .spell },
    .arcane_barrier = .{ .module = tactics.ArcaneBarrier, .reticle = .ground },
    .guard = .{ .module = tactics.Guard },
    .whirlwind = .{ .module = tactics.Whirlwind, .delivery = .melee },
    .unyielding = .{ .module = tactics.Unyielding },
    .life_flask = .{ .module = flask.Life },
    .mana_flask = .{ .module = flask.Mana },
});

const CONTRACTS = blk: {
    @setEvalBranchQuota(100_000);
    var table = std.EnumArray(Act, contracts.Contract).initUndefined();
    for (ACTS) |act| table.set(act, contracts.interpret(@tagName(act), SKILLS.get(act)));
    break :blk table;
};

/// The skills a class may bind, in the bind picker's order.
pub fn kit(c: hero.Class) []const Act {
    return switch (c) {
        .archer => &.{ .shoot, .wait, .secondary, .juke, .steady_aim, .burning_arrow, .glacial_shot, .barbed_arrow, .caltrops, .pinning_shot, .overwatch, .life_flask, .mana_flask },
        .wizard => &.{ .spark, .wait, .secondary, .blink, .fireball, .frost_nova, .mana_shield, .chain_lightning, .combustion, .gravity_well, .arcane_barrier, .life_flask, .mana_flask },
        .knight => &.{ .cleave, .wait, .secondary, .charge, .guard, .shield_bash, .whirlwind, .unyielding, .life_flask, .mana_flask },
    };
}

comptime {
    @setEvalBranchQuota(100_000);
    for (ACTS) |a| {
        if ((a.reticle() == .bow or Act.has(a, "BASE")) != (a.attack() != null)) @compileError(@tagName(a) ++ ": a damage skill has no attack type to scale by");
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

    pub fn slotOf(self: Bar, a: Act) ?Slot {
        for (SETS) |s| for (SLOTS) |b| {
            if (self.at(.{ .set = s, .button = b }) == a) return .{ .set = s, .button = b };
        };
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

test "arrows scale as ranged, bolts and novas as spells, swings and rushes as melee" {
    const want = std.EnumArray(Act, ?attrs.Attack).init(.{
        .shoot = .ranged,
        .wait = null,
        .secondary = null,
        .juke = null,
        .burning_arrow = .ranged,
        .glacial_shot = .ranged,
        .spark = .spell,
        .blink = null,
        .shield_bash = .melee,
        .cleave = .melee,
        .pinning_shot = .ranged,
        .barbed_arrow = .ranged,
        .frost_nova = .spell,
        .fireball = .spell,
        .chain_lightning = .spell,
        .mana_shield = null,
        .charge = .melee,
        .caltrops = null,
        .overwatch = .ranged,
        .steady_aim = null,
        .gravity_well = null,
        .combustion = .spell,
        .arcane_barrier = null,
        .guard = null,
        .whirlwind = .melee,
        .unyielding = null,
        .life_flask = null,
        .mana_flask = null,
    });
    for (ACTS) |a| try std.testing.expectEqual(want.get(a), a.attack());
}

test "each afflicting skill's stated chance is what its roll lands" {
    const TRIES = 4000;
    var n: usize = 0;
    inline for (comptime std.enums.values(Act)) |a| if (comptime a.ailment()) |ail| {
        var rng = mathx.Rng.init(0xA11);
        var landed: u32 = 0;
        for (0..TRIES) |_| landed += @intFromBool(Act.skill(a).procs(&rng, 0));
        const pc = landed * mathx.PERCENT / TRIES;
        try std.testing.expect(pc + 3 >= ail.chance and pc <= ail.chance + 3);
        n += 1;
    };
    std.debug.print("ailments: {d} afflicting skills land within 3 points of their stated chance\n", .{n});
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

pub const INSPECT = Button.inspect;
const NOT_SLOTS = [_]Button{ Button.character, Button.pause, INSPECT };

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
