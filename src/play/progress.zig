const std = @import("std");
const attrs = @import("attrs.zig");
const hero = @import("hero.zig");
const actor = @import("actor.zig");
const skillbar = @import("skillbar.zig");
const items = @import("items.zig");
const damage = @import("damage.zig");
const mathx = @import("../core/mathx.zig");

pub const RANKS: u8 = 3;
/// Percent more damage, and percent less mana, per rank past the first.
const RANK_DAMAGE_PERCENT: i32 = 20;
const RANK_COST_PERCENT: i32 = 10;
const XP_BASE: u64 = 40;
const XP_STEP: u64 = 20;
const POINTS_PER_LEVEL: u16 = 1;
/// Points a passive node or a skill rank costs.
pub const POINT_COST: u16 = 1;
pub const passives = @import("passives.zig");
const Node = passives.Node;
pub const NODES = passives.NODES;
pub const start = passives.start;

pub fn xpOf(k: actor.Kind) u32 {
    return @intCast(actor.row(k).hp);
}

/// What allocating node `i` grants `c`: nothing at its own free origin.
pub fn bonusAt(c: hero.Class, i: usize) ?Node {
    return if (i == start(c)) null else NODES[i];
}

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
            .{ .act = .cleave, .initial = true, .at = .{ .x = 1, .y = 0 } },
        },
    };
}

