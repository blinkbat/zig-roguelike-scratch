const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const raster = @import("raster.zig");
const shaders = @import("shaders.zig");
const sky = @import("sky.zig");

// After Brogue's `getCellAppearance`.

const P = mathx.P;

/// Texels per cell side: a cell is flat, and the step to the next blends over half a cell.
const SUB: i32 = 2;
const TEX_W: i32 = grid.W * SUB;
const TEX_H: i32 = grid.H * SUB;
const TEXELS: usize = @intCast(TEX_W * TEX_H);
const TINT_LO: f32 = 0.30;
const TINT_PER: f32 = 0.01;
const TINT_HI: f32 = 0.90;
const FIGURE_SHARE: f32 = 0.5;
/// Per second.
const EASE: f32 = 8.0;

fn tintOf(volume: u16) f32 {
    if (volume == 0) return 0;
    return @min(TINT_HI, TINT_LO + TINT_PER * @as(f32, @floatFromInt(volume)));
}

const Shade = struct { shader: rl.Shader, time: i32 };
const Veil = struct { shader: rl.Shader, time: i32, cloud: i32, origin: i32, cell: i32, screen: i32, lit: i32, texel: i32, strength: i32, body: i32, hidden: i32 };

pub const Cloud = struct {
    tint: std.EnumArray(grid.Gas, [grid.CELLS]f32),
    /// Each texel's gases mixed, its colour premultiplied by its alpha.
    px: [TEXELS]rl.Color,
    stale: bool = true,
    baked: grid.Box = .{ .lo = .{ .x = 0, .y = 0 }, .hi = .{ .x = 0, .y = 0 } },
    /// Seconds, for the drift.
    t: mathx.Seconds = .{},
    /// Seconds until the burst the newest gas came from lands; till then the cloud stays as drawn.
    held: f32 = 0,
    tex: ?rl.Texture2D = null,
    shade: ?Shade = null,
    veil: ?Veil = null,
    map_view: shaders.MapView,
    visible: bool = false,

    pub fn create(alloc: std.mem.Allocator) !*Cloud {
        const c = try alloc.create(Cloud);
        mathx.defaults(c);
        @memset(&c.px, rl.Color.blank);
        c.clear();
        return c;
    }

    /// The drift restarts too, as it does whenever no gas is drawn: the shader's hash loses its grain as `t` grows.
    pub fn clear(self: *Cloud) void {
        for (&self.tint.values) |*tint| @memset(tint, 0);
        self.stale = true;
        self.t = .{};
        self.held = 0;
        self.visible = false;
    }

    /// As if long eased: the gas in sight, and nothing remembered.
    pub fn settle(self: *Cloud, lv: *const grid.Level) void {
        for (std.enums.values(grid.Gas)) |kind| {
            for (self.tint.getPtr(kind), &lv.lit, lv.volumes(kind)) |*t, lit, v| t.* = if (lit) tintOf(v) else 0;
        }
        self.stale = true;
        self.held = 0;
    }

    pub fn hold(self: *Cloud, s: f32) void {
        self.held = @max(self.held, s);
    }

    pub fn step(self: *Cloud, lv: *const grid.Level, dt: f32) void {
        self.t.step(dt);
        self.held -= dt;
        if (self.held > 0) return;
        self.held = 0;
        const k = mathx.easing(dt, EASE);
        for (&lv.lit, 0..) |lit, i| {
            if (!lit) continue;
            inline for (comptime std.enums.values(grid.Gas)) |kind| {
                const t = &self.tint.getPtr(kind)[i];
                const want = tintOf(lv.volumes(kind)[i]);
                if (t.* != want) {
                    t.* = mathx.ease(t.*, want, k, k);
                    self.stale = true;
                }
            }
        }
    }

    /// Needs a live GL context.
    pub fn load(self: *Cloud) void {
        self.tex = raster.canvas(TEX_W, TEX_H, rl.Color.blank, .bilinear);
        self.shade = shaders.program(Shade, CLOUD_FS);
        self.veil = shaders.program(Veil, VEIL_FS);
    }

    pub fn unload(self: *Cloud) void {
        look.unloadAll(self);
    }

    /// `ox, oy` is where the floor's top-left corner lands.
    pub fn draw(self: *Cloud, lv: *const grid.Level, on_screen: grid.Box, ox: i32, oy: i32, cell: i32, screen: mathx.P) void {
        self.visible = false;
        const tex = self.tex orelse return;
        if (!self.tinted(grid.Box.inMap(0))) {
            self.t = .{};
            return;
        }
        const view = on_screen.grown(1);
        if (!self.tinted(view.grown(1))) return;
        self.visible = true;
        self.map_view = .of(ox, oy, cell, screen.x, screen.y);
        if (self.stale or !std.meta.eql(view, self.baked)) {
            self.bake(lv, view);
            rl.updateTexture(tex, &self.px);
            self.stale = false;
        }
        const s = self.shade orelse return raster.overFloor(tex, ox, oy, cell);
        rl.beginShaderMode(s.shader);
        defer rl.endShaderMode();
        shaders.setUniform(s.shader, s.time, self.t.at());
        raster.overFloor(tex, ox, oy, cell);
        rl.gl.rlDrawRenderBatchActive();
    }

    /// `lit` is the light on what it veils.
    pub fn beginVeil(self: *const Cloud, lit: rl.Color, focus: look.Focused) bool {
        return self.beginOccludedVeil(lit, focus, .{});
    }

    pub fn beginOccludedVeil(self: *const Cloud, lit: rl.Color, focus: look.Focused, occlusion: look.Occlusion) bool {
        if (!self.visible) return false;
        const tex = self.tex orelse return false;
        const s = self.veil orelse return false;
        rl.beginShaderMode(s.shader);
        focus.set(s.shader, s.texel, s.strength);
        occlusion.set(s.shader, s.body, s.hidden);
        shaders.setUniform(s.shader, s.time, self.t.at());
        shaders.setMapView(s, self.map_view);
        const rgb: [3]f32 = look.rgbOf(lit);
        shaders.setUniform(s.shader, s.lit, rgb);
        rl.setShaderValueTexture(s.shader, s.cloud, tex);
        return true;
    }

    /// Once what `beginVeil` veils is drawn again: flushed while the veil is still bound.
    pub fn endVeil() void {
        rl.gl.rlDrawRenderBatchActive();
        rl.endShaderMode();
    }

    /// Whether a veil over the cells of `box` could show any gas.
    pub fn veils(self: *const Cloud, box: grid.Box) bool {
        return self.visible and self.tinted(box.grown(1));
    }

    /// Whether any gas is drawn over `box`, which must cover every cell a baked texel reads.
    fn tinted(self: *const Cloud, box: grid.Box) bool {
        const lo: usize = @intCast(@max(0, box.lo.x));
        const hi: usize = @intCast(@min(grid.W, box.hi.x));
        if (hi <= lo) return false;
        var y = @max(0, box.lo.y);
        while (y < @min(grid.H, box.hi.y)) : (y += 1) {
            const row: usize = @intCast(y * grid.W);
            for (&self.tint.values) |*tint| {
                if (!std.mem.allEqual(f32, tint[row + lo .. row + hi], 0)) return true;
            }
        }
        return false;
    }

    fn bake(self: *Cloud, lv: *const grid.Level, view: grid.Box) void {
        var ty = view.lo.y * SUB;
        while (ty < view.hi.y * SUB) : (ty += 1) {
            var tx = view.lo.x * SUB;
            while (tx < view.hi.x * SUB) : (tx += 1) self.px[@intCast(ty * TEX_W + tx)] = self.mixed(lv, tx, ty);
        }
        self.baked = view;
    }

    /// Premultiplied, so filtering mixes each gas's colour by its share, and none from where there is no gas.
    fn mixed(self: *const Cloud, lv: *const grid.Level, tx: i32, ty: i32) rl.Color {
        var rgb: sky.Rgb = @splat(0);
        var sum: f32 = 0;
        for (std.enums.values(grid.Gas)) |kind| {
            const t = texel(self.tint.getPtrConst(kind), lv, tx, ty);
            rgb += look.rgbOf(look.gasInk(kind)) * sky.splat(t);
            sum += t;
        }
        if (sum == 0) return rl.Color.blank;
        const a = @min(TINT_HI, sum);
        return look.colourOf(rgb * sky.splat(a / sum), a);
    }
};

