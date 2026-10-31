const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const climate = @import("../map/climate.zig");
const day = @import("../map/day.zig");
const lume = @import("../map/lume.zig");
const actor = @import("../play/actor.zig");
const chronicle = @import("../play/chronicle.zig");
const attrs = @import("../play/attrs.zig");
const terrain = @import("../play/terrain.zig");
const resilience = @import("../play/resilience.zig");
const sunder = @import("../play/sunder.zig");
const blind = @import("../play/blind.zig");
const damage = @import("../play/damage.zig");
const flask = @import("../play/flask.zig");
const heroes = @import("../play/hero.zig");
const items = @import("../play/items.zig");
const passives = @import("../play/passives.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const log = @import("../play/log.zig");
const trigger = @import("../play/trigger.zig");
const P = mathx.P;

pub const Flasks = std.EnumArray(flask.Kind, flask.Flask);

/// A node as the hero left it.
pub const Visit = struct {
    lv: grid.Level,
    pool: actor.Pool,
    facing: [actor.MAX]actor.Facing,
    ground: items.Ground,
};

/// A body's harm ticks, each run at most once a turn.
pub const Tick = enum { gassed, scalded, healed, burned, bled, worn };
/// The ticks a body's turn has run, which a half split off it mid-turn has had too.
pub const Ran = std.EnumSet(Tick);

pub const DamageResult = struct {
    target: actor.ActorId,
    dmg: i32 = 0,
    lethal: bool = false,
    mana: i32 = 0,
};

pub const UNKILLABLE_HP: i32 = 1;

/// The run as it is, whatever has been drawn of it.
pub const Simulation = struct {
    name: heroes.Name = heroes.DEFAULT.unnamed(),
    /// Set before a run begins.
    class: heroes.Class = heroes.DEFAULT,
    clock: day.Clock = .{},
    outdoors: bool = false,
    /// Kept across runs, never saved.
    unkillable: bool = false,
    unsaved: bool = false,
    lv: grid.Level,
    pool: actor.Pool = .{},
    hero: u16 = grid.NO_ONE,
    /// The map being played; null plays one generated floor.
    map: ?*const atlas.Atlas = null,
    node: usize = 0,
    /// Indexed by node.
    visits: *[atlas.MAX_NODES]Visit,
    visited: std.StaticBitSet(atlas.MAX_NODES) = .initEmpty(),
    /// The door the hero stepped onto this turn, gone through once the turn is drawn.
    travel: ?atlas.Link = null,
    rng: mathx.Rng,
    seed: u64 = 0,
    kills: usize = 0,
    gold: i32 = 0,
    mana: i32 = heroes.DEFAULT.attrs().mana(),
    mana_recovery: i32 = 0,
    flasks: Flasks = .initFill(.{}),
    /// Turns until each can be used again.
    cooldown: std.EnumArray(skillbar.Act, u8) = .initFill(0),
    /// The hero stepped, leapt or was knocked back since its last action, which tears a bleed wider.
    stepped: bool = false,
    displaced: std.StaticBitSet(actor.MAX) = .initEmpty(),
    inventory: items.Inventory = .{ .gear = .flasks },
    growth: progress.State = progress.State.of(heroes.DEFAULT),
    ground: items.Ground = .{},
    loot_rng: mathx.Rng = mathx.Rng.init(1),
    log: log.Log = .{},
    /// The map's triggers and conversation as the run has them.
    plot: trigger.Runtime = .{},
    chronicle: chronicle.Chronicle = .{},
    /// Living foes at turn start, nearest first; also their presentation order.
    order: [actor.MAX]u16 = undefined,
    order_n: usize = 0,
    ran: [actor.MAX]Ran = @splat(Ran.initEmpty()),
    /// Terrain only, so the turn's first chase fills it for every foe after.
    flowed: bool = false,
    flow: [grid.CELLS]i32,
    queue: [grid.CELLS]u32,

    pub fn heroActor(self: *Simulation) ?*actor.Actor {
        return self.pool.get(self.hero);
    }

    pub fn resolveDamage(self: *Simulation, target: actor.ActorId, amount: i32) DamageResult {
        const a = self.pool.get(target.value) orelse return .{ .target = target };
        const absorbed = if (target.value == self.hero) a.ward.takes(self.mana, amount) else 0;
        self.mana -= absorbed;
        const left = amount - absorbed;
        const taken = if (target.value == self.hero and self.unkillable) std.math.clamp(a.hp - UNKILLABLE_HP, 0, left) else left;
        return .{ .target = target, .dmg = taken, .lethal = self.pool.damage(&self.lv, target.value, taken), .mana = absorbed };
    }

    pub fn recoverLife(self: *Simulation, amount: i32) bool {
        const h = self.heroActor() orelse return false;
        return amount > 0 and h.heal(amount) > 0;
    }

    pub fn finishTurn(self: *Simulation) void {
        for (self.pool.slice()) |*a| a.settle();
        self.clearTurnMarks();
    }

    pub fn resetTransientTurn(self: *Simulation) void {
        self.travel = null;
        self.order_n = 0;
        self.clearTurnMarks();
        self.flowed = false;
    }

    fn clearTurnMarks(self: *Simulation) void {
        self.ran = @splat(Ran.initEmpty());
        self.displaced = .initEmpty();
    }

    pub fn heroMoved(self: *Simulation) void {
        if (self.heroActor()) |h| h.tactics.steady = 0;
        self.stepped = true;
    }

    pub fn heroSteady(self: *const Simulation) u8 {
        const h = self.heroBody() orelse return 0;
        return h.tactics.steady;
    }

    pub fn heroSlot(self: *const Simulation) ?usize {
        return if (self.hero == grid.NO_ONE) null else actor.Pool.slot(self.hero);
    }

    /// Living or not.
    pub fn heroBody(self: *const Simulation) ?*const actor.Actor {
        const i = self.heroSlot() orelse return null;
        return &self.pool.items[i];
    }

    pub fn heroAt(self: *const Simulation) ?P {
        return (self.heroBody() orelse return null).at;
    }

    /// What the map's triggers read of the run.
    pub fn world(self: *const Simulation) trigger.World {
        var w = trigger.World{ .node = self.node, .hero = self.heroAt() orelse .{ .x = 0, .y = 0 } };
        for (self.pool.constSlice()) |a| {
            if (a.alive and a.foe()) w.alive.getPtr(a.kind.family()).* += 1;
        }
        return w;
    }

    pub fn isHero(self: *const Simulation, slot: usize) bool {
        return actor.Pool.idOf(slot) == self.hero;
    }

    /// A body stands at `p` that nothing shows: a chest that is a mimic, a leech under the water.
    pub fn hiddenAt(self: *const Simulation, p: P) bool {
        const a = self.pool.getConst(self.lv.who(p)) orelse return false;
        return a.veiled();
    }

    pub fn heroRow(self: *const Simulation) actor.Row {
        return actor.row(self.class.kind());
    }

    pub fn heroAttrs(self: *const Simulation) attrs.Attrs {
        return self.inventory.gear.stats(self.growth.attributes(self.class));
    }

    pub fn heroPerks(self: *const Simulation) passives.Perks {
        return self.inventory.gear.perks(self.growth.perks());
    }

    pub fn combatStats(self: *const Simulation, a: *const actor.Actor) terrain.Stats {
        return self.combatStatsAt(a, a.at, a.resilience, a.sunder);
    }

    pub fn combatStatsAt(self: *const Simulation, a: *const actor.Actor, at: P, buildup: resilience.State, sundered: sunder.Sunder) terrain.Stats {
        var base = terrain.Stats{ .elements = a.resists, .armour = actor.row(a.kind).armour };
        if (!a.foe()) {
            const by = self.heroAttrs();
            base.dodge = by.dodge();
            base.armour = by.armour;
        }
        base.armour -= sundered.lost();
        for (std.enums.values(resilience.Kind)) |k| {
            base.statuses.set(k, @as(i16, actor.innateResist(a.kind, k)) + buildup.meters.get(k).percent);
        }
        return base.on(self.lv.at(at));
    }

    pub fn takeStatus(self: *Simulation, a: *actor.Actor, kind: resilience.Kind) bool {
        return a.resilience.takeResisted(kind, self.combatStats(a).statuses.get(kind), &self.rng);
    }

    pub fn procStatus(self: *Simulation, a: *actor.Actor, kind: resilience.Kind, chance: u32) bool {
        const resistance = self.combatStats(a).statuses.get(kind);
        const effective = damage.resistedChance(chance, @min(0, resistance));
        return damage.procs(&self.rng, effective) and self.takeStatus(a, kind);
    }

    /// `a` held `turns` longer unless its pin resistance holds; true when it is.
    pub fn pinFor(self: *Simulation, a: *actor.Actor, turns: u8) bool {
        if (turns == 0 or !self.takeStatus(a, .pin)) return false;
        a.pin.extend(turns);
        return true;
    }

    /// Fire takes hold of `a` as far as its fire and burn resistance allow; true when it does.
    pub fn ignite(self: *Simulation, a: *actor.Actor) bool {
        const chance = damage.resistedChance(mathx.PERCENT, self.combatStats(a).elements.get(.fire));
        if (!self.procStatus(a, .burn, chance)) return false;
        a.burn.start();
        return true;
    }

    pub fn lifeMax(self: *const Simulation) i32 {
        return self.heroAttrs().life();
    }

    pub fn manaMax(self: *const Simulation) i32 {
        return self.heroAttrs().mana();
    }

    pub fn gainMana(self: *Simulation, n: i32) void {
        self.mana = @min(self.manaMax(), self.mana + n);
    }

    pub fn manaRegen(self: *const Simulation) i32 {
        return heroes.manaRegen(self.heroPerks());
    }

    /// Levels gained so far, the current one's progress as the fraction.
    pub fn xpLevels(self: *const Simulation) f32 {
        const xp: f32 = @floatFromInt(self.growth.xp);
        const needed: f32 = @floatFromInt(self.growth.needed());
        return @as(f32, @floatFromInt(self.growth.level - 1)) + xp / needed;
    }

    pub fn leadsTo(self: *const Simulation, p: P) ?atlas.Link {
        const w = self.map orelse return null;
        const k = self.lv.doorAt(p) orelse return null;
        return w.door(.{ .node = self.node, .door = k }).to;
    }

    pub fn outdoorsNow(self: *const Simulation) bool {
        const w = self.map orelse return false;
        return w.node[self.node].outdoor();
    }

    pub fn climateNow(self: *const Simulation) climate.Climate {
        const w = self.map orelse return .{};
        return w.node[self.node].sky();
    }

    /// What the hero sees from `from`, by its own sight, the sky's and every carried light.
    pub fn see(self: *Simulation, from: P) void {
        var carried: [actor.MAX]lume.Source = undefined;
        var n: usize = 0;
        for (self.pool.slice(), 0..) |a, i| {
            const r = actor.row(a.kind).light;
            if (!a.alive or r <= 0) continue;
            carried[n] = .{ .at = if (self.isHero(i)) from else a.at, .reach = r };
            n += 1;
        }
        const sight = blind.sight(if (self.heroBody()) |h| h.blind.turns > 0 else false, self.heroRow().sight);
        lume.see(&self.lv, from, sight, lume.skyReach(self.outdoors, self.clock.hour(), sight), carried[0..n]);
    }

    pub fn sayAt(self: *Simulation, at: P, comptime fmt: []const u8, args: anytype) void {
        self.sayAs(.status, at, fmt, args);
    }

    /// Logged only if `at` is in sight.
    pub fn sayAs(self: *Simulation, kind: log.Kind, at: P, comptime fmt: []const u8, args: anytype) void {
        if (self.lv.isLit(at)) self.log.push(kind, fmt, args);
    }

    /// Logged only if `a` is seen, not underwater or in its chest.
    pub fn sayOf(self: *Simulation, a: *const actor.Actor, comptime fmt: []const u8, args: anytype) void {
        if (a.seenIn(&self.lv)) self.log.push(.status, fmt, args);
    }
};