/// Every hero has it from the start, outside the class's tree.
fn innate(act: skillbar.Act) bool {
    return act == .wait or act == .secondary or act.flaskOf() != null;
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

pub const Hit = struct { physical: damage.Span, element: ?damage.Span, style: attrs.Style };
pub const Blow = struct { by: attrs.Attrs, style: attrs.Style, bases: skillbar.EquippedBases };

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
        var buf: [passives.MAX_FEED]usize = undefined;
        const fs = passives.feeders(i, &buf);
        if (fs.len == 0) return true;
        for (fs) |j| if (self.nodes.isSet(j)) return true;
        return false;
    }

    /// Reachable, with a point to spend on it.
    pub fn canAllocate(self: *const State, i: usize) bool {
        return self.passive_points >= POINT_COST and self.available(i);
    }

    pub fn allocate(self: *State, i: usize) bool {
        if (!self.canAllocate(i)) return false;
        self.nodes.set(i);
        self.passive_points -= POINT_COST;
        return true;
    }

    pub fn attributes(self: *const State, c: hero.Class) attrs.Attrs {
        var out = c.attrs();
        var it = self.nodes.iterator(.{});
        while (it.next()) |i| if (bonusAt(c, i)) |n| n.apply(&out);
        return out;
    }

    /// Origins grant only attributes, so a class's free one adds nothing here.
    pub fn perks(self: *const State) passives.Perks {
        var out = passives.Perks{};
        var it = self.nodes.iterator(.{});
        while (it.next()) |i| NODES[i].perk(&out);
        return out;
    }

    pub fn unlocked(self: *const State, act: skillbar.Act) bool {
        return innate(act) or self.ranks.get(act) > 0;
    }

    pub fn maxed(self: *const State, act: skillbar.Act) bool {
        return self.ranks.get(act) >= RANKS;
    }

    pub fn canLearn(self: *const State, c: hero.Class, act: skillbar.Act) bool {
        if (self.active_points < POINT_COST or self.maxed(act)) return false;
        for (skills(c)) |s| if (s.act == act) {
            return if (s.parent) |p| self.unlocked(p) else true;
        };
        return false;
    }

    pub fn learn(self: *State, c: hero.Class, act: skillbar.Act) bool {
        if (!self.canLearn(c, act)) return false;
        self.ranks.getPtr(act).* += 1;
        self.active_points -= POINT_COST;
        return true;
    }

    fn extraRanks(self: *const State, act: skillbar.Act) u8 {
        return self.ranks.get(act) -| 1;
    }

    pub fn damageBonus(self: *const State, act: skillbar.Act) i32 {
        if (act.attack() == null) return 0;
        return @as(i32, self.extraRanks(act)) * RANK_DAMAGE_PERCENT;
    }

    fn skillAttrs(self: *const State, equipped: attrs.Attrs, gear: items.Gear, act: skillbar.Act) attrs.Attrs {
        var out = if (act.attack()) |attack| gear.forAttack(equipped, attack) else equipped;
        if (act.attack()) |attack| out.damage_bonus.getPtr(gear.scaling(attack)).* += self.damageBonus(act);
        return out;
    }

    /// What scales `act`'s blow with `gear`, for previews and live rolls alike.
    pub fn blowOf(self: *const State, equipped: attrs.Attrs, gear: items.Gear, act: skillbar.Act) ?Blow {
        const attack = act.attack() orelse return null;
        return .{ .by = self.skillAttrs(equipped, gear, act), .style = gear.scaling(attack), .bases = act.equippedBases(gear) };
    }

    /// Its blow's non-critical spans with `gear`, as live damage rolls them.
    pub fn hit(self: *const State, equipped: attrs.Attrs, gear: items.Gear, act: skillbar.Act) ?Hit {
        const b = self.blowOf(equipped, gear, act) orelse return null;
        return .{ .physical = b.by.span(b.style, b.bases.physical()), .element = if (b.bases.element) |e| b.by.elementSpan(b.style, e, act.element().?) else null, .style = b.style };
    }

    pub fn cost(self: *const State, act: skillbar.Act) i32 {
        if (act.cost() == 0) return 0;
        const percent = @max(0, mathx.PERCENT - @as(i32, self.extraRanks(act)) * RANK_COST_PERCENT - self.perks().mana_cost);
        return @max(1, std.math.divCeil(i32, act.cost() * percent, mathx.PERCENT) catch unreachable);
    }

    pub fn cooldown(self: *const State, act: skillbar.Act) u8 {
        if (act.attack() != null or act.cooldown() == 0) return act.cooldown();
        // A cooldown of 1 runs out in the turn the skill took, so a turn-taking skill keeps 2.
        const floor = @min(act.cooldown(), 1 + act.turns());
        return @max(floor, act.cooldown() -| self.extraRanks(act));
    }

    /// What using it costs at its rank: "3 mana, 1 turn, 2-turn cooldown".
    pub fn writeUsage(self: *const State, act: skillbar.Act, w: anytype) void {
        const c = self.cost(act);
        if (c > 0) w.print("{d} mana, ", .{c}) catch {};
        const turns = act.turns();
        if (turns == 0) w.writeAll("no turn cost") catch {} else w.print("{d} turn{s}", .{ turns, mathx.plural(turns) }) catch {};
        const cd = self.cooldown(act);
        if (cd > 0) w.print(", {d}-turn cooldown", .{cd}) catch {};
    }

    pub fn kit(self: *const State, c: hero.Class, out: *skillbar.KitBuf) []const skillbar.Act {
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
    std.debug.print("progression: {d} classes traverse all {d} passive nodes; {d} ranks, prerequisites and separate point pools checked; top-rank blink cools {d}, juke {d}, ward {d}\n", .{ std.enums.values(hero.Class).len, NODES.len, RANKS, top.cooldown(.blink), top.cooldown(.juke), top.cooldown(.mana_shield) });
}

test "small mana costs round discounts up and paid skills stay paid at every rank" {
    var state = State{};
    try std.testing.expectEqual(@as(i32, 2), state.cost(.spark));
    try std.testing.expectEqual(@as(i32, 7), state.cost(.blink));
    state.ranks.set(.spark, RANKS);
    state.ranks.set(.blink, RANKS);
    try std.testing.expectEqual(@as(i32, 2), state.cost(.spark));
    try std.testing.expectEqual(@as(i32, 6), state.cost(.blink));
    for (0..NODES.len) |i| state.nodes.set(i);
    var checked: usize = 0;
    for (skillbar.ACTS) |act| {
        for (1..RANKS + 1) |rank| {
            state.ranks.set(act, @intCast(rank));
            const n = state.cost(act);
            try std.testing.expect(n <= act.cost());
            if (act.cost() == 0) {
                try std.testing.expectEqual(@as(i32, 0), n);
            } else {
                try std.testing.expect(n >= 1);
            }
            checked += 1;
        }
    }
    try std.testing.expectEqual(@as(i32, 1), state.cost(.spark));
    std.debug.print("small mana costs: {d} action/rank cases, rounded discounts and free actions checked\n", .{checked});
}

