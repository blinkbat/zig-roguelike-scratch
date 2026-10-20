const std = @import("std");
const attrs = @import("attrs.zig");
const hero = @import("hero.zig");

pub const Arm = enum {
    warrior,
    rogue,
    wizard,

    pub fn stat(a: Arm) Kind {
        return switch (a) {
            .warrior => .strength,
            .rogue => .dexterity,
            .wizard => .intelligence,
        };
    }

    /// The class that starts on it.
    pub fn class(a: Arm) hero.Class {
        return switch (a) {
            .warrior => .knight,
            .rogue => .archer,
            .wizard => .wizard,
        };
    }

    pub fn of(c: hero.Class) Arm {
        for (std.enums.values(Arm)) |a| {
            if (a.class() == c) return a;
        }
        unreachable;
    }
};
pub const Branch = enum {
    warrior_life,
    warrior_berserk,
    rogue_evade,
    rogue_ranged,
    wizard_well,
    wizard_cast,

    pub fn arm(b: Branch) Arm {
        return BRANCH_POSITIONS.get(b).arm;
    }
    pub fn lane(b: Branch) usize {
        return BRANCH_POSITIONS.get(b).lane;
    }
    pub fn on(a: Arm, lane_: usize) Branch {
        return BRANCHES.get(a)[lane_];
    }
    pub fn name(b: Branch) [:0]const u8 {
        return switch (b) {
            .warrior_life => "Fortitude",
            .warrior_berserk => "Might",
            .rogue_evade => "Agility",
            .rogue_ranged => "Finesse",
            .wizard_well => "Reserves",
            .wizard_cast => "Sorcery",
        };
    }
};
pub const Seam = enum {
    warrior_rogue,
    rogue_wizard,
    wizard_warrior,
    pub fn from(s: Seam) Arm {
        return SEAMS.get(s)[0];
    }
    pub fn to(s: Seam) Arm {
        return SEAMS.get(s)[1];
    }
};
const BRANCHES = std.EnumArray(Arm, [2]Branch).init(.{
    .warrior = .{ .warrior_life, .warrior_berserk },
    .rogue = .{ .rogue_evade, .rogue_ranged },
    .wizard = .{ .wizard_well, .wizard_cast },
});
const BRANCH_POSITIONS = blk: {
    var out = std.EnumArray(Branch, struct { arm: Arm, lane: usize }).initUndefined();
    var seen = std.EnumSet(Branch).initEmpty();
    for (std.enums.values(Arm)) |a| for (BRANCHES.get(a), 0..) |b, lane| {
        if (seen.contains(b)) @compileError(@tagName(b) ++ " belongs to more than one passive branch");
        seen.insert(b);
        out.set(b, .{ .arm = a, .lane = lane });
    };
    for (std.enums.values(Branch)) |b| {
        if (!seen.contains(b)) @compileError(@tagName(b) ++ " has no passive arm");
    }
    break :blk out;
};
const SEAMS = std.EnumArray(Seam, [2]Arm).init(.{
    .warrior_rogue = .{ .warrior, .rogue },
    .rogue_wizard = .{ .rogue, .wizard },
    .wizard_warrior = .{ .wizard, .warrior },
});
pub const Tier = enum { stat, interest, capstone };
pub const Kind = enum {
    strength,
    dexterity,
    intelligence,
    life,
    mana,
    armour,
    heavy_damage,
    light_damage,
    spell_damage,

    /// The damage it raises by a percentage, for a damage kind.
    pub fn style(k: Kind) ?attrs.Style {
        return switch (k) {
            .heavy_damage => .heavy,
            .light_damage => .light,
            .spell_damage => .spell,
            .strength, .dexterity, .intelligence, .life, .mana, .armour => null,
        };
    }

    /// The attribute it raises, for a pure attribute kind.
    pub fn attr(k: Kind) ?attrs.Attr {
        return switch (k) {
            inline else => |t| comptime std.meta.stringToEnum(attrs.Attr, @tagName(t)),
        };
    }
};
/// What each class origin grants of its arm's attribute.
pub const ROOT_GRANT: i32 = 2;
pub const Grant = struct {
    kind: Kind,
    amount: i32,

    pub fn label(g: Grant) [:0]const u8 {
        return switch (g.kind) {
            .strength => "Strength",
            .dexterity => "Dexterity",
            .intelligence => "Intelligence",
            .life => "Maximum life",
            .mana => "Maximum mana",
            .armour => "Armour",
            .heavy_damage => "Heavy weapon damage",
            .light_damage => "Light weapon damage",
            .spell_damage => "Spell damage",
        };
    }
    pub fn isPercent(g: Grant) bool {
        return g.kind.style() != null;
    }
    pub fn apply(g: Grant, a: *attrs.Attrs) void {
        if (g.kind.style()) |s| {
            a.damage_bonus.getPtr(s).* += g.amount;
            return;
        }
        switch (g.kind) {
            .heavy_damage, .light_damage, .spell_damage => unreachable,
            inline else => |k| a.add(@field(attrs.Bonus, @tagName(k)), g.amount),
        }
    }
};
pub const Node = struct {
    arm: Arm,
    branch: ?Branch = null,
    seam: ?Seam = null,
    ring: u8,
    slot: u8 = 0,
    name: [:0]const u8,
    tier: Tier = .stat,
    grant: Grant,
    bump: ?Grant = null,

    pub fn apply(n: Node, a: *attrs.Attrs) void {
        n.grant.apply(a);
        if (n.bump) |g| g.apply(a);
    }
};