/// A wall's texels take the tint of the open cell each faces, so gas meets a wall whole and none shows past it.
fn texel(tint: *const [grid.CELLS]f32, lv: *const grid.Level, tx: i32, ty: i32) f32 {
    const c = P{ .x = @divFloor(tx, SUB), .y = @divFloor(ty, SUB) };
    if (lv.flat(c)) return openAt(tint, lv, c);
    const sx: i32 = if (@mod(tx, SUB) * 2 < SUB) -1 else 1;
    const sy: i32 = if (@mod(ty, SUB) * 2 < SUB) -1 else 1;
    return @max(openAt(tint, lv, c.add(.{ .x = sx, .y = 0 })), openAt(tint, lv, c.add(.{ .x = 0, .y = sy })));
}

fn openAt(tint: *const [grid.CELLS]f32, lv: *const grid.Level, p: P) f32 {
    if (!lv.flat(p)) return 0;
    return grid.cellOr(f32, tint, p, 0);
}

/// Cells the noise pushes a pixel's lookup, and the fray's reach.
const WARP: f32 = 0.12;
const SOFT: f32 = 0.12;

comptime {
    // Past a quarter cell a pixel beside a wall reads the gas of the room behind the wall.
    std.debug.assert(WARP + SOFT < 0.5 / @as(f32, SUB));
}
const OCTAVES: u32 = 3;
/// Each of `fbm`'s octaves weighs this much of the last, the first this much of one.
const FBM_GAIN: f32 = 0.5;
const FBM_MAX: f32 = FBM_GAIN * (1 - mathx.powi(FBM_GAIN, OCTAVES)) / (1 - FBM_GAIN);

