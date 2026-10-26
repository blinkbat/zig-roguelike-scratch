const std = @import("std");
const wire = @import("core/wire.zig");
const store = @import("core/store.zig");
const data = @import("save_data.zig");
const game = @import("game.zig");
const grid = @import("map/grid.zig");
const atlas = @import("map/atlas.zig");
const actor = @import("play/actor.zig");
const items = @import("play/items.zig");
const hero = @import("play/hero.zig");
const progress = @import("play/progress.zig");
const log = @import("play/log.zig");
const skillbar = @import("play/skillbar.zig");
const flask = @import("play/flask.zig");
const day = @import("map/day.zig");

pub const MAGIC = "cistern-save\n";
pub const VERSION: u64 = 1;
const Code = wire.Codec(Policy);
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
};

fn references(comptime T: type) type {
    const original = std.meta.fields(T);
    var fields: [original.len]std.builtin.Type.StructField = undefined;
    for (original, 0..) |field, i| {
        const Pointer = *const field.type;
        fields[i] = .{ .name = field.name, .type = Pointer, .default_value_ptr = null, .is_comptime = false, .alignment = @alignOf(Pointer) };
    }
    return @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
}

pub fn write(g: *game.Game, out: *std.ArrayList(u8)) !void {
    std.debug.assert(out.items.len == 0);
    var visits: [atlas.MAX_NODES]?*const data.Visit = @splat(null);
    var visited = g.sim.visited.iterator(.{});
    while (visited.next()) |node| visits[node] = &g.sim.visits[node];
    var run: references(data.Tail) = undefined;
    inline for (data.TAIL_FIELDS) |field| @field(run, field[1]) = &@field(data.part(g, field[0]), field[1]);
    const body = g.sim.heroActor() orelse return error.Damaged;
    var summary = data.Summary{ .name = g.sim.name, .hp = body.hp, .max = body.max, .gold = g.sim.gold, .node = null };
    if (g.sim.map) |map| {
        summary.node = g.sim.node;
        summary.place = map.node[g.sim.node].label;
    }
    try store.begin(out.writer(), MAGIC, VERSION);
    try Code.write(out, .{ .summary = summary, .seed = g.sim.seed, .map = g.sim.map, .node = g.sim.node, .visits = &visits, .run = &run });
    try out.ensureUnusedCapacity(store.SUM);
}

pub fn capture(g: *game.Game, snapshot: *Snapshot) !void {
    const body = g.sim.heroActor() orelse return error.Damaged;
    snapshot.summary = .{ .name = g.sim.name, .hp = body.hp, .max = body.max, .gold = g.sim.gold, .node = null };
    snapshot.seed = g.sim.seed;
    snapshot.node = g.sim.node;
    snapshot.map = null;
    if (g.sim.map) |map| {
        snapshot.map = map.*;
        snapshot.summary.node = g.sim.node;
        snapshot.summary.place = map.node[g.sim.node].label;
    }
    for (&snapshot.visits, 0..) |*visit, node| {
        visit.* = null;
        if (g.sim.visited.isSet(node)) visit.* = g.sim.visits[node];
    }
    inline for (data.TAIL_FIELDS) |field| @field(snapshot.run, field[1]) = @field(data.part(g, field[0]), field[1]);
}

pub fn writeSnapshot(snapshot: *const Snapshot, out: *std.ArrayList(u8)) !void {
    std.debug.assert(out.items.len == 0);
    var visits: [atlas.MAX_NODES]?*const data.Visit = @splat(null);
    for (&snapshot.visits, 0..) |*visit, node| if (visit.*) |*loaded| {
        visits[node] = loaded;
    };
    var run: references(data.Tail) = undefined;
    inline for (std.meta.fields(data.Tail)) |field| @field(run, field.name) = &@field(snapshot.run, field.name);
    const map: ?*const data.Map = if (snapshot.map) |*loaded| loaded else null;
    try store.begin(out.writer(), MAGIC, VERSION);
    try Code.write(out, .{ .summary = &snapshot.summary, .seed = snapshot.seed, .map = map, .node = snapshot.node, .visits = &visits, .run = &run });
    try out.ensureUnusedCapacity(store.SUM);
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
    source.sim.visits[0] = .{ .lv = source.sim.lv, .pool = source.sim.pool, .ground = source.sim.ground, .facing = source.pic.facing };
    source.sim.visited.set(0);
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
    std.debug.print("portable autosave: current run, map, visited actors and terrain frozen independently for worker encoding\n", .{});
}

fn parse(bytes: []const u8) !*Snapshot {
    const body = store.open(bytes, MAGIC, VERSION) catch |err| return switch (err) {
        error.Foreign => error.NotASave,
        else => err,
    };
    const snapshot = try std.heap.page_allocator.create(Snapshot);
    errdefer std.heap.page_allocator.destroy(snapshot);
    try Code.read(body, snapshot);
    try validate(snapshot);
    return snapshot;
}

pub fn peek(bytes: []const u8) !data.Summary {
    const snapshot = try parse(bytes);
    defer std.heap.page_allocator.destroy(snapshot);
    return snapshot.summary;
}

