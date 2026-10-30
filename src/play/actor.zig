const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const bow = @import("bow.zig");
const burning = @import("burning.zig");
const glacial = @import("glacial.zig");
const bleeding = @import("bleeding.zig");
const resilience = @import("resilience.zig");
const clock = @import("clock.zig");
const pinning = @import("pinning.zig");
const shock = @import("shock.zig");
const sunder = @import("sunder.zig");
const blind = @import("blind.zig");
const confusion = @import("confusion.zig");
const ward = @import("ward.zig");
const heroes = @import("hero.zig");
const wording = @import("../core/wording.zig");

const P = mathx.P;

pub const ActorId = struct {
    value: u16,

    pub fn fromInt(value: u16) ActorId {
        std.debug.assert(value != grid.NO_ONE and value <= MAX);
        return .{ .value = value };
    }

    pub fn slot(self: ActorId) ActorSlot {
        return .{ .index = Pool.slot(self.value) };
    }
};

pub const ActorSlot = struct {
    index: usize,

    pub fn fromIndex(index: usize) ActorSlot {
        std.debug.assert(index < MAX);
        return .{ .index = index };
    }

    pub fn id(self: ActorSlot) ActorId {
        return .{ .value = Pool.idOf(self.index) };
    }
};

pub const Kind = enum {
    archer,
    wizard,
    knight,
    rat,
    slime,
    slime_half,
    slime_quarter,
    bloat,
    pib,
    beefy_pib,
    bandit_crossbowman,
    bandit_netter,
    bandit_shieldbearer,
    frost_wisp,
    pyre_bloat,
    pib_shaman,
    bog_leech,
    mimic,

    pub fn foe(k: Kind) bool {
        return row(k).foe_type != null;
    }

    pub fn stocked(k: Kind) bool {
        return k.foe() and k.family() == k;
    }

    pub fn family(k: Kind) Kind {
        return FAMILY.get(k);
    }

    pub fn gasses(k: Kind) bool {
        return switch (row(k).blow) {
            .burst => |b| b == .gas,
            .strike => false,
        };
    }
};

const DESCENT = blk: {
    var t = std.EnumArray(Kind, std.EnumSet(Kind)).initUndefined();
    for (std.enums.values(Kind)) |k| {
        var s = std.EnumSet(Kind).initEmpty();
        var c: ?Kind = k;
        while (c) |x| : (c = row(x).splits) s.insert(x);
        t.set(k, s);
    }
    break :blk t;
};

pub fn descent(k: Kind) std.EnumSet(Kind) {
    return DESCENT.get(k);
}

const FAMILY = blk: {
    var t = std.EnumArray(Kind, Kind).initUndefined();
    for (std.enums.values(Kind)) |k| t.set(k, k);
    for (std.enums.values(Kind)) |k| {
        var forms = DESCENT.get(k).iterator();
        while (forms.next()) |x| t.set(x, t.get(k));
    }
    break :blk t;
};

/// The hero a map's start is drawn as.
pub const HERO: Kind = .archer;

comptime {
    for (std.enums.values(Kind)) |k| std.debug.assert(row(k).pace >= clock.TURN);
}

pub const FOES = blk: {
    var ks: []const Kind = &.{};
    for (std.enums.values(Kind)) |k| {
        if (k.stocked()) ks = ks ++ &[_]Kind{k};
    }
    break :blk ks[0..ks.len].*;
};

pub fn most(k: Kind) usize {
    return if (row(k).splits) |n| 2 * most(n) else 1;
}

pub fn roomFor(bodies: usize, k: Kind) bool {
    return bodies + most(k) <= MAX;
}

/// `bleeds`/`stuns`: percent chance a blow that leaves its mark alive opens a bleed or stuns it.
pub const Strike = struct {
    hit: damage.Base,
    verb: [:0]const u8,
    /// How its blow kills, said after "was".
    slain: ?[:0]const u8 = null,
    bleeds: u32 = 0,
    stuns: u32 = 0,
    /// Percent chance, before cold resistance, to chill.
    chills: u32 = 0,
    /// Its damage is this element's, resisted as such instead of by armour.
    element: ?damage.Element = null,
    /// A landed blow pushes the struck body a cell straight away.
    knocks: bool = false,

    pub fn roll(s: Strike, rng: *mathx.Rng) i32 {
        return s.hit.roll(rng);
    }
};

pub const Burst = enum { gas, fire };

pub const Blow = union(enum) {
    strike: Strike,
    /// It dies instead (Brogue's kamikaze), and bursts however it dies.
    burst: Burst,
};

/// Swimming bodies keep to deep water and shallows.
pub const Movement = enum { ground, flying, swimming };
pub const FoeType = enum { beast, humanoid, aberration, undead, construct };

pub const Ranged = struct { range: i32, retreat: i32 };

/// Thrown every `every` turns at a hero within `range`, holding it for `pins` turns.
pub const Net = struct { range: i32, pins: u8, every: u8 };

