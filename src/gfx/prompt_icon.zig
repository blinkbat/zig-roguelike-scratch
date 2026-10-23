const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const font = @import("font.zig");
const look = @import("look.zig");
const raster = @import("raster.zig");

/// Device-specific input icons: PlayStation shapes, Xbox letters, or keyboard caps.
pub const Prompt = union(enum) {
    face: struct { button: FaceButton, sony: bool },
    pill: [:0]const u8,
    view,
    menu,
    key: [:0]const u8,
    stick: enum { left, right },
    dpad,
    arrows,
    mouse: enum { left, right, middle, wheel },

    pub fn menuOf(st: *const input.State, b: input.Button) Prompt {
        return if (st.device.pad()) of(st, b) else .{ .key = st.caption(b) };
    }

    /// A menu button as `device` shows it, outside any live input state.
    pub fn menuOn(device: input.Device, b: input.Button) Prompt {
        return menuOf(&.{ .device = device }, b);
    }

    pub fn of(st: *const input.State, b: input.Button) Prompt {
        if (!st.device.pad()) return .{ .key = st.slotCaption(b) };
        return switch (b.pad()) {
            .right_face_down => .{ .face = .{ .button = .a, .sony = st.device.playstation() } },
            .right_face_right => .{ .face = .{ .button = .b, .sony = st.device.playstation() } },
            .right_face_left => .{ .face = .{ .button = .x, .sony = st.device.playstation() } },
            .right_face_up => .{ .face = .{ .button = .y, .sony = st.device.playstation() } },
            .left_trigger_1, .right_trigger_1, .right_trigger_2, .right_thumb => .{ .pill = st.caption(b) },
            .middle_right => if (st.device.playstation()) .{ .pill = st.caption(b) } else .menu,
            .middle_left => if (st.device.playstation()) .{ .pill = st.caption(b) } else .view,
            else => unreachable,
        };
    }

    /// Across, at `h` tall.
    pub fn width(p: Prompt, face: *const font.Face, h: i32) i32 {
        return switch (p) {
            .face, .stick, .dpad, .arrows, .mouse => h,
            .pill => |s| face.width(s, labelPx(h)) + h,
            .view, .menu => h + @divTrunc(h, 2),
            .key => |s| @max(h, face.width(s, labelPx(h)) + @divTrunc(h, 2)),
        };
    }

    /// `draw`, its left on `x`; returns the x past it.
    pub fn drawFrom(p: Prompt, face: *const font.Face, x: i32, cy: i32, h: i32, alpha: f32) i32 {
        const w = p.width(face, h);
        p.draw(face, x + @divTrunc(w, 2), cy, h, alpha);
        return x + w;
    }

    /// Its middle on `cx`, `cy`, `h` tall, faded to `alpha`.
    pub fn draw(p: Prompt, face: *const font.Face, cx: i32, cy: i32, h: i32, alpha: f32) void {
        const w = p.width(face, h);
        const box = raster.rect(cx - @divTrunc(w, 2), cy - @divTrunc(h, 2), w, h);
        switch (p) {
            .stick => |side| {
                const c = raster.vec(.{ .x = cx, .y = cy });
                const radius: f32 = @as(f32, @floatFromInt(h)) * 0.46;
                rl.drawCircleV(c, radius, look.fade(PROMPT_BODY, alpha));
                rl.drawRing(c, radius - 1.5, radius, 0, 360, 24, look.fade(PROMPT_EDGE, alpha));
                face.centred(if (side == .left) "L" else "R", cx, cy, labelPx(h), look.fade(PROMPT_INK, alpha));
            },
            .dpad, .arrows => {
                const step = @divTrunc(h, 3);
                for (input.DPAD) |d| {
                    const offset = d.delta();
                    const ink = if (p == .dpad and offset.x != 0) PROMPT_EDGE else PROMPT_INK;
                    promptArrow(d, cx + offset.x * step, cy + offset.y * step, arrowPx(h), look.fade(ink, alpha));
                }
            },
            .mouse => |button| {
                const shell = raster.rect(cx - @divTrunc(h, 3), cy - @divTrunc(h, 2), @divTrunc(h * 2, 3), h);
                rl.drawRectangleRounded(shell, MOUSE_ROUND.roundness, MOUSE_ROUND.segments, look.fade(PROMPT_BODY, alpha));
                rl.drawRectangleRoundedLinesEx(shell, MOUSE_ROUND.roundness, MOUSE_ROUND.segments, 1, look.fade(PROMPT_EDGE, alpha));
                const x: f32 = @floatFromInt(cx);
                const y: f32 = @floatFromInt(cy);
                const s: f32 = @floatFromInt(h);
                if (button == .left or button == .right) {
                    rl.drawRectangleRec(.{ .x = x + (if (button == .left) -s * 0.24 else @as(f32, 0.04)), .y = y - s * 0.33, .width = s * 0.2, .height = s * 0.3 }, look.fade(PROMPT_INK, alpha));
                } else {
                    rl.drawRectangleRounded(.{ .x = x - 1.5, .y = y - s * 0.3, .width = 3, .height = s * 0.3 }, WHEEL_ROUND.roundness, WHEEL_ROUND.segments, look.fade(PROMPT_INK, alpha));
                    if (button == .wheel) for ([_]mathx.Dir{ .n, .s }) |d| {
                        promptArrow(d, cx, cy + d.delta().y * @divTrunc(h, 3), arrowPx(h), look.fade(PROMPT_INK, alpha));
                    };
                }
            },
            .face => |f| faceButton(face, f.button, f.sony, cx, cy, h, alpha),
            .pill => |s| {
                pill(box, alpha);
                face.centred(s, cx, cy, labelPx(h), look.fade(PROMPT_INK, alpha));
            },
            .view => {
                pill(box, alpha);
                viewMark(cx, cy, h, alpha);
            },
            .menu => {
                pill(box, alpha);
                menuMark(cx, cy, h, alpha);
            },
            .key => |s| {
                keycap(box, alpha);
                const direction: ?mathx.Dir = for (input.ARROW_KEYS) |a| {
                    if (std.mem.eql(u8, s, a.caption)) break a.d;
                } else null;
                if (direction) |d| promptArrow(d, cx, cy - @divTrunc(h, 12), @divTrunc(h, 2), look.fade(PROMPT_INK, alpha)) else face.centred(s, cx, cy - @divTrunc(h, 12), labelPx(h), look.fade(PROMPT_INK, alpha));
            },
        }
    }
};

