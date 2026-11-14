const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const atlas = @import("../../map/atlas.zig");
const lens = @import("../../gfx/lens.zig");
const game = @import("../../game.zig");

pub const SHOT_SEED: u64 = 0x5EED_1234;
pub const SHOTS_DIR = "shots";
pub const SHOTS_MAPS = SHOTS_DIR ++ "/maps";
pub const MOUSE_DIR = SHOTS_DIR ++ "/mouse";
pub const CINEMA_DIR = SHOTS_DIR ++ "/cinema";
pub const SIZES = [_]mathx.P{ game.SCREEN_720, game.SCREEN_1080 };
const PATH_MAX = 256;

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

pub const SHOT_BIOME = "qud/qud_salt_marsh";
pub const SHOT_OUTDOOR = "wilds";

pub const MIN_PIXELS = 100;
pub const sameRgb = game.harness.sameRgb;

/// Draws into `target`, whose batch raylib flushes at `endTextureMode`, and saves it.
pub fn capture(g: *game.Game, target: rl.RenderTexture2D, path: [:0]const u8) !void {
    drawInto(g, target);
    try exportTarget(target, path);
}

pub fn capturef(g: *game.Game, target: rl.RenderTexture2D, comptime fmt: []const u8, args: anytype) !void {
    var path: [PATH_MAX]u8 = undefined;
    try capture(g, target, try std.fmt.bufPrintZ(&path, fmt, args));
}

/// The target's pixels, top row first; the caller unloads it.
pub fn readTarget(target: rl.RenderTexture2D) !rl.Image {
    var img = try rl.loadImageFromTexture(target.texture);
    rl.imageFlipVertical(&img);
    return img;
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
