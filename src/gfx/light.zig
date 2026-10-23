const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const raster = @import("raster.zig");
const shaders = @import("shaders.zig");
const sky = @import("sky.zig");
const lume = @import("../map/lume.zig");
const actor = @import("../play/actor.zig");
const shadow = @import("shadow.zig");
const light_gpu = @import("light_gpu.zig");

const P = mathx.P;
pub const Rgb = sky.Rgb;
const mix = sky.mix;

/// Light-map texels per cell side.
pub const SUB: i32 = 4;
pub const MAP_W: i32 = grid.W * SUB;
pub const MAP_H: i32 = grid.H * SUB;
const NONE_BAKED = [2]i32{ MAP_H, 0 };
pub const TEXELS: usize = @intCast(MAP_W * MAP_H);
pub const Layer = enum { map, glints, fog };
/// Each layer's texel where nothing is remembered.
pub const UNSEEN = std.EnumArray(Layer, rl.Color).init(.{ .map = rl.Color.blank, .glints = rl.Color.blank, .fog = rl.Color.white });
/// DST_COLOR/SRC_COLOR blending doubles the stored light.
pub const OVERBRIGHT: f32 = 2.0;

pub const REACH: i32 = lume.TORCH_REACH;
const REACH2: f32 = @floatFromInt(REACH * REACH);
const SPAN: i32 = grid.Cells.span(REACH);
/// Cells: the inverse square's reference distance.
const FALLOFF_D0: f32 = 2.5;
/// Wall height in cells; the brick face below `FACE_FROM` is foreshortened.
pub const WALL_H: f32 = 1.0;
const FACE_FROM: f32 = 1 - @as(f32, @floatFromInt(look.WALL_FACE_PX)) / @as(f32, @floatFromInt(look.SPRITE_PX));
const FACE_H: f32 = 1 - FACE_FROM;
const FLAME_Z: f32 = 0.6;
/// Flame offset from its wall, preventing edge-on lighting of neighbouring bricks.
const STANDOFF: f32 = 0.3;
const FLOOR_WRAP: f32 = 1.0;
const FACE_WRAP: f32 = 0.35;
const FACE_GAIN: f32 = 1.25;
const CEILING_CATCH: f32 = 0.2;
pub const BODY_Z: f32 = 0.4;

pub const CARRY: Rgb = .{ 0.92, 0.88, 0.80 };
const MOON_CARRY: Rgb = .{ 0.52, 0.68, 1.0 };
/// A cell past what the hero's light lets it see, so its glow fades out on the edge of sight.
const CARRY_R: f32 = @floatFromInt(actor.row(actor.HERO).light + 1);
const CARRY_FADE: f32 = 0.3;
const CARRY_CEILING: f32 = 0.7;
const CARRY_FACE_WRAP: f32 = 0.6;

/// The light remembered terrain is drawn under, after Brogue's memory colour.
pub const MEMORY = rgbOf(look.rgb(0x33385c));
const FLAME: Rgb = .{ 1.30, 0.80, 0.40 };
/// Per channel, the power the flicker is raised to, so a flame whitens as it flares.
const FLAME_SHIFT: Rgb = .{ 1.0, 1.6, 2.4 };
pub const FAINT: f32 = 0.002;
const TINT_DIRECT: f32 = 0.6;
/// Per second.
const REVEAL: f32 = 14.0;
const FORGET: f32 = 5.0;
/// Cells: memory is black on the edge of anything unseen and full this far from it.
const VOID_FADE: f32 = 1.5;
/// Keep the sight fade inside unseen cell rims so visible ground stays bright.
const SIGHT_FADE: f32 = 0.4;
pub const VOID_REACH: i32 = @intFromFloat(@ceil(VOID_FADE));
const VOID_SPAN: usize = @intCast(grid.Cells.span(VOID_REACH));
const CORNERS_W = grid.CORNERS_W;
const CORNERS_H = grid.CORNERS_H;
pub const FLICKER: f32 = 0.14;
const FLICKER_BANDS = [_]struct { hz: f32, weight: f32 }{
    .{ .hz = 1.5, .weight = 0.6 },
    .{ .hz = 5.0, .weight = 0.3 },
    .{ .hz = 11.0, .weight = 0.1 },
};
/// Brogue's `adjustedLightValue`: bend channels above this knee toward sqrt.
pub const KNEE: f32 = 1.5;

pub const BODY_LIGHTS: usize = 4;
/// A pale flash remains visible over red bodies.
pub const FLASH_RGB = Rgb{ 0.88, 0.38, 0.30 };
/// Texels toward the viewer, for the side-lighting of a body.
const BODY_LIGHT_Z: f32 = 40.0;
/// Darkest ground tint; overlapping shadows take the channelwise minimum.
pub const SHADE_RGB = Rgb{ 0.42, 0.45, 0.54 };
/// Darkens whatever lights the ground, the hero's own light too.
const MOON_SHADE_RGB = Rgb{ 0.34, 0.40, 0.62 };
pub const SHADOW_MAX: f32 = 0.85;
/// A light with this share of all that reaches a body casts its darkest shadow; under it the shadow eases out to none.
const SHADOW_FULL: f32 = 0.5;
pub const SHADOW_TAPS: i32 = 3;
const GLOW_CORE: f32 = 0.45;
const GLOW_HALO: f32 = 2.6;
const GLOW_CORE_A: f32 = 0.85;
const GLOW_HALO_A: f32 = 0.2;
const GLOW_TINT: Rgb = .{ 1.0, 0.52, 0.22 };
/// Cells between ray samples; softness is a fraction of caster height and a cell distance from round edges.
const SUN_STEP: f32 = 0.1;
pub const SUN_SOFT: f32 = 0.7;
pub const SUN_EDGE: f32 = 0.2;
/// Of the sky's light, how much a sun shadow takes away at its darkest, and how dark a body's sun shadow is.
const SUN_SHADE: f32 = 0.45;
const SUN_SHADOW_A: f32 = 0.4;
const SKY_SHADOW = SHADOW_MAX * SUN_SHADOW_A;
/// Cells to the side the sun lights a body from, as the body shader takes a lamp.
const SUN_LAMP_D: f32 = 3;

/// Height and optional circular radius in cells; null radius fills a square cell.
const Caster = struct { h: f32, r: ?f32 = null };

pub const CASTERS = std.EnumArray(grid.Tile, ?Caster).initDefault(@as(?Caster, null), .{
    .wall = .{ .h = WALL_H },
    .rock = .{ .h = WALL_H },
    .grave = .{ .h = 0.5, .r = 0.28 },
    .fence = .{ .h = 0.5 },
    .reeds = .{ .h = 0.5 },
    .crop = .{ .h = 0.4 },
});

comptime {
    for (std.enums.values(grid.Tile)) |t| {
        if (t.upright()) std.debug.assert((CASTERS.get(t) != null) != look.stands(t));
    }
}

const CAST_TALLEST: f32 = blk: {
    var most: f32 = 0;
    for (CASTERS.values) |c| most = @max(most, if (c) |k| k.h else 0);
    break :blk most;
};

/// 1 where the light the sky casts reaches a point `z` cells up, eased to 0 under anything between it and the light.
pub fn sunlit(lv: *const grid.Level, ray: SunRay, x: f32, y: f32, z: f32) f32 {
    if (sky.upright(ray.flat)) return 1;
    const ux = ray.u[0];
    const uy = ray.u[1];
    const rise = ray.rise;
    const far = ray.far(z);
    var lit: f32 = 1;
    var t: f32 = SUN_STEP * 0.5;
    while (t < far) : (t += SUN_STEP) {
        const px = x + ux * t;
        const py = y + uy * t;
        const c = mathx.cellOf(.{ px, py });
        if (!grid.Level.inside(c)) break;
        const k = CASTERS.getPtrConst(lv.at(c)).* orelse continue;
        var over = (k.h - z - t * rise) / (SUN_SOFT * k.h);
        if (k.r) |r| over = @min(over, (r - offMiddle(c, .{ px, py })) / SUN_EDGE);
        if (over <= 0) continue;
        lit = @min(lit, 1 - smooth(over));
        if (lit <= 0) return 0;
    }
    return lit;
}

/// Low-sun ground light floor relative to a high sun.
const GROUND_WRAP: f32 = 0.5;
/// Cloud shadows: cells across, cells a second drifting, share of sky covered, edge softness, share of the sun taken.
const CLOUD_SCALE: f32 = 14;
const CLOUD_DRIFT = [2]f32{ 0.35, 0.12 };
const CLOUD_COVER: f32 = 0.52;
const CLOUD_SOFT: f32 = 0.3;
const CLOUD_DEPTH: f32 = 0.18;
const CLOUD_OCTAVES = [2]f32{ 0.65, 0.35 };
const CLOUD_LACUNARITY: f32 = 2.3;