pub const BRANCH_RINGS = [_]u8{ 1, 2, 3, 3, 2, 1 };
pub const BRIDGE_RINGS = [_]u8{ 3, 5 };
pub const MAX_FEED = 4;
pub const PER_BRANCH = blk: {
    var count: usize = 0;
    for (BRANCH_RINGS) |width| count += width;
    break :blk count;
};
pub const PER_ARM = 1 + BRANCHES.values[0].len * PER_BRANCH;
pub const NTREE = std.enums.values(Arm).len * PER_ARM;
pub const N = NTREE + std.enums.values(Seam).len * BRIDGE_RINGS.len;
pub const RINGS = BRANCH_RINGS.len + 1;
pub const HUB = N;
pub const Point = struct { x: f32, y: f32 };

pub fn armFirst(a: Arm) usize {
    return @as(usize, @intFromEnum(a)) * PER_ARM;
}
pub fn branchFirst(b: Branch) usize {
    return armFirst(b.arm()) + 1 + b.lane() * PER_BRANCH;
}
pub fn bridgeFirst(s: Seam) usize {
    return NTREE + @intFromEnum(s) * BRIDGE_RINGS.len;
}
pub fn start(c: hero.Class) usize {
    return armFirst(Arm.of(c));
}
fn ringFirst(b: Branch, br: usize) usize {
    var at = branchFirst(b);
    for (BRANCH_RINGS[0..br]) |wide| at += wide;
    return at;
}
pub fn bridgeAnchors(s: Seam, ring: u8) [2]usize {
    const br = ring - 1;
    return .{ ringFirst(Branch.on(s.from(), 0), br), ringFirst(Branch.on(s.to(), 1), br) + BRANCH_RINGS[br] - 1 };
}
fn overlaps(p: usize, wp: usize, s: usize, wc: usize) bool {
    return p * wc < (s + 1) * wp and s * wp < (p + 1) * wc;
}
fn bridgeOn(i: usize, out: *[MAX_FEED]usize, k: usize) usize {
    var n = k;
    for (std.enums.values(Seam)) |s| for (BRIDGE_RINGS, 0..) |ring, bi| {
        const anchors = bridgeAnchors(s, ring);
        if (anchors[0] != i and anchors[1] != i) continue;
        out[n] = bridgeFirst(s) + bi;
        n += 1;
    };
    return n;
}
pub fn feeders(i: usize, out: *[MAX_FEED]usize) []const usize {
    const f = &FEEDS[i];
    out.* = f.at;
    return out[0..f.n];
}

const Feeds = struct { at: [MAX_FEED]usize, n: usize };
const FEEDS: [N]Feeds = blk: {
    @setEvalBranchQuota(200_000);
    var out: [N]Feeds = undefined;
    for (0..N) |i| {
        var buf: [MAX_FEED]usize = @splat(0);
        const n = feedersOf(i, &buf).len;
        out[i] = .{ .at = buf, .n = n };
    }
    break :blk out;
};

fn feedersOf(i: usize, out: *[MAX_FEED]usize) []const usize {
    const n = NODES[i];
    if (n.seam) |s| {
        const a = bridgeAnchors(s, n.ring);
        out[0] = a[0];
        out[1] = a[1];
        return out[0..2];
    }
    if (n.ring == 0) return out[0..0];
    const br = n.ring - 1;
    const b = n.branch.?;
    if (br == 0) {
        out[0] = armFirst(b.arm());
        return out[0..bridgeOn(i, out, 1)];
    }
    const base = ringFirst(b, br - 1);
    const wp = BRANCH_RINGS[br - 1];
    const wc = BRANCH_RINGS[br];
    var k: usize = 0;
    for (0..wp) |p| {
        if (!overlaps(p, wp, n.slot, wc)) continue;
        out[k] = base + p;
        k += 1;
    }
    return out[0..bridgeOn(i, out, k)];
}
pub fn linked(a: usize, b: usize) bool {
    var buf: [MAX_FEED]usize = undefined;
    for (feeders(a, &buf)) |i| if (i == b) return true;
    for (feeders(b, &buf)) |i| if (i == a) return true;
    return false;
}

