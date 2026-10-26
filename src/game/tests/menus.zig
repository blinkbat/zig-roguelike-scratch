const std = @import("std");
const progress = @import("../../play/progress.zig");
const mathx = @import("../../core/mathx.zig");
const input = @import("../../core/input.zig");
const grid = @import("../../map/grid.zig");
const atlas = @import("../../map/atlas.zig");
const spar = @import("../../map/spar.zig");
const menu = @import("../../ui/menu.zig");
const hud = @import("../../ui/hud.zig");
const book = @import("../../ui/book.zig");
const actor = @import("../../play/actor.zig");
const bleeding = @import("../../play/bleeding.zig");
const skillbar = @import("../../play/skillbar.zig");
const raster = @import("../../gfx/raster.zig");
const overlay = @import("../overlay.zig");
const character = @import("../character.zig");
const harness = @import("../harness.zig");
const game = @import("../../game.zig");
const skills = @import("../skills.zig");
const P = mathx.P;
const CONFIRM = menu.CONFIRM;
const BACK = menu.BACK;
const CHANGE = menu.CHANGE;
const PAUSE = menu.PAUSE;
const HERO = actor.HERO;

test "a way held through closing inspect, a reticle or pause walks nobody until let go or turned" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const dt = harness.TEST_DT;
    const Case = struct { mode: game.Mode, close: input.Button };
    const cases = [_]Case{
        .{ .mode = .inspect, .close = skillbar.INSPECT },
        .{ .mode = .aim, .close = menu.BACK },
        .{ .mode = .pause, .close = menu.BACK },
    };
    for (cases) |case| {
        harness.arena(g, .{ .x = 20, .y = 32 }, &.{});
        g.st = .{};
        const start = g.sim.heroActor().?.at;
        g.mark = start;
        if (case.mode == .aim) skills.aiming(g, .a, .juke);
        g.mode = case.mode;
        harness.walkFor(g, 0.6, .e);
        g.st.pressed.insert(case.close);
        game.update(g, dt);
        g.st.pressed = .initEmpty();
        try std.testing.expectEqual(game.Mode.play, g.mode);
        harness.walkFor(g, 1, .e);
        try std.testing.expect(g.sim.heroActor().?.at.eq(start));
        harness.walkFrame(g, dt, null);
        for (0..30) |_| {
            harness.walkFrame(g, dt, .e);
        }
        try std.testing.expect(!g.sim.heroActor().?.at.eq(start));
    }
    std.debug.print("held walk: {d} screens closed with the way held, none walked till it was let go\n", .{cases.len});
}

test "a way held from play into pause or inspect moves nothing there until let go or turned" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const dt = harness.TEST_DT;
    const Case = struct { open: input.Button, way: mathx.Dir };
    for ([_]Case{ .{ .open = PAUSE, .way = .s }, .{ .open = skillbar.INSPECT, .way = .e } }) |case| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        g.st = .{};
        for (0..10) |_| harness.walkFrame(g, dt, case.way);
        harness.pressWalking(g, case.open, case.way);
        try std.testing.expect(g.mode != .play);
        const menu_at = g.pause_menu.at;
        const spot = g.inspecting;
        harness.walkFor(g, 1, case.way);
        try std.testing.expectEqual(menu_at, g.pause_menu.at);
        try std.testing.expectEqual(spot, g.inspecting);
        harness.walkFrame(g, dt, null);
        for (0..30) |_| harness.walkFrame(g, dt, case.way);
        try std.testing.expect(g.pause_menu.at != menu_at or !std.meta.eql(spot, g.inspecting));
        g.mode = .play;
    }
}

