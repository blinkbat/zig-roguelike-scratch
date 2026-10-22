const std = @import("std");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const menu = @import("../ui/menu.zig");
const book = @import("../ui/book.zig");
const actor = @import("../play/actor.zig");
const look = @import("../gfx/look.zig");
const scene = @import("scene.zig");
const game = @import("../game.zig");
const P = mathx.P;
const PAUSE = menu.PAUSE;

pub fn openPause(g: *game.Game) void {
    g.pause_menu = .{};
    g.pause_page = .main;
    g.mode = .pause;
    g.pending = null;
}

pub fn openInspect(g: *game.Game) void {
    g.mode = .inspect;
    g.pending = null;
}

/// A pad's View switches a screen over play to the game menu.
pub fn padToGame(g: *game.Game) bool {
    if (!g.st.device.pad() or !g.st.hit(PAUSE)) return false;
    openPause(g);
    return true;
}

pub fn openCharacter(g: *game.Game) void {
    g.character.open();
    g.pause_page = .character;
    g.mode = .pause;
    game.holdWalk(g);
}

pub fn dropShown(g: *const game.Game, drop: items.Drop) bool {
    return g.lv.isLit(drop.at) and dropLanded(g, drop);
}

/// Laid, or its foe's death drawn; seen or not.
pub fn dropLanded(g: *const game.Game, drop: items.Drop) bool {
    if (drop.source == grid.NO_ONE) return true;
    const i = actor.Pool.slot(drop.source);
    return g.pictured[i].down();
}

fn withinReach(from: P, p: P) bool {
    return mathx.dist(from, p) <= game.INTERACT_REACH;
}

pub fn nearbyOf(g: *game.Game, out: *game.NearbyBuf) []const book.Nearby {
    const hero = game.heroSlot(g) orelse return out[0..0];
    const at = g.pool.items[hero].at;
    var n: usize = 0;
    var listed = std.StaticBitSet(grid.CELLS).initEmpty();
    for (g.ground.drops[0..g.ground.n]) |drop| {
        if (!dropReached(g, at, drop)) continue;
        const cell = grid.Level.idx(drop.at);
        if (listed.isSet(cell)) continue;
        listed.set(cell);
        out[n] = .{ .kind = if (g.lv.at(drop.at) == .chest_open or g.lv.at(drop.at) == .chest) .chest else .bag, .at = drop.at };
        n += 1;
    }
    var cells = grid.Cells.around(at, game.INTERACT_REACH);
    while (cells.next()) |p| {
        const chest = chestReached(g, at, p) and !listed.isSet(grid.Level.idx(p));
        if (!chest and doorReached(g, at, p) == null) continue;
        out[n] = .{ .kind = if (chest) .chest else .door, .at = p };
        n += 1;
    }
    return out[0..n];
}

fn lootOf(g: *game.Game, out: *game.NearbyBuf, at: P) []const book.Nearby {
    const hero = game.heroSlot(g) orelse return out[0..0];
    var n: usize = 0;
    for (g.ground.drops[0..g.ground.n], 0..) |drop, i| {
        if (!drop.at.eq(at) or !dropReached(g, g.pool.items[hero].at, drop)) continue;
        out[n] = .{ .kind = .loot, .index = i, .at = at, .item = drop.item };
        n += 1;
    }
    return out[0..n];
}

/// What Interact can reach from `from`, as listed and as resolved alike.
fn dropReached(g: *const game.Game, from: P, drop: items.Drop) bool {
    return withinReach(from, drop.at) and dropShown(g, drop);
}

fn chestReached(g: *const game.Game, from: P, p: P) bool {
    return withinReach(from, p) and g.lv.isLit(p) and g.lv.at(p).opened() != null;
}

/// The hero's own door, or a clear one beside.
pub fn doorReached(g: *game.Game, from: P, p: P) ?atlas.Link {
    if (!withinReach(from, p) or !g.lv.isLit(p) or !g.lv.walkable(p)) return null;
    const link = game.leadsTo(g, p) orelse return null;
    return if (!p.eq(from) and bodyShownIn(g, p)) null else link;
}

fn bodyShownIn(g: *game.Game, p: P) bool {
    if (game.quiet(g)) return g.lv.taken(p);
    for (0..g.pool.n) |i| {
        if ((game.drawnCell(g, i) orelse continue).eq(p)) return true;
    }
    return scene.barrelShownAt(g, p);
}

