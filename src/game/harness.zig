const std = @import("std");
const items = @import("../play/items.zig");
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
const P = mathx.P;
const CONFIRM = menu.CONFIRM;

pub fn arena(g: *game.Game, hero: P, rats: []const P) void {
    heroArena(g, heroes.DEFAULT, hero, rats);
}

pub fn heroArena(g: *game.Game, c: heroes.Class, hero: P, rats: []const P) void {
    g.class = c;
    g.lv = grid.openFloor();
    game.reset(g, hero);
    for (progress.skills(g.class)) |s| g.growth.ranks.set(s.act, 1);
    g.bar = skillbar.Bar.of(g.class);
    g.outdoors = true;
    g.clock = day.Clock.at(day.NOON);
    for (rats) |r| _ = g.pool.spawn(&g.lv, actor.Actor.of(.rat, r));
    game.settle(g);
}

fn rngWhere(want: anytype) mathx.Rng {
    var seed: u64 = 0;
    while (true) : (seed += 1) {
        var rng = mathx.Rng.init(seed);
        if (want.holds(&rng)) return mathx.Rng.init(seed);
    }
}

/// An RNG matching `confirmAim` under which the first `procs` body hits, the direct one first, afflict or not as `want` says.
pub fn procRng(g: *const game.Game, comptime act: skillbar.Act, procs: usize, want: bool) mathx.Rng {
    const Procs = struct {
        by: attrs.Attrs,
        style: attrs.Style,
        bases: skillbar.EquippedBases,
        n: usize,
        want: bool,
        fn holds(p: @This(), rng: *mathx.Rng) bool {
            var raw = combat.rollRaw(rng, act, p.bases, true);
            for (0..p.n) |_| {
                _ = combat.scaled(rng, p.by, p.style, raw);
                if (skillbar.Act.skill(act).procs(rng, 0) != p.want) return false;
                raw.physical = 0;
            }
            return true;
        }
    };
    const b = combat.blowFor(g, act);
    return rngWhere(Procs{ .by = b.by, .style = b.style, .bases = b.bases, .n = procs, .want = want });
}

pub fn foes(g: *game.Game) []actor.Actor {
    return g.pool.slice()[1..];
}

pub fn wakeFoes(g: *game.Game) void {
    for (foes(g)) |*a| a.awake = true;
}

pub fn toughenFoes(g: *game.Game) void {
    for (foes(g)) |*a| toughen(a);
}

pub fn logged(g: *const game.Game, needle: []const u8) bool {
    for (0..g.log.n) |i| {
        if (std.mem.indexOf(u8, g.log.line(i).?, needle) != null) return true;
    }
    return false;
}

pub fn staggerOnly(g: *game.Game, id: u16) void {
    g.order[0] = id;
    g.order_n = 1;
    g.lead = 0;
    game.stepGlide(g, 0);
}

pub fn stepTo(g: *game.Game, id: u16, to: P) void {
    g.pool.move(&g.lv, id, to);
    game.stepGlide(g, 0);
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
    g.busy = 0;
    g.pending = null;
}

pub fn press(g: *game.Game, a: input.Button) void {
    pressHolding(g, a, &.{});
}

pub fn openDebug(g: *game.Game) void {
    press(g, menu.PAUSE);
    for (0..game.rowAt(game.PauseRow.debug)) |_| nudge(g, .s);
    press(g, CONFIRM);
}

pub fn pressInteract(g: *game.Game) void {
    g.st = .{ .interact = true, .pressed = .initOne(CONFIRM), .down = .initOne(CONFIRM) };
    game.update(g, 0);
}

pub fn use(g: *game.Game, act: skillbar.Act) void {
    const u = boundTo(g, act);
    if (u.set == .secondary) pressHolding(g, u.by, &.{g.bar.modifier.?}) else press(g, u.by);
}

pub fn confirmUse(g: *game.Game, act: skillbar.Act) void {
    use(g, act);
    press(g, CONFIRM);
}

pub fn boundTo(g: *const game.Game, act: skillbar.Act) skills.Use {
    for (skillbar.SETS) |s| {
        if (g.bar.buttonOf(s, act)) |b| return .{ .act = act, .by = b, .set = s };
    }
    unreachable;
}

/// Wall from `lo` to `hi`, both inclusive.
pub fn wallIn(lv: *grid.Level, lo: P, hi: P) void {
    carve.box(lv, grid.Box.between(lo, hi), .wall);
}

pub fn wallRow(lv: *grid.Level, y: i32, x0: i32, x1: i32) void {
    wallIn(lv, .{ .x = x0, .y = y }, .{ .x = x1, .y = y });
}

pub fn grassOver(lv: *grid.Level) void {
    for (&lv.tile) |*t| {
        if (t.* == .floor) t.* = .grass;
    }
}

pub fn expectWithin(v: anytype, lo: @TypeOf(v), hi: @TypeOf(v)) !void {
    if (v < lo or v > hi) {
        std.debug.print("{d} is outside {d} to {d}\n", .{ v, lo, hi });
        return error.TestUnexpectedResult;
    }
}

