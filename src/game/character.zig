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
const resilience = @import("../play/resilience.zig");
const terrain = @import("../play/terrain.zig");
const look = @import("../gfx/look.zig");
const scene = @import("scene.zig");
const game = @import("../game.zig");
const rewards = @import("rewards.zig");
const binds = @import("binds.zig");
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
    return g.sim.lv.isLit(drop.at) and dropLanded(g, drop);
}

/// Laid, or its foe's death drawn; seen or not.
pub fn dropLanded(g: *const game.Game, drop: items.Drop) bool {
    if (drop.source == grid.NO_ONE) return true;
    const i = actor.Pool.slot(drop.source);
    return g.pic.pictured[i].down();
}

fn withinReach(from: P, p: P) bool {
    return mathx.dist(from, p) <= game.INTERACT_REACH;
}

pub fn nearbyOf(g: *game.Game, out: *game.NearbyBuf) []const book.Nearby {
    const at = g.sim.heroAt() orelse return out[0..0];
    var n: usize = 0;
    var listed = std.StaticBitSet(grid.CELLS).initEmpty();
    for (g.sim.ground.drops[0..g.sim.ground.n]) |drop| {
        if (!dropReached(g, at, drop)) continue;
        const cell = grid.Level.idx(drop.at);
        if (listed.isSet(cell)) continue;
        listed.set(cell);
        out[n] = if (g.sim.lv.at(drop.at).isChest()) .{ .chest = drop.at } else .{ .bag = drop.at };
        n += 1;
    }
    var cells = grid.Cells.around(at, game.INTERACT_REACH);
    while (cells.next()) |p| {
        if (!grid.Level.inside(p)) continue;
        if (!listed.isSet(grid.Level.idx(p))) {
            const chest = chestReached(g, at, p);
            const gold = goldReached(g, at, p);
            if (chest or gold != null) {
                out[n] = if (chest or g.sim.lv.at(p).isChest()) .{ .chest = p } else .{ .gold = gold.? };
                n += 1;
            }
        }
        if (doorReached(g, at, p) != null) {
            out[n] = .{ .door = p };
            n += 1;
        }
    }
    return out[0..n];
}

fn lootOf(g: *game.Game, out: *game.NearbyBuf, at: P) []const book.Nearby {
    const from = g.sim.heroAt() orelse return out[0..0];
    var n: usize = 0;
    for (g.sim.ground.drops[0..g.sim.ground.n], 0..) |drop, i| {
        if (!inLoot(g, from, at, drop)) continue;
        out[n] = .{ .loot = .{ .index = i, .item = drop.item } };
        n += 1;
    }
    if (goldReached(g, from, at)) |pile| {
        out[n] = .{ .gold = pile };
        n += 1;
    }
    return out[0..n];
}

fn goldReached(g: *const game.Game, from: P, at: P) ?items.Coins {
    if (!withinReach(from, at)) return null;
    for (g.sim.ground.coins[0..g.sim.ground.coin_n]) |pile| {
        if (pile.at.eq(at)) return scene.pileShown(g, pile);
    }
    return null;
}

/// What Interact can reach from `from`, as listed and as resolved alike.
fn dropReached(g: *const game.Game, from: P, drop: items.Drop) bool {
    return withinReach(from, drop.at) and dropShown(g, drop);
}

fn inLoot(g: *const game.Game, from: P, at: P, drop: items.Drop) bool {
    return drop.at.eq(at) and dropReached(g, from, drop);
}

pub fn lootReached(g: *const game.Game, from: P, at: P) bool {
    for (g.sim.ground.drops[0..g.sim.ground.n]) |drop| {
        if (inLoot(g, from, at, drop)) return true;
    }
    return g.sim.lv.at(at).isChest() and goldReached(g, from, at) != null;
}

pub fn chestReached(g: *const game.Game, from: P, p: P) bool {
    return withinReach(from, p) and g.sim.lv.isLit(p) and g.sim.lv.at(p).opened() != null;
}

/// The hero's own door, or a clear one beside.
pub fn doorReached(g: *game.Game, from: P, p: P) ?atlas.Link {
    if (!withinReach(from, p) or !g.sim.lv.isLit(p) or !g.sim.lv.walkable(p)) return null;
    const link = g.sim.leadsTo(p) orelse return null;
    return if (!p.eq(from) and bodyShownIn(g, p)) null else link;
}

fn bodyShownIn(g: *game.Game, p: P) bool {
    if (g.pic.quiet()) return g.sim.lv.taken(p);
    return scene.shownAt(g, &scene.stoodNow(g), p);
}

