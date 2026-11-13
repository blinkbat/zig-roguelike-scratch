const std = @import("std");
const progress = @import("play/progress.zig");
const passives = @import("play/passives.zig");
const mathx = @import("core/mathx.zig");
const wire = @import("core/wire.zig");
const data = @import("save_data.zig");
const script = @import("map/script.zig");
const actor = @import("play/actor.zig");

const SavedRng = struct {
    xoshiro256: [4]u64,

    const Live = mathx.Rng;

    fn of(rng: mathx.Rng) SavedRng {
        return .{ .xoshiro256 = rng.impl.s };
    }

    fn live(stored: SavedRng) wire.Error!mathx.Rng {
        const rng = mathx.Rng{ .impl = .{ .s = stored.xoshiro256 } };
        if (!rng.valid()) return error.Damaged;
        return rng;
    }
};

const SAVED = .{ SavedRng, SavedProgress, SavedNpc };
const Node = passives.Node;
const NodeKey = struct {
    arm: @FieldType(Node, "arm"),
    branch: @FieldType(Node, "branch") = null,
    seam: @FieldType(Node, "seam") = null,
    ring: u8,
    slot: u8 = 0,

    fn of(node: Node) NodeKey {
        return .{ .arm = node.arm, .branch = node.branch, .seam = node.seam, .ring = node.ring, .slot = node.slot };
    }
};

test "save values retain passive identities refund retired nodes and preserve the RNG stream" {
    var state = progress.State.of(.wizard);
    state.nodes.set(passives.start(.knight));
    state.passive_points = 3;
    var stored = try Policy.encode(state);
    try std.testing.expectEqualDeep(state, try Policy.decode(progress.State, stored));
    stored.allocations[stored.n] = .{ .arm = passives.NODES[0].arm, .ring = 255 };
    stored.n += 1;
    const recovered = try Policy.decode(progress.State, stored);
    try std.testing.expectEqual(state.passive_points + 1, recovered.passive_points);
    try std.testing.expectEqualDeep(state.nodes, recovered.nodes);
    stored.allocations[1] = stored.allocations[0];
    try std.testing.expectError(error.Damaged, Policy.decode(progress.State, stored));
    var before = mathx.Rng.init(42);
    _ = before.below(1000);
    var after = try Policy.decode(mathx.Rng, try Policy.encode(before));
    for (0..100) |_| try std.testing.expectEqual(before.below(100000), after.below(100000));
    try std.testing.expectError(error.Damaged, Policy.decode(mathx.Rng, .{ .xoshiro256 = @splat(0) }));
}
const ALLOCATION_MAX: usize = 512;
const SavedProgress = struct {
    level: u16 = 1,
    xp: u64 = 0,
    passive_points: u16 = 0,
    active_points: u16 = 0,
    allocations: [ALLOCATION_MAX]NodeKey = undefined,
    n: usize = 0,
    ranks: @FieldType(progress.State, "ranks") = .initFill(0),

    pub const COUNTED = .{.{ "allocations", "n" }};
    const Live = progress.State;

    fn of(value: progress.State) SavedProgress {
        var result = SavedProgress{};
        copyKept(progress.State, carried, &result, value);
        var allocated = value.nodes.iterator(.{});
        while (allocated.next()) |index| {
            result.allocations[result.n] = NodeKey.of(passives.NODES[index]);
            result.n += 1;
        }
        return result;
    }

    fn live(stored: SavedProgress) wire.Error!progress.State {
        var result = progress.State{};
        copyKept(progress.State, carried, &result, stored);
        for (stored.allocations[0..stored.n], 0..) |key, index| {
            for (stored.allocations[0..index]) |previous| if (std.meta.eql(key, previous)) return error.Damaged;
            for (passives.NODES, 0..) |node, current| {
                if (std.meta.eql(key, NodeKey.of(node))) {
                    result.nodes.set(current);
                    break;
                }
            } else result.passive_points +|= progress.POINT_COST;
        }
        return result;
    }
};

/// `nodes` is kept by identity in `allocations`.
fn carried(comptime name: []const u8) bool {
    return !std.mem.eql(u8, name, "nodes");
}

