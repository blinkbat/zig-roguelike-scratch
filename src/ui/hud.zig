const sprite = @import("../gfx/sprites.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const font = @import("../gfx/font.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const fx = @import("../gfx/fx.zig");

pub const WIDTH: i32 = 640;
const HEIGHT: i32 = 160;
pub const EDGE: i32 = 12;
const BOTTOM: i32 = EDGE;
pub const COVER: i32 = BOTTOM + HEIGHT;
const ORB_R: i32 = 48;
const FILL_INSET: i32 = 8;
const FILL_R: i32 = ORB_R - FILL_INSET;
const ORB_INSET: i32 = 60;
const ORB_Y: i32 = 101;
const ORB_GAP: i32 = 12;
pub const SKILLS_MAX_W: i32 = WIDTH - 2 * (ORB_INSET + ORB_R + ORB_GAP);
const PLATE_Y: i32 = 54;
pub const PLATE_PAD: i32 = 8;
pub const PLATE_H: i32 = 94;
const SHADOW_DROP: i32 = 3;
const PLATE_SHADOW_GROW: i32 = 2;
const ORB_SHADOW_DY: i32 = 4;
const ORB_SHADOW_GROW: i32 = 2;
const STATUS_Y: i32 = 4;
const PLATE_SHADOW_A: f32 = 0.25;
const ORB_SHADOW_A: f32 = 0.6;
const ORB_RIM: i32 = 2;
const ORB_RING: i32 = 5;
const WELL_RIM_W: i32 = 2;
const SURFACE_A: f32 = 0.8;
const GLINT_AT = mathx.P{ .x = -20, .y = -24 };
const GLINT_R = [2]f32{ 3, 6 };
const GLINT_A: f32 = 0.16;
const LABEL_RISE: i32 = font.SMALL + 3;
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
const LIFE_CORE = look.rgb(0xb83b32);
const LIFE_EDGE = look.rgb(0x541412);
const MANA_CORE = look.rgb(0x376eb4);
const MANA_EDGE = look.rgb(0x14294d);
const STATUS_PX: i32 = 40;
const STATUS_GAP: i32 = 8;
const RESIST_INSET: i32 = 4;
const RESIST_RISE: i32 = 5;
const RESIST_H: i32 = 2;
const RESIST_W: i32 = STATUS_PX - 2 * RESIST_INSET;

pub const Layout = struct {
    left: i32,
    top: i32,
    life: mathx.P,
    mana: mathx.P,
    skills: mathx.P,
    skills_w: i32,

    pub fn of(screen: mathx.P, skills_w: i32) Layout {
        const left = leftOf(screen);
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

pub fn leftOf(screen: mathx.P) i32 {
    return @divTrunc(screen.x - WIDTH, 2);
}

pub fn frame(layout: Layout, sprites: *const sprite.Sprites) void {
    const x = layout.life.x;
    const y = layout.top + PLATE_Y;
    const width = layout.mana.x - x;
    shadow(x, y, width, PLATE_H);
    sprite.backing(sprites, x, y, width, PLATE_H);
}

fn shadow(x: i32, y: i32, width: i32, height: i32) void {
    rl.drawRectangle(x - SHADOW_DROP, y + SHADOW_DROP, width + 2 * SHADOW_DROP, height + PLATE_SHADOW_GROW, look.fade(rl.Color.black, PLATE_SHADOW_A));
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
    face.textMid(label, x, y - ORB_R - LABEL_RISE, font.SMALL, look.TEXT);
}

const XP_SEGMENTS = 10;
const XP_H: i32 = 3;
const XP_PLATE_GAP: i32 = 4;
const XP_Y: i32 = PLATE_Y - XP_PLATE_GAP - XP_H;
const XP_GAP: i32 = 3;
const XP_TRACK = look.fade(rl.Color.white, 0.18);
const XP_BACK = look.fade(rl.Color.black, 0.6);
const XP_TOP = look.rgb(0xd6cbb0);
const XP_BOTTOM = look.rgb(0x7d7462);

comptime {
    std.debug.assert(STATUS_Y + STATUS_PX < XP_Y - 1);
}

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
        if (w > 0) rl.drawRectangleGradientV(x, y, w, XP_H, XP_TOP, XP_BOTTOM);
    }
}

pub const Shown = [std.enums.values(fx.Status).len]fx.Status;

pub fn shownStatuses(status: std.EnumArray(fx.Status, u8), out: *Shown) []const fx.Status {
    var n: usize = 0;
    for (std.enums.values(fx.Status)) |s| {
        if (status.get(s) == 0) continue;
        out[n] = s;
        n += 1;
    }
    return out[0..n];
}

pub fn statusBox(layout: Layout, count: usize, k: usize) rl.Rectangle {
    const n: i32 = @intCast(count);
    const x = layout.left + @divTrunc(WIDTH - n * (STATUS_PX + STATUS_GAP) + STATUS_GAP, 2) + @as(i32, @intCast(k)) * (STATUS_PX + STATUS_GAP);
    return raster.rect(x, layout.top + STATUS_Y, STATUS_PX, STATUS_PX);
}

pub fn orbBox(centre: mathx.P) rl.Rectangle {
    return raster.rect(centre.x - ORB_R, centre.y - ORB_R, 2 * ORB_R, 2 * ORB_R);
}

pub fn statuses(layout: Layout, sprites: *const sprite.Sprites, face: *const font.Face, status: std.EnumArray(fx.Status, u8), resistance: u8) void {
    var buf_shown: Shown = undefined;
    const shown = shownStatuses(status, &buf_shown);
    for (shown, 0..) |s, k| {
        const turns = status.get(s);
        const box = statusBox(layout, shown.len, k);
        const x = raster.left(box);
        const y = raster.top(box);
        sprite.backingIn(sprites, box);
        statusIcon(s, x + ICON_AT.x, y + ICON_AT.y);
        if (s == .resistant) {
            raster.meter(x + RESIST_INSET, y + STATUS_PX - RESIST_RISE, RESIST_W, RESIST_H, resistance, mathx.PERCENT, look.EDGE, look.UI_GOLD);
        }
        counter(face, box, turns);
    }
}

pub fn counter(face: *const font.Face, box: rl.Rectangle, n: u32) void {
    var buf: [12]u8 = undefined;
    const label = std.fmt.bufPrintZ(&buf, "{d}", .{n}) catch "";
    face.text(label, raster.right(box) - face.width(label, font.SMALL) - COUNT_INSET.x, raster.bottom(box) - font.SMALL - COUNT_INSET.y, font.SMALL, look.TEXT);
}

const FOCUS_GROW: f32 = 4;
const FOCUS_W: f32 = 2;
const TIP_W: i32 = 380;
const TIP_PAD: i32 = 12;
const TIP_GAP: i32 = 8;
const TIP_LINE = font.SMALL_LINE;
const TIP_BODY_Y = TIP_PAD + font.BODY + TIP_GAP;
const TIP_MARGIN: i32 = 8;
pub const TIP_LINES_MAX: usize = 96;

pub fn focus(box: rl.Rectangle, round: bool) void {
    if (round) {
        const r = box.width / 2 + FOCUS_GROW;
        rl.drawRing(raster.middle(box), r - FOCUS_W, r, 0, 360, 64, look.UI_FOCUS);
        return;
    }
    rl.drawRectangleLinesEx(raster.grown(box, FOCUS_GROW), FOCUS_W, look.UI_FOCUS);
}

const TIP_SEP = '|';
pub const TIP_RULE = "---";

pub fn table(comptime rows: anytype) []const u8 {
    comptime var out: []const u8 = "";
    inline for (rows, 0..) |r, i| out = out ++ (if (i > 0) "\n" else "") ++ r[0] ++ [_]u8{TIP_SEP} ++ r[1];
    return out;
}
const TIP_VALUE_DX = 24;
const TIP_VALUE_X = @divTrunc(TIP_W, 2) + TIP_VALUE_DX;

/// Returns the first line shown.
pub fn tooltipScrolled(face: *const font.Face, sprites: *const sprite.Sprites, layout: Layout, screen: mathx.P, over: rl.Rectangle, title: [:0]const u8, body: []const u8, scroll: usize) usize {
    var buf: [TIP_LINES_MAX][font.WRAP_COLS_MAX + 1]u8 = undefined;
    var lines: [TIP_LINES_MAX][:0]const u8 = undefined;
    var wrapped: font.Wrapped = undefined;
    var parts: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
    var n: usize = 0;
    var rows = std.mem.splitScalar(u8, body, '\n');
    while (rows.next()) |r| {
        if (n == TIP_LINES_MAX) break;
        if (std.mem.indexOfScalar(u8, r, TIP_SEP) != null or r.len == 0) {
            const len = @min(r.len, font.WRAP_COLS_MAX);
            @memcpy(buf[n][0..len], r[0..len]);
            buf[n][len] = 0;
            lines[n] = buf[n][0..len :0];
            n += 1;
        } else {
            const count = font.wrap(face, r, font.SMALL, TIP_W - 2 * TIP_PAD, &wrapped, &parts);
            for (parts[0..@min(count, TIP_LINES_MAX - n)]) |part| {
                @memcpy(buf[n][0 .. part.len + 1], part[0 .. part.len + 1]);
                lines[n] = buf[n][0..part.len :0];
                n += 1;
            }
        }
    }
    const limit: usize = @intCast(@max(1, @divTrunc(screen.y - 2 * TIP_MARGIN - TIP_BODY_Y - TIP_PAD, TIP_LINE)));
    const shown = @min(n, limit);
    const first = @min(scroll, n - shown);
    const h = TIP_BODY_Y + TIP_PAD + @as(i32, @intCast(shown)) * TIP_LINE;
    var x = centredOver(over, TIP_W, screen);
    var y = above(@min(raster.top(over), layout.top + STATUS_Y), h);
    if (over.y < @as(f32, @floatFromInt(layout.top)) and over.y < @as(f32, @floatFromInt(h + TIP_GAP + TIP_MARGIN))) {
        const right = raster.right(over) + TIP_GAP;
        const left = raster.left(over) - TIP_GAP - TIP_W;
        const fits_right = right + TIP_W <= screen.x - TIP_MARGIN;
        if (fits_right or left >= TIP_MARGIN) {
            x = if (fits_right) right else left;
            y = onScreen(raster.top(over) - @divTrunc(h, 2), h, screen.y);
        }
    }
    sprite.backing(sprites, x, y, TIP_W, h);
    face.text(title, x + TIP_PAD, y + TIP_PAD, font.BODY, look.UI_FOCUS);
    for (lines[first .. first + shown], first..) |l, i| {
        const top = y + TIP_BODY_Y + @as(i32, @intCast(i - first)) * TIP_LINE;
        if (std.mem.eql(u8, l, TIP_RULE)) {
            rl.drawLine(x + TIP_PAD, top + @divTrunc(TIP_LINE, 2), x + TIP_W - TIP_PAD, top + @divTrunc(TIP_LINE, 2), FRAME);
        } else if (std.mem.indexOfScalar(u8, l, TIP_SEP)) |split| {
            buf[i][split] = 0;
            face.text(buf[i][0..split :0], x + TIP_PAD, top, font.SMALL, look.DIM);
            face.text(buf[i][split + 1 .. l.len :0], x + TIP_VALUE_X, top, font.SMALL, look.TEXT);
        } else face.text(l, x + TIP_PAD, top, font.SMALL, look.TEXT);
    }
    return first;
}

pub fn prompt(face: *const font.Face, sprites: *const sprite.Sprites, screen: mathx.P, over: rl.Rectangle, text: [:0]const u8) void {
    const w = face.width(text, font.BODY) + 2 * TIP_PAD;
    const h = font.BODY + 2 * TIP_PAD;
    const x = centredOver(over, w, screen);
    const y = above(raster.top(over), h);
    sprite.backing(sprites, x, y, w, h);
    face.text(text, x + TIP_PAD, y + TIP_PAD, font.BODY, look.UI_FOCUS);
}

fn onScreen(at: i32, size: i32, room: i32) i32 {
    return std.math.clamp(at, TIP_MARGIN, @max(TIP_MARGIN, room - size - TIP_MARGIN));
}

fn centredOver(over: rl.Rectangle, w: i32, screen: mathx.P) i32 {
    return onScreen(raster.middleAt(over).x - @divTrunc(w, 2), w, screen.x);
}

fn above(top: i32, h: i32) i32 {
    return @max(TIP_MARGIN, top - TIP_GAP - h);
}

test "a tooltip's body breaks at spaces into lines that each fit" {
    const face = @import("menu.zig").TestFace{};
    var buf: font.Wrapped = undefined;
    var lines: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
    const body = "Recover 50% of life over 3 turns. Uses 20 of 60 charges; kills refill 5. Takes a turn.";
    const w = TIP_W - 2 * TIP_PAD;
    const n = font.wrap(&face, body, font.SMALL, w, &buf, &lines);
    var words: usize = 0;
    for (lines[0..n]) |l| {
        try std.testing.expect(face.width(l, font.SMALL) <= w);
        words += std.mem.count(u8, l, " ") + 1;
    }
    try std.testing.expect(n > 1);
    try std.testing.expectEqual(std.mem.count(u8, body, " ") + 1, words);
    const long = "x" ** (font.WRAP_COLS_MAX + 4) ++ " y";
    const long_n = font.wrap(&face, long, font.SMALL, w, &buf, &lines);
    var retained: usize = 0;
    for (lines[0..long_n]) |line| {
        try std.testing.expect(face.width(line, font.SMALL) <= w);
        retained += std.mem.count(u8, line, "x");
    }
    try std.testing.expectEqual(font.WRAP_COLS_MAX + 4, retained);
    try std.testing.expect(std.mem.endsWith(u8, lines[long_n - 1], "y"));
}

const SWIRL_STEPS = 14;

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
        .shocked => {
            rl.drawLine(x + 3, y - 8, x - 3, y - 1, colour);
            rl.drawLine(x - 3, y - 1, x + 3, y + 1, colour);
            rl.drawLine(x + 3, y + 1, x - 3, y + 8, colour);
        },
        .sundered, .exposed => {
            rl.drawRectangleLines(x - 6, y - 7, 12, 14, colour);
            rl.drawLine(x - 1, y - 7, x + 2, y - 1, colour);
            rl.drawLine(x + 2, y - 1, x - 2, y + 3, colour);
            rl.drawLine(x - 2, y + 3, x + 1, y + 7, colour);
        },
        .blinded => {
            rl.drawEllipseLines(x, y, 8, 4, colour);
            rl.drawCircle(x, y, 2, colour);
            rl.drawLine(x - 7, y + 7, x + 7, y - 7, colour);
        },
        .confused => {
            const origin = raster.vec(.{ .x = x, .y = y });
            var at = origin;
            for (1..SWIRL_STEPS + 1) |i| {
                const k: f32 = @floatFromInt(i);
                const a = k * 0.9;
                const r = k * 0.55;
                const next = rl.Vector2{ .x = origin.x + @cos(a) * r, .y = origin.y + @sin(a) * r };
                rl.drawLineV(at, next, colour);
                at = next;
            }
        },
        .enfeebled => {
            rl.drawLine(x - 6, y - 6, x, y, colour);
            rl.drawLine(x, y, x + 6, y - 6, colour);
            rl.drawLine(x - 6, y + 1, x, y + 7, colour);
            rl.drawLine(x, y + 7, x + 6, y + 1, colour);
        },
        .maimed => {
            rl.drawLine(x - 2, y - 8, x - 2, y, colour);
            rl.drawLine(x - 2, y, x + 5, y + 4, colour);
            rl.drawLine(x + 5, y + 4, x + 1, y + 8, colour);
            rl.drawLine(x - 7, y + 8, x + 7, y + 8, colour);
        },
        .frightened => {
            rl.drawRectangle(x - 1, y - 8, 3, 11, colour);
            rl.drawRectangle(x - 1, y + 5, 3, 3, colour);
        },
        .warded, .guarding => {
            rl.drawCircleLines(x, y, 8, colour);
            rl.drawCircleLines(x, y, 5, colour);
        },
        .resistant => {
            for (0..3) |i| {
                const dy: i32 = @intCast(i * 5);
                rl.drawRectangle(x - 7, y - 6 + dy, 14, 3, colour);
            }
        },
        .unyielding => {
            rl.drawLine(x - 6, y - 7, x - 6, y + 6, colour);
            rl.drawLine(x + 6, y - 7, x + 6, y + 6, colour);
            rl.drawLine(x - 6, y + 6, x + 6, y + 6, colour);
            rl.drawLine(x - 4, y + 3, x + 4, y - 5, colour);
        },
        .steady, .overwatch => {
            rl.drawCircleLines(x, y, 6, colour);
            rl.drawLine(x - 9, y, x + 9, y, colour);
            rl.drawLine(x, y - 9, x, y + 9, colour);
        },
        .imbued => {
            rl.drawLine(x - 7, y + 8, x + 5, y - 4, colour);
            rl.drawLine(x - 6, y + 2, x - 1, y + 7, colour);
            rl.drawLine(x + 3, y - 2, x + 3, y - 8, colour);
            rl.drawLine(x + 3, y - 8, x + 7, y - 3, colour);
        },
        .biding => {
            rl.drawCircleLines(x, y, 8, colour);
            rl.drawLine(x - 4, y - 4, x + 4, y + 4, colour);
            rl.drawLine(x - 4, y + 4, x + 4, y - 4, colour);
        },
    }
}

