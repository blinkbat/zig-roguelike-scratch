const std = @import("std");
const progress = @import("../../play/progress.zig");
const passives = @import("../../play/passives.zig");
const mathx = @import("../../core/mathx.zig");
const input = @import("../../core/input.zig");
const grid = @import("../../map/grid.zig");
const atlas = @import("../../map/atlas.zig");
const spar = @import("../../map/spar.zig");
const playground = @import("../../map/playground.zig");
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
        switch (case.mode) {
            .aim => skills.aiming(g, .a, .juke),
            .inspect => g.mode = .inspect,
            .pause => g.mode = .pause,
            else => unreachable,
        }
        harness.walkFor(g, 0.6, .e);
        g.st.pressed.insert(case.close);
        game.update(g, dt);
        g.st.pressed = .initEmpty();
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
        harness.walkFor(g, 1, .e);
        try std.testing.expect(g.sim.heroActor().?.at.eq(start));
        harness.walkFrame(g, dt, null);
        for (0..30) |_| {
            harness.walkFrame(g, dt, .e);
        }
        try std.testing.expect(!g.sim.heroActor().?.at.eq(start));
    }
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
}

test "a way held between a Character page and its tabs turns no page and moves no cursor until let go" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.st = .{};
    character.openCharacter(g);
    try std.testing.expect(!g.character.tabbing);
    harness.pressWalking(g, BACK, null);
    try std.testing.expect(g.character.tabbing);
    for (0..10) |_| harness.walkFrame(g, harness.TEST_DT, .s);
    harness.pressWalking(g, CONFIRM, .s);
    try std.testing.expect(!g.character.tabbing);
    const cursor = g.character.cursor;
    harness.walkFor(g, 1, .s);
    try std.testing.expectEqual(cursor, g.character.cursor);
    harness.walkFrame(g, harness.TEST_DT, null);
    for (0..10) |_| harness.walkFrame(g, harness.TEST_DT, .e);
    const page = g.character.page;
    harness.pressWalking(g, BACK, .e);
    try std.testing.expect(g.character.tabbing);
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(page, g.character.page);
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
}

test "the dead archer's floor restarts only once the death is shown" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.bittenToDeath(g);
    try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
    g.st = .{};
    g.st.pressed.insert(CONFIRM);
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
    _ = harness.framesUntil(g, 0, harness.deathDrawn);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
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
    _ = harness.framesUntil(g, 0, harness.deathDrawn);
    g.st.pointer = raster.middleAt(spot.box);
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
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
    try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.pause, game.modeShown(g));
    _ = harness.framesUntil(g, 0, harness.deathDrawn);
    try std.testing.expectEqual(game.Mode.dead, game.modeShown(g));
}

test "the Nearby list keeps its entries over a lethal pickup until the bite is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at: P = .{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    g.sim.heroActor().?.hp = 1;
    const piles = [_]P{ .{ .x = 19, .y = 20 }, .{ .x = 20, .y = 21 } };
    var turns: usize = 0;
    while (g.mode != .dead and turns < harness.TRIES) : (turns += 1) {
        for (piles) |p| try std.testing.expect(g.sim.ground.gold(p, 5));
        if (g.mode != .pause) try std.testing.expect(character.openNearby(g));
        character.characterCommand(g, .{ .take_gold = piles[0] });
        if (g.mode != .dead) harness.drawnOut(g);
    }
    try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.pause, game.modeShown(g));
    var buf: game.NearbyBuf = undefined;
    const shown = character.nearbyOf(g, &buf).len;
    try std.testing.expect(shown > 0);
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
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    }
}

test "the pause menu spends no turn, and its way out leads back to where the game was started from" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    harness.wakeFoes(g);
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    for (std.enums.values(game.Back)) |back| {
        g.back = back;
        harness.pickPause(g, .back);
        try std.testing.expectEqual(@as(?game.Exit, .back), g.exit);
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
        g.exit = null;
    }
    try std.testing.expectEqual(P{ .x = 26, .y = 20 }, g.sim.pool.get(harness.foeId(0)).?.at);
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
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    harness.press(g, menu.CHARACTER);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    try std.testing.expectEqual(book.Page.inventory, g.character.page);
    harness.press(g, BACK);
    try std.testing.expect(g.character.tabbing);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(clock, g.sim.clock);
}