test "a way held into or out of a Debug submenu moves neither cursor until let go" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.st = .{};
    g.mode = .pause;
    game.debugging.select(g, .effects);
    for (0..10) |_| harness.walkFrame(g, harness.TEST_DT, .s);
    harness.pressWalking(g, menu.CONFIRM, .s);
    try std.testing.expectEqual(game.debugging.Page.effects, g.debug.page);
    harness.walkFor(g, 1, .s);
    try std.testing.expectEqual(@as(usize, 0), g.pause_menu.at);
    harness.pressWalking(g, menu.BACK, .s);
    try std.testing.expectEqual(game.debugging.Page.main, g.debug.page);
    const parent = g.pause_menu.at;
    harness.walkFor(g, 1, .s);
    try std.testing.expectEqual(parent, g.pause_menu.at);
}

test "a way held into or out of Character moves nothing until let go" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    for (0..10) |_| harness.walkFrame(g, harness.TEST_DT, .s);
    harness.pressWalking(g, menu.CHARACTER, .s);
    const cursor = g.character.cursor;
    harness.walkFor(g, 1, .s);
    try std.testing.expectEqual(cursor, g.character.cursor);
    harness.pressWalking(g, menu.BACK, .s);
    const at = g.sim.heroActor().?.at;
    harness.walkFor(g, 1, .s);
    try std.testing.expectEqual(at, g.sim.heroActor().?.at);
    std.debug.print("held walk: direct Character entry and exit suppress carried movement\n", .{});
}

test "a way held into or out of the skill picker moves neither cursor until let go" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.st = .{};
    character.openCharacter(g);
    character.characterCommand(g, .{ .bindings = .shoot });
    g.binds.assigning = null;
    for (0..10) |_| harness.walkFrame(g, harness.TEST_DT, .e);
    harness.pressWalking(g, CHANGE, .e);
    const picked = g.binds.menu.pick;
    const slot = g.binds.slot();
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(picked, g.binds.menu.pick);
    harness.pressWalking(g, menu.BACK, .e);
    try std.testing.expect(g.binds.menu == .browse);
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(slot, g.binds.slot());
    std.debug.print("held walk: the skill picker and the slot it returns to stayed put with the way held\n", .{});
}

test "the dead archer's floor restarts only once the death is shown" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.bittenToDeath(g);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    g.st = .{};
    g.st.pressed.insert(CONFIRM);
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    _ = harness.framesUntil(g, 0, harness.deathDrawn);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, g.mode);
}

test "the hud's tooltip stays up until the lethal bite is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.bittenToDeath(g);
    try std.testing.expect(g.mode == .dead and !game.deathShown(g));
    var buf: [overlay.SPOTS_MAX]overlay.Part = undefined;
    const spot = overlay.spotsOf(g, &buf)[0];
    g.st.pointer = raster.middleAt(spot.box);
    try std.testing.expectEqual(spot.spot, overlay.hovered(g).?.spot);
    const t = harness.framesUntil(g, 0, harness.deathDrawn);
    g.st.pointer = raster.middleAt(spot.box);
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    std.debug.print("dying: tooltip held {d:.3} s until the death is drawn\n", .{t});
}

test "Character stays drawn over a lethal item turn until the bite is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    g.sim.heroActor().?.hp = 1;
    character.openCharacter(g);
    var turns: usize = 0;
    while (g.mode != .dead and turns < harness.TRIES) : (turns += 1) {
        try std.testing.expect(g.sim.inventory.add(.{ .kind = .ring }));
        character.characterCommand(g, .{ .drop = g.sim.inventory.n - 1 });
        if (g.mode != .dead) harness.drawnOut(g);
    }
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.pause, game.modeShown(g));
    const t = harness.framesUntil(g, 0, harness.deathDrawn);
    try std.testing.expectEqual(game.Mode.dead, game.modeShown(g));
    std.debug.print("dying in Character: book held {d:.3} s until the death is drawn\n", .{t});
}

