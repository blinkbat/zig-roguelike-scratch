const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const skillbar = @import("../play/skillbar.zig");
const items = @import("../play/items.zig");
const consumable = @import("../play/consumable.zig");
const look = @import("look.zig");
const raster = @import("raster.zig");

pub fn drawDirection(d: mathx.Dir, cx: i32, cy: i32, size: i32, col: rl.Color) void {
    const delta = d.delta();
    const unit: f32 = if (d.diagonal()) std.math.sqrt1_2 else 1;
    const dx = @as(f32, @floatFromInt(delta.x)) * unit;
    const dy = @as(f32, @floatFromInt(delta.y)) * unit;
    const scale = @as(f32, @floatFromInt(size)) / SKILL_GRID;
    const x: f32 = @floatFromInt(cx);
    const y: f32 = @floatFromInt(cy);
    const lines = [_][4]f32{ .{ -12, 0, 12, 0 }, .{ 4, -8, 12, 0 }, .{ 12, 0, 4, 8 } };
    for (lines) |line| {
        const from = rl.Vector2{
            .x = x + (dx * line[0] - dy * line[1]) * scale,
            .y = y + (dy * line[0] + dx * line[1]) * scale,
        };
        const to = rl.Vector2{
            .x = x + (dx * line[2] - dy * line[3]) * scale,
            .y = y + (dy * line[2] + dx * line[3]) * scale,
        };
        stroke(from, to, scale, col);
    }
}

const FLASK = [_][4]f32{
    .{ 13, 4, 19, 4 },
    .{ 13, 4, 13, 11 },
    .{ 19, 4, 19, 11 },
    .{ 13, 11, 6, 18 },
    .{ 19, 11, 26, 18 },
    .{ 6, 18, 6, 26 },
    .{ 26, 18, 26, 26 },
    .{ 6, 28, 26, 28 },
};

const ARROW_LINES = [_][4]f32{
    .{ 6, 26, 26, 6 },
    .{ 16, 6, 26, 6 },
    .{ 26, 6, 26, 16 },
};

const SHIELD_LINES = [_][4]f32{
    .{ 6, 5, 26, 5 },
    .{ 26, 5, 26, 16 },
    .{ 26, 16, 16, 28 },
    .{ 16, 28, 6, 16 },
    .{ 6, 16, 6, 5 },
};

