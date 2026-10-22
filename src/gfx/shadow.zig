const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const raster = @import("raster.zig");
const shaders = @import("shaders.zig");
const sky = @import("sky.zig");
const light = @import("light.zig");
const P = mathx.P;
const Rgb = sky.Rgb;
const smooth = mathx.smooth;
const lum = sky.luma;

/// And a light at least this bright; a torch is, out to about half its reach.
const SHADOW_LAMP_FULL: f32 = 0.25;
const SHADOW_FAINT = look.CLEAR_A;
/// Of the body's drawn height.
const SHADOW_LEN_LO: f32 = 0.5;
const SHADOW_LEN_HI: f32 = 1.8;
const SHADOW_LEN_PER_CELL: f32 = 0.2;
const SHADOW_SQUASH: f32 = 0.55;
/// Cells: a light this close to a body's middle stands over it and casts no shadow.
pub const SHADOW_OVERHEAD: f32 = 0.05;
const SHADOW_NEAR: f32 = 0.5;
const SHADOW_PAD: f32 = SHADOW_SOFT_TIP * @as(f32, @floatFromInt(light.SHADOW_TAPS));
/// Texels between the shadow shader's blur taps, at its tip and at its foot.
const SHADOW_SOFT_TIP: f32 = 2.0;
const SHADOW_SOFT_FOOT: f32 = 0.6;
/// Vertical shadow share: silhouettes fade to streaks from `THIN_HI` to `THIN_LO`.
const THIN_LO: f32 = 0.06;
const THIN_HI: f32 = 0.28;
/// The streak's half-width, a share of the sprite's width, and its darkness against the silhouette's.
const STREAK_W: f32 = 0.3;
const STREAK_A: f32 = 0.8;
/// Of the streak's length, how much lies behind the feet, where it eases in.
pub const STREAK_FOOT: f32 = 0.1;
/// How sharply it fades from the feet to the tip: 1 evenly.
const STREAK_TAIL: f32 = 1.5;
const CONTACT_W: f32 = 0.62;
const CONTACT_H: f32 = 0.2;
const CONTACT_A: f32 = 0.7;
/// Canopy radius uses sprite width; trunk contact is relative to a body's.
const CANOPY_R: f32 = 0.55;
const CANOPY_SQUASH: f32 = 0.7;
const CANOPY_AT: f32 = 0.45;
const CANOPY_STRETCH: f32 = 0.5;
const CANOPY_A: f32 = 1.6;
const FOREST_STEPS: usize = 8;
const FOREST_A: f32 = 1.3;
const FOREST_MAX: f32 = 0.75;
const FOREST_SOFT: f32 = 3.0;
const FOREST_PAD: f32 = FOREST_SOFT * light.SHADOW_TAPS;
/// Maximum ground reach, in cells, of a cell-tall sky or torch caster.
pub const CAST_REACH: f32 = blk: {
    const l = @max(sky.REACH_MAX, SHADOW_LEN_HI);
    const pad = @max(SHADOW_PAD, FOREST_PAD) / look.SPRITE_PX;
    break :blk 0.5 + @max(pad + l * (1 + pad), CANOPY_AT * l + CANOPY_R * (1 + l * CANOPY_STRETCH));
};
const TRUNK_OF: f32 = 0.6;
fn footOf(self: *const light.Light, tex: rl.Texture2D, dest: rl.Rectangle, s: *const light.Shine, contact: f32) ?struct { x: f32, y: f32, height: f32, share: f32 } {
    const lit = s.reached();
    if (lit <= light.FAINT) return null;
    const foot = self.gpu.art(tex).foot;
    const tall: f32 = @floatFromInt(tex.height);
    const share = foot / tall;
    const height = light.Light.artY(tex, dest, foot);
    const x = raster.middle(dest).x;
    const y = dest.y + height;
    if (self.gpu.glow) |g| {
        const a = CONTACT_A * @min(1, lit / lum(light.CARRY));
        light.glowAt(g, x, y, dest.width * CONTACT_W * 0.5 * contact, dest.width * CONTACT_H * 0.5 * contact, light.colourOf(light.SHADE_RGB, a));
    }
    return .{ .x = x, .y = y, .height = height, .share = share };
}

