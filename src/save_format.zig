const std = @import("std");
const wire = @import("core/wire.zig");
const store = @import("core/store.zig");
const data = @import("save_data.zig");
const game = @import("game.zig");
const grid = @import("map/grid.zig");
const atlas = @import("map/atlas.zig");
const actor = @import("play/actor.zig");
const ground_items = @import("play/ground_items.zig");
const inventory = @import("play/inventory.zig");
const item_bases = @import("play/item_bases.zig");
const items = @import("play/items.zig");
const hero = @import("play/hero.zig");
const progress = @import("play/progress.zig");
const log = @import("play/log.zig");
const skillbar = @import("play/skillbar.zig");
const flask = @import("play/flask.zig");
const sunder = @import("play/sunder.zig");
const glacial = @import("play/glacial.zig");
const bleeding = @import("play/bleeding.zig");
const day = @import("map/day.zig");
const climate = @import("map/climate.zig");
const P = @import("core/mathx.zig").P;

pub const MAGIC = "cistern-save\n";
const VERSION: u64 = 4;
/// Runs saved before cells' climate locations were kept: they take them from the level they saved.
const PLACELESS: u64 = 3;
/// Runs saved before heroes started holding their class arms, and the first builds after: see `armless`.
const UNARMED: u64 = 2;
/// Runs saved before flasks were worn as items.
const FLASKLESS: u64 = 1;
const LEGACY = [_]u64{ UNARMED, FLASKLESS };
const READABLE = [_]u64{ VERSION, PLACELESS } ++ LEGACY;
const HANDS = [_]item_bases.Slot{ .right_hand, .left_hand };
pub const Code = wire.Codec(Policy);
pub const FILE_CAP = blk: {
    @setEvalBranchQuota(100_000);
    break :blk @max(64 << 20, store.head(MAGIC) + Code.maxSize(Snapshot) + store.SUM);
};

pub const Policy = @import("save_values.zig").Policy;

pub const Snapshot = struct {
    summary: data.Summary,
    seed: u64,
    map: ?data.Map = null,
    node: usize = 0,
    visits: [atlas.MAX_NODES]?data.Visit = @splat(null),
    run: data.Tail,
    portable: data.Portable = .{},
};

fn references(comptime T: type) type {
    const original = std.meta.fields(T);
    var fields: [original.len]std.builtin.Type.StructField = undefined;
    for (original, 0..) |field, i| {
        fields[i] = data.fieldOf(field.name, *const field.type, null);
    }
    return data.Struct(fields);
}

const Encoded = struct {
    summary: *const data.Summary,
    seed: u64,
    map: ?*const data.Map,
    node: usize,
    visits: *const [atlas.MAX_NODES]?*const data.Visit,
    run: *const references(data.Tail),
    portable: *const references(data.Portable),
};

comptime {
    const want = std.meta.fieldNames(Snapshot);
    const got = std.meta.fieldNames(Encoded);
    if (want.len != got.len) @compileError("save_format.Encoded must hold every Snapshot field");
    for (want, got) |w, e| {
        if (!std.mem.eql(u8, w, e)) @compileError("save_format.Encoded must list Snapshot's fields in its order: " ++ w ++ ", not " ++ e);
    }
}

/// Into an empty `out`, all but the sum `seal` ends it with, with room kept for that sum.
fn encode(out: *std.ArrayList(u8), file: Encoded) !void {
    std.debug.assert(out.items.len == 0);
    try store.begin(out.writer(), MAGIC, VERSION);
    try Code.write(out, file);
    try out.ensureUnusedCapacity(store.SUM);
}

pub fn write(g: *game.Game, out: *std.ArrayList(u8)) !void {
    const snapshot = try out.allocator.create(Snapshot);
    defer out.allocator.destroy(snapshot);
    try capture(g, snapshot);
    try writeSnapshot(snapshot, out);
}

const PARTS = .{ .{ "run", data.TAIL_FIELDS }, .{ "portable", data.PORTABLE_FIELDS } };

fn refer(into: anytype, from: anytype) void {
    inline for (std.meta.fields(@TypeOf(from.*))) |field| @field(into, field.name) = &@field(from, field.name);
}

pub fn capture(g: *game.Game, snapshot: *Snapshot) !void {
    return captureOver(g, snapshot, false, false);
}

/// `map_held` when `snapshot.map` already holds this run's map; `visits_held` when its visits are this run's as last captured.
pub fn captureOver(g: *game.Game, snapshot: *Snapshot, map_held: bool, visits_held: bool) !void {
    snapshot.summary = data.Summary.of(g) orelse return error.Damaged;
    snapshot.seed = g.sim.seed;
    snapshot.node = g.sim.node;
    if (!map_held) {
        snapshot.map = null;
        if (g.sim.map) |map| snapshot.map = map.*;
    }
    for (&snapshot.visits, 0..) |*visit, node| {
        if (!g.sim.visited.isSet(node)) {
            visit.* = null;
        } else if (!visits_held or visit.* == null or g.sim.visits_changed.isSet(node)) visit.* = g.sim.visits[node];
    }
    inline for (PARTS) |p| inline for (p[1]) |field| {
        @field(@field(snapshot, p[0]), field[1]) = @field(data.part(g, field[0]), field[1]);
    };
}

pub fn writeSnapshot(snapshot: *const Snapshot, out: *std.ArrayList(u8)) !void {
    var visits: [atlas.MAX_NODES]?*const data.Visit = @splat(null);
    for (&snapshot.visits, 0..) |*visit, node| if (visit.*) |*loaded| {
        visits[node] = loaded;
    };
    var run: references(data.Tail) = undefined;
    refer(&run, &snapshot.run);
    var portable: references(data.Portable) = undefined;
    refer(&portable, &snapshot.portable);
    const map: ?*const data.Map = if (snapshot.map) |*loaded| loaded else null;
    try encode(out, .{ .summary = &snapshot.summary, .seed = snapshot.seed, .map = map, .node = snapshot.node, .visits = &visits, .run = &run, .portable = &portable });
}

