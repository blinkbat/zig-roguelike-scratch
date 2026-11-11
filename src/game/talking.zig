const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const script = @import("../map/script.zig");
const trigger = @import("../play/trigger.zig");
const ground_items = @import("../play/ground_items.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const look = @import("../gfx/look.zig");
const menu = @import("../ui/menu.zig");
const panel = @import("../ui/talk.zig");
const game = @import("../game.zig");
const P = mathx.P;

fn scriptOf(g: *const game.Game) ?*const script.Script {
    const w = g.sim.map orelse return null;
    return &w.script;
}

pub fn afterTurn(g: *game.Game) void {
    const s = scriptOf(g) orelse return;
    if (g.mode == .dead) return;
    g.sim.plot.turn(s, g.sim.world(), &g.sim.log);
    restand(g);
}

/// On arriving at a node, no time passing.
pub fn arrived(g: *game.Game) void {
    const s = scriptOf(g) orelse return;
    g.sim.plot.evaluate(s, g.sim.world(), &g.sim.log);
    restand(g);
    g.pic.showPlot(&g.sim);
}

const Standing = struct {
    rt: *const trigger.Runtime,
    s: *const script.Script,
    w: trigger.World,
    ground: *const ground_items.Ground,

    pub fn shows(self: Standing, i: usize) bool {
        return self.rt.shows(self.s, i, self.w);
    }

    pub fn lying(self: Standing) grid.CellSet {
        return self.ground.lying();
    }
};

pub fn stampNpcs(g: *game.Game, n: usize, lv: *grid.Level) void {
    stampIn(g, n, lv, g.sim.world());
}

/// Node `n`'s NPCs as the hero arrives at `at`, before a fresh node's foes stand: its own world, not the one left.
pub fn stampEntering(g: *game.Game, n: usize, at: P, back: bool) void {
    var world = g.sim.world();
    world.node = n;
    world.hero = at;
    if (!back) world.alive = .initFill(0);
    stampIn(g, n, &g.sim.lv, world);
}

fn stampIn(g: *game.Game, n: usize, lv: *grid.Level, world: trigger.World) void {
    const w = g.sim.map orelse return lv.clearNpcs();
    const ground = if (n == g.sim.node) &g.sim.ground else &g.sim.visits[n].ground;
    w.stampNpcs(n, lv, &g.sim.plot.spots, Standing{ .rt = &g.sim.plot, .s = &w.script, .w = world, .ground = ground });
}

pub fn restand(g: *game.Game) void {
    stampNpcs(g, g.sim.node, &g.sim.lv);
}

pub fn beside(g: *game.Game) ?usize {
    const s = scriptOf(g) orelse return null;
    const at = g.sim.heroAt() orelse return null;
    var cells = grid.Cells.around(at, game.INTERACT_REACH);
    while (cells.next()) |p| {
        if (p.eq(at) or !g.pic.litShown(&g.sim, p)) continue;
        const f = g.pic.npcShown(p) orelse continue;
        if (f < s.npc_n) if (s.npc[f].dialog) |d| if (s.opens(d)) return f;
    }
    return null;
}

pub fn speak(g: *game.Game, npc: usize) void {
    const s = scriptOf(g) orelse return;
    if (npc >= s.npc_n) return;
    const who = &s.npc[npc];
    if (g.sim.heroAt()) |at| if (g.sim.plot.spotOf(s, npc)) |there| g.pic.turnHero(&g.sim, there.x - at.x);
    if (who.dialog) |d| if (g.sim.plot.open(s, d, @intCast(npc), &g.sim.log)) return opened(g);
    game.holdWalk(g);
    g.sim.log.say("{s} has nothing to say.", .{who.called()});
}

fn opened(g: *game.Game) void {
    game.holdWalk(g);
    g.mode = .talk;
    g.sim.unsaved = true;
    restand(g);
    handOver(g);
}

/// A spoken `trade` opens the merchant's wares over the conversation.
fn handOver(g: *game.Game) void {
    const npc = g.sim.plot.takeTrading() orelse return;
    game.character.openTrade(g, npc);
}

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
    opened(g);
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
    out.view = .{ .who = rt.speaker(s), .say = ln.say.text(), .choices = out.labels[0..offered.len], .cursor = rt.talk.?.cursor, .prompt = prompt_icon.Prompt.menuOf(&g.st, menu.CONFIRM), .figure = figureOf(g, s, ln) };
    out.layout.of(&g.face, g.screen, out.view);
    return true;
}

