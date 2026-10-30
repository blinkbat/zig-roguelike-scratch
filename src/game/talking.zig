const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const script = @import("../map/script.zig");
const trigger = @import("../play/trigger.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const menu = @import("../ui/menu.zig");
const panel = @import("../ui/talk.zig");
const game = @import("../game.zig");
const P = mathx.P;

fn scriptOf(g: *const game.Game) ?*const script.Script {
    const w = g.sim.map orelse return null;
    return &w.script;
}

/// After a spent turn: timers and waits count down, then the map's triggers are looked at.
pub fn afterTurn(g: *game.Game) void {
    const s = scriptOf(g) orelse return;
    if (g.mode == .dead) return;
    g.sim.plot.turn(s, g.sim.world(), &g.sim.log);
}

/// On arriving at a node, no time passing.
pub fn arrived(g: *game.Game) void {
    const s = scriptOf(g) orelse return;
    g.sim.plot.evaluate(s, g.sim.world(), &g.sim.log);
}

/// A folk with something to say the hero sees standing beside it.
pub fn beside(g: *game.Game) ?usize {
    const s = scriptOf(g) orelse return null;
    const at = g.sim.heroAt() orelse return null;
    var cells = grid.Cells.around(at, game.INTERACT_REACH);
    while (cells.next()) |p| {
        if (p.eq(at) or !g.sim.lv.isLit(p)) continue;
        const f = g.sim.lv.folkAt(p) orelse continue;
        if (f < s.folk_n and s.folk[f].dialog != null) return f;
    }
    return null;
}

/// Opens the folk's conversation; speaking spends no turn.
pub fn speak(g: *game.Game, folk: usize) void {
    const s = scriptOf(g) orelse return;
    if (folk >= s.folk_n) return;
    const f = &s.folk[folk];
    if (g.sim.heroAt()) |at| g.pic.turnToward(g.sim.hero, f.at.x - at.x);
    game.holdWalk(g);
    const d = f.dialog orelse return g.sim.log.say("{s} has nothing to say.", .{f.called()});
    if (!g.sim.plot.open(s, d, @intCast(folk), &g.sim.log)) return;
    g.mode = .talk;
    g.sim.unsaved = true;
}

/// A conversation up, or one a trigger asked for once the turn is drawn: it takes the screen.
pub fn due(g: *game.Game) bool {
    if (g.sim.plot.talk != null) {
        g.mode = .talk;
        return true;
    }
    if (g.sim.plot.asked == null or !g.pic.quiet() or g.sim.travel != null) return false;
    const s = scriptOf(g) orelse {
        g.sim.plot.asked = null;
        return false;
    };
    if (!g.sim.plot.open(s, g.sim.plot.takeAsked().?, null, &g.sim.log)) return false;
    game.holdWalk(g);
    g.mode = .talk;
    g.sim.unsaved = true;
    return true;
}

const Shown = struct {
    labels: [script.MAX_CHOICES][]const u8 = undefined,
    view: panel.View,
    layout: panel.Layout = .{ .panel = undefined, .text_x = 0, .text_w = 0, .action = undefined },
};

fn shownOf(g: *game.Game, s: *const script.Script, out: *Shown) bool {
    const rt = &g.sim.plot;
    const ln = rt.lineOf(s) orelse return false;
    var picks: [script.MAX_CHOICES]u8 = undefined;
    const offered = rt.offered(s, g.sim.world(), &picks);
    for (offered, 0..) |c, i| out.labels[i] = ln.choice[c].ask.text();
    out.view = .{ .who = rt.speaker(s), .say = ln.say.text(), .choices = out.labels[0..offered.len], .cursor = rt.talk.?.cursor, .prompt = prompt_icon.Prompt.menuOf(&g.st, menu.CONFIRM) };
    out.layout.of(&g.face, g.screen, out.view);
    return true;
}

/// No way out but one of its own endings; the cursor walks what is offered.
pub fn step(g: *game.Game) void {
    const s = scriptOf(g) orelse return finished(g);
    var shown: Shown = .{ .view = undefined };
    if (!shownOf(g, s, &shown)) return finished(g);
    const w = g.sim.world();
    const rt = &g.sim.plot;
    if (g.st.walk) |d| if (d.delta().y != 0) rt.moveCursor(s, w, d.delta().y);
    if (g.st.pointing()) if (shown.layout.rowAt(g.st.pointer.?)) |row| {
        rt.talk.?.cursor = @intCast(row);
        if (g.st.click) {
            rt.pick(s, row, w, &g.sim.log);
            g.sim.unsaved = true;
        }
    };
    if (rt.talk != null and (g.st.hit(menu.CONFIRM) or g.st.clicked(shown.layout.action))) {
        rt.confirm(s, w, &g.sim.log);
        g.sim.unsaved = true;
    }
    if (rt.talk == null) finished(g);
}

fn finished(g: *game.Game) void {
    g.mode = .play;
    game.holdWalk(g);
}

pub fn draw(g: *game.Game) void {
    const s = scriptOf(g) orelse return;
    var shown: Shown = .{ .view = undefined };
    if (!shownOf(g, s, &shown)) return;
    panel.draw(&g.face, g.screen, shown.view, &shown.layout);
}

const harness = @import("harness.zig");
const atlas = @import("../map/atlas.zig");
const script_text = @import("../map/script_text.zig");

fn testWorld(text: []const u8) !*atlas.Atlas {
    const w = try atlas.testAtlas();
    errdefer std.testing.allocator.destroy(w);
    const n = w.add(.{ .bespoke = .{} }).?;
    const b = &w.node[n].plan.bespoke;
    var floor = grid.Box.sized(.{ .x = 2, .y = 2 }, 20, 12).cells();
    while (floor.next()) |p| b.tile[grid.Level.idx(p)] = .floor;
    w.start = .{ .node = n, .at = .{ .x = 5, .y = 5 } };
    try script_text.readAlone(text, &w.script, w.node_n);
    return w;
}

const press = harness.press;

test "bumping a folk opens its conversation without a turn; it closes only through an ending" {
    const w = try testWorld(
        \\flag met
        \\dialog wenna
        \\line root
        \\say Nobody comes down the well.
        \\ask Who are you? -> name
        \\ask Goodbye. -> end
        \\line name
        \\act flag met on
        \\say Wenna. I keep the cistern.
        \\then root
        \\folk 0 6 5 wenna Old Wenna
        \\folk 0 5 6 -
    );
    defer std.testing.allocator.destroy(w);
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, 9);
    try std.testing.expectEqual(@as(?usize, 0), g.sim.lv.folkAt(.{ .x = 6, .y = 5 }));
    try std.testing.expect(!g.sim.lv.vacant(.{ .x = 6, .y = 5 }));
    const turns = g.sim.plot.turns;
    const at = g.sim.heroActor().?.at;
    try std.testing.expectEqual(game.Move.talk, game.heroMove(g, .e));
    game.heroStep(g, .e, 0);
    try std.testing.expect(g.sim.heroActor().?.at.eq(at));
    try std.testing.expectEqual(game.Mode.talk, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(turns, g.sim.plot.turns);
    press(g, menu.BACK);
    try std.testing.expectEqual(game.Mode.talk, std.meta.activeTag(g.mode));
    press(g, menu.CONFIRM);
    try std.testing.expect(g.sim.plot.flags[0]);
    press(g, menu.CONFIRM);
    g.st.walk = .s;
    game.update(g, harness.TEST_DT);
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(g.sim.plot.talked[0]);
    try std.testing.expect(g.sim.plot.talk == null);
    game.heroStep(g, .s, 0);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqualStrings("Stranger has nothing to say.", g.sim.log.line(0).?);
    std.debug.print("folk: bump opens a conversation on turn {d}; back refused, two lines walked and an ending closes it\n", .{turns});
}

test "a trigger's conversation waits for the turn to be drawn, then takes the screen" {
    const w = try testWorld(
        \\dialog warn
        \\line root
        \\say Turn back.
        \\trigger warned 0 once live
        \\when elapsed >= 1
        \\do dialog warn
        \\do text The voice fades.
    );
    defer std.testing.allocator.destroy(w);
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, 9);
    try std.testing.expectEqual(@as(?u8, null), g.sim.plot.asked);
    game.heroStep(g, .e, 0);
    try std.testing.expectEqual(@as(?u8, 0), g.sim.plot.asked);
    for (0..400) |_| {
        if (g.mode == .talk) break;
        game.update(g, harness.TEST_DT);
    }
    try std.testing.expectEqual(game.Mode.talk, std.meta.activeTag(g.mode));
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqualStrings("The voice fades.", g.sim.log.line(0).?);
}