test "the HUD stays centered at a fixed width with room between orbs and skills" {
    const display = @import("../core/window.zig");
    const widths = [_]mathx.P{ display.SCREEN_720, display.WINDOW, display.SCREEN_1080, display.SCREEN_1440 };
    for (widths) |screen| {
        const layout = Layout.of(screen, SKILLS_MAX_W);
        try std.testing.expectEqual(screen.x, layout.left * 2 + WIDTH);
        try std.testing.expectEqual(screen.x, layout.life.x + layout.mana.x);
        try std.testing.expect(layout.life.x + ORB_R + ORB_GAP <= layout.skills.x);
        try std.testing.expect(layout.skills.x + layout.skills_w + ORB_GAP <= layout.mana.x - ORB_R);
        try std.testing.expect(layout.top > 0 and layout.life.y + ORB_R < screen.y);
    }
}

test "orb fill clamps values and gives full half and empty reservoirs" {
    const cases = [_]struct { value: i32, max: i32, want: i32 }{
        .{ .value = 100, .max = 100, .want = FILL_R * 2 },
        .{ .value = 50, .max = 100, .want = FILL_R },
        .{ .value = 0, .max = 100, .want = 0 },
        .{ .value = -5, .max = 100, .want = 0 },
        .{ .value = 110, .max = 100, .want = FILL_R * 2 },
        .{ .value = std.math.maxInt(i32), .max = std.math.maxInt(i32), .want = FILL_R * 2 },
    };
    for (cases) |c| try std.testing.expectEqual(c.want, fillHeight(mathx.fillOf(c.value, c.max)));
}
