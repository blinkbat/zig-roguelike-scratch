const std = @import("std");
const rl = @import("raylib");
const game = @import("../game.zig");
const skills = @import("skills.zig");
const binds = @import("binds.zig");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const skillbar = @import("../play/skillbar.zig");
const actor = @import("../play/actor.zig");
const day = @import("../map/day.zig");
const menu = @import("../ui/menu.zig");
const book = @import("../ui/book.zig");
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
    corners_shown: bool = false,

    pub fn stop(self: *State) void {
        self.target = null;
        self.foe = null;
        self.fresh = false;
    }
};

const BUTTON = P{ .x = 144, .y = 32 };
const BUTTON_RIGHT: i32 = hud.EDGE;
const BUTTON_BOTTOM: i32 = 16;
const Corner = struct { button: input.Button, label: [:0]const u8 };
const CORNER = [_]Corner{
    .{ .button = menu.PAUSE, .label = "Menu" },
    .{ .button = menu.CHARACTER, .label = "Character" },
};

fn buttonBox(screen: P, button: input.Button) rl.Rectangle {
    const row = for (CORNER, 0..) |c, k| {
        if (c.button == button) break k;
    } else unreachable;
    const up: i32 = @intCast(row);
    return raster.rect(screen.x - BUTTON_RIGHT - BUTTON.x, screen.y - BUTTON_BOTTOM - BUTTON.y - up * (BUTTON.y + menu.ACTION_GAP), BUTTON.x, BUTTON.y);
}

fn buttonAt(screen: P, p: P) ?input.Button {
    for (CORNER) |c| {
        if (raster.holds(buttonBox(screen, c.button), p)) return c.button;
    }
    return null;
}

pub fn draw(g: *game.Game) void {
    g.mouse.corners_shown = !g.st.device.pad() and clickable(game.modeShown(g));
    if (!g.mouse.corners_shown) return;
    for (CORNER) |c| menu.action(&g.face, buttonBox(g.screen, c.button), prompt_icon.Prompt.menuOf(&g.st, c.button), c.label);
}

pub fn clickable(mode: game.Mode) bool {
    return mode == .play or mode == .aim or mode == .inspect;
}

pub fn overUi(g: *const game.Game, p: P) bool {
    const layout = game.overlay.hudLayout(g);
    return raster.holds(raster.rect(layout.left, layout.top, hud.WIDTH, hud.COVER), p) or
        raster.holds(journal.box(g.screen), p) or raster.holds(game.scene.miniFrame(g.screen.x), p) or
        (g.mouse.corners_shown and buttonAt(g.screen, p) != null) or overStatus(g, layout, p);
}

fn overStatus(g: *const game.Game, layout: hud.Layout, p: P) bool {
    var buf: hud.Shown = undefined;
    const shown = game.overlay.heroStatuses(g, &buf);
    for (0..shown.len) |k| if (raster.holds(hud.statusBox(layout, shown.len, k), p)) return true;
    return false;
}

pub fn cell(g: *game.Game) ?P {
    const p = g.st.pointer orelse return null;
    if (p.x < 0 or p.y < 0 or p.x >= g.screen.x or p.y >= g.screen.y or overUi(g, p)) return null;
    const at = game.scene.Cam.of(g).cellAt(g.cinema.lens.sourcePoint(p, g.screen));
    return if (grid.Level.inside(at)) at else null;
}

fn forget(g: *game.Game) void {
    g.mouse.stop();
    g.pending = null;
}

pub fn prepare(g: *game.Game) void {
    if (g.st.device.pad()) g.mouse.secondary = false;
    if (!g.st.focused or g.mode != .play or g.st.walk != null or g.st.interact or g.st.pressed.count() > 0 or g.st.character_page != null) g.mouse.stop();
    if (!g.st.focused or !clickable(std.meta.activeTag(g.mode))) return;
    if (g.st.right_click and g.mode == .play) {
        forget(g);
        g.st.pressed.insert(menu.PAUSE);
        return;
    }
    const p = g.st.pointer orelse return;
    if (g.st.click) {
        forget(g);
        if (g.mouse.corners_shown) if (buttonAt(g.screen, p)) |b| {
            g.mode = .play;
            g.st.pressed.insert(b);
            return;
        };
    }
    if (g.mode != .play) return;
    if (g.st.click or g.st.scroll != 0) if (game.overlay.hoveredSlot(g, p)) |slot| {
        if (g.st.scroll != 0) g.mouse.secondary = g.st.scroll < 0;
        if (g.st.click) {
            const b = skillbar.SLOTS[slot];
            if (b == g.bar.modifier) {
                g.mouse.secondary = !g.mouse.secondary;
            } else g.st.pressed.insert(b);
        }
    };
    if (!g.st.click or !game.acceptsAction(g)) return;
    const at = cell(g) orelse return;
    if (!g.pic.seenShown(&g.sim, at)) return;
    g.mouse.target = at;
    g.mouse.fresh = true;
    for (g.sim.pool.slice(), 0..) |a, i| {
        if (!a.livingFoe()) continue;
        const drawn = g.pic.drawnCell(&g.sim, i) orelse continue;
        if (drawn.eq(at)) {
            g.mouse.foe = actor.Pool.idOf(i);
            break;
        }
    }
}

