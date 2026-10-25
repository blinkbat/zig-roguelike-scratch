const std = @import("std");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const resilience = @import("../play/resilience.zig");
const chronicle = @import("../play/chronicle.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const gas = @import("../map/gas.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const damage = @import("../play/damage.zig");
const attrs = @import("../play/attrs.zig");
const burning = @import("../play/burning.zig");
const turn_clock = @import("../play/clock.zig");
const glacial = @import("../play/glacial.zig");
const flask = @import("../play/flask.zig");
const skillbar = @import("../play/skillbar.zig");
const fx = @import("../gfx/fx.zig");
const game = @import("../game.zig");
const skills = @import("skills.zig");
const glide = @import("glide.zig");
const tactics = @import("tactics.zig");
const P = mathx.P;
const Stroke = game.presentation.Stroke;
/// Ground drops kept free for every foe a node may hold, slime halves included, to drop on dying.
const FOE_DROPS = actor.MAX;

comptime {
    std.debug.assert(items.GROUND_MAX > FOE_DROPS);
}

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
        arrowHit(g, id, heroArrow(g, act, true), act, .{ .from = from, .wait = wait });
        from = at;
    }
    g.pic.holdUntil(wait);
    g.pic.lead = wait;
}

pub fn swing(g: *game.Game, from: P, act: skillbar.Act) void {
    const d = mathx.dirTo(from, g.mark).?;
    const s = game.heroBump(g, from, g.mark, 0);
    switch (act) {
        inline else => |a| if (comptime a.reticle() != .swing)
            unreachable
        else if (comptime a.sweeps())
            sweep(g, a, s)
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
fn sweep(g: *game.Game, comptime act: skillbar.Act, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const arc = M.arc(&g.sim.lv, s.from, g.mark);
    const struck = occupants(M.WIDTH, &g.sim.lv, &arc);
    const raw = rawFor(g, act, true);
    for (arc.slice(), struck[0..arc.n]) |p, w| {
        if (w != grid.NO_ONE) wound(g, w, heroScaled(g, act, raw).physical(), M.VERB, s) else smash(g, p, M.VERB, s);
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
    var r = heroSkill(g, act).against(a, &g.sim.rng);
    const takes = if (comptime act.afflicts()) afflicted(g, a, M, r.dmg > 0 and r.dmg < a.hp, 0) else false;
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

/// Roll status before nonlethal damage so split halves inherit it.
fn afflicted(g: *game.Game, a: *actor.Actor, comptime M: type, lands: bool, resist: i16) bool {
    const takes = lands and M.procs(&g.sim.rng, resist) and a.takeStatus(M.AILMENT, &g.sim.rng);
    if (takes) M.afflict(a, &g.sim.rng);
    return takes;
}

pub const SHOOT = bow.VERB;
const IT_DIES = " It dies.";
const CUT_DOWN = " It is cut down.";

const Roll = struct {
    dmg: i32,
    crit: bool = false,
    physical: i32 = 0,
    effect: items.WeaponEffect = .{},
    applied: ?resilience.Kind = null,

    fn against(self: Roll, a: *const actor.Actor, rng: *mathx.Rng) Roll {
        var out = self;
        out.dmg -= self.physical - attrs.armoured(actor.row(a.kind).armour - self.effect.penetration, self.physical, rng);
        out.physical = 0;
        return out;
    }
};
const Rolled = struct {
    blow: damage.Damage,
    crit: bool = false,
    effect: items.WeaponEffect = .{},

    pub fn physical(h: Rolled) Roll {
        return .{ .dmg = h.blow.physical, .physical = h.blow.physical, .crit = h.crit, .effect = h.effect };
    }
};

/// A bump's roll before attributes: the melee weapon's, or the body's own blow.
pub fn kickRaw(rng: *mathx.Rng, gear: *const items.Gear, blow: actor.Strike) i32 {
    return if (gear.weapon(.melee)) |b| b.roll(rng) else blow.roll(rng);
}

/// The crit is drawn after the damage it scales.
pub fn scaled(rng: *mathx.Rng, by: attrs.Attrs, style: attrs.Style, hit: damage.Damage) Rolled {
    const crit = by.crits(rng);
    return .{ .blow = by.blow(style, hit, crit, rng), .crit = crit };
}

pub fn heroRoll(g: *game.Game, comptime attack: attrs.Attack, raw: i32) Roll {
    const gear = g.sim.inventory.gear;
    var hit = scaled(&g.sim.rng, gear.forAttack(g.sim.heroAttrs(), attack), gear.scaling(attack), .{ .physical = raw });
    hit.effect = gear.onHit(attack);
    return hit.physical();
}

pub fn heroSkill(g: *game.Game, comptime act: skillbar.Act) Roll {
    return heroArrow(g, act, true).physical();
}

pub fn heroArrow(g: *game.Game, comptime act: skillbar.Act, body: bool) Rolled {
    return heroScaled(g, act, rawFor(g, act, body));
}

/// A raw `act` roll scaled by the hero's attributes and its rank, with its crit.
pub fn heroScaled(g: *game.Game, comptime act: skillbar.Act, raw: damage.Damage) Rolled {
    const b = blowFor(g, act);
    var hit = scaled(&g.sim.rng, b.by, b.style, raw);
    if (raw.physical > 0) hit.effect = g.sim.inventory.gear.onHit(act.attack().?);
    return hit;
}

pub fn blowFor(g: *const game.Game, comptime act: skillbar.Act) progress.Blow {
    comptime std.debug.assert(act.attack() != null);
    return g.sim.growth.preparedBlow(g.sim.heroAttrs(), g.sim.inventory.gear, act, if (g.sim.heroBody()) |h| h.tactics.steady else 0).?;
}

pub fn basesFor(g: *const game.Game, act: skillbar.Act) skillbar.EquippedBases {
    return act.equippedBases(g.sim.inventory.gear);
}

/// Physical before elemental, preserving the seeded shot sequence; without `body`, no physical.
pub fn rollRaw(rng: *mathx.Rng, comptime act: skillbar.Act, bases: skillbar.EquippedBases, body: bool) damage.Damage {
    var raw = damage.Damage{};
    if (body) for (bases.parts()) |maybe| {
        if (maybe) |b| raw.physical += b.roll(rng);
    };
    if (comptime act.element()) |element| raw.elements.set(element, bases.element.?.roll(rng));
    return raw;
}

fn rawFor(g: *game.Game, comptime act: skillbar.Act, body: bool) damage.Damage {
    return rollRaw(&g.sim.rng, act, basesFor(g, act), body);
}

pub fn arrowHit(g: *game.Game, id: u16, hit: Rolled, comptime act: skillbar.Act, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const el = comptime act.element();
    const a = g.sim.pool.get(id) orelse return;
    var r = (Roll{ .dmg = hit.blow.total(a.resists), .physical = hit.blow.physical, .crit = hit.crit, .effect = hit.effect }).against(a, &g.sim.rng);
    const at = a.at;
    const name = actor.row(a.kind).name;
    const lands = r.dmg > 0 and r.dmg < a.hp and if (el) |e| hit.blow.reaches(a.resists, e) else true;
    const takes = afflicted(g, a, M, lands, if (el) |e| a.resists.get(e) else 0);
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
    const raw = rawFor(g, act, direct != null);
    if (barrel) smash(g, at, barrelVerb(act), s);
    for (struck.slice()) |id| {
        var hit = raw;
        if (direct != id) hit.physical = 0;
        arrowHit(g, id, heroScaled(g, act, hit), act, s);
    }
}
pub fn smash(g: *game.Game, p: P, comptime verb: []const u8, s: Stroke) void {
    const gold = barrelGold(g, p) orelse return;
    g.sim.log.push(.loot, "{s} " ++ verb ++ BARREL_DROPS, .{ g.sim.name.text(), gold });
    g.pic.strike(&g.sim, g.cloud, null, s, p, true, null);
}

const BARREL_DROPS = " the barrel. It drops {d} gold.";

/// The gold a barrel on `p` drops as it breaks; null with none there.
fn barrelGold(g: *game.Game, p: P) ?i32 {
    if (!g.sim.lv.breakBarrel(p)) return null;
    return loot(g, p, items.BARREL_GOLD);
}

pub fn openChest(g: *game.Game, p: P) bool {
    const opened = g.sim.lv.at(p).opened() orelse return false;
    if (!groundRoom(g)) return false;
    g.sim.lv.set(p, opened);
    dropItem(g, .{ .item = items.roll(&g.sim.loot_rng, g.sim.heroAttrs().item_rarity), .at = p });
    g.sim.log.push(.loot, "{s} opens the chest: {d} gold and an item.", .{ g.sim.name.text(), loot(g, p, items.CHEST_GOLD) });
    g.sim.chronicle.mark(.chest);
    return true;
}

pub fn groundRoom(g: *game.Game) bool {
    if (g.sim.ground.room(FOE_DROPS)) return true;
    g.character.message.say("Ground full", .{});
    g.sim.log.say("Ground full: collect an item first.", .{});
    return false;
}

fn loot(g: *game.Game, at: P, range: items.Gold) i32 {
    const gold = range.roll(&g.sim.loot_rng);
    dropGold(g, at, gold);
    return gold;
}

fn dropGold(g: *game.Game, at: P, amount: i32) void {
    const added = g.sim.ground.gold(at, amount);
    std.debug.assert(added);
}

pub fn dropItem(g: *game.Game, drop: items.Drop) void {
    const added = g.sim.ground.add(drop);
    std.debug.assert(added);
}

pub fn collectGold(g: *game.Game, at: P) void {
    const coins = g.sim.ground.collect(at);
    if (coins == 0) return;
    const amount = g.sim.heroAttrs().collectedGold(coins, &g.sim.loot_rng);
    g.pic.gold_taken = .{ .at = at, .amount = coins };
    g.sim.gold +|= amount;
    g.sim.log.push(.loot, "{s} picks up {d} gold.", .{ g.sim.name.text(), amount });
    g.sim.unsaved = true;
}

pub fn arrive(g: *game.Game, at: P) void {
    if (!g.sim.lv.at(at).isChest() and !g.sim.ground.hasItems(at)) collectGold(g, at);
    noticeItems(g, at);
}

pub fn noticeItems(g: *game.Game, at: P) void {
    var name: [items.NAME_MAX]u8 = undefined;
    for (g.sim.ground.drops[0..g.sim.ground.n]) |drop| {
        if (drop.at.eq(at)) g.sim.log.push(.loot, "{s} steps over {s}.", .{ g.sim.name.text(), drop.item.name(&name) });
    }
}

pub fn wound(g: *game.Game, id: u16, raw: Roll, comptime verb: []const u8, s: Stroke) void {
    woundAt(g, id, raw, verb, s, null, null);
}

pub fn reaction(g: *game.Game, id: u16, raw: Roll, comptime verb: []const u8, s: Stroke, source: u16, flight: ?bow.Flight) void {
    woundAt(g, id, raw, verb, s, source, flight);
}

fn woundAt(g: *game.Game, id: u16, raw: Roll, comptime verb: []const u8, s: Stroke, source: ?u16, flight: ?bow.Flight) void {
    const a = g.sim.pool.get(id) orelse return;
    const r = raw.against(a, &g.sim.rng);
    const kind = a.kind;
    const at = a.at;
    const i = actor.Pool.slot(id);
    const name = actor.row(kind).name;
    const perks = g.sim.heroPerks();
    const culled = r.dmg > 0 and perks.culls(a.hp - r.dmg, a.max);
    var bled: ?[]const u8 = null;
    var stunned = false;
    if (!culled and r.dmg > 0 and r.dmg < a.hp) {
        if (r.applied != .bleed and procOn(g, a, .bleed, r.effect.bleed)) {
            bled = a.bleed.said();
            a.bleed.startWith(r.effect.bleed_damage);
        }
        if (r.applied != .stun and procOn(g, a, .stun, r.effect.stun)) {
            a.clock.stun();
            stunned = true;
        }
    }
    const h = hurt(g, id, if (culled) a.hp else r.dmg);
    const lethal = h.lethal;
    g.sim.chronicle.note(.{ .dealt = .{ .to = kind, .killed = lethal, .reaction = source != null } });
    g.sim.sayAs(.damage, at, "{s} " ++ verb ++ " the {s}{s} for {d}.{s}", .{ g.sim.name.text(), name, if (r.crit) " critically" else "", r.dmg, if (culled) CUT_DOWN else if (lethal) IT_DIES else "" });
    if (bled) |said| g.sim.sayAt(at, "The {s} {s}!", .{ name, said });
    if (stunned) sayTakes(g, turn_clock.STUNNED, at, name);
    const after = afterBlow(g, id, h);
    if (source) |by| {
        g.pic.owed[actor.Pool.slot(by)].reaction = .{ .from = s.from, .flight = flight, .hit = .{ .slot = i, .at = at, .lethal = lethal, .after = after } };
    } else g.pic.strike(&g.sim, g.cloud, i, s, at, lethal, after);
    if (lethal) fell(g, id);
    if (h.dmg > 0) {
        const recovery = perks.life_on_hit + if (lethal) perks.life_on_kill else 0;
        if (source) |by| g.pic.owed[actor.Pool.slot(by)].reaction.?.recovery = recoverLife(g, recovery) else heal(g, recovery, s.wait);
    }
}

fn procOn(g: *game.Game, a: *actor.Actor, kind: resilience.Kind, pc: u32) bool {
    return damage.procs(&g.sim.rng, pc) and a.takeStatus(kind, &g.sim.rng);
}

/// Shown on the hero as the blow that earned it lands.
pub fn heal(g: *game.Game, n: i32, wait: f32) void {
    const after = recoverLife(g, n) orelse return;
    g.pic.fx.settle(wait, .{ .slot = g.sim.heroSlot().?, .after = after });
}

fn recoverLife(g: *game.Game, n: i32) ?fx.After {
    const h = g.sim.heroActor() orelse return null;
    if (n <= 0 or h.hp >= h.max) return null;
    h.hp = @min(h.max, h.hp + n);
    return g.pic.afterOf(&g.sim, g.sim.heroSlot().?);
}

fn afterBlow(g: *game.Game, id: u16, h: Hurt) fx.After {
    const other = if (h.lethal) null else split(g, id);
    var after = g.pic.afterOf(&g.sim, actor.Pool.slot(id));
    after.reveals = other;
    after.mana = h.mana;
    return after;
}

/// Split halves become visible only when the splitting blow lands.
fn split(g: *game.Game, id: u16) ?usize {
    const i = actor.Pool.slot(id);
    const name = actor.row(g.sim.pool.items[i].kind).name;
    const other = g.sim.pool.split(&g.sim.lv, id, &g.sim.rng) orelse return null;
    const o = actor.Pool.slot(other);
    const b = g.sim.pool.items[o];
    g.pic.split_from[o] = i;
    g.sim.ran[o] = g.sim.ran[i];
    g.pic.pictured[o] = fx.Body.of(b, g.pic.seq);
    g.pic.glide[o] = glide.Glide.rest(&b);
    g.pic.facing[o] = if (g.pic.turning[i]) |t| t.to else g.pic.facing[i];
    g.sim.sayAt(g.sim.pool.items[i].at, "The {s} splits in two!", .{name});
    return o;
}

pub fn fell(g: *game.Game, id: u16) void {
    const fallen = actor.Pool.slot(id);
    const kind = g.sim.pool.items[fallen].kind;
    const at = g.sim.pool.items[fallen].at;
    const name = actor.row(kind).name;
    g.sim.kills += 1;
    const xp = progress.xpOf(kind);
    const was = g.sim.growth;
    const levels = g.sim.growth.gain(xp);
    g.sim.log.push(.progress, "{s} gains {d} experience.", .{ g.sim.name.text(), xp });
    if (levels > 0) g.sim.chronicle.mark(.level);
    if (levels > 0) g.sim.log.push(.progress, "Level {d}: +{d} passive, +{d} active points.", .{ g.sim.growth.level, g.sim.growth.passive_points - was.passive_points, g.sim.growth.active_points - was.active_points });
    const reward = items.foeLoot(&g.sim.loot_rng, g.sim.heroAttrs().item_rarity);
    g.pic.dropped_gold[fallen] = reward.gold;
    if (reward.gold > 0) dropGold(g, at, reward.gold);
    if (reward.item) |item| dropItem(g, .{ .item = item, .at = at, .source = id });
    for (&g.sim.flasks.values) |*f| f.fill(flask.PER_KILL);
    if (kind.bursts()) {
        g.sim.lv.addGas(at, gas.BURST);
        g.sim.sayAt(at, "The {s} bursts, leaving a cloud of " ++ gas.NAME ++ "!", .{name});
    }
    const family = kind.family();
    if (g.sim.pool.tally(family).left == 0) {
        g.sim.log.say("The last {s} is dead.", .{actor.row(family).name});
        g.sim.chronicle.mark(.{ .cleared = family });
    }
    scare(g, fallen);
}

pub fn scare(g: *game.Game, fallen: usize) void {
    const at = g.sim.pool.items[fallen].at;
    for (g.sim.pool.slice(), 0..) |*a, i| {
        const row = actor.row(a.kind);
        if (!a.alive or !row.flees or mathx.dist(a.at, at) > actor.FRIGHT_REACH or !grid.clearLine(&g.sim.lv, a.at, at)) continue;
        const steady = a.fright == 0;
        a.fright = actor.FLEE_TURNS;
        a.awake = true;
        if (steady) {
            g.sim.sayAt(a.at, "The {s} flees in terror!", .{row.name});
            g.pic.fx.frighten(i, fallen);
        }
    }
}

fn heroDies(g: *game.Game) void {
    g.sim.log.push(.danger, "{s} dies.", .{g.sim.name.text()});
    g.died_in = g.mode;
    g.mode = .dead;
    game.epitaph.inscribe(g);
}

/// Brogue turn order; recast sight after carried enemy lights move.
pub fn endTurn(g: *game.Game) void {
    const h = g.sim.heroActor() orelse return;
    g.sim.unsaved = true;
    g.sim.clock.turn();
    tactics.startTurn(g);
    skills.recover(g);
    for (&g.sim.cooldown.values) |*c| c.* -|= 1;
    defer {
        for (g.sim.pool.slice()) |*a| a.settle();
        g.sim.ran = @splat(game.simulation.Ran.initEmpty());
        g.sim.displaced = .initEmpty();
    }
    game.castSight(g, h.at);
    g.sim.flowed = false;
    orderFoes(g, h.at);
    harmAfter(g, g.sim.hero, g.sim.stepped);
    g.sim.stepped = false;
    if (g.mode == .dead) return;
    gas.turn(&g.sim.lv, &g.sim.rng);
    for (g.sim.pool.slice()) |*a| {
        if (a.alive and a.foe()) a.clock.pass(actor.row(a.kind).pace);
    }
    for (g.sim.order[0..g.sim.order_n]) |id| {
        const i = actor.Pool.slot(id);
        const was = g.sim.pool.items[i].at;
        foeTurn(g, id);
        if (g.mode == .dead) return;
        harmAfter(g, id, !g.sim.pool.items[i].at.eq(was));
    }
    var i: usize = 0;
    while (i < g.sim.pool.n) : (i += 1) {
        const a = g.sim.pool.items[i];
        if (!a.alive or !a.waits) continue;
        const id = actor.Pool.idOf(i);
        _ = wearTurn(g, id);
        harmAfter(g, id, false);
    }
    if (g.sim.heroActor()) |a| {
        if (a.ward.turns > 0) {
            a.ward.wear();
            const hero = g.sim.heroSlot().?;
            g.pic.owed[hero].worn = g.pic.afterOf(&g.sim, hero);
        }
        game.castSight(g, a.at);
        g.sim.chronicle.begin(game.epitaph.turnStart(g));
    }
}

const Hurt = struct { dmg: i32, lethal: bool, mana: i32 = 0 };

pub const UNKILLABLE_HP: i32 = 1;

fn hurt(g: *game.Game, id: u16, dmg: i32) Hurt {
    const a = g.sim.pool.get(id) orelse return .{ .dmg = 0, .lethal = false };
    var left = dmg;
    if (id == g.sim.hero) {
        const took = a.ward.takes(g.sim.mana, dmg);
        if (took > 0) {
            g.sim.mana -= took;
            g.pic.mana_held += took;
            left -= took;
            g.sim.log.say("The mana shield takes {d}.", .{took});
        }
    }
    const taken = if (id == g.sim.hero and g.sim.unkillable) std.math.clamp(a.hp - UNKILLABLE_HP, 0, left) else left;
    if (id == g.sim.hero and (taken > 0 or dmg > left)) g.mouse.stop();
    return .{ .dmg = taken, .lethal = g.sim.pool.damage(&g.sim.lv, id, taken), .mana = dmg - left };
}

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
    const dmg = a.burn.tick(a.resists.get(burning.ELEMENT)) orelse return;
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
    const h = hurt(g, id, dmg);
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
    @field(g.pic.owed[actor.Pool.slot(id)], @tagName(owed)) = debt;
    return h;
}

const Worn = struct { held: bool = false, skips: bool = false };

fn wearTurn(g: *game.Game, id: u16) Worn {
    const a = g.sim.pool.get(id) orelse return .{};
    const i = actor.Pool.slot(id);
    if (ranAlready(g, id, .worn) or (a.pin.turns == 0 and a.chill.turns == 0)) return .{};
    const w = Worn{ .held = a.pin.hold(), .skips = a.chill.turns > 0 and a.chill.skip() };
    g.pic.owed[i].worn = g.pic.afterOf(&g.sim, i);
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
            reach(g, id, row);
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
                    g.pic.owed[actor.Pool.slot(id)].arrow = flight;
                    reach(g, id, row);
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
    reach(g, id, row);
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

/// The strike's damage, or null when the hero dodges it; the dodge is drawn first.
pub fn bite(rng: *mathx.Rng, by: attrs.Attrs, s: actor.Strike) ?i32 {
    if (by.dodges(rng)) return null;
    return s.roll(rng);
}

fn reach(g: *game.Game, id: u16, row: actor.Row) void {
    const i = actor.Pool.slot(id);
    const kind = g.sim.pool.items[i].kind;
    switch (row.blow) {
        .strike => |s| {
            const sweeps = sweepReady(g, id, row);
            if (sweeps) sweepRound(g, id, row, s);
            const verb = if (sweeps) actor.SWEEP_VERB else s.verb;
            const dmg = bite(&g.sim.rng, g.sim.heroAttrs(), s) orelse {
                g.sim.log.say("{s} dodges the {s}.", .{ g.sim.name.text(), row.name });
                g.pic.owed[i].bit = .miss;
                if (row.ranged == null) tactics.counter(g, id);
                return;
            };
            const hero = g.sim.heroActor().?;
            const before = hero.hp;
            var physical = g.sim.heroAttrs().physical(dmg, &g.sim.rng);
            if (hero.tactics.guard > 0) physical = @intCast(@divTrunc(@as(i64, physical) * (100 - @import("../play/tactics.zig").Guard.reduction(hero.tactics.guard)) + 99, 100));
            const h = hurt(g, g.sim.hero, physical);
            const lethal = h.lethal;
            g.sim.log.push(.danger, "The {s} {s} {s} for {d}.", .{ row.name, verb, g.sim.name.text(), h.dmg });
            g.sim.chronicle.note(.{ .hurt = .{ .by = .{ .foe = kind }, .dmg = h.dmg, .before = before, .best = dmg == s.hit.hi } });
            if (!lethal and h.dmg > 0 and procOn(g, hero, .bleed, s.bleeds)) {
                g.sim.log.say("{s} {s}!", .{ g.sim.name.text(), hero.bleed.said() });
                hero.bleed.start();
            }
            if (!lethal and h.dmg > 0 and procOn(g, hero, .stun, s.stuns)) {
                hero.clock.stun();
                g.sim.log.say("{s} " ++ turn_clock.STUNNED ++ "!", .{g.sim.name.text()});
                g.sim.chronicle.note(.{ .stunned = kind });
            }
            const after = afterBlow(g, g.sim.hero, h);
            g.pic.owed[i].bit = if (lethal) .{ .kill = after } else .{ .hurt = after };
            if (row.ranged == null) returnThorns(g, id, hero.at);
            if (lethal) heroDies(g) else if (row.ranged == null) tactics.counter(g, id);
        },
        .burst => {
            g.sim.chronicle.note(.burst);
            const a = g.sim.pool.get(id).?.*;
            _ = g.sim.pool.damage(&g.sim.lv, id, a.hp);
            g.pic.owed[i].bit = .{ .burst = g.pic.afterOf(&g.sim, i) };
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
    const h = hurt(g, id, dmg);
    const after = afterBlow(g, id, h);
    g.sim.chronicle.note(.{ .dealt = .{ .to = kind, .killed = h.lethal, .reaction = true } });
    g.sim.sayAs(.damage, at, "{s}'s thorns hurt the {s} for {d}.{s}", .{ g.sim.name.text(), actor.row(kind).name, h.dmg, if (h.lethal) IT_DIES else "" });
    if (h.lethal) fell(g, id);
    g.pic.owed[actor.Pool.slot(id)].thorns = .{ .kill = h.lethal, .after = after, .recovery = if (h.lethal) recoverLife(g, g.sim.inventory.gear.killRecovery()) else null };
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
        const hit = if (w != grid.NO_ONE) swipe(g, w, row, s) else smashedBy(g, p, row) orelse continue;
        swept.hit[swept.n] = hit;
        swept.n += 1;
    }
    if (swept.n > 0) g.pic.owed[actor.Pool.slot(id)].swept = swept;
}

fn swipe(g: *game.Game, id: u16, by: actor.Row, s: actor.Strike) game.presentation.Swipe {
    const a = g.sim.pool.get(id).?;
    const at = a.at;
    const name = actor.row(a.kind).name;
    const rolled = s.roll(&g.sim.rng);
    const dmg = (Roll{ .dmg = rolled, .physical = rolled }).against(a, &g.sim.rng).dmg;
    const stunned = dmg > 0 and dmg < a.hp and procOn(g, a, .stun, s.stuns);
    if (stunned) {
        if (!a.waits and !g.sim.ran[actor.Pool.slot(id)].contains(.worn)) a.clock.stunBeforeAction(actor.row(a.kind).pace) else a.clock.stun();
    }
    const h = hurt(g, id, dmg);
    g.sim.sayAt(at, "The {s} " ++ actor.SWEEP_VERB ++ " the {s} for {d}.{s}", .{ by.name, name, h.dmg, if (h.lethal) IT_DIES else "" });
    if (stunned) sayTakes(g, turn_clock.STUNNED, at, name);
    const after = afterBlow(g, id, h);
    if (h.lethal) fell(g, id);
    return .{ .slot = actor.Pool.slot(id), .at = at, .lethal = h.lethal, .after = after };
}

fn smashedBy(g: *game.Game, p: P, by: actor.Row) ?game.presentation.Swipe {
    const gold = barrelGold(g, p) orelse return null;
    g.sim.sayAt(p, "The {s} smashes" ++ BARREL_DROPS, .{ by.name, gold });
    return .{ .slot = null, .at = p, .lethal = true };
}
