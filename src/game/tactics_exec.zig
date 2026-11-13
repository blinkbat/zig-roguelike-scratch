const attacks = @import("attacks.zig");
const Simulation = @import("sim.zig").Simulation;
const std = @import("std");
const game = @import("../game.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fire = @import("../map/fire.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const glacial = @import("../play/glacial.zig");
const areas = @import("../play/area.zig");
const progress = @import("../play/progress.zig");
const tactics = @import("../play/tactics.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const combat = @import("combat.zig");
const skills = @import("skills.zig");
const P = mathx.P;

pub fn instant(g: *game.Game, comptime act: skillbar.Act) void {
    const h = g.sim.heroActor() orelse return;
    const rank = g.sim.growth.ranks.get(act);
    const ending = skills.endingStance(&g.sim, act);
    switch (act) {
        .steady_aim => h.tactics.steady = rank,
        .guard => h.tactics.guard = rank,
        .unyielding => h.tactics.unyielding = !h.tactics.unyielding,
        .whirlwind => {
            const area = tactics.Whirlwind.area(&g.sim.lv, h.at);
            const ids = skills.foesIn(g, area);
            const raw = attacks.rawFor(&g.sim, .whirlwind);
            const s = game.presentation.Stroke{ .from = h.at, .wait = game.CAST_S };
            for (ids.slice()) |id| combat.wound(g, id, attacks.heroScaled(&g.sim, .whirlwind, raw).physical(), tactics.Whirlwind.VERB, s);
            for (area.slice()) |at| combat.smash(g, at, tactics.Whirlwind.VERB, s);
            g.pic.leadUntil(s.wait);
        },
        .war_cry => {
            warCry(g, h.at, rank);
            g.pic.leadUntil(game.CAST_S);
        },
        .imbue => h.tactics.imbue = tactics.Imbue.laid(),
        .bide => {
            h.tactics.bide = tactics.Bide.laid();
            h.tactics.bided = 0;
        },
        else => @compileError(@tagName(act) ++ " has no instant tactical use"),
    }
    g.sim.log.say("{s}: {s}{s}.", .{ g.sim.name.text(), act.name(), if (ending) " ended" else "" });
    g.pic.fx.shimmer(mathx.centre(h.at), look.UI_GOLD);
}

fn warCry(g: *game.Game, from: P, rank: u8) void {
    const reach = @min(tactics.WarCry.RADIUS + g.sim.wider(), areas.BURST_MAX);
    for (g.sim.pool.slice(), 0..) |*a, slot| {
        if (!a.seenFoe(&g.sim.lv) or mathx.dist(a.at, from) > reach) continue;
        a.awake = true;
        if (!g.sim.procStatus(a, .fright, tactics.WarCry.chance(rank))) continue;
        if (a.frighten(tactics.WarCry.turns(rank))) g.sim.sayAt(a.at, actor.FLEES, .{actor.row(a.kind).name});
        g.pic.settleSlot(&g.sim, game.CAST_S, .fromIndex(slot));
    }
}

pub fn valid(g: *const game.Game, from: P, at: P) bool {
    return validAct(g, g.mode.aim.act(), from, at);
}

pub fn validAct(g: *const game.Game, act: skillbar.Act, from: P, at: P) bool {
    if (!act.aimableIn(&g.sim.lv, from, at, g.sim.reachOf(act)) or strikesHidden(g, act, from, at)) return false;
    const start = (if (g.mode == .aim) g.mode.aim.anchor() else null) orelse at;
    if (act.consumes()) {
        const a = g.sim.pool.getConst(g.sim.lv.who(at)) orelse return false;
        return a.seenFoe(&g.sim.lv) and fuelOf(act, a) > 0;
    }
    if (act.spans()) return span(g, act, from, start, at) != null;
    if (act == .raise_skeleton) return raisable(g, at);
    return act != .overwatch or !from.eq(at);
}

fn raisable(g: *const game.Game, at: P) bool {
    return actor.standsOffDoor(.skeleton, &g.sim.lv, at) and canRise(g, .skeleton);
}

pub fn canRise(g: *const game.Game, kind: actor.Kind) bool {
    return g.sim.pool.hasRoomFor(kind) or spentSlot(g) != null;
}

pub fn spentSlot(g: *const game.Game) ?usize {
    var i: usize = 0;
    while (g.sim.pool.spentFrom(i)) |dead| : (i = dead + 1) {
        if (g.pic.gone(&g.sim, dead)) return dead;
    }
    return null;
}

/// The living skeletons, oldest first.
fn skeletons(sim: *const game.simulation.Simulation) grid.Bounded(u16, actor.MAX) {
    var out = grid.Bounded(u16, actor.MAX){};
    for (sim.pool.constSlice(), 0..) |a, i| {
        if (a.livingAlly() and a.kind == .skeleton) out.push(actor.Pool.idOf(i));
    }
    std.mem.sort(u16, out.items[0..out.n], &sim.pool, olderThan);
    return out;
}

fn olderThan(pool: *const actor.Pool, a: u16, b: u16) bool {
    return pool.items[actor.Pool.slot(a)].tactics.risen < pool.items[actor.Pool.slot(b)].tactics.risen;
}

fn raise(g: *game.Game, at: P, rank: u8) void {
    const risen = skeletons(&g.sim);
    const newest = if (risen.n > 0) g.sim.pool.items[actor.Pool.slot(risen.items[risen.n - 1])].tactics.risen else 0;
    if (risen.n >= tactics.RaiseSkeleton.most(rank)) {
        const oldest = risen.items[0];
        const slot = actor.Pool.slot(oldest);
        _ = g.sim.pool.damage(&g.sim.lv, oldest, g.sim.pool.items[slot].hp);
        combat.fell(g, oldest);
        g.pic.settleSlot(&g.sim, game.CAST_S, .fromIndex(slot));
    }
    var body = actor.Actor.of(.skeleton, at);
    body.max = tactics.RaiseSkeleton.life(rank);
    body.hp = body.max;
    body.tactics.risen = newest +| 1;
    const id = rise(g, body, spentSlot(g), game.CAST_S);
    g.pic.shimmerBody(game.CAST_S, &g.sim.pool.items[actor.Pool.slot(id)]);
    g.sim.sayAt(at, "A skeleton claws its way up.", .{});
    landed(g, id);
}

/// `body` come into being in slot `over` or a new one, awake and acting from the next turn, drawn once `wait` has passed.
pub fn rise(g: *game.Game, body: actor.Actor, over: ?usize, wait: f32) u16 {
    var b = body;
    b.awake = true;
    b.waits = true;
    const id = g.sim.pool.spawnOver(&g.sim.lv, over, b);
    if (g.target == id) g.target = null;
    g.pic.recordBirth(&g.sim, .fromInt(id), wait);
    return id;
}

pub fn span(g: *const game.Game, act: skillbar.Act, from: P, start: P, end: P) ?tactics.Wall {
    const rank = g.sim.growth.ranks.get(act);
    return switch (act) {
        .arcane_barrier => tactics.wall(&g.sim.lv, from, start, end, rank),
        .fire_wall => tactics.blaze(&g.sim.lv, from, start, end, rank),
        inline else => |a| if (comptime a.spans()) @compileError(@tagName(a) ++ " spans with no wall") else null,
    };
}

pub fn strikesHidden(g: *const game.Game, act: skillbar.Act, from: P, at: P) bool {
    switch (act.reticle() orelse return false) {
        .rush => return g.sim.untargetableAt(at),
        .swing => switch (act) {
            inline else => |a| {
                if (comptime !a.sweeps()) return g.sim.untargetableAt(at);
                const arc = skillbar.Act.skill(a).arc(&g.sim.lv, from, at);
                for (arc.slice()) |p| {
                    if (g.sim.lv.taken(p) and !g.sim.untargetableAt(p)) return false;
                }
                return true;
            },
        },
        .bow, .leap, .ground => return false,
    }
}

fn fuelOf(act: skillbar.Act, a: *const actor.Actor) u8 {
    switch (act) {
        inline else => |c| return if (comptime c.consumes()) @field(a, @tagName(skillbar.Act.skill(c).FUEL)).turns else 0,
    }
}

pub fn cast(g: *game.Game, aim: game.Aim, from: P) void {
    switch (aim.act()) {
        inline else => |a| if (comptime a.reticle() != .ground) unreachable else castGround(g, a, aim, from),
    }
}

fn castGround(g: *game.Game, comptime act: skillbar.Act, aim: game.Aim, from: P) void {
    const rank = g.sim.growth.ranks.get(act);
    const at = aim.mark;
    if (comptime act.consumes()) detonate(g, act, at, from) else switch (act) {
        .overwatch => {
            g.sim.heroActor().?.tactics.overwatch = mathx.toward(from, at).?;
            g.pic.settleHero(&g.sim, 0);
        },
        .caltrops => {
            const area = tactics.Caltrops.area(&g.sim.lv, at, g.sim.wider());
            for (area.slice()) |p| {
                if (!g.sim.lv.isLit(p)) continue;
                g.sim.lv.caltrops[grid.Level.idx(p)] = .{ .turns = tactics.Caltrops.laid(rank), .rank = rank };
            }
            g.pic.holdFlames(&g.sim.lv, game.CAST_S);
        },
        .gravity_well => {
            const area = tactics.GravityWell.area(&g.sim.lv, at, g.sim.wider());
            const ids = skills.foesIn(g, area);
            for (ids.slice()) |id| {
                const a = g.sim.pool.get(id) orelse continue;
                if (!a.seenIn(&g.sim.lv)) continue;
                for (0..tactics.GravityWell.pulls(rank)) |_| {
                    if (a.pin.holding()) break;
                    const d = mathx.toward(a.at, at) orelse break;
                    const to = a.at.add(d.delta());
                    if (!actor.holds(a.kind, &g.sim.lv, to) or !area.has(to)) break;
                    displace(g, id, to);
                }
                if (g.sim.displaced.isSet(actor.Pool.slot(id))) _ = g.pic.glideToHeld(.fromIndex(actor.Pool.slot(id)), a.at, -game.CAST_S);
                _ = g.sim.pinFor(a, tactics.GravityWell.pins(rank));
                g.pic.settleSlot(&g.sim, game.CAST_S, .fromIndex(actor.Pool.slot(id)));
            }
            g.sim.flowed = false;
            g.pic.fx.shimmer(mathx.centre(at), look.WARD);
        },
        .arcane_barrier => {
            const area = span(g, act, from, aim.anchor().?, at).?;
            for (area.slice()) |p| g.sim.lv.barrier[grid.Level.idx(p)] = tactics.ArcaneBarrier.laid(rank);
            g.pic.holdFlames(&g.sim.lv, game.CAST_S);
        },
        .fire_wall => {
            const area = span(g, act, from, aim.anchor().?, at).?;
            for (area.slice()) |p| fire.lay(&g.sim.lv, p, tactics.FireWall.laid(rank), tactics.FireWall.HEAT);
            g.pic.holdFire(&g.sim.lv, game.CAST_S);
            for (area.slice()) |p| {
                const id = g.sim.lv.who(p);
                const a = g.sim.pool.get(id) orelse continue;
                if (a.foe() and g.sim.ignite(actor.Pool.slot(id), a)) g.pic.settleSlot(&g.sim, game.CAST_S, .fromIndex(actor.Pool.slot(id)));
            }
        },
        .raise_skeleton => raise(g, at, rank),
        else => @compileError(@tagName(act) ++ " has no ground tactical use"),
    }
    g.sim.log.say("{s} casts {s}.", .{ g.sim.name.text(), act.name() });
    g.pic.leadUntil(game.CAST_S);
    combat.endTurn(g);
}

fn detonate(g: *game.Game, comptime act: skillbar.Act, at: P, from: P) void {
    const Skill = skillbar.Act.skill(act);
    const struck = g.sim.lv.who(at);
    const target = g.sim.pool.get(struck).?;
    const fuel: i32 = fuelOf(act, target);
    @field(target, @tagName(Skill.FUEL)) = .{};
    g.pic.settleSlot(&g.sim, game.CAST_S, .fromIndex(actor.Pool.slot(struck)));
    const area = Skill.area(&g.sim.lv, at, g.sim.wider());
    const ids = skills.foesIn(g, area);
    var raw = attacks.rawElementFor(&g.sim, act);
    raw.elements.getPtr(Skill.ELEMENT).* += Skill.FUEL_DAMAGE * fuel;
    const s = game.presentation.Stroke{ .from = from, .wait = game.CAST_S, .element = Skill.ELEMENT };
    g.pic.fx.burst(s.wait, .{ .at = at, .area = area, .element = Skill.ELEMENT });
    for (ids.slice()) |id| {
        const a = g.sim.pool.get(id) orelse continue;
        const hit = attacks.heroScaled(&g.sim, act, raw);
        combat.wound(g, id, hit.against(g.sim.combatStats(a).elements), Skill.VERB, s);
    }
    if (comptime Skill.ELEMENT == .fire) combat.fireLands(g, at, Skill.REACH, Skill.KINDLE, s.wait);
    if (comptime Skill.ELEMENT == .cold) combat.coldLands(g, &area, s.wait);
}

pub fn beforeAction(sim: *Simulation) void {
    const h = sim.heroActor() orelse return;
    h.tactics.guard = 0;
    h.tactics.overwatch = null;
}

pub fn startTurn(sim: *Simulation) void {
    const h = sim.heroActor() orelse return;
    if (h.tactics.unyielding) {
        if (sim.mana >= tactics.Unyielding.DRAIN) {
            sim.mana -= tactics.Unyielding.DRAIN;
        } else {
            h.tactics.unyielding = false;
            sim.log.say("{s}'s Unyielding ends: not enough mana.", .{sim.name.text()});
        }
    }
    h.tactics.imbue -|= 1;
    for (&sim.lv.barrier) |*t| t.* -|= 1;
    for (&sim.lv.caltrops) |*c| {
        c.turns -|= 1;
        if (c.turns == 0) c.rank = 0;
    }
}

pub fn bideTurn(g: *game.Game) void {
    const h = g.sim.heroActor() orelse return;
    if (h.tactics.bide == 0) return;
    h.tactics.bide -= 1;
    if (h.tactics.bide > 0) return;
    const dmg = tactics.Bide.released(h.tactics.bided);
    h.tactics.bided = 0;
    const s = game.presentation.Stroke{ .from = h.at, .wait = (g.pic.lead orelse 0) + game.CAST_S };
    g.pic.leadUntil(s.wait);
    g.pic.settleHero(&g.sim, s.wait);
    if (dmg == 0) return g.sim.log.say("{s}'s Bide ends.", .{g.sim.name.text()});
    g.sim.log.say("{s} releases Bide: {d} to each foe beside.", .{ g.sim.name.text(), dmg });
    g.pic.fx.sweep(s.wait, mathx.centre(h.at));
    const area = tactics.Bide.area(&g.sim.lv, h.at);
    const ids = skills.foesIn(g, area);
    for (ids.slice()) |id| combat.wound(g, id, .{ .dmg = dmg, .physical = dmg, .hit_checked = true }, tactics.Bide.VERB, s);
}

pub fn displace(g: *game.Game, id: u16, to: P) void {
    g.sim.pool.move(&g.sim.lv, id, to);
    shoved(g, id);
}

pub fn shoved(g: *game.Game, id: u16) void {
    g.sim.displaced.set(actor.Pool.slot(id));
    entered(g, id);
}

pub fn entered(g: *game.Game, id: u16) void {
    landed(g, id);
    const a = g.sim.pool.get(id) orelse return;
    const h = g.sim.heroActor() orelse return;
    const direction = h.tactics.overwatch orelse return;
    if (a.veiled() or !a.foe() or !tactics.covered(h.at, direction, a.at)) return;
    const flight = bow.clearShot(&g.sim.lv, h.at, a.at, tactics.Overwatch.RANGE, id) orelse return;
    h.tactics.overwatch = null;
    combat.reaction(g, id, attacks.heroSkill(&g.sim, .overwatch), tactics.Overwatch.VERB, .{ .from = h.at, .wait = 0 }, id, flight);
    h.tactics.steady = 0;
    if (g.pic.owed[actor.Pool.slot(id)].reaction) |*r| r.recovery = g.pic.heroAfter(&g.sim);
}

pub fn watches(lv: *const grid.Level, from: P, d: mathx.Dir, p: P) bool {
    return tactics.covered(from, d, p) and bow.aimable(lv, from, p, tactics.Overwatch.RANGE);
}

pub fn landed(g: *game.Game, id: u16) void {
    const a = g.sim.pool.get(id) orelse return;
    const cell = grid.Level.idx(a.at);
    const trap = g.sim.lv.caltrops[cell];
    if (trap.turns > 0 and a.foe() and actor.row(a.kind).movement.grounded()) {
        _ = g.sim.pinFor(a, tactics.Caltrops.pins(trap.rank));
        if (tactics.Caltrops.bleed(trap.rank) > 0 and g.sim.takeStatus(a, .bleed)) a.bleed.startWith(tactics.Caltrops.bleed(trap.rank));
        g.pic.recordWear(&g.sim, .fromInt(id));
        g.sim.sayOf(a, "The {s} steps into caltrops.", .{actor.row(a.kind).name});
    }
    if (g.sim.lv.burning(a.at) and g.sim.ignite(actor.Pool.slot(id), a)) g.pic.recordWear(&g.sim, .fromInt(id));
}

pub fn counter(g: *game.Game, id: u16) void {
    const h = g.sim.heroActor() orelse return;
    const a = g.sim.pool.get(id) orelse return;
    if (!h.tactics.unyielding or !mathx.adjacent(h.at, a.at) or !g.sim.rng.percent(tactics.Unyielding.chance(g.sim.growth.ranks.get(.unyielding)))) return;
    combat.reaction(g, id, attacks.heroMelee(&g.sim), tactics.Unyielding.VERB, .{ .from = h.at, .wait = 0 }, id, null);
}

test "tactical caltrops ranks pin entering ground foes and unlock stronger bleeding" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    for (1..progress.RANKS + 1) |rank| {
        h.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
        g.sim.growth.ranks.set(.caltrops, @intCast(rank));
        const id = h.spawnAt(g, .rat, .{ .x = 24, .y = 20 }, true);
        h.toughen(g.sim.pool.get(id).?);
        h.aimAt(g, .caltrops, .{ .x = 22, .y = 20 });
        const foe = g.sim.pool.get(id).?;
        try std.testing.expectEqual(@as(i32, 23), foe.at.x);
        try std.testing.expectEqual(tactics.Caltrops.pins(@intCast(rank)), foe.pin.turns);
        try std.testing.expectEqual(rank >= 2, foe.bleed.turns > 0);
        if (rank >= 2) try std.testing.expectEqual(@as(i32, @intCast(rank - 1)), foe.bleed.amount);
        const turns = g.sim.lv.caltrops[grid.Level.idx(foe.at)].turns;
        h.drawnOut(g);
        game.update(g, 1);
        try std.testing.expectEqual(turns, g.sim.lv.caltrops[grid.Level.idx(foe.at)].turns);
    }
}

test "tactical overwatch fires once after movement and steady aim is consumed or canceled by movement" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .archer, from, &.{});
    game.harness.useAct(g, .steady_aim);
    try std.testing.expectEqual(@as(u8, 1), g.sim.heroActor().?.tactics.steady);
    const boosted = attacks.blowFor(&g.sim, .shoot).by;
    g.sim.heroActor().?.tactics.steady = 0;
    const plain = attacks.blowFor(&g.sim, .shoot).by;
    try std.testing.expectEqual(plain.increase(.light) + tactics.SteadyAim.bonus(1), boosted.increase(.light));
    h.drawnOut(g);
    g.sim.heroActor().?.tactics.steady = 2;
    const id = h.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, true);
    h.toughen(g.sim.pool.get(id).?);
    game.settle(g);
    const before = g.sim.pool.get(id).?.hp;
    h.aimAt(g, .overwatch, .{ .x = 25, .y = 20 });
    try std.testing.expect(g.sim.pool.get(id).?.hp < before);
    try std.testing.expect(g.sim.heroActor().?.tactics.overwatch == null);
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.tactics.steady);
    try std.testing.expect(g.pic.owed[actor.Pool.slot(id)].reaction != null);
    try std.testing.expectEqual(before, g.pic.pictured[actor.Pool.slot(id)].hp);
    g.pic.stepGlide(&g.sim, g.cloud, 0);
    g.pic.catchUp(&g.sim);
    try std.testing.expectEqual(@as(u8, 1), g.pic.heroShown(&g.sim).?.status.get(.overwatch));
    try std.testing.expectEqual(@as(u8, 1), g.pic.heroShown(&g.sim).?.status.get(.steady));
    h.drawnOut(g);
    try std.testing.expectEqual(@as(u8, 0), g.pic.heroShown(&g.sim).?.status.get(.overwatch));
    try std.testing.expectEqual(@as(u8, 0), g.pic.heroShown(&g.sim).?.status.get(.steady));
    g.sim.heroActor().?.tactics.steady = 1;
    game.heroStep(g, .w, 0);
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.tactics.steady);
}