test "the Nearby list keeps its entries over a lethal pickup until the bite is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at: P = .{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    g.sim.heroActor().?.hp = 1;
    var turns: usize = 0;
    while (g.mode != .dead and turns < harness.TRIES) : (turns += 1) {
        for (0..2) |_| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
        if (g.mode != .pause) try std.testing.expect(character.openNearby(g));
        character.characterCommand(g, .{ .pickup = 0 });
        if (g.mode != .dead) harness.drawnOut(g);
    }
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.pause, game.modeShown(g));
    var buf: game.NearbyBuf = undefined;
    const shown = character.nearbyOf(g, &buf).len;
    try std.testing.expect(shown > 0);
    std.debug.print("dying in Nearby: {d} entries still listed while the bite is drawn\n", .{shown});
}

test "the ring slid under the cursor after an equip starts on the left ring again" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    for (0..2) |_| try std.testing.expect(g.sim.inventory.add(.{ .kind = .ring }));
    character.openCharacter(g);
    g.character.choose(.inventory);
    g.character.destination_index = 1;
    character.characterCommand(g, .{ .equip = .{ .index = 0, .slot = .right_ring } });
    try std.testing.expect(g.sim.inventory.gear.slots.get(.right_ring) != null);
    try std.testing.expectEqual(@as(usize, 0), g.character.destination_index);
}

test "Menu, B or X leaves the death screen as A does, and none of them pauses it" {
    for (game.DISMISS) |b| {
        const g = try game.boot(std.testing.allocator);
        defer game.shut(std.testing.allocator, g);
        harness.bittenToDeath(g);
        _ = harness.framesUntil(g, 0, harness.deathDrawn);
        harness.press(g, b);
        try std.testing.expectEqual(game.Mode.play, g.mode);
    }
}

test "the pause menu spends no turn, and its way out leads back to where the game was started from" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    harness.wakeFoes(g);
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    for (std.enums.values(game.Back)) |back| {
        g.back = back;
        harness.pickPause(g, .back);
        try std.testing.expectEqual(@as(?game.Exit, .back), g.exit);
        try std.testing.expectEqual(game.Mode.play, g.mode);
        g.exit = null;
    }
    try std.testing.expectEqual(P{ .x = 26, .y = 20 }, g.sim.pool.get(2).?.at);
}

test "Character and Game have separate shortcuts and never spend a turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const clock = g.sim.clock;
    const hp = g.sim.heroActor().?.hp;
    harness.press(g, menu.CHARACTER);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    g.character.choose(.inventory);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
    harness.press(g, menu.CHARACTER);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    harness.press(g, menu.CHARACTER);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    try std.testing.expectEqual(book.Page.inventory, g.character.page);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(clock, g.sim.clock);
    std.debug.print("Character: direct toggle, retained page, one-step back; Game: separate menu; zero turns\n", .{});
}

test "Character page shortcuts open switch and close without acting or carrying movement" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const at = g.sim.heroActor().?.at;
    const clock = g.sim.clock;
    const mana = g.sim.mana;
    var checked: usize = 0;
    for ([_]game.Mode{ .play, .aim, .inspect, .bind, .pause }) |mode| {
        g.mode = mode;
        g.pause_page = .main;
        for (std.enums.values(input.CharacterPage)) |page| {
            g.st = .{ .device = .keys, .character_page = page, .walk = .s };
            game.update(g, 0);
            try std.testing.expectEqual(game.Mode.pause, g.mode);
            try std.testing.expectEqual(game.PausePage.character, g.pause_page);
            try std.testing.expectEqual(book.Page.of(page), g.character.page);
            try std.testing.expect(g.st.walk == null and g.pending == null);
            if (page == .passives) try std.testing.expectEqual(progress.start(g.sim.class), g.character.cursor);
            try std.testing.expectEqual(at, g.sim.heroActor().?.at);
            checked += 1;
        }
        g.st = .{ .device = .keys, .character_page = .skills };
        game.update(g, 0);
        try std.testing.expectEqual(game.Mode.play, g.mode);
    }
    g.mode = .dead;
    g.st = .{ .character_page = .equipment };
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(mana, g.sim.mana);
    std.debug.print("Character shortcuts: {d} page openings, 5 toggles, death guarded; no turns or mana spent\n", .{checked});
}

