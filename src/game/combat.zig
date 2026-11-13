const std = @import("std");
const chronicle = @import("../play/chronicle.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const gas = @import("../map/gas.zig");
const fire = @import("../map/fire.zig");
const ice = @import("../map/ice.zig");
const atlas = @import("../map/atlas.zig");
const day = @import("../map/day.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const firebolt = @import("../play/firebolt.zig");
const windup = @import("../play/windup.zig");
const attrs = @import("../play/attrs.zig");
const burning = @import("../play/burning.zig");
const damage = @import("../play/damage.zig");
const turn_clock = @import("../play/clock.zig");
const glacial = @import("../play/glacial.zig");
const areas = @import("../play/area.zig");
const blind = @import("../play/blind.zig");
const confusion = @import("../play/confusion.zig");
const shock = @import("../play/shock.zig");
const skillbar = @import("../play/skillbar.zig");
const tactics = @import("../play/tactics.zig");
const fx = @import("../gfx/fx.zig");
const look = @import("../gfx/look.zig");
const game = @import("../game.zig");
const foes = @import("foe_rules.zig");
const attacks = @import("attacks.zig");
const rewards = @import("rewards.zig");
const skills = @import("skills.zig");
const tactics_exec = @import("tactics_exec.zig");
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
        skillHit(g, id, attacks.heroBlow(&g.sim, act), act, .{ .from = from, .wait = wait, .element = s.element });
        from = at;
    }
    g.pic.leadUntil(wait);
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
            cut(g, a, d, s),
    }
    g.pic.turnHero(&g.sim, d.delta().x);
    g.pic.lead = s.wait;
    endTurn(g);
}

/// Snapshot arc targets before damage so newborn slime halves are spared.
fn sweep(g: *game.Game, comptime act: skillbar.Act, mark: P, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const arc = M.arc(&g.sim.lv, s.from, mark);
    const struck = occupants(M.WIDTH, &g.sim.lv, &arc);
    const raw = attacks.rawFor(&g.sim, act);
    for (arc.slice(), struck[0..arc.n]) |p, w| {
        if (w != grid.NO_ONE) wound(g, w, attacks.heroScaled(&g.sim, act, raw).physical(), M.VERB, s) else smash(g, p, M.VERB, s);
    }
}

fn occupants(comptime N: usize, lv: *const grid.Level, area: *const grid.Bounded(P, N)) [N]u16 {
    var out: [N]u16 = undefined;
    for (area.slice(), out[0..area.n]) |p, *w| w.* = lv.who(p);
    return out;
}

const Struck = struct { id: u16, takes: bool };

fn strike(g: *game.Game, comptime act: skillbar.Act, d: mathx.Dir, s: Stroke) ?Struck {
    const M = skillbar.Act.skill(act);
    const to = s.from.add(d.delta());
    const id = g.sim.lv.who(to);
    if (id == grid.NO_ONE) {
        smash(g, to, M.VERB, s);
        return null;
    }
    const a = g.sim.pool.get(id).?;
    if (!a.foe() or !attacks.heroLands(&g.sim, a, .chosen)) return null;
    const blow = attacks.chosenBlow(&g.sim, a, attacks.heroSkill(&g.sim, act), act, true, 0);
    wound(g, id, blow.roll, M.VERB, s);
    if (g.sim.pool.get(id) == null) return null;
    return .{ .id = id, .takes = blow.takes };
}

fn cut(g: *game.Game, comptime act: skillbar.Act, d: mathx.Dir, s: Stroke) void {
    const hit = strike(g, act, d, s) orelse return;
    const a = g.sim.pool.get(hit.id).?;
    if (comptime act.afflicts()) if (hit.takes) g.sim.sayFoeTakes(a, skillbar.Act.skill(act).TAKES);
}

pub fn knock(g: *game.Game, comptime act: skillbar.Act, d: mathx.Dir, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const hit = strike(g, act, d, s) orelse return;
    const id = hit.id;
    const a = g.sim.pool.get(id).?;
    const name = actor.row(a.kind).name;
    const back = if (a.pin.holding()) null else M.knocked(&g.sim.lv, a.at, d, id);
    if (back) |b| if (actor.holds(a.kind, &g.sim.lv, b)) {
        tactics_exec.displace(g, id, b);
        _ = g.pic.glideToHeld(.fromIndex(actor.Pool.slot(id)), b, -s.wait);
        g.sim.sayAt(b, "The {s} is knocked back.", .{name});
    };
    if (comptime act.afflicts()) if (hit.takes) g.sim.sayFoeTakes(a, M.TAKES);
}

pub const SHOOT = bow.VERB;
const IT_DIES = " It dies.";
const CUT_DOWN = " It is cut down.";

fn deathNote(h: Hurt) []const u8 {
    return if (h.lethal) IT_DIES else "";
}

pub fn skillHit(g: *game.Game, id: u16, hit: attacks.Rolled, comptime act: skillbar.Act, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const el = comptime act.element();
    const a = g.sim.pool.get(id) orelse return;
    const at = a.at;
    const grounded = actor.row(a.kind).movement.grounded();
    var wet: ?Wet = null;
    if (el == .lightning and grounded) {
        if (wading(&g.sim, at)) |bodies| {
            wet = .{ .bodies = bodies, .struck = actor.Pool.slot(id), .born = g.sim.pool.n };
        }
    }
    defer conductTo(g, at, wet, s);
    if (!a.foe() or !attacks.heroLands(&g.sim, a, .chosen)) return;
    const resists = g.sim.combatStats(a).elements;
    const reaches = if (el) |e| hit.blow.reaches(resists, e) else true;
    const blow = attacks.chosenBlow(&g.sim, a, hit.against(resists), act, reaches, if (el) |e| resists.get(e) else 0);
    if (blow.roll.dmg > 0) wound(g, id, blow.roll, M.VERB, s);
    if (blow.takes) if (g.sim.pool.get(id)) |b| g.sim.sayFoeTakes(b, M.TAKES);
}

pub fn conduct(g: *game.Game, at: P, s: Stroke) void {
    conductTo(g, at, if (wading(&g.sim, at)) |bodies| .{ .bodies = bodies } else null, s);
}

const Wet = struct { bodies: rewards.Caught, struck: ?usize = null, born: usize = 0 };

/// The grounded bodies in the water joined to `at`, taken before a blow so a half it splits off is not shocked apart from its parent.
fn wading(sim: *const game.simulation.Simulation, at: P) ?rewards.Caught {
    const water = shock.conducted(&sim.lv, at);
    if (water.n == 0) return null;
    var out = rewards.Caught.initEmpty();
    for (sim.pool.constSlice(), 0..) |a, slot| {
        if (a.alive and water.has(a.at) and actor.row(a.kind).movement.grounded()) out.set(slot);
    }
    return out;
}

