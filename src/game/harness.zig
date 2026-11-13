const attacks = @import("attacks.zig");
const std = @import("std");
const affixes = @import("../play/affixes.zig");
const item_bases = @import("../play/item_bases.zig");
const items = @import("../play/items.zig");
const loot = @import("../play/loot.zig");
const progress = @import("../play/progress.zig");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const menu = @import("../ui/menu.zig");
const heroes = @import("../play/hero.zig");
const actor = @import("../play/actor.zig");
const damage = @import("../play/damage.zig");
const attrs = @import("../play/attrs.zig");
const skillbar = @import("../play/skillbar.zig");
const day = @import("../map/day.zig");
const atlas = @import("../map/atlas.zig");
const carve = @import("../map/carve.zig");
const combat = @import("combat.zig");
const game = @import("../game.zig");
const skills = @import("skills.zig");
const bow = @import("../play/bow.zig");
const P = mathx.P;
const CONFIRM = menu.CONFIRM;

pub fn arena(g: *game.Game, hero: P, rats: []const P) void {
    heroArena(g, heroes.DEFAULT, hero, rats);
}

pub fn heroArena(g: *game.Game, c: heroes.Class, hero: P, rats: []const P) void {
    g.sim.class = c;
    g.sim.lv = grid.openFloor();
    game.reset(g, hero);
    for (progress.skills(g.sim.class)) |s| g.sim.growth.ranks.set(s.act, 1);
    g.bar = skillbar.Bar.of(g.sim.class);
    g.sim.outdoors = true;
    g.sim.clock = day.Clock.at(day.NOON);
    for (rats) |r| _ = g.sim.pool.spawn(&g.sim.lv, actor.Actor.of(.rat, r));
    game.settle(g);
}

pub fn grassArena(g: *game.Game, hero: P, rats: []const P) void {
    arena(g, hero, rats);
    grassOver(&g.sim.lv);
}

pub fn rngWhere(want: anytype) mathx.Rng {
    var seed: u64 = 0;
    while (true) : (seed += 1) {
        var rng = mathx.Rng.init(seed);
        if (want.holds(&rng)) return mathx.Rng.init(seed);
    }
}

pub fn procRng(g: *const game.Game, comptime act: skillbar.Act, procs: usize, want: bool) mathx.Rng {
    const Procs = struct {
        by: attrs.Attrs,
        style: attrs.Style,
        bases: skillbar.EquippedBases,
        n: usize,
        want: bool,
        fn holds(p: @This(), rng: *mathx.Rng) bool {
            var raw = attacks.rollRaw(rng, act, p.bases);
            for (0..p.n) |_| {
                _ = attacks.scaled(rng, p.by, p.style, raw);
                if (skillbar.Act.skill(act).procs(rng, 0) != p.want) return false;
                raw.physical = 0;
            }
            return true;
        }
    };
    const b = attacks.blowFor(&g.sim, act);
    return rngWhere(Procs{ .by = b.by, .style = b.style, .bases = b.bases, .n = procs, .want = want });
}

pub fn foes(g: *game.Game) []actor.Actor {
    return g.sim.pool.slice()[1..];
}

pub fn foeId(i: usize) u16 {
    return actor.Pool.idOf(foeSlot(i));
}

pub fn foeSlot(i: usize) usize {
    return i + 1;
}

pub fn wakeFoes(g: *game.Game) void {
    for (foes(g)) |*a| a.awake = true;
}

pub fn toughenFoes(g: *game.Game) void {
    for (foes(g)) |*a| toughen(a);
}

pub fn logged(g: *const game.Game, needle: []const u8) bool {
    for (0..g.sim.log.n) |i| {
        if (std.mem.indexOf(u8, g.sim.log.line(i).?, needle) != null) return true;
    }
    return false;
}

pub fn staggerOnly(g: *game.Game, id: u16) void {
    g.sim.order[0] = id;
    g.sim.order_n = 1;
    stagger(g);
}

pub fn stagger(g: *game.Game) void {
    g.pic.lead = 0;
    g.pic.stepGlide(&g.sim, g.cloud, 0);
}

