const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");

pub fn whole(t: rl.Texture2D) rl.Rectangle {
    return rect(0, 0, t.width, t.height);
}

pub fn facing(t: rl.Texture2D, left: bool) rl.Rectangle {
    return rect(0, 0, if (left) -t.width else t.width, t.height);
}

pub fn sizeOf(t: rl.Texture2D) [2]f32 {
    return .{ @floatFromInt(t.width), @floatFromInt(t.height) };
}

pub fn uvOf(t: rl.Texture2D, r: rl.Rectangle) [4]f32 {
    const w, const h = sizeOf(t);
    return .{ r.x / w, r.y / h, r.width / w, r.height / h };
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

pub fn middleAt(r: rl.Rectangle) mathx.P {
    const m = middle(r);
    return .{ .x = @intFromFloat(m.x), .y = @intFromFloat(m.y) };
}

pub fn stretch(t: rl.Texture2D, dest: rl.Rectangle, tint: rl.Color) void {
    blit(t, whole(t), dest, tint);
}

pub fn meter(x: i32, y: i32, w: i32, h: i32, v: i32, max: i32, back: rl.Color, fill: rl.Color) void {
    rl.drawRectangle(x, y, w, h, back);
    rl.drawRectangle(x, y, mathx.filled(v, max, w), h, fill);
}

pub fn grown(r: rl.Rectangle, by: f32) rl.Rectangle {
    return .{ .x = r.x - by, .y = r.y - by, .width = r.width + 2 * by, .height = r.height + 2 * by };
}

pub fn blit(t: rl.Texture2D, src: rl.Rectangle, dest: rl.Rectangle, tint: rl.Color) void {
    rl.drawTexturePro(t, src, dest, .{ .x = 0, .y = 0 }, 0, tint);
}

pub fn overFloor(t: rl.Texture2D, ox: i32, oy: i32, cell: i32) void {
    stretch(t, floorRect(ox, oy, cell), look.LIT);
}

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

/// Needs a live GL context.
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

pub fn endTarget(outer: u32) void {
    rl.gl.rlDrawRenderBatchActive();
    rl.gl.rlEnableFramebuffer(outer);
}

pub fn beginBlend(src: i32, dst: i32, equation: i32) void {
    rl.gl.rlSetBlendFactors(src, dst, equation);
    rl.beginBlendMode(.custom);
}

pub fn beginReplace() void {
    beginBlend(rl.gl.rl_one, rl.gl.rl_zero, rl.gl.rl_func_add);
}

/// A render texture over the whole frame, flipped the right way up.
pub fn drawTarget(t: rl.Texture2D) void {
    drawTargetPart(t, whole(t), rl.Color.white);
}

pub fn drawTargetPart(t: rl.Texture2D, r: rl.Rectangle, tint: rl.Color) void {
    const h: f32 = @floatFromInt(t.height);
    rl.drawTextureRec(t, .{ .x = r.x, .y = h - r.y - r.height, .width = r.width, .height = -r.height }, .{ .x = r.x, .y = r.y }, tint);
}

/// Needs a live GL context.
pub fn radial(comptime px: i32, comptime alphaAt: fn (f32) f32) ?rl.Texture2D {
    return fieldOf(px, px, roundOf(alphaAt), false);
}

pub fn radialPremultiplied(comptime px: i32, comptime alphaAt: fn (f32) f32) ?rl.Texture2D {
    return fieldOf(px, px, roundOf(alphaAt), true);
}

fn roundOf(comptime alphaAt: fn (f32) f32) fn (f32, f32) f32 {
    return struct {
        fn at(u: f32, v: f32) f32 {
            return alphaAt(mathx.len(u * 2 - 1, v * 2 - 1));
        }
    }.at;
}

/// Needs a live GL context.
pub fn field(comptime w: i32, comptime h: i32, comptime alphaAt: fn (f32, f32) f32) ?rl.Texture2D {
    return fieldOf(w, h, alphaAt, false);
}

fn fieldOf(comptime w: i32, comptime h: i32, comptime alphaAt: fn (f32, f32) f32, comptime premultiplied: bool) ?rl.Texture2D {
    const nw: usize = @intCast(w);
    const nh: usize = @intCast(h);
    var img: [nw * nh]rl.Color = undefined;
    for (0..nh) |y| {
        for (0..nw) |x| {
            const u = (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(w));
            const v = (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(h));
            const a = alphaAt(u, v);
            img[y * nw + x] = if (premultiplied) look.premultiplied(@splat(1), a) else look.fade(rl.Color.white, a);
        }
    }
    return clamped(rgba(&img, w, h), .bilinear);
}

/// `img`'s texture, with `img` unloaded. Needs a live GL context.
pub fn adopt(img: rl.Image) ?rl.Texture2D {
    defer rl.unloadImage(img);
    return rl.loadTextureFromImage(img) catch null;
}

pub fn release(held: *?rl.Texture2D) void {
    if (held.*) |t| rl.unloadTexture(t);
    held.* = null;
}

fn unloadEach(held: []?rl.Texture2D) void {
    for (held) |*h| release(h);
}

pub fn unloadAll(v: anytype) void {
    inline for (std.meta.fields(@TypeOf(v.*))) |f| {
        if (comptime @typeInfo(f.type) == .@"struct" and @hasField(f.type, "values") and @hasDecl(f.type, "Key") and std.meta.Elem(@FieldType(f.type, "values")) == ?rl.Texture2D) {
            unloadEach(&@field(v.*, f.name).values);
            continue;
        }
        if (comptime @typeInfo(f.type) == .array and std.meta.Elem(f.type) == ?rl.Texture2D) {
            unloadEach(&@field(v.*, f.name));
            continue;
        }
        const Child = switch (@typeInfo(f.type)) {
            .optional => |o| o.child,
            else => void,
        };
        const program_ = @typeInfo(Child) == .@"struct" and @hasField(Child, "shader");
        const resource = Child == rl.Texture2D or Child == rl.RenderTexture2D or Child == rl.Shader or program_;
        if (!resource and comptime std.mem.startsWith(u8, @typeName(Child), "raylib.")) @compileError("unloadAll frees no " ++ @typeName(Child));
        if (resource) {
            const held = &@field(v.*, f.name);
            if (held.*) |r| {
                if (Child == rl.Texture2D) rl.unloadTexture(r) else if (Child == rl.RenderTexture2D) rl.unloadRenderTexture(r) else if (Child == rl.Shader) rl.unloadShader(r) else rl.unloadShader(r.shader);
            }
            held.* = null;
        }
    }
}