fn skillLines(a: skillbar.Act) []const [4]f32 {
    return switch (a) {
        .caltrops => &.{ .{ 4, 25, 13, 8 }, .{ 13, 8, 22, 25 }, .{ 6, 18, 26, 18 }, .{ 23, 8, 23, 27 } },
        .overwatch => &.{ .{ 3, 16, 10, 8 }, .{ 10, 8, 22, 8 }, .{ 22, 8, 29, 16 }, .{ 29, 16, 22, 24 }, .{ 22, 24, 10, 24 }, .{ 10, 24, 3, 16 }, .{ 16, 11, 16, 21 } },
        .steady_aim => &.{ .{ 16, 3, 16, 29 }, .{ 3, 16, 29, 16 }, .{ 8, 8, 24, 8 }, .{ 8, 24, 24, 24 }, .{ 8, 8, 8, 24 }, .{ 24, 8, 24, 24 } },
        .gravity_well => &.{ .{ 3, 3, 12, 12 }, .{ 29, 3, 20, 12 }, .{ 3, 29, 12, 20 }, .{ 29, 29, 20, 20 }, .{ 9, 12, 12, 12 }, .{ 12, 9, 12, 12 }, .{ 20, 23, 20, 20 }, .{ 23, 20, 20, 20 } },
        .combustion => &.{ .{ 5, 27, 12, 17 }, .{ 12, 17, 9, 10 }, .{ 9, 10, 18, 3 }, .{ 18, 3, 17, 14 }, .{ 17, 14, 24, 9 }, .{ 24, 9, 28, 22 }, .{ 28, 22, 20, 28 }, .{ 5, 27, 20, 28 } },
        .arcane_barrier => &.{ .{ 4, 7, 28, 7 }, .{ 4, 25, 28, 25 }, .{ 7, 7, 7, 25 }, .{ 16, 7, 16, 25 }, .{ 25, 7, 25, 25 }, .{ 4, 16, 28, 16 } },
        .guard => &.{ .{ 5, 5, 27, 5 }, .{ 5, 5, 7, 22 }, .{ 27, 5, 25, 22 }, .{ 7, 22, 16, 29 }, .{ 25, 22, 16, 29 }, .{ 16, 9, 16, 22 } },
        .whirlwind => &.{ .{ 6, 6, 23, 6 }, .{ 23, 6, 28, 14 }, .{ 28, 14, 23, 26 }, .{ 23, 26, 8, 26 }, .{ 8, 26, 4, 18 }, .{ 4, 18, 16, 10 }, .{ 16, 10, 23, 16 }, .{ 23, 16, 17, 22 } },
        .unyielding => &.{ .{ 7, 3, 7, 25 }, .{ 7, 25, 16, 29 }, .{ 16, 29, 25, 25 }, .{ 25, 25, 25, 3 }, .{ 11, 20, 22, 9 }, .{ 16, 9, 22, 9 }, .{ 22, 9, 22, 15 } },
        .rend => &.{ .{ 5, 9, 17, 27 }, .{ 11, 5, 23, 23 }, .{ 17, 3, 27, 18 }, .{ 24, 25, 24, 29 } },
        .war_cry => &.{ .{ 3, 12, 9, 16 }, .{ 9, 16, 3, 20 }, .{ 13, 9, 17, 16 }, .{ 17, 16, 13, 23 }, .{ 19, 6, 24, 16 }, .{ 24, 16, 19, 26 }, .{ 25, 3, 30, 16 }, .{ 30, 16, 25, 29 } },
        .piercing_shot => &(ARROW_LINES ++ [_][4]f32{
            .{ 8, 18, 14, 24 },
            .{ 16, 10, 22, 16 },
        }),
        .shatter => &.{ .{ 16, 3, 27, 16 }, .{ 27, 16, 16, 29 }, .{ 16, 29, 5, 16 }, .{ 5, 16, 16, 3 }, .{ 16, 3, 13, 13 }, .{ 13, 13, 19, 18 }, .{ 19, 18, 16, 29 }, .{ 13, 13, 5, 16 } },
        .fire_wall => &.{ .{ 4, 27, 8, 15 }, .{ 8, 15, 12, 27 }, .{ 12, 27, 16, 8 }, .{ 16, 8, 20, 27 }, .{ 20, 27, 24, 15 }, .{ 24, 15, 28, 27 }, .{ 4, 28, 28, 28 } },
        .shoot => &(ARROW_LINES ++ [_][4]f32{
            .{ 5, 19, 12, 19 },
            .{ 12, 19, 12, 26 },
        }),
        .burning_arrow => &.{
            .{ 13, 26, 27, 12 },
            .{ 19, 12, 27, 12 },
            .{ 27, 12, 27, 20 },
            .{ 9, 23, 4, 18 },
            .{ 4, 18, 4, 14 },
            .{ 4, 14, 11, 5 },
            .{ 11, 5, 10, 13 },
            .{ 10, 13, 15, 10 },
            .{ 15, 10, 17, 17 },
            .{ 17, 17, 13, 22 },
        },
        .glacial_shot => &.{
            .{ 5, 27, 25, 7 },
            .{ 17, 7, 25, 7 },
            .{ 25, 7, 25, 15 },
            .{ 5, 6, 15, 16 },
            .{ 5, 16, 15, 6 },
            .{ 3, 11, 17, 11 },
            .{ 10, 4, 10, 18 },
        },
        .juke => &.{
            .{ 6, 7, 15, 16 },
            .{ 15, 16, 6, 25 },
            .{ 17, 7, 26, 16 },
            .{ 26, 16, 17, 25 },
        },
        .spark => &.{
            .{ 19, 3, 9, 17 },
            .{ 9, 17, 17, 17 },
            .{ 17, 17, 12, 29 },
            .{ 12, 29, 24, 13 },
            .{ 24, 13, 16, 13 },
            .{ 16, 13, 19, 3 },
        },
        .blink => &.{
            .{ 4, 16, 8, 16 },
            .{ 6, 14, 6, 18 },
            .{ 12, 16, 16, 16 },
            .{ 20, 16, 28, 16 },
            .{ 24, 10, 24, 22 },
            .{ 20, 12, 28, 20 },
            .{ 20, 20, 28, 12 },
        },
        .shield_bash => &(SHIELD_LINES ++ [_][4]f32{
            .{ 16, 9, 16, 22 },
        }),
        .pinning_shot => &.{
            .{ 16, 4, 16, 24 },
            .{ 11, 19, 16, 24 },
            .{ 21, 19, 16, 24 },
            .{ 12, 4, 16, 8 },
            .{ 20, 4, 16, 8 },
            .{ 5, 27, 27, 27 },
        },
        .barbed_arrow => &(ARROW_LINES ++ [_][4]f32{
            .{ 11, 21, 7, 21 },
            .{ 11, 21, 11, 25 },
            .{ 16, 16, 12, 16 },
            .{ 16, 16, 16, 20 },
        }),
        .frost_nova => &.{
            .{ 16, 3, 16, 29 },
            .{ 3, 16, 29, 16 },
            .{ 7, 7, 25, 25 },
            .{ 7, 25, 25, 7 },
            .{ 13, 4, 16, 7 },
            .{ 19, 4, 16, 7 },
            .{ 13, 28, 16, 25 },
            .{ 19, 28, 16, 25 },
        },
        .fireball => &.{
            .{ 14, 10, 20, 12 },
            .{ 20, 12, 22, 18 },
            .{ 22, 18, 20, 24 },
            .{ 20, 24, 14, 26 },
            .{ 14, 26, 8, 24 },
            .{ 8, 24, 6, 18 },
            .{ 6, 18, 8, 12 },
            .{ 8, 12, 14, 10 },
            .{ 20, 12, 27, 5 },
            .{ 22, 18, 29, 13 },
            .{ 14, 10, 18, 3 },
        },
        .chain_lightning => &.{
            .{ 4, 27, 11, 15 },
            .{ 11, 15, 17, 21 },
            .{ 17, 21, 22, 9 },
            .{ 22, 9, 28, 14 },
            .{ 9, 13, 13, 17 },
            .{ 15, 19, 19, 23 },
            .{ 20, 7, 24, 11 },
        },
        .mana_shield => &(SHIELD_LINES ++ [_][4]f32{
            .{ 16, 9, 21, 15 },
            .{ 21, 15, 16, 21 },
            .{ 16, 21, 11, 15 },
            .{ 11, 15, 16, 9 },
        }),
        .charge => &.{
            .{ 14, 16, 28, 16 },
            .{ 22, 10, 28, 16 },
            .{ 28, 16, 22, 22 },
            .{ 4, 10, 12, 10 },
            .{ 2, 16, 10, 16 },
            .{ 4, 22, 12, 22 },
        },
        .life_flask => &(FLASK ++ [_][4]f32{
            .{ 16, 17, 16, 25 },
            .{ 12, 21, 20, 21 },
        }),
        .mana_flask => &(FLASK ++ [_][4]f32{
            .{ 11, 21, 14, 18 },
            .{ 14, 18, 18, 24 },
            .{ 18, 24, 21, 21 },
        }),
        .bandage => &.{
            .{ 4, 12, 28, 12 },
            .{ 4, 20, 28, 20 },
            .{ 4, 12, 4, 20 },
            .{ 28, 12, 28, 20 },
            .{ 12, 12, 12, 20 },
            .{ 20, 12, 20, 20 },
        },
        .smelling_salts => &.{
            .{ 10, 14, 22, 14 },
            .{ 10, 14, 10, 28 },
            .{ 22, 14, 22, 28 },
            .{ 10, 28, 22, 28 },
            .{ 13, 10, 19, 10 },
            .{ 12, 7, 14, 3 },
            .{ 16, 7, 18, 3 },
            .{ 20, 7, 22, 3 },
        },
        .frost_vial => &(FLASK ++ [_][4]f32{
            .{ 16, 17, 16, 25 },
            .{ 12, 19, 20, 23 },
            .{ 12, 23, 20, 19 },
        }),
        .cleave => &.{
            .{ 4, 26, 24, 6 },
            .{ 20, 4, 27, 11 },
            .{ 8, 20, 12, 24 },
            .{ 6, 10, 4, 16 },
            .{ 22, 28, 16, 28 },
            .{ 4, 16, 6, 22 },
            .{ 16, 28, 10, 26 },
        },
        .wait => &.{
            .{ 7, 5, 25, 5 },
            .{ 7, 27, 25, 27 },
            .{ 9, 5, 9, 10 },
            .{ 9, 10, 23, 22 },
            .{ 23, 22, 23, 27 },
            .{ 23, 5, 23, 10 },
            .{ 23, 10, 9, 22 },
            .{ 9, 22, 9, 27 },
        },
        .secondary => &.{
            .{ 6, 10, 26, 10 },
            .{ 20, 4, 26, 10 },
            .{ 26, 10, 20, 16 },
            .{ 26, 22, 6, 22 },
            .{ 12, 16, 6, 22 },
            .{ 6, 22, 12, 28 },
        },
    };
}