/// The small arrows of an input icon `h` tall.
fn arrowPx(h: i32) i32 {
    return @max(6, @divTrunc(h, 3));
}

fn promptArrow(d: mathx.Dir, cx: i32, cy: i32, size: i32, col: rl.Color) void {
    const delta = d.delta();
    const dx: f32 = @floatFromInt(delta.x);
    const dy: f32 = @floatFromInt(delta.y);
    const radius = @as(f32, @floatFromInt(size)) / 2;
    const x: f32 = @floatFromInt(cx);
    const y: f32 = @floatFromInt(cy);
    const tip = rl.Vector2{ .x = x + dx * radius, .y = y + dy * radius };
    rl.drawLineEx(.{ .x = x - dx * radius, .y = y - dy * radius }, tip, 1.2, col);
    for ([_]f32{ -1, 1 }) |side| rl.drawLineEx(.{ .x = x - dy * radius * side, .y = y + dx * radius * side }, tip, 1.2, col);
}

/// An input icon `h` tall: its caption's text size.
pub fn labelPx(h: i32) i32 {
    return @divTrunc(h * 11, 16);
}

const PROMPT_BODY = look.rgb(0x1b1713);
const PROMPT_FACE = look.rgb(0x28221c);
const PROMPT_EDGE = look.rgb(0x6a604e);
const PROMPT_LIP = look.rgb(0x0c0a08);
const PROMPT_INK = look.rgb(0xe2d2b4);

pub const FaceButton = enum { a, b, x, y };

pub fn faceInk(b: FaceButton, sony: bool) rl.Color {
    return switch (b) {
        .a => if (sony) look.rgb(0x7cb2e8) else look.rgb(0x5eb242),
        .b => if (sony) look.rgb(0xea6060) else look.rgb(0xd63e34),
        .x => if (sony) look.rgb(0xd686c4) else look.rgb(0x2e78cd),
        .y => if (sony) look.rgb(0x40c4a0) else look.UI_FOCUS,
    };
}