pub fn stepTo(g: *game.Game, id: u16, to: P) void {
    g.sim.pool.move(&g.sim.lv, id, to);
    g.pic.stepGlide(&g.sim, g.cloud, 0);
}

pub const TRIES: usize = 300;

pub fn aboutRate(hits: usize, rate: f32) bool {
    return aboutRateOf(hits, TRIES, rate);
}

const RATE_TOL: f32 = 0.08;

pub fn aboutRateOf(hits: usize, of: usize, rate: f32) bool {
    const got = @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(of));
    return @abs(got - rate) < RATE_TOL;
}

pub fn deathDrawn(g: *game.Game, _: usize) bool {
    return game.deathShown(g);
}

pub fn calm(g: *game.Game) void {
    g.pic.busy = 0;
    g.pending = null;
}

pub fn press(g: *game.Game, a: input.Button) void {
    pressHolding(g, a, &.{});
}

pub fn openDebug(g: *game.Game) void {
    pickPause(g, .debug);
}

pub fn pickPause(g: *game.Game, row: game.PauseRow) void {
    press(g, menu.PAUSE);
    for (0..game.rowAt(row)) |_| nudge(g, .s);
    press(g, CONFIRM);
}

pub fn clickAt(g: *game.Game, p: P) void {
    g.st = .{ .device = .keys, .click = true, .pointer = p };
    game.update(g, 0);
}

pub fn clickCell(g: *game.Game, at: P) void {
    clickAt(g, game.scene.Cam.of(g).mid(at));
}

pub fn pressInteract(g: *game.Game) void {
    g.st = .{ .interact = true, .pressed = .initOne(CONFIRM), .down = .initOne(CONFIRM) };
    game.update(g, 0);
}

pub fn use(g: *game.Game, act: skillbar.Act) void {
    const u = boundTo(g, act);
    if (u.set == .secondary) pressHolding(g, u.by.?, &.{g.bar.modifier.?}) else press(g, u.by.?);
}

pub fn confirmUse(g: *game.Game, act: skillbar.Act) void {
    use(g, act);
    press(g, CONFIRM);
}

pub fn useAct(g: *game.Game, act: skillbar.Act) void {
    skills.useSkill(g, .{ .act = act, .by = null });
}

pub fn aimAt(g: *game.Game, act: skillbar.Act, at: P) void {
    useAct(g, act);
    if (g.mode != .aim) return;
    g.mode.aim.mark = at;
    skills.confirmAim(g);
    if (g.mode == .aim and g.mode.aim.askedHere()) skills.confirmAim(g);
}

pub fn boundTo(g: *const game.Game, act: skillbar.Act) skills.Use {
    const s = g.bar.slotOf(act).?;
    return .{ .act = act, .by = s.button, .set = s.set };
}

/// Wall from `lo` to `hi`, both inclusive.
pub fn wallIn(lv: *grid.Level, lo: P, hi: P) void {
    carve.box(lv, grid.Box.between(lo, hi), .wall);
}

pub fn wallRow(lv: *grid.Level, y: i32, x0: i32, x1: i32) void {
    wallIn(lv, .{ .x = x0, .y = y }, .{ .x = x1, .y = y });
}

pub fn hemIn(lv: *grid.Level, at: P, open: ?P) void {
    for (mathx.ALL_DIRS) |d| {
        const p = at.add(d.delta());
        if (open == null or !p.eq(open.?)) lv.set(p, .wall);
    }
}

pub fn sameRgb(a: rl.Color, b: rl.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b;
}

fn grassOver(lv: *grid.Level) void {
    retile(lv, .floor, .grass);
}

pub fn retile(lv: *grid.Level, from: grid.Tile, to: grid.Tile) void {
    for (&lv.tile) |*t| {
        if (t.* == from) t.* = to;
    }
}

pub fn expectWithin(v: anytype, lo: @TypeOf(v), hi: @TypeOf(v)) !void {
    if (v < lo or v > hi) {
        std.debug.print("{d} is outside {d} to {d}\n", .{ v, lo, hi });
        return error.TestUnexpectedResult;
    }
}