/// The NPC spoken to, unless the line names another speaker.
fn figureOf(g: *const game.Game, s: *const script.Script, ln: *const script.Line) ?panel.Figure {
    const npc = &s.npc[g.sim.plot.talk.?.npc orelse return null];
    if (ln.who.n > 0 and !ln.who.eql(npc.called())) return null;
    const k = npc.looks orelse return .{};
    return .{ .tex = g.sprites.body(k), .glyph = look.body(k) };
}

pub fn step(g: *game.Game) void {
    const s = scriptOf(g) orelse return finished(g);
    var shown: Shown = .{ .view = undefined };
    if (!shownOf(g, s, &shown)) return finished(g);
    const w = g.sim.world();
    const rt = &g.sim.plot;
    if (g.st.walk) |d| if (d.delta().y != 0) rt.moveCursor(s, w, d.delta().y);
    var picked = false;
    if (g.st.pointing()) if (shown.layout.rowAt(g.st.pointer.?)) |row| {
        rt.talk.?.cursor = @intCast(row);
        if (g.st.click) {
            rt.pick(s, row, w, &g.sim.log);
            picked = true;
        }
    };
    if (!picked and rt.talk != null and (g.st.hit(menu.CONFIRM) or g.st.clicked(shown.layout.action))) {
        rt.confirm(s, w, &g.sim.log);
        picked = true;
    }
    if (picked) {
        g.sim.unsaved = true;
        restand(g);
    }
    if (rt.trading != null) return handOver(g);
    if (rt.talk == null) finished(g);
}

fn finished(g: *game.Game) void {
    game.toPlay(g);
}

pub fn draw(g: *game.Game) void {
    const s = scriptOf(g) orelse return;
    var shown: Shown = .{ .view = undefined };
    if (!shownOf(g, s, &shown)) return;
    panel.draw(&g.face, &g.sprites, g.screen, shown.view, &shown.layout);
}

const harness = @import("harness.zig");
const atlas = @import("../map/atlas.zig");
const script_text = @import("../map/script_text.zig");
const raster = @import("../gfx/raster.zig");
const book = @import("../ui/book.zig");
const trade = @import("../play/trade.zig");

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
const SEED = 9;

const WENNA =
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
    \\npc 0 6 5 wenna Old Wenna
;

test "bumping an NPC opens its conversation without a turn; it closes only through an ending" {
    const w = try testWorld(WENNA ++ "\nnpc 0 5 6 -");
    defer std.testing.allocator.destroy(w);
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, SEED);
    try std.testing.expectEqual(@as(?usize, 0), g.sim.lv.npcAt(.{ .x = 6, .y = 5 }));
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
}

test "a choice clicked while confirm is pressed is one pick" {
    const w = try testWorld(WENNA);
    defer std.testing.allocator.destroy(w);
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, SEED);
    game.heroStep(g, .e, 0);
    try std.testing.expectEqual(game.Mode.talk, std.meta.activeTag(g.mode));
    var shown: Shown = .{ .view = undefined };
    try std.testing.expect(shownOf(g, scriptOf(g).?, &shown));
    g.st = .{ .device = .keys, .click = true, .pointer = raster.middleAt(shown.layout.rows[0]), .pressed = .initOne(menu.CONFIRM) };
    game.update(g, 0);
    try std.testing.expectEqual(@as(u8, 1), g.sim.plot.talk.?.line);
}

test "a direction held as the conversation moves to another line does not walk the new line's choices" {
    const w = try testWorld(
        \\dialog wenna
        \\line root
        \\say Nobody comes down the well.
        \\then pick
        \\line pick
        \\say Well?
        \\ask Stay. -> end
        \\ask Go. -> end
        \\npc 0 6 5 wenna Old Wenna
    );
    defer std.testing.allocator.destroy(w);
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, SEED);
    game.heroStep(g, .e, 0);
    try std.testing.expectEqual(game.Mode.talk, std.meta.activeTag(g.mode));
    g.st = .{ .device = .keys, .walk = .s, .pressed = .initOne(menu.CONFIRM) };
    game.update(g, 0);
    try std.testing.expectEqual(@as(u8, 1), g.sim.plot.talk.?.line);
    try std.testing.expect(g.st.step.carried());
}

