const attacks = @import("attacks.zig");
const std = @import("std");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const heroes = @import("../play/hero.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const areas = @import("../play/area.zig");
const juke = @import("../play/juke.zig");
const pinning = @import("../play/pinning.zig");
const flask = @import("../play/flask.zig");
const consumable = @import("../play/consumable.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const fx = @import("../gfx/fx.zig");
const combat = @import("combat.zig");
const glide = @import("glide.zig");
const tactics_exec = @import("tactics_exec.zig");
const tactics = @import("../play/tactics.zig");
const game = @import("../game.zig");
const menu = @import("../ui/menu.zig");
const P = mathx.P;

pub fn openAim(run: *game.Game, by: ?input.Button, act: skillbar.Act) void {
    const hero = run.sim.heroActor() orelse return;
    const suggested = preferredTarget(run, act, hero.at) orelse (if (act.consumes()) null else bow.pick(&run.sim.lv, &run.sim.pool, hero.at, act.reach()));
    if (suggested) |at| return aimAt(run, by, act, hero.at, at);
    if (act.reticle() == .bow) {
        const slot = run.sim.heroSlot().?;
        const dx: i32 = if (run.pic.facing[slot] == .left) -1 else 1;
        const ahead = hero.at.add(.{ .x = dx, .y = 0 });
        return aimAt(run, by, act, hero.at, if (grid.Level.inside(ahead)) ahead else hero.at.add(.{ .x = -dx, .y = 0 }));
    }
    aimAt(run, by, act, hero.at, null);
}

fn targetAt(run: *game.Game, act: skillbar.Act, from: P, id: u16) ?P {
    const a = run.sim.pool.get(id) orelse return null;
    if (!a.seenFoe(&run.sim.lv) or !tactics_exec.validAct(run, act, from, a.at)) return null;
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

pub fn openLeap(run: *game.Game, by: ?input.Button, act: skillbar.Act) void {
    const hero = run.sim.heroActor() orelse return;
    aiming(run, by, act);
    const ahead = hero.at.add(run.stride.delta());
    run.mode.aim.mark = if (act == .raise_skeleton and grid.Level.inside(ahead) and tactics_exec.validAct(run, act, hero.at, ahead)) ahead else hero.at;
}

fn openSwing(run: *game.Game, by: ?input.Button, act: skillbar.Act) void {
    const hero = run.sim.heroActor() orelse return;
    if (preferredTarget(run, act, hero.at)) |at| return aimAt(run, by, act, hero.at, at);
    var mark: ?P = null;
    for (mathx.ALL_DIRS) |d| {
        const p = hero.at.add(d.delta());
        if (!tactics_exec.validAct(run, act, hero.at, p)) continue;
        const foe = if (run.sim.pool.get(run.sim.lv.who(p))) |a| a.seenFoe(&run.sim.lv) else false;
        if (foe or (mark == null and !run.sim.allyAt(p))) mark = p;
        if (foe) break;
    }
    aimAt(run, by, act, hero.at, mark);
}

fn aimAt(run: *game.Game, by: ?input.Button, act: skillbar.Act, from: P, mark: ?P) void {
    const to = mark orelse {
        run.sim.log.say("Nothing in reach.", .{});
        return;
    };
    aiming(run, by, act);
    markAim(run, from, to);
}

pub fn markAim(run: *game.Game, from: P, at: P) void {
    run.mode.aim.mark = at;
    rememberTarget(run);
    run.pic.turnHero(&run.sim, at.x - from.x);
}

pub fn aiming(run: *game.Game, by: ?input.Button, act: skillbar.Act) void {
    run.mode = .{ .aim = game.Aim.of(by, act, run.sim.heroAt().?) };
}

pub fn closeAim(run: *game.Game) void {
    if (run.mode == .aim) run.mode = .play;
}

const Blocked = enum { cooling, mana, unworn, empty, none_left, locked, pinned };

pub fn heroPinned(run: *const game.Game) bool {
    return (run.sim.heroBody() orelse return false).pin.holding();
}

pub fn blocked(run: *const game.Game, act: skillbar.Act, flasks: *const game.simulation.Flasks, mana: i32, pinned: bool) ?Blocked {
    if (!run.sim.growth.unlocked(act)) return .locked;
    if (act.moves() and pinned) return .pinned;
    if (endingStance(&run.sim, act)) return null;
    if (run.sim.cooldown.get(act) > 0) return .cooling;
    if (act.flaskOf()) |k| {
        if (!run.sim.inventory.gear.holds(k)) return .unworn;
        if (!flasks.get(k).full()) return .empty;
    }
    if (act.supplyOf()) |k| if (run.sim.inventory.stacks.get(k) == 0) return .none_left;
    if (mana < needs(run, act)) return .mana;
    return null;
}

pub fn endingStance(sim: *const game.simulation.Simulation, act: skillbar.Act) bool {
    const h = sim.heroBody() orelse return false;
    return act == .unyielding and h.tactics.unyielding;
}

pub fn blockedNow(run: *const game.Game, act: skillbar.Act) ?Blocked {
    return blocked(run, act, &run.sim.flasks, run.sim.mana, heroPinned(run));
}

fn needs(run: *const game.Game, act: skillbar.Act) i32 {
    if (run.sim.playground) return 0;
    const upkeep: i32 = if (act == .unyielding) tactics.Unyielding.DRAIN else 0;
    return run.sim.growth.cost(act) + upkeep;
}

fn ready(run: *game.Game, act: skillbar.Act) bool {
    if (!run.pic.quiet()) return false;
    switch (blockedNow(run, act) orelse return true) {
        .cooling => {
            const left = run.sim.cooldown.get(act);
            run.sim.log.say("{s} is ready in {d} turn{s}.", .{ act.name(), left, plural(left) });
        },
        .mana => run.sim.log.say("{s} needs {d} mana.", .{ act.name(), needs(run, act) }),
        .unworn => run.sim.log.say("{s} is not equipped.", .{act.name()}),
        .empty => run.sim.log.say("{s} is empty.", .{act.name()}),
        .none_left => run.sim.log.say("{s}: none carried.", .{act.name()}),
        .locked => run.sim.log.say("{s} is not learned.", .{act.name()}),
        .pinned => run.sim.log.say("{s} " ++ pinning.TAKES ++ ".", .{run.sim.name.text()}),
    }
    return false;
}

fn acted(run: *game.Game, used: skillbar.Act) void {
    tactics_exec.beforeAction(&run.sim);
    run.sim.chronicle.note(.{ .used = used });
}

fn spend(run: *game.Game, act: skillbar.Act) void {
    acted(run, act);
    if (!run.sim.playground) {
        run.sim.mana -= run.sim.growth.cost(act);
        run.sim.cooldown.set(act, run.sim.growth.cooldown(act, run.sim.inventory.gear.quicker()));
    }
    if (act.supplyOf()) |k| run.sim.inventory.stacks.getPtr(k).* -= 1;
}

const plural = mathx.plural;

pub fn aimable(run: *const game.Game, from: P, to: P) bool {
    const act = run.mode.aim.act();
    if (act.reticle() == .ground) return tactics_exec.valid(run, from, to);
    if (act.reticle() == .bow and !run.sim.lv.inLos(to)) return false;
    return act.aimableIn(&run.sim.lv, from, to, run.sim.reachOf(act)) and !tactics_exec.strikesHidden(run, act, from, to);
}

fn leap(run: *game.Game, from: P, act: skillbar.Act, to: P) void {
    game.heroTo(run, to);
    run.pic.glide[run.sim.heroSlot().?] = glide.Glide.rest(run.sim.heroActor().?);
    run.pic.turnHero(&run.sim, to.x - from.x);
    if (act.teleports()) {
        run.pic.fx.shimmer(mathx.centre(from), look.WARD);
        run.pic.fx.shimmer(mathx.centre(to), look.WARD);
    } else run.pic.fx.juke(from, to);
    sayDone(run, act);
    if (run.sim.travel != null) run.pic.holdUntil(fx.JUKE_S);
    run.sim.unsaved = true;
    game.castSight(run, to);
    if (act.free()) return;
    endAtOnce(run);
}

fn endAtOnce(run: *game.Game) void {
    run.pic.lead = 0;
    combat.endTurn(run);
}

fn drink(run: *game.Game, act: skillbar.Act, k: flask.Kind) void {
    const hero = run.sim.heroActor() orelse return;
    spend(run, act);
    run.sim.flasks.getPtr(k).drink(flask.recovers(k, hero.max, run.sim.heroDraughts()));
    run.pic.flasks_shown.set(k, run.sim.flasks.get(k));
    run.pic.fx.shimmer(mathx.centre(hero.at), switch (k) {
        .life => look.LIFE,
        .mana => look.WARD,
    });
    run.sim.log.push(.recovery, "{s} drinks a {s} flask.", .{ run.sim.name.text(), menu.word(k) });
    endAtOnce(run);
}

fn useSupply(run: *game.Game, comptime act: skillbar.Act, comptime k: consumable.Kind) void {
    const hero = run.sim.heroActor() orelse return;
    spend(run, act);
    switch (k) {
        .bandage => hero.bleed = .{},
        .smelling_salts => consumable.SmellingSalts.steel(&hero.resilience),
        .frost_vial => @compileError(@tagName(act) ++ " is thrown, not used where it is"),
    }
    sayDone(run, act);
    run.pic.fx.shimmer(mathx.centre(hero.at), look.TEXT);
    run.pic.settleHero(&run.sim, 0);
    endAtOnce(run);
}

pub fn recover(run: *game.Game) void {
    run.sim.gainMana(accrue(&run.sim.mana_recovery, run.sim.manaRegen(), heroes.MANA_REGEN_TURNS));
    combat.heal(run, accrue(&run.sim.life_recovery, run.sim.lifeRegen(), heroes.LIFE_REGEN_TURNS), run.pic.lead orelse 0);
    if (run.sim.playground) run.sim.gainMana(run.sim.manaMax());
    for (std.enums.values(flask.Kind)) |k| recoverFlask(run, k, run.pic.lead orelse 0);
}

fn accrue(banked: *i32, regen: i32, turns: i32) i32 {
    banked.* +|= regen;
    defer banked.* = @mod(banked.*, turns);
    return @divTrunc(banked.*, turns);
}

fn recoverFlask(run: *game.Game, k: flask.Kind, wait: f32) void {
    const n = run.sim.flasks.getPtr(k).tick();
    switch (k) {
        .life => combat.heal(run, n, wait),
        .mana => run.sim.gainMana(n),
    }
}

pub const Use = struct { act: skillbar.Act, by: ?input.Button, set: skillbar.Set = .primary };

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
            combat.passTurn(run);
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
    if (endingStance(&run.sim, act)) {
        acted(run, act);
    } else spend(run, act);
    if (comptime act.surrounds()) {
        const s = game.presentation.Stroke{ .from = hero.at, .wait = game.CAST_S };
        run.pic.leadUntil(s.wait);
        const area = Skill.around(&run.sim.lv, hero.at, run.sim.wider());
        if (foesIn(run, area).n == 0) sayDone(run, act);
        combat.areaHit(run, act, hero.at, area, s, null, false);
    } else if (comptime act.wards()) {
        sayDone(run, act);
        hero.ward.raise();
        run.pic.fx.shimmer(mathx.centre(hero.at), look.WARD);
        run.pic.settleHero(&run.sim, 0);
        run.pic.lead = 0;
    } else tactics_exec.instant(run, act);
    combat.endTurn(run);
}

const Struck = grid.Bounded(u16, actor.MAX);

/// Snapshot targets before damage so newborn slime halves are not hit twice.
pub fn foesIn(run: *game.Game, area: areas.Burst) Struck {
    var out = Struck{};
    for (run.sim.pool.slice(), 0..) |a, i| {
        if (a.livingFoe() and area.has(a.at)) out.push(actor.Pool.idOf(i));
    }
    return out;
}

fn openRush(run: *game.Game, by: ?input.Button, act: skillbar.Act) void {
    const hero = run.sim.heroActor() orelse return;
    if (preferredTarget(run, act, hero.at)) |at| return aimAt(run, by, act, hero.at, at);
    var near = grid.Nearest{ .from = hero.at };
    var empty = grid.Nearest{ .from = hero.at };
    var cells = grid.Cells.around(hero.at, run.sim.reachOf(act));
    while (cells.next()) |p| {
        if (tactics_exec.validAct(run, act, hero.at, p)) {
            const who = run.sim.lv.who(p);
            if (who == grid.NO_ONE) {
                empty.offer(p);
            } else if (run.sim.pool.getConst(who)) |a| if (a.foe()) near.offer(p);
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
    if (!stop.eq(from)) game.heroTo(run, stop);
    const stroke = game.presentation.Stroke{ .from = stop, .wait = run.pic.glideToHeld(.fromIndex(run.sim.heroSlot().?), stop, 0) };
    if (occupied) combat.knock(run, action, direction, stroke) else sayDone(run, action);
    run.pic.turnHero(&run.sim, direction.delta().x);
    run.pic.lead = stroke.wait;
}

/// Over the hero's own cell, so the reticle reaches the far side of a corridor.
pub fn nudgeAim(run: *game.Game, d: mathx.Dir) void {
    const hero = run.sim.heroActor() orelse return;
    const act = run.mode.aim.act();
    if (act.attack() != null and act.reticle() != .leap and targetAt(run, act, hero.at, run.sim.lv.who(run.mode.aim.mark)) != null) {
        if (targetToward(run, hero.at, d)) |at| return markAim(run, hero.at, at);
    }
    var to = run.mode.aim.mark.add(d.delta());
    switch (act.reticle().?) {
        .leap, .rush, .ground => if (!juke.inReach(hero.at, to, run.sim.reachOf(act)) or !grid.Level.inside(to)) return,
        .bow => {
            if (to.eq(hero.at)) to = to.add(d.delta());
            if (!aimable(run, hero.at, to)) return;
        },
        .swing => to = hero.at.add(d.delta()),
    }
    markAim(run, hero.at, to);
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
        if (across > along) continue;
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
            .leap => run.sim.log.say("{s} needs a visible, empty landing within {d} tiles.", .{ act.name(), run.sim.reachOf(act) }),
            .swing => run.sim.log.say("Nothing to strike there.", .{}),
            .rush => run.sim.log.say("{s} needs a clear straight line {d} to {d} tiles away.", .{ act.name(), act.nearest(), run.sim.reachOf(act) }),
            .ground => run.sim.log.say("Choose a legal visible target for {s}.", .{act.name()}),
        }
        return;
    }
    if (reticle == .bow and shownFlight(run, hero.at, act, run.mode.aim.mark).struck == null and !run.mode.aim.askedHere()) {
        run.mode.aim.asked = run.mode.aim.mark;
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
        .ground => tactics_exec.cast(run, aim, from),
    }
}

/// The flight the reticle shows toward `mark`, passing over bodies the hero cannot see.
pub fn shownFlight(run: *const game.Game, from: P, act: skillbar.Act, mark: P) bow.Flight {
    if (act.pierces()) return bow.piercePreviewAmong(&run.sim.lv, &run.sim.pool, from, mark);
    const extra = skewers(&run.sim, act);
    if (extra > 0) return bow.skewerPreviewAmong(&run.sim.lv, &run.sim.pool, from, mark, act.reach(), extra);
    return bow.previewAmong(&run.sim.lv, &run.sim.pool, from, mark);
}

/// The extra foes worn pierce lets a single-target projectile pass through.
fn skewers(sim: *const game.simulation.Simulation, act: skillbar.Act) usize {
    if (act.reticle() != .bow or act.pierces() or act.bursts() or act.chains()) return 0;
    return sim.inventory.gear.pierce();
}

pub const UNSEEN_ASK = "There's no visible target, {s} anyway?";

fn loose(run: *game.Game, from: P, act: skillbar.Act, to: P) void {
    const extra = skewers(&run.sim, act);
    const pierced = if (act.pierces()) bow.pierce(&run.sim.lv, from, to) else if (extra > 0) bow.skewer(&run.sim.lv, from, to, act.reach(), extra) else null;
    const flight = if (pierced) |p| p.flight else bow.fly(&run.sim.lv, from, to);
    const stroke = run.pic.recordProjectile(from, act, flight);
    if (flight.struck) |hit| {
        switch (act) {
            inline else => |action| {
                if (comptime action.pierces()) {
                    combat.pierceHit(run, action, pierced.?, stroke);
                } else if (comptime action.reticle() == .bow) {
                    if (pierced != null and pierced.?.n > 0) skewerHits(run, action, pierced.?, stroke) else resolveProjectileHit(run, action, hit, flight, stroke);
                } else unreachable;
            },
        }
    } else {
        run.sim.log.say("{s}'s {s} finds nothing.", .{ run.sim.name.text(), act.bolt() orelse "arrow" });
        run.sim.chronicle.note(.{ .missed = .{} });
        comeDown(run, act, flight, stroke);
    }
    if (tactics.SteadyAim.readies(act)) if (run.sim.heroActor()) |hero| {
        hero.tactics.steady = 0;
    };
    combat.endTurn(run);
}

fn comeDown(run: *game.Game, act: skillbar.Act, flight: bow.Flight, stroke: game.presentation.Stroke) void {
    const at = flight.grounded(&run.sim.lv) orelse return;
    switch (act) {
        inline else => |action| {
            combat.boilUnder(run, action, at, stroke.wait);
            if (comptime action.element() == .cold and action.bursts()) combat.coldLands(run, &skillbar.Act.elemental(action).burst(&run.sim.lv, stroke.from, at, run.sim.wider()), stroke.wait);
            if (comptime action.element() == .lightning) combat.conduct(run, at, stroke);
        },
    }
}

fn resolveProjectileHit(run: *game.Game, comptime action: skillbar.Act, hit: bow.Hit, flight: bow.Flight, stroke: game.presentation.Stroke) void {
    if (comptime action.bursts()) {
        combat.burstHit(run, action, hit, flight.impact().?, stroke);
        return;
    }
    switch (hit) {
        .body => |id| hitProjectileActor(run, action, id, stroke),
        .barrel, .plant => |at| combat.smash(run, at, combat.barrelVerb(action), stroke),
    }
    combat.boilUnder(run, action, flight.impact().?, stroke.wait);
}

/// Each body struck as the projectile reaches its cell, then whatever stopped it.
fn skewerHits(run: *game.Game, comptime action: skillbar.Act, pierced: bow.Pierced, stroke: game.presentation.Stroke) void {
    for (pierced.body[0..pierced.n], pierced.step[0..pierced.n]) |id, step| {
        hitProjectileActor(run, action, id, stroke.along(step, pierced.flight.len));
    }
    switch (pierced.flight.struck.?) {
        .barrel, .plant => |at| combat.smash(run, at, combat.barrelVerb(action), stroke),
        .body => {},
    }
    combat.boilUnder(run, action, pierced.flight.impact().?, stroke.wait);
}

fn hitProjectileActor(run: *game.Game, comptime action: skillbar.Act, id: u16, stroke: game.presentation.Stroke) void {
    if (comptime action.chains()) {
        combat.chainHit(run, action, id, stroke);
    } else if (comptime action.afflicts()) {
        combat.skillHit(run, id, attacks.heroBlow(&run.sim, action), action, stroke);
    } else {
        comptime std.debug.assert(action.element() == null);
        combat.wound(run, id, attacks.heroSkill(&run.sim, action), combat.SHOOT, stroke);
    }
}

fn sayDone(run: *game.Game, act: skillbar.Act) void {
    const done = act.done() orelse return;
    run.sim.log.say("{s} {s}.", .{ run.sim.name.text(), done });
}