pub fn anyNearby(g: *game.Game) bool {
    var nearby: game.NearbyBuf = undefined;
    return nearbyOf(g, &nearby).len > 0;
}

fn shownNearby(g: *game.Game, buf: *game.NearbyBuf) []const book.Nearby {
    return if (g.character.page == .loot) lootOf(g, buf, g.character.loot_at) else nearbyOf(g, buf);
}

fn directEmptied(g: *game.Game) bool {
    return g.character.direct() and shownNearby(g, &g.nearby).len == 0;
}

pub fn bookView(g: *game.Game, nearby: *game.NearbyBuf) book.View {
    const now = g.pic.quiet();
    const growth = if (now) &g.sim.growth else &g.pic.growth_shown;
    const life = g.pic.lifeShown(&g.sim);
    var v = book.View{ .class = g.sim.class, .name = g.sim.name.text(), .inventory = &g.sim.inventory, .growth = growth, .base = growth.attributes(g.sim.class), .gold = if (now) g.sim.gold else g.pic.gold_shown, .nearby = shownNearby(g, nearby), .device = g.st.device, .chest = g.character.page == .loot and g.sim.lv.at(g.character.loot_at) == .chest_open, .life = .{ .now = life.hp, .max = life.max }, .mana = .{ .now = g.pic.manaShown(&g.sim), .max = g.sim.manaMax() } };
    if (g.sim.heroBody()) |h| {
        v.steady = h.tactics.steady;
        const at = g.pic.drawnCell(&g.sim, g.sim.heroSlot().?) orelse h.at;
        const buildup = if (g.pic.heroShown(&g.sim)) |shown| shown.resilience else h.resilience;
        const stats = g.sim.combatStatsAt(h, at, buildup);
        v.resists = stats.elements;
        v.environment = terrain.of(g.sim.lv.at(at));
        for (std.enums.values(resilience.Kind)) |k| v.status_resist.set(k, .{ .percent = stats.statuses.get(k), .turns = buildup.meters.get(k).turns });
    }
    return v;
}

pub fn openNearby(g: *game.Game) bool {
    var buf: game.NearbyBuf = undefined;
    const nearby = nearbyOf(g, &buf);
    if (nearby.len == 0) return false;
    openCharacter(g);
    g.character.choose(.nearby);
    if (nearby.len == 1 and nearby[0] != .door) characterCommand(g, nearby[0].command());
    return true;
}

pub fn openLoot(g: *game.Game, at: P) void {
    if (!drawnFor(g)) return;
    if (g.sim.travel != null) return notYet(g);
    const h = g.sim.heroActor() orelse return;
    if (chestReached(g, h.at, at)) {
        if (!game.combat.openChest(g, at)) return;
        @import("tactics.zig").beforeAction(&g.sim);
        g.pic.turnToward(g.sim.hero, at.x - h.at.x);
        g.mode = .play;
        game.holdWalk(g);
        game.combat.endTurn(g);
        return;
    }
    if (!lootReached(g, h.at, at)) return;
    g.pic.turnToward(g.sim.hero, at.x - h.at.x);
    openCharacter(g);
    g.character.choose(.loot);
    g.character.loot_at = at;
}

fn itemFailed(g: *game.Game, err: items.Failure) void {
    g.character.message.say("{s}", .{items.caption(err)});
}

fn takeDrop(g: *game.Game, i: usize) bool {
    var name: [items.NAME_MAX]u8 = undefined;
    const item = g.sim.ground.drops[i].item;
    if (!g.sim.ground.take(i, &g.sim.inventory)) {
        itemFailed(g, error.Full);
        return false;
    }
    g.sim.log.push(.loot, "Picked up {s}.", .{item.name(&name)});
    return true;
}

fn notYet(g: *game.Game) void {
    g.character.message.say("Not until the turn ends", .{});
}

pub fn characterCommand(g: *game.Game, command: book.Command) void {
    switch (command) {
        .close => g.mode = .play,
        .bindings => |act| {
            binds.openBinds(g);
            if (g.sim.growth.unlocked(act)) g.binds.assigning = act;
        },
        .passive => |i| {
            if (!drawnFor(g) or !g.sim.growth.allocate(i)) return;
            g.sim.log.push(.progress, "{s} allocated.", .{progress.NODES[i].name});
            game.syncStats(g);
            g.sim.unsaved = true;
        },
        .skill => |act| {
            if (!drawnFor(g)) return;
            const unlocked = g.sim.growth.unlocked(act);
            if (!g.sim.growth.learn(g.sim.class, act)) return;
            g.sim.log.push(.progress, "{s}: rank {d}.", .{ act.name(), g.sim.growth.ranks.get(act) });
            if (!unlocked) if (g.bar.firstEmpty()) |slot| g.bar.bind(slot, act);
            g.sim.unsaved = true;
        },
        .open_loot => |at| openLoot(g, at),
        .equip, .unequip, .drop, .pickup, .take_gold, .take_all, .travel => itemCommand(g, command),
    }
}

