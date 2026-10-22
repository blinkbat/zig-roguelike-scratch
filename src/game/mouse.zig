const std = @import("std");
const rl = @import("raylib");
const game = @import("../game.zig");
const skills = @import("skills.zig");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const skillbar = @import("../play/skillbar.zig");
const menu = @import("../ui/menu.zig");
const hud = @import("../ui/hud.zig");
const journal = @import("../ui/journal.zig");
const raster = @import("../gfx/raster.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const P = mathx.P;

pub const State = struct {
    target: ?P = null,
    foe: ?u16 = null,
    fresh: bool = false,
    secondary: bool = false,

    pub fn stop(self: *State) void {
        self.target = null;
        self.foe = null;
        self.fresh = false;
    }
};

pub fn buttonBox(screen: P, character: bool) rl.Rectangle {
    return raster.rect(screen.x - 156, screen.y - (if (character) @as(i32, 88) else 48), 144, 32);
}

pub fn draw(g: *game.Game) void {
    if (g.st.device.pad() or !clickable(g.mode)) return;
    menu.action(&g.face, buttonBox(g.screen, true), prompt_icon.Prompt.menuOf(&g.st, menu.CHARACTER), "Character");
    menu.action(&g.face, buttonBox(g.screen, false), prompt_icon.Prompt.menuOf(&g.st, menu.PAUSE), "Menu");
}

fn clickable(mode: game.Mode) bool {
    return mode == .play or mode == .aim or mode == .inspect;
}

pub fn overUi(g: *const game.Game, p: P) bool {
    const layout = game.overlay.hudLayout(g);
    return raster.holds(raster.rect(layout.left, layout.top, hud.WIDTH, hud.COVER), p) or
        raster.holds(journal.box(g.screen), p) or raster.holds(game.scene.miniFrame(g.screen.x), p) or
        raster.holds(buttonBox(g.screen, true), p) or raster.holds(buttonBox(g.screen, false), p);
}

pub fn cell(g: *game.Game) ?P {
    const p = g.st.pointer orelse return null;
    if (p.x < 0 or p.y < 0 or p.x >= g.screen.x or p.y >= g.screen.y or overUi(g, p)) return null;
    const cam = game.scene.Cam.of(g);
    const at = P{ .x = @divFloor(p.x + cam.x, game.CELL), .y = @divFloor(p.y + cam.y, game.CELL) };
    return if (grid.Level.inside(at)) at else null;
}

pub fn prepare(g: *game.Game) void {
    if (g.st.device.pad()) g.mouse.secondary = false;
    if (!g.st.focused or g.mode != .play or g.st.walk != null or g.st.interact or g.st.pressed.count() > 0 or g.st.character_page != null) g.mouse.stop();
    if (!g.st.focused or !clickable(g.mode)) return;
    if (g.st.right_click and g.mode == .play) {
        g.mouse.stop();
        g.pending = null;
        g.st.pressed.insert(menu.PAUSE);
        return;
    }
    const p = g.st.pointer orelse return;
    if (g.st.click) {
        g.mouse.stop();
        g.pending = null;
        if (raster.holds(buttonBox(g.screen, true), p)) {
            g.mode = .play;
            g.st.pressed.insert(menu.CHARACTER);
            return;
        }
        if (raster.holds(buttonBox(g.screen, false), p)) {
            g.mode = .play;
            g.st.pressed.insert(menu.PAUSE);
            return;
        }
    }
    if (g.mode != .play) return;
    if (game.overlay.hovered(g)) |part| {
        if (part.spot == .slot) {
            if (g.st.scroll != 0) g.mouse.secondary = g.st.scroll < 0;
            if (g.st.click) {
                const b = skillbar.SLOTS[part.spot.slot];
                if (b == g.bar.modifier) {
                    g.mouse.secondary = !g.mouse.secondary;
                } else g.st.pressed.insert(b);
            }
        }
    }
    if (!g.st.click) return;
    const at = cell(g) orelse return;
    if (!g.lv.isSeen(at)) return;
    g.mouse.target = at;
    g.mouse.fresh = true;
    for (g.pool.slice(), 0..) |a, i| {
        if (!a.foe()) continue;
        const drawn = game.drawnCell(g, i) orelse continue;
        if (drawn.eq(at)) {
            g.mouse.foe = @import("../play/actor.zig").Pool.idOf(i);
            break;
        }
    }
}

pub fn aim(g: *game.Game) bool {
    if (!g.st.pointing()) return false;
    const at = cell(g) orelse return false;
    const h = g.heroActor() orelse return false;
    if (g.aim_act.reticle() == .swing) {
        const d = mathx.stepDir(at.sub(h.at).sign()) orelse return false;
        g.mark = h.at.add(d.delta());
    } else g.mark = at;
    game.turnToward(g, g.hero, g.mark.x - h.at.x);
    return g.st.click;
}

fn danger(g: *const game.Game) bool {
    for (g.pool.items[0..g.pool.n]) |a| if (a.alive and a.foe() and g.lv.isLit(a.at)) return true;
    return false;
}

fn attack(g: *game.Game, at: P) bool {
    const h = g.heroActor() orelse return false;
    const set = skills.activeSet(g);
    for (skillbar.SLOTS) |b| {
        const act = g.bar.at(.{ .set = set, .button = b }) orelse continue;
        if (act.reticle() == null or act.attack() == null or !act.aimable(&g.lv, h.at, at)) continue;
        if (skills.blocked(g, act, &g.flasks, g.mana) != null) continue;
        skills.useSkill(g, .{ .act = act, .by = b, .set = set });
        if (g.mode == .aim) {
            g.mark = at;
            skills.confirmAim(g);
        }
        return true;
    }
    return false;
}

/// A routed walk rests this long between steps, slower than a held walk's joined glides.
pub const REST_S: f32 = game.GLIDE_S * 0.5;

pub fn step(g: *game.Game) bool {
    var at = g.mouse.target orelse return false;
    if (!game.quiet(g)) return true;
    if (!g.mouse.fresh and game.sinceQuiet(g) < REST_S) return true;
    const h = g.heroActor() orelse {
        g.mouse.stop();
        return false;
    };
    if (!g.mouse.fresh and danger(g)) {
        g.mouse.stop();
        return true;
    }
    if (g.mouse.foe) |id| {
        g.mouse.stop();
        const foe = g.pool.get(id) orelse return true;
        if (!foe.alive or !g.lv.isLit(foe.at)) return true;
        at = foe.at;
        if (attack(g, at)) return true;
        if (mathx.dist(h.at, at) <= 1) {
            game.heroStep(g, mathx.stepDir(at.sub(h.at)).?, 0);
            return true;
        }
        g.mouse.target = at;
    }
    if (mathx.dist(h.at, at) <= game.INTERACT_REACH and g.lv.isLit(at)) {
        if (g.lv.at(at).opened() != null or game.character.lootReached(g, h.at, at)) {
            g.mouse.stop();
            game.character.openLoot(g, at);
            return true;
        }
        if (game.character.doorReached(g, h.at, at) != null) {
            g.mouse.stop();
            game.character.characterCommand(g, .{ .travel = at });
            return true;
        }
    }
    if (h.at.eq(at)) {
        const fresh = g.mouse.fresh;
        g.mouse.stop();
        if (fresh) skills.useSkill(g, .{ .act = .wait, .by = input.CONFIRM });
        return true;
    }
    const d = next(g, h.at, at) orelse {
        g.mouse.stop();
        return true;
    };
    g.mouse.fresh = false;
    if (danger(g) or h.at.add(d.delta()).eq(at)) g.mouse.stop();
    game.heroStep(g, d, 0);
    return true;
}

pub fn next(g: *const game.Game, from: P, to: P) ?mathx.Dir {
    if (!grid.Level.inside(to) or !g.lv.isSeen(to) or from.eq(to)) return null;
    var visited = std.StaticBitSet(grid.CELLS).initEmpty();
    var queue: [grid.CELLS]P = undefined;
    var first: [grid.CELLS]mathx.Dir = undefined;
    var head: usize = 0;
    var tail: usize = 1;
    queue[0] = from;
    visited.set(grid.Level.idx(from));
    while (head < tail) : (head += 1) {
        const p = queue[head];
        const toward = mathx.stepDir(to.sub(p).sign()).?;
        for ([_]u3{ 0, 1, 7, 2, 6, 3, 5, 4 }) |offset| {
            const d = toward.turned(offset);
            const q = p.add(d.delta());
            if (!grid.Level.inside(q) or !g.lv.isSeen(q)) continue;
            const i = grid.Level.idx(q);
            if (visited.isSet(i)) continue;
            const end = q.eq(to);
            if (!g.lv.walkable(q) and !(end and g.lv.at(q).opened() != null)) continue;
            if (g.lv.barrelSeen(q) and !end) continue;
            if (g.lv.isLit(q) and ((g.lv.taken(q) and !end) or g.lv.gassy(q))) continue;
            if (!end and game.leadsTo(g, q) != null) continue;
            const way = if (head == 0) d else first[head];
            if (end) return way;
            visited.set(i);
            first[tail] = way;
            queue[tail] = q;
            tail += 1;
        }
    }
    return null;
}

fn clickCell(g: *game.Game, at: P) void {
    g.st = .{ .device = .keys, .click = true, .pointer = game.scene.Cam.of(g).mid(at) };
    game.update(g, 0);
}

test "mouse walking stops on harm despite healing or mana shielding" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]bool{ false, true }) |shield| {
        game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const h = g.heroActor().?;
        h.hp -= 20;
        const initial = h.hp;
        clickCell(g, .{ .x = 24, .y = 20 });
        try std.testing.expect(g.mouse.target != null);
        h.hp += 10;
        if (shield) h.ward.raise();
        h.burn.start();
        _ = h.burn.tick(0);
        g.st = .{};
        game.update(g, 2);
        try std.testing.expect(h.hp > initial);
        try std.testing.expect(g.mouse.target == null);
        const stopped = h.at;
        game.update(g, 2);
        try std.testing.expectEqual(stopped, h.at);
    }
    std.debug.print("mouse walking: harm cancels routes after healing and through mana shields\n", .{});
}

