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
const consumable = @import("play/consumable.zig");
const sunder = @import("play/sunder.zig");
const glacial = @import("play/glacial.zig");
const day = @import("map/day.zig");

pub const MAGIC = "cistern-save\n";
pub const VERSION: u64 = 2;
/// Runs saved before flasks were worn as items.
const FLASKLESS: u64 = 1;
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

/// `Snapshot` as the file holds it, each field by reference.
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
    var visits: [atlas.MAX_NODES]?*const data.Visit = @splat(null);
    var visited = g.sim.visited.iterator(.{});
    while (visited.next()) |node| visits[node] = &g.sim.visits[node];
    var run: references(data.Tail) = undefined;
    inline for (data.TAIL_FIELDS) |field| @field(run, field[1]) = &@field(data.part(g, field[0]), field[1]);
    var portable: references(data.Portable) = undefined;
    inline for (data.PORTABLE_FIELDS) |field| @field(portable, field[1]) = &@field(data.part(g, field[0]), field[1]);
    const summary = data.Summary.of(g) orelse return error.Damaged;
    try encode(out, .{ .summary = &summary, .seed = g.sim.seed, .map = g.sim.map, .node = g.sim.node, .visits = &visits, .run = &run, .portable = &portable });
}

pub fn capture(g: *game.Game, snapshot: *Snapshot) !void {
    snapshot.summary = data.Summary.of(g) orelse return error.Damaged;
    snapshot.seed = g.sim.seed;
    snapshot.node = g.sim.node;
    snapshot.map = null;
    if (g.sim.map) |map| snapshot.map = map.*;
    for (&snapshot.visits, 0..) |*visit, node| {
        visit.* = null;
        if (g.sim.visited.isSet(node)) visit.* = g.sim.visits[node];
    }
    inline for (data.TAIL_FIELDS) |field| @field(snapshot.run, field[1]) = @field(data.part(g, field[0]), field[1]);
    inline for (data.PORTABLE_FIELDS) |field| @field(snapshot.portable, field[1]) = @field(data.part(g, field[0]), field[1]);
}