fn legacyKeyZoo() atlas.zoo.Spec {
    var s = atlas.zoo.Spec{};
    s.key = s.approach().add(.{ .x = -1, .y = 0 });
    return s;
}

fn legacyKeyLevel(s: atlas.zoo.Spec) grid.Level {
    const way = s.approach();
    var lv = grid.openFloor();
    for (&lv.tile) |*t| t.* = .rock;
    lv.set(way, .floor);
    lv.set(s.key.?, .zoo_key);
    var it = grid.Box.sized(.{ .x = way.x - 10, .y = way.y - 2 }, 9, 5).cells();
    while (it.next()) |p| lv.set(p, .floor);
    return lv;
}

fn legacyKeyRun(g: *game.Game, map: *data.Map) atlas.zoo.Spec {
    map.* = .{};
    _ = map.add(.{ .procgen = .{} });
    const s = legacyKeyZoo();
    map.node[0].zoo = s;
    map.start = .{ .node = 0, .at = s.approach() };
    g.sim.lv = legacyKeyLevel(s);
    game.reset(g, s.approach());
    g.sim.map = map;
    return s;
}

test "a legacy key cell that was the only way to the gate migrates to an open chest with its key lying out" {
    const s = legacyKeyZoo();
    try std.testing.expect(s.valid());
    for ([_]bool{ true, false }) |choke| {
        var lv = legacyKeyLevel(s);
        if (!choke) lv.set(s.approach().add(.{ .x = -1, .y = 1 }), .floor);
        var ground = ground_items.Ground{};
        var bag = inventory.Inventory{};
        try migrateZooKey(&lv, &ground, &.{}, s, &bag);
        try std.testing.expectEqual(if (choke) grid.Tile.chest_open else grid.Tile.chest, lv.at(s.key.?));
        try std.testing.expectEqual(choke, ground.hasItems(s.key.?));
    }
}

test "a legacy key that would crowd out the drops still to come goes in the bag, not on the ground" {
    const s = legacyKeyZoo();
    var lv = legacyKeyLevel(s);
    const pool = actor.Pool{};
    var ground = ground_items.Ground{};
    while (ground.room(deathsToCome(&pool))) _ = ground.add(.{ .item = items.SMALL_KEY, .at = s.approach() });
    const full = ground.n;
    var bag = inventory.Inventory{};
    try migrateZooKey(&lv, &ground, &pool, s, &bag);
    try std.testing.expectEqual(grid.Tile.chest_open, lv.at(s.key.?));
    try std.testing.expectEqual(full, ground.n);
    try std.testing.expectEqual(@as(usize, 1), bag.n);
}

test "legacy key migration rejects exhausted storage without losing the key" {
    const s = legacyKeyZoo();
    for ([_]grid.Tile{ .zoo_key, .key_taken }) |tile| {
        var lv = legacyKeyLevel(s);
        lv.set(s.key.?, tile);
        lv.set(s.door(), .locked_gate);
        var ground = ground_items.Ground{};
        const pool = actor.Pool{};
        while (ground.room(deathsToCome(&pool))) _ = ground.add(.{ .item = .{ .kind = .ring }, .at = s.approach() });
        var bag = inventory.Inventory{};
        while (bag.add(.{ .kind = .ring })) {}
        const ground_n = ground.n;
        try std.testing.expectError(error.Damaged, migrateZooKey(&lv, &ground, &pool, s, &bag));
        try std.testing.expectEqual(tile, lv.at(s.key.?));
        try std.testing.expectEqual(ground_n, ground.n);
        try std.testing.expectEqual(inventory.BAG_MAX, bag.n);
    }
}

test "portable autosave snapshots own every byte while the live run changes" {
    const alloc = std.testing.allocator;
    const source = try game.boot(alloc);
    defer game.shut(alloc, source);
    const world = try alloc.create(data.Map);
    defer alloc.destroy(world);
    world.* = .{};
    _ = world.add(.{ .procgen = .{} });
    world.start = .{ .node = 0, .at = .{ .x = 10, .y = 10 } };
    game.beginMapAt(source, world, world.start, 73);
    game.keepVisit(source, 0);
    const snapshot = try alloc.create(Snapshot);
    defer alloc.destroy(snapshot);
    try capture(source, snapshot);
    var before = std.ArrayList(u8).init(alloc);
    defer before.deinit();
    try write(source, &before);
    source.sim.name = hero.Name.of("Changed");
    source.sim.gold += 100;
    source.sim.visits[0].pool.items[0].hp = 1;
    source.sim.visits[0].lv.tile[0] = .lava;
    _ = world.node[0].label.set("Changed");
    var frozen = std.ArrayList(u8).init(alloc);
    defer frozen.deinit();
    try writeSnapshot(snapshot, &frozen);
    try std.testing.expectEqualSlices(u8, before.items, frozen.items);
}

test "a held autosave snapshot recopies only the visits written since it was taken, and every one after a fresh turn" {
    const alloc = std.testing.allocator;
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    const world = try alloc.create(data.Map);
    defer alloc.destroy(world);
    world.* = .{};
    _ = world.add(.{ .procgen = .{} });
    _ = world.add(.{ .procgen = .{} });
    world.start = .{ .node = 0, .at = .{ .x = 10, .y = 10 } };
    game.beginMapAt(g, world, world.start, 73);
    game.keepVisit(g, 0);
    game.keepVisit(g, 1);
    const snapshot = try alloc.create(Snapshot);
    defer alloc.destroy(snapshot);
    try captureOver(g, snapshot, false, false);
    g.sim.visits_changed = .initEmpty();
    const kept = snapshot.visits[0].?.lv.tile[0];
    g.sim.visits[0].lv.tile[0] = .lava;
    g.sim.lv.tile[0] = .water;
    game.keepVisit(g, 1);
    try captureOver(g, snapshot, true, true);
    try std.testing.expectEqual(kept, snapshot.visits[0].?.lv.tile[0]);
    try std.testing.expectEqual(grid.Tile.water, snapshot.visits[1].?.lv.tile[0]);
    g.sim.resetTransientTurn();
    try captureOver(g, snapshot, true, true);
    try std.testing.expectEqual(grid.Tile.lava, snapshot.visits[0].?.lv.tile[0]);
}

