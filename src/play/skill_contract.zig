const std = @import("std");
const attrs = @import("attrs.zig");
const damage = @import("damage.zig");
const bow = @import("bow.zig");
const flask = @import("flask.zig");
const consumable = @import("consumable.zig");
const resilience = @import("resilience.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const glacial = @import("glacial.zig");
const actor = @import("actor.zig");

const MELEE_REACH: i32 = 1;

pub const Reticle = enum { bow, leap, swing, rush, ground };
pub const Definition = struct { module: ?type, reticle: ?Reticle = null, delivery: ?attrs.Attack = null };
pub const Declaration = enum { describe, FREE, TELEPORTS, KIND, BOLT, arc, COST, ELEMENT, burst, JUMPS, afflict, AILMENT, CHANCE, around, Ward, knocked, COOLDOWN, MIN_RANGE, BASE, DONE, PIERCES, length, FUEL_DAMAGE, SUPPLY };
pub const Bases = struct { physical: ?damage.Base, element: ?damage.Base };
pub const Ailment = struct { kind: resilience.Kind, chance: u32 };

pub const Contract = struct {
    reticle: ?Reticle,
    delivery: ?attrs.Attack,
    declarations: std.EnumSet(Declaration),
    source: enum { none, arrow, physical, elemental },
    bases: Bases,
    ailment: ?Ailment,
    element: ?damage.Element,
    bolt: ?[]const u8,
    flask_kind: ?flask.Kind,
    supply: ?consumable.Kind,
    free: bool,
    cost: i32,
    cooldown: u8,
    reach: i32,
    nearest: i32,
    done: ?[]const u8,

    pub fn has(self: Contract, comptime name: []const u8) bool {
        return self.declarations.contains(@field(Declaration, name));
    }
};

fn has(comptime d: Definition, comptime name: []const u8) bool {
    return if (d.module) |m| @hasDecl(m, name) else false;
}

fn value(comptime d: Definition, comptime name: []const u8, fallback: anytype) @TypeOf(fallback) {
    return if (has(d, name)) @field(d.module.?, name) else fallback;
}

fn signature(comptime m: type, comptime name: []const u8, comptime params: []const ?type, comptime result: type) bool {
    if (!@hasDecl(m, name)) return false;
    const info = @typeInfo(@TypeOf(@field(m, name)));
    if (info != .@"fn") return false;
    const f = info.@"fn";
    if (f.params.len != params.len or f.return_type != result) return false;
    for (f.params, params) |p, want| if (p.type != want) return false;
    return true;
}

pub fn invalid(comptime d: Definition) ?[]const u8 {
    const m = d.module orelse {
        if (d.reticle != null and (d.reticle != .bow or d.delivery != .ranged)) return "builtin projectile requires bow targeting and ranged delivery";
        return null;
    };
    if (!@hasDecl(m, "DESCRIPTION")) return "module requires DESCRIPTION";
    if ((d.reticle == .bow or has(d, "BASE")) != (d.delivery != null)) return "damage BASE requires explicit delivery (melee, ranged or spell)";
    if (has(d, "ELEMENT") and (!has(d, "BASE") or d.delivery == null)) return "ELEMENT requires BASE and delivery";
    if (has(d, "BOLT") and (d.reticle != .bow or d.delivery != .spell)) return "BOLT requires bow targeting and spell delivery";
    if (d.reticle == .bow and !has(d, "BOLT") and d.delivery != .ranged) return "arrow requires ranged delivery";
    if (has(d, "afflict")) {
        if (!has(d, "AILMENT") or !has(d, "CHANCE") or !@hasDecl(m, "TAKES") or !@hasDecl(m, "VERB")) return "afflict requires AILMENT, CHANCE, TAKES and VERB";
        if (!signature(m, "afflict", &.{ null, *mathx.Rng }, void)) return "afflict must accept (actor: anytype, rng: *Rng) and return void";
        if (!signature(m, "procs", &.{ *mathx.Rng, i16 }, bool)) return "procs must accept (*Rng, i16) and return bool";
        if (!signature(m, "chance", &.{i16}, u32)) return "chance must accept (resist: i16) and return u32";
    }
    if (has(d, "burst")) {
        if (d.reticle != .bow or !has(d, "ELEMENT") or !has(d, "afflict")) return "burst requires an elemental afflicting projectile";
        if (!signature(m, "burst", &.{ *const grid.Level, mathx.P, mathx.P }, glacial.Burst)) return "burst must accept (*const Level, P, P) and return glacial.Burst";
    }
    if (has(d, "around")) {
        if (d.reticle != null or !has(d, "ELEMENT") or !has(d, "afflict")) return "around requires an unaimed elemental afflicting skill";
        if (!signature(m, "around", &.{ *const grid.Level, mathx.P }, glacial.Burst)) return "around must accept (*const Level, P) and return glacial.Burst";
    }
    if (has(d, "JUMPS")) {
        if (d.reticle != .bow or !has(d, "afflict") or has(d, "burst")) return "JUMPS requires a non-burst afflicting projectile";
        if (!signature(m, "chain", &.{ *const grid.Level, *actor.Pool, u16 }, actor.Ids(m.JUMPS + 1))) return "chain must accept (*const Level, *Pool, u16) and return actor.Ids(JUMPS + 1)";
    }
    if (has(d, "PIERCES") and (d.reticle != .bow or has(d, "BOLT") or has(d, "burst") or has(d, "afflict") or has(d, "JUMPS"))) return "PIERCES requires a plain arrow";
    if (has(d, "length") and d.reticle != .ground) return "length requires ground targeting";
    if (has(d, "FUEL_DAMAGE") and (d.reticle != .ground or !has(d, "ELEMENT") or !@hasDecl(m, "area"))) return "FUEL_DAMAGE requires a ground-targeted elemental area";
    if (has(d, "knocked") and !signature(m, "knocked", &.{ *const grid.Level, mathx.P, mathx.Dir, u16 }, ?mathx.P)) return "knocked must accept (*const Level, P, Dir, u16) and return ?P";
    if (has(d, "arc")) {
        if (!@hasDecl(m, "WIDTH")) return "arc requires WIDTH";
        if (!signature(m, "arc", &.{ *const grid.Level, mathx.P, mathx.P }, grid.Area(m.WIDTH))) return "arc must accept (*const Level, P, P) and return grid.Area(WIDTH)";
    }
    if (d.reticle) |r| switch (r) {
        .leap, .rush, .swing => {
            if (!signature(m, "aimable", &.{ *const grid.Level, mathx.P, mathx.P }, bool)) return "targeting requires aimable(*const Level, P, P) bool";
            if (r != .swing and !@hasDecl(m, "RANGE")) return "targeting requires RANGE";
            if (r == .swing and has(d, "arc") and has(d, "knocked")) return "swing takes at most one of arc or knocked";
            if (r == .swing and !has(d, "arc") and !has(d, "knocked") and !has(d, "afflict")) return "a single-target swing requires afflict";
            if (r == .rush) {
                if (!has(d, "knocked")) return "rush requires knocked";
                if (!signature(m, "wayTo", &.{ mathx.P, mathx.P }, ?mathx.Dir)) return "rush requires wayTo(P, P) ?Dir";
                if (!signature(m, "stop", &.{ mathx.P, mathx.P }, mathx.P)) return "rush requires stop(P, P) P";
            }
        },
        .ground => if (!@hasDecl(m, "RANGE")) return "ground targeting requires RANGE",
        .bow => {},
    };
    if (has(d, "Ward") and d.reticle != null) return "Ward must be unaimed";
    if (has(d, "KIND") and (d.reticle != null or d.delivery != null)) return "flasks cannot have targeting or attack delivery";
    if (has(d, "SUPPLY") and (has(d, "COST") or has(d, "COOLDOWN"))) return "consumables cannot cost mana or cool down";
    if (has(d, "TELEPORTS") and d.reticle != .leap) return "TELEPORTS requires leap targeting";
    return null;
}

pub fn interpret(comptime name: []const u8, comptime d: Definition) Contract {
    if (comptime invalid(d)) |why| @compileError("skill " ++ name ++ ": " ++ why);
    var declarations = std.EnumSet(Declaration).initEmpty();
    for (std.enums.values(Declaration)) |decl| if (has(d, @tagName(decl))) {
        declarations.insert(decl);
    };
    const arrow = d.reticle == .bow and !has(d, "BOLT");
    const elemental = has(d, "ELEMENT");
    return .{
        .reticle = d.reticle,
        .delivery = d.delivery,
        .declarations = declarations,
        .source = if (arrow) .arrow else if (elemental) .elemental else if (has(d, "BASE")) .physical else .none,
        .bases = .{ .physical = if (arrow) bow.BASE else if (!elemental) value(d, "BASE", @as(?damage.Base, null)) else null, .element = if (elemental) d.module.?.BASE else null },
        .ailment = if (has(d, "afflict")) .{ .kind = d.module.?.AILMENT, .chance = d.module.?.CHANCE } else null,
        .element = value(d, "ELEMENT", @as(?damage.Element, null)),
        .bolt = value(d, "BOLT", @as(?[]const u8, null)),
        .flask_kind = value(d, "KIND", @as(?flask.Kind, null)),
        .supply = value(d, "SUPPLY", @as(?consumable.Kind, null)),
        .free = value(d, "FREE", false),
        .cost = value(d, "COST", @as(i32, 0)),
        .cooldown = value(d, "COOLDOWN", @as(u8, 0)),
        .reach = if (d.reticle) |r| switch (r) {
            .bow => bow.RANGE,
            .swing => MELEE_REACH,
            .leap, .rush, .ground => d.module.?.RANGE,
        } else 0,
        .nearest = value(d, "MIN_RANGE", MELEE_REACH),
        .done = value(d, "DONE", @as(?[]const u8, null)),
    };
}

test "skill contract diagnostics reject missing delivery status requirements and wrong geometry signatures" {
    const MissingDelivery = struct {
        pub const DESCRIPTION = "sample";
        pub const BASE = damage.Base{ .lo = 1, .hi = 2 };
    };
    const MissingStatus = struct {
        pub const DESCRIPTION = "sample";
        pub fn afflict(_: anytype, _: *mathx.Rng) void {}
    };
    const BadGeometry = struct {
        pub const DESCRIPTION = "sample";
        pub fn aimable(_: mathx.P) bool {
            return true;
        }
    };
    try std.testing.expectEqualStrings("damage BASE requires explicit delivery (melee, ranged or spell)", comptime invalid(.{ .module = MissingDelivery }).?);
    try std.testing.expectEqualStrings("afflict requires AILMENT, CHANCE, TAKES and VERB", comptime invalid(.{ .module = MissingStatus }).?);
    try std.testing.expectEqualStrings("targeting requires aimable(*const Level, P, P) bool", comptime invalid(.{ .module = BadGeometry, .reticle = .leap }).?);
    std.debug.print("skill contracts: 3 incomplete definitions rejected with actionable delivery, status and signature diagnostics\n", .{});
}