fn conductTo(g: *game.Game, at: P, wet: ?Wet, s: Stroke) void {
    const w = wet orelse return;
    g.sim.sayAt(at, shock.CONDUCTS, .{});
    var each = w.bodies.iterator(.{});
    while (each.next()) |slot| {
        const a = &g.sim.pool.items[slot];
        if (!a.alive) continue;
        if (!a.at.eq(at) and g.sim.lv.isLit(at) and a.seenIn(&g.sim.lv)) g.pic.fx.zap(s.wait, .{ .from = mathx.centre(at), .to = mathx.centre(a.at) });
        if (!g.sim.takeStatus(a, .shock)) continue;
        a.shock.start();
        g.sim.sayTakes(slot, a, shock.TAKES);
        g.pic.settleSlot(&g.sim, s.wait, .fromIndex(slot));
        if (w.struck != slot) continue;
        for (g.sim.pool.items[w.born..g.sim.pool.n], w.born..) |*half, o| {
            if (!half.alive) continue;
            half.shock = a.shock;
            half.resilience.meters.set(.shock, a.resilience.meters.get(.shock));
            g.pic.settleSlot(&g.sim, s.wait, .fromIndex(o));
        }
    }
}

/// Rolled once and scaled per body, as an area blow; each is struck as the arrow reaches its cell.
pub fn pierceHit(g: *game.Game, comptime act: skillbar.Act, pierced: bow.Pierced, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const raw = attacks.rawFor(&g.sim, act);
    for (pierced.body[0..pierced.n], pierced.step[0..pierced.n]) |id, step| {
        wound(g, id, attacks.heroScaled(&g.sim, act, raw).physical(), M.VERB, s.along(step, pierced.flight.len));
    }
    const end = pierced.flight.struck orelse return;
    switch (end) {
        .barrel, .plant => |at| smash(g, at, M.VERB, s),
        .body => {},
    }
}

pub fn burstHit(g: *game.Game, comptime act: skillbar.Act, hit: bow.Hit, impact: P, s: Stroke) void {
    const M = skillbar.Act.elemental(act);
    const direct: ?u16 = switch (hit) {
        .body => |id| id,
        .barrel, .plant => null,
    };
    areaHit(g, act, impact, M.burst(&g.sim.lv, s.from, impact, g.sim.wider()), s, direct, hit != .body);
    boilUnder(g, act, impact, s.wait);
}

pub fn boilUnder(g: *game.Game, comptime act: skillbar.Act, at: P, wait: f32) void {
    if (comptime act.element() != .fire) return;
    const M = skillbar.Act.elemental(act);
    fireLands(g, at, if (comptime act.bursts()) M.BLAST + g.sim.wider() else 0, M.KINDLE, wait);
}

pub fn fireLands(g: *game.Game, at: P, range: i32, kindle: fire.Kindle, wait: f32) void {
    g.pic.holdFire(&g.sim.lv, wait);
    const fired = rewards.fireRound(&g.sim, at, range, kindle);
    if (fired.steeped != null or fired.caught) g.cloud.hold(wait);
}

/// `direct` is struck even where the burst spreads no further, as a body in deep water.
pub fn areaHit(g: *game.Game, comptime act: skillbar.Act, at: P, area: areas.Burst, s: Stroke, direct: ?u16, prop: bool) void {
    var struck = skills.foesIn(g, area);
    if (direct) |id| if (!struck.has(id)) struck.push(id);
    g.pic.fx.burst(s.wait, .{ .at = at, .area = area, .element = act.element().? });
    const raw = if (direct != null) attacks.rawFor(&g.sim, act) else attacks.rawElementFor(&g.sim, act);
    if (prop) smash(g, at, barrelVerb(act), s);
    for (struck.slice()) |id| {
        var hit = raw;
        if (direct != id) hit.physical = 0;
        skillHit(g, id, attacks.heroScaled(&g.sim, act, hit), act, s);
    }
    if (comptime act.element() == .cold) coldLands(g, &area, s.wait);
}

pub fn coldLands(g: *game.Game, area: *const areas.Burst, wait: f32) void {
    g.pic.holdFlames(&g.sim.lv, wait);
    const doused = rewards.douseRound(&g.sim, area);
    _ = rewards.freezeRound(&g.sim, area);
    var each = doused.iterator(.{});
    while (each.next()) |slot| g.pic.settleSlot(&g.sim, wait, .fromIndex(slot));
}
pub fn smash(g: *game.Game, p: P, comptime verb: []const u8, s: Stroke) void {
    if (g.sim.lv.at(p).bursts()) return burstPlant(g, p, s);
    const gold = rewards.barrelLoot(&g.sim, p) orelse return;
    g.sim.log.push(.loot, "{s} " ++ verb ++ BARREL_DROPS, .{ g.sim.name.text(), gold });
    g.pic.strike(&g.sim, g.cloud, .{ .barrel = p }, s);
}

const BARREL_DROPS = " the barrel. It drops {d} gold.";

pub fn burstPlant(g: *game.Game, p: P, s: Stroke) void {
    const was = g.sim.lv.at(p);
    if (!gas.burst(&g.sim.lv, p)) return;
    g.sim.sayAt(p, "The glowbulb bursts, leaving a cloud of " ++ gas.HEALING_NAME ++ "!", .{});
    g.cloud.hold(s.wait);
    g.pic.burstPlant(&g.sim.lv, p, was, s.wait);
    if (g.sim.lv.isLit(p)) g.pic.fx.puff(s.wait, .{ .at = mathx.centre(p), .ink = look.gasInk(.healing), .motes = fx.BURST_WISPS });
}

pub fn openChest(g: *game.Game, p: P) bool {
    if (g.sim.pool.get(g.sim.lv.who(p))) |a| if (a.disguised) {
        unmaskMimic(g, a, 0);
        g.sim.log.push(.danger, CHEST_IS, .{actor.row(a.kind).name});
        return true;
    };
    switch (rewards.openChest(&g.sim, p)) {
        .opened => return true,
        .not_closed => return false,
        .ground_full => return groundFull(g),
    }
}

pub fn groundRoom(g: *game.Game) bool {
    return rewards.groundRoom(&g.sim) or groundFull(g);
}

fn groundFull(g: *game.Game) bool {
    g.character.message.say("Ground full", .{});
    return false;
}

pub fn collectGold(g: *game.Game, at: P) void {
    const coins = rewards.collectGold(&g.sim, at) orelse return;
    g.pic.gold_taken = coins;
}

pub fn arrive(g: *game.Game, at: P) void {
    if (rewards.coinDrop(&g.sim, at)) collectGold(g, at);
    rewards.noticeItems(&g.sim, at);
}

pub fn wound(g: *game.Game, id: u16, raw: attacks.Roll, comptime verb: []const u8, s: Stroke) void {
    woundAt(g, .fromInt(id), raw, verb, s, .chosen, null);
}

pub fn reaction(g: *game.Game, id: u16, raw: attacks.Roll, comptime verb: []const u8, s: Stroke, source: u16, flight: ?bow.Flight) void {
    woundAt(g, .fromInt(id), raw, verb, s, .{ .reaction = .fromInt(source) }, flight);
}

/// A blow on a mimic still posing as its chest flings it open, to act from the next turn; its chest stays drawn where it stands until the blow lands.
fn reveal(g: *game.Game, target: actor.ActorId, s: Stroke) void {
    const a = g.sim.pool.get(target.value) orelse return;
    if (!a.disguised) return;
    unmaskMimic(g, a, s.wait);
    a.waits = true;
    g.sim.sayAs(.danger, a.at, CHEST_IS, .{actor.row(a.kind).name});
    g.pic.masked.set(target.slot().index);
}

