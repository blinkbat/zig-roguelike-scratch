const std = @import("std");
const attrs = @import("attrs.zig");
const hero = @import("hero.zig");
const actor = @import("actor.zig");
const skillbar = @import("skillbar.zig");
const mathx = @import("../core/mathx.zig");

pub const RANKS: u8 = 3;
/// Percent more damage, and percent less mana, per rank past the first.
const RANK_DAMAGE_PERCENT: i32 = 20;
const RANK_COST_PERCENT: i32 = 10;
const XP_BASE: u64 = 40;
const XP_STEP: u64 = 20;
pub const POINTS_PER_LEVEL: u16 = 1;
const Bonus = attrs.Bonus;
pub const Node = struct { q: i32, r: i32, bonus: Bonus, amount: i32 };
/// The passive tree is a hexagon of axial cells this many steps from its middle.
const RADIUS: i32 = 4;
/// Along the tree's rows every `CYCLE`th node from each of these grants it; the rest grant their region's attribute.
const CYCLE = 7;
const CYCLED = [_]struct { at: usize, bonus: Bonus }{ .{ .at = 0, .bonus = .life }, .{ .at = 3, .bonus = .mana }, .{ .at = 6, .bonus = .armour } };
const AMOUNT = std.EnumArray(Bonus, i32).init(.{ .strength = 2, .dexterity = 2, .intelligence = 2, .life = 3, .mana = 5, .armour = 2 });
pub const NODES = blk: {
    var nodes: [3 * RADIUS * (RADIUS + 1) + 1]Node = undefined;
    var n: usize = 0;
    var r: i32 = -RADIUS;
    while (r <= RADIUS) : (r += 1) {
        var q: i32 = -RADIUS;
        while (q <= RADIUS) : (q += 1) {
            if (@abs(q + r) > RADIUS) continue;
            var bonus: Bonus = if (q < 0) .strength else if (r < 0) .dexterity else .intelligence;
            for (CYCLED) |c| if (n % CYCLE == c.at) {
                bonus = c.bonus;
            };
            nodes[n] = .{ .q = q, .r = r, .bonus = bonus, .amount = AMOUNT.get(bonus) };
            n += 1;
        }
    }
    std.debug.assert(n == nodes.len);
    break :blk nodes;
};

pub fn adjacent(a: usize, b: usize) bool {
    const dq = NODES[a].q - NODES[b].q;
    const dr = NODES[a].r - NODES[b].r;
    return @max(@max(@abs(dq), @abs(dr)), @abs(dq + dr)) == 1;
}

/// A kill is worth the foe's life in experience.
pub fn xpOf(k: actor.Kind) u32 {
    return @intCast(actor.row(k).hp);
}

/// What allocating node `i` grants; the class's start grants nothing.
pub fn bonusAt(c: hero.Class, i: usize) ?Node {
    return if (i == start(c)) null else NODES[i];
}

pub fn start(c: hero.Class) usize {
    return STARTS.get(c);
}

const STARTS = blk: {
    var out = std.EnumArray(hero.Class, usize).initUndefined();
    for (hero.CLASSES) |c| {
        const at: [2]i32 = switch (c) {
            .knight => .{ -RADIUS, 0 },
            .archer => .{ RADIUS, -RADIUS },
            .wizard => .{ 0, RADIUS },
        };
        out.set(c, for (NODES, 0..) |n, i| {
            if (n.q == at[0] and n.r == at[1]) break i;
        } else unreachable);
    }
    break :blk out;
};