const Entry = struct { name: [:0]const u8, kind: Kind, amount: i32, rider: i32 = 0 };
const BANK = std.EnumArray(Branch, [PER_BRANCH]Entry).init(.{
    .warrior_life = .{
        .{ .name = "Warrior's Blood", .kind = .strength, .amount = 2 },
        .{ .name = "Thick Hide", .kind = .armour, .amount = 2, .rider = 1 },
        .{ .name = "Stout Heart", .kind = .life, .amount = 3, .rider = 1 },
        .{ .name = "Boiled Leather", .kind = .armour, .amount = 2, .rider = 1 },
        .{ .name = "Stubborn Flesh", .kind = .strength, .amount = 3 },
        .{ .name = "Scar Tissue", .kind = .life, .amount = 4, .rider = 1 },
        .{ .name = "Stalwart", .kind = .armour, .amount = 3 },
        .{ .name = "Unshaken", .kind = .strength, .amount = 3 },
        .{ .name = "Deep Roots", .kind = .life, .amount = 5 },
        .{ .name = "Ironbound", .kind = .armour, .amount = 4, .rider = 2 },
        .{ .name = "Lasting Vigor", .kind = .life, .amount = 5, .rider = 1 },
        .{ .name = "Living Fortress", .kind = .life, .amount = 12, .rider = 3 },
    },
    .warrior_berserk = .{
        .{ .name = "Reaver", .kind = .strength, .amount = 2 },
        .{ .name = "Heavy Hands", .kind = .heavy_damage, .amount = 4, .rider = 1 },
        .{ .name = "Hard Knocks", .kind = .life, .amount = 3 },
        .{ .name = "Brute Force", .kind = .strength, .amount = 3 },
        .{ .name = "Crushing Blows", .kind = .heavy_damage, .amount = 4, .rider = 1 },
        .{ .name = "Firm Grip", .kind = .strength, .amount = 2 },
        .{ .name = "Red Harvest", .kind = .heavy_damage, .amount = 5 },
        .{ .name = "Battle Hardened", .kind = .armour, .amount = 3 },
        .{ .name = "Executioner", .kind = .heavy_damage, .amount = 5, .rider = 1 },
        .{ .name = "Frenzy", .kind = .heavy_damage, .amount = 6, .rider = 1 },
        .{ .name = "Blood Rush", .kind = .strength, .amount = 3 },
        .{ .name = "Overwhelming Force", .kind = .heavy_damage, .amount = 15, .rider = 2 },
    },
    .rogue_evade = .{
        .{ .name = "Fleet", .kind = .dexterity, .amount = 2 },
        .{ .name = "Second Wind", .kind = .life, .amount = 3, .rider = 1 },
        .{ .name = "Light Step", .kind = .dexterity, .amount = 2 },
        .{ .name = "Sure Feet", .kind = .dexterity, .amount = 3 },
        .{ .name = "Tumbler", .kind = .life, .amount = 4, .rider = 1 },
        .{ .name = "Long Stride", .kind = .dexterity, .amount = 2 },
        .{ .name = "Wind at Heel", .kind = .dexterity, .amount = 3 },
        .{ .name = "Deep Lungs", .kind = .life, .amount = 5, .rider = 1 },
        .{ .name = "Warded Blood", .kind = .armour, .amount = 3 },
        .{ .name = "Slip", .kind = .dexterity, .amount = 3 },
        .{ .name = "Survivor", .kind = .life, .amount = 5, .rider = 2 },
        .{ .name = "Untouchable", .kind = .dexterity, .amount = 6 },
    },
    .rogue_ranged = .{
        .{ .name = "Keen Eye", .kind = .dexterity, .amount = 2 },
        .{ .name = "Practised Arm", .kind = .light_damage, .amount = 4, .rider = 1 },
        .{ .name = "Wayfinder", .kind = .dexterity, .amount = 2 },
        .{ .name = "Light Touch", .kind = .light_damage, .amount = 4, .rider = 1 },
        .{ .name = "Steady Hand", .kind = .dexterity, .amount = 3 },
        .{ .name = "Hunter's Vigor", .kind = .life, .amount = 4 },
        .{ .name = "Precision", .kind = .light_damage, .amount = 5 },
        .{ .name = "Strong Draw", .kind = .strength, .amount = 2 },
        .{ .name = "Deft Strikes", .kind = .light_damage, .amount = 5, .rider = 1 },
        .{ .name = "Expert Handling", .kind = .light_damage, .amount = 6, .rider = 2 },
        .{ .name = "Watchful", .kind = .dexterity, .amount = 3 },
        .{ .name = "Perfect Technique", .kind = .light_damage, .amount = 15, .rider = 2 },
    },
    .wizard_well = .{
        .{ .name = "Open Mind", .kind = .intelligence, .amount = 2 },
        .{ .name = "Deep Well", .kind = .mana, .amount = 5, .rider = 1 },
        .{ .name = "Slow Tide", .kind = .life, .amount = 3 },
        .{ .name = "Wider Mind", .kind = .intelligence, .amount = 3 },
        .{ .name = "Runic Skin", .kind = .armour, .amount = 2, .rider = 1 },
        .{ .name = "Still Water", .kind = .mana, .amount = 6, .rider = 1 },
        .{ .name = "Veil", .kind = .armour, .amount = 3 },
        .{ .name = "Warded", .kind = .life, .amount = 5 },
        .{ .name = "Brimming", .kind = .mana, .amount = 8, .rider = 2 },
        .{ .name = "Sealed Mind", .kind = .intelligence, .amount = 3 },
        .{ .name = "Overflow", .kind = .mana, .amount = 8, .rider = 1 },
        .{ .name = "Wellspring", .kind = .mana, .amount = 20, .rider = 2 },
    },
    .wizard_cast = .{
        .{ .name = "Attuned", .kind = .intelligence, .amount = 2 },
        .{ .name = "Charged Words", .kind = .spell_damage, .amount = 4, .rider = 1 },
        .{ .name = "Arcana", .kind = .mana, .amount = 5 },
        .{ .name = "Deeper Lore", .kind = .intelligence, .amount = 3 },
        .{ .name = "Potent Runes", .kind = .spell_damage, .amount = 4, .rider = 1 },
        .{ .name = "Sigil Craft", .kind = .spell_damage, .amount = 4 },
        .{ .name = "Inner Quiet", .kind = .mana, .amount = 6 },
        .{ .name = "Focused", .kind = .intelligence, .amount = 3 },
        .{ .name = "Runewright", .kind = .spell_damage, .amount = 5, .rider = 1 },
        .{ .name = "Adept", .kind = .intelligence, .amount = 3 },
        .{ .name = "Spellweaver", .kind = .spell_damage, .amount = 6, .rider = 1 },
        .{ .name = "Arcane Dominion", .kind = .spell_damage, .amount = 15, .rider = 2 },
    },
});

