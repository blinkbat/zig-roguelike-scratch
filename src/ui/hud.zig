const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const font = @import("../gfx/font.zig");
const look = @import("../gfx/look.zig");
const fx = @import("../gfx/fx.zig");

pub const WIDTH: i32 = 744;
const HEIGHT: i32 = 172;
const BOTTOM: i32 = 12;
/// How far up from the screen's foot the hud covers the world.
pub const COVER: i32 = BOTTOM + HEIGHT;
const ORB_R: i32 = 52;
const FILL_R: i32 = 44;
/// The orbs' centres, in from the assembly's sides and down from its top.
const ORB_INSET: i32 = 64;
const ORB_Y: i32 = 104;
/// Clear space between an orb's rim and the skill strip.
const ORB_GAP: i32 = 18;
pub const SKILLS_MAX_W: i32 = WIDTH - 2 * (ORB_INSET + ORB_R + ORB_GAP);
const PLATE_Y: i32 = 66;
pub const PLATE_PAD: i32 = 10;
pub const PLATE_H: i32 = 88;
const PLATE_RULE: i32 = 5;
const SHADOW_DROP: i32 = 3;
/// How far an orb's shadow falls below it, and how much wider it is.
const ORB_SHADOW_DY: i32 = 4;
const ORB_SHADOW_GROW: i32 = 2;
/// How far in from the plate's sides its rules stop.
const RULE_INSET: i32 = 8;
const STATUS_Y: i32 = 20;
const PLATE_SHADOW_A: f32 = 0.5;
const ORB_SHADOW_A: f32 = 0.6;
/// Insets of the orb's bright rim and the dark ring inside it, and the well's rim past the fill.
const ORB_RIM: i32 = 2;
const ORB_RING: i32 = 5;
const WELL_RIM_W: i32 = 2;
const SURFACE_A: f32 = 0.8;
/// The glint on an orb's glass: up and left of its middle, its radii and alpha.
const GLINT_AT = mathx.P{ .x = -20, .y = -24 };
const GLINT_R = [2]f32{ 3, 6 };
const GLINT_A: f32 = 0.16;
/// Above an orb's rim, its label's top.
const LABEL_RISE: i32 = 23;
/// A status icon's middle in its square, and its count's inset from the square's corner.
const ICON_AT = mathx.P{ .x = 12, .y = 13 };
const COUNT_INSET = mathx.P{ .x = 3, .y = 1 };

comptime {
    std.debug.assert(PLATE_Y + PLATE_H < ORB_Y + ORB_R);
    std.debug.assert(ORB_Y + ORB_R + ORB_SHADOW_DY + ORB_SHADOW_GROW <= HEIGHT);
}

const FRAME = look.rgb(0x625a48);
const FRAME_DARK = look.rgb(0x22211f);
const WELL = look.rgb(0x080a10);
const WELL_RIM = look.rgb(0x020305);
const PLATE = look.rgb(0x101114);
const LIFE_CORE = look.rgb(0xb83b32);
const LIFE_EDGE = look.rgb(0x541412);
const MANA_CORE = look.rgb(0x376eb4);
const MANA_EDGE = look.rgb(0x14294d);
const STATUS_PX: i32 = 32;
const STATUS_GAP: i32 = 8;

pub const Layout = struct {
    left: i32,
    top: i32,
    life: mathx.P,
    mana: mathx.P,
    skills: mathx.P,
    skills_w: i32,

    pub fn of(screen: mathx.P, skills_w: i32) Layout {
        const left = @divTrunc(screen.x - WIDTH, 2);
        const top = screen.y - COVER;
        return .{
            .left = left,
            .top = top,
            .life = .{ .x = left + ORB_INSET, .y = top + ORB_Y },
            .mana = .{ .x = left + WIDTH - ORB_INSET, .y = top + ORB_Y },
            .skills = .{ .x = @divTrunc(screen.x - skills_w, 2), .y = top + PLATE_Y + PLATE_PAD },
            .skills_w = skills_w,
        };
    }
};