fn path(comptime points: []const [2]f32) [points.len - 1][4]f32 {
    var out: [points.len - 1][4]f32 = undefined;
    for (&out, points[0 .. points.len - 1], points[1..]) |*line, a, b| line.* = .{ a[0], a[1], b[0], b[1] };
    return out;
}

fn closed(comptime points: []const [2]f32) [points.len][4]f32 {
    return path(&(points[0..points.len].* ++ [_][2]f32{points[0]}));
}

/// `n` sides round `cx`, `cy`, the first corner `turn` of a side clockwise from straight up.
fn polygon(comptime cx: f32, comptime cy: f32, comptime r: f32, comptime n: usize, comptime turn: f32) [n][4]f32 {
    var out: [n][4]f32 = undefined;
    for (&out, 0..) |*line, i| {
        const a = corner(cx, cy, r, n, turn, i);
        const b = corner(cx, cy, r, n, turn, i + 1);
        line.* = .{ a[0], a[1], b[0], b[1] };
    }
    return out;
}

fn corner(cx: f32, cy: f32, r: f32, n: usize, turn: f32, i: usize) [2]f32 {
    const a = std.math.tau * (@as(f32, @floatFromInt(i)) + turn) / @as(f32, @floatFromInt(n)) - std.math.pi / 2.0;
    return .{ cx + r * @cos(a), cy + r * @sin(a) };
}

