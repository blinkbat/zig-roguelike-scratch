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
const flask = @import("../play/flask.zig");
const heroes = @import("../play/hero.zig");
const items = @import("../play/items.zig");
const passives = @import("../play/passives.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const journal = @import("../ui/journal.zig");
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
pub const Tick = enum { gassed, burned, bled, worn };
/// The ticks a body's turn has run, which a half split off it mid-turn has had too.
pub const Ran = std.EnumSet(Tick);

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
    /// The hero stepped or leapt since the last turn ended, which tears a bleed wider.
    stepped: bool = false,
    displaced: std.StaticBitSet(actor.MAX) = .initEmpty(),
    inventory: items.Inventory = .{},
    growth: progress.State = progress.State.of(heroes.DEFAULT),
    ground: items.Ground = .{},
    loot_rng: mathx.Rng = mathx.Rng.init(1),
    log: journal.Log = .{},
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

    pub fn isHero(self: *const Simulation, slot: usize) bool {
        return actor.Pool.idOf(slot) == self.hero;
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
        const sight = self.heroRow().sight;
        lume.see(&self.lv, from, sight, lume.skyReach(self.outdoors, self.clock.hour(), sight), carried[0..n]);
    }

    pub fn sayAt(self: *Simulation, at: P, comptime fmt: []const u8, args: anytype) void {
        self.sayAs(.status, at, fmt, args);
    }

    /// Logged only if `at` is in sight.
    pub fn sayAs(self: *Simulation, kind: journal.Kind, at: P, comptime fmt: []const u8, args: anytype) void {
        if (self.lv.isLit(at)) self.log.push(kind, fmt, args);
    }
};