pub fn frame(layout: Layout) void {
    const x = layout.life.x;
    const y = layout.top + PLATE_Y;
    const width = layout.mana.x - x;
    rl.drawRectangle(x - SHADOW_DROP, y + SHADOW_DROP, width + 2 * SHADOW_DROP, PLATE_H + 2, look.fade(rl.Color.black, PLATE_SHADOW_A));
    rl.drawRectangle(x, y, width, PLATE_H, PLATE);
    rl.drawRectangleLinesEx(look.rect(x, y, width, PLATE_H), 2, FRAME);
    rl.drawLine(x + RULE_INSET, y + PLATE_RULE, x + width - RULE_INSET, y + PLATE_RULE, FRAME_DARK);
    rl.drawLine(x + RULE_INSET, y + PLATE_H - 1 - PLATE_RULE, x + width - RULE_INSET, y + PLATE_H - 1 - PLATE_RULE, FRAME_DARK);
}

pub fn resources(layout: Layout, face: *const font.Face, hp: i32, hp_max: i32, mana: i32, mana_max: i32) void {
    orb(face, layout.life, "Life", hp, hp_max, LIFE_CORE, LIFE_EDGE);
    orb(face, layout.mana, "Mana", mana, mana_max, MANA_CORE, MANA_EDGE);
}

fn fillHeight(value: i32, max: i32) i32 {
    if (max <= 0) return 0;
    const clamped: i64 = std.math.clamp(value, 0, max);
    return @intCast(@divTrunc(clamped * FILL_R * 2, max));
}

fn orb(face: *const font.Face, centre: mathx.P, name: []const u8, value: i32, max: i32, core: rl.Color, edge: rl.Color) void {
    const x = centre.x;
    const y = centre.y;
    rl.drawCircle(x, y + ORB_SHADOW_DY, ORB_R + ORB_SHADOW_GROW, look.fade(rl.Color.black, ORB_SHADOW_A));
    rl.drawCircle(x, y, ORB_R, FRAME_DARK);
    rl.drawCircle(x, y, ORB_R - ORB_RIM, FRAME);
    rl.drawCircle(x, y, ORB_R - ORB_RING, FRAME_DARK);
    rl.drawCircle(x, y, FILL_R + WELL_RIM_W, WELL_RIM);
    rl.drawCircle(x, y, FILL_R, WELL);
    const filled = fillHeight(value, max);
    if (filled > 0) {
        const surface = y + FILL_R - filled;
        rl.beginScissorMode(x - FILL_R, surface, FILL_R * 2, filled);
        rl.drawCircleGradient(x, y, FILL_R, core, edge);
        rl.endScissorMode();
        if (filled < FILL_R * 2) {
            const dy: f32 = @floatFromInt(surface - y);
            const half: i32 = @intFromFloat(@sqrt(@max(0, FILL_R * FILL_R - dy * dy)));
            rl.drawLine(x - half + 1, surface, x + half - 1, surface, look.fade(core, SURFACE_A));
        }
    }
    rl.drawEllipse(x + GLINT_AT.x, y + GLINT_AT.y, GLINT_R[0], GLINT_R[1], look.fade(look.TEXT, GLINT_A));
    var buf: [48]u8 = undefined;
    const label = std.fmt.bufPrintZ(&buf, "{s} {d}/{d}", .{ name, @max(0, value), @max(0, max) }) catch "";
    face.textMid(label, x, y - ORB_R - LABEL_RISE, font.BODY, look.TEXT);
}

