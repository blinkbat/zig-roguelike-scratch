const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const hero = @import("../play/hero.zig");
const actor = @import("../play/actor.zig");

const N = hero.CLASSES.len;
const N_I: i32 = N;

/// Screen height per whole step of sprite scale.
const SCALE_STEP: i32 = 240;
const INFO_W: i32 = 340;
const COLUMN_GAP: i32 = 48;
/// From the heading's top to the sprites' tops, where the beam shows.
const HEAD_ROOM: i32 = menu.TITLE + 56;
/// From the heading's top to where the beam starts, under its rule.
const BEAM_DROP: i32 = menu.TITLE + 16;
const BEAM_ABOVE: i32 = HEAD_ROOM - BEAM_DROP;
const PITCH_SPRITES: i32 = 2;
const INFO_GAP: i32 = 26;
const BLURB_GAP: i32 = 10;
const BLURB_LINES: i32 = 3;
const INFO_H: i32 = INFO_GAP + menu.ROW + BLURB_GAP + BLURB_LINES * (menu.NOTE + font.LEADING);
const BESIDE_GAP: i32 = 48;

const SHADE = look.rgb(0x1c1a22);
const BEAM = look.rgb(0xfff0cf);
const BEAM_A: f32 = 0.2;
const BEAM_SLICES = 24;
const BEAM_TOP_W: f32 = 0.16;
const BEAM_FOOT_W: f32 = 0.56;
/// Of the beam's half-width, the edge over which it fades out.
const BEAM_SOFT: f32 = 0.6;
const POOL_A: f32 = 0.34;
const POOL_RX: f32 = 0.62;
const POOL_RY: f32 = 0.15;
const POOL_SEGMENTS = 40;
/// Of the pitch between heroes, how far from the beam a hero falls fully into shadow.
const LIGHT_REACH: f32 = 0.5;

const SPOT_RATE: f32 = 9;
const SHOW_RATE: f32 = 8;

pub fn scaleFor(screen: mathx.P) i32 {
    const tall = @divTrunc(screen.y, SCALE_STEP);
    const wide = @divTrunc(screen.x - 2 * menu.PANEL_PAD, N_I * PITCH_SPRITES * look.SPRITE_PX);
    return @max(1, @min(tall, wide));
}

/// Every hero's body that is not resident yet, loaded beside what is; true when any was missing.
pub fn loadHeroes(sprites: *look.Sprites) bool {
    var need = sprites.resident();
    var missing = false;
    for (hero.CLASSES) |c| {
        missing = missing or sprites.body(c.kind()) == null;
        need.body(c.kind());
    }
    if (missing) sprites.sync(need);
    return missing;
}

/// `k` standing with its feet's middle on `feet`, `scale` times its pixels, `light` from shadow (0) to its own colours (1).
pub fn figure(sprites: *const look.Sprites, k: actor.Kind, feet: mathx.P, scale: i32, light: f32) void {
    const tex = sprites.body(k) orelse return;
    const size = look.SPRITE_PX * scale;
    raster.stretch(tex, raster.rect(feet.x - @divTrunc(size, 2), feet.y - size, size, size), look.mixed(SHADE, look.LIT, light));
}

/// A soft beam from `top` down onto a pool at `feet`, sized for a figure `size` pixels tall.
pub fn spotlight(cx: f32, top: f32, feet: f32, size: f32) void {
    rl.gl.rlSetTexture(rl.gl.rlGetTextureIdDefault());
    defer rl.gl.rlSetTexture(0);
    rl.gl.rlBegin(rl.gl.rl_triangles);
    defer rl.gl.rlEnd();
    const clear = look.fade(BEAM, 0);
    const w0 = size * BEAM_TOP_W;
    const w1 = size * BEAM_FOOT_W;
    const fade_y = feet + size * POOL_RY;
    for (0..BEAM_SLICES) |s| {
        const l = across(s);
        const r = across(s + 1);
        const cl = look.fade(BEAM, BEAM_A * beamEdge(l));
        const cr = look.fade(BEAM, BEAM_A * beamEdge(r));
        vertex(cx + w0 * l, top, clear);
        vertex(cx + w1 * l, feet, cl);
        vertex(cx + w1 * r, feet, cr);
        vertex(cx + w0 * l, top, clear);
        vertex(cx + w1 * r, feet, cr);
        vertex(cx + w0 * r, top, clear);
        vertex(cx + w1 * l, feet, cl);
        vertex(cx + w1 * l, fade_y, clear);
        vertex(cx + w1 * r, fade_y, clear);
        vertex(cx + w1 * l, feet, cl);
        vertex(cx + w1 * r, fade_y, clear);
        vertex(cx + w1 * r, feet, cr);
    }
    const rx = size * POOL_RX;
    const ry = size * POOL_RY;
    const core = look.fade(BEAM, POOL_A);
    for (0..POOL_SEGMENTS) |s| {
        const a0 = mathx.TAU * @as(f32, @floatFromInt(s)) / POOL_SEGMENTS;
        const a1 = mathx.TAU * @as(f32, @floatFromInt(s + 1)) / POOL_SEGMENTS;
        vertex(cx, feet, core);
        vertex(cx + rx * @cos(a1), feet + ry * @sin(a1), clear);
        vertex(cx + rx * @cos(a0), feet + ry * @sin(a0), clear);
    }
}