/// What of the sun a cloud's shadow drifting over a point at `t` seconds leaves it.
fn clouded(x: f32, y: f32, t: f32) f32 {
    const u = x / CLOUD_SCALE + t * CLOUD_DRIFT[0] / CLOUD_SCALE;
    const v = y / CLOUD_SCALE + t * CLOUD_DRIFT[1] / CLOUD_SCALE;
    const n = value2(u, v) * CLOUD_OCTAVES[0] + value2(u * CLOUD_LACUNARITY + 17, v * CLOUD_LACUNARITY - 9) * CLOUD_OCTAVES[1];
    const edge = 1 - CLOUD_COVER;
    const cover = mathx.smoothstep(edge - CLOUD_SOFT / 2, edge + CLOUD_SOFT / 2, n);
    return 1 - CLOUD_DEPTH * cover;
}

fn value2(u: f32, v: f32) f32 {
    return mathx.valueNoise({}, hash2, u, v);
}

fn hash2(_: void, x: i32, y: i32) f32 {
    return hash(x *% 73856093 ^ y *% 19349663, 0xC10D);
}

fn shaded(sun: f32) f32 {
    return 1 - SUN_SHADE * (1 - sun);
}

fn reaching(sun: f32, cloud: f32) f32 {
    return shaded(sun) * cloud;
}

fn faceCatch(cos: f32) f32 {
    return wrapped(cos, FACE_WRAP) * FACE_GAIN;
}

pub const SunRay = struct {
    k: sky.Sky,
    flat: f32,
    u: [2]f32,
    /// Cells up per cell along the ground toward the light.
    rise: f32,
    /// How deep the moon's shadows darken the ground, whatever lights it, and in what.
    night: f32,
    shade: Rgb,
    glint: f32,

    pub fn of(k: sky.Sky) SunRay {
        const flat = k.flat();
        return .{
            .k = k,
            .flat = flat,
            .u = k.across(),
            .rise = k.rise(),
            .night = k.moon * skyDepth(k, 1),
            .shade = skyShade(k),
            .glint = smoothSpecular(k.dir, SUN_GLINT_POWER),
        };
    }

    fn dim(ray: SunRay, sun: f32, cloud: f32) Rgb {
        return mix(splat(1), ray.shade, (1 - sun) * cloud * ray.night);
    }

    /// Cells along the ground from a point `z` up to where the ray has risen over everything that casts.
    fn far(ray: SunRay, z: f32) f32 {
        return @max(0, CAST_TALLEST - z) / ray.rise;
    }
};

fn cloudIn(corners: [4]f32, c: P, q: [2]f32) f32 {
    const u = q[0] - @as(f32, @floatFromInt(c.x));
    const v = q[1] - @as(f32, @floatFromInt(c.y));
    return mathx.bilerp(corners, u, v);
}

/// Ignores what stands in the way.
fn sunFacing(sk: sky.Sky, s: Spot) f32 {
    return switch (s.surface) {
        .floor, .ceiling => wrapped(sk.dir[2], GROUND_WRAP),
        .face => faceCatch(sk.dir[1]),
    };
}

pub const Surface = enum { floor, face, ceiling };

pub fn topOf(t: grid.Tile, cell: P, q: [2]f32) f32 {
    const k = CASTERS.getPtrConst(t).* orelse return 0;
    const r = k.r orelse return k.h;
    return if (offMiddle(cell, q) < r) k.h else 0;
}

fn offset(a: [3]f32, x: f32, y: f32, z: f32) [3]f32 {
    return .{ a[0] - x, a[1] - y, a[2] - z };
}

fn len2(d: [3]f32) f32 {
    return d[0] * d[0] + d[1] * d[1] + d[2] * d[2];
}

pub fn offMiddle(c: P, q: [2]f32) f32 {
    const m = mathx.centre(c);
    return mathx.len(q[0] - m[0], q[1] - m[1]);
}

/// Light-map coordinates account for walls drawn above their ground cell.
pub const Spot = struct {
    x: f32,
    y: f32,
    z: f32,
    surface: Surface,

    pub fn of(lv: *const grid.Level, q: [2]f32) Spot {
        const cell = mathx.cellOf(q);
        const t = lv.at(cell);
        if (t != .wall) return .{ .x = q[0], .y = q[1], .z = topOf(t, cell, q), .surface = .floor };
        const fy = q[1] - @floor(q[1]);
        const top: f32 = @floatFromInt(cell.y);
        const faced = if (lv.wallShape(cell)) |s| s.faced() else false;
        if (faced and fy >= FACE_FROM) {
            return .{ .x = q[0], .y = top + 1, .z = faceZ(fy), .surface = .face };
        }
        return .{ .x = q[0], .y = q[1] + FACE_H, .z = WALL_H, .surface = .ceiling };
    }
};

fn faceZ(fy: f32) f32 {
    return (1 - fy) / FACE_H * WALL_H;
}

fn faceY(top: f32, z: f32) f32 {
    return top + 1 - z / WALL_H * FACE_H;
}

pub const TorchIx = std.math.IntFittingRange(0, grid.MAX_TORCHES - 1);

const Torch = struct {
    wall: P,
    /// 1 where the flame's light gets to, over the box of cells centred on the floor below the flame.
    reach: [grid.Cells.square(REACH)]f32,
    /// Sight-blocking mask for interpolation; prevents walls passing light onward.
    open: [grid.Cells.square(REACH)]f32,
    seed: u32,
    colour: Rgb = FLAME,
    glow: f32 = 1,

    fn floor(t: *const Torch) P {
        return lume.torchFloor(t.wall);
    }

    /// On the ground plane.
    pub fn flame(t: *const Torch) [3]f32 {
        return .{ mathx.centre(t.wall)[0], @as(f32, @floatFromInt(t.floor().y)) + STANDOFF, FLAME_Z };
    }

    fn drawn(t: *const Torch) [2]f32 {
        return .{ mathx.centre(t.wall)[0], faceY(@floatFromInt(t.wall.y), FLAME_Z) };
    }

    fn box(t: *const Torch) grid.Box {
        return grid.Box.around(t.floor(), REACH);
    }

    fn corner(t: *const Torch) P {
        return t.box().lo;
    }

    fn texel(t: *const Torch, p: P) usize {
        return t.box().slot(p).?;
    }

    fn reached(t: *const Torch, x: f32, y: f32) f32 {
        const uv = fieldUv(t.corner(), x, y);
        return occluded(&t.reach, &t.open, SPAN, SPAN, uv[0], uv[1]);
    }

    /// The flame's offset from a point and how much of it reaches there, fallen off and occluded; null out of reach.
    fn toward(t: *const Torch, x: f32, y: f32, z: f32) ?struct { d: [3]f32, d2: f32, k: f32 } {
        const f = t.flame();
        const d = offset(f, x, y, z);
        const d2 = len2(d);
        if (d2 >= REACH2) return null;
        const o = t.reached(x, y);
        if (o <= 0) return null;
        return .{ .d = d, .d2 = d2, .k = falloff(d2) * o };
    }

    fn shine(t: *const Torch, s: Spot) f32 {
        const r = t.toward(s.x, s.y, s.z) orelse return 0;
        const facing = switch (s.surface) {
            .floor => wrapped(r.d[2] / @sqrt(r.d2), FLOOR_WRAP),
            .face, .ceiling => upright(s.surface, r.d[0], r.d[1]),
        };
        return r.k * facing;
    }
};

fn upright(surface: Surface, dx: f32, dy: f32) f32 {
    return switch (surface) {
        .floor => unreachable,
        .face => faceCatch(faceCos(dy, mathx.len(dx, dy))),
        .ceiling => CEILING_CATCH,
    };
}

/// From the water toward the viewer, who looks down at 45 degrees from the south.
const VIEWER: Rgb = .{ 0, std.math.sqrt1_2, std.math.sqrt1_2 };
const SUN_GLINT_POWER: u32 = 24;
pub const GLINT_POWER: u32 = 80;
const SUN_GLINT: f32 = 0.05;
const CARRY_GLINT: f32 = 0.08;
const TORCH_GLINT: f32 = 0.12;
const EFFECT_GLINT: f32 = 0.11;

pub fn smoothSpecular(toward: [3]f32, comptime power: u32) f32 {
    const d: Rgb = toward;
    const len = sky.norm(d);
    if (len <= 1e-5 or d[2] <= 0) return 0;
    const half = d / splat(len) + VIEWER;
    const h = sky.unit(half);
    return mathx.powi(@max(0, h[2]), power);
}