pub fn expectDamage(g: *const game.Game, comptime act: skillbar.Act, dealt: i32, ranges: []const damage.Base) !void {
    const b = attacks.blowFor(&g.sim, act);
    var lo: i32 = 0;
    var hi: i32 = 0;
    for (ranges) |r| {
        lo += b.by.dealt(b.style, r.lo, false).least();
        hi += b.by.dealt(b.style, r.hi, true).most();
    }
    try expectWithin(dealt, lo, hi);
}

pub const FoeAttack = struct { id: u16, lands: bool };

fn combatant(g: *const game.Game, id: u16) *const actor.Actor {
    return g.sim.pool.getConst(id).?;
}

fn foeAttacksHold(g: *const game.Game, hero_at: P, foe_attacks: []const FoeAttack, rng: *mathx.Rng) bool {
    const hero = g.sim.heroBody().?;
    const defender = g.sim.combatStatsOn(hero, g.sim.lv.at(hero_at), hero.resilience, hero.sunder);
    for (foe_attacks, 0..) |b, i| {
        const a = combatant(g, b.id);
        const strike = actor.row(a.kind).blow.strike;
        const hit = attacks.foeRoll(rng, g.sim.combatStats(a), defender, strike);
        if ((hit != null) != b.lands) return false;
        if (i + 1 < foe_attacks.len) armourBefore(g, strike, defender.armour, hit, rng);
    }
    return true;
}

fn armourBefore(g: *const game.Game, strike: actor.Strike, armour: i32, hit: ?i32, rng: *mathx.Rng) void {
    std.debug.assert(strike.bleeds == 0 and strike.stuns == 0 and g.sim.heroAttrs().thorns == 0 and !g.sim.heroBody().?.tactics.unyielding);
    if (hit) |dmg| _ = attrs.armoured(armour, dmg, rng);
}

pub fn foeAttacksRng(g: *const game.Game, foe_attacks: []const FoeAttack) mathx.Rng {
    return foeAttacksRngAt(g, g.sim.heroAt().?, foe_attacks);
}

pub fn foeAttacksRngAt(g: *const game.Game, hero_at: P, foe_attacks: []const FoeAttack) mathx.Rng {
    const FoeAttacks = struct {
        g: *const game.Game,
        hero_at: P,
        foe_attacks: []const FoeAttack,

        fn holds(b: @This(), rng: *mathx.Rng) bool {
            return foeAttacksHold(b.g, b.hero_at, b.foe_attacks, rng);
        }
    };
    return rngWhere(FoeAttacks{ .g = g, .hero_at = hero_at, .foe_attacks = foe_attacks });
}

pub fn sweepStunRng(g: *const game.Game, sweeper: u16, victim: u16, after_attack: bool) mathx.Rng {
    const Stun = struct {
        g: *const game.Game,
        sweeper: u16,
        victim: u16,
        after_attack: bool,

        fn holds(s: @This(), rng: *mathx.Rng) bool {
            if (s.after_attack) {
                const a = combatant(s.g, s.victim);
                const hero = s.g.sim.combatStats(s.g.sim.heroBody().?);
                if (attacks.foeRoll(rng, s.g.sim.combatStats(a), hero, actor.row(a.kind).blow.strike)) |dmg| _ = attrs.armoured(hero.armour, dmg, rng);
            }
            const attacker = combatant(s.g, s.sweeper);
            const target = combatant(s.g, s.victim);
            const defender = s.g.sim.combatStats(target);
            std.debug.assert(defender.statuses.get(.stun) == 0);
            const strike = actor.row(attacker.kind).blow.strike;
            const hit = attacks.foeRoll(rng, s.g.sim.combatStats(attacker), defender, strike) orelse return false;
            const dmg = attrs.armoured(defender.armour, hit, rng);
            if (dmg <= 0 or dmg >= target.hp) return false;
            return damage.procs(rng, strike.stuns);
        }
    };
    return rngWhere(Stun{ .g = g, .sweeper = sweeper, .victim = victim, .after_attack = after_attack });
}

pub fn lootRng(magic: ?bool) mathx.Rng {
    const Loot = struct {
        magic: ?bool,

        fn holds(l: @This(), rng: *mathx.Rng) bool {
            const reward = loot.foeLoot(rng, 0);
            if (reward.gold <= 0) return false;
            const m = l.magic orelse return true;
            const it = reward.item orelse return false;
            return it.magical() == m;
        }
    };
    return rngWhere(Loot{ .magic = magic });
}