pub fn aim(g: *game.Game) bool {
    const dropped = if (g.mode.aim.action == .wall_end) blk: {
        const wall = &g.mode.aim.action.wall_end;
        const dropped = wall.dragging and g.st.left_released and g.st.focused;
        if (!g.st.left_down or !g.st.focused) wall.dragging = false;
        break :blk dropped;
    } else false;
    if (!g.st.pointing() and !dropped) return false;
    const at = cell(g) orelse return false;
    const h = g.sim.heroActor() orelse return false;
    const mark = if (g.mode.aim.act().reticle() == .swing) h.at.add((mathx.toward(h.at, at) orelse return false).delta()) else at;
    skills.markAim(g, h.at, mark);
    return g.st.click or dropped;
}

pub fn confirmAim(g: *game.Game) void {
    const starts_wall = g.st.click and g.st.left_down and g.mode.aim.action == .wall_start;
    skills.confirmAim(g);
    if (starts_wall and g.mode == .aim and g.mode.aim.action == .wall_end) g.mode.aim.action.wall_end.dragging = true;
}

fn attack(g: *game.Game, id: u16) bool {
    const h = g.sim.heroActor() orelse return false;
    const set = skills.activeSet(g);
    for (skillbar.SLOTS) |b| {
        const act = g.bar.at(.{ .set = set, .button = b }) orelse continue;
        if (act.reticle() == null or act.attack() == null or act == .overwatch or act.supplyOf() != null) continue;
        if (skills.blockedNow(g, act) != null) continue;
        const at = skills.targetAt(g, act, h.at, id) orelse continue;
        skills.useSkill(g, .{ .act = act, .by = b, .set = set });
        if (g.mode == .aim) {
            g.mode.aim.mark = at;
            skills.confirmAim(g);
        }
        return true;
    }
    return false;
}

pub fn step(g: *game.Game) bool {
    var at = g.mouse.target orelse return false;
    if (!g.pic.quiet()) return true;
    const h = g.sim.heroActor() orelse {
        g.mouse.stop();
        return false;
    };
    if (!g.mouse.fresh and game.foesNear(g)) {
        g.mouse.stop();
        return true;
    }
    if (g.mouse.foe) |id| {
        g.mouse.stop();
        const foe = g.sim.pool.get(id) orelse return true;
        if (!foe.seenFoe(&g.sim.lv)) return true;
        at = foe.at;
        if (attack(g, id)) return true;
        if (mathx.adjacent(h.at, at)) {
            game.heroStep(g, mathx.dirTo(h.at, at).?, 0);
            return true;
        }
        g.mouse.target = at;
    }
    if (game.character.chestReached(g, h.at, at) or game.character.lootReached(g, h.at, at)) {
        g.mouse.stop();
        game.character.openLoot(g, at);
        return true;
    }
    if (game.jail.reached(g, at)) {
        g.mouse.stop();
        return game.jail.interact(g, at);
    }
    if (!h.at.eq(at) and game.character.doorReached(g, h.at, at) != null) {
        g.mouse.stop();
        game.character.characterCommand(g, .{ .travel = at });
        return true;
    }
    if (h.at.eq(at)) {
        const fresh = g.mouse.fresh;
        g.mouse.stop();
        if (fresh) skills.useSkill(g, .{ .act = .wait, .by = null });
        return true;
    }
    const d = next(g, h.at, at) orelse {
        g.mouse.stop();
        return true;
    };
    g.mouse.fresh = false;
    if (game.foesNear(g) or h.at.add(d.delta()).eq(at)) g.mouse.stop();
    game.heroStep(g, d, 0);
    return true;
}

