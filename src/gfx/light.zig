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
pub const Rgb = sky.Rgb;
const mix = sky.mix;

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
const FACE_FROM: f32 = 1 - @as(f32, @floatFromInt(look.WALL_FACE_PX)) / @as(f32, @floatFromInt(look.SPRITE_PX));
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
/// What a shadow at its darkest leaves of the ground, a little cool; overlaps keep the darker (Photoshop's Darken).
const SHADE_RGB = Rgb{ 0.42, 0.45, 0.54 };
/// Darkens whatever lights the ground, the archer's own light too.
const MOON_SHADE_RGB = Rgb{ 0.34, 0.40, 0.62 };
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
const SHADOW_NEAR: f32 = 0.5;
/// Texels of blur room round a shadow's silhouette.
const SHADOW_PAD: f32 = 6;
/// Texels between the shadow shader's blur taps, at its tip and at its foot.
const SHADOW_SOFT_TIP: f32 = 2.0;
const SHADOW_SOFT_FOOT: f32 = 0.6;
const SHADOW_TAPS: i32 = 3;
/// Of a shadow's length, its run up or down the screen: under `THIN_HI` its silhouette gives way to a soft streak, wholly by `THIN_LO`.
const THIN_LO: f32 = 0.06;
const THIN_HI: f32 = 0.28;
/// The streak's half-width, a share of the sprite's width, and its darkness against the silhouette's.
const STREAK_W: f32 = 0.3;
const STREAK_A: f32 = 0.8;
/// Of the streak's length, how much lies behind the feet, where it eases in.
const STREAK_FOOT: f32 = 0.1;
/// How sharply it fades from the feet to the tip: 1 evenly.
const STREAK_TAIL: f32 = 1.5;
const STREAK_PX = [2]i32{ 64, 16 };

const CONTACT_W: f32 = 0.62;
const CONTACT_H: f32 = 0.2;
const CONTACT_A: f32 = 0.7;
const GLOW_PX: i32 = 64;
const GLOW_CORE: f32 = 0.45;
const GLOW_HALO: f32 = 2.6;
const GLOW_CORE_A: f32 = 0.85;
const GLOW_HALO_A: f32 = 0.2;
const GLOW_TINT: Rgb = .{ 1.0, 0.52, 0.22 };
/// Cells between a sun ray's samples; a shadow eases in over `SUN_SOFT` of its caster's height under its top, and `SUN_EDGE` cells in from a round one's edge.
const SUN_STEP: f32 = 0.1;
const SUN_SOFT: f32 = 0.5;
const SUN_EDGE: f32 = 0.2;
/// Of the sky's light, how much a sun shadow takes away at its darkest, and how dark a body's sun shadow is.
const SUN_SHADE: f32 = 0.55;
const SUN_SHADOW_A: f32 = 0.4;
const SKY_SHADOW = SHADOW_MAX * SUN_SHADOW_A;
/// A tree's shadow: canopy radius (of sprite width), squash, place along a full-height shadow, stretch per height it runs, darkness; trunk contact of a body's.
const CANOPY_R: f32 = 0.55;
const CANOPY_SQUASH: f32 = 0.7;
const CANOPY_AT: f32 = 0.45;
const CANOPY_STRETCH: f32 = 0.5;
const CANOPY_A: f32 = 1.6;
/// Cells from a cell-tall caster its longest shadow, sky's or torch's, silhouette or canopy, reaches.
pub const CAST_REACH: f32 = blk: {
    const l = @max(sky.REACH_MAX, SHADOW_LEN_HI);
    break :blk @max(l, CANOPY_AT * l + CANOPY_R * (1 + l * CANOPY_STRETCH));
};
const TRUNK_OF: f32 = 0.6;
/// Cells to the side the sun lights a body from, as the body shader takes a lamp.
const SUN_LAMP_D: f32 = 3;

/// What stands in the sun's way: cells tall, and how far from its middle a round one reaches; square fills its cell.
const Caster = struct { h: f32, r: ?f32 = null };

const CASTERS = std.EnumArray(grid.Tile, ?Caster).initDefault(@as(?Caster, null), .{
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
fn sunlit(lv: *const grid.Level, ray: SunRay, x: f32, y: f32, z: f32) f32 {
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
        const k = CASTERS.get(lv.at(c)) orelse continue;
        var over = (k.h - z - t * rise) / (SUN_SOFT * k.h);
        if (k.r) |r| over = @min(over, (r - offMiddle(c, .{ px, py })) / SUN_EDGE);
        if (over <= 0) continue;
        lit = @min(lit, 1 - smooth(@min(over, 1)));
        if (lit <= 0) return 0;
    }
    return lit;
}

/// Ground under a low sun keeps this much of a high one's light, so morning and evening stay warm and not dim.
const GROUND_WRAP: f32 = 0.5;
/// Cloud shadows: cells across, cells a second drifting, share of sky covered, edge softness, share of the sun taken.
const CLOUD_SCALE: f32 = 14;
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

/// Worked out once per bake rather than per texel.
const SunRay = struct {
    k: sky.Sky,
    flat: f32,
    u: [2]f32,
    /// Cells up per cell along the ground toward the light.
    rise: f32,
    /// How deep the moon's shadows darken the ground, whatever lights it, and in what.
    night: f32,
    shade: Rgb,

    fn of(k: sky.Sky) SunRay {
        const flat = k.flat();
        return .{
            .k = k,
            .flat = flat,
            .u = k.across(),
            .rise = k.rise(),
            .night = k.moon * skyDepth(k, 1),
            .shade = skyShade(k),
        };
    }

    /// What a moon shadow leaves of all the light at a point `sun` of the ray reaches, under `cloud`.
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

const Sun = struct { ray: SunRay, cloud: f32 };

/// Ignores what stands in the way.
fn sunFacing(sk: sky.Sky, s: Spot) f32 {
    return switch (s.surface) {
        .floor, .ceiling => wrapped(sk.dir[2], GROUND_WRAP),
        .face => faceCatch(sk.dir[1]),
    };
}

comptime {
    std.debug.assert(SHADOW_PAD >= SHADOW_SOFT_TIP * @as(f32, @floatFromInt(SHADOW_TAPS)));
}

const Surface = enum { floor, face, ceiling };

fn topOf(t: grid.Tile, cell: P, q: [2]f32) f32 {
    const k = CASTERS.get(t) orelse return 0;
    const r = k.r orelse return k.h;
    return if (offMiddle(cell, q) < r) k.h else 0;
}

fn offMiddle(c: P, q: [2]f32) f32 {
    const m = mathx.centre(c);
    return mathx.len(q[0] - m[0], q[1] - m[1]);
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
            return .{ .x = q[0], .y = top + 1, .z = faceZ(fy), .surface = .face };
        }
        return .{ .x = q[0], .y = q[1] + FACE_H, .z = WALL_H, .surface = .ceiling };
    }
};