/// Shadows accumulate by minimum in a screen mask; `outer` restores the framebuffer. False without GL.
pub fn beginShadows(self: *light.Light, screen: P, outer: u32) bool {
    if (!self.options.shadows) return false;
    const pool = self.gpu.shade orelse return false;
    if (self.gpu.shadow == null or self.gpu.receiver == null or self.gpu.layers.get(.map) == null) return false;
    self.gpu.outer = outer;
    if (!raster.beginTarget(&self.gpu.mask, screen, outer, rl.Color.white)) return false;
    raster.beginBlend(rl.gl.rl_one, rl.gl.rl_one, rl.gl.rl_min);
    rl.beginShaderMode(pool);
    return true;
}

pub fn endShadows(self: *light.Light, ox: i32, oy: i32, cell: i32) void {
    flushForest(self);
    rl.endShaderMode();
    rl.endBlendMode();
    raster.endTarget(self.gpu.outer);
    const t = self.gpu.mask.?.texture;
    self.uploadMap();
    const receiver = self.gpu.receiver.?;
    rl.beginBlendMode(.multiplied);
    defer rl.endBlendMode();
    rl.beginShaderMode(receiver.shader);
    defer rl.endShaderMode();
    rl.setShaderValueTexture(receiver.shader, receiver.lightmap, self.gpu.layers.get(.map).?);
    shaders.setMapView(receiver, .of(ox, oy, cell, t.width, t.height));
    raster.drawTarget(t);
}

/// Between `beginShadows` and `endShadows`, before the walls, which cover whatever of it reaches them.
pub fn drawShadows(self: *const light.Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: *const light.Shine) void {
    const f = footOf(self, tex, dest, s, 1) orelse return;
    const fx = f.x;
    const fy = f.y;
    var buf: [light.BODY_LIGHTS]Cast = undefined;
    const cs = casts(s, centre, f.height, &buf);
    if (cs.len == 0) return;
    const foot = f.share;
    if (!beginSilhouettes(self, tex, foot, (Sides{}).uniform(), .{ SHADOW_SOFT_TIP, SHADOW_SOFT_FOOT })) return;
    for (cs) |c| {
        if (c.solid <= 0) continue;
        var full = c;
        full.alpha *= c.solid;
        silhouette(tex, fx, fy, dest.width, foot, left, full);
    }
    endSilhouettes(self);
    const g = self.gpu.streak orelse return;
    for (cs) |c| {
        if (c.solid < 1) streak(g, fx, fy, dest.width, c);
    }
}

/// Between `beginShadows` and `endShadows`: a tree's canopy pool thrown away from each light, a soft pool over its trunk's foot.
pub fn drawCanopy(self: *const light.Light, tex: rl.Texture2D, dest: rl.Rectangle, centre: [2]f32, s: *const light.Shine) void {
    const g = self.gpu.glow orelse return;
    const f = footOf(self, tex, dest, s, TRUNK_OF) orelse return;
    const fx = f.x;
    const fy = f.y;
    const height = f.height;
    var buf: [light.BODY_LIGHTS]Cast = undefined;
    for (casts(s, centre, height, &buf)) |c| {
        const r = dest.width * CANOPY_R;
        const rx = r * (1 + c.len / height * CANOPY_STRETCH);
        const ry = r * CANOPY_SQUASH;
        drawAlong(g, .{ fx + c.lean[0] * CANOPY_AT, fy + c.lean[1] * CANOPY_AT }, c.lean, .{ rx * 2, ry * 2 }, .{ .x = rx, .y = ry }, light.colourOf(c.shade, c.alpha * CANOPY_A));
    }
}

