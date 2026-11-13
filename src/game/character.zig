const std = @import("std");
const ground_items = @import("../play/ground_items.zig");
const inventory = @import("../play/inventory.zig");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const passives = @import("../play/passives.zig");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const menu = @import("../ui/menu.zig");
const options = @import("../ui/options.zig");
const book = @import("../ui/book.zig");
const resilience = @import("../play/resilience.zig");
const look = @import("../gfx/look.zig");
const scene = @import("scene.zig");
const game = @import("../game.zig");
const rewards = @import("rewards.zig");
const binds = @import("binds.zig");
const skills = @import("skills.zig");
const tactics_exec = @import("tactics_exec.zig");
const skillbar = @import("../play/skillbar.zig");
const consumable = @import("../play/consumable.zig");
const trade = @import("../play/trade.zig");
const hero = @import("../play/hero.zig");
const quest_log = @import("../ui/quests.zig");
const script = atlas.script;
const P = mathx.P;
const PAUSE = menu.PAUSE;

pub fn questEntries(g: *const game.Game, out: *[script.MAX_QUESTS]quest_log.Entry) []const quest_log.Entry {
    const w = g.sim.map orelse return out[0..0];
    var n: usize = 0;
    for ([_]script.QuestState{ .active, .done }) |state| {
        for (w.script.quests(), 0..) |*q, i| {
            const at = g.pic.quests_shown[i];
            if (at.state != state) continue;
            _ = mathx.push(quest_log.Entry, out, &n, .{ .title = q.titled(), .asks = q.asks(at.stage), .done = state == .done });
        }
    }
    return out[0..n];
}

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

/// What Interact can reach from `from`, as listed and as resolved alike.
fn laidReached(g: *const game.Game, from: P, laid: anytype) bool {
    return withinReach(from, laid.at) and g.pic.laidShown(&g.sim, laid);
}

fn inLoot(g: *const game.Game, from: P, at: P, laid: anytype) bool {
    return laid.at.eq(at) and laidReached(g, from, laid);
}

fn takeable(g: *const game.Game, from: P, laid: anytype) bool {
    return if (g.character.page == .loot) inLoot(g, from, g.character.loot_at, laid) else laidReached(g, from, laid);
}

pub fn withinReach(from: P, p: P) bool {
    return mathx.dist(from, p) <= game.INTERACT_REACH;
}

pub fn nearbyOf(g: *game.Game, out: *game.NearbyBuf) []const book.Nearby {
    const at = g.sim.heroAt() orelse return out[0..0];
    var n: usize = 0;
    var listed = grid.CellSet.initEmpty();
    inline for (g.sim.ground.laid()) |laid| for (laid) |l| {
        if (!laidReached(g, at, l)) continue;
        const cell = grid.Level.idx(l.at);
        if (listed.isSet(cell)) continue;
        listed.set(cell);
        _ = mathx.push(book.Nearby, out, &n, if (g.sim.lv.at(l.at).isChest()) .{ .chest = l.at } else .{ .bag = l.at });
    };
    var cells = grid.Cells.around(at, game.INTERACT_REACH);
    while (cells.next()) |p| {
        if (!grid.Level.inside(p)) continue;
        if (!listed.isSet(grid.Level.idx(p))) {
            const chest = chestReached(g, at, p);
            const gold = goldReached(g, at, p);
            if (chest or gold != null) _ = mathx.push(book.Nearby, out, &n, if (chest or g.sim.lv.at(p).isChest()) .{ .chest = p } else .{ .gold = gold.? });
        }
        if (doorReached(g, at, p) != null) _ = mathx.push(book.Nearby, out, &n, .{ .door = p });
    }
    return out[0..n];
}

fn lootOf(g: *game.Game, out: *game.NearbyBuf, at: P) []const book.Nearby {
    const from = g.sim.heroAt() orelse return out[0..0];
    var n: usize = 0;
    for (g.sim.ground.drops[0..g.sim.ground.n], 0..) |drop, i| {
        if (inLoot(g, from, at, drop)) _ = mathx.push(book.Nearby, out, &n, .{ .loot = .{ .index = i, .item = drop.item } });
    }
    for (g.sim.ground.supplies[0..g.sim.ground.supply_n], 0..) |s, i| {
        if (inLoot(g, from, at, s)) _ = mathx.push(book.Nearby, out, &n, .{ .supply = .{ .index = i, .kind = s.kind } });
    }
    return out[0..n];
}