test "mouse walking follows explored routes once per turn and stops on arrival or another input" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const dest = P{ .x = 23, .y = 20 };
    for ([_]P{ game.SCREEN_720, game.SCREEN_1080, game.SCREEN_1440 }) |screen| {
        g.screen = screen;
        game.harness.arena(g, start, &.{});
        const clock = g.clock.minute;
        clickCell(g, dest);
        try std.testing.expectEqual(start.add(mathx.Dir.e.delta()), g.heroActor().?.at);
        try std.testing.expect(g.mouse.target != null);
        g.st = .{ .device = .keys };
        for (0..3) |_| game.update(g, 2);
        try std.testing.expectEqual(dest, g.heroActor().?.at);
        try std.testing.expect(g.mouse.target == null);
        try std.testing.expectEqual(clock + 3 * @import("../map/day.zig").TURN_MINUTES, g.clock.minute);
    }
    game.harness.arena(g, start, &.{});
    g.busy = 0.5;
    const clock = g.clock;
    clickCell(g, dest);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(start, g.heroActor().?.at);
    g.st = .{ .walk = .s };
    game.update(g, 0);
    try std.testing.expect(g.mouse.target == null and g.pending.? == .walk);
    game.harness.arena(g, start, &.{});
    clickCell(g, dest);
    const stopped = g.heroActor().?.at;
    g.st = .{ .focused = false };
    game.update(g, 2);
    try std.testing.expectEqual(stopped, g.heroActor().?.at);
    try std.testing.expect(g.mouse.target == null);
    std.debug.print("mouse walking: three resolutions, nine exact turns, busy queue, keyboard override and focus cancellation\n", .{});
}