/// Every `every` turns: heals the most hurt `kin` within `reach` by `amount`, or else wakes the sleeping ones.
pub const Mend = struct { reach: i32, amount: i32, every: u8, kin: []const Kind };

pub const Row = struct {
    armour: i32 = 0,
    stun_resist: u8 = 0,
    fright_resist: u8 = 0,
    name: [:0]const u8,
    movement: Movement,
    foe_type: ?FoeType,
    /// A fresh body's; one split off a slime has half what that slime had left.
    hp: i32,
    /// Cells its eyes reach, where there is light to see by.
    sight: i32,
    blow: Blow,
    ranged: ?Ranged = null,
    /// Cells round it the light it carries reaches.
    light: i32 = 0,
    /// Brogue's `MONST_FLITS`: a third of its moves go a random way.
    flits: bool = false,
    /// Runs from the hero for `FLEE_TURNS` of its turns when it sees a foe die within `FRIGHT_REACH`.
    flees: bool = false,
    /// What it splits into, two of them, when a blow leaves it under half its hp.
    splits: ?Kind = null,
    resists: damage.Resists = .initFill(0),
    /// Ticks each of its actions takes (Brogue's `movementDuration`); a turn is drawn with one action at most.
    pace: i32 = clock.TURN,
    /// Its turns from one sweep, a blow at every cell round it, to the next; 0, it never sweeps.
    sweep_every: u8 = 0,
    /// Unseen, even where lit, until the hero is beside it.
    lurks: bool = false,
    /// Spawns as a closed chest, inert until opened.
    disguised: bool = false,
    /// Backs off from a hero this close, and comes no closer.
    keeps: i32 = 0,
    net: ?Net = null,
    mends: ?Mend = null,
};

pub const LURK_REACH: i32 = 1;

pub const SWEEP_VERB = "sweeps";
pub const SWEEP_CELLS = mathx.ALL_DIRS.len;
pub const Swept = grid.Area(SWEEP_CELLS);

/// The cells round `from` its sweep reaches, those a step could.
pub fn sweep(lv: *const grid.Level, from: P) Swept {
    return lv.reachable(SWEEP_CELLS, from, mathx.ALL_DIRS[0..SWEEP_CELLS].*);
}

pub const FLIT: f32 = 0.33;
pub const FRIGHT_REACH: i32 = 5;
pub const FLEE_TURNS: u8 = 4;
pub const FRIGHT_STATUS = "Runs from the hero, attacking only when cornered.";

const SLAM = Blow{ .strike = .{ .hit = .{ .lo = 2, .hi = 5 }, .verb = "slams", .slain = "crushed" } };
const NET = Net{ .range = 5, .pins = 2, .every = 4 };
const MEND = Mend{ .reach = 5, .amount = 8, .every = 3, .kin = &.{ .pib, .beefy_pib } };
const ICY = damage.Resists.init(.{ .cold = 100, .fire = -50, .chaos = 0, .lightning = 0 });
const FIERY = damage.Resists.init(.{ .cold = -50, .fire = 100, .chaos = 0, .lightning = 0 });

pub fn innateResist(k: Kind, status: resilience.Kind) u8 {
    return switch (status) {
        .stun => row(k).stun_resist,
        .fright => row(k).fright_resist,
        else => 0,
    };
}