fn goldReached(g: *const game.Game, from: P, at: P) ?ground_items.Coins {
    if (!withinReach(from, at)) return null;
    for (g.sim.ground.coins[0..g.sim.ground.coin_n]) |pile| {
        if (pile.at.eq(at)) return g.pic.pileShown(&g.sim, pile);
    }
    return null;
}

pub fn lootReached(g: *const game.Game, from: P, at: P) bool {
    inline for (g.sim.ground.laid()) |laid| for (laid) |l| {
        if (inLoot(g, from, at, l)) return true;
    };
    return g.sim.lv.at(at).isChest() and goldReached(g, from, at) != null;
}

pub fn chestReached(g: *const game.Game, from: P, p: P) bool {
    return withinReach(from, p) and g.sim.lv.isLit(p) and g.sim.lv.at(p).opened() != null;
}

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
    if (game.jail.beside(g) != null) return true;
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
        v.keywords = &g.keywords;
        v.readied = g.sim.heroReadied();
        const at = g.pic.drawnCell(&g.sim, g.sim.heroSlot().?) orelse h.at;
        const pictured = g.pic.heroShown(&g.sim);
        const buildup = if (pictured) |shown| shown.resilience else h.resilience;
        const sundered = if (pictured) |shown| shown.sunder else h.sunder;
        const stats = g.sim.combatStatsOn(h, g.pic.tileShown(&g.sim, at), buildup, sundered);
        v.defence = .{ .dodge = stats.dodge, .armour = stats.armour };
        v.resists = stats.elements;
        for (std.enums.values(resilience.Kind)) |k| v.status_resist.set(k, .{ .percent = stats.statuses.get(k), .turns = buildup.meters.get(k).turns });
    }
    if (g.character.page == .loot) if (g.sim.heroAt()) |from| if (goldReached(g, from, g.character.loot_at)) |pile| {
        v.loot_gold = pile.amount;
    };
    v.quests = book.journalOn(g.screen, g.face, questEntries(g, &g.journal));
    if (g.character.page == .trade) v.dealer = dealerOf(g);
    return v;
}

fn dealerOf(g: *const game.Game) ?book.Dealer {
    const w = g.sim.map orelse return null;
    const npc = g.character.dealer;
    if (npc >= w.script.npc_n) return null;
    const shelf = &(g.sim.plot.wares[npc] orelse return null);
    return .{ .who = w.script.npc[npc].called(), .shelf = shelf };
}

/// The conversation stays open beneath, and is back once the trade is done.
pub fn openTrade(g: *game.Game, npc: u8) void {
    const w = g.sim.map orelse return;
    if (npc >= w.script.npc_n) return;
    _ = g.sim.plot.shelf(npc, g.sim.seed);
    openCharacter(g);
    g.character.choose(.trade);
    g.character.dealer = npc;
}

fn closeBook(g: *game.Game) void {
    if (g.character.page != .trade or g.sim.plot.talk == null) return game.toPlay(g);
    g.mode = .talk;
    game.holdWalk(g);
}

fn deal(g: *game.Game, command: book.Command) void {
    if (!drawnFor(g)) return;
    const shelf = &(g.sim.plot.wares[g.character.dealer] orelse return);
    const done = switch (command) {
        .buy => |row| trade.buy(shelf, row, &g.sim.inventory, &g.sim.gold),
        .sell => |row| trade.sell(shelf, row, &g.sim.inventory, &g.sim.gold),
        else => unreachable,
    } catch |err| {
        g.character.message.say("{s}", .{trade.caption(err)});
        return;
    };
    var name: [items.NAME_MAX]u8 = undefined;
    const what = switch (done.ware) {
        .item => |it| it.spoken(&name),
        .supply => |k| consumable.phrase(k),
    };
    const verb = if (command == .buy) "Bought" else "Sold";
    g.sim.log.push(.loot, "{s} {s} for " ++ hero.COINS_FMT ++ ".", .{ verb, what, done.gold });
    g.character.message.say("{s} for " ++ hero.COINS_FMT, .{ verb, done.gold });
    g.pic.gold_shown = g.sim.gold;
    g.sim.unsaved = true;
}

