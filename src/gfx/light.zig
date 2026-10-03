const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const fov = @import("../world/fov.zig");
const look = @import("look.zig");
const sky = @import("sky.zig");
const lume = @import("../world/lume.zig");
const actor = @import("../play/actor.zig");

const P = mathx.P;
pub const Rgb = @Vector(3, f32);

/// Light-map texels per cell side.
pub const SUB: i32 = 4;
const MAP_W: i32 = grid.W * SUB;
const MAP_H: i32 = grid.H * SUB;
const TEXELS: usize = @intCast(MAP_W * MAP_H);
/// The map is drawn with (DST_COLOR, SRC_COLOR) blending, so a texel stores half the light and reaches twice the art.
const OVERBRIGHT: f32 = 2.0;

/// Cells.
pub const REACH: i32 = lume.TORCH_REACH;
const REACH2: f32 = @floatFromInt(REACH * REACH);
const SPAN: i32 = grid.Cells.span(REACH);
/// Cells: the inverse square's reference distance.
const FALLOFF_D0: f32 = 2.5;
/// A wall is this tall; its brick face fills the cell below `FACE_FROM`, so the face is drawn foreshortened.
const WALL_H: f32 = 1.0;
const FACE_FROM: f32 = 0.6;
const FACE_H: f32 = 1 - FACE_FROM;
const FLAME_Z: f32 = 0.6;
/// How far the flame stands out from its wall, so the bricks beside it are not lit edge-on.
const STANDOFF: f32 = 0.3;
const FLOOR_WRAP: f32 = 1.0;
const FACE_WRAP: f32 = 0.35;
const FACE_GAIN: f32 = 1.25;
const CEILING_CATCH: f32 = 0.2;
const BODY_Z: f32 = 0.4;

/// The archer's own light; `CARRY_R` is cells.
const CARRY: Rgb = .{ 0.92, 0.88, 0.80 };
/// A cell past what the archer's light lets it see, so its glow fades out on the edge of sight.
const CARRY_R: f32 = @floatFromInt(actor.row(.archer).light + 1);
const CARRY_FADE: f32 = 0.3;
const CARRY_CEILING: f32 = 0.7;
const CARRY_FACE_WRAP: f32 = 0.6;

const AMBIENT: Rgb = .{ 0.10, 0.11, 0.17 };
/// The light remembered terrain is drawn under, after Brogue's memory colour.
const MEMORY = rgbOf(look.rgb(0x33385c));
const FLAME: Rgb = .{ 1.30, 0.80, 0.40 };
/// Per channel, the power the flicker is raised to, so a flame whitens as it flares.
const FLAME_SHIFT: Rgb = .{ 1.0, 1.6, 2.4 };
const FAINT: f32 = 0.002;
/// A body drawn without its shader takes this share of its direct light.
const TINT_DIRECT: f32 = 0.6;
/// Per second.
const REVEAL: f32 = 14.0;
const FORGET: f32 = 5.0;
/// Cells: memory is black on the edge of anything unseen and full this far from it.
const VOID_FADE: f32 = 1.5;
/// The same fade on ground in sight: short of a neighbour's middle, so nothing seen is darkened past the unseen cell's rim.
const SIGHT_FADE: f32 = 0.4;
const VOID_REACH: i32 = @intFromFloat(@ceil(VOID_FADE));
const VOID_SPAN: usize = @intCast(grid.Cells.span(VOID_REACH));
const FLICKER: f32 = 0.14;
const FLICKER_BANDS = [_]struct { hz: f32, weight: f32 }{
    .{ .hz = 1.5, .weight = 0.6 },
    .{ .hz = 5.0, .weight = 0.3 },
    .{ .hz = 11.0, .weight = 0.1 },
};
/// Per channel, light past this bends toward a square root instead of clipping (Brogue's `adjustedLightValue`).
const KNEE: f32 = 1.5;

pub const BODY_LIGHTS: usize = 4;
/// zig-soulslike's hit flash, pale arterial rather than blood red so it reads on a red body.
pub const FLASH_RGB = Rgb{ 0.88, 0.38, 0.30 };
/// Texels toward the viewer, for the side-lighting of a body.
const BODY_LIGHT_Z: f32 = 40.0;
const SHADOW_MAX: f32 = 0.85;
/// A light with this share of all that reaches a body casts its darkest shadow; under it the shadow eases out to none.
const SHADOW_FULL: f32 = 0.5;
/// And a light at least this bright; a torch is, out to about half its reach.
const SHADOW_LAMP_FULL: f32 = 0.25;
const SHADOW_FAINT: f32 = 0.004;
/// Of the body's drawn height.
const SHADOW_LEN_LO: f32 = 0.5;
const SHADOW_LEN_HI: f32 = 1.8;
const SHADOW_LEN_PER_CELL: f32 = 0.2;
const SHADOW_SQUASH: f32 = 0.55;
/// Cells: a light this close to a body's middle stands over it and casts no shadow.
const SHADOW_OVERHEAD: f32 = 0.05;
const SHADOW_RISE_MIN: f32 = 0.3;
/// Texels of blur room round a shadow's silhouette.
const SHADOW_PAD: f32 = 6;
/// Texels between the shadow shader's blur taps, at its tip and at its foot.
const SHADOW_SOFT_TIP: f32 = 4.0;
const SHADOW_SOFT_FOOT: f32 = 1.2;
const SHADOW_TAPS: i32 = 3;
const CONTACT_W: f32 = 0.62;
const CONTACT_H: f32 = 0.2;
const CONTACT_A: f32 = 0.7;
const GLOW_PX: i32 = 64;
const GLOW_CORE: f32 = 0.45;
const GLOW_HALO: f32 = 2.6;
const GLOW_CORE_A: f32 = 0.85;
const GLOW_HALO_A: f32 = 0.2;
const GLOW_TINT: Rgb = .{ 1.0, 0.52, 0.22 };
/// Cells between a sun ray's samples. A shadow goes from none to full over this share of its caster's height under
/// the caster's top, and over `SUN_EDGE` cells in from a round one's edge.
const SUN_STEP: f32 = 0.1;
const SUN_SOFT: f32 = 0.5;
const SUN_EDGE: f32 = 0.2;
/// Of the sky's light, how much a sun shadow takes away at its darkest, and how dark a body's sun shadow is.
const SUN_SHADE: f32 = 0.55;
const SUN_SHADOW_A: f32 = 0.4;
/// A tree's shadow: its canopy's pool, this share of the sprite wide, as deep across as it is long, centred this far
/// along a full-height shadow, stretched this much more for every height its shadow runs, and this dark; its trunk's
/// contact this share of a body's.
const CANOPY_R: f32 = 0.55;
const CANOPY_SQUASH: f32 = 0.7;
const CANOPY_AT: f32 = 0.45;
const CANOPY_STRETCH: f32 = 0.5;
const CANOPY_A: f32 = 1.6;
const TRUNK_OF: f32 = 0.6;
/// Cells to the side the sun lights a body from, as the body shader takes a lamp.
const SUN_LAMP_D: f32 = 3;
/// Under this many cells of shadow a cell of height, the sun stands overhead and a body casts none.
const SUN_OVERHEAD: f32 = 0.05;

/// What stands in the sun's way: cells tall, and how far from its middle a round one reaches; square fills its cell.
const Caster = struct { h: f32, r: ?f32 = null };

const CASTERS = std.EnumArray(grid.Tile, ?Caster).initDefault(@as(?Caster, null), .{
    .wall = .{ .h = WALL_H },
    .rock = .{ .h = WALL_H },
    .fungus = .{ .h = 0.6, .r = 0.35 },
    .grave = .{ .h = 0.5, .r = 0.28 },
    .fence = .{ .h = 0.5 },
    .reeds = .{ .h = 0.5 },
    .crop = .{ .h = 0.4 },
});

comptime {
    for (std.enums.values(grid.Tile)) |t| {
        if (t.solid() and !t.liquid()) std.debug.assert((CASTERS.get(t) != null) != look.stands(t));
    }
}

const CAST_TALLEST: f32 = blk: {
    var most: f32 = 0;
    for (CASTERS.values) |c| most = @max(most, if (c) |k| k.h else 0);
    break :blk most;
};

/// 1 where the light the sky casts reaches a point `z` cells up, eased to 0 under anything between it and the light.
fn sunlit(lv: *const grid.Level, sk: sky.Sky, x: f32, y: f32, z: f32) f32 {
    const flat = sk.flat();
    if (flat < 1e-4) return 1;
    const u = sk.across();
    const ux = u[0];
    const uy = u[1];
    const rise = sk.dir[2] / flat;
    const far = (CAST_TALLEST - z) / rise;
    var lit: f32 = 1;
    var t: f32 = SUN_STEP * 0.5;
    while (t < far) : (t += SUN_STEP) {
        const px = x + ux * t;
        const py = y + uy * t;
        const c = mathx.cellOf(.{ px, py });
        if (!grid.Level.inside(c)) break;
        const k = CASTERS.get(lv.at(c)) orelse continue;
        var over = (k.h - z - t * rise) / (SUN_SOFT * k.h);
        if (k.r) |r| {
            const m = mathx.centre(c);
            const dx = px - m[0];
            const dy = py - m[1];
            over = @min(over, (r - @sqrt(dx * dx + dy * dy)) / SUN_EDGE);
        }
        if (over <= 0) continue;
        lit = @min(lit, 1 - smooth(@min(over, 1)));
        if (lit <= 0) return 0;
    }
    return lit;
}

/// What of the sky's light reaches a point `sunlit` has: shade keeps some of it.
/// Cells across a cloud's shadow, cells a second it drifts, how much of the sky it covers and how soft its edge, and
/// how much of the sun one takes.
const CLOUD_SCALE: f32 = 14;
/// Ground under a low sun keeps this much of a high one's light, so morning and evening stay warm and not dim.
const GROUND_WRAP: f32 = 0.5;
const CLOUD_DRIFT = [2]f32{ 0.35, 0.12 };
const CLOUD_COVER: f32 = 0.52;
const CLOUD_SOFT: f32 = 0.3;
const CLOUD_DEPTH: f32 = 0.18;

/// What of the sun a cloud's shadow drifting over a point at `t` seconds leaves it.
fn clouded(x: f32, y: f32, t: f32) f32 {
    const u = x / CLOUD_SCALE + t * CLOUD_DRIFT[0] / CLOUD_SCALE;
    const v = y / CLOUD_SCALE + t * CLOUD_DRIFT[1] / CLOUD_SCALE;
    const n = value2(u, v) * 0.65 + value2(u * 2.3 + 17, v * 2.3 - 9) * 0.35;
    const edge = 1 - CLOUD_COVER;
    const cover = mathx.smoothstep(edge - CLOUD_SOFT / 2, edge + CLOUD_SOFT / 2, n);
    return 1 - CLOUD_DEPTH * cover;
}

fn value2(u: f32, v: f32) f32 {
    const iu = @floor(u);
    const iv = @floor(v);
    const x: i32 = @intFromFloat(iu);
    const y: i32 = @intFromFloat(iv);
    const a = smooth(u - iu);
    const b = smooth(v - iv);
    const top = mathx.lerpF(hash2(x, y), hash2(x + 1, y), a);
    const bot = mathx.lerpF(hash2(x, y + 1), hash2(x + 1, y + 1), a);
    return mathx.lerpF(top, bot, b);
}

