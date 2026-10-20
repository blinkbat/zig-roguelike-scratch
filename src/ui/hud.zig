const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const font = @import("../gfx/font.zig");
const look = @import("../gfx/look.zig");
const fx = @import("../gfx/fx.zig");

pub const WIDTH: i32 = 640;
const HEIGHT: i32 = 160;
const BOTTOM: i32 = 12;
/// How far up from the screen's foot the hud covers the map.
pub const COVER: i32 = BOTTOM + HEIGHT;
const ORB_R: i32 = 48;
/// The template's opening sits this far inside the orb's rim.
const FILL_INSET: i32 = 8;
const FILL_R: i32 = ORB_R - FILL_INSET;
/// The orbs' centres, in from the assembly's sides and down from its top.
const ORB_INSET: i32 = 60;
const ORB_Y: i32 = 101;
/// Clear space between an orb's rim and the skill strip.
const ORB_GAP: i32 = 12;
pub const SKILLS_MAX_W: i32 = WIDTH - 2 * (ORB_INSET + ORB_R + ORB_GAP);
const PLATE_Y: i32 = 54;
pub const PLATE_PAD: i32 = 8;
pub const PLATE_H: i32 = 94;
const SHADOW_DROP: i32 = 3;
const PLATE_SHADOW_GROW: i32 = 2;
/// How far an orb's shadow falls below it, and how much wider it is.
const ORB_SHADOW_DY: i32 = 4;
const ORB_SHADOW_GROW: i32 = 2;
const STATUS_Y: i32 = 4;
const PLATE_A: f32 = 0.7;
const PLATE_SHADOW_A: f32 = 0.25;
const TIP_SHADOW_A: f32 = 0.5;
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
    std.debug.assert(ORB_Y - ORB_R <= PLATE_Y and PLATE_Y + PLATE_H < ORB_Y + ORB_R);
    std.debug.assert(ORB_Y + ORB_R + ORB_SHADOW_DY + ORB_SHADOW_GROW <= HEIGHT);
}

const FRAME = look.rgb(0x625a48);
const FRAME_DARK = look.rgb(0x22211f);
const WELL = look.rgb(0x080a10);
const WELL_RIM = look.rgb(0x020305);
pub const PLATE = look.rgb(0x101114);
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
    shadow(x, y, width, PLATE_H, PLATE_SHADOW_A);
    look.hudPanel(sprites, x, y, width, PLATE_H, look.fade(PLATE, PLATE_A), look.LIT);
}

fn shadow(x: i32, y: i32, width: i32, height: i32, opacity: f32) void {
    rl.drawRectangle(x - SHADOW_DROP, y + SHADOW_DROP, width + 2 * SHADOW_DROP, height + PLATE_SHADOW_GROW, look.fade(rl.Color.black, opacity));
}

pub const LIFE = "Life";
pub const MANA = "Mana";

pub fn resources(layout: Layout, face: *const font.Face, hp: i32, hp_max: i32, mana: i32, mana_max: i32, life_fill: f32, mana_fill: f32) void {
    orb(face, layout.life, LIFE, hp, hp_max, life_fill, LIFE_CORE, LIFE_EDGE);
    orb(face, layout.mana, MANA, mana, mana_max, mana_fill, MANA_CORE, MANA_EDGE);
}

fn fillHeight(fill: f32) i32 {
    return @intFromFloat(@round(std.math.clamp(fill, 0, 1) * (FILL_R * 2)));
}