pub fn openNearby(g: *game.Game) bool {
    var buf: game.NearbyBuf = undefined;
    const nearby = nearbyOf(g, &buf);
    const only_doors = for (nearby) |n| {
        if (n != .door) break false;
    } else true;
    if (only_doors) if (game.jail.beside(g)) |at| return game.jail.interact(g, at);
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
        g.pic.turnHero(&g.sim, at.x - h.at.x);
        game.toPlay(g);
        spendTurn(g);
        return;
    }
    if (!lootReached(g, h.at, at)) return;
    g.pic.turnHero(&g.sim, at.x - h.at.x);
    g.loot_gold = at;
    if (lootOf(g, &g.nearby, at).len == 0) {
        takeLootGold(g);
        if (directEmptied(g)) g.mode = .play;
        return;
    }
    openCharacter(g);
    g.character.choose(.loot);
    g.character.loot_at = at;
}

/// Waits for the turn to be drawn, so no gold a death has yet to drop is taken with it.
fn takeLootGold(g: *game.Game) void {
    const at = g.loot_gold orelse return;
    if (!g.pic.quiet()) return;
    g.loot_gold = null;
    const h = g.sim.heroActor() orelse return;
    if (goldReached(g, h.at, at) != null) game.combat.collectGold(g, at);
}

fn itemFailed(g: *game.Game, err: inventory.Failure) void {
    g.character.message.say("{s}", .{inventory.caption(err)});
}

fn takeDrop(g: *game.Game, i: usize) bool {
    var name: [items.NAME_MAX]u8 = undefined;
    const item = g.sim.ground.drops[i].item;
    if (!g.sim.ground.take(i, &g.sim.inventory)) {
        itemFailed(g, error.Full);
        return false;
    }
    g.sim.log.push(.loot, PICKED_UP, .{item.spoken(&name)});
    return true;
}

fn takeSupply(g: *game.Game, i: usize) bool {
    const kind = g.sim.ground.supplies[i].kind;
    if (!g.sim.ground.takeSupply(i, &g.sim.inventory)) {
        g.character.message.say(inventory.STACK_FULL, .{});
        return false;
    }
    g.sim.log.push(.loot, PICKED_UP, .{consumable.phrase(kind)});
    return true;
}

const PICKED_UP = "Picked up {s}.";

fn useCarried(g: *game.Game, k: consumable.Kind) void {
    if (!turnFree(g)) return;
    const act = skillbar.Act.ofSupply(k);
    if (act.reticle() != null) g.mode = .play;
    const slot = g.bar.slotOf(act);
    skills.useSkill(g, .{ .act = act, .by = if (slot) |s| s.button else null, .set = if (slot) |s| s.set else .primary });
}

fn notYet(g: *game.Game) void {
    g.character.message.say("Not until the turn ends", .{});
}