test "tactical gravity ranks pull and unlock pin while combustion consumes burn and hits each victim once" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    for (1..progress.RANKS + 1) |rank| {
        h.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
        g.sim.growth.ranks.set(.gravity_well, @intCast(rank));
        const id = h.spawnAt(g, .rat, .{ .x = 24, .y = 20 }, false);
        h.aimAt(g, .gravity_well, .{ .x = 22, .y = 20 });
        const foe = g.sim.pool.get(id).?;
        try std.testing.expectEqual(@as(i32, if (rank == 3) 22 else 23), foe.at.x);
        try std.testing.expectEqual(rank >= 2, foe.resilience.meters.get(.pin).percent > 0);
    }
    h.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    const id = h.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, false);
    const neighbor = h.spawnAt(g, .rat, .{ .x = 23, .y = 21 }, false);
    h.toughen(g.sim.pool.get(id).?);
    h.toughen(g.sim.pool.get(neighbor).?);
    const before = g.sim.pool.get(id).?.hp;
    const mana = g.sim.mana;
    h.aimAt(g, .combustion, .{ .x = 23, .y = 20 });
    try std.testing.expectEqual(mana, g.sim.mana);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    g.sim.pool.get(id).?.burn.start();
    h.aimAt(g, .combustion, .{ .x = 23, .y = 20 });
    try std.testing.expectEqual(@as(u8, 0), g.sim.pool.get(id).?.burn.turns);
    try std.testing.expect(g.sim.pool.get(id).?.hp < before);
    try std.testing.expect(g.sim.pool.get(neighbor).?.hp < before);
}