test "Character page shortcuts open switch and close without acting or carrying movement" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const at = g.sim.heroActor().?.at;
    const clock = g.sim.clock;
    const mana = g.sim.mana;
    inline for (.{ game.Mode.play, .aim, .inspect, .bind, .pause }) |mode| {
        if (mode == .aim) skills.aiming(g, .x, .shoot) else g.mode = mode;
        g.pause_page = .main;
        for (std.enums.values(input.CharacterPage)) |page| {
            g.st = .{ .device = .keys, .character_page = page, .walk = .s };
            game.update(g, 0);
            try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
            try std.testing.expectEqual(game.PausePage.character, g.pause_page);
            try std.testing.expectEqual(book.Page.of(page), g.character.page);
            try std.testing.expect(g.st.walk == null and g.pending == null);
            if (page == .passives) try std.testing.expectEqual(passives.start(g.sim.class), g.character.cursor);
            try std.testing.expectEqual(at, g.sim.heroActor().?.at);
        }
        const pages = comptime std.enums.values(input.CharacterPage);
        g.st = .{ .device = .keys, .character_page = pages[pages.len - 1] };
        game.update(g, 0);
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    }
    g.mode = .dead;
    g.st = .{ .character_page = .equipment };
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(mana, g.sim.mana);
}

test "an arena restart restores its selected opponent and hero" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try atlas.testAtlas();
    defer std.testing.allocator.destroy(map);
    spar.author(map, .bloat);
    game.beginMap(g, map);
    _ = g.sim.pool.damage(&g.sim.lv, harness.foeId(0), 100);
    _ = g.sim.pool.damage(&g.sim.lv, g.sim.hero, 3);
    g.sim.mana = 0;
    game.restart(g);
    try std.testing.expectEqual(@as(usize, 2), g.sim.pool.n);
    try std.testing.expectEqual(actor.Kind.bloat, g.sim.pool.items[harness.foeSlot(0)].kind);
    try std.testing.expect(g.sim.pool.items[harness.foeSlot(0)].alive);
    try std.testing.expectEqual(actor.row(HERO).hp, g.sim.heroActor().?.hp);
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    try std.testing.expectEqual(spar.HERO, g.sim.heroActor().?.at);
}

test "the playground's wizard casts freely and cannot die, and a restart lays its terrain afresh" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try atlas.testAtlas();
    defer std.testing.allocator.destroy(map);
    game.enterPlayground(g, map);
    game.beginMap(g, map);
    for (progress.skills(playground.CLASS)) |s| try std.testing.expect(g.sim.growth.unlocked(s.act) and g.bar.slotOf(s.act) != null);
    const clock = g.sim.clock;
    for (0..3) |_| {
        harness.aimAt(g, .fireball, playground.HERO.add(.{ .x = 0, .y = 4 }));
        harness.drawnOut(g);
        try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
        try std.testing.expectEqual(@as(u8, 0), g.sim.cooldown.get(.fireball));
    }
    try std.testing.expect(!std.meta.eql(clock, g.sim.clock));
    _ = game.hurt(g, .{ .value = g.sim.hero }, 1000);
    try std.testing.expect(g.sim.heroActor().?.alive);
    const lv = try std.testing.allocator.create(grid.Level);
    defer std.testing.allocator.destroy(lv);
    map.node[0].stamp(lv, 0);
    const at = grid.Level.idx(playground.boxOf(0).centre());
    g.sim.lv.tile[at] = .dirt;
    g.sim.lv.flames[at] = 3;
    game.restart(g);
    try std.testing.expectEqualSlices(grid.Tile, &lv.tile, &g.sim.lv.tile);
    try std.testing.expectEqual(@as(u8, 0), g.sim.lv.flames[at]);
    try std.testing.expectEqual(playground.HERO, g.sim.heroActor().?.at);
    try std.testing.expectEqual(actor.Kind.wizard, g.sim.heroActor().?.kind);
    for (progress.skills(playground.CLASS)) |s| try std.testing.expect(g.sim.growth.unlocked(s.act));
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
                try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
                toggles += 1;
            }
        }
    }
}