/// Whether the turn is drawn, so a command acts; says so when not.
fn drawnFor(g: *game.Game) bool {
    if (!g.pic.quiet()) {
        notYet(g);
        return false;
    }
    g.character.message.clear();
    return true;
}

/// Item commands spend the turn, and wait out door travel.
fn itemCommand(g: *game.Game, command: book.Command) void {
    var name: [items.NAME_MAX]u8 = undefined;
    if (!drawnFor(g)) return;
    if (g.sim.travel != null) return notYet(g);
    const h = g.sim.heroActor() orelse return;
    const base = g.sim.growth.attributes(g.sim.class);
    switch (command) {
        .close, .passive, .skill, .bindings, .open_loot => unreachable,
        .equip => |e| {
            g.sim.inventory.equip(e.index, e.slot, base) catch |err| {
                itemFailed(g, err);
                return;
            };
            g.sim.log.push(.loot, "Equipped {s}: {s}.", .{ g.sim.inventory.gear.slots.get(e.slot).?.name(&name), e.slot.name() });
        },
        .unequip => |s| {
            g.sim.inventory.unequip(s, base) catch |err| {
                itemFailed(g, err);
                return;
            };
            g.sim.log.push(.loot, "Unequipped {s}.", .{s.name()});
        },
        .drop => |i| {
            if (i >= g.sim.inventory.n) return;
            if (!game.combat.groundRoom(g)) return;
            rewards.dropItem(&g.sim, .{ .item = g.sim.inventory.bag[i], .at = h.at });
            g.sim.log.push(.loot, "Dropped {s}.", .{g.sim.inventory.remove(i).name(&name)});
        },
        .pickup => |i| {
            if (i >= g.sim.ground.n or !dropReached(g, h.at, g.sim.ground.drops[i])) return;
            if (g.character.page == .loot and !g.sim.ground.drops[i].at.eq(g.character.loot_at)) return;
            if (!takeDrop(g, i)) return;
        },
        .take_gold => |at| {
            if (goldReached(g, h.at, at) == null) return;
            if (g.character.page == .loot) {
                if (!at.eq(g.character.loot_at)) return;
            } else if (g.sim.lv.at(at).isChest() or g.sim.ground.hasItems(at)) return;
            game.combat.collectGold(g, at);
        },
        .take_all => {
            if (g.character.page != .loot) return;
            var taken: usize = 0;
            if (goldReached(g, h.at, g.character.loot_at) != null) {
                game.combat.collectGold(g, g.character.loot_at);
                taken += 1;
            }
            var i: usize = 0;
            while (i < g.sim.ground.n) {
                if (!inLoot(g, h.at, g.character.loot_at, g.sim.ground.drops[i])) {
                    i += 1;
                    continue;
                }
                if (!takeDrop(g, i)) break;
                taken += 1;
            }
            if (taken == 0) return;
        },
        .travel => |p| {
            const link = doorReached(g, h.at, p) orelse return;
            const dx = p.x - h.at.x;
            if (p.eq(h.at)) g.sim.travel = link else game.heroTo(g, p);
            g.pic.turnToward(g.sim.hero, dx);
        },
    }
    game.syncStats(g);
    g.character.destination_index = 0;
    if (command == .travel or directEmptied(g)) g.mode = .play;
    game.holdWalk(g);
    @import("tactics.zig").beforeAction(&g.sim);
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
            if (menu.backedAt(&g.st, g.screen)) {
                g.mode = .play;
                return;
            }
            const i = g.pause_menu.stepAt(&g.st, game.PAUSE_ROWS.len, g.screen) orelse return;
            switch (game.PAUSE_ROWS[i]) {
                .resume_ => g.mode = .play,
                .debug => game.debugging.open(g, .main),
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
    g.light.reveal(&g.sim.lv, !g.light.reveal_map);
    g.mini.stale = true;
}

pub fn terrainSeen(g: *const game.Game, p: P) bool {
    return g.light.remembers(&g.sim.lv, p);
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
            menu.drawBack(&g.face, g.screen, &g.st);
        },
    }
}