test "legacy key migration failure leaves the live run and map unchanged" {
    const alloc = std.testing.allocator;
    const current = try game.boot(alloc);
    defer game.shut(alloc, current);
    game.begin(current, 37);
    const map = try alloc.create(data.Map);
    defer alloc.destroy(map);
    const s = legacyKeyRun(current, map);
    const snapshot = try alloc.create(Snapshot);
    defer alloc.destroy(snapshot);
    try capture(current, snapshot);
    while (snapshot.run.ground.room(deathsToCome(&snapshot.run.pool))) _ = snapshot.run.ground.add(.{ .item = .{ .kind = .ring }, .at = s.approach() });
    while (snapshot.run.inventory.add(.{ .kind = .ring })) {}
    var kept = try Untouched.init(alloc, current, map);
    defer kept.deinit();
    var bytes = std.ArrayList(u8).init(alloc);
    defer bytes.deinit();
    for ([_]grid.Tile{ .zoo_key, .key_taken }) |tile| {
        snapshot.run.lv.set(s.key.?, tile);
        snapshot.run.lv.set(s.door(), .locked_gate);
        bytes.clearRetainingCapacity();
        try writeSnapshot(snapshot, &bytes);
        seal(&bytes);
        try std.testing.expectError(error.Damaged, read(bytes.items, current, map));
        try kept.expectKept();
    }
}

test "legacy key migration ignores the stale visit for the active node" {
    const alloc = std.testing.allocator;
    const current = try game.boot(alloc);
    defer game.shut(alloc, current);
    game.begin(current, 37);
    const map = try alloc.create(data.Map);
    defer alloc.destroy(map);
    const s = legacyKeyRun(current, map);
    while (current.sim.ground.room(deathsToCome(&current.sim.pool))) _ = current.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = s.approach() });
    while (current.sim.inventory.n < inventory.BAG_MAX - 1) try std.testing.expect(current.sim.inventory.add(.{ .kind = .ring }));
    game.keepVisit(current, 0);
    var bytes = std.ArrayList(u8).init(alloc);
    defer bytes.deinit();
    try sealed(current, &bytes);
    try read(bytes.items, current, map);
    try std.testing.expectEqual(grid.Tile.chest_open, current.sim.lv.at(s.key.?));
    try std.testing.expectEqual(inventory.BAG_MAX, current.sim.inventory.n);
    try std.testing.expectEqual(items.SMALL_KEY.kind, current.sim.inventory.bag[inventory.BAG_MAX - 1].kind);
    try std.testing.expectEqual(grid.Tile.zoo_key, current.sim.visits[0].lv.at(s.key.?));
    for ([_]i32{ -4, -5 }, 0..) |dx, i| {
        const at = s.approach().add(.{ .x = dx, .y = 0 });
        try std.testing.expectEqual(@as(?usize, i), map.addDoor(0, at));
        current.sim.lv.putDoor(at, i);
    }
    map.link(.{ .node = 0, .door = 0 }, .{ .node = 0, .door = 1 });
    current.sim.travel = .{ .node = 0, .door = 1 };
    game.leave(current);
    try std.testing.expectEqual(grid.Tile.chest_open, current.sim.lv.at(s.key.?));
    try std.testing.expectEqual(grid.Tile.chest_open, current.sim.visits[0].lv.at(s.key.?));
    try std.testing.expectEqual(inventory.BAG_MAX, current.sim.inventory.n);
}

pub const OpenError = error{ NotASave, OtherBuild, Short, Damaged };

pub fn open(bytes: []const u8, magic: []const u8, print: u64) OpenError![]const u8 {
    return store.open(bytes, magic, print) catch |err| switch (err) {
        error.Foreign => error.NotASave,
        else => |other| other,
    };
}

fn opened(bytes: []const u8) !struct { body: []const u8, version: u64 } {
    for (READABLE) |version| {
        const body = open(bytes, MAGIC, version) catch |err| switch (err) {
            error.OtherBuild => continue,
            else => return err,
        };
        return .{ .body = body, .version = version };
    }
    return error.OtherBuild;
}

pub fn parse(bytes: []const u8) !*Snapshot {
    const file = try opened(bytes);
    const snapshot = try std.heap.page_allocator.create(Snapshot);
    errdefer std.heap.page_allocator.destroy(snapshot);
    try Code.read(file.body, snapshot);
    if (file.version != VERSION) placeFromLevel(snapshot);
    if (file.version == FLASKLESS) snapshot.run.inventory.gear.wearFlasks();
    if (file.version == FLASKLESS or (file.version == UNARMED and armless(&snapshot.run.inventory, snapshot.run.class))) snapshot.run.inventory.gear.arm(snapshot.run.class);
    try validate(snapshot);
    return snapshot;
}

pub fn placeFromLevel(snapshot: *Snapshot) void {
    snapshot.portable.locations = climate.locations(&snapshot.run.lv);
}

/// No hand held and no class arm carried: a version-2 run from before heroes started armed, not one that put its arms away.
fn armless(inv: *const inventory.Inventory, class: hero.Class) bool {
    for (HANDS) |slot| if (inv.gear.slots.get(slot) != null) return false;
    for (inv.bag[0..inv.n]) |it| for (class.arms()) |k| if (it.kind == k) return false;
    return true;
}