const DRIFT = [2]f32{ 0.21, 0.13 };

/// The softened density weighs its own texel and the four `SOFT` round it with `look.FOCUS_WEIGHTS`, which must precede it.
const CLOUD_NOISE = shaders.glslConsts(.{
    .TINT_HI = TINT_HI,
    .WARP = WARP,
    .SOFT = SOFT,
    .OCTAVES = OCTAVES,
    .FBM_GAIN = FBM_GAIN,
    .FBM_MAX = FBM_MAX,
    .DRIFT = DRIFT,
}) ++
    \\uniform float time;
    \\float hash(vec2 p) {
    \\    p = fract(p * vec2(123.34, 456.21));
    \\    p += dot(p, p + 45.32);
    \\    return fract(p.x * p.y);
    \\}
    \\
++ shaders.VALUE_NOISE_FS ++
    \\float fbm(vec2 p) {
    \\    float v = 0.0;
    \\    float a = FBM_GAIN;
    \\    for (int i = 0; i < OCTAVES; i++) {
    \\        v += a * noise(p);
    \\        p = p * 2.07 + vec2(5.2, 1.3);
    \\        a *= FBM_GAIN;
    \\    }
    \\    return v / FBM_MAX;
    \\}
    \\vec4 cloudTap(sampler2D field, vec2 c) {
    \\    return texture(field, c / CELLS);
    \\}
    \\vec4 cloudAt(sampler2D field, vec2 c) {
    \\    vec2 drift = DRIFT * time;
    \\    vec2 w = vec2(fbm(c * 0.7 + drift), fbm(c * 0.7 - drift.yx + 4.0)) - 0.5;
    \\    vec2 q = c + w * WARP * 2.0;
    \\    vec4 s = cloudTap(field, q) * FOCUS_CENTRE_W
    \\        + (cloudTap(field, q + vec2(SOFT, 0.0)) + cloudTap(field, q - vec2(SOFT, 0.0))
    \\        + cloudTap(field, q + vec2(0.0, SOFT)) + cloudTap(field, q - vec2(0.0, SOFT))) * FOCUS_SIDE_W;
    \\    if (s.a < CLEAR_A) discard;
    \\    float n = fbm(c * 1.3 + w * 1.5 - drift * 0.6);
    \\    return vec4(s.rgb / s.a * mix(0.75, 1.2, n), clamp(s.a * mix(0.5, 1.1, n), 0.0, TINT_HI));
    \\}
;

const CLOUD_FS = shaders.FS_HEAD ++ look.FOCUS_WEIGHTS ++ CLOUD_NOISE ++
    \\void main() {
    \\    finalColor = cloudAt(texture0, fragTexCoord * CELLS) * fragColor;
    \\}
;

const VEIL_FS = shaders.FS_HEAD ++ look.FOCUS_TAPS ++ shaders.MAP_VIEW_FS ++ look.OCCLUSION_FS ++ CLOUD_NOISE ++ shaders.glslConsts(.{ .FIGURE_SHARE = FIGURE_SHARE }) ++
    \\uniform sampler2D cloud;
    \\uniform vec3 lit;
    \\void main() {
    \\    float a = focused().a * fragColor.a * occlusionAt(cellAtFrag());
    \\    if (a < CLEAR_A) discard;
    \\    vec4 gas = cloudAt(cloud, cellAtFrag());
    \\    finalColor = vec4(gas.rgb * lit, gas.a * a * FIGURE_SHARE);
    \\}
;

test "Brogue's tint: 30% at the thinnest, a point a unit, 90% at most" {
    try std.testing.expectEqual(@as(f32, 0), tintOf(0));
    try std.testing.expectApproxEqAbs(@as(f32, 0.31), tintOf(1), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.70), tintOf(40), 1e-6);
    try std.testing.expectEqual(TINT_HI, tintOf(60));
    try std.testing.expectEqual(TINT_HI, tintOf(2000));
}