const CHEST_IS = "The chest is a {s}!";

fn unmaskMimic(g: *game.Game, a: *actor.Actor, wait: f32) void {
    a.unmask(&g.sim.lv);
    g.pic.shimmerBody(wait, a);
}

fn woundAt(g: *game.Game, target: actor.ActorId, raw: attacks.Roll, comptime verb: []const u8, s: Stroke, origin: chronicle.AttackOrigin, flight: ?bow.Flight) void {
    var roll = raw;
    const struck = g.sim.pool.get(target.value) orelse return;
    if (!struck.foe()) return;
    roll.hit_checked = roll.hit_checked or struck.disguised;
    reveal(g, target, s);
    const outcome = attacks.resolve(&g.sim, target, roll, origin) orelse return;
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
    const slot = target.slot().index;
    if (h.lethal or !g.sim.pool.items[slot].veiled()) {
        g.sim.sayAs(.damage, hit.at, "{s} " ++ verb ++ " the {s}{s} for {d}.{s}", .{ g.sim.name.text(), name, if (hit.roll.crit) " critically" else "", hit.roll.dmg, if (hit.culled) CUT_DOWN else deathNote(h) });
        if (hit.bled) |said| g.sim.sayAt(hit.at, "The {s} {s}!", .{ name, said });
        if (hit.stunned) g.sim.sayFoeTakes(&g.sim.pool.items[slot], turn_clock.STUNNED);
        inline for (attacks.IMBUED) |M| if (hit.imbued.contains(M.AILMENT)) g.sim.sayFoeTakes(&g.sim.pool.items[slot], M.TAKES);
    }
    const impact = landedImpact(g, target.value, hit.at, h);
    const recovery = recoverLife(g, hit.recovery);
    g.pic.recordAttack(&g.sim, g.cloud, origin, s, flight, .{ .hit = impact }, recovery);
}

pub fn heal(g: *game.Game, n: i32, wait: f32) void {
    const after = recoverLife(g, n) orelse return;
    g.pic.recordRecovery(&g.sim, wait, after);
}

fn recoverLife(g: *game.Game, n: i32) ?fx.After {
    if (!g.sim.recoverLife(n)) return null;
    return g.pic.heroAfter(&g.sim);
}

fn slain(g: *game.Game, id: u16) ?fx.After {
    const killed = g.sim.pool.items[actor.Pool.slot(id)];
    fell(g, id);
    if (killed.kind.ally() or killed.raider) return null;
    return recoverLife(g, g.sim.inventory.gear.killRecovery());
}

fn landBlow(g: *game.Game, id: u16, h: Hurt) fx.After {
    const after = afterBlow(g, id, h);
    if (h.lethal) fell(g, id);
    return after;
}

fn landedImpact(g: *game.Game, id: u16, at: P, h: Hurt) fx.ActorImpact {
    return .{ .slot = actor.ActorId.fromInt(id).slot(), .at = at, .lethal = h.lethal, .after = landBlow(g, id, h) };
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
    tactics_exec.landed(g, other);
    return .fromInt(other);
}

pub fn fell(g: *game.Game, id: u16) void {
    const target = actor.ActorId.fromInt(id);
    g.pic.beforeDeath(&g.sim, target);
    const death = rewards.defeat(&g.sim, target);
    g.pic.recordDeath(&g.sim, target, death);
}

pub fn scare(g: *game.Game, fallen: usize) void {
    const frightened = rewards.scare(&g.sim, g.sim.pool.items[fallen].at);
    g.pic.recordFright(&g.sim, .fromIndex(fallen), frightened);
}

fn heroDies(g: *game.Game) void {
    g.sim.log.push(.danger, "{s} dies.", .{g.sim.name.text()});
    g.died_in = std.meta.activeTag(g.mode);
    g.mode = .dead;
    game.epitaph.inscribe(g);
}

/// The hero's action is spent: a turn passes unless haste spares it.
pub fn endTurn(g: *game.Game) void {
    if (!hastened(g)) passTurn(g);
}

/// As a free action: nothing ages, no foe acts.
fn hastened(g: *game.Game) bool {
    const h = g.sim.heroActor() orelse return false;
    if (!g.sim.hastens()) return false;
    g.sim.unsaved = true;
    for (g.sim.pool.slice()) |*a| a.waits = false;
    game.castSight(g, h.at);
    g.sim.log.say("{s} acts with haste: no turn passes.", .{g.sim.name.text()});
    return true;
}

pub fn passTurn(g: *game.Game) void {
    const h = g.sim.heroActor() orelse return;
    defer g.sim.finishTurn();
    beginTurn(g, h.at);
    heroAfterAction(g);
    if (g.mode == .dead) return;
    spreadGasAndAdvanceClocks(&g.sim);
    if (!flyBolts(g)) return;
    if (!orderedFoeTurns(g)) return;
    waitingNewbornTurns(g);
    finishTurnPicture(g);
    game.talking.afterTurn(g);
}

fn beginTurn(g: *game.Game, from: P) void {
    g.sim.unsaved = true;
    if (g.sim.clock.turn()) g.sim.days +|= 1;
    tactics_exec.startTurn(&g.sim);
    tactics_exec.bideTurn(g);
    const lying = g.sim.ground.lying();
    _ = fire.turn(&g.sim.lv, &g.sim.rng, g.sim.rainNow(), &lying);
    _ = ice.turn(&g.sim.lv);
    skills.recover(g);
    for (&g.sim.cooldown.values) |*c| c.* -|= 1;
    game.castSight(g, from);
    g.sim.flowed = false;
    raiders(g);
    foes.orderFoes(&g.sim, from);
}

fn raiders(g: *game.Game) void {
    const w = g.sim.map orelse return;
    const nd = &w.node[g.sim.node];
    const door = nd.raidDoor() orelse return;
    const r = nd.plan.procgen.raid;
    const now = g.sim.clock.since(g.sim.days);
    for (0..atlas.raid.arriving(r, game.rollOf(g.sim.seed, g.sim.node), now -| day.TURN_MINUTES, now)) |_| {
        if (!tactics_exec.canRise(g, atlas.raid.RAIDER)) return;
        const at = atlas.landing(&g.sim.lv, door, &.{}) orelse return;
        var body = actor.Actor.of(atlas.raid.RAIDER, at);
        body.raider = true;
        const id = tactics_exec.rise(g, body, tactics_exec.spentSlot(g), g.pic.lead orelse 0);
        g.sim.sayAt(at, "A {s} raider comes in from the dark.", .{actor.row(atlas.raid.RAIDER).name});
        tactics_exec.landed(g, id);
    }
}

fn heroAfterAction(g: *game.Game) void {
    wearHero(g);
    harmAfter(g, g.sim.hero, g.sim.stepped);
    g.sim.stepped = false;
}

fn spreadGasAndAdvanceClocks(sim: *game.simulation.Simulation) void {
    gas.turn(&sim.lv, &sim.rng);
    for (sim.pool.slice()) |*a| {
        if (a.alive and !a.kind.hero() and !(a.waits and actor.row(a.kind).disguised)) a.clock.pass(actor.row(a.kind).pace);
    }
}

