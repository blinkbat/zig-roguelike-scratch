const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const atlas = @import("../../map/atlas.zig");
const lens = @import("../../gfx/lens.zig");
const look = @import("../../gfx/look.zig");
const game = @import("../../game.zig");

pub const SHOT_SEED: u64 = 0x5EED_1234;
pub const SHOTS_DIR = "shots";
pub const SHOTS_MAPS = SHOTS_DIR ++ "/maps";
pub const MOUSE_DIR = SHOTS_DIR ++ "/mouse";
pub const CINEMA_DIR = SHOTS_DIR ++ "/cinema";
pub const PATH_MAX = 256;

pub fn renderTarget(g: *game.Game) !rl.RenderTexture2D {
    return rl.loadRenderTexture(g.screen.x, g.screen.y);
}

pub const Sized = struct {
    target: rl.RenderTexture2D,
    screen: mathx.P,

    pub fn close(self: Sized, g: *game.Game) void {
        rl.unloadRenderTexture(self.target);
        g.screen = self.screen;
    }
};

pub fn targetAt(g: *game.Game, size: mathx.P) !Sized {
    const screen = g.screen;
    errdefer g.screen = screen;
    g.screen = size;
    return .{ .target = try renderTarget(g), .screen = screen };
}

pub fn target720(g: *game.Game) !Sized {
    return targetAt(g, game.SCREEN_720);
}

pub fn heapAtlas() !*atlas.Atlas {
    return std.heap.c_allocator.create(atlas.Atlas);
}

pub fn dropAtlas(g: *game.Game, w: *atlas.Atlas) void {
    g.sim.map = null;
    std.heap.c_allocator.destroy(w);
}

pub fn neutralLens(g: *game.Game) lens.Options {
    const was = g.cinema.lens.options;
    g.cinema.lens.options = .neutral;
    return was;
}

pub fn differentPixels(a: rl.Image, b: rl.Image) usize {
    var changed: usize = 0;
    var px = pixels(a.width, a.height);
    while (px.next()) |p| changed += @intFromBool(!sameRgb(rl.getImageColor(a, p.x, p.y), rl.getImageColor(b, p.x, p.y)));
    return changed;
}

pub fn redrawnDiff(g: *game.Game, target: rl.RenderTexture2D, base: rl.Image) !usize {
    drawInto(g, target);
    const now = try readTarget(target);
    defer rl.unloadImage(now);
    return differentPixels(base, now);
}

pub const Toggled = struct { changed: usize, restored: bool };

pub fn toggled(g: *game.Game, target: rl.RenderTexture2D, base: rl.Image, value: anytype, off: @TypeOf(value.*), path: ?[:0]const u8) !Toggled {
    const on = value.*;
    value.* = off;
    const changed = changed: {
        defer value.* = on;
        drawInto(g, target);
        if (path) |p| try exportTarget(target, p);
        const now = try readTarget(target);
        defer rl.unloadImage(now);
        break :changed differentPixels(base, now);
    };
    return .{ .changed = changed, .restored = try redrawnDiff(g, target, base) == 0 };
}

pub fn pixels(width: i32, height: i32) grid.Cells {
    return grid.Cells.of(.{ .x = 0, .y = 0 }, .{ .x = width, .y = height });
}

pub fn drawInto(g: *game.Game, target: rl.RenderTexture2D) void {
    game.prepare(g);
    intoTarget(g, target);
    defer outOfTarget(g);
    game.drawFrame(g);
}

pub fn intoTarget(g: *game.Game, target: rl.RenderTexture2D) void {
    rl.beginTextureMode(target);
    g.framebuffer = target.id;
}

pub fn outOfTarget(g: *game.Game) void {
    rl.endTextureMode();
    g.framebuffer = 0;
}

pub fn drawMapInto(g: *game.Game, target: rl.RenderTexture2D, clear: rl.Color) void {
    intoTarget(g, target);
    rl.clearBackground(clear);
    game.scene.drawMap(g);
    outOfTarget(g);
}

/// The atmosphere pass alone over `clear`; the caller unloads it.
pub fn airImage(g: *game.Game, target: rl.RenderTexture2D, clear: rl.Color, reflections: bool) !rl.Image {
    const c = game.scene.Cam.of(g);
    g.cinema.prepare(&g.sim.lv, g.light, game.scene.viewBox(g, c), &.{}, &g.sim.locations, g.pic.local_weather_shown);
    intoTarget(g, target);
    rl.clearBackground(clear);
    g.cinema.drawAir(g.light, c.origin(), game.CELL_F, g.screen, g.pic.hour_shown, reflections);
    outOfTarget(g);
    return readTarget(target);
}

pub fn seekHalfway(g: *game.Game, t: f32, span: f32) void {
    game.update(g, @max(0, span / 2 - t));
}

pub const SHOT_BIOME = "qud/qud_salt_marsh";
pub const SHOT_OUTDOOR = "wilds";

pub const MIN_PIXELS = 100;
pub const VEIL_GAS = 60;
pub const sameRgb = look.sameRgb;

pub fn veil(lv: *grid.Level, cells: grid.Cells) void {
    var each = cells;
    while (each.next()) |p| lv.gas[grid.Level.idx(p)] = VEIL_GAS;
}

/// Draws into `target`, whose batch raylib flushes at `endTextureMode`, and saves it.
pub fn capture(g: *game.Game, target: rl.RenderTexture2D, path: [:0]const u8) !void {
    drawInto(g, target);
    try exportTarget(target, path);
}

pub fn capturef(g: *game.Game, target: rl.RenderTexture2D, comptime fmt: []const u8, args: anytype) !void {
    var path: [PATH_MAX]u8 = undefined;
    try capture(g, target, try std.fmt.bufPrintZ(&path, fmt, args));
}

pub fn captureAlong(g: *game.Game, target: rl.RenderTexture2D, times: []const f32, comptime prefix: []const u8) !void {
    var elapsed: f32 = 0;
    for (times, 0..) |t, i| {
        game.update(g, t - elapsed);
        elapsed = t;
        try capturef(g, target, prefix ++ "{d}.png", .{i});
    }
}

/// The target's pixels, top row first; the caller unloads it.
pub fn readTarget(target: rl.RenderTexture2D) !rl.Image {
    var img = try rl.loadImageFromTexture(target.texture);
    rl.imageFlipVertical(&img);
    return img;
}

pub fn drawOver(target: rl.RenderTexture2D, clear: rl.Color) void {
    rl.beginTextureMode(target);
    rl.clearBackground(clear);
}

pub fn exportDrawn(target: rl.RenderTexture2D, path: [:0]const u8) !void {
    rl.endTextureMode();
    try exportTarget(target, path);
}

pub fn exportTarget(target: rl.RenderTexture2D, path: [:0]const u8) !void {
    errdefer std.debug.print("{s} FAILED\n", .{path});
    var img = try readTarget(target);
    defer rl.unloadImage(img);
    // Blending leaves alpha in the target that a window never shows.
    rl.imageFormat(&img, .uncompressed_r8g8b8);
    try exportImage(img, path);
    std.debug.print("{s} written\n", .{path});
}

pub fn exportImage(img: rl.Image, path: [:0]const u8) !void {
    if (!rl.exportImage(img, path)) return error.ExportFailed;
}