pub fn characterCommand(g: *game.Game, command: book.Command) void {
    defer settleLoot(g);
    switch (command) {
        .close => closeBook(g),
        .buy, .sell => deal(g, command),
        .bindings => |act| {
            binds.openBinds(g);
            if (g.sim.growth.unlocked(act)) g.binds.assigning = act;
        },
        .passive => |i| {
            if (!drawnFor(g) or !g.sim.growth.allocate(i)) return;
            g.sim.log.push(.progress, "{s} allocated.", .{passives.NODES[i].name});
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

fn itemCommand(g: *game.Game, command: book.Command) void {
    var name: [items.NAME_MAX]u8 = undefined;
    if (!turnFree(g)) return;
    const h = g.sim.heroActor() orelse return;
    const base = g.sim.growth.attributes(g.sim.class);
    switch (command) {
        .close, .passive, .skill, .bindings, .open_loot, .use, .buy, .sell => unreachable,
        .equip => |e| {
            g.sim.inventory.equip(e.index, e.slot, base) catch |err| {
                itemFailed(g, err);
                return;
            };
            g.sim.log.push(.loot, "Equipped {s}: {s}.", .{ g.sim.inventory.gear.slots.get(e.slot).?.spoken(&name), e.slot.name() });
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
            g.sim.log.push(.loot, "Dropped {s}.", .{g.sim.inventory.remove(i).spoken(&name)});
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
            if (g.character.page == .loot or goldReached(g, h.at, at) == null) return;
            if (!rewards.coinDrop(&g.sim, at)) return;
            game.combat.collectGold(g, at);
        },
        .take_all => {
            if (g.character.page != .loot) return;
            var taken: usize = 0;
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
                if (h.pin.holding()) game.struggle(g) else g.sim.travel = link;
            } else if (h.hampered()) {
                game.toPlay(g);
                return game.heroStep(g, mathx.dirTo(h.at, p).?, 0);
            } else game.heroTo(g, p);
            g.pic.turnHero(&g.sim, dx);
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

pub fn endLoot(g: *game.Game) void {
    takeLootGold(g);
    if (!g.looted) return;
    g.looted = false;
    spendTurn(g);
}

fn spendTurn(g: *game.Game) void {
    tactics_exec.beforeAction(&g.sim);
    game.combat.endTurn(g);
}

pub fn pauseStep(g: *game.Game) void {
    switch (g.pause_page) {
        .options, .visuals, .display => {
            const page = options.pageOf(g.pause_page);
            const back = menu.backedAt(&g.st, g.screen);
            const pick = if (back) null else options.step(&g.cinema, &g.pause_menu, &g.st, g.screen, page, &g.display);
            switch (options.go(page, back, pick) orelse return) {
                .page => |p| {
                    g.pause_page = options.hostPage(@TypeOf(g.pause_page), p.to);
                    g.pause_menu = .{ .at = p.at };
                },
                .leave => {
                    g.pause_page = .main;
                    g.pause_menu = .{ .at = game.rowAt(game.PauseRow.options) };
                },
                .fullscreen => game.syncScreen(g, true),
                .debug => game.debugging.open(g, .main),
            }
        },
        .character => {
            const trading = g.character.page == .trade;
            if (!trading and padToGame(g)) return;
            const view = bookView(g, &g.nearby);
            if (g.character.direct() and !trading and view.nearby.len == 0) {
                g.mode = .play;
                return;
            }
            if (trading and view.dealer == null) return closeBook(g);
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
                .options => {
                    g.pause_page = .options;
                    g.pause_menu = .{};
                },
                .debug => game.debugging.open(g, .main),
                inline .back, .quit => |r| {
                    g.mode = .play;
                    g.exit = @field(game.Exit, @tagName(r));
                },
            }
        },
    }
}

fn pauseLabel(g: *const game.Game, r: game.PauseRow) [:0]const u8 {
    return switch (r) {
        .resume_ => "Resume",
        .options, .debug, .quit => menu.named(r),
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
        .options, .visuals, .display => {
            options.draw(g.face, &g.sprites, g.screen, &g.cinema, g.pause_menu.at, options.pageOf(g.pause_page), g.display);
            menu.drawBack(&g.face, g.screen, &g.st);
        },
        .character => {
            g.character.draw(&g.face, &g.sprites, g.screen, bookView(g, &g.nearby));
        },
        .debug => game.debugging.draw(g),
        .main => {
            var rows: [game.PAUSE_ROWS.len][]const u8 = undefined;
            for (game.PAUSE_ROWS, &rows) |r, *l| l.* = pauseLabel(g, r);
            menu.draw(g.face, &g.sprites, g.screen, "PAUSED", &rows, g.pause_menu.at, null);
            menu.drawBack(&g.face, g.screen, &g.st);
        },
    }
}

test "the Quests tab scrolls to its last screenful without a turn and reopens at the first" {
    const alloc = std.testing.allocator;
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    const w = try atlas.testAtlas();
    defer alloc.destroy(w);
    game.harness.arena(g, grid.MIDDLE, &.{});
    g.sim.map = w;
    for (0..script.MAX_QUESTS) |_| {
        const q = w.script.addQuest().?;
        _ = w.script.quest[q].stage[0].set("a word " ** (script.NOTE_MAX / 7));
        g.sim.plot.quests[q] = .{ .state = .active, .stage = 1 };
    }
    game.settle(g);
    g.st = .{ .device = .keys, .character_page = .quests };
    game.update(g, 0);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    try std.testing.expectEqual(book.Page.quests, g.character.page);
    try std.testing.expectEqual(script.MAX_QUESTS, bookView(g, &g.nearby).quests.entries.len);
    const clock = g.sim.clock;
    const last = bookView(g, &g.nearby).quests.last_top;
    g.st = .{ .scroll = -100 };
    game.update(g, mathx.FRAME_DT);
    try std.testing.expectEqual(last, g.character.top);
    try std.testing.expectEqualDeep(clock, g.sim.clock);
    g.st = .{ .device = .keys, .character_page = .quests };
    game.update(g, 0);
    g.st = .{ .device = .keys, .character_page = .quests };
    game.update(g, 0);
    try std.testing.expectEqual(@as(usize, 0), g.character.top);
    try std.testing.expectEqual(book.Page.quests, g.character.page);
}