pub fn read(bytes: []const u8, g: *game.Game, map: *data.Map) !void {
    const snapshot = try parse(bytes);
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
    inline for (data.TAIL_FIELDS) |field| @field(data.part(g, field[0]), field[1]) = @field(snapshot.run, field[1]);
    game.resumeRun(g);
    g.sim.unsaved = true;
}

pub fn validate(snapshot: *Snapshot) !void {
    const run = &snapshot.run;
    if (!run.name.valid() or run.hero == 0 or run.hero > run.pool.n) return error.Damaged;
    const body = &run.pool.items[actor.Pool.slot(run.hero)];
    if (!body.alive or body.kind != run.class.kind()) return error.Damaged;
    if (run.gold < 0 or run.mana < 0 or run.growth.level == 0) return error.Damaged;
    if (run.growth.xp >= run.growth.needed()) return error.Damaged;
    run.clock = day.Clock.at(run.clock.hour());
    run.mana_recovery = @mod(run.mana_recovery, hero.MANA_REGEN_TURNS);
    Policy.restoreStart(&run.growth, run.class);
    for (skillbar.ACTS) |act| {
        const rank = run.growth.ranks.get(act);
        const limit = progress.rankLimit(act);
        if (rank > limit) {
            run.growth.active_points +|= rank - limit;
            run.growth.ranks.set(act, limit);
        }
    }
    for (&run.flasks.values) |*bottle| {
        bottle.charges = @min(bottle.charges, flask.CHARGES);
        bottle.turns = @min(bottle.turns, flask.TURNS);
        if (bottle.left < 0) return error.Damaged;
        if (bottle.turns == 0) bottle.left = 0;
    }
    run.log.scroll = @min(run.log.scroll, run.log.n -| 1);
    try validateLevel(&run.lv, &run.pool, &run.ground);
    try validateLog(&run.log);
    if (snapshot.map) |*map| {
        if (map.node_n == 0 or map.node_n > atlas.MAX_NODES or snapshot.node >= map.node_n) return error.Damaged;
        if (map.start.node >= map.node_n or !grid.Level.inside(map.start.at)) return error.Damaged;
        try validateDoors(&run.lv, &map.node[snapshot.node]);
        for (map.nodes(), 0..) |*node, index| {
            if (!node.label.valid()) return error.Damaged;
            for (node.doors(), 0..) |door, door_index| {
                if (!grid.Level.inside(door.at)) return error.Damaged;
                if (door.to) |target| {
                    if (target.node >= map.node_n or target.door >= map.node[target.node].door_n) return error.Damaged;
                    const reverse = map.node[target.node].door[target.door].to orelse return error.Damaged;
                    if (reverse.node != index or reverse.door != door_index) return error.Damaged;
                }
            }
            switch (node.plan) {
                .procgen => |*plan| plan.* = plan.fit(),
                .bespoke => |*plan| for (plan.foes()) |foe| {
                    if (!foe.kind.foe() or !grid.Level.inside(foe.at)) return error.Damaged;
                },
            }
        }
        for (&snapshot.visits, 0..) |*visit, node| {
            if (visit.*) |*loaded| {
                if (node >= map.node_n) return error.Damaged;
                try validateLevel(&loaded.lv, &loaded.pool, &loaded.ground);
                try validateDoors(&loaded.lv, &map.node[node]);
            }
        }
    } else {
        if (snapshot.node != 0) return error.Damaged;
        for (&snapshot.visits) |*visit| if (visit.* != null) return error.Damaged;
        try validateDoors(&run.lv, null);
    }
    if (!snapshot.summary.name.valid() or !snapshot.summary.place.valid()) return error.Damaged;
    if (snapshot.summary.node != (if (snapshot.map != null) @as(?usize, snapshot.node) else null)) return error.Damaged;
    if (!std.mem.eql(u8, snapshot.summary.name.text(), run.name.text())) return error.Damaged;
    if (snapshot.summary.hp != body.hp or snapshot.summary.max != body.max or snapshot.summary.gold != run.gold) return error.Damaged;
}

fn validateDoors(level: *const grid.Level, node: ?*const atlas.Node) !void {
    for (level.door, 0..) |door, cell| {
        if (door == grid.NO_DOOR) continue;
        const owner = node orelse return error.Damaged;
        if (door > owner.door_n or !owner.door[door - 1].at.eq(grid.Level.of(cell))) return error.Damaged;
    }
}