fn faceButton(face: *const font.Face, b: FaceButton, sony: bool, cx: i32, cy: i32, h: i32, alpha: f32) void {
    const r: f32 = @as(f32, @floatFromInt(h)) / 2;
    const c = raster.vec(.{ .x = cx, .y = cy });
    const ink = faceInk(b, sony);
    rl.drawCircleV(c, r, look.fade(PROMPT_LIP, alpha));
    rl.drawCircleV(c, r - 1, look.fade(PROMPT_BODY, alpha));
    rl.drawCircleV(.{ .x = c.x, .y = c.y - r * 0.12 }, r * 0.78, look.fade(PROMPT_FACE, alpha));
    rl.drawRing(c, r - 2.6, r - 1, 0, 360, 32, look.fade(ink, alpha));
    if (!sony) {
        const letter = [_:0]u8{std.ascii.toUpper(@tagName(b)[0])};
        return face.centred(&letter, cx, cy, labelPx(h), look.fade(ink, alpha));
    }
    const s = r * 0.42;
    const line = @max(1.5, r * 0.16);
    const col = look.fade(ink, alpha);
    switch (b) {
        .a => {
            rl.drawLineEx(.{ .x = c.x - s, .y = c.y - s }, .{ .x = c.x + s, .y = c.y + s }, line, col);
            rl.drawLineEx(.{ .x = c.x - s, .y = c.y + s }, .{ .x = c.x + s, .y = c.y - s }, line, col);
        },
        .b => rl.drawRing(c, s - line / 2, s + line / 2, 0, 360, 24, col),
        .x => rl.drawRectangleLinesEx(.{ .x = c.x - s, .y = c.y - s, .width = s * 2, .height = s * 2 }, line, col),
        .y => {
            const top = rl.Vector2{ .x = c.x, .y = c.y - s * 1.1 };
            const left = rl.Vector2{ .x = c.x - s * 1.1, .y = c.y + s * 0.8 };
            const right = rl.Vector2{ .x = c.x + s * 1.1, .y = c.y + s * 0.8 };
            rl.drawLineEx(top, left, line, col);
            rl.drawLineEx(left, right, line, col);
            rl.drawLineEx(right, top, line, col);
        },
    }
}

const Round = struct { roundness: f32, segments: i32 };
const PILL_ROUND = Round{ .roundness = 0.6, .segments = 8 };
const KEYCAP_ROUND = Round{ .roundness = 0.3, .segments = 6 };
const MOUSE_ROUND = Round{ .roundness = 0.65, .segments = 8 };
const WHEEL_ROUND = Round{ .roundness = 0.5, .segments = 4 };

fn pill(box: rl.Rectangle, alpha: f32) void {
    rl.drawRectangleRounded(box, PILL_ROUND.roundness, PILL_ROUND.segments, look.fade(PROMPT_BODY, alpha));
    rl.drawRectangleRoundedLinesEx(box, PILL_ROUND.roundness, PILL_ROUND.segments, 1, look.fade(PROMPT_EDGE, alpha));
}

fn keycap(box: rl.Rectangle, alpha: f32) void {
    const lip = @max(2, box.height / 8);
    rl.drawRectangleRounded(box, KEYCAP_ROUND.roundness, KEYCAP_ROUND.segments, look.fade(PROMPT_LIP, alpha));
    const top = rl.Rectangle{ .x = box.x, .y = box.y, .width = box.width, .height = box.height - lip };
    rl.drawRectangleRounded(top, KEYCAP_ROUND.roundness, KEYCAP_ROUND.segments, look.fade(PROMPT_FACE, alpha));
    rl.drawRectangleRoundedLinesEx(top, KEYCAP_ROUND.roundness, KEYCAP_ROUND.segments, 1, look.fade(PROMPT_EDGE, alpha));
}

fn viewMark(cx: i32, cy: i32, h: i32, alpha: f32) void {
    const s: f32 = @as(f32, @floatFromInt(h)) * 0.22;
    const x: f32 = @floatFromInt(cx);
    const y: f32 = @floatFromInt(cy);
    const col = look.fade(PROMPT_INK, alpha);
    rl.drawRectangleLinesEx(.{ .x = x - s * 1.3, .y = y - s * 1.1, .width = s * 1.6, .height = s * 1.4 }, 1.2, col);
    rl.drawRectangleLinesEx(.{ .x = x - s * 0.3, .y = y - s * 0.3, .width = s * 1.6, .height = s * 1.4 }, 1.2, col);
}

fn menuMark(cx: i32, cy: i32, h: i32, alpha: f32) void {
    const s: f32 = @as(f32, @floatFromInt(h)) * 0.24;
    const x: f32 = @floatFromInt(cx);
    const y: f32 = @floatFromInt(cy);
    for ([_]f32{ -1, 0, 1 }) |k| rl.drawLineEx(.{ .x = x - s, .y = y + k * s * 0.7 }, .{ .x = x + s, .y = y + k * s * 0.7 }, 1.5, look.fade(PROMPT_INK, alpha));
}
