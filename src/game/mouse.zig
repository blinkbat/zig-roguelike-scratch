const std = @import("std");
const rl = @import("raylib");
const game = @import("../game.zig");
const skills = @import("skills.zig");
const tactics = @import("tactics.zig");
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

    pub fn stop(self: *State) void {
        self.target = null;
        self.foe = null;
        self.fresh = false;
    }
};

const BUTTON = P{ .x = 144, .y = 32 };
const BUTTON_RIGHT: i32 = 12;
const BUTTON_BOTTOM: i32 = 16;
const Corner = struct { button: input.Button, label: [:0]const u8 };
const CORNER = [_]Corner{
    .{ .button = menu.PAUSE, .label = "Menu" },
    .{ .button = menu.CHARACTER, .label = "Character" },
};

pub fn buttonBox(screen: P, button: input.Button) rl.Rectangle {
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
    if (g.st.device.pad() or !clickable(g.mode)) return;
    for (CORNER) |c| menu.action(&g.face, buttonBox(g.screen, c.button), prompt_icon.Prompt.menuOf(&g.st, c.button), c.label);
}

fn clickable(mode: game.ModeState) bool {
    return mode == .play or mode == .aim or mode == .inspect;
}

pub fn overUi(g: *const game.Game, p: P) bool {
    const layout = game.overlay.hudLayout(g);
    return raster.holds(raster.rect(layout.left, layout.top, hud.WIDTH, hud.COVER), p) or
        raster.holds(journal.box(g.screen), p) or raster.holds(game.scene.miniFrame(g.screen.x), p) or
        buttonAt(g.screen, p) != null;
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
        if (buttonAt(g.screen, p)) |b| {
            g.mode = .play;
            g.st.pressed.insert(b);
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
    if (!g.sim.lv.isSeen(at)) return;
    g.mouse.target = at;
    g.mouse.fresh = true;
    for (g.sim.pool.slice(), 0..) |a, i| {
        if (!a.foe()) continue;
        const drawn = g.pic.drawnCell(&g.sim, i) orelse continue;
        if (drawn.eq(at)) {
            g.mouse.foe = actor.Pool.idOf(i);
            break;
        }
    }
}

pub fn aim(g: *game.Game) bool {
    if (!g.st.pointing() and !g.st.left_released) return false;
    const at = cell(g) orelse return false;
    const h = g.sim.heroActor() orelse return false;
    if (g.mode.aim.act().reticle() == .swing) {
        const d = mathx.toward(h.at, at) orelse return false;
        g.mode.aim.mark = h.at.add(d.delta());
    } else g.mode.aim.mark = at;
    skills.rememberTarget(g);
    g.pic.turnToward(g.sim.hero, g.mode.aim.mark.x - h.at.x);
    return g.st.click or (g.mode.aim.act() == .arcane_barrier and g.mode.aim.anchor() != null and g.st.left_released);
}

fn danger(g: *const game.Game) bool {
    for (g.sim.pool.items[0..g.sim.pool.n]) |a| if (a.alive and a.foe() and g.sim.lv.isLit(a.at)) return true;
    return false;
}

fn attack(g: *game.Game, at: P) bool {
    const h = g.sim.heroActor() orelse return false;
    const set = skills.activeSet(g);
    for (skillbar.SLOTS) |b| {
        const act = g.bar.at(.{ .set = set, .button = b }) orelse continue;
        if (act.reticle() == null or act.attack() == null or !tactics.validAct(g, act, h.at, at)) continue;
        if (skills.blocked(g, act, &g.sim.flasks, g.sim.mana) != null) continue;
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
    if (!g.mouse.fresh and danger(g)) {
        g.mouse.stop();
        return true;
    }
    if (g.mouse.foe) |id| {
        g.mouse.stop();
        const foe = g.sim.pool.get(id) orelse return true;
        if (!foe.alive or !g.sim.lv.isLit(foe.at)) return true;
        at = foe.at;
        if (attack(g, at)) return true;
        if (mathx.dist(h.at, at) <= 1) {
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
    if (game.character.doorReached(g, h.at, at) != null) {
        g.mouse.stop();
        game.character.characterCommand(g, .{ .travel = at });
        return true;
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

/// Eighths turned off the heading, straight ahead first, then alternating sides outward.
const FAN = [_]u3{ 0, 1, 7, 2, 6, 3, 5, 4 };

pub fn next(g: *const game.Game, from: P, to: P) ?mathx.Dir {
    if (!grid.Level.inside(to) or !g.sim.lv.isSeen(to) or from.eq(to)) return null;
    var visited = std.StaticBitSet(grid.CELLS).initEmpty();
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
            const end = q.eq(to);
            if (!g.sim.lv.walkable(q) and !(end and g.sim.lv.at(q).opened() != null)) continue;
            if (g.sim.lv.barrelSeen(q) and !end) continue;
            if (g.sim.lv.isLit(q) and ((g.sim.lv.taken(q) and !end) or g.sim.lv.gassy(q))) continue;
            if (!end and g.sim.leadsTo(q) != null) continue;
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
    std.debug.print("mouse walking: harm cancels routes after healing and through mana shields\n", .{});
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
    g.st = .{ .walk = .s };
    game.update(g, 0);
    try std.testing.expect(g.mouse.target == null and g.pending.? == .walk);
    game.harness.arena(g, start, &.{});
    clickCell(g, dest);
    const stopped = g.sim.heroActor().?.at;
    g.st = .{ .focused = false };
    game.update(g, 2);
    try std.testing.expectEqual(stopped, g.sim.heroActor().?.at);
    try std.testing.expect(g.mouse.target == null);
    std.debug.print("mouse walking: three resolutions, nine exact turns, busy queue, keyboard override and focus cancellation\n", .{});
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
    std.debug.print("routed walk: {d:.3} s a step against a held walk's {d:.3}\n", .{ t, input.Stepper.ARR });
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
    std.debug.print("mouse routes: walls, gas, barrels, unknown destinations and newly visible enemies checked\n", .{});
}

test "mouse targeting respects legality and hud clicks never confirm or move through panels" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = P{ .x = 20, .y = 20 };
    const target = P{ .x = 23, .y = 20 };
    game.harness.arena(g, start, &.{target});
    const clock = g.sim.clock;
    const use = game.harness.boundTo(g, .shoot);
    const slot = game.overlay.slotBox(game.overlay.hudLayout(g), binds.Binds.colOf(use.by));
    g.st = .{ .device = .keys, .pointer = raster.middleAt(slot), .click = true };
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(clock, g.sim.clock);
    g.st = .{ .device = .keys, .pointer = raster.middleAt(slot), .click = true };
    game.update(g, 0);
    try std.testing.expectEqual(clock, g.sim.clock);
    const blocked = P{ .x = 20, .y = 24 };
    g.sim.lv.set(.{ .x = 20, .y = 22 }, .wall);
    game.castSight(g, start);
    clickCell(g, blocked);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    g.st = .{ .right_click = true };
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    clickCell(g, target);
    try std.testing.expect(g.pic.shot != null);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    game.harness.drawnOut(g);
    const after = g.sim.clock;
    g.st = .{ .device = .keys, .pointer = raster.middleAt(journal.box(g.screen)), .click = true };
    game.update(g, 0);
    try std.testing.expectEqual(after, g.sim.clock);
    try std.testing.expect(g.mouse.target == null);
    std.debug.print("mouse targeting: HUD activation, no click-through, blocked shot, cancel and one clicked foe attack\n", .{});
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
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
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
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(g.pic.shot == null);
    try std.testing.expect(foe.hp < hp);
    try std.testing.expectEqual(@as(u8, 0), foe.burn.turns);
    try std.testing.expectEqual(clock + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expect(g.sim.cooldown.get(.combustion) > 0);
    std.debug.print("mouse attacks: 2 unburning-target cases choose Spark; burning target consumes burn with Combustion, one turn each\n", .{});
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
    std.debug.print("clicked foe with every attack cooling: the turn is spent on a bump\n", .{});
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
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(clock + day.TURN_MINUTES, g.sim.clock.minute);
    g.st = .{ .right_click = true };
    game.update(g, 0);
    g.st = .{ .click = true, .pointer = raster.middleAt(buttonBox(g.screen, menu.CHARACTER)) };
    game.update(g, 0);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    g.st = .{ .right_click = true };
    game.update(g, 0);
    g.st = .{ .click = true, .pointer = raster.middleAt(buttonBox(g.screen, menu.PAUSE)) };
    game.update(g, 0);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    g.st = .{ .right_click = true };
    game.update(g, 0);
    const modifier = game.overlay.slotBox(game.overlay.hudLayout(g), binds.Binds.colOf(g.bar.modifier.?));
    g.st = .{ .device = .keys, .click = true, .pointer = raster.middleAt(modifier) };
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Set.secondary, skills.activeSet(g));
    g.st = .{ .device = .keys, .click = true, .pointer = raster.middleAt(modifier) };
    game.update(g, 0);
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
    std.debug.print("mouse actions: chest one turn, loot free, character/menu/back, secondary toggle, death waits for presentation\n", .{});
}