/// Contact draws now; silhouettes batch by joined sides at `endShadows`.
pub fn drawForestShadows(self: *light.Light, tex: rl.Texture2D, dest: rl.Rectangle, centre: [2]f32, s: *const light.Shine, shape: grid.WallShape) void {
    _ = footOf(self, tex, dest, s, 1) orelse return;
    var f = ForestCast{ .tex = tex, .dest = dest, .centre = centre, .cast = undefined, .n = 0, .joined = .of(shape) };
    f.n = casts(s, centre, dest.height, &f.cast).len;
    if (f.n == 0) return;
    if (self.forest_n == FOREST_QUEUE) flushForest(self);
    self.forest[self.forest_n] = f;
    self.forest_n += 1;
}

fn flushForest(self: *light.Light) void {
    defer self.forest_n = 0;
    const order = self.forest_order[0..self.forest_n];
    for (self.forest[0..self.forest_n], order, 0..) |*f, *o, i| {
        const bits: u64 = @as(u4, @bitCast(f.joined));
        o.* = bits << JOINED_AT | @as(u64, f.tex.id) << INDEX_BITS | i;
    }
    std.sort.pdq(u64, order, {}, std.sort.asc(u64));
    var drawing: ?struct { joined: Sides, size: [2]i32 } = null;
    for (order) |o| {
        const f = &self.forest[@as(std.meta.Int(.unsigned, INDEX_BITS), @truncate(o))];
        const size = [2]i32{ f.tex.width, f.tex.height };
        if (drawing == null or drawing.?.joined != f.joined or !std.meta.eql(drawing.?.size, size)) {
            if (drawing != null) endSilhouettes(self);
            if (!beginSilhouettes(self, f.tex, 1, f.joined.uniform(), .{ FOREST_SOFT, FOREST_SOFT })) return;
            drawing = .{ .joined = f.joined, .size = size };
        }
        for (f.cast[0..f.n]) |c| forestQuads(f.tex, f.dest, f.centre, c, light.colourOf(c.shade, @min(FOREST_MAX, c.alpha * FOREST_A)));
    }
    if (drawing != null) endSilhouettes(self);
}

/// `joined` is (w, e, n, s); `softness` is (tip, foot). End with `endSilhouettes`.
fn beginSilhouettes(self: *const light.Light, tex: rl.Texture2D, foot: f32, joined: [4]f32, softness: [2]f32) bool {
    const sh = self.gpu.shadow orelse return false;
    const size = raster.sizeOf(tex);
    rl.beginShaderMode(sh.shader);
    shaders.setUniform(sh.shader, sh.size, size);
    shaders.setUniform(sh.shader, sh.foot, foot);
    shaders.setUniform(sh.shader, sh.joined, joined);
    shaders.setUniform(sh.shader, sh.softness, softness);
    return true;
}

fn endSilhouettes(self: *const light.Light) void {
    rl.gl.rlDrawRenderBatchActive();
    rl.beginShaderMode(self.gpu.shade.?);
}

/// Pixels: `lean` from the feet to the tip; `solid` the share that is silhouette, the rest a streak.
pub const Cast = struct { lean: [2]f32, len: f32, solid: f32, alpha: f32, shade: Rgb, source: ?[2]f32 = null };

const Sides = packed struct(u4) {
    w: bool = false,
    e: bool = false,
    n: bool = false,
    s: bool = false,

    fn of(shape: grid.WallShape) Sides {
        var out: Sides = .{};
        inline for (std.meta.fields(Sides)) |f| @field(out, f.name) = @field(shape, f.name);
        return out;
    }

    fn uniform(self: Sides) [4]f32 {
        var out: [4]f32 = undefined;
        inline for (std.meta.fields(Sides), &out) |f, *o| o.* = light.mask(@field(self, f.name));
        return out;
    }
};
pub const ForestCast = struct { tex: rl.Texture2D, dest: rl.Rectangle, centre: [2]f32, cast: [light.BODY_LIGHTS]Cast, n: usize, joined: Sides };
pub const FOREST_QUEUE: usize = 2048;
/// `flushForest`'s sort key: the queue index below, the texture id over it, the joined sides on top.
const INDEX_BITS = 16;
const JOINED_AT = INDEX_BITS + @bitSizeOf(u32);