test "the drawn cloud eases to the gas in sight, and out of sight keeps what was last seen" {
    const alloc = std.testing.allocator;
    const c = try Cloud.create(alloc);
    defer alloc.destroy(c);
    var lv = grid.openFloor();
    const i = grid.Level.idx(.{ .x = 10, .y = 10 });
    const shown = c.tint.getPtrConst(.caustic);
    lv.gas[i] = 40;
    lv.lit[i] = true;
    const dt = mathx.TEST_DT;
    var t: f32 = 0;
    while (shown[i] < tintOf(40) * 0.95) : (t += dt) c.step(&lv, dt);
    for (0..240) |_| c.step(&lv, dt);
    std.debug.print("gas cloud: 95% of the way to its tint in {d:.0} ms\n", .{t * 1000});
    try std.testing.expect(t > 0.2 and t < 0.6);
    try std.testing.expectEqual(tintOf(40), shown[i]);
    lv.lit[i] = false;
    lv.gas[i] = 0;
    for (0..240) |_| c.step(&lv, dt);
    try std.testing.expectEqual(tintOf(40), shown[i]);
    lv.lit[i] = true;
    for (0..480) |_| c.step(&lv, dt);
    try std.testing.expectEqual(@as(f32, 0), shown[i]);
}

test "gas remembered off screen leaves the view untinted, gas a wall away from it does not" {
    const alloc = std.testing.allocator;
    const c = try Cloud.create(alloc);
    defer alloc.destroy(c);
    const view = grid.Box.sized(.{ .x = 10, .y = 10 }, 20, 12);
    const reads = view.grown(2);
    c.tint.getPtr(.caustic)[grid.Level.idx(.{ .x = 50, .y = 40 })] = 0.5;
    try std.testing.expect(!c.tinted(reads));
    c.tint.getPtr(.healing)[grid.Level.idx(.{ .x = view.hi.x + 1, .y = view.lo.y })] = 0.5;
    try std.testing.expect(c.tinted(reads));
}

test "a texel mixes the gases by their shares, premultiplied, and holds no colour where there is no gas" {
    const alloc = std.testing.allocator;
    const c = try Cloud.create(alloc);
    defer alloc.destroy(c);
    const lv = grid.openFloor();
    const at = P{ .x = 10, .y = 10 };
    const i = grid.Level.idx(at);
    try std.testing.expectEqual(rl.Color.blank, c.mixed(&lv, at.x * SUB, at.y * SUB));
    c.tint.getPtr(.healing)[i] = 0.5;
    const healing = c.mixed(&lv, at.x * SUB, at.y * SUB);
    try std.testing.expectEqual(@as(u8, 128), healing.a);
    try std.testing.expectEqual(@as(u8, @intFromFloat(@round(@as(f32, look.HEALING_GAS.b) * 0.5))), healing.b);
    c.tint.getPtr(.caustic)[i] = 0.5;
    const both = c.mixed(&lv, at.x * SUB, at.y * SUB);
    std.debug.print("a texel of healing gas {any}, with as much caustic gas {any}\n", .{ healing, both });
    try std.testing.expectEqual(@as(u8, @intFromFloat(@round(TINT_HI * 255))), both.a);
    for ([_]u8{ both.r, both.g, both.b }, [_]u8{ look.GAS.r, look.GAS.g, look.GAS.b }, [_]u8{ look.HEALING_GAS.r, look.HEALING_GAS.g, look.HEALING_GAS.b }) |got, a, b| {
        try std.testing.expectApproxEqAbs((@as(f32, @floatFromInt(a)) + @as(f32, @floatFromInt(b))) / 2, @as(f32, @floatFromInt(got)) / look.alphaOf(both), 1.5);
    }
}

test "a wall's texels carry the gas of the room they face up to it, and none shows in the corridor past it" {
    const alloc = std.testing.allocator;
    const c = try Cloud.create(alloc);
    defer alloc.destroy(c);
    var lv = grid.Level.blank();
    var y: i32 = 5;
    while (y < 10) : (y += 1) {
        var x: i32 = 5;
        while (x < 10) : (x += 1) {
            lv.set(.{ .x = x, .y = y }, .floor);
            c.tint.getPtr(.caustic)[grid.Level.idx(.{ .x = x, .y = y })] = 0.8;
        }
        lv.set(.{ .x = 11, .y = y }, .floor);
    }
    const wall_x = 10 * SUB;
    try std.testing.expectEqual(@as(f32, 0.8), texel(c.tint.getPtrConst(.caustic), &lv, wall_x, 7 * SUB));
    try std.testing.expectEqual(@as(f32, 0), texel(c.tint.getPtrConst(.caustic), &lv, wall_x + SUB - 1, 7 * SUB));
    try std.testing.expectEqual(@as(f32, 0), texel(c.tint.getPtrConst(.caustic), &lv, 11 * SUB, 7 * SUB));
    try std.testing.expectEqual(@as(f32, 0.8), texel(c.tint.getPtrConst(.caustic), &lv, 7 * SUB, 4 * SUB + SUB - 1));
    try std.testing.expectEqual(@as(f32, 0), texel(c.tint.getPtrConst(.caustic), &lv, 7 * SUB, 4 * SUB));
}
