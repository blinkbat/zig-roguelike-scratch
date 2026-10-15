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
const PLATE_Y: i32 = 54;
pub const PLATE_PAD: i32 = 8;
pub const PLATE_H: i32 = 100;
const SHADOW_DROP: i32 = 3;
const PLATE_SHADOW_GROW: i32 = 2;
/// How far an orb's shadow falls below it, and how much wider it is.
const ORB_SHADOW_DY: i32 = 4;
const ORB_SHADOW_GROW: i32 = 2;
const STATUS_Y: i32 = 4;
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
const ICON_AT = mathx.P{ .x = 14, .y = 15 };
const COUNT_INSET = mathx.P{ .x = 7, .y = 6 };

comptime {
    std.debug.assert(STATUS_Y + STATUS_PX < PLATE_Y);
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
const STATUS_PX: i32 = 40;
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

pub fn frame(layout: Layout, sprites: *const look.Sprites) void {
    const x = layout.life.x;
    const y = layout.top + PLATE_Y;
    const width = layout.mana.x - x;
    rl.drawRectangle(x - SHADOW_DROP, y + SHADOW_DROP, width + 2 * SHADOW_DROP, PLATE_H + PLATE_SHADOW_GROW, look.fade(rl.Color.black, PLATE_SHADOW_A));
    rl.drawRectangle(x, y, width, PLATE_H, PLATE);
    look.hudBorder(sprites, x, y, width, PLATE_H, look.LIT);
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

/// The statuses shown, in the order they are drawn.
pub fn shownStatuses(status: std.EnumArray(fx.Status, u8), out: *[std.enums.values(fx.Status).len]fx.Status) []const fx.Status {
    var n: usize = 0;
    for (std.enums.values(fx.Status)) |s| {
        if (status.get(s) == 0) continue;
        out[n] = s;
        n += 1;
    }
    return out[0..n];
}

/// The square of the `k`th of `count` statuses shown.
pub fn statusBox(layout: Layout, count: usize, k: usize) rl.Rectangle {
    const n: i32 = @intCast(count);
    const x = layout.left + @divTrunc(WIDTH - n * (STATUS_PX + STATUS_GAP) + STATUS_GAP, 2) + @as(i32, @intCast(k)) * (STATUS_PX + STATUS_GAP);
    return look.rect(x, layout.top + STATUS_Y, STATUS_PX, STATUS_PX);
}

pub fn orbBox(centre: mathx.P) rl.Rectangle {
    return look.rect(centre.x - ORB_R, centre.y - ORB_R, 2 * ORB_R, 2 * ORB_R);
}

pub fn statuses(layout: Layout, sprites: *const look.Sprites, face: *const font.Face, status: std.EnumArray(fx.Status, u8)) void {
    var buf_shown: [std.enums.values(fx.Status).len]fx.Status = undefined;
    const shown = shownStatuses(status, &buf_shown);
    for (shown, 0..) |s, k| {
        const turns = status.get(s);
        const box = statusBox(layout, shown.len, k);
        const x: i32 = @intFromFloat(box.x);
        const y: i32 = @intFromFloat(box.y);
        rl.drawRectangle(x, y, STATUS_PX, STATUS_PX, PLATE);
        look.hudBorder(sprites, x, y, STATUS_PX, STATUS_PX, look.LIT);

        statusIcon(s, x + ICON_AT.x, y + ICON_AT.y);
        var buf: [4]u8 = undefined;
        const label = std.fmt.bufPrintZ(&buf, "{d}", .{turns}) catch "";
        face.text(label, x + STATUS_PX - face.width(label, font.SMALL) - COUNT_INSET.x, y + STATUS_PX - font.SMALL - COUNT_INSET.y, font.SMALL, look.TEXT);
    }
}

/// Out from what is inspected, the mark round it.
const FOCUS_GROW: f32 = 4;
const FOCUS_W: f32 = 2;
const TIP_W: i32 = 380;
const TIP_PAD: i32 = 12;
const TIP_GAP: i32 = 8;
const TIP_LINE: i32 = font.SMALL + 4;
const TIP_MARGIN: i32 = 8;
const TIP_LINES_MAX: usize = 8;
const TIP_COLS_MAX: usize = 96;

/// The mark round what is inspected: a ring round an orb, a frame round anything else.
pub fn focus(box: rl.Rectangle, round: bool) void {
    if (round) {
        const r = box.width / 2 + FOCUS_GROW;
        rl.drawRing(.{ .x = box.x + box.width / 2, .y = box.y + box.height / 2 }, r - FOCUS_W, r, 0, 360, 64, look.RETICLE);
        return;
    }
    rl.drawRectangleLinesEx(.{ .x = box.x - FOCUS_GROW, .y = box.y - FOCUS_GROW, .width = box.width + 2 * FOCUS_GROW, .height = box.height + 2 * FOCUS_GROW }, FOCUS_W, look.RETICLE);
}

/// `body` broken at spaces into lines no wider than `w` in `size`; each line's text is nul-ended in `buf`.
fn wrap(face: anytype, body: []const u8, size: i32, w: i32, buf: *[TIP_LINES_MAX][TIP_COLS_MAX + 1]u8, lines: *[TIP_LINES_MAX][:0]const u8) usize {
    var n: usize = 0;
    var words = std.mem.tokenizeScalar(u8, body, ' ');
    var len: usize = 0;
    while (words.next()) |word| {
        if (n == TIP_LINES_MAX) break;
        const line = &buf[n];
        const with = len + @intFromBool(len > 0) + word.len;
        if (with <= TIP_COLS_MAX) {
            var try_buf: [TIP_COLS_MAX + 1]u8 = undefined;
            @memcpy(try_buf[0..len], line[0..len]);
            if (len > 0) try_buf[len] = ' ';
            @memcpy(try_buf[with - word.len .. with], word);
            try_buf[with] = 0;
            if (len == 0 or face.width(try_buf[0..with :0], size) <= w) {
                @memcpy(line[0 .. with + 1], try_buf[0 .. with + 1]);
                len = with;
                lines[n] = line[0..len :0];
                continue;
            }
        }
        n += 1;
        if (n == TIP_LINES_MAX) break;
        const fit = @min(word.len, TIP_COLS_MAX);
        @memcpy(buf[n][0..fit], word[0..fit]);
        buf[n][fit] = 0;
        len = fit;
        lines[n] = buf[n][0..len :0];
    }
    return if (len > 0) @min(n + 1, TIP_LINES_MAX) else n;
}

/// A panel over `over` and above the whole hud, kept on the screen: what is inspected, then what it does.
pub fn tooltip(face: *const font.Face, layout: Layout, screen: mathx.P, over: rl.Rectangle, title: [:0]const u8, body: []const u8) void {
    var buf: [TIP_LINES_MAX][TIP_COLS_MAX + 1]u8 = undefined;
    var lines: [TIP_LINES_MAX][:0]const u8 = undefined;
    const n = wrap(face, body, font.SMALL, TIP_W - 2 * TIP_PAD, &buf, &lines);
    const h = 2 * TIP_PAD + font.BODY + TIP_GAP + @as(i32, @intCast(n)) * TIP_LINE;
    const mid: i32 = @intFromFloat(over.x + over.width / 2);
    const x = std.math.clamp(mid - @divTrunc(TIP_W, 2), TIP_MARGIN, @max(TIP_MARGIN, screen.x - TIP_W - TIP_MARGIN));
    const y = @max(TIP_MARGIN, @min(@as(i32, @intFromFloat(over.y)), layout.top + STATUS_Y) - TIP_GAP - h);
    rl.drawRectangle(x - SHADOW_DROP, y + SHADOW_DROP, TIP_W + 2 * SHADOW_DROP, h + PLATE_SHADOW_GROW, look.fade(rl.Color.black, PLATE_SHADOW_A));
    rl.drawRectangle(x, y, TIP_W, h, PLATE);
    rl.drawRectangleLinesEx(look.rect(x, y, TIP_W, h), FOCUS_W, FRAME);
    face.text(title, x + TIP_PAD, y + TIP_PAD, font.BODY, look.RETICLE);
    for (lines[0..n], 0..) |l, i| face.text(l, x + TIP_PAD, y + TIP_PAD + font.BODY + TIP_GAP + @as(i32, @intCast(i)) * TIP_LINE, font.SMALL, look.TEXT);
}

test "a tooltip's body breaks at spaces into lines that each fit" {
    const Fixed = struct {
        fn width(_: @This(), s: [:0]const u8, size: i32) i32 {
            return @as(i32, @intCast(s.len)) * @divTrunc(size, 2);
        }
    };
    const face = Fixed{};
    var buf: [TIP_LINES_MAX][TIP_COLS_MAX + 1]u8 = undefined;
    var lines: [TIP_LINES_MAX][:0]const u8 = undefined;
    const body = "Recover 50% of life over 3 turns. Uses 20 of 60 charges; kills refill 5. Takes a turn.";
    const w = TIP_W - 2 * TIP_PAD;
    const n = wrap(&face, body, font.SMALL, w, &buf, &lines);
    var words: usize = 0;
    for (lines[0..n]) |l| {
        try std.testing.expect(face.width(l, font.SMALL) <= w);
        words += std.mem.count(u8, l, " ") + 1;
    }
    try std.testing.expect(n > 1);
    try std.testing.expectEqual(std.mem.count(u8, body, " ") + 1, words);
    std.debug.print("tooltip: a {d}-word description in {d} lines of {d} px at most\n", .{ words, n, w });
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
        .pinned => {
            rl.drawLine(x - 7, y + 8, x + 7, y + 8, colour);
            for ([_]i32{ -5, 0, 5 }) |dx| rl.drawLine(x + dx, y - 6, x + dx, y + 8, colour);
        },
        .warded => {
            rl.drawCircleLines(x, y, 8, colour);
            rl.drawCircleLines(x, y, 5, colour);
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