test "a dialog no way through ends never opens, while one whose way out is gated does" {
    const w = try testWorld(
        \\flag met
        \\dialog loop
        \\line root
        \\say Round and round.
        \\then root
        \\dialog gated
        \\line root
        \\say Not yet.
        \\ask Leave. -> end
        \\need flag met on
        \\npc 0 6 5 loop Looper
        \\npc 0 5 6 gated Keeper
    );
    defer std.testing.allocator.destroy(w);
    try std.testing.expect(!w.script.dialog[0].ends());
    try std.testing.expect(w.script.dialog[1].ends());
    try std.testing.expectEqual(@as(usize, 1), w.script.endless());
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, SEED);
    game.heroStep(g, .e, 0);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    game.heroStep(g, .s, 0);
    try std.testing.expectEqual(game.Mode.talk, std.meta.activeTag(g.mode));
}

test "a dialog with a reachable line no way out of never opens, though its first line can end" {
    const w = try testWorld(
        \\dialog trap
        \\line root
        \\say Choose.
        \\ask Bye. -> end
        \\ask Stay. -> held
        \\line held
        \\say Stay forever.
        \\then held
        \\npc 0 6 5 trap Trapper
    );
    defer std.testing.allocator.destroy(w);
    try std.testing.expect(!w.script.dialog[0].ends());
    try std.testing.expectEqual(@as(usize, 1), w.script.endless());
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, SEED);
    game.heroStep(g, .e, 0);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqualStrings("Trapper has nothing to say.", g.sim.log.line(0).?);
}

test "a dialog whose only way out is gated beside an ungated loop never opens, nor one whose gated choice loops" {
    const w = try testWorld(
        \\flag f
        \\dialog hidden
        \\line a
        \\say Again.
        \\ask Again. -> a
        \\ask Leave. -> end
        \\need flag f on
        \\dialog looping
        \\line a
        \\say Ask.
        \\ask About it. -> b
        \\need flag f on
        \\line b
        \\say It.
        \\then a
        \\npc 0 6 5 hidden Hider
    );
    defer std.testing.allocator.destroy(w);
    try std.testing.expect(!w.script.dialog[0].ends());
    try std.testing.expect(!w.script.dialog[1].ends());
    try std.testing.expectEqual(@as(usize, 2), w.script.endless());
}

test "a way out that never shows ends nothing: its NPC has nothing to say and a trigger asking for it goes on" {
    const w = try testWorld(
        \\flag reward
        \\dialog stuck
        \\line root
        \\say Again.
        \\ask Again. -> root
        \\ask Bye. -> end
        \\need never
        \\npc 0 6 5 stuck Stuck
        \\trigger asks 0 once live
        \\when elapsed >= 1
        \\do dialog stuck
        \\do flag reward on
    );
    defer std.testing.allocator.destroy(w);
    try std.testing.expect(!w.script.dialog[0].ends());
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, SEED);
    try std.testing.expectEqual(@as(?usize, null), beside(g));
    game.heroStep(g, .e, 0);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqualStrings("Stuck has nothing to say.", g.sim.log.line(0).?);
    game.heroStep(g, .s, 0);
    try std.testing.expectEqual(@as(?u8, null), g.sim.plot.asked);
    try std.testing.expect(g.sim.plot.flags[0]);
    try std.testing.expect(!g.sim.plot.runs[0].held);
}