fn orderedFoeTurns(g: *game.Game) bool {
    for (g.sim.order[0..g.sim.order_n]) |id| {
        const i = actor.Pool.slot(id);
        if (g.sim.pool.items[i].waits) continue;
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
        const a = &g.sim.pool.items[i];
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
    inline for (comptime std.enums.values(game.simulation.Tick)) |t| switch (t) {
        .gassed => gasTick(g, id, .gassed, .{ .hero = "The " ++ gas.NAME ++ " eats at {s} for {d}." }),
        .scalded => gasTick(g, id, .scalded, .{ .hero = "The " ++ gas.STEAM_NAME ++ " scalds {s} for {d}." }),
        .healed => gasHeal(g, id),
        .scorched => scorch(g, id),
        .burned => burnHarm(g, id),
        .bled => bleedHarm(g, id, moved or g.sim.displaced.isSet(actor.Pool.slot(id))),
        .worn => {},
    };
}

fn gasTick(g: *game.Game, id: u16, comptime tick: game.simulation.Tick, comptime said: Said) void {
    const a = g.sim.pool.get(id) orelse return;
    const kind = comptime tick.gas().?;
    if (g.sim.lv.volumeAt(kind, a.at) == 0 or ranAlready(g, id, tick)) return;
    const harm = if (kind == .steam) gas.scald(g.sim.combatStats(a).elements) else gas.harm(a.max);
    const dmg = masked(g, id, harm);
    if (dmg == 0) return;
    _ = harmTick(g, id, dmg, tick, said);
}

fn masked(g: *game.Game, id: u16, dmg: i32) i32 {
    const share = if (id == g.sim.hero) std.math.clamp(g.sim.inventory.gear.sum(.masked), 0, mathx.PERCENT) else 0;
    if (share == 0 or dmg <= 0) return dmg;
    return @intCast(mathx.percentRound(@as(i64, dmg) * (mathx.PERCENT - share), &g.sim.rng));
}

fn gasHeal(g: *game.Game, id: u16) void {
    const a = g.sim.pool.get(id) orelse return;
    if (g.sim.lv.volumeAt(comptime game.simulation.Tick.healed.gas().?, a.at) == 0 or ranAlready(g, id, .healed) or !a.hurt()) return;
    const n = a.heal(gas.heal(a.max));
    if (id == g.sim.hero) g.sim.log.push(.recovery, "The " ++ gas.HEALING_NAME ++ " mends {s} for {d}.", .{ g.sim.name.text(), n });
    g.pic.owe(.fromInt(id), .healed, g.pic.afterOf(&g.sim, .fromIndex(actor.Pool.slot(id))));
}

fn scorch(g: *game.Game, id: u16) void {
    const a = g.sim.pool.get(id) orelse return;
    if (!g.sim.lv.burning(a.at) or ranAlready(g, id, .scorched)) return;
    const caught = g.sim.igniteFresh(actor.Pool.slot(id), a, fire.CATCH);
    const dmg = fire.scorch(g.sim.combatStats(a).elements);
    if (dmg > 0) {
        _ = harmTick(g, id, dmg, .scorched, .{ .hero = "The " ++ fire.NAME ++ " scorch {s} for {d}.", .foe = "The " ++ fire.NAME ++ " scorch the {s} for {d}." });
    } else if (caught) g.pic.recordWear(&g.sim, .fromInt(id));
}

/// Mark a tick consumed; split halves inherit the parent's consumed ticks.
fn ranAlready(g: *game.Game, id: u16, comptime tick: game.simulation.Tick) bool {
    const r = &g.sim.ran[actor.Pool.slot(id)];
    defer r.insert(tick);
    return r.contains(tick);
}

pub fn burnHarm(g: *game.Game, id: u16) void {
    const a = g.sim.pool.get(id) orelse return;
    if (ranAlready(g, id, .burned) or a.burn.turns == 0) return;
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

const Said = struct { hero: []const u8, foe: ?[]const u8 = null, torn: bool = false };

fn harmTick(g: *game.Game, id: u16, dmg: i32, comptime owed: game.simulation.Tick, comptime said: Said) Hurt {
    const a = g.sim.pool.get(id).?;
    const kind = a.kind;
    const before = a.hp;
    const h = game.hurt(g, .fromInt(id), dmg);
    const hero = id == g.sim.hero;
    const name = actor.row(kind).name;
    if (hero) {
        g.sim.log.push(.danger, said.hero, .{ g.sim.name.text(), h.dmg });
        g.sim.chronicle.note(.{ .hurt = .{ .by = comptime owed.source().?, .dmg = h.dmg, .before = before, .torn = said.torn } });
    } else if (comptime said.foe) |line| {
        g.sim.sayOf(a, line ++ "{s}", .{ name, h.dmg, deathNote(h) });
    } else if (h.lethal) g.sim.sayOf(a, "The {s} dies.", .{name});
    var debt = game.presentation.Harm{ .kill = h.lethal, .after = afterBlow(g, id, h) };
    if (h.lethal) {
        if (hero) heroDies(g) else debt.recovery = slain(g, id);
    }
    g.pic.owe(.fromInt(id), owed, debt);
    return h;
}

const Worn = struct { held: bool = false, skips: bool = false, afflicted: actor.Afflicted = .initEmpty() };

fn wearTurn(g: *game.Game, id: u16) Worn {
    const a = g.sim.pool.get(id) orelse return .{};
    if (ranAlready(g, id, .worn) or !a.wearsAny()) return .{};
    const w = Worn{ .held = a.pin.hold(), .skips = a.chill.turns > 0 and a.chill.skip(), .afflicted = a.wearAfflictions() };
    g.pic.recordWear(&g.sim, .fromInt(id));
    return w;
}

/// The hero's own action is spent: so is a turn of what afflicts, holds or chills it; a chill's skipped action is its next turn.
fn wearHero(g: *game.Game) void {
    const h = g.sim.heroActor() orelse return;
    if (!wearTurn(g, g.sim.hero).skips) return;
    h.clock.delay(turn_clock.TURN);
    g.sim.log.say("The cold slows {s}.", .{g.sim.name.text()});
}

fn foeTurn(g: *game.Game, id: u16) void {
    const body = g.sim.pool.get(id) orelse return;
    const braced = body.braced;
    body.braced = null;
    const stalled = body.clock.stalled;
    const worn = wearTurn(g, id);
    if (braced != null) g.pic.recordWear(&g.sim, .fromInt(id));
    if (body.disguised) return;
    body.sweep_in -|= 1;
    body.ready_in -|= 1;
    if (body.stuck) {
        body.stuck = false;
        g.pic.recordWear(&g.sim, .fromInt(id));
        return;
    }
    const held = worn.held;
    if (worn.skips or stalled) return;
    const foe = g.sim.pool.get(id) orelse return;
    const hero = g.sim.heroActor() orelse return;
    const row = actor.row(foe.kind);
    const afflictions = worn.afflicted;
    const sight = blind.sight(afflictions.contains(.blind), row.sight);
    if (row.allied) return allyTurn(g, id, held, afflictions, sight);
    if (!foe.awake) {
        if (!fov.sees(&g.sim.lv, foe.at, hero.at, @max(1, sight - g.sim.inventory.gear.sum(.stillness)))) return;
        foe.awake = true;
        g.pic.turnLater(.fromInt(id), hero.at.x - foe.at.x);
        if (!foe.submerged) g.sim.sayAt(foe.at, "A {s} notices {s}.", .{ row.name, g.sim.name.text() });
        return;
    }
    const groping = afflictions.contains(.blind) and mathx.dist(foe.at, hero.at) > sight;
    if (foe.fright > 0) {
        foe.fright -= 1;
        g.pic.recordWear(&g.sim, .fromInt(id));
        if (!groping) {
            const escape = if (held) null else fleeWay(g, foe.at, id, hero.at);
            if (escape) |direction| {
                foeStep(g, id, foe.at, direction, afflictions);
            } else if (foes.besideWay(&g.sim, foe.at, hero.at)) |direction| {
                _ = reach(g, id, row, direction.delta().x, null, afflictions);
            }
        }
        if (foe.fright == 0 and foe.alive) g.sim.sayAt(foe.at, "The {s} stops running.", .{row.name});
        return;
    }
    if (groping) return;
    if (row.movement == .swimming) return swimTurn(g, id, row, held, afflictions);
    if (row.charges) |charge| if (chargeTurn(g, id, row, charge, braced, held, afflictions, sight)) return;
    if (row.hooks) |hook| if (hookTurn(g, id, row, hook, braced, afflictions, sight)) return;
    if (row.keeps > 0) return keepAway(g, id, row, held, afflictions, sight);
    if (row.ranged) |ranged| {
        const gap = mathx.dist(foe.at, hero.at);
        if (!held and backOff(g, id, ranged.retreat, afflictions)) return;
        if (bow.clearShot(&g.sim.lv, foe.at, hero.at, ranged.range, g.sim.hero)) |flight| {
            _ = reach(g, id, row, hero.at.x - foe.at.x, flight, afflictions);
            return;
        }
        if (!held and gap > ranged.retreat) closeIn(g, id, ranged.retreat, afflictions);
        return;
    }
    if (row.blow == .strike and foes.besideWay(&g.sim, foe.at, hero.at) == null) {
        if (foes.besideOf(&g.sim, foe.at, .ally)) |ally| return bodyStrike(g, id, ally, afflictions, null);
    }
    var flitted: ?mathx.Dir = null;
    if (!held and row.flits and g.sim.rng.chance(actor.FLIT)) {
        flitted = actor.flit(&g.sim.lv, foe.at, id, g.sim.hero, &g.sim.rng);
    }
    const direction = flitted orelse foeWay(g, foe.at, id, hero.at) orelse return;
    const to = foe.at.add(direction.delta());
    if (held and !to.eq(hero.at)) return;
    if (!to.eq(hero.at)) return foeStep(g, id, foe.at, direction, afflictions);
    _ = reach(g, id, row, direction.delta().x, null, afflictions);
}

fn brace(g: *game.Game, id: u16, d: mathx.Dir, comptime said: []const u8) void {
    const r = g.sim.pool.get(id).?;
    r.braced = d;
    g.pic.recordWear(&g.sim, .fromInt(id));
    g.pic.turnLater(.fromInt(id), d.delta().x);
    g.sim.sayOf(r, said, .{actor.row(r.kind).name});
}

/// Braces at a hero on an open straight line in reach; the turn after, rushes the braced way whatever the hero did.
fn chargeTurn(g: *game.Game, id: u16, row: actor.Row, c: actor.Charge, braced: ?mathx.Dir, held: bool, af: actor.Afflicted, sight: i32) bool {
    if (held) return false;
    if (braced) |d| {
        rush(g, id, row, c, d, af);
        return true;
    }
    const hero = foes.braceTarget(&g.sim, id, c.range, sight) orelse return false;
    const d = windup.openTo(&g.sim.lv, g.sim.pool.get(id).?.at, hero, c.range) orelse return false;
    brace(g, id, d, "The {s} braces to charge.");
    return true;
}

/// Runs until the next cell is blocked: a hero there takes the charge's blow; anything else leaves it stuck.
fn rush(g: *game.Game, id: u16, row: actor.Row, c: actor.Charge, d: mathx.Dir, af: actor.Afflicted) void {
    const r = g.sim.pool.get(id).?;
    r.ready_in = c.every;
    var at = r.at;
    var cells: i32 = 0;
    while (cells < c.rush and g.sim.lv.stepOk(at, d, id)) : (cells += 1) at = at.add(d.delta());
    g.pic.turnLater(.fromInt(id), d.delta().x);
    if (cells > 0) {
        g.sim.pool.move(&g.sim.lv, id, at);
        tactics_exec.entered(g, id);
    }
    const crab = g.sim.pool.get(id) orelse return;
    const next = at.add(d.delta());
    if (cells < c.rush and g.sim.lv.passOk(at, d)) {
        const w = g.sim.lv.who(next);
        if (w != grid.NO_ONE and w == g.sim.hero) {
            var rammed = row;
            rammed.blow = .{ .strike = c.blow };
            _ = reach(g, id, rammed, d.delta().x, null, af);
            return;
        }
        if (g.sim.pool.get(w) != null) {
            const hit = bodyBlow(g, id, w, c.blow, c.blow.verb, af.contains(.enfeeble), false);
            g.pic.owe(.fromInt(id), .struck, .{ .at = next, .impact = if (hit) |a| .{ .actor = a } else null });
        } else if (smashedBy(g, next, row)) |hit| g.pic.owe(.fromInt(id), .struck, .{ .at = next, .impact = hit });
    }
    crab.stuck = true;
    g.pic.recordWear(&g.sim, .fromInt(id));
    g.sim.sayOf(crab, "The {s} is stuck fast.", .{row.name});
}

/// Braces at a hero on a straight line in reach; the turn after, flings its hook the braced way.
fn hookTurn(g: *game.Game, id: u16, row: actor.Row, hk: actor.Hook, braced: ?mathx.Dir, af: actor.Afflicted, sight: i32) bool {
    if (braced) |d| {
        fling(g, id, row, hk, d, af);
        return true;
    }
    const hero = foes.braceTarget(&g.sim, id, hk.range, sight) orelse return false;
    const r = g.sim.pool.get(id).?;
    const d = mathx.lineDir(r.at, hero) orelse return false;
    if (!windup.lane(&g.sim.lv, r.at, d, hk.range).has(hero)) return false;
    brace(g, id, d, "The {s} swings its hook.");
    return true;
}

/// The first body or barrel down the line takes the hook; only a hero is struck and dragged a cell closer.
fn fling(g: *game.Game, id: u16, row: actor.Row, hk: actor.Hook, d: mathx.Dir, af: actor.Afflicted) void {
    const r = g.sim.pool.get(id).?;
    r.ready_in = hk.every;
    g.pic.turnLater(.fromInt(id), d.delta().x);
    var flight = bow.Flight{ .most = @intCast(hk.range) };
    for (windup.lane(&g.sim.lv, r.at, d, hk.range).slice()) |at| {
        flight.path[flight.len] = at;
        flight.len += 1;
        const w = g.sim.lv.who(at);
        if (w != grid.NO_ONE) {
            flight.struck = .{ .body = w };
            break;
        }
        if (g.sim.lv.hasBarrel(at)) {
            flight.struck = .{ .barrel = at };
            break;
        }
    }
    const caught = flight.struck orelse {
        g.sim.sayOf(r, "The {s}'s hook catches nothing.", .{row.name});
        return g.pic.recordFoeAttack(.fromInt(id), .miss, flight);
    };
    switch (caught) {
        .body => |w| if (w == g.sim.hero) {
            var hooked = row;
            hooked.blow = .{ .strike = hk.blow };
            hooked.ranged = .{ .range = hk.range, .retreat = 0 };
            if (reach(g, id, hooked, d.delta().x, flight, af) and g.mode != .dead) shove(g, id, d.opposite(), "{s} is dragged closer.");
            return;
        } else {
            const a = g.sim.pool.get(w).?;
            g.sim.sayOf(a, "The {s}'s hook catches on the {s}.", .{ row.name, actor.row(a.kind).name });
        },
        .barrel, .plant => |p| g.sim.sayAt(p, "The {s}'s hook catches on the barrel.", .{row.name}),
    }
    g.pic.recordFoeAttack(.fromInt(id), .miss, flight);
}

/// A firebolt at the hero along a clear shot, once its last has come down; the turn after it moves.
fn hurlerTurn(g: *game.Game, id: u16, hu: actor.Hurl, held: bool, af: actor.Afflicted) bool {
    const r = g.sim.pool.get(id).?;
    if (r.bolt == null and r.ready_in == 0 and hurl(g, id, hu)) return true;
    return !held and r.ready_in > 0 and reposition(g, id, hu, af);
}

fn hurl(g: *game.Game, id: u16, hu: actor.Hurl) bool {
    const r = g.sim.pool.get(id).?;
    const hero = g.sim.heroAt().?;
    if (mathx.adjacent(r.at, hero)) return false;
    _ = bow.clearShot(&g.sim.lv, r.at, hero, hu.range, g.sim.hero) orelse return false;
    const b = firebolt.Bolt.aimed(r.at, hero, hu.range);
    r.bolt = b;
    r.ready_in = hu.every;
    g.pic.turnLater(.fromInt(id), hero.x - r.at.x);
    g.sim.sayOf(r, "The {s} hurls a " ++ firebolt.NAME ++ ".", .{actor.row(r.kind).name});
    g.pic.recordHurl(.fromInt(id), b, hero, g.pic.lead orelse 0);
    return true;
}

/// A step to another cell it keeps its distance from and still has a clear shot from.
fn reposition(g: *game.Game, id: u16, projectile: actor.Hurl, afflictions: actor.Afflicted) bool {
    const direction = foes.repositionStep(&g.sim, id, projectile) orelse return false;
    const from = g.sim.pool.get(id).?.at;
    foeStep(g, id, from, direction, afflictions);
    return true;
}

/// Every firebolt in the air flies on, its thrower living or not; false once one kills the hero.
fn flyBolts(g: *game.Game) bool {
    const wait = boltsWait(g);
    for (0..g.sim.pool.n) |i| {
        const thrower = &g.sim.pool.items[i];
        const hu = actor.row(thrower.kind).hurls orelse continue;
        const was = thrower.bolt orelse continue;
        var now = was;
        const flew = firebolt.fly(&now, &g.sim.lv, hu);
        const lands = flew.stop != null;
        thrower.bolt = if (lands) null else now;
        if (lands) thrower.ready_in = @max(thrower.ready_in, hu.every);
        const kind = thrower.kind;
        const s = Stroke{ .from = was.at(), .wait = g.pic.recordBolt(&g.sim, .fromIndex(i), was, now, flew.cells, lands, wait), .element = .fire };
        const stop = flew.stop orelse continue;
        if (stop == .body or stop == .barrel) g.pic.bolt_lands = @max(g.pic.bolt_lands, s.wait);
        switch (stop) {
            .body => |w| if (!boltHits(g, kind, w, hu, s)) return false,
            .barrel => |p| if (rewards.barrelLoot(&g.sim, p)) |gold| {
                g.sim.sayAt(p, "The {s}'s " ++ firebolt.NAME ++ " smashes" ++ BARREL_DROPS, .{ actor.row(kind).name, gold });
                g.pic.strike(&g.sim, g.cloud, .{ .barrel = p }, s);
            },
            .wall, .spent => if (g.pic.litShown(&g.sim, now.at())) g.pic.fx.puff(s.wait, .{ .at = now.point(), .ink = look.FIRE }),
        }
    }
    return true;
}

/// Bolts fly once the hero's own step this turn is drawn.
fn boltsWait(g: *const game.Game) f32 {
    const lead = g.pic.lead orelse 0;
    const at = g.pic.knocked_from orelse g.sim.heroAt() orelse return lead;
    const step = g.pic.glide[actor.Pool.slot(g.sim.hero)];
    if (step.to.eq(at)) return lead;
    return @max(lead, step.toward(at, 0).left());
}

/// Fire past its fire resistance, without a dodge, on whatever body it flies into; false when that kills the hero.
fn boltHits(g: *game.Game, by: actor.Kind, id: u16, hu: actor.Hurl, s: Stroke) bool {
    reveal(g, .fromInt(id), s);
    const a = g.sim.pool.get(id) orelse return true;
    const at = a.at;
    const slot = actor.Pool.slot(id);
    const kind = a.kind;
    const thrower = actor.row(by).name;
    const dmg = damage.resisted(hu.hit.roll(&g.sim.rng), g.sim.combatStats(a).elements.get(firebolt.ELEMENT));
    const before = a.hp;
    const h = game.hurt(g, .fromInt(id), dmg);
    const hero = id == g.sim.hero;
    if (hero) {
        g.sim.log.push(.danger, "The {s}'s " ++ firebolt.NAME ++ " burns {s} for {d}.", .{ thrower, g.sim.name.text(), h.dmg });
        g.sim.chronicle.note(.{ .hurt = .{ .by = .{ .foe = by }, .dmg = h.dmg, .before = before } });
    } else if (h.lethal or !a.veiled()) g.sim.sayAt(at, "The {s}'s " ++ firebolt.NAME ++ " burns the {s} for {d}.{s}", .{ thrower, actor.row(kind).name, h.dmg, deathNote(h) });
    if (!h.lethal and h.dmg > 0) _ = g.sim.igniteFresh(slot, a, hu.burns);
    if (hero) {
        g.pic.strike(&g.sim, g.cloud, .{ .actor = .{ .slot = .fromIndex(slot), .at = at, .lethal = h.lethal, .after = afterBlow(g, id, h) } }, s);
        if (h.lethal) heroDies(g);
        return !h.lethal;
    }
    g.pic.strike(&g.sim, g.cloud, .{ .actor = landedImpact(g, id, at, h) }, s);
    return true;
}

fn allyTurn(g: *game.Game, id: u16, held: bool, af: actor.Afflicted, sight: i32) void {
    const r = g.sim.pool.get(id).?;
    if (actor.row(r.kind).posted) return guardTurn(g, id, af, sight);
    const hero = g.sim.heroAt().?;
    if (foes.besideOf(&g.sim, r.at, .foe)) |foe| return bodyStrike(g, id, foe, af, null);
    if (held) return;
    if (foes.quarry(&g.sim, r.at, hero, sight)) |at| {
        if (actor.approach(&g.sim.lv, r.at, id, at)) |d| return foeStep(g, id, r.at, d, af);
    }
    if (mathx.dist(r.at, hero) <= tactics.RaiseSkeleton.FOLLOW) return;
    const d = actor.chase(&g.sim.lv, r.at, id, foes.flowTo(&g.sim, hero)) orelse return;
    foeStep(g, id, r.at, d, af);
}

fn guardTurn(g: *game.Game, id: u16, af: actor.Afflicted, sight: i32) void {
    const r = g.sim.pool.get(id).?;
    var near = grid.Nearest{ .from = r.at, .reach = @min(sight, actor.row(r.kind).ranged.?.range) };
    var shot: ?bow.Flight = null;
    for (g.sim.pool.constSlice(), 0..) |a, i| {
        if (!a.livingFoe() or a.veiled() or !fov.sees(&g.sim.lv, r.at, a.at, near.reach)) continue;
        const flight = bow.clearShot(&g.sim.lv, r.at, a.at, near.reach, actor.Pool.idOf(i)) orelse continue;
        near.offer(a.at);
        if (near.best) |b| if (b.eq(a.at)) {
            shot = flight;
        };
    }
    const at = near.best orelse return;
    bodyStrike(g, id, g.sim.lv.who(at), af, shot);
}

fn bodyStrike(g: *game.Game, id: u16, target: u16, af: actor.Afflicted, flight: ?bow.Flight) void {
    const r = g.sim.pool.get(id).?;
    const s = actor.row(r.kind).blow.strike;
    const at = g.sim.pool.get(target).?.at;
    g.pic.turnLater(.fromInt(id), at.x - r.at.x);
    const impact: ?fx.Impact = if (bodyBlow(g, id, target, s, s.verb, af.contains(.enfeeble), false)) |hit| .{ .actor = hit } else null;
    g.pic.owe(.fromInt(id), .struck, .{ .at = at, .impact = impact });
    g.pic.owe(.fromInt(id), .arrow, flight);
}

/// Only a sweep rolls `s.stuns`.
fn bodyBlow(g: *game.Game, by: u16, target: u16, s: actor.Strike, verb: []const u8, weak: bool, stuns: bool) ?fx.ActorImpact {
    const striker = g.sim.pool.get(by).?;
    const a = g.sim.pool.get(target).?;
    const who = actor.row(striker.kind).name;
    const name = actor.row(a.kind).name;
    const dmg = (attacks.foeBlow(&g.sim, striker, a, s, weak) orelse {
        g.sim.sayOf(a, "The {s} misses the {s}.", .{ who, name });
        return null;
    }).dealt;
    const at = a.at;
    const stunned = stuns and dmg > 0 and dmg < a.hp and g.sim.procStatus(a, .stun, s.stuns);
    if (stunned) {
        if (!a.waits and !g.sim.ran[actor.Pool.slot(target)].contains(.worn)) a.clock.stunBeforeAction(actor.row(a.kind).pace) else a.clock.stun();
    }
    const h = game.hurt(g, .fromInt(target), dmg);
    g.sim.sayOf(a, "The {s} {s} the {s} for {d}.{s}", .{ who, verb, name, h.dmg, deathNote(h) });
    if (stunned) g.sim.sayFoeTakes(a, turn_clock.STUNNED);
    return landedImpact(g, target, at, h);
}

fn swimTurn(g: *game.Game, id: u16, row: actor.Row, held: bool, af: actor.Afflicted) void {
    const r = g.sim.pool.get(id).?;
    const h = g.sim.heroActor().?;
    if (foes.besideWay(&g.sim, r.at, h.at)) |d| {
        r.submerged = false;
        _ = reach(g, id, row, d.delta().x, null, af);
        return;
    }
    if (held) return;
    const d = actor.swim(&g.sim.lv, r.at, r.kind, h.at) orelse return;
    foeStep(g, id, r.at, d, af.intersectWith(.initOne(.maim)));
}

fn keepAway(g: *game.Game, id: u16, row: actor.Row, held: bool, af: actor.Afflicted, sight: i32) void {
    if (row.mends) |m| if (mend(g, id, m, sight)) return;
    if (row.net) |n| if (throwNet(g, id, n)) return;
    if (row.hurls) |hu| if (hurlerTurn(g, id, hu, held, af)) return;
    if (!held and backOff(g, id, row.keeps, af)) return;
    const r = g.sim.pool.get(id).?;
    if (foes.besideWay(&g.sim, r.at, g.sim.heroAt().?)) |d| {
        _ = reach(g, id, row, d.delta().x, null, af);
        return;
    }
    if (!held) closeIn(g, id, row.keeps, af);
}

fn backOff(g: *game.Game, id: u16, keep: i32, af: actor.Afflicted) bool {
    const r = g.sim.pool.get(id).?;
    const hero = g.sim.heroAt().?;
    if (mathx.dist(r.at, hero) > keep) return false;
    const d = fleeWay(g, r.at, id, hero) orelse return false;
    foeStep(g, id, r.at, d, af);
    return true;
}

fn closeIn(g: *game.Game, id: u16, keep: i32, af: actor.Afflicted) void {
    const r = g.sim.pool.get(id).?;
    const hero = g.sim.heroAt().?;
    const d = actor.chase(&g.sim.lv, r.at, id, foes.flowTo(&g.sim, hero)) orelse return;
    if (mathx.dist(r.at.add(d.delta()), hero) <= keep) return;
    foeStep(g, id, r.at, d, af);
}

/// Thrown along a clear flight at a hero not already held; a dodge or resistance spends it all the same.
fn throwNet(g: *game.Game, id: u16, net: actor.Net) bool {
    const result = foes.throwNet(&g.sim, id, net) orelse return false;
    g.pic.turnLater(.fromInt(id), result.facing_delta);
    const after = if (result.landed) g.pic.heroAfter(&g.sim) else null;
    g.pic.recordFoeAttack(.fromInt(id), .{ .snare = after }, result.flight);
    return true;
}

fn mend(g: *game.Game, id: u16, healing: actor.Mend, sight: i32) bool {
    const result = foes.mend(&g.sim, id, healing, sight) orelse return false;
    const after = if (result.slot) |slot| g.pic.afterOf(&g.sim, slot) else null;
    g.pic.owe(.fromInt(id), .mended, .{ .slot = result.slot, .after = after });
    return true;
}

fn foeStep(g: *game.Game, id: u16, from: P, chosen: mathx.Dir, af: actor.Afflicted) void {
    const d = if (confusion.strays(af.contains(.confusion), &g.sim.rng)) actor.stumble(&g.sim.lv, from, id, &g.sim.rng) orelse chosen else chosen;
    g.pic.turnLater(.fromInt(id), d.delta().x);
    g.sim.pool.move(&g.sim.lv, id, from.add(d.delta()));
    _ = g.sim.pool.get(id).?.limp(af);
    tactics_exec.entered(g, id);
}

fn foeWay(g: *game.Game, at: P, id: u16, hero: P) ?mathx.Dir {
    return foes.besideWay(&g.sim, at, hero) orelse actor.chase(&g.sim.lv, at, id, foes.flowTo(&g.sim, hero));
}

fn fleeWay(g: *game.Game, at: P, id: u16, hero: P) ?mathx.Dir {
    return actor.flee(&g.sim.lv, at, id, foes.flowTo(&g.sim, hero));
}

/// Whether a strike landed on the hero; afflictions are those worn under this action.
fn reach(g: *game.Game, attacker_id: u16, row: actor.Row, facing_delta: i32, flight: ?bow.Flight, afflictions: actor.Afflicted) bool {
    const attacker = actor.ActorId.fromInt(attacker_id);
    const attacker_slot = attacker.slot();
    g.pic.turnLater(attacker, facing_delta);
    const kind = g.sim.pool.items[attacker_slot.index].kind;
    switch (row.blow) {
        .strike => |blow| {
            const sweeps = sweepReady(g, attacker_id, row);
            const weak = afflictions.contains(.enfeeble);
            if (sweeps) sweepRound(g, attacker_id, row, blow, weak);
            const verb = if (sweeps) actor.SWEEP_VERB else blow.verb;
            const outcome = attacks.strikeHero(&g.sim, attacker, blow, weak);
            const hit = switch (outcome) {
                .blocked, .dodged => {
                    g.sim.log.say("{s} {s} the {s}.", .{ g.sim.name.text(), if (outcome == .blocked) "blocks" else "dodges", row.name });
                    g.pic.recordFoeAttack(attacker, .miss, flight);
                    if (row.ranged == null) tactics_exec.counter(g, attacker_id);
                    return false;
                },
                .hit => |hit| hit,
            };
            const harm = hit.damage;
            const hero = &g.sim.pool.items[harm.target.slot().index];
            game.presentDamage(g, harm);
            g.sim.log.push(.danger, "The {s} {s} {s} for {d}.", .{ row.name, verb, g.sim.name.text(), harm.dmg });
            g.sim.chronicle.note(.{ .hurt = .{ .by = .{ .foe = kind }, .dmg = harm.dmg, .before = hit.hp_before, .best = hit.maximum_roll } });
            if (hit.bled) |said| g.sim.log.push(.danger, "{s} {s}!", .{ g.sim.name.text(), said });
            if (hit.stunned) {
                g.sim.sayTakes(g.sim.heroSlot().?, hero, turn_clock.STUNNED);
                g.sim.chronicle.note(.{ .stunned = kind });
            }
            if (hit.chilled) g.sim.sayTakes(g.sim.heroSlot().?, hero, glacial.TAKES);
            const after = afterBlow(g, g.sim.hero, harm);
            g.pic.recordFoeAttack(attacker, if (harm.lethal) .{ .kill = after } else .{ .hurt = after }, flight);
            if (row.ranged == null) returnThorns(g, attacker_id, hero.at);
            if (harm.lethal) {
                heroDies(g);
            } else if (row.ranged == null) {
                tactics_exec.counter(g, attacker_id);
            }
            if (!harm.lethal and blow.knocks) knockHero(g, attacker_id);
            return true;
        },
        .burst => |b| {
            if (b == .gas) g.sim.chronicle.note(.burst);
            _ = g.sim.pool.damage(&g.sim.lv, attacker_id, g.sim.pool.get(attacker_id).?.hp);
            g.pic.recordFoeAttack(attacker, .{ .burst = g.pic.afterOf(&g.sim, attacker_slot) }, flight);
            fell(g, attacker_id);
            return false;
        },
    }
}

fn knockHero(g: *game.Game, by: u16) void {
    const striker = g.sim.pool.items[actor.Pool.slot(by)].at;
    const h = g.sim.heroActor() orelse return;
    shove(g, by, mathx.dirTo(striker, h.at) orelse return, "{s} is knocked back.");
}

/// The hero a cell `d`, unless held or the cell is taken or a door.
fn shove(g: *game.Game, by: u16, d: mathx.Dir, comptime said: []const u8) void {
    const h = g.sim.heroActor() orelse return;
    if (h.pin.holding()) return;
    const from = h.at;
    const to = from.add(d.delta());
    if (!g.sim.lv.vacant(to) or g.sim.lv.doorAt(to) != null) return;
    g.sim.pool.move(&g.sim.lv, g.sim.hero, to);
    g.sim.travel = null;
    g.sim.flowed = false;
    g.sim.heroMoved();
    game.castSight(g, to);
    g.sim.log.say(said, .{g.sim.name.text()});
    g.pic.recordKnock(.fromInt(by), from, to);
}

fn returnThorns(g: *game.Game, id: u16, from: P) void {
    const amount = g.sim.heroAttrs().thorns;
    if (amount <= 0) return;
    const a = g.sim.pool.get(id) orelse return;
    if (!mathx.adjacent(from, a.at)) return;
    const dmg = attrs.armoured(g.sim.combatStats(a).armour, amount, &g.sim.rng);
    if (dmg <= 0) return;
    const at = a.at;
    const kind = a.kind;
    const h = game.hurt(g, .fromInt(id), dmg);
    const after = afterBlow(g, id, h);
    g.sim.chronicle.note(.{ .dealt = .{ .to = kind, .killed = h.lethal, .origin = .{ .reaction = .fromInt(id) } } });
    g.sim.sayAs(.damage, at, "{s}'s thorns hurt the {s} for {d}.{s}", .{ g.sim.name.text(), actor.row(kind).name, h.dmg, deathNote(h) });
    const recovery = if (h.lethal) slain(g, id) else null;
    g.pic.owe(.fromInt(id), .thorns, .{ .kill = h.lethal, .after = after, .recovery = recovery });
}

fn sweepReady(g: *game.Game, id: u16, row: actor.Row) bool {
    const a = g.sim.pool.get(id).?;
    if (row.sweep_every == 0 or a.sweep_in > 0) return false;
    a.sweep_in = row.sweep_every;
    return true;
}

/// Every body and barrel round the sweeper but the hero, snapshot before any blow so newborn halves are spared.
fn sweepRound(g: *game.Game, id: u16, row: actor.Row, s: actor.Strike, weak: bool) void {
    const from = g.sim.pool.get(id).?.at;
    const cells = actor.sweep(&g.sim.lv, from);
    const struck = occupants(actor.SWEEP_CELLS, &g.sim.lv, &cells);
    var swept = game.presentation.Swept{};
    for (cells.slice(), struck[0..cells.n]) |p, w| {
        if (w == g.sim.hero) continue;
        const hit: fx.Impact = if (w != grid.NO_ONE) .{ .actor = bodyBlow(g, id, w, s, actor.SWEEP_VERB, weak, true) orelse continue } else smashedBy(g, p, row) orelse continue;
        _ = mathx.push(fx.Impact, &swept.hit, &swept.n, hit);
    }
    g.pic.owe(.fromInt(id), .swept, swept);
}

fn smashedBy(g: *game.Game, p: P, by: actor.Row) ?fx.Impact {
    const gold = rewards.barrelLoot(&g.sim, p) orelse return null;
    g.sim.sayAt(p, "The {s} smashes" ++ BARREL_DROPS, .{ by.name, gold });
    return .{ .barrel = p };
}