comptime {
    for (.{ "w", "e", "n", "s" }, std.meta.fieldNames(Sides)) |want, got| {
        if (!std.mem.eql(u8, want, got)) @compileError("SHADOW_FS reads joined as x w, y e, z n, w s");
    }
    std.debug.assert(FOREST_QUEUE <= 1 << INDEX_BITS);
    std.debug.assert(JOINED_AT + @bitSizeOf(Sides) <= @bitSizeOf(u64));
}

/// `height` is pixels from the feet to the top of the art.
pub fn casts(s: *const light.Shine, centre: [2]f32, height: f32, out: *[light.BODY_LIGHTS]Cast) []const Cast {
    const lit = s.lit();
    if (lit <= 0) return out[0..0];
    var n: usize = 0;
    for (s.lamp[0..s.n]) |l| {
        if (!l.casts) continue;
        const own = lum(l.colour);
        var alpha = if (l.sky) |k| k.depth else light.SHADOW_MAX * light.castShare(own, lit) * smooth(own / SHADOW_LAMP_FULL);
        const dx = centre[0] - l.ground[0];
        const dy = centre[1] - l.ground[1];
        const d = mathx.len(dx, dy);
        if (d < SHADOW_OVERHEAD) continue;
        if (l.sky == null) alpha *= mathx.smoothstep(SHADOW_OVERHEAD, SHADOW_NEAR, d);
        if (alpha < SHADOW_FAINT) continue;
        const lean = if (l.sky) |k| [2]f32{ dx / d * height * k.reach, dy / d * height * k.reach } else lampLean(.{ dx, dy }, height);
        out[n] = .{ .lean = lean, .len = mathx.len(lean[0], lean[1]), .solid = solidity(lean), .alpha = alpha, .shade = if (l.sky) |k| k.shade else light.SHADE_RGB, .source = if (l.sky == null) l.ground else null };
        n += 1;
    }
    return out[0..n];
}

pub fn lampRise(dy_d: f32) f32 {
    return dy_d * SHADOW_SQUASH;
}

fn lampLean(delta: [2]f32, height: f32) [2]f32 {
    const d = mathx.len(delta[0], delta[1]);
    if (d < SHADOW_OVERHEAD) return .{ 0, 0 };
    const len = height * std.math.clamp(SHADOW_LEN_LO + SHADOW_LEN_PER_CELL * d, SHADOW_LEN_LO, SHADOW_LEN_HI);
    return .{ delta[0] / d * len, lampRise(delta[1] / d) * len };
}

pub fn forestTip(c: Cast, centre: [2]f32, uv: [2]f32, height: f32) [2]f32 {
    const source = c.source orelse return c.lean;
    return lampLean(.{ centre[0] + uv[0] - 0.5 - source[0], centre[1] + uv[1] - 0.5 - source[1] }, height);
}

fn forestQuads(tex: rl.Texture2D, dest: rl.Rectangle, centre: [2]f32, c: Cast, ink: rl.Color) void {
    const pad = FOREST_PAD / @as(f32, @floatFromInt(tex.width));
    const uvs = [4][2]f32{ .{ -pad, -pad }, .{ -pad, 1 + pad }, .{ 1 + pad, 1 + pad }, .{ 1 + pad, -pad } };
    var leans: [4][2]f32 = undefined;
    for (uvs, &leans) |uv, *l| l.* = forestTip(c, centre, uv, dest.height);
    for (0..FOREST_STEPS + 1) |i| {
        const along = @as(f32, @floatFromInt(i)) / FOREST_STEPS;
        var corners: [4][4]f32 = undefined;
        for (uvs, leans, &corners) |uv, lean, *v| {
            v.* = .{ uv[0], uv[1], dest.x + uv[0] * dest.width + lean[0] * along, dest.y + uv[1] * dest.height + lean[1] * along };
        }
        texQuad(tex, ink, corners);
    }
}