fn peek(bytes: []const u8) !data.Summary {
    return peekWith(parse, bytes);
}

pub fn read(bytes: []const u8, g: *game.Game, map: *data.Map) !void {
    return readWith(parse, bytes, g, map);
}

pub fn peekWith(comptime parseFn: anytype, bytes: []const u8) !data.Summary {
    const snapshot = try parseFn(bytes);
    defer std.heap.page_allocator.destroy(snapshot);
    return snapshot.summary;
}

pub fn readWith(comptime parseFn: anytype, bytes: []const u8, g: *game.Game, map: *data.Map) !void {
    const snapshot = try parseFn(bytes);
    defer std.heap.page_allocator.destroy(snapshot);
    apply(snapshot, g, map);
}

pub fn apply(snapshot: *Snapshot, g: *game.Game, map: *data.Map) void {
    if (snapshot.map) |*loaded| map.* = loaded.*;
    g.sim.map = if (snapshot.map != null) map else null;
    g.sim.seed = snapshot.seed;
    g.sim.node = snapshot.node;
    g.sim.visited = .initEmpty();
    for (&snapshot.visits, 0..) |*visit, node| {
        if (visit.*) |*loaded| {
            g.sim.visited.set(node);
            g.sim.visits[node] = loaded.*;
        }
    }
    inline for (PARTS) |p| inline for (p[1]) |field| {
        @field(data.part(g, field[0]), field[1]) = @field(@field(snapshot, p[0]), field[1]);
    };
    game.resumeRun(g);
    g.sim.unsaved = true;
}

pub fn validate(snapshot: *Snapshot) !void {
    const run = &snapshot.run;
    if (run.hero != actor.Pool.idOf(0)) return error.Damaged;
    if (!run.rng.valid() or !run.loot_rng.valid()) return error.Damaged;
    if (!run.name.valid()) return error.Damaged;
    const body = heroIn(&run.pool, run.hero, run.class.kind()) orelse return error.Damaged;
    if (run.bar.modifier) |m| if (std.mem.indexOfScalar(@TypeOf(m), &skillbar.SLOTS, m) == null) {
        run.bar.modifier = null;
    };
    if (run.gold < 0 or run.mana < 0 or run.growth.level == 0) return error.Damaged;
    _ = run.growth.gain(0);
    run.clock = day.Clock.at(run.clock.hour());
    run.mana_recovery = @mod(run.mana_recovery, hero.MANA_REGEN_TURNS);
    snapshot.portable.life_recovery = @mod(snapshot.portable.life_recovery, hero.LIFE_REGEN_TURNS);
    run.growth.restoreStart(run.class);
    _ = run.growth.refundExcessRanks();
    for (&run.flasks.values) |*bottle| {
        if (bottle.left < 0) return error.Damaged;
        bottle.mend();
    }
    if (run.inventory.n > inventory.BAG_MAX) return error.Damaged;
    run.inventory.mend();
    for (&snapshot.portable.plot.wares) |*shelf| if (shelf.*) |*w| {
        if (!w.valid()) return error.Damaged;
        w.mend();
    };
    run.log.scroll = @min(run.log.scroll, run.log.n -| 1);
    try validateLevel(&run.lv, &run.pool, &run.ground);
    try validateLog(&run.log);
    if (snapshot.map) |*map| {
        if (!atlas.holdsNodes(map.node_n, snapshot.node)) return error.Damaged;
        if (map.start.node >= map.node_n or !grid.Level.inside(map.start.at)) return error.Damaged;
        if (!map.linksValid()) return error.Damaged;
        try validateDoors(&run.lv, &map.node[snapshot.node]);
        for (map.nodes()) |*node| {
            if (!node.label.valid() or !node.zooFits()) return error.Damaged;
            for (node.doors()) |door| {
                if (!grid.Level.inside(door.at)) return error.Damaged;
            }
            switch (node.plan) {
                .procgen => |*plan| {
                    if (!plan.section.valid()) return error.Damaged;
                    plan.* = plan.fit();
                },
                .bespoke => |*plan| {
                    for (plan.foes()) |foe| {
                        if (!foe.kind.foe() or !grid.Level.inside(foe.at)) return error.Damaged;
                    }
                    for (plan.torches()) |at| if (!grid.Level.inside(at)) return error.Damaged;
                },
            }
        }
        for (&snapshot.visits, 0..) |*visit, node| {
            if (visit.*) |*loaded| {
                if (node >= map.node_n or heroIn(&loaded.pool, run.hero, run.class.kind()) == null) return error.Damaged;
                try validateLevel(&loaded.lv, &loaded.pool, &loaded.ground);
                try validateDoors(&loaded.lv, &map.node[node]);
            }
        }
        if (!map.script.valid(map.node_n)) return error.Damaged;
        try validatePlot(&snapshot.portable.plot, &map.script);
    } else {
        if (snapshot.node != 0) return error.Damaged;
        for (&snapshot.visits) |*visit| if (visit.* != null) return error.Damaged;
        try validateDoors(&run.lv, null);
        try validatePlot(&snapshot.portable.plot, &.{});
    }
    if (!snapshot.summary.valid()) return error.Damaged;
    if (snapshot.summary.node != (if (snapshot.map != null) @as(?usize, snapshot.node) else null)) return error.Damaged;
    if (snapshot.map) |*map| if (!std.mem.eql(u8, snapshot.summary.place.text(), map.node[snapshot.node].label.text())) return error.Damaged;
    if (!std.mem.eql(u8, snapshot.summary.name.text(), run.name.text())) return error.Damaged;
    if (snapshot.summary.hp != body.hp or snapshot.summary.max != body.max or snapshot.summary.gold != run.gold) return error.Damaged;
    if (snapshot.map) |*map| {
        try migrateZooKey(&run.lv, &run.ground, &run.pool, map.node[snapshot.node].zoo, &run.inventory);
        for (&snapshot.visits, 0..) |*visit, node| if (visit.*) |*loaded| {
            if (node != snapshot.node) try migrateZooKey(&loaded.lv, &loaded.ground, &loaded.pool, map.node[node].zoo, &run.inventory);
        };
    }
}