const WAND = [_][4]f32{ .{ 6, 26, 18, 14 } };
const TUNIC = path(&.{ .{ 12, 4 }, .{ 16, 9 }, .{ 20, 4 } }) ++ path(&.{ .{ 12, 4 }, .{ 5, 7 }, .{ 8, 15 }, .{ 8, 28 }, .{ 24, 28 }, .{ 24, 15 }, .{ 27, 7 }, .{ 20, 4 } });
const GLOVE = path(&.{ .{ 8, 22 }, .{ 8, 8 }, .{ 10, 5 }, .{ 22, 5 }, .{ 24, 8 }, .{ 24, 22 } }) ++ [_][4]f32{ .{ 13.3, 5, 13.3, 13 }, .{ 18.7, 5, 18.7, 13 } } ++ path(&.{ .{ 8, 20 }, .{ 4, 15 }, .{ 5, 11 }, .{ 8, 12 } });
const BOOT = closed(&.{ .{ 9, 4 }, .{ 9, 27 }, .{ 27, 27 }, .{ 27, 23 }, .{ 19, 18 }, .{ 19, 4 } });
const RING_BAND = polygon(16, 21, 7.5, 12, 0.5);

const ITEM_LINES = std.EnumArray(items.Kind, []const [4]f32).init(.{
    .sword = &([_][4]f32{ .{ 12, 20, 25, 7 }, .{ 9, 17, 15, 23 }, .{ 12, 20, 7, 25 } }),
    .axe = &([_][4]f32{ .{ 16, 3, 16, 29 } } ++ path(&.{ .{ 16, 8 }, .{ 21, 7 }, .{ 25, 4 }, .{ 28, 12 }, .{ 25, 20 }, .{ 21, 16 }, .{ 16, 15 } }) ++ path(&.{ .{ 16, 8 }, .{ 11, 7 }, .{ 7, 4 }, .{ 4, 12 }, .{ 7, 20 }, .{ 11, 16 }, .{ 16, 15 } })),
    .bow = &(path(&.{ .{ 21, 6 }, .{ 15, 9 }, .{ 12, 16 }, .{ 15, 23 }, .{ 21, 26 } }) ++ [_][4]f32{ .{ 21, 6, 21, 26 } }),
    .staff = &([_][4]f32{ .{ 16, 8, 16, 29 } } ++ path(&.{ .{ 16, 8 }, .{ 17, 4 }, .{ 21, 3 }, .{ 24, 6 }, .{ 23, 10 } }) ++ [_][4]f32{ .{ 16, 16, 12, 13 } }),
    .longsword = &([_][4]f32{ .{ 12, 20, 27, 5 }, .{ 8, 16, 16, 24 }, .{ 12, 20, 6, 26 }, .{ 4, 24, 8, 28 } }),
    .mace = &(polygon(16, 10, 7, 8, 0.5) ++ [_][4]f32{ .{ 16, 17, 16, 29 }, .{ 9.5, 10, 5, 10 }, .{ 22.5, 10, 27, 10 } }),
    .greatsword = &(path(&.{ .{ 11, 17 }, .{ 23, 5 }, .{ 28, 4 } }) ++ path(&.{ .{ 15, 21 }, .{ 27, 9 }, .{ 28, 4 } }) ++ [_][4]f32{ .{ 7, 13, 19, 25 }, .{ 13, 19, 5, 27 } }),
    .crossbow = &([_][4]f32{ .{ 16, 4, 16, 29 } } ++ path(&.{ .{ 4, 14 }, .{ 9, 9 }, .{ 23, 9 }, .{ 28, 14 } }) ++ path(&.{ .{ 4, 14 }, .{ 16, 20 }, .{ 28, 14 } })),
    .greatclub = &(closed(&.{ .{ 14, 29 }, .{ 13, 19 }, .{ 9, 10 }, .{ 10, 5 }, .{ 15, 3 }, .{ 20, 4 }, .{ 23, 9 }, .{ 21, 16 }, .{ 18, 20 }, .{ 18, 29 } }) ++ [_][4]f32{ .{ 9.5, 7.5, 6, 6 }, .{ 22, 6.5, 25.5, 4.5 }, .{ 22.5, 12.5, 26, 13 } }),
    .sling = &([_][4]f32{ .{ 8, 3, 12, 18 }, .{ 24, 3, 20, 18 } } ++ path(&.{ .{ 12, 18 }, .{ 14, 25 }, .{ 18, 25 }, .{ 20, 18 } }) ++ [_][4]f32{ .{ 16, 20.5, 16, 20.5 } }),
    .dagger = &([_][4]f32{ .{ 10, 18, 23, 9 }, .{ 14, 22, 23, 9 }, .{ 8, 16, 16, 24 }, .{ 12, 20, 8, 24 } }),
    .handaxe = &([_][4]f32{ .{ 18, 4.5, 6, 25.3 } } ++ path(&.{ .{ 16.5, 7.1 }, .{ 21.4, 8.7 }, .{ 26.3, 8.1 }, .{ 24.9, 16.5 }, .{ 18.3, 22 }, .{ 16.9, 16.5 }, .{ 13, 13.1 } })),
    .wand = &(WAND ++ [_][4]f32{ .{ 23, 4, 23, 14 }, .{ 18, 9, 28, 9 } }),
    .tome = &(closed(&.{ .{ 8, 5 }, .{ 25, 5 }, .{ 25, 27 }, .{ 8, 27 } }) ++ [_][4]f32{ .{ 11, 5, 11, 27 }, .{ 15, 11, 22, 11 }, .{ 15, 15, 22, 15 } }),
    .orb = &(polygon(16, 16, 11, 12, 0.5) ++ path(&.{ .{ 9.5, 16 }, .{ 10.4, 12.75 }, .{ 12.75, 10.4 } })),
    .buckler = &(polygon(16, 16, 12, 12, 0.5) ++ polygon(16, 16, 4, 8, 0.5)),
    .totem = &(closed(&.{ .{ 11, 6 }, .{ 21, 6 }, .{ 21, 29 }, .{ 11, 29 } }) ++ [_][4]f32{ .{ 14, 11, 14, 11 }, .{ 18, 11, 18, 11 }, .{ 14, 16, 18, 16 }, .{ 11, 23, 21, 23 } } ++ path(&.{ .{ 11, 7 }, .{ 4, 5 }, .{ 11, 12 } }) ++ path(&.{ .{ 21, 7 }, .{ 28, 5 }, .{ 21, 12 } })),
    .shield = &(SHIELD_LINES ++ [_][4]f32{ .{ 11, 5, 11, 22 }, .{ 21, 5, 21, 22 } }),
    .cap = &(path(&.{ .{ 7, 22 }, .{ 8, 14 }, .{ 12, 9 }, .{ 20, 9 }, .{ 24, 14 }, .{ 25, 22 } }) ++ [_][4]f32{ .{ 4, 22, 28, 22 }, .{ 16, 9, 16, 22 } }),
    .helmet = &(closed(&.{ .{ 7, 28 }, .{ 7, 13 }, .{ 10, 8 }, .{ 16, 5 }, .{ 22, 8 }, .{ 25, 13 }, .{ 25, 28 } }) ++ [_][4]f32{ .{ 9, 15, 23, 15 }, .{ 16, 15, 16, 24 } }),
    .leather = &(TUNIC ++ [_][4]f32{ .{ 8, 22, 24, 22 } }),
    .mail = &(TUNIC ++ path(&.{ .{ 9, 15 }, .{ 11, 17 }, .{ 13, 15 }, .{ 15, 17 }, .{ 17, 15 }, .{ 19, 17 }, .{ 21, 15 }, .{ 23, 17 } }) ++ path(&.{ .{ 9, 21 }, .{ 11, 23 }, .{ 13, 21 }, .{ 15, 23 }, .{ 17, 21 }, .{ 19, 23 }, .{ 21, 21 }, .{ 23, 23 } })),
    .belt = &([_][4]f32{ .{ 3, 13, 11, 13 }, .{ 21, 13, 29, 13 }, .{ 3, 19, 11, 19 }, .{ 21, 19, 29, 19 } } ++ closed(&.{ .{ 11, 10 }, .{ 21, 10 }, .{ 21, 22 }, .{ 11, 22 } }) ++ [_][4]f32{ .{ 11, 16, 18, 16 } }),
    .gloves = &(GLOVE ++ closed(&.{ .{ 8, 22 }, .{ 24, 22 }, .{ 24, 28 }, .{ 8, 28 } })),
    .boots = &(BOOT ++ [_][4]f32{ .{ 9, 9, 19, 9 } }),
    .ring = &(RING_BAND ++ path(&.{ .{ 12, 13 }, .{ 14, 11 }, .{ 18, 11 }, .{ 20, 13 } })),
    .amulet = &(path(&.{ .{ 5, 3 }, .{ 9, 12 }, .{ 16, 17 } }) ++ path(&.{ .{ 27, 3 }, .{ 23, 12 }, .{ 16, 17 } }) ++ closed(&.{ .{ 16, 17 }, .{ 20, 22 }, .{ 16, 28 }, .{ 12, 22 } })),
    .hunting_bow = &(path(&.{ .{ 22, 3 }, .{ 14, 8 }, .{ 11, 16 }, .{ 14, 24 }, .{ 22, 29 } }) ++ [_][4]f32{ .{ 22, 3, 22, 29 }, .{ 4, 16, 25, 16 } } ++ path(&.{ .{ 8, 12 }, .{ 4, 16 }, .{ 8, 20 } })),
    .war_bow = &(path(&.{ .{ 26, 5 }, .{ 22, 3 }, .{ 14, 8 }, .{ 11, 16 }, .{ 14, 24 }, .{ 22, 29 }, .{ 26, 27 } }) ++ [_][4]f32{ .{ 22, 3, 22, 29 } }),
    .ash_wand = &(WAND ++ closed(&.{ .{ 21, 14 }, .{ 19, 9 }, .{ 23, 3 }, .{ 27, 9 }, .{ 25, 14 } })),
    .rime_wand = &(WAND ++ [_][4]f32{ .{ 24, 3, 24, 13 }, .{ 19.7, 5.5, 28.3, 10.5 }, .{ 19.7, 10.5, 28.3, 5.5 } }),
    .storm_wand = &(WAND ++ path(&.{ .{ 27, 3 }, .{ 21, 9 }, .{ 27, 10 }, .{ 22, 16 } })),
    .plate = &(path(&.{ .{ 12, 4 }, .{ 16, 8 }, .{ 20, 4 } }) ++ path(&.{ .{ 12, 4 }, .{ 5, 5 }, .{ 3, 10 }, .{ 8, 12 } }) ++ path(&.{ .{ 20, 4 }, .{ 27, 5 }, .{ 29, 10 }, .{ 24, 12 } }) ++ path(&.{ .{ 8, 12 }, .{ 8, 24 }, .{ 12, 28 }, .{ 20, 28 }, .{ 24, 24 }, .{ 24, 12 } }) ++ [_][4]f32{ .{ 16, 8, 16, 28 }, .{ 8, 19, 24, 19 } }),
    .robes = &(path(&.{ .{ 12, 4 }, .{ 16, 9 }, .{ 20, 4 } }) ++ path(&.{ .{ 12, 4 }, .{ 7, 6 }, .{ 3, 17 }, .{ 8, 18 }, .{ 10, 13 }, .{ 6, 29 }, .{ 26, 29 }, .{ 22, 13 }, .{ 24, 18 }, .{ 29, 17 }, .{ 25, 6 }, .{ 20, 4 } }) ++ [_][4]f32{ .{ 16, 9, 16, 29 } }),
    .hood = &(path(&.{ .{ 6, 28 }, .{ 8, 15 }, .{ 16, 3 }, .{ 24, 15 }, .{ 26, 28 } }) ++ path(&.{ .{ 11, 28 }, .{ 11, 20 }, .{ 16, 15 }, .{ 21, 20 }, .{ 21, 28 } }) ++ [_][4]f32{ .{ 6, 28, 11, 28 }, .{ 21, 28, 26, 28 } }),
    .circlet = &(path(&.{ .{ 4, 17 }, .{ 10, 21 }, .{ 22, 21 }, .{ 28, 17 } }) ++ closed(&.{ .{ 16, 8 }, .{ 19.5, 12.5 }, .{ 16, 17 }, .{ 12.5, 12.5 } }) ++ [_][4]f32{ .{ 16, 17, 16, 21 }, .{ 10, 21, 9, 15 }, .{ 22, 21, 23, 15 } }),
    .gauntlets = &(GLOVE ++ [_][4]f32{ .{ 8, 22, 24, 22 } } ++ path(&.{ .{ 8, 22 }, .{ 5, 29 }, .{ 27, 29 }, .{ 24, 22 } }) ++ [_][4]f32{ .{ 8, 13, 24, 13 } }),
    .spellwraps = &(GLOVE ++ path(&.{ .{ 8, 22 }, .{ 8, 28 }, .{ 24, 28 }, .{ 24, 22 } }) ++ [_][4]f32{ .{ 8, 17, 24, 21 }, .{ 8, 22, 24, 26 } }),
    .iron_boots = &(BOOT ++ [_][4]f32{ .{ 9, 11, 19, 11 }, .{ 9, 16, 19, 16 }, .{ 22, 20, 22, 27 } }),
    .broad_belt = &([_][4]f32{ .{ 3, 9, 11, 9 }, .{ 21, 9, 29, 9 }, .{ 3, 23, 11, 23 }, .{ 21, 23, 29, 23 } } ++ closed(&.{ .{ 11, 6 }, .{ 21, 6 }, .{ 21, 26 }, .{ 11, 26 } }) ++ [_][4]f32{ .{ 11, 16, 18, 16 }, .{ 6, 16, 6, 16 }, .{ 26, 16, 26, 16 } }),
    .flask_belt = &([_][4]f32{ .{ 3, 7, 29, 7 }, .{ 3, 12, 29, 12 }, .{ 9, 12, 9, 16 } } ++ closed(&.{ .{ 9, 16 }, .{ 13, 21 }, .{ 13, 26 }, .{ 5, 26 }, .{ 5, 21 } }) ++ [_][4]f32{ .{ 23, 12, 23, 16 } } ++ closed(&.{ .{ 23, 16 }, .{ 27, 21 }, .{ 27, 26 }, .{ 19, 26 }, .{ 19, 21 } })),
    .sash = &([_][4]f32{ .{ 3, 11, 17, 11 }, .{ 25, 11, 29, 11 }, .{ 3, 17, 17, 17 }, .{ 25, 17, 29, 17 } } ++ closed(&.{ .{ 21, 9 }, .{ 25, 14 }, .{ 21, 19 }, .{ 17, 14 } }) ++ [_][4]f32{ .{ 20, 19, 16, 29 }, .{ 22, 19, 26, 29 } }),
    .iron_ring = &(polygon(16, 17, 10, 6, 0)),
    .jade_ring = &(RING_BAND ++ path(&.{ .{ 11, 13 }, .{ 12, 8 }, .{ 16, 6 }, .{ 20, 8 }, .{ 21, 13 } })),
    .ruby_ring = &(RING_BAND ++ closed(&.{ .{ 16, 3 }, .{ 21, 8 }, .{ 16, 13 }, .{ 11, 8 } })),
    .sapphire_ring = &(RING_BAND ++ closed(&.{ .{ 12, 5 }, .{ 20, 5 }, .{ 20, 13 }, .{ 12, 13 } })),
    .life_flask = skillLines(.life_flask),
    .mana_flask = skillLines(.mana_flask),
});