fn across(s: usize) f32 {
    return @as(f32, @floatFromInt(s)) / BEAM_SLICES * 2 - 1;
}

fn beamEdge(u: f32) f32 {
    return mathx.smooth((1 - @abs(u)) / BEAM_SOFT);
}

fn vertex(x: f32, y: f32, c: rl.Color) void {
    rl.gl.rlColor4ub(c.r, c.g, c.b, c.a);
    rl.gl.rlVertex2f(x, y);
}

/// `k` spotlit, standing left of `box` with its feet level with `box`'s foot.
pub fn beside(sprites: *const look.Sprites, k: actor.Kind, box: rl.Rectangle, screen: mathx.P) void {
    const at = Beside.of(box, screen);
    spotlight(@floatFromInt(at.feet.x), at.top(), @floatFromInt(at.feet.y), @floatFromInt(at.size));
    figure(sprites, k, at.feet, at.scale, 1);
}

pub fn besideBounds(box: rl.Rectangle, screen: mathx.P) rl.Rectangle {
    const at = Beside.of(box, screen);
    const size: f32 = @floatFromInt(at.size);
    const cx: f32 = @floatFromInt(at.feet.x);
    return .{ .x = cx - size * POOL_RX, .y = at.top(), .width = size * POOL_RX * 2, .height = size * (1 + POOL_RY) + @as(f32, @floatFromInt(BEAM_ABOVE)) };
}

/// Where `beside` stands its figure for `box`, and how large.
const Beside = struct {
    feet: mathx.P,
    scale: i32,
    size: i32,

    fn of(box: rl.Rectangle, screen: mathx.P) Beside {
        const scale = scaleFor(screen);
        const size = look.SPRITE_PX * scale;
        return .{ .scale = scale, .size = size, .feet = .{ .x = @as(i32, @intFromFloat(box.x)) - BESIDE_GAP - @divTrunc(size, 2), .y = @intFromFloat(box.y + box.height) } };
    }

    /// The beam's top, over the figure's head.
    fn top(self: Beside) f32 {
        return @floatFromInt(self.feet.y - self.size - BEAM_ABOVE);
    }
};

const Layout = struct {
    scale: i32,
    size: i32,
    pitch: i32,
    info_w: i32,
    top: i32,
    feet_y: i32,
    left: i32,

    fn of(screen: mathx.P) Layout {
        const scale = scaleFor(screen);
        const size = look.SPRITE_PX * scale;
        const pitch = @min(@max(INFO_W + COLUMN_GAP, PITCH_SPRITES * size), @divTrunc(screen.x - 2 * menu.PANEL_PAD, N_I));
        const top = @divTrunc(screen.y - (HEAD_ROOM + size + INFO_H), 2);
        return .{
            .scale = scale,
            .size = size,
            .pitch = pitch,
            .info_w = @min(INFO_W, pitch - COLUMN_GAP),
            .top = top,
            .feet_y = top + HEAD_ROOM + size,
            .left = @divTrunc(screen.x - pitch * N_I, 2),
        };
    }

    fn centreX(self: Layout, at: f32) f32 {
        return @as(f32, @floatFromInt(self.left)) + (at + 0.5) * @as(f32, @floatFromInt(self.pitch));
    }

    fn feet(self: Layout, i: usize) mathx.P {
        return .{ .x = @intFromFloat(self.centreX(@floatFromInt(i))), .y = self.feet_y };
    }

    fn box(self: Layout, i: usize) rl.Rectangle {
        const y = self.feet_y - self.size - @divTrunc(BEAM_ABOVE, 2);
        return raster.rect(self.left + @as(i32, @intCast(i)) * self.pitch, y, self.pitch, self.feet_y + INFO_H - y);
    }
};