pub fn row(k: Kind) Row {
    return switch (k) {
        inline .archer, .wizard, .knight => |h| heroRow(@field(heroes.Class, @tagName(h))),
        .rat => .{ .name = "rat", .movement = .ground, .foe_type = .beast, .hp = 6, .sight = 7, .blow = .{ .strike = .{ .hit = .{ .lo = 1, .hi = 3 }, .verb = "bites", .slain = "bitten to death" } } },
        .slime => .{ .name = "slime", .movement = .ground, .foe_type = .aberration, .hp = 40, .sight = 6, .blow = SLAM, .splits = .slime_half, .fright_resist = 100 },
        .slime_half => smaller(.slime, "half slime", .slime_quarter),
        .slime_quarter => smaller(.slime_half, "quarter slime", null),
        .bloat => .{ .name = "bloat", .movement = .flying, .foe_type = .aberration, .hp = 4, .sight = 7, .blow = .{ .burst = .gas }, .flits = true, .fright_resist = 100 },
        .pib => .{ .name = "pib", .movement = .ground, .foe_type = .beast, .hp = 10, .sight = 7, .blow = .{ .strike = .{ .hit = .{ .lo = 1, .hi = 3 }, .verb = "stabs", .slain = "stabbed to death", .bleeds = 30 } }, .flees = true },
        .beefy_pib => .{ .name = "beefy pib", .movement = .ground, .foe_type = .beast, .hp = 40, .sight = 7, .blow = .{ .strike = .{ .hit = .{ .lo = 3, .hi = 6 }, .verb = "pummels", .slain = "beaten to death", .stuns = 25 } }, .sweep_every = 4, .stun_resist = 75, .fright_resist = 50, .armour = 20 },
        .bandit_crossbowman => .{ .name = "bandit crossbowman", .movement = .ground, .foe_type = .humanoid, .hp = 10, .sight = bow.RANGE, .blow = .{ .strike = .{ .hit = bow.BASE, .verb = bow.VERB, .slain = "shot dead" } }, .ranged = .{ .range = bow.RANGE, .retreat = 2 }, .armour = 15, .fright_resist = 25 },
        .bandit_netter => .{ .name = "bandit netter", .movement = .ground, .foe_type = .humanoid, .hp = 10, .sight = 7, .blow = .{ .strike = .{ .hit = .{ .lo = 1, .hi = 3 }, .verb = "clubs", .slain = "clubbed down" } }, .keeps = 2, .net = NET, .armour = 10, .fright_resist = 25 },
        .bandit_shieldbearer => .{ .name = "bandit shieldbearer", .movement = .ground, .foe_type = .humanoid, .hp = 24, .sight = 7, .blow = .{ .strike = .{ .hit = .{ .lo = 2, .hi = 4 }, .verb = "bashes", .slain = "battered down", .knocks = true } }, .armour = 40, .stun_resist = 75, .fright_resist = 50 },
        .frost_wisp => .{ .name = "frost wisp", .movement = .flying, .foe_type = .aberration, .hp = 8, .sight = 7, .blow = .{ .strike = .{ .hit = .{ .lo = 1, .hi = 3 }, .verb = "touches", .slain = "frozen solid", .element = .cold, .chills = 100 } }, .flits = true, .resists = ICY, .fright_resist = 100 },
        .pyre_bloat => .{ .name = "pyre bloat", .movement = .flying, .foe_type = .aberration, .hp = 4, .sight = 7, .blow = .{ .burst = .fire }, .flits = true, .resists = FIERY, .fright_resist = 100 },
        .pib_shaman => .{ .name = "pib shaman", .movement = .ground, .foe_type = .beast, .hp = 12, .sight = 7, .blow = .{ .strike = .{ .hit = .{ .lo = 1, .hi = 2 }, .verb = "pokes", .slain = "poked to death" } }, .keeps = 3, .mends = MEND },
        .bog_leech => .{ .name = "bog leech", .movement = .swimming, .foe_type = .beast, .hp = 12, .sight = 5, .blow = .{ .strike = .{ .hit = .{ .lo = 2, .hi = 4 }, .verb = "bites", .slain = "drained dry", .bleeds = 50 } }, .lurks = true, .fright_resist = 100 },
        .mimic => .{ .name = "mimic", .movement = .ground, .foe_type = .aberration, .hp = 24, .sight = 7, .blow = .{ .strike = .{ .hit = .{ .lo = 3, .hi = 6 }, .verb = "chomps", .slain = "swallowed whole" } }, .disguised = true, .armour = 10, .fright_resist = 100 },
    };
}

/// The ground a `k` stands on: a swimmer's water, a mimic's where a chest could stand, the rest's any open ground.
pub fn groundFits(k: Kind, t: grid.Tile) bool {
    const r = row(k);
    if (r.movement == .swimming) return t.wet();
    if (r.disguised) return t.rewards();
    return !t.solid();
}

/// Where a `k` may be set down: its ground with no body, barrel, folk or barrier on it, and a mimic's off any door.
pub fn dwells(k: Kind, lv: *const grid.Level, p: P) bool {
    if (!grid.Level.inside(p) or !groundFits(k, lv.at(p)) or lv.taken(p) or lv.folkAt(p) != null or lv.hasBarrier(p)) return false;
    return !row(k).disguised or lv.doorAt(p) == null;
}

/// Where a `k` may be pushed or pulled to: wherever its feet, or its fins, can go.
pub fn holds(k: Kind, lv: *const grid.Level, p: P) bool {
    if (row(k).movement == .swimming) return dwells(k, lv, p);
    return lv.vacant(p);
}

fn heroRow(comptime c: heroes.Class) Row {
    return .{ .name = wording.word(c), .movement = .ground, .foe_type = null, .hp = c.attrs().life(), .sight = 10, .light = 5, .blow = .{ .strike = c.strike() } };
}

fn smaller(of: Kind, name: [:0]const u8, splits: ?Kind) Row {
    var r = row(of);
    r.name = name;
    r.hp = @divTrunc(r.hp, 2);
    r.splits = splits;
    return r;
}

pub fn plural(k: Kind) [:0]const u8 {
    return PLURALS.get(k);
}

const PLURALS = blk: {
    var t = std.EnumArray(Kind, [:0]const u8).initUndefined();
    for (std.enums.values(Kind)) |k| t.set(k, row(k).name ++ "s");
    t.set(.bandit_crossbowman, "bandit crossbowmen");
    t.set(.bog_leech, "bog leeches");
    break :blk t;
};

