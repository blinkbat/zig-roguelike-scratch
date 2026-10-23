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
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const fx = @import("../gfx/fx.zig");
const combat = @import("combat.zig");
const glide = @import("glide.zig");
const game = @import("../game.zig");
const P = mathx.P;

pub fn openAim(g: *game.Game, by: input.Button, act: skillbar.Act) void {
    const h = g.sim.heroActor() orelse return;
    aimAt(g, by, act, h.at, bow.pick(&g.sim.lv, &g.sim.pool, h.at));
}

pub fn openLeap(g: *game.Game, by: input.Button, act: skillbar.Act) void {
    const h = g.sim.heroActor() orelse return;
    g.mark = h.at;
    aiming(g, by, act);
}

fn openSwing(g: *game.Game, by: input.Button, act: skillbar.Act) void {
    const h = g.sim.heroActor() orelse return;
    var mark: ?P = null;
    for (mathx.ALL_DIRS) |d| {
        const p = h.at.add(d.delta());
        if (!act.aimable(&g.sim.lv, h.at, p)) continue;
        const foe = if (g.sim.pool.get(g.sim.lv.who(p))) |a| a.foe() else false;
        if (foe or mark == null) mark = p;
        if (foe) break;
    }
    aimAt(g, by, act, h.at, mark);
}

fn aimAt(g: *game.Game, by: input.Button, act: skillbar.Act, from: P, mark: ?P) void {
    g.mark = mark orelse {
        g.sim.log.say("Nothing in reach.", .{});
        return;
    };
    g.pic.turnToward(g.sim.hero, g.mark.x - from.x);
    aiming(g, by, act);
}

pub fn aiming(g: *game.Game, by: input.Button, act: skillbar.Act) void {
    g.aim_by = by;
    g.aim_act = act;
    g.mode = .aim;
}

const Blocked = enum { cooling, mana, empty, locked };

pub fn blocked(g: *const game.Game, act: skillbar.Act, flasks: *const game.simulation.Flasks, mana: i32) ?Blocked {
    if (!g.sim.growth.unlocked(act)) return .locked;
    if (g.sim.cooldown.get(act) > 0) return .cooling;
    if (act.flaskOf()) |k| {
        if (!flasks.get(k).full()) return .empty;
    }
    if (mana < g.sim.growth.cost(act)) return .mana;
    return null;
}

fn ready(g: *game.Game, act: skillbar.Act) bool {
    if (!g.pic.quiet()) return false;
    switch (blocked(g, act, &g.sim.flasks, g.sim.mana) orelse return true) {
        .cooling => {
            const left = g.sim.cooldown.get(act);
            g.sim.log.say("{s} is ready in {d} turn{s}.", .{ act.name(), left, plural(left) });
        },
        .mana => g.sim.log.say("{s} needs {d} mana.", .{ act.name(), g.sim.growth.cost(act) }),
        .empty => g.sim.log.say("{s} is empty.", .{act.name()}),
        .locked => g.sim.log.say("{s} is not learned.", .{act.name()}),
    }
    return false;
}

fn spend(g: *game.Game, act: skillbar.Act) void {
    g.sim.chronicle.note(.{ .used = act });
    g.sim.mana -= g.sim.growth.cost(act);
    g.sim.cooldown.set(act, g.sim.growth.cooldown(act));
}

const plural = mathx.plural;

pub fn aimable(g: *const game.Game, from: P, to: P) bool {
    return g.aim_act.aimable(&g.sim.lv, from, to);
}

fn leap(g: *game.Game, from: P, act: skillbar.Act) void {
    const to = g.mark;
    game.heroTo(g, to);
    g.pic.glide[g.sim.heroSlot().?] = glide.Glide.rest(g.sim.heroActor().?);
    g.pic.turnToward(g.sim.hero, to.x - from.x);
    if (act.teleports()) {
        g.pic.fx.shimmer(mathx.centre(from), look.WARD);
        g.pic.fx.shimmer(mathx.centre(to), look.WARD);
    } else g.pic.fx.juke(from, to);
    sayDone(g, act);
    if (g.sim.travel != null) g.pic.holdUntil(fx.JUKE_S);
    g.sim.unsaved = true;
    game.castSight(g, to);
    if (act.free()) return;
    g.pic.lead = 0;
    combat.endTurn(g);
}

fn drink(g: *game.Game, act: skillbar.Act, k: flask.Kind) void {
    const h = g.sim.heroActor() orelse return;
    spend(g, act);
    g.sim.flasks.getPtr(k).drink(flask.recovers(k, h.max, g.sim.heroPerks()));
    recoverFlask(g, k, 0);
    g.pic.flasks_shown.set(k, g.sim.flasks.get(k));
    g.pic.fx.shimmer(mathx.centre(h.at), switch (k) {
        .life => look.LIFE,
        .mana => look.WARD,
    });
    g.sim.log.push(.recovery, "{s} drinks a {s} flask.", .{ g.sim.name.text(), @tagName(k) });
    g.sim.unsaved = true;
}