fn hash2(x: i32, y: i32) f32 {
    return hash(x *% 73856093 ^ y *% 19349663, 0xC10D);
}

fn shaded(sun: f32) f32 {
    return 1 - SUN_SHADE * (1 - sun);
}

/// The sky's light as a ray toward it, worked out once for a whole bake rather than a texel at a time.
const SunRay = struct {
    k: sky.Sky,
    flat: f32,
    u: [2]f32,
    /// Cells up per cell along the ground toward the light.
    rise: f32,

    fn of(k: sky.Sky) SunRay {
        const flat = k.flat();
        return .{ .k = k, .flat = flat, .u = k.across(), .rise = k.dir[2] / @max(flat, 1e-4) };
    }
};

/// What of the sky's light reaches a texel: its ray, and the cloud over it.
const Sun = struct { ray: SunRay, cloud: f32 };

/// How square a surface faces the light the sky casts, sunlit or not.
fn sunFacing(sk: sky.Sky, s: Spot) f32 {
    return switch (s.surface) {
        .floor, .ceiling => wrapped(sk.dir[2], GROUND_WRAP),
        .face => wrapped(sk.dir[1], FACE_WRAP) * FACE_GAIN,
    };
}

comptime {
    std.debug.assert(SHADOW_PAD >= SHADOW_SOFT_TIP * 0.5 * @as(f32, @floatFromInt(SHADOW_TAPS)));
}

const Surface = enum { floor, face, ceiling };

/// Under a caster's top, its height; the ground round a round one, none.
fn topOf(t: grid.Tile, cell: P, q: [2]f32) f32 {
    const k = CASTERS.get(t) orelse return 0;
    const r = k.r orelse return k.h;
    const m = mathx.centre(cell);
    const dx = q[0] - m[0];
    const dy = q[1] - m[1];
    return if (dx * dx + dy * dy < r * r) k.h else 0;
}

/// Where a light-map texel sits in the world: the screen shows a wall's face and ceiling lifted off the ground.
const Spot = struct {
    x: f32,
    y: f32,
    z: f32,
    surface: Surface,

    fn of(lv: *const grid.Level, q: [2]f32) Spot {
        const cell = mathx.cellOf(q);
        const t = lv.at(cell);
        if (t != .wall) return .{ .x = q[0], .y = q[1], .z = topOf(t, cell, q), .surface = .floor };
        const fy = q[1] - @floor(q[1]);
        const top: f32 = @floatFromInt(cell.y);
        const faced = if (lv.wallShape(cell)) |s| s.faced() else false;
        if (faced and fy >= FACE_FROM) {
            return .{ .x = q[0], .y = top + 1, .z = (1 - fy) / FACE_H * WALL_H, .surface = .face };
        }
        return .{ .x = q[0], .y = q[1] + FACE_H, .z = WALL_H, .surface = .ceiling };
    }
};

const TorchIx = std.math.IntFittingRange(0, grid.MAX_TORCHES - 1);

const Torch = struct {
    wall: P,
    /// 1 where the flame's light gets to, over the box of cells centred on the floor below the flame.
    reach: [SPAN * SPAN]f32,
    seed: u32,
    colour: Rgb = FLAME,
    glow: f32 = 1,

    fn floor(t: Torch) P {
        return t.wall.add(mathx.Dir.s.delta());
    }

    /// On the ground plane.
    fn flame(t: Torch) [3]f32 {
        return .{ mathx.centre(t.wall)[0], @as(f32, @floatFromInt(t.wall.y)) + 1 + STANDOFF, FLAME_Z };
    }

    /// Where the flame is drawn: up its wall's foreshortened face.
    fn drawn(t: Torch) [2]f32 {
        return .{ mathx.centre(t.wall)[0], @as(f32, @floatFromInt(t.wall.y)) + 1 - FLAME_Z / WALL_H * FACE_H };
    }

    /// The top-left of the box `reach` covers.
    fn corner(t: *const Torch) P {
        return t.floor().sub(.{ .x = REACH, .y = REACH });
    }

    fn texel(t: *const Torch, p: P) usize {
        const o = t.corner();
        return @intCast((p.y - o.y) * SPAN + (p.x - o.x));
    }

    fn reached(t: *const Torch, x: f32, y: f32) f32 {
        const o = t.corner();
        const u = x - @as(f32, @floatFromInt(o.x)) - 0.5;
        const v = y - @as(f32, @floatFromInt(o.y)) - 0.5;
        return bilinear(&t.reach, SPAN, SPAN, u, v, 0);
    }

    /// The flame's offset from a point and how much of it reaches there, fallen off and occluded; null out of reach.
    fn toward(t: *const Torch, x: f32, y: f32, z: f32) ?struct { d: [3]f32, d2: f32, k: f32 } {
        const f = t.flame();
        const d = [3]f32{ f[0] - x, f[1] - y, f[2] - z };
        const d2 = d[0] * d[0] + d[1] * d[1] + d[2] * d[2];
        if (d2 >= REACH2) return null;
        const o = t.reached(x, y);
        if (o <= 0) return null;
        return .{ .d = d, .d2 = d2, .k = falloff(d2) * o };
    }

    fn shine(t: *const Torch, s: Spot) f32 {
        const r = t.toward(s.x, s.y, s.z) orelse return 0;
        const facing = switch (s.surface) {
            .floor => wrapped(r.d[2] / @sqrt(r.d2), FLOOR_WRAP),
            .face => wrapped(r.d[1] / @sqrt(@max(r.d[0] * r.d[0] + r.d[1] * r.d[1], 1e-4)), FACE_WRAP) * FACE_GAIN,
            .ceiling => CEILING_CATCH,
        };
        return r.k * facing;
    }
};

/// Memory's dim out of sight, black where never seen: the ground's and a body's alike.
fn remembered(view: Rgb, sight: f32, memory: f32) Rgb {
    return (MEMORY + (view - MEMORY) * splat(sight)) * splat(memory);
}

/// Windowed inverse square: exactly nothing at `REACH`.
fn falloff(d2: f32) f32 {
    const r = d2 / REACH2;
    const w = std.math.clamp(1 - r * r, 0, 1);
    return w * w / (1 + d2 / (FALLOFF_D0 * FALLOFF_D0));
}

fn carryFade(d: f32) f32 {
    return @max(0, 1 - (1 - CARRY_FADE) * d / CARRY_R);
}

fn wrapped(cos: f32, wrap: f32) f32 {
    return @max(0, (cos + wrap) / (1 + wrap));
}

/// `out` where `(u, v)` falls outside the grid; texel centres sit on whole numbers.
fn bilinear(f: []const f32, w: i32, h: i32, u: f32, v: f32, out: f32) f32 {
    const fx = @floor(u);
    const fy = @floor(v);
    const x0: i32 = @intFromFloat(fx);
    const y0: i32 = @intFromFloat(fy);
    const a = u - fx;
    const b = v - fy;
    const top = mathx.lerpF(texel(f, w, h, x0, y0, out), texel(f, w, h, x0 + 1, y0, out), a);
    const bot = mathx.lerpF(texel(f, w, h, x0, y0 + 1, out), texel(f, w, h, x0 + 1, y0 + 1, out), a);
    return mathx.lerpF(top, bot, b);
}

fn texel(f: []const f32, w: i32, h: i32, x: i32, y: i32, out: f32) f32 {
    if (x < 0 or y < 0 or x >= w or y >= h) return out;
    return f[@intCast(y * w + x)];
}

/// A cell's memory at each point in it, from the cells round it short of wholly remembered.
const Fade = struct {
    flat: ?f32 = null,
    n: usize = 0,
    short: [VOID_SPAN * VOID_SPAN]Short = undefined,

    const Short = struct { x: f32, y: f32, m: f32 };

    fn at(f: *const Fade, x: f32, y: f32, sight: f32) f32 {
        if (f.flat) |v| return v;
        const reach = mathx.lerpF(VOID_FADE, SIGHT_FADE, sight);
        var v: f32 = 1;
        for (f.short[0..f.n]) |c| {
            const dx = @max(0, @max(c.x - x, x - c.x - 1));
            const dy = @max(0, @max(c.y - y, y - c.y - 1));
            if (dx >= reach or dy >= reach) continue;
            v = @min(v, c.m + (1 - c.m) * smooth(@sqrt(dx * dx + dy * dy) / reach));
        }
        return v;
    }
};

fn hash(n: i32, seed: u32) f32 {
    var x: u32 = @bitCast(n);
    x = (x ^ seed) *% 0x9E3779B1;
    x ^= x >> 15;
    x *%= 0x85EBCA77;
    x ^= x >> 13;
    return @as(f32, @floatFromInt(x >> 8)) / @as(f32, 1 << 24);
}

fn noise(t: f32, seed: u32) f32 {
    const i = @floor(t);
    const f = t - i;
    const n: i32 = @intFromFloat(i);
    return mathx.lerpF(hash(n, seed), hash(n +% 1, seed), smooth(f));
}

pub fn flicker(t: f32, seed: u32) f32 {
    var n: f32 = 0;
    for (FLICKER_BANDS, 0..) |b, i| n += b.weight * (noise(t * b.hz, seed ^ (@as(u32, @intCast(i)) *% 0x5BD1E995)) * 2 - 1);
    return 1 + FLICKER * n;
}

fn knee(c: Rgb) Rgb {
    var out = c;
    for (0..3) |i| {
        if (c[i] > KNEE) out[i] = KNEE * @sqrt(c[i] / KNEE);
    }
    return out;
}

const smooth = mathx.smooth;

fn splat(k: f32) Rgb {
    return @splat(k);
}

fn rgbOf(c: rl.Color) Rgb {
    return Rgb{ @floatFromInt(c.r), @floatFromInt(c.g), @floatFromInt(c.b) } / splat(255);
}

fn colourOf(c: Rgb, a: f32) rl.Color {
    const k = @max(splat(0), @min(splat(1), c)) * splat(255) + splat(0.5);
    return .{ .r = @intFromFloat(k[0]), .g = @intFromFloat(k[1]), .b = @intFromFloat(k[2]), .a = @intFromFloat(std.math.clamp(a, 0, 1) * 255 + 0.5) };
}

const DARK = colourOf(@splat(0), 1);

fn texelOf(c: Rgb) rl.Color {
    return colourOf(knee(c) / splat(OVERBRIGHT), 1);
}

fn lum(c: Rgb) f32 {
    return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722;
}

/// One light reaching a body: as drawn on screen, where it stands on the ground, and what reaches the body, cells.
const Lamp = struct {
    drawn: [2]f32,
    ground: [2]f32,
    colour: Rgb,
    /// The carried light casts no body's shadow, as it casts none of its carrier's.
    casts: bool,
    /// The sky's, far off: its shadow runs this many of the body's heights, whatever the distance.
    reach: ?f32 = null,
};