pub fn anyNearby(g: *game.Game) bool {
    var nearby: game.NearbyBuf = undefined;
    return nearbyOf(g, &nearby).len > 0;
}

pub fn bookView(g: *game.Game, nearby: *game.NearbyBuf) book.View {
    const now = game.quiet(g);
    const growth = if (now) &g.growth else &g.growth_shown;
    return .{ .class = g.class, .name = g.name.text(), .inventory = &g.inventory, .growth = growth, .base = growth.attributes(g.class), .gold = if (now) g.gold else g.gold_shown, .nearby = if (g.character.page == .loot) lootOf(g, nearby, g.character.loot_at) else nearbyOf(g, nearby), .device = g.st.device, .chest = g.character.page == .loot and g.lv.at(g.character.loot_at) == .chest_open };
}

pub fn openNearby(g: *game.Game) bool {
    var buf: game.NearbyBuf = undefined;
    const nearby = nearbyOf(g, &buf);
    if (nearby.len == 0) return false;
    openCharacter(g);
    g.character.choose(.nearby);
    if (nearby.len == 1 and nearby[0].kind != .door) characterCommand(g, nearby[0].command());
    return true;
}

pub fn openLoot(g: *game.Game, at: P) void {
    if (!drawnFor(g)) return;
    if (g.travel != null) return notYet(g);
    const h = g.heroActor() orelse return;
    const chest = chestReached(g, h.at, at);
    if (chest) {
        if (!game.combat.openChest(g, at)) return;
    } else if (lootOf(g, &g.nearby, at).len == 0) return;
    game.combat.collectGold(g, at);
    game.turnToward(g, g.hero, at.x - h.at.x);
    openCharacter(g);
    g.character.choose(.loot);
    g.character.loot_at = at;
    if (chest) game.combat.endTurn(g);
}

fn itemFailed(g: *game.Game, err: items.Failure) void {
    g.character.message.say("{s}", .{items.caption(err)});
}

fn notYet(g: *game.Game) void {
    g.character.message.say("Not until the turn ends", .{});
}

pub fn characterCommand(g: *game.Game, command: book.Command) void {
    switch (command) {
        .close => g.mode = .play,
        .bindings => |act| {
            game.openBinds(g);
            if (g.growth.unlocked(act)) g.binds.assigning = act;
        },
        .passive => |i| {
            if (!drawnFor(g) or !g.growth.allocate(i)) return;
            g.log.push(.progress, "{s} allocated.", .{progress.NODES[i].name});
            game.syncStats(g);
            g.unsaved = true;
        },
        .skill => |act| {
            if (!drawnFor(g)) return;
            const unlocked = g.growth.unlocked(act);
            if (!g.growth.learn(g.class, act)) return;
            g.log.push(.progress, "{s}: rank {d}.", .{ act.name(), g.growth.ranks.get(act) });
            if (!unlocked) if (g.bar.firstEmpty()) |slot| g.bar.bind(slot, act);
            g.unsaved = true;
        },
        .open_loot => |at| openLoot(g, at),
        .equip, .unequip, .drop, .pickup, .take_all, .travel => itemCommand(g, command),
    }
}

/// Whether the turn is drawn, so a command acts; says so when not.
fn drawnFor(g: *game.Game) bool {
    if (!game.quiet(g)) {
        notYet(g);
        return false;
    }
    g.character.message.clear();
    return true;
}