test "tactical combustion consumes pictured burn at explosion time even when damage misses" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 20 };
    var misses: usize = 0;
    for ([_]u64{ 0, 10 }) |seed| {
        h.heroArena(g, .wizard, from, &.{at});
        g.sim.lv.set(from, .reeds);
        const id = g.sim.lv.who(at);
        const foe = g.sim.pool.get(id).?;
        h.toughen(foe);
        foe.burn.start();
        game.settle(g);
        const slot = actor.Pool.slot(id);
        const hp = foe.hp;
        const burnt = g.pic.pictured[slot].status.get(.burning);
        g.sim.rng = mathx.Rng.init(seed);
        h.aimAt(g, .combustion, at);
        misses += @intFromBool(foe.hp == hp);
        try std.testing.expectEqual(@as(u8, 0), foe.burn.turns);
        g.pic.stepGlide(&g.sim, g.cloud, 0);
        g.pic.advance(&g.sim, game.CAST_S / 2);
        try std.testing.expectEqual(burnt, g.pic.pictured[slot].status.get(.burning));
        try std.testing.expectEqual(hp, g.pic.pictured[slot].hp);
        g.pic.advance(&g.sim, game.CAST_S / 2 + 0.001);
        try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[slot].status.get(.burning));
        try std.testing.expectEqual(foe.hp, g.pic.pictured[slot].hp);
        h.drawnOut(g);
    }
    try std.testing.expectEqual(@as(usize, 1), misses);
}