pub const Skill = struct { act: skillbar.Act, parent: ?skillbar.Act = null, initial: bool = false, at: mathx.P };
pub fn skills(c: hero.Class) []const Skill {
    return switch (c) {
        .archer => &.{
            .{ .act = .shoot, .initial = true, .at = .{ .x = 0, .y = 0 } },
            .{ .act = .juke, .initial = true, .at = .{ .x = 1, .y = 0 } },
            .{ .act = .burning_arrow, .parent = .shoot, .at = .{ .x = 0, .y = 1 } },
            .{ .act = .glacial_shot, .parent = .shoot, .at = .{ .x = 1, .y = 1 } },
            .{ .act = .barbed_arrow, .parent = .burning_arrow, .at = .{ .x = 0, .y = 2 } },
            .{ .act = .pinning_shot, .parent = .glacial_shot, .at = .{ .x = 1, .y = 2 } },
        },
        .wizard => &.{
            .{ .act = .spark, .initial = true, .at = .{ .x = 0, .y = 0 } },
            .{ .act = .blink, .initial = true, .at = .{ .x = 1, .y = 0 } },
            .{ .act = .fireball, .parent = .spark, .at = .{ .x = 0, .y = 1 } },
            .{ .act = .frost_nova, .parent = .blink, .at = .{ .x = 1, .y = 1 } },
            .{ .act = .chain_lightning, .parent = .fireball, .at = .{ .x = 0, .y = 2 } },
            .{ .act = .mana_shield, .parent = .frost_nova, .at = .{ .x = 1, .y = 2 } },
        },
        .knight => &.{
            .{ .act = .charge, .initial = true, .at = .{ .x = 0, .y = 0 } },
            .{ .act = .shield_bash, .parent = .charge, .at = .{ .x = 0, .y = 1 } },
            .{ .act = .cleave, .parent = .charge, .at = .{ .x = 1, .y = 1 } },
        },
    };
}

/// Every hero has it from the start, outside the class's tree.
fn innate(act: skillbar.Act) bool {
    return switch (act) {
        .wait, .secondary, .life_flask, .mana_flask => true,
        else => false,
    };
}

comptime {
    @setEvalBranchQuota(10_000);
    for (hero.CLASSES) |c| for (skillbar.kit(c)) |a| {
        var tree = false;
        for (skills(c)) |s| tree = tree or s.act == a;
        if (tree == innate(a)) @compileError(@tagName(a) ++ ": a kit skill is either innate or in the class tree");
    };
    for (hero.CLASSES) |c| for (skills(c)) |s| {
        if (std.mem.indexOfScalar(skillbar.Act, skillbar.kit(c), s.act) == null) @compileError(@tagName(s.act) ++ ": a tree skill must be in its class's kit");
    };
}