fn migrateZooKey(level: *grid.Level, ground: *ground_items.Ground, pool: *const actor.Pool, zoo: ?atlas.zoo.Spec, carried: ?*inventory.Inventory) !void {
    const z = zoo orelse return;
    const at = z.key orelse return;
    const key = items.SMALL_KEY;
    const grounded = ground.room(deathsToCome(pool));
    switch (level.at(at)) {
        .zoo_key => {
            if (chestable(level, z, at)) return level.set(at, .chest);
            if (!grounded or !ground.add(.{ .item = key, .at = at })) {
                const bag = carried orelse return error.Damaged;
                if (!bag.add(key)) return error.Damaged;
            }
            level.set(at, .chest_open);
        },
        .key_taken => {
            if (level.at(z.door()) != .locked_gate) return level.set(at, .chest_open);
            const bag = carried orelse return error.Damaged;
            if (bag.add(key)) return level.set(at, .chest_open);
            if (chestable(level, z, at)) return level.set(at, .chest);
            if (!grounded or !ground.add(.{ .item = key, .at = at })) return error.Damaged;
            level.set(at, .chest_open);
        },
        else => {},
    }
}

fn chestable(level: *grid.Level, z: atlas.zoo.Spec, at: P) bool {
    return level.who(at) == grid.NO_ONE and !severs(level, z, at);
}

fn severs(level: *grid.Level, z: atlas.zoo.Spec, at: P) bool {
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const reached = grid.distances(level, z.approach(), &dist, &queue);
    const was = level.at(at);
    level.set(at, .chest);
    defer level.set(at, was);
    return grid.distances(level, z.approach(), &dist, &queue) + 1 < reached;
}

fn validatePlot(plot: *const @FieldType(data.Portable, "plot"), s: *const atlas.script.Script) !void {
    if (plot.asked) |d| if (d >= s.dialog_n) return error.Damaged;
    for (plot.spots) |spot| if (spot) |p| if (!grid.Level.inside(p)) return error.Damaged;
    for (plot.quests) |q| if (!atlas.script.STAGE_SPAN.holds(q.stage)) return error.Damaged;
    if (plot.trading) |f| if (f >= s.npc_n) return error.Damaged;
    for (plot.wares, 0..) |shelf, i| if (shelf != null and i >= s.npc_n) return error.Damaged;
    const talk = plot.talk orelse return;
    if (talk.dialog >= s.dialog_n or talk.line >= s.dialog[talk.dialog].line_n or talk.cursor >= atlas.script.MAX_CHOICES) return error.Damaged;
    if (talk.npc) |f| if (f >= s.npc_n) return error.Damaged;
}

fn validateDoors(level: *const grid.Level, node: ?*const atlas.Node) !void {
    for (level.door, 0..) |door, cell| {
        if (door == grid.NO_DOOR) continue;
        const owner = node orelse return error.Damaged;
        if (door > owner.door_n or !owner.door[door - 1].at.eq(grid.Level.of(cell))) return error.Damaged;
    }
}

fn heroIn(pool: *const actor.Pool, id: u16, kind: actor.Kind) ?*const actor.Actor {
    const body = pool.getConst(id) orelse return null;
    return if (body.kind == kind) body else null;
}

fn deathsToCome(pool: *const actor.Pool) usize {
    var alive: usize = 0;
    for (pool.constSlice()) |*a| alive += @intFromBool(a.livingFoe());
    return alive + (actor.MAX - pool.n);
}

/// Beyond this a turn's arithmetic on a body's clock, bleed or life overflows.
const BODY_MOST: i32 = std.math.maxInt(i32) / 2;

fn validateLevel(level: *const grid.Level, pool: *actor.Pool, ground: *ground_items.Ground) !void {
    if (pool.n > actor.MAX or ground.n > ground_items.GROUND_MAX or ground.coin_n > grid.CELLS or level.torch.n > grid.MAX_TORCHES) return error.Damaged;
    if (ground.n + deathsToCome(pool) > ground_items.GROUND_MAX) return error.Damaged;
    for (pool.slice(), 0..) |body, slot| {
        if (!grid.Level.inside(body.at) or body.max <= 0 or body.hp < 0 or body.hp > body.max) return error.Damaged;
        if (body.alive and (body.hp == 0 or level.who(body.at) != actor.Pool.idOf(slot))) return error.Damaged;
        if (body.chill.phase >= glacial.CYCLE or body.bleed.amount < 0 or body.bleed.move_bonus < 0) return error.Damaged;
        if (body.max > BODY_MOST or body.bleed.amount > BODY_MOST or body.bleed.move_bonus > BODY_MOST or body.clock.ticks < -BODY_MOST or body.clock.ticks > BODY_MOST) return error.Damaged;
        if (@as(i64, body.bleed.amount) * bleeding.MOVE_FACTOR + body.bleed.move_bonus > std.math.maxInt(i32)) return error.Damaged;
        if (body.sunder.stacks > sunder.MOST or (body.sunder.stacks == 0) != (body.sunder.turns == 0)) return error.Damaged;
        if (body.maim.limp and body.maim.turns == 0) return error.Damaged;
        if (body.tactics.guard > progress.RANKS or body.tactics.steady > progress.RANKS) return error.Damaged;
        if (body.bolt) |b| {
            const hu = actor.row(body.kind).hurls orelse return error.Damaged;
            if (!b.valid(hu.range)) return error.Damaged;
        }
    }
    for (level.occupant, 0..) |id, index| {
        if (id == grid.NO_ONE) continue;
        const body = pool.getConst(id) orelse return error.Damaged;
        if (!body.at.eq(grid.Level.of(index))) return error.Damaged;
    }
    for (level.torches()) |at| if (!grid.Level.inside(at)) return error.Damaged;
    for (level.caltrops) |patch| if (patch.turns != 0 and (patch.rank == 0 or patch.rank > progress.RANKS)) return error.Damaged;
    for (ground.drops[0..ground.n]) |*drop| {
        if (!grid.Level.inside(drop.at) or drop.source > pool.n) return error.Damaged;
        drop.item.mend();
    }
    for (ground.coins[0..ground.coin_n]) |coins| if (!grid.Level.inside(coins.at) or coins.amount <= 0) return error.Damaged;
    for (ground.supplies[0..ground.supply_n]) |s| if (!grid.Level.inside(s.at) or s.source > pool.n) return error.Damaged;
}

