const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const day = @import("../map/day.zig");
const climate = @import("../map/climate.zig");
const fire = @import("../map/fire.zig");
const ice = @import("../map/ice.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const firebolt = @import("../play/firebolt.zig");
const damage = @import("../play/damage.zig");
const ground_items = @import("../play/ground_items.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const chronicle = @import("../play/chronicle.zig");
const fx = @import("../gfx/fx.zig");
const cloud = @import("../gfx/cloud.zig");
const look = @import("../gfx/look.zig");
const visibility = @import("../gfx/light_visibility.zig");
const game = @import("../game.zig");
const glide = @import("glide.zig");
const simulation = @import("sim.zig");
const rewards = @import("rewards.zig");
const schedule = @import("turn_schedule.zig");
const Simulation = simulation.Simulation;
const P = mathx.P;

const projectiles = @import("projectile_motion.zig");
pub const Shot = projectiles.Shot;
const BoltShown = projectiles.BoltShown;
const MotionView = projectiles.MotionView;
pub const flown = projectiles.flown;
const BOLT_CELL_S = projectiles.BOLT_CELL_S;
const TAKEN_MAX = 4;

/// `snare`: a net, holding the hero as it lands, or dodged (null).
pub const FoeHit = union(enum) { hurt: fx.After, kill: fx.After, burst: fx.After, snare: ?fx.After, miss };

pub const Knock = struct { from: P, to: P };

pub const Mended = struct { slot: ?actor.ActorSlot = null, after: ?fx.After = null };

pub const Befallen = struct {
    slots: std.StaticBitSet(actor.MAX) = .initEmpty(),
    after: [actor.MAX]fx.After = undefined,
};

/// `was` stands at `at` for `left` seconds more.
pub const Bursting = struct { at: P, was: grid.Tile, left: f32 };

const SightCells = struct {
    lit: [grid.CELLS]bool = @splat(false),
    seen: [grid.CELLS]bool = @splat(false),
    barrel_seen: [grid.CELLS]bool = @splat(false),

    fn of(lv: *const grid.Level) SightCells {
        return .{ .lit = lv.lit, .seen = lv.seen, .barrel_seen = lv.barrel_seen };
    }
};

/// `before` is drawn for `left` seconds; `due` when it was taken ahead of the hold that will keep it.
pub fn Held(comptime T: type) type {
    return struct {
        before: T,
        left: f32 = 0,
        due: bool = false,

        const Self = @This();

        pub fn on(self: *const Self) bool {
            return self.left > 0;
        }

        fn snap(self: *Self, now: *const T) void {
            if (self.on() or self.due) return;
            self.before = now.*;
            self.due = true;
        }

        fn hold(self: *Self, now: *const T, wait: f32) void {
            self.snap(now);
            self.due = false;
            self.left = @max(self.left, wait);
        }

        fn tick(self: *Self, dt: f32) void {
            self.left = @max(0, self.left - dt);
        }
    };
}

pub const Pictured = struct { masked: std.StaticBitSet(actor.MAX) = .initEmpty(), bursting: ?P = null, held: bool = false, tiles_held: bool = false };

/// Presentation debts land at the body's stagger, or after the hero when it has no stagger.
pub const Owed = struct {
    foe_hit: ?FoeHit = null,
    arrow: ?bow.Flight = null,
    gassed: ?Harm = null,
    scalded: ?Harm = null,
    scorched: ?Harm = null,
    healed: ?fx.After = null,
    burned: ?Harm = null,
    bled: ?Harm = null,
    worn: ?fx.After = null,
    swept: ?Swept = null,
    thorns: ?Harm = null,
    reaction: ?Reaction = null,
    knock: ?Knock = null,
    mended: ?Mended = null,
    struck: ?Struck = null,
    /// A hurl thrown at this cell, drawn leaving the hand as the throw lands.
    hurled: ?P = null,

    pub fn any(o: *const Owed) bool {
        inline for (std.meta.fields(Owed)) |f| {
            if (@field(o, f.name) != null) return true;
        }
        return false;
    }
};

const NOTHING_OWED: Owed = .{};

/// A blow one body lands on another, neither the hero; `impact` null is a miss.
pub const Struck = struct { at: P, impact: ?fx.Impact = null };

pub const ReactionOutcome = union(enum) { miss, hit: fx.ActorImpact };
pub const Reaction = struct { from: P, flight: ?bow.Flight, outcome: ReactionOutcome, recovery: ?fx.After = null };

pub const Swept = struct {
    hit: [actor.SWEEP_CELLS]fx.Impact = undefined,
    n: usize = 0,
};

comptime {
    std.debug.assert(fx.OWED_KINDS == std.meta.fields(Owed).len);
}

pub const Harm = struct { kill: bool, after: fx.After, recovery: ?fx.After = null };

/// `in` is set once the turn it was taken in has its stagger.
pub const Turning = struct { to: actor.Facing, in: ?f32 = null };

pub const SeenBody = struct {
    at: rl.Vector2,
    pic: fx.Body,
    lift: i32,
    facing: actor.Facing,
    opacity: f32,
    dark: f32,
    flash: f32,
};

pub const SeenCell = struct {
    alpha: f32 = 0,
    bag: bool = false,
    coins: i32 = 0,
    npc: ?usize = null,
    flame: f32 = 0,
    barrier: bool = false,
    caltrops: bool = false,
};

/// When each `Presentation` field is reset, every field in exactly one list; `save_data.zig` checks it.
pub const Fields = struct {
    /// Defaulted as a turn starts afresh: a node entered or a saved run resumed.
    pub const turn = [_][]const u8{ "shot", "foe_shots", "bolts", "knocked_from", "bursting", "sight_held", "lit_kindled", "tiles", "embers", "embers_lit", "burnt", "busy", "lead", "bolt_lands", "owed", "split_from", "dropped_gold", "mana_killed", "masked", "under", "dives", "befallen", "turning", "gold_taken" };
    pub const run = [_][]const u8{ "mana_held", "flasks_shown" };
    pub const facing = [_][]const u8{"facing"};
    pub const settled = [_][]const u8{ "occlusion", "glide", "sighted", "seen_bodies", "seen_cells", "pictured", "flames_shown", "tiles_drawn", "barrier_shown", "caltrops_shown", "xp_aim", "xp_shown", "life_fill", "mana_fill", "growth_shown", "gold_shown", "npc_shown", "quests_shown", "hour_shown", "weather_shown", "local_weather_shown" };
    pub const scratch = [_][]const u8{ "ground_shown", "burnt_ground", "burnt_box" };
    /// Kept for the presentation's life: `fx` clears itself each turn, `seq` counts on, `occluder` keeps the last body each cell faded around.
    pub const kept = [_][]const u8{ "seq", "fx", "occluder" };
};

/// What is drawn of the run, lagging the simulation until each blow lands; nothing in the simulation reads it.
pub const Presentation = struct {
    occlusion: [grid.CELLS]f32 = @splat(0),
    /// The middle of the body each occluding cell last fades around, cells.
    occluder: [grid.CELLS][2]f32 = @splat(.{ 0, 0 }),
    glide: [actor.MAX]glide.Glide = undefined,
    facing: [actor.MAX]actor.Facing = @splat(.right),
    turning: [actor.MAX]?Turning = @splat(null),
    /// How far into sight each body has faded; 0 while unseen.
    sighted: [actor.MAX]f32 = @splat(1),
    seen_bodies: [actor.MAX]?SeenBody = @splat(null),
    seen_cells: [grid.CELLS]SeenCell = @splat(.{}),
    pictured: [actor.MAX]fx.Body = undefined,
    /// The blows dealt so far, so the picture takes them in the order they were dealt.
    seq: u64 = 0,
    /// Indexed by pool slot: the slot a slime split off, until the blow that split it lands.
    split_from: [actor.MAX]?usize = @splat(null),
    /// Indexed by pool slot: gold kept out of its drop until that death is drawn.
    dropped_gold: [actor.MAX]i32 = @splat(0),
    masked: std.StaticBitSet(actor.MAX) = .initEmpty(),
    under: std.StaticBitSet(actor.MAX) = .initEmpty(),
    /// Indexed by pool slot: seconds until a body that surfaced or dived this turn is drawn so.
    dives: [actor.MAX]?f32 = @splat(null),
    befallen: [actor.MAX]Befallen = @splat(.{}),
    owed: [actor.MAX]Owed = @splat(.{}),
    shot: ?Shot = null,
    foe_shots: [actor.MAX]?Shot = @splat(null),
    /// Indexed by the thrower's pool slot; rebuilt from the simulation's bolts as a turn starts afresh.
    bolts: [actor.MAX]?BoltShown = @splat(null),
    /// Where the hero stood before the turn's first knockback: its own move ends there.
    knocked_from: ?P = null,
    bursting: ?Bursting = null,
    sight_held: Held(SightCells) = .{ .before = .{} },
    lit_kindled: bool = false,
    /// The ground's flames, barrier and caltrops as drawn: the simulation's, but kept as they were while `tiles` holds.
    flames_shown: [grid.CELLS]u8 = @splat(0),
    tiles_drawn: [grid.CELLS]grid.Tile = @splat(.floor),
    embers: [grid.CELLS]f32 = @splat(0),
    embers_lit: bool = false,
    burnt: [grid.CELLS]?grid.Tile = @splat(null),
    barrier_shown: [grid.CELLS]u8 = @splat(0),
    caltrops_shown: @FieldType(grid.Level, "caltrops") = @splat(.{}),
    tiles: Held([grid.CELLS]grid.Tile) = .{ .before = @splat(.floor) },
    ground_shown: grid.Level = undefined,
    burnt_ground: grid.Level = undefined,
    burnt_box: grid.Box = undefined,
    /// Seconds until the last turn's slowest glide, arrow or flash ends; a walk waits for it.
    busy: f32 = 0,
    /// Seconds until the hero's non-walking action lands; starts the foe stagger.
    lead: ?f32 = null,
    /// Seconds until the turn's last hurl strikes; the foes act after it.
    bolt_lands: f32 = 0,
    fx: fx.Fx = .{},
    gold_taken: grid.Bounded(ground_items.Coins, TAKEN_MAX) = .{},
    mana_held: i32 = 0,
    flasks_shown: simulation.Flasks = .initFill(.{}),
    mana_killed: [actor.MAX]i32 = @splat(0),
    xp_aim: f32 = 0,
    xp_shown: f32 = 0,
    life_fill: f32 = 1,
    mana_fill: f32 = 1,
    growth_shown: progress.State = .{},
    gold_shown: i32 = 0,
    npc_shown: @FieldType(grid.Level, "npc") = @splat(grid.NO_NPC),
    quests_shown: @FieldType(@FieldType(Simulation, "plot"), "quests") = @splat(.{}),
    hour_shown: f32 = day.Clock.hour(.{}),
    weather_shown: climate.Now = .initFill(0),
    local_weather_shown: climate.Local = climate.CALM,

    pub fn quiet(self: *const Presentation) bool {
        return self.busy <= PACE_SLACK;
    }

    pub fn sinceQuiet(self: *const Presentation) f32 {
        return @max(0, -self.busy);
    }

    pub fn holdUntil(self: *Presentation, t: f32) void {
        self.busy = @max(self.busy, t);
    }

    pub fn leadUntil(self: *Presentation, t: f32) void {
        self.holdUntil(t);
        self.lead = t;
    }

    pub fn leadNow(self: *const Presentation) f32 {
        return self.lead orelse 0;
    }

    pub fn deferDamage(self: *Presentation, result: simulation.DamageResult) void {
        self.mana_held += result.mana;
    }

    pub fn recordAttack(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, origin: chronicle.AttackOrigin, stroke: Stroke, flight: ?bow.Flight, outcome: ReactionOutcome, recovery: ?fx.After) void {
        switch (origin) {
            .reaction => |by| self.owe(by, .reaction, .{ .from = stroke.from, .flight = flight, .outcome = outcome, .recovery = recovery }),
            .chosen => {
                switch (outcome) {
                    .hit => |hit| self.strike(sim, gas, .{ .actor = hit }, stroke),
                    .miss => {},
                }
                if (recovery) |after| self.recordRecovery(sim, stroke.wait, after);
            },
        }
    }

    pub fn recordRecovery(self: *Presentation, sim: *const Simulation, wait: f32, after: fx.After) void {
        self.fx.settle(wait, .{ .slot = sim.heroActorSlot().?, .after = after });
    }

    pub fn recordProjectile(self: *Presentation, from: P, act: skillbar.Act, flight: bow.Flight) Stroke {
        self.shot = .{ .flight = flight, .from = from, .act = act };
        const loosed = self.loose(self.shot.?);
        const stroke = Stroke{ .from = from, .wait = loosed.lands, .element = act.element() };
        self.shot.?.zapInto(&self.fx);
        self.lead = stroke.wait;
        return stroke;
    }

    pub fn damageAfter(self: *Presentation, sim: *const Simulation, result: simulation.DamageResult, child: ?actor.ActorId) fx.After {
        var after = self.afterOf(sim, result.target.slot());
        after.reveals = if (child) |id| id.slot() else null;
        after.mana = result.mana;
        return after;
    }

    pub fn recordBurst(self: *Presentation, sim: *const Simulation, wait: f32, burst: fx.Burst) void {
        var shown = burst;
        shown.area = .{};
        shown.density_cells = burst.density_cells orelse burst.area.n;
        for (burst.area.slice()) |p| {
            if (self.litShown(sim, p)) shown.area.push(p);
        }
        if (shown.area.n > 0 or self.litShown(sim, burst.at)) self.fx.burst(wait, shown);
    }

    pub fn recordSplit(self: *Presentation, sim: *const Simulation, parent: actor.ActorId, child: actor.ActorId) void {
        const i = parent.slot().index;
        const o = child.slot().index;
        self.split_from[o] = i;
        self.stand(o, &sim.pool.items[o], if (self.turning[i]) |t| t.to else self.facing[i]);
    }

    fn stand(self: *Presentation, i: usize, body: *const actor.Actor, facing: actor.Facing) void {
        self.seen_bodies[i] = null;
        self.pictured[i] = fx.Body.of(body.*, self.seq);
        self.glide[i] = glide.Glide.rest(body);
        self.facing[i] = facing;
    }

    pub fn recordBirth(self: *Presentation, sim: *const Simulation, born: actor.ActorId, wait: f32) void {
        const i = born.slot().index;
        const body = &sim.pool.items[i];
        self.fx.impacts.forget(born.slot());
        self.stand(i, body, if (sim.heroAt()) |h| facingOf(h.x - body.at.x) orelse .right else .right);
        self.sighted[i] = 1;
        var after = self.afterOf(sim, born.slot());
        after.reveals = born.slot();
        self.fx.settle(wait, .{ .slot = born.slot(), .after = after });
    }

    pub fn beforeDeath(self: *Presentation, sim: *const Simulation, target: actor.ActorId) void {
        if (!actor.row(sim.pool.items[target.slot().index].kind).blow.pyre()) return;
        self.tiles.snap(&sim.lv.tile);
        self.sight_held.snap(&SightCells.of(&sim.lv));
    }

    pub fn recordDeath(self: *Presentation, sim: *const Simulation, target: actor.ActorId, death: rewards.Death) void {
        const i = target.slot().index;
        self.dropped_gold[i] = death.gold;
        self.mana_killed[i] = death.mana;
        if (death.unmasked) self.masked.set(i);
        self.recordFright(sim, target.slot(), death.frightened);
        self.befall(sim, i, death.caught);
    }

    pub fn recordFright(self: *Presentation, sim: *const Simulation, fallen: actor.ActorSlot, frightened: rewards.Frightened) void {
        var slots = frightened.iterator(.{});
        while (slots.next()) |slot| self.fx.frighten(slot, fallen.index);
        self.befall(sim, fallen.index, frightened);
    }

    fn befall(self: *Presentation, sim: *const Simulation, by: usize, slots: std.StaticBitSet(actor.MAX)) void {
        const consequences = &self.befallen[by];
        var each = slots.iterator(.{});
        while (each.next()) |slot| {
            consequences.slots.set(slot);
            consequences.after[slot] = self.afterOf(sim, .fromIndex(slot));
        }
    }

    fn landBefallen(self: *Presentation, fallen: usize, wait: f32) void {
        const consequences = &self.befallen[fallen];
        var each = consequences.slots.iterator(.{});
        while (each.next()) |slot| {
            self.fx.settle(wait, .{ .slot = .fromIndex(slot), .after = consequences.after[slot] });
        }
        consequences.slots = .initEmpty();
    }

    pub fn recordFoeAttack(self: *Presentation, by: actor.ActorId, outcome: FoeHit, flight: ?bow.Flight) void {
        self.owe(by, .foe_hit, outcome);
        self.owe(by, .arrow, flight);
    }

    pub fn owe(self: *Presentation, target: actor.ActorId, comptime field: anytype, value: @FieldType(Owed, @tagName(field))) void {
        @field(self.owed[target.slot().index], @tagName(field)) = value;
    }

    pub fn recordWear(self: *Presentation, sim: *const Simulation, target: actor.ActorId) void {
        self.owe(target, .worn, self.afterOf(sim, target.slot()));
    }

    /// Drawn in the thrower's hand from `wait` seconds on, until its throw is staggered.
    pub fn recordHurl(self: *Presentation, by: actor.ActorId, b: firebolt.Bolt, element: damage.Element, at: P, wait: f32) void {
        var shown = BoltShown.resting(b, element);
        shown.t = -wait;
        shown.before = false;
        self.bolts[by.slot().index] = shown;
        self.owe(by, .hurled, at);
    }

    /// `was` flown on to `now` from `wait` seconds on, gone once there if it stopped; when it gets there.
    pub fn recordBolt(self: *Presentation, sim: *const Simulation, by: actor.ActorSlot, was: firebolt.Bolt, now: firebolt.Bolt, flew: firebolt.Flew, element: damage.Element, wait: f32) f32 {
        const old = self.bolts[by.index];
        const from = if (old) |b| b.to() else was.point();
        const span = @as(f32, @floatFromInt(flew.cells)) * BOLT_CELL_S;
        const lands = wait + span;
        self.bolts[by.index] = .{ .element = element, .line = now, .view = if (old) |b| b.view else .{}, .from = from, .t = -wait, .span = span, .after = flew.stop == null };
        const seen = for (was.flown..@as(usize, now.flown) + 1) |k| {
            if (self.litShown(sim, now.cell(k))) break true;
        } else false;
        if (!seen) return lands;
        self.holdUntil(lands);
        if (flew.stop) |stop| switch (stop) {
            .body, .barrel => self.bolt_lands = @max(self.bolt_lands, lands),
            .wall, .spent => {},
        };
        return lands;
    }

    fn catchUpBolts(self: *Presentation, sim: *const Simulation) void {
        for (sim.pool.constSlice(), self.bolts[0..sim.pool.n]) |a, *shown| {
            if (shown.*) |b| {
                if (b.done() and (!b.after or a.bolt == null)) shown.* = null;
            } else if (a.bolt) |bolt| shown.* = BoltShown.resting(bolt, actor.row(a.kind).hurls.?.element);
        }
    }

    pub fn takeGold(self: *Presentation, coins: ground_items.Coins) void {
        if (self.gold_taken.n < TAKEN_MAX) self.gold_taken.push(coins);
    }

    fn dropReachedGold(self: *Presentation, hero: glide.Glide) void {
        if (hero.left() <= PACE_SLACK) {
            self.gold_taken = .{};
            return;
        }
        var kept: usize = 0;
        for (self.gold_taken.slice()) |pile| {
            if (!hero.reaching(pile.at)) continue;
            self.gold_taken.items[kept] = pile;
            kept += 1;
        }
        self.gold_taken.n = kept;
    }

    pub fn recordKnock(self: *Presentation, by: actor.ActorId, from: P, to: P) void {
        if (self.knocked_from == null) self.knocked_from = from;
        self.owe(by, .knock, .{ .from = from, .to = to });
    }

    pub fn freshTurn(self: *Presentation) void {
        mathx.toDefaults(self, &Fields.turn);
        self.fx.clear();
    }

    pub fn freshRun(self: *Presentation) void {
        mathx.toDefaults(self, &Fields.run);
    }

    pub fn freshFacing(self: *Presentation) void {
        mathx.toDefaults(self, &Fields.facing);
    }

    fn glideHeld(self: *Presentation, target: actor.ActorSlot, gl: glide.Glide) f32 {
        const slot = target.index;
        self.glide[slot] = gl;
        self.holdUntil(gl.left());
        return gl.left();
    }

    pub fn bumpHeld(self: *Presentation, target: actor.ActorSlot, at: P, late: f32) f32 {
        return self.glideHeld(target, self.glide[target.index].bumping(at, late));
    }

    pub fn glideToHeld(self: *Presentation, target: actor.ActorSlot, to: P, t: f32) f32 {
        return self.glideHeld(target, self.glide[target.index].toward(to, t));
    }

    pub fn turnToward(self: *Presentation, target: actor.ActorId, dx: i32) void {
        self.facing[target.slot().index] = facingOf(dx) orelse return;
    }

    pub fn turnHero(self: *Presentation, sim: *const Simulation, dx: i32) void {
        self.turnToward(.fromInt(sim.hero), dx);
    }

    pub fn turnLater(self: *Presentation, target: actor.ActorId, dx: i32) void {
        self.turning[target.slot().index] = .{ .to = facingOf(dx) orelse return };
    }

    pub fn turnNow(self: *Presentation) void {
        for (self.turning, &self.facing) |t, *f| {
            if (t) |u| f.* = u.to;
        }
        mathx.toDefaults(self, &.{"turning"});
    }

    fn stepTurning(self: *Presentation, dt: f32) void {
        for (&self.turning, 0..) |*t, i| {
            if (t.*) |*u| {
                const left = (u.in orelse continue) - dt;
                u.in = left;
                if (left > PACE_SLACK) continue;
                self.facing[i] = u.to;
                t.* = null;
            }
        }
    }

    pub fn snap(self: *Presentation, a: actor.Actor) fx.Body {
        self.seq += 1;
        return fx.Body.of(a, self.seq);
    }

    pub fn afterOf(self: *Presentation, sim: *const Simulation, target: actor.ActorSlot) fx.After {
        return .{ .body = self.snap(sim.pool.items[target.index]) };
    }

    pub fn heroAfter(self: *Presentation, sim: *const Simulation) fx.After {
        return self.afterOf(sim, sim.heroActorSlot().?);
    }

    pub fn settleHero(self: *Presentation, sim: *const Simulation, wait: f32) void {
        self.settleSlot(sim, wait, sim.heroActorSlot().?);
    }

    pub fn settleSlot(self: *Presentation, sim: *const Simulation, wait: f32, target: actor.ActorSlot) void {
        self.fx.settle(wait, .{ .slot = target, .after = self.afterOf(sim, target) });
    }

    pub fn snapGlide(self: *Presentation, pool: *const actor.Pool) void {
        mathx.toDefaults(self, &.{ "occlusion", "sighted", "seen_bodies", "seen_cells" });
        for (pool.constSlice(), 0..) |*a, i| self.glide[i] = glide.Glide.rest(a);
    }

    pub fn standing(self: *const Presentation, sim: *const Simulation, i: usize) bool {
        if (self.split_from[i] != null or self.fx.impacts.revealing(.fromIndex(i))) return false;
        if (sim.pool.items[i].alive or self.fx.impacts.holds(.fromIndex(i))) return true;
        return self.glide[i].done() < 1 and (!self.pictured[i].down() or self.fx.impacts.isDying(.fromIndex(i)));
    }

    pub fn gone(self: *const Presentation, sim: *const Simulation, i: usize) bool {
        return !self.standing(sim, i) and !self.fx.impacts.isDying(.fromIndex(i));
    }

    pub fn heroShown(self: *const Presentation, sim: *const Simulation) ?fx.Body {
        const i = sim.heroSlot() orelse return null;
        return self.pictured[i];
    }

    pub fn heroGlide(self: *const Presentation, sim: *const Simulation) ?glide.Glide {
        const i = sim.heroSlot() orelse return null;
        return if (self.standing(sim, i)) self.glide[i] else null;
    }

    pub fn heroCell(self: *const Presentation, sim: *const Simulation) ?P {
        return self.knocked_from orelse sim.heroAt();
    }

    pub fn heroNow(self: *const Presentation, sim: *const Simulation) ?rl.Vector2 {
        return (self.heroGlide(sim) orelse return null).now();
    }

    pub fn carrierAt(self: *const Presentation, sim: *const Simulation) ?[2]f32 {
        return game.middle(self.heroNow(sim) orelse return null);
    }

    pub fn drawnAt(self: *const Presentation, sim: *const Simulation, i: usize) ?rl.Vector2 {
        if (!self.figured(sim, i)) return null;
        return self.litNow(sim, i);
    }

    fn litNow(self: *const Presentation, sim: *const Simulation, i: usize) ?rl.Vector2 {
        const at = self.glide[i].now();
        return if (self.litShown(sim, game.cellUnder(at))) at else null;
    }

    pub fn drawnCell(self: *const Presentation, sim: *const Simulation, i: usize) ?P {
        return game.cellUnder(self.drawnAt(sim, i) orelse return null);
    }

    pub fn bodyAt(self: *const Presentation, sim: *const Simulation, i: usize) ?rl.Vector2 {
        if (self.visibleBody(sim, i)) |at| return at;
        if (self.sighted[i] <= 0) return null;
        return if (self.seen_bodies[i]) |b| b.at else null;
    }

    fn visibleBody(self: *const Presentation, sim: *const Simulation, i: usize) ?rl.Vector2 {
        return if (self.fading(sim, i)) self.litNow(sim, i) else self.drawnAt(sim, i);
    }

    pub fn bodyShown(self: *const Presentation, sim: *const Simulation, i: usize) SeenBody {
        if (self.visibleBody(sim, i) == null) if (self.seen_bodies[i]) |b| return b;
        const dying = self.fx.impacts.dyingOf(.fromIndex(i));
        return .{ .at = self.glide[i].now(), .pic = self.pictured[i], .lift = self.glide[i].lift(), .facing = self.facing[i], .opacity = dying.alpha, .dark = dying.dark, .flash = if (self.fx.impacts.isDying(.fromIndex(i))) 0 else self.fx.impacts.flashOf(.fromIndex(i)) };
    }

    pub const ShownBody = struct { slot: usize, at: rl.Vector2, body: SeenBody };

    pub const ShownBodies = struct {
        pic: *const Presentation,
        sim: *const Simulation,
        i: usize = 0,

        pub fn next(self: *ShownBodies) ?ShownBody {
            while (self.i < self.sim.pool.n) {
                const i = self.i;
                self.i += 1;
                const at = self.pic.bodyAt(self.sim, i) orelse continue;
                return .{ .slot = i, .at = at, .body = self.pic.bodyShown(self.sim, i) };
            }
            return null;
        }
    };

    pub fn shownBodies(self: *const Presentation, sim: *const Simulation) ShownBodies {
        return .{ .pic = self, .sim = sim };
    }

    fn fading(self: *const Presentation, sim: *const Simulation, i: usize) bool {
        return self.fx.impacts.isDying(.fromIndex(i)) and !self.standing(sim, i) and self.split_from[i] == null and !self.boxedOrSunk(i);
    }

    fn boxedOrSunk(self: *const Presentation, i: usize) bool {
        return self.under.isSet(i) or self.masked.isSet(i);
    }

    fn veiledShown(self: *const Presentation, body: *const actor.Actor, slot: usize, surfacing: bool) bool {
        return body.disguised or (!surfacing and body.submerged and self.under.isSet(slot));
    }

    pub fn casterAt(self: *const Presentation, sim: *const Simulation, i: usize, area: grid.Box) ?rl.Vector2 {
        const at = self.bodyAt(sim, i) orelse return null;
        return if (area.holds(game.cellUnder(at))) at else null;
    }

    fn figured(self: *const Presentation, sim: *const Simulation, i: usize) bool {
        return self.standing(sim, i) and !sim.pool.items[i].disguised and !self.boxedOrSunk(i);
    }

    pub fn tileShown(self: *const Presentation, sim: *const Simulation, p: P) grid.Tile {
        const t = sim.lv.at(p);
        if (!self.reshapes()) return t;
        if (self.bursting) |b| if (b.at.eq(p)) return b.was;
        if (self.mimicAt(sim, p)) return .chest;
        if (!self.tiles.on()) return t;
        return heldBack(grid.cellOr(grid.Tile, &self.tiles.before, p, t), t);
    }

    fn reshapes(self: *const Presentation) bool {
        return self.tiles.on() or self.bursting != null or self.masked.count() > 0;
    }

    pub fn groundShown(self: *Presentation, sim: *const Simulation) *const grid.Level {
        const reshaped = self.reshapes();
        const held = self.sight_held.on();
        if (!reshaped and !held) return &sim.lv;
        self.ground_shown = sim.lv;
        const tiles = &self.ground_shown.tile;
        if (self.tiles.on()) {
            for (tiles, self.tiles.before) |*t, was| t.* = heldBack(was, t.*);
            inline for (LAID_LAYERS) |name| @field(self.ground_shown, name) = @field(self, name ++ "_shown");
        }
        var masked = self.masked.iterator(.{});
        while (masked.next()) |i| if (grid.Level.inside(sim.pool.items[i].at)) {
            tiles[grid.Level.idx(sim.pool.items[i].at)] = .chest;
        };
        if (self.bursting) |b| if (grid.Level.inside(b.at)) {
            tiles[grid.Level.idx(b.at)] = b.was;
        };
        if (held) {
            self.holdCells(&self.ground_shown.lit, &self.sight_held.before.lit);
            self.holdCells(&self.ground_shown.seen, &self.sight_held.before.seen);
        }
        return &self.ground_shown;
    }

    pub fn pictureKey(self: *const Presentation) Pictured {
        return .{ .masked = self.masked, .bursting = if (self.bursting) |b| b.at else null, .held = self.sight_held.on(), .tiles_held = self.tiles.on() };
    }

    pub fn mimicAt(self: *const Presentation, sim: *const Simulation, p: P) bool {
        var each = self.masked.iterator(.{});
        while (each.next()) |i| if (sim.pool.items[i].at.eq(p)) return true;
        if (sim.lv.at(p) != .chest) return false;
        const a = sim.pool.getConst(sim.lv.who(p)) orelse return false;
        return a.disguised;
    }

    pub fn burstPlant(self: *Presentation, lv: *const grid.Level, at: P, was: grid.Tile, wait: f32) void {
        self.bursting = .{ .at = at, .was = was, .left = wait };
        self.holdLit(lv, wait, false);
    }

    /// Light gone with the ground stays lit while it holds; light a fire `kindles` stays dark too.
    fn holdLit(self: *Presentation, lv: *const grid.Level, wait: f32, kindles: bool) void {
        if (!self.sight_held.on()) self.lit_kindled = false;
        self.sight_held.hold(&SightCells.of(lv), wait);
        self.lit_kindled = self.lit_kindled or kindles;
    }

    fn holdTiles(self: *Presentation, lv: *const grid.Level, wait: f32, kindles: bool) void {
        self.tiles.hold(&lv.tile, wait);
        self.holdLit(lv, wait, kindles);
    }

    pub fn holdFlames(self: *Presentation, lv: *const grid.Level, wait: f32) void {
        self.holdTiles(lv, wait, false);
    }

    pub fn holdFire(self: *Presentation, lv: *const grid.Level, wait: f32) void {
        self.holdTiles(lv, wait, true);
    }

    fn litHeld(self: *const Presentation, now: bool, was: bool) bool {
        return was or (now and !self.lit_kindled);
    }

    fn holdCells(self: *const Presentation, now: *[grid.CELLS]bool, was: *const [grid.CELLS]bool) void {
        for (now, was) |*n, w| n.* = self.litHeld(n.*, w);
    }

    pub fn litCells(self: *Presentation, sim: *const Simulation) *const [grid.CELLS]bool {
        if (!self.sight_held.on()) return &sim.lv.lit;
        self.ground_shown.lit = sim.lv.lit;
        self.holdCells(&self.ground_shown.lit, &self.sight_held.before.lit);
        return &self.ground_shown.lit;
    }

    fn cellShown(self: *const Presentation, now: bool, was: *const [grid.CELLS]bool, p: P) bool {
        if (!self.sight_held.on()) return now;
        return self.litHeld(now, grid.cellOr(bool, was, p, false));
    }

    pub fn flamesShown(self: *const Presentation, i: usize) bool {
        return self.flames_shown[i] > 0;
    }

    pub fn ember(self: *const Presentation, i: usize) f32 {
        return self.embers[i] / EMBER_S;
    }

    pub fn fadingBurnt(self: *const Presentation, i: usize) ?grid.Tile {
        return if (self.embers[i] > 0) self.burnt[i] else null;
    }

    /// Null while no tile is still fading from a fire.
    pub fn burntShown(self: *Presentation, ground: *const grid.Level) ?*const grid.Level {
        if (!self.embers_lit) return null;
        self.burnt_box = (grid.boundsWhere(@as(*const Presentation, self), burntAt) orelse return null).grown(1);
        self.burnt_ground = ground.*;
        for (&self.burnt_ground.tile, 0..) |*t, i| if (self.fadingBurnt(i)) |was| {
            t.* = was;
        };
        return &self.burnt_ground;
    }

    fn burntAt(self: *const Presentation, i: usize) bool {
        return self.fadingBurnt(i) != null;
    }

    fn goneOut(self: *Presentation, lv: *const grid.Level) void {
        for (&self.flames_shown, &lv.flames, &self.tiles_drawn, &lv.tile, 0..) |was, now, before, after, i| {
            if (was == 0 or now > 0) continue;
            self.embers[i] = EMBER_S;
            self.embers_lit = true;
            self.burnt[i] = if (before != after and fire.burntDown(before, after)) before else null;
        }
    }

    pub fn showLaid(self: *Presentation, lv: *const grid.Level) void {
        self.tiles_drawn = lv.tile;
        inline for (LAID_LAYERS) |name| @field(self, name ++ "_shown") = @field(lv, name);
    }

    pub fn litShown(self: *const Presentation, sim: *const Simulation, p: P) bool {
        return self.cellShown(sim.lv.isLit(p), &self.sight_held.before.lit, p);
    }

    pub fn seenShown(self: *const Presentation, sim: *const Simulation, p: P) bool {
        return self.cellShown(sim.lv.isSeen(p), &self.sight_held.before.seen, p);
    }

    pub fn barrelSeenShown(self: *const Presentation, sim: *const Simulation, p: P) bool {
        if (!self.sight_held.on()) return sim.lv.barrelSeen(p);
        return grid.cellOr(bool, &self.sight_held.before.barrel_seen, p, false);
    }

    fn flightSeen(self: *const Presentation, sim: *const Simulation, flight: *const bow.Flight) bool {
        for (flight.path[0..flight.len]) |p| if (self.litShown(sim, p)) return true;
        return false;
    }

    pub fn barrelPresent(self: *const Presentation, sim: *const Simulation, p: P) bool {
        return sim.lv.hasBarrel(p) or self.fx.impacts.breaking(p);
    }

    pub fn pileShown(self: *const Presentation, sim: *const Simulation, pile: ground_items.Coins) ?ground_items.Coins {
        if (!self.litShown(sim, pile.at) or self.barrelPresent(sim, pile.at)) return null;
        return self.pileLanded(sim, pile);
    }

    pub fn pileLanded(self: *const Presentation, sim: *const Simulation, pile: ground_items.Coins) ?ground_items.Coins {
        var shown = pile;
        for (sim.pool.constSlice(), 0..) |a, i| {
            if (a.at.eq(pile.at) and self.fallingUnshown(a, i)) shown.amount -= self.dropped_gold[i];
        }
        return if (shown.amount > 0) shown else null;
    }

    /// `laid` is an `ground_items.Drop` or `ground_items.Supply`.
    pub fn laidShown(self: *const Presentation, sim: *const Simulation, laid: anytype) bool {
        return self.litShown(sim, laid.at) and self.laidDown(laid) and !self.barrelPresent(sim, laid.at);
    }

    pub fn laidDown(self: *const Presentation, laid: anytype) bool {
        if (laid.source == grid.NO_ONE) return true;
        return self.pictured[actor.Pool.slot(laid.source)].down();
    }

    pub fn uprooted(self: *Presentation) ?P {
        const b = self.bursting orelse return null;
        if (b.left > 0) return null;
        self.bursting = null;
        return b.at;
    }

    fn fallingUnshown(self: *const Presentation, a: actor.Actor, i: usize) bool {
        return !a.alive and !self.pictured[i].down();
    }

    pub fn manaShown(self: *const Presentation, sim: *const Simulation) i32 {
        var killed: i32 = 0;
        for (sim.pool.constSlice(), 0..) |a, i| {
            if (self.fallingUnshown(a, i)) killed += self.mana_killed[i];
        }
        return @max(0, @min(sim.manaMax(), sim.mana + self.mana_held) - killed);
    }

    pub fn lifeShown(self: *const Presentation, sim: *const Simulation) Life {
        const h = self.heroShown(sim) orelse return .{ .hp = 0, .max = sim.lifeMax() };
        return .{ .hp = h.hp, .max = h.max };
    }

    fn lifeFill(self: *const Presentation, sim: *const Simulation) f32 {
        const life = self.lifeShown(sim);
        return mathx.fillOf(life.hp, life.max);
    }

    fn manaFill(self: *const Presentation, sim: *const Simulation) f32 {
        return mathx.fillOf(self.manaShown(sim), sim.manaMax());
    }

    pub fn settleResources(self: *Presentation, sim: *const Simulation) void {
        self.life_fill = self.lifeFill(sim);
        self.mana_fill = self.manaFill(sim);
    }

    pub fn settleSky(self: *Presentation, sim: *const Simulation) void {
        self.hour_shown = sim.clock.hour();
        self.weather_shown = sim.weatherHere();
        self.local_weather_shown = sim.localWeather();
    }

    pub fn showProgress(self: *Presentation, sim: *const Simulation) void {
        self.growth_shown = sim.growth;
        self.gold_shown = sim.gold;
        self.showPlot(sim);
        self.xp_aim = sim.xpLevels();
    }

    pub fn showPlot(self: *Presentation, sim: *const Simulation) void {
        self.npc_shown = sim.lv.npc;
        self.quests_shown = sim.plot.quests;
    }

    pub fn npcShown(self: *const Presentation, p: P) ?usize {
        return grid.npcOf(grid.cellOr(u8, &self.npc_shown, p, grid.NO_NPC));
    }

    pub fn settleXp(self: *Presentation, sim: *const Simulation) void {
        self.showProgress(sim);
        self.xp_shown = self.xp_aim;
    }

    pub fn easeOver(self: *Presentation, sim: *const Simulation, ground: *const grid.Level, dt: f32) void {
        self.stepOcclusion(sim, &ground.tile, dt);
        self.stepSighted(sim, dt);
        self.stepSeenCells(sim, &ground.lit, mathx.easing(dt, visibility.REVEAL));
        self.hour_shown = day.wrapHour(self.hour_shown + day.toward(self.hour_shown, sim.clock.hour()) * mathx.easing(dt, HOUR_EASE));
        self.weather_shown = climate.eased(self.weather_shown, sim.weatherHere(), mathx.easing(dt, WEATHER_EASE));
        const local_weather = sim.localWeather();
        for (std.enums.values(climate.Location)) |place| {
            self.local_weather_shown.set(place, climate.eased(self.local_weather_shown.get(place), local_weather.get(place), mathx.easing(dt, WEATHER_EASE)));
        }
        self.xp_shown = mathx.ease(self.xp_shown, self.xp_aim, mathx.easing(dt, XP_EASE), 1);
        const resource_ease = mathx.easing(dt, RESOURCE_EASE);
        self.life_fill = mathx.ease(self.life_fill, self.lifeFill(sim), resource_ease, resource_ease);
        self.mana_fill = mathx.ease(self.mana_fill, self.manaFill(sim), resource_ease, resource_ease);
    }

    fn stepProjectileView(self: *const Presentation, sim: *const Simulation, view: *MotionView, at: ?[2]f32, easing: f32) void {
        const visible = if (at) |position| self.litShown(sim, mathx.cellOf(position)) else false;
        view.step(at, visible, easing);
    }

    fn stepSighted(self: *Presentation, sim: *const Simulation, dt: f32) void {
        const k = mathx.easing(dt, visibility.REVEAL);
        if (self.shot) |*s| self.stepProjectileView(sim, &s.view, s.now(), k);
        for (&self.foe_shots) |*pending| if (pending.*) |*s| {
            self.stepProjectileView(sim, &s.view, s.now(), k);
        };
        for (&self.bolts) |*pending| if (pending.*) |*b| {
            self.stepProjectileView(sim, &b.view, b.at(), k);
        };
        for (self.sighted[0..sim.pool.n], 0..) |*s, i| {
            const visible = self.visibleBody(sim, i) != null;
            if (visible) {
                self.seen_bodies[i] = self.bodyShown(sim, i);
            } else if (self.seen_bodies[i]) |b| {
                if (b.dark > 0 and self.gone(sim, i)) self.seen_bodies[i] = null;
            }
            if (!visible and self.seen_bodies[i] == null) {
                s.* = if (self.figured(sim, i)) 0 else 1;
                continue;
            }
            s.* = mathx.easeTo(s.*, visible, k);
        }
    }

    pub fn snapSight(self: *Presentation, sim: *const Simulation) void {
        self.stepSighted(sim, 1);
        self.stepSeenCells(sim, &self.groundShown(sim).lit, 1);
    }

    fn stepSeenCells(self: *Presentation, sim: *const Simulation, lit: *const [grid.CELLS]bool, k: f32) void {
        for (&self.seen_cells, lit, &self.npc_shown, 0..) |*v, visible, npc, i| {
            if (!visible) {
                if (v.alpha > 0) v.alpha = mathx.easeTo(v.alpha, false, k);
                continue;
            }
            v.alpha = mathx.easeTo(v.alpha, true, k);
            v.bag = false;
            v.coins = 0;
            v.npc = grid.npcOf(npc);
            v.flame = if (self.flamesShown(i)) 1 else self.ember(i);
            v.barrier = self.barrier_shown[i] > 0;
            v.caltrops = self.caltrops_shown[i].turns > 0;
        }
        inline for (sim.ground.laid()) |laid| for (laid) |l| {
            if (self.laidShown(sim, l)) self.seen_cells[grid.Level.idx(l.at)].bag = true;
        };
        for (sim.ground.coins[0..sim.ground.coin_n]) |pile| {
            if (self.pileShown(sim, pile)) |p| self.seen_cells[grid.Level.idx(p.at)].coins = p.amount;
        }
    }

    pub fn cellAlpha(self: *const Presentation, p: P) f32 {
        return grid.cellOr(SeenCell, &self.seen_cells, p, .{}).alpha;
    }

    fn occluding(self: *const Presentation, sim: *const Simulation, i: usize) ?rl.Vector2 {
        const at = self.drawnAt(sim, i) orelse return null;
        return .{ .x = at.x, .y = at.y - @as(f32, @floatFromInt(self.glide[i].lift())) };
    }

    fn stepOcclusion(self: *Presentation, sim: *const Simulation, tiles: *const [grid.CELLS]grid.Tile, dt: f32) void {
        var covered = grid.CellSet.initEmpty();
        if (sim.heroSlot()) |h| if (self.occluding(sim, h)) |at| self.cover(tiles, at, &covered);
        for (0..sim.pool.n) |i| if (!sim.isHero(i)) if (self.occluding(sim, i)) |at| self.cover(tiles, at, &covered);
        for (&self.npc_shown, 0..) |f, i| {
            if (f == grid.NO_NPC) continue;
            const p = grid.Level.of(i);
            if (self.litShown(sim, p)) self.cover(tiles, glide.cellPx(p), &covered);
        }
        const k = mathx.easing(dt, OCCLUSION_EASE);
        for (tiles, &self.occlusion, 0..) |t, *hidden, i| {
            if (hidden.* == 0 and !covered.isSet(i)) continue;
            hidden.* = if (look.occludes(t)) mathx.easeTo(hidden.*, covered.isSet(i), k) else 0;
        }
    }

    fn cover(self: *Presentation, tiles: *const [grid.CELLS]grid.Tile, at: rl.Vector2, covered: *grid.CellSet) void {
        const under = game.cellUnder(at);
        var near = grid.Cells.of(under.sub(COVER_LO), under.add(COVER_HI));
        while (near.next()) |p| {
            if (!grid.Level.inside(p)) continue;
            const i = grid.Level.idx(p);
            const t = tiles[i];
            if (covered.isSet(i) or !look.occludes(t) or !hides(at, p, t)) continue;
            covered.set(i);
            self.occluder[i] = game.middle(at);
        }
    }

    pub fn advance(self: *Presentation, sim: *const Simulation, dt: f32) void {
        self.busy -= dt;
        if (self.bursting) |*b| b.left -= dt;
        self.sight_held.tick(dt);
        self.tiles.tick(dt);
        if (self.embers_lit) {
            var lit = false;
            for (&self.embers) |*e| {
                e.* = @max(0, e.* - dt);
                lit = lit or e.* > 0;
            }
            self.embers_lit = lit;
        }
        if (!self.tiles.on()) {
            if (!std.mem.allEqual(u8, &self.flames_shown, 0)) self.goneOut(&sim.lv);
            self.showLaid(&sim.lv);
        }
        for (self.glide[0..sim.pool.n]) |*gl| gl.t += dt;
        for (&self.bolts) |*b| if (b.*) |*shown| {
            shown.t += dt;
        };
        for (&self.dives) |*d| if (d.*) |*left| {
            left.* -= dt;
            if (left.* <= 0) d.* = null;
        };
        if (sim.heroSlot()) |h| self.dropReachedGold(self.glide[h]);
        self.fx.step(&sim.lv, dt);
        self.catchUp(sim);
    }

    pub fn stepMotion(self: *Presentation, sim: *const Simulation, dt: f32) void {
        self.footfalls(sim);
        const lit = self.litCells(sim);
        if (self.shot) |*s| {
            if (!s.fly(&self.fx, &sim.lv, lit, dt)) self.shot = null;
        }
        for (&self.foe_shots) |*pending| {
            if (pending.*) |*s| {
                if (!s.fly(&self.fx, &sim.lv, lit, dt)) pending.* = null;
            }
        }
        for (&self.bolts) |*pending| if (pending.*) |*b| if (b.moving()) {
            if (b.at()) |at| self.fx.hurlTrail(&sim.lv, lit, at, b.heading(), b.element);
        };
        self.stepTurning(dt);
    }

    pub fn footfalls(self: *Presentation, sim: *const Simulation) void {
        for (self.glide[0..sim.pool.n], 0..) |*gl, i| {
            if (gl.stepped or gl.done() < STEP_AT) continue;
            gl.stepped = true;
            if (gl.bump != null or std.meta.eql(gl.from, glide.cellPx(gl.to))) continue;
            if (self.pictured[i].down() or actor.row(self.pictured[i].kind).movement != .ground) continue;
            const at = self.drawnAt(sim, i) orelse continue;
            const under = self.tileShown(sim, game.cellUnder(at));
            if (under == .shallows) {
                self.fx.splash(game.middle(at));
            } else if (under == .grass or under == .tall_grass) {
                self.fx.leaves(game.middle(at));
            } else if (under == .bridge) {
                self.fx.woodDust(game.middle(at));
            } else if (look.stepDust(under)) |col| self.fx.dust(game.middle(at), col);
        }
    }

    pub fn catchUp(self: *Presentation, sim: *const Simulation) void {
        var dying = false;
        for (sim.pool.constSlice(), 0..) |a, i| {
            if (!self.fx.impacts.pending(.fromIndex(i))) {
                self.pictured[i] = fx.Body.of(a, self.seq);
            } else if (self.fx.impacts.landedOn(.fromIndex(i))) |b| {
                if (b.seq > self.pictured[i].seq) self.pictured[i] = b;
            }
            if (self.fallingUnshown(a, i)) dying = true;
            if (self.pictured[i].down() or (a.alive and !self.fx.impacts.pending(.fromIndex(i)))) self.masked.unset(i);
            if (self.dives[i] == null) self.under.setValue(i, a.submerged);
            const from = self.split_from[i] orelse continue;
            if (self.fx.impacts.revealing(.fromIndex(i)) or self.split_from[from] != null) continue;
            self.split_from[i] = null;
            self.glide[i] = self.glide[from].toward(a.at, -self.clearIn(sim, i, a.at));
            if (self.litShown(sim, sim.pool.items[from].at) or self.litShown(sim, a.at)) self.holdUntil(self.glide[i].left());
        }
        if (!dying) self.flasks_shown = sim.flasks;
        self.mana_held = @max(0, self.mana_held - self.fx.impacts.takeMana());
        if (sim.heroSlot()) |h| {
            if (!self.fx.impacts.pending(.fromIndex(h))) self.mana_held = 0;
        }
        self.fx.react(self.pictured[0..sim.pool.n]);
        self.catchUpBolts(sim);
    }

    /// `late` is seconds since the glides started.
    pub fn stepGlide(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, late: f32) void {
        var turn = schedule.Turn.begin(late, self.lead, self.heroCell(sim).?, PACE);
        turn.quiet = self.lead == null and !self.foeInSight(sim);
        const hero = sim.heroSlot().?;
        const warded = self.owed[hero].worn;
        self.owed[hero].worn = null;
        const hero_done = @max(self.stagger(sim, gas, .fromInt(sim.hero), self.leadNow(), &turn), self.bolt_lands);
        turn.afterBolts(self.bolt_lands);
        self.lead = null;
        self.bolt_lands = 0;
        self.knocked_from = null;
        var part: [actor.MAX]f32 = @splat(hero_done);
        for (sim.order[0..sim.order_n]) |id| part[actor.Pool.slot(id)] = self.stagger(sim, gas, .fromInt(id), hero_done, &turn);
        for (self.owed[0..sim.pool.n], 0..) |*o, i| {
            if (!o.any()) continue;
            const start = if (self.split_from[i]) |p| @max(hero_done, part[p], self.fx.impacts.revealsIn(.fromIndex(i))) else hero_done;
            part[i] = self.stagger(sim, gas, actor.ActorSlot.fromIndex(i).id(), start, &turn);
        }
        for (&self.befallen) |*consequences| consequences.slots = .initEmpty();
        if (warded) |c| self.recordRecovery(sim, std.mem.max(f32, part[0..sim.pool.n]), c);
        for (sim.pool.constSlice(), 0..) |*a, i| {
            if (!self.glide[i].to.eq(a.at)) self.glide[i] = self.glide[i].toward(a.at, late);
            if (a.submerged != self.under.isSet(i) and self.dives[i] == null) self.dives[i] = part[i];
        }
    }

    /// As pictured before this turn's glides: a foe killed or gone out of sight this turn still counts.
    fn foeInSight(self: *const Presentation, sim: *const Simulation) bool {
        for (sim.pool.constSlice(), 0..) |*a, i| {
            if (a.foe() and !self.pictured[i].down() and !self.veiledShown(a, i, false) and self.litShown(sim, self.glide[i].to)) return true;
        }
        return false;
    }

    fn stagger(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, target: actor.ActorId, start: f32, turn: *schedule.Turn) f32 {
        const slot = target.slot().index;
        if (!self.owed[slot].any()) return self.scheduleOwed(sim, gas, target, &NOTHING_OWED, start, turn);
        const owed = self.owed[slot];
        self.owed[slot] = .{};
        return self.scheduleOwed(sim, gas, target, &owed, start, turn);
    }

    fn scheduleOwed(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, target: actor.ActorId, owed: *const Owed, start: f32, turn: *schedule.Turn) f32 {
        var timing = self.scheduleMotion(sim, target, owed, start, turn) orelse return start;
        self.scheduleBlows(sim, gas, owed, &timing);
        const countered = self.scheduleReaction(sim, gas, owed, &timing, turn);
        self.scheduleKnock(sim, owed, countered, &timing, turn);
        return self.scheduleHarm(sim, gas, owed, &timing, turn);
    }

    fn scheduleMotion(self: *Presentation, sim: *const Simulation, target: actor.ActorId, owed: *const Owed, start: f32, turn: *schedule.Turn) ?BodyTiming {
        const slot = target.slot().index;
        const body = &sim.pool.items[slot];
        const motion = &self.glide[slot];
        const is_hero = target.value == sim.hero;
        const destination = if (is_hero) self.heroCell(sim).? else body.at;
        const moved = !motion.to.eq(destination);
        if (!moved and !owed.any()) {
            if (self.turning[slot]) |*t| {
                if (t.in == null) t.in = start;
            }
            return null;
        }
        const attack = owed.foe_hit;
        const hidden = self.veiledShown(body, slot, attack != null);
        const shown = self.litShown(sim, destination) and !hidden;
        const visible_origin = !hidden and self.litShown(sim, motion.to);
        const arrow_seen = if (owed.arrow) |*f| owed.struck == null or shown or self.flightSeen(sim, f) else false;
        const lunges = attack != null or owed.struck != null or owed.hurled != null;
        var facts = schedule.Motion{
            .start_in = start,
            .hero = is_hero,
            .ally = body.livingAlly(),
            .moved = moved,
            .lunges = lunges,
            .shown = shown,
            .visible_origin = visible_origin,
            .arrow_seen = arrow_seen,
            .mending = owed.mended != null,
            .motion_left = motion.left(),
            .clear_in = 0,
        };
        if (moved and !is_hero and schedule.staggers(facts)) facts.clear_in = self.clearIn(sim, slot, body.at);
        var clock = turn.motion(facts);
        if (self.turning[slot]) |*t| t.in = clock.begins_in;
        const hero_at = if (owed.knock) |k| k.from else turn.hero_cell;
        const bumps = owed.arrow == null and lunges;
        if (moved) {
            motion.* = motion.toward(destination, turn.late - clock.starts_at);
        } else if (bumps) {
            motion.* = motion.bumping(if (owed.struck) |s| s.at else owed.hurled orelse hero_at, turn.late - clock.starts_at);
        }
        if (clock.afterMotion(bumps, attack != null or owed.struck != null, motion.left())) self.holdUntil(clock.finishes_in);
        if (arrow_seen) {
            const release = @max(start, clock.starts_at - turn.late);
            const s = Shot{ .from = body.at, .flight = owed.arrow.?, .t = -release, .net = attack != null and attack.? == .snare, .hook = actor.row(body.kind).hooks != null };
            self.foe_shots[slot] = s;
            const loosed = self.loose(s);
            turn.projectile(&clock, loosed.lands, loosed.ends);
        }
        return .{
            .slot = target.slot(),
            .body = body,
            .at = destination,
            .hero_at = hero_at,
            .shown = shown,
            .clock = clock,
        };
    }

    fn scheduleBlows(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, owed: *const Owed, timing: *BodyTiming) void {
        if (owed.foe_hit) |b| switch (b) {
            .hurt, .kill => |after| self.strikeBody(sim, gas, sim.heroActorSlot().?, timing.hero_at, b == .kill, after, .{ .from = timing.body.at, .wait = timing.clock.impact_in, .element = strikeElement(timing.body.kind) }),
            .burst => |after| self.strikeBody(sim, gas, timing.slot, timing.body.at, true, after, .{ .from = timing.hero_at, .wait = timing.clock.impact_in }),
            .snare => |held| if (held) |after| self.recordRecovery(sim, timing.clock.impact_in, after),
            .miss => {},
        };
        if (owed.mended) |m| {
            timing.clock.finishAfter(timing.clock.impact_in);
            var seen = timing.shown;
            if (timing.shown) self.shimmerBody(timing.clock.impact_in, timing.body);
            if (m.slot) |s| {
                if (m.after) |after| self.fx.settle(timing.clock.impact_in, .{ .slot = s, .after = after });
                const kin = self.glide[s.index].to;
                if (self.litShown(sim, kin)) {
                    self.fx.shimmerIn(timing.clock.impact_in, .{ .at = mathx.centre(kin), .col = look.LIFE });
                    seen = true;
                }
            }
            if (seen) self.holdUntil(timing.clock.impact_in);
        }
        if (owed.swept) |*sw| {
            if (timing.shown) self.fx.sweep(timing.clock.impact_in, mathx.centre(timing.body.at));
            for (sw.hit[0..sw.n]) |h| self.strike(sim, gas, h, .{ .from = timing.body.at, .wait = timing.clock.impact_in });
        }
        if (owed.thorns) |h| {
            self.strikeBody(sim, gas, timing.slot, timing.body.at, h.kill, h.after, .{ .from = timing.hero_at, .wait = timing.clock.impact_in });
            if (h.recovery) |after| self.recordRecovery(sim, timing.clock.impact_in, after);
        }
        if (owed.struck) |s| if (s.impact) |hit| self.strike(sim, gas, hit, .{ .from = timing.body.at, .wait = timing.clock.impact_in });
        if (owed.hurled != null) if (self.bolts[timing.slot.index]) |*b| {
            b.t = -timing.clock.impact_in;
        };
    }

    fn scheduleReaction(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, owed: *const Owed, timing: *BodyTiming, turn: *schedule.Turn) f32 {
        var countered = timing.clock.impact_in;
        if (owed.reaction) |r| {
            const release = timing.clock.reactionRelease();
            var impact = release + turn.pace.bump_lands;
            if (r.flight) |f| {
                const shot_ = Shot{ .from = r.from, .flight = f, .act = .overwatch, .t = -release };
                self.shot = shot_;
                impact = self.loose(shot_).lands;
            }
            switch (r.outcome) {
                .miss => {},
                .hit => |h| self.strike(sim, gas, .{ .actor = h }, .{ .from = r.from, .wait = impact }),
            }
            if (r.recovery) |after| self.recordRecovery(sim, impact, after);
            self.holdUntil(impact);
            turn.reaction(&timing.clock, impact);
            countered = impact;
        }
        return countered;
    }

    /// `s` released `-s.t` seconds on: held until it ends; when it lands and ends.
    fn loose(self: *Presentation, s: Shot) struct { lands: f32, ends: f32 } {
        const release = -s.t;
        self.holdUntil(release + s.ends());
        return .{ .lands = release + s.lands(), .ends = release + s.ends() };
    }

    fn scheduleKnock(self: *Presentation, sim: *const Simulation, owed: *const Owed, countered: f32, timing: *BodyTiming, turn: *schedule.Turn) void {
        if (owed.knock) |k| {
            const shoved = &self.glide[sim.heroSlot().?];
            shoved.* = shoved.toward(k.to, -countered);
            self.holdUntil(shoved.left());
            turn.knock(&timing.clock, k.to, shoved.left());
        }
    }

    fn scheduleHarm(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, owed: *const Owed, timing: *BodyTiming, turn: *const schedule.Turn) f32 {
        timing.clock.finishAfter(self.fx.impacts.landsIn(timing.slot));
        inline for (comptime std.enums.values(simulation.Tick)) |t| {
            if (comptime @FieldType(Owed, @tagName(t)) == ?Harm) if (@field(owed, @tagName(t))) |h| {
                if (h.recovery != null) timing.clock.finishAfter(turn.recoveryReadyIn());
            };
        }
        if (owed.worn) |c| self.fx.settle(timing.clock.finishes_in, .{ .slot = timing.slot, .after = c });
        const mark: ?[2]f32 = if (timing.shown) mathx.centre(timing.at) else null;
        const drip: ?fx.Drip = if (mark) |m| .{ .at = m, .matter = fx.matterOf(timing.body.kind) } else null;
        const in_view = timing.shown or timing.clock.staggered;
        inline for (comptime std.enums.values(simulation.Tick)) |t| switch (t) {
            .worn => {},
            .healed => if (owed.healed) |after| self.fx.settle(timing.clock.finishes_in, .{ .slot = timing.slot, .after = after, .puff = fx.Puff.over(mark, look.gasInk(comptime t.gas().?)) }),
            .gassed, .scalded => if (@field(owed, @tagName(t))) |h| self.harmShown(sim, gas, timing.at, timing.clock.finishes_in, h, null, in_view, .{ .slot = timing.slot, .puff = fx.Puff.over(mark, look.gasInk(comptime t.gas().?)) }),
            .scorched, .burned => if (@field(owed, @tagName(t))) |h| self.harmShown(sim, gas, timing.at, timing.clock.finishes_in, h, .fire, in_view, .{ .slot = timing.slot, .fire_at = mark }),
            .bled => if (owed.bled) |h| self.harmShown(sim, gas, timing.at, timing.clock.finishes_in, h, null, in_view, .{ .slot = timing.slot, .drip = drip }),
        };
        if (timing.body.submerged != self.under.isSet(timing.slot.index)) {
            self.dives[timing.slot.index] = timing.clock.emergesIn(timing.body.submerged);
        }
        return timing.clock.finishes_in;
    }

    fn clearIn(self: *const Presentation, sim: *const Simulation, slot: usize, to: P) f32 {
        var t: f32 = if (self.fx.speech[slot].after) |fallen| self.fx.impacts.landsIn(.fromIndex(fallen)) else 0;
        if (!self.litShown(sim, to)) return t;
        for (sim.pool.constSlice(), 0..) |a, j| {
            if (a.alive or !a.at.eq(to) or !self.standing(sim, j)) continue;
            t = @max(t, @max(self.fx.impacts.heldIn(.fromIndex(j)), self.glide[j].left()));
        }
        return t;
    }

    fn harmShown(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, at: P, lands: f32, h: Harm, element: ?damage.Element, in_view: bool, s: fx.Sting) void {
        if (h.recovery) |after| self.recordRecovery(sim, lands, after);
        if (h.kill) {
            self.strikeBody(sim, gas, s.slot, at, true, h.after, .{ .from = at, .wait = lands, .element = element });
        } else if (in_view) {
            var shown = s;
            shown.after = h.after;
            self.sting(lands, shown);
        } else self.fx.settle(lands, .{ .slot = s.slot, .after = h.after });
    }

    pub fn strike(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, impact: fx.Impact, s: Stroke) void {
        const at = impact.at();
        const dir: ?[2]f32 = if (at.eq(s.from)) null else mathx.unitToward(mathx.centre(s.from), mathx.centre(at));
        const body: ?*const actor.Actor = switch (impact) {
            .actor => |a| &sim.pool.items[a.slot.index],
            .barrel => null,
        };
        const kind: ?actor.Kind = if (body) |b| b.kind else null;
        const hero = impact == .actor and sim.isHero(impact.actor.slot.index);
        const veiled = if (body) |b| self.veiledShown(b, impact.actor.slot.index, false) else false;
        if (hero or (self.litShown(sim, at) and !veiled)) {
            self.fx.strike(s.wait, .{ .impact = impact, .dir = dir, .matter = fx.matterOf(kind), .element = s.element });
            self.flashes(s.wait);
        } else switch (impact) {
            .actor => |a| if (a.after) |after| self.fx.settle(s.wait, .{ .slot = a.slot, .after = after }),
            .barrel => {},
        }
        const k = kind orelse return;
        if (!impact.lethal()) return;
        self.landBefallen(impact.actor.slot.index, s.wait);
        switch (actor.row(k).blow) {
            .burst => |b| switch (b) {
                .gas => gas.hold(s.wait),
                .fire => {
                    gas.hold(s.wait);
                    self.holdFire(&sim.lv, s.wait);
                    if (self.litShown(sim, at)) self.recordBurst(sim, s.wait, .{ .at = at, .area = rewards.pyre(&sim.lv, at), .element = .fire });
                },
            },
            .strike => {},
        }
    }

    fn strikeBody(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, slot: actor.ActorSlot, at: P, lethal: bool, after: fx.After, s: Stroke) void {
        self.strike(sim, gas, .{ .actor = .{ .slot = slot, .at = at, .lethal = lethal, .after = after } }, s);
    }

    pub fn shimmerBody(self: *Presentation, wait: f32, a: *const actor.Actor) void {
        self.fx.shimmerIn(wait, .{ .at = mathx.centre(a.at), .col = look.body(a.kind).fg });
    }

    pub fn sting(self: *Presentation, wait: f32, s: fx.Sting) void {
        self.fx.sting(wait, s);
        self.flashes(wait);
    }

    fn flashes(self: *Presentation, wait: f32) void {
        self.holdUntil(wait + fx.FLASH_S);
    }
};

/// Where a blow came from, and how long until the picture reaches it.
pub const Stroke = struct {
    from: P,
    wait: f32,
    element: ?damage.Element = null,

    pub fn along(s: Stroke, step: usize, cells: usize) Stroke {
        var out = s;
        out.wait = s.wait * @as(f32, @floatFromInt(step + 1)) / @as(f32, @floatFromInt(cells));
        return out;
    }
};

pub const Life = struct { hp: i32, max: i32 };

const LAID_LAYERS = .{ "flames", "barrier", "caltrops" };
const PACE = schedule.Pace{ .stagger = game.STAGGER_S, .bump_lands = game.BUMP_LANDS };

/// A walk due this close to the turn's last glide ending is not held for it.
const PACE_SLACK: f32 = 1e-4;
/// How far through a step its splash or dust is drawn: the foot coming down.
pub const STEP_AT: f32 = 0.85;
const HOUR_EASE: f32 = 4;
const WEATHER_EASE: f32 = 1.5;
const OCCLUSION_EASE: f32 = 12;
pub const EMBER_S: f32 = 0.45;
const XP_EASE: f32 = 8;
pub const RESOURCE_EASE = XP_EASE;

/// Cell-widths a drawn figure stops short of its cell's sides, and of its top and bottom, as scenery hides it.
const FIGURE_INSET_X = 0.15;
const FIGURE_INSET_Y = 0.1;
/// Cells round a body that may hide it, from a cell up-left to the two-cell tall scenery in front of it.
const COVER_LO = P{ .x = grid.WIDEST, .y = 1 };
const COVER_HI = P{ .x = 2, .y = 3 };

fn hides(at: rl.Vector2, p: P, t: grid.Tile) bool {
    const corner = glide.cellPx(p);
    const x = corner.x;
    const y = corner.y;
    const top = y - if (look.tall(t)) game.CELL_F else 0;
    const bottom = y + if (look.tall(t)) 0 else game.CELL_F;
    return at.x + game.CELL_F * (1 - FIGURE_INSET_X) > x and at.x + game.CELL_F * FIGURE_INSET_X < x + game.CELL_F * @as(f32, @floatFromInt(t.footprint(p).width())) and
        at.y + game.CELL_F * (1 - FIGURE_INSET_Y) > top and at.y + game.CELL_F * FIGURE_INSET_Y < bottom;
}

fn heldBack(was: grid.Tile, now: grid.Tile) grid.Tile {
    return if (fire.burntDown(was, now) or ice.turned(was, now)) was else now;
}

fn facingOf(dx: i32) ?actor.Facing {
    return if (dx < 0) .left else if (dx > 0) .right else null;
}

fn strikeElement(k: actor.Kind) ?damage.Element {
    return switch (actor.row(k).blow) {
        .strike => |s| s.element,
        .burst => null,
    };
}

const BodyTiming = struct {
    slot: actor.ActorSlot,
    body: *const actor.Actor,
    at: P,
    hero_at: P,
    shown: bool,
    clock: schedule.Body,
};