pub const Shine = struct {
    ambient: Rgb = @splat(0),
    n: usize = 0,
    lamp: [BODY_LIGHTS]Lamp = undefined,

    fn add(self: *Shine, l: Lamp) void {
        var i = self.n;
        if (self.n == BODY_LIGHTS) {
            i = 0;
            for (1..BODY_LIGHTS) |k| {
                if (lum(self.lamp[k].colour) < lum(self.lamp[i].colour)) i = k;
            }
            if (lum(l.colour) <= lum(self.lamp[i].colour)) return;
        } else self.n += 1;
        self.lamp[i] = l;
    }

    fn total(self: Shine) Rgb {
        var c: Rgb = @splat(0);
        for (self.lamp[0..self.n]) |l| c += l.colour;
        return c;
    }

    fn lit(self: Shine) f32 {
        return lum(self.ambient + self.total());
    }

    pub fn tint(self: Shine, c: rl.Color) rl.Color {
        return recolour(c, rgbOf(c) * (self.ambient + self.total() * splat(TINT_DIRECT)));
    }

    /// As the body shader would draw `c`, for what is drawn without it.
    pub fn drawn(self: Shine, c: rl.Color, flash: f32) rl.Color {
        return flashed(self.tint(c), flash);
    }
};

fn recolour(c: rl.Color, rgb: Rgb) rl.Color {
    return colourOf(rgb, @as(f32, @floatFromInt(c.a)) / 255);
}

/// `lit` is how far in sight the flame is, `memory` how far remembered, as the ground under a body is.
pub const Flame = struct { at: [2]f32, glow: f32, lit: f32, memory: f32 };

