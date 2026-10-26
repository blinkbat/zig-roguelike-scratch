const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const sky = @import("sky.zig");
const lume = @import("../map/lume.zig");
const actor = @import("../play/actor.zig");
const visibility = @import("light_visibility.zig");

pub const P = mathx.P;
pub const Rgb = sky.Rgb;
pub const mix = sky.mix;

/// Light-map texels per cell side.
pub const SUB: i32 = 4;
pub const MAP_W: i32 = grid.W * SUB;
pub const MAP_H: i32 = grid.H * SUB;
pub const NONE_BAKED = [2]i32{ MAP_H, 0 };
pub const TEXELS: usize = @intCast(MAP_W * MAP_H);
pub const Layer = enum { map, glints, fog };
/// Each layer's texel where nothing is remembered.
pub const UNSEEN = std.EnumArray(Layer, rl.Color).init(.{ .map = rl.Color.blank, .glints = rl.Color.blank, .fog = rl.Color.white });
/// DST_COLOR/SRC_COLOR blending doubles the stored light.
pub const OVERBRIGHT: f32 = 2.0;

pub const REACH: i32 = lume.TORCH_REACH;
pub const REACH2: f32 = @floatFromInt(REACH * REACH);
pub const SPAN: i32 = grid.Cells.span(REACH);
/// Cells: the inverse square's reference distance.
pub const FALLOFF_D0: f32 = 2.5;
/// Wall height in cells; the brick face below `FACE_FROM` is foreshortened.
pub const WALL_H: f32 = 1.0;
pub const FACE_FROM: f32 = 1 - @as(f32, @floatFromInt(look.WALL_FACE_PX)) / @as(f32, @floatFromInt(look.SPRITE_PX));
pub const FACE_H: f32 = 1 - FACE_FROM;
pub const FLAME_Z: f32 = 0.6;
/// Flame offset from its wall, preventing edge-on lighting of neighbouring bricks.
pub const STANDOFF: f32 = 0.3;
pub const FLOOR_WRAP: f32 = 1.0;
pub const FACE_WRAP: f32 = 0.35;
pub const FACE_GAIN: f32 = 1.25;
pub const CEILING_CATCH: f32 = 0.2;
pub const BODY_Z: f32 = 0.4;

pub const CARRY: Rgb = .{ 0.92, 0.88, 0.80 };
pub const MOON_CARRY: Rgb = .{ 0.52, 0.68, 1.0 };
/// A cell past what the hero's light lets it see, so its glow fades out on the edge of sight.
pub const CARRY_R: f32 = @floatFromInt(actor.row(actor.HERO).light + 1);
pub const CARRY_FADE: f32 = 0.3;
pub const CARRY_CEILING: f32 = 0.7;
pub const CARRY_FACE_WRAP: f32 = 0.6;