fn orb(face: *const font.Face, centre: mathx.P, name: []const u8, value: i32, max: i32, fill: f32, core: rl.Color, edge: rl.Color) void {
    const x = centre.x;
    const y = centre.y;
    rl.drawCircle(x, y + ORB_SHADOW_DY, ORB_R + ORB_SHADOW_GROW, look.fade(rl.Color.black, ORB_SHADOW_A));
    rl.drawCircle(x, y, ORB_R, FRAME_DARK);
    rl.drawCircle(x, y, ORB_R - ORB_RIM, FRAME);
    rl.drawCircle(x, y, ORB_R - ORB_RING, FRAME_DARK);
    rl.drawCircle(x, y, FILL_R + WELL_RIM_W, WELL_RIM);
    rl.drawCircle(x, y, FILL_R, WELL);
    const filled = fillHeight(fill);
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

/// The experience bar, between the statuses and the plate, as wide as the skills.
const XP_SEGMENTS = 10;
const XP_H: i32 = 3;
const XP_Y: i32 = PLATE_Y - 4 - XP_H;
const XP_GAP: i32 = 3;
const XP_TRACK = look.fade(rl.Color.white, 0.18);
const XP_BACK = look.fade(rl.Color.black, 0.6);

comptime {
    std.debug.assert(STATUS_Y + STATUS_PX < XP_Y - 1);
}

/// `fill` of the way through the current level, in `XP_SEGMENTS` parts.
pub fn experience(layout: Layout, fill: f32) void {
    const seg_w = @divTrunc(layout.skills_w - (XP_SEGMENTS - 1) * XP_GAP, XP_SEGMENTS);
    const x0 = layout.skills.x + @divTrunc(layout.skills_w - (XP_SEGMENTS * seg_w + (XP_SEGMENTS - 1) * XP_GAP), 2);
    const y = layout.top + XP_Y;
    for (0..XP_SEGMENTS) |i| {
        const x = x0 + @as(i32, @intCast(i)) * (seg_w + XP_GAP);
        rl.drawRectangle(x - 1, y - 1, seg_w + 2, XP_H + 2, XP_BACK);
        rl.drawRectangle(x, y, seg_w, XP_H, XP_TRACK);
        const part = std.math.clamp(fill * XP_SEGMENTS - @as(f32, @floatFromInt(i)), 0, 1);
        const w: i32 = @intFromFloat(@round(part * @as(f32, @floatFromInt(seg_w))));
        if (w > 0) rl.drawRectangle(x, y, w, XP_H, rl.Color.white);
    }
}

/// Room for every status shown at once.
pub const Shown = [std.enums.values(fx.Status).len]fx.Status;

/// The statuses shown, in the order they are drawn.
pub fn shownStatuses(status: std.EnumArray(fx.Status, u8), out: *Shown) []const fx.Status {
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
    var buf_shown: Shown = undefined;
    const shown = shownStatuses(status, &buf_shown);
    for (shown, 0..) |s, k| {
        const turns = status.get(s);
        const box = statusBox(layout, shown.len, k);
        const x: i32 = @intFromFloat(box.x);
        const y: i32 = @intFromFloat(box.y);
        look.hudPanelIn(sprites, box, PLATE, look.LIT);
        statusIcon(s, x + ICON_AT.x, y + ICON_AT.y);
        counter(face, box, turns);
    }
}

/// `n` in the bottom right corner of `box`, inside its frame.
pub fn counter(face: *const font.Face, box: rl.Rectangle, n: u32) void {
    var buf: [12]u8 = undefined;
    const label = std.fmt.bufPrintZ(&buf, "{d}", .{n}) catch "";
    const right: i32 = @intFromFloat(box.x + box.width);
    const bottom: i32 = @intFromFloat(box.y + box.height);
    face.text(label, right - face.width(label, font.SMALL) - COUNT_INSET.x, bottom - font.SMALL - COUNT_INSET.y, font.SMALL, look.TEXT);
}

/// Out from what is inspected, the mark round it.
const FOCUS_GROW: f32 = 4;
const FOCUS_W: f32 = 2;
const TIP_W: i32 = 380;
const TIP_PAD: i32 = 12;
const TIP_GAP: i32 = 8;
const TIP_LEADING: i32 = 4;
const TIP_LINE: i32 = font.SMALL + TIP_LEADING;
const TIP_FRAME_W: f32 = 2;
const TIP_MARGIN: i32 = 8;
pub const TIP_LINES_MAX: usize = 18;
pub const TIP_COLS_MAX: usize = 96;

/// The mark round what is inspected: a ring round an orb, a frame round anything else.
pub fn focus(box: rl.Rectangle, round: bool) void {
    if (round) {
        const r = box.width / 2 + FOCUS_GROW;
        rl.drawRing(look.middle(box), r - FOCUS_W, r, 0, 360, 64, look.UI_FOCUS);
        return;
    }
    rl.drawRectangleLinesEx(look.grown(box, FOCUS_GROW), FOCUS_W, look.UI_FOCUS);
}

/// Each line in `buf` is nul-terminated; wrapping breaks only at spaces.
pub fn wrap(face: anytype, body: []const u8, size: i32, w: i32, buf: *[TIP_LINES_MAX][TIP_COLS_MAX + 1]u8, lines: *[TIP_LINES_MAX][:0]const u8) usize {
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
        if (len > 0) n += 1;
        if (n == TIP_LINES_MAX) break;
        const fit = @min(word.len, TIP_COLS_MAX);
        @memcpy(buf[n][0..fit], word[0..fit]);
        buf[n][fit] = 0;
        len = fit;
        lines[n] = buf[n][0..len :0];
    }
    return if (len > 0) @min(n + 1, TIP_LINES_MAX) else n;
}

