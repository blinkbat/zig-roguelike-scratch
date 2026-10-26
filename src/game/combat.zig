const std = @import("std");
const chronicle = @import("../play/chronicle.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const gas = @import("../map/gas.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const attrs = @import("../play/attrs.zig");
const burning = @import("../play/burning.zig");
const turn_clock = @import("../play/clock.zig");
const glacial = @import("../play/glacial.zig");
const skillbar = @import("../play/skillbar.zig");
const fx = @import("../gfx/fx.zig");
const game = @import("../game.zig");
const attacks = @import("attacks.zig");
const rewards = @import("rewards.zig");
const skills = @import("skills.zig");
const tactics = @import("tactics.zig");
const P = mathx.P;
const Stroke = game.presentation.Stroke;

pub fn barrelVerb(comptime act: skillbar.Act) []const u8 {
    return if (comptime act.bolt() != null) skillbar.Act.skill(act).VERB else SHOOT;
}

/// Choose targets before striking; each jump delays the next hit and the foes' stagger.
pub fn chainHit(g: *game.Game, comptime act: skillbar.Act, first: u16, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const c = M.chain(&g.sim.lv, &g.sim.pool, first);
    var from = s.from;
    var wait = s.wait;
    for (c.slice(), 0..) |id, k| {
        const slot = actor.Pool.slot(id);
        const at = g.sim.pool.items[slot].at;
        if (k > 0) {
            g.pic.fx.zap(wait, .{ .from = mathx.centre(from), .to = mathx.centre(at) });
            wait += game.ZAP_S;
        }
        arrowHit(g, id, attacks.heroArrow(&g.sim, act, true), act, .{ .from = from, .wait = wait });
        from = at;
    }
    g.pic.holdUntil(wait);
    g.pic.lead = wait;
}

pub fn swing(g: *game.Game, from: P, act: skillbar.Act, mark: P) void {
    const d = mathx.dirTo(from, mark).?;
    const s = game.heroBump(g, from, mark, 0);
    switch (act) {
        inline else => |a| if (comptime a.reticle() != .swing)
            unreachable
        else if (comptime a.sweeps())
            sweep(g, a, mark, s)
        else if (comptime a.knocks())
            knock(g, a, d, s)
        else
            @compileError(@tagName(a) ++ " swings at nothing"),
    }
    g.pic.turnToward(g.sim.hero, d.delta().x);
    g.pic.lead = s.wait;
    endTurn(g);
}

/// Snapshot arc targets before damage so newborn slime halves are spared.
fn sweep(g: *game.Game, comptime act: skillbar.Act, mark: P, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const arc = M.arc(&g.sim.lv, s.from, mark);
    const struck = occupants(M.WIDTH, &g.sim.lv, &arc);
    const raw = attacks.rawFor(&g.sim, act, true);
    for (arc.slice(), struck[0..arc.n]) |p, w| {
        if (w != grid.NO_ONE) wound(g, w, attacks.heroScaled(&g.sim, act, raw).physical(), M.VERB, s) else smash(g, p, M.VERB, s);
    }
}

fn occupants(comptime N: usize, lv: *const grid.Level, area: *const grid.Area(N)) [N]u16 {
    var out: [N]u16 = undefined;
    for (area.slice(), out[0..area.n]) |p, *w| w.* = lv.who(p);
    return out;
}

pub fn knock(g: *game.Game, comptime act: skillbar.Act, d: mathx.Dir, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const to = s.from.add(d.delta());
    const id = g.sim.lv.who(to);
    if (id == grid.NO_ONE) return smash(g, to, M.VERB, s);
    const a = g.sim.pool.get(id).?;
    if (!attacks.heroLands(&g.sim, a, .chosen)) return;
    var r = attacks.heroSkill(&g.sim, act).against(a, &g.sim.rng);
    r.hit_checked = true;
    const takes = if (comptime act.afflicts()) attacks.afflicted(&g.sim, a, M, r.dmg > 0 and r.dmg < a.hp, 0) else false;
    if (comptime act.afflicts()) if (takes) {
        r.applied = M.AILMENT;
    };
    wound(g, id, r, M.VERB, s);
    if (g.sim.pool.get(id) == null) return;
    const name = actor.row(a.kind).name;
    const back = if (a.pin.turns > 0) null else M.knocked(&g.sim.lv, a.at, d, id);
    if (back) |b| {
        const i = actor.Pool.slot(id);
        g.sim.pool.move(&g.sim.lv, id, b);
        g.sim.displaced.set(i);
        _ = g.pic.glideToHeld(i, b, -s.wait);
        tactics.entered(g, id);
        g.sim.sayAt(b, "The {s} is knocked back.", .{name});
    }
    if (takes) sayTakes(g, M.TAKES, a.at, name);
}

fn sayTakes(g: *game.Game, comptime takes: []const u8, at: P, name: []const u8) void {
    g.sim.sayAt(at, "The {s} " ++ takes ++ "!", .{name});
}

pub const SHOOT = bow.VERB;
const IT_DIES = " It dies.";
const CUT_DOWN = " It is cut down.";

pub fn arrowHit(g: *game.Game, id: u16, hit: attacks.Rolled, comptime act: skillbar.Act, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const el = comptime act.element();
    const a = g.sim.pool.get(id) orelse return;
    if (!attacks.heroLands(&g.sim, a, .chosen)) return;
    const resists = g.sim.combatStats(a).elements;
    var r = (attacks.Roll{ .dmg = hit.blow.total(resists), .physical = hit.blow.physical, .crit = hit.crit, .effect = hit.effect, .hit_checked = true }).against(a, &g.sim.rng);
    const at = a.at;
    const name = actor.row(a.kind).name;
    const lands = r.dmg > 0 and r.dmg < a.hp and if (el) |e| hit.blow.reaches(resists, e) else true;
    const takes = attacks.afflicted(&g.sim, a, M, lands, if (el) |e| resists.get(e) else 0);
    if (takes) r.applied = M.AILMENT;
    if (r.dmg > 0) wound(g, id, r, M.VERB, s);
    if (takes and g.sim.pool.get(id) != null) sayTakes(g, M.TAKES, at, name);
}

pub fn burstHit(g: *game.Game, comptime act: skillbar.Act, hit: bow.Hit, impact: P, s: Stroke) void {
    const M = skillbar.Act.elemental(act);
    const direct: ?u16 = switch (hit) {
        .body => |id| id,
        .barrel => null,
    };
    areaHit(g, act, impact, M.burst(&g.sim.lv, s.from, impact), s, direct, hit == .barrel);
}

pub fn areaHit(g: *game.Game, comptime act: skillbar.Act, at: P, area: glacial.Burst, s: Stroke, direct: ?u16, barrel: bool) void {
    const struck = skills.foesIn(g, area);
    g.pic.fx.burst(s.wait, .{ .at = at, .area = area, .element = act.element().? });
    const raw = attacks.rawFor(&g.sim, act, direct != null);
    if (barrel) smash(g, at, barrelVerb(act), s);
    for (struck.slice()) |id| {
        var hit = raw;
        if (direct != id) hit.physical = 0;
        arrowHit(g, id, attacks.heroScaled(&g.sim, act, hit), act, s);
    }
}
pub fn smash(g: *game.Game, p: P, comptime verb: []const u8, s: Stroke) void {
    const gold = rewards.barrelGold(&g.sim, p) orelse return;
    g.sim.log.push(.loot, "{s} " ++ verb ++ BARREL_DROPS, .{ g.sim.name.text(), gold });
    g.pic.strike(&g.sim, g.cloud, .{ .barrel = p }, s);
}

const BARREL_DROPS = " the barrel. It drops {d} gold.";

pub fn openChest(g: *game.Game, p: P) bool {
    switch (rewards.openChest(&g.sim, p)) {
        .opened => return true,
        .not_closed => return false,
        .ground_full => {
            g.character.message.say("Ground full", .{});
            return false;
        },
    }
}

pub fn groundRoom(g: *game.Game) bool {
    if (rewards.groundRoom(&g.sim)) return true;
    g.character.message.say("Ground full", .{});
    return false;
}

pub fn collectGold(g: *game.Game, at: P) void {
    const coins = rewards.collectGold(&g.sim, at) orelse return;
    g.pic.gold_taken = coins;
}

pub fn arrive(g: *game.Game, at: P) void {
    if (!g.sim.lv.at(at).isChest() and !g.sim.ground.hasItems(at)) collectGold(g, at);
    rewards.noticeItems(&g.sim, at);
}

pub fn wound(g: *game.Game, id: u16, raw: attacks.Roll, comptime verb: []const u8, s: Stroke) void {
    woundAt(g, .fromInt(id), raw, verb, s, .chosen, null);
}

pub fn reaction(g: *game.Game, id: u16, raw: attacks.Roll, comptime verb: []const u8, s: Stroke, source: u16, flight: ?bow.Flight) void {
    woundAt(g, .fromInt(id), raw, verb, s, .{ .reaction = .fromInt(source) }, flight);
}

fn woundAt(g: *game.Game, target: actor.ActorId, raw: attacks.Roll, comptime verb: []const u8, s: Stroke, origin: chronicle.AttackOrigin, flight: ?bow.Flight) void {
    const outcome = attacks.resolve(&g.sim, target, raw, origin) orelse return;
    const hit = switch (outcome) {
        .miss => {
            g.pic.recordAttack(&g.sim, g.cloud, origin, s, flight, .miss, null);
            return;
        },
        .hit => |hit| hit,
    };
    const h = hit.damage;
    game.presentDamage(g, h);
    const name = actor.row(hit.kind).name;
    g.sim.chronicle.note(.{ .dealt = .{ .to = hit.kind, .killed = h.lethal, .origin = origin } });
    g.sim.sayAs(.damage, hit.at, "{s} " ++ verb ++ " the {s}{s} for {d}.{s}", .{ g.sim.name.text(), name, if (hit.roll.crit) " critically" else "", hit.roll.dmg, if (hit.culled) CUT_DOWN else if (h.lethal) IT_DIES else "" });
    if (hit.bled) |said| g.sim.sayAt(hit.at, "The {s} {s}!", .{ name, said });
    if (hit.stunned) sayTakes(g, turn_clock.STUNNED, hit.at, name);
    const after = afterBlow(g, target.value, h);
    const impact = fx.ActorImpact{ .slot = target.slot(), .at = hit.at, .lethal = h.lethal, .after = after };
    if (h.lethal) fell(g, target.value);
    const recovery = recoverLife(g, hit.recovery);
    g.pic.recordAttack(&g.sim, g.cloud, origin, s, flight, .{ .hit = impact }, recovery);
}

/// Shown on the hero as the blow that earned it lands.
pub fn heal(g: *game.Game, n: i32, wait: f32) void {
    const after = recoverLife(g, n) orelse return;
    g.pic.recordRecovery(&g.sim, wait, after);
}

fn recoverLife(g: *game.Game, n: i32) ?fx.After {
    if (!g.sim.recoverLife(n)) return null;
    return g.pic.afterOf(&g.sim, g.sim.heroSlot().?);
}

fn afterBlow(g: *game.Game, id: u16, h: Hurt) fx.After {
    const other = if (h.lethal) null else split(g, id);
    return g.pic.damageAfter(&g.sim, h, other);
}

/// Split halves become visible only when the splitting blow lands.
fn split(g: *game.Game, id: u16) ?actor.ActorId {
    const i = actor.Pool.slot(id);
    const name = actor.row(g.sim.pool.items[i].kind).name;
    const other = g.sim.pool.split(&g.sim.lv, id, &g.sim.rng) orelse return null;
    const o = actor.Pool.slot(other);
    g.sim.ran[o] = g.sim.ran[i];
    g.pic.recordSplit(&g.sim, .fromInt(id), .fromInt(other));
    g.sim.sayAt(g.sim.pool.items[i].at, "The {s} splits in two!", .{name});
    return .fromInt(other);
}

pub fn fell(g: *game.Game, id: u16) void {
    const target = actor.ActorId.fromInt(id);
    const death = rewards.defeat(&g.sim, target);
    g.pic.recordDeath(target, death);
}

pub fn scare(g: *game.Game, fallen: usize) void {
    const frightened = rewards.scare(&g.sim, g.sim.pool.items[fallen].at);
    g.pic.recordFright(.fromIndex(fallen), frightened);
}

fn heroDies(g: *game.Game) void {
    g.sim.log.push(.danger, "{s} dies.", .{g.sim.name.text()});
    g.died_in = std.meta.activeTag(g.mode);
    g.mode = .dead;
    game.epitaph.inscribe(g);
}

pub fn endTurn(g: *game.Game) void {
    const h = g.sim.heroActor() orelse return;
    defer g.sim.finishTurn();
    beginTurn(g, h.at);
    heroAfterAction(g);
    if (g.mode == .dead) return;
    spreadGasAndAdvanceClocks(&g.sim);
    if (!orderedFoeTurns(g)) return;
    waitingNewbornTurns(g);
    finishTurnPicture(g);
}

fn beginTurn(g: *game.Game, from: P) void {
    g.sim.unsaved = true;
    g.sim.clock.turn();
    tactics.startTurn(&g.sim);
    skills.recover(g);
    for (&g.sim.cooldown.values) |*c| c.* -|= 1;
    game.castSight(g, from);
    g.sim.flowed = false;
    orderFoes(g, from);
}

fn heroAfterAction(g: *game.Game) void {
    harmAfter(g, g.sim.hero, g.sim.stepped);
    g.sim.stepped = false;
}

fn spreadGasAndAdvanceClocks(sim: *game.simulation.Simulation) void {
    gas.turn(&sim.lv, &sim.rng);
    for (sim.pool.slice()) |*a| {
        if (a.alive and a.foe()) a.clock.pass(actor.row(a.kind).pace);
    }
}

fn orderedFoeTurns(g: *game.Game) bool {
    for (g.sim.order[0..g.sim.order_n]) |id| {
        const i = actor.Pool.slot(id);
        const was = g.sim.pool.items[i].at;
        foeTurn(g, id);
        if (g.mode == .dead) return false;
        harmAfter(g, id, !g.sim.pool.items[i].at.eq(was));
    }
    return true;
}

fn waitingNewbornTurns(g: *game.Game) void {
    var i: usize = 0;
    while (i < g.sim.pool.n) : (i += 1) {
        const a = g.sim.pool.items[i];
        if (!a.alive or !a.waits) continue;
        const id = actor.Pool.idOf(i);
        _ = wearTurn(g, id);
        harmAfter(g, id, false);
    }
}

fn finishTurnPicture(g: *game.Game) void {
    if (g.sim.heroActor()) |a| {
        if (a.ward.turns > 0) {
            a.ward.wear();
            g.pic.recordWear(&g.sim, .fromInt(g.sim.hero));
        }
        game.castSight(g, a.at);
        g.sim.chronicle.begin(game.epitaph.turnStart(g));
    }
}

const Hurt = game.simulation.DamageResult;

fn harmAfter(g: *game.Game, id: u16, moved: bool) void {
    gasHarm(g, id);
    burnHarm(g, id);
    bleedHarm(g, id, moved or g.sim.displaced.isSet(actor.Pool.slot(id)));
}

fn gasHarm(g: *game.Game, id: u16) void {
    const a = g.sim.pool.get(id) orelse return;
    if (!g.sim.lv.gassy(a.at) or ranAlready(g, id, .gassed)) return;
    _ = harmTick(g, id, gas.harm(a.max), .gassed, .{ .hero = "The " ++ gas.NAME ++ " eats at {s} for {d}." });
}

/// Mark a tick consumed; split halves inherit the parent's consumed ticks.
fn ranAlready(g: *game.Game, id: u16, comptime tick: game.simulation.Tick) bool {
    const r = &g.sim.ran[actor.Pool.slot(id)];
    defer r.insert(tick);
    return r.contains(tick);
}

pub fn burnHarm(g: *game.Game, id: u16) void {
    const a = g.sim.pool.get(id) orelse return;
    if (ranAlready(g, id, .burned)) return;
    const dmg = a.burn.tick(g.sim.combatStats(a).elements.get(burning.ELEMENT)) orelse return;
    if (dmg == 0) return;
    _ = harmTick(g, id, dmg, .burned, .{ .hero = "Burning sears {s} for {d}.", .foe = "Burning sears the {s} for {d}." });
}

fn bleedHarm(g: *game.Game, id: u16, moved: bool) void {
    const a = g.sim.pool.get(id) orelse return;
    if (ranAlready(g, id, .bled)) return;
    const dmg = a.bleed.tick(moved) orelse return;
    const stopped = a.bleed.turns == 0;
    const foe = "The {s} bleeds for {d}.";
    const h = if (moved)
        harmTick(g, id, dmg, .bled, .{ .hero = "Moving tears {s}'s wound: it bleeds for {d}.", .foe = foe, .torn = true })
    else
        harmTick(g, id, dmg, .bled, .{ .hero = "{s} bleeds for {d}.", .foe = foe });
    if (id == g.sim.hero and stopped and !h.lethal) g.sim.log.say("{s} stops bleeding.", .{g.sim.name.text()});
}

/// Each takes the name and the damage; a foe with no line of its own is said only to die.
const Said = struct { hero: []const u8, foe: ?[]const u8 = null, torn: bool = false };

fn harmTick(g: *game.Game, id: u16, dmg: i32, comptime owed: game.simulation.Tick, comptime said: Said) Hurt {
    const a = g.sim.pool.get(id).?;
    const kind = a.kind;
    const at = a.at;
    const before = a.hp;
    const h = game.hurt(g, .fromInt(id), dmg);
    const hero = id == g.sim.hero;
    const name = actor.row(kind).name;
    if (hero) {
        g.sim.log.push(.danger, said.hero, .{ g.sim.name.text(), h.dmg });
        const by: chronicle.Source = switch (owed) {
            .gassed => .gas,
            .burned => .burn,
            .bled => .bleed,
            .worn => unreachable,
        };
        g.sim.chronicle.note(.{ .hurt = .{ .by = by, .dmg = h.dmg, .before = before, .torn = said.torn } });
    } else if (comptime said.foe) |line| {
        g.sim.sayAt(at, line ++ "{s}", .{ name, h.dmg, if (h.lethal) IT_DIES else "" });
    } else if (h.lethal) g.sim.sayAt(at, "The {s} dies.", .{name});
    var debt = game.presentation.Harm{ .kill = h.lethal, .after = afterBlow(g, id, h) };
    if (h.lethal) {
        if (hero) heroDies(g) else {
            fell(g, id);
            debt.recovery = recoverLife(g, g.sim.inventory.gear.killRecovery());
        }
    }
    g.pic.recordStatus(.fromInt(id), owed, debt);
    return h;
}

const Worn = struct { held: bool = false, skips: bool = false };

fn wearTurn(g: *game.Game, id: u16) Worn {
    const a = g.sim.pool.get(id) orelse return .{};
    if (ranAlready(g, id, .worn) or (a.pin.turns == 0 and a.chill.turns == 0)) return .{};
    const w = Worn{ .held = a.pin.hold(), .skips = a.chill.turns > 0 and a.chill.skip() };
    g.pic.recordWear(&g.sim, .fromInt(id));
    return w;
}

fn orderFoes(g: *game.Game, from: P) void {
    g.sim.order_n = 0;
    for (g.sim.pool.slice(), 0..) |a, i| {
        const id = actor.Pool.idOf(i);
        if (id == g.sim.hero or !a.alive or a.waits) continue;
        g.sim.order[g.sim.order_n] = id;
        g.sim.order_n += 1;
    }
    const Near = struct {
        pool: *const actor.Pool,
        from: P,
        fn nearer(n: @This(), a: u16, b: u16) bool {
            const sa = actor.Pool.slot(a);
            const sb = actor.Pool.slot(b);
            const da = mathx.dist(n.pool.items[sa].at, n.from);
            const db = mathx.dist(n.pool.items[sb].at, n.from);
            return da < db or (da == db and a < b);
        }
    };
    std.mem.sort(u16, g.sim.order[0..g.sim.order_n], Near{ .pool = &g.sim.pool, .from = from }, Near.nearer);
}

fn foeTurn(g: *game.Game, id: u16) void {
    const f = g.sim.pool.get(id) orelse return;
    f.sweep_in -|= 1;
    const stalled = f.clock.stalled;
    const worn = wearTurn(g, id);
    const held = worn.held;
    if (worn.skips or stalled) return;
    const r = g.sim.pool.get(id) orelse return;
    const h = g.sim.heroActor() orelse return;
    const row = actor.row(r.kind);
    if (!r.awake) {
        if (!fov.sees(&g.sim.lv, r.at, h.at, row.sight)) return;
        r.awake = true;
        g.pic.turnLater(id, h.at.x - r.at.x);
        g.sim.sayAt(r.at, "A {s} notices {s}.", .{ row.name, g.sim.name.text() });
        return;
    }
    if (r.fright > 0) {
        r.fright -= 1;
        if (if (held) null else fleeWay(g, r.at, id, h.at)) |d| {
            foeStep(g, id, r.at, d);
        } else if (besideWay(g, r.at, h.at)) |d| {
            g.pic.turnLater(id, d.delta().x);
            reach(g, id, row, null);
        }
        if (r.fright == 0) g.sim.sayAt(r.at, "The {s} stops running.", .{row.name});
        return;
    }
    if (row.ranged) |ranged| {
        const gap = mathx.dist(r.at, h.at);
        if (!held and gap <= ranged.retreat) {
            if (fleeWay(g, r.at, id, h.at)) |d| return foeStep(g, id, r.at, d);
        }
        if (gap <= ranged.range and bow.aimable(&g.sim.lv, r.at, h.at)) {
            const flight = bow.fly(&g.sim.lv, r.at, h.at);
            if (flight.struck) |hit| {
                if (hit == .body and hit.body == g.sim.hero) {
                    g.pic.turnLater(id, h.at.x - r.at.x);
                    reach(g, id, row, flight);
                    return;
                }
            }
        }
        if (!held and gap > ranged.retreat) if (actor.chase(&g.sim.lv, r.at, id, flowTo(g, h.at))) |d| {
            if (mathx.dist(r.at.add(d.delta()), h.at) <= ranged.retreat) return;
            foeStep(g, id, r.at, d);
        };
        return;
    }
    const flitted = if (!held and row.flits and g.sim.rng.chance(actor.FLIT)) actor.flit(&g.sim.lv, r.at, id, g.sim.hero, &g.sim.rng) else null;
    const d = flitted orelse foeWay(g, r.at, id, h.at) orelse return;
    const to = r.at.add(d.delta());
    if (held and !to.eq(h.at)) return;
    if (!to.eq(h.at)) return foeStep(g, id, r.at, d);
    g.pic.turnLater(id, d.delta().x);
    reach(g, id, row, null);
}

fn foeStep(g: *game.Game, id: u16, from: P, d: mathx.Dir) void {
    g.pic.turnLater(id, d.delta().x);
    g.sim.pool.move(&g.sim.lv, id, from.add(d.delta()));
    tactics.entered(g, id);
}

fn foeWay(g: *game.Game, at: P, id: u16, hero: P) ?mathx.Dir {
    return besideWay(g, at, hero) orelse actor.chase(&g.sim.lv, at, id, flowTo(g, hero));
}

fn fleeWay(g: *game.Game, at: P, id: u16, hero: P) ?mathx.Dir {
    return actor.flee(&g.sim.lv, at, id, flowTo(g, hero));
}

fn besideWay(g: *const game.Game, at: P, hero: P) ?mathx.Dir {
    const d = mathx.dirTo(at, hero) orelse return null;
    return if (g.sim.lv.passOk(at, d)) d else null;
}

fn flowTo(g: *game.Game, hero: P) *const [grid.CELLS]i32 {
    if (!g.sim.flowed) {
        _ = grid.distances(&g.sim.lv, hero, &g.sim.flow, &g.sim.queue);
        g.sim.flowed = true;
    }
    return &g.sim.flow;
}

fn reach(g: *game.Game, id: u16, row: actor.Row, flight: ?bow.Flight) void {
    const i = actor.Pool.slot(id);
    const kind = g.sim.pool.items[i].kind;
    switch (row.blow) {
        .strike => |s| {
            const sweeps = sweepReady(g, id, row);
            if (sweeps) sweepRound(g, id, row, s);
            const verb = if (sweeps) actor.SWEEP_VERB else s.verb;
            const hero = g.sim.heroActor().?;
            const attacker = &g.sim.pool.items[i];
            const dmg = attacks.bite(&g.sim.rng, g.sim.combatStats(attacker), g.sim.combatStats(hero), s);
            const landed = dmg orelse {
                g.sim.log.say("{s} dodges the {s}.", .{ g.sim.name.text(), row.name });
                g.pic.recordFoeAttack(.fromInt(id), .miss, flight);
                if (row.ranged == null) tactics.counter(g, id);
                return;
            };
            const before = hero.hp;
            var physical = g.sim.heroAttrs().physical(landed, &g.sim.rng);
            if (hero.tactics.guard > 0) physical = @intCast(@divTrunc(@as(i64, physical) * (100 - @import("../play/tactics.zig").Guard.reduction(hero.tactics.guard)) + 99, 100));
            const h = game.hurt(g, .fromInt(g.sim.hero), physical);
            const lethal = h.lethal;
            g.sim.log.push(.danger, "The {s} {s} {s} for {d}.", .{ row.name, verb, g.sim.name.text(), h.dmg });
            g.sim.chronicle.note(.{ .hurt = .{ .by = .{ .foe = kind }, .dmg = h.dmg, .before = before, .best = landed == s.hit.hi } });
            if (!lethal and h.dmg > 0 and g.sim.procStatus(hero, .bleed, s.bleeds)) {
                g.sim.log.say("{s} {s}!", .{ g.sim.name.text(), hero.bleed.said() });
                hero.bleed.start();
            }
            if (!lethal and h.dmg > 0 and g.sim.procStatus(hero, .stun, s.stuns)) {
                hero.clock.stun();
                g.sim.log.say("{s} " ++ turn_clock.STUNNED ++ "!", .{g.sim.name.text()});
                g.sim.chronicle.note(.{ .stunned = kind });
            }
            const after = afterBlow(g, g.sim.hero, h);
            g.pic.recordFoeAttack(.fromInt(id), if (lethal) .{ .kill = after } else .{ .hurt = after }, flight);
            if (row.ranged == null) returnThorns(g, id, hero.at);
            if (lethal) heroDies(g) else if (row.ranged == null) tactics.counter(g, id);
        },
        .burst => {
            g.sim.chronicle.note(.burst);
            const a = g.sim.pool.get(id).?.*;
            _ = g.sim.pool.damage(&g.sim.lv, id, a.hp);
            g.pic.recordFoeAttack(.fromInt(id), .{ .burst = g.pic.afterOf(&g.sim, i) }, flight);
            fell(g, id);
        },
    }
}

fn returnThorns(g: *game.Game, id: u16, from: P) void {
    const amount = g.sim.heroAttrs().thorns;
    if (amount <= 0) return;
    const a = g.sim.pool.get(id) orelse return;
    if (mathx.dist(from, a.at) != 1) return;
    const dmg = attrs.armoured(actor.row(a.kind).armour, amount, &g.sim.rng);
    if (dmg <= 0) return;
    const at = a.at;
    const kind = a.kind;
    const h = game.hurt(g, .fromInt(id), dmg);
    const after = afterBlow(g, id, h);
    g.sim.chronicle.note(.{ .dealt = .{ .to = kind, .killed = h.lethal, .origin = .{ .reaction = .fromInt(id) } } });
    g.sim.sayAs(.damage, at, "{s}'s thorns hurt the {s} for {d}.{s}", .{ g.sim.name.text(), actor.row(kind).name, h.dmg, if (h.lethal) IT_DIES else "" });
    if (h.lethal) fell(g, id);
    g.pic.recordThorns(.fromInt(id), .{ .kill = h.lethal, .after = after, .recovery = if (h.lethal) recoverLife(g, g.sim.inventory.gear.killRecovery()) else null });
}

fn sweepReady(g: *game.Game, id: u16, row: actor.Row) bool {
    const a = g.sim.pool.get(id).?;
    if (row.sweep_every == 0 or a.sweep_in > 0) return false;
    a.sweep_in = row.sweep_every;
    return true;
}

/// Every body and barrel round the sweeper but the hero, snapshot before any blow so newborn halves are spared.
fn sweepRound(g: *game.Game, id: u16, row: actor.Row, s: actor.Strike) void {
    const from = g.sim.pool.get(id).?.at;
    const cells = actor.sweep(&g.sim.lv, from);
    const struck = occupants(actor.SWEEP_CELLS, &g.sim.lv, &cells);
    var swept = game.presentation.Swept{};
    for (cells.slice(), struck[0..cells.n]) |p, w| {
        if (w == g.sim.hero) continue;
        const hit = if (w != grid.NO_ONE) swipe(g, id, w, row, s) orelse continue else smashedBy(g, p, row) orelse continue;
        swept.hit[swept.n] = hit;
        swept.n += 1;
    }
    g.pic.recordSweep(.fromInt(id), swept);
}

fn swipe(g: *game.Game, source: u16, id: u16, by: actor.Row, s: actor.Strike) ?fx.Impact {
    const a = g.sim.pool.get(id).?;
    const rolled = attacks.bite(&g.sim.rng, g.sim.combatStats(g.sim.pool.get(source).?), g.sim.combatStats(a), s) orelse {
        g.sim.sayAt(a.at, "The {s} misses the {s}.", .{ by.name, actor.row(a.kind).name });
        return null;
    };
    const at = a.at;
    const name = actor.row(a.kind).name;
    const dmg = (attacks.Roll{ .dmg = rolled, .physical = rolled }).against(a, &g.sim.rng).dmg;
    const stunned = dmg > 0 and dmg < a.hp and g.sim.procStatus(a, .stun, s.stuns);
    if (stunned) {
        if (!a.waits and !g.sim.ran[actor.Pool.slot(id)].contains(.worn)) a.clock.stunBeforeAction(actor.row(a.kind).pace) else a.clock.stun();
    }
    const h = game.hurt(g, .fromInt(id), dmg);
    g.sim.sayAt(at, "The {s} " ++ actor.SWEEP_VERB ++ " the {s} for {d}.{s}", .{ by.name, name, h.dmg, if (h.lethal) IT_DIES else "" });
    if (stunned) sayTakes(g, turn_clock.STUNNED, at, name);
    const after = afterBlow(g, id, h);
    if (h.lethal) fell(g, id);
    return .{ .actor = .{ .slot = actor.ActorId.fromInt(id).slot(), .at = at, .lethal = h.lethal, .after = after } };
}

fn smashedBy(g: *game.Game, p: P, by: actor.Row) ?fx.Impact {
    const gold = rewards.barrelGold(&g.sim, p) orelse return null;
    g.sim.sayAt(p, "The {s} smashes" ++ BARREL_DROPS, .{ by.name, gold });
    return .{ .barrel = p };
}