pub const Actor = struct {
    kind: Kind,
    at: P,
    hp: i32,
    max: i32,
    awake: bool = false,
    alive: bool = true,
    /// Split off this turn: it acts from the next.
    waits: bool = false,
    resists: damage.Resists = .initFill(0),
    burn: burning.Burn = .{},
    chill: glacial.Chill = .{},
    bleed: bleeding.Bleed = .{},
    resilience: resilience.State = .{},
    clock: clock.Clock = .{},
    pin: pinning.Pin = .{},
    shock: shock.Shock = .{},
    sunder: sunder.Sunder = .{},
    blind: blind.Blind = .{},
    confusion: confusion.Confusion = .{},
    ward: ward.Ward = .{},
    tactics: @import("tactics.zig").State = .{},
    /// Its turns left running from the hero.
    fright: u8 = 0,
    /// Its turns until it can sweep again.
    sweep_in: u8 = 0,
    /// Its turns until it can throw a net or mend again.
    ready_in: u8 = 0,
    /// Lurking out of the hero's reach.
    submerged: bool = false,
    /// Standing as a closed chest.
    disguised: bool = false,
    /// The ground its chest stands on.
    under: grid.Tile = .floor,

    pub fn of(k: Kind, at: P) Actor {
        return .{ .kind = k, .at = at, .hp = row(k).hp, .max = row(k).hp, .resists = row(k).resists, .submerged = row(k).lurks, .disguised = row(k).disguised };
    }

    /// Not seen as a body even where lit.
    pub fn veiled(self: Actor) bool {
        return self.submerged or self.disguised;
    }

    pub fn seenIn(self: Actor, lv: *const grid.Level) bool {
        return lv.isLit(self.at) and !self.veiled();
    }

    /// A living foe the hero sees.
    pub fn seenFoe(self: Actor, lv: *const grid.Level) bool {
        return self.alive and self.foe() and self.seenIn(lv);
    }

    /// Up to `n` hp back, never past its most: what it got.
    pub fn heal(self: *Actor, n: i32) i32 {
        const got = std.math.clamp(n, 0, @max(0, self.max - self.hp));
        self.hp += got;
        return got;
    }

    /// Its chest flung open: the ground comes back and it wakes.
    pub fn unmask(self: *Actor, lv: *grid.Level) void {
        if (!self.disguised) return;
        lv.set(self.at, self.under);
        self.disguised = false;
        self.awake = true;
    }

    pub fn hurt(self: Actor) bool {
        return self.hp < self.max;
    }

    pub fn takeStatus(self: *Actor, kind: resilience.Kind, rng: *mathx.Rng) bool {
        return self.resilience.take(kind, innateResist(self.kind, kind), rng);
    }

    pub fn foe(self: Actor) bool {
        return self.kind.foe();
    }

    pub fn afflicted(self: Actor) bool {
        inline for (AFFLICTIONS) |k| {
            if (@field(self, @tagName(k)).turns > 0) return true;
        }
        return false;
    }

    /// Something its own turns wear: an affliction, a pin or a chill.
    pub fn wearsAny(self: Actor) bool {
        return self.pin.turns > 0 or self.chill.turns > 0 or self.afflicted();
    }

    /// One of its turns spent under each of `AFFLICTIONS`, in order.
    pub fn wearAfflictions(self: *Actor) Afflicted {
        var out = Afflicted{};
        inline for (AFFLICTIONS) |k| {
            const status = &@field(self, @tagName(k));
            const ran = status.turns > 0;
            _ = status.wear();
            switch (k) {
                .blind => out.blinded = ran,
                .confusion => out.confused = ran,
                else => {},
            }
        }
        return out;
    }

    /// The turn is over: what started or split off in it is no longer fresh.
    pub fn settle(self: *Actor) void {
        self.waits = false;
        inline for (std.meta.fields(Actor)) |f| {
            if (@typeInfo(f.type) == .@"struct" and @hasDecl(f.type, "settle")) @field(self, f.name).settle();
        }
    }
};

/// What a turn worn under them was.
pub const Afflicted = struct { blinded: bool = false, confused: bool = false };

/// The statuses worn on a body's own turn, each kept in the `Actor` field its kind names.
pub const AFFLICTIONS = [_]resilience.Kind{ .shock, .sunder, .blind, .confusion };

pub const MAX: usize = 64;

/// The last way a body stepped, struck or aimed across.
pub const Facing = enum { right, left };

test "heroes and foes share independent status buildup with innate beefy pib stun resistance" {
    var rng = mathx.Rng.init(0x51A7);
    const kinds = [_]Kind{ .archer, .wizard, .knight, .rat, .beefy_pib };
    for (kinds) |kind| {
        var a = Actor.of(kind, .{ .x = 1, .y = 1 });
        for (std.enums.values(resilience.Kind)) |status| {
            var n: usize = 0;
            for (0..1000) |_| n += @intFromBool(a.takeStatus(status, &rng));
            try std.testing.expectEqual(@as(usize, (mathx.PERCENT - innateResist(kind, status) + resilience.GAIN - 1) / resilience.GAIN), n);
        }
        for (0..resilience.EXPIRY + 1) |_| a.settle();
        try std.testing.expectEqual(@as(u8, 0), a.resilience.peak().percent);
    }
    std.debug.print("status buildup: {d} bodies, all {d} ailments; beefy pib has {d}% innate stun and {d}% fright resistance\n", .{ kinds.len, std.enums.values(resilience.Kind).len, row(.beefy_pib).stun_resist, row(.beefy_pib).fright_resist });
}