/// Eighths turned off the heading, straight ahead first, then alternating sides outward.
const FAN = [_]u3{ 0, 1, 7, 2, 6, 3, 5, 4 };

pub fn next(g: *const game.Game, from: P, to: P) ?mathx.Dir {
    if (!grid.Level.inside(to) or !g.sim.lv.isSeen(to) or from.eq(to)) return null;
    var visited = grid.CellSet.initEmpty();
    var queue: [grid.CELLS]P = undefined;
    var first: [grid.CELLS]mathx.Dir = undefined;
    var head: usize = 0;
    var tail: usize = 1;
    queue[0] = from;
    visited.set(grid.Level.idx(from));
    while (head < tail) : (head += 1) {
        const p = queue[head];
        const ahead = mathx.toward(p, to).?;
        for (FAN) |offset| {
            const d = ahead.turned(offset);
            const q = p.add(d.delta());
            if (!grid.Level.inside(q) or !g.sim.lv.isSeen(q)) continue;
            const i = grid.Level.idx(q);
            if (visited.isSet(i)) continue;
            visited.set(i);
            const end = q.eq(to);
            const t = g.sim.lv.at(q);
            if (!g.sim.lv.walkable(q) and !(end and (t.opened() != null or t.closedGate()))) continue;
            if ((g.sim.lv.barrelSeen(q) or (g.sim.lv.isLit(q) and g.sim.lv.npcAt(q) != null)) and !end) continue;
            if (!end) if (g.sim.pool.getConst(g.sim.lv.who(q))) |body| {
                if (body.seenFoe(&g.sim.lv)) continue;
            };
            if (g.sim.lv.isLit(q) and g.sim.lv.harmful(q)) continue;
            if (!end and g.sim.leadsTo(q) != null) continue;
            const way = if (head == 0) d else first[head];
            if (end) return way;
            first[tail] = way;
            queue[tail] = q;
            tail += 1;
        }
    }
    return null;
}

const clickCell = game.harness.clickCell;

test "mouse walking stops on harm despite healing or mana shielding" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]bool{ false, true }) |shield| {
        game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const h = g.sim.heroActor().?;
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
}

test "combat mouse clicks only queue at the tail of the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    for ([_]bool{ false, true }) |tail| {
        game.harness.arena(g, start, &.{.{ .x = 24, .y = 20 }});
        g.pic.busy = if (tail) game.COMBAT_QUEUE_S else game.GLIDE_S;
        const clock = g.sim.clock;
        clickCell(g, .{ .x = 18, .y = 20 });
        try std.testing.expectEqual(tail, g.mouse.target != null);
        g.st = .{};
        game.update(g, g.pic.busy + mathx.FRAME_DT);
        try std.testing.expectEqual(if (tail) start.add(mathx.Dir.w.delta()) else start, g.sim.heroActor().?.at);
        try std.testing.expectEqual(game.harness.turned(clock, @intFromBool(tail)), g.sim.clock);
        try std.testing.expect(g.mouse.target == null);
    }
}

test "mouse walking follows explored routes once per turn and stops on arrival or another input" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const dest = P{ .x = 23, .y = 20 };
    for (game.SCREENS) |screen| {
        g.screen = screen;
        game.harness.arena(g, start, &.{});
        const clock = g.sim.clock.minute;
        clickCell(g, dest);
        try std.testing.expectEqual(start.add(mathx.Dir.e.delta()), g.sim.heroActor().?.at);
        try std.testing.expect(g.mouse.target != null);
        g.st = .{ .device = .keys };
        for (0..3) |_| game.update(g, 2);
        try std.testing.expectEqual(dest, g.sim.heroActor().?.at);
        try std.testing.expect(g.mouse.target == null);
        try std.testing.expectEqual(clock + 3 * day.TURN_MINUTES, g.sim.clock.minute);
    }
    game.harness.arena(g, start, &.{});
    g.pic.busy = 0.5;
    const clock = g.sim.clock;
    clickCell(g, dest);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(start, g.sim.heroActor().?.at);
    game.harness.walkBusy(g, .s, 0);
    try std.testing.expect(g.mouse.target == null and g.pending.? == .walk);
    game.harness.arena(g, start, &.{});
    clickCell(g, dest);
    const stopped = g.sim.heroActor().?.at;
    g.st = .{ .focused = false };
    game.update(g, 2);
    try std.testing.expectEqual(stopped, g.sim.heroActor().?.at);
    try std.testing.expect(g.mouse.target == null);
}