/// The heroes side by side, a spotlight easing onto the chosen one and its words fading in beneath it.
pub const Lineup = struct {
    at: usize = 0,
    spot: f32 = 0,
    shown: [N]f32 = shownAt(0),

    fn shownAt(at: usize) [N]f32 {
        var out: [N]f32 = undefined;
        for (&out, 0..) |*s, i| s.* = goal(at, i);
        return out;
    }

    fn goal(at: usize, i: usize) f32 {
        return @floatFromInt(@intFromBool(i == at));
    }

    pub fn on(i: usize) Lineup {
        var l = Lineup{ .at = i };
        l.settle();
        return l;
    }

    pub fn settle(self: *Lineup) void {
        self.spot = @floatFromInt(self.at);
        self.shown = shownAt(self.at);
    }

    pub fn step(self: *Lineup, st: *const input.State, screen: mathx.P) ?usize {
        if (menu.pointAt(&self.at, st, N, Layout.of(screen), Layout.box)) |i| return i;
        if (st.walk) |d| {
            const v = d.delta();
            self.at = mathx.wrap(self.at, if (v.x != 0) v.x else v.y, N);
        }
        return if (st.hit(menu.CONFIRM)) self.at else null;
    }

    pub fn tick(self: *Lineup, dt: f32) void {
        const k = mathx.easing(dt, SPOT_RATE);
        self.spot = mathx.ease(self.spot, @floatFromInt(self.at), k, k);
        const f = mathx.easing(dt, SHOW_RATE);
        for (&self.shown, 0..) |*s, i| s.* = mathx.ease(s.*, goal(self.at, i), f, f);
    }

    fn lightOf(self: *const Lineup, i: usize) f32 {
        return mathx.smooth(1 - @abs(self.spot - @as(f32, @floatFromInt(i))) / LIGHT_REACH);
    }

    pub fn draw(self: *const Lineup, face: font.Face, sprites: *const look.Sprites, screen: mathx.P, title: [:0]const u8) void {
        const lay = Layout.of(screen);
        menu.pageHeading(face, screen, title, lay.top);
        spotlight(lay.centreX(self.spot), @floatFromInt(lay.top + BEAM_DROP), @floatFromInt(lay.feet_y), @floatFromInt(lay.size));
        for (hero.CLASSES, 0..) |c, i| {
            const feet = lay.feet(i);
            figure(sprites, c.kind(), feet, lay.scale, self.lightOf(i));
            const a = mathx.smooth(self.shown[i]);
            if (a <= 0) continue;
            const y = feet.y + INFO_GAP;
            face.engravedMid(c.title(), feet.x, y, menu.ROW, look.fade(look.UI_FOCUS, a));
            _ = face.paragraphWith(font.Face.textMid, c.blurb(), feet.x, y + menu.ROW + BLURB_GAP, lay.info_w, menu.NOTE, look.fade(look.DIM, a));
        }
    }
};

const SCREENS = @import("../core/window.zig").SCREENS;

test "the spotlight eases onto the chosen hero and only its words stay shown" {
    var l = Lineup{};
    _ = l.step(&.{ .walk = .e }, SCREENS[0]);
    try std.testing.expectEqual(@as(usize, 1), l.at);
    l.tick(1.0 / 60.0);
    try std.testing.expect(l.spot > 0 and l.spot < 1);
    try std.testing.expect(l.shown[0] < 1 and l.shown[1] > 0 and l.shown[2] == 0);
    var frames: usize = 1;
    var last = l.spot;
    while (l.spot != 1 or l.shown[0] != 0 or l.shown[1] != 1) : (frames += 1) {
        l.tick(1.0 / 60.0);
        try std.testing.expect(l.spot >= last);
        last = l.spot;
        try std.testing.expect(frames < 120);
    }
    try std.testing.expectEqual(@as(f32, 1), l.lightOf(1));
    try std.testing.expectEqual(@as(f32, 0), l.lightOf(0));
    _ = l.step(&.{ .walk = .w }, SCREENS[0]);
    _ = l.step(&.{ .walk = .w }, SCREENS[0]);
    try std.testing.expectEqual(@as(usize, N - 1), l.at);
    std.debug.print("lineup: spotlight and words settle on the next hero in {d} frames at 60 fps\n", .{frames});
}

test "pointing at a hero picks it, and the lineup keeps inside the screen at 720p, 1080p and 1440p" {
    for (SCREENS) |screen| {
        const lay = Layout.of(screen);
        try std.testing.expect(lay.box(0).x >= menu.PANEL_PAD and lay.box(N - 1).x + lay.box(N - 1).width <= @as(f32, @floatFromInt(screen.x - menu.PANEL_PAD)));
        try std.testing.expect(lay.top >= menu.PANEL_PAD and lay.box(0).y + lay.box(0).height < menu.footerBox(screen).y);
        try std.testing.expect(lay.size >= 2 * look.SPRITE_PX and @rem(lay.size, look.SPRITE_PX) == 0);
        var l = Lineup{};
        for (0..N) |i| {
            const p = raster.middleAt(lay.box(i));
            try std.testing.expectEqual(@as(?usize, null), l.step(&.{ .pointer = p, .mouse_moved = true }, screen));
            try std.testing.expectEqual(i, l.at);
            try std.testing.expectEqual(@as(?usize, i), l.step(&.{ .pointer = p, .click = true }, screen));
        }
        std.debug.print("lineup at {d}x{d}: {d}x sprites, {d} px apart\n", .{ screen.x, screen.y, lay.scale, lay.pitch });
    }
}