pub const SKILL_PX: i32 = 30;

pub fn drawSkill(sprites: *const look.Sprites, a: skillbar.Act, x: i32, y: i32, alpha: f32) void {
    const ink = look.fade(rl.Color.white, alpha);
    const t = sprites.skills orelse return inkSkill(a, x, y, ink);
    raster.blit(t, raster.rect(skillX(a), 0, SKILL_PX, SKILL_PX), raster.rect(x, y, SKILL_PX, SKILL_PX), ink);
}

fn skillX(a: skillbar.Act) i32 {
    return @as(i32, @intCast(a.index())) * SKILL_PX;
}

/// Needs a live GL context.
pub fn skillIcons() ?rl.Texture2D {
    return baked(SKILL_PX * @as(i32, @intCast(skillbar.ACTS.len)), SKILL_PX, inkSkills);
}

fn inkSkills() void {
    for (skillbar.ACTS) |a| inkSkill(a, skillX(a), 0, rl.Color.white);
}

/// An item glyph's side: beside a list row's text, or filling a paperdoll cell.
pub const ItemSize = enum(i32) { row = 24, cell = 48 };

pub fn drawItem(sprites: *const look.Sprites, k: items.Kind, size: ItemSize, cx: i32, cy: i32, ink: rl.Color) void {
    drawIcon(sprites, @intFromEnum(k), size, cx, cy, ink);
}