pub fn expectDamage(g: *const game.Game, comptime act: skillbar.Act, dealt: i32, ranges: []const damage.Base) !void {
    const b = combat.blowFor(g, act);
    var lo: i32 = 0;
    var hi: i32 = 0;
    for (ranges) |r| {
        lo += b.by.dealt(b.style, r.lo, false).least();
        hi += b.by.dealt(b.style, r.hi, true).most();
    }
    try expectWithin(dealt, lo, hi);
}

/// An RNG under which the next strikes by `kind` land, or are dodged, as `lands` says.
pub fn bitesRng(g: *const game.Game, comptime kind: actor.Kind, lands: []const bool) mathx.Rng {
    const s = comptime actor.row(kind).blow.strike;
    std.debug.assert(lands.len <= 1 or s.bleeds == 0);
    const Bites = struct {
        by: attrs.Attrs,
        lands: []const bool,

        fn holds(b: @This(), rng: *mathx.Rng) bool {
            for (b.lands) |l| {
                if ((combat.bite(rng, b.by, s) != null) != l) return false;
            }
            return true;
        }
    };
    return rngWhere(Bites{ .by = game.heroAttrs(g), .lands = lands });
}

pub fn sweepStunRng(g: *const game.Game, after_bite: bool) mathx.Rng {
    const strike = comptime actor.row(.beefy_pib).blow.strike;
    const Stun = struct {
        by: attrs.Attrs,
        after_bite: bool,

        fn holds(s: @This(), rng: *mathx.Rng) bool {
            if (s.after_bite) {
                if (combat.bite(rng, s.by, actor.row(.rat).blow.strike)) |dmg| _ = s.by.physical(dmg, rng);
            }
            _ = strike.roll(rng);
            return damage.procs(rng, strike.stuns);
        }
    };
    return rngWhere(Stun{ .by = game.heroAttrs(g), .after_bite = after_bite });
}

pub fn lootRng(magic: ?bool) mathx.Rng {
    const Loot = struct {
        magic: ?bool,

        fn holds(l: @This(), rng: *mathx.Rng) bool {
            const reward = items.foeLoot(rng);
            if (reward.gold <= 0) return false;
            const m = l.magic orelse return true;
            const it = reward.item orelse return false;
            return it.magical() == m;
        }
    };
    return rngWhere(Loot{ .magic = magic });
}

pub fn slay(g: *game.Game, id: u16, from: P) void {
    combat.wound(g, id, .{ .dmg = 1000 }, combat.SHOOT, .{ .from = from, .wait = 0.2 });
}

pub fn meleeThenBites(g: *const game.Game, count: usize) mathx.Rng {
    const Sequence = struct {
        by: attrs.Attrs,
        gear: *const items.Gear,
        strike: actor.Strike,
        n: usize,
        fn holds(s: @This(), rng: *mathx.Rng) bool {
            const raw = game.kickRaw(rng, s.gear, s.strike);
            _ = combat.scaled(rng, s.by, s.gear.scaling(.melee), .{ .physical = raw });
            for (0..s.n) |_| if (combat.bite(rng, s.by, actor.row(.rat).blow.strike) == null) return false;
            return true;
        }
    };
    return rngWhere(Sequence{ .by = game.heroAttrs(g), .gear = &g.inventory.gear, .strike = g.class.strike(), .n = count });
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

/// Seconds of idle frames until `done(g, slot)`, a second at most.
pub fn framesUntil(g: *game.Game, slot: usize, comptime done: fn (*game.Game, usize) bool) f32 {
    g.st = .{};
    var t: f32 = 0;
    while (!done(g, slot) and t < 1) : (t += TEST_DT) game.update(g, TEST_DT);
    return t;
}

pub fn flashing(g: *game.Game, slot: usize) bool {
    return g.fx.flashOf(slot) > 0;
}

pub fn facesLeft(g: *game.Game, slot: usize) bool {
    return g.facing[slot] == .left;
}

pub fn gone(g: *game.Game, slot: usize) bool {
    return game.drawnAt(g, slot) == null;
}

pub fn drawn(g: *game.Game, slot: usize) bool {
    return !gone(g, slot);
}

pub const TEST_HP: i32 = 100;

pub fn toughen(a: *actor.Actor) void {
    setLife(a, TEST_HP, TEST_HP);
}

pub const TEST_GAS = 100;
pub const SLIME_HALF = actor.row(.slime_half).hp;

pub fn drawnOut(g: *game.Game) void {
    g.st = .{};
    var t: f32 = 0;
    while (t < 2 and (g.busy > 0 or turningAny(g))) : (t += TEST_DT) game.update(g, TEST_DT);
}

fn turningAny(g: *game.Game) bool {
    for (g.turning) |t| {
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
    const id = g.pool.spawn(&g.lv, actor.Actor.of(k, at));
    g.pool.get(id).?.awake = awake;
    game.snapGlide(g);
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

/// Two corridors joined by a door at each one's end, starting a step from the first's; the second's node.
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
    g.pool.get(id).?.hp = SLIME_HALF + 1;
    return id;
}

pub fn bittenToDeath(g: *game.Game) void {
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    wakeFoes(g);
    g.heroActor().?.hp = 1;
    nudge(g, .e);
}

pub fn idle(g: *game.Game) void {
    calm(g);
    g.st = .{};
    game.update(g, 0);
}

pub fn caughtUp(g: *game.Game, slot: usize) bool {
    return g.pictured[slot].hp == g.pool.items[slot].hp;
}