pub const Light = struct {
    sight: [grid.CELLS]f32,
    memory: [grid.CELLS]f32,
    soft_sight: [grid.CELLS]f32,
    seen_sight: [grid.CELLS]f32,
    soft_memory: [grid.CELLS]f32,
    blur: [grid.CELLS]f32,
    clear: [grid.CELLS]bool,
    clear_row: [grid.CELLS]bool,
    torch: [grid.MAX_TORCHES]Torch,
    torch_n: usize,
    /// The archer's centre as drawn, cells.
    carrier: ?[2]f32,
    /// Open to the sky: its light and shadows, and its ambient for the dark's.
    sky: ?sky.Sky,
    /// How many of the cells above and left of each corner cast, so a box of them is counted in four reads.
    casting: [(grid.COLS + 1) * (grid.ROWS + 1)]u16,
    t: f32,
    map: [TEXELS]rl.Color,
    scratch: grid.Level,
    gpu: Gpu,

    /// Set field by field: built as one value, it is a temporary bigger than a thread's stack.
    pub fn create(alloc: std.mem.Allocator) !*Light {
        const l = try alloc.create(Light);
        l.torch_n = 0;
        l.carrier = null;
        l.sky = null;
        @memset(&l.casting, 0);
        l.t = 0;
        l.gpu = .{};
        @memset(&l.sight, 0);
        @memset(&l.memory, 0);
        @memset(&l.map, rl.Color.black);
        l.soften();
        return l;
    }

    pub fn settle(self: *Light, lv: *const grid.Level) void {
        self.scratch = lv.*;
        self.countCasters(lv);
        self.torch_n = 0;
        for (lv.torches(), 0..) |w, i| {
            var t = Torch{ .wall = w, .reach = undefined, .seed = @as(u32, @intCast(i)) *% 0x27D4EB2F +% 0x165667B1 };
            const f = t.floor();
            fov.cast(&self.scratch, f, REACH);
            var box = grid.Cells.around(f, REACH);
            while (box.next()) |p| t.reach[t.texel(p)] = if (self.scratch.isLit(p)) 1 else 0;
            self.torch[self.torch_n] = t;
            self.torch_n += 1;
        }
        for (0..grid.CELLS) |i| {
            self.sight[i] = if (lv.lit[i]) 1 else 0;
            self.memory[i] = if (lv.seen[i]) 1 else 0;
        }
        self.soften();
        self.t = 0;
        self.fan();
    }

    pub fn step(self: *Light, lv: *const grid.Level, dt: f32) void {
        const up = mathx.easing(dt, REVEAL);
        const down = mathx.easing(dt, FORGET);
        var moved = false;
        for (0..grid.CELLS) |i| {
            const s = mathx.ease(self.sight[i], if (lv.lit[i]) 1 else 0, up, down);
            const m = mathx.ease(self.memory[i], if (lv.seen[i]) 1 else 0, up, down);
            moved = moved or s != self.sight[i] or m != self.memory[i];
            self.sight[i] = s;
            self.memory[i] = m;
        }
        if (moved) self.soften();
        self.t += dt;
        self.fan();
    }

    fn fan(self: *Light) void {
        for (self.torch[0..self.torch_n]) |*t| {
            t.glow = flicker(self.t, t.seed);
            var shift: Rgb = undefined;
            for (0..3) |k| shift[k] = std.math.pow(f32, t.glow, FLAME_SHIFT[k]);
            t.colour = FLAME * shift;
        }
    }

    /// Sight blurs over seen ground only, so a cell never seen does not dim the ground in sight round it.
    fn soften(self: *Light) void {
        for (&self.seen_sight, &self.sight, &self.memory) |*w, s, m| w.* = s * m;
        blur121(&self.seen_sight, &self.blur, &self.soft_sight);
        blur121(&self.memory, &self.blur, &self.soft_memory);
        for (&self.soft_sight, &self.soft_memory) |*s, m| s.* = if (m > 0) @min(1, s.* / m) else 0;
        const r: usize = VOID_REACH;
        const w = grid.COLS;
        const h = grid.ROWS;
        for (0..h) |y| {
            for (0..w) |x| {
                var ok = x >= r and x + r < w;
                if (ok) {
                    for (x - r..x + r + 1) |k| ok = ok and self.memory[y * w + k] >= 1;
                }
                self.clear_row[y * w + x] = ok;
            }
        }
        for (0..h) |y| {
            for (0..w) |x| {
                var ok = y >= r and y + r < h;
                if (ok) {
                    for (y - r..y + r + 1) |k| ok = ok and self.clear_row[k * w + x];
                }
                self.clear[y * w + x] = ok;
            }
        }
    }

    /// A point on the screen, cells.
    fn sightAt(self: *const Light, x: f32, y: f32) f32 {
        return bilinear(&self.soft_sight, grid.W, grid.H, x - 0.5, y - 0.5, 0);
    }

    /// By distance, not a blur: a blur is not black on the edge of an unseen cell that seen ground wraps round.
    fn fadeOf(self: *const Light, c: P) Fade {
        const own = self.memoryAt(c);
        if (own <= 0) return .{ .flat = 0 };
        if (own >= 1 and self.whole(c)) return .{ .flat = 1 };
        var f = Fade{};
        var box = grid.Cells.around(c, VOID_REACH);
        while (box.next()) |p| {
            const m = self.memoryAt(p);
            if (m >= 1) continue;
            f.short[f.n] = .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y), .m = m };
            f.n += 1;
        }
        return f;
    }

    fn memoryAt(self: *const Light, p: P) f32 {
        return grid.cellOr(f32, &self.memory, p, 0);
    }

    /// Nothing within reach of `fadeOf`'s fade round cell `p` is short of wholly remembered.
    fn whole(self: *const Light, p: P) bool {
        return grid.cellOr(bool, &self.clear, p, false);
    }

    fn near(self: *const Light, lo: P, hi: P, out: *[grid.MAX_TORCHES]TorchIx) []const TorchIx {
        var n: usize = 0;
        for (self.torch[0..self.torch_n], 0..) |*t, i| {
            const f = t.floor();
            if (f.x + REACH < lo.x or f.x - REACH > hi.x or f.y + REACH < lo.y or f.y - REACH > hi.y) continue;
            out[n] = @intCast(i);
            n += 1;
        }
        return out[0..n];
    }

    /// Cells across the ground from the carried light, and how far of that is southward.
    fn fromCarrier(self: *const Light, x: f32, y: f32) ?struct { flat: f32, dy: f32 } {
        const c = self.carrier orelse return null;
        const dx = c[0] - x;
        const dy = c[1] - y;
        return .{ .flat = @sqrt(dx * dx + dy * dy), .dy = dy };
    }

    fn carried(self: *const Light, s: Spot) f32 {
        const f = self.fromCarrier(s.x, s.y) orelse return 0;
        const facing = switch (s.surface) {
            .floor => 1,
            .face => wrapped(f.dy / @max(f.flat, 1e-2), CARRY_FACE_WRAP),
            .ceiling => CARRY_CEILING,
        };
        return carryFade(f.flat) * facing * self.carryShare();
    }

    fn countCasters(self: *Light, lv: *const grid.Level) void {
        const w = grid.COLS + 1;
        @memset(self.casting[0..w], 0);
        for (0..grid.ROWS) |y| {
            var row: u16 = 0;
            self.casting[(y + 1) * w] = 0;
            for (0..grid.COLS) |x| {
                row += @intFromBool(CASTERS.get(lv.tile[y * grid.COLS + x]) != null);
                self.casting[(y + 1) * w + x + 1] = self.casting[y * w + x + 1] + row;
            }
        }
    }

    /// `sunlit`, but 1 at once where nothing that casts stands anywhere the ray toward the light could cross.
    fn sunAt(self: *const Light, lv: *const grid.Level, ray: SunRay, x: f32, y: f32, z: f32) f32 {
        if (ray.flat < 1e-4) return 1;
        const u = ray.u;
        const far = @max(0, CAST_TALLEST - z) / ray.rise;
        const ex = x + u[0] * far;
        const ey = y + u[1] * far;
        const x0: i32 = @as(i32, @intFromFloat(@floor(@min(x, ex)))) - 1;
        const y0: i32 = @as(i32, @intFromFloat(@floor(@min(y, ey)))) - 1;
        const x1: i32 = @as(i32, @intFromFloat(@floor(@max(x, ex)))) + 2;
        const y1: i32 = @as(i32, @intFromFloat(@floor(@max(y, ey)))) + 2;
        if (self.castersIn(x0, y0, x1, y1) == 0) return 1;
        return sunlit(lv, ray.k, x, y, z);
    }

    /// Of the cells from `x0, y0` up to `x1, y1`, clipped to the map, how many cast.
    fn castersIn(self: *const Light, x0: i32, y0: i32, x1: i32, y1: i32) u16 {
        const w: usize = grid.COLS + 1;
        const a: usize = @intCast(std.math.clamp(x0, 0, grid.W));
        const b: usize = @intCast(std.math.clamp(y0, 0, grid.H));
        const c: usize = @intCast(std.math.clamp(x1, 0, grid.W));
        const d: usize = @intCast(std.math.clamp(y1, 0, grid.H));
        if (c <= a or d <= b) return 0;
        return self.casting[d * w + c] + self.casting[b * w + a] - self.casting[b * w + c] - self.casting[d * w + a];
    }

    fn carryShare(self: *const Light) f32 {
        return if (self.sky) |k| k.carry else 1;
    }

    fn base(self: *const Light) Rgb {
        return if (self.sky) |k| k.ambient else AMBIENT;
    }

    /// `q` is in cells.
    pub fn at(self: *const Light, lv: *const grid.Level, torches: []const TorchIx, q: [2]f32) Rgb {
        const fade = self.fadeOf(mathx.cellOf(q));
        const sun: ?Sun = if (self.sky) |k| .{ .ray = SunRay.of(k), .cloud = clouded(q[0], q[1], self.t) } else null;
        return self.shade(lv, torches, q, &fade, sun);
    }

    fn shade(self: *const Light, lv: *const grid.Level, torches: []const TorchIx, q: [2]f32, fade: *const Fade, sun: ?Sun) Rgb {
        const sight = self.sightAt(q[0], q[1]);
        const memory = fade.at(q[0], q[1], sight);
        if (memory <= FAINT) return @splat(0);
        var view = self.base();
        if (sight > FAINT) {
            const s = Spot.of(lv, q);
            view += CARRY * splat(self.carried(s));
            for (torches) |i| {
                const t = &self.torch[i];
                view += t.colour * splat(t.shine(s));
            }
            if (sun) |n| {
                const facing = sunFacing(n.ray.k, s);
                if (facing > 0) view += n.ray.k.key * splat(facing * shaded(self.sunAt(lv, n.ray, s.x, s.y, s.z)) * n.cloud);
            }
        }
        return remembered(view, sight, memory);
    }

    /// Cells `lo` up to `hi`, and a texel round them for the filter.
    pub fn bake(self: *Light, lv: *const grid.Level, lo: P, hi: P) void {
        var ids: [grid.MAX_TORCHES]TorchIx = undefined;
        const torches = self.near(lo.sub(.{ .x = 1, .y = 1 }), hi.add(.{ .x = 1, .y = 1 }), &ids);
        const t0 = P{ .x = @max(0, lo.x * SUB - 1), .y = @max(0, lo.y * SUB - 1) };
        const t1 = P{ .x = @min(MAP_W, hi.x * SUB + 1), .y = @min(MAP_H, hi.y * SUB + 1) };
        const ray: ?SunRay = if (self.sky) |k| SunRay.of(k) else null;
        var c = P{ .x = 0, .y = @divFloor(t0.y, SUB) };
        while (c.y * SUB < t1.y) : (c.y += 1) {
            c.x = @divFloor(t0.x, SUB);
            while (c.x * SUB < t1.x) : (c.x += 1) self.bakeCell(lv, torches, c, t0, t1, ray);
        }
    }

    /// A cloud's shadow is cells across, so it is read at a cell's corners and eased between them.
    fn bakeCell(self: *Light, lv: *const grid.Level, torches: []const TorchIx, c: P, t0: P, t1: P, ray: ?SunRay) void {
        const fade = self.fadeOf(c);
        const dark = if (fade.flat) |v| v == 0 else false;
        const sub: f32 = @floatFromInt(SUB);
        const cx: f32 = @floatFromInt(c.x);
        const cy: f32 = @floatFromInt(c.y);
        const corners: [4]f32 = if (ray != null and !dark) .{
            clouded(cx, cy, self.t),
            clouded(cx + 1, cy, self.t),
            clouded(cx, cy + 1, self.t),
            clouded(cx + 1, cy + 1, self.t),
        } else @splat(1);
        var ty = @max(t0.y, c.y * SUB);
        while (ty < @min(t1.y, (c.y + 1) * SUB)) : (ty += 1) {
            var tx = @max(t0.x, c.x * SUB);
            while (tx < @min(t1.x, (c.x + 1) * SUB)) : (tx += 1) {
                const q = [2]f32{ (@as(f32, @floatFromInt(tx)) + 0.5) / sub, (@as(f32, @floatFromInt(ty)) + 0.5) / sub };
                const sun: ?Sun = if (ray) |r| .{
                    .ray = r,
                    .cloud = mathx.lerpF(mathx.lerpF(corners[0], corners[1], q[0] - cx), mathx.lerpF(corners[2], corners[3], q[0] - cx), q[1] - cy),
                } else null;
                self.map[@intCast(ty * MAP_W + tx)] = if (dark) DARK else texelOf(self.shade(lv, torches, q, &fade, sun));
            }
        }
    }

    /// How far in sight and how far remembered a point is, cells, as the light map has the ground there.
    fn viewAt(self: *const Light, q: [2]f32) struct { sight: f32, memory: f32 } {
        const sight = self.sightAt(q[0], q[1]);
        return .{ .sight = sight, .memory = self.fadeOf(mathx.cellOf(q)).at(q[0], q[1], sight) };
    }

    /// `centre` is on the ground, cells. The carried light lights its own `carrier` flat. Faded as the ground under it is.
    pub fn onBody(self: *const Light, centre: [2]f32, carrier: bool) Shine {
        const v = self.viewAt(centre);
        var s = Shine{ .ambient = remembered(self.base(), v.sight, v.memory) };
        const lit = v.sight * v.memory;
        if (self.sky) |k| self.sunOnBody(&s, k, centre, lit);
        if (self.fromCarrier(centre[0], centre[1])) |f| {
            const c = self.carrier.?;
            const k = carryFade(f.flat) * lit * self.carryShare();
            if (carrier) {
                s.ambient += CARRY * splat(k);
            } else if (k > FAINT) {
                s.add(.{ .drawn = c, .ground = c, .colour = CARRY * splat(k), .casts = false });
            }
        }
        for (self.torch[0..self.torch_n]) |*t| {
            const r = t.toward(centre[0], centre[1], BODY_Z) orelse continue;
            const k = r.k * lit;
            if (k <= FAINT) continue;
            const fl = t.flame();
            s.add(.{ .drawn = t.drawn(), .ground = .{ fl[0], fl[1] }, .colour = t.colour * splat(k), .casts = true });
        }
        return s;
    }

    /// The light the sky casts, from off to the body's side, throwing its shadow away as long as the hour has it.
    fn sunOnBody(self: *const Light, s: *Shine, k: sky.Sky, centre: [2]f32, lit: f32) void {
        const toward = k.across();
        const on = lit * shaded(self.sunAt(&self.scratch, SunRay.of(k), centre[0], centre[1], BODY_Z)) * clouded(centre[0], centre[1], self.t);
        if (lum(k.key) * on <= FAINT) return;
        s.add(.{
            .drawn = .{ centre[0] + toward[0] * SUN_LAMP_D, centre[1] + toward[1] * SUN_LAMP_D },
            .ground = .{ centre[0] + toward[0], centre[1] + toward[1] },
            .colour = k.key * splat(on),
            .casts = k.reach() > SUN_OVERHEAD,
            .reach = k.reach(),
        });
    }

    /// A flame hangs on its wall's south face, so a wall seen only from behind shows none.
    pub fn flames(self: *const Light, lv: *const grid.Level, out: *[grid.MAX_TORCHES]Flame) []const Flame {
        var n: usize = 0;
        for (self.torch[0..self.torch_n]) |*t| {
            if (!lv.isSeen(t.wall) or !lv.isSeen(t.floor())) continue;
            const d = t.drawn();
            const v = self.viewAt(d);
            out[n] = .{ .at = d, .glow = t.glow, .lit = v.sight * v.memory, .memory = v.memory };
            n += 1;
        }
        return out[0..n];
    }

    /// Needs a live GL context.
    pub fn load(self: *Light, figures: *const [look.FIGURES]?rl.Texture2D) void {
        self.gpu = Gpu.load(figures);
    }

    pub fn unload(self: *Light) void {
        self.gpu.unload();
        self.gpu = .{};
    }

    /// `ox, oy` is where the map's top-left corner lands on screen.
    pub fn drawMap(self: *Light, ox: i32, oy: i32, cell: i32) void {
        const tex = self.gpu.map orelse return;
        rl.updateTexture(tex, &self.map);
        rl.gl.rlSetBlendFactors(rl.gl.rl_dst_color, rl.gl.rl_src_color, rl.gl.rl_func_add);
        rl.beginBlendMode(.custom);
        defer rl.endBlendMode();
        look.overFloor(tex, ox, oy, cell);
    }

    /// `centre` is its middle, cells; `flash` is how far toward `FLASH_RGB` it is drawn.
    pub fn drawBody(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: Shine, flash: f32) void {
        const w: f32 = @floatFromInt(tex.width);
        const h: f32 = @floatFromInt(tex.height);
        const src = rl.Rectangle{ .x = 0, .y = 0, .width = if (left) -w else w, .height = h };
        const normals = self.gpu.art(tex).normals;
        const sh = self.gpu.body;
        if (sh == null or normals == null) {
            rl.drawTexturePro(tex, src, dest, .{ .x = 0, .y = 0 }, 0, s.drawn(rl.Color.white, flash));
            return;
        }
        var pos: [BODY_LIGHTS][3]f32 = undefined;
        var col: [BODY_LIGHTS][3]f32 = undefined;
        for (s.lamp[0..s.n], 0..) |l, i| {
            pos[i] = .{ (l.drawn[0] - centre[0]) * w, (l.drawn[1] - centre[1]) * h, BODY_LIGHT_Z };
            col[i] = l.colour;
        }
        const size = [2]f32{ w, h };
        const flip: f32 = if (left) -1 else 1;
        const ambient: [3]f32 = s.ambient;
        const n: i32 = @intCast(s.n);
        const b = sh.?;
        rl.beginShaderMode(b.shader);
        defer rl.endShaderMode();
        rl.setShaderValue(b.shader, b.size, &size, .vec2);
        rl.setShaderValue(b.shader, b.flip, &flip, .float);
        rl.setShaderValue(b.shader, b.ambient, &ambient, .vec3);
        rl.setShaderValue(b.shader, b.count, &n, .int);
        rl.setShaderValue(b.shader, b.flash, &flash, .float);
        rl.setShaderValueTexture(b.shader, b.normals, normals.?);
        if (s.n > 0) {
            rl.setShaderValueV(b.shader, b.lpos, &pos, .vec3, n);
            rl.setShaderValueV(b.shader, b.lcol, &col, .vec3, n);
        }
        rl.drawTexturePro(tex, src, dest, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
        rl.gl.rlDrawRenderBatchActive();
    }

    /// Where a sprite drawn over `dest` stands, and its height to there, with the dark pool its foot leaves `contact`
    /// times a body's; null where nothing lights it.
    fn footOf(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, s: Shine, contact: f32) ?struct { x: f32, y: f32, height: f32 } {
        const lit = s.lit();
        if (lit <= 0) return null;
        const height = self.gpu.art(tex).foot * dest.height / @as(f32, @floatFromInt(tex.height));
        const x = dest.x + dest.width * 0.5;
        const y = dest.y + height;
        if (self.gpu.glow) |g| {
            const a = CONTACT_A * @min(1, lit / lum(CARRY));
            glowAt(g, x, y, dest.width * CONTACT_W * 0.5 * contact, dest.width * CONTACT_H * 0.5 * contact, colourOf(@splat(0), a));
        }
        return .{ .x = x, .y = y, .height = height };
    }

    /// Drawn before the walls, which cover whatever of it reaches them.
    pub fn drawShadows(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: Shine) void {
        const f = self.footOf(tex, dest, s, 1) orelse return;
        const fx = f.x;
        const fy = f.y;
        const sh = self.gpu.shadow orelse return;
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(s, centre, f.height, &buf);
        if (cs.len == 0) return;
        const size = [2]f32{ @floatFromInt(tex.width), @floatFromInt(tex.height) };
        const foot = self.gpu.art(tex).foot / size[1];
        rl.beginShaderMode(sh.shader);
        defer rl.endShaderMode();
        rl.setShaderValue(sh.shader, sh.size, &size, .vec2);
        rl.setShaderValue(sh.shader, sh.foot, &foot, .float);
        for (cs) |c| silhouette(tex, fx, fy, c.lean, dest.width, foot, left, c.alpha);
        rl.gl.rlDrawRenderBatchActive();
    }

    /// A tree's: its canopy's dapple thrown along the ground away from each light, a soft pool over its trunk's foot.
    pub fn drawCanopy(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, centre: [2]f32, s: Shine) void {
        const g = self.gpu.glow orelse return;
        const f = self.footOf(tex, dest, s, TRUNK_OF) orelse return;
        const fx = f.x;
        const fy = f.y;
        const height = f.height;
        var buf: [BODY_LIGHTS]Cast = undefined;
        for (casts(s, centre, height, &buf)) |c| {
            const len = @sqrt(c.lean[0] * c.lean[0] + c.lean[1] * c.lean[1]);
            const r = dest.width * CANOPY_R;
            const rx = r * (1 + len / height * CANOPY_STRETCH);
            const ry = r * CANOPY_SQUASH;
            const pool = rl.Rectangle{ .x = fx + c.lean[0] * CANOPY_AT, .y = fy + c.lean[1] * CANOPY_AT, .width = rx * 2, .height = ry * 2 };
            const turn = std.math.radiansToDegrees(std.math.atan2(c.lean[1], c.lean[0]));
            const src = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(g.width), .height = @floatFromInt(g.height) };
            rl.drawTexturePro(g, src, pool, .{ .x = rx, .y = ry }, turn, colourOf(@splat(0), c.alpha * CANOPY_A));
        }
    }

    pub fn drawGlows(self: *const Light, flames_: []const Flame, ox: f32, oy: f32, cell: f32) void {
        const g = self.gpu.glow orelse return;
        rl.beginBlendMode(.additive);
        defer rl.endBlendMode();
        for (flames_) |f| {
            if (f.lit <= FAINT) continue;
            const x = ox + f.at[0] * cell;
            const y = oy + f.at[1] * cell;
            glowAt(g, x, y, cell * GLOW_HALO, cell * GLOW_HALO, colourOf(GLOW_TINT, GLOW_HALO_A * f.glow * f.lit));
            glowAt(g, x, y, cell * GLOW_CORE, cell * GLOW_CORE, colourOf(GLOW_TINT, GLOW_CORE_A * f.glow * f.lit));
        }
    }
};