/// A supply's glyph is its skill's.
pub fn drawSupply(sprites: *const look.Sprites, k: consumable.Kind, size: ItemSize, cx: i32, cy: i32, ink: rl.Color) void {
    drawIcon(sprites, ITEM_KINDS.len + @intFromEnum(k), size, cx, cy, ink);
}

fn drawIcon(sprites: *const look.Sprites, i: usize, size: ItemSize, cx: i32, cy: i32, ink: rl.Color) void {
    const px = @intFromEnum(size);
    const x = cx - @divTrunc(px, 2);
    const y = cy - @divTrunc(px, 2);
    const t = sprites.item_icons orelse return inkLines(iconLines(i), x, y, px, ink);
    raster.blit(t, raster.rect(iconX(i, size), iconY(size), px, px), raster.rect(x, y, px, px), ink);
}

const ITEM_KINDS = std.enums.values(items.Kind);
const ICONS = ITEM_KINDS.len + consumable.KINDS.len;

fn iconLines(i: usize) []const [4]f32 {
    if (i < ITEM_KINDS.len) return ITEM_LINES.get(ITEM_KINDS[i]);
    return skillLines(skillbar.Act.ofSupply(consumable.KINDS[i - ITEM_KINDS.len]));
}

fn iconX(i: usize, size: ItemSize) i32 {
    return @as(i32, @intCast(i)) * @intFromEnum(size);
}