test "passive origins preserve class bases and failed purchases preserve the whole state" {
    var paid: usize = 0;
    var failed: usize = 0;
    for (hero.CLASSES) |c| {
        var state = State.of(c);
        try std.testing.expectEqual(@as(usize, 1), state.nodes.count());
        try std.testing.expect(state.nodes.isSet(start(c)));
        try std.testing.expectEqualDeep(c.attrs(), state.attributes(c));
        for (hero.CLASSES) |other| {
            if (other == c) continue;
            const root = start(other);
            try std.testing.expect(state.available(root));
            const poor = state;
            try std.testing.expect(!state.allocate(root));
            try std.testing.expectEqualDeep(poor, state);
            failed += 1;

            state.passive_points = 1;
            state.active_points = 7;
            const before = state.attributes(c);
            try std.testing.expect(state.allocate(root));
            try std.testing.expectEqual(@as(u16, 0), state.passive_points);
            try std.testing.expectEqual(@as(u16, 7), state.active_points);
            var want = before;
            want.points.getPtr(passives.Arm.of(other).stat().attr().?).* += passives.ROOT_GRANT;
            try std.testing.expectEqualDeep(want, state.attributes(c));
            paid += 1;
        }
        state.passive_points = 3;
        for ([_]usize{ start(c), NODES.len, passives.branchFirst(.warrior_life) + passives.PER_BRANCH - 1 }) |blocked| {
            const before = state;
            try std.testing.expect(!state.allocate(blocked));
            try std.testing.expectEqualDeep(before, state);
            failed += 1;
        }
    }
    std.debug.print("passive origins: {d} free class starts, {d} paid alternate starts, and {d} failed purchases preserve point pools and state\n", .{ hero.CLASSES.len, paid, failed });
}

test "passive branch gates advance one layer and apply exact stat interest and capstone packages" {
    const route = comptime blk: {
        var out: [passives.BRANCH_RINGS.len]usize = undefined;
        for (&out, 0..) |*first, r| first.* = passives.ringOffset(r);
        break :blk out;
    };
    for (std.enums.values(passives.Branch)) |b| {
        const c = b.arm().class();
        var state = State.of(c);
        state.passive_points = route.len;
        state.active_points = 9;
        for (route, 0..) |offset, rung| {
            const node = passives.branchFirst(b) + offset;
            try std.testing.expect(state.available(node));
            if (rung + 1 < route.len) {
                const next = passives.branchFirst(b) + route[rung + 1];
                const before = state;
                try std.testing.expect(!state.available(next));
                try std.testing.expect(!state.allocate(next));
                try std.testing.expectEqualDeep(before, state);
            }
            const points = state.passive_points;
            try std.testing.expect(state.allocate(node));
            try std.testing.expectEqual(points - 1, state.passive_points);
            try std.testing.expectEqual(@as(u16, 9), state.active_points);
        }
        try std.testing.expectEqual(@as(u16, 0), state.passive_points);
        try std.testing.expectEqual(route.len + 1, state.nodes.count());
    }

    const Case = struct {
        class: hero.Class,
        branch: passives.Branch,
        attr: attrs.Attr,
        points: i32,
        life: i32 = 0,
        mana: i32 = 0,
        armour: i32 = 0,
        style: attrs.Style,
        damage: i32 = 0,
        crit: i32 = 0,
        perks: passives.Perks = .{},
    };
    const cases = [_]Case{
        .{ .class = .knight, .branch = .warrior_life, .attr = .strength, .points = 9, .armour = 11, .style = .heavy, .perks = .{ .life_on_hit = 1 } },
        .{ .class = .knight, .branch = .warrior_berserk, .attr = .strength, .points = 5, .style = .heavy, .damage = 25, .perks = .{ .life_on_kill = 3, .cull = 10 } },
        .{ .class = .archer, .branch = .rogue_ranged, .attr = .dexterity, .points = 4, .style = .light, .damage = 24, .crit = 13 },
        .{ .class = .wizard, .branch = .wizard_cast, .attr = .intelligence, .points = 7, .style = .spell, .damage = 19, .perks = .{ .mana_cost = 30 } },
    };
    for (cases) |case| {
        var state = State.of(case.class);
        state.passive_points = route.len;
        for (route) |offset| try std.testing.expect(state.allocate(passives.branchFirst(case.branch) + offset));
        const base = case.class.attrs();
        var want = base;
        want.points.getPtr(case.attr).* += case.points;
        want.life_bonus += case.life;
        want.mana_bonus += case.mana;
        want.armour += case.armour;
        want.damage_bonus.getPtr(case.style).* += case.damage;
        want.crit_bonus += case.crit;
        const actual = state.attributes(case.class);
        try std.testing.expectEqualDeep(want, actual);
        try std.testing.expectEqualDeep(case.perks, state.perks());
        try std.testing.expectEqual(base.increase(case.style) + case.points + case.damage, actual.increase(case.style));
        try std.testing.expectEqual(want.life(), actual.life());
        try std.testing.expectEqual(want.mana(), actual.mana());
    }
    const branches = std.enums.values(passives.Branch).len;
    std.debug.print("passive branches: {d} one-point layer gates, {d} blocked skips; exact attribute and perk totals on {d} capstone routes\n", .{ branches * route.len, branches * (route.len - 1), cases.len });
}