/// The height a wall's face shows `fy` down its cell; `faceY` is its inverse.
fn faceZ(fy: f32) f32 {
    return (1 - fy) / FACE_H * WALL_H;
}

/// Where height `z` up the face of the wall at row `top` is drawn.
fn faceY(top: f32, z: f32) f32 {
    return top + 1 - z / WALL_H * FACE_H;
}

const TorchIx = std.math.IntFittingRange(0, grid.MAX_TORCHES - 1);

const Torch = struct {
    wall: P,
    /// 1 where the flame's light gets to, over the box of cells centred on the floor below the flame.
    reach: [SPAN * SPAN]f32,
    /// `reach` but for what blocks sight: all a cell the flame misses blends from, so no wall passes its light on.
    open: [SPAN * SPAN]f32,
    seed: u32,
    colour: Rgb = FLAME,
    glow: f32 = 1,

    fn floor(t: Torch) P {
        return lume.torchFloor(t.wall);
    }

    /// On the ground plane.
    fn flame(t: Torch) [3]f32 {
        return .{ mathx.centre(t.wall)[0], @as(f32, @floatFromInt(t.wall.y)) + 1 + STANDOFF, FLAME_Z };
    }

    /// Where the flame is drawn: up its wall's foreshortened face.
    fn drawn(t: Torch) [2]f32 {
        return .{ mathx.centre(t.wall)[0], faceY(@floatFromInt(t.wall.y), FLAME_Z) };
    }

    fn corner(t: *const Torch) P {
        return grid.Box.around(t.floor(), REACH).lo;
    }

    fn texel(t: *const Torch, p: P) usize {
        const o = t.corner();
        return @intCast((p.y - o.y) * SPAN + (p.x - o.x));
    }

    fn reached(t: *const Torch, x: f32, y: f32) f32 {
        const o = t.corner();
        const u = x - @as(f32, @floatFromInt(o.x)) - 0.5;
        const v = y - @as(f32, @floatFromInt(o.y)) - 0.5;
        const c = mathx.cellOf(.{ x, y });
        const own = mathx.dist(c, t.floor()) <= REACH and blk: {
            const i = t.texel(c);
            break :blk t.reach[i] > 0;
        };
        return bilinear(if (own) &t.reach else &t.open, SPAN, SPAN, u, v, 0);
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
            .face => faceCatch(r.d[1] / @sqrt(@max(r.d[0] * r.d[0] + r.d[1] * r.d[1], 1e-4))),
            .ceiling => CEILING_CATCH,
        };
        return r.k * facing;
    }
};

fn remembered(view: Rgb, sight: f32, memory: f32) Rgb {
    return mix(MEMORY, view, sight) * splat(memory);
}

/// Windowed inverse square: exactly nothing at `REACH`.
fn falloff(d2: f32) f32 {
    const r = d2 / REACH2;
    const w = std.math.clamp(1 - r * r, 0, 1);
    return w * w / (1 + d2 / (FALLOFF_D0 * FALLOFF_D0));
}

fn carryFade(d: f32) f32 {
    return @max(0, @min(carryAlong(d), CARRY_EDGE * (CARRY_R - d)));
}

fn carryAlong(d: f32) f32 {
    return 1 - (1 - CARRY_FADE) * d / CARRY_R;
}

const CARRY_EDGE = carryAlong(CARRY_R - 1);

fn wrapped(cos: f32, wrap: f32) f32 {
    return @max(0, (cos + wrap) / (1 + wrap));
}

/// `out` where `(u, v)` falls outside the grid; texel centres sit on whole numbers.
fn bilinear(f: []const f32, w: i32, h: i32, u: f32, v: f32, out: f32) f32 {
    const fx = @floor(u);
    const fy = @floor(v);
    const x0: i32 = @intFromFloat(fx);
    const y0: i32 = @intFromFloat(fy);
    return mathx.bilerp(.{ texel(f, w, h, x0, y0, out), texel(f, w, h, x0 + 1, y0, out), texel(f, w, h, x0, y0 + 1, out), texel(f, w, h, x0 + 1, y0 + 1, out) }, u - fx, v - fy);
}