fn remembered(view: Rgb, sight: f32, memory: f32) Rgb {
    return mix(MEMORY, view, sight) * splat(memory);
}

/// Windowed inverse square: exactly nothing at `REACH`.
fn falloff(d2: f32) f32 {
    const r = d2 / REACH2;
    const w = std.math.clamp(1 - r * r, 0, 1);
    return w * w / (1 + d2 / (FALLOFF_D0 * FALLOFF_D0));
}

pub fn carryFade(d: f32) f32 {
    return @max(0, @min(carryAlong(d), CARRY_EDGE * (CARRY_R - d)));
}

fn carryAlong(d: f32) f32 {
    return 1 - (1 - CARRY_FADE) * d / CARRY_R;
}

const CARRY_EDGE = carryAlong(CARRY_R - 1);

fn wrapped(cos: f32, wrap: f32) f32 {
    return @max(0, (cos + wrap) / (1 + wrap));
}

/// 0 outside the grid; texel centres sit on whole numbers.
fn bilinear(f: []const f32, w: i32, h: i32, u: f32, v: f32) f32 {
    const fx = @floor(u);
    const fy = @floor(v);
    const x0: i32 = @intFromFloat(fx);
    const y0: i32 = @intFromFloat(fy);
    return mathx.bilerp(.{ texel(f, w, h, x0, y0), texel(f, w, h, x0 + 1, y0), texel(f, w, h, x0, y0 + 1), texel(f, w, h, x0 + 1, y0 + 1) }, u - fx, v - fy);
}

/// Bilinear self-weight is at least 1/4, keeping remembered open ground whole.
const OPEN_WHOLE: f32 = 4;

/// A map-sized field at a point on the screen, cells.
fn sample(f: *const [grid.CELLS]f32, x: f32, y: f32) f32 {
    const uv = fieldUv(.{ .x = 0, .y = 0 }, x, y);
    return bilinear(f, grid.W, grid.H, uv[0], uv[1]);
}

fn fieldUv(o: P, x: f32, y: f32) [2]f32 {
    return .{ x - @as(f32, @floatFromInt(o.x)) - 0.5, y - @as(f32, @floatFromInt(o.y)) - 0.5 };
}

const SightField = enum { soft, weight, open };

fn sightOf(sees: anytype, ground: bool, x: f32, y: f32) f32 {
    const soft = sees.at(.soft, x, y);
    if (!ground) return soft;
    const weight = sees.at(.weight, x, y);
    if (weight <= 0) return soft;
    return mathx.lerpF(soft, sees.at(.open, x, y) / weight, @min(1, weight * OPEN_WHOLE));
}

const Whole = struct {
    l: *const Light,

    fn at(w: Whole, k: SightField, x: f32, y: f32) f32 {
        return sample(w.l.sightField(k), x, y);
    }
};

const Patch = struct {
    const SIDE = 3;

    lo: P,
    v: std.EnumArray(SightField, [SIDE * SIDE]f32),

    fn of(l: *const Light, c: P) Patch {
        var p = Patch{ .lo = c.sub(.{ .x = SIDE / 2, .y = SIDE / 2 }), .v = undefined };
        for (std.enums.values(SightField)) |k| {
            const f = l.sightField(k);
            const out = p.v.getPtr(k);
            for (out, 0..) |*o, i| {
                const q = p.lo.add(mathx.unslot(i, SIDE));
                o.* = texel(f, grid.W, grid.H, q.x, q.y);
            }
        }
        return p;
    }

    fn at(p: *const Patch, k: SightField, x: f32, y: f32) f32 {
        const u = x - 0.5;
        const v = y - 0.5;
        const fx = @floor(u);
        const fy = @floor(v);
        const ix: usize = @intCast(@as(i32, @intFromFloat(fx)) - p.lo.x);
        const iy: usize = @intCast(@as(i32, @intFromFloat(fy)) - p.lo.y);
        const f = p.v.getPtrConst(k);
        const i = iy * SIDE + ix;
        return mathx.bilerp(.{ f[i], f[i + 1], f[i + SIDE], f[i + SIDE + 1] }, u - fx, v - fy);
    }
};

fn sampleOccluded(reach: *const [grid.CELLS]f32, open: *const [grid.CELLS]f32, x: f32, y: f32) f32 {
    const uv = fieldUv(.{ .x = 0, .y = 0 }, x, y);
    return occluded(reach, open, grid.W, grid.H, uv[0], uv[1]);
}

pub fn texel(f: []const f32, w: i32, h: i32, x: i32, y: i32) f32 {
    return f[mathx.slot(x, y, @intCast(w), @intCast(h)) orelse return 0];
}

/// Blend unreachable cells over `open` so walls cannot pass light onward.
fn occluded(reach: []const f32, open: []const f32, w: i32, h: i32, u: f32, v: f32) f32 {
    const own = texel(reach, w, h, mathx.roundTiesUp(u), mathx.roundTiesUp(v)) > 0;
    return bilinear(if (own) reach else open, w, h, u, v);
}

pub fn mask(on: bool) f32 {
    return @floatFromInt(@intFromBool(on));
}

fn hidesGround(t: grid.Tile) bool {
    return t.blind() and t.upright() and !look.stands(t);
}

