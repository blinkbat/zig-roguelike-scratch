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
const skills = @import("skills.zig");
const tactics = @import("tactics.zig");
const skillbar = @import("../play/skillbar.zig");
const consumable = @import("../play/consumable.zig");
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

/// `laid` is an `items.Drop` or `items.Supply`: lying lit where its foe's death has been drawn.
pub fn laidShown(g: *const game.Game, laid: anytype) bool {
    return g.sim.lv.isLit(laid.at) and laidDown(g, laid);
}

/// Laid, or its foe's death drawn; seen or not.
pub fn laidDown(g: *const game.Game, laid: anytype) bool {
    if (laid.source == grid.NO_ONE) return true;
    const i = actor.Pool.slot(laid.source);
    return g.pic.pictured[i].down();
}

/// What Interact can reach from `from`, as listed and as resolved alike.
fn laidReached(g: *const game.Game, from: P, laid: anytype) bool {
    return withinReach(from, laid.at) and laidShown(g, laid);
}

fn inLoot(g: *const game.Game, from: P, at: P, laid: anytype) bool {
    return laid.at.eq(at) and laidReached(g, from, laid);
}

fn takeable(g: *const game.Game, from: P, laid: anytype) bool {
    return if (g.character.page == .loot) inLoot(g, from, g.character.loot_at, laid) else laidReached(g, from, laid);
}

fn withinReach(from: P, p: P) bool {
    return mathx.dist(from, p) <= game.INTERACT_REACH;
}