pub fn barrelRng(item: bool) mathx.Rng {
    const Barrel = struct {
        item: bool,

        fn holds(b: @This(), rng: *mathx.Rng) bool {
            return (loot.barrelLoot(rng, true).item != null) == b.item;
        }
    };
    return rngWhere(Barrel{ .item = item });
}

pub const LETHAL_DMG: i32 = 1000;
const SLAY_WAIT_S: f32 = 0.2;

pub fn slay(g: *game.Game, id: u16, from: P) void {
    combat.wound(g, id, .{ .dmg = LETHAL_DMG }, combat.SHOOT, .{ .from = from, .wait = SLAY_WAIT_S });
}

pub fn kill(g: *game.Game, id: u16, from: P, wait: f32) void {
    combat.wound(g, id, .{ .dmg = LETHAL_DMG, .hit_checked = true }, combat.SHOOT, .{ .from = from, .wait = wait });
}

pub fn meleeThenFoeAttacks(g: *const game.Game, target: u16, attackers: []const u16) mathx.Rng {
    const Sequence = struct {
        g: *const game.Game,
        target: u16,
        attackers: []const u16,
        fn holds(s: @This(), rng: *mathx.Rng) bool {
            const gear = &s.g.sim.inventory.gear;
            const effect = gear.onHit(.melee);
            std.debug.assert(effect.bleed == 0 and effect.stun == 0);
            const hit = attacks.heroRollWith(rng, &s.g.sim, .melee, attacks.meleeRaw(rng, gear, s.g.sim.class.strike()));
            const hero = s.g.sim.heroBody().?;
            const target_actor = combatant(s.g, s.target);
            if (s.g.sim.combatStats(hero).misses(s.g.sim.combatStats(target_actor), rng)) return false;
            _ = hit.against(s.g.sim.combatStats(target_actor).armour, rng);
            var landing: [actor.MAX]FoeAttack = undefined;
            for (s.attackers, landing[0..s.attackers.len]) |id, *b| b.* = .{ .id = id, .lands = true };
            return foeAttacksHold(s.g, hero.at, landing[0..s.attackers.len], rng);
        }
    };
    return rngWhere(Sequence{ .g = g, .target = target, .attackers = attackers });
}

pub fn nudge(g: *game.Game, d: mathx.Dir) void {
    calm(g);
    g.st = .{ .walk = d };
    game.update(g, 0);
}

pub fn walkFrame(g: *game.Game, dt: f32, d: ?mathx.Dir) void {
    g.st.walk = if (d) |w| g.st.step.tick(dt, 1, w.heading(), input.Stepper.SETTLE) else g.st.step.tick(dt, 0, 0, input.Stepper.SETTLE);
    game.update(g, dt);
}

pub fn walkFor(g: *game.Game, secs: f32, d: ?mathx.Dir) void {
    var t: f32 = 0;
    while (t < secs) : (t += TEST_DT) walkFrame(g, TEST_DT, d);
}

pub fn pressWalking(g: *game.Game, b: input.Button, d: ?mathx.Dir) void {
    g.st.pressed.insert(b);
    walkFrame(g, TEST_DT, d);
    g.st.pressed = .initEmpty();
}

pub const TEST_DT = mathx.TEST_DT;
pub const TEST_TOL: f32 = TEST_DT * 1.5;
pub const FADING_S: f32 = 0.04;
pub const FADE_FRAMES = 120;
pub const FADED: f32 = 0.99;
pub const UNFADED: f32 = 0.01;

const UNTIL_CAP_S: f32 = 1;
const DRAWN_OUT_CAP_S: f32 = 2;

fn framesWhile(g: *game.Game, cap: f32, ctx: anytype) f32 {
    g.st = .{};
    var t: f32 = 0;
    while (t < cap and !ctx.met(g)) : (t += TEST_DT) game.update(g, TEST_DT);
    return t;
}

pub fn framesUntil(g: *game.Game, slot: usize, comptime done: fn (*game.Game, usize) bool) f32 {
    const Until = struct {
        slot: usize,
        fn met(u: @This(), run: *game.Game) bool {
            return done(run, u.slot);
        }
    };
    return framesWhile(g, UNTIL_CAP_S, Until{ .slot = slot });
}