pub const Tally = struct { left: usize = 0, total: usize = 0 };

pub fn Ids(comptime N: usize) type {
    return struct {
        id: [N]u16 = undefined,
        n: usize = 0,

        pub fn slice(self: *const @This()) []const u16 {
            return self.id[0..self.n];
        }

        pub fn push(self: *@This(), id: u16) void {
            self.id[self.n] = id;
            self.n += 1;
        }

        pub fn has(self: *const @This(), id: u16) bool {
            return std.mem.indexOfScalar(u16, self.slice(), id) != null;
        }
    };
}

/// Ids are 1-based so `grid.NO_ONE` (0) is never a body.
pub const Pool = struct {
    items: [MAX]Actor = undefined,
    n: usize = 0,

    pub const COUNTED = .{.{ "items", "n" }};

    pub fn idOf(i: usize) u16 {
        return @intCast(i + 1);
    }

    pub fn slot(id: u16) usize {
        return id - 1;
    }

    pub fn spawn(self: *Pool, lv: *grid.Level, a: Actor) u16 {
        std.debug.assert(self.n < MAX);
        const id = idOf(self.n);
        self.items[self.n] = a;
        if (a.disguised) {
            self.items[self.n].under = lv.at(a.at);
            lv.set(a.at, .chest);
        }
        self.n += 1;
        lv.stand(a.at, id);
        return id;
    }

    /// Lurkers out of reach of the hero at `hero` sink; those within it rise.
    pub fn surface(self: *Pool, hero: P) void {
        for (self.slice()) |*a| a.submerged = row(a.kind).lurks and mathx.dist(a.at, hero) > LURK_REACH;
    }

    pub fn get(self: *Pool, id: u16) ?*Actor {
        if (id == grid.NO_ONE or id > self.n) return null;
        const a = &self.items[slot(id)];
        return if (a.alive) a else null;
    }

    pub fn slice(self: *Pool) []Actor {
        return self.items[0..self.n];
    }

    pub fn tally(self: *Pool, k: Kind) Tally {
        var t = Tally{};
        for (self.slice()) |a| {
            if (a.kind.family() != k) continue;
            t.total += 1;
            if (a.alive) t.left += 1;
        }
        return t;
    }

    pub fn move(self: *Pool, lv: *grid.Level, id: u16, to: P) void {
        const a = self.get(id) orelse return;
        lv.clear(a.at);
        a.at = to;
        lv.stand(to, id);
    }

    /// The only path harm takes off hp; true on the killing blow.
    pub fn damage(self: *Pool, lv: *grid.Level, id: u16, amount: i32) bool {
        const a = self.get(id) orelse return false;
        a.hp = @max(0, a.hp - amount);
        a.awake = true;
        if (a.hp > 0) return false;
        a.alive = false;
        lv.clear(a.at);
        return true;
    }

    /// Call after `damage`; with no free cell beside it, it splits on a later blow. The new body's id.
    pub fn split(self: *Pool, lv: *grid.Level, id: u16, rng: *mathx.Rng) ?u16 {
        const a = self.get(id) orelse return null;
        const next = row(a.kind).splits orelse return null;
        if (a.hp * 2 >= a.max or self.n == MAX) return null;
        const d = rng.pickWhere(mathx.Dir, mathx.ALL_DIRS, Step{ .lv = lv, .from = a.at, .id = grid.NO_ONE }, Step.free) orelse return null;
        const hp = @max(1, @divTrunc(a.hp, 2));
        a.kind = next;
        a.hp = hp;
        a.max = hp;
        var half = a.*;
        half.at = a.at.add(d.delta());
        half.awake = true;
        half.waits = true;
        return self.spawn(lv, half);
    }
};

const Step = struct {
    lv: *const grid.Level,
    from: P,
    id: u16,
    prey: u16 = grid.NO_ONE,

    fn free(s: Step, d: mathx.Dir) bool {
        return s.lv.stepOk(s.from, d, s.id);
    }

    fn flits(s: Step, d: mathx.Dir) bool {
        const onto = s.lv.passOk(s.from, d) and s.lv.who(s.from.add(d.delta())) == s.prey;
        return onto or (s.free(d) and !shuns(s.lv, s.from, d));
    }
};

/// Brogue's `monsterAvoids`: gas and flames are shunned by a body not already in some.
fn shuns(lv: *const grid.Level, from: P, d: mathx.Dir) bool {
    const to = from.add(d.delta());
    return (lv.gassy(to) and !lv.gassy(from)) or (lv.burning(to) and !lv.burning(from));
}