test "tactical barrier selects endpoints without spending then blocks paths until spent-turn expiry" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    const start = P{ .x = 22, .y = 19 };
    const end = P{ .x = 22, .y = 21 };
    h.heroArena(g, .wizard, from, &.{});
    const mana = g.sim.mana;
    h.aimAt(g, .arcane_barrier, start);
    try std.testing.expectEqual(mana, g.sim.mana);
    try std.testing.expectEqual(start, g.mode.aim.anchor().?);
    g.mode.aim.mark = end;
    skills.confirmAim(g);
    const middle = P{ .x = 22, .y = 20 };
    try std.testing.expect(g.sim.lv.hasBarrier(middle));
    try std.testing.expect(!g.sim.lv.walkable(middle));
    try std.testing.expect(bow.aimable(&g.sim.lv, from, .{ .x = 24, .y = 20 }, bow.RANGE));
    try std.testing.expect(grid.clearLine(&g.sim.lv, from, .{ .x = 24, .y = 20 }));
    try std.testing.expectEqual(@as(usize, 1), bow.fly(&g.sim.lv, from, .{ .x = 24, .y = 20 }).len);
    try std.testing.expect(g.sim.lv.isLit(.{ .x = 24, .y = 20 }));
    h.drawnOut(g);
    for (0..tactics.ArcaneBarrier.duration(1)) |_| {
        game.harness.useAct(g, .wait);
        h.drawnOut(g);
    }
    try std.testing.expect(!g.sim.lv.hasBarrier(middle));
    try std.testing.expectEqual(grid.Tile.floor, g.sim.lv.at(middle));
}