test "a routed walk keeps a held walk's pace, the first step leaving at once" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    game.harness.arena(g, start, &.{});
    clickCell(g, .{ .x = 26, .y = 20 });
    try std.testing.expectEqual(start.add(mathx.Dir.e.delta()), g.sim.heroActor().?.at);
    g.st = .{ .device = .keys };
    var t: f32 = 0;
    const first = g.sim.heroActor().?.at;
    while (g.sim.heroActor().?.at.eq(first)) : (t += mathx.FRAME_DT) game.update(g, mathx.FRAME_DT);
    try std.testing.expect(t >= input.Stepper.ARR - mathx.FRAME_DT);
    try std.testing.expect(t <= input.Stepper.ARR + 2 * mathx.FRAME_DT);
}

test "mouse routes avoid unknown cells walls gas barrels and stop when enemies appear" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const dest = P{ .x = 23, .y = 20 };
    game.harness.arena(g, start, &.{});
    const east = start.add(mathx.Dir.e.delta());
    try std.testing.expectEqual(@as(?mathx.Dir, .e), next(g, start, dest));
    g.sim.lv.set(east, .wall);
    try std.testing.expect(next(g, start, dest).? != .e);
    g.sim.lv.set(east, .floor);
    g.sim.lv.gas[grid.Level.idx(east)] = game.harness.TEST_GAS;
    try std.testing.expect(next(g, start, dest).? != .e);
    g.sim.lv.gas[grid.Level.idx(east)] = 0;
    g.sim.lv.putBarrel(east);
    g.sim.lv.barrel_seen[grid.Level.idx(east)] = true;
    try std.testing.expect(next(g, start, dest).? != .e);
    try std.testing.expectEqual(@as(?mathx.Dir, .e), next(g, start, east));
    g.sim.lv.seen[grid.Level.idx(dest)] = false;
    try std.testing.expect(next(g, start, dest) == null);
    const clock = g.sim.clock;
    clickCell(g, dest);
    try std.testing.expectEqual(clock, g.sim.clock);
    game.harness.arena(g, start, &.{});
    clickCell(g, dest);
    const stopped = g.sim.heroActor().?.at;
    _ = game.harness.spawnAt(g, .rat, .{ .x = 24, .y = 21 }, false);
    game.castSight(g, stopped);
    g.st = .{};
    game.update(g, 2);
    try std.testing.expectEqual(stopped, g.sim.heroActor().?.at);
    try std.testing.expect(g.mouse.target == null);
}

test "mouse targeting respects legality and hud clicks never confirm or move through panels" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const target = P{ .x = 23, .y = 20 };
    game.harness.arena(g, start, &.{target});
    const clock = g.sim.clock;
    const use = game.harness.boundTo(g, .shoot);
    const slot = game.overlay.slotBox(game.overlay.hudLayout(g), binds.Binds.colOf(use.by.?));
    game.harness.clickAt(g, raster.middleAt(slot));
    try game.harness.expectMode(g, .aim);
    try std.testing.expectEqual(clock, g.sim.clock);
    game.harness.clickAt(g, raster.middleAt(slot));
    try std.testing.expectEqual(clock, g.sim.clock);
    const blocked = P{ .x = 20, .y = 24 };
    g.sim.lv.set(.{ .x = 20, .y = 22 }, .wall);
    game.castSight(g, start);
    clickCell(g, blocked);
    try std.testing.expectEqual(clock, g.sim.clock);
    try game.harness.expectMode(g, .aim);
    game.harness.rightClick(g);
    try game.harness.expectMode(g, .play);
    clickCell(g, target);
    try std.testing.expect(g.pic.shot != null);
    try game.harness.expectMode(g, .play);
    game.harness.drawnOut(g);
    const after = g.sim.clock;
    game.harness.clickAt(g, raster.middleAt(journal.box(g.screen)));
    try std.testing.expectEqual(after, g.sim.clock);
    try std.testing.expect(g.mouse.target == null);
}

test "a mouse release that ends no wall drag leaves a smart-aimed reticle on its foe" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const target = P{ .x = 23, .y = 20 };
    game.harness.arena(g, start, &.{target});
    skills.openAim(g, null, .shoot);
    try std.testing.expectEqual(target, g.mode.aim.mark);
    g.st = .{ .device = .keys, .left_released = true, .pointer = game.scene.Cam.of(g).mid(.{ .x = 20, .y = 23 }) };
    game.update(g, 0);
    try game.harness.expectMode(g, .aim);
    try std.testing.expectEqual(target, g.mode.aim.mark);
}