fn texel(f: []const f32, w: i32, h: i32, x: i32, y: i32, out: f32) f32 {
    return f[mathx.slot(x, y, @intCast(w), @intCast(h)) orelse return out];
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
            v = @min(v, c.m + (1 - c.m) * smooth(mathx.len(dx, dy) / reach));
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

const splat = sky.splat;

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

/// Cells: `drawn` as on screen, `ground` where it stands.
const Lamp = struct {
    drawn: [2]f32,
    ground: [2]f32,
    colour: Rgb,
    /// The carried light casts no body's shadow, as it casts none of its carrier's.
    casts: bool,
    sky: ?SkyCast = null,
};

/// The sky's light, far off: its shadow runs `reach` body heights whatever the distance, `depth` dark in `shade`.
const SkyCast = struct { reach: f32, depth: f32, shade: Rgb };

/// As the key's share of the sky's light, so none as the sun and moon swap; `lit` is the share of the key reaching.
fn skyDepth(k: sky.Sky, lit: f32) f32 {
    const key = lum(k.key) * lit;
    return SKY_SHADOW * castShare(key, key + lum(k.ambient));
}

/// A light with `own` of the `all` that reaches a body: how much of its darkest shadow it casts.
fn castShare(own: f32, all: f32) f32 {
    return smooth(own / @max(all, 1e-6) / SHADOW_FULL);
}

fn skyShade(k: sky.Sky) Rgb {
    return mix(SHADE_RGB, MOON_SHADE_RGB, k.moon);
}

pub const Shine = struct {
    ambient: Rgb = @splat(0),
    /// How far in sight the ground under the body is.
    sight: f32 = 1,
    n: usize = 0,
    lamp: [BODY_LIGHTS]Lamp = undefined,

    /// The dimmest gives way when all are taken, but never the sky's: its shadow is as dark however dim its light.
    fn add(self: *Shine, l: Lamp) void {
        var i = self.n;
        if (self.n == BODY_LIGHTS) {
            var dimmest: ?usize = null;
            for (self.lamp, 0..) |m, k| {
                if (m.sky != null) continue;
                if (dimmest == null or lum(m.colour) < lum(self.lamp[dimmest.?].colour)) dimmest = k;
            }
            i = dimmest orelse return;
            if (l.sky == null and lum(l.colour) <= lum(self.lamp[i].colour)) return;
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
    t: mathx.Seconds,
    map: [TEXELS]rl.Color,
    /// The rows of `map` the last `bake` wrote, all the texture needs sent.
    baked: [2]i32,
    scratch: grid.Level,
    gpu: Gpu,

    /// Set field by field: built as one value, it is a temporary bigger than a thread's stack.
    pub fn create(alloc: std.mem.Allocator) !*Light {
        const l = try alloc.create(Light);
        l.torch_n = 0;
        l.carrier = null;
        l.sky = null;
        @memset(&l.casting, 0);
        l.t = .{};
        l.gpu = .{};
        @memset(&l.sight, 0);
        @memset(&l.memory, 0);
        @memset(&l.map, rl.Color.black);
        l.baked = .{ 0, MAP_H };
        l.soften();
        return l;
    }

    pub fn settle(self: *Light, lv: *const grid.Level) void {
        self.scratch = lv.*;
        self.countCasters(lv);
        self.torch_n = 0;
        for (lv.torches(), 0..) |w, i| {
            var t = Torch{ .wall = w, .reach = undefined, .open = undefined, .seed = @as(u32, @intCast(i)) *% 0x27D4EB2F +% 0x165667B1 };
            var pool: [grid.CELLS]bool = @splat(false);
            lume.torchPool(lv, w, &pool);
            var box = grid.Cells.around(t.floor(), REACH);
            while (box.next()) |p| {
                const k = t.texel(p);
                t.reach[k] = if (grid.Level.inside(p) and pool[grid.Level.idx(p)]) 1 else 0;
                t.open[k] = if (lv.at(p).blind()) 0 else t.reach[k];
            }
            self.torch[self.torch_n] = t;
            self.torch_n += 1;
        }
        for (0..grid.CELLS) |i| {
            self.sight[i] = if (lv.lit[i]) 1 else 0;
            self.memory[i] = if (lv.seen[i]) 1 else 0;
        }
        self.soften();
        self.t = .{};
        self.fan();
    }

    pub fn step(self: *Light, lv: *const grid.Level, dt: f32) void {
        const up = mathx.easing(dt, REVEAL);
        const down = mathx.easing(dt, FORGET);
        var moved = false;
        for (0..grid.CELLS) |i| {
            const want_s: f32 = if (lv.lit[i]) 1 else 0;
            const want_m: f32 = if (lv.seen[i]) 1 else 0;
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

    fn fan(self: *Light) void {
        for (self.torch[0..self.torch_n]) |*t| {
            t.glow = flicker(self.t.at(), t.seed);
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

    fn near(self: *const Light, view: grid.Box, out: *[grid.MAX_TORCHES]TorchIx) []const TorchIx {
        var n: usize = 0;
        for (self.torch[0..self.torch_n], 0..) |*t, i| {
            const f = t.floor();
            if (!grid.Box.around(f, REACH).overlaps(view, 0)) continue;
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
        return .{ .flat = mathx.len(dx, dy), .dy = dy };
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
        if (sky.upright(ray.flat)) return 1;
        const u = ray.u;
        const far = ray.far(z);
        const ex = x + u[0] * far;
        const ey = y + u[1] * far;
        const x0: i32 = @as(i32, @intFromFloat(@floor(@min(x, ex)))) - 1;
        const y0: i32 = @as(i32, @intFromFloat(@floor(@min(y, ey)))) - 1;
        const x1: i32 = @as(i32, @intFromFloat(@floor(@max(x, ex)))) + 2;
        const y1: i32 = @as(i32, @intFromFloat(@floor(@max(y, ey)))) + 2;
        if (self.castersIn(x0, y0, x1, y1) == 0) return 1;
        return sunlit(lv, ray, x, y, z);
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
        return @max(MEMORY, if (self.sky) |k| k.ambient else AMBIENT);
    }

    /// `q` is in cells.
    pub fn at(self: *const Light, lv: *const grid.Level, torches: []const TorchIx, q: [2]f32) Rgb {
        const c = mathx.cellOf(q);
        const fade = self.fadeOf(c);
        const sun: ?Sun = if (self.sky) |k| .{ .ray = SunRay.of(k), .cloud = cloudIn(self.cloudCorners(c), c, q) } else null;
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
                if (facing > 0 or n.ray.night > 0) {
                    const on = self.sunAt(lv, n.ray, s.x, s.y, s.z);
                    if (facing > 0) view += n.ray.k.key * splat(facing * reaching(on, n.cloud));
                    view *= n.ray.dim(on, n.cloud);
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
        const ray: ?SunRay = if (self.sky) |k| SunRay.of(k) else null;
        self.baked = .{ t0.y, t1.y };
        var c = P{ .x = 0, .y = @divFloor(t0.y, SUB) };
        while (c.y * SUB < t1.y) : (c.y += 1) {
            c.x = @divFloor(t0.x, SUB);
            while (c.x * SUB < t1.x) : (c.x += 1) self.bakeCell(lv, torches, c, t0, t1, ray);
        }
    }

    /// A cloud's shadow is cells across, so it is read at a cell's corners and eased between them.
    fn cloudCorners(self: *const Light, c: P) [4]f32 {
        const cx: f32 = @floatFromInt(c.x);
        const cy: f32 = @floatFromInt(c.y);
        const t = self.t.at();
        return .{
            clouded(cx, cy, t),
            clouded(cx + 1, cy, t),
            clouded(cx, cy + 1, t),
            clouded(cx + 1, cy + 1, t),
        };
    }

    fn bakeCell(self: *Light, lv: *const grid.Level, torches: []const TorchIx, c: P, t0: P, t1: P, ray: ?SunRay) void {
        const fade = self.fadeOf(c);
        const dark = if (fade.flat) |v| v == 0 else false;
        const sub: f32 = @floatFromInt(SUB);
        const corners: [4]f32 = if (ray != null and !dark) self.cloudCorners(c) else @splat(1);
        var ty = @max(t0.y, c.y * SUB);
        while (ty < @min(t1.y, (c.y + 1) * SUB)) : (ty += 1) {
            var tx = @max(t0.x, c.x * SUB);
            while (tx < @min(t1.x, (c.x + 1) * SUB)) : (tx += 1) {
                const q = [2]f32{ (@as(f32, @floatFromInt(tx)) + 0.5) / sub, (@as(f32, @floatFromInt(ty)) + 0.5) / sub };
                const sun: ?Sun = if (ray) |r| .{ .ray = r, .cloud = cloudIn(corners, c, q) } else null;
                self.map[@intCast(ty * MAP_W + tx)] = if (dark) DARK else texelOf(self.shade(lv, torches, q, &fade, sun));
            }
        }
    }

    /// `q` in cells, as the light map has the ground there.
    fn viewAt(self: *const Light, q: [2]f32) struct { sight: f32, memory: f32, lit: f32 } {
        const sight = self.sightAt(q[0], q[1]);
        const memory = self.fadeOf(mathx.cellOf(q)).at(q[0], q[1], sight);
        return .{ .sight = sight, .memory = memory, .lit = sight * memory };
    }

    /// `centre` is on the ground, cells. The carried light lights its own `carrier` flat. Faded as the ground under it is.
    pub fn onBody(self: *const Light, centre: [2]f32, carrier: bool) Shine {
        const v = self.viewAt(centre);
        const lit = v.lit;
        var s = Shine{ .sight = lit };
        const night: Rgb = if (self.sky) |k| self.sunOnBody(&s, k, centre, lit) else splat(1);
        s.ambient = remembered(self.base() * night, v.sight, v.memory);
        if (self.fromCarrier(centre[0], centre[1])) |f| {
            const c = self.carrier.?;
            const k = carryFade(f.flat) * lit * self.carryShare();
            if (carrier) {
                s.ambient += CARRY * splat(k) * night;
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
        for (s.lamp[0..s.n]) |*l| l.colour *= night;
        return s;
    }

    /// The sky's light from off the body's side; returns what a moon shadow over the body leaves of every light on it.
    fn sunOnBody(self: *const Light, s: *Shine, k: sky.Sky, centre: [2]f32, lit: f32) Rgb {
        const ray = SunRay.of(k);
        const toward = ray.u;
        const sun = self.sunAt(&self.scratch, ray, centre[0], centre[1], BODY_Z);
        const cloud = clouded(centre[0], centre[1], self.t.at());
        const on = reaching(sun, cloud);
        if (lit > 0) s.add(.{
            .drawn = .{ centre[0] + toward[0] * SUN_LAMP_D, centre[1] + toward[1] * SUN_LAMP_D },
            .ground = .{ centre[0] + toward[0], centre[1] + toward[1] },
            .colour = k.key * splat(lit * on),
            .casts = !sky.upright(k.flat()),
            .sky = .{ .reach = k.reach(), .depth = skyDepth(k, sun * cloud) * lit, .shade = ray.shade },
        });
        return ray.dim(sun, cloud);
    }

    /// A flame hangs on its wall's south face, so a wall seen only from behind shows none.
    pub fn flames(self: *const Light, lv: *const grid.Level, out: *[grid.MAX_TORCHES]Flame) []const Flame {
        var n: usize = 0;
        for (self.torch[0..self.torch_n]) |*t| {
            if (!lv.isSeen(t.wall) or !lv.isSeen(t.floor())) continue;
            const d = t.drawn();
            const v = self.viewAt(d);
            out[n] = .{ .at = d, .glow = t.glow, .lit = v.lit, .memory = v.memory };
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
        const from, const to = self.baked;
        if (to > from) rl.updateTextureRec(tex, look.rect(0, from, MAP_W, to - from), &self.map[@intCast(from * MAP_W)]);
        rl.gl.rlSetBlendFactors(rl.gl.rl_dst_color, rl.gl.rl_src_color, rl.gl.rl_func_add);
        rl.beginBlendMode(.custom);
        defer rl.endBlendMode();
        look.overFloor(tex, ox, oy, cell);
    }

    /// `centre` is its middle, cells; `flash` is how far toward `FLASH_RGB` it is drawn.
    pub fn drawBody(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: Shine, flash: f32) void {
        const w: f32 = @floatFromInt(tex.width);
        const h: f32 = @floatFromInt(tex.height);
        const src = look.rect(0, 0, if (left) -tex.width else tex.width, tex.height);
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

    /// Draws the foot's contact pool, `contact` times a body's, and returns the foot and its height; null where nothing lights it.
    fn footOf(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, s: Shine, contact: f32) ?struct { x: f32, y: f32, height: f32 } {
        const lit = s.lit();
        if (lit <= 0) return null;
        const height = self.gpu.art(tex).foot * dest.height / @as(f32, @floatFromInt(tex.height));
        const x = dest.x + dest.width * 0.5;
        const y = dest.y + height;
        if (self.gpu.glow) |g| {
            const a = CONTACT_A * @min(1, lit / lum(CARRY));
            glowAt(g, x, y, dest.width * CONTACT_W * 0.5 * contact, dest.width * CONTACT_H * 0.5 * contact, colourOf(SHADE_RGB, a));
        }
        return .{ .x = x, .y = y, .height = height };
    }

    /// Shadows until `endShadows` go into a mask of the screen, the darker winning; false with no GL. `outer` is the framebuffer being drawn into.
    pub fn beginShadows(self: *Light, screen: P, outer: u32) bool {
        const pool = self.gpu.shade orelse return false;
        if (self.gpu.shadow == null) return false;
        rl.gl.rlDrawRenderBatchActive();
        self.gpu.outer = outer;
        if (self.gpu.mask) |m| {
            if (m.texture.width != screen.x or m.texture.height != screen.y) {
                rl.unloadRenderTexture(m);
                self.gpu.mask = null;
            }
        }
        // Loading or unloading a render texture leaves framebuffer 0 bound, whatever was drawing.
        if (self.gpu.mask == null) self.gpu.mask = rl.loadRenderTexture(screen.x, screen.y) catch {
            rl.gl.rlEnableFramebuffer(self.gpu.outer);
            return false;
        };
        rl.gl.rlEnableFramebuffer(self.gpu.mask.?.id);
        rl.clearBackground(rl.Color.white);
        rl.gl.rlSetBlendFactors(rl.gl.rl_one, rl.gl.rl_one, rl.gl.rl_min);
        rl.beginBlendMode(.custom);
        rl.beginShaderMode(pool);
        return true;
    }

    pub fn endShadows(self: *Light) void {
        rl.endShaderMode();
        rl.endBlendMode();
        rl.gl.rlEnableFramebuffer(self.gpu.outer);
        const t = self.gpu.mask.?.texture;
        rl.beginBlendMode(.multiplied);
        defer rl.endBlendMode();
        rl.drawTextureRec(t, look.rect(0, 0, t.width, -t.height), .{ .x = 0, .y = 0 }, rl.Color.white);
    }

    /// Between `beginShadows` and `endShadows`, before the walls, which cover whatever of it reaches them.
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
        rl.setShaderValue(sh.shader, sh.size, &size, .vec2);
        rl.setShaderValue(sh.shader, sh.foot, &foot, .float);
        for (cs) |c| {
            if (c.solid <= 0) continue;
            var full = c;
            full.alpha *= c.solid;
            silhouette(tex, fx, fy, dest.width, foot, left, full);
        }
        rl.gl.rlDrawRenderBatchActive();
        rl.beginShaderMode(self.gpu.shade.?);
        const g = self.gpu.streak orelse return;
        for (cs) |c| {
            if (c.solid < 1) streak(g, fx, fy, dest.width, c);
        }
    }

    /// Between `beginShadows` and `endShadows`: a tree's canopy pool thrown away from each light, a soft pool over its trunk's foot.
    pub fn drawCanopy(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, centre: [2]f32, s: Shine) void {
        const g = self.gpu.glow orelse return;
        const f = self.footOf(tex, dest, s, TRUNK_OF) orelse return;
        const fx = f.x;
        const fy = f.y;
        const height = f.height;
        var buf: [BODY_LIGHTS]Cast = undefined;
        for (casts(s, centre, height, &buf)) |c| {
            const r = dest.width * CANOPY_R;
            const rx = r * (1 + c.len / height * CANOPY_STRETCH);
            const ry = r * CANOPY_SQUASH;
            drawAlong(g, .{ fx + c.lean[0] * CANOPY_AT, fy + c.lean[1] * CANOPY_AT }, c.lean, .{ rx * 2, ry * 2 }, .{ .x = rx, .y = ry }, colourOf(c.shade, c.alpha * CANOPY_A));
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
    return recolour(c, mix(from, FLASH_RGB, k));
}

/// Pixels: `lean` from the feet to the tip; `solid` the share that is silhouette, the rest a streak.
const Cast = struct { lean: [2]f32, len: f32, solid: f32, alpha: f32, shade: Rgb };

/// `height` is pixels from the feet to the top of the art.
fn casts(s: Shine, centre: [2]f32, height: f32, out: *[BODY_LIGHTS]Cast) []const Cast {
    const lit = s.lit();
    if (lit <= 0) return out[0..0];
    var n: usize = 0;
    for (s.lamp[0..s.n]) |l| {
        if (!l.casts) continue;
        const own = lum(l.colour);
        var alpha = if (l.sky) |k| k.depth else SHADOW_MAX * castShare(own, lit) * smooth(own / SHADOW_LAMP_FULL);
        const dx = centre[0] - l.ground[0];
        const dy = centre[1] - l.ground[1];
        const d = mathx.len(dx, dy);
        if (d < SHADOW_OVERHEAD) continue;
        if (l.sky == null) alpha *= mathx.smoothstep(SHADOW_OVERHEAD, SHADOW_NEAR, d);
        if (alpha < SHADOW_FAINT) continue;
        const len = height * if (l.sky) |k| k.reach else std.math.clamp(SHADOW_LEN_LO + SHADOW_LEN_PER_CELL * d, SHADOW_LEN_LO, SHADOW_LEN_HI);
        // The sky's turns slowly through due east and west: floored, it would flip across the feet in a frame.
        const rise = if (l.sky != null) dy / d else lampRise(dy / d);
        const lean = [2]f32{ dx / d * len, rise * len };
        out[n] = .{ .lean = lean, .len = mathx.len(lean[0], lean[1]), .solid = solidity(lean), .alpha = alpha, .shade = if (l.sky) |k| k.shade else SHADE_RGB };
        n += 1;
    }
    return out[0..n];
}

fn lampRise(dy_d: f32) f32 {
    return dy_d * SHADOW_SQUASH;
}

fn solidity(lean: [2]f32) f32 {
    const len = mathx.len(lean[0], lean[1]);
    if (len <= 0) return 1;
    return mathx.smoothstep(THIN_LO, THIN_HI, @abs(lean[1]) / len);
}

fn streak(g: rl.Texture2D, fx: f32, fy: f32, width: f32, c: Cast) void {
    const len = c.len / (1 - STREAK_FOOT);
    const ry = width * STREAK_W;
    drawAlong(g, .{ fx, fy }, c.lean, .{ len, ry * 2 }, .{ .x = len * STREAK_FOOT, .y = ry }, colourOf(c.shade, c.alpha * STREAK_A * (1 - c.solid)));
}

/// `g` stretched to `size`, its long side turned down `lean`, `origin` of it at `at`.
fn drawAlong(g: rl.Texture2D, at: [2]f32, lean: [2]f32, size: [2]f32, origin: rl.Vector2, c: rl.Color) void {
    const turn = std.math.radiansToDegrees(std.math.atan2(lean[1], lean[0]));
    rl.drawTexturePro(g, look.whole(g), .{ .x = at[0], .y = at[1], .width = size[0], .height = size[1] }, origin, turn, c);
}

/// `u` 0 to 1 from behind the feet to the tip, the feet at `STREAK_FOOT`; `v` 0 to 1 across.
fn streakAlpha(u: f32, v: f32) f32 {
    const along = if (u < STREAK_FOOT) mathx.smoothstep(0, STREAK_FOOT, u) else std.math.pow(f32, 1 - (u - STREAK_FOOT) / (1 - STREAK_FOOT), STREAK_TAIL);
    const off = v * 2 - 1;
    const across = @max(0, 1 - off * off);
    return along * across * across;
}

fn glowAt(g: rl.Texture2D, x: f32, y: f32, rx: f32, ry: f32, c: rl.Color) void {
    look.stretch(g, .{ .x = x - rx, .y = y - ry, .width = rx * 2, .height = ry * 2 }, c);
}

/// `lean` is pixels, feet to head. Leaning down the screen mirrors the quad, so its corners reverse to keep the winding the rasteriser does not cull.
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
    rl.gl.rlSetTexture(tex.id);
    rl.gl.rlBegin(rl.gl.rl_quads);
    const shade = colourOf(c.shade, c.alpha);
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

/// A pool's alpha as the factor it darkens the ground by, toward its colour, the shade.
const POOL_HEAD = look.FS_HEAD ++
    \\vec4 pool(float a) {
    \\    return vec4(mix(vec3(1.0), fragColor.rgb, a * fragColor.a), 1.0);
    \\}
    \\
;

const SHADE_FS = POOL_HEAD ++
    \\void main() {
    \\    finalColor = pool(texture(texture0, fragTexCoord).a);
    \\}
;

const SHADOW_FS = POOL_HEAD ++ std.fmt.comptimePrint(
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
    \\            a += alphaAt(fragTexCoord + vec2(float(i), float(j)) * spread / size);
    \\        }
    \\    }
    \\    float n = float(TAPS * 2 + 1);
    \\    finalColor = pool(a / (n * n));
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
    streak: ?rl.Texture2D = null,
    body: ?BodyShader = null,
    shadow: ?ShadowShader = null,
    shade: ?rl.Shader = null,
    /// The screen's shadows, white where there are none; sized to the screen when drawn.
    mask: ?rl.RenderTexture2D = null,
    /// The framebuffer the mask was drawn from, to go back to.
    outer: u32 = 0,
    arts: [look.FIGURES]Art = undefined,
    art_n: usize = 0,

    fn load(figures: *const [look.FIGURES]?rl.Texture2D) Gpu {
        var g = Gpu{};
        g.map = look.canvas(MAP_W, MAP_H, rl.Color.black, .bilinear);
        g.glow = look.radial(GLOW_PX, glowAlpha);
        g.streak = look.field(STREAK_PX[0], STREAK_PX[1], streakAlpha);
        g.body = look.program(BodyShader, BODY_FS);
        g.shadow = look.program(ShadowShader, SHADOW_FS);
        g.shade = look.shader(SHADE_FS);
        for (figures) |b| {
            const t = b orelse continue;
            g.arts[g.art_n] = artOf(t);
            g.art_n += 1;
        }
        return g;
    }

    fn unload(g: *Gpu) void {
        look.unloadAll(g);
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

/// Laigter's soft bevel: distance to the nearest clear texel (outside counts as clear), raised on a quarter circle; `solid` packed `w` to a row.
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
                    const k = mathx.slot(x + dx, y + dy, @intCast(w), @intCast(h));
                    const clear = if (k) |s| !solid[s] else true;
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

fn glowAlpha(r: f32) f32 {
    const r2 = @min(1, r * r);
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
    return lum(l.at(lv, l.near(grid.Box.inMap(0), &ids), q)) - lum(l.at(lv, &.{}, q));
}

test "a torch pools light on the floor below it, fading to nothing at its reach" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const fl = l.torch[0].flame();
    std.debug.print("torchlight on the floor by cells from the flame:", .{});
    var last = std.math.floatMax(f32);
    for ([_]f32{ 0.25, 1, 2, 3, 4, 5, 6, @floatFromInt(REACH) }) |r| {
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

test "no torchlight reaches the floor behind its wall" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const behind = added(l, &lv, .{ 20.5, 10 - EDGE_EPS });
    const behind_along = added(l, &lv, .{ 24.5, 9.9 });
    const below = added(l, &lv, .{ 24.5, 11 + EDGE_EPS });
    std.debug.print("torchlight on the floor at the back of its wall {d:.3}, 4 along {d:.3}, at its front 4 along {d:.3}\n", .{ behind, behind_along, below });
    try std.testing.expectApproxEqAbs(@as(f32, 0), behind, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), behind_along, 1e-5);
    try std.testing.expect(below > 0.05);
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
    const bright = lum(l.base() + CARRY);
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
    l.sky = sky.at(12);
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
    const torches = l.near(grid.Box.inMap(-1), &ids);
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
        worst = @max(worst, @abs(v - lum(l.base() + CARRY * splat(carryFade(d)))));
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

test "a shadow fades through zero as a body passes directly under a torch" {
    var s = Shine{ .ambient = AMBIENT };
    s.add(.{ .drawn = .{ 40.5, 30.5 }, .ground = .{ 40.5, 30.5 }, .colour = splat(1), .casts = true });
    var last: f32 = 0;
    var worst: f32 = 0;
    for (0..201) |i| {
        const dx = (@as(f32, @floatFromInt(i)) - 100) / 100;
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(s, .{ 40.5 + dx, 30.5 }, ART_H, &buf);
        const alpha = if (cs.len == 0) 0 else cs[0].alpha;
        if (i > 0) worst = @max(worst, @abs(alpha - last));
        if (@abs(dx) <= SHADOW_OVERHEAD) try std.testing.expectEqual(@as(f32, 0), alpha);
        last = alpha;
    }
    std.debug.print("torch shadow passing under the light: largest alpha step {d:.4}\n", .{worst});
    try std.testing.expect(worst < 0.04);
}

test "torch shadow crosses its light's horizontal line without flipping" {
    var s = Shine{ .ambient = AMBIENT };
    s.add(.{ .drawn = .{ 43.5, 30.5 }, .ground = .{ 43.5, 30.5 }, .colour = splat(1), .casts = true });
    var last: ?[2]f32 = null;
    var worst: f32 = 0;
    for (0..41) |i| {
        const dy = (@as(f32, @floatFromInt(i)) - 20) / 1000;
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(s, .{ 40.5, 30.5 + dy }, ART_H, &buf);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        try std.testing.expectEqual(@as(f32, 0), cs[0].solid);
        if (last) |was| worst = @max(worst, mathx.len(cs[0].lean[0] - was[0], cs[0].lean[1] - was[1]));
        last = cs[0].lean;
    }
    std.debug.print("torch shadow across the horizontal: largest tip step {d:.4} px\n", .{worst});
    try std.testing.expect(worst < 0.1);
}

test "night lantern on explored ground fades into memory without a dark ring" {
    var lv = grid.openFloor();
    lv.seen = @splat(true);
    const at = P{ .x = 40, .y = 30 };
    lume.see(&lv, at, actor.row(.archer).sight, 0, &.{.{ .at = at, .reach = actor.row(.archer).light }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.carrier = mathx.centre(at);
    l.sky = sky.at(1);
    var lowest = lum(MEMORY);
    var rise: f32 = 0;
    var last = lum(l.at(&lv, &.{}, l.carrier.?));
    for (1..161) |i| {
        const d = @as(f32, @floatFromInt(i)) / 20;
        const value = lum(l.at(&lv, &.{}, .{ 40.5 + d, 30.5 }));
        lowest = @min(lowest, value);
        rise = @max(rise, value - last);
        last = value;
    }
    std.debug.print("night lantern into explored ground: minimum {d:.4}, memory {d:.4}, outward rise {d:.4}\n", .{ lowest, lum(MEMORY), rise });
    try std.testing.expect(lowest >= lum(MEMORY) - 0.002);
    try std.testing.expect(rise < 0.002);
}

test "moving night light stays above memory at 60 and 144 Hz" {
    const from = P{ .x = 40, .y = 30 };
    for ([_]f32{ 60, 144 }) |hz| {
        var lv = grid.openFloor();
        lv.seen = @splat(true);
        lume.see(&lv, from, 10, 0, &.{.{ .at = from, .reach = actor.row(.archer).light }});
        const l = try testLight(&lv);
        defer std.testing.allocator.destroy(l);
        l.sky = sky.at(1);
        const to = from.add(.{ .x = 1, .y = 1 });
        lume.see(&lv, to, 10, 0, &.{.{ .at = to, .reach = actor.row(.archer).light }});
        var lowest = lum(MEMORY);
        var worst: f32 = 0;
        var previous: [80]f32 = undefined;
        var frame: usize = 0;
        var t: f32 = 0;
        while (t <= 1) : (t += 1 / hz) {
            const k = @min(1, t / 0.13);
            l.carrier = .{ 40.5 + k, 30.5 + k };
            l.step(&lv, 1 / hz);
            for (0..80) |i| {
                const x = 35.5 + @as(f32, @floatFromInt(i)) / 5;
                const v = lum(l.at(&lv, &.{}, .{ x, 30.5 }));
                lowest = @min(lowest, v);
                if (frame > 0) worst = @max(worst, @abs(v - previous[i]));
                previous[i] = v;
            }
            frame += 1;
        }
        std.debug.print("moving night light at {d} Hz: minimum {d:.4}, largest frame change {d:.4}\n", .{ hz, lowest, worst });
        try std.testing.expect(lowest >= lum(MEMORY) - 0.002);
        try std.testing.expect(worst < 0.08);
    }
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
    const past = lum(l.at(&lv, &.{}, .{ 40.5 + edge + 1, 30.5 }));
    std.debug.print(", a cell past {d:.3}, memory {d:.3}\n", .{ past, lum(MEMORY) });
    try std.testing.expect(last > lum(MEMORY));
    try std.testing.expectApproxEqAbs(lum(MEMORY), past, 1e-4);
}

test "a torch on a wall never seen has no flame to draw, though the floor below it is in sight" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    lv.lightless();
    @memset(&lv.seen, false);
    lv.light(lume.torchFloor(TORCH_AT));
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
    const cs = casts(l.onBody(at, carrier), at, ART_H, &buf);
    if (cs.len == 0) return .{ 0, 0 };
    return .{ cs[0].alpha, cs[0].len };
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
        while (d < @as(f32, @floatFromInt(REACH)) + 0.5) : (d += 0.0625) {
            const at = [2]f32{ fl[0] + d, fl[1] + 0.5 };
            l.carrier = if (r.carrier) |c| .{ at[0] + c, at[1] } else null;
            const v = castAlpha(l, at, r.carrying);
            if (@mod(d, 1) == 0.5) std.debug.print(" {d:.1}:{d:.2}/{d:.0}", .{ d, v[0], v[1] });
            if (last) |was| worst = @max(worst, was - v[0]);
            if (v[0] > 0) gone = d;
            last = v[0];
        }
        std.debug.print("; biggest drop per 1/16 cell {d:.3}, last cast at {d:.2}\n", .{ worst, gone });
        steepest = @max(steepest, worst);
        nearest_end = @min(nearest_end, gone);
    }
    try std.testing.expect(steepest < 0.07);
    try std.testing.expect(nearest_end + 0.0625 >= @as(f32, @floatFromInt(REACH)) - 1.5);
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

const ART_H: f32 = @floatFromInt(look.SPRITE_PX);

/// From the middle of `c`, cells away from the sky's light along the ground until the point is half lit.
fn shadowLength(lv: *const grid.Level, k: sky.Sky, c: P) f32 {
    const u = k.across();
    const m = mathx.centre(c);
    var d: f32 = 0;
    while (d < 12) : (d += 0.01) {
        const x = m[0] - u[0] * d;
        const y = m[1] - u[1] * d;
        if (!mathx.cellOf(.{ x, y }).eq(c) and sunlit(lv, SunRay.of(k), x, y, 0) > 0.5) return d;
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
        const u = k.across();
        try std.testing.expectEqual(@as(f32, 1), sunlit(&lv, SunRay.of(k), m[0] + u[0] * 0.6, m[1] + u[1] * 0.6, 0));
    }
}

test "everything that blocks a step and does not stand shades the ground past its edge away from the sun, morning, noon and evening" {
    const at = P{ .x = 30, .y = 30 };
    const m = mathx.centre(at);
    for (std.enums.values(grid.Tile)) |t| {
        if (!t.upright() or look.stands(t)) continue;
        var lv = grid.openFloor();
        lv.set(at, t);
        var worst: f32 = 0;
        for ([_]f32{ 8, 12, 17 }) |hour| {
            const k = sky.at(hour);
            const ux = k.across()[0];
            const uy = k.across()[1];
            const edge = CASTERS.get(t).?.r orelse 0.5 / @max(@abs(ux), @abs(uy));
            const past = edge + 0.05;
            const shade = sunlit(&lv, SunRay.of(k), m[0] - ux * past, m[1] - uy * past, 0);
            worst = @max(worst, shade);
            if (CASTERS.get(t).?.r != null) try std.testing.expectEqual(@as(f32, 1), sunlit(&lv, SunRay.of(k), m[0], m[1], topOf(t, at, m)));
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
        const cs = casts(s, mathx.centre(c), ART_H, &out[i]);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        lean[i] = cs[0].lean;
    }
    std.debug.print("at 16.5h a shrub's shadow leans {d:.1},{d:.1} px, a foe's {d:.1},{d:.1}\n", .{ lean[0][0], lean[0][1], lean[1][0], lean[1][1] });
    for (0..2) |k| try std.testing.expectApproxEqAbs(lean[1][k], lean[0][k], 1e-3);
    try std.testing.expect(lean[0][0] > 0);
}

test "a body's sun shadow runs the way the ground's do, its height times the hour's reach" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const at = mathx.centre(.{ .x = 40, .y = 30 });
    for ([_]f32{ 9, 13, 16.5 }) |hour| {
        l.sky = sky.at(hour);
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(l.onBody(at, false), at, ART_H, &buf);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        const u = l.sky.?.across();
        const want = ART_H * l.sky.?.reach();
        std.debug.print("at {d:.1}h a body's shadow leans {d:.1},{d:.1} px, the ground's {d:.1},{d:.1}\n", .{ hour, cs[0].lean[0], cs[0].lean[1], -u[0] * want, -u[1] * want });
        for (0..2) |k| try std.testing.expectApproxEqAbs(-u[k] * want, cs[0].lean[k], 1e-2);
    }
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
                try std.testing.expectEqual(sunlit(&lv, SunRay.of(k), q[0], q[1], z), l.sunAt(&lv, SunRay.of(k), q[0], q[1], z));
                const far = SunRay.of(k).far(z);
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
            const cs = casts(l.onBody(at, false), at, ART_H, &buf);
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
    const none: []const TorchIx = &.{};
    l.sky = sky.at(morning);
    const k = l.sky.?;
    const u = k.across();
    const m = mathx.centre(rock);
    const behind = 0.5 + k.reach() * 0.5;
    const shade = lum(l.at(&lv, none, .{ m[0] - u[0] * behind, m[1] - u[1] * behind }));
    const sun = lum(l.at(&lv, none, .{ m[0] + u[0] * 2, m[1] + u[1] * 2 }));
    l.sky = sky.at(0);
    const night = lum(l.at(&lv, none, .{ m[0] + 5, m[1] }));
    std.debug.print("{d}h ground: {d:.2} in the sun, {d:.2} in a rock's shadow; {d:.3} at midnight\n", .{ morning, sun, shade, night });
    try std.testing.expect(sun > shade * 1.2 and sun < shade * 2 and shade > night * 2.5);
    try std.testing.expect(night >= lum(MEMORY));
}

test "the moon throws a cold shadow as deep as the sun's, over the archer's own light too" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const rock = P{ .x = 30, .y = 30 };
    lv.set(rock, .rock);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const m = mathx.centre(rock);
    l.carrier = m;
    const foe = mathx.centre(.{ .x = 40, .y = 30 });
    var depth: [2]f32 = undefined;
    var blue: [2]f32 = undefined;
    for ([_]f32{ 12, 1 }, 0..) |h, i| {
        l.sky = sky.at(h);
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(l.onBody(foe, false), foe, ART_H, &buf);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        depth[i] = cs[0].alpha;
        blue[i] = cs[0].shade[2] / cs[0].shade[0];
    }
    const none: []const TorchIx = &.{};
    const k = l.sky.?;
    const u = k.across();
    const off = 0.5 + k.reach() * 0.5;
    const back = [2]f32{ m[0] - u[0] * off, m[1] - u[1] * off };
    const front = [2]f32{ m[0] + u[0] * off, m[1] + u[1] * off };
    const behind = l.at(&lv, none, back);
    const toward = l.at(&lv, none, front);
    const near = 0.65;
    const body_behind = l.onBody(.{ m[0] - u[0] * near, m[1] - u[1] * near }, false).lit();
    const body_toward = l.onBody(.{ m[0] + u[0] * near, m[1] + u[1] * near }, false).lit();
    const ground_near = lum(l.at(&lv, none, .{ m[0] - u[0] * near, m[1] - u[1] * near })) / lum(l.at(&lv, none, .{ m[0] + u[0] * near, m[1] + u[1] * near }));
    std.debug.print("a foe's shadow {d:.2} deep at noon, {d:.2} at 1h, blue over red {d:.2} and {d:.2}; by the archer's own light at 1h, ground behind a rock {d:.3} to {d:.3} in front, blue over red {d:.2} to {d:.2}; just past its edge a body takes {d:.2} of the light in front, the ground {d:.2}\n", .{ depth[0], depth[1], blue[0], blue[1], lum(behind), lum(toward), behind[2] / behind[0], toward[2] / toward[0], body_behind / body_toward, ground_near });
    try std.testing.expect(depth[1] > depth[0] * 0.8 and blue[1] > blue[0]);
    try std.testing.expect(lum(behind) < lum(toward) * 0.85 and behind[2] / behind[0] > toward[2] / toward[0]);
    try std.testing.expect(body_behind / body_toward < 0.9 and body_behind / body_toward > ground_near - 0.05);
}

test "sun and torch shadows thinned to slivers give way to soft streaks" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const at = mathx.centre(.{ .x = 40, .y = 30 });
    var silhouette_at: [3]f32 = undefined;
    for ([_]f32{ 6, 8, 12 }, &silhouette_at) |h, *k| {
        l.sky = sky.at(h);
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(l.onBody(at, false), at, ART_H, &buf);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        k.* = cs[0].solid;
    }
    var torch_least: f32 = 1;
    var a: f32 = 0;
    while (a < std.math.tau) : (a += 0.01) torch_least = @min(torch_least, solidity(.{ @cos(a), lampRise(@sin(a)) }));
    std.debug.print("of a sun shadow, silhouette: {d:.2} at 6h, {d:.2} at 8h, {d:.2} at noon; of a torch's, {d:.2} at least\n", .{ silhouette_at[0], silhouette_at[1], silhouette_at[2], torch_least });
    try std.testing.expect(silhouette_at[0] < 0.1 and silhouette_at[1] > 0.5 and silhouette_at[2] == 1 and torch_least == 0);
}

test "a streak is darkest at the feet and gone at the tip, and a sideways sun shadow runs at most its reach" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const at = mathx.centre(.{ .x = 40, .y = 30 });
    var longest: f32 = 0;
    var h: f32 = 5.5;
    while (h <= 20.5) : (h += 0.1) {
        l.sky = sky.at(h);
        var buf: [BODY_LIGHTS]Cast = undefined;
        for (casts(l.onBody(at, false), at, ART_H, &buf)) |c| longest = @max(longest, c.len / ART_H);
    }
    const mid = 0.5;
    var peak_u: f32 = 0;
    var peak: f32 = 0;
    var u: f32 = 0;
    while (u <= 1) : (u += 0.01) {
        if (streakAlpha(u, mid) > peak) {
            peak = streakAlpha(u, mid);
            peak_u = u;
        }
    }
    std.debug.print("a streak peaks {d:.2} along, the feet at {d:.2}, {d:.2} at the tip; the longest sun shadow {d:.2} heights\n", .{ peak_u, STREAK_FOOT, streakAlpha(1, mid), longest });
    try std.testing.expectApproxEqAbs(STREAK_FOOT, peak_u, 0.011);
    try std.testing.expect(streakAlpha(1, mid) < 1e-3 and longest <= sky.REACH_MAX + 1e-3);
}