test "tactical knight guard expires on action whirlwind hits neighbors and unyielding drains and toggles off empty" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .knight, from, &.{});
    game.harness.useAct(g, .guard);
    try std.testing.expect(g.sim.heroActor().?.tactics.guard > 0);
    h.drawnOut(g);
    game.harness.useAct(g, .wait);
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.tactics.guard);
    h.drawnOut(g);
    const a = h.spawnAt(g, .rat, from.add(.{ .x = 1, .y = 0 }), false);
    const b = h.spawnAt(g, .rat, from.add(.{ .x = -1, .y = 0 }), false);
    h.toughen(g.sim.pool.get(a).?);
    h.toughen(g.sim.pool.get(b).?);
    const before = g.sim.pool.get(a).?.hp;
    game.settle(g);
    game.harness.useAct(g, .whirlwind);
    try std.testing.expect(g.sim.pool.get(a).?.hp < before and g.sim.pool.get(b).?.hp < before);
    h.drawnOut(g);
    h.heroArena(g, .knight, from, &.{});
    g.sim.mana = 4;
    game.harness.useAct(g, .unyielding);
    try std.testing.expect(g.sim.heroActor().?.tactics.unyielding);
    try std.testing.expectEqual(@as(i32, 0), g.sim.mana);
    h.drawnOut(g);
    game.harness.useAct(g, .unyielding);
    try std.testing.expect(!g.sim.heroActor().?.tactics.unyielding);
    h.drawnOut(g);
    g.sim.heroActor().?.tactics.unyielding = true;
    game.harness.useAct(g, .wait);
    try std.testing.expect(!g.sim.heroActor().?.tactics.unyielding);
}

test "unyielding is refused without the mana for its first turn's upkeep as well as its cost" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{});
    const needed = g.sim.growth.cost(.unyielding) + tactics.Unyielding.DRAIN;
    g.sim.mana = needed - 1;
    game.harness.useAct(g, .unyielding);
    try std.testing.expect(!g.sim.heroActor().?.tactics.unyielding);
    try std.testing.expectEqual(needed - 1, g.sim.mana);
    g.sim.mana = needed;
    game.harness.useAct(g, .unyielding);
    try std.testing.expect(g.sim.heroActor().?.tactics.unyielding);
}

test "tactical regressions cover forced trap entries chest action cleanup and prepared previews" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .wizard, from, &.{});
    g.sim.growth.ranks.set(.gravity_well, 3);
    const id = h.spawnAt(g, .rat, .{ .x = 24, .y = 20 }, false);
    g.sim.lv.caltrops[grid.Level.idx(.{ .x = 23, .y = 20 })] = .{ .turns = 5, .rank = 2 };
    h.aimAt(g, .gravity_well, .{ .x = 22, .y = 20 });
    try std.testing.expectEqual(@as(i32, 23), g.sim.pool.get(id).?.at.x);
    try std.testing.expect(g.sim.pool.get(id).?.bleed.turns > 0);
    h.heroArena(g, .knight, from, &.{});
    const bashed = h.spawnAt(g, .rat, .{ .x = 21, .y = 20 }, false);
    h.toughen(g.sim.pool.get(bashed).?);
    g.sim.lv.caltrops[grid.Level.idx(.{ .x = 22, .y = 20 })] = .{ .turns = 5, .rank = 2 };
    combat.knock(g, .shield_bash, .e, .{ .from = from, .wait = 0 });
    try std.testing.expect(g.sim.pool.get(bashed).?.pin.turns > 0);
    try std.testing.expect(g.sim.pool.get(bashed).?.bleed.turns > 0);
    h.heroArena(g, .knight, from, &.{});
    const chest = P{ .x = 21, .y = 20 };
    g.sim.lv.set(chest, .chest);
    g.sim.heroActor().?.tactics = .{ .guard = 1, .overwatch = .e };
    game.character.openLoot(g, chest);
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.tactics.guard);
    try std.testing.expect(g.sim.heroActor().?.tactics.overwatch == null);
    h.heroArena(g, .archer, from, &.{});
    g.sim.heroActor().?.tactics.steady = 3;
    const preview = g.sim.growth.preparedHit(g.sim.heroAttrs(), g.sim.inventory.gear, .shoot, .{ .steady = 3 }).?;
    try std.testing.expectEqualDeep(attacks.blowFor(&g.sim, .shoot).hit(.shoot), preview);
}

test "tactical reaction recovery waits for impact and Harvest restores life from bleeding kills" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .knight, from, &.{});
    g.sim.inventory.gear.slots.set(.left_ring, h.harvestRing());
    game.syncStats(g);
    g.sim.heroActor().?.hp -= 10;
    const id = h.spawnAt(g, .rat, .{ .x = 21, .y = 20 }, true);
    game.settle(g);
    const before = g.sim.heroActor().?.hp;
    combat.reaction(g, id, .{ .dmg = 100 }, tactics.Unyielding.VERB, .{ .from = from, .wait = 0 }, id, null);
    try std.testing.expectEqual(before + h.HARVEST_LIFE, g.sim.heroActor().?.hp);
    g.pic.stepGlide(&g.sim, g.cloud, 0);
    g.pic.catchUp(&g.sim);
    try std.testing.expectEqual(before, g.pic.heroShown(&g.sim).?.hp);
    h.drawnOut(g);
    try std.testing.expectEqual(before + h.HARVEST_LIFE, g.pic.heroShown(&g.sim).?.hp);
    const bled = h.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, false);
    h.bleedingOut(g.sim.pool.get(bled).?);
    game.settle(g);
    game.harness.useAct(g, .wait);
    try std.testing.expect(g.sim.pool.get(bled) == null);
    try std.testing.expectEqual(before + 2 * h.HARVEST_LIFE, g.sim.heroActor().?.hp);
    h.drawnOut(g);
    try std.testing.expectEqual(before + 2 * h.HARVEST_LIFE, g.pic.heroShown(&g.sim).?.hp);
}