/// Item commands spend the turn, and wait out door travel.
fn itemCommand(g: *game.Game, command: book.Command) void {
    if (!drawnFor(g)) return;
    if (g.travel != null) return notYet(g);
    const h = g.heroActor() orelse return;
    const base = g.growth.attributes(g.class);
    switch (command) {
        .close, .passive, .skill, .bindings, .open_loot => unreachable,
        .equip => |e| {
            g.inventory.equip(e.index, e.slot, base) catch |err| {
                itemFailed(g, err);
                return;
            };
            g.log.push(.loot, "Equipped {s}: {s}.", .{ g.inventory.gear.slots.get(e.slot).?.name(), e.slot.name() });
        },
        .unequip => |s| {
            g.inventory.unequip(s, base) catch |err| {
                itemFailed(g, err);
                return;
            };
            g.log.push(.loot, "Unequipped {s}.", .{s.name()});
        },
        .drop => |i| {
            if (i >= g.inventory.n) return;
            if (!game.combat.groundRoom(g)) return;
            const added = g.ground.add(.{ .item = g.inventory.bag[i], .at = h.at });
            std.debug.assert(added);
            g.log.push(.loot, "Dropped {s}.", .{g.inventory.remove(i).name()});
        },
        .pickup => |i| {
            if (i >= g.ground.n or !dropReached(g, h.at, g.ground.drops[i])) return;
            if (g.character.page == .loot and !g.ground.drops[i].at.eq(g.character.loot_at)) return;
            if (!g.ground.take(i, &g.inventory)) {
                itemFailed(g, error.Full);
                return;
            }
            g.log.push(.loot, "Picked up {s}.", .{g.inventory.bag[g.inventory.n - 1].name()});
        },
        .take_all => {
            if (g.character.page != .loot) return;
            var taken: usize = 0;
            var i: usize = 0;
            while (i < g.ground.n) {
                const drop = g.ground.drops[i];
                if (!drop.at.eq(g.character.loot_at) or !dropReached(g, h.at, drop)) {
                    i += 1;
                    continue;
                }
                if (!g.ground.take(i, &g.inventory)) {
                    itemFailed(g, error.Full);
                    break;
                }
                taken += 1;
                g.log.push(.loot, "Picked up {s}.", .{drop.item.name()});
            }
            if (taken == 0) return;
        },
        .travel => |p| {
            const link = doorReached(g, h.at, p) orelse return;
            const dx = p.x - h.at.x;
            if (p.eq(h.at)) g.travel = link else game.heroTo(g, p);
            game.turnToward(g, g.hero, dx);
        },
    }
    game.syncStats(g);
    g.character.destination_index = 0;
    if (command == .travel or (g.character.direct() and bookView(g, &g.nearby).nearby.len == 0)) g.mode = .play;
    game.holdWalk(g);
    game.combat.endTurn(g);
}

pub fn pauseStep(g: *game.Game) void {
    switch (g.pause_page) {
        .character => {
            if (padToGame(g)) return;
            const view = bookView(g, &g.nearby);
            if (g.character.direct() and view.nearby.len == 0) {
                g.mode = .play;
                return;
            }
            if (g.character.step(&g.st, g.screen, view)) |command| characterCommand(g, command);
        },
        .debug => game.debugging.step(g),
        .main => {
            if (menu.backed(&g.st)) {
                g.mode = .play;
                return;
            }
            const i = g.pause_menu.step(&g.st, game.PAUSE_ROWS.len) orelse return;
            switch (game.PAUSE_ROWS[i]) {
                .resume_ => g.mode = .play,
                .debug => {
                    g.pause_page = .debug;
                    g.debug.page = .main;
                    g.pause_menu = .{};
                },
                .back => {
                    g.mode = .play;
                    g.exit = .back;
                },
                .quit => {
                    g.mode = .play;
                    g.exit = .quit;
                },
            }
        },
    }
}

pub fn toggleReveal(g: *game.Game) void {
    g.light.reveal(&g.lv, !g.light.reveal_map);
    g.mini.stale = true;
}

pub fn terrainSeen(g: *const game.Game, p: P) bool {
    return g.light.remembers(&g.lv, p);
}

fn pauseLabel(g: *const game.Game, r: game.PauseRow) [:0]const u8 {
    return switch (r) {
        .resume_ => "Resume",
        .debug, .quit => menu.named(r),
        .back => switch (g.back) {
            .title => "Title",
            .editor => "Back to the editor",
        },
    };
}

pub fn veil(g: *const game.Game) void {
    rl.drawRectangle(0, 0, g.screen.x, g.screen.y, look.VEIL);
}

pub fn drawPause(g: *game.Game) void {
    veil(g);
    switch (g.pause_page) {
        .character => {
            g.character.draw(&g.face, &g.sprites, g.screen, bookView(g, &g.nearby));
        },
        .debug => game.debugging.draw(g),
        .main => {
            var rows: [game.PAUSE_ROWS.len][]const u8 = undefined;
            for (game.PAUSE_ROWS, &rows) |r, *l| l.* = pauseLabel(g, r);
            menu.draw(g.face, g.screen, "PAUSED", &rows, g.pause_menu.at, null);
        },
    }
}