/// The water step that most closes on `toward`, by steps then by the straighter line; none that gains.
pub fn swim(lv: *const grid.Level, from: P, k: Kind, toward: P) ?mathx.Dir {
    var near = grid.Nearest{ .from = toward, .best_d = mathx.dist(from, toward), .best_line = mathx.distEuclid(from, toward) };
    var best: ?mathx.Dir = null;
    for (mathx.ALL_DIRS) |d| {
        const to = from.add(d.delta());
        if (!dwells(k, lv, to)) continue;
        near.offer(to);
        if (near.best) |b| {
            if (b.eq(to)) best = d;
        }
    }
    return best;
}

/// Downhill on `flow`, a walked-distance map from the hero.
pub fn chase(lv: *const grid.Level, from: P, id: u16, flow: *const [grid.CELLS]i32) ?mathx.Dir {
    return climb(lv, from, id, flow, -1);
}

/// Uphill on `flow`: the step furthest a walk from the hero, or none when no step gains on it.
pub fn flee(lv: *const grid.Level, from: P, id: u16, flow: *const [grid.CELLS]i32) ?mathx.Dir {
    return climb(lv, from, id, flow, 1);
}

fn climb(lv: *const grid.Level, from: P, id: u16, flow: *const [grid.CELLS]i32, comptime sign: i32) ?mathx.Dir {
    var best: ?mathx.Dir = null;
    var best_d = flow[grid.Level.idx(from)];
    if (best_d < 0) return null;
    for (mathx.ALL_DIRS) |d| {
        if (!lv.stepOk(from, d, id) or shuns(lv, from, d)) continue;
        const v = flow[grid.Level.idx(from.add(d.delta()))];
        if (v >= 0 and (v - best_d) * sign > 0) {
            best_d = v;
            best = d;
        }
    }
    return best;
}

/// A confused step: any free cell, gas or not.
pub fn stumble(lv: *const grid.Level, from: P, id: u16, rng: *mathx.Rng) ?mathx.Dir {
    return rng.pickWhere(mathx.Dir, mathx.ALL_DIRS, Step{ .lv = lv, .from = from, .id = id }, Step.free);
}

/// Brogue's `randValidDirectionFrom`: any step it may take and does not shun, or one onto `prey`.
pub fn flit(lv: *const grid.Level, from: P, id: u16, prey: u16, rng: *mathx.Rng) ?mathx.Dir {
    return rng.pickWhere(mathx.Dir, mathx.ALL_DIRS, Step{ .lv = lv, .from = from, .id = id, .prey = prey }, Step.flits);
}

test "a spawned body stands on the grid and leaves it when it dies" {
    var lv = grid.openFloor();
    var pool = Pool{};
    const id = pool.spawn(&lv, Actor.of(.rat, .{ .x = 5, .y = 5 }));
    try std.testing.expectEqual(id, lv.who(.{ .x = 5, .y = 5 }));
    try std.testing.expect(!pool.damage(&lv, id, 2));
    try std.testing.expect(pool.get(id).?.awake);
    try std.testing.expect(pool.damage(&lv, id, 99));
    try std.testing.expectEqual(grid.NO_ONE, lv.who(.{ .x = 5, .y = 5 }));
    try std.testing.expectEqual(@as(?*Actor, null), pool.get(id));
}

test "a slime a blow leaves under half its hp splits in two of the next kind, each on half what it had left" {
    var lv = grid.openFloor();
    var pool = Pool{};
    var rng = mathx.Rng.init(0x5717);
    const at = P{ .x = 10, .y = 10 };
    const id = pool.spawn(&lv, Actor.of(.slime, at));
    const full = row(.slime).hp;
    try std.testing.expect(!pool.damage(&lv, id, @divTrunc(full, 2)));
    try std.testing.expectEqual(@as(?u16, null), pool.split(&lv, id, &rng));
    try std.testing.expect(!pool.damage(&lv, id, 3));
    const left = pool.get(id).?.hp;
    const other = pool.split(&lv, id, &rng) orelse return error.NoSplit;
    const a = pool.get(id).?.*;
    const b = pool.get(other).?.*;
    std.debug.print("a slime of {d} hp left on {d}: two half slimes of {d}/{d} hp, a cell apart\n", .{ full, left, a.hp, a.max });
    for ([_]Actor{ a, b }) |s| {
        try std.testing.expectEqual(Kind.slime_half, s.kind);
        try std.testing.expectEqual(@divTrunc(left, 2), s.hp);
        try std.testing.expectEqual(s.hp, s.max);
    }
    try std.testing.expectEqual(at, a.at);
    try std.testing.expectEqual(@as(i32, 1), mathx.dist(a.at, b.at));
    try std.testing.expectEqual(other, lv.who(b.at));
    try std.testing.expect(b.awake and b.waits and !a.waits);
    for ([_]u16{ id, other }) |half| {
        try std.testing.expect(!pool.damage(&lv, half, pool.get(half).?.hp - 1));
        const q = pool.split(&lv, half, &rng) orelse return error.NoSplit;
        for ([_]u16{ half, q }) |s| {
            try std.testing.expectEqual(Kind.slime_quarter, pool.get(s).?.kind);
            try std.testing.expectEqual(@as(i32, 1), pool.get(s).?.max);
        }
    }
    try std.testing.expectEqual(Tally{ .left = 4, .total = 4 }, pool.tally(.slime));
    for (pool.slice()) |s| try std.testing.expectEqual(Kind.slime_quarter, s.kind);
    const last = pool.spawn(&lv, Actor.of(.slime_quarter, .{ .x = 30, .y = 30 }));
    try std.testing.expect(!pool.damage(&lv, last, row(.slime_quarter).hp - 1));
    try std.testing.expectEqual(@as(?u16, null), pool.split(&lv, last, &rng));
}