/// Each corner its texture's u, v, then the screen's x, y.
fn texQuad(tex: rl.Texture2D, ink: rl.Color, corners: [4][4]f32) void {
    rl.gl.rlSetTexture(tex.id);
    rl.gl.rlBegin(rl.gl.rl_quads);
    rl.gl.rlColor4ub(ink.r, ink.g, ink.b, ink.a);
    for (corners) |v| {
        rl.gl.rlTexCoord2f(v[0], v[1]);
        rl.gl.rlVertex2f(v[2], v[3]);
    }
    rl.gl.rlEnd();
    rl.gl.rlSetTexture(0);
}

pub fn solidity(lean: [2]f32) f32 {
    const len = mathx.len(lean[0], lean[1]);
    if (len <= 0) return 1;
    return mathx.smoothstep(THIN_LO, THIN_HI, @abs(lean[1]) / len);
}

fn streak(g: rl.Texture2D, fx: f32, fy: f32, width: f32, c: Cast) void {
    const len = c.len / (1 - STREAK_FOOT);
    const ry = width * STREAK_W;
    drawAlong(g, .{ fx, fy }, c.lean, .{ len, ry * 2 }, .{ .x = len * STREAK_FOOT, .y = ry }, light.colourOf(c.shade, c.alpha * STREAK_A * (1 - c.solid)));
}

/// `g` stretched to `size`, its long side turned down `lean`, `origin` of it at `at`.
fn drawAlong(g: rl.Texture2D, at: [2]f32, lean: [2]f32, size: [2]f32, origin: rl.Vector2, c: rl.Color) void {
    const turn = std.math.radiansToDegrees(std.math.atan2(lean[1], lean[0]));
    rl.drawTexturePro(g, raster.whole(g), .{ .x = at[0], .y = at[1], .width = size[0], .height = size[1] }, origin, turn, c);
}

/// `u` 0 to 1 from behind the feet to the tip, the feet at `STREAK_FOOT`; `v` 0 to 1 across.
pub fn streakAlpha(u: f32, v: f32) f32 {
    const along = if (u < STREAK_FOOT) mathx.smoothstep(0, STREAK_FOOT, u) else std.math.pow(f32, 1 - (u - STREAK_FOOT) / (1 - STREAK_FOOT), STREAK_TAIL);
    const off = v * 2 - 1;
    const across = @max(0, 1 - off * off);
    return along * across * across;
}

/// Downward lean reverses the quad's winding; reverse its corners to avoid back-face culling.
fn silhouette(tex: rl.Texture2D, fx: f32, fy: f32, width: f32, foot: f32, left: bool, c: Cast) void {
    const lean = c.lean;
    const pad = SHADOW_PAD / @as(f32, @floatFromInt(tex.width));
    const mirrored = lean[1] > 0;
    const half = width * 0.5 * (1 + pad * 2);
    const stretch = 1 + pad / foot;
    const west: f32 = if (left) 1 + pad else -pad;
    const east: f32 = if (left) -pad else 1 + pad;
    const tip = [2]f32{ fx + lean[0] * stretch, fy + lean[1] * stretch };
    const corners = [4][4]f32{
        .{ west, -pad, tip[0] - half, tip[1] },
        .{ west, foot, fx - half, fy },
        .{ east, foot, fx + half, fy },
        .{ east, -pad, tip[0] + half, tip[1] },
    };
    texQuad(tex, light.colourOf(c.shade, c.alpha), if (mirrored) .{ corners[3], corners[2], corners[1], corners[0] } else corners);
}