test "a wall drag can only start on the map before the first endpoint is chosen" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    const start = P{ .x = 22, .y = 19 };
    const end = P{ .x = 22, .y = 21 };
    for ([_]bool{ false, true }) |from_map| {
        h.heroArena(g, .wizard, from, &.{});
        const camera = game.scene.Cam.of(g);
        const clock = g.sim.clock;
        if (from_map) h.useAct(g, .arcane_barrier) else h.aimAt(g, .arcane_barrier, start);
        g.st = .{
            .click = true,
            .left_down = true,
            .pointer = if (from_map) camera.mid(start) else raster.middleAt(journal.box(g.screen)),
        };
        game.update(g, 0);
        try std.testing.expectEqual(start, g.mode.aim.anchor().?);
        try std.testing.expectEqual(clock, g.sim.clock);
        g.st = .{ .left_released = true, .pointer = camera.mid(end) };
        game.update(g, 0);
        try std.testing.expectEqual(from_map, g.sim.lv.hasBarrier(.{ .x = 22, .y = 20 }));
        try std.testing.expectEqual(h.turned(clock, @intFromBool(from_map)), g.sim.clock);
    }
}

test "hidden corner buttons pass the first mouse click through to the map" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const point = raster.middleAt(buttonBox(g.screen, menu.PAUSE));
    g.st = .{ .device = .keys, .click = true, .pointer = point };
    const at = cell(g) orelse return error.NoMapCell;
    g.sim.lv.seen[grid.Level.idx(at)] = true;
    g.pic.snapSight(&g.sim);
    prepare(g);
    try std.testing.expectEqual(@as(?P, at), g.mouse.target);
    try std.testing.expect(!g.st.hit(menu.PAUSE));
    g.mouse.corners_shown = true;
    prepare(g);
    try std.testing.expect(g.mouse.target == null and g.st.hit(menu.PAUSE));
}

test "mouse routing across lit shallows ignores submerged foes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const leech = P{ .x = 22, .y = 20 };
    const to = P{ .x = 24, .y = 20 };
    game.harness.arena(g, from, &.{});
    var cells = grid.Cells.of(from.sub(.{ .x = 1, .y = 1 }), to.add(.{ .x = 2, .y = 2 }));
    while (cells.next()) |p| if (p.y != from.y) g.sim.lv.set(p, .wall);
    @memset(&g.sim.lv.seen, false);
    for (from.x..to.x + 1) |x| {
        const i = grid.Level.idx(.{ .x = @intCast(x), .y = from.y });
        g.sim.lv.seen[i] = true;
        g.sim.lv.lit[i] = true;
    }
    g.sim.lv.set(leech, .shallows);
    try std.testing.expectEqual(@as(?mathx.Dir, .e), next(g, from, to));
    const id = g.sim.pool.spawn(&g.sim.lv, actor.Actor.of(.bog_leech, leech));
    const body = g.sim.pool.get(id).?;
    body.submerged = true;
    try std.testing.expectEqual(@as(?mathx.Dir, .e), next(g, from, to));
    body.submerged = false;
    try std.testing.expectEqual(@as(?mathx.Dir, null), next(g, from, to));
}

test "mouse attacks skip combustion for unburning foes and cast it on burning foes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const target = P{ .x = 23, .y = 20 };
    const other = P{ .x = 23, .y = 22 };
    for ([_]bool{ false, true }) |other_burning| {
        game.harness.heroArena(g, .wizard, start, &.{ target, other });
        g.bar.bind(.{ .set = .primary, .button = .a }, .combustion);
        if (other_burning) game.harness.foes(g)[1].burn.start();
        const clock = g.sim.clock.minute;
        clickCell(g, target);
        try game.harness.expectMode(g, .play);
        try std.testing.expect(g.pic.shot != null);
        try std.testing.expectEqual(skillbar.Act.spark, g.pic.shot.?.act);
        try std.testing.expectEqual(clock + day.TURN_MINUTES, g.sim.clock.minute);
        try std.testing.expectEqual(@as(u8, 0), g.sim.cooldown.get(.combustion));
    }
    game.harness.heroArena(g, .wizard, start, &.{target});
    g.bar.bind(.{ .set = .primary, .button = .a }, .combustion);
    const foe = &game.harness.foes(g)[0];
    game.harness.toughen(foe);
    foe.burn.start();
    const hp = foe.hp;
    const clock = g.sim.clock.minute;
    clickCell(g, target);
    try game.harness.expectMode(g, .play);
    try std.testing.expect(g.pic.shot == null);
    try std.testing.expect(foe.hp < hp);
    try std.testing.expectEqual(@as(u8, 0), foe.burn.turns);
    try std.testing.expectEqual(clock + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expect(g.sim.cooldown.get(.combustion) > 0);
}