test "an arena restart restores its selected opponent and hero" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(map);
    spar.author(map, .bloat);
    game.beginMap(g, map);
    _ = g.sim.pool.damage(&g.sim.lv, 2, 100);
    _ = g.sim.pool.damage(&g.sim.lv, g.sim.hero, 3);
    g.sim.mana = 0;
    game.restart(g);
    try std.testing.expectEqual(@as(usize, 2), g.sim.pool.n);
    try std.testing.expectEqual(actor.Kind.bloat, g.sim.pool.items[1].kind);
    try std.testing.expect(g.sim.pool.items[1].alive);
    try std.testing.expectEqual(actor.row(HERO).hp, g.sim.heroActor().?.hp);
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    try std.testing.expectEqual(spar.HERO, g.sim.heroActor().?.at);
    std.debug.print("arena retry: bloat and hero restored at their starting positions with full resources\n", .{});
}

test "Debug graphics toggles are independent and spend no simulation" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
    const before = g.sim.lv;
    const clock = g.sim.clock;
    const rng = g.sim.rng;
    const hp = g.sim.heroActor().?.hp;
    harness.openDebug(g);
    var toggles: usize = 0;
    inline for (game.debugging.SWITCHES) |T| {
        const group = game.debugging.switches(g, T);
        inline for (std.meta.fields(T)) |f| {
            game.debugging.select(g, @field(game.debugging.Row, f.name));
            for ([_]bool{ false, true }) |on| {
                harness.press(g, CONFIRM);
                inline for (std.meta.fields(T)) |other| {
                    const expected = if (comptime std.mem.eql(u8, f.name, other.name)) on else true;
                    try std.testing.expectEqual(expected, @field(group, other.name));
                }
                try std.testing.expectEqualSlices(bool, &before.seen, &g.sim.lv.seen);
                try std.testing.expectEqualSlices(bool, &before.lit, &g.sim.lv.lit);
                try std.testing.expectEqualSlices(grid.Tile, &before.tile, &g.sim.lv.tile);
                try std.testing.expectEqual(clock, g.sim.clock);
                try std.testing.expectEqual(rng, g.sim.rng);
                try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
                try std.testing.expectEqual(game.Mode.pause, g.mode);
                toggles += 1;
            }
        }
    }
    std.debug.print("Debug graphics: {d} independent toggles preserve terrain, visibility, clock, RNG and life\n", .{toggles});
}

test "Debug reveal toggles map terrain without spending turns or changing explored cells" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const far = P{ .x = 60, .y = 40 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{far});
    const seen = g.sim.lv.seen;
    const lit = g.sim.lv.lit;
    const clock = g.sim.clock;
    const rng = g.sim.rng;
    try std.testing.expect(!character.terrainSeen(g, far));
    harness.openDebug(g);
    try std.testing.expectEqual(game.PausePage.debug, g.pause_page);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.debugging.Page.gameplay, g.debug.page);
    harness.nudge(g, .s);
    for ([_]bool{ true, false }) |enabled| {
        harness.press(g, CONFIRM);
        try std.testing.expectEqual(enabled, g.light.reveal_map);
        try std.testing.expectEqual(enabled, character.terrainSeen(g, far));
        try std.testing.expectEqual(@as(f32, if (enabled) 1 else 0), g.light.memory[grid.Level.idx(far)]);
        try std.testing.expectEqualSlices(bool, &seen, &g.sim.lv.seen);
        try std.testing.expectEqualSlices(bool, &lit, &g.sim.lv.lit);
        try std.testing.expectEqual(clock, g.sim.clock);
        try std.testing.expectEqual(rng, g.sim.rng);
        try std.testing.expect(g.pic.drawnAt(&g.sim, actor.Pool.slot(2)) == null);
    }
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.debug, g.pause_page);
    try std.testing.expectEqual(game.debugging.Page.main, g.debug.page);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    std.debug.print("Debug reveal: on/off restores fog, all {d} exploration cells unchanged; back exits one menu at a time\n", .{grid.CELLS});
}