test "a routed walk rests between steps, the first leaving at once" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    game.harness.arena(g, start, &.{});
    clickCell(g, .{ .x = 26, .y = 20 });
    try std.testing.expectEqual(start.add(mathx.Dir.e.delta()), g.heroActor().?.at);
    g.st = .{ .device = .keys };
    var t: f32 = 0;
    const first = g.heroActor().?.at;
    while (g.heroActor().?.at.eq(first)) : (t += mathx.FRAME_DT) game.update(g, mathx.FRAME_DT);
    std.debug.print("routed walk: {d:.3} s a step against a held walk's {d:.3}\n", .{ t, game.GLIDE_S });
    try std.testing.expect(t >= game.GLIDE_S + REST_S - mathx.FRAME_DT);
    try std.testing.expect(t <= game.GLIDE_S + REST_S + 2 * mathx.FRAME_DT);
}

test "mouse routes avoid unknown cells walls gas barrels and stop when enemies appear" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const dest = P{ .x = 23, .y = 20 };
    game.harness.arena(g, start, &.{});
    const east = start.add(mathx.Dir.e.delta());
    try std.testing.expectEqual(@as(?mathx.Dir, .e), next(g, start, dest));
    g.lv.set(east, .wall);
    try std.testing.expect(next(g, start, dest).? != .e);
    g.lv.set(east, .floor);
    g.lv.gas[grid.Level.idx(east)] = 100;
    try std.testing.expect(next(g, start, dest).? != .e);
    g.lv.gas[grid.Level.idx(east)] = 0;
    g.lv.putBarrel(east);
    g.lv.barrel_seen[grid.Level.idx(east)] = true;
    try std.testing.expect(next(g, start, dest).? != .e);
    try std.testing.expectEqual(@as(?mathx.Dir, .e), next(g, start, east));
    g.lv.seen[grid.Level.idx(dest)] = false;
    try std.testing.expect(next(g, start, dest) == null);
    const clock = g.clock;
    clickCell(g, dest);
    try std.testing.expectEqual(clock, g.clock);
    game.harness.arena(g, start, &.{});
    clickCell(g, dest);
    const stopped = g.heroActor().?.at;
    _ = game.harness.spawnAt(g, .rat, .{ .x = 24, .y = 21 }, false);
    game.castSight(g, stopped);
    g.st = .{};
    game.update(g, 2);
    try std.testing.expectEqual(stopped, g.heroActor().?.at);
    try std.testing.expect(g.mouse.target == null);
    std.debug.print("mouse routes: walls, gas, barrels, unknown destinations and newly visible enemies checked\n", .{});
}