test "Options sliders are independent and return through their parent without a turn" {
    const options = @import("../../ui/options.zig");
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const clock = g.sim.clock;
    const rng = g.sim.rng;
    character.openPause(g);
    g.pause_menu.at = game.rowAt(game.PauseRow.options);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.PausePage.options, g.pause_page);
    g.pause_menu.at = options.index(.main, .visuals);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.PausePage.visuals, g.pause_page);
    inline for (std.meta.fields(@TypeOf(g.cinema.lens.options))) |field| {
        g.pause_menu.at = options.index(.visuals, @field(options.Row, field.name));
        const defaults: @TypeOf(g.cinema.lens.options) = .{};
        for ([_]mathx.Dir{ .e, .w }) |direction| {
            harness.nudge(g, direction);
            inline for (std.meta.fields(@TypeOf(g.cinema.lens.options))) |other| {
                const adjustment: f32 = if (direction == .e and std.mem.eql(u8, field.name, other.name)) 0.05 else 0;
                try std.testing.expectApproxEqAbs(@field(defaults, other.name) + adjustment, @field(g.cinema.lens.options, other.name), 0.0001);
            }
        }
    }
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.options, g.pause_page);
    g.pause_menu.at = options.index(.main, .display);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.PausePage.display, g.pause_page);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.options, g.pause_page);
    g.pause_menu.at = options.index(.main, .debug);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.PausePage.debug, g.pause_page);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.options, g.pause_page);
    try std.testing.expectEqual(options.index(.main, .debug), g.pause_menu.at);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    try std.testing.expectEqual(game.rowAt(game.PauseRow.options), g.pause_menu.at);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(rng, g.sim.rng);
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
    try std.testing.expect(!game.scene.terrainSeen(g, far));
    harness.openDebug(g);
    try std.testing.expectEqual(game.PausePage.debug, g.pause_page);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.debugging.Page.gameplay, g.debug.page);
    harness.nudge(g, .s);
    for ([_]bool{ true, false }) |enabled| {
        harness.press(g, CONFIRM);
        try std.testing.expectEqual(enabled, g.light.reveal_map);
        try std.testing.expectEqual(enabled, game.scene.terrainSeen(g, far));
        try std.testing.expectEqual(@as(f32, if (enabled) 1 else 0), g.light.visibility.memory[grid.Level.idx(far)]);
        try std.testing.expectEqualSlices(bool, &seen, &g.sim.lv.seen);
        try std.testing.expectEqualSlices(bool, &lit, &g.sim.lv.lit);
        try std.testing.expectEqual(clock, g.sim.clock);
        try std.testing.expectEqual(rng, g.sim.rng);
        try std.testing.expect(g.pic.drawnAt(&g.sim, harness.foeSlot(0)) == null);
    }
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.debug, g.pause_page);
    try std.testing.expectEqual(game.debugging.Page.main, g.debug.page);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
}

test "Debug restart begins the map anew and clears visited nodes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try atlas.testAtlas();
    defer std.testing.allocator.destroy(map);
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
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(map.start.node, g.sim.node);
    try std.testing.expectEqual(@as(usize, 0), g.sim.visited.count());
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try std.testing.expectEqual(g.sim.heroRow().hp, g.sim.heroActor().?.hp);
    try std.testing.expect(g.sim.seed != 12);
}

test "inspect walks the orbs, the slots and the statuses, spends no turn, and backs out by any way back or its own button" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    g.sim.heroActor().?.bleed.turns = bleeding.TURNS;
    g.pic.catchUp(&g.sim);
    const clock = g.sim.clock;
    harness.press(g, skillbar.INSPECT);
    try std.testing.expectEqual(game.Mode.inspect, std.meta.activeTag(g.mode));
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
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
        harness.press(g, skillbar.INSPECT);
        try std.testing.expectEqual(game.Mode.inspect, std.meta.activeTag(g.mode));
    }
    harness.press(g, skillbar.INSPECT);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(std.meta.eql(clock, g.sim.clock));
}