test "a slime with no free cell beside it waits to split until a blow finds one" {
    var lv = grid.openFloor();
    var pool = Pool{};
    var rng = mathx.Rng.init(0x5717);
    const at = P{ .x = 10, .y = 10 };
    const id = pool.spawn(&lv, Actor.of(.slime, at));
    for (mathx.ALL_DIRS) |d| lv.set(at.add(d.delta()), .wall);
    lv.set(at.add(mathx.Dir.e.delta()), .floor);
    lv.putBarrel(at.add(mathx.Dir.e.delta()));
    try std.testing.expect(!pool.damage(&lv, id, row(.slime).hp - 3));
    try std.testing.expectEqual(@as(?u16, null), pool.split(&lv, id, &rng));
    try std.testing.expectEqual(Kind.slime, pool.get(id).?.kind);
    _ = lv.breakBarrel(at.add(mathx.Dir.e.delta()));
    try std.testing.expect(!pool.damage(&lv, id, 1));
    const other = pool.split(&lv, id, &rng) orelse return error.NoSplit;
    try std.testing.expectEqual(at.add(mathx.Dir.e.delta()), pool.get(other).?.at);
    try std.testing.expectEqual(@as(i32, 1), pool.get(other).?.hp);
}

test "every foe a floor is stocked with is its own family, and a slime ends as four quarters at most" {
    try std.testing.expectEqualSlices(Kind, &.{ .rat, .slime, .bloat, .pib, .beefy_pib, .bandit_crossbowman, .bandit_netter, .bandit_shieldbearer, .frost_wisp, .pyre_bloat, .pib_shaman, .bog_leech, .mimic }, &FOES);
    try std.testing.expectEqual(Kind.slime, Kind.slime_quarter.family());
    try std.testing.expectEqual(Kind.rat, Kind.rat.family());
    try std.testing.expectEqual(@as(usize, 4), most(.slime));
    try std.testing.expectEqual(@as(usize, 1), most(.rat));
}

test "a sweep reaches every cell round it a step could, and none through a wall" {
    var lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    try std.testing.expectEqual(mathx.ALL_DIRS.len, sweep(&lv, from).n);
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    const s = sweep(&lv, from);
    try std.testing.expect(!s.has(.{ .x = 21, .y = 20 }) and !s.has(from));
    std.debug.print("sweep: {d} cells in the open, {d} beside a wall\n", .{ mathx.ALL_DIRS.len, s.n });
    try std.testing.expectEqual(mathx.ALL_DIRS.len - 1, s.n);
}

test "chase walks round a wall toward the hero" {
    var lv = grid.openFloor();
    var y: i32 = 1;
    while (y < 12) : (y += 1) lv.set(.{ .x = 10, .y = y }, .wall);
    var flow: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const hero = P{ .x = 12, .y = 5 };
    _ = grid.distances(&lv, hero, &flow, &queue);
    var at = P{ .x = 8, .y = 5 };
    var steps: usize = 0;
    while (mathx.dist(at, hero) > 1 and steps < 40) : (steps += 1) {
        const d = chase(&lv, at, 1, &flow) orelse return error.Stuck;
        at = at.add(d.delta());
    }
    std.debug.print("round a wall: {d} steps to reach a hero 4 cells away\n", .{steps});
    try std.testing.expect(mathx.dist(at, hero) <= 1);
}

test "flee gains a step on the hero every turn, and stops in a dead end" {
    const lv = grid.openFloor();
    var flow: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    _ = grid.distances(&lv, .{ .x = 10, .y = 10 }, &flow, &queue);
    var at = P{ .x = 12, .y = 10 };
    const start = flow[grid.Level.idx(at)];
    for (0..FLEE_TURNS) |_| {
        const d = flee(&lv, at, 1, &flow) orelse return error.Stuck;
        at = at.add(d.delta());
    }
    std.debug.print("{d} turns fleeing: {d} walked steps from the hero, from {d}\n", .{ FLEE_TURNS, flow[grid.Level.idx(at)], start });
    try std.testing.expectEqual(start + FLEE_TURNS, flow[grid.Level.idx(at)]);
    var pit = grid.openFloor();
    for (mathx.ALL_DIRS) |d| pit.set((P{ .x = 20, .y = 20 }).add(d.delta()), .wall);
    pit.set(.{ .x = 19, .y = 20 }, .floor);
    _ = grid.distances(&pit, .{ .x = 17, .y = 20 }, &flow, &queue);
    try std.testing.expectEqual(@as(?mathx.Dir, null), flee(&pit, .{ .x = 20, .y = 20 }, 1, &flow));
}