pub fn untilCaughtUp(g: *game.Game, slots: []const usize) f32 {
    const AllCaughtUp = struct {
        slots: []const usize,
        fn met(a: @This(), run: *game.Game) bool {
            for (a.slots) |s| if (!caughtUp(run, s)) return false;
            return true;
        }
    };
    return framesWhile(g, UNTIL_CAP_S, AllCaughtUp{ .slots = slots });
}

pub fn idleFor(g: *game.Game, secs: f32) void {
    var t: f32 = 0;
    while (t < secs) : (t += TEST_DT) game.update(g, TEST_DT);
}

pub fn flashing(g: *game.Game, slot: usize) bool {
    return g.pic.fx.impacts.flashOf(.fromIndex(slot)) > 0;
}

pub fn facesLeft(g: *game.Game, slot: usize) bool {
    return g.pic.facing[slot] == .left;
}

pub fn undrawn(g: *game.Game, slot: usize) bool {
    return g.pic.drawnAt(&g.sim, slot) == null;
}

pub fn drawn(g: *game.Game, slot: usize) bool {
    return !undrawn(g, slot);
}

/// An arrow shot from `SHOT_FROM` at `SHOT_AT`, its full reach off, lands `SHOT_LANDS` in.
pub const SHOT_FROM = P{ .x = 22, .y = 20 };
pub const SHOT_AT = P{ .x = SHOT_FROM.x + bow.RANGE, .y = SHOT_FROM.y };
pub const SHOT_LANDS = game.presentation.flown(bow.RANGE - 1);

pub const TEST_HP: i32 = 100;
pub const TEST_MANA: i32 = 99;

pub fn toughen(a: *actor.Actor) void {
    setLife(a, TEST_HP, TEST_HP);
}

pub fn affixed(kind: item_bases.Kind, affix: affixes.Affix) items.Item {
    var it = items.Item{ .kind = kind };
    it.mods[0] = affix;
    return it;
}

pub const HARVEST_LIFE: i32 = 2;

pub fn harvestRing() items.Item {
    return affixed(.ring, .{ .kind = .life_on_kill, .value = HARVEST_LIFE });
}

pub fn bleedingOut(a: *actor.Actor) void {
    a.hp = 1;
    a.bleed.startWith(2);
    a.bleed.fresh = false;
}

pub const TEST_GAS = 100;
pub const SLIME_HALF = actor.row(.slime_half).hp;

pub fn expectGroundShown(g: *game.Game) !void {
    const ground = g.pic.groundShown(&g.sim);
    for (ground.tile, 0..) |t, i| try std.testing.expectEqual(g.pic.tileShown(&g.sim, grid.Level.of(i)), t);
}

pub fn drawnOut(g: *game.Game) void {
    const Settled = struct {
        fn met(_: @This(), run: *game.Game) bool {
            return !(run.pic.busy > 0 or turningAny(run));
        }
    };
    _ = framesWhile(g, DRAWN_OUT_CAP_S, Settled{});
}

pub const FADED_S: f32 = 0.6;

pub fn ease(g: *game.Game, dt: f32) void {
    g.pic.easeOver(&g.sim, g.pic.groundShown(&g.sim), dt);
}

pub fn turned(clock: day.Clock, n: usize) day.Clock {
    var next = clock;
    for (0..n) |_| _ = next.turn();
    return next;
}

fn turningAny(g: *game.Game) bool {
    for (g.pic.turning) |t| {
        if (t != null) return true;
    }
    return false;
}

pub fn samePx(a: rl.Vector2, b: rl.Vector2) bool {
    return @abs(a.x - b.x) < 1e-3 and @abs(a.y - b.y) < 1e-3;
}

pub fn reddened(g: *game.Game, _: usize) bool {
    return g.vignette.alpha() > 0;
}

pub fn pressHolding(g: *game.Game, a: input.Button, held: []const input.Button) void {
    calm(g);
    g.st = .{};
    g.st.pressed.insert(a);
    g.st.down.insert(a);
    for (held) |h| g.st.down.insert(h);
    game.update(g, 0);
}