/// `text` wrapped to `w`, a line every `step` from `y`; returns the y below it.
pub fn paragraph(face: *const font.Face, text: []const u8, x: i32, y: i32, w: i32, size: i32, step: i32, ink: rl.Color) i32 {
    var buf: [TIP_LINES_MAX][TIP_COLS_MAX + 1]u8 = undefined;
    var lines: [TIP_LINES_MAX][:0]const u8 = undefined;
    const n = wrap(face, text, size, w, &buf, &lines);
    for (lines[0..n], 0..) |line, i| face.draw(line, x, y + @as(i32, @intCast(i)) * step, size, ink);
    return y + @as(i32, @intCast(n)) * step;
}

/// A body with this splits into "label|value" rows, drawn as a table.
pub const TIP_SEP = '|';
const TIP_VALUE_X = @divTrunc(TIP_W, 2) + 24;

/// A panel over `over` and above the whole hud, kept on the screen: what is inspected, then what it does.
pub fn tooltip(face: *const font.Face, layout: Layout, screen: mathx.P, over: rl.Rectangle, title: [:0]const u8, body: []const u8) void {
    var buf: [TIP_LINES_MAX][TIP_COLS_MAX + 1]u8 = undefined;
    var lines: [TIP_LINES_MAX][:0]const u8 = undefined;
    var wrapped: [TIP_LINES_MAX][TIP_COLS_MAX + 1]u8 = undefined;
    var parts: [TIP_LINES_MAX][:0]const u8 = undefined;
    var n: usize = 0;
    var rows = std.mem.splitScalar(u8, body, '\n');
    while (rows.next()) |r| {
        if (n == TIP_LINES_MAX) break;
        if (std.mem.indexOfScalar(u8, r, TIP_SEP) != null or r.len == 0) {
            const len = @min(r.len, TIP_COLS_MAX);
            @memcpy(buf[n][0..len], r[0..len]);
            buf[n][len] = 0;
            lines[n] = buf[n][0..len :0];
            n += 1;
        } else {
            const count = wrap(face, r, font.SMALL, TIP_W - 2 * TIP_PAD, &wrapped, &parts);
            for (parts[0..@min(count, TIP_LINES_MAX - n)]) |part| {
                @memcpy(buf[n][0 .. part.len + 1], part[0 .. part.len + 1]);
                lines[n] = buf[n][0..part.len :0];
                n += 1;
            }
        }
    }
    const h = 2 * TIP_PAD + font.BODY + TIP_GAP + @as(i32, @intCast(n)) * TIP_LINE;
    const mid = look.middleAt(over).x;
    const x = std.math.clamp(mid - @divTrunc(TIP_W, 2), TIP_MARGIN, @max(TIP_MARGIN, screen.x - TIP_W - TIP_MARGIN));
    const y = @max(TIP_MARGIN, @min(@as(i32, @intFromFloat(over.y)), layout.top + STATUS_Y) - TIP_GAP - h);
    shadow(x, y, TIP_W, h, TIP_SHADOW_A);
    rl.drawRectangle(x, y, TIP_W, h, PLATE);
    rl.drawRectangleLinesEx(look.rect(x, y, TIP_W, h), TIP_FRAME_W, FRAME);
    face.text(title, x + TIP_PAD, y + TIP_PAD, font.BODY, look.UI_FOCUS);
    for (lines[0..n], 0..) |l, i| {
        const top = y + TIP_PAD + font.BODY + TIP_GAP + @as(i32, @intCast(i)) * TIP_LINE;
        if (std.mem.indexOfScalar(u8, l, TIP_SEP)) |split| {
            buf[i][split] = 0;
            face.text(buf[i][0..split :0], x + TIP_PAD, top, font.SMALL, look.DIM);
            face.text(buf[i][split + 1 .. l.len :0], x + TIP_VALUE_X, top, font.SMALL, look.TEXT);
        } else face.text(l, x + TIP_PAD, top, font.SMALL, look.TEXT);
    }
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
    const long = "x" ** (TIP_COLS_MAX + 4) ++ " y";
    try std.testing.expectEqual(@as(usize, 2), wrap(&face, long, font.SMALL, w, &buf, &lines));
    try std.testing.expectEqual(TIP_COLS_MAX, lines[0].len);
    try std.testing.expectEqualStrings("y", lines[1]);
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
    for (cases) |c| try std.testing.expectEqual(c.want, fillHeight(if (c.max > 0) @as(f32, @floatFromInt(c.value)) / @as(f32, @floatFromInt(c.max)) else 0));
    std.debug.print("orbs: {d} resource fill cases verified\n", .{cases.len});
}