fn validateLevel(level: *const grid.Level, pool: *actor.Pool, ground: *const items.Ground) !void {
    if (pool.n > actor.MAX or ground.n > items.GROUND_MAX or ground.coin_n > grid.CELLS or level.torch.n > grid.MAX_TORCHES) return error.Damaged;
    for (pool.slice(), 0..) |body, slot| {
        if (!grid.Level.inside(body.at) or body.max <= 0 or body.hp < 0 or body.hp > body.max) return error.Damaged;
        if (body.alive and (body.hp == 0 or level.who(body.at) != actor.Pool.idOf(slot))) return error.Damaged;
        if (body.chill.phase > 2 or body.bleed.amount < 0) return error.Damaged;
    }
    for (level.occupant, 0..) |id, index| {
        if (id == grid.NO_ONE) continue;
        if (id > pool.n) return error.Damaged;
        const body = pool.items[actor.Pool.slot(id)];
        if (!body.alive or !body.at.eq(grid.Level.of(index))) return error.Damaged;
    }
    for (level.torches()) |at| if (!grid.Level.inside(at)) return error.Damaged;
    for (level.caltrops) |patch| if (patch.turns != 0 and (patch.rank == 0 or patch.rank > progress.RANKS)) return error.Damaged;
    for (ground.drops[0..ground.n]) |drop| if (!grid.Level.inside(drop.at) or drop.source > pool.n) return error.Damaged;
    for (ground.coins[0..ground.coin_n]) |coins| if (!grid.Level.inside(coins.at) or coins.amount <= 0) return error.Damaged;
}

fn validateLog(history: *const log.Log) !void {
    if (history.n > log.Log.LINES or history.head >= log.Log.LINES or history.held > history.n) return error.Damaged;
    for (&history.lines) |*line| if (line.n >= log.Log.COLS or line.buf[line.n] != 0) return error.Damaged;
}

const TestRecord = struct {
    fn change(out: *std.ArrayList(u8), bytes: []const u8, path: []const []const u8, replacement: ?[]const u8) !void {
        var cursor = wire.Cursor{ .bytes = bytes };
        var record = try wire.Record.init(&cursor);
        try wire.integer(out, u16, record.remaining - @as(u16, @intFromBool(path.len == 1 and replacement == null)));
        var found = false;
        while (try record.next()) |entry| {
            const matches = std.mem.eql(u8, entry.name, path[0]);
            if (matches) found = true;
            if (matches and path.len == 1 and replacement == null) continue;
            try wire.integer(out, u16, @intCast(entry.name.len));
            try out.appendSlice(entry.name);
            const size_at = out.items.len;
            try wire.integer(out, u32, 0);
            if (matches and path.len > 1) {
                try change(out, entry.bytes, path[1..], replacement);
            } else try out.appendSlice(if (matches) replacement.? else entry.bytes);
            std.mem.writeInt(u32, out.items[size_at..][0..4], @intCast(out.items.len - size_at - 4), .little);
        }
        try std.testing.expect(found and cursor.bytes.len == 0);
    }

    fn file(out: *std.ArrayList(u8), bytes: []const u8, path: []const []const u8, replacement: ?[]const u8) !void {
        out.clearRetainingCapacity();
        try store.begin(out.writer(), MAGIC, VERSION);
        try change(out, try store.open(bytes, MAGIC, VERSION), path, replacement);
        try store.seal(out.writer(), out.items[store.head(MAGIC)..]);
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
        original.clearRetainingCapacity();
        try write(source, &original);
        try store.seal(original.writer(), original.items[store.head(MAGIC)..]);
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
        try std.testing.expectEqual(items.Kind.sword, target.sim.inventory.bag[0].kind);
        try std.testing.expectEqualDeep(source.sim.growth.bar(class), target.bar);
        try std.testing.expectEqual(@as(i32, 0), target.sim.mana);
        try std.testing.expectEqual(@as(usize, 0), target.sim.log.n);
        try std.testing.expectEqual(@as(i32, 0), target.sim.mana_recovery);
        for (target.sim.flasks.values) |bottle| try std.testing.expectEqual(flask.Flask{}, bottle);
        for (target.sim.cooldown.values) |turns| try std.testing.expectEqual(@as(u8, 0), turns);
        try std.testing.expect(target.sim.unsaved);
    }
    std.debug.print("portable saves: 7 absent run fields and initial skill ranks default across 3 classes; name, gold, gear, progress and RNG retained\n", .{});
}

test "portable save corruption and missing required state leave the live game and map unchanged" {
    const alloc = std.testing.allocator;
    const current = try game.boot(alloc);
    defer game.shut(alloc, current);
    game.begin(current, 37);
    const map = try alloc.create(data.Map);
    defer alloc.destroy(map);
    map.* = .{};
    const map_hash = store.sum(std.mem.asBytes(map));
    var original = std.ArrayList(u8).init(alloc);
    defer original.deinit();
    try write(current, &original);
    try store.seal(original.writer(), original.items[store.head(MAGIC)..]);
    var changed = std.ArrayList(u8).init(alloc);
    defer changed.deinit();
    var after = std.ArrayList(u8).init(alloc);
    defer after.deinit();
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
        try std.testing.expectEqual(map_hash, store.sum(std.mem.asBytes(map)));
        after.clearRetainingCapacity();
        try write(current, &after);
        try store.seal(after.writer(), after.items[store.head(MAGIC)..]);
        try std.testing.expectEqualSlices(u8, original.items, after.items);
    }
    std.debug.print("portable saves: 8 checksummed semantic corruptions refused by listing and loading; complete run and map unchanged\n", .{});
}
