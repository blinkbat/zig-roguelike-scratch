const std = @import("std");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const gas = @import("../map/gas.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const damage = @import("../play/damage.zig");
const attrs = @import("../play/attrs.zig");
const burning = @import("../play/burning.zig");
const bleeding = @import("../play/bleeding.zig");
const turn_clock = @import("../play/clock.zig");
const glacial = @import("../play/glacial.zig");
const flask = @import("../play/flask.zig");
const skillbar = @import("../play/skillbar.zig");
const fx = @import("../gfx/fx.zig");
const game = @import("../game.zig");
const P = mathx.P;
const FOE_DROPS = actor.MAX;

pub fn barrelVerb(comptime act: skillbar.Act) []const u8 {
    return if (comptime act.bolt() != null) skillbar.Act.skill(act).VERB else SHOOT;
}

/// Choose targets before striking; each jump delays the next hit and the foes' stagger.
pub fn chainHit(g: *game.Game, comptime act: skillbar.Act, first: u16, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const c = M.chain(&g.lv, &g.pool, first);
    var from = s.from;
    var wait = s.wait;
    for (c.slice(), 0..) |id, k| {
        const slot = actor.Pool.slot(id);
        const at = g.pool.items[slot].at;
        if (k > 0) {
            g.fx.zap(wait, .{ .from = mathx.centre(from), .to = mathx.centre(at) });
            wait += game.ZAP_S;
        }
        arrowHit(g, id, heroArrow(g, act, true), act, .{ .from = from, .wait = wait });
        from = at;
    }
    holdUntil(g, wait);
    g.lead = wait;
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
    game.turnToward(g, g.hero, d.delta().x);
    g.lead = s.wait;
    endTurn(g);
}

/// Snapshot arc targets before damage so newborn slime halves are spared.
fn sweep(g: *game.Game, comptime act: skillbar.Act, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const arc = M.arc(&g.lv, s.from, g.mark);
    var struck: [M.WIDTH]u16 = undefined;
    for (arc.slice(), struck[0..arc.n]) |p, *w| w.* = g.lv.who(p);
    const raw = rawFor(g, act, true);
    for (arc.slice(), struck[0..arc.n]) |p, w| {
        if (w != grid.NO_ONE) wound(g, w, heroScaled(g, act, raw).physical(), M.VERB, s) else smash(g, p, M.VERB, s);
    }
}

pub fn knock(g: *game.Game, comptime act: skillbar.Act, d: mathx.Dir, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const to = s.from.add(d.delta());
    const id = g.lv.who(to);
    if (id == grid.NO_ONE) return smash(g, to, M.VERB, s);
    const a = g.pool.get(id).?;
    const r = heroSkill(g, act);
    const takes = if (comptime act.afflicts()) afflicted(g, a, M, r.dmg < a.hp, 0) else false;
    wound(g, id, r, M.VERB, s);
    if (g.pool.get(id) == null) return;
    const name = actor.row(a.kind).name;
    const back = if (a.pin.turns > 0) null else M.knocked(&g.lv, a.at, d, id);
    if (back) |b| {
        const i = actor.Pool.slot(id);
        g.pool.move(&g.lv, id, b);
        g.displaced.set(i);
        _ = glideHeld(g, i, g.glide[i].toward(b, -s.wait));
        game.sayAt(g, b, "The {s} is knocked back.", .{name});
    }
    if (takes) sayTakes(g, M, a.at, name);
}

fn sayTakes(g: *game.Game, comptime M: type, at: P, name: []const u8) void {
    game.sayAt(g, at, "The {s} " ++ M.TAKES ++ "!", .{name});
}

/// Roll status before nonlethal damage so split halves inherit it.
fn afflicted(g: *game.Game, a: *actor.Actor, comptime M: type, lands: bool, resist: i16) bool {
    const takes = lands and M.procs(&g.rng, resist);
    if (takes) M.afflict(a, &g.rng);
    return takes;
}

pub const SHOOT = bow.VERB;
const IT_DIES = " It dies.";
const CUT_DOWN = " It is cut down.";

const Roll = struct { dmg: i32, crit: bool = false };
const Rolled = struct {
    blow: damage.Damage,
    crit: bool = false,

    fn physical(h: Rolled) Roll {
        return .{ .dmg = h.blow.physical, .crit = h.crit };
    }
};

/// The crit is drawn after the damage it scales.
pub fn scaled(rng: *mathx.Rng, by: attrs.Attrs, style: attrs.Style, hit: damage.Damage) Rolled {
    const crit = by.crits(rng);
    return .{ .blow = by.blow(style, hit, crit, rng), .crit = crit };
}

pub fn heroRoll(g: *game.Game, comptime attack: attrs.Attack, raw: i32) Roll {
    return scaled(&g.rng, game.heroAttrs(g), g.inventory.gear.scaling(attack), .{ .physical = raw }).physical();
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
    return scaled(&g.rng, b.by, b.style, raw);
}

pub const SkillBases = skillbar.EquippedBases;

pub fn blowFor(g: *const game.Game, comptime act: skillbar.Act) progress.Blow {
    comptime std.debug.assert(act.attack() != null);
    return g.growth.blowOf(game.heroAttrs(g), g.inventory.gear, act).?;
}

pub fn basesOf(gear: *const items.Gear, act: skillbar.Act) SkillBases {
    return act.equippedBases(gear.*);
}

pub fn basesFor(g: *const game.Game, act: skillbar.Act) SkillBases {
    return basesOf(&g.inventory.gear, act);
}

/// Physical before elemental, preserving the seeded shot sequence; without `body`, no physical.
pub fn rollRaw(rng: *mathx.Rng, comptime act: skillbar.Act, bases: SkillBases, body: bool) damage.Damage {
    var raw = damage.Damage{};
    if (body) for (bases.parts()) |maybe| {
        if (maybe) |b| raw.physical += b.roll(rng);
    };
    if (comptime act.element()) |element| raw.elements.set(element, bases.element.?.roll(rng));
    return raw;
}

fn rawFor(g: *game.Game, comptime act: skillbar.Act, body: bool) damage.Damage {
    return rollRaw(&g.rng, act, basesFor(g, act), body);
}

pub fn arrowHit(g: *game.Game, id: u16, hit: Rolled, comptime act: skillbar.Act, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const el = comptime act.element();
    const a = g.pool.get(id) orelse return;
    const dealt = hit.blow.total(a.resists);
    const at = a.at;
    const name = actor.row(a.kind).name;
    const lands = if (el) |e| hit.blow.afflicts(a.resists, e, a.hp) else dealt < a.hp;
    const takes = afflicted(g, a, M, lands, if (el) |e| a.resists.get(e) else 0);
    if (dealt > 0) wound(g, id, .{ .dmg = dealt, .crit = hit.crit }, M.VERB, s);
    if (takes and g.pool.get(id) != null) sayTakes(g, M, at, name);
}

pub fn burstHit(g: *game.Game, comptime act: skillbar.Act, hit: bow.Hit, impact: P, s: Stroke) void {
    const M = skillbar.Act.elemental(act);
    const direct: ?u16 = switch (hit) {
        .body => |id| id,
        .barrel => null,
    };
    areaHit(g, act, impact, M.burst(&g.lv, s.from, impact), s, direct, hit == .barrel);
}

pub fn areaHit(g: *game.Game, comptime act: skillbar.Act, at: P, area: glacial.Burst, s: Stroke, direct: ?u16, barrel: bool) void {
    const struck = game.foesIn(g, area);
    g.fx.burst(s.wait, .{ .at = at, .area = area, .element = act.element().? });
    const raw = rawFor(g, act, direct != null);
    if (barrel) smash(g, at, barrelVerb(act), s);
    for (struck.slice()) |id| {
        var hit = raw;
        if (direct != id) hit.physical = 0;
        arrowHit(g, id, heroScaled(g, act, hit), act, s);
    }
}
/// Where a blow came from, and how long until the picture reaches it.
pub const Stroke = struct { from: P, wait: f32, fire: bool = false };

pub fn strike(g: *game.Game, slot: ?usize, s: Stroke, at: P, lethal: bool, after: ?fx.After) void {
    const len = mathx.distEuclid(at, s.from);
    const dir: ?[2]f32 = if (len == 0) null else .{ @as(f32, @floatFromInt(at.x - s.from.x)) / len, @as(f32, @floatFromInt(at.y - s.from.y)) / len };
    const kind: ?actor.Kind = if (slot) |i| g.pool.items[i].kind else null;
    if (slot == null or slot == game.heroSlot(g) or g.lv.isLit(at)) {
        g.fx.strike(s.wait, .{ .slot = slot, .at = mathx.centre(at), .dir = dir, .matter = fx.matterOf(kind), .lethal = lethal, .after = after, .fire = s.fire });
        flashes(g, s.wait);
    } else if (after) |a| g.fx.settle(s.wait, .{ .slot = slot.?, .after = a });
    const k = kind orelse return;
    if (lethal and k.bursts()) g.cloud.hold(s.wait);
}

pub fn sting(g: *game.Game, wait: f32, s: fx.Sting) void {
    g.fx.sting(wait, s);
    flashes(g, wait);
}

pub fn snap(g: *game.Game, slot: usize) fx.Body {
    g.seq += 1;
    return fx.Body.of(g.pool.items[slot], g.seq);
}

pub fn settleHero(g: *game.Game, wait: f32) void {
    const slot = game.heroSlot(g).?;
    g.fx.settle(wait, .{ .slot = slot, .after = .{ .body = snap(g, slot) } });
}

fn flashes(g: *game.Game, wait: f32) void {
    holdUntil(g, wait + fx.FLASH_S);
}

pub fn holdUntil(g: *game.Game, t: f32) void {
    g.busy = @max(g.busy, t);
}

pub fn glideHeld(g: *game.Game, slot: usize, gl: game.Glide) f32 {
    g.glide[slot] = gl;
    holdUntil(g, gl.left());
    return gl.left();
}

pub fn smash(g: *game.Game, p: P, comptime verb: []const u8, s: Stroke) void {
    if (!g.lv.breakBarrel(p)) return;
    g.log.push(.loot, "{s} " ++ verb ++ " the barrel. It drops {d} gold.", .{ g.name.text(), loot(g, p, items.BARREL_GOLD) });
    strike(g, null, s, p, true, null);
}

pub fn openChest(g: *game.Game, p: P) bool {
    const opened = g.lv.at(p).opened() orelse return false;
    if (!groundRoom(g)) return false;
    g.lv.set(p, opened);
    const added = g.ground.add(.{ .item = items.roll(&g.loot_rng), .at = p });
    std.debug.assert(added);
    g.log.push(.loot, "{s} opens the chest: {d} gold and an item.", .{ g.name.text(), loot(g, p, items.CHEST_GOLD) });
    return true;
}

pub fn groundRoom(g: *game.Game) bool {
    if (g.ground.room(FOE_DROPS)) return true;
    g.character.message.say("Ground full", .{});
    g.log.say("Ground full: collect an item first.", .{});
    return false;
}

fn loot(g: *game.Game, at: P, range: items.Gold) i32 {
    const gold = g.loot_rng.range(range.lo, range.hi);
    const added = g.ground.gold(at, gold);
    std.debug.assert(added);
    return gold;
}

pub fn collectGold(g: *game.Game, at: P) void {
    const amount = g.ground.collect(at);
    if (amount == 0) return;
    g.gold_taken = at;
    g.gold +|= amount;
    g.log.push(.loot, "{s} picks up {d} gold.", .{ g.name.text(), amount });
    g.unsaved = true;
}

pub fn noticeItems(g: *game.Game, at: P) void {
    for (g.ground.drops[0..g.ground.n]) |drop| {
        if (drop.at.eq(at)) g.log.push(.loot, "{s} steps over {s}.", .{ g.name.text(), drop.item.name() });
    }
}

pub fn wound(g: *game.Game, id: u16, r: Roll, comptime verb: []const u8, s: Stroke) void {
    const a = g.pool.get(id) orelse return;
    const kind = a.kind;
    const at = a.at;
    const i = actor.Pool.slot(id);
    const name = actor.row(kind).name;
    const perks = g.growth.perks();
    const culled = perks.culls(a.hp - r.dmg, a.max);
    const h = hurt(g, id, if (culled) a.hp else r.dmg);
    const lethal = h.lethal;
    game.sayAs(g, .damage, at, "{s} " ++ verb ++ " the {s}{s} for {d}.{s}", .{ g.name.text(), name, if (r.crit) " critically" else "", r.dmg, if (culled) CUT_DOWN else if (lethal) IT_DIES else "" });
    strike(g, i, s, at, lethal, afterBlow(g, id, h));
    if (lethal) fell(g, id);
    if (h.dmg > 0) heal(g, perks.life_on_hit + if (lethal) perks.life_on_kill else 0, s.wait);
}

/// Shown on the hero as the blow that earned it lands.
pub fn heal(g: *game.Game, n: i32, wait: f32) void {
    const h = g.heroActor() orelse return;
    if (n <= 0 or h.hp >= h.max) return;
    h.hp = @min(h.max, h.hp + n);
    settleHero(g, wait);
}

fn afterBlow(g: *game.Game, id: u16, h: Hurt) fx.After {
    const other = if (h.lethal) null else split(g, id);
    return .{ .body = snap(g, actor.Pool.slot(id)), .reveals = other, .mana = h.mana };
}

/// Split halves become visible only when the splitting blow lands.
fn split(g: *game.Game, id: u16) ?usize {
    const i = actor.Pool.slot(id);
    const name = actor.row(g.pool.items[i].kind).name;
    const other = g.pool.split(&g.lv, id, &g.rng) orelse return null;
    const o = actor.Pool.slot(other);
    const b = g.pool.items[o];
    g.split_from[o] = i;
    g.ran[o] = g.ran[i];
    g.pictured[o] = fx.Body.of(b, g.seq);
    g.glide[o] = game.Glide.rest(&b);
    g.facing[o] = if (g.turning[i]) |t| t.to else g.facing[i];
    game.sayAt(g, g.pool.items[i].at, "The {s} splits in two!", .{name});
    return o;
}

pub fn fell(g: *game.Game, id: u16) void {
    const fallen = actor.Pool.slot(id);
    const kind = g.pool.items[fallen].kind;
    const at = g.pool.items[fallen].at;
    const name = actor.row(kind).name;
    g.kills += 1;
    const xp = progress.xpOf(kind);
    const was = g.growth;
    const levels = g.growth.gain(xp);
    g.log.push(.progress, "{s} gains {d} experience.", .{ g.name.text(), xp });
    if (levels > 0) g.log.push(.progress, "Level {d}: +{d} passive, +{d} active points.", .{ g.growth.level, g.growth.passive_points - was.passive_points, g.growth.active_points - was.active_points });
    if (g.loot_rng.percent(items.DROP_PERCENT)) {
        const added = g.ground.add(.{ .item = items.roll(&g.loot_rng), .at = at, .source = id });
        std.debug.assert(added);
    }
    for (&g.flasks.values) |*f| f.fill(flask.PER_KILL);
    if (kind.bursts()) {
        g.lv.addGas(at, gas.BURST);
        game.sayAt(g, at, "The {s} bursts, leaving a cloud of caustic gas!", .{name});
    }
    const family = kind.family();
    if (g.pool.tally(family).left == 0) g.log.say("The last {s} is dead.", .{actor.row(family).name});
    scare(g, fallen);
}

pub fn scare(g: *game.Game, fallen: usize) void {
    const at = g.pool.items[fallen].at;
    for (g.pool.slice(), 0..) |*a, i| {
        const row = actor.row(a.kind);
        if (!a.alive or !row.flees or mathx.dist(a.at, at) > actor.FRIGHT_REACH or !grid.clearLine(&g.lv, a.at, at)) continue;
        const steady = a.fright == 0;
        a.fright = actor.FLEE_TURNS;
        a.awake = true;
        if (steady) {
            game.sayAt(g, a.at, "The {s} flees in terror!", .{row.name});
            g.fx.frighten(i, fallen);
        }
    }
}

fn heroDies(g: *game.Game) void {
    g.log.push(.danger, "{s} dies.", .{g.name.text()});
    g.died_in = g.mode;
    g.mode = .dead;
}

/// Brogue turn order; recast sight after carried enemy lights move.
pub fn endTurn(g: *game.Game) void {
    const h = g.heroActor() orelse return;
    g.unsaved = true;
    g.clock.turn();
    game.recover(g);
    for (&g.cooldown.values) |*c| c.* -|= 1;
    defer {
        for (g.pool.slice()) |*a| a.settle();
        g.ran = @splat(game.Ran.initEmpty());
        g.displaced = .initEmpty();
    }
    game.castSight(g, h.at);
    g.flowed = false;
    orderFoes(g, h.at);
    harmAfter(g, g.hero, g.stepped);
    g.stepped = false;
    if (g.mode == .dead) return;
    gas.turn(&g.lv, &g.rng);
    for (g.pool.slice()) |*a| {
        if (a.alive and a.foe()) a.clock.pass(actor.row(a.kind).pace);
    }
    for (g.order[0..g.order_n]) |id| {
        const i = actor.Pool.slot(id);
        const was = g.pool.items[i].at;
        foeTurn(g, id);
        if (g.mode == .dead) return;
        harmAfter(g, id, !g.pool.items[i].at.eq(was));
    }
    var i: usize = 0;
    while (i < g.pool.n) : (i += 1) {
        const a = g.pool.items[i];
        if (!a.alive or !a.waits) continue;
        const id = actor.Pool.idOf(i);
        _ = wearTurn(g, id);
        harmAfter(g, id, false);
    }
    if (g.heroActor()) |a| {
        if (a.ward.turns > 0) {
            a.ward.wear();
            const hero = game.heroSlot(g).?;
            g.owed[hero].worn = .{ .body = snap(g, hero) };
        }
        game.castSight(g, a.at);
    }
}

const Hurt = struct { dmg: i32, lethal: bool, mana: i32 = 0 };

pub const UNKILLABLE_HP: i32 = 1;

pub fn hurt(g: *game.Game, id: u16, dmg: i32) Hurt {
    const a = g.pool.get(id) orelse return .{ .dmg = 0, .lethal = false };
    var left = dmg;
    if (id == g.hero) {
        const took = a.ward.takes(g.mana, dmg);
        if (took > 0) {
            g.mana -= took;
            g.mana_held += took;
            left -= took;
            g.log.say("The mana shield takes {d}.", .{took});
        }
    }
    const taken = if (id == g.hero and g.unkillable) std.math.clamp(a.hp - UNKILLABLE_HP, 0, left) else left;
    return .{ .dmg = taken, .lethal = g.pool.damage(&g.lv, id, taken), .mana = dmg - left };
}

fn harmAfter(g: *game.Game, id: u16, moved: bool) void {
    gasHarm(g, id);
    burnHarm(g, id);
    bleedHarm(g, id, moved or g.displaced.isSet(actor.Pool.slot(id)));
}

fn gasHarm(g: *game.Game, id: u16) void {
    const a = g.pool.get(id) orelse return;
    if (!g.lv.gassy(a.at) or ranAlready(g, id, .gassed)) return;
    _ = harmTick(g, id, gas.harm(a.max), .gassed, .{ .hero = "The caustic gas eats at {s} for {d}." });
}

/// Mark a tick consumed; split halves inherit the parent's consumed ticks.
fn ranAlready(g: *game.Game, id: u16, comptime tick: game.Tick) bool {
    const r = &g.ran[actor.Pool.slot(id)];
    defer r.insert(tick);
    return r.contains(tick);
}

pub fn burnHarm(g: *game.Game, id: u16) void {
    const a = g.pool.get(id) orelse return;
    if (ranAlready(g, id, .burned)) return;
    const dmg = a.burn.tick(a.resists.get(burning.ELEMENT)) orelse return;
    if (dmg == 0) return;
    _ = harmTick(g, id, dmg, .burned, .{ .hero = "Burning sears {s} for {d}.", .foe = "Burning sears the {s} for {d}." });
}

fn bleedHarm(g: *game.Game, id: u16, moved: bool) void {
    const a = g.pool.get(id) orelse return;
    if (ranAlready(g, id, .bled)) return;
    const dmg = a.bleed.tick(moved) orelse return;
    const stopped = a.bleed.turns == 0;
    const foe = "The {s} bleeds for {d}.";
    const h = if (moved)
        harmTick(g, id, dmg, .bled, .{ .hero = "Moving tears {s}'s wound: it bleeds for {d}.", .foe = foe })
    else
        harmTick(g, id, dmg, .bled, .{ .hero = "{s} bleeds for {d}.", .foe = foe });
    if (id == g.hero and stopped and !h.lethal) g.log.say("{s} stops bleeding.", .{g.name.text()});
}

/// Each takes the name and the damage; a foe with no line of its own is said only to die.
const Said = struct { hero: []const u8, foe: ?[]const u8 = null };

fn harmTick(g: *game.Game, id: u16, dmg: i32, comptime owed: game.Tick, comptime said: Said) Hurt {
    const a = g.pool.get(id).?;
    const kind = a.kind;
    const at = a.at;
    const h = hurt(g, id, dmg);
    const hero = id == g.hero;
    const name = actor.row(kind).name;
    if (hero) {
        g.log.push(.danger, said.hero, .{ g.name.text(), h.dmg });
    } else if (comptime said.foe) |line| {
        game.sayAt(g, at, line ++ "{s}", .{ name, h.dmg, if (h.lethal) IT_DIES else "" });
    } else if (h.lethal) game.sayAt(g, at, "The {s} dies.", .{name});
    @field(g.owed[actor.Pool.slot(id)], @tagName(owed)) = .{ .kill = h.lethal, .after = afterBlow(g, id, h) };
    if (h.lethal) {
        if (hero) heroDies(g) else fell(g, id);
    }
    return h;
}

const Worn = struct { held: bool = false, skips: bool = false };

fn wearTurn(g: *game.Game, id: u16) Worn {
    const a = g.pool.get(id) orelse return .{};
    const i = actor.Pool.slot(id);
    if (ranAlready(g, id, .worn) or (a.pin.turns == 0 and a.chill.turns == 0)) return .{};
    const w = Worn{ .held = a.pin.hold(), .skips = a.chill.turns > 0 and a.chill.skip() };
    g.owed[i].worn = .{ .body = snap(g, i) };
    return w;
}

fn orderFoes(g: *game.Game, from: P) void {
    g.order_n = 0;
    for (g.pool.slice(), 0..) |a, i| {
        const id = actor.Pool.idOf(i);
        if (id == g.hero or !a.alive or a.waits) continue;
        g.order[g.order_n] = id;
        g.order_n += 1;
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
    std.mem.sort(u16, g.order[0..g.order_n], Near{ .pool = &g.pool, .from = from }, Near.nearer);
}

fn foeTurn(g: *game.Game, id: u16) void {
    const f = g.pool.get(id) orelse return;
    f.sweep_in -|= 1;
    const stalled = f.clock.stalled;
    const worn = wearTurn(g, id);
    const held = worn.held;
    if (worn.skips or stalled) return;
    const r = g.pool.get(id) orelse return;
    const h = g.heroActor() orelse return;
    const row = actor.row(r.kind);
    if (!r.awake) {
        if (!fov.sees(&g.lv, r.at, h.at, row.sight)) return;
        r.awake = true;
        game.turnLater(g, id, h.at.x - r.at.x);
        game.sayAt(g, r.at, "A {s} notices {s}.", .{ row.name, g.name.text() });
        return;
    }
    if (r.fright > 0) {
        r.fright -= 1;
        if (if (held) null else actor.flee(&g.lv, r.at, id, flowTo(g, h.at))) |d| {
            game.turnLater(g, id, d.delta().x);
            g.pool.move(&g.lv, id, r.at.add(d.delta()));
        } else if (besideWay(g, r.at, h.at)) |d| {
            game.turnLater(g, id, d.delta().x);
            reach(g, id, row);
        }
        if (r.fright == 0) game.sayAt(g, r.at, "The {s} stops running.", .{row.name});
        return;
    }
    const flitted = if (!held and row.flits and g.rng.chance(actor.FLIT)) actor.flit(&g.lv, r.at, id, g.hero, &g.rng) else null;
    const d = flitted orelse foeWay(g, r.at, id, h.at) orelse return;
    const to = r.at.add(d.delta());
    if (held and !to.eq(h.at)) return;
    game.turnLater(g, id, d.delta().x);
    if (to.eq(h.at)) return reach(g, id, row);
    g.pool.move(&g.lv, id, to);
}

fn foeWay(g: *game.Game, at: P, id: u16, hero: P) ?mathx.Dir {
    return besideWay(g, at, hero) orelse actor.chase(&g.lv, at, id, flowTo(g, hero));
}

fn besideWay(g: *const game.Game, at: P, hero: P) ?mathx.Dir {
    const d = mathx.dirTo(at, hero) orelse return null;
    return if (g.lv.passOk(at, d)) d else null;
}

fn flowTo(g: *game.Game, hero: P) *const [grid.CELLS]i32 {
    if (!g.flowed) {
        _ = grid.distances(&g.lv, hero, &g.flow, &g.queue);
        g.flowed = true;
    }
    return &g.flow;
}

/// The strike's damage, or null when the hero dodges it; the dodge is drawn first.
pub fn bite(rng: *mathx.Rng, by: attrs.Attrs, s: actor.Strike) ?i32 {
    if (by.dodges(rng)) return null;
    return s.roll(rng);
}

fn reach(g: *game.Game, id: u16, row: actor.Row) void {
    const i = actor.Pool.slot(id);
    switch (row.blow) {
        .strike => |s| {
            const sweeps = sweepReady(g, id, row);
            if (sweeps) sweepRound(g, id, row, s);
            const verb = if (sweeps) actor.SWEEP_VERB else s.verb;
            const dmg = bite(&g.rng, game.heroAttrs(g), s) orelse {
                g.log.say("{s} dodges the {s}.", .{ g.name.text(), row.name });
                g.owed[i].bit = .miss;
                return;
            };
            const h = hurt(g, g.hero, game.heroAttrs(g).physical(dmg, &g.rng));
            const lethal = h.lethal;
            g.log.push(.danger, "The {s} {s} {s} for {d}.", .{ row.name, verb, g.name.text(), h.dmg });
            if (!lethal and h.dmg > 0 and damage.procs(&g.rng, s.bleeds)) {
                const b = &g.heroActor().?.bleed;
                g.log.say("{s} {s}!", .{ g.name.text(), if (b.turns == 0) bleeding.TAKES else "bleeds anew" });
                b.start();
            }
            if (!lethal and damage.procs(&g.rng, s.stuns)) {
                g.heroActor().?.clock.stun();
                g.log.say("{s} " ++ turn_clock.STUNNED ++ "!", .{g.name.text()});
            }
            const after = afterBlow(g, g.hero, h);
            g.owed[i].bit = if (lethal) .{ .kill = after } else .{ .hurt = after };
            if (lethal) heroDies(g);
        },
        .burst => {
            const a = g.pool.get(id).?.*;
            _ = g.pool.damage(&g.lv, id, a.hp);
            g.owed[i].bit = .{ .burst = .{ .body = snap(g, i) } };
            fell(g, id);
        },
    }
}

fn sweepReady(g: *game.Game, id: u16, row: actor.Row) bool {
    const a = g.pool.get(id).?;
    if (row.sweep_every == 0 or a.sweep_in > 0) return false;
    a.sweep_in = row.sweep_every;
    return true;
}

/// Every body and barrel round the sweeper but the hero, snapshot before any blow so newborn halves are spared.
fn sweepRound(g: *game.Game, id: u16, row: actor.Row, s: actor.Strike) void {
    const from = g.pool.get(id).?.at;
    const cells = actor.sweep(&g.lv, from);
    var struck: [actor.SWEEP_CELLS]u16 = undefined;
    for (cells.slice(), struck[0..cells.n]) |p, *w| w.* = g.lv.who(p);
    var swept = game.Swept{};
    for (cells.slice(), struck[0..cells.n]) |p, w| {
        if (w == g.hero) continue;
        const hit = if (w != grid.NO_ONE) swipe(g, w, row, s) else smashedBy(g, p, row) orelse continue;
        swept.hit[swept.n] = hit;
        swept.n += 1;
    }
    if (swept.n > 0) g.owed[actor.Pool.slot(id)].swept = swept;
}

fn swipe(g: *game.Game, id: u16, by: actor.Row, s: actor.Strike) game.Swipe {
    const a = g.pool.get(id).?;
    const at = a.at;
    const name = actor.row(a.kind).name;
    const dmg = s.roll(&g.rng);
    const stunned = dmg < a.hp and damage.procs(&g.rng, s.stuns);
    if (stunned) a.clock.stun();
    const h = hurt(g, id, dmg);
    game.sayAt(g, at, "The {s} " ++ actor.SWEEP_VERB ++ " the {s} for {d}.{s}", .{ by.name, name, h.dmg, if (h.lethal) IT_DIES else "" });
    if (stunned) game.sayAt(g, at, "The {s} " ++ turn_clock.STUNNED ++ "!", .{name});
    const after = afterBlow(g, id, h);
    if (h.lethal) fell(g, id);
    return .{ .slot = actor.Pool.slot(id), .at = at, .lethal = h.lethal, .after = after };
}

fn smashedBy(g: *game.Game, p: P, by: actor.Row) ?game.Swipe {
    if (!g.lv.breakBarrel(p)) return null;
    const gold = loot(g, p, items.BARREL_GOLD);
    game.sayAt(g, p, "The {s} smashes the barrel. It drops {d} gold.", .{ by.name, gold });
    return .{ .slot = null, .at = p, .lethal = true };
}