test "tactical overwatch reaction finishes before the next foe can expose its recovery" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .archer, from, &.{});
    g.sim.inventory.gear.slots.set(.left_ring, h.harvestRing());
    game.syncStats(g);
    g.sim.heroActor().?.hp -= 10;
    const rat = h.spawnAt(g, .rat, .{ .x = 24, .y = 20 }, true);
    g.sim.pool.get(rat).?.hp = 1;
    const bandit = h.spawnAt(g, .bandit_crossbowman, .{ .x = 24, .y = 21 }, true);
    const hidden = h.spawnAt(g, .rat, .{ .x = 40, .y = 20 }, false);
    h.bleedingOut(g.sim.pool.get(hidden).?);
    game.settle(g);
    h.aimAt(g, .overwatch, .{ .x = 25, .y = 20 });
    try std.testing.expect(g.pic.owed[actor.Pool.slot(rat)].reaction.?.recovery != null);
    g.pic.stepGlide(&g.sim, g.cloud, 0);
    const reaction_shot = g.pic.shot.?;
    const pictured_before = g.pic.heroShown(&g.sim).?.hp;
    const next_shot = g.pic.foe_shots[actor.Pool.slot(bandit)].?;
    try std.testing.expect(-next_shot.t >= -reaction_shot.t + reaction_shot.lands());
    g.pic.advance(&g.sim, 0.01);
    try std.testing.expectEqual(pictured_before, g.pic.heroShown(&g.sim).?.hp);
    h.drawnOut(g);
}

test "war cry frightens foes as their fright resistance allows and the picture shows it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    var rats: usize = 0;
    var pibs: usize = 0;
    var slimes: usize = 0;
    for (0..h.TRIES) |seed| {
        h.heroArena(g, .knight, from, &.{});
        g.sim.growth.ranks.set(.war_cry, 1);
        g.sim.mana = h.TEST_MANA;
        const rat = h.spawnAt(g, .rat, .{ .x = 22, .y = 20 }, false);
        const beefy = h.spawnAt(g, .beefy_pib, .{ .x = 20, .y = 22 }, false);
        const slime = h.spawnAt(g, .slime, .{ .x = 18, .y = 20 }, false);
        game.settle(g);
        g.sim.rng = mathx.Rng.init(seed);
        game.harness.useAct(g, .war_cry);
        rats += @intFromBool(g.sim.pool.get(rat).?.fright > 0);
        pibs += @intFromBool(g.sim.pool.get(beefy).?.fright > 0);
        slimes += @intFromBool(g.sim.pool.get(slime).?.fright > 0);
    }
    const chance = mathx.fraction(tactics.WarCry.chance(1));
    try std.testing.expect(h.aboutRate(rats, chance));
    try std.testing.expect(h.aboutRate(pibs, chance * mathx.fraction(mathx.PERCENT - actor.row(.beefy_pib).fright_resist)));
    try std.testing.expectEqual(@as(usize, 0), slimes);
    h.heroArena(g, .knight, from, &.{});
    g.sim.growth.ranks.set(.war_cry, 3);
    g.sim.unkillable = true;
    const rat = h.spawnAt(g, .rat, .{ .x = 22, .y = 20 }, false);
    game.settle(g);
    for (0..h.TRIES) |_| {
        if (g.sim.pool.get(rat).?.fright > 0) break;
        g.sim.cooldown.set(.war_cry, 0);
        g.sim.mana = h.TEST_MANA;
        game.harness.useAct(g, .war_cry);
        h.drawnOut(g);
    }
    try std.testing.expect(g.sim.pool.get(rat).?.fright > 0);
    try std.testing.expectEqual(g.sim.pool.get(rat).?.fright, g.pic.pictured[actor.Pool.slot(rat)].status.get(.frightened));
    g.sim.unkillable = false;
}

test "shatter consumes chill for cold damage over its neighbours and refuses an unchilled foe without spending" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    h.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    g.sim.growth.ranks.set(.shatter, 1);
    const at = P{ .x = 23, .y = 20 };
    const id = h.spawnAt(g, .rat, at, false);
    const neighbor = h.spawnAt(g, .rat, .{ .x = 23, .y = 21 }, false);
    h.toughen(g.sim.pool.get(id).?);
    h.toughen(g.sim.pool.get(neighbor).?);
    const before = g.sim.pool.get(id).?.hp;
    const mana = g.sim.mana;
    h.aimAt(g, .shatter, at);
    try std.testing.expectEqual(mana, g.sim.mana);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    g.sim.pool.get(id).?.chill.apply();
    game.settle(g);
    try std.testing.expectEqual(glacial.TURNS, g.pic.pictured[actor.Pool.slot(id)].status.get(.chilled));
    h.aimAt(g, .shatter, at);
    try std.testing.expectEqual(@as(u8, 0), g.sim.pool.get(id).?.chill.turns);
    try std.testing.expect(g.sim.pool.get(id).?.hp < before);
    try std.testing.expect(g.sim.pool.get(neighbor).?.hp < before);
    try std.testing.expect(g.sim.mana < mana);
}

test "fire wall ignites foes it rises under and those that enter, is shunned, and burns out" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .wizard, from, &.{});
    g.sim.growth.ranks.set(.fire_wall, 1);
    const under = h.spawnAt(g, .rat, .{ .x = 22, .y = 20 }, false);
    const outside = h.spawnAt(g, .rat, .{ .x = 23, .y = 21 }, false);
    h.toughen(g.sim.pool.get(under).?);
    h.toughen(g.sim.pool.get(outside).?);
    const mana = g.sim.mana;
    h.aimAt(g, .fire_wall, .{ .x = 22, .y = 19 });
    try std.testing.expectEqual(mana, g.sim.mana);
    g.mode.aim.mark = .{ .x = 22, .y = 21 };
    skills.confirmAim(g);
    for ([_]i32{ 19, 20, 21 }) |y| try std.testing.expect(g.sim.lv.burning(.{ .x = 22, .y = y }));
    try std.testing.expect(g.sim.pool.get(under).?.burn.turns > 0);
    try std.testing.expectEqual(@as(u8, 0), g.sim.pool.get(outside).?.burn.turns);
    var flow: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    _ = grid.distances(&g.sim.lv, from, &flow, &queue);
    const step = actor.chase(&g.sim.lv, g.sim.pool.get(outside).?.at, outside, &flow);
    if (step) |d| try std.testing.expect(!g.sim.lv.burning(g.sim.pool.get(outside).?.at.add(d.delta())));
    h.drawnOut(g);
    const into = P{ .x = 22, .y = 21 };
    g.sim.pool.move(&g.sim.lv, outside, into);
    entered(g, outside);
    try std.testing.expect(g.sim.pool.get(outside).?.burn.turns > 0);
    g.sim.unkillable = true;
    for (0..tactics.FireWall.duration(1)) |_| {
        h.drawnOut(g);
        game.harness.useAct(g, .wait);
    }
    g.sim.unkillable = false;
    try std.testing.expect(!g.sim.lv.burning(into));
}