test "mouse targeting respects legality and hud clicks never confirm or move through panels" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const target = P{ .x = 23, .y = 20 };
    game.harness.arena(g, start, &.{target});
    const clock = g.clock;
    const use = game.harness.boundTo(g, .shoot);
    var spots: [game.overlay.SPOTS_MAX]game.overlay.Part = undefined;
    const slot = for (game.overlay.spotsOf(g, &spots)) |part| {
        if (part.spot == .slot and skillbar.SLOTS[part.spot.slot] == use.by) break part.box;
    } else unreachable;
    g.st = .{ .device = .keys, .pointer = raster.middleAt(slot), .click = true };
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    try std.testing.expectEqual(clock, g.clock);
    g.st = .{ .device = .keys, .pointer = raster.middleAt(slot), .click = true };
    game.update(g, 0);
    try std.testing.expectEqual(clock, g.clock);
    const blocked = P{ .x = 20, .y = 24 };
    g.lv.set(.{ .x = 20, .y = 22 }, .wall);
    game.castSight(g, start);
    clickCell(g, blocked);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    g.st = .{ .right_click = true };
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    clickCell(g, target);
    try std.testing.expect(g.shot != null);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    game.harness.drawnOut(g);
    const after = g.clock;
    g.st = .{ .device = .keys, .pointer = raster.middleAt(journal.box(g.screen)), .click = true };
    game.update(g, 0);
    try std.testing.expectEqual(after, g.clock);
    try std.testing.expect(g.mouse.target == null);
    std.debug.print("mouse targeting: HUD activation, no click-through, blocked shot, cancel and one clicked foe attack\n", .{});
}

test "a clicked foe beside the hero is bumped when every aimed attack is cooling" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    for (std.enums.values(skillbar.Act)) |a| {
        if (a.attack() != null) g.cooldown.set(a, 5);
    }
    const clock = g.clock;
    clickCell(g, .{ .x = 21, .y = 20 });
    try std.testing.expect(!std.meta.eql(clock, g.clock));
    std.debug.print("clicked foe with every attack cooling: the turn is spent on a bump\n", .{});
}

test "mouse containers menu buttons secondary set and death action preserve their turn contracts" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const chest = P{ .x = 21, .y = 20 };
    game.harness.arena(g, start, &.{});
    g.lv.set(chest, .chest);
    game.settle(g);
    const clock = g.clock.minute;
    clickCell(g, chest);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(chest));
    try std.testing.expectEqual(clock + @import("../map/day.zig").TURN_MINUTES, g.clock.minute);
    game.harness.drawnOut(g);
    clickCell(g, chest);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(@import("../ui/book.zig").Page.loot, g.character.page);
    try std.testing.expectEqual(clock + @import("../map/day.zig").TURN_MINUTES, g.clock.minute);
    g.st = .{ .right_click = true };
    game.update(g, 0);
    g.st = .{ .click = true, .pointer = raster.middleAt(buttonBox(g.screen, true)) };
    game.update(g, 0);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    g.st = .{ .right_click = true };
    game.update(g, 0);
    g.st = .{ .click = true, .pointer = raster.middleAt(buttonBox(g.screen, false)) };
    game.update(g, 0);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    g.st = .{ .right_click = true };
    game.update(g, 0);
    var spots: [game.overlay.SPOTS_MAX]game.overlay.Part = undefined;
    const modifier = for (game.overlay.spotsOf(g, &spots)) |part| {
        if (part.spot == .slot and skillbar.SLOTS[part.spot.slot] == g.bar.modifier) break part.box;
    } else unreachable;
    g.st = .{ .device = .keys, .click = true, .pointer = raster.middleAt(modifier) };
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Set.secondary, skills.activeSet(g));
    g.st = .{ .device = .keys, .click = true, .pointer = raster.middleAt(modifier) };
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Set.primary, skills.activeSet(g));
    g.mode = .dead;
    g.permadeath = true;
    g.busy = 1;
    g.st = .{ .click = true, .pointer = raster.middleAt(game.deadBox(g.screen)) };
    game.update(g, 0);
    try std.testing.expect(g.exit == null);
    g.busy = 0;
    game.update(g, 0);
    try std.testing.expectEqual(@as(?game.Exit, .back), g.exit);
    std.debug.print("mouse actions: chest one turn, loot free, character/menu/back, secondary toggle, death waits for presentation\n", .{});
}