test "NPCs stand by a prop and far off; a quest given, carried and finished takes one away and brings another" {
    const w = try testWorld(
        \\flag carrying
        \\quest pib The Stolen Pib
        \\stage Find it.
        \\stage Bring it back.
        \\dialog merchant
        \\line root
        \\say Well met.
        \\ask Help? -> help
        \\need quest pib unstarted
        \\ask Here it is. -> thanks
        \\need flag carrying on
        \\ask Bye. -> end
        \\line help
        \\say Find my pib.
        \\act quest pib stage 1
        \\line thanks
        \\say Thank you.
        \\act flag carrying off
        \\act quest pib done
        \\dialog lost
        \\line root
        \\say Squeak.
        \\ask Take it. -> end
        \\gets flag carrying on
        \\gets quest pib stage 2
        \\npc 0 by chest merchant Merchant
        \\npc 0 far lost Baby pib
        \\shows stage pib < 2
        \\looks pib
        \\npc 0 by chest - Baby pib
        \\shows quest pib done
    );
    defer std.testing.allocator.destroy(w);
    const chest = P{ .x = 10, .y = 6 };
    w.node[0].plan.bespoke.tile[grid.Level.idx(chest)] = .chest;
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, SEED);
    try std.testing.expectEqual(@as(?usize, 0), g.sim.lv.npcAt(.{ .x = 9, .y = 7 }));
    const far = g.sim.plot.spots[1] orelse return error.NoPlace;
    try std.testing.expectEqual(@as(?usize, 1), g.sim.lv.npcAt(far));
    try std.testing.expect(mathx.dist(far, .{ .x = 2, .y = 2 }) >= 15);
    try std.testing.expectEqual(@as(?P, null), g.sim.plot.spots[2]);
    speak(g, 0);
    press(g, menu.CONFIRM);
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(trigger.Progress{ .state = .active, .stage = 1 }, g.sim.plot.quests[0]);
    try std.testing.expectEqualStrings("New quest: The Stolen Pib.", g.sim.log.line(0).?);
    speak(g, 1);
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(?usize, null), g.sim.lv.npcAt(far));
    try std.testing.expectEqual(@as(u8, 2), g.sim.plot.quests[0].stage);
    speak(g, 0);
    press(g, menu.CONFIRM);
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(script.QuestState.done, g.sim.plot.quests[0].state);
    const home = g.sim.plot.spots[2] orelse return error.NoPlace;
    try std.testing.expectEqual(@as(?usize, 2), g.sim.lv.npcAt(home));
    try std.testing.expectEqual(@as(i32, 1), mathx.dist(home, chest));
    game.update(g, 0);
    const log = game.character.questEntries(g, &g.journal);
    try std.testing.expect(log.len == 1 and log[0].done);
    g.st = .{ .device = .keys, .character_page = .quests };
    game.update(g, 0);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    try std.testing.expect(game.character.bookView(g, &g.nearby).quests.entries[0].done);
}

test "an NPC's found spot keeps off the node's painted foes and what lies on the ground" {
    const w = try testWorld(
        \\npc 0 far - Hermit
    );
    defer std.testing.allocator.destroy(w);
    var lv: grid.Level = undefined;
    var stood: script.Stood = @splat(null);
    w.node[0].sketch(&lv);
    w.stampNpcs(0, &lv, &stood, atlas.EVERY_NPC);
    const first = stood[0] orelse return error.NoPlace;
    try std.testing.expect(w.node[0].plan.bespoke.addFoe(.{ .kind = .rat, .at = first }));
    stood = @splat(null);
    w.node[0].sketch(&lv);
    w.stampNpcs(0, &lv, &stood, atlas.EVERY_NPC);
    const second = stood[0] orelse return error.NoPlace;
    try std.testing.expect(!second.eq(first));
    const Lying = struct {
        cell: P,
        pub fn shows(_: @This(), _: usize) bool {
            return true;
        }
        pub fn lying(self: @This()) grid.CellSet {
            var cells = grid.CellSet.initEmpty();
            cells.set(grid.Level.idx(self.cell));
            return cells;
        }
    };
    stood = @splat(null);
    w.node[0].sketch(&lv);
    w.stampNpcs(0, &lv, &stood, Lying{ .cell = second });
    const third = stood[0] orelse return error.NoPlace;
    try std.testing.expect(!third.eq(first) and !third.eq(second));
}