/// The body shader's flash, for what is drawn without it.
pub fn flashed(c: rl.Color, k: f32) rl.Color {
    const from = rgbOf(c);
    return recolour(c, from + (FLASH_RGB - from) * splat(k));
}

/// `lean` is pixels from the feet to the tip.
const Cast = struct { lean: [2]f32, alpha: f32 };

/// `height` is pixels from the feet to the top of the art.
fn casts(s: Shine, centre: [2]f32, height: f32, out: *[BODY_LIGHTS]Cast) []const Cast {
    const lit = s.lit();
    if (lit <= 0) return out[0..0];
    var n: usize = 0;
    for (s.lamp[0..s.n]) |l| {
        if (!l.casts) continue;
        const own = lum(l.colour);
        const alpha = SHADOW_MAX * smooth(own / lit / SHADOW_FULL) * smooth(own / SHADOW_LAMP_FULL) * (if (l.reach != null) SUN_SHADOW_A else 1);
        if (alpha < SHADOW_FAINT) continue;
        const dx = centre[0] - l.ground[0];
        const dy = centre[1] - l.ground[1];
        const d = @sqrt(dx * dx + dy * dy);
        if (d < SHADOW_OVERHEAD) continue;
        const len = height * (l.reach orelse std.math.clamp(SHADOW_LEN_LO + SHADOW_LEN_PER_CELL * d, SHADOW_LEN_LO, SHADOW_LEN_HI));
        const down: f32 = if (dy >= 0) 1 else -1;
        // The sky's turns slowly through due east and west: floored, it would flip across the feet in a frame.
        const rise = if (l.reach != null) dy / d * SHADOW_SQUASH else down * @max(@abs(dy / d) * SHADOW_SQUASH, SHADOW_RISE_MIN);
        out[n] = .{ .lean = .{ dx / d * len, rise * len }, .alpha = alpha };
        n += 1;
    }
    return out[0..n];
}

/// Centred on `(x, y)`, reaching `rx` and `ry` out from it.
fn glowAt(g: rl.Texture2D, x: f32, y: f32, rx: f32, ry: f32, c: rl.Color) void {
    look.stretch(g, .{ .x = x - rx, .y = y - ry, .width = rx * 2, .height = ry * 2 }, c);
}

/// `lean` is pixels from the feet to the top of the head. Leaning down the screen mirrors the quad, so its corners go
/// the other way round to keep the winding the rasteriser does not cull.
fn silhouette(tex: rl.Texture2D, fx: f32, fy: f32, lean: [2]f32, width: f32, foot: f32, left: bool, alpha: f32) void {
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
    rl.gl.rlSetTexture(tex.id);
    rl.gl.rlBegin(rl.gl.rl_quads);
    const shade = colourOf(@splat(0), alpha);
    rl.gl.rlColor4ub(shade.r, shade.g, shade.b, shade.a);
    for (0..4) |k| {
        const v = corners[if (mirrored) 3 - k else k];
        rl.gl.rlTexCoord2f(v[0], v[1]);
        rl.gl.rlVertex2f(v[2], v[3]);
    }
    rl.gl.rlEnd();
    rl.gl.rlSetTexture(0);
}

fn blur121(src: *const [grid.CELLS]f32, tmp: *[grid.CELLS]f32, out: *[grid.CELLS]f32) void {
    const w = grid.COLS;
    const h = grid.ROWS;
    for (0..h) |y| {
        for (0..w) |x| {
            const l = src[y * w + (if (x == 0) 0 else x - 1)];
            const r = src[y * w + @min(w - 1, x + 1)];
            tmp[y * w + x] = (l + src[y * w + x] * 2 + r) * 0.25;
        }
    }
    for (0..h) |y| {
        for (0..w) |x| {
            const u = tmp[(if (y == 0) 0 else y - 1) * w + x];
            const d = tmp[@min(h - 1, y + 1) * w + x];
            out[y * w + x] = (u + tmp[y * w + x] * 2 + d) * 0.25;
        }
    }
}

const BODY_FS = look.FS_HEAD ++ std.fmt.comptimePrint(
    "#define LIGHTS {d}\nconst float KNEE = {d:.4};\nconst vec3 FLASH = vec3({d:.4}, {d:.4}, {d:.4});\n",
    .{ BODY_LIGHTS, KNEE, FLASH_RGB[0], FLASH_RGB[1], FLASH_RGB[2] },
) ++
    \\uniform sampler2D normals;
    \\uniform vec2 size;
    \\uniform float flip;
    \\uniform vec3 ambient;
    \\uniform int count;
    \\uniform vec3 lpos[LIGHTS];
    \\uniform vec3 lcol[LIGHTS];
    \\uniform float flash;
    \\const float WRAP = 0.4;
    \\const float RISE = 0.7;
    \\const float RIM = 0.8;
    \\const float RIM_REACH = 2.0;
    \\const float SHEEN = 0.12;
    \\float alphaAt(vec2 px) {
    \\    if (px.x < 0.0 || px.y < 0.0 || px.x >= size.x || px.y >= size.y) return 0.0;
    \\    return texture(texture0, px / size).a;
    \\}
    \\void main() {
    \\    vec2 px = floor(fragTexCoord * size) + 0.5;
    \\    vec4 c = texture(texture0, px / size);
    \\    if (c.a < CLEAR_A) discard;
    \\    vec3 n = texture(normals, px / size).xyz * 2.0 - 1.0;
    \\    n.x *= flip;
    \\    n = normalize(n);
    \\    vec2 p = vec2((px.x - size.x * 0.5) * flip, px.y - size.y * 0.5);
    \\    vec3 light = ambient;
    \\    vec3 sheen = vec3(0.0);
    \\    for (int i = 0; i < LIGHTS; i++) {
    \\        if (i >= count) break;
    \\        vec3 l = lpos[i] - vec3(p, 0.0);
    \\        l.z = max(l.z, length(l.xy) * RISE);
    \\        float diffuse = max((dot(n, normalize(l)) + WRAP) / (1.0 + WRAP), 0.0);
    \\        vec2 toward = normalize(l.xy) * RIM_REACH;
    \\        toward.x *= flip;
    \\        float rim = c.a * (1.0 - alphaAt(px + toward));
    \\        light += lcol[i] * (diffuse + rim * RIM);
    \\        sheen += lcol[i] * rim * SHEEN;
    \\    }
    \\    light = mix(light, KNEE * sqrt(light / KNEE), step(KNEE, light));
    \\    finalColor = vec4(mix(c.rgb * light + sheen, FLASH, flash), c.a) * fragColor;
    \\}
;

const SHADOW_FS = look.FS_HEAD ++ std.fmt.comptimePrint(
    "const float SOFT_TIP = {d:.4};\nconst float SOFT_FOOT = {d:.4};\nconst int TAPS = {d};\n",
    .{ SHADOW_SOFT_TIP, SHADOW_SOFT_FOOT, SHADOW_TAPS },
) ++
    \\uniform vec2 size;
    \\uniform float foot;
    \\float alphaAt(vec2 uv) {
    \\    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > foot) return 0.0;
    \\    return texture(texture0, uv).a;
    \\}
    \\void main() {
    \\    float spread = mix(SOFT_TIP, SOFT_FOOT, clamp(fragTexCoord.y / foot, 0.0, 1.0));
    \\    float a = 0.0;
    \\    for (int i = -TAPS; i <= TAPS; i++) {
    \\        for (int j = -TAPS; j <= TAPS; j++) {
    \\            a += alphaAt(fragTexCoord + vec2(float(i), float(j)) * spread * 0.5 / size);
    \\        }
    \\    }
    \\    float n = float(TAPS * 2 + 1);
    \\    finalColor = vec4(0.0, 0.0, 0.0, a / (n * n) * fragColor.a);
    \\}
;

const BodyShader = struct {
    shader: rl.Shader,
    size: i32,
    flip: i32,
    ambient: i32,
    count: i32,
    lpos: i32,
    lcol: i32,
    normals: i32,
    flash: i32,
};

const ShadowShader = struct {
    shader: rl.Shader,
    size: i32,
    foot: i32,
};

const Art = struct {
    id: u32,
    /// Texel rows from the sprite's top to just under its lowest opaque row.
    foot: f32,
    normals: ?rl.Texture2D,

    /// Footed at its bottom row, with no normals.
    fn bare(t: rl.Texture2D) Art {
        return .{ .id = t.id, .foot = @floatFromInt(t.height), .normals = null };
    }
};

/// Texels in from the silhouette over which a body's edge rounds off, and how steeply.
const BEVEL_PX: i32 = 5;
const BEVEL_DEPTH: f32 = 2.0;
const ART_MAX: i32 = 2 * look.SPRITE_PX;
/// Alpha above which a texel is part of the silhouette.
const SOLID_A: u8 = 25;