/// The light remembered terrain is drawn under, after Brogue's memory colour.
pub const MEMORY = rgbOf(look.rgb(0x33385c));
pub const FLAME: Rgb = .{ 1.30, 0.80, 0.40 };
/// Per channel, the power the flicker is raised to, so a flame whitens as it flares.
pub const FLAME_SHIFT: Rgb = .{ 1.0, 1.6, 2.4 };
pub const FAINT: f32 = 0.002;
pub const TINT_DIRECT: f32 = 0.6;
pub const VOID_REACH = visibility.VOID_REACH;
pub const CORNERS_W = grid.CORNERS_W;
pub const CORNERS_H = grid.CORNERS_H;
pub const FLICKER: f32 = 0.14;
pub const FLICKER_BANDS = [_]struct { hz: f32, weight: f32 }{
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
pub const BODY_LIGHT_Z: f32 = 40.0;
/// Darkest ground tint; overlapping shadows take the channelwise minimum.
pub const SHADE_RGB = Rgb{ 0.42, 0.45, 0.54 };
/// Darkens whatever lights the ground, the hero's own light too.
pub const MOON_SHADE_RGB = Rgb{ 0.34, 0.40, 0.62 };
pub const SHADOW_MAX: f32 = 0.85;
/// A light with this share of all that reaches a body casts its darkest shadow; under it the shadow eases out to none.
pub const SHADOW_FULL: f32 = 0.5;
pub const SHADOW_TAPS: i32 = 3;
pub const GLOW_CORE: f32 = 0.45;
pub const GLOW_HALO: f32 = 2.6;
pub const GLOW_CORE_A: f32 = 0.85;
pub const GLOW_HALO_A: f32 = 0.2;
pub const GLOW_TINT: Rgb = .{ 1.0, 0.52, 0.22 };
/// Cells between ray samples; softness is a fraction of caster height and a cell distance from round edges.
pub const SUN_STEP: f32 = 0.1;
pub const SUN_SOFT: f32 = 0.7;
pub const SUN_EDGE: f32 = 0.2;
/// Of the sky's light, how much a sun shadow takes away at its darkest, and how dark a body's sun shadow is.
pub const SUN_SHADE: f32 = 0.45;
pub const SUN_SHADOW_A: f32 = 0.4;
pub const SKY_SHADOW = SHADOW_MAX * SUN_SHADOW_A;
/// Cells to the side the sun lights a body from, as the body shader takes a lamp.
pub const SUN_LAMP_D: f32 = 3;

/// Height and optional circular radius in cells; null radius fills a square cell.
pub const Caster = struct { h: f32, r: ?f32 = null };

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

pub const CAST_TALLEST: f32 = blk: {
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
pub const GROUND_WRAP: f32 = 0.5;
/// Cloud shadows: cells across, cells a second drifting, share of sky covered, edge softness, share of the sun taken.
pub const CLOUD_SCALE: f32 = 14;
pub const CLOUD_DRIFT = [2]f32{ 0.35, 0.12 };
pub const CLOUD_COVER: f32 = 0.52;
pub const CLOUD_SOFT: f32 = 0.3;
pub const CLOUD_DEPTH: f32 = 0.18;
pub const CLOUD_OCTAVES = [2]f32{ 0.65, 0.35 };
pub const CLOUD_LACUNARITY: f32 = 2.3;

/// What of the sun a cloud's shadow drifting over a point at `t` seconds leaves it.
pub fn clouded(x: f32, y: f32, t: f32) f32 {
    const u = x / CLOUD_SCALE + t * CLOUD_DRIFT[0] / CLOUD_SCALE;
    const v = y / CLOUD_SCALE + t * CLOUD_DRIFT[1] / CLOUD_SCALE;
    const n = value2(u, v) * CLOUD_OCTAVES[0] + value2(u * CLOUD_LACUNARITY + 17, v * CLOUD_LACUNARITY - 9) * CLOUD_OCTAVES[1];
    const edge = 1 - CLOUD_COVER;
    const cover = mathx.smoothstep(edge - CLOUD_SOFT / 2, edge + CLOUD_SOFT / 2, n);
    return 1 - CLOUD_DEPTH * cover;
}

pub fn value2(u: f32, v: f32) f32 {
    return mathx.valueNoise({}, hash2, u, v);
}

pub fn hash2(_: void, x: i32, y: i32) f32 {
    return hash(x *% 73856093 ^ y *% 19349663, 0xC10D);
}

pub fn shaded(sun: f32) f32 {
    return 1 - SUN_SHADE * (1 - sun);
}

pub fn reaching(sun: f32, cloud: f32) f32 {
    return shaded(sun) * cloud;
}

pub fn faceCatch(cos: f32) f32 {
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

    pub fn dim(ray: SunRay, sun: f32, cloud: f32) Rgb {
        return mix(splat(1), ray.shade, (1 - sun) * cloud * ray.night);
    }

    /// Cells along the ground from a point `z` up to where the ray has risen over everything that casts.
    pub fn far(ray: SunRay, z: f32) f32 {
        return @max(0, CAST_TALLEST - z) / ray.rise;
    }
};

pub fn cloudIn(corners: [4]f32, c: P, q: [2]f32) f32 {
    const u = q[0] - @as(f32, @floatFromInt(c.x));
    const v = q[1] - @as(f32, @floatFromInt(c.y));
    return mathx.bilerp(corners, u, v);
}

/// Ignores what stands in the way.
pub fn sunFacing(sk: sky.Sky, s: Spot) f32 {
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

pub fn offset(a: [3]f32, x: f32, y: f32, z: f32) [3]f32 {
    return .{ a[0] - x, a[1] - y, a[2] - z };
}

pub fn len2(d: [3]f32) f32 {
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

pub fn faceZ(fy: f32) f32 {
    return (1 - fy) / FACE_H * WALL_H;
}

pub fn faceY(top: f32, z: f32) f32 {
    return top + 1 - z / WALL_H * FACE_H;
}

pub const TorchIx = std.math.IntFittingRange(0, grid.MAX_TORCHES - 1);

pub const Torch = struct {
    wall: P,
    /// 1 where the flame's light gets to, over the box of cells centred on the floor below the flame.
    reach: [grid.Cells.square(REACH)]f32,
    /// Sight-blocking mask for interpolation; prevents walls passing light onward.
    open: [grid.Cells.square(REACH)]f32,
    seed: u32,
    colour: Rgb = FLAME,
    glow: f32 = 1,

    pub fn floor(t: *const Torch) P {
        return lume.torchFloor(t.wall);
    }

    /// On the ground plane.
    pub fn flame(t: *const Torch) [3]f32 {
        return .{ mathx.centre(t.wall)[0], @as(f32, @floatFromInt(t.floor().y)) + STANDOFF, FLAME_Z };
    }

    pub fn drawn(t: *const Torch) [2]f32 {
        return .{ mathx.centre(t.wall)[0], faceY(@floatFromInt(t.wall.y), FLAME_Z) };
    }

    pub fn box(t: *const Torch) grid.Box {
        return grid.Box.around(t.floor(), REACH);
    }

    pub fn corner(t: *const Torch) P {
        return t.box().lo;
    }

    pub fn texel(t: *const Torch, p: P) usize {
        return t.box().slot(p).?;
    }

    pub fn reached(t: *const Torch, x: f32, y: f32) f32 {
        const uv = visibility.fieldUv(t.corner(), x, y);
        return visibility.occluded(&t.reach, &t.open, SPAN, SPAN, uv[0], uv[1]);
    }

    /// The flame's offset from a point and how much of it reaches there, fallen off and occluded; null out of reach.
    pub fn toward(t: *const Torch, x: f32, y: f32, z: f32) ?struct { d: [3]f32, d2: f32, k: f32 } {
        const f = t.flame();
        const d = offset(f, x, y, z);
        const d2 = len2(d);
        if (d2 >= REACH2) return null;
        const o = t.reached(x, y);
        if (o <= 0) return null;
        return .{ .d = d, .d2 = d2, .k = falloff(d2) * o };
    }

    pub fn shine(t: *const Torch, s: Spot) f32 {
        const r = t.toward(s.x, s.y, s.z) orelse return 0;
        const facing = switch (s.surface) {
            .floor => wrapped(r.d[2] / @sqrt(r.d2), FLOOR_WRAP),
            .face, .ceiling => upright(s.surface, r.d[0], r.d[1]),
        };
        return r.k * facing;
    }
};

pub fn upright(surface: Surface, dx: f32, dy: f32) f32 {
    return switch (surface) {
        .floor => unreachable,
        .face => faceCatch(faceCos(dy, mathx.len(dx, dy))),
        .ceiling => CEILING_CATCH,
    };
}

/// From the water toward the viewer, who looks down at 45 degrees from the south.
pub const VIEWER: Rgb = .{ 0, std.math.sqrt1_2, std.math.sqrt1_2 };
pub const SUN_GLINT_POWER: u32 = 24;
pub const GLINT_POWER: u32 = 80;
pub const SUN_GLINT: f32 = 0.05;
pub const CARRY_GLINT: f32 = 0.08;
pub const TORCH_GLINT: f32 = 0.12;
pub const EFFECT_GLINT: f32 = 0.11;

pub fn smoothSpecular(toward: [3]f32, comptime power: u32) f32 {
    const d: Rgb = toward;
    const len = sky.norm(d);
    if (len <= 1e-5 or d[2] <= 0) return 0;
    const half = d / splat(len) + VIEWER;
    const h = sky.unit(half);
    return mathx.powi(@max(0, h[2]), power);
}

pub fn remembered(view: Rgb, sight: f32, memory: f32) Rgb {
    return mix(MEMORY, view, sight) * splat(memory);
}

/// Windowed inverse square: exactly nothing at `REACH`.
pub fn falloff(d2: f32) f32 {
    const r = d2 / REACH2;
    const w = std.math.clamp(1 - r * r, 0, 1);
    return w * w / (1 + d2 / (FALLOFF_D0 * FALLOFF_D0));
}

pub fn carryFade(d: f32) f32 {
    return @max(0, @min(carryAlong(d), CARRY_EDGE * (CARRY_R - d)));
}

pub fn carryAlong(d: f32) f32 {
    return 1 - (1 - CARRY_FADE) * d / CARRY_R;
}

pub const CARRY_EDGE = carryAlong(CARRY_R - 1);

pub fn wrapped(cos: f32, wrap: f32) f32 {
    return @max(0, (cos + wrap) / (1 + wrap));
}

pub const texel = visibility.texel;
pub const mask = visibility.mask;

pub fn hash(n: i32, seed: u32) f32 {
    var x: u32 = @bitCast(n);
    x = (x ^ seed) *% 0x9E3779B1;
    x ^= x >> 15;
    x *%= 0x85EBCA77;
    x ^= x >> 13;
    return @as(f32, @floatFromInt(x >> 8)) / @as(f32, 1 << 24);
}

pub fn noise(t: f32, seed: u32) f32 {
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

pub fn knee(c: Rgb) Rgb {
    var out = c;
    for (0..3) |i| {
        if (c[i] > KNEE) out[i] = KNEE * @sqrt(c[i] / KNEE);
    }
    return out;
}

pub const smooth = mathx.smooth;

/// The cosine a light `dy` south of a south face and `flat` from it along the ground strikes it at.
pub fn faceCos(dy: f32, flat: f32) f32 {
    return dy / @max(flat, FACE_EPS);
}

pub const FACE_EPS: f32 = 1e-2;

pub const splat = sky.splat;

pub const rgbOf = look.rgbOf;

pub fn colourOf(c: Rgb, a: f32) rl.Color {
    const k = @max(splat(0), @min(splat(1), c)) * splat(255) + splat(0.5);
    return .{ .r = @intFromFloat(k[0]), .g = @intFromFloat(k[1]), .b = @intFromFloat(k[2]), .a = @intFromFloat(std.math.clamp(a, 0, 1) * 255 + 0.5) };
}

pub fn texelOf(c: Rgb, sight: f32) rl.Color {
    return colourOf(knee(c) / splat(OVERBRIGHT), sight);
}

pub const lum = sky.luma;

/// Cells: `drawn` as on screen, `ground` where it stands.
pub const Lamp = struct {
    drawn: [2]f32,
    ground: [2]f32,
    colour: Rgb,
    /// The carried light casts no body's shadow, as it casts none of its carrier's.
    casts: bool,
    sky: ?SkyCast = null,
};

/// Distant sky shadow: `reach` body heights, `depth` intensity in `shade`.
pub const SkyCast = struct { reach: f32, depth: f32, shade: Rgb };

pub fn skyDepth(k: sky.Sky, lit: f32) f32 {
    const key = lum(k.key) * lit;
    return SKY_SHADOW * castShare(key, key + lum(k.ambient));
}

pub fn castShare(own: f32, all: f32) f32 {
    return smooth(own / @max(all, 1e-6) / SHADOW_FULL);
}

pub fn skyShade(k: sky.Sky) Rgb {
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

pub fn recolour(c: rl.Color, rgb: Rgb) rl.Color {
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
pub const COMPOSED_KEY: Rgb = .{ 1.035, 1.005, 0.96 };
pub const COMPOSED_AMBIENT: Rgb = .{ 0.94, 0.98, 1.04 };
/// Composed sun through cloud: lifted in the open, deeper under cloud, dappled under crowns.
pub const PATCH_LIFT: f32 = 1.045;
pub const PATCH_CLOUD: f32 = 1.6;
pub const DAPPLE_WAVE = [3]f32{ 2.1, 1.6, 1.2 };
pub const DAPPLE_MIN: f32 = 0.07;
pub const DAPPLE_SPAN: f32 = 0.10;
/// Crowns within this many cells shade a cell's sun, each by this much over one plus its squared distance.
pub const DAPPLE_REACH = 2;
pub const DAPPLE_COVER: f32 = 0.3;

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
pub const EFFECT_REACH = 5;
pub const EFFECT_SPAN: comptime_int = grid.Cells.span(EFFECT_REACH);

pub const Effect = struct {
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

    pub fn texel(e: *const Effect, p: P) ?usize {
        return e.box().slot(p);
    }
};

pub const Options = struct {
    shadows: bool = true,
    body_lighting: bool = true,
    effect_lights: bool = true,
    water_glints: bool = true,
};

/// The body shader's flash, for what is drawn without it.
pub fn flashed(c: rl.Color, k: f32) rl.Color {
    const from = rgbOf(c);
    return recolour(c, mix(from, FLASH_RGB, k));
}
