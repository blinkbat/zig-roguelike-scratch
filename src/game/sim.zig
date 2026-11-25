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
const loot = @import("../play/loot.zig");
const terrain = @import("../play/terrain.zig");
const resilience = @import("../play/resilience.zig");
const sunder = @import("../play/sunder.zig");
const blind = @import("../play/blind.zig");
const burning = @import("../play/burning.zig");
const bleeding = @import("../play/bleeding.zig");
const damage = @import("../play/damage.zig");
const flask = @import("../play/flask.zig");
const heroes = @import("../play/hero.zig");
const ground_items = @import("../play/ground_items.zig");
const inventory = @import("../play/inventory.zig");
const passives = @import("../play/passives.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const log = @import("../play/log.zig");
const trigger = @import("../play/trigger.zig");
const P = mathx.P;

pub const Flasks = std.EnumArray(flask.Kind, flask.Flask);

pub const Visit = struct {
    lv: grid.Level,
    pool: actor.Pool,
    facing: [actor.MAX]actor.Facing,
    ground: ground_items.Ground,
};

/// Each runs at most once a turn.
pub const Tick = enum {
    gassed,
    scalded,
    healed,
    scorched,
    burned,
    bled,
    worn,

    pub fn gas(t: Tick) ?grid.Gas {
        return switch (t) {
            .gassed => .caustic,
            .scalded => .steam,
            .healed => .healing,
            .scorched, .burned, .bled, .worn => null,
        };
    }

    pub fn source(t: Tick) ?chronicle.Source {
        return switch (t) {
            .gassed => .gas,
            .scalded => .steam,
            .burned, .scorched => .burn,
            .bled => .bleed,
            .healed, .worn => null,
        };
    }
};
/// The ticks a body's turn has run, which a half split off it mid-turn has had too.
pub const Ran = std.EnumSet(Tick);

pub const DamageResult = struct {
    target: actor.ActorId,
    dmg: i32 = 0,
    lethal: bool = false,
    mana: i32 = 0,
};

pub const UNKILLABLE_HP: i32 = 1;

pub const Fields = struct {
    /// Defaulted as the hero is spawned: a run's first node and each node entered afresh.
    pub const hero = [_][]const u8{"pool"};
    pub const start = [_][]const u8{ "visited", "node", "hero", "clock", "days" };
    /// Worked out from the map as a run starts, a node is entered and a saved run resumes.
    pub const derived = [_][]const u8{"outdoors"};
    /// Defaulted as a run starts, and again as a saved one resumes.
    pub const rebuilt = [_][]const u8{ "chronicle", "visits_changed" };
    pub const run = [_][]const u8{ "kills", "gold", "mana_recovery", "life_recovery", "flasks", "cooldown", "stepped", "log", "inventory", "ground", "plot" };
    pub const resumed = [_][]const u8{"unsaved"};
    /// Defaulted as a turn starts afresh: a node entered or a saved run resumed.
    pub const turn = [_][]const u8{ "travel", "order_n", "flowed" };
    /// Defaulted as each turn ends, and as a turn starts afresh.
    pub const marks = [_][]const u8{ "ran", "displaced" };
    /// Given their values by hand: by the app, as a run begins, or as a node is entered or left.
    pub const set = [_][]const u8{ "name", "class", "lv", "map", "visits", "rng", "seed", "mana", "growth", "loot_rng", "locations" };
    pub const scratch = [_][]const u8{ "order", "flow", "queue" };
    pub const kept = [_][]const u8{ "unkillable", "playground" };
};

pub const Simulation = struct {
    name: heroes.Name = heroes.DEFAULT.unnamed(),
    class: heroes.Class = heroes.DEFAULT,
    clock: day.Clock = .{},
    days: u32 = 0,
    outdoors: bool = false,
    locations: climate.Field = @splat(.inland),
    /// Never saved.
    unkillable: bool = false,
    /// Never saved; the app sets it for every run.
    playground: bool = false,
    unsaved: bool = false,
    lv: grid.Level,
    pool: actor.Pool = .{},
    hero: u16 = grid.NO_ONE,
    /// The map being played; null plays one generated floor.
    map: ?*const atlas.Atlas = null,
    node: usize = 0,
    visits: *[atlas.MAX_NODES]Visit,
    visited: std.StaticBitSet(atlas.MAX_NODES) = .initEmpty(),
    /// Visits written since the autosave last copied them.
    visits_changed: std.StaticBitSet(atlas.MAX_NODES) = .initFull(),
    /// The door the hero stepped onto this turn, gone through once the turn is drawn.
    travel: ?atlas.Link = null,
    rng: mathx.Rng,
    seed: u64 = 0,
    kills: usize = 0,
    gold: i32 = 0,
    mana: i32 = heroes.DEFAULT.attrs().mana(),
    mana_recovery: i32 = 0,
    life_recovery: i32 = 0,
    flasks: Flasks = .initFill(.{}),
    cooldown: std.EnumArray(skillbar.Act, u8) = .initFill(0),
    /// The hero stepped, leapt or was knocked back since its last action, which tears a bleed wider.
    stepped: bool = false,
    displaced: std.StaticBitSet(actor.MAX) = .initEmpty(),
    inventory: inventory.Inventory = .{ .gear = .flasks },
    growth: progress.State = progress.State.of(heroes.DEFAULT),
    ground: ground_items.Ground = .{},
    loot_rng: mathx.Rng = mathx.Rng.init(1),
    log: log.Log = .{},
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
        const taken = if (target.value == self.hero and (self.unkillable or self.playground)) std.math.clamp(a.hp - UNKILLABLE_HP, 0, left) else left;
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
        mathx.toDefaults(self, &Fields.turn);
        self.clearTurnMarks();
    }

    fn clearTurnMarks(self: *Simulation) void {
        mathx.toDefaults(self, &Fields.marks);
    }

    pub fn heroMoved(self: *Simulation) void {
        if (self.heroActor()) |h| h.tactics.steady = 0;
        self.stepped = true;
    }

    pub fn heroReadied(self: *const Simulation) progress.Readied {
        const h = self.heroBody() orelse return .{};
        return .{ .steady = h.tactics.steady, .imbued = h.tactics.imbue > 0 };
    }

    pub fn heroSlot(self: *const Simulation) ?usize {
        return if (self.hero == grid.NO_ONE) null else actor.Pool.slot(self.hero);
    }

    pub fn heroActorSlot(self: *const Simulation) ?actor.ActorSlot {
        return .fromIndex(self.heroSlot() orelse return null);
    }

    /// Living or not.
    pub fn heroBody(self: *const Simulation) ?*const actor.Actor {
        const i = self.heroSlot() orelse return null;
        return &self.pool.items[i];
    }

    pub fn heroAt(self: *const Simulation) ?P {
        return (self.heroBody() orelse return null).at;
    }

    pub fn world(self: *const Simulation) trigger.World {
        var w = trigger.World{ .node = self.node, .hero = self.heroAt() orelse .{ .x = 0, .y = 0 } };
        for (self.pool.constSlice()) |a| {
            if (a.livingFoe()) w.alive.getPtr(a.kind.family()).* += 1;
        }
        return w;
    }

    pub fn isHero(self: *const Simulation, slot: usize) bool {
        return actor.Pool.idOf(slot) == self.hero;
    }

    pub fn allyAt(self: *const Simulation, p: P) bool {
        const a = self.pool.getConst(self.lv.who(p)) orelse return false;
        return a.kind.ally();
    }

    pub fn untargetableAt(self: *const Simulation, p: P) bool {
        const a = self.pool.getConst(self.lv.who(p)) orelse return false;
        return a.veiled() or a.kind.ally();
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

    pub fn heroDraughts(self: *const Simulation) flask.Bonus {
        return self.inventory.gear.draughtsOver(self.growth.perks());
    }

    pub fn reachOf(self: *const Simulation, act: skillbar.Act) i32 {
        return act.reachWith(if (act.moves()) self.inventory.gear.bounding() else 0);
    }

    pub fn combatStats(self: *const Simulation, a: *const actor.Actor) terrain.Stats {
        return self.combatStatsOn(a, a.at, self.lv.at(a.at), a.resilience, a.sunder);
    }

    pub fn combatStatsOn(self: *const Simulation, a: *const actor.Actor, at: P, tile: grid.Tile, buildup: resilience.State, sundered: sunder.Sunder) terrain.Stats {
        var base = terrain.Stats{ .hit = actor.row(a.kind).hit, .elements = a.resists, .armour = if (a.stuck) 0 else actor.row(a.kind).armour };
        const is_hero = a.kind.hero();
        const composure: i16 = if (is_hero) std.math.lossyCast(i16, self.inventory.gear.sum(.composure)) else 0;
        if (is_hero) {
            const by = self.heroAttrs();
            base.dodge = by.dodge();
            base.armour = by.armour;
        }
        base.armour -= sundered.lost();
        for (std.enums.values(resilience.Kind)) |k| {
            base.statuses.set(k, @as(i16, actor.innateResist(a.kind, k)) + buildup.meters.get(k).percent);
            if (resilience.tags(k).contains(.mental)) base.statuses.getPtr(k).* +|= composure;
        }
        if (is_hero) base.statuses.getPtr(.stun).* +|= std.math.lossyCast(i16, self.inventory.gear.sum(.resolve));
        return base.onRained(tile, self.rainAt(at));
    }

    /// The rain falling on the open ground at `p`, 0 under a roof.
    pub fn rainAt(self: *const Simulation, p: P) f32 {
        if (!self.outdoors) return 0;
        const place = climate.placeAt(&self.locations, p);
        const c = if (self.nodeHere()) |node| self.climateNow().in(node.locations, place) else self.climateNow();
        return c.rain(self.seed, self.clock.since(self.days));
    }

    pub fn localWeather(self: *const Simulation) climate.Local {
        if (!self.outdoors) return climate.CALM;
        const overrides = if (self.nodeHere()) |node| node.locations else climate.Locations.initFill(null);
        return climate.local(self.climateNow(), overrides, self.seed, self.clock.since(self.days));
    }

    pub fn rainField(self: *const Simulation) climate.Rain {
        const weather = self.localWeather();
        var rain = climate.Rain{ .field = &self.locations };
        for (std.enums.values(climate.Location)) |place| rain.local.set(place, weather.get(place).get(.rain));
        return rain;
    }

    pub fn weatherHere(self: *const Simulation) climate.Now {
        return climate.strongest(self.localWeather());
    }

    pub fn takeStatus(self: *Simulation, a: *actor.Actor, kind: resilience.Kind) bool {
        return a.resilience.takeResisted(kind, self.combatStats(a).statuses.get(kind), &self.rng);
    }

    pub fn cleanseWound(self: *Simulation) bool {
        if (!self.inventory.gear.cleanses()) return false;
        const h = self.heroActor() orelse return false;
        inline for (comptime std.enums.values(resilience.Kind)) |k| {
            if (comptime resilience.tags(k).contains(.wounds)) {
                const status = &@field(h, @tagName(k));
                if (status.turns > 0) {
                    status.* = .{};
                    return true;
                }
            }
        }
        return false;
    }

    pub fn procStatus(self: *Simulation, a: *actor.Actor, kind: resilience.Kind, chance: u32) bool {
        if (chance == 0) return false;
        const resistance = self.combatStats(a).statuses.get(kind);
        return self.rollStatus(a, kind, chance, resistance);
    }

    pub fn procResisted(self: *Simulation, a: *actor.Actor, kind: resilience.Kind, chance: u32, element: damage.Element) bool {
        if (chance == 0) return false;
        const stats = self.combatStats(a);
        return self.rollStatus(a, kind, damage.resistedChance(chance, stats.elements.get(element)), stats.statuses.get(kind));
    }

    fn rollStatus(self: *Simulation, a: *actor.Actor, kind: resilience.Kind, chance: u32, resistance: i16) bool {
        const effective = damage.resistedChance(chance, @min(0, resistance));
        return damage.procs(&self.rng, effective) and a.resilience.takeResisted(kind, resistance, &self.rng);
    }

    /// `a` held `turns` longer unless its pin resistance holds; true when it is.
    pub fn pinFor(self: *Simulation, a: *actor.Actor, turns: u8) bool {
        if (turns == 0 or !self.takeStatus(a, .pin)) return false;
        a.pin.extend(turns);
        return true;
    }

    pub fn frighten(self: *Simulation, a: *actor.Actor, turns: u8) bool {
        if (!a.frighten(turns)) return false;
        self.sayAt(a.at, actor.FLEES, .{actor.row(a.kind).name});
        return true;
    }

    pub fn ignite(self: *Simulation, slot: usize, a: *actor.Actor) bool {
        return self.igniteFresh(slot, a, mathx.PERCENT);
    }

    /// Fire that takes hold of `a` only `of` percent of the time, past its fire and burn resistance.
    fn igniteBy(self: *Simulation, a: *actor.Actor, of: u32) bool {
        if (!self.procResisted(a, .burn, of, .fire)) return false;
        a.burn.start();
        return true;
    }

    pub fn igniteFresh(self: *Simulation, slot: usize, a: *actor.Actor, of: u32) bool {
        const fresh = a.burn.turns == 0;
        if (!self.igniteBy(a, of)) return false;
        if (fresh) self.sayTakes(slot, a, burning.TAKES);
        return true;
    }

    pub fn lifeMax(self: *const Simulation) i32 {
        return self.heroAttrs().life();
    }

    pub fn manaMax(self: *const Simulation) i32 {
        return self.heroAttrs().mana();
    }

    pub fn clampMana(self: *Simulation) void {
        self.mana = @min(self.mana, self.manaMax());
    }

    pub fn gainMana(self: *Simulation, n: i32) void {
        self.mana = @min(self.manaMax(), self.mana +| n);
    }

    pub fn manaRegen(self: *const Simulation) i32 {
        return heroes.manaRegen(self.heroPerks());
    }

    pub fn lifeRegen(self: *const Simulation) i32 {
        return self.inventory.gear.lifeRegen();
    }

    pub fn wider(self: *const Simulation) i32 {
        return self.inventory.gear.wider();
    }

    pub fn heroBlocks(self: *Simulation) bool {
        return damage.procs(&self.rng, self.heroAttrs().blockChance());
    }

    pub fn hastens(self: *Simulation) bool {
        return damage.procs(&self.rng, self.inventory.gear.haste());
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

    pub fn nodeHere(self: *const Simulation) ?*const atlas.Node {
        const w = self.map orelse return null;
        return &w.node[self.node];
    }

    pub fn script(self: *const Simulation) ?*const atlas.script.Script {
        const w = self.map orelse return null;
        return &w.script;
    }

    pub fn outdoorsNow(self: *const Simulation) bool {
        return (self.nodeHere() orelse return false).outdoor();
    }

    pub fn zooNow(self: *const Simulation) ?atlas.zoo.Spec {
        return (self.nodeHere() orelse return null).zoo;
    }

    pub fn areaLevel(self: *const Simulation, node: usize) u8 {
        const w = self.map orelse return loot.areaLevel(0);
        return loot.areaLevel(w.hops(node));
    }

    pub fn commanded(self: *const Simulation, v: i32) i32 {
        return mathx.percentCeil(v, mathx.PERCENT + self.inventory.gear.commander());
    }

    /// A bleed the hero just opened takes Grievous's extra damage each turn its body moves.
    pub fn grieve(self: *const Simulation, b: *bleeding.Bleed) void {
        b.move_bonus = @max(b.move_bonus, self.inventory.gear.grievous());
    }

    fn climateNow(self: *const Simulation) climate.Climate {
        return (self.nodeHere() orelse return .{}).sky();
    }

    pub fn heroLight(self: *const Simulation) i32 {
        return self.heroRow().light + self.inventory.gear.sum(.lantern);
    }

    fn lights(self: *const Simulation, from: P, hero_too: bool, out: *[actor.MAX]lume.Source) usize {
        var n: usize = 0;
        for (self.pool.constSlice(), 0..) |a, i| {
            if (self.isHero(i) and !hero_too) continue;
            const r = if (self.isHero(i)) self.heroLight() else actor.row(a.kind).light;
            if (!a.alive or r <= 0) continue;
            _ = mathx.push(lume.Source, out, &n, .{ .at = if (self.isHero(i)) from else a.at, .reach = r });
        }
        return n;
    }

    fn sightRange(self: *const Simulation) i32 {
        return blind.sight(if (self.heroBody()) |h| h.blind.turns > 0 else false, self.heroRow().sight);
    }

    pub fn see(self: *Simulation, from: P) void {
        var carried: [actor.MAX]lume.Source = undefined;
        const n = self.lights(from, true, &carried);
        const reach = self.sightRange();
        lume.see(&self.lv, from, reach, self.skyReach(reach), carried[0..n]);
    }

    fn skyReach(self: *const Simulation, reach: i32) f32 {
        return lume.skyReach(self.outdoors, self.clock.hour(), reach);
    }

    /// Lit by no light but the hero's own.
    pub fn inDark(self: *const Simulation, p: P) bool {
        const h = self.heroBody() orelse return false;
        const reach = self.heroRow().sight;
        if (mathx.reaches(h.at, p, self.skyReach(reach))) return false;
        var carried: [actor.MAX]lume.Source = undefined;
        const n = self.lights(h.at, false, &carried);
        return !lume.pooled(&self.lv, p, 0, carried[0..n], p);
    }

    pub fn sayAt(self: *Simulation, at: P, comptime fmt: []const u8, args: anytype) void {
        self.sayAs(.status, at, fmt, args);
    }

    pub fn sayAs(self: *Simulation, kind: log.Kind, at: P, comptime fmt: []const u8, args: anytype) void {
        if (self.lv.isLit(at)) self.log.push(kind, fmt, args);
    }

    pub fn sayAnyAt(self: *Simulation, cells: []const P, comptime fmt: []const u8, args: anytype) void {
        for (cells) |p| if (self.lv.isLit(p)) return self.log.say(fmt, args);
    }

    pub fn sayOf(self: *Simulation, a: *const actor.Actor, comptime fmt: []const u8, args: anytype) void {
        if (a.seenIn(&self.lv)) self.log.push(.status, fmt, args);
    }

    pub fn sayFoeTakes(self: *Simulation, a: *const actor.Actor, comptime takes: []const u8) void {
        self.sayOf(a, "The {s} " ++ takes ++ "!", .{actor.row(a.kind).name});
    }

    pub fn sayTakes(self: *Simulation, slot: usize, a: *const actor.Actor, comptime takes: []const u8) void {
        if (self.isHero(slot)) self.log.push(.danger, "{s} " ++ takes ++ "!", .{self.name.text()}) else self.sayFoeTakes(a, takes);
    }
};