const Gpu = struct {
    map: ?rl.Texture2D = null,
    glow: ?rl.Texture2D = null,
    body: ?BodyShader = null,
    shadow: ?ShadowShader = null,
    arts: [look.FIGURES]Art = undefined,
    art_n: usize = 0,

    fn load(figures: *const [look.FIGURES]?rl.Texture2D) Gpu {
        var g = Gpu{};
        g.map = look.canvas(MAP_W, MAP_H, rl.Color.black);
        g.glow = look.radial(GLOW_PX, glowAlpha);
        if (look.shader(BODY_FS)) |s| g.body = look.uniforms(BodyShader, s);
        if (look.shader(SHADOW_FS)) |s| g.shadow = look.uniforms(ShadowShader, s);
        for (figures) |b| {
            const t = b orelse continue;
            g.arts[g.art_n] = artOf(t);
            g.art_n += 1;
        }
        return g;
    }

    fn unload(g: Gpu) void {
        if (g.map) |t| rl.unloadTexture(t);
        if (g.glow) |t| rl.unloadTexture(t);
        if (g.body) |s| rl.unloadShader(s.shader);
        if (g.shadow) |s| rl.unloadShader(s.shader);
        for (g.arts[0..g.art_n]) |a| {
            if (a.normals) |t| rl.unloadTexture(t);
        }
    }

    fn art(g: *const Gpu, t: rl.Texture2D) Art {
        for (g.arts[0..g.art_n]) |a| {
            if (a.id == t.id) return a;
        }
        return Art.bare(t);
    }
};

fn artOf(t: rl.Texture2D) Art {
    var a = Art.bare(t);
    if (t.width > ART_MAX or t.height > ART_MAX) return a;
    const img = rl.loadImageFromTexture(t) catch return a;
    defer rl.unloadImage(img);
    var solid: [ART_MAX * ART_MAX]bool = undefined;
    const w: usize = @intCast(t.width);
    for (0..@intCast(t.height)) |y| {
        for (0..w) |x| solid[y * w + x] = rl.getImageColor(img, @intCast(x), @intCast(y)).a > SOLID_A;
    }
    var y: i32 = t.height - 1;
    while (y >= 0) : (y -= 1) {
        if (rowSolid(&solid, t.width, y)) {
            a.foot = @floatFromInt(y + 1);
            break;
        }
    }
    a.normals = bevelNormals(&solid, t.width, t.height);
    return a;
}

fn rowSolid(solid: *const [ART_MAX * ART_MAX]bool, w: i32, y: i32) bool {
    var x: i32 = 0;
    while (x < w) : (x += 1) {
        if (solid[@intCast(y * w + x)]) return true;
    }
    return false;
}

/// Laigter's soft bevel: distance to the nearest clear texel (outside counts as clear), raised on a quarter circle.
/// `solid` is packed `w` to a row.
fn bevelNormals(solid: *const [ART_MAX * ART_MAX]bool, w: i32, h: i32) ?rl.Texture2D {
    var height: [ART_MAX * ART_MAX]f32 = undefined;
    const reach = BEVEL_PX + 1;
    var y: i32 = 0;
    while (y < h) : (y += 1) {
        var x: i32 = 0;
        while (x < w) : (x += 1) {
            const i: usize = @intCast(y * w + x);
            if (!solid[i]) {
                height[i] = 0;
                continue;
            }
            var near2: i32 = reach * reach;
            var dy: i32 = -reach;
            while (dy <= reach) : (dy += 1) {
                var dx: i32 = -reach;
                while (dx <= reach) : (dx += 1) {
                    const sx = x + dx;
                    const sy = y + dy;
                    const clear = sx < 0 or sy < 0 or sx >= w or sy >= h or !solid[@intCast(sy * w + sx)];
                    if (clear) near2 = @min(near2, dx * dx + dy * dy);
                }
            }
            const t = std.math.clamp((@sqrt(@as(f32, @floatFromInt(near2))) - 0.5) / @as(f32, @floatFromInt(BEVEL_PX)), 0, 1);
            height[i] = @sqrt(1 - (t - 1) * (t - 1));
        }
    }
    var px: [ART_MAX * ART_MAX]rl.Color = undefined;
    y = 0;
    while (y < h) : (y += 1) {
        var x: i32 = 0;
        while (x < w) : (x += 1) {
            const gx = texel(&height, w, h, x + 1, y, 0) - texel(&height, w, h, x - 1, y, 0);
            const gy = texel(&height, w, h, x, y + 1, 0) - texel(&height, w, h, x, y - 1, 0);
            const n = Rgb{ -gx * BEVEL_DEPTH, -gy * BEVEL_DEPTH, 1 };
            const unit = n / splat(@sqrt(@reduce(.Add, n * n)));
            px[@intCast(y * w + x)] = colourOf(unit * splat(0.5) + splat(0.5), 1);
        }
    }
    return look.clamped(look.rgba(&px, w, h), .point);
}

fn glowAlpha(dx: f32, dy: f32) f32 {
    const r2 = @min(1, dx * dx + dy * dy);
    return (1 - r2) * (1 - r2) * @exp(-3 * r2);
}

const gen = @import("../world/gen.zig");

const TORCH_AT = P{ .x = 20, .y = 10 };
/// Cells in from an edge, so a sample on it reads the seen cell and not the unseen one past it.
const EDGE_EPS: f32 = 1e-4;

fn testRoom(lv: *grid.Level, walls: []const P) void {
    lv.* = grid.openFloor();
    var x: i32 = 1;
    while (x < grid.W - 1) : (x += 1) lv.set(.{ .x = x, .y = TORCH_AT.y }, .wall);
    for (walls) |w| lv.set(w, .wall);
    gen.shapeWalls(lv);
    lv.addTorch(TORCH_AT);
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
}

fn testLight(lv: *const grid.Level) !*Light {
    const l = try Light.create(std.testing.allocator);
    l.settle(lv);
    return l;
}

fn added(l: *const Light, lv: *const grid.Level, q: [2]f32) f32 {
    var ids: [grid.MAX_TORCHES]TorchIx = undefined;
    return lum(l.at(lv, l.near(.{ .x = 0, .y = 0 }, .{ .x = grid.W, .y = grid.H }, &ids), q)) - lum(AMBIENT);
}

test "a torch pools light on the floor below it, fading to nothing at its reach" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const fl = l.torch[0].flame();
    std.debug.print("torchlight on the floor by cells from the flame:", .{});
    var last = std.math.floatMax(f32);
    for ([_]f32{ 0.25, 1, 2, 3, 4, 5, 6, 7 }) |r| {
        const v = added(l, &lv, .{ fl[0], fl[1] + r });
        std.debug.print(" {d}:{d:.3}", .{ r, v });
        try std.testing.expect(v <= last);
        last = v;
    }
    std.debug.print("\n", .{});
    try std.testing.expect(added(l, &lv, .{ fl[0], fl[1] + 0.25 }) > 0.6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), last, 1e-5);
}

test "a brick face by its torch catches far more than the ceiling above it, and one turned away catches none" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{.{ .x = 22, .y = 14 }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const own = added(l, &lv, .{ 20.5, 10.875 });
    const ceiling = added(l, &lv, .{ 20.5, 10.25 });
    const along = added(l, &lv, .{ 23.5, 10.875 });
    const along_ceiling = added(l, &lv, .{ 23.5, 10.25 });
    const away = added(l, &lv, .{ 22.5, 14.875 });
    const away_ceiling = added(l, &lv, .{ 22.5, 14.25 });
    std.debug.print("torchlight: its own face {d:.3} and the ceiling above {d:.3}, a face 3 along {d:.3} and its ceiling {d:.3}, a face in reach turned away {d:.3} under a ceiling at {d:.3}\n", .{ own, ceiling, along, along_ceiling, away, away_ceiling });
    try std.testing.expect(own > ceiling * 3);
    try std.testing.expect(own > along);
    try std.testing.expect(along > along_ceiling * 1.5);
    try std.testing.expect(away_ceiling > 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), away, 1e-5);
}

test "a pillar throws the torch's shadow across the floor behind it" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{.{ .x = 20, .y = 13 }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const behind = added(l, &lv, .{ 20.5, 15.5 });
    const beside = added(l, &lv, .{ 22.5, 14.5 });
    std.debug.print("torchlight behind a pillar {d:.3}, beside it {d:.3}\n", .{ behind, beside });
    try std.testing.expectApproxEqAbs(@as(f32, 0), behind, 1e-5);
    try std.testing.expect(beside > 0.05);
}

fn stepUntil(l: *Light, lv: *const grid.Level, q: [2]f32, comptime done: fn (f32) bool) usize {
    var frames: usize = 0;
    var ids: [grid.MAX_TORCHES]TorchIx = undefined;
    const none = ids[0..0];
    while (frames < 600 and !done(lum(l.at(lv, none, q)))) : (frames += 1) l.step(lv, 1.0 / 60.0);
    return frames;
}