pub fn nearbyOf(g: *game.Game, out: *game.NearbyBuf) []const book.Nearby {
    const at = g.sim.heroAt() orelse return out[0..0];
    var n: usize = 0;
    var listed = grid.CellSet.initEmpty();
    inline for (.{ g.sim.ground.drops[0..g.sim.ground.n], g.sim.ground.supplies[0..g.sim.ground.supply_n] }) |laid| for (laid) |l| {
        if (!laidReached(g, at, l)) continue;
        const cell = grid.Level.idx(l.at);
        if (listed.isSet(cell)) continue;
        listed.set(cell);
        out[n] = if (g.sim.lv.at(l.at).isChest()) .{ .chest = l.at } else .{ .bag = l.at };
        n += 1;
    };
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
    for (g.sim.ground.supplies[0..g.sim.ground.supply_n], 0..) |s, i| {
        if (!inLoot(g, from, at, s)) continue;
        out[n] = .{ .supply = .{ .index = i, .kind = s.kind } };
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

pub fn lootReached(g: *const game.Game, from: P, at: P) bool {
    inline for (.{ g.sim.ground.drops[0..g.sim.ground.n], g.sim.ground.supplies[0..g.sim.ground.supply_n] }) |laid| for (laid) |l| {
        if (inLoot(g, from, at, l)) return true;
    };
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
        const pictured = g.pic.heroShown(&g.sim);
        const buildup = if (pictured) |shown| shown.resilience else h.resilience;
        const sundered = if (pictured) |shown| shown.sunder else h.sunder;
        const stats = g.sim.combatStatsAt(h, at, buildup, sundered);
        v.defence = .{ .dodge = stats.dodge, .armour = stats.armour };
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
    if (!turnFree(g)) return;
    const h = g.sim.heroActor() orelse return;
    if (chestReached(g, h.at, at)) {
        if (!game.combat.openChest(g, at)) return;
        g.pic.turnToward(g.sim.hero, at.x - h.at.x);
        g.mode = .play;
        game.holdWalk(g);
        spendTurn(g);
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

fn takeSupply(g: *game.Game, i: usize) bool {
    const kind = g.sim.ground.supplies[i].kind;
    if (!g.sim.ground.takeSupply(i, &g.sim.inventory)) {
        g.character.message.say("Stack full", .{});
        return false;
    }
    g.sim.log.push(.loot, "Picked up {s}.", .{consumable.phrase(kind)});
    return true;
}

/// Throwing closes Character for the reticle; anything else is used where it is.
fn useCarried(g: *game.Game, k: consumable.Kind) void {
    if (!turnFree(g)) return;
    const act = skillbar.Act.ofSupply(k);
    if (act.reticle() != null) g.mode = .play;
    const slot = g.bar.slotOf(act);
    skills.useSkill(g, .{ .act = act, .by = if (slot) |s| s.button else menu.CONFIRM, .set = if (slot) |s| s.set else .primary });
}

fn notYet(g: *game.Game) void {
    g.character.message.say("Not until the turn ends", .{});
}

pub fn characterCommand(g: *game.Game, command: book.Command) void {
    defer settleLoot(g);
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
        .use => |k| useCarried(g, k),
        .equip, .unequip, .drop, .pickup, .take_supply, .take_gold, .take_all, .travel => itemCommand(g, command),
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

fn turnFree(g: *game.Game) bool {
    if (!drawnFor(g)) return false;
    if (g.sim.travel == null) return true;
    notYet(g);
    return false;
}

/// Item commands spend the turn, and wait out door travel.
fn itemCommand(g: *game.Game, command: book.Command) void {
    var name: [items.NAME_MAX]u8 = undefined;
    if (!turnFree(g)) return;
    const h = g.sim.heroActor() orelse return;
    const base = g.sim.growth.attributes(g.sim.class);
    switch (command) {
        .close, .passive, .skill, .bindings, .open_loot, .use => unreachable,
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
            if (i >= g.sim.ground.n or !takeable(g, h.at, g.sim.ground.drops[i])) return;
            if (!takeDrop(g, i)) return;
        },
        .take_supply => |i| {
            if (i >= g.sim.ground.supply_n or !takeable(g, h.at, g.sim.ground.supplies[i])) return;
            if (!takeSupply(g, i)) return;
        },
        .take_gold => |at| {
            if (goldReached(g, h.at, at) == null) return;
            if (g.character.page == .loot) {
                if (!at.eq(g.character.loot_at)) return;
            } else if (g.sim.lv.at(at).isChest() or g.sim.ground.bagged(at)) return;
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
            var bag_full = false;
            while (i < g.sim.ground.n) {
                if (!inLoot(g, h.at, g.character.loot_at, g.sim.ground.drops[i])) {
                    i += 1;
                    continue;
                }
                if (!takeDrop(g, i)) {
                    bag_full = true;
                    break;
                }
                taken += 1;
            }
            i = 0;
            while (i < g.sim.ground.supply_n) {
                if (!inLoot(g, h.at, g.character.loot_at, g.sim.ground.supplies[i]) or !takeSupply(g, i)) {
                    i += 1;
                    continue;
                }
                taken += 1;
            }
            if (bag_full) itemFailed(g, error.Full);
            if (taken == 0) return;
        },
        .travel => |p| {
            const link = doorReached(g, h.at, p) orelse return;
            const dx = p.x - h.at.x;
            if (p.eq(h.at)) {
                if (h.pin.turns > 0) game.struggle(g) else g.sim.travel = link;
            } else if (h.pin.turns > 0 or h.confusion.turns > 0) {
                g.mode = .play;
                game.holdWalk(g);
                return game.heroStep(g, mathx.dirTo(h.at, p).?, 0);
            } else game.heroTo(g, p);
            g.pic.turnToward(g.sim.hero, dx);
        },
    }
    game.syncStats(g);
    g.character.destination_index = 0;
    const looting = g.character.page == .loot;
    if (command == .travel or directEmptied(g)) g.mode = .play;
    game.holdWalk(g);
    if (looting) {
        g.looted = true;
        return;
    }
    spendTurn(g);
}

/// Everything taken while the loot menu was open is one action, spent once it closes.
pub fn settleLoot(g: *game.Game) void {
    if (game.characterShown(g) and g.character.page == .loot) return;
    endLoot(g);
}

/// The loot visit's one turn, spent now if anything was taken.
pub fn endLoot(g: *game.Game) void {
    if (!g.looted) return;
    g.looted = false;
    spendTurn(g);
}

fn spendTurn(g: *game.Game) void {
    tactics.beforeAction(&g.sim);
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
