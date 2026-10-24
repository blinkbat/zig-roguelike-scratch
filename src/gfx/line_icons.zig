const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const skillbar = @import("../play/skillbar.zig");
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
    const target = rl.loadRenderTexture(SKILL_PX * @as(i32, @intCast(skillbar.ACTS.len)), SKILL_PX) catch return null;
    defer rl.unloadRenderTexture(target);
    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color.blank);
    for (skillbar.ACTS) |a| inkSkill(a, skillX(a), 0, rl.Color.white);
    rl.endTextureMode();
    var img = rl.loadImageFromTexture(target.texture) catch return null;
    rl.imageFlipVertical(&img);
    return look.Sprites.toTexture(img);
}

const SKILL_GRID: f32 = 32;

fn inkSkill(a: skillbar.Act, x: i32, y: i32, ink: rl.Color) void {
    const scale = @as(f32, @floatFromInt(SKILL_PX)) / SKILL_GRID;
    const ox: f32 = @floatFromInt(x);
    const oy: f32 = @floatFromInt(y);
    for (skillLines(a)) |line| {
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