test "a cell coming into sight fades up fast, and fades down to memory slower once out of it" {
    var lv = grid.openFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var y: i32 = 10;
    while (y < 21) : (y += 1) {
        var x: i32 = 10;
        while (x < 21) : (x += 1) lv.light(.{ .x = x, .y = y });
    }
    const q = [2]f32{ 15.5, 15.5 };
    l.carrier = q;
    const bright = lum(AMBIENT + CARRY);
    const dim = lum(MEMORY);
    const Up = struct {
        var want: f32 = 0;
        fn f(v: f32) bool {
            return v >= want;
        }
    };
    Up.want = bright * 0.95;
    const up = stepUntil(l, &lv, q, Up.f);
    lv.lightless();
    const Down = struct {
        var want: f32 = 0;
        fn f(v: f32) bool {
            return v <= want;
        }
    };
    Down.want = dim + (bright - dim) * 0.05;
    const down = stepUntil(l, &lv, q, Down.f);
    std.debug.print("fog: 95% of the way into sight in {d} ms, out of it to memory in {d} ms\n", .{ up * 1000 / 60, down * 1000 / 60 });
    try std.testing.expect(up > 0 and up < 20);
    try std.testing.expect(down > up and down < 60);
    for (0..600) |_| l.step(&lv, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(dim, lum(l.at(&lv, &.{}, q)), 0.002);
}

test "the edge of sight ramps across texels instead of stepping at a cell" {
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| {
        lv.seen[i] = true;
        lv.lit[i] = grid.Level.of(i).x < 20;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.bake(&lv, .{ .x = 10, .y = 25 }, .{ .x = 30, .y = 35 });
    const row: i32 = 30 * SUB;
    var biggest: f32 = 0;
    var ramp: usize = 0;
    const from = lum(rgbOf(l.map[@intCast(row * MAP_W + 12 * SUB)]));
    const to = lum(rgbOf(l.map[@intCast(row * MAP_W + 28 * SUB)]));
    var tx: i32 = 12 * SUB;
    while (tx < 28 * SUB) : (tx += 1) {
        const a = lum(rgbOf(l.map[@intCast(row * MAP_W + tx)]));
        const b = lum(rgbOf(l.map[@intCast(row * MAP_W + tx + 1)]));
        biggest = @max(biggest, @abs(b - a));
        if (@abs(b - a) > 0.001) ramp += 1;
    }
    const jump = @abs(to - from);
    std.debug.print("fog edge: {d} texels of ramp, the steepest step {d:.0}% of the jump\n", .{ ramp, biggest / jump * 100 });
    try std.testing.expect(ramp >= SUB * 2);
    try std.testing.expect(biggest < jump * 0.2);
}

test "a baked texel is exactly the light `at` gives its middle, fading or never seen" {
    var lv: grid.Level = undefined;
    const f = gen.build(&lv, 0xBA4E);
    fov.cast(&lv, f.start, actor.row(.archer).sight);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    fov.cast(&lv, f.rooms[1].centre(), actor.row(.archer).sight);
    l.carrier = mathx.centre(f.start);
    for (0..4) |_| l.step(&lv, 1.0 / 60.0);
    l.bake(&lv, .{ .x = 0, .y = 0 }, .{ .x = grid.W, .y = grid.H });
    var ids: [grid.MAX_TORCHES]TorchIx = undefined;
    const torches = l.near(.{ .x = -1, .y = -1 }, .{ .x = grid.W + 1, .y = grid.H + 1 }, &ids);
    const sub: f32 = @floatFromInt(SUB);
    var dark: usize = 0;
    var fading: usize = 0;
    var off: usize = 0;
    for (0..TEXELS) |i| {
        const tx: f32 = @floatFromInt(i % @as(usize, @intCast(MAP_W)));
        const ty: f32 = @floatFromInt(i / @as(usize, @intCast(MAP_W)));
        const q = [2]f32{ (tx + 0.5) / sub, (ty + 0.5) / sub };
        const m = l.memoryAt(mathx.cellOf(q));
        if (m == 0) dark += 1;
        if (m > 0 and m < 1) fading += 1;
        const want = texelOf(l.at(&lv, torches, q));
        if (!std.meta.eql(want, l.map[i])) off += 1;
    }
    std.debug.print("whole floor baked: {d} texels never seen, {d} fading in, {d} off what `at` gives\n", .{ dark, fading, off });
    try std.testing.expect(dark > 0 and fading > 0);
    try std.testing.expectEqual(@as(usize, 0), off);
}

test "remembered ground fades to black exactly at the edge of what was ever seen" {
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| lv.seen[i] = grid.Level.of(i).x < 20;
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const full = lum(l.at(&lv, &.{}, .{ 15.5, 30.5 }));
    const at_edge = lum(l.at(&lv, &.{}, .{ 20.0 - EDGE_EPS, 30.5 }));
    const half_in = lum(l.at(&lv, &.{}, .{ 19.5, 30.5 }));
    const one_in = lum(l.at(&lv, &.{}, .{ 19.0, 30.5 }));
    const two_in = lum(l.at(&lv, &.{}, .{ 18.0, 30.5 }));
    var biggest: f32 = 0;
    var x: f32 = 16;
    while (x < 20) : (x += 1.0 / @as(f32, @floatFromInt(SUB))) {
        biggest = @max(biggest, @abs(lum(l.at(&lv, &.{}, .{ x + 0.25, 30.5 })) - lum(l.at(&lv, &.{}, .{ x, 30.5 }))));
    }
    std.debug.print("memory at the edge of the unseen: {d:.3} on the line, {d:.3} half a cell in, {d:.3} one in, {d:.3} two in, {d:.3} deep; steepest texel step {d:.0}% of full\n", .{ at_edge, half_in, one_in, two_in, full, biggest / full * 100 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), at_edge, 1e-4);
    try std.testing.expect(half_in < one_in and one_in < two_in);
    try std.testing.expect(two_in > full * 0.97);
    try std.testing.expect(biggest < full * 0.3);
}

test "remembered ground is black on every line where a seen cell meets an unseen one" {
    var lv: grid.Level = undefined;
    const l = try Light.create(std.testing.allocator);
    defer std.testing.allocator.destroy(l);
    const sight = actor.row(.archer).sight;
    const full = lum(MEMORY);
    var lines: usize = 0;
    var bright: usize = 0;
    var worst: f32 = 0;
    for (0..10) |n| {
        const f = gen.build(&lv, 0x5EE +% n *% 7919);
        for (f.rooms[0..@min(3, f.room_n)]) |r| fov.cast(&lv, r.centre(), sight);
        lv.lightless();
        l.settle(&lv);
        for (0..grid.CELLS) |i| {
            if (!lv.seen[i]) continue;
            const a = grid.Level.of(i);
            for ([_]mathx.Dir{ .n, .e, .s, .w }) |d| {
                const b = a.add(d.delta());
                if (!grid.Level.inside(b) or lv.isSeen(b)) continue;
                lines += 1;
                const ax: f32 = @floatFromInt(a.x);
                const ay: f32 = @floatFromInt(a.y);
                var most: f32 = 0;
                for ([_]f32{ 0, 0.25, 0.5, 0.75, 1 - EDGE_EPS }) |t| {
                    const q: [2]f32 = switch (d) {
                        .n => .{ ax + t, ay },
                        .s => .{ ax + t, ay + 1 - EDGE_EPS },
                        .w => .{ ax, ay + t },
                        else => .{ ax + 1 - EDGE_EPS, ay + t },
                    };
                    most = @max(most, lum(l.at(&lv, &.{}, q)) / full);
                }
                if (most > 0.05) bright += 1;
                worst = @max(worst, most);
            }
        }
    }
    std.debug.print("{d} lines between seen and unseen over 10 floors, {d} showing memory above 5%, the brightest {d:.0}% of full\n", .{ lines, bright, worst * 100 });
    try std.testing.expect(lines > 500);
    try std.testing.expect(worst < 0.01);
}

test "a doorway sight skips in a hall's side wall leaves no dark patch in the hall" {
    var lv = grid.Level.blank();
    var x: i32 = 5;
    while (x <= 40) : (x += 1) lv.set(.{ .x = x, .y = 20 }, .floor);
    const door = P{ .x = 25, .y = 21 };
    lv.set(door, .floor);
    var y: i32 = 22;
    while (y <= 26) : (y += 1) {
        x = 22;
        while (x <= 28) : (x += 1) lv.set(.{ .x = x, .y = y }, .floor);
    }
    gen.shapeWalls(&lv);
    fov.cast(&lv, .{ .x = 20, .y = 20 }, actor.row(.archer).sight);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.carrier = .{ 20.5, 20.5 };
    try std.testing.expect(!lv.isSeen(door));
    std.debug.print("hall light by cells from the archer, a doorway sight skips at 5:", .{});
    var worst: f32 = 0;
    x = 20;
    while (x < 30) : (x += 1) {
        const d: f32 = @floatFromInt(x - 20);
        const v = lum(l.at(&lv, &.{}, .{ 20.5 + d, 20.5 }));
        std.debug.print(" {d}:{d:.3}", .{ d, v });
        worst = @max(worst, @abs(v - lum(AMBIENT + CARRY * splat(carryFade(d)))));
    }
    std.debug.print("; furthest off the carried light alone {d:.4}\n", .{worst});
    try std.testing.expect(worst < 1e-3);
    try std.testing.expectEqual(@as(f32, 0), lum(l.at(&lv, &.{}, .{ 25.5, 21.5 })));
}

test "a flame flickers within a tenth or so either way and never jumps" {
    var lo: f32 = 2;
    var hi: f32 = 0;
    var jump: f32 = 0;
    var last = flicker(0, 7);
    var i: usize = 1;
    while (i < 60 * 60) : (i += 1) {
        const v = flicker(@as(f32, @floatFromInt(i)) / 60.0, 7);
        lo = @min(lo, v);
        hi = @max(hi, v);
        jump = @max(jump, @abs(v - last));
        last = v;
    }
    std.debug.print("flicker over a minute: {d:.3} to {d:.3}, at most {d:.4} a frame at 60 Hz\n", .{ lo, hi, jump });
    try std.testing.expect(lo >= 1 - FLICKER and hi <= 1 + FLICKER);
    try std.testing.expect(hi - lo > FLICKER);
    try std.testing.expect(jump < 0.03);
}

test "the carried light fades across what it lets the archer see and leaves that edge above memory" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.carrier = .{ 40.5, 30.5 };
    std.debug.print("carried light on the floor by cells out:", .{});
    var last = std.math.floatMax(f32);
    const edge: f32 = @floatFromInt(actor.row(.archer).light);
    for ([_]f32{ 0, edge * 0.4, edge * 0.8, edge }) |d| {
        const v = lum(l.at(&lv, &.{}, .{ 40.5 + d, 30.5 }));
        std.debug.print(" {d}:{d:.3}", .{ d, v });
        try std.testing.expect(v < last);
        last = v;
    }
    std.debug.print(", memory {d:.3}\n", .{lum(MEMORY)});
    try std.testing.expect(last > lum(MEMORY));
}

test "a torch on a wall never seen has no flame to draw, though the floor below it is in sight" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    lv.lightless();
    @memset(&lv.seen, false);
    lv.light(TORCH_AT.add(mathx.Dir.s.delta()));
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var buf: [grid.MAX_TORCHES]Flame = undefined;
    const got = l.flames(&lv, &buf);
    std.debug.print("unseen torch over a floor in sight: {d} flame(s), lit {d:.3}\n", .{ got.len, if (got.len > 0) got[0].lit else 0 });
    try std.testing.expectEqual(@as(usize, 0), got.len);
}

test "a torch seen only from behind its wall has no flame, and a remembered one fades up with its wall" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    lv.lightless();
    @memset(&lv.seen, false);
    for (0..grid.CELLS) |i| {
        if (grid.Level.of(i).y <= TORCH_AT.y) lv.light(grid.Level.of(i));
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var buf: [grid.MAX_TORCHES]Flame = undefined;
    try std.testing.expect(lv.isSeen(TORCH_AT));
    try std.testing.expectEqual(@as(usize, 0), l.flames(&lv, &buf).len);
    @memset(&lv.seen, false);
    lv.lightless();
    l.settle(&lv);
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    l.step(&lv, 1.0 / 60.0);
    const first = l.flames(&lv, &buf)[0].memory;
    for (0..120) |_| l.step(&lv, 1.0 / 60.0);
    const settled = l.flames(&lv, &buf)[0].memory;
    std.debug.print("a torch coming into sight: its remembered flame at {d:.3} the first frame, {d:.3} two seconds on\n", .{ first, settled });
    try std.testing.expect(first < 0.3);
    try std.testing.expectEqual(@as(f32, 1), settled);
}

fn castAlpha(l: *const Light, at: [2]f32, carrier: bool) [2]f32 {
    var buf: [BODY_LIGHTS]Cast = undefined;
    const cs = casts(l.onBody(at, carrier), at, 60, &buf);
    if (cs.len == 0) return .{ 0, 0 };
    return .{ cs[0].alpha, @sqrt(cs[0].lean[0] * cs[0].lean[0] + cs[0].lean[1] * cs[0].lean[1]) };
}

test "a cast shadow fades out smoothly as its body walks away from the torch" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const fl = l.torch[0].flame();
    const Row = struct { name: []const u8, carrier: ?f32, carrying: bool };
    var steepest: f32 = 0;
    var nearest_end: f32 = std.math.floatMax(f32);
    for ([_]Row{ .{ .name = "alone", .carrier = null, .carrying = false }, .{ .name = "archer", .carrier = 0, .carrying = true }, .{ .name = "rat by archer", .carrier = 2, .carrying = false } }) |r| {
        std.debug.print("shadow alpha/px, {s}, by cells from the flame:", .{r.name});
        var last: ?f32 = null;
        var worst: f32 = 0;
        var gone: f32 = 0;
        var d: f32 = 0.5;
        while (d < @as(f32, @floatFromInt(REACH)) + 0.5) : (d += 0.125) {
            const at = [2]f32{ fl[0] + d, fl[1] + 0.5 };
            l.carrier = if (r.carrier) |c| .{ at[0] + c, at[1] } else null;
            const v = castAlpha(l, at, r.carrying);
            if (@mod(d, 1) == 0.5) std.debug.print(" {d:.1}:{d:.2}/{d:.0}", .{ d, v[0], v[1] });
            if (last) |was| worst = @max(worst, was - v[0]);
            if (v[0] > 0) gone = d;
            last = v[0];
        }
        std.debug.print("; biggest drop per 1/8 cell {d:.3}, last cast at {d:.2}\n", .{ worst, gone });
        steepest = @max(steepest, worst);
        nearest_end = @min(nearest_end, gone);
    }
    try std.testing.expect(steepest < 0.07);
    try std.testing.expect(nearest_end >= @as(f32, @floatFromInt(REACH)) - 1.5);
}