test "passive bridges pay both attributes and cross either way without opening inward prerequisites" {
    var crossings: usize = 0;
    for (std.enums.values(passives.Seam)) |seam| {
        for (passives.BRIDGE_RINGS, 0..) |ring, bridge_at| {
            const anchors = passives.bridgeAnchors(seam, ring);
            const bridge = passives.bridgeFirst(seam) + bridge_at;
            for (0..2) |side| {
                const near = anchors[side];
                const far = anchors[1 - side];
                const c = NODES[near].arm.class();
                var state = State.of(c);
                state.passive_points = 100;
                try std.testing.expect(!state.available(bridge));
                for (passives.branchFirst(NODES[near].branch.?)..near + 1) |i| try std.testing.expect(state.allocate(i));
                try std.testing.expect(state.available(bridge));
                try std.testing.expect(!state.available(far));
                const before = state.attributes(c);
                const points = state.passive_points;
                try std.testing.expect(state.allocate(bridge));
                try std.testing.expectEqual(points - 1, state.passive_points);
                var want = before;
                const amount: i32 = @intCast(bridge_at + 1);
                for ([_]passives.Arm{ seam.from(), seam.to() }) |arm| want.points.getPtr(arm.stat().attr().?).* += amount;
                try std.testing.expectEqualDeep(want, state.attributes(c));
                try std.testing.expect(state.available(far));
                try std.testing.expect(state.allocate(far));
                try std.testing.expectEqual(points - 2, state.passive_points);
                var buf: [passives.MAX_FEED]usize = undefined;
                for (passives.feeders(far, &buf)) |prerequisite| {
                    if (NODES[prerequisite].seam != null) continue;
                    try std.testing.expect(!state.available(prerequisite));
                }
                var outward = false;
                for (NODES, 0..) |n, i| {
                    if (n.branch != NODES[far].branch or n.ring != ring + 1) continue;
                    if (std.mem.indexOfScalar(usize, passives.feeders(i, &buf), far) == null) continue;
                    try std.testing.expect(state.available(i));
                    outward = true;
                }
                try std.testing.expect(outward);
                crossings += 1;
            }
        }
    }
    try std.testing.expectEqual(passives.BRIDGES * 2, crossings);
    std.debug.print("passive bridges: all {d} directional crossings apply exact paired stats, open the far anchor and advance outward only\n", .{crossings});
}