test "imbue adds fire and its rank's ignite chance to melee blows for its turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .knight, from, &.{});
    const plain = attacks.heroMelee(&g.sim);
    try std.testing.expectEqual(@as(i32, 0), plain.fire);
    try std.testing.expectEqual(@as(u32, 0), plain.effect.burn);
    h.useAct(g, .imbue);
    try std.testing.expectEqual(tactics.Imbue.TURNS, g.sim.heroActor().?.tactics.imbue);
    h.drawnOut(g);
    g.sim.growth.ranks.set(.imbue, progress.RANKS);
    const kick = attacks.heroMelee(&g.sim);
    try std.testing.expect(kick.fire >= tactics.Imbue.FIRE.lo);
    try std.testing.expectEqual(tactics.Imbue.ignites(progress.RANKS), kick.effect.burn);
    try std.testing.expect(attacks.heroSkill(&g.sim, .cleave).fire >= tactics.Imbue.FIRE.lo);
    const id = h.spawnAt(g, .rat, from.add(.{ .x = 1, .y = 0 }), false);
    var hits: usize = 0;
    var burnt: usize = 0;
    for (0..h.TRIES) |_| {
        const a = g.sim.pool.get(id).?;
        h.toughen(a);
        a.burn = .{};
        a.resilience = .{};
        combat.wound(g, id, attacks.heroMelee(&g.sim), "kicks", .{ .from = from, .wait = 0 });
        hits += @intFromBool(a.hp < h.TEST_HP);
        burnt += @intFromBool(a.burn.turns > 0);
    }
    try std.testing.expect(h.aboutRateOf(burnt, hits, mathx.fraction(tactics.Imbue.ignites(progress.RANKS))));
    for (0..tactics.Imbue.TURNS) |_| {
        h.drawnOut(g);
        h.useAct(g, .wait);
    }
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.tactics.imbue);
    try std.testing.expectEqual(@as(i32, 0), attacks.heroMelee(&g.sim).fire);
}

test "bide cuts each blow while it holds, then deals twice what it took to every foe beside" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .knight, from, &.{});
    g.sim.unkillable = true;
    defer g.sim.unkillable = false;
    const rank: u8 = 2;
    g.sim.growth.ranks.set(.bide, rank);
    const near = h.openMimic(g, from.add(.{ .x = 1, .y = 0 }));
    const far = h.spawnAt(g, .rat, from.add(.{ .x = 3, .y = 0 }), false);
    h.toughen(g.sim.pool.get(near).?);
    h.toughen(g.sim.pool.get(far).?);
    g.sim.pool.get(far).?.pin.extend(20);
    game.settle(g);
    const hero = g.sim.heroActor().?;
    const foe = g.sim.pool.get(near).?;
    const s = actor.row(.mimic).blow.strike;
    var seed: u64 = 0;
    while (true) : (seed += 1) {
        g.sim.rng = mathx.Rng.init(seed);
        if (attacks.foeBlow(&g.sim, foe, hero, s, false)) |b| if (b.dealt >= 3) break;
    }
    g.sim.rng = mathx.Rng.init(seed);
    const plain = attacks.foeBlow(&g.sim, foe, hero, s, false).?;
    hero.tactics.bide = 1;
    g.sim.rng = mathx.Rng.init(seed);
    const braced = attacks.foeBlow(&g.sim, foe, hero, s, false).?;
    try std.testing.expectEqual(tactics.Bide.reduce(rank, plain.dealt), braced.dealt);
    try std.testing.expect(braced.dealt < plain.dealt);
    try std.testing.expectEqual(braced.dealt, hero.tactics.bided);
    hero.tactics = .{};
    h.useAct(g, .bide);
    try std.testing.expectEqual(tactics.Bide.TURNS, hero.tactics.bide);
    for (0..tactics.Bide.TURNS - 1) |_| {
        h.drawnOut(g);
        h.useAct(g, .wait);
    }
    h.drawnOut(g);
    try std.testing.expectEqual(@as(u8, 1), hero.tactics.bide);
    hero.tactics.bided +|= 5;
    const stored = hero.tactics.bided;
    const before = foe.hp;
    h.useAct(g, .wait);
    try std.testing.expectEqual(@as(u8, 0), hero.tactics.bide);
    try std.testing.expect(foe.hp < before);
    try std.testing.expect(before - foe.hp <= tactics.Bide.released(stored));
    try std.testing.expectEqual(h.TEST_HP, g.sim.pool.get(far).?.hp);
}

fn skeletonCount(g: *game.Game) usize {
    return skeletons(&g.sim).n;
}

test "a raised skeleton fights a foe beside it, takes foes' blows, is spared the hero's and crumbles past its rank's limit" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .wizard, from, &.{});
    g.sim.unkillable = true;
    defer g.sim.unkillable = false;
    g.sim.mana = h.TEST_MANA;
    const first = P{ .x = 22, .y = 20 };
    h.aimAt(g, .raise_skeleton, first);
    const id = g.sim.lv.who(first);
    const bones = g.sim.pool.get(id).?;
    try std.testing.expectEqual(actor.Kind.skeleton, bones.kind);
    try std.testing.expectEqual(tactics.RaiseSkeleton.life(1), bones.max);
    combat.wound(g, id, .{ .dmg = 50, .physical = 50, .hit_checked = true }, "strikes", .{ .from = from, .wait = 0 });
    try std.testing.expectEqual(bones.max, bones.hp);
    h.drawnOut(g);
    g.sim.cooldown.set(.raise_skeleton, 0);
    h.aimAt(g, .raise_skeleton, .{ .x = 20, .y = 22 });
    try std.testing.expect(g.sim.pool.get(id) == null);
    try std.testing.expectEqual(@as(usize, 1), skeletonCount(g));
    h.drawnOut(g);
    g.sim.growth.ranks.set(.raise_skeleton, 2);
    g.sim.cooldown.set(.raise_skeleton, 0);
    h.aimAt(g, .raise_skeleton, .{ .x = 18, .y = 20 });
    try std.testing.expectEqual(@as(usize, 2), skeletonCount(g));
    const guard = g.sim.lv.who(.{ .x = 20, .y = 22 });
    const rat = h.spawnAt(g, .rat, .{ .x = 21, .y = 23 }, true);
    h.toughen(g.sim.pool.get(rat).?);
    game.settle(g);
    for (0..8) |_| {
        h.drawnOut(g);
        h.useAct(g, .wait);
    }
    const struck = g.sim.pool.get(rat).?;
    const held = g.sim.pool.items[actor.Pool.slot(guard)];
    try std.testing.expect(struck.hp < h.TEST_HP);
    try std.testing.expect(held.hp < held.max);
}