test "Debug restart begins the map anew and clears visited nodes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(map);
    map.* = .{};
    _ = map.add(.{ .procgen = .{} });
    _ = map.add(.{ .procgen = .{} });
    game.beginMapAt(g, map, .{ .node = 1, .at = grid.MIDDLE }, 12);
    g.sim.visited.set(1);
    g.sim.gold = 99;
    g.sim.heroActor().?.hp = 1;
    harness.openDebug(g);
    try std.testing.expectEqual(game.PausePage.debug, g.pause_page);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.debugging.Page.gameplay, g.debug.page);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(map.start.node, g.sim.node);
    try std.testing.expectEqual(@as(usize, 0), g.sim.visited.count());
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try std.testing.expectEqual(g.sim.heroRow().hp, g.sim.heroActor().?.hp);
    try std.testing.expect(g.sim.seed != 12);
    std.debug.print("Debug restart: returns to map start, rerolls seed, restores hero and clears visited nodes and gold\n", .{});
}

test "inspect walks the orbs, the slots and the statuses, spends no turn, and backs out by any way back or its own button" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    g.sim.heroActor().?.bleed.turns = bleeding.TURNS;
    g.pic.catchUp(&g.sim);
    const clock = g.sim.clock;
    harness.press(g, skillbar.INSPECT);
    try std.testing.expectEqual(game.Mode.inspect, g.mode);
    g.inspecting = .life;
    var walked: usize = 0;
    while (g.inspecting != .mana and walked < 20) : (walked += 1) harness.nudge(g, .e);
    try std.testing.expectEqual(skillbar.SLOTS.len + 1, walked);
    harness.nudge(g, .e);
    try std.testing.expect(g.inspecting == .actor);
    g.inspecting = .{ .slot = 3 };
    harness.nudge(g, .n);
    try std.testing.expectEqual(game.Spot{ .status = .bleeding }, g.inspecting);
    harness.nudge(g, .s);
    try std.testing.expect(g.inspecting == .slot);
    for ([_]input.Button{ menu.BACK, menu.PAUSE, skillbar.INSPECT }) |out| {
        harness.press(g, out);
        try std.testing.expectEqual(game.Mode.play, g.mode);
        harness.press(g, skillbar.INSPECT);
        try std.testing.expectEqual(game.Mode.inspect, g.mode);
    }
    harness.press(g, skillbar.INSPECT);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expect(std.meta.eql(clock, g.sim.clock));
    std.debug.print("inspect: life to mana in {d} steps across {d} slots, then a visible character; status navigation, 3 ways out and no turn spent\n", .{ walked, skillbar.SLOTS.len });
}

test "the mouse over an orb, a slot or a status shows its tooltip while playing, and nothing off the hud" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    g.sim.heroActor().?.bleed.turns = bleeding.TURNS;
    g.pic.catchUp(&g.sim);
    var buf: [overlay.SPOTS_MAX]overlay.Part = undefined;
    const spots = overlay.spotsOf(g, &buf);
    for (spots) |s| {
        g.st.pointer = raster.middleAt(s.box);
        try std.testing.expectEqual(s.spot, overlay.hovered(g).?.spot);
    }
    const orb = hud.orbBox(overlay.hudLayout(g).life);
    g.st.pointer = .{ .x = @intFromFloat(orb.x + 1), .y = @intFromFloat(orb.y + 1) };
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    g.st.pointer = .{ .x = 0, .y = 0 };
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    g.st.pointer = null;
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    g.st.pointer = raster.middleAt(spots[1].box);
    g.mode = .pause;
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    std.debug.print("hover: {d} hud parts each found at their centre; the orb's corner, the screen's, no mouse and pause show none\n", .{spots.len});
}