test "chase will not step from clean air into gas, but walks on through it from inside" {
    var lv = grid.openFloor();
    var flow: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    _ = grid.distances(&lv, .{ .x = 20, .y = 5 }, &flow, &queue);
    var y: i32 = 1;
    while (y < grid.H - 1) : (y += 1) lv.addGas(.{ .x = 15, .y = y }, 50);
    const at = P{ .x = 14, .y = 5 };
    try std.testing.expectEqual(@as(?mathx.Dir, null), chase(&lv, at, 1, &flow));
    lv.addGas(at, 50);
    const d = chase(&lv, at, 1, &flow) orelse return error.Stuck;
    try std.testing.expectEqual(@as(i32, 15), at.add(d.delta()).x);
}

test "a flit goes every open way about evenly, onto its prey too, and never into gas from clean air" {
    var lv = grid.openFloor();
    var rng = mathx.Rng.init(0xF117);
    const from = P{ .x = 10, .y = 10 };
    lv.stand(from, 2);
    lv.stand(.{ .x = 11, .y = 10 }, 1);
    lv.putBarrel(.{ .x = 9, .y = 10 });
    lv.addGas(.{ .x = 10, .y = 9 }, 30);
    const TRIES: usize = 6000;
    var counts = std.EnumArray(mathx.Dir, usize).initFill(0);
    for (0..TRIES) |_| counts.getPtr(flit(&lv, from, 2, 1, &rng) orelse return error.Stuck).* += 1;
    std.debug.print("{d} flits beside a barrel west and gas north:", .{TRIES});
    for (mathx.ALL_DIRS) |d| std.debug.print(" {s} {d}", .{ @tagName(d), counts.get(d) });
    std.debug.print("\n", .{});
    try std.testing.expectEqual(@as(usize, 0), counts.get(.w));
    try std.testing.expectEqual(@as(usize, 0), counts.get(.n));
    for ([_]mathx.Dir{ .ne, .e, .se, .s, .sw, .nw }) |d| {
        try std.testing.expect(counts.get(d) * 6 > TRIES * 85 / 100 and counts.get(d) * 6 < TRIES * 115 / 100);
    }
}

test "a leech swims only through water toward the hero and surfaces only beside it" {
    var lv = grid.openFloor();
    var cells = grid.Cells.of(.{ .x = 10, .y = 10 }, .{ .x = 16, .y = 11 });
    while (cells.next()) |p| lv.set(p, if (p.x < 13) .water else .shallows);
    var pool = Pool{};
    const id = pool.spawn(&lv, Actor.of(.bog_leech, .{ .x = 10, .y = 10 }));
    const hero = P{ .x = 18, .y = 10 };
    var at = pool.get(id).?.at;
    var steps: usize = 0;
    while (swim(&lv, at, .bog_leech, hero)) |d| : (steps += 1) {
        pool.move(&lv, id, at.add(d.delta()));
        at = pool.get(id).?.at;
        try std.testing.expect(lv.at(at).wet());
    }
    std.debug.print("bog leech: {d} strokes to the last water cell, {d} from a hero on dry ground\n", .{ steps, mathx.dist(at, hero) });
    try std.testing.expectEqual(P{ .x = 15, .y = 10 }, at);
    pool.surface(hero);
    lv.lit = @splat(true);
    try std.testing.expect(pool.get(id).?.submerged and !pool.get(id).?.seenIn(&lv));
    pool.surface(.{ .x = 16, .y = 11 });
    try std.testing.expect(!pool.get(id).?.submerged);
    try std.testing.expect(dwells(.bog_leech, &lv, .{ .x = 11, .y = 10 }) and !dwells(.bog_leech, &lv, .{ .x = 11, .y = 12 }));
    try std.testing.expect(!holds(.bog_leech, &lv, .{ .x = 16, .y = 10 }) and holds(.rat, &lv, .{ .x = 16, .y = 10 }));
}

test "a mimic stands as a closed chest on its own ground until unmasked" {
    var lv = grid.openFloor();
    lv.set(.{ .x = 5, .y = 5 }, .grass);
    var pool = Pool{};
    try std.testing.expect(dwells(.mimic, &lv, .{ .x = 5, .y = 5 }) and !dwells(.mimic, &lv, .{ .x = 0, .y = 0 }));
    const id = pool.spawn(&lv, Actor.of(.mimic, .{ .x = 5, .y = 5 }));
    const m = pool.get(id).?;
    try std.testing.expect(m.disguised and m.veiled() and !m.awake);
    try std.testing.expectEqual(grid.Tile.chest, lv.at(m.at));
    try std.testing.expectEqual(id, lv.who(m.at));
    m.unmask(&lv);
    try std.testing.expectEqual(grid.Tile.grass, lv.at(m.at));
    try std.testing.expect(!m.disguised and m.awake);
}
