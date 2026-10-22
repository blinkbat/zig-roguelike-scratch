const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");

pub fn whole(t: rl.Texture2D) rl.Rectangle {
    return rect(0, 0, t.width, t.height);
}

pub fn sizeOf(t: rl.Texture2D) [2]f32 {
    return .{ @floatFromInt(t.width), @floatFromInt(t.height) };
}

pub fn rect(x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    return .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(h) };
}

pub fn vec(p: mathx.P) rl.Vector2 {
    return .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
}

pub fn holds(r: rl.Rectangle, p: mathx.P) bool {
    return rl.checkCollisionPointRec(vec(p), r);
}

pub fn middle(r: rl.Rectangle) rl.Vector2 {
    return .{ .x = r.x + r.width / 2, .y = r.y + r.height / 2 };
}

/// The pixel at `r`'s middle.
pub fn middleAt(r: rl.Rectangle) mathx.P {
    const m = middle(r);
    return .{ .x = @intFromFloat(m.x), .y = @intFromFloat(m.y) };
}

pub fn stretch(t: rl.Texture2D, dest: rl.Rectangle, tint: rl.Color) void {
    blit(t, whole(t), dest, tint);
}

/// `r` grown `by` pixels on every side.
pub fn grown(r: rl.Rectangle, by: f32) rl.Rectangle {
    return .{ .x = r.x - by, .y = r.y - by, .width = r.width + 2 * by, .height = r.height + 2 * by };
}

/// `src` of `t` drawn over `dest`, unturned.
pub fn blit(t: rl.Texture2D, src: rl.Rectangle, dest: rl.Rectangle, tint: rl.Color) void {
    rl.drawTexturePro(t, src, dest, .{ .x = 0, .y = 0 }, 0, tint);
}

pub fn overFloor(t: rl.Texture2D, ox: i32, oy: i32, cell: i32) void {
    stretch(t, floorRect(ox, oy, cell), look.LIT);
}

/// The whole floor on screen, its top-left at `ox, oy`.
pub fn floorRect(ox: i32, oy: i32, cell: i32) rl.Rectangle {
    return rect(ox, oy, grid.W * cell, grid.H * cell);
}

/// Borrows `px`, packed `w` to a row: nothing to unload.
pub fn rgba(px: *anyopaque, w: i32, h: i32) rl.Image {
    return .{ .data = px, .width = w, .height = h, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
}

/// Needs a live GL context.
pub fn clamped(img: rl.Image, filter: rl.TextureFilter) ?rl.Texture2D {
    const t = rl.loadTextureFromImage(img) catch return null;
    rl.setTextureFilter(t, filter);
    rl.setTextureWrap(t, .clamp);
    return t;
}

/// Filled with `c`, for pixels uploaded every frame. Needs a live GL context.
pub fn canvas(w: i32, h: i32, c: rl.Color, filter: rl.TextureFilter) ?rl.Texture2D {
    const img = rl.genImageColor(w, h, c);
    defer rl.unloadImage(img);
    return clamped(img, filter);
}

pub fn beginTarget(target: *?rl.RenderTexture2D, screen: mathx.P, outer: u32, clear: rl.Color) bool {
    rl.gl.rlDrawRenderBatchActive();
    if (target.*) |t| {
        if (t.texture.width != screen.x or t.texture.height != screen.y) {
            rl.unloadRenderTexture(t);
            target.* = null;
        }
    }
    if (target.* == null) target.* = rl.loadRenderTexture(screen.x, screen.y) catch {
        endTarget(outer);
        return false;
    };
    rl.gl.rlEnableFramebuffer(target.*.?.id);
    rl.clearBackground(clear);
    return true;
}

/// Back to `outer` after `beginTarget`, with what was drawn flushed into the target.
pub fn endTarget(outer: u32) void {
    rl.gl.rlDrawRenderBatchActive();
    rl.gl.rlEnableFramebuffer(outer);
}

/// Blending by GL factors and equation, until `rl.endBlendMode`.
pub fn beginBlend(src: i32, dst: i32, equation: i32) void {
    rl.gl.rlSetBlendFactors(src, dst, equation);
    rl.beginBlendMode(.custom);
}

/// A render texture over the whole frame, flipped the right way up.
pub fn drawTarget(t: rl.Texture2D) void {
    rl.drawTextureRec(t, rect(0, 0, t.width, -t.height), .{ .x = 0, .y = 0 }, rl.Color.white);
}

/// White, its alpha `alphaAt(r)` at `r` from the middle, 1 at the middle of each edge. Needs a live GL context.
pub fn radial(comptime px: i32, comptime alphaAt: fn (f32) f32) ?rl.Texture2D {
    const round = struct {
        fn at(u: f32, v: f32) f32 {
            return alphaAt(mathx.len(u * 2 - 1, v * 2 - 1));
        }
    };
    return field(px, px, round.at);
}

/// White, its alpha `alphaAt(u, v)` at each texel's middle, `u` and `v` 0 to 1 across and down. Needs a live GL context.
pub fn field(comptime w: i32, comptime h: i32, comptime alphaAt: fn (f32, f32) f32) ?rl.Texture2D {
    const nw: usize = @intCast(w);
    const nh: usize = @intCast(h);
    var img: [nw * nh]rl.Color = undefined;
    for (0..nh) |y| {
        for (0..nw) |x| {
            const u = (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(w));
            const v = (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(h));
            img[y * nw + x] = look.fade(rl.Color.white, alphaAt(u, v));
        }
    }
    return clamped(rgba(&img, w, h), .bilinear);
}