test "a body is lit as the ground under it is, fading into sight and on the edge of the unseen" {
    var lv = grid.openFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var y: i32 = 10;
    while (y < 21) : (y += 1) {
        var x: i32 = 10;
        while (x < 21) : (x += 1) lv.light(.{ .x = x, .y = y });
    }
    l.carrier = .{ 15.5, 15.5 };
    var worst: f32 = 0;
    var first: [2]f32 = undefined;
    for (0..30) |frame| {
        l.step(&lv, 1.0 / 60.0);
        for ([_][2]f32{ .{ 15.5, 15.5 }, .{ 18.5, 12.5 }, .{ 20.5, 15.5 }, .{ 20.9, 20.9 } }, 0..) |c, k| {
            const body = l.onBody(c, false);
            const on = lum(body.ambient + body.total());
            const ground = lum(l.at(&lv, &.{}, c));
            if (frame == 0 and k == 0) first = .{ on, ground };
            worst = @max(worst, @abs(on - ground));
        }
    }
    std.debug.print("a body and its ground fading into sight: {d:.3} and {d:.3} the first frame, at most {d:.5} apart\n", .{ first[0], first[1], worst });
    try std.testing.expect(worst < FAINT);
}

test "a body takes its torch's light from where the flame is drawn, and none from behind a pillar" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{.{ .x = 20, .y = 13 }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const open = l.onBody(.{ 23.5, 13.5 }, false);
    try std.testing.expectEqual(@as(usize, 1), open.n);
    try std.testing.expect(open.lamp[0].drawn[0] < 23.5 and open.lamp[0].drawn[1] < 13.5);
    try std.testing.expectEqual(@as(usize, 0), l.onBody(.{ 20.5, 15.5 }, false).n);
    l.carrier = .{ 30.5, 20.5 };
    const near_carrier = l.onBody(.{ 33.5, 20.5 }, false);
    const carrying = l.onBody(.{ 30.5, 20.5 }, true);
    std.debug.print("a rat 3 east of the archer has {d} light(s), the archer {d} and ambient {d:.3}\n", .{ near_carrier.n, carrying.n, lum(carrying.ambient) });
    try std.testing.expectEqual(@as(usize, 1), near_carrier.n);
    try std.testing.expect(near_carrier.lamp[0].drawn[0] < 33.5);
    try std.testing.expect(!near_carrier.lamp[0].casts);
    try std.testing.expect(open.lamp[0].casts);
    try std.testing.expectEqual(@as(usize, 0), carrying.n);
    try std.testing.expect(lum(carrying.ambient) > lum(AMBIENT + CARRY) * 0.95);
}

/// From the middle of `c`, cells away from the sky's light along the ground until the point is half lit.
fn shadowLength(lv: *const grid.Level, k: sky.Sky, c: P) f32 {
    const flat = k.flat();
    const m = mathx.centre(c);
    var d: f32 = 0;
    while (d < 12) : (d += 0.01) {
        const x = m[0] - k.dir[0] / flat * d;
        const y = m[1] - k.dir[1] / flat * d;
        if (!mathx.cellOf(.{ x, y }).eq(c) and sunlit(lv, k, x, y, 0) > 0.5) return d;
    }
    return d;
}

test "the sun throws a thing's shadow its height times the hour's reach, away from the sun, and none on itself" {
    var lv = grid.openFloor();
    const rock = P{ .x = 30, .y = 30 };
    const bush = P{ .x = 60, .y = 30 };
    lv.set(rock, .rock);
    lv.set(bush, .grave);
    for ([_]f32{ 9, 13, 16.5 }) |hour| {
        const k = sky.at(hour);
        const rock_len = shadowLength(&lv, k, rock);
        const bush_len = shadowLength(&lv, k, bush);
        const b = CASTERS.get(.grave).?;
        const tip = b.h * k.reach() + b.r.?;
        std.debug.print("at {d:.1}h, reach {d:.2}: a rock's shadow runs {d:.2} cells from its middle, a grave's {d:.2} (its top's tip {d:.2})\n", .{ hour, k.reach(), rock_len, bush_len, tip });
        try std.testing.expect(rock_len > k.reach() * WALL_H * (1 - SUN_SOFT) and rock_len < k.reach() * WALL_H + 0.75);
        try std.testing.expect(bush_len > tip - SUN_SOFT * b.h * k.reach() - SUN_EDGE and bush_len <= tip);
        const m = mathx.centre(rock);
        const flat = k.flat();
        try std.testing.expectEqual(@as(f32, 1), sunlit(&lv, k, m[0] + k.dir[0] / flat * 0.6, m[1] + k.dir[1] / flat * 0.6, 0));
    }
}

test "everything that blocks a step and does not stand shades the ground past its edge away from the sun, morning, noon and evening" {
    const at = P{ .x = 30, .y = 30 };
    const m = mathx.centre(at);
    for (std.enums.values(grid.Tile)) |t| {
        if (!t.solid() or t.liquid() or look.stands(t)) continue;
        var lv = grid.openFloor();
        lv.set(at, t);
        var worst: f32 = 0;
        for ([_]f32{ 8, 12, 17 }) |hour| {
            const k = sky.at(hour);
            const flat = k.flat();
            const ux = k.dir[0] / flat;
            const uy = k.dir[1] / flat;
            const edge = CASTERS.get(t).?.r orelse 0.5 / @max(@abs(ux), @abs(uy));
            const past = edge + 0.05;
            const shade = sunlit(&lv, k, m[0] - ux * past, m[1] - uy * past, 0);
            worst = @max(worst, shade);
            if (CASTERS.get(t).?.r != null) try std.testing.expectEqual(@as(f32, 1), sunlit(&lv, k, m[0], m[1], topOf(t, at, m)));
        }
        std.debug.print("a {s}: the ground just past its edge takes at most {d:.2} of the sun\n", .{ @tagName(t), worst });
        try std.testing.expect(worst < 0.3);
    }
}

test "a standing shrub takes the sun as a body does, and throws its shadow the same length away from it" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const shrub = P{ .x = 30, .y = 30 };
    const foe = P{ .x = 40, .y = 30 };
    lv.set(shrub, .shrub);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.sky = sky.at(16.5);
    var out: [2][BODY_LIGHTS]Cast = undefined;
    var lean: [2][2]f32 = undefined;
    for ([_]P{ shrub, foe }, 0..) |c, i| {
        const s = l.onBody(mathx.centre(c), false);
        const cs = casts(s, mathx.centre(c), 64, &out[i]);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        lean[i] = cs[0].lean;
    }
    std.debug.print("at 16.5h a shrub's shadow leans {d:.1},{d:.1} px, a foe's {d:.1},{d:.1}\n", .{ lean[0][0], lean[0][1], lean[1][0], lean[1][1] });
    for (0..2) |k| try std.testing.expectApproxEqAbs(lean[1][k], lean[0][k], 1e-3);
    try std.testing.expect(lean[0][0] > 0);
}

test "skipping the sun's march where nothing that casts is near changes nothing it would have found" {
    const procgen = @import("../world/procgen.zig");
    var lv: grid.Level = undefined;
    procgen.roll(&lv, 0x5A7, &.{}, procgen.Floor.of(.wilds), &.{});
    lv.set(.{ .x = 40, .y = 30 }, .rock);
    lv.set(.{ .x = 41, .y = 30 }, .fence);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var skipped: usize = 0;
    var checked: usize = 0;
    for ([_]f32{ 7, 12, 16.5, 19.5 }) |h| {
        const k = sky.at(h);
        var i: usize = 0;
        while (i < grid.CELLS) : (i += 3) {
            const c = mathx.centre(grid.Level.of(i));
            for ([_]f32{ 0, 0.4 }) |z| {
                const q = [2]f32{ c[0] + 0.3, c[1] - 0.2 };
                checked += 1;
                try std.testing.expectEqual(sunlit(&lv, k, q[0], q[1], z), l.sunAt(&lv, SunRay.of(k), q[0], q[1], z));
                const flat = k.flat();
                const far = (CAST_TALLEST - z) / (k.dir[2] / flat);
                const e = [2]f32{ q[0] + k.across()[0] * far, q[1] + k.across()[1] * far };
                const lo = mathx.cellOf(.{ @min(q[0], e[0]), @min(q[1], e[1]) });
                const hi = mathx.cellOf(.{ @max(q[0], e[0]), @max(q[1], e[1]) });
                if (l.castersIn(lo.x - 1, lo.y - 1, hi.x + 2, hi.y + 2) == 0) skipped += 1;
            }
        }
    }
    std.debug.print("a wilds floor: {d} of {d} sun rays skip the march, every answer the same\n", .{ skipped, checked });
    try std.testing.expect(skipped > checked / 4);
}

test "a sun shadow turns smoothly through due east and due west, never flipping across the feet" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const at = mathx.centre(.{ .x = 40, .y = 30 });
    var worst: f32 = 0;
    for ([_][2]f32{ .{ 5.2, 5.9 }, .{ 20.1, 20.6 } }) |span| {
        var was: ?[2]f32 = null;
        var h = span[0];
        while (h < span[1]) : (h += 0.005) {
            l.sky = sky.at(h);
            var buf: [BODY_LIGHTS]Cast = undefined;
            const cs = casts(l.onBody(at, false), at, 64, &buf);
            if (cs.len == 0) {
                was = null;
                continue;
            }
            if (was) |w| worst = @max(worst, @abs(cs[0].lean[1] - w[1]));
            was = cs[0].lean;
        }
    }
    std.debug.print("a sun shadow's lean up or down the screen moves at most {d:.2} px in 18 game seconds\n", .{worst});
    try std.testing.expect(worst < 3);
}

test "under the sky, ground in the sun outshines ground in shade, and night is darker than both" {
    const morning: f32 = 9;
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const rock = P{ .x = 30, .y = 30 };
    lv.set(rock, .rock);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var ids: [grid.MAX_TORCHES]TorchIx = undefined;
    const none = l.near(.{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 }, &ids);
    l.sky = sky.at(morning);
    const k = l.sky.?;
    const flat = k.flat();
    const m = mathx.centre(rock);
    const behind = 0.5 + k.reach() * 0.5;
    const shade = lum(l.at(&lv, none, .{ m[0] - k.dir[0] / flat * behind, m[1] - k.dir[1] / flat * behind }));
    const sun = lum(l.at(&lv, none, .{ m[0] + k.dir[0] / flat * 2, m[1] + k.dir[1] / flat * 2 }));
    l.sky = sky.at(0);
    const night = lum(l.at(&lv, none, .{ m[0] + 5, m[1] }));
    std.debug.print("{d}h ground: {d:.2} in the sun, {d:.2} in a rock's shadow; {d:.3} at midnight\n", .{ morning, sun, shade, night });
    try std.testing.expect(sun > shade * 1.2 and sun < shade * 2 and shade > night * 4);
}