pub fn recover(g: *game.Game) void {
    g.sim.mana_recovery += g.sim.manaRegen();
    g.sim.gainMana(@divTrunc(g.sim.mana_recovery, heroes.MANA_REGEN_TURNS));
    g.sim.mana_recovery = @mod(g.sim.mana_recovery, heroes.MANA_REGEN_TURNS);
    for (std.enums.values(flask.Kind)) |k| recoverFlask(g, k, g.pic.lead orelse 0);
}

fn recoverFlask(g: *game.Game, k: flask.Kind, wait: f32) void {
    const n = g.sim.flasks.getPtr(k).tick();
    switch (k) {
        .life => combat.heal(g, n, wait),
        .mana => g.sim.gainMana(n),
    }
}

pub const Use = struct { act: skillbar.Act, by: input.Button, set: skillbar.Set = .primary };

/// Since PoE2 0.2.0, pressing the modifier while a button is already held fires that button's secondary skill.
pub fn usedSkill(g: *game.Game) ?Use {
    const set = activeSet(g);
    for (skillbar.SLOTS) |b| {
        if (!g.st.hit(b)) continue;
        return skillOn(g, set, b) orelse continue;
    }
    const m = g.bar.modifier orelse return null;
    if (!g.st.hit(m)) return null;
    for (skillbar.SLOTS) |b| {
        if (b == m or !g.st.held(b)) continue;
        return skillOn(g, .secondary, b) orelse continue;
    }
    return null;
}

pub fn activeSet(g: *const game.Game) skillbar.Set {
    return if (g.mouse.secondary and g.bar.modifier != null) .secondary else g.bar.active(g.st.down);
}

fn skillOn(g: *const game.Game, set: skillbar.Set, b: input.Button) ?Use {
    const a = g.bar.at(.{ .set = set, .button = b }) orelse return null;
    return if (a == .secondary) null else .{ .act = a, .by = b, .set = set };
}

pub fn useSkill(g: *game.Game, u: Use) void {
    if (!g.pic.quiet()) return;
    const r = u.act.reticle() orelse return switch (u.act) {
        .wait => {
            g.sim.chronicle.note(.{ .used = .wait });
            combat.endTurn(g);
        },
        .secondary => unreachable,
        inline else => |a| if (comptime a.reticle() != null)
            unreachable
        else if (comptime a.flaskOf()) |k| {
            if (ready(g, a)) drink(g, a, k);
        } else if (ready(g, a)) spell(g, a),
    };
    if (!ready(g, u.act)) return;
    g.aim_set = u.set;
    switch (r) {
        .bow => openAim(g, u.by, u.act),
        .leap => openLeap(g, u.by, u.act),
        .swing => openSwing(g, u.by, u.act),
        .rush => openRush(g, u.by, u.act),
    }
}

fn spell(g: *game.Game, comptime act: skillbar.Act) void {
    const M = skillbar.Act.skill(act);
    const h = g.sim.heroActor() orelse return;
    spend(g, act);
    if (comptime act.surrounds()) {
        const s = game.presentation.Stroke{ .from = h.at, .wait = game.CAST_S };
        g.pic.holdUntil(s.wait);
        const area = M.around(&g.sim.lv, h.at);
        if (foesIn(g, area).n == 0) sayDone(g, act);
        combat.areaHit(g, act, h.at, area, s, null, false);
        g.pic.lead = s.wait;
    } else if (comptime act.wards()) {
        sayDone(g, act);
        h.ward.raise();
        g.pic.fx.shimmer(mathx.centre(h.at), look.WARD);
        g.pic.settleHero(&g.sim, 0);
        g.pic.lead = 0;
    } else @compileError(@tagName(act) ++ " has no reticle and no use");
    combat.endTurn(g);
}

const Struck = actor.Ids(actor.MAX);

/// Snapshot targets before damage so newborn slime halves are not hit twice.
pub fn foesIn(g: *game.Game, area: glacial.Burst) Struck {
    var out = Struck{};
    for (g.sim.pool.slice(), 0..) |a, i| {
        if (a.alive and a.foe() and area.has(a.at)) out.push(actor.Pool.idOf(i));
    }
    return out;
}

fn openRush(g: *game.Game, by: input.Button, act: skillbar.Act) void {
    const h = g.sim.heroActor() orelse return;
    var near = bow.Nearest{ .from = h.at };
    var empty = bow.Nearest{ .from = h.at };
    var cells = grid.Cells.around(h.at, act.reach());
    while (cells.next()) |p| {
        if (act.aimable(&g.sim.lv, h.at, p)) {
            if (g.sim.lv.who(p) != grid.NO_ONE) near.offer(p) else empty.offer(p);
        }
    }
    aimAt(g, by, act, h.at, near.best orelse empty.best);
}

