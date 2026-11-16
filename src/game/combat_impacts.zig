const std = @import("std");
const chronicle = @import("../play/chronicle.zig");
const mathx = @import("../core/mathx.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const firebolt = @import("../play/firebolt.zig");
const attrs = @import("../play/attrs.zig");
const damage = @import("../play/damage.zig");
const turn_clock = @import("../play/clock.zig");
const glacial = @import("../play/glacial.zig");
const fx = @import("../gfx/fx.zig");
const game = @import("../game.zig");
const attacks = @import("attacks.zig");
const rewards = @import("rewards.zig");
const tactics_exec = @import("tactics_exec.zig");
const P = mathx.P;
const Stroke = game.presentation.Stroke;
const Hurt = game.simulation.DamageResult;

const IT_DIES = " It dies.";
const CUT_DOWN = " It is cut down.";
const CHEST_IS = "The chest is a {s}!";

pub const Said = struct { hero: []const u8, foe: ?[]const u8 = null, torn: bool = false };
pub const Incoming = enum { missed, hurt, killed };

pub fn wound(g: *game.Game, id: u16, raw: attacks.Roll, comptime verb: []const u8, s: Stroke) void {
    woundAt(g, .fromInt(id), raw, verb, s, .chosen, null);
}

pub fn reaction(g: *game.Game, id: u16, raw: attacks.Roll, comptime verb: []const u8, s: Stroke, source: u16, flight: ?bow.Flight) void {
    woundAt(g, .fromInt(id), raw, verb, s, .{ .reaction = .fromInt(source) }, flight);
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

pub fn harmTick(g: *game.Game, id: u16, dmg: i32, comptime owed: game.simulation.Tick, comptime said: Said) Hurt {
    const a = g.sim.pool.get(id).?;
    const kind = a.kind;
    const before = a.hp;
    const h = game.hurt(g, .fromInt(id), dmg);
    const hero = id == g.sim.hero;
    const name = actor.row(kind).name;
    if (hero) {
        heroHurt(g, said.hero, .{ g.sim.name.text(), h.dmg }, .{ .by = comptime owed.source().?, .dmg = h.dmg, .before = before, .torn = said.torn });
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

pub fn boltHits(g: *game.Game, by: actor.Kind, id: u16, hu: actor.Hurl, s: Stroke) bool {
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
        heroHurt(g, "The {s}'s " ++ firebolt.NAME ++ " burns {s} for {d}.", .{ thrower, g.sim.name.text(), h.dmg }, .{ .by = .{ .foe = by }, .dmg = h.dmg, .before = before });
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

pub fn bodyBlow(g: *game.Game, by: u16, target: u16, s: actor.Strike, verb: []const u8, weak: bool, stuns: bool) ?fx.ActorImpact {
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

pub fn incomingStrike(g: *game.Game, attacker: actor.ActorId, kind: actor.Kind, row: actor.Row, blow: actor.Strike, verb: []const u8, flight: ?bow.Flight, weak: bool) Incoming {
    const outcome = attacks.strikeHero(&g.sim, attacker, blow, weak);
    const hit = switch (outcome) {
        .blocked, .dodged => {
            g.sim.log.say("{s} {s} the {s}.", .{ g.sim.name.text(), if (outcome == .blocked) "blocks" else "dodges", row.name });
            g.pic.recordFoeAttack(attacker, .miss, flight);
            if (row.ranged == null) tactics_exec.counter(g, attacker.value);
            return .missed;
        },
        .hit => |hit| hit,
    };
    const harm = hit.damage;
    const hero = &g.sim.pool.items[harm.target.slot().index];
    game.presentDamage(g, harm);
    heroHurt(g, "The {s} {s} {s} for {d}.", .{ row.name, verb, g.sim.name.text(), harm.dmg }, .{ .by = .{ .foe = kind }, .dmg = harm.dmg, .before = hit.hp_before, .best = hit.maximum_roll });
    if (hit.bled) |said| g.sim.log.push(.danger, "{s} {s}!", .{ g.sim.name.text(), said });
    if (hit.stunned) {
        g.sim.sayTakes(g.sim.heroSlot().?, hero, turn_clock.STUNNED);
        g.sim.chronicle.note(.{ .stunned = kind });
    }
    if (hit.chilled) g.sim.sayTakes(g.sim.heroSlot().?, hero, glacial.TAKES);
    const after = afterBlow(g, g.sim.hero, harm);
    g.pic.recordFoeAttack(attacker, if (harm.lethal) .{ .kill = after } else .{ .hurt = after }, flight);
    if (row.ranged == null) returnThorns(g, attacker.value, hero.at);
    if (harm.lethal) {
        heroDies(g);
    } else if (row.ranged == null) {
        tactics_exec.counter(g, attacker.value);
    }
    return if (harm.lethal) .killed else .hurt;
}

pub fn burst(g: *game.Game, attacker: actor.ActorId, kind: actor.Burst, flight: ?bow.Flight) void {
    if (kind == .gas) g.sim.chronicle.note(.burst);
    _ = g.sim.pool.slay(&g.sim.lv, attacker.value);
    g.pic.recordFoeAttack(attacker, .{ .burst = g.pic.afterOf(&g.sim, attacker.slot()) }, flight);
    fell(g, attacker.value);
}

pub fn openMimic(g: *game.Game, p: P) bool {
    const a = g.sim.pool.get(g.sim.lv.who(p)) orelse return false;
    if (!a.disguised) return false;
    unmaskMimic(g, a, 0);
    g.sim.log.push(.danger, CHEST_IS, .{actor.row(a.kind).name});
    return true;
}

fn reveal(g: *game.Game, target: actor.ActorId, s: Stroke) void {
    const a = g.sim.pool.get(target.value) orelse return;
    if (!a.disguised) return;
    unmaskMimic(g, a, s.wait);
    a.waits = true;
    g.sim.sayAs(.danger, a.at, CHEST_IS, .{actor.row(a.kind).name});
    g.pic.masked.set(target.slot().index);
}

fn unmaskMimic(g: *game.Game, a: *actor.Actor, wait: f32) void {
    a.unmask(&g.sim.lv);
    g.pic.shimmerBody(wait, a);
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

pub fn fellOutright(g: *game.Game, id: u16) void {
    _ = g.sim.pool.slay(&g.sim.lv, id);
    fell(g, id);
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

fn heroHurt(g: *game.Game, comptime fmt: []const u8, args: anytype, hurt: chronicle.Hurt) void {
    g.sim.log.push(.danger, fmt, args);
    g.sim.chronicle.note(.{ .hurt = hurt });
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

fn deathNote(h: Hurt) []const u8 {
    return if (h.lethal) IT_DIES else "";
}