pub fn statuses(layout: Layout, face: *const font.Face, status: std.EnumArray(fx.Status, u8)) void {
    var count: i32 = 0;
    for (status.values) |turns| count += @intFromBool(turns > 0);
    var x = layout.left + @divTrunc(WIDTH - count * (STATUS_PX + STATUS_GAP) + STATUS_GAP, 2);
    const y = layout.top + STATUS_Y;
    for (std.enums.values(fx.Status)) |s| {
        const turns = status.get(s);
        if (turns == 0) continue;
        rl.drawRectangle(x, y, STATUS_PX, STATUS_PX, PLATE);
        rl.drawRectangleLinesEx(look.rect(x, y, STATUS_PX, STATUS_PX), 1, s.ink());
        statusIcon(s, x + ICON_AT.x, y + ICON_AT.y);
        var buf: [4]u8 = undefined;
        const label = std.fmt.bufPrintZ(&buf, "{d}", .{turns}) catch "";
        face.text(label, x + STATUS_PX - face.width(label, font.SMALL) - COUNT_INSET.x, y + STATUS_PX - font.SMALL - COUNT_INSET.y, font.SMALL, look.TEXT);
        x += STATUS_PX + STATUS_GAP;
    }
}

fn statusIcon(status: fx.Status, x: i32, y: i32) void {
    const colour = status.ink();
    switch (status) {
        .bleeding => {
            rl.drawCircle(x, y + 3, 5, colour);
            rl.drawTriangle(.{ .x = @floatFromInt(x), .y = @floatFromInt(y - 7) }, .{ .x = @floatFromInt(x - 5), .y = @floatFromInt(y + 3) }, .{ .x = @floatFromInt(x + 5), .y = @floatFromInt(y + 3) }, colour);
        },
        .burning => {
            rl.drawCircle(x, y + 3, 6, colour);
            rl.drawTriangle(.{ .x = @floatFromInt(x + 2), .y = @floatFromInt(y - 8) }, .{ .x = @floatFromInt(x - 6), .y = @floatFromInt(y + 3) }, .{ .x = @floatFromInt(x + 5), .y = @floatFromInt(y + 4) }, colour);
            rl.drawCircle(x, y + 5, 3, look.FIRE_CORE);
        },
        .chilled => {
            rl.drawLine(x, y - 8, x, y + 8, colour);
            rl.drawLine(x - 7, y - 4, x + 7, y + 4, colour);
            rl.drawLine(x - 7, y + 4, x + 7, y - 4, colour);
            rl.drawCircle(x, y, 2, colour);
        },
    }
}

test "the HUD stays centered at a fixed width with room between orbs and skills" {
    const widths = [_]mathx.P{ .{ .x = 1280, .y = 720 }, .{ .x = 1600, .y = 900 }, .{ .x = 1920, .y = 1080 }, .{ .x = 2560, .y = 1440 } };
    for (widths) |screen| {
        const layout = Layout.of(screen, SKILLS_MAX_W);
        try std.testing.expectEqual(screen.x, layout.left * 2 + WIDTH);
        try std.testing.expectEqual(screen.x, layout.life.x + layout.mana.x);
        try std.testing.expect(layout.life.x + ORB_R + ORB_GAP <= layout.skills.x);
        try std.testing.expect(layout.skills.x + layout.skills_w + ORB_GAP <= layout.mana.x - ORB_R);
        try std.testing.expect(layout.top > 0 and layout.life.y + ORB_R < screen.y);
    }
    std.debug.print("HUD: {d}px centered assembly verified at {d} resolutions\n", .{ WIDTH, widths.len });
}

test "orb fill clamps values and gives full half and empty reservoirs" {
    const cases = [_]struct { value: i32, max: i32, want: i32 }{
        .{ .value = 100, .max = 100, .want = FILL_R * 2 },
        .{ .value = 50, .max = 100, .want = FILL_R },
        .{ .value = 0, .max = 100, .want = 0 },
        .{ .value = -5, .max = 100, .want = 0 },
        .{ .value = 110, .max = 100, .want = FILL_R * 2 },
        .{ .value = 5, .max = 0, .want = 0 },
        .{ .value = std.math.maxInt(i32), .max = std.math.maxInt(i32), .want = FILL_R * 2 },
    };
    for (cases) |c| try std.testing.expectEqual(c.want, fillHeight(c.value, c.max));
    std.debug.print("orbs: {d} resource fill cases verified\n", .{cases.len});
}
