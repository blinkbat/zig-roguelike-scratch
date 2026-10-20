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
    pub fn lane(b: Branch) Lane {
        return BRANCH_POSITIONS.get(b).lane;
    }
    pub fn on(a: Arm, lane_: Lane) Branch {
        return BRANCHES.get(a)[@intFromEnum(lane_)];
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
/// An arm's two branches: the one whose bridges reach the next arm in `Arm`'s order, then the one reached from the previous.
pub const Lane = enum { next, previous };
const BRANCHES = std.EnumArray(Arm, [std.enums.values(Lane).len]Branch).init(.{
    .warrior = .{ .warrior_life, .warrior_berserk },
    .rogue = .{ .rogue_evade, .rogue_ranged },
    .wizard = .{ .wizard_well, .wizard_cast },
});
const BRANCH_POSITIONS = blk: {
    var out = std.EnumArray(Branch, struct { arm: Arm, lane: Lane }).initUndefined();
    var seen = std.EnumSet(Branch).initEmpty();
    for (std.enums.values(Arm)) |a| for (BRANCHES.get(a), 0..) |b, lane| {
        if (seen.contains(b)) @compileError(@tagName(b) ++ " belongs to more than one passive branch");
        seen.insert(b);
        out.set(b, .{ .arm = a, .lane = @enumFromInt(lane) });
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
/// What a grant is about, which colours its node.
pub const Group = enum { attribute, life, mana, offense, defense };
/// Effects the game reads off the allocated tree rather than off the attributes.
pub const Perks = struct {
    life_on_hit: i32 = 0,
    life_on_kill: i32 = 0,
    life_flask: i32 = 0,
    cull: i32 = 0,
    mana_regen: i32 = 0,
    mana_cost: i32 = 0,
};
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
    crit,
    dodge,
    life_on_hit,
    life_on_kill,
    life_flask,
    cull,
    mana_regen,
    mana_cost,

    pub fn perk(k: Kind) bool {
        return switch (k) {
            inline else => |t| @hasField(Perks, @tagName(t)),
        };
    }

    pub fn group(k: Kind) Group {
        return switch (k) {
            .strength, .dexterity, .intelligence => .attribute,
            .life, .life_on_hit, .life_on_kill, .life_flask => .life,
            .mana, .mana_regen, .mana_cost => .mana,
            .heavy_damage, .light_damage, .spell_damage, .crit, .cull => .offense,
            .armour, .dodge => .defense,
        };
    }

    pub fn abbrev(k: Kind) [:0]const u8 {
        return switch (k) {
            .strength => "Str",
            .dexterity => "Dex",
            .intelligence => "Int",
            else => unreachable,
        };
    }

    /// The damage it raises by a percentage, for a damage kind.
    pub fn style(k: Kind) ?attrs.Style {
        return switch (k) {
            inline else => |t| if (comptime std.mem.endsWith(u8, @tagName(t), DAMAGE)) @field(attrs.Style, @tagName(t)[0 .. @tagName(t).len - DAMAGE.len]) else null,
        };
    }
    const DAMAGE = "_damage";

    /// What it adds to, for a kind that is not a damage percentage.
    pub fn bonus(k: Kind) ?attrs.Bonus {
        return switch (k) {
            inline else => |t| if (@hasField(attrs.Bonus, @tagName(t))) @field(attrs.Bonus, @tagName(t)) else null,
        };
    }

    comptime {
        for (std.enums.values(Kind)) |k| {
            const homes = @as(u8, @intFromBool(k.style() != null)) + @intFromBool(k.bonus() != null) + @intFromBool(k.perk()) + @intFromBool(k == .crit or k == .dodge);
            std.debug.assert(homes == 1);
        }
    }

    /// The attribute it raises, for a pure attribute kind.
    pub fn attr(k: Kind) ?attrs.Attr {
        return switch (k) {
            inline else => |t| comptime if (@hasField(attrs.Attr, @tagName(t))) @field(attrs.Attr, @tagName(t)) else null,
        };
    }
};
/// What each class origin grants of its arm's attribute.
pub const ROOT_GRANT: i32 = 2;
pub const Grant = struct {
    kind: Kind,
    amount: i32,

    pub fn apply(g: Grant, a: *attrs.Attrs) void {
        switch (g.kind) {
            .crit => a.crit_bonus += g.amount,
            .dodge => a.dodge_bonus += g.amount,
            else => if (g.kind.style()) |s| {
                a.damage_bonus.getPtr(s).* += g.amount;
            } else if (g.kind.bonus()) |b| a.add(b, g.amount),
        }
    }

    pub fn perk(g: Grant, p: *Perks) void {
        switch (g.kind) {
            inline else => |t| if (comptime @hasField(Perks, @tagName(t))) {
                @field(p, @tagName(t)) += g.amount;
            },
        }
    }

    /// The whole modifier: "+4% Heavy weapon damage".
    pub fn write(g: Grant, w: anytype) void {
        const n = g.amount;
        (switch (g.kind) {
            .armour => w.print("+{d}% physical damage reduction", .{n}),
            .crit => w.print("+{d}% critical strike chance", .{n}),
            .dodge => w.print("+{d}% chance to dodge attacks", .{n}),
            .life_on_hit => w.print("Heal {d} life for each foe a blow damages", .{n}),
            .life_on_kill => w.print("Heal {d} life for each foe a blow kills", .{n}),
            .life_flask => w.print("+{d}% life flask recovery", .{n}),
            .cull => w.print("Blows kill foes left at {d}% life or less", .{n}),
            .mana_regen => w.print("+{d} mana recovered per turn", .{n}),
            .mana_cost => w.print("Skills cost {d}% less mana", .{n}),
            else => if (g.kind.style()) |s| w.print("+{d}% {s}", .{ n, s.label() }) else w.print("+{d} to {s}", .{ n, g.kind.bonus().?.label() }),
        }) catch {};
    }

    /// The tree's label is this over `word`: "+4%" over "Heavy".
    pub fn writeAmount(g: Grant, w: anytype) void {
        const sign: []const u8 = switch (g.kind) {
            .mana_cost => "-",
            .cull => "",
            else => "+",
        };
        const percent = g.kind.style() != null or switch (g.kind) {
            .armour, .crit, .dodge, .life_flask, .cull, .mana_cost => true,
            else => false,
        };
        w.print("{s}{d}{s}", .{ sign, g.amount, if (percent) "%" else "" }) catch {};
    }

    pub fn word(g: Grant) [:0]const u8 {
        return switch (g.kind) {
            .strength, .dexterity, .intelligence => g.kind.abbrev(),
            .life => "Life",
            .mana => "Mana",
            .armour => "Armour",
            .heavy_damage => "Heavy",
            .light_damage => "Light",
            .spell_damage => "Spell",
            .crit => "Crit",
            .dodge => "Dodge",
            .life_on_hit => "Leech",
            .life_on_kill => "On kill",
            .life_flask => "Flask",
            .cull => "Cull",
            .mana_regen => "Regen",
            .mana_cost => "Cost",
        };
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

    pub fn perk(n: Node, p: *Perks) void {
        n.grant.perk(p);
        if (n.bump) |g| g.perk(p);
    }

    /// Its grant's, or both attributes of a bridge.
    pub fn word(n: Node) [:0]const u8 {
        const s = n.seam orelse return n.grant.word();
        return switch (s) {
            inline else => |t| comptime t.from().stat().abbrev() ++ "/" ++ t.to().stat().abbrev(),
        };
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
const PER_ARM = 1 + std.enums.values(Lane).len * PER_BRANCH;
const NTREE = std.enums.values(Arm).len * PER_ARM;
pub const N = NTREE + std.enums.values(Seam).len * BRIDGE_RINGS.len;
pub const RINGS = BRANCH_RINGS.len + 1;
pub const HUB = N;
pub const Point = struct { x: f32, y: f32 };

fn armFirst(a: Arm) usize {
    return @as(usize, @intFromEnum(a)) * PER_ARM;
}
pub fn branchFirst(b: Branch) usize {
    return armFirst(b.arm()) + 1 + @as(usize, @intFromEnum(b.lane())) * PER_BRANCH;
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
    return .{ ringFirst(Branch.on(s.from(), .next), br), ringFirst(Branch.on(s.to(), .previous), br) + BRANCH_RINGS[br] - 1 };
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

const Entry = struct {
    name: [:0]const u8,
    grant: Grant,
    rider: ?Grant = null,

    fn ride(e: Entry, kind: Kind, amount: i32) Entry {
        var out = e;
        out.rider = .{ .kind = kind, .amount = amount };
        return out;
    }
};
fn entry(name: [:0]const u8, kind: Kind, amount: i32) Entry {
    return .{ .name = name, .grant = .{ .kind = kind, .amount = amount } };
}
const BANK = std.EnumArray(Branch, [PER_BRANCH]Entry).init(.{
    .warrior_life = .{
        entry("Warrior's Blood", .strength, 2),
        entry("Thick Hide", .armour, 2).ride(.strength, 1),
        entry("Stout Heart", .life, 3).ride(.strength, 1),
        entry("Boiled Leather", .armour, 2).ride(.strength, 1),
        entry("Stubborn Flesh", .strength, 3),
        entry("Scar Tissue", .life_flask, 20).ride(.strength, 1),
        entry("Stalwart", .armour, 3),
        entry("Unshaken", .strength, 3),
        entry("Deep Roots", .life, 5),
        entry("Ironbound", .armour, 4).ride(.strength, 2),
        entry("Long Draught", .life_flask, 25).ride(.strength, 1),
        entry("Sanguine Pact", .life_on_hit, 1).ride(.strength, 3),
    },
    .warrior_berserk = .{
        entry("Reaver", .life_on_kill, 1),
        entry("Heavy Hands", .heavy_damage, 4).ride(.strength, 1),
        entry("Culling Blow", .cull, 5),
        entry("Brute Force", .strength, 3),
        entry("Crushing Blows", .heavy_damage, 4).ride(.strength, 1),
        entry("Butcher's Eye", .crit, 3).ride(.strength, 1),
        entry("Red Harvest", .life_on_kill, 2),
        entry("Battle Hardened", .armour, 3),
        entry("Executioner", .cull, 5).ride(.strength, 1),
        entry("Frenzy", .heavy_damage, 6).ride(.strength, 1),
        entry("Blood Rush", .strength, 3),
        entry("Berserk", .heavy_damage, 15).ride(.cull, 10),
    },
    .rogue_evade = .{
        entry("Fleet", .dodge, 3),
        entry("Second Wind", .life, 3).ride(.dexterity, 1),
        entry("Light Step", .dexterity, 2),
        entry("Sure Feet", .dexterity, 3),
        entry("Tumbler", .dodge, 3).ride(.dexterity, 1),
        entry("Long Stride", .dexterity, 2),
        entry("Wind at Heel", .dodge, 4),
        entry("Deep Lungs", .life, 5).ride(.dexterity, 1),
        entry("Warded Blood", .armour, 3),
        entry("Slip", .dodge, 4).ride(.dexterity, 1),
        entry("Survivor", .life_flask, 25).ride(.dexterity, 2),
        entry("Untouchable", .dodge, 10).ride(.dexterity, 4),
    },
    .rogue_ranged = .{
        entry("Keen Eye", .crit, 2),
        entry("Practised Arm", .light_damage, 4).ride(.dexterity, 1),
        entry("Wayfinder", .dexterity, 2),
        entry("Light Touch", .light_damage, 4).ride(.dexterity, 1),
        entry("Steady Hand", .dexterity, 3),
        entry("Hunter's Vigor", .life_on_kill, 1),
        entry("Precision", .crit, 3),
        entry("Strong Draw", .strength, 2),
        entry("Deft Strikes", .light_damage, 5).ride(.dexterity, 1),
        entry("Expert Handling", .light_damage, 6).ride(.dexterity, 2),
        entry("Watchful", .crit, 4),
        entry("Deadeye", .crit, 8).ride(.light_damage, 10),
    },
    .wizard_well = .{
        entry("Open Mind", .intelligence, 2),
        entry("Deep Well", .mana, 5).ride(.intelligence, 1),
        entry("Slow Tide", .mana_regen, 1),
        entry("Wider Mind", .intelligence, 3),
        entry("Runic Skin", .armour, 2).ride(.intelligence, 1),
        entry("Still Water", .mana, 6).ride(.intelligence, 1),
        entry("Veil", .armour, 3),
        entry("Warded", .life, 5),
        entry("Brimming", .mana, 8).ride(.intelligence, 2),
        entry("Sealed Mind", .intelligence, 3),
        entry("Overflow", .mana_regen, 1).ride(.intelligence, 1),
        entry("Wellspring", .mana_regen, 2).ride(.mana, 10),
    },
    .wizard_cast = .{
        entry("Attuned", .mana_cost, 10),
        entry("Charged Words", .spell_damage, 4).ride(.intelligence, 1),
        entry("Arcana", .mana, 5),
        entry("Deeper Lore", .intelligence, 3),
        entry("Potent Runes", .spell_damage, 4).ride(.intelligence, 1),
        entry("Sigil Craft", .crit, 3).ride(.intelligence, 1),
        entry("Inner Quiet", .mana_cost, 10),
        entry("Focused", .intelligence, 3),
        entry("Runewright", .spell_damage, 5).ride(.intelligence, 1),
        entry("Adept", .intelligence, 3),
        entry("Spellweaver", .spell_damage, 6).ride(.intelligence, 1),
        entry("Arcane Dominion", .spell_damage, 15).ride(.mana_cost, 10),
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
                const capstone = r == BRANCH_RINGS.len - 1;
                if (e.rider) |rider| {
                    if (rider.kind == e.grant.kind) @compileError(e.name ++ " rides its own grant twice");
                    if (!capstone and rider.kind.attr() == null) @compileError(e.name ++ ": only a capstone's rider may be more than an attribute");
                }
                out[branchFirst(b) + i] = .{
                    .arm = a,
                    .branch = b,
                    .ring = @intCast(r + 1),
                    .slot = @intCast(slot),
                    .name = e.name,
                    .tier = if (capstone) .capstone else if (e.grant.kind.attr() != null) .stat else .interest,
                    .grant = e.grant,
                    .bump = e.rider,
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

/// Radians a branch turns off its arm's bearing, and its ring's slots spread either side, wider further out.
const LANE_TURN: f32 = 0.42;
const SLOT_TURN: f32 = 0.130;
const SLOT_TURN_PER_RING: f32 = 0.032;
/// A step browses only to nodes within 60 degrees of the push, sideways distance costing more than distance ahead.
const STEP_COS: f32 = 0.5;
const STEP_AHEAD: f32 = 0.65;

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
        angle += if (b.lane() == .next) -LANE_TURN else LANE_TURN;
        const slots = BRANCH_RINGS[n.ring - 1];
        if (slots > 1) {
            const t = @as(f32, @floatFromInt(n.slot)) / @as(f32, @floatFromInt(slots - 1));
            angle += (t * 2 - 1) * (SLOT_TURN + SLOT_TURN_PER_RING * @as(f32, @floatFromInt(n.ring)));
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
        if (dist < 1e-5 or along / dist < STEP_COS) continue;
        const s = @abs(ax * dy - ay * dx) / push + STEP_AHEAD * along;
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
        for ([_]?Grant{ n.grant, n.bump }) |maybe| {
            const g = maybe orelse continue;
            var a = attrs.Attrs.of(.{ .strength = 0, .dexterity = 0, .intelligence = 0 });
            var p = Perks{};
            g.apply(&a);
            g.perk(&p);
            const changed = !std.meta.eql(a, attrs.Attrs.of(.{ .strength = 0, .dexterity = 0, .intelligence = 0 })) or !std.meta.eql(p, Perks{});
            try std.testing.expect(changed);
            try std.testing.expectEqual(g.kind.perk(), !std.meta.eql(p, Perks{}));
        }
        if (n.ring == 0) try std.testing.expect(!n.grant.kind.perk() and n.bump == null);
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
    std.debug.print("passives: {d} nodes, {d} stat / {d} interest / {d} capstone; 6 two-way bridges; all {d} grant kinds and 81 directional targets checked\n", .{ N, tiers[0], tiers[1], tiers[2], kinds.count() });
}