fn validateLog(history: *const log.Log) !void {
    if (history.n > log.Log.LINES or history.head >= log.Log.LINES or history.held > history.n) return error.Damaged;
    for (&history.lines) |*line| if (line.n >= log.Log.COLS or line.buf[line.n] != 0) return error.Damaged;
}

pub const TestRecord = struct {
    pub fn change(out: *std.ArrayList(u8), bytes: []const u8, path: []const []const u8, replacement: ?[]const u8) !void {
        var cursor = wire.Cursor{ .bytes = bytes };
        var record = try wire.Record.init(&cursor);
        try wire.integer(out, wire.FieldCount, record.remaining - @as(wire.FieldCount, @intFromBool(path.len == 1 and replacement == null)));
        var found = false;
        while (try record.next()) |entry| {
            const matches = std.mem.eql(u8, entry.name, path[0]);
            if (matches) found = true;
            if (matches and path.len == 1 and replacement == null) continue;
            const size_at = try wire.beginField(out, entry.name);
            if (matches and path.len > 1) {
                try change(out, entry.bytes, path[1..], replacement);
            } else try out.appendSlice(if (matches) replacement.? else entry.bytes);
            wire.endField(out, size_at);
        }
        try std.testing.expect(found and cursor.bytes.len == 0);
    }

    fn file(out: *std.ArrayList(u8), bytes: []const u8, path: []const []const u8, replacement: ?[]const u8) !void {
        out.clearRetainingCapacity();
        try store.begin(out.writer(), MAGIC, VERSION);
        try change(out, try store.open(bytes, MAGIC, VERSION), path, replacement);
        try out.ensureUnusedCapacity(store.SUM);
        seal(out);
    }
};

pub fn seal(out: *std.ArrayList(u8)) void {
    store.sealReserved(out, store.head(MAGIC));
}

pub fn sealed(g: *game.Game, out: *std.ArrayList(u8)) !void {
    out.clearRetainingCapacity();
    try write(g, out);
    seal(out);
}

/// The live run and the map a refused read would have loaded into, as they stood before it.
pub const Untouched = struct {
    g: *game.Game,
    map: *const data.Map,
    map_hash: u64,
    before: std.ArrayList(u8),
    after: std.ArrayList(u8),

    pub fn init(alloc: std.mem.Allocator, g: *game.Game, map: *const data.Map) !Untouched {
        var self = Untouched{ .g = g, .map = map, .map_hash = store.sum(std.mem.asBytes(map)), .before = .init(alloc), .after = .init(alloc) };
        errdefer self.deinit();
        try sealed(g, &self.before);
        return self;
    }

    pub fn deinit(self: *Untouched) void {
        self.before.deinit();
        self.after.deinit();
    }

    pub fn expectKept(self: *Untouched) !void {
        try std.testing.expectEqual(self.map_hash, store.sum(std.mem.asBytes(self.map)));
        try sealed(self.g, &self.after);
        try std.testing.expectEqualSlices(u8, self.before.items, self.after.items);
    }
};

test "portable save parsing defaults optional fields for every class and retains essential state" {
    const alloc = std.testing.allocator;
    const source = try game.boot(alloc);
    defer game.shut(alloc, source);
    const target = try game.boot(alloc);
    defer game.shut(alloc, target);
    const map = try alloc.create(data.Map);
    defer alloc.destroy(map);
    var original = std.ArrayList(u8).init(alloc);
    defer original.deinit();
    var changed = std.ArrayList(u8).init(alloc);
    defer changed.deinit();
    const omitted = [_][]const u8{ "bar", "mana", "flasks", "cooldown", "mana_recovery", "facing", "log" };
    for (hero.CLASSES) |class| {
        source.sim.class = class;
        game.begin(source, 59);
        source.sim.name = hero.Name.of("Recovered");
        source.sim.gold = 73;
        _ = source.sim.growth.gain(100);
        try std.testing.expect(source.sim.inventory.add(.{ .kind = .sword }));
        try sealed(source, &original);
        try TestRecord.file(&changed, original.items, &.{ "run", "growth", "ranks" }, null);
        std.mem.swap(std.ArrayList(u8), &original, &changed);
        for (omitted) |field| {
            try TestRecord.file(&changed, original.items, &.{ "run", field }, null);
            std.mem.swap(std.ArrayList(u8), &original, &changed);
        }
        try read(original.items, target, map);
        try std.testing.expectEqual(class, target.sim.class);
        try std.testing.expectEqualDeep(source.sim.growth, target.sim.growth);
        try std.testing.expectEqualDeep(source.sim.rng, target.sim.rng);
        try std.testing.expectEqual(@as(i32, 73), target.sim.gold);
        try std.testing.expectEqual(item_bases.Kind.sword, target.sim.inventory.bag[0].kind);
        try std.testing.expectEqualDeep(source.sim.growth.bar(class), target.bar);
        try std.testing.expectEqual(@as(i32, 0), target.sim.mana);
        try std.testing.expectEqual(@as(usize, 0), target.sim.log.n);
        try std.testing.expectEqual(@as(i32, 0), target.sim.mana_recovery);
        for (target.sim.flasks.values) |bottle| try std.testing.expectEqual(flask.Flask{}, bottle);
        for (target.sim.cooldown.values) |turns| try std.testing.expectEqual(@as(u8, 0), turns);
        try std.testing.expect(target.sim.unsaved);
    }
}

