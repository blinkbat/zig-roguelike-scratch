const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const look = @import("look.zig");

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
/// Per second.
const EASE: f32 = 8.0;

pub fn tintOf(volume: u16) f32 {
    if (volume == 0) return 0;
    return @min(TINT_HI, TINT_LO + TINT_PER * @as(f32, @floatFromInt(volume)));
}

const Shade = struct { shader: rl.Shader, time: i32, cells: i32 };

pub const Cloud = struct {
    tint: [grid.CELLS]f32,
    px: [TEXELS]rl.Color,
    stale: bool,
    /// The cells last baked into `px`.
    baked: [2]P,
    /// Seconds, for the drift.
    t: f32,
    /// Seconds until the burst the newest gas came from lands; till then the cloud stays as drawn.
    held: f32,
    tex: ?rl.Texture2D,
    shade: ?Shade,

    pub fn create(alloc: std.mem.Allocator) !*Cloud {
        const c = try alloc.create(Cloud);
        c.tex = null;
        c.shade = null;
        c.baked = @splat(.{ .x = 0, .y = 0 });
        c.clear();
        return c;
    }

    /// The drift restarts too: the shader's hash loses its grain as `t` grows.
    pub fn clear(self: *Cloud) void {
        @memset(&self.tint, 0);
        self.stale = true;
        self.t = 0;
        self.held = 0;
    }

    /// As if long eased: the gas in sight, and nothing remembered.
    pub fn settle(self: *Cloud, lv: *const grid.Level) void {
        for (&self.tint, &lv.lit, &lv.gas) |*t, lit, v| t.* = if (lit) tintOf(v) else 0;
        self.stale = true;
        self.held = 0;
    }

    pub fn hold(self: *Cloud, s: f32) void {
        self.held = @max(self.held, s);
    }

    pub fn step(self: *Cloud, lv: *const grid.Level, dt: f32) void {
        self.t += dt;
        self.held -= dt;
        if (self.held > 0) return;
        self.held = 0;
        const k = mathx.easing(dt, EASE);
        for (&self.tint, &lv.lit, &lv.gas) |*t, lit, v| {
            const want = tintOf(v);
            if (!lit or t.* == want) continue;
            t.* = mathx.ease(t.*, want, k, k);
            self.stale = true;
        }
    }

    /// Needs a live GL context.
    pub fn load(self: *Cloud) void {
        self.tex = look.canvas(TEX_W, TEX_H, rl.Color.blank);
        const s = look.shader(CLOUD_FS) orelse return;
        self.shade = look.uniforms(Shade, s);
    }

    pub fn unload(self: *Cloud) void {
        if (self.tex) |t| rl.unloadTexture(t);
        if (self.shade) |s| rl.unloadShader(s.shader);
        self.tex = null;
        self.shade = null;
    }

    /// Cells `lo` up to `hi` are on screen; `ox, oy` is where the floor's top-left corner lands.
    pub fn draw(self: *Cloud, lv: *const grid.Level, lo: P, hi: P, ox: i32, oy: i32, cell: i32) void {
        const tex = self.tex orelse return;
        if (std.mem.allEqual(f32, &self.tint, 0)) return;
        const view = grid.grown(lo, hi, 1);
        if (self.stale or !view[0].eq(self.baked[0]) or !view[1].eq(self.baked[1])) {
            self.bake(lv, view);
            rl.updateTexture(tex, &self.px);
            self.stale = false;
        }
        const s = self.shade orelse return look.overFloor(tex, ox, oy, cell);
        const cells = [2]f32{ @floatFromInt(grid.W), @floatFromInt(grid.H) };
        rl.beginShaderMode(s.shader);
        defer rl.endShaderMode();
        rl.setShaderValue(s.shader, s.time, &self.t, .float);
        rl.setShaderValue(s.shader, s.cells, &cells, .vec2);
        look.overFloor(tex, ox, oy, cell);
        rl.gl.rlDrawRenderBatchActive();
    }

    fn bake(self: *Cloud, lv: *const grid.Level, view: [2]P) void {
        var ty = view[0].y * SUB;
        while (ty < view[1].y * SUB) : (ty += 1) {
            var tx = view[0].x * SUB;
            while (tx < view[1].x * SUB) : (tx += 1) self.px[@intCast(ty * TEX_W + tx)] = look.fade(look.GAS, self.texel(lv, tx, ty));
        }
        self.baked = view;
    }

    /// A wall's texels take the tint of the open cell each faces, so gas meets a wall whole and none shows past it.
    fn texel(self: *const Cloud, lv: *const grid.Level, tx: i32, ty: i32) f32 {
        const c = P{ .x = @divFloor(tx, SUB), .y = @divFloor(ty, SUB) };
        if (lv.walkable(c)) return self.openAt(lv, c);
        const sx: i32 = if (@mod(tx, SUB) * 2 < SUB) -1 else 1;
        const sy: i32 = if (@mod(ty, SUB) * 2 < SUB) -1 else 1;
        return @max(self.openAt(lv, c.add(.{ .x = sx, .y = 0 })), self.openAt(lv, c.add(.{ .x = 0, .y = sy })));
    }

    fn openAt(self: *const Cloud, lv: *const grid.Level, p: P) f32 {
        if (!lv.walkable(p)) return 0;
        return grid.cellOr(f32, &self.tint, p, 0);
    }
};