const Fade = struct {
    flat: ?f32 = null,
    n: usize = 0,
    short: [grid.Cells.square(VOID_REACH)]Short = undefined,

    const Short = struct { x: f32, y: f32, m: f32 };

    fn at(f: *const Fade, x: f32, y: f32, sight: f32) f32 {
        if (f.flat) |v| return v;
        const reach = mathx.lerpF(VOID_FADE, SIGHT_FADE, sight);
        var v: f32 = 1;
        for (f.short[0..f.n]) |c| {
            const dx = @max(0, @max(c.x - x, x - c.x - 1));
            const dy = @max(0, @max(c.y - y, y - c.y - 1));
            if (dx >= reach or dy >= reach) continue;
            v = @min(v, mathx.lerpF(c.m, 1, smooth(mathx.len(dx, dy) / reach)));
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

/// The cosine a light `dy` south of a south face and `flat` from it along the ground strikes it at.
fn faceCos(dy: f32, flat: f32) f32 {
    return dy / @max(flat, FACE_EPS);
}

const FACE_EPS: f32 = 1e-2;

const splat = sky.splat;

const rgbOf = look.rgbOf;

pub fn colourOf(c: Rgb, a: f32) rl.Color {
    const k = @max(splat(0), @min(splat(1), c)) * splat(255) + splat(0.5);
    return .{ .r = @intFromFloat(k[0]), .g = @intFromFloat(k[1]), .b = @intFromFloat(k[2]), .a = @intFromFloat(std.math.clamp(a, 0, 1) * 255 + 0.5) };
}

pub fn texelOf(c: Rgb, sight: f32) rl.Color {
    return colourOf(knee(c) / splat(OVERBRIGHT), sight);
}

const lum = sky.luma;

/// Cells: `drawn` as on screen, `ground` where it stands.
const Lamp = struct {
    drawn: [2]f32,
    ground: [2]f32,
    colour: Rgb,
    /// The carried light casts no body's shadow, as it casts none of its carrier's.
    casts: bool,
    sky: ?SkyCast = null,
};

/// Distant sky shadow: `reach` body heights, `depth` intensity in `shade`.
const SkyCast = struct { reach: f32, depth: f32, shade: Rgb };

fn skyDepth(k: sky.Sky, lit: f32) f32 {
    const key = lum(k.key) * lit;
    return SKY_SHADOW * castShare(key, key + lum(k.ambient));
}

pub fn castShare(own: f32, all: f32) f32 {
    return smooth(own / @max(all, 1e-6) / SHADOW_FULL);
}

fn skyShade(k: sky.Sky) Rgb {
    return mix(SHADE_RGB, MOON_SHADE_RGB, k.moon);
}

pub const Shine = struct {
    ambient: Rgb = @splat(0),
    emission: Rgb = @splat(0),
    /// Of `ambient`, what memory's floor lifts it by: no light reaches with it.
    floor: Rgb = @splat(0),
    /// How far in sight times how far remembered the ground under the body is.
    sight: f32 = 1,
    n: usize = 0,
    lamp: [BODY_LIGHTS]Lamp = undefined,

    /// The dimmest gives way when all are taken, but never the sky's: its shadow is as dark however dim its light.
    pub fn add(self: *Shine, l: Lamp) void {
        var i = self.n;
        if (self.n == BODY_LIGHTS) {
            var dimmest: ?usize = null;
            for (&self.lamp, 0..) |*m, k| {
                if (m.sky != null) continue;
                if (dimmest == null or lum(m.colour) < lum(self.lamp[dimmest.?].colour)) dimmest = k;
            }
            i = dimmest orelse return;
            if (l.sky == null and lum(l.colour) <= lum(self.lamp[i].colour)) return;
        } else self.n += 1;
        self.lamp[i] = l;
    }

    pub fn total(self: *const Shine) Rgb {
        var c: Rgb = @splat(0);
        for (self.lamp[0..self.n]) |l| c += l.colour;
        return c;
    }

    pub fn lit(self: *const Shine) f32 {
        return lum(self.ambient + self.total());
    }

    pub fn reached(self: *const Shine) f32 {
        return lum(self.ambient - self.floor + self.total());
    }

    pub fn tint(self: *const Shine, c: rl.Color) rl.Color {
        return recolour(c, rgbOf(c) * knee(self.ambient + self.total() * splat(TINT_DIRECT)));
    }

    /// As the body shader would draw `c`, for what is drawn without it.
    pub fn drawn(self: *const Shine, c: rl.Color, flash: f32) rl.Color {
        return flashed(recolour(c, rgbOf(self.tint(c)) + self.emission * splat(self.sight)), flash);
    }
};

fn recolour(c: rl.Color, rgb: Rgb) rl.Color {
    return colourOf(rgb, look.alphaOf(c));
}

/// `lit` combines sight and memory; `memory` retains only exploration visibility.
pub const Flame = struct {
    at: [2]f32,
    foot: f32,
    glow: f32,
    lit: f32,
    memory: f32,

    /// Seen enough to glow and bloom.
    pub fn live(f: Flame) bool {
        return f.lit > FAINT;
    }
};

/// Composed daylight warms the sun and cools the shade.
const COMPOSED_KEY: Rgb = .{ 1.035, 1.005, 0.96 };
const COMPOSED_AMBIENT: Rgb = .{ 0.94, 0.98, 1.04 };
/// Composed sun through cloud: lifted in the open, deeper under cloud, dappled under crowns.
const PATCH_LIFT: f32 = 1.045;
const PATCH_CLOUD: f32 = 1.6;
const DAPPLE_WAVE = [3]f32{ 2.1, 1.6, 1.2 };
const DAPPLE_MIN: f32 = 0.07;
const DAPPLE_SPAN: f32 = 0.10;
/// Crowns within this many cells shade a cell's sun, each by this much over one plus its squared distance.
const DAPPLE_REACH = 2;
const DAPPLE_COVER: f32 = 0.3;

pub const Emission = struct {
    at: [3]f32,
    col: rl.Color,
    radius: f32,
    gain: f32,

    /// Where the source shows on the map, lifted by its height.
    pub fn drawn(e: Emission) [2]f32 {
        return .{ e.at[0], e.at[1] - e.at[2] };
    }
};

pub const EFFECTS = 48;
pub const EffectSet = std.StaticBitSet(EFFECTS);
const EFFECT_REACH = 5;
pub const EFFECT_SPAN: comptime_int = grid.Cells.span(EFFECT_REACH);

const Effect = struct {
    source: Emission,
    origin: P,
    reach: [grid.Cells.square(EFFECT_REACH)]bool,

    pub fn strength(e: *const Effect, x: f32, y: f32, z: f32) f32 {
        const s = e.source;
        const d2 = len2(offset(s.at, x, y, z));
        if (d2 >= s.radius * s.radius) return 0;
        const i = e.texel(mathx.cellOf(.{ x, y })) orelse return 0;
        if (!e.reach[i]) return 0;
        const k = 1 - d2 / (s.radius * s.radius);
        return s.gain * k * k;
    }

    pub fn box(e: *const Effect) grid.Box {
        return .around(e.origin, EFFECT_REACH);
    }

    fn texel(e: *const Effect, p: P) ?usize {
        return e.box().slot(p);
    }
};

pub const Options = struct {
    shadows: bool = true,
    body_lighting: bool = true,
    effect_lights: bool = true,
    water_glints: bool = true,
};

pub const Light = struct {
    options: Options = .{},
    effects: [EFFECTS]Effect = undefined,
    effect_n: usize = 0,
    sight: [grid.CELLS]f32,
    memory: [grid.CELLS]f32,
    soft_sight: [grid.CELLS]f32,
    /// Weighted sight over open ground only, preventing light leaks through walls.
    open_sight: [grid.CELLS]f32,
    /// 1 on a cell that blocks no sight; set from the tiles in `settle`.
    see_through: [grid.CELLS]f32,
    /// Open-ground memory weights; `sightAt` divides weighted sight by these.
    open_weight: [grid.CELLS]f32,
    /// Ground visibility includes shrub edges, keeping them continuous with adjacent ground.
    ground: [grid.CELLS]f32,
    blur: [grid.CELLS]f32,
    share: [grid.CELLS]f32,
    /// `sight` but for what blocks it, as `Torch.open` is, so the carried light passes through no wall.
    carry_open: [grid.CELLS]f32,
    clear: [grid.CELLS]bool,
    clear_row: [grid.CELLS]bool,
    torch: [grid.MAX_TORCHES]Torch,
    torch_n: usize = 0,
    /// The hero's centre as drawn, cells.
    carrier: ?[2]f32 = null,
    sky: ?sky.Sky = null,
    /// Integral image of caster counts at cell corners.
    casting: [CORNERS_W * CORNERS_H]u16,
    clouds: [CORNERS_W * CORNERS_H]f32,
    /// Cached inclusive cloud corners and sample time in seconds.
    clouds_held: ?struct { box: grid.Box, t: f32 } = null,
    t: mathx.Seconds = .{},
    texels: std.EnumArray(Layer, [TEXELS]rl.Color),
    /// The rows of `texels` baked since the texture was last sent, all it needs sent.
    baked: [2]i32,
    scratch: grid.Level,
    gpu: light_gpu.Gpu = .{},
    forest: [shadow.FOREST_QUEUE]shadow.ForestCast,
    forest_n: usize = 0,
    forest_order: [shadow.FOREST_QUEUE]u64,
    reveal_map: bool = false,
    composed: bool = false,
    canopy: [grid.CELLS]f32,
    /// Per light-map texel, `dapplingAt` its centre: fixed while the ground is.
    dappling: [TEXELS]f32,

    /// Initialize fields separately to avoid a temporary larger than the thread stack.
    pub fn create(alloc: std.mem.Allocator) !*Light {
        const l = try alloc.create(Light);
        mathx.defaults(l);
        @memset(&l.casting, 0);
        @memset(&l.sight, 0);
        @memset(&l.memory, 0);
        @memset(&l.scratch.tile, .floor);
        @memset(&l.scratch.los, false);
        l.grounded();
        for (std.enums.values(Layer)) |k| @memset(l.texels.getPtr(k), UNSEEN.get(k));
        l.baked = .{ 0, MAP_H };
        l.soften();
        return l;
    }

    pub fn settle(self: *Light, lv: *const grid.Level) void {
        self.effect_n = 0;
        self.scratch = lv.*;
        self.grounded();
        self.countCasters(lv);
        self.torch_n = 0;
        for (lv.torches(), 0..) |w, i| {
            var t = Torch{ .wall = w, .reach = undefined, .open = undefined, .seed = @as(u32, @intCast(i)) *% 0x27D4EB2F +% 0x165667B1 };
            var pool: [grid.CELLS]bool = @splat(false);
            lume.torchPool(lv, w, &pool);
            var box = t.box().cells();
            while (box.next()) |p| {
                const k = t.texel(p);
                t.reach[k] = mask(grid.cellOr(bool, &pool, p, false));
                t.open[k] = t.reach[k] * grid.cellOr(f32, &self.see_through, p, 0);
            }
            self.torch[self.torch_n] = t;
            self.torch_n += 1;
        }
        for (0..grid.CELLS) |i| {
            self.sight[i] = mask(lv.lit[i]);
            self.memory[i] = mask(self.recalls(lv, i));
        }
        self.soften();
        self.t = .{};
        self.fan();
    }

    pub fn step(self: *Light, lv: *const grid.Level, dt: f32) void {
        self.scratch.los = lv.los;
        const up = mathx.easing(dt, REVEAL);
        const down = mathx.easing(dt, FORGET);
        var moved = false;
        for (0..grid.CELLS) |i| {
            const want_s = mask(lv.lit[i]);
            const want_m = mask(self.recalls(lv, i));
            if (self.sight[i] == want_s and self.memory[i] == want_m) continue;
            const s = mathx.ease(self.sight[i], want_s, up, down);
            const m = mathx.ease(self.memory[i], want_m, up, down);
            moved = moved or s != self.sight[i] or m != self.memory[i];
            self.sight[i] = s;
            self.memory[i] = m;
        }
        if (moved) self.soften();
        self.t.step(dt);
        self.fan();
    }

    pub fn reveal(self: *Light, lv: *const grid.Level, enabled: bool) void {
        self.reveal_map = enabled;
        for (0..grid.CELLS) |i| self.memory[i] = mask(self.recalls(lv, i));
        self.soften();
    }

    fn recalls(self: *const Light, lv: *const grid.Level, i: usize) bool {
        return self.reveal_map or lv.seen[i];
    }

    /// Drawn as terrain: explored, or everything while the debug reveal is on.
    pub fn remembers(self: *const Light, lv: *const grid.Level, p: P) bool {
        return self.reveal_map or lv.isSeen(p);
    }

    fn fan(self: *Light) void {
        for (self.torch[0..self.torch_n]) |*t| {
            t.glow = flicker(self.t.at(), t.seed);
            var shift: Rgb = undefined;
            for (0..3) |k| shift[k] = std.math.pow(f32, t.glow, FLAME_SHIFT[k]);
            t.colour = FLAME * shift;
        }
    }

    pub const TEXELS_W: usize = @intCast(MAP_W);

    pub fn texelCentre(tx: usize, ty: usize) [2]f32 {
        const sub: f32 = @floatFromInt(SUB);
        return .{ (@as(f32, @floatFromInt(tx)) + 0.5) / sub, (@as(f32, @floatFromInt(ty)) + 0.5) / sub };
    }

    pub fn texelCentreOf(i: usize) [2]f32 {
        return texelCentre(i % TEXELS_W, i / TEXELS_W);
    }

    fn grounded(self: *Light) void {
        for (&self.see_through, &self.ground, &self.scratch.tile) |*k, *g, t| {
            k.* = mask(!t.blind());
            g.* = mask(!hidesGround(t));
        }
        var cells = grid.Cells.of(.{ .x = 0, .y = 0 }, grid.SIZE);
        while (cells.next()) |p| {
            var neighbours = grid.Cells.around(p, DAPPLE_REACH);
            var cover: f32 = 0;
            while (neighbours.next()) |q| {
                if (!look.crowned(self.scratch.at(q))) continue;
                const d = p.sub(q);
                cover += 1 / @as(f32, @floatFromInt(1 + d.x * d.x + d.y * d.y));
            }
            self.canopy[grid.Level.idx(p)] = @min(1, cover * DAPPLE_COVER);
        }
        for (&self.dappling, 0..) |*d, i| d.* = self.dapplingAt(texelCentreOf(i));
    }

    /// Blur only seen cells, and ground sight only over open ground, to prevent dim rims and wall leaks.
    pub fn soften(self: *Light) void {
        for (&self.soft_sight, &self.open_sight, &self.open_weight, &self.carry_open, &self.sight, &self.memory, &self.see_through) |*seen, *open, *w, *carry, s, m, k| {
            seen.* = s * m;
            open.* = s * m * k;
            w.* = m * k;
            carry.* = s * k;
        }
        self.blurShare(&self.soft_sight, &self.memory);
        self.blurShare(&self.open_sight, &self.open_weight);
        for (&self.open_sight, &self.open_weight) |*o, w| o.* *= w;
        self.markClear();
    }

    fn markClear(self: *Light) void {
        const r: usize = VOID_REACH;
        const span = VOID_SPAN;
        const w = grid.COLS;
        const h = grid.ROWS;
        @memset(&self.clear_row, false);
        @memset(&self.clear, false);
        for (0..h) |y| {
            var run: usize = 0;
            for (self.memory[y * w ..][0..w], 0..) |m, x| {
                run = if (m >= 1) run + 1 else 0;
                if (run >= span) self.clear_row[y * w + x - r] = true;
            }
        }
        var runs: [grid.COLS]u16 = @splat(0);
        for (0..h) |y| {
            for (self.clear_row[y * w ..][0..w], &runs, 0..) |ok, *run, x| {
                run.* = if (ok) run.* + 1 else 0;
                if (run.* >= span) self.clear[(y - r) * w + x] = true;
            }
        }
    }

    fn blurShare(self: *Light, num: *[grid.CELLS]f32, den: *const [grid.CELLS]f32) void {
        blur121(num, &self.blur, num);
        blur121(den, &self.blur, &self.share);
        for (num, &self.share) |*o, d| o.* = if (d > 0) @min(1, o.* / d) else 0;
    }

    /// A point on the screen, cells.
    pub fn sightAt(self: *const Light, x: f32, y: f32) f32 {
        return sightOf(Whole{ .l = self }, self.groundAt(mathx.cellOf(.{ x, y })), x, y);
    }

    fn groundAt(self: *const Light, c: P) bool {
        return grid.cellOr(f32, &self.ground, c, 0) > 0;
    }

    fn sightField(self: *const Light, k: SightField) *const [grid.CELLS]f32 {
        return switch (k) {
            .soft => &self.soft_sight,
            .weight => &self.open_weight,
            .open => &self.open_sight,
        };
    }

    /// Distance fade reaches black at unseen rims; a blur leaks around corners.
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

    pub fn memoryAt(self: *const Light, p: P) f32 {
        return grid.cellOr(f32, &self.memory, p, 0);
    }

    fn whole(self: *const Light, p: P) bool {
        return grid.cellOr(bool, &self.clear, p, false);
    }

    pub fn near(self: *const Light, view: grid.Box, out: *[grid.MAX_TORCHES]TorchIx) []const TorchIx {
        var n: usize = 0;
        for (self.torch[0..self.torch_n], 0..) |*t, i| {
            if (!t.box().overlaps(view, 0)) continue;
            out[n] = @intCast(i);
            n += 1;
        }
        return out[0..n];
    }

    /// Ground distance and southward offset in cells, plus attenuated visibility.
    fn carryToward(self: *const Light, x: f32, y: f32, fogged: bool) ?struct { at: [2]f32, flat: f32, dy: f32, k: f32 } {
        const c = self.carrier orelse return null;
        const share = self.carryShare();
        if (share <= 0) return null;
        const dx = c[0] - x;
        const dy = c[1] - y;
        const flat = mathx.len(dx, dy);
        if (flat >= CARRY_R) return null;
        const reach = if (fogged) sampleOccluded(&self.sight, &self.carry_open, x, y) else self.carryReach(x, y);
        return .{ .at = c, .flat = flat, .dy = dy, .k = carryFade(flat) * share * reach };
    }

    fn carried(self: *const Light, s: Spot) f32 {
        const f = self.carryToward(s.x, s.y, true) orelse return 0;
        const facing = switch (s.surface) {
            .floor => 1,
            .face => wrapped(faceCos(f.dy, f.flat), CARRY_FACE_WRAP),
            .ceiling => CARRY_CEILING,
        };
        return f.k * facing;
    }

    fn carryReach(self: *const Light, x: f32, y: f32) f32 {
        const corner = mathx.cellOf(.{ x - 0.5, y - 0.5 });
        var reach: [4]f32 = undefined;
        var open: [4]f32 = undefined;
        for (0..4) |i| {
            const p = corner.add(mathx.unslot(i, 2));
            reach[i] = mask(self.scratch.inLos(p));
            open[i] = reach[i] * grid.cellOr(f32, &self.see_through, p, 0);
        }
        return occluded(&reach, &open, 2, 2, x - 0.5 - @as(f32, @floatFromInt(corner.x)), y - 0.5 - @as(f32, @floatFromInt(corner.y)));
    }

    fn countCasters(self: *Light, lv: *const grid.Level) void {
        const w = CORNERS_W;
        @memset(self.casting[0..w], 0);
        for (0..grid.ROWS) |y| {
            var row: u16 = 0;
            self.casting[(y + 1) * w] = 0;
            for (0..grid.COLS) |x| {
                row += @intFromBool(CASTERS.getPtrConst(lv.tile[y * grid.COLS + x]).* != null);
                self.casting[(y + 1) * w + x + 1] = self.casting[y * w + x + 1] + row;
            }
        }
    }

    pub fn sunAt(self: *const Light, lv: *const grid.Level, ray: *const SunRay, x: f32, y: f32, z: f32) f32 {
        if (sky.upright(ray.flat)) return 1;
        const b = sunBox(ray.*, x, y, z);
        if (self.castersIn(b) == 0) return 1;
        return sunlit(lv, ray.*, x, y, z);
    }

    pub fn sunBox(ray: SunRay, x: f32, y: f32, z: f32) grid.Box {
        const far = ray.far(z);
        return grid.Box.between(mathx.cellOf(.{ x, y }), mathx.cellOf(.{ x + ray.u[0] * far, y + ray.u[1] * far })).grown(1);
    }

    pub fn castersIn(self: *const Light, box: grid.Box) u16 {
        const w = CORNERS_W;
        const a: usize = @intCast(std.math.clamp(box.lo.x, 0, grid.W));
        const b: usize = @intCast(std.math.clamp(box.lo.y, 0, grid.H));
        const c: usize = @intCast(std.math.clamp(box.hi.x, 0, grid.W));
        const d: usize = @intCast(std.math.clamp(box.hi.y, 0, grid.H));
        if (c <= a or d <= b) return 0;
        return self.casting[d * w + c] + self.casting[b * w + a] - self.casting[b * w + c] - self.casting[d * w + a];
    }

    fn carryShare(self: *const Light) f32 {
        return if (self.sky) |k| k.carry else 1;
    }

    fn ambientOf(self: *const Light) Rgb {
        return if (self.profile()) |k| k.ambient else splat(0);
    }

    fn profile(self: *const Light) ?sky.Sky {
        var k = self.sky orelse return null;
        if (self.composed) {
            k.key *= mix(splat(1), COMPOSED_KEY, k.sun());
            k.ambient *= mix(splat(1), COMPOSED_AMBIENT, k.sun());
        }
        return k;
    }

    fn sunRay(self: *const Light) ?SunRay {
        return if (self.profile()) |k| SunRay.of(k) else null;
    }

    /// The sun the clouds let through at `q`, composed; from the cached dappling when `q` is light-map texel `map_at`'s centre.
    fn composedAt(self: *const Light, map_at: ?usize, q: [2]f32, cloud: f32) f32 {
        const k = self.sky orelse return cloud;
        if (!self.composed or k.sun() == 0) return cloud;
        const dappling = if (map_at) |i| self.dappling[i] else self.dapplingAt(q);
        const patch = PATCH_LIFT - (1 - cloud) * PATCH_CLOUD - dappling;
        return mathx.lerpF(cloud, patch, k.sun());
    }

    /// How much the canopy's dappled shade takes from the sun at `q`.
    fn dapplingAt(self: *const Light, q: [2]f32) f32 {
        const cover = sample(&self.canopy, q[0], q[1]);
        if (cover == 0) return 0;
        const dapple = 0.5 + 0.5 * @sin(q[0] * DAPPLE_WAVE[0] + q[1] * DAPPLE_WAVE[1] + @sin(q[1] * DAPPLE_WAVE[2]));
        return cover * (DAPPLE_MIN + DAPPLE_SPAN * dapple);
    }

    pub fn base(self: *const Light) Rgb {
        return @max(MEMORY, self.ambientOf());
    }

    fn carryColour(self: *const Light) Rgb {
        return if (self.sky) |k| mix(CARRY, MOON_CARRY, k.moon) else CARRY;
    }

    /// Before a frame's `emit`s: effect lights last one frame.
    pub fn clearEffects(self: *Light) void {
        self.effect_n = 0;
    }

    pub fn emit(self: *Light, lv: *const grid.Level, source: Emission) void {
        if (!self.options.effect_lights) return;
        const origin = mathx.cellOf(.{ source.at[0], source.at[1] });
        if (self.effect_n == EFFECTS or source.gain <= FAINT or source.radius <= 0 or !lv.isLit(origin)) return;
        const e = &self.effects[self.effect_n];
        self.effect_n += 1;
        e.source = source;
        e.source.radius = @min(source.radius, EFFECT_REACH - 1);
        e.origin = origin;
        @memset(&e.reach, false);
        var cells = grid.Cells.around(origin, @intFromFloat(@ceil(e.source.radius)));
        while (cells.next()) |p| {
            e.reach[e.texel(p).?] = grid.Level.inside(p) and grid.clearLine(lv, origin, p);
        }
    }

    pub fn effectsNear(self: *const Light, c: P) EffectSet {
        var kept = EffectSet.initEmpty();
        const x: f32 = @floatFromInt(c.x);
        const y: f32 = @floatFromInt(c.y);
        for (self.effects[0..self.effect_n], 0..) |*e, i| {
            const s = e.source;
            if (s.at[0] + s.radius <= x or s.at[0] - s.radius >= x + 1 or
                s.at[1] + s.radius <= y or s.at[1] - s.radius >= y + 1 + FACE_H) continue;
            kept.set(i);
        }
        return kept;
    }

    /// `q` is in cells.
    pub fn at(self: *const Light, lv: *const grid.Level, torches: []const TorchIx, q: [2]f32) Rgb {
        const c = mathx.cellOf(q);
        const fade = self.fadeOf(c);
        const ray = self.sunRay();
        const cloud = if (ray != null) self.cloudAt(q) else 1;
        return self.shade(lv, torches, self.effectsNear(c), q, null, self.viewIn(q, &fade), if (ray) |*r| r else null, cloud);
    }

    /// `cloud` is the share of the sky's light the clouds let through, read only with a `ray`.
    pub fn shade(self: *const Light, lv: *const grid.Level, torches: []const TorchIx, effects: EffectSet, q: [2]f32, map_at: ?usize, v: View, ray: ?*const SunRay, cloud: f32) Rgb {
        const sight = v.sight;
        const memory = v.memory;
        if (memory <= FAINT) return @splat(0);
        var view = self.base();
        if (sight > FAINT) {
            const s = Spot.of(lv, q);
            view += self.carryColour() * splat(self.carried(s));
            for (torches) |i| {
                const t = &self.torch[i];
                view += t.colour * splat(t.shine(s));
            }
            if (ray) |r| {
                const facing = sunFacing(r.k, s);
                if (facing > 0 or r.night > 0) {
                    const on = self.sunAt(lv, r, s.x, s.y, s.z);
                    if (facing > 0) view += r.k.key * splat(facing * reaching(on, self.composedAt(map_at, q, cloud)));
                    view *= r.dim(on, cloud);
                }
            }
            if (lv.isLit(mathx.cellOf(q))) {
                var it = effects.iterator(.{});
                while (it.next()) |i| {
                    const e = &self.effects[i];
                    const strength = e.strength(s.x, s.y, s.z);
                    if (strength <= 0) continue;
                    const facing: f32 = switch (s.surface) {
                        .floor => 1,
                        .face, .ceiling => upright(s.surface, e.source.at[0] - s.x, e.source.at[1] - s.y),
                    };
                    view += rgbOf(e.source.col) * splat(strength * facing);
                }
            }
        }
        return remembered(view, sight, memory);
    }

    /// Cells `lo` up to `hi`, and a texel round them for the filter.
    pub fn bake(self: *Light, lv: *const grid.Level, lo: P, hi: P) void {
        var ids: [grid.MAX_TORCHES]TorchIx = undefined;
        const torches = self.near((grid.Box{ .lo = lo, .hi = hi }).grown(1), &ids);
        const t0 = P{ .x = @max(0, lo.x * SUB - 1), .y = @max(0, lo.y * SUB - 1) };
        const t1 = P{ .x = @min(MAP_W, hi.x * SUB + 1), .y = @min(MAP_H, hi.y * SUB + 1) };
        const ray = self.sunRay();
        self.baked = .{ @min(self.baked[0], t0.y), @max(self.baked[1], t1.y) };
        const c0 = P{ .x = @divFloor(t0.x, SUB), .y = @divFloor(t0.y, SUB) };
        if (ray != null) self.cloudsOver(c0, .{ .x = std.math.divCeil(i32, t1.x, SUB) catch unreachable, .y = std.math.divCeil(i32, t1.y, SUB) catch unreachable });
        var c = P{ .x = 0, .y = c0.y };
        while (c.y * SUB < t1.y) : (c.y += 1) {
            c.x = c0.x;
            while (c.x * SUB < t1.x) : (c.x += 1) self.bakeCell(lv, torches, c, t0, t1, ray);
        }
    }

    /// The corners from `lo` to `hi`, both inclusive.
    fn cloudsOver(self: *Light, lo: P, hi: P) void {
        const t = self.t.at();
        var y = lo.y;
        while (y <= hi.y) : (y += 1) {
            var x = lo.x;
            while (x <= hi.x) : (x += 1) self.clouds[cornerAt(.{ .x = x, .y = y })] = clouded(@floatFromInt(x), @floatFromInt(y), t);
        }
        self.clouds_held = .{ .box = .{ .lo = lo, .hi = hi }, .t = t };
    }

    fn cornerAt(p: P) usize {
        return @as(usize, @intCast(p.y)) * CORNERS_W + @as(usize, @intCast(p.x));
    }

    fn cloudAt(self: *const Light, q: [2]f32) f32 {
        const c = mathx.cellOf(q);
        return cloudIn(self.cloudCorners(c), c, q);
    }

    fn cloudCorners(self: *const Light, c: P) [4]f32 {
        const t = self.t.at();
        if (self.clouds_held) |h| {
            if (h.t == t and h.box.holds(c)) return self.heldCorners(c);
        }
        const cx: f32 = @floatFromInt(c.x);
        const cy: f32 = @floatFromInt(c.y);
        return .{
            clouded(cx, cy, t),
            clouded(cx + 1, cy, t),
            clouded(cx, cy + 1, t),
            clouded(cx + 1, cy + 1, t),
        };
    }

    fn heldCorners(self: *const Light, c: P) [4]f32 {
        const k = cornerAt(c);
        return .{ self.clouds[k], self.clouds[k + 1], self.clouds[k + CORNERS_W], self.clouds[k + CORNERS_W + 1] };
    }

    fn bakeCell(self: *Light, lv: *const grid.Level, torches: []const TorchIx, c: P, t0: P, t1: P, ray: ?SunRay) void {
        const fade = self.fadeOf(c);
        const dark = if (fade.flat) |v| v == 0 else false;
        const x0 = @max(t0.x, c.x * SUB);
        const x1 = @min(t1.x, (c.x + 1) * SUB);
        const y0 = @max(t0.y, c.y * SUB);
        const y1 = @min(t1.y, (c.y + 1) * SUB);
        if (dark) {
            var y = y0;
            while (y < y1) : (y += 1) {
                const first: usize = @intCast(y * MAP_W + x0);
                const last: usize = @intCast(y * MAP_W + x1);
                inline for (comptime std.enums.values(Layer)) |k| @memset(self.texels.getPtr(k)[first..last], UNSEEN.get(k));
            }
            return;
        }
        const corners: [4]f32 = if (ray != null) self.heldCorners(c) else @splat(1);

        const patch = Patch.of(self, c);
        const ground = self.groundAt(c);
        const effects = self.effectsNear(c);
        var wet = false;
        var neighbours = grid.Cells.around(c, 1);
        while (neighbours.next()) |p| {
            if (look.reflects(lv.at(p))) {
                wet = true;
                break;
            }
        }
        const map = self.texels.getPtr(.map);
        const glints = self.texels.getPtr(.glints);
        const fog = self.texels.getPtr(.fog);
        var ty = y0;
        while (ty < y1) : (ty += 1) {
            var tx = x0;
            while (tx < x1) : (tx += 1) {
                const i: usize = @intCast(ty * MAP_W + tx);
                glints[i] = UNSEEN.get(.glints);
                const q = texelCentre(@intCast(tx), @intCast(ty));
                const v = viewOf(sightOf(&patch, ground, q[0], q[1]), q, &fade);
                fog[i] = look.fade(rl.Color.white, 1 - v.memory);
                const cloud = if (ray != null) cloudIn(corners, c, q) else 1;
                map[i] = texelOf(self.shade(lv, torches, effects, q, i, v, if (ray) |*r| r else null, cloud), v.lit);
                if (self.options.water_glints and wet and v.lit > FAINT and lv.isLit(c))
                    glints[i] = colourOf(self.waterGlint(torches, effects, q, i, if (ray) |*r| r else null, cloud), 1);
            }
        }
    }

    pub fn waterGlint(self: *const Light, torches: []const TorchIx, effects: EffectSet, q: [2]f32, map_at: ?usize, ray: ?*const SunRay, cloud: f32) Rgb {
        var gleam: Rgb = @splat(0);
        if (ray) |r| {
            const on = self.sunAt(&self.scratch, r, q[0], q[1], 0);
            gleam += r.k.key * splat(r.glint * reaching(on, self.composedAt(map_at, q, cloud)) * SUN_GLINT);
        }
        if (self.carryToward(q[0], q[1], true)) |f|
            gleam += self.carryColour() * splat(smoothSpecular(.{ f.at[0] - q[0], f.at[1] - q[1], BODY_Z }, GLINT_POWER) * f.k * CARRY_GLINT);
        for (torches) |i| {
            const t = &self.torch[i];
            const r = t.toward(q[0], q[1], 0) orelse continue;
            gleam += t.colour * splat(smoothSpecular(r.d, GLINT_POWER) * r.k * TORCH_GLINT);
        }
        var it = effects.iterator(.{});
        while (it.next()) |i| {
            const e = &self.effects[i];
            const s = e.source;
            const k = e.strength(q[0], q[1], 0);
            if (k <= FAINT) continue;
            gleam += rgbOf(s.col) * splat(smoothSpecular(offset(s.at, q[0], q[1], 0), GLINT_POWER) * k * EFFECT_GLINT);
        }
        return gleam;
    }

    const View = struct { sight: f32, memory: f32, lit: f32 };

    pub fn viewAt(self: *const Light, q: [2]f32) View {
        return self.viewIn(q, &self.fadeOf(mathx.cellOf(q)));
    }

    fn viewIn(self: *const Light, q: [2]f32, fade: *const Fade) View {
        return viewOf(self.sightAt(q[0], q[1]), q, fade);
    }

    fn viewOf(sight: f32, q: [2]f32, fade: *const Fade) View {
        const memory = fade.at(q[0], q[1], sight);
        return .{ .sight = sight, .memory = memory, .lit = sight * memory };
    }

    /// Ground centre in cells; self-carried light is flat, visibility follows the ground.
    pub fn onBody(self: *const Light, centre: [2]f32, carrier: bool) Shine {
        return self.bodyLight(centre, carrier, true);
    }

    pub fn onCaster(self: *const Light, centre: [2]f32, carrier: bool) Shine {
        return self.bodyLight(centre, carrier, false);
    }

    fn bodyLight(self: *const Light, centre: [2]f32, carrier: bool, fogged: bool) Shine {
        const v = if (fogged) self.viewAt(centre) else View{ .sight = 1, .memory = 1, .lit = 1 };
        const lit = v.lit;
        var s = Shine{ .sight = lit };
        const night: Rgb = if (self.sunRay()) |ray| self.sunOnBody(&s, &ray, centre, lit) else splat(1);
        s.ambient = remembered(self.base() * night, v.sight, v.memory);
        s.floor = remembered((self.base() - self.ambientOf()) * night, v.sight, v.memory);
        if (self.carryToward(centre[0], centre[1], fogged)) |f| {
            const k = f.k * lit;
            if (carrier) {
                s.ambient += self.carryColour() * splat(k) * night;
            } else if (k > FAINT) {
                s.add(.{ .drawn = f.at, .ground = f.at, .colour = self.carryColour() * splat(k), .casts = false });
            }
        }
        for (self.torch[0..self.torch_n]) |*t| {
            const r = t.toward(centre[0], centre[1], BODY_Z) orelse continue;
            const k = r.k * lit;
            if (k <= FAINT) continue;
            const fl = t.flame();
            s.add(.{ .drawn = t.drawn(), .ground = .{ fl[0], fl[1] }, .colour = t.colour * splat(k), .casts = true });
        }
        for (s.lamp[0..s.n]) |*l| l.colour *= night;
        for (self.effects[0..self.effect_n]) |*e| {
            const k = e.strength(centre[0], centre[1], BODY_Z) * lit;
            if (k <= FAINT) continue;
            const p = e.source.at;
            s.add(.{ .drawn = e.source.drawn(), .ground = .{ p[0], p[1] }, .colour = rgbOf(e.source.col) * splat(k), .casts = true });
        }
        return s;
    }

    fn sunOnBody(self: *const Light, s: *Shine, ray: *const SunRay, centre: [2]f32, lit: f32) Rgb {
        const k = ray.k;
        const toward = ray.u;
        const sun = self.sunAt(&self.scratch, ray, centre[0], centre[1], BODY_Z);
        const cloud = self.cloudAt(centre);
        const on = reaching(sun, self.composedAt(null, centre, cloud));
        if (lit > 0) s.add(.{
            .drawn = .{ centre[0] + toward[0] * SUN_LAMP_D, centre[1] + toward[1] * SUN_LAMP_D },
            .ground = .{ centre[0] + toward[0], centre[1] + toward[1] },
            .colour = k.key * splat(lit * on),
            .casts = !sky.upright(ray.flat),
            .sky = .{ .reach = k.reach(), .depth = skyDepth(k, sun * cloud) * lit, .shade = ray.shade },
        });
        return ray.dim(sun, cloud);
    }

    /// A flame hangs on its wall's south face, so a wall seen only from behind shows none, and burns live only while that face's floor is in sight.
    pub fn flames(self: *const Light, lv: *const grid.Level, out: *[grid.MAX_TORCHES]Flame) []const Flame {
        var n: usize = 0;
        for (self.torch[0..self.torch_n]) |*t| {
            if (!self.remembers(lv, t.wall) or !self.remembers(lv, t.floor())) continue;
            const d = t.drawn();
            const v = self.viewAt(d);
            const face = self.viewAt(mathx.centre(t.floor()));
            out[n] = .{ .at = d, .foot = t.flame()[1], .glow = t.glow, .lit = @min(v.lit, face.lit), .memory = v.memory };
            n += 1;
        }
        return out[0..n];
    }

    /// Needs a live GL context.
    pub fn load(self: *Light) void {
        self.gpu = light_gpu.Gpu.load();
    }

    pub fn syncFigures(self: *Light, figures: *const [look.FIGURES]?rl.Texture2D) void {
        self.gpu.syncFigures(figures);
    }

    pub fn clearFigures(self: *Light) void {
        self.gpu.syncFigures(&light_gpu.NO_FIGURES);
    }

    pub fn unload(self: *Light) void {
        self.gpu.unload();
        self.gpu = .{};
    }

    /// `ox, oy` is where the map's top-left corner lands on screen.
    pub fn drawMap(self: *Light, ox: i32, oy: i32, cell: i32) void {
        const tex = self.mapTexture() orelse return;
        raster.beginBlend(rl.gl.rl_dst_color, rl.gl.rl_src_color, rl.gl.rl_func_add);
        raster.overFloor(tex, ox, oy, cell);
        rl.endBlendMode();
        if (self.gpu.layers.get(.fog)) |fog| {
            rl.beginBlendMode(.additive);
            raster.stretch(fog, raster.floorRect(ox, oy, cell), look.FOG);
            rl.endBlendMode();
        }
    }

    pub fn mapTexture(self: *Light) ?rl.Texture2D {
        self.uploadMap();
        return self.gpu.layers.get(.map);
    }

    pub fn glintTexture(self: *Light) ?rl.Texture2D {
        self.uploadMap();
        return self.gpu.layers.get(.glints);
    }

    pub fn uploadMap(self: *Light) void {
        if (self.gpu.layers.get(.map) == null) return;
        const from, const to = self.baked;
        if (to > from) {
            const rect = raster.rect(0, from, MAP_W, to - from);
            for (std.enums.values(Layer)) |k| {
                if (self.gpu.layers.get(k)) |t| rl.updateTextureRec(t, rect, &self.texels.getPtr(k)[@intCast(from * MAP_W)]);
            }
        }
        self.baked = NONE_BAKED;
    }

    /// `centre` is its middle, cells; `flash` is how far toward `FLASH_RGB` it is drawn.
    pub fn drawBody(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: *const Shine, flash: f32, fade_bounds: [2]f32) void {
        const size = raster.sizeOf(tex);
        const w, const h = size;
        const src = raster.rect(0, 0, if (left) -tex.width else tex.width, tex.height);
        const normals = self.gpu.art(tex).normals;
        const sh = self.gpu.body;
        if (!self.options.body_lighting or sh == null or normals == null) {
            const fading = self.beginMirrorFade(fade_bounds);
            defer if (fading) rl.endShaderMode();
            raster.blit(tex, src, dest, s.drawn(rl.Color.white, flash));
            return;
        }
        var pos: [BODY_LIGHTS][3]f32 = undefined;
        var col: [BODY_LIGHTS][3]f32 = undefined;
        for (s.lamp[0..s.n], 0..) |l, i| {
            pos[i] = .{ (l.drawn[0] - centre[0]) * w, (l.drawn[1] - centre[1]) * h, BODY_LIGHT_Z };
            col[i] = l.colour;
        }
        const flip: f32 = if (left) -1 else 1;
        const ambient: [3]f32 = s.ambient;
        const emission: [3]f32 = s.emission * splat(s.sight);
        const n: i32 = @intCast(s.n);
        const b = sh.?;
        rl.beginShaderMode(b.shader);
        defer rl.endShaderMode();
        shaders.setUniform(b.shader, b.size, size);
        shaders.setUniform(b.shader, b.flip, flip);
        shaders.setUniform(b.shader, b.ambient, ambient);
        shaders.setUniform(b.shader, b.emission, emission);
        shaders.setUniform(b.shader, b.count, n);
        shaders.setUniform(b.shader, b.flash, flash);
        shaders.setUniform(b.shader, b.fade_bounds, fade_bounds);
        rl.setShaderValueTexture(b.shader, b.normals, normals.?);
        if (s.n > 0) {
            shaders.setUniforms(b.shader, b.lpos, &pos, n);
            shaders.setUniforms(b.shader, b.lcol, &col, n);
        }
        raster.blit(tex, src, dest, rl.Color.white);
        rl.gl.rlDrawRenderBatchActive();
    }

    pub fn footY(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle) f32 {
        return dest.y + artY(tex, dest, self.gpu.art(tex).foot);
    }

    pub fn topY(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle) f32 {
        return dest.y + artY(tex, dest, self.gpu.art(tex).top);
    }

    /// Screen pixels below `dest`'s top that texel row `row` of `tex` lands.
    pub fn artY(tex: rl.Texture2D, dest: rl.Rectangle, row: f32) f32 {
        return row * dest.height / @as(f32, @floatFromInt(tex.height));
    }

    pub fn beginMirrorFade(self: *const Light, bounds: [2]f32) bool {
        if (bounds[0] >= bounds[1]) return false;
        const s = self.gpu.mirror_fade orelse return false;
        rl.beginShaderMode(s.shader);
        shaders.setUniform(s.shader, s.fade_bounds, bounds);
        return true;
    }

    pub const beginShadows = shadow.beginShadows;
    pub const endShadows = shadow.endShadows;
    pub const drawShadows = shadow.drawShadows;
    pub const drawCanopy = shadow.drawCanopy;
    pub const drawForestShadows = shadow.drawForestShadows;

    pub fn drawGlows(self: *const Light, flames_: []const Flame, ox: f32, oy: f32, cell: f32) void {
        const g = self.gpu.glow orelse return;
        rl.beginBlendMode(.additive);
        defer rl.endBlendMode();
        for (flames_) |f| {
            if (!f.live()) continue;
            const x = ox + f.at[0] * cell;
            const y = oy + f.at[1] * cell;
            glowAt(g, x, y, cell * GLOW_HALO, cell * GLOW_HALO, colourOf(GLOW_TINT, GLOW_HALO_A * f.glow * f.lit));
            glowAt(g, x, y, cell * GLOW_CORE, cell * GLOW_CORE, colourOf(GLOW_TINT, GLOW_CORE_A * f.glow * f.lit));
        }
    }
};

pub fn glowAt(g: rl.Texture2D, x: f32, y: f32, rx: f32, ry: f32, c: rl.Color) void {
    raster.stretch(g, .{ .x = x - rx, .y = y - ry, .width = rx * 2, .height = ry * 2 }, c);
}

/// The body shader's flash, for what is drawn without it.
pub fn flashed(c: rl.Color, k: f32) rl.Color {
    const from = rgbOf(c);
    return recolour(c, mix(from, FLASH_RGB, k));
}

/// The edges repeat their own cell. `out` may be `src`.
fn blur121(src: *const [grid.CELLS]f32, tmp: *[grid.CELLS]f32, out: *[grid.CELLS]f32) void {
    const w = grid.COLS;
    const h = grid.ROWS;
    for (0..h) |y| {
        const s = src[y * w ..][0..w];
        const t = tmp[y * w ..][0..w];
        t[0] = (s[0] + s[0] * 2 + s[1]) * 0.25;
        for (t[1 .. w - 1], s[0 .. w - 2], s[1 .. w - 1], s[2..w]) |*v, l, m, r| v.* = (l + m * 2 + r) * 0.25;
        t[w - 1] = (s[w - 2] + s[w - 1] * 2 + s[w - 1]) * 0.25;
    }
    for (0..h) |y| {
        const u = tmp[(if (y == 0) 0 else y - 1) * w ..][0..w];
        const m = tmp[y * w ..][0..w];
        const d = tmp[@min(h - 1, y + 1) * w ..][0..w];
        for (out[y * w ..][0..w], u, m, d) |*v, a, b, c| v.* = (a + b * 2 + c) * 0.25;
    }
}