fn iconY(size: ItemSize) i32 {
    return if (size == .cell) 0 else @intFromEnum(ItemSize.cell);
}

/// Needs a live GL context.
pub fn itemIcons() ?rl.Texture2D {
    const cell = @intFromEnum(ItemSize.cell);
    return baked(cell * @as(i32, ICONS), cell + @intFromEnum(ItemSize.row), inkItems);
}

fn inkItems() void {
    for (0..ICONS) |i| for (std.enums.values(ItemSize)) |size| {
        inkLines(iconLines(i), iconX(i, size), iconY(size), @intFromEnum(size), rl.Color.white);
    };
}

fn baked(w: i32, h: i32, comptime paint: fn () void) ?rl.Texture2D {
    const target = rl.loadRenderTexture(w, h) catch return null;
    defer rl.unloadRenderTexture(target);
    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color.blank);
    paint();
    rl.endTextureMode();
    var img = rl.loadImageFromTexture(target.texture) catch return null;
    rl.imageFlipVertical(&img);
    return look.Sprites.toTexture(img);
}

const SKILL_GRID: f32 = 32;

fn inkSkill(a: skillbar.Act, x: i32, y: i32, ink: rl.Color) void {
    inkLines(skillLines(a), x, y, SKILL_PX, ink);
}