pub const State = struct {
    level: u16 = 1,
    xp: u64 = 0,
    passive_points: u16 = 0,
    active_points: u16 = 0,
    nodes: std.StaticBitSet(NODES.len) = .initEmpty(),
    ranks: std.EnumArray(skillbar.Act, u8) = .initFill(0),

    pub fn of(c: hero.Class) State {
        var out = State{};
        out.nodes.set(start(c));
        for (skills(c)) |s| if (s.initial) {
            out.ranks.set(s.act, 1);
        };
        return out;
    }

    pub fn needed(self: State) u64 {
        return XP_BASE + @as(u64, self.level - 1) * XP_STEP;
    }

    pub fn gain(self: *State, xp: u32) u16 {
        const was = self.level;
        self.xp +|= xp;
        while (self.level < std.math.maxInt(u16) and self.xp >= self.needed()) {
            self.xp -= self.needed();
            self.level += 1;
            self.passive_points +|= POINTS_PER_LEVEL;
            self.active_points +|= POINTS_PER_LEVEL;
        }
        return self.level - was;
    }

    pub fn available(self: *const State, i: usize) bool {
        if (i >= NODES.len or self.nodes.isSet(i)) return false;
        var it = self.nodes.iterator(.{});
        while (it.next()) |j| if (adjacent(i, j)) return true;
        return false;
    }

    pub fn allocate(self: *State, i: usize) bool {
        if (self.passive_points == 0 or !self.available(i)) return false;
        self.nodes.set(i);
        self.passive_points -= 1;
        return true;
    }

    pub fn attributes(self: *const State, c: hero.Class) attrs.Attrs {
        var out = c.attrs();
        var it = self.nodes.iterator(.{});
        while (it.next()) |i| if (bonusAt(c, i)) |n| out.add(n.bonus, n.amount);
        return out;
    }

    pub fn unlocked(self: *const State, act: skillbar.Act) bool {
        return innate(act) or self.ranks.get(act) > 0;
    }

    pub fn canLearn(self: *const State, c: hero.Class, act: skillbar.Act) bool {
        if (self.active_points == 0 or self.ranks.get(act) >= RANKS) return false;
        for (skills(c)) |s| if (s.act == act) {
            return if (s.parent) |p| self.unlocked(p) else true;
        };
        return false;
    }

    pub fn learn(self: *State, c: hero.Class, act: skillbar.Act) bool {
        if (!self.canLearn(c, act)) return false;
        self.ranks.getPtr(act).* += 1;
        self.active_points -= 1;
        return true;
    }

    pub fn damageBonus(self: *const State, act: skillbar.Act) i32 {
        if (act.style() == null) return 0;
        return @as(i32, self.ranks.get(act) -| 1) * RANK_DAMAGE_PERCENT;
    }

    pub fn cost(self: *const State, act: skillbar.Act) i32 {
        return mathx.percentOf(act.cost(), mathx.PERCENT - @as(i32, self.ranks.get(act) -| 1) * RANK_COST_PERCENT);
    }

    pub fn cooldown(self: *const State, act: skillbar.Act) u8 {
        if (act.style() != null or act.cooldown() == 0) return act.cooldown();
        // A cooldown of 1 runs out in the turn the skill took, so a turn-taking skill keeps 2.
        const floor = @min(act.cooldown(), 1 + act.turns());
        return @max(floor, act.cooldown() -| (self.ranks.get(act) -| 1));
    }

    pub fn kit(self: *const State, c: hero.Class, out: *[skillbar.ACTS.len]skillbar.Act) []const skillbar.Act {
        var n: usize = 0;
        for (skillbar.kit(c)) |a| if (self.unlocked(a)) {
            out[n] = a;
            n += 1;
        };
        return out[0..n];
    }

    pub fn bar(self: *const State, c: hero.Class) skillbar.Bar {
        var out = skillbar.Bar.of(c);
        for (skillbar.SETS) |set| for (skillbar.SLOTS) |button| {
            const slot = skillbar.Slot{ .set = set, .button = button };
            if (out.at(slot)) |a| if (!self.unlocked(a)) out.clear(slot);
        };
        return out;
    }
};

test "experience awards both point pools; passive paths cross class regions; active skills obey class and rank limits" {
    for (hero.CLASSES) |c| {
        var state = State.of(c);
        try std.testing.expectEqual(@as(u16, 2), state.gain(100));
        try std.testing.expectEqual(@as(u16, 2), state.passive_points);
        try std.testing.expectEqual(@as(u16, 2), state.active_points);
        try std.testing.expect(!state.allocate(start(c)));
        state.passive_points = NODES.len - 1;
        var count: usize = 1;
        while (count < NODES.len) {
            var moved = false;
            for (NODES, 0..) |_, i| if (state.allocate(i)) {
                count += 1;
                moved = true;
            };
            try std.testing.expect(moved);
        }
        try std.testing.expectEqual(@as(u16, 0), state.passive_points);
        try std.testing.expect(state.attributes(c).life() > c.attrs().life());
        state.active_points = 100;
        for (skills(c)) |s| {
            while (state.learn(c, s.act)) {}
            try std.testing.expectEqual(RANKS, state.ranks.get(s.act));
        }
        for (hero.CLASSES) |other| if (other != c) {
            try std.testing.expect(!state.learn(c, skills(other)[0].act));
        };
    }
    var top = State{};
    for ([_]skillbar.Act{ .juke, .blink, .mana_shield }) |a| top.ranks.set(a, RANKS);
    try std.testing.expectEqual(@as(u8, 1), top.cooldown(.juke));
    try std.testing.expectEqual(@as(u8, 2), top.cooldown(.blink));
    try std.testing.expectEqual(@as(i32, 0), top.damageBonus(.blink));
    std.debug.print("progression: 3 classes traverse all {d} passive nodes; 3 ranks, prerequisites and separate point pools checked; top-rank blink cools {d}, juke {d}, ward {d}\n", .{ NODES.len, top.cooldown(.blink), top.cooldown(.juke), top.cooldown(.mana_shield) });
}