pub const NODES: [N]Node = blk: {
    @setEvalBranchQuota(10_000);
    var out: [N]Node = undefined;
    const roots = std.EnumArray(Arm, [:0]const u8).init(.{
        .warrior = "Iron Thews",
        .rogue = "Quick Hands",
        .wizard = "Lore",
    });
    for (std.enums.values(Arm)) |a| {
        out[armFirst(a)] = .{ .arm = a, .ring = 0, .name = roots.get(a), .grant = .{ .kind = a.stat(), .amount = ROOT_GRANT } };
        for (BRANCHES.get(a)) |b| {
            var i: usize = 0;
            for (BRANCH_RINGS, 0..) |wide, r| for (0..wide) |slot| {
                const e = BANK.get(b)[i];
                const pure = e.kind.attr() != null;
                out[branchFirst(b) + i] = .{
                    .arm = a,
                    .branch = b,
                    .ring = @intCast(r + 1),
                    .slot = @intCast(slot),
                    .name = e.name,
                    .tier = if (r == BRANCH_RINGS.len - 1) .capstone else if (pure) .stat else .interest,
                    .grant = .{ .kind = e.kind, .amount = e.amount },
                    .bump = if (e.rider == 0) null else .{ .kind = a.stat(), .amount = e.rider },
                };
                i += 1;
            };
            std.debug.assert(i == PER_BRANCH);
        }
    }
    const names = std.EnumArray(Seam, [BRIDGE_RINGS.len][:0]const u8).init(.{
        .warrior_rogue = .{ "Rough and Ready", "Duellist" },
        .rogue_wizard = .{ "Keen Mind", "Spellbow" },
        .wizard_warrior = .{ "Stone Mind", "Battlemage" },
    });
    for (std.enums.values(Seam)) |s| for (BRIDGE_RINGS, 0..) |r, bi| {
        const amount: i32 = @intCast(bi + 1);
        out[bridgeFirst(s) + bi] = .{
            .arm = s.from(),
            .seam = s,
            .ring = r,
            .name = names.get(s)[bi],
            .grant = .{ .kind = s.from().stat(), .amount = amount },
            .bump = .{ .kind = s.to().stat(), .amount = amount },
        };
    };
    break :blk out;
};

