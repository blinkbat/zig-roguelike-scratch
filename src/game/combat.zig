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
const attrs = @import("../play/attrs.zig");
const burning = @import("../play/burning.zig");
const damage = @import("../play/damage.zig");
const turn_clock = @import("../play/clock.zig");
const glacial = @import("../play/glacial.zig");
const areas = @import("../play/area.zig");
const blind = @import("../play/blind.zig");
const confusion = @import("../play/confusion.zig");
const shock = @import("../play/shock.zig");
const resilience = @import("../play/resilience.zig");
const skillbar = @import("../play/skillbar.zig");
const tactics = @import("../play/tactics.zig");
const fx = @import("../gfx/fx.zig");
const look = @import("../gfx/look.zig");
const game = @import("../game.zig");
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
        skillHit(g, id, attacks.heroBlow(&g.sim, act), act, .{ .from = from, .wait = wait });
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

fn survives(sim: *const game.simulation.Simulation, a: *const actor.Actor, dmg: i32, ailment: resilience.Kind) bool {
    const d = attacks.dealt(sim, a, dmg, ailment);
    return d > 0 and d < a.hp;
}

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
    const blow = chosenBlow(g, a, attacks.heroSkill(&g.sim, act), act, true, 0);
    wound(g, id, blow.roll, M.VERB, s);
    if (g.sim.pool.get(id) == null) return null;
    return .{ .id = id, .takes = blow.takes };
}

const Chosen = struct { roll: attacks.Roll, takes: bool };