pub fn spawnAt(g: *game.Game, k: actor.Kind, at: P, awake: bool) u16 {
    const id = g.sim.pool.spawn(&g.sim.lv, actor.Actor.of(k, at));
    g.sim.pool.get(id).?.awake = awake;
    g.pic.snapGlide(&g.sim.pool);
    return id;
}

pub fn openMimic(g: *game.Game, at: P) u16 {
    const id = spawnAt(g, .mimic, at, true);
    g.sim.pool.get(id).?.unmask(&g.sim.lv);
    return id;
}

pub fn setLife(a: *actor.Actor, hp: i32, max: i32) void {
    a.hp = hp;
    a.max = max;
}

pub fn corridor(b: *atlas.Bespoke) void {
    var x: i32 = 2;
    while (x <= 12) : (x += 1) b.tile[grid.Level.idx(.{ .x = x, .y = 5 })] = .floor;
}

pub fn twoRooms(w: *atlas.Atlas) usize {
    w.* = .{};
    const a = w.add(.{ .bespoke = .{} }).?;
    const b = w.add(.{ .bespoke = .{} }).?;
    for ([_]usize{ a, b }) |n| corridor(&w.node[n].plan.bespoke);
    const da = w.addDoor(a, .{ .x = 2, .y = 5 }).?;
    const db = w.addDoor(b, .{ .x = 11, .y = 5 }).?;
    w.link(.{ .node = a, .door = da }, .{ .node = b, .door = db });
    w.start = .{ .node = a, .at = .{ .x = 3, .y = 5 } };
    return b;
}

pub fn splittable(g: *game.Game, at: P, awake: bool) u16 {
    const id = spawnAt(g, .slime, at, awake);
    g.sim.pool.get(id).?.hp = SLIME_HALF + 1;
    return id;
}

pub fn bittenToDeath(g: *game.Game) void {
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    wakeFoes(g);
    g.sim.heroActor().?.hp = 1;
    nudge(g, .e);
}

pub fn idle(g: *game.Game) void {
    calm(g);
    g.st = .{};
    game.update(g, 0);
}

pub fn caughtUp(g: *game.Game, slot: usize) bool {
    return g.pic.pictured[slot].hp == g.sim.pool.items[slot].hp;
}

test "predicted foe strikes follow terrain and ordered armour rolls in real turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    for (heroes.CLASSES) |class| for ([_]grid.Tile{ .floor, .reeds }) |tile| {
        for ([_]bool{ false, true }) |first| for ([_]bool{ false, true }) |second| {
            heroArena(g, class, at, &.{});
            g.sim.lv.set(at, tile);
            g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather });
            game.syncStats(g);
            const near = spawnAt(g, .bandit_crossbowman, .{ .x = 23, .y = 20 }, true);
            const far = spawnAt(g, .bandit_crossbowman, .{ .x = 20, .y = 24 }, true);
            g.sim.lv.set(g.sim.pool.get(near).?.at, .reeds);
            g.sim.rng = foeAttacksRng(g, &.{ .{ .id = near, .lands = first }, .{ .id = far, .lands = second } });
            combat.endTurn(g);
            for ([_]u16{ near, far }, [_]bool{ first, second }) |id, landed| {
                const hit = g.pic.owed[actor.Pool.slot(id)].foe_hit.?;
                try std.testing.expectEqual(!landed, hit == .miss);
            }
        };
    };
}

test "a strike with zero dodge draws only terrain hit chance and damage" {
    const terrain = @import("../play/terrain.zig");
    const strike = actor.row(.rat).blow.strike;
    for ([_]grid.Tile{ .floor, .reeds }) |tile| for (0..256) |seed| {
        var rng = mathx.Rng.init(seed);
        var expected = rng;
        const attacker = (terrain.Stats{}).onRained(tile, 0);
        const lands = attacker.hit == mathx.PERCENT or expected.percent(attacker.hit);
        const want: ?i32 = if (lands) strike.roll(&expected) else null;
        try std.testing.expectEqual(want, attacks.foeRoll(&rng, attacker, .{}, strike));
        try std.testing.expectEqualDeep(expected, rng);
    };
}