fn rush(g: *game.Game, from: P, act: skillbar.Act) void {
    switch (act) {
        inline else => |a| if (comptime a.reticle() != .rush) unreachable else {
            const M = skillbar.Act.skill(a);
            const d = M.wayTo(from, g.mark).?;
            const occupied = g.sim.lv.who(g.mark) != grid.NO_ONE;
            const stop = if (occupied) M.stop(from, g.mark) else g.mark;
            game.heroTo(g, stop);
            const s = game.presentation.Stroke{ .from = stop, .wait = g.pic.glideToHeld(g.sim.heroSlot().?, stop, 0) };
            if (occupied) combat.knock(g, a, d, s) else sayDone(g, a);
            g.pic.turnToward(g.sim.hero, d.delta().x);
            g.pic.lead = s.wait;
        },
    }
    combat.endTurn(g);
}

/// Over the hero's own cell, so the reticle reaches the far side of a corridor.
pub fn nudgeAim(g: *game.Game, d: mathx.Dir) void {
    const h = g.sim.heroActor() orelse return;
    var to = g.mark.add(d.delta());
    switch (g.aim_act.reticle().?) {
        .leap, .rush => if (!juke.inReach(h.at, to, g.aim_act.reach()) or !grid.Level.inside(to)) return,
        .bow => {
            if (to.eq(h.at)) to = to.add(d.delta());
            if (!bow.aimable(&g.sim.lv, h.at, to)) return;
        },
        .swing => to = h.at.add(d.delta()),
    }
    g.mark = to;
    g.pic.turnToward(g.sim.hero, to.x - h.at.x);
}

pub fn confirmAim(g: *game.Game) void {
    const h = g.sim.heroActor() orelse return;
    const act = g.aim_act;
    if (!ready(g, act)) return;
    const reticle = act.reticle().?;
    if (!aimable(g, h.at, g.mark)) {
        switch (reticle) {
            .bow => g.sim.log.say("Can't shoot there.", .{}),
            .leap => g.sim.log.say("{s} needs a visible, empty landing within {d} tiles.", .{ act.name(), act.reach() }),
            .swing => g.sim.log.say("Nothing to strike there.", .{}),
            .rush => g.sim.log.say("{s} needs a clear straight line {d} to {d} tiles away.", .{ act.name(), act.nearest(), act.reach() }),
        }
        return;
    }
    g.mode = .play;
    spend(g, act);
    const from = h.at;
    switch (reticle) {
        .bow => loose(g, from, act),
        .leap => leap(g, from, act),
        .swing => combat.swing(g, from, act),
        .rush => rush(g, from, act),
    }
}

fn loose(g: *game.Game, from: P, act: skillbar.Act) void {
    const to = g.mark;
    const f = bow.fly(&g.sim.lv, from, to);
    g.pic.shot = .{ .flight = f, .from = from, .act = act };
    g.pic.holdUntil(g.pic.shot.?.ends());
    const s = game.presentation.Stroke{ .from = from, .wait = g.pic.shot.?.lands(), .fire = act.element() == .fire };
    if (act.element() == .lightning and f.len > 0) g.pic.fx.zap(@max(0, s.wait - game.ZAP_S), .{ .from = mathx.centre(from), .to = mathx.centre(f.path[f.len - 1]) });
    g.pic.lead = s.wait;
    if (f.struck) |hit| switch (act) {
        inline else => |a| if (comptime a.reticle() != .bow) unreachable else if (comptime a.bursts()) combat.burstHit(g, a, hit, f.impact().?, s) else switch (hit) {
            .body => |id| if (comptime a.chains())
                combat.chainHit(g, a, id, s)
            else if (comptime !a.afflicts()) blk: {
                comptime std.debug.assert(a.element() == null);
                break :blk combat.wound(g, id, combat.heroSkill(g, a), combat.SHOOT, s);
            } else combat.arrowHit(g, id, combat.heroArrow(g, a, true), a, s),
            .barrel => |p| combat.smash(g, p, combat.barrelVerb(a), s),
        },
    } else {
        g.sim.log.say("{s}'s {s} finds nothing.", .{ g.sim.name.text(), act.bolt() orelse "arrow" });
        g.sim.chronicle.note(.missed);
    }
    combat.endTurn(g);
}

fn sayDone(g: *game.Game, act: skillbar.Act) void {
    const done = act.done() orelse return;
    g.sim.log.say("{s} {s}.", .{ g.sim.name.text(), done });
}