/// A landing chosen blow through `a`'s armour, its ailment rolled first where `through` and the blow leaves it alive.
fn chosenBlow(g: *game.Game, a: *actor.Actor, raw: attacks.Roll, comptime act: skillbar.Act, through: bool, resist: i16) Chosen {
    const M = skillbar.Act.skill(act);
    var r = raw.against(g.sim.combatStats(a).armour, &g.sim.rng);
    r.hit_checked = true;
    r.opportunity = attacks.opportune(&g.sim, a);
    const takes = if (comptime act.afflicts()) attacks.afflicted(&g.sim, a, M, through and survives(&g.sim, a, r.dmg, M.AILMENT), resist) else false;
    if (comptime act.afflicts()) if (takes) {
        r.applied = M.AILMENT;
    };
    return .{ .roll = r, .takes = takes };
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
    const wet: ?Wet = if (el == .lightning and grounded) if (wading(&g.sim, at)) |bodies| .{ .bodies = bodies, .struck = actor.Pool.slot(id), .born = g.sim.pool.n } else null else null;
    defer conductTo(g, at, wet, s);
    if (!a.foe() or !attacks.heroLands(&g.sim, a, .chosen)) return;
    const resists = g.sim.combatStats(a).elements;
    const reaches = if (el) |e| hit.blow.reaches(resists, e) else true;
    const blow = chosenBlow(g, a, hit.against(resists), act, reaches, if (el) |e| resists.get(e) else 0);
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
    const cells: f32 = @floatFromInt(pierced.flight.len);
    for (pierced.body[0..pierced.n], pierced.step[0..pierced.n]) |id, step| {
        const wait = s.wait * @as(f32, @floatFromInt(step + 1)) / cells;
        wound(g, id, attacks.heroScaled(&g.sim, act, raw).physical(), M.VERB, .{ .from = s.from, .wait = wait });
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
    areaHit(g, act, impact, M.burst(&g.sim.lv, s.from, impact), s, direct, hit != .body);
    boilUnder(g, act, impact, s.wait);
}

pub fn boilUnder(g: *game.Game, comptime act: skillbar.Act, at: P, wait: f32) void {
    if (comptime act.element() != .fire) return;
    const M = skillbar.Act.elemental(act);
    fireLands(g, at, if (comptime act.bursts()) M.BLAST else 0, M.KINDLE, wait);
}

pub fn fireLands(g: *game.Game, at: P, range: i32, kindle: fire.Kindle, wait: f32) void {
    g.pic.holdFlames(&g.sim.lv, wait);
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
    const killed = g.sim.pool.items[actor.Pool.slot(id)].kind;
    fell(g, id);
    if (killed.ally()) return null;
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
    orderFoes(g, from);
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
    gasTick(g, id, .gassed, .{ .hero = "The " ++ gas.NAME ++ " eats at {s} for {d}." });
    gasTick(g, id, .scalded, .{ .hero = "The " ++ gas.STEAM_NAME ++ " scalds {s} for {d}." });
    gasHeal(g, id);
    scorch(g, id);
    burnHarm(g, id);
    bleedHarm(g, id, moved or g.sim.displaced.isSet(actor.Pool.slot(id)));
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

fn orderFoes(g: *game.Game, from: P) void {
    g.sim.order_n = 0;
    for (g.sim.pool.slice(), 0..) |a, i| {
        const id = actor.Pool.idOf(i);
        if (id == g.sim.hero or !a.alive or a.waits) continue;
        _ = mathx.push(u16, &g.sim.order, &g.sim.order_n, id);
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
    const stalled = f.clock.stalled;
    const worn = wearTurn(g, id);
    if (f.disguised) return;
    f.sweep_in -|= 1;
    f.ready_in -|= 1;
    const held = worn.held;
    if (worn.skips or stalled) return;
    const r = g.sim.pool.get(id) orelse return;
    const h = g.sim.heroActor() orelse return;
    const row = actor.row(r.kind);
    const af = worn.afflicted;
    const sight = blind.sight(af.contains(.blind), row.sight);
    if (row.allied) return allyTurn(g, id, held, af, sight);
    if (!r.awake) {
        if (!fov.sees(&g.sim.lv, r.at, h.at, @max(1, sight - g.sim.inventory.gear.sum(.stillness)))) return;
        r.awake = true;
        g.pic.turnLater(.fromInt(id), h.at.x - r.at.x);
        if (!r.submerged) g.sim.sayAt(r.at, "A {s} notices {s}.", .{ row.name, g.sim.name.text() });
        return;
    }
    const groping = af.contains(.blind) and mathx.dist(r.at, h.at) > sight;
    if (r.fright > 0) {
        r.fright -= 1;
        g.pic.recordWear(&g.sim, .fromInt(id));
        if (groping) {} else if (if (held) null else fleeWay(g, r.at, id, h.at)) |d| {
            foeStep(g, id, r.at, d, af);
        } else if (besideWay(g, r.at, h.at)) |d| {
            reach(g, id, row, d.delta().x, null, af);
        }
        if (r.fright == 0) g.sim.sayAt(r.at, "The {s} stops running.", .{row.name});
        return;
    }
    if (groping) return;
    if (row.movement == .swimming) return swimTurn(g, id, row, held, af);
    if (row.keeps > 0) return keepAway(g, id, row, held, af, sight);
    if (row.ranged) |ranged| {
        const gap = mathx.dist(r.at, h.at);
        if (!held and backOff(g, id, ranged.retreat, af)) return;
        if (bow.clearShot(&g.sim.lv, r.at, h.at, ranged.range, g.sim.hero)) |flight| return reach(g, id, row, h.at.x - r.at.x, flight, af);
        if (!held and gap > ranged.retreat) closeIn(g, id, ranged.retreat, af);
        return;
    }
    if (row.blow == .strike and besideWay(g, r.at, h.at) == null) if (besideOf(g, r.at, .ally)) |ally| return bodyStrike(g, id, ally, af, null);
    const flitted = if (!held and row.flits and g.sim.rng.chance(actor.FLIT)) actor.flit(&g.sim.lv, r.at, id, g.sim.hero, &g.sim.rng) else null;
    const d = flitted orelse foeWay(g, r.at, id, h.at) orelse return;
    const to = r.at.add(d.delta());
    if (held and !to.eq(h.at)) return;
    if (!to.eq(h.at)) return foeStep(g, id, r.at, d, af);
    reach(g, id, row, d.delta().x, null, af);
}

fn allyTurn(g: *game.Game, id: u16, held: bool, af: actor.Afflicted, sight: i32) void {
    const r = g.sim.pool.get(id).?;
    if (actor.row(r.kind).posted) return guardTurn(g, id, af, sight);
    const hero = g.sim.heroAt().?;
    if (besideOf(g, r.at, .foe)) |foe| return bodyStrike(g, id, foe, af, null);
    if (held) return;
    if (quarry(g, r.at, hero, sight)) |at| {
        if (actor.approach(&g.sim.lv, r.at, id, at)) |d| return foeStep(g, id, r.at, d, af);
    }
    if (mathx.dist(r.at, hero) <= tactics.RaiseSkeleton.FOLLOW) return;
    const d = actor.chase(&g.sim.lv, r.at, id, flowTo(g, hero)) orelse return;
    foeStep(g, id, r.at, d, af);
}

const Side = enum { foe, ally };

fn besideOf(g: *game.Game, at: P, side: Side) ?u16 {
    var best: ?u16 = null;
    for (mathx.ALL_DIRS) |d| {
        if (!g.sim.lv.passOk(at, d)) continue;
        const id = g.sim.lv.who(at.add(d.delta()));
        const a = g.sim.pool.getConst(id) orelse continue;
        const fits = switch (side) {
            .foe => a.foe(),
            .ally => a.kind.ally(),
        };
        if (!fits or a.veiled()) continue;
        if (best) |b| if (g.sim.pool.items[actor.Pool.slot(b)].hp <= a.hp) continue;
        best = id;
    }
    return best;
}

fn quarry(g: *game.Game, from: P, hero: P, sight: i32) ?P {
    var near = grid.Nearest{ .from = from };
    for (g.sim.pool.constSlice()) |a| {
        if (!a.seenFoe(&g.sim.lv) or mathx.dist(a.at, hero) > tactics.RaiseSkeleton.LEASH) continue;
        if (!fov.sees(&g.sim.lv, from, a.at, sight)) continue;
        near.offer(a.at);
    }
    return near.best;
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
    if (besideWay(g, r.at, h.at)) |d| {
        r.submerged = false;
        return reach(g, id, row, d.delta().x, null, af);
    }
    if (held) return;
    const d = actor.swim(&g.sim.lv, r.at, r.kind, h.at) orelse return;
    foeStep(g, id, r.at, d, af.intersectWith(.initOne(.maim)));
}

fn keepAway(g: *game.Game, id: u16, row: actor.Row, held: bool, af: actor.Afflicted, sight: i32) void {
    if (row.mends) |m| if (mend(g, id, m, sight)) return;
    if (row.net) |n| if (throwNet(g, id, n)) return;
    if (!held and backOff(g, id, row.keeps, af)) return;
    const r = g.sim.pool.get(id).?;
    if (besideWay(g, r.at, g.sim.heroAt().?)) |d| return reach(g, id, row, d.delta().x, null, af);
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
    const d = actor.chase(&g.sim.lv, r.at, id, flowTo(g, hero)) orelse return;
    if (mathx.dist(r.at.add(d.delta()), hero) <= keep) return;
    foeStep(g, id, r.at, d, af);
}

fn kinInReach(lv: *const grid.Level, m: actor.Mend, a: *const actor.Actor, from: P, within: i32) bool {
    if (!a.alive or std.mem.indexOfScalar(actor.Kind, m.kin, a.kind) == null) return false;
    return mathx.dist(a.at, from) <= within and grid.sightLine(lv, from, a.at);
}

/// Thrown along a clear flight at a hero not already held; a dodge or resistance spends it all the same.
fn throwNet(g: *game.Game, id: u16, n: actor.Net) bool {
    const r = g.sim.pool.get(id).?;
    const h = g.sim.heroActor().?;
    if (r.ready_in > 0 or h.pin.holding()) return false;
    const flight = bow.clearShot(&g.sim.lv, r.at, h.at, n.range, g.sim.hero) orelse return false;
    r.ready_in = n.every;
    g.pic.turnLater(.fromInt(id), h.at.x - r.at.x);
    const name = actor.row(r.kind).name;
    if (g.sim.combatStats(r).misses(g.sim.combatStats(h), &g.sim.rng)) {
        g.sim.log.say("{s} dodges the {s}'s net.", .{ g.sim.name.text(), name });
        g.pic.recordFoeAttack(.fromInt(id), .{ .snare = null }, flight);
        return true;
    }
    if (g.sim.pinFor(h, n.pins)) {
        g.sim.log.push(.danger, "The {s} nets {s}!", .{ name, g.sim.name.text() });
    } else g.sim.log.say("{s} shrugs off the {s}'s net.", .{ g.sim.name.text(), name });
    g.pic.recordFoeAttack(.fromInt(id), .{ .snare = g.pic.heroAfter(&g.sim) }, flight);
    return true;
}

fn mend(g: *game.Game, id: u16, m: actor.Mend, sight: i32) bool {
    const r = g.sim.pool.get(id).?;
    if (r.ready_in > 0) return false;
    const within = @min(m.reach, sight);
    var hurt: ?usize = null;
    var sleepers = false;
    for (g.sim.pool.slice(), 0..) |*a, i| {
        if (!kinInReach(&g.sim.lv, m, a, r.at, within)) continue;
        sleepers = sleepers or !a.awake;
        if (!a.hurt()) continue;
        if (hurt) |b| {
            const worst = g.sim.pool.items[b];
            if (@as(i64, a.hp) * worst.max >= @as(i64, worst.hp) * a.max) continue;
        }
        hurt = i;
    }
    const name = actor.row(r.kind).name;
    if (hurt) |i| {
        const a = &g.sim.pool.items[i];
        _ = a.heal(m.amount);
        g.sim.sayAt(r.at, "The {s} mends the {s}.", .{ name, actor.row(a.kind).name });
        g.pic.owe(.fromInt(id), .mended, .{ .slot = actor.ActorSlot.fromIndex(i), .after = g.pic.afterOf(&g.sim, .fromIndex(i)) });
    } else if (sleepers) {
        for (g.sim.pool.slice()) |*a| {
            if (kinInReach(&g.sim.lv, m, a, r.at, within)) a.awake = true;
        }
        g.sim.sayAt(r.at, "The {s} rouses its kin.", .{name});
        g.pic.owe(.fromInt(id), .mended, .{});
    } else return false;
    r.ready_in = m.every;
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

/// `af`: what the turn it strikes on was worn under.
fn reach(g: *game.Game, id: u16, row: actor.Row, dx: i32, flight: ?bow.Flight, af: actor.Afflicted) void {
    g.pic.turnLater(.fromInt(id), dx);
    const i = actor.Pool.slot(id);
    const kind = g.sim.pool.items[i].kind;
    switch (row.blow) {
        .strike => |s| {
            const sweeps = sweepReady(g, id, row);
            const weak = af.contains(.enfeeble);
            if (sweeps) sweepRound(g, id, row, s, weak);
            const verb = if (sweeps) actor.SWEEP_VERB else s.verb;
            const hero = g.sim.heroActor().?;
            const attacker = &g.sim.pool.items[i];
            const blow = attacks.foeBlow(&g.sim, attacker, hero, s, weak) orelse {
                g.sim.log.say("{s} dodges the {s}.", .{ g.sim.name.text(), row.name });
                g.pic.recordFoeAttack(.fromInt(id), .miss, flight);
                if (row.ranged == null) tactics_exec.counter(g, id);
                return;
            };
            const before = hero.hp;
            const defended = g.sim.combatStats(hero);
            const h = game.hurt(g, .fromInt(g.sim.hero), blow.dealt);
            const lethal = h.lethal;
            g.sim.log.push(.danger, "The {s} {s} {s} for {d}.", .{ row.name, verb, g.sim.name.text(), h.dmg });
            g.sim.chronicle.note(.{ .hurt = .{ .by = .{ .foe = kind }, .dmg = h.dmg, .before = before, .best = blow.rolled == s.hit.hi } });
            const wounded = !lethal and h.dmg > 0;
            if (wounded and g.sim.procStatus(hero, .bleed, s.bleeds)) {
                g.sim.log.push(.danger, "{s} {s}!", .{ g.sim.name.text(), hero.bleed.said() });
                hero.bleed.start();
            }
            if (wounded and g.sim.procStatus(hero, .stun, s.stuns)) {
                hero.clock.stun();
                g.sim.sayTakes(g.sim.heroSlot().?, hero, turn_clock.STUNNED);
                g.sim.chronicle.note(.{ .stunned = kind });
            }
            const chills = damage.resistedChance(s.chills, defended.elements.get(glacial.ELEMENT));
            if (wounded and g.sim.procStatus(hero, glacial.AILMENT, chills)) {
                hero.chill.apply();
                g.sim.sayTakes(g.sim.heroSlot().?, hero, glacial.TAKES);
            }
            const after = afterBlow(g, g.sim.hero, h);
            g.pic.recordFoeAttack(.fromInt(id), if (lethal) .{ .kill = after } else .{ .hurt = after }, flight);
            if (row.ranged == null) returnThorns(g, id, hero.at);
            if (lethal) heroDies(g) else if (row.ranged == null) tactics_exec.counter(g, id);
            if (!lethal and s.knocks) knockHero(g, id);
        },
        .burst => |b| {
            if (b == .gas) g.sim.chronicle.note(.burst);
            _ = g.sim.pool.damage(&g.sim.lv, id, g.sim.pool.get(id).?.hp);
            g.pic.recordFoeAttack(.fromInt(id), .{ .burst = g.pic.afterOf(&g.sim, .fromIndex(i)) }, flight);
            fell(g, id);
        },
    }
}

fn knockHero(g: *game.Game, by: u16) void {
    const slot = actor.Pool.slot(by);
    const striker = g.sim.pool.items[slot].at;
    const h = g.sim.heroActor() orelse return;
    if (h.pin.holding()) return;
    const d = mathx.dirTo(striker, h.at) orelse return;
    const from = h.at;
    const to = from.add(d.delta());
    if (!g.sim.lv.vacant(to) or g.sim.lv.doorAt(to) != null) return;
    g.sim.pool.move(&g.sim.lv, g.sim.hero, to);
    g.sim.travel = null;
    g.sim.flowed = false;
    g.sim.heroMoved();
    game.castSight(g, to);
    g.sim.log.say("{s} is knocked back.", .{g.sim.name.text()});
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