test "a clicked foe beside the hero is bumped when every aimed attack is cooling" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    for (std.enums.values(skillbar.Act)) |a| {
        if (a.attack() != null) g.sim.cooldown.set(a, 5);
    }
    const clock = g.sim.clock;
    clickCell(g, .{ .x = 21, .y = 20 });
    try std.testing.expect(!std.meta.eql(clock, g.sim.clock));
}

test "a click on a foe behind a visible interceptor uses a bound piercing shot" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const target = P{ .x = 24, .y = 20 };
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 22, .y = 20 }, target });
    g.sim.growth.ranks.set(.piercing_shot, 1);
    g.bar = .{};
    g.bar.bind(.{ .set = .primary, .button = .a }, .shoot);
    g.bar.bind(.{ .set = .primary, .button = .x }, .piercing_shot);
    for (game.harness.foes(g)) |*foe| game.harness.toughen(foe);
    clickCell(g, target);
    try std.testing.expectEqual(skillbar.Act.piercing_shot, g.pic.shot.?.act);
    try std.testing.expect(game.harness.foes(g)[1].hurt());
}

test "a clicked foe that dived out of sight before the walk resumed draws no reticle or shot" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const lake = P{ .x = 24, .y = 20 };
    g.sim.lv.set(lake, .water);
    const id = game.harness.spawnAt(g, .bog_leech, lake, false);
    game.settle(g);
    try std.testing.expect(g.sim.pool.get(id).?.submerged and g.sim.lv.isLit(lake));
    g.mouse.target = lake;
    g.mouse.foe = id;
    const clock = g.sim.clock;
    try std.testing.expect(step(g));
    try game.harness.expectMode(g, .play);
    try std.testing.expectEqual(clock, g.sim.clock);
}

test "mouse containers menu buttons secondary set and death action preserve their turn contracts" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const chest = P{ .x = 21, .y = 20 };
    game.harness.arena(g, start, &.{});
    g.sim.lv.set(chest, .chest);
    game.settle(g);
    const clock = g.sim.clock.minute;
    clickCell(g, chest);
    try std.testing.expectEqual(grid.Tile.chest_open, g.sim.lv.at(chest));
    try std.testing.expectEqual(clock + day.TURN_MINUTES, g.sim.clock.minute);
    game.harness.drawnOut(g);
    clickCell(g, chest);
    try game.harness.expectMode(g, .pause);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(clock + day.TURN_MINUTES, g.sim.clock.minute);
    game.harness.rightClick(g);
    g.mouse.corners_shown = true;
    g.st = .{ .click = true, .pointer = raster.middleAt(buttonBox(g.screen, menu.CHARACTER)) };
    game.update(g, 0);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    try game.harness.expectMode(g, .pause);
    game.harness.rightClick(g);
    try game.harness.expectMode(g, .play);
    g.st = .{ .click = true, .pointer = raster.middleAt(buttonBox(g.screen, menu.PAUSE)) };
    game.update(g, 0);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    game.harness.rightClick(g);
    const modifier = game.overlay.slotBox(game.overlay.hudLayout(g), binds.Binds.colOf(g.bar.modifier.?));
    game.harness.clickAt(g, raster.middleAt(modifier));
    try std.testing.expectEqual(skillbar.Set.secondary, skills.activeSet(g));
    game.harness.clickAt(g, raster.middleAt(modifier));
    try std.testing.expectEqual(skillbar.Set.primary, skills.activeSet(g));
    g.mode = .dead;
    g.permadeath = true;
    g.pic.busy = 1;
    g.st = .{ .click = true, .pointer = raster.middleAt(game.deadBox(g.screen)) };
    game.update(g, 0);
    try std.testing.expect(g.exit == null);
    g.pic.busy = 0;
    game.update(g, 0);
    try std.testing.expectEqual(@as(?game.Exit, .back), g.exit);
}
