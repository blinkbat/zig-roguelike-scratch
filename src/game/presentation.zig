const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const day = @import("../map/day.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const chain = @import("../play/chain.zig");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const chronicle = @import("../play/chronicle.zig");
const fx = @import("../gfx/fx.zig");
const cloud = @import("../gfx/cloud.zig");
const look = @import("../gfx/look.zig");
const hud = @import("../ui/hud.zig");
const game = @import("../game.zig");
const glide = @import("glide.zig");
const simulation = @import("sim.zig");
const rewards = @import("rewards.zig");
const Simulation = simulation.Simulation;
const P = mathx.P;

const FLIGHT_S: f32 = 0.022;
const TRAIL_PER_CELL: usize = 12;

pub fn flown(n: usize) f32 {
    return @as(f32, @floatFromInt(n)) * FLIGHT_S;
}

/// Presentation only: the hit already resolved when this was made.
pub const Shot = struct {
    flight: bow.Flight,
    from: P,
    act: skillbar.Act = .shoot,
    /// A thrown net rather than an arrow.
    net: bool = false,
    t: f32 = 0,
    trail_t: f32 = 0,

    /// When the missile reaches its last cell, as its hit is presented.
    pub fn lands(self: *const Shot) f32 {
        return flown(self.flight.len -| 1);
    }

    pub fn ends(self: *const Shot) f32 {
        return flown(self.flight.len);
    }

    pub fn position(self: *const Shot, time: f32) [2]f32 {
        const a = mathx.centre(self.from);
        if (self.flight.len == 0) return a;
        const b = mathx.centre(self.flight.path[self.flight.len - 1]);
        const duration = self.lands();
        const k = if (duration > 0) std.math.clamp(time / duration, 0, 1) else 1;
        return mathx.lerp2(a, b, k);
    }

    pub fn direction(self: *const Shot) [2]f32 {
        const a = mathx.centre(self.from);
        const b = self.position(self.ends());
        const len = @max(0.001, mathx.len(b[0] - a[0], b[1] - a[1]));
        return .{ (b[0] - a[0]) / len, (b[1] - a[1]) / len };
    }
};

test "missiles move continuously to the existing impact time in every direction" {
    const lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    var checked: usize = 0;
    for (mathx.ALL_DIRS) |d| {
        const delta = d.delta();
        const to = P{ .x = from.x + delta.x * 6, .y = from.y + delta.y * 6 };
        const shot_ = Shot{ .from = from, .flight = bow.fly(&lv, from, to) };
        const lands = shot_.lands();
        try std.testing.expectEqual(mathx.centre(from), shot_.position(0));
        try std.testing.expectEqual(mathx.centre(to), shot_.position(lands));
        const a = shot_.position(lands * 0.4);
        const b = shot_.position(lands * 0.41);
        const moved = mathx.len(b[0] - a[0], b[1] - a[1]);
        try std.testing.expect(moved > 0 and moved < 0.1);
        checked += 1;
    }
    std.debug.print("smooth missiles: {d} directions, sub-tile motion, exact arrival at presented impact\n", .{checked});
}

/// `snare`: a net, holding the hero as it lands, or dodged (null).
pub const Bite = union(enum) { hurt: fx.After, kill: fx.After, burst: fx.After, snare: ?fx.After, miss };

/// The hero shoved from one cell to the next as the blow lands.
pub const Knock = struct { from: P, to: P };

/// A body healed as the mending lands; none when the mending only woke its kin.
pub const Mended = struct { slot: ?actor.ActorSlot = null, after: ?fx.After = null };

/// Presentation debts land at the body's stagger, or after the hero when it has no stagger.
pub const Owed = struct {
    bit: ?Bite = null,
    arrow: ?bow.Flight = null,
    gassed: ?Harm = null,
    healed: ?fx.After = null,
    burned: ?Harm = null,
    bled: ?Harm = null,
    worn: ?fx.After = null,
    swept: ?Swept = null,
    thorns: ?Harm = null,
    reaction: ?Reaction = null,
    knock: ?Knock = null,
    mended: ?Mended = null,

    pub fn any(o: *const Owed) bool {
        inline for (std.meta.fields(Owed)) |f| {
            if (@field(o, f.name) != null) return true;
        }
        return false;
    }
};

pub const ReactionOutcome = union(enum) { miss, hit: fx.ActorImpact };
pub const Reaction = struct { from: P, flight: ?bow.Flight, outcome: ReactionOutcome, recovery: ?fx.After = null };

/// What a foe's sweep struck besides the hero, landing with its blow on the hero.
pub const Swept = struct {
    hit: [actor.SWEEP_CELLS]fx.Impact = undefined,
    n: usize = 0,
};

comptime {
    std.debug.assert(fx.DUE >= actor.MAX * (std.meta.fields(Owed).len + actor.SWEEP_CELLS) + @max(2, chain.JUMPS));
}

pub const Harm = struct { kill: bool, after: fx.After, recovery: ?fx.After = null };

/// `in` is set once the turn it was taken in has its stagger.
pub const Turning = struct { to: actor.Facing, in: ?f32 = null };

/// What is drawn of the run, lagging the simulation until each blow lands; nothing in the simulation reads it.
pub const Presentation = struct {
    occlusion: [grid.CELLS]f32 = @splat(0),
    /// The middle of the body each occluding cell last fades around, cells.
    occluder: [grid.CELLS][2]f32 = @splat(.{ 0, 0 }),
    /// Indexed by pool slot.
    glide: [actor.MAX]glide.Glide = undefined,
    /// Indexed by pool slot.
    facing: [actor.MAX]actor.Facing = @splat(.right),
    turning: [actor.MAX]?Turning = @splat(null),
    /// Pool-indexed presentation state, updated when each blow lands.
    pictured: [actor.MAX]fx.Body = undefined,
    /// The blows dealt so far, so the picture takes them in the order they were dealt.
    seq: u64 = 0,
    /// Indexed by pool slot: the slot a slime split off, until the blow that split it lands.
    split_from: [actor.MAX]?usize = @splat(null),
    /// Indexed by pool slot: gold kept out of its drop until that death is drawn.
    dropped_gold: [actor.MAX]i32 = @splat(0),
    owed: [actor.MAX]Owed = @splat(.{}),
    shot: ?Shot = null,
    foe_shots: [actor.MAX]?Shot = @splat(null),
    /// Where the hero stood before the turn's first knockback: its own move ends there.
    knocked_from: ?P = null,
    /// Seconds until the last turn's slowest glide, arrow or flash ends; a walk waits for it.
    busy: f32 = 0,
    /// Seconds until the hero's non-walking action lands; starts the foe stagger.
    lead: ?f32 = null,
    fx: fx.Fx = .{},
    gold_taken: ?items.Coins = null,
    /// Spent shield mana held for blows not yet presented.
    mana_held: i32 = 0,
    /// Kill refills appear only when the killing blow lands.
    flasks_shown: simulation.Flasks = .initFill(.{}),
    /// `xpLevels` as of the last drawn turn, and the bar easing toward it.
    xp_aim: f32 = 0,
    xp_shown: f32 = 0,
    life_fill: f32 = 1,
    mana_fill: f32 = 1,
    /// `growth` and `gold` as of the last drawn turn, for the character book.
    growth_shown: progress.State = .{},
    gold_shown: i32 = 0,
    hour_shown: f32 = day.Clock.hour(.{}),

    pub fn quiet(self: *const Presentation) bool {
        return self.busy <= PACE_SLACK;
    }

    /// Seconds since the last turn was drawn out.
    pub fn sinceQuiet(self: *const Presentation) f32 {
        return @max(0, -self.busy);
    }

    pub fn holdUntil(self: *Presentation, t: f32) void {
        self.busy = @max(self.busy, t);
    }

    pub fn deferDamage(self: *Presentation, result: simulation.DamageResult) void {
        self.mana_held += result.mana;
    }

    pub fn recordAttack(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, origin: chronicle.AttackOrigin, stroke: Stroke, flight: ?bow.Flight, outcome: ReactionOutcome, recovery: ?fx.After) void {
        switch (origin) {
            .reaction => |by| self.owed[by.slot().index].reaction = .{ .from = stroke.from, .flight = flight, .outcome = outcome, .recovery = recovery },
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
        self.fx.settle(wait, .{ .slot = sim.heroSlot().?, .after = after });
    }

    pub fn recordProjectile(self: *Presentation, from: P, act: skillbar.Act, flight: bow.Flight) Stroke {
        self.shot = .{ .flight = flight, .from = from, .act = act };
        self.holdUntil(self.shot.?.ends());
        const stroke = Stroke{ .from = from, .wait = self.shot.?.lands(), .fire = act.element() == .fire };
        if (act.element() == .lightning and flight.len > 0) self.fx.zap(@max(0, stroke.wait - game.ZAP_S), .{ .from = mathx.centre(from), .to = mathx.centre(flight.path[flight.len - 1]) });
        self.lead = stroke.wait;
        return stroke;
    }

    pub fn damageAfter(self: *Presentation, sim: *const Simulation, result: simulation.DamageResult, child: ?actor.ActorId) fx.After {
        var after = self.afterOf(sim, result.target.slot().index);
        after.reveals = if (child) |id| id.slot().index else null;
        after.mana = result.mana;
        return after;
    }

    pub fn recordSplit(self: *Presentation, sim: *const Simulation, parent: actor.ActorId, child: actor.ActorId) void {
        const i = parent.slot().index;
        const o = child.slot().index;
        const body = sim.pool.items[o];
        self.split_from[o] = i;
        self.pictured[o] = fx.Body.of(body, self.seq);
        self.glide[o] = glide.Glide.rest(&body);
        self.facing[o] = if (self.turning[i]) |t| t.to else self.facing[i];
    }

    pub fn recordDeath(self: *Presentation, target: actor.ActorId, death: rewards.Death) void {
        self.dropped_gold[target.slot().index] = death.gold;
        self.recordFright(target.slot(), death.frightened);
    }

    pub fn recordFright(self: *Presentation, fallen: actor.ActorSlot, frightened: rewards.Frightened) void {
        var slots = frightened.iterator(.{});
        while (slots.next()) |slot| self.fx.frighten(slot, fallen.index);
    }

    pub fn recordFoeAttack(self: *Presentation, by: actor.ActorId, outcome: Bite, flight: ?bow.Flight) void {
        const owed = &self.owed[by.slot().index];
        owed.bit = outcome;
        owed.arrow = flight;
    }

    pub fn recordStatus(self: *Presentation, target: actor.ActorId, comptime tick: simulation.Tick, harm: Harm) void {
        @field(self.owed[target.slot().index], @tagName(tick)) = harm;
    }

    pub fn recordHeal(self: *Presentation, target: actor.ActorId, after: fx.After) void {
        self.owed[target.slot().index].healed = after;
    }

    pub fn recordWear(self: *Presentation, sim: *const Simulation, target: actor.ActorId) void {
        self.owed[target.slot().index].worn = self.afterOf(sim, target.slot().index);
    }

    pub fn recordThorns(self: *Presentation, target: actor.ActorId, harm: Harm) void {
        self.owed[target.slot().index].thorns = harm;
    }

    pub fn recordSweep(self: *Presentation, by: actor.ActorId, swept: Swept) void {
        if (swept.n > 0) self.owed[by.slot().index].swept = swept;
    }

    pub fn recordKnock(self: *Presentation, by: actor.ActorId, from: P, to: P) void {
        if (self.knocked_from == null) self.knocked_from = from;
        self.owed[by.slot().index].knock = .{ .from = from, .to = to };
    }

    pub fn recordMend(self: *Presentation, by: actor.ActorId, mended: Mended) void {
        self.owed[by.slot().index].mended = mended;
    }

    pub fn freshTurn(self: *Presentation) void {
        game.toDefaults(self, &.{ "shot", "foe_shots", "knocked_from", "busy", "lead", "owed", "split_from", "dropped_gold", "turning", "gold_taken" });
        self.fx.clear();
    }

    pub fn freshRun(self: *Presentation) void {
        game.toDefaults(self, &.{ "mana_held", "flasks_shown" });
    }

    pub fn freshFacing(self: *Presentation) void {
        game.toDefaults(self, &.{"facing"});
    }

    fn glideHeld(self: *Presentation, slot: usize, gl: glide.Glide) f32 {
        self.glide[slot] = gl;
        self.holdUntil(gl.left());
        return gl.left();
    }

    pub fn bumpHeld(self: *Presentation, slot: usize, at: P, late: f32) f32 {
        return self.glideHeld(slot, self.glide[slot].bumping(at, late));
    }

    pub fn glideToHeld(self: *Presentation, slot: usize, to: P, t: f32) f32 {
        return self.glideHeld(slot, self.glide[slot].toward(to, t));
    }

    pub fn turnToward(self: *Presentation, id: u16, dx: i32) void {
        self.facing[actor.Pool.slot(id)] = facingOf(dx) orelse return;
    }

    pub fn turnLater(self: *Presentation, id: u16, dx: i32) void {
        self.turning[actor.Pool.slot(id)] = .{ .to = facingOf(dx) orelse return };
    }

    /// Every pending turn taken at once.
    pub fn turnNow(self: *Presentation) void {
        for (self.turning, &self.facing) |t, *f| {
            if (t) |u| f.* = u.to;
        }
        self.turning = @splat(null);
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

    /// The body as a blow dealt now leaves it, numbered after every blow before.
    pub fn snap(self: *Presentation, a: actor.Actor) fx.Body {
        self.seq += 1;
        return fx.Body.of(a, self.seq);
    }

    pub fn afterOf(self: *Presentation, sim: *const Simulation, slot: usize) fx.After {
        return .{ .body = self.snap(sim.pool.items[slot]) };
    }

    pub fn settleHero(self: *Presentation, sim: *const Simulation, wait: f32) void {
        const slot = sim.heroSlot().?;
        self.fx.settle(wait, .{ .slot = slot, .after = self.afterOf(sim, slot) });
    }

    pub fn snapGlide(self: *Presentation, pool: *const actor.Pool) void {
        self.occlusion = @splat(0);
        for (pool.items[0..pool.n], 0..) |*a, i| self.glide[i] = glide.Glide.rest(a);
    }

    /// Dead bodies remain until their killing blow, flash and glide finish.
    pub fn standing(self: *const Presentation, sim: *const Simulation, i: usize) bool {
        if (self.split_from[i] != null) return false;
        return sim.pool.items[i].alive or self.fx.holds(i) or self.glide[i].done() < 1;
    }

    pub fn heroShown(self: *const Presentation, sim: *const Simulation) ?fx.Body {
        const i = sim.heroSlot() orelse return null;
        return self.pictured[i];
    }

    pub fn heroGlide(self: *const Presentation, sim: *const Simulation) ?glide.Glide {
        const i = sim.heroSlot() orelse return null;
        return if (self.standing(sim, i)) self.glide[i] else null;
    }

    pub fn heroNow(self: *const Presentation, sim: *const Simulation) ?rl.Vector2 {
        return (self.heroGlide(sim) orelse return null).now();
    }

    /// The hero's middle as drawn, cells: the carried light glides with the body.
    pub fn carrierAt(self: *const Presentation, sim: *const Simulation) ?[2]f32 {
        return game.middle(self.heroNow(sim) orelse return null);
    }

    pub fn drawnAt(self: *const Presentation, sim: *const Simulation, i: usize) ?rl.Vector2 {
        if (!self.standing(sim, i) or sim.pool.items[i].veiled()) return null;
        const at = self.glide[i].now();
        return if (sim.lv.isLit(game.cellUnder(at))) at else null;
    }

    pub fn drawnCell(self: *const Presentation, sim: *const Simulation, i: usize) ?P {
        return game.cellUnder(self.drawnAt(sim, i) orelse return null);
    }

    pub fn casterAt(self: *const Presentation, sim: *const Simulation, i: usize, area: grid.Box) ?rl.Vector2 {
        if (!self.standing(sim, i)) return null;
        const at = self.glide[i].now();
        return if (area.holds(game.cellUnder(at))) at else null;
    }

    pub fn manaShown(self: *const Presentation, sim: *const Simulation) i32 {
        return @min(sim.manaMax(), sim.mana + self.mana_held);
    }

    pub fn lifeShown(self: *const Presentation, sim: *const Simulation) Life {
        const h = self.heroShown(sim) orelse return .{ .hp = 0, .max = sim.lifeMax() };
        return .{ .hp = h.hp, .max = h.max };
    }

    /// Where the orbs' fills are easing to.
    pub fn lifeFill(self: *const Presentation, sim: *const Simulation) f32 {
        const life = self.lifeShown(sim);
        return hud.fillOf(life.hp, life.max);
    }

    pub fn manaFill(self: *const Presentation, sim: *const Simulation) f32 {
        return hud.fillOf(self.manaShown(sim), sim.manaMax());
    }

    pub fn settleResources(self: *Presentation, sim: *const Simulation) void {
        self.life_fill = self.lifeFill(sim);
        self.mana_fill = self.manaFill(sim);
    }

    pub fn showProgress(self: *Presentation, sim: *const Simulation) void {
        self.growth_shown = sim.growth;
        self.gold_shown = sim.gold;
        self.xp_aim = sim.xpLevels();
    }

    pub fn settleXp(self: *Presentation, sim: *const Simulation) void {
        self.showProgress(sim);
        self.xp_shown = self.xp_aim;
    }

    /// The sky, experience bar and orbs ease toward what the drawn turns show.
    pub fn ease(self: *Presentation, sim: *const Simulation, dt: f32) void {
        self.stepOcclusion(sim, dt);
        self.hour_shown = day.wrapHour(self.hour_shown + day.toward(self.hour_shown, sim.clock.hour()) * mathx.easing(dt, HOUR_EASE));
        self.xp_shown = mathx.ease(self.xp_shown, self.xp_aim, mathx.easing(dt, XP_EASE), 1);
        const resource_ease = mathx.easing(dt, RESOURCE_EASE);
        self.life_fill = mathx.ease(self.life_fill, self.lifeFill(sim), resource_ease, resource_ease);
        self.mana_fill = mathx.ease(self.mana_fill, self.manaFill(sim), resource_ease, resource_ease);
    }

    fn occluding(self: *const Presentation, sim: *const Simulation, i: usize) ?rl.Vector2 {
        const at = self.drawnAt(sim, i) orelse return null;
        return .{ .x = at.x, .y = at.y - @as(f32, @floatFromInt(self.glide[i].lift())) };
    }

    fn stepOcclusion(self: *Presentation, sim: *const Simulation, dt: f32) void {
        var covered = Covered.initEmpty();
        if (sim.heroSlot()) |h| self.cover(sim, h, &covered);
        for (0..sim.pool.n) |i| if (!sim.isHero(i)) self.cover(sim, i, &covered);
        const k = mathx.easing(dt, OCCLUSION_EASE);
        for (sim.lv.tile, &self.occlusion, 0..) |t, *hidden, i| {
            hidden.* = if (look.occludes(t)) mathx.ease(hidden.*, if (covered.isSet(i)) 1 else 0, k, k) else 0;
        }
    }

    fn cover(self: *Presentation, sim: *const Simulation, slot: usize, covered: *Covered) void {
        const at = self.occluding(sim, slot) orelse return;
        const under = game.cellUnder(at);
        var near = grid.Cells.of(under.sub(.{ .x = 1, .y = 1 }), under.add(.{ .x = 2, .y = 3 }));
        while (near.next()) |p| {
            if (!grid.Level.inside(p)) continue;
            const i = grid.Level.idx(p);
            const t = sim.lv.tile[i];
            if (covered.isSet(i) or !look.occludes(t) or !hides(at, p, t)) continue;
            covered.set(i);
            self.occluder[i] = game.middle(at);
        }
    }

    /// Time passes on the picture, then it takes whatever blows have landed.
    pub fn advance(self: *Presentation, sim: *const Simulation, dt: f32) void {
        self.busy -= dt;
        for (self.glide[0..sim.pool.n]) |*gl| gl.t += dt;
        if (sim.heroSlot()) |h| {
            if (self.glide[h].left() <= PACE_SLACK) self.gold_taken = null;
        }
        self.fx.step(&sim.lv, dt);
        self.catchUp(sim);
    }

    /// Footfalls, missiles and pending turns move on.
    pub fn stepMotion(self: *Presentation, sim: *const Simulation, dt: f32) void {
        self.splashSteps(sim);
        if (self.shot) |*s| {
            s.t += dt;
            const end = @min(s.t, s.lands());
            const gap = s.lands() / @as(f32, @floatFromInt(@max(1, s.flight.len * TRAIL_PER_CELL)));
            const heading = s.direction();
            while (s.trail_t < end) : (s.trail_t += gap) self.fx.trail(&sim.lv, s.position(s.trail_t), heading, s.act, s.t - s.trail_t);
            if (s.t >= s.ends()) self.shot = null;
        }
        for (&self.foe_shots) |*pending| {
            if (pending.*) |*s| {
                s.t += dt;
                if (s.t >= s.ends()) pending.* = null;
            }
        }
        self.stepTurning(dt);
    }

    pub fn splashSteps(self: *Presentation, sim: *const Simulation) void {
        for (self.glide[0..sim.pool.n], 0..) |*gl, i| {
            if (gl.splashed or gl.done() < SPLASH_AT) continue;
            gl.splashed = true;
            if (gl.bump != null or std.meta.eql(gl.from, glide.cellPx(gl.to))) continue;
            if (self.pictured[i].down() or actor.row(self.pictured[i].kind).movement != .ground) continue;
            const at = self.drawnAt(sim, i) orelse continue;
            if (sim.lv.at(game.cellUnder(at)) == .shallows) self.fx.splash(game.middle(at));
        }
    }

    /// Reveal split halves at impact, after their parent becomes visible.
    pub fn catchUp(self: *Presentation, sim: *const Simulation) void {
        var dying = false;
        for (sim.pool.items[0..sim.pool.n], 0..) |a, i| {
            if (!self.fx.pending(i)) {
                self.pictured[i] = fx.Body.of(a, self.seq);
            } else if (self.fx.landedOn(i)) |b| {
                if (b.seq > self.pictured[i].seq) self.pictured[i] = b;
            }
            if (!a.alive and !self.pictured[i].down()) dying = true;
            const from = self.split_from[i] orelse continue;
            if (self.fx.revealing(i) or self.split_from[from] != null) continue;
            self.split_from[i] = null;
            self.glide[i] = self.glide[from].toward(a.at, -self.clearIn(sim, i, a.at));
            if (sim.lv.isLit(sim.pool.items[from].at) or sim.lv.isLit(a.at)) self.holdUntil(self.glide[i].left());
        }
        if (!dying) self.flasks_shown = sim.flasks;
        self.mana_held = @max(0, self.mana_held - self.fx.mana_landed);
        self.fx.mana_landed = 0;
        if (sim.heroSlot()) |h| {
            if (!self.fx.pending(h)) self.mana_held = 0;
        }
        self.fx.react(self.pictured[0..sim.pool.n]);
    }

    /// `late` is seconds since the glides started; visible foes follow the hero in acting order.
    pub fn stepGlide(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, late: f32) void {
        var next: f32 = if (self.lead) |t| t + late + game.STAGGER_S else 0;
        const hero = sim.heroSlot().?;
        const warded = self.owed[hero].worn;
        self.owed[hero].worn = null;
        const hero_done = self.stagger(sim, gas, sim.hero, late, self.lead orelse 0, &next);
        self.lead = null;
        self.knocked_from = null;
        var part: [actor.MAX]f32 = @splat(hero_done);
        for (sim.order[0..sim.order_n]) |id| part[actor.Pool.slot(id)] = self.stagger(sim, gas, id, late, hero_done, &next);
        for (self.owed[0..sim.pool.n], 0..) |*o, i| {
            if (!o.any()) continue;
            const start = if (self.split_from[i]) |p| @max(hero_done, part[p], self.fx.revealsIn(i)) else hero_done;
            part[i] = self.stagger(sim, gas, actor.Pool.idOf(i), late, start, &next);
        }
        if (warded) |c| self.fx.settle(std.mem.max(f32, part[0..sim.pool.n]), .{ .slot = hero, .after = c });
        for (sim.pool.items[0..sim.pool.n], 0..) |*a, i| {
            if (!self.glide[i].to.eq(a.at)) self.glide[i] = self.glide[i].toward(a.at, late);
        }
    }

    /// Completion time; unplaced bodies wait for the hero and knockback slide.
    fn stagger(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, id: u16, late: f32, start: f32, next: *f32) f32 {
        comptime for (std.enums.values(std.meta.FieldEnum(Owed))) |t| switch (t) {
            .bit, .arrow, .gassed, .healed, .burned, .bled, .worn, .swept, .thorns, .reaction, .knock, .mended => {},
        };
        const i = actor.Pool.slot(id);
        const a = sim.pool.items[i];
        const gl = &self.glide[i];
        const dest = if (id == sim.hero) self.knocked_from orelse a.at else a.at;
        const moved = !gl.to.eq(dest);
        if (!moved and !self.owed[i].any()) {
            if (self.turning[i]) |*t| {
                if (t.in == null) t.in = start;
            }
            return start;
        }
        const owed = self.owed[i];
        self.owed[i] = .{};
        const bit = owed.bit;
        const shown = sim.lv.isLit(a.at);
        const placed = if (moved) shown or sim.lv.isLit(gl.to) else (shown or owed.arrow != null) and (bit != null or owed.mended != null);
        var wait = if (placed) next.* else 0;
        if (placed and id != sim.hero and (moved or bit != null)) wait = @max(wait, late + gl.left());
        if (placed and moved and id != sim.hero) wait = @max(wait, late + self.clearIn(sim, i, a.at));
        if (placed) next.* = wait + game.STAGGER_S;
        if (self.turning[i]) |*t| t.in = if (placed) wait - late else start;
        const hero = sim.heroSlot().?;
        const hero_at = if (owed.knock) |k| k.from else sim.heroAt().?;
        var lands = if (placed) wait else if (moved) start else @max(start, gl.left());
        if (moved) {
            gl.* = gl.toward(dest, late - wait);
        } else if (bit != null and owed.arrow == null) {
            gl.* = gl.bumping(hero_at, late - wait);
        }
        if ((moved or (bit != null and owed.arrow == null)) and placed) {
            lands = gl.left();
            self.holdUntil(lands);
        }
        var hits = (if (placed) wait - late else start) + game.BUMP_LANDS;
        if (owed.arrow) |flight| {
            const release = @max(start, wait - late);
            const s = Shot{ .from = a.at, .flight = flight, .t = -release, .net = bit != null and bit.? == .snare };
            self.foe_shots[i] = s;
            hits = release + s.lands();
            lands = release + s.ends();
            next.* = @max(next.*, lands + late);
            self.holdUntil(lands);
        }
        if (bit) |b| switch (b) {
            .hurt, .kill => |after| self.strike(sim, gas, .{ .actor = .{ .slot = .fromIndex(hero), .at = hero_at, .lethal = b == .kill, .after = after } }, .{ .from = a.at, .wait = hits }),
            .burst => |after| self.strike(sim, gas, .{ .actor = .{ .slot = .fromIndex(i), .at = a.at, .lethal = true, .after = after } }, .{ .from = hero_at, .wait = hits }),
            .snare => |held| if (held) |after| self.fx.settle(hits, .{ .slot = hero, .after = after }),
            .miss => {},
        };
        if (owed.knock) |k| {
            const shoved = &self.glide[hero];
            shoved.* = shoved.toward(k.to, -hits);
            self.holdUntil(shoved.left());
            lands = @max(lands, shoved.left());
        }
        if (owed.mended) |m| {
            if (shown) self.fx.shimmer(mathx.centre(a.at), look.body(a.kind).fg);
            if (m.slot) |s| {
                if (m.after) |after| self.fx.settle(hits, .{ .slot = s.index, .after = after });
                if (sim.lv.isLit(sim.pool.items[s.index].at)) self.fx.shimmer(mathx.centre(sim.pool.items[s.index].at), look.LIFE);
            }
        }
        if (owed.swept) |*sw| for (sw.hit[0..sw.n]) |h| self.strike(sim, gas, h, .{ .from = a.at, .wait = hits });
        if (owed.thorns) |h| {
            self.strike(sim, gas, .{ .actor = .{ .slot = .fromIndex(i), .at = a.at, .lethal = h.kill, .after = h.after } }, .{ .from = hero_at, .wait = hits });
            if (h.recovery) |after| self.fx.settle(hits, .{ .slot = hero, .after = after });
        }
        if (owed.reaction) |r| {
            const release = if (moved) lands else hits;
            var impact = release + game.BUMP_LANDS;
            if (r.flight) |f| {
                const shot_ = Shot{ .from = r.from, .flight = f, .act = .overwatch, .t = -release };
                self.shot = shot_;
                impact = release + shot_.lands();
                self.holdUntil(release + shot_.ends());
            }
            switch (r.outcome) {
                .miss => {},
                .hit => |h| self.strike(sim, gas, .{ .actor = h }, .{ .from = r.from, .wait = impact }),
            }
            if (r.recovery) |after| self.fx.settle(impact, .{ .slot = hero, .after = after });
            self.holdUntil(impact);
            lands = @max(lands, impact);
            next.* = @max(next.*, impact + late + game.STAGGER_S);
        }
        lands = @max(lands, self.fx.landsIn(i));
        inline for (.{ "gassed", "burned", "bled" }) |field| if (@field(owed, field)) |h| {
            if (h.recovery != null) lands = @max(lands, @max(0, next.* - late));
        };
        if (owed.worn) |c| self.fx.settle(lands, .{ .slot = i, .after = c });
        const mark: ?[2]f32 = if (shown) mathx.centre(a.at) else null;
        const drip: ?fx.Drip = if (mark) |m| .{ .at = m, .matter = fx.matterOf(a.kind) } else null;
        const in_view = shown or placed;
        if (owed.gassed) |h| self.harmShown(sim, gas, a.at, lands, h, false, in_view, .{ .slot = i, .puff = fx.Puff.over(mark, look.GAS) });
        if (owed.healed) |after| self.fx.settle(lands, .{ .slot = i, .after = after, .puff = fx.Puff.over(mark, look.HEALING_GAS) });
        if (owed.burned) |h| self.harmShown(sim, gas, a.at, lands, h, true, in_view, .{ .slot = i, .fire_at = mark });
        if (owed.bled) |h| self.harmShown(sim, gas, a.at, lands, h, false, in_view, .{ .slot = i, .drip = drip });
        return lands;
    }

    /// Wait for deaths at the destination and witnessed deaths that caused flight.
    fn clearIn(self: *const Presentation, sim: *const Simulation, slot: usize, to: P) f32 {
        var t: f32 = if (self.fx.speech[slot].after) |fallen| self.fx.landsIn(fallen) else 0;
        if (!sim.lv.isLit(to)) return t;
        for (sim.pool.items[0..sim.pool.n], 0..) |a, j| {
            if (a.alive or !a.at.eq(to) or !self.standing(sim, j)) continue;
            t = @max(t, @max(self.fx.heldIn(j), self.glide[j].left()));
        }
        return t;
    }

    fn harmShown(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, at: P, lands: f32, h: Harm, fire: bool, in_view: bool, s: fx.Sting) void {
        if (h.recovery) |after| self.fx.settle(lands, .{ .slot = sim.heroSlot().?, .after = after });
        if (h.kill) {
            self.strike(sim, gas, .{ .actor = .{ .slot = .fromIndex(s.slot), .at = at, .lethal = true, .after = h.after } }, .{ .from = at, .wait = lands, .fire = fire });
        } else if (in_view) {
            var shown = s;
            shown.after = h.after;
            self.sting(lands, shown);
        } else self.fx.settle(lands, .{ .slot = s.slot, .after = h.after });
    }

    /// A blow drawn landing on `at`, or only settled when the hero cannot see it; a bursting kill holds its gas back as long.
    pub fn strike(self: *Presentation, sim: *const Simulation, gas: *cloud.Cloud, impact: fx.Impact, s: Stroke) void {
        const at = impact.at();
        const len = mathx.distEuclid(at, s.from);
        const dir: ?[2]f32 = if (len == 0) null else .{ @as(f32, @floatFromInt(at.x - s.from.x)) / len, @as(f32, @floatFromInt(at.y - s.from.y)) / len };
        const kind: ?actor.Kind = switch (impact) {
            .actor => |a| sim.pool.items[a.slot.index].kind,
            .barrel => null,
        };
        const hero = switch (impact) {
            .actor => |a| sim.isHero(a.slot.index),
            .barrel => false,
        };
        if (hero or sim.lv.isLit(at)) {
            self.fx.strike(s.wait, .{ .impact = impact, .dir = dir, .matter = fx.matterOf(kind), .fire = s.fire });
            self.flashes(s.wait);
        } else switch (impact) {
            .actor => |a| if (a.after) |after| self.fx.settle(s.wait, .{ .slot = a.slot.index, .after = after }),
            .barrel => {},
        }
        const k = kind orelse return;
        if (!impact.lethal()) return;
        switch (actor.row(k).blow) {
            .burst => |b| switch (b) {
                .gas => gas.hold(s.wait),
                .fire => if (sim.lv.isLit(at)) self.fx.burst(s.wait, .{ .at = at, .area = rewards.pyre(&sim.lv, at), .element = .fire }),
            },
            .strike => {},
        }
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
pub const Stroke = struct { from: P, wait: f32, fire: bool = false };

pub const Life = struct { hp: i32, max: i32 };

/// A walk due this close to the turn's last glide ending is not held for it.
const PACE_SLACK: f32 = 1e-4;
/// How far through a step in shallows its splash is drawn: the foot coming down.
pub const SPLASH_AT: f32 = 0.85;
/// Per second, how fast the sky drawn catches the hour a turn moved on.
const HOUR_EASE: f32 = 4;
const OCCLUSION_EASE: f32 = 12;
/// Per second, how fast the experience bar fills toward a drawn turn's experience.
const XP_EASE: f32 = 8;
/// Per second, how fast the life and mana orbs fill toward what is shown.
pub const RESOURCE_EASE = XP_EASE;

const Covered = std.StaticBitSet(grid.CELLS);

fn hides(at: rl.Vector2, p: P, t: grid.Tile) bool {
    const x = @as(f32, @floatFromInt(p.x)) * game.CELL_F;
    const y = @as(f32, @floatFromInt(p.y)) * game.CELL_F;
    const top = y - if (look.tall(t)) game.CELL_F else 0;
    const bottom = y + if (look.tall(t)) 0 else game.CELL_F;
    return at.x + game.CELL_F * 0.85 > x and at.x + game.CELL_F * 0.15 < x + game.CELL_F and
        at.y + game.CELL_F * 0.9 > top and at.y + game.CELL_F * 0.1 < bottom;
}

fn facingOf(dx: i32) ?actor.Facing {
    return if (dx < 0) .left else if (dx > 0) .right else null;
}