/// Cells the noise pushes a pixel's lookup, and the fray's reach.
const WARP: f32 = 0.12;
const SOFT: f32 = 0.12;

comptime {
    // Past a quarter cell a pixel beside a wall reads the gas of the room behind the wall.
    std.debug.assert(WARP + SOFT < 0.25);
}

const OCTAVES: u32 = 3;
/// The most `fbm`'s octaves, each half the last, sum to.
const FBM_MAX: f32 = 1 - std.math.pow(f32, 0.5, OCTAVES);
/// The softened density's share from its own texel; the four `SOFT` round it split the rest.
const CENTRE_W: f32 = 0.4;
const SIDE_W: f32 = (1 - CENTRE_W) / 4;

const CLOUD_FS = look.FS_HEAD ++ std.fmt.comptimePrint(
    "const float TINT_HI = {d:.4};\nconst float WARP = {d:.4};\nconst float SOFT = {d:.4};\n" ++
        "const int OCTAVES = {d};\nconst float FBM_MAX = {d:.4};\nconst float CENTRE_W = {d:.4};\nconst float SIDE_W = {d:.4};\n",
    .{ TINT_HI, WARP, SOFT, OCTAVES, FBM_MAX, CENTRE_W, SIDE_W },
) ++
    \\uniform float time;
    \\uniform vec2 cells;
    \\const vec2 DRIFT = vec2(0.21, 0.13);
    \\float hash(vec2 p) {
    \\    p = fract(p * vec2(123.34, 456.21));
    \\    p += dot(p, p + 45.32);
    \\    return fract(p.x * p.y);
    \\}
    \\float noise(vec2 p) {
    \\    vec2 i = floor(p);
    \\    vec2 f = fract(p);
    \\    vec2 u = f * f * (3.0 - 2.0 * f);
    \\    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
    \\}
    \\float fbm(vec2 p) {
    \\    float v = 0.0;
    \\    float a = 0.5;
    \\    for (int i = 0; i < OCTAVES; i++) {
    \\        v += a * noise(p);
    \\        p = p * 2.07 + vec2(5.2, 1.3);
    \\        a *= 0.5;
    \\    }
    \\    return v / FBM_MAX;
    \\}
    \\float density(vec2 c) {
    \\    return texture(texture0, c / cells).a;
    \\}
    \\void main() {
    \\    vec2 c = fragTexCoord * cells;
    \\    vec2 drift = DRIFT * time;
    \\    vec2 w = vec2(fbm(c * 0.7 + drift), fbm(c * 0.7 - drift.yx + 4.0)) - 0.5;
    \\    vec2 q = c + w * WARP * 2.0;
    \\    float d = density(q) * CENTRE_W
    \\        + (density(q + vec2(SOFT, 0.0)) + density(q - vec2(SOFT, 0.0))
    \\        + density(q + vec2(0.0, SOFT)) + density(q - vec2(0.0, SOFT))) * SIDE_W;
    \\    if (d < CLEAR_A) discard;
    \\    float n = fbm(c * 1.3 + w * 1.5 - drift * 0.6);
    \\    vec3 col = texture(texture0, q / cells).rgb * mix(0.75, 1.2, n);
    \\    finalColor = vec4(col, clamp(d * mix(0.5, 1.1, n), 0.0, TINT_HI)) * fragColor;
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
    lv.gas[i] = 40;
    lv.lit[i] = true;
    const dt: f32 = 1.0 / 240.0;
    var t: f32 = 0;
    while (c.tint[i] < tintOf(40) * 0.95) : (t += dt) c.step(&lv, dt);
    for (0..240) |_| c.step(&lv, dt);
    std.debug.print("gas cloud: 95% of the way to its tint in {d:.0} ms\n", .{t * 1000});
    try std.testing.expect(t > 0.2 and t < 0.6);
    try std.testing.expectEqual(tintOf(40), c.tint[i]);
    lv.lit[i] = false;
    lv.gas[i] = 0;
    for (0..240) |_| c.step(&lv, dt);
    try std.testing.expectEqual(tintOf(40), c.tint[i]);
    lv.lit[i] = true;
    for (0..480) |_| c.step(&lv, dt);
    try std.testing.expectEqual(@as(f32, 0), c.tint[i]);
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
            c.tint[grid.Level.idx(.{ .x = x, .y = y })] = 0.8;
        }
        lv.set(.{ .x = 11, .y = y }, .floor);
    }
    const wall_x = 10 * SUB;
    try std.testing.expectEqual(@as(f32, 0.8), c.texel(&lv, wall_x, 7 * SUB));
    try std.testing.expectEqual(@as(f32, 0), c.texel(&lv, wall_x + SUB - 1, 7 * SUB));
    try std.testing.expectEqual(@as(f32, 0), c.texel(&lv, 11 * SUB, 7 * SUB));
    try std.testing.expectEqual(@as(f32, 0.8), c.texel(&lv, 7 * SUB, 4 * SUB + SUB - 1));
    try std.testing.expectEqual(@as(f32, 0), c.texel(&lv, 7 * SUB, 4 * SUB));
}