test "an NPC's found spot keeps off a painted NPC listed after it" {
    const alone = try testWorld(
        \\npc 0 far - Hermit
    );
    defer std.testing.allocator.destroy(alone);
    var lv: grid.Level = undefined;
    var stood: script.Stood = @splat(null);
    alone.node[0].sketch(&lv);
    alone.stampNpcs(0, &lv, &stood, atlas.EVERY_NPC);
    const far = stood[0] orelse return error.NoPlace;
    var text: [64]u8 = undefined;
    const w = try testWorld(try std.fmt.bufPrint(&text, "npc 0 far - Hermit\nnpc 0 {d} {d} - Painted", .{ far.x, far.y }));
    defer std.testing.allocator.destroy(w);
    stood = @splat(null);
    w.node[0].sketch(&lv);
    w.stampNpcs(0, &lv, &stood, atlas.EVERY_NPC);
    const hermit = stood[0] orelse return error.NoPlace;
    try std.testing.expect(!hermit.eq(far));
    try std.testing.expectEqual(@as(?usize, 1), lv.npcAt(far));
    try std.testing.expectEqual(@as(?usize, 0), lv.npcAt(hermit));
}

const MERCHANT =
    \\dialog pedlar
    \\line root
    \\say Salt, rope, steel.
    \\ask Show me your wares. -> end
    \\gets trade
    \\ask What else? -> more
    \\gets trade
    \\ask Goodbye. -> end
    \\line more
    \\say Nothing else.
    \\npc 0 6 5 pedlar Pedlar
;

test "a choice that trades opens the merchant's wares without a turn; buying spends gold and closing returns to play" {
    const w = try testWorld(MERCHANT);
    defer std.testing.allocator.destroy(w);
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, SEED);
    game.heroStep(g, .e, 0);
    const turns = g.sim.plot.turns;
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(book.Page.trade, g.character.page);
    try std.testing.expect(g.sim.plot.talk == null and g.sim.plot.trading == null);
    const shelf = &g.sim.plot.wares[0].?;
    const k = shelf.at(0).?.supply;
    const stocked = shelf.supplies.get(k);
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(@as(u8, 0), g.sim.inventory.stacks.get(k));
    try std.testing.expectEqualStrings(trade.NOT_ENOUGH_GOLD, g.character.message.text());
    g.sim.gold = 100;
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(@as(u8, 1), g.sim.inventory.stacks.get(k));
    try std.testing.expectEqual(stocked - 1, shelf.supplies.get(k));
    try std.testing.expectEqual(100 - trade.supplyPrice(k), g.sim.gold);
    try std.testing.expectEqual(g.sim.gold, g.pic.gold_shown);
    press(g, menu.CHANGE);
    try std.testing.expect(g.character.selling);
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(@as(u8, 0), g.sim.inventory.stacks.get(k));
    try std.testing.expectEqual(100 - trade.supplyPrice(k) + trade.offered(trade.supplyPrice(k)), g.sim.gold);
    press(g, menu.BACK);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(turns, g.sim.plot.turns);
    game.heroStep(g, .e, 0);
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(stocked - 1, g.sim.plot.wares[0].?.supplies.get(k));
}

test "a trade taken on the way to another line hands back to the conversation" {
    const w = try testWorld(MERCHANT);
    defer std.testing.allocator.destroy(w);
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.beginMapAt(g, w, w.start, SEED);
    game.heroStep(g, .e, 0);
    g.st = .{ .device = .keys, .walk = .s };
    game.update(g, 0);
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(book.Page.trade, g.character.page);
    try std.testing.expectEqual(@as(u8, 1), g.sim.plot.talk.?.line);
    press(g, menu.BACK);
    try std.testing.expectEqual(game.Mode.talk, std.meta.activeTag(g.mode));
    press(g, menu.CONFIRM);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
}

test "a trigger may not trade, and a conversation a trigger opened has no one to trade with" {
    var rt = trigger.Runtime{};
    const s = try script.testScript();
    defer std.testing.allocator.destroy(s);
    try script_text.readAlone(MERCHANT, s, 1);
    var l = @import("../play/log.zig").Log{};
    try std.testing.expect(rt.open(s, 0, null, &l));
    rt.pick(s, 0, .{}, &l);
    try std.testing.expectEqual(@as(?u8, null), rt.takeTrading());
    try std.testing.expect(std.meta.isError(script_text.readAlone("trigger t 0 once live\nwhen always\ndo trade\n", s, 1)));
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
    game.beginMapAt(g, w, w.start, SEED);
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
