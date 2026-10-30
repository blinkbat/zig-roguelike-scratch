const attacks = @import("attacks.zig");
const std = @import("std");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const heroes = @import("../play/hero.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const glacial = @import("../play/glacial.zig");
const juke = @import("../play/juke.zig");
const flask = @import("../play/flask.zig");
const consumable = @import("../play/consumable.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const fx = @import("../gfx/fx.zig");
const combat = @import("combat.zig");
const glide = @import("glide.zig");
const tactics = @import("tactics.zig");
const rules = @import("../play/tactics.zig");
const game = @import("../game.zig");
const menu = @import("../ui/menu.zig");
const P = mathx.P;

pub fn openAim(run: *game.Game, by: input.Button, act: skillbar.Act) void {
    const hero = run.sim.heroActor() orelse return;
    const suggested = preferredTarget(run, act, hero.at) orelse (if (act.consumes()) null else bow.pick(&run.sim.lv, &run.sim.pool, hero.at));
    if (suggested) |at| return aimAt(run, by, act, hero.at, at);
    if (act.reticle() == .bow) {
        const dx: i32 = if (run.pic.facing[run.sim.heroSlot().?] == .left) -1 else 1;
        const ahead = hero.at.add(.{ .x = dx, .y = 0 });
        return aimAt(run, by, act, hero.at, if (grid.Level.inside(ahead)) ahead else hero.at.add(.{ .x = -dx, .y = 0 }));
    }
    aimAt(run, by, act, hero.at, null);
}

fn targetAt(run: *game.Game, act: skillbar.Act, from: P, id: u16) ?P {
    const a = run.sim.pool.get(id) orelse return null;
    if (!a.seenFoe(&run.sim.lv) or !tactics.validAct(run, act, from, a.at)) return null;
    if (act.reticle() == .bow) {
        const flight = bow.previewAmong(&run.sim.lv, &run.sim.pool, from, a.at);
        if (!flight.hits(id)) return null;
    }
    return a.at;
}

fn preferredTarget(run: *game.Game, act: skillbar.Act, from: P) ?P {
    if (run.target) |id| if (targetAt(run, act, from, id)) |at| return at;
    var near = grid.Nearest{ .from = from };
    for (0..run.sim.pool.n) |i| {
        if (targetAt(run, act, from, actor.Pool.idOf(i))) |at| near.offer(at);
    }
    return near.best;
}

pub fn rememberTarget(run: *game.Game) void {
    if (run.mode.aim.act().attack() == null) return;
    const id = run.sim.lv.who(run.mode.aim.mark);
    const a = run.sim.pool.get(id);
    run.target = if (a != null and a.?.seenFoe(&run.sim.lv)) id else null;
}

pub fn openLeap(run: *game.Game, by: input.Button, act: skillbar.Act) void {
    const hero = run.sim.heroActor() orelse return;
    aiming(run, by, act);
    run.mode.aim.mark = hero.at;
}

fn openSwing(run: *game.Game, by: input.Button, act: skillbar.Act) void {
    const hero = run.sim.heroActor() orelse return;
    if (preferredTarget(run, act, hero.at)) |at| return aimAt(run, by, act, hero.at, at);
    var mark: ?P = null;
    for (mathx.ALL_DIRS) |d| {
        const p = hero.at.add(d.delta());
        if (!tactics.validAct(run, act, hero.at, p)) continue;
        const foe = if (run.sim.pool.get(run.sim.lv.who(p))) |a| a.foe() else false;
        if (foe or mark == null) mark = p;
        if (foe) break;
    }
    aimAt(run, by, act, hero.at, mark);
}

fn aimAt(run: *game.Game, by: input.Button, act: skillbar.Act, from: P, mark: ?P) void {
    const to = mark orelse {
        run.sim.log.say("Nothing in reach.", .{});
        return;
    };
    aiming(run, by, act);
    run.mode.aim.mark = to;
    run.pic.turnToward(run.sim.hero, to.x - from.x);
    rememberTarget(run);
}

pub fn aiming(run: *game.Game, by: input.Button, act: skillbar.Act) void {
    run.mode = .{ .aim = game.Aim.of(by, act, run.sim.heroAt().?) };
}

pub fn closeAim(run: *game.Game) void {
    if (run.mode == .aim) run.mode = .play;
}

const Blocked = enum { cooling, mana, unworn, empty, none_left, locked, pinned };

pub fn heroPinned(run: *const game.Game) bool {
    return (run.sim.heroBody() orelse return false).pin.turns > 0;
}

pub fn blocked(run: *const game.Game, act: skillbar.Act, flasks: *const game.simulation.Flasks, mana: i32, pinned: bool) ?Blocked {
    if (!run.sim.growth.unlocked(act)) return .locked;
    if (movesHero(act) and pinned) return .pinned;
    if (act == .unyielding and run.sim.heroBody() != null and run.sim.heroBody().?.tactics.unyielding) return null;
    if (run.sim.cooldown.get(act) > 0) return .cooling;
    if (act.flaskOf()) |k| {
        if (!run.sim.inventory.gear.holds(k)) return .unworn;
        if (!flasks.get(k).full()) return .empty;
    }
    if (act.supplyOf()) |k| if (run.sim.inventory.stacks.get(k) == 0) return .none_left;
    if (mana < needs(run, act)) return .mana;
    return null;
}

/// A stance's first upkeep falls due on the turn it is raised.
fn needs(run: *const game.Game, act: skillbar.Act) i32 {
    const upkeep: i32 = if (act == .unyielding) rules.Unyielding.DRAIN else 0;
    return run.sim.growth.cost(act) + upkeep;
}

fn ready(run: *game.Game, act: skillbar.Act) bool {
    if (!run.pic.quiet()) return false;
    switch (blocked(run, act, &run.sim.flasks, run.sim.mana, heroPinned(run)) orelse return true) {
        .cooling => {
            const left = run.sim.cooldown.get(act);
            run.sim.log.say("{s} is ready in {d} turn{s}.", .{ act.name(), left, plural(left) });
        },
        .mana => run.sim.log.say("{s} needs {d} mana.", .{ act.name(), needs(run, act) }),
        .unworn => run.sim.log.say("{s} is not equipped.", .{act.name()}),
        .empty => run.sim.log.say("{s} is empty.", .{act.name()}),
        .none_left => run.sim.log.say("{s}: none carried.", .{act.name()}),
        .locked => run.sim.log.say("{s} is not learned.", .{act.name()}),
        .pinned => run.sim.log.say("{s} is pinned.", .{run.sim.name.text()}),
    }
    return false;
}

fn movesHero(act: skillbar.Act) bool {
    const r = act.reticle() orelse return false;
    return r == .leap or r == .rush;
}

/// The hero acts: what it held up ends, and the turn's report notes what it did.
fn acted(run: *game.Game, used: skillbar.Act) void {
    tactics.beforeAction(&run.sim);
    run.sim.chronicle.note(.{ .used = used });
}

fn spend(run: *game.Game, act: skillbar.Act) void {
    acted(run, act);
    run.sim.mana -= run.sim.growth.cost(act);
    run.sim.cooldown.set(act, run.sim.growth.cooldown(act));
    if (act.supplyOf()) |k| run.sim.inventory.stacks.getPtr(k).* -= 1;
}

const plural = mathx.plural;

pub fn aimable(run: *const game.Game, from: P, to: P) bool {
    const act = run.mode.aim.act();
    if (act.reticle() == .ground) return tactics.valid(run, from, to);
    if (act.reticle() == .bow and !run.sim.lv.inLos(to)) return false;
    return act.aimable(&run.sim.lv, from, to) and !tactics.strikesHidden(run, act, from, to);
}

fn leap(run: *game.Game, from: P, act: skillbar.Act, to: P) void {
    game.heroTo(run, to);
    run.pic.glide[run.sim.heroSlot().?] = glide.Glide.rest(run.sim.heroActor().?);
    run.pic.turnToward(run.sim.hero, to.x - from.x);
    if (act.teleports()) {
        run.pic.fx.shimmer(mathx.centre(from), look.WARD);
        run.pic.fx.shimmer(mathx.centre(to), look.WARD);
    } else run.pic.fx.juke(from, to);
    sayDone(run, act);
    if (run.sim.travel != null) run.pic.holdUntil(fx.JUKE_S);
    run.sim.unsaved = true;
    game.castSight(run, to);
    if (act.free()) return;
    run.pic.lead = 0;
    combat.endTurn(run);
}

fn drink(run: *game.Game, act: skillbar.Act, k: flask.Kind) void {
    const hero = run.sim.heroActor() orelse return;
    spend(run, act);
    run.sim.flasks.getPtr(k).drink(flask.recovers(k, hero.max, run.sim.heroPerks()));
    run.pic.flasks_shown.set(k, run.sim.flasks.get(k));
    run.pic.fx.shimmer(mathx.centre(hero.at), switch (k) {
        .life => look.LIFE,
        .mana => look.WARD,
    });
    run.sim.log.push(.recovery, "{s} drinks a {s} flask.", .{ run.sim.name.text(), menu.word(k) });
    run.pic.lead = 0;
    combat.endTurn(run);
}

fn useSupply(run: *game.Game, act: skillbar.Act, k: consumable.Kind) void {
    const hero = run.sim.heroActor() orelse return;
    spend(run, act);
    switch (k) {
        .bandage => hero.bleed = .{},
        .smelling_salts => consumable.SmellingSalts.steel(&hero.resilience),
        .frost_vial => unreachable,
    }
    sayDone(run, act);
    run.pic.fx.shimmer(mathx.centre(hero.at), look.TEXT);
    run.pic.settleHero(&run.sim, 0);
    run.pic.lead = 0;
    combat.endTurn(run);
}

pub fn recover(run: *game.Game) void {
    run.sim.mana_recovery += run.sim.manaRegen();
    run.sim.gainMana(@divTrunc(run.sim.mana_recovery, heroes.MANA_REGEN_TURNS));
    run.sim.mana_recovery = @mod(run.sim.mana_recovery, heroes.MANA_REGEN_TURNS);
    for (std.enums.values(flask.Kind)) |k| recoverFlask(run, k, run.pic.lead orelse 0);
}

fn recoverFlask(run: *game.Game, k: flask.Kind, wait: f32) void {
    const n = run.sim.flasks.getPtr(k).tick();
    switch (k) {
        .life => combat.heal(run, n, wait),
        .mana => run.sim.gainMana(n),
    }
}

pub const Use = struct { act: skillbar.Act, by: input.Button, set: skillbar.Set = .primary };

/// Since PoE2 0.2.0, pressing the modifier while a button is already held fires that button's secondary skill.
pub fn usedSkill(run: *game.Game) ?Use {
    const set = activeSet(run);
    for (skillbar.SLOTS) |b| {
        if (!run.st.hit(b)) continue;
        return skillOn(run, set, b) orelse continue;
    }
    const m = run.bar.modifier orelse return null;
    if (!run.st.hit(m)) return null;
    for (skillbar.SLOTS) |b| {
        if (b == m or !run.st.held(b)) continue;
        return skillOn(run, .secondary, b) orelse continue;
    }
    return null;
}

pub fn activeSet(run: *const game.Game) skillbar.Set {
    return if (run.mouse.secondary and run.bar.modifier != null) .secondary else run.bar.active(run.st.down);
}

fn skillOn(run: *const game.Game, set: skillbar.Set, b: input.Button) ?Use {
    const a = run.bar.at(.{ .set = set, .button = b }) orelse return null;
    return if (a == .secondary) null else .{ .act = a, .by = b, .set = set };
}

pub fn useSkill(run: *game.Game, selection: Use) void {
    if (!run.pic.quiet()) return;
    const reticle = selection.act.reticle() orelse return useUnaimed(run, selection.act);
    if (!ready(run, selection.act)) return;
    openTargeting(run, selection, reticle);
}

fn useUnaimed(run: *game.Game, act: skillbar.Act) void {
    switch (act) {
        .wait => {
            acted(run, .wait);
            combat.endTurn(run);
        },
        .secondary => unreachable,
        inline else => |action| {
            if (comptime action.reticle() != null) {
                unreachable;
            } else if (comptime action.flaskOf()) |kind| {
                if (ready(run, action)) drink(run, action, kind);
            } else if (comptime action.supplyOf()) |kind| {
                if (ready(run, action)) useSupply(run, action, kind);
            } else if (ready(run, action)) {
                castSpell(run, action);
            }
        },
    }
}

fn openTargeting(run: *game.Game, selection: Use, reticle: skillbar.Act.Reticle) void {
    switch (reticle) {
        .bow => openAim(run, selection.by, selection.act),
        .leap => openLeap(run, selection.by, selection.act),
        .swing => openSwing(run, selection.by, selection.act),
        .rush => openRush(run, selection.by, selection.act),
        .ground => if (selection.act.consumes()) openAim(run, selection.by, selection.act) else openLeap(run, selection.by, selection.act),
    }
    if (run.mode == .aim) run.mode.aim.set = selection.set;
}

fn castSpell(run: *game.Game, comptime act: skillbar.Act) void {
    const Skill = skillbar.Act.skill(act);
    const hero = run.sim.heroActor() orelse return;
    const ending_stance = act == .unyielding and hero.tactics.unyielding;
    if (ending_stance) {
        acted(run, act);
    } else spend(run, act);
    if (comptime act.surrounds()) {
        const s = game.presentation.Stroke{ .from = hero.at, .wait = game.CAST_S };
        run.pic.holdUntil(s.wait);
        const area = Skill.around(&run.sim.lv, hero.at);
        if (foesIn(run, area).n == 0) sayDone(run, act);
        combat.areaHit(run, act, hero.at, area, s, null, false);
        run.pic.lead = s.wait;
    } else if (comptime act.wards()) {
        sayDone(run, act);
        hero.ward.raise();
        run.pic.fx.shimmer(mathx.centre(hero.at), look.WARD);
        run.pic.settleHero(&run.sim, 0);
        run.pic.lead = 0;
    } else tactics.instant(run, act);
    combat.endTurn(run);
}

const Struck = actor.Ids(actor.MAX);

/// Snapshot targets before damage so newborn slime halves are not hit twice.
pub fn foesIn(run: *game.Game, area: glacial.Burst) Struck {
    var out = Struck{};
    for (run.sim.pool.slice(), 0..) |a, i| {
        if (a.alive and a.foe() and area.has(a.at)) out.push(actor.Pool.idOf(i));
    }
    return out;
}

fn openRush(run: *game.Game, by: input.Button, act: skillbar.Act) void {
    const hero = run.sim.heroActor() orelse return;
    if (preferredTarget(run, act, hero.at)) |at| return aimAt(run, by, act, hero.at, at);
    var near = grid.Nearest{ .from = hero.at };
    var empty = grid.Nearest{ .from = hero.at };
    var cells = grid.Cells.around(hero.at, act.reach());
    while (cells.next()) |p| {
        if (tactics.validAct(run, act, hero.at, p)) {
            if (run.sim.lv.who(p) != grid.NO_ONE) near.offer(p) else empty.offer(p);
        }
    }
    aimAt(run, by, act, hero.at, near.best orelse empty.best);
}

fn rush(run: *game.Game, from: P, act: skillbar.Act, mark: P) void {
    switch (act) {
        inline else => |action| {
            if (comptime action.reticle() == .rush) rushTo(run, from, action, mark) else unreachable;
        },
    }
    combat.endTurn(run);
}

fn rushTo(run: *game.Game, from: P, comptime action: skillbar.Act, mark: P) void {
    const Skill = skillbar.Act.skill(action);
    const direction = Skill.wayTo(from, mark).?;
    const occupied = run.sim.lv.who(mark) != grid.NO_ONE;
    const stop = if (occupied) Skill.stop(from, mark) else mark;
    game.heroTo(run, stop);
    const stroke = game.presentation.Stroke{ .from = stop, .wait = run.pic.glideToHeld(run.sim.heroSlot().?, stop, 0) };
    if (occupied) combat.knock(run, action, direction, stroke) else sayDone(run, action);
    run.pic.turnToward(run.sim.hero, direction.delta().x);
    run.pic.lead = stroke.wait;
}

/// Over the hero's own cell, so the reticle reaches the far side of a corridor.
pub fn nudgeAim(run: *game.Game, d: mathx.Dir) void {
    const hero = run.sim.heroActor() orelse return;
    if (run.mode.aim.act().attack() != null and run.mode.aim.act().reticle() != .bow) if (targetToward(run, hero.at, d)) |at| {
        run.mode.aim.mark = at;
        rememberTarget(run);
        run.pic.turnToward(run.sim.hero, at.x - hero.at.x);
        return;
    };
    var to = run.mode.aim.mark.add(d.delta());
    switch (run.mode.aim.act().reticle().?) {
        .leap, .rush, .ground => if (!juke.inReach(hero.at, to, run.mode.aim.act().reach()) or !grid.Level.inside(to)) return,
        .bow => {
            if (to.eq(hero.at)) to = to.add(d.delta());
            if (!aimable(run, hero.at, to)) return;
        },
        .swing => to = hero.at.add(d.delta()),
    }
    run.mode.aim.mark = to;
    rememberTarget(run);
    run.pic.turnToward(run.sim.hero, to.x - hero.at.x);
}

fn targetToward(run: *game.Game, from: P, d: mathx.Dir) ?P {
    const way = d.delta();
    var best: ?P = null;
    var best_score: i32 = std.math.maxInt(i32);
    for (0..run.sim.pool.n) |i| {
        const at = targetAt(run, run.mode.aim.act(), from, actor.Pool.idOf(i)) orelse continue;
        const delta = at.sub(run.mode.aim.mark);
        const along = delta.x * way.x + delta.y * way.y;
        if (along <= 0) continue;
        const across: i32 = @intCast(@abs(delta.x * way.y - delta.y * way.x));
        const score = along + 2 * across;
        if (score >= best_score) continue;
        best_score = score;
        best = at;
    }
    return best;
}

pub fn confirmAim(run: *game.Game) void {
    const hero = run.sim.heroActor() orelse return;
    if (run.mode != .aim) return;
    const act = run.mode.aim.act();
    if (!ready(run, act)) return;
    const reticle = act.reticle().?;
    if (!aimable(run, hero.at, run.mode.aim.mark)) {
        switch (reticle) {
            .bow => run.sim.log.say("Can't shoot there.", .{}),
            .leap => run.sim.log.say("{s} needs a visible, empty landing within {d} tiles.", .{ act.name(), act.reach() }),
            .swing => run.sim.log.say("Nothing to strike there.", .{}),
            .rush => run.sim.log.say("{s} needs a clear straight line {d} to {d} tiles away.", .{ act.name(), act.nearest(), act.reach() }),
            .ground => run.sim.log.say("Choose a legal visible target for {s}.", .{act.name()}),
        }
        return;
    }
    if (run.mode.aim.chooseStart()) return;
    rememberTarget(run);
    const aim = run.mode.aim;
    closeAim(run);
    spend(run, act);
    const from = hero.at;
    switch (reticle) {
        .bow => loose(run, from, act, aim.mark),
        .leap => leap(run, from, act, aim.mark),
        .swing => combat.swing(run, from, act, aim.mark),
        .rush => rush(run, from, act, aim.mark),
        .ground => tactics.cast(run, aim, from),
    }
}

fn loose(run: *game.Game, from: P, act: skillbar.Act, to: P) void {
    const pierced = if (act.pierces()) bow.pierce(&run.sim.lv, from, to) else null;
    const flight = if (pierced) |p| p.flight else bow.fly(&run.sim.lv, from, to);
    const stroke = run.pic.recordProjectile(from, act, flight);
    if (flight.struck) |hit| {
        switch (act) {
            inline else => |action| {
                if (comptime action.pierces()) {
                    combat.pierceHit(run, action, pierced.?, stroke);
                } else if (comptime action.reticle() == .bow) {
                    resolveProjectileHit(run, action, hit, flight, stroke);
                } else unreachable;
            },
        }
    } else {
        run.sim.log.say("{s}'s {s} finds nothing.", .{ run.sim.name.text(), act.bolt() orelse "arrow" });
        run.sim.chronicle.note(.{ .missed = .{} });
    }
    if (act.isArrow()) if (run.sim.heroActor()) |hero| {
        hero.tactics.steady = 0;
    };
    combat.endTurn(run);
}

fn resolveProjectileHit(run: *game.Game, comptime action: skillbar.Act, hit: bow.Hit, flight: bow.Flight, stroke: game.presentation.Stroke) void {
    if (comptime action.bursts()) {
        combat.burstHit(run, action, hit, flight.impact().?, stroke);
        return;
    }
    switch (hit) {
        .body => |id| hitProjectileActor(run, action, id, stroke),
        .barrel => |at| combat.smash(run, at, combat.barrelVerb(action), stroke),
    }
    if (comptime action.element() == .fire) combat.boil(run, flight.impact().?, 0, stroke.wait);
}

fn hitProjectileActor(run: *game.Game, comptime action: skillbar.Act, id: u16, stroke: game.presentation.Stroke) void {
    if (comptime action.chains()) {
        combat.chainHit(run, action, id, stroke);
    } else if (comptime action.afflicts()) {
        combat.arrowHit(run, id, attacks.heroArrow(&run.sim, action, true), action, stroke);
    } else {
        comptime std.debug.assert(action.element() == null);
        combat.wound(run, id, attacks.heroSkill(&run.sim, action), combat.SHOOT, stroke);
    }
}

fn sayDone(run: *game.Game, act: skillbar.Act) void {
    const done = act.done() orelse return;
    run.sim.log.say("{s} {s}.", .{ run.sim.name.text(), done });
}