test "runs saved before flasks were items gain both, while a current run keeps a flask taken off" {
    const alloc = std.testing.allocator;
    const source = try game.boot(alloc);
    defer game.shut(alloc, source);
    const target = try game.boot(alloc);
    defer game.shut(alloc, target);
    const map = try alloc.create(data.Map);
    defer alloc.destroy(map);
    var bytes = std.ArrayList(u8).init(alloc);
    defer bytes.deinit();
    var stripped = std.ArrayList(u8).init(alloc);
    defer stripped.deinit();
    game.begin(source, 41);
    try source.sim.inventory.unequip(.life_flask, source.sim.growth.attributes(source.sim.class));
    try sealed(source, &bytes);
    try read(bytes.items, target, map);
    try std.testing.expect(!target.sim.inventory.gear.holds(.life) and target.sim.inventory.gear.holds(.mana));
    try std.testing.expectEqual(item_bases.Kind.life_flask, target.sim.inventory.bag[0].kind);
    source.sim.inventory = .{};
    try sealed(source, &bytes);
    try TestRecord.file(&stripped, bytes.items, &.{ "run", "inventory", "gear", "slots", "life_flask" }, null);
    try TestRecord.file(&bytes, stripped.items, &.{ "run", "inventory", "gear", "slots", "mana_flask" }, null);
    store.stamp(bytes.items, MAGIC, FLASKLESS);
    try read(bytes.items, target, map);
    for (std.enums.values(flask.Kind)) |k| try std.testing.expect(target.sim.inventory.gear.holds(k));
    store.stamp(bytes.items, MAGIC, VERSION);
    try read(bytes.items, target, map);
    for (std.enums.values(flask.Kind)) |k| try std.testing.expect(!target.sim.inventory.gear.holds(k));
}

test "a run's climate locations load as they were worked out on entry, and a run saved before them takes its level's" {
    const alloc = std.testing.allocator;
    const source = try game.boot(alloc);
    defer game.shut(alloc, source);
    const target = try game.boot(alloc);
    defer game.shut(alloc, target);
    const map = try alloc.create(data.Map);
    defer alloc.destroy(map);
    var bytes = std.ArrayList(u8).init(alloc);
    defer bytes.deinit();
    game.begin(source, 47);
    const i = grid.Level.idx(source.sim.heroActor().?.at);
    const entered = source.sim.locations[i];
    source.sim.locations[i] = if (entered == .forest) .inland else .forest;
    try sealed(source, &bytes);
    try read(bytes.items, target, map);
    try std.testing.expectEqualSlices(climate.Location, &source.sim.locations, &target.sim.locations);
    store.stamp(bytes.items, MAGIC, PLACELESS);
    try read(bytes.items, target, map);
    try std.testing.expectEqual(entered, target.sim.locations[i]);
}

test "runs saved before class arms gain them where the hands fit, while a current run keeps them taken off" {
    const alloc = std.testing.allocator;
    const source = try game.boot(alloc);
    defer game.shut(alloc, source);
    const target = try game.boot(alloc);
    defer game.shut(alloc, target);
    const map = try alloc.create(data.Map);
    defer alloc.destroy(map);
    var bytes = std.ArrayList(u8).init(alloc);
    defer bytes.deinit();
    for (hero.CLASSES) |class| {
        source.sim.class = class;
        game.begin(source, 43);
        for (HANDS) |slot| source.sim.inventory.gear.slots.set(slot, null);
        try sealed(source, &bytes);
        try read(bytes.items, target, map);
        try std.testing.expectEqualDeep(source.sim.inventory.gear, target.sim.inventory.gear);
        for (LEGACY) |version| {
            store.stamp(bytes.items, MAGIC, version);
            try read(bytes.items, target, map);
            try std.testing.expectEqualDeep(@import("play/gear.zig").Gear.startFor(class).slots, target.sim.inventory.gear.slots);
        }
    }
    source.sim.class = .knight;
    game.begin(source, 43);
    source.sim.inventory.gear.slots.set(.right_hand, .{ .kind = .greatsword });
    source.sim.inventory.gear.slots.set(.left_hand, null);
    try sealed(source, &bytes);
    store.stamp(bytes.items, MAGIC, UNARMED);
    try read(bytes.items, target, map);
    try std.testing.expectEqual(item_bases.Kind.greatsword, target.sim.inventory.gear.slots.get(.right_hand).?.kind);
    try std.testing.expectEqual(@as(?items.Item, null), target.sim.inventory.gear.slots.get(.left_hand));
    game.begin(source, 43);
    const shield = source.sim.inventory.gear.slots.get(.left_hand).?;
    source.sim.inventory.bag[0] = shield;
    source.sim.inventory.n = 1;
    for (HANDS) |slot| source.sim.inventory.gear.slots.set(slot, null);
    try sealed(source, &bytes);
    store.stamp(bytes.items, MAGIC, UNARMED);
    try read(bytes.items, target, map);
    try std.testing.expectEqual(@as(?items.Item, null), target.sim.inventory.gear.slots.get(.left_hand));
    try std.testing.expectEqual(@as(?items.Item, null), target.sim.inventory.gear.slots.get(.right_hand));
}