test "raising skeletons past the limit never crumbles a caravan guard" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    h.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    g.sim.mana = h.TEST_MANA;
    const guard = h.spawnAt(g, .caravan_guard, .{ .x = 24, .y = 20 }, true);
    for ([_]P{ .{ .x = 22, .y = 20 }, .{ .x = 20, .y = 22 } }) |at| {
        g.sim.cooldown.set(.raise_skeleton, 0);
        h.aimAt(g, .raise_skeleton, at);
        h.drawnOut(g);
    }
    try std.testing.expectEqual(@as(usize, 1), skeletonCount(g));
    try std.testing.expect(g.sim.pool.get(guard) != null);
}

test "a raised skeleton stands once its cast lands, and a recast takes a crumbled one's slot" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    h.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    g.sim.mana = h.TEST_MANA;
    const cells = [_]P{ .{ .x = 22, .y = 20 }, .{ .x = 20, .y = 22 }, .{ .x = 18, .y = 20 } };
    var bodies: [cells.len]usize = undefined;
    for (cells, &bodies) |at, *n| {
        g.sim.cooldown.set(.raise_skeleton, 0);
        h.aimAt(g, .raise_skeleton, at);
        const slot = actor.Pool.slot(g.sim.lv.who(at));
        try std.testing.expect(!g.pic.standing(&g.sim, slot));
        h.drawnOut(g);
        try std.testing.expect(g.pic.standing(&g.sim, slot));
        n.* = g.sim.pool.n;
        h.idleFor(g, @import("../gfx/impact_queue.zig").DEATH_S);
    }
    try std.testing.expectEqual(bodies[0] + 1, bodies[1]);
    try std.testing.expectEqual(bodies[1], bodies[2]);
    try std.testing.expectEqual(@as(usize, 1), skeletonCount(g));
}

test "the oldest skeleton crumbles first though a younger rose in an older one's slot" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    h.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    g.sim.mana = h.TEST_MANA;
    g.sim.growth.ranks.set(.raise_skeleton, 2);
    const a = P{ .x = 22, .y = 20 };
    const b = P{ .x = 20, .y = 22 };
    const c = P{ .x = 18, .y = 20 };
    const d = P{ .x = 20, .y = 18 };
    for ([_]P{ a, b }) |at| {
        g.sim.cooldown.set(.raise_skeleton, 0);
        h.aimAt(g, .raise_skeleton, at);
        h.drawnOut(g);
    }
    const elder = g.sim.lv.who(a);
    const first = actor.Pool.slot(elder);
    _ = g.sim.pool.damage(&g.sim.lv, elder, g.sim.pool.items[first].hp);
    combat.fell(g, elder);
    g.pic.settleSlot(&g.sim, h.TEST_DT, .fromIndex(first));
    h.idleFor(g, 1);
    for ([_]P{ c, d }) |at| {
        g.sim.cooldown.set(.raise_skeleton, 0);
        h.aimAt(g, .raise_skeleton, at);
        h.drawnOut(g);
    }
    try std.testing.expectEqual(first, actor.Pool.slot(g.sim.lv.who(c)));
    try std.testing.expect(g.sim.lv.who(b) == grid.NO_ONE);
    try std.testing.expect(g.sim.lv.who(c) != grid.NO_ONE and g.sim.lv.who(d) != grid.NO_ONE);
}

test "the hero trades places with a skeleton it walks into" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    const east = P{ .x = 21, .y = 20 };
    h.heroArena(g, .wizard, from, &.{});
    const id = h.spawnAt(g, .skeleton, east, true);
    game.settle(g);
    try std.testing.expectEqual(game.Move.swap, game.heroMove(g, .e));
    game.heroStep(g, .e, 0);
    try std.testing.expectEqual(east, g.sim.heroActor().?.at);
    try std.testing.expectEqual(from, g.sim.pool.get(id).?.at);
    try std.testing.expectEqual(id, g.sim.lv.who(from));
    try std.testing.expectEqual(g.sim.hero, g.sim.lv.who(east));
}

test "swings and rushes never mark an ally, a sweep needs more than allies, and raising leaves room for owed halves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    const east = P{ .x = 21, .y = 20 };
    const far = P{ .x = 23, .y = 20 };
    h.heroArena(g, .knight, from, &.{});
    _ = h.spawnAt(g, .skeleton, east, true);
    _ = h.spawnAt(g, .skeleton, far, true);
    game.settle(g);
    for ([_]skillbar.Act{ .shield_bash, .rend, .cleave }) |act| try std.testing.expect(!validAct(g, act, from, east));
    try std.testing.expect(!validAct(g, .charge, from, far));
    for ([_]skillbar.Act{ .shield_bash, .rend, .cleave, .charge }) |act| {
        skills.aiming(g, null, act);
        try std.testing.expect(!skills.aimable(g, from, if (act == .charge) far else east));
        skills.closeAim(g);
    }
    _ = h.spawnAt(g, .rat, .{ .x = 21, .y = 21 }, false);
    game.settle(g);
    try std.testing.expect(validAct(g, .cleave, from, east));
    skills.aiming(g, null, .cleave);
    try std.testing.expect(skills.aimable(g, from, east));
    skills.closeAim(g);
    const before = g.sim.pool.eventual();
    _ = h.spawnAt(g, .slime, .{ .x = 25, .y = 25 }, false);
    try std.testing.expectEqual(before + actor.most(.slime), g.sim.pool.eventual());
}

test "a charge strikes the foe a tile past its longest rush" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .knight, from, &.{});
    const at = from.add(.{ .x = skillbar.Act.charge.reach(), .y = 0 });
    const id = h.spawnAt(g, .rat, at, false);
    h.toughen(g.sim.pool.get(id).?);
    game.settle(g);
    h.aimAt(g, .charge, at);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(at.sub(.{ .x = 1, .y = 0 }), g.sim.heroActor().?.at);
    try std.testing.expect(g.sim.cooldown.get(.charge) > 0);
}