test "status inspection explains overlapping tags without changing the simulation" {
    const keywords = @import("../../ui/keywords.zig");
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.sim.heroActor().?.chill.apply();
    g.pic.catchUp(&g.sim);
    const before = g.sim.heroActor().?.*;
    const clock = g.sim.clock;
    var title: [overlay.TIP_TITLE_MAX]u8 = undefined;
    var body: [overlay.TIP_BODY_MAX]u8 = undefined;
    const tip = overlay.tipOf(g, .{ .status = .chilled }, &title, &body).?;
    try std.testing.expect(std.mem.startsWith(u8, tip.body, @import("../../play/glacial.zig").STATUS));
    try std.testing.expect(std.mem.indexOf(u8, tip.body, "\nSlows, Elemental") != null);
    try std.testing.expect(std.mem.indexOf(u8, tip.body, "Tags:") == null);
    try std.testing.expect(std.mem.indexOf(u8, keywords.STATUS_TERMS[1].body, "\nStun, Chill, Pin, Maim.") != null);
    try std.testing.expect(std.mem.indexOf(u8, keywords.STATUS_TERMS[3].body, "\nBurn, Chill, Shock.") != null);
    const enfeebled = overlay.tipOf(g, .{ .status = .enfeebled }, &title, &body).?;
    try std.testing.expect(std.mem.endsWith(u8, enfeebled.body, "\nWounds"));
    const guarding = overlay.tipOf(g, .{ .status = .guarding }, &title, &body).?;
    try std.testing.expect(std.mem.indexOf(u8, guarding.body, "Tags:") == null);
    try std.testing.expectEqualDeep(before, g.sim.heroActor().?.*);
    try std.testing.expectEqualDeep(clock, g.sim.clock);
}

test "keyword inspection sits above character menus and HUD inspection without spending turns" {
    const keywords = @import("../../ui/keywords.zig");
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const clock = g.sim.clock;
    for ([_]game.Mode{ .pause, .inspect }) |mode| {
        g.mode = if (mode == .pause) .pause else .inspect;
        g.pause_page = .character;
        g.character.choose(.stats);
        g.character.advanced = true;
        g.inspecting = .{ .status = .chilled };
        g.keywords = .{ .screen = g.screen };
        g.keywords.register(keywords.STATUS_TERMS[0], raster.rect(100, 100, 60, 20));
        g.keywords.register(keywords.STATUS_TERMS[1], raster.rect(200, 100, 60, 20));
        harness.press(g, skillbar.INSPECT);
        try std.testing.expectEqual(@as(?usize, 0), g.keywords.focus);
        harness.nudge(g, .e);
        try std.testing.expectEqual(@as(?usize, 1), g.keywords.focus);
        harness.press(g, CONFIRM);
        try std.testing.expectEqual(@as(?usize, 1), g.keywords.focus);
        harness.press(g, BACK);
        try std.testing.expectEqual(@as(?usize, null), g.keywords.focus);
        try std.testing.expectEqual(mode, std.meta.activeTag(g.mode));
        try std.testing.expectEqual(book.Page.stats, g.character.page);
        try std.testing.expect(g.character.advanced);
        try std.testing.expectEqual(game.Spot{ .status = .chilled }, g.inspecting);
        try std.testing.expectEqualDeep(clock, g.sim.clock);
    }
}

test "inspect forgets the body it was on once the hero enters a node" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const foe = P{ .x = 30, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{foe});
    g.inspecting = .{ .actor = g.sim.lv.who(foe) };
    g.inspect_scroll = 2;
    game.reset(g, .{ .x = 20, .y = 20 });
    try std.testing.expectEqual(game.Spot{ .slot = 0 }, g.inspecting);
    try std.testing.expectEqual(@as(usize, 0), g.inspect_scroll);
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
}

test "actor inspection follows the perspective shown on screen" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    g.screen = game.SCREEN_720;
    g.cam = .{ .x = @floatFromInt(from.x * game.CELL - 1000), .y = @floatFromInt(from.y * game.CELL - 450) };
    const lens = &g.cinema.lens;
    lens.program = std.mem.zeroes(std.meta.Child(@TypeOf(lens.program)));
    lens.scene = std.mem.zeroes(std.meta.Child(@TypeOf(lens.scene)));
    defer {
        lens.program = null;
        lens.scene = null;
    }
    for ([_]f32{ 0, 0.5, 2 }) |strength| {
        lens.options.perspective = strength;
        const y = 480;
        const x: f32 = 1000 + game.CELL_F - 5;
        const scale = 1 + 0.10 * strength * (y + 0.5) / 720;
        g.st = .{ .device = .keys, .pointer = .{ .x = @intFromFloat(@floor((x + 0.5 - 640) * scale + 640)), .y = y }, .mouse_moved = true };
        g.mode = .play;
        const part = overlay.hovered(g).?;
        try std.testing.expectEqual(game.Spot{ .actor = g.sim.hero }, part.spot);
        try std.testing.expect(raster.holds(part.box, g.st.pointer.?));
        g.mode = .inspect;
        g.inspecting = .life;
        overlay.inspectStep(g);
        try std.testing.expectEqual(part.spot, g.inspecting);
    }
}