pub fn writeSnapshot(snapshot: *const Snapshot, out: *std.ArrayList(u8)) !void {
    var visits: [atlas.MAX_NODES]?*const data.Visit = @splat(null);
    for (&snapshot.visits, 0..) |*visit, node| if (visit.*) |*loaded| {
        visits[node] = loaded;
    };
    var run: references(data.Tail) = undefined;
    inline for (std.meta.fields(data.Tail)) |field| @field(run, field.name) = &@field(snapshot.run, field.name);
    var portable: references(data.Portable) = undefined;
    inline for (std.meta.fields(data.Portable)) |field| @field(portable, field.name) = &@field(snapshot.portable, field.name);
    const map: ?*const data.Map = if (snapshot.map) |*loaded| loaded else null;
    try encode(out, .{ .summary = &snapshot.summary, .seed = snapshot.seed, .map = map, .node = snapshot.node, .visits = &visits, .run = &run, .portable = &portable });
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

pub const OpenError = error{ NotASave, OtherBuild, Short, Damaged };

/// `store.open`, a file of another kind being no save.
pub fn open(bytes: []const u8, magic: []const u8, print: u64) OpenError![]const u8 {
    return store.open(bytes, magic, print) catch |err| switch (err) {
        error.Foreign => error.NotASave,
        else => |other| other,
    };
}

fn opened(bytes: []const u8) !struct { body: []const u8, version: u64 } {
    for ([_]u64{ VERSION, FLASKLESS }) |version| {
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
    if (file.version == FLASKLESS) snapshot.run.inventory.gear.wearFlasks();
    try validate(snapshot);
    return snapshot;
}

fn peek(bytes: []const u8) !data.Summary {
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
    inline for (data.PORTABLE_FIELDS) |field| @field(data.part(g, field[0]), field[1]) = @field(snapshot.portable, field[1]);
    game.resumeRun(g);
    g.sim.unsaved = true;
}

pub fn validate(snapshot: *Snapshot) !void {
    const run = &snapshot.run;
    if (!run.rng.valid() or !run.loot_rng.valid()) return error.Damaged;
    if (!run.name.valid() or !holdsHero(&run.pool, run.hero, run.class.kind())) return error.Damaged;
    const body = &run.pool.items[actor.Pool.slot(run.hero)];
    if (run.bar.modifier) |m| if (std.mem.indexOfScalar(@TypeOf(m), &skillbar.SLOTS, m) == null) {
        run.bar.modifier = null;
    };
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
    for (&run.inventory.stacks.values) |*carried| carried.* = @min(carried.*, consumable.STACK_MAX);
    if (run.inventory.n > items.BAG_MAX) return error.Damaged;
    run.inventory.mend();
    run.log.scroll = @min(run.log.scroll, run.log.n -| 1);
    try validateLevel(&run.lv, &run.pool, &run.ground);
    try validateLog(&run.log);
    if (snapshot.map) |*map| {
        if (!atlas.holdsNodes(map.node_n, snapshot.node)) return error.Damaged;
        if (map.start.node >= map.node_n or !grid.Level.inside(map.start.at)) return error.Damaged;
        if (!map.linksValid()) return error.Damaged;
        try validateDoors(&run.lv, &map.node[snapshot.node]);
        for (map.nodes()) |*node| {
            if (!node.label.valid()) return error.Damaged;
            for (node.doors()) |door| {
                if (!grid.Level.inside(door.at)) return error.Damaged;
            }
            switch (node.plan) {
                .procgen => |*plan| plan.* = plan.fit(),
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
                if (node >= map.node_n or !holdsHero(&loaded.pool, run.hero, run.class.kind())) return error.Damaged;
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
    if (!snapshot.summary.name.valid() or !snapshot.summary.place.valid()) return error.Damaged;
    if (snapshot.summary.node != (if (snapshot.map != null) @as(?usize, snapshot.node) else null)) return error.Damaged;
    if (snapshot.map) |*map| if (!std.mem.eql(u8, snapshot.summary.place.text(), map.node[snapshot.node].label.text())) return error.Damaged;
    if (!std.mem.eql(u8, snapshot.summary.name.text(), run.name.text())) return error.Damaged;
    if (snapshot.summary.hp != body.hp or snapshot.summary.max != body.max or snapshot.summary.gold != run.gold) return error.Damaged;
}

/// The conversation it was in and the one it was waiting on name lines the map still has.
fn validatePlot(plot: *const @FieldType(data.Portable, "plot"), s: *const atlas.script.Script) !void {
    if (plot.asked) |d| if (d >= s.dialog_n) return error.Damaged;
    const talk = plot.talk orelse return;
    if (talk.dialog >= s.dialog_n or talk.line >= s.dialog[talk.dialog].line_n or talk.cursor >= atlas.script.MAX_CHOICES) return error.Damaged;
    if (talk.folk) |f| if (f >= s.folk_n) return error.Damaged;
}

fn validateDoors(level: *const grid.Level, node: ?*const atlas.Node) !void {
    for (level.door, 0..) |door, cell| {
        if (door == grid.NO_DOOR) continue;
        const owner = node orelse return error.Damaged;
        if (door > owner.door_n or !owner.door[door - 1].at.eq(grid.Level.of(cell))) return error.Damaged;
    }
}

fn holdsHero(pool: *const actor.Pool, id: u16, kind: actor.Kind) bool {
    if (id == 0 or id > pool.n) return false;
    const body = &pool.items[actor.Pool.slot(id)];
    return body.alive and body.kind == kind;
}

/// Every death still to come, of a body standing or one yet to split off, drops on the ground with room for it.
fn deathsToCome(pool: *const actor.Pool) usize {
    var alive: usize = 0;
    for (pool.items[0..pool.n]) |a| alive += @intFromBool(a.alive and a.foe());
    return alive + (actor.MAX - pool.n);
}

/// Beyond this a turn's arithmetic on a body's clock, bleed or life overflows.
const BODY_MOST: i32 = std.math.maxInt(i32) / 2;

fn validateLevel(level: *const grid.Level, pool: *actor.Pool, ground: *items.Ground) !void {
    if (pool.n > actor.MAX or ground.n > items.GROUND_MAX or ground.coin_n > grid.CELLS or level.torch.n > grid.MAX_TORCHES) return error.Damaged;
    if (ground.n + deathsToCome(pool) > items.GROUND_MAX) return error.Damaged;
    for (pool.slice(), 0..) |body, slot| {
        if (!grid.Level.inside(body.at) or body.max <= 0 or body.hp < 0 or body.hp > body.max) return error.Damaged;
        if (body.alive and (body.hp == 0 or level.who(body.at) != actor.Pool.idOf(slot))) return error.Damaged;
        if (body.chill.phase >= glacial.CYCLE or body.bleed.amount < 0) return error.Damaged;
        if (body.max > BODY_MOST or body.bleed.amount > BODY_MOST or body.clock.ticks < -BODY_MOST or body.clock.ticks > BODY_MOST) return error.Damaged;
        if (body.sunder.stacks > sunder.MOST or (body.sunder.stacks == 0) != (body.sunder.turns == 0)) return error.Damaged;
        if (body.maim.limp and body.maim.turns == 0) return error.Damaged;
    }
    for (level.occupant, 0..) |id, index| {
        if (id == grid.NO_ONE) continue;
        if (id > pool.n) return error.Damaged;
        const body = &pool.items[actor.Pool.slot(id)];
        if (!body.alive or !body.at.eq(grid.Level.of(index))) return error.Damaged;
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

const TestRecord = struct {
    fn change(out: *std.ArrayList(u8), bytes: []const u8, path: []const []const u8, replacement: ?[]const u8) !void {
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
        try seal(out);
    }

    fn seal(out: *std.ArrayList(u8)) !void {
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
        try TestRecord.seal(&original);
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
    std.debug.print("portable saves: {d} absent run fields and initial skill ranks default across {d} classes; name, gold, gear, progress and RNG retained\n", .{ omitted.len, hero.CLASSES.len });
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
    try write(source, &bytes);
    try TestRecord.seal(&bytes);
    try read(bytes.items, target, map);
    try std.testing.expect(!target.sim.inventory.gear.holds(.life) and target.sim.inventory.gear.holds(.mana));
    try std.testing.expectEqual(items.Kind.life_flask, target.sim.inventory.bag[0].kind);
    source.sim.inventory = .{};
    bytes.clearRetainingCapacity();
    try write(source, &bytes);
    try TestRecord.seal(&bytes);
    try TestRecord.file(&stripped, bytes.items, &.{ "run", "inventory", "gear", "slots", "life_flask" }, null);
    try TestRecord.file(&bytes, stripped.items, &.{ "run", "inventory", "gear", "slots", "mana_flask" }, null);
    std.mem.writeInt(u64, bytes.items[MAGIC.len..][0..@sizeOf(u64)], FLASKLESS, .little);
    try read(bytes.items, target, map);
    for (std.enums.values(flask.Kind)) |k| try std.testing.expect(target.sim.inventory.gear.holds(k));
    std.mem.writeInt(u64, bytes.items[MAGIC.len..][0..@sizeOf(u64)], VERSION, .little);
    try read(bytes.items, target, map);
    for (std.enums.values(flask.Kind)) |k| try std.testing.expect(!target.sim.inventory.gear.holds(k));
    std.debug.print("flask saves: version {d} runs gain both flasks; version {d} keeps an unequipped flask in the bag\n", .{ FLASKLESS, VERSION });
}

test "a body whose clock, bleed or life would overflow a turn's arithmetic is damaged" {
    const alloc = std.testing.allocator;
    const run = try game.boot(alloc);
    defer game.shut(alloc, run);
    game.begin(run, 37);
    try validateLevel(&run.sim.lv, &run.sim.pool, &run.sim.ground);
    const h = run.sim.heroActor().?;
    const saved = h.*;
    for (0..3) |case| {
        h.* = saved;
        switch (case) {
            0 => h.clock.ticks = std.math.minInt(i32),
            1 => h.bleed.amount = std.math.maxInt(i32),
            else => {
                h.max = std.math.maxInt(i32);
                h.hp = h.max;
            },
        }
        try std.testing.expectError(error.Damaged, validateLevel(&run.sim.lv, &run.sim.pool, &run.sim.ground));
    }
    h.* = saved;
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
    const map_hash = store.sum(std.mem.asBytes(map));
    var original = std.ArrayList(u8).init(alloc);
    defer original.deinit();
    try write(current, &original);
    try TestRecord.seal(&original);
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
        try TestRecord.seal(&after);
        try std.testing.expectEqualSlices(u8, original.items, after.items);
    }
    std.debug.print("portable saves: {d} checksummed semantic corruptions refused by listing and loading; complete run and map unchanged\n", .{std.enums.values(Case).len});
}