test "a body whose clock, bleed or life would overflow a turn's arithmetic is damaged" {
    const alloc = std.testing.allocator;
    const run = try game.boot(alloc);
    defer game.shut(alloc, run);
    game.begin(run, 37);
    try validateLevel(&run.sim.lv, &run.sim.pool, &run.sim.ground);
    const h = run.sim.heroActor().?;
    const saved = h.*;
    for (0..5) |case| {
        h.* = saved;
        switch (case) {
            0 => h.clock.ticks = std.math.minInt(i32),
            1 => h.bleed.amount = std.math.maxInt(i32),
            2 => h.bleed.move_bonus = -1,
            3 => {
                h.bleed.amount = BODY_MOST;
                h.bleed.move_bonus = 2;
            },
            else => {
                h.max = std.math.maxInt(i32);
                h.hp = h.max;
            },
        }
        try std.testing.expectError(error.Damaged, validateLevel(&run.sim.lv, &run.sim.pool, &run.sim.ground));
    }
    h.* = saved;
}

test "portable saves reject tactical ranks beyond the supported skills before applying them" {
    const alloc = std.testing.allocator;
    const run = try game.boot(alloc);
    defer game.shut(alloc, run);
    game.harness.arena(run, .{ .x = 20, .y = 20 }, &.{});
    const id = game.harness.spawnAt(run, .skeleton, .{ .x = 21, .y = 20 }, true);
    const snapshot = try alloc.create(Snapshot);
    defer alloc.destroy(snapshot);
    try capture(run, snapshot);
    const into = try alloc.create(data.Map);
    defer alloc.destroy(into);
    into.* = .{};
    var bytes = std.ArrayList(u8).init(alloc);
    defer bytes.deinit();
    const body = &snapshot.run.pool.items[actor.Pool.slot(id)];
    inline for (.{ "guard", "steady" }) |field| {
        @field(body.tactics, field) = progress.RANKS;
        try validate(snapshot);
        @field(body.tactics, field) = 255;
        bytes.clearRetainingCapacity();
        try writeSnapshot(snapshot, &bytes);
        seal(&bytes);
        try std.testing.expectError(error.Damaged, read(bytes.items, run, into));
        try std.testing.expectEqual(@as(u8, 0), @field(run.sim.pool.get(id).?.tactics, field));
        try std.testing.expectEqual(@as(usize, 0), into.node_n);
        @field(body.tactics, field) = 0;
    }
}

test "a loaded modifier below its roll is raised to the least its roll gives, carried or lying" {
    const alloc = std.testing.allocator;
    const run = try game.boot(alloc);
    defer game.shut(alloc, run);
    game.begin(run, 37);
    var it = items.Item{ .kind = .sword };
    it.mods[0] = .{ .kind = .imbue, .value = -5, .element = .cold };
    it.mods[1] = .{ .kind = .mana_on_kill, .value = -3 };
    try std.testing.expect(run.sim.inventory.add(it));
    try std.testing.expect(run.sim.ground.add(.{ .item = it, .at = run.sim.heroActor().?.at }));
    try validateLevel(&run.sim.lv, &run.sim.pool, &run.sim.ground);
    run.sim.inventory.mend();
    for ([_]items.Item{ run.sim.inventory.bag[run.sim.inventory.n - 1], run.sim.ground.drops[run.sim.ground.n - 1].item }) |got| {
        try std.testing.expectEqual(@as(i32, 10), got.value(.imbue));
        try std.testing.expectEqual(@as(i32, 1), got.value(.mana_on_kill));
    }
}

test "portable save corruption and missing required state leave the live game and map unchanged" {
    const alloc = std.testing.allocator;
    const current = try game.boot(alloc);
    defer game.shut(alloc, current);
    game.begin(current, 37);
    const map = try alloc.create(data.Map);
    defer alloc.destroy(map);
    map.* = .{};
    var kept = try Untouched.init(alloc, current, map);
    defer kept.deinit();
    const original = &kept.before;
    var changed = std.ArrayList(u8).init(alloc);
    defer changed.deinit();
    var replacement = std.ArrayList(u8).init(alloc);
    defer replacement.deinit();
    const Case = enum { missing_hero, missing_rng, bad_hero, bad_count, bad_name, bad_log, overflow, bad_occupant };
    for (std.enums.values(Case)) |case| {
        replacement.clearRetainingCapacity();
        const path: []const []const u8 = switch (case) {
            .missing_hero, .bad_hero, .overflow => &.{ "run", "hero" },
            .missing_rng => &.{ "run", "rng" },
            .bad_count => &.{ "run", "pool", "n" },
            .bad_name => &.{ "run", "name", "n" },
            .bad_log => &.{ "run", "log", "head" },
            .bad_occupant => &.{ "run", "lv", "occupant" },
        };
        switch (case) {
            .missing_hero, .missing_rng => {},
            .bad_hero => try Code.write(&replacement, @as(u16, 0)),
            .bad_count => try Code.write(&replacement, @as(usize, actor.MAX + 1)),
            .bad_name => try Code.write(&replacement, @as(u8, 255)),
            .bad_log => try Code.write(&replacement, @as(usize, log.Log.LINES)),
            .overflow => try Code.write(&replacement, @as(u64, std.math.maxInt(u64))),
            .bad_occupant => {
                var occupants = current.sim.lv.occupant;
                occupants[grid.Level.idx(current.sim.heroActor().?.at)] = actor.MAX + 1;
                try Code.write(&replacement, &occupants);
            },
        }
        const missing = case == .missing_hero or case == .missing_rng;
        try TestRecord.file(&changed, original.items, path, if (missing) null else replacement.items);
        const expected = if (missing) error.Short else error.Damaged;
        try std.testing.expectError(expected, peek(changed.items));
        try std.testing.expectError(expected, read(changed.items, current, map));
        try kept.expectKept();
    }
}
