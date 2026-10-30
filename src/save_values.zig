const std = @import("std");
const hero = @import("play/hero.zig");
const progress = @import("play/progress.zig");
const mathx = @import("core/mathx.zig");
const wire = @import("core/wire.zig");
const data = @import("save_data.zig");

const SavedRng = struct { xoshiro256: [4]u64 };
const Node = progress.passives.Node;
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
    state.nodes.set(progress.start(.knight));
    state.passive_points = 3;
    var stored = try Policy.encode(state);
    try std.testing.expectEqualDeep(state, try Policy.decode(progress.State, stored));
    stored.allocations[stored.n] = .{ .arm = progress.NODES[0].arm, .ring = 255 };
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
    std.debug.print("save identities: passive allocations retained, removed node refunded, duplicate refused; 100 RNG draws identical\n", .{});
}
const SavedProgress = struct {
    level: u16 = 1,
    xp: u64 = 0,
    passive_points: u16 = 0,
    active_points: u16 = 0,
    allocations: [512]NodeKey = undefined,
    n: usize = 0,
    ranks: @FieldType(progress.State, "ranks") = .initFill(0),
};

/// A `progress.State` field `SavedProgress` keeps as it is; `nodes` is kept by identity in `allocations`.
fn carried(comptime name: []const u8) bool {
    return !std.mem.eql(u8, name, "nodes");
}

comptime {
    @setEvalBranchQuota(100_000);
    if (progress.NODES.len > 512) @compileError("raise the saved allocation limit");
    for (progress.NODES, 0..) |node, index| for (progress.NODES[0..index]) |other| {
        if (std.meta.eql(NodeKey.of(node), NodeKey.of(other))) @compileError("passive save identities must be unique");
    };
    for (std.meta.fields(progress.State)) |f| {
        if (carried(f.name) and (!@hasField(SavedProgress, f.name) or @FieldType(SavedProgress, f.name) != f.type)) @compileError("SavedProgress does not keep progress.State." ++ f.name);
    }
}

pub const Policy = struct {
    pub fn restoreStart(state: *progress.State, class: hero.Class) void {
        state.nodes.set(progress.start(class));
        for (progress.skills(class)) |skill| if (skill.initial and state.ranks.get(skill.act) == 0) {
            state.ranks.set(skill.act, 1);
        };
    }

    pub fn defaults(destination: anytype, seen: anytype) void {
        if (std.meta.Child(@TypeOf(destination)) == data.Tail) {
            restoreStart(&destination.growth, destination.class);
            if (!seen.isSet(std.meta.fieldIndex(data.Tail, "bar").?)) destination.bar = destination.growth.bar(destination.class);
            if (!seen.isSet(std.meta.fieldIndex(data.Tail, "mana").?)) destination.mana = 0;
        }
    }

    pub fn Stored(comptime T: type) type {
        return if (T == mathx.Rng) SavedRng else if (T == progress.State) SavedProgress else T;
    }

    pub fn encode(value: anytype) wire.Error!Stored(@TypeOf(value)) {
        if (@TypeOf(value) == mathx.Rng) return .{ .xoshiro256 = value.impl.s };
        var result = SavedProgress{};
        inline for (std.meta.fields(progress.State)) |f| {
            if (comptime carried(f.name)) @field(result, f.name) = @field(value, f.name);
        }
        var allocated = value.nodes.iterator(.{});
        while (allocated.next()) |index| {
            result.allocations[result.n] = NodeKey.of(progress.NODES[index]);
            result.n += 1;
        }
        return result;
    }

    pub fn decode(comptime T: type, stored: Stored(T)) wire.Error!T {
        if (T == mathx.Rng) {
            if (std.mem.allEqual(u64, &stored.xoshiro256, 0)) return error.Damaged;
            return .{ .impl = .{ .s = stored.xoshiro256 } };
        }
        var result = progress.State{};
        inline for (std.meta.fields(progress.State)) |f| {
            if (comptime carried(f.name)) @field(result, f.name) = @field(stored, f.name);
        }
        for (stored.allocations[0..stored.n], 0..) |key, index| {
            for (stored.allocations[0..index]) |previous| if (std.meta.eql(key, previous)) return error.Damaged;
            for (progress.NODES, 0..) |node, current| {
                if (std.meta.eql(key, NodeKey.of(node))) {
                    result.nodes.set(current);
                    break;
                }
            } else result.passive_points +|= progress.POINT_COST;
        }
        return result;
    }

    pub fn countField(comptime T: type, comptime field: []const u8) ?[]const u8 {
        if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "COUNTED")) {
            inline for (T.COUNTED) |entry| {
                if (comptime std.mem.eql(u8, field, entry[0])) return entry[1];
            }
        }
        if (T == data.LegacyMap) return countField(data.Map, field);
        inline for (.{
            .{ SavedProgress, "allocations", "n" },
        }) |entry| {
            if (T == entry[0] and std.mem.eql(u8, field, entry[1])) return entry[2];
        }
        return null;
    }
};