comptime {
    @setEvalBranchQuota(100_000);
    if (passives.NODES.len > ALLOCATION_MAX) @compileError("raise the saved allocation limit");
    for (passives.NODES, 0..) |node, index| for (passives.NODES[0..index]) |other| {
        if (std.meta.eql(NodeKey.of(node), NodeKey.of(other))) @compileError("passive save identities must be unique");
    };
    for (std.meta.fields(progress.State)) |f| {
        if (!carried(f.name)) continue;
        if (!@hasField(SavedProgress, f.name) or @FieldType(SavedProgress, f.name) != f.type) @compileError("SavedProgress does not keep progress.State." ++ f.name);
        if (!std.meta.eql(@field(SavedProgress{}, f.name), f.defaultValue().?)) @compileError("SavedProgress defaults progress.State." ++ f.name ++ " differently");
    }
}

/// An NPC as kept: where it stands in `spot`, or, written before NPCs stood anywhere but a painted cell, in `at`.
const SavedNpc = struct {
    node: u8 = 0,
    at: mathx.P = .{ .x = 0, .y = 0 },
    spot: ?script.Spot = null,
    name: script.Who = .{},
    dialog: ?u8 = null,
    shows: ?script.Cond = null,
    looks: ?actor.Kind = null,

    const Live = script.Npc;

    fn of(value: script.Npc) SavedNpc {
        var result = SavedNpc{ .spot = value.spot };
        copyKept(script.Npc, npcKept, &result, value);
        return result;
    }

    fn live(stored: SavedNpc) wire.Error!script.Npc {
        var npc = script.Npc{ .spot = stored.spot orelse .{ .at = stored.at } };
        copyKept(script.Npc, npcKept, &npc, stored);
        return npc;
    }
};
fn npcKept(comptime name: []const u8) bool {
    return !std.mem.eql(u8, name, "spot");
}

fn copyKept(comptime T: type, comptime kept: anytype, into: anytype, from: anytype) void {
    inline for (std.meta.fields(T)) |f| {
        if (comptime kept(f.name)) @field(into, f.name) = @field(from, f.name);
    }
}

comptime {
    for (std.meta.fields(script.Npc)) |f| {
        if (!npcKept(f.name)) continue;
        if (@FieldType(SavedNpc, f.name) != f.type) @compileError("SavedNpc does not keep script.Npc." ++ f.name);
    }
}

test "an NPC kept before it could stand off a painted cell loads where it stood" {
    const C = wire.Codec(Policy);
    const Old = struct { node: u8, at: mathx.P, name: script.Who, dialog: ?u8 };
    var bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer bytes.deinit();
    try wire.Codec(struct {
        pub fn countField(comptime T: type, comptime field: []const u8) ?[]const u8 {
            return wire.counted(T, field);
        }
    }).write(&bytes, Old{ .node = 1, .at = .{ .x = 6, .y = 5 }, .name = script.Who.of("Wenna"), .dialog = 0 });
    var back: script.Npc = undefined;
    try C.read(bytes.items, &back);
    try std.testing.expectEqualDeep(script.Npc{ .node = 1, .spot = .{ .at = .{ .x = 6, .y = 5 } }, .name = script.Who.of("Wenna"), .dialog = 0 }, back);
    bytes.clearRetainingCapacity();
    const now = script.Npc{ .node = 2, .spot = .{ .by = .caravan }, .looks = .pib, .shows = .{ .kind = .quest, .state = .done } };
    try C.write(&bytes, now);
    try C.read(bytes.items, &back);
    try std.testing.expectEqualDeep(now, back);
}

pub const Policy = struct {
    pub fn defaults(destination: anytype, seen: anytype) void {
        if (std.meta.Child(@TypeOf(destination)) == data.Tail) {
            destination.growth.restoreStart(destination.class);
            if (!seen.isSet(std.meta.fieldIndex(data.Tail, "bar").?)) destination.bar = destination.growth.bar(destination.class);
            if (!seen.isSet(std.meta.fieldIndex(data.Tail, "mana").?)) destination.mana = 0;
        }
    }

    pub fn Stored(comptime T: type) type {
        inline for (SAVED) |S| {
            if (S.Live == T) return S;
        }
        return T;
    }

    pub fn encode(value: anytype) wire.Error!Stored(@TypeOf(value)) {
        return Stored(@TypeOf(value)).of(value);
    }

    pub fn decode(comptime T: type, stored: Stored(T)) wire.Error!T {
        return stored.live();
    }

    pub fn countField(comptime T: type, comptime field: []const u8) ?[]const u8 {
        if (comptime wire.counted(T, field)) |count| return count;
        if (T == data.LegacyMap) return countField(data.Map, field);
        return null;
    }
};