fn armAngle(a: Arm) f32 {
    return switch (a) {
        .wizard => 0,
        .rogue => std.math.tau / 3.0,
        .warrior => 2.0 * std.math.tau / 3.0,
    };
}
pub fn unitPos(i: usize) Point {
    if (i >= N) return .{ .x = 0, .y = 0 };
    const n = NODES[i];
    var angle = armAngle(n.arm);
    if (n.seam) |s| {
        angle = armAngle(s.from()) - std.math.tau / 6.0;
    } else if (n.branch) |b| {
        angle += if (b.lane() == 0) @as(f32, -0.42) else 0.42;
        const slots = BRANCH_RINGS[n.ring - 1];
        if (slots > 1) {
            const t = @as(f32, @floatFromInt(n.slot)) / @as(f32, @floatFromInt(slots - 1));
            angle += (t * 2 - 1) * (0.130 + 0.032 * @as(f32, @floatFromInt(n.ring)));
        }
    }
    const radius: f32 = @floatFromInt(n.ring + 1);
    return .{ .x = @sin(angle) * radius, .y = -@cos(angle) * radius };
}
pub fn step(cur: usize, dx: f32, dy: f32) usize {
    const push = std.math.hypot(dx, dy);
    if (push < 1e-6) return cur;
    const from = unitPos(cur);
    var best = cur;
    var score: f32 = std.math.floatMax(f32);
    for (0..N) |i| {
        if (i == cur) continue;
        const p = unitPos(i);
        const ax = p.x - from.x;
        const ay = p.y - from.y;
        const dist = std.math.hypot(ax, ay);
        const along = (ax * dx + ay * dy) / push;
        if (dist < 1e-5 or along / dist < 0.5) continue;
        const s = @abs(ax * dy - ay * dx) / push + 0.65 * along;
        if (s < score) {
            score = s;
            best = i;
        }
    }
    return best;
}

test "radial branches preserve capstone routes, bridge crossings, live grants and directional reach" {
    var kinds = std.StaticBitSet(std.enums.values(Kind).len).initEmpty();
    var tiers = [_]usize{0} ** std.enums.values(Tier).len;
    for (NODES, 0..) |n, i| {
        tiers[@intFromEnum(n.tier)] += 1;
        kinds.set(@intFromEnum(n.grant.kind));
        var a = attrs.Attrs.of(.{ .strength = 0, .dexterity = 0, .intelligence = 0 });
        n.apply(&a);
        try std.testing.expect(!std.meta.eql(a, attrs.Attrs.of(.{ .strength = 0, .dexterity = 0, .intelligence = 0 })));
        var buf: [MAX_FEED]usize = undefined;
        const fs = feeders(i, &buf);
        try std.testing.expect(fs.len <= MAX_FEED);
        try std.testing.expectEqual(n.ring == 0, fs.len == 0);
        if (n.tier == .capstone) try std.testing.expectEqual(@as(usize, 2), fs.len);
        for (fs) |f| {
            try std.testing.expect(f < N and f != i);
            try std.testing.expect(linked(i, f));
        }
        if (n.seam) |s| for (bridgeAnchors(s, n.ring)) |anchor| {
            var back: [MAX_FEED]usize = undefined;
            try std.testing.expect(std.mem.indexOfScalar(usize, feeders(anchor, &back), i) != null);
        };
    }
    try std.testing.expectEqual(std.enums.values(Branch).len, tiers[@intFromEnum(Tier.capstone)]);
    try std.testing.expectEqual(std.enums.values(Kind).len, kinds.count());
    var seen = std.StaticBitSet(N).initEmpty();
    seen.set(start(.knight));
    var changed = true;
    while (changed) {
        changed = false;
        for (0..N) |i| if (seen.isSet(i)) {
            for ([_]Point{ .{ .x = 1, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 0, .y = -1 } }) |d| {
                const next = step(i, d.x, d.y);
                if (!seen.isSet(next)) {
                    seen.set(next);
                    changed = true;
                }
            }
        };
    }
    try std.testing.expectEqual(@as(usize, N), seen.count());
    std.debug.print("passives: {d} nodes, {d} stat / {d} interest / {d} capstone; 6 two-way bridges; all nine grant kinds and 81 directional targets checked\n", .{ N, tiers[0], tiers[1], tiers[2] });
}