fn inkLines(lines: []const [4]f32, x: i32, y: i32, px: i32, ink: rl.Color) void {
    const scale = @as(f32, @floatFromInt(px)) / SKILL_GRID;
    const ox: f32 = @floatFromInt(x);
    const oy: f32 = @floatFromInt(y);
    for (lines) |line| {
        const from = rl.Vector2{ .x = ox + line[0] * scale, .y = oy + line[1] * scale };
        const to = rl.Vector2{ .x = ox + line[2] * scale, .y = oy + line[3] * scale };
        stroke(from, to, scale, ink);
    }
}

/// Two grid units wide, with round caps.
fn stroke(from: rl.Vector2, to: rl.Vector2, scale: f32, col: rl.Color) void {
    rl.drawLineEx(from, to, 2 * scale, col);
    rl.drawCircleV(from, scale, col);
    rl.drawCircleV(to, scale, col);
}

test "every item and supply glyph keeps its strokes on the grid and differs from every other" {
    var strokes: usize = 0;
    for (0..ICONS) |i| {
        const own = iconLines(i);
        try std.testing.expect(own.len > 0);
        for (own) |line| for (line) |v| try std.testing.expect(v >= 1 and v <= SKILL_GRID - 1);
        for (0..i) |j| try std.testing.expect(!std.mem.eql(u8, std.mem.sliceAsBytes(own), std.mem.sliceAsBytes(iconLines(j))));
        strokes += own.len;
    }
    std.debug.print("item glyphs: {d} icons, {d} strokes, all within the {d}-unit grid and distinct\n", .{ ICONS, strokes, @as(u32, @intFromFloat(SKILL_GRID)) });
}
