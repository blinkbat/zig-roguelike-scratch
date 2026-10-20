const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const look = @import("look.zig");
const sky = @import("sky.zig");
const lume = @import("../map/lume.zig");
const actor = @import("../play/actor.zig");

const P = mathx.P;
pub const Rgb = sky.Rgb;
const mix = sky.mix;

/// Light-map texels per cell side.
pub const SUB: i32 = 4;
const MAP_W: i32 = grid.W * SUB;
const MAP_H: i32 = grid.H * SUB;
const NONE_BAKED = [2]i32{ MAP_H, 0 };
const TEXELS: usize = @intCast(MAP_W * MAP_H);
/// DST_COLOR/SRC_COLOR blending doubles the stored light.
pub const OVERBRIGHT: f32 = 2.0;

pub const REACH: i32 = lume.TORCH_REACH;
const REACH2: f32 = @floatFromInt(REACH * REACH);
const SPAN: i32 = grid.Cells.span(REACH);
/// Cells: the inverse square's reference distance.
const FALLOFF_D0: f32 = 2.5;
/// Wall height in cells; the brick face below `FACE_FROM` is foreshortened.
const WALL_H: f32 = 1.0;
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

const CARRY: Rgb = .{ 0.92, 0.88, 0.80 };
const MOON_CARRY: Rgb = .{ 0.52, 0.68, 1.0 };
/// A cell past what the hero's light lets it see, so its glow fades out on the edge of sight.
const CARRY_R: f32 = @floatFromInt(actor.row(actor.HERO).light + 1);
const CARRY_FADE: f32 = 0.3;
const CARRY_CEILING: f32 = 0.7;
const CARRY_FACE_WRAP: f32 = 0.6;

/// The light remembered terrain is drawn under, after Brogue's memory colour.
const MEMORY = rgbOf(look.rgb(0x33385c));
const FLAME: Rgb = .{ 1.30, 0.80, 0.40 };
/// Per channel, the power the flicker is raised to, so a flame whitens as it flares.
const FLAME_SHIFT: Rgb = .{ 1.0, 1.6, 2.4 };
const FAINT: f32 = 0.002;
const TINT_DIRECT: f32 = 0.6;
/// Per second.
const REVEAL: f32 = 14.0;
const FORGET: f32 = 5.0;
/// Cells: memory is black on the edge of anything unseen and full this far from it.
const VOID_FADE: f32 = 1.5;
/// Keep the sight fade inside unseen cell rims so visible ground stays bright.
const SIGHT_FADE: f32 = 0.4;
const VOID_REACH: i32 = @intFromFloat(@ceil(VOID_FADE));
const VOID_SPAN: usize = @intCast(grid.Cells.span(VOID_REACH));
const CORNERS_W = grid.CORNERS_W;
const CORNERS_H = grid.CORNERS_H;
const FLICKER: f32 = 0.14;
const FLICKER_BANDS = [_]struct { hz: f32, weight: f32 }{
    .{ .hz = 1.5, .weight = 0.6 },
    .{ .hz = 5.0, .weight = 0.3 },
    .{ .hz = 11.0, .weight = 0.1 },
};
/// Brogue's `adjustedLightValue`: bend channels above this knee toward sqrt.
const KNEE: f32 = 1.5;

const BODY_LIGHTS: usize = 4;
/// A pale flash remains visible over red bodies.
const FLASH_RGB = Rgb{ 0.88, 0.38, 0.30 };
/// Texels toward the viewer, for the side-lighting of a body.
const BODY_LIGHT_Z: f32 = 40.0;
/// Darkest ground tint; overlapping shadows take the channelwise minimum.
const SHADE_RGB = Rgb{ 0.42, 0.45, 0.54 };
/// Darkens whatever lights the ground, the hero's own light too.
const MOON_SHADE_RGB = Rgb{ 0.34, 0.40, 0.62 };
const SHADOW_MAX: f32 = 0.85;
/// A light with this share of all that reaches a body casts its darkest shadow; under it the shadow eases out to none.
const SHADOW_FULL: f32 = 0.5;
/// And a light at least this bright; a torch is, out to about half its reach.
const SHADOW_LAMP_FULL: f32 = 0.25;
const SHADOW_FAINT = look.CLEAR_A;
/// Of the body's drawn height.
const SHADOW_LEN_LO: f32 = 0.5;
const SHADOW_LEN_HI: f32 = 1.8;
const SHADOW_LEN_PER_CELL: f32 = 0.2;
const SHADOW_SQUASH: f32 = 0.55;
/// Cells: a light this close to a body's middle stands over it and casts no shadow.
const SHADOW_OVERHEAD: f32 = 0.05;
const SHADOW_NEAR: f32 = 0.5;
const SHADOW_PAD: f32 = SHADOW_SOFT_TIP * @as(f32, @floatFromInt(SHADOW_TAPS));
/// Texels between the shadow shader's blur taps, at its tip and at its foot.
const SHADOW_SOFT_TIP: f32 = 2.0;
const SHADOW_SOFT_FOOT: f32 = 0.6;
const SHADOW_TAPS: i32 = 3;
/// Vertical shadow share: silhouettes fade to streaks from `THIN_HI` to `THIN_LO`.
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
/// Cells between ray samples; softness is a fraction of caster height and a cell distance from round edges.
const SUN_STEP: f32 = 0.1;
const SUN_SOFT: f32 = 0.7;
const SUN_EDGE: f32 = 0.2;
/// Of the sky's light, how much a sun shadow takes away at its darkest, and how dark a body's sun shadow is.
const SUN_SHADE: f32 = 0.45;
const SUN_SHADOW_A: f32 = 0.4;
const SKY_SHADOW = SHADOW_MAX * SUN_SHADOW_A;
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
const FOREST_PAD: f32 = FOREST_SOFT * SHADOW_TAPS;
/// Maximum ground reach, in cells, of a cell-tall sky or torch caster.
pub const CAST_REACH: f32 = blk: {
    const l = @max(sky.REACH_MAX, SHADOW_LEN_HI);
    const pad = @max(SHADOW_PAD, FOREST_PAD) / look.SPRITE_PX;
    break :blk 0.5 + @max(pad + l * (1 + pad), CANOPY_AT * l + CANOPY_R * (1 + l * CANOPY_STRETCH));
};
const TRUNK_OF: f32 = 0.6;
/// Cells to the side the sun lights a body from, as the body shader takes a lamp.
const SUN_LAMP_D: f32 = 3;

/// Height and optional circular radius in cells; null radius fills a square cell.
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

const SunRay = struct {
    k: sky.Sky,
    flat: f32,
    u: [2]f32,
    /// Cells up per cell along the ground toward the light.
    rise: f32,
    /// How deep the moon's shadows darken the ground, whatever lights it, and in what.
    night: f32,
    shade: Rgb,
    glint: f32,

    fn of(k: sky.Sky) SunRay {
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

const Surface = enum { floor, face, ceiling };

fn topOf(t: grid.Tile, cell: P, q: [2]f32) f32 {
    const k = CASTERS.getPtrConst(t).* orelse return 0;
    const r = k.r orelse return k.h;
    return if (offMiddle(cell, q) < r) k.h else 0;
}

fn offMiddle(c: P, q: [2]f32) f32 {
    const m = mathx.centre(c);
    return mathx.len(q[0] - m[0], q[1] - m[1]);
}

/// Light-map coordinates account for walls drawn above their ground cell.
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

fn faceZ(fy: f32) f32 {
    return (1 - fy) / FACE_H * WALL_H;
}

fn faceY(top: f32, z: f32) f32 {
    return top + 1 - z / WALL_H * FACE_H;
}

const TorchIx = std.math.IntFittingRange(0, grid.MAX_TORCHES - 1);

const Torch = struct {
    wall: P,
    /// 1 where the flame's light gets to, over the box of cells centred on the floor below the flame.
    reach: [SPAN * SPAN]f32,
    /// Sight-blocking mask for interpolation; prevents walls passing light onward.
    open: [SPAN * SPAN]f32,
    seed: u32,
    colour: Rgb = FLAME,
    glow: f32 = 1,

    fn floor(t: *const Torch) P {
        return lume.torchFloor(t.wall);
    }

    /// On the ground plane.
    fn flame(t: *const Torch) [3]f32 {
        return .{ mathx.centre(t.wall)[0], @as(f32, @floatFromInt(t.wall.y)) + 1 + STANDOFF, FLAME_Z };
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
        const o = t.corner();
        return mathx.slot(p.x - o.x, p.y - o.y, SPAN, SPAN).?;
    }

    fn reached(t: *const Torch, x: f32, y: f32) f32 {
        const o = t.corner();
        return occluded(&t.reach, &t.open, SPAN, SPAN, x - @as(f32, @floatFromInt(o.x)) - 0.5, y - @as(f32, @floatFromInt(o.y)) - 0.5);
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
const SUN_GLINT_POWER: f32 = 24;
const GLINT_POWER: f32 = 80;
const SUN_GLINT: f32 = 0.05;
const CARRY_GLINT: f32 = 0.08;
const TORCH_GLINT: f32 = 0.12;
const EFFECT_GLINT: f32 = 0.11;

fn smoothSpecular(toward: [3]f32, power: f32) f32 {
    const d: Rgb = toward;
    const len = @sqrt(@reduce(.Add, d * d));
    if (len <= 1e-5 or d[2] <= 0) return 0;
    const half = d / splat(len) + VIEWER;
    const h = half / splat(@sqrt(@reduce(.Add, half * half)));
    return std.math.pow(f32, @max(0, h[2]), power);
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
    return bilinear(f, grid.W, grid.H, x - 0.5, y - 0.5);
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
    lo: P,
    v: std.EnumArray(SightField, [9]f32),

    fn of(l: *const Light, c: P) Patch {
        var p = Patch{ .lo = c.sub(.{ .x = 1, .y = 1 }), .v = undefined };
        for (std.enums.values(SightField)) |k| {
            const f = l.sightField(k);
            const out = p.v.getPtr(k);
            for (0..9) |i| out[i] = texel(f, grid.W, grid.H, p.lo.x + @as(i32, @intCast(i % 3)), p.lo.y + @as(i32, @intCast(i / 3)));
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
        const i = iy * 3 + ix;
        return mathx.bilerp(.{ f[i], f[i + 1], f[i + 3], f[i + 4] }, u - fx, v - fy);
    }
};

fn sampleOccluded(reach: *const [grid.CELLS]f32, open: *const [grid.CELLS]f32, x: f32, y: f32) f32 {
    return occluded(reach, open, grid.W, grid.H, x - 0.5, y - 0.5);
}

fn texel(f: []const f32, w: i32, h: i32, x: i32, y: i32) f32 {
    return f[mathx.slot(x, y, @intCast(w), @intCast(h)) orelse return 0];
}

/// Blend unreachable cells over `open` so walls cannot pass light onward.
fn occluded(reach: []const f32, open: []const f32, w: i32, h: i32, u: f32, v: f32) f32 {
    const own = texel(reach, w, h, mathx.roundTiesUp(u), mathx.roundTiesUp(v)) > 0;
    return bilinear(if (own) reach else open, w, h, u, v);
}

fn mask(on: bool) f32 {
    return @floatFromInt(@intFromBool(on));
}

fn hidesGround(t: grid.Tile) bool {
    return t.blind() and t.upright() and !look.stands(t);
}

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

/// The cosine a light `dy` south of a south face and `flat` from it along the ground strikes it at.
fn faceCos(dy: f32, flat: f32) f32 {
    return dy / @max(flat, FACE_EPS);
}

const FACE_EPS: f32 = 1e-2;

const splat = sky.splat;

const rgbOf = look.rgbOf;

fn colourOf(c: Rgb, a: f32) rl.Color {
    const k = @max(splat(0), @min(splat(1), c)) * splat(255) + splat(0.5);
    return .{ .r = @intFromFloat(k[0]), .g = @intFromFloat(k[1]), .b = @intFromFloat(k[2]), .a = @intFromFloat(std.math.clamp(a, 0, 1) * 255 + 0.5) };
}

fn texelOf(c: Rgb, sight: f32) rl.Color {
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

fn castShare(own: f32, all: f32) f32 {
    return smooth(own / @max(all, 1e-6) / SHADOW_FULL);
}

fn skyShade(k: sky.Sky) Rgb {
    return mix(SHADE_RGB, MOON_SHADE_RGB, k.moon);
}

pub const Shine = struct {
    ambient: Rgb = @splat(0),
    /// Of `ambient`, what memory's floor lifts it by: no light reaches with it.
    floor: Rgb = @splat(0),
    /// How far in sight times how far remembered the ground under the body is.
    sight: f32 = 1,
    n: usize = 0,
    lamp: [BODY_LIGHTS]Lamp = undefined,

    /// The dimmest gives way when all are taken, but never the sky's: its shadow is as dark however dim its light.
    fn add(self: *Shine, l: Lamp) void {
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

    fn total(self: *const Shine) Rgb {
        var c: Rgb = @splat(0);
        for (self.lamp[0..self.n]) |l| c += l.colour;
        return c;
    }

    fn lit(self: *const Shine) f32 {
        return lum(self.ambient + self.total());
    }

    fn reached(self: *const Shine) f32 {
        return lum(self.ambient - self.floor + self.total());
    }

    pub fn tint(self: *const Shine, c: rl.Color) rl.Color {
        return recolour(c, rgbOf(c) * (self.ambient + self.total() * splat(TINT_DIRECT)));
    }

    /// As the body shader would draw `c`, for what is drawn without it.
    pub fn drawn(self: *const Shine, c: rl.Color, flash: f32) rl.Color {
        return flashed(self.tint(c), flash);
    }
};

fn recolour(c: rl.Color, rgb: Rgb) rl.Color {
    return colourOf(rgb, @as(f32, @floatFromInt(c.a)) / 255);
}

/// `lit` combines sight and memory; `memory` retains only exploration visibility.
pub const Flame = struct { at: [2]f32, foot: f32, glow: f32, lit: f32, memory: f32 };

pub const Emission = struct {
    at: [3]f32,
    col: rl.Color,
    radius: f32,
    gain: f32,
};

const EFFECTS = 48;
const EffectSet = std.StaticBitSet(EFFECTS);
const EFFECT_REACH = 5;
const EFFECT_SPAN: comptime_int = grid.Cells.span(EFFECT_REACH);

const Effect = struct {
    source: Emission,
    origin: P,
    reach: [EFFECT_SPAN * EFFECT_SPAN]bool,

    fn strength(e: *const Effect, x: f32, y: f32, z: f32) f32 {
        const s = e.source;
        const dx = s.at[0] - x;
        const dy = s.at[1] - y;
        const dz = s.at[2] - z;
        const d2 = dx * dx + dy * dy + dz * dz;
        if (d2 >= s.radius * s.radius) return 0;
        const i = e.texel(mathx.cellOf(.{ x, y })) orelse return 0;
        if (!e.reach[i]) return 0;
        const k = 1 - d2 / (s.radius * s.radius);
        return s.gain * k * k;
    }

    fn texel(e: *const Effect, p: P) ?usize {
        return mathx.slot(p.x - e.origin.x + EFFECT_REACH, p.y - e.origin.y + EFFECT_REACH, EFFECT_SPAN, EFFECT_SPAN);
    }
};

pub const Light = struct {
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
    torch_n: usize,
    /// The hero's centre as drawn, cells.
    carrier: ?[2]f32,
    sky: ?sky.Sky,
    /// Integral image of caster counts at cell corners.
    casting: [CORNERS_W * CORNERS_H]u16,
    clouds: [CORNERS_W * CORNERS_H]f32,
    /// Cached inclusive cloud corners and sample time in seconds.
    clouds_held: ?struct { box: grid.Box, t: f32 } = null,
    t: mathx.Seconds,
    map: [TEXELS]rl.Color,
    glints: [TEXELS]rl.Color,
    /// The rows of `map` baked since the texture was last sent, all it needs sent.
    baked: [2]i32,
    scratch: grid.Level,
    gpu: Gpu,
    forest: [FOREST_QUEUE]ForestCast,
    forest_n: usize,
    forest_order: [FOREST_QUEUE]u64,
    reveal_map: bool = false,
    composed: bool = false,
    canopy: [grid.CELLS]f32,
    /// Per light-map texel, `dapplingAt` its centre: fixed while the ground is.
    dappling: [TEXELS]f32,

    /// Initialize fields separately to avoid a temporary larger than the thread stack.
    pub fn create(alloc: std.mem.Allocator) !*Light {
        const l = try alloc.create(Light);
        mathx.defaults(l);
        l.forest_n = 0;
        l.torch_n = 0;
        l.carrier = null;
        l.sky = null;
        @memset(&l.casting, 0);
        l.t = .{};
        l.gpu = .{};
        @memset(&l.sight, 0);
        @memset(&l.memory, 0);
        @memset(&l.scratch.tile, .floor);
        @memset(&l.scratch.los, false);
        l.grounded();
        @memset(&l.map, rl.Color.blank);
        @memset(&l.glints, rl.Color.blank);
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

    const TEXELS_W: usize = @intCast(MAP_W);

    fn texelCentre(tx: usize, ty: usize) [2]f32 {
        const sub: f32 = @floatFromInt(SUB);
        return .{ (@as(f32, @floatFromInt(tx)) + 0.5) / sub, (@as(f32, @floatFromInt(ty)) + 0.5) / sub };
    }

    fn grounded(self: *Light) void {
        for (&self.see_through, &self.ground, &self.scratch.tile) |*k, *g, t| {
            k.* = mask(!t.blind());
            g.* = mask(!hidesGround(t));
        }
        var cells = grid.Cells.of(.{ .x = 0, .y = 0 }, grid.SIZE);
        while (cells.next()) |p| {
            var neighbours = grid.Cells.around(p, 2);
            var cover: f32 = 0;
            while (neighbours.next()) |q| {
                if (!look.canopy(self.scratch.at(q))) continue;
                const d = p.sub(q);
                cover += 1 / @as(f32, @floatFromInt(1 + d.x * d.x + d.y * d.y));
            }
            self.canopy[grid.Level.idx(p)] = @min(1, cover * 0.3);
        }
        for (&self.dappling, 0..) |*d, i| d.* = self.dapplingAt(texelCentre(i % TEXELS_W, i / TEXELS_W));
    }

    /// Blur only seen cells, and ground sight only over open ground, to prevent dim rims and wall leaks.
    fn soften(self: *Light) void {
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
    fn sightAt(self: *const Light, x: f32, y: f32) f32 {
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

    fn memoryAt(self: *const Light, p: P) f32 {
        return grid.cellOr(f32, &self.memory, p, 0);
    }

    fn whole(self: *const Light, p: P) bool {
        return grid.cellOr(bool, &self.clear, p, false);
    }

    fn near(self: *const Light, view: grid.Box, out: *[grid.MAX_TORCHES]TorchIx) []const TorchIx {
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
            const p = corner.add(.{ .x = @intCast(i % 2), .y = @intCast(i / 2) });
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

    fn sunAt(self: *const Light, lv: *const grid.Level, ray: *const SunRay, x: f32, y: f32, z: f32) f32 {
        if (sky.upright(ray.flat)) return 1;
        const b = sunBox(ray.*, x, y, z);
        if (self.castersIn(b) == 0) return 1;
        return sunlit(lv, ray.*, x, y, z);
    }

    fn sunBox(ray: SunRay, x: f32, y: f32, z: f32) grid.Box {
        const far = ray.far(z);
        const e = [2]f32{ x + ray.u[0] * far, y + ray.u[1] * far };
        const lo = mathx.cellOf(.{ @min(x, e[0]), @min(y, e[1]) });
        const hi = mathx.cellOf(.{ @max(x, e[0]), @max(y, e[1]) });
        return .{ .lo = lo.sub(.{ .x = 1, .y = 1 }), .hi = hi.add(.{ .x = 2, .y = 2 }) };
    }

    fn castersIn(self: *const Light, box: grid.Box) u16 {
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
            const daylight = 1 - k.moon;
            k.key *= mix(splat(1), .{ 1.035, 1.005, 0.96 }, daylight);
            k.ambient *= mix(splat(1), .{ 0.94, 0.98, 1.04 }, daylight);
        }
        return k;
    }

    fn composedCloud(self: *const Light, q: [2]f32, cloud: f32) f32 {
        if (!self.composed or self.sky == null) return cloud;
        return self.composedWith(self.dapplingAt(q), cloud);
    }

    /// `composedCloud` at `q`, from the cached dappling when `q` is light-map texel `map_at`'s centre.
    fn composedAt(self: *const Light, map_at: ?usize, q: [2]f32, cloud: f32) f32 {
        const i = map_at orelse return self.composedCloud(q, cloud);
        if (!self.composed or self.sky == null) return cloud;
        return self.composedWith(self.dappling[i], cloud);
    }

    fn composedWith(self: *const Light, dappling: f32, cloud: f32) f32 {
        const k = self.sky.?;
        const patch = 1.045 - (1 - cloud) * 1.6 - dappling;
        return mathx.lerpF(cloud, patch, 1 - k.moon);
    }

    /// How much the canopy's dappled shade takes from the sun at `q`.
    fn dapplingAt(self: *const Light, q: [2]f32) f32 {
        const p = mathx.cellOf(.{ q[0] - 0.5, q[1] - 0.5 });
        var corners: [4]f32 = undefined;
        for (&corners, 0..) |*c, i| {
            c.* = grid.cellOr(f32, &self.canopy, p.add(.{ .x = @intCast(i % 2), .y = @intCast(i / 2) }), 0);
        }
        const cover = mathx.bilerp(corners, q[0] - 0.5 - @as(f32, @floatFromInt(p.x)), q[1] - 0.5 - @as(f32, @floatFromInt(p.y)));
        const dapple = 0.5 + 0.5 * @sin(q[0] * 2.1 + q[1] * 1.6 + @sin(q[1] * 1.2));
        return cover * (0.07 + 0.10 * dapple);
    }

    fn base(self: *const Light) Rgb {
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

    fn effectsNear(self: *const Light, c: P) EffectSet {
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
        const ray: ?SunRay = if (self.profile()) |k| SunRay.of(k) else null;
        const cloud = if (ray != null) self.cloudAt(q) else 1;
        return self.shade(lv, torches, self.effectsNear(c), q, null, self.viewIn(q, &fade), if (ray) |*r| r else null, cloud);
    }

    /// `cloud` is the share of the sky's light the clouds let through, read only with a `ray`.
    fn shade(self: *const Light, lv: *const grid.Level, torches: []const TorchIx, effects: EffectSet, q: [2]f32, map_at: ?usize, v: View, ray: ?*const SunRay, cloud: f32) Rgb {
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
        const ray: ?SunRay = if (self.profile()) |k| SunRay.of(k) else null;
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
            if (h.t == t and c.x >= h.box.lo.x and c.y >= h.box.lo.y and c.x < h.box.hi.x and c.y < h.box.hi.y) return self.heldCorners(c);
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
        const sub: f32 = @floatFromInt(SUB);
        const corners: [4]f32 = if (ray != null and !dark) self.heldCorners(c) else @splat(1);

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
        var ty = @max(t0.y, c.y * SUB);
        while (ty < @min(t1.y, (c.y + 1) * SUB)) : (ty += 1) {
            var tx = @max(t0.x, c.x * SUB);
            while (tx < @min(t1.x, (c.x + 1) * SUB)) : (tx += 1) {
                const i: usize = @intCast(ty * MAP_W + tx);
                self.glints[i] = rl.Color.blank;
                if (dark) {
                    self.map[i] = rl.Color.blank;
                    continue;
                }
                const q = [2]f32{ (@as(f32, @floatFromInt(tx)) + 0.5) / sub, (@as(f32, @floatFromInt(ty)) + 0.5) / sub };
                const v = viewOf(sightOf(&patch, ground, q[0], q[1]), q, &fade);
                const cloud = if (ray != null) cloudIn(corners, c, q) else 1;
                self.map[i] = texelOf(self.shade(lv, torches, effects, q, i, v, if (ray) |*r| r else null, cloud), v.lit);
                if (wet and v.lit > FAINT and lv.isLit(c))
                    self.glints[i] = colourOf(self.waterGlint(torches, effects, q, i, if (ray) |*r| r else null, cloud), 1);
            }
        }
    }

    fn waterGlint(self: *const Light, torches: []const TorchIx, effects: EffectSet, q: [2]f32, map_at: ?usize, ray: ?*const SunRay, cloud: f32) Rgb {
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
            gleam += rgbOf(s.col) * splat(smoothSpecular(.{ s.at[0] - q[0], s.at[1] - q[1], s.at[2] }, GLINT_POWER) * k * EFFECT_GLINT);
        }
        return gleam;
    }

    const View = struct { sight: f32, memory: f32, lit: f32 };

    fn viewAt(self: *const Light, q: [2]f32) View {
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
        const night: Rgb = if (self.profile()) |k| self.sunOnBody(&s, k, centre, lit) else splat(1);
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
            s.add(.{ .drawn = .{ p[0], p[1] - p[2] }, .ground = .{ p[0], p[1] }, .colour = rgbOf(e.source.col) * splat(k), .casts = true });
        }
        return s;
    }

    fn sunOnBody(self: *const Light, s: *Shine, k: sky.Sky, centre: [2]f32, lit: f32) Rgb {
        const ray = SunRay.of(k);
        const toward = ray.u;
        const sun = self.sunAt(&self.scratch, &ray, centre[0], centre[1], BODY_Z);
        const cloud = self.cloudAt(centre);
        const on = reaching(sun, self.composedCloud(centre, cloud));
        if (lit > 0) s.add(.{
            .drawn = .{ centre[0] + toward[0] * SUN_LAMP_D, centre[1] + toward[1] * SUN_LAMP_D },
            .ground = .{ centre[0] + toward[0], centre[1] + toward[1] },
            .colour = k.key * splat(lit * on),
            .casts = !sky.upright(ray.flat),
            .sky = .{ .reach = k.reach(), .depth = skyDepth(k, sun * cloud) * lit, .shade = ray.shade },
        });
        return ray.dim(sun, cloud);
    }

    /// A flame hangs on its wall's south face, so a wall seen only from behind shows none.
    pub fn flames(self: *const Light, lv: *const grid.Level, out: *[grid.MAX_TORCHES]Flame) []const Flame {
        var n: usize = 0;
        for (self.torch[0..self.torch_n]) |*t| {
            if (!self.remembers(lv, t.wall) or !self.remembers(lv, t.floor())) continue;
            const d = t.drawn();
            const v = self.viewAt(d);
            out[n] = .{ .at = d, .foot = t.flame()[1], .glow = t.glow, .lit = v.lit, .memory = v.memory };
            n += 1;
        }
        return out[0..n];
    }

    /// Needs a live GL context.
    pub fn load(self: *Light) void {
        self.gpu = Gpu.load();
    }

    pub fn syncFigures(self: *Light, figures: *const [look.FIGURES]?rl.Texture2D) void {
        self.gpu.syncFigures(figures);
    }

    pub fn clearFigures(self: *Light) void {
        self.gpu.syncFigures(&NO_FIGURES);
    }

    pub fn unload(self: *Light) void {
        self.gpu.unload();
        self.gpu = .{};
    }

    /// `ox, oy` is where the map's top-left corner lands on screen.
    pub fn drawMap(self: *Light, ox: i32, oy: i32, cell: i32) void {
        const tex = self.mapTexture() orelse return;
        rl.gl.rlSetBlendFactors(rl.gl.rl_dst_color, rl.gl.rl_src_color, rl.gl.rl_func_add);
        rl.beginBlendMode(.custom);
        defer rl.endBlendMode();
        look.overFloor(tex, ox, oy, cell);
    }

    pub fn mapTexture(self: *Light) ?rl.Texture2D {
        self.uploadMap();
        return self.gpu.map;
    }

    pub fn glintTexture(self: *Light) ?rl.Texture2D {
        self.uploadMap();
        return self.gpu.glints;
    }

    fn uploadMap(self: *Light) void {
        const tex = self.gpu.map orelse return;
        const from, const to = self.baked;
        if (to > from) {
            const rect = look.rect(0, from, MAP_W, to - from);
            rl.updateTextureRec(tex, rect, &self.map[@intCast(from * MAP_W)]);
            if (self.gpu.glints) |g| rl.updateTextureRec(g, rect, &self.glints[@intCast(from * MAP_W)]);
        }
        self.baked = NONE_BAKED;
    }

    /// `centre` is its middle, cells; `flash` is how far toward `FLASH_RGB` it is drawn.
    pub fn drawBody(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: *const Shine, flash: f32, fade_bounds: [2]f32) void {
        const w: f32 = @floatFromInt(tex.width);
        const h: f32 = @floatFromInt(tex.height);
        const src = look.rect(0, 0, if (left) -tex.width else tex.width, tex.height);
        const normals = self.gpu.art(tex).normals;
        const sh = self.gpu.body;
        if (sh == null or normals == null) {
            const fading = self.beginMirrorFade(fade_bounds);
            defer if (fading) rl.endShaderMode();
            look.blit(tex, src, dest, s.drawn(rl.Color.white, flash));
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
        look.setUniform(b.shader, b.size, size);
        look.setUniform(b.shader, b.flip, flip);
        look.setUniform(b.shader, b.ambient, ambient);
        look.setUniform(b.shader, b.count, n);
        look.setUniform(b.shader, b.flash, flash);
        look.setUniform(b.shader, b.fade_bounds, fade_bounds);
        rl.setShaderValueTexture(b.shader, b.normals, normals.?);
        if (s.n > 0) {
            look.setUniforms(b.shader, b.lpos, &pos, n);
            look.setUniforms(b.shader, b.lcol, &col, n);
        }
        look.blit(tex, src, dest, rl.Color.white);
        rl.gl.rlDrawRenderBatchActive();
    }

    pub fn footY(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle) f32 {
        return dest.y + self.gpu.art(tex).foot * dest.height / @as(f32, @floatFromInt(tex.height));
    }

    pub fn topY(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle) f32 {
        return dest.y + self.gpu.art(tex).top * dest.height / @as(f32, @floatFromInt(tex.height));
    }

    pub fn beginMirrorFade(self: *const Light, bounds: [2]f32) bool {
        if (bounds[0] >= bounds[1]) return false;
        const s = self.gpu.mirror_fade orelse return false;
        rl.beginShaderMode(s.shader);
        look.setUniform(s.shader, s.fade_bounds, bounds);
        return true;
    }

    fn footOf(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, s: *const Shine, contact: f32) ?struct { x: f32, y: f32, height: f32, share: f32 } {
        const lit = s.reached();
        if (lit <= FAINT) return null;
        const foot = self.gpu.art(tex).foot;
        const tall: f32 = @floatFromInt(tex.height);
        const share = foot / tall;
        const height = foot * dest.height / tall;
        const x = dest.x + dest.width * 0.5;
        const y = dest.y + height;
        if (self.gpu.glow) |g| {
            const a = CONTACT_A * @min(1, lit / lum(CARRY));
            glowAt(g, x, y, dest.width * CONTACT_W * 0.5 * contact, dest.width * CONTACT_H * 0.5 * contact, colourOf(SHADE_RGB, a));
        }
        return .{ .x = x, .y = y, .height = height, .share = share };
    }

    /// Shadows accumulate by minimum in a screen mask; `outer` restores the framebuffer. False without GL.
    pub fn beginShadows(self: *Light, screen: P, outer: u32) bool {
        const pool = self.gpu.shade orelse return false;
        if (self.gpu.shadow == null or self.gpu.receiver == null or self.gpu.map == null) return false;
        self.gpu.outer = outer;
        if (!look.beginTarget(&self.gpu.mask, screen, outer, rl.Color.white)) return false;
        rl.gl.rlSetBlendFactors(rl.gl.rl_one, rl.gl.rl_one, rl.gl.rl_min);
        rl.beginBlendMode(.custom);
        rl.beginShaderMode(pool);
        return true;
    }

    pub fn endShadows(self: *Light, ox: i32, oy: i32, cell: i32) void {
        self.flushForest();
        rl.endShaderMode();
        rl.endBlendMode();
        rl.gl.rlEnableFramebuffer(self.gpu.outer);
        const t = self.gpu.mask.?.texture;
        self.uploadMap();
        const receiver = self.gpu.receiver.?;
        const floor = look.floorRect(ox, oy, cell);
        const map_rect = [4]f32{ floor.x, floor.y, floor.width, floor.height };
        const screen = [2]f32{ @floatFromInt(t.width), @floatFromInt(t.height) };
        rl.beginBlendMode(.multiplied);
        defer rl.endBlendMode();
        rl.beginShaderMode(receiver.shader);
        defer rl.endShaderMode();
        rl.setShaderValueTexture(receiver.shader, receiver.lightmap, self.gpu.map.?);
        look.setUniform(receiver.shader, receiver.map_rect, map_rect);
        look.setUniform(receiver.shader, receiver.screen, screen);
        look.drawTarget(t);
    }

    /// Between `beginShadows` and `endShadows`, before the walls, which cover whatever of it reaches them.
    pub fn drawShadows(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: *const Shine) void {
        const f = self.footOf(tex, dest, s, 1) orelse return;
        const fx = f.x;
        const fy = f.y;
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(s, centre, f.height, &buf);
        if (cs.len == 0) return;
        const foot = f.share;
        if (!self.beginSilhouettes(tex, foot, (Sides{}).uniform(), .{ SHADOW_SOFT_TIP, SHADOW_SOFT_FOOT })) return;
        for (cs) |c| {
            if (c.solid <= 0) continue;
            var full = c;
            full.alpha *= c.solid;
            silhouette(tex, fx, fy, dest.width, foot, left, full);
        }
        self.endSilhouettes();
        const g = self.gpu.streak orelse return;
        for (cs) |c| {
            if (c.solid < 1) streak(g, fx, fy, dest.width, c);
        }
    }

    /// Between `beginShadows` and `endShadows`: a tree's canopy pool thrown away from each light, a soft pool over its trunk's foot.
    pub fn drawCanopy(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, centre: [2]f32, s: *const Shine) void {
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

    /// Contact draws now; silhouettes batch by joined sides at `endShadows`.
    pub fn drawForestShadows(self: *Light, tex: rl.Texture2D, dest: rl.Rectangle, centre: [2]f32, s: *const Shine, shape: grid.WallShape) void {
        _ = self.footOf(tex, dest, s, 1) orelse return;
        var f = ForestCast{ .tex = tex, .dest = dest, .centre = centre, .cast = undefined, .n = 0, .joined = .of(shape) };
        f.n = casts(s, centre, dest.height, &f.cast).len;
        if (f.n == 0) return;
        if (self.forest_n == FOREST_QUEUE) self.flushForest();
        self.forest[self.forest_n] = f;
        self.forest_n += 1;
    }

    fn flushForest(self: *Light) void {
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
                if (drawing != null) self.endSilhouettes();
                if (!self.beginSilhouettes(f.tex, 1, f.joined.uniform(), .{ FOREST_SOFT, FOREST_SOFT })) return;
                drawing = .{ .joined = f.joined, .size = size };
            }
            for (f.cast[0..f.n]) |c| forestQuads(f.tex, f.dest, f.centre, c, colourOf(c.shade, @min(FOREST_MAX, c.alpha * FOREST_A)));
        }
        if (drawing != null) self.endSilhouettes();
    }

    /// `joined` is (w, e, n, s); `softness` is (tip, foot). End with `endSilhouettes`.
    fn beginSilhouettes(self: *const Light, tex: rl.Texture2D, foot: f32, joined: [4]f32, softness: [2]f32) bool {
        const sh = self.gpu.shadow orelse return false;
        const size = [2]f32{ @floatFromInt(tex.width), @floatFromInt(tex.height) };
        rl.beginShaderMode(sh.shader);
        look.setUniform(sh.shader, sh.size, size);
        look.setUniform(sh.shader, sh.foot, foot);
        look.setUniform(sh.shader, sh.joined, joined);
        look.setUniform(sh.shader, sh.softness, softness);
        return true;
    }

    fn endSilhouettes(self: *const Light) void {
        rl.gl.rlDrawRenderBatchActive();
        rl.beginShaderMode(self.gpu.shade.?);
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
const Cast = struct { lean: [2]f32, len: f32, solid: f32, alpha: f32, shade: Rgb, source: ?[2]f32 = null };

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
        inline for (std.meta.fields(Sides), &out) |f, *o| o.* = mask(@field(self, f.name));
        return out;
    }
};
const ForestCast = struct { tex: rl.Texture2D, dest: rl.Rectangle, centre: [2]f32, cast: [BODY_LIGHTS]Cast, n: usize, joined: Sides };
const FOREST_QUEUE: usize = 2048;
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
fn casts(s: *const Shine, centre: [2]f32, height: f32, out: *[BODY_LIGHTS]Cast) []const Cast {
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
        const lean = if (l.sky) |k| [2]f32{ dx / d * height * k.reach, dy / d * height * k.reach } else lampLean(.{ dx, dy }, height);
        out[n] = .{ .lean = lean, .len = mathx.len(lean[0], lean[1]), .solid = solidity(lean), .alpha = alpha, .shade = if (l.sky) |k| k.shade else SHADE_RGB, .source = if (l.sky == null) l.ground else null };
        n += 1;
    }
    return out[0..n];
}

fn lampRise(dy_d: f32) f32 {
    return dy_d * SHADOW_SQUASH;
}

fn lampLean(delta: [2]f32, height: f32) [2]f32 {
    const d = mathx.len(delta[0], delta[1]);
    if (d < SHADOW_OVERHEAD) return .{ 0, 0 };
    const len = height * std.math.clamp(SHADOW_LEN_LO + SHADOW_LEN_PER_CELL * d, SHADOW_LEN_LO, SHADOW_LEN_HI);
    return .{ delta[0] / d * len, lampRise(delta[1] / d) * len };
}

fn forestTip(c: Cast, centre: [2]f32, uv: [2]f32, height: f32) [2]f32 {
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
    texQuad(tex, colourOf(c.shade, c.alpha), if (mirrored) .{ corners[3], corners[2], corners[1], corners[0] } else corners);
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

const MIRROR_HEAD = look.FS_HEAD ++
    \\uniform vec2 fade_bounds;
    \\float mirrorFade() {
    \\    if (fade_bounds.x >= fade_bounds.y) return 1.0;
    \\    return smoothstep(fade_bounds.x, fade_bounds.y, gl_FragCoord.y);
    \\}
++ "\n";

const MIRROR_FS = MIRROR_HEAD ++
    \\void main() {
    \\    finalColor = texture(texture0, fragTexCoord) * fragColor;
    \\    finalColor.a *= mirrorFade();
    \\}
;

const BODY_FS = MIRROR_HEAD ++ std.fmt.comptimePrint(
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
    \\    finalColor.a *= mirrorFade();
    \\}
;

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

const RECEIVER_FS = look.FS_HEAD ++
    \\uniform sampler2D lightmap;
    \\uniform vec4 map_rect;
    \\uniform vec2 screen;
    \\void main() {
    \\    vec2 pixel = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y) * screen;
    \\    vec2 uv = (pixel - map_rect.xy) / map_rect.zw;
    \\    float sight = texture(lightmap, uv).a;
    \\    vec3 shadow = texture(texture0, fragTexCoord).rgb;
    \\    finalColor = vec4(mix(vec3(1.0), shadow, sight), 1.0);
    \\}
;

const ReceiverShader = struct {
    shader: rl.Shader,
    lightmap: i32,
    map_rect: i32,
    screen: i32,
};

const SHADOW_FS = POOL_HEAD ++ std.fmt.comptimePrint(
    "const int TAPS = {d};\n",
    .{SHADOW_TAPS},
) ++
    \\uniform vec2 size;
    \\uniform float foot;
    \\uniform vec4 joined;
    \\uniform vec2 softness;
    \\float alphaAt(vec2 uv) {
    \\    if ((uv.x < 0.0 && joined.x < 0.5) || (uv.x > 1.0 && joined.y < 0.5)) return 0.0;
    \\    if ((uv.y < 0.0 && joined.z < 0.5) || (uv.y > foot && joined.w < 0.5)) return 0.0;
    \\    return texture(texture0, clamp(uv, vec2(0.0), vec2(1.0, foot))).a;
    \\}
    \\void main() {
    \\    float spread = mix(softness.x, softness.y, clamp(fragTexCoord.y / foot, 0.0, 1.0));
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
    fade_bounds: i32,
};

const MirrorShader = struct { shader: rl.Shader, fade_bounds: i32 };

const ShadowShader = struct {
    shader: rl.Shader,
    size: i32,
    foot: i32,
    joined: i32,
    softness: i32,
};

const Art = struct {
    id: u32,
    top: f32,
    /// Texel rows from the sprite's top to just under its lowest opaque row.
    foot: f32,
    normals: ?rl.Texture2D,

    fn bare(t: rl.Texture2D) Art {
        return .{ .id = t.id, .top = 0, .foot = @floatFromInt(t.height), .normals = null };
    }
};

/// Texels in from the silhouette over which a body's edge rounds off, and how steeply.
const BEVEL_PX: i32 = 5;
const BEVEL_DEPTH: f32 = 2.0;
const ART_MAX: i32 = 2 * look.SPRITE_PX;
const SOLID_A: u8 = 25;

const NO_FIGURES: [look.FIGURES]?rl.Texture2D = @splat(null);

const Gpu = struct {
    map: ?rl.Texture2D = null,
    glints: ?rl.Texture2D = null,
    glow: ?rl.Texture2D = null,
    streak: ?rl.Texture2D = null,
    body: ?BodyShader = null,
    mirror_fade: ?MirrorShader = null,
    shadow: ?ShadowShader = null,
    receiver: ?ReceiverShader = null,
    shade: ?rl.Shader = null,
    /// The screen's shadows, white where there are none; sized to the screen when drawn.
    mask: ?rl.RenderTexture2D = null,
    /// The framebuffer the mask was drawn from, to go back to.
    outer: u32 = 0,
    arts: [look.FIGURES]?Art = @splat(null),

    fn load() Gpu {
        var g = Gpu{};
        g.map = look.canvas(MAP_W, MAP_H, rl.Color.blank, .bilinear);
        g.glints = look.canvas(MAP_W, MAP_H, rl.Color.blank, .bilinear);
        g.glow = look.radial(GLOW_PX, glowAlpha);
        g.streak = look.field(STREAK_PX[0], STREAK_PX[1], streakAlpha);
        g.body = look.program(BodyShader, BODY_FS);
        g.mirror_fade = look.program(MirrorShader, MIRROR_FS);
        g.shadow = look.program(ShadowShader, SHADOW_FS);
        g.receiver = look.program(ReceiverShader, RECEIVER_FS);
        g.shade = look.shader(SHADE_FS);
        return g;
    }

    fn syncFigures(g: *Gpu, figures: *const [look.FIGURES]?rl.Texture2D) void {
        for (&g.arts, figures, 0..) |*held, tex, i| {
            if (held.*) |a| {
                if (tex) |t| {
                    if (a.id == t.id) continue;
                }
                if (a.normals) |t| rl.unloadTexture(t);
            }
            held.* = if (tex) |t| artOf(t, i < look.LIT_FIGURES) else null;
        }
    }

    fn unload(g: *Gpu) void {
        look.unloadAll(g);
        g.syncFigures(&NO_FIGURES);
    }

    fn art(g: *const Gpu, t: rl.Texture2D) Art {
        for (&g.arts) |*held| {
            if (held.*) |*a| if (a.id == t.id) return a.*;
        }
        return Art.bare(t);
    }
};

fn artOf(t: rl.Texture2D, lit: bool) Art {
    var a = Art.bare(t);
    if (t.width > ART_MAX or t.height > ART_MAX) return a;
    const img = rl.loadImageFromTexture(t) catch return a;
    defer rl.unloadImage(img);
    var solid: [ART_MAX * ART_MAX]bool = undefined;
    const w: usize = @intCast(t.width);
    for (0..@intCast(t.height)) |y| {
        for (0..w) |x| solid[y * w + x] = rl.getImageColor(img, @intCast(x), @intCast(y)).a > SOLID_A;
    }
    for (0..@intCast(t.height)) |top| {
        if (rowSolid(&solid, t.width, @intCast(top))) {
            a.top = @floatFromInt(top);
            break;
        }
    }
    var y: i32 = t.height - 1;
    while (y >= 0) : (y -= 1) {
        if (rowSolid(&solid, t.width, y)) {
            a.foot = @floatFromInt(y + 1);
            break;
        }
    }
    if (lit) a.normals = bevelNormals(&solid, t.width, t.height);
    return a;
}

fn rowSolid(solid: *const [ART_MAX * ART_MAX]bool, w: i32, y: i32) bool {
    var x: i32 = 0;
    while (x < w) : (x += 1) {
        if (solid[@intCast(y * w + x)]) return true;
    }
    return false;
}

/// Laigter soft bevel: quarter-circle height from clear-pixel distance; `solid` is packed width-first.
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
            const gx = texel(&height, w, h, x + 1, y) - texel(&height, w, h, x - 1, y);
            const gy = texel(&height, w, h, x, y + 1) - texel(&height, w, h, x, y - 1);
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

const gen = @import("../map/gen.zig");
const day = @import("../map/day.zig");

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

test "effect lights shade terrain and bodies without revealing memory or crossing walls" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    for (0..grid.H) |y| lv.set(.{ .x = 22, .y = @intCast(y) }, .wall);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const near = [2]f32{ 21.5, 20.5 };
    const far = [2]f32{ 23.5, 20.5 };
    const before = l.at(&lv, &.{}, near);
    const hidden = l.at(&lv, &.{}, far);
    const sight = lv.lit;
    const seen = lv.seen;
    l.emit(&lv, .{ .at = .{ 20.5, 20.5, 0.4 }, .col = look.FIRE, .radius = 4, .gain = 1 });
    try std.testing.expect(lum(l.at(&lv, &.{}, near)) > lum(before) + 0.1);
    try std.testing.expectEqual(hidden, l.at(&lv, &.{}, far));
    try std.testing.expect(l.onBody(near, false).n > 0);
    try std.testing.expectEqual(@as(usize, 0), l.onBody(far, false).n);
    try std.testing.expectEqualSlices(bool, &sight, &lv.lit);
    try std.testing.expectEqualSlices(bool, &seen, &lv.seen);
    lv.lit[grid.Level.idx(.{ .x = 21, .y = 20 })] = false;
    l.settle(&lv);
    const memory = l.at(&lv, &.{}, near);
    l.emit(&lv, .{ .at = .{ 20.5, 20.5, 0.4 }, .col = look.COLD, .radius = 4, .gain = 1 });
    try std.testing.expectEqual(memory, l.at(&lv, &.{}, near));
    l.effect_n = 0;
    lv.lit[grid.Level.idx(.{ .x = 20, .y = 20 })] = false;
    l.emit(&lv, .{ .at = .{ 20.5, 20.5, 0.4 }, .col = look.FIRE, .radius = 4, .gain = 1 });
    try std.testing.expectEqual(@as(usize, 0), l.effect_n);
    std.debug.print("effect lighting: floor and body lit; wall, memory and hidden source blocked; visibility unchanged\n", .{});
}

test "effect reach bounds preserve lighting at fractional positions and map edges" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    for (18..25) |x| lv.set(.{ .x = @intCast(x), .y = 21 }, .wall);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const positions = [_][2]f32{ .{ 0.01, 0.99 }, .{ 20.5, 20.5 }, .{ 21.001, 20.999 }, .{ @as(f32, @floatFromInt(grid.W)) - 0.01, @as(f32, @floatFromInt(grid.H)) - 0.01 } };
    const radii = [_]f32{ 0.1, 0.6, 1, 1.6, 2.2, 2.8, 4, 8 };
    const offsets = [_]f32{ 0.001, 0.5, 0.999 };
    const heights = [_]f32{ 0, 0.4, 1.4 };
    var samples: usize = 0;
    var lit: usize = 0;
    for (positions) |at| {
        for (radii) |radius| {
            l.effect_n = 0;
            l.emit(&lv, .{ .at = .{ at[0], at[1], 0.4 }, .col = look.FIRE, .radius = radius, .gain = 1 });
            try std.testing.expectEqual(@as(usize, 1), l.effect_n);
            const bounded = &l.effects[0];
            var reference = bounded.*;
            for (&reference.reach, 0..) |*reached, i| {
                const p = P{ .x = reference.origin.x + @as(i32, @intCast(i % EFFECT_SPAN)) - EFFECT_REACH, .y = reference.origin.y + @as(i32, @intCast(i / EFFECT_SPAN)) - EFFECT_REACH };
                reached.* = grid.Level.inside(p) and grid.clearLine(&lv, reference.origin, p);
                for (offsets) |dx| {
                    for (offsets) |dy| {
                        for (heights) |z| {
                            const x = @as(f32, @floatFromInt(p.x)) + dx;
                            const y = @as(f32, @floatFromInt(p.y)) + dy;
                            const expected = reference.strength(x, y, z);
                            try std.testing.expectEqual(expected, bounded.strength(x, y, z));
                            samples += 1;
                            if (expected > 0) lit += 1;
                        }
                    }
                }
            }
        }
    }
    try std.testing.expect(lit > 0);
    std.debug.print("effect reach bounds: {d} samples unchanged, including {d} lit samples across {d} positions and {d} radii\n", .{ samples, lit, positions.len, radii.len });
}

test "cell effect culling preserves floor wall and water lighting" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    for (18..25) |x| lv.set(.{ .x = @intCast(x), .y = 21 }, .wall);
    @import("../map/procgen.zig").reshape(&lv);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const radii = [_]f32{ 0.6, 1.6, 2.8, 4 };
    const heights = [_]f32{ 0, 0.3, 1.4 };
    var all = EffectSet.initEmpty();
    for (0..EFFECTS) |i| {
        l.emit(&lv, .{
            .at = .{ 16.2 + @as(f32, @floatFromInt(i % 8)) * 2.4, 14.9 + @as(f32, @floatFromInt(i / 8)) * 2.7, heights[i % heights.len] },
            .col = if (i % 2 == 0) look.FIRE else look.COLD,
            .radius = radii[i % radii.len],
            .gain = 0.8,
        });
        all.set(i);
    }
    var cells = grid.Cells.of(.{ .x = 14, .y = 14 }, .{ .x = 38, .y = 32 });
    var samples: usize = 0;
    var candidates: usize = 0;
    var surfaces = std.EnumSet(Surface).initEmpty();
    const sub: usize = SUB;
    while (cells.next()) |c| {
        const kept = l.effectsNear(c);
        for (0..sub * sub) |i| {
            const q = [2]f32{
                @as(f32, @floatFromInt(c.x)) + (@as(f32, @floatFromInt(i % sub)) + 0.5) / SUB,
                @as(f32, @floatFromInt(c.y)) + (@as(f32, @floatFromInt(i / sub)) + 0.5) / SUB,
            };
            const v = l.viewAt(q);
            surfaces.insert(Spot.of(&lv, q).surface);
            try std.testing.expectEqual(l.shade(&lv, &.{}, all, q, null, v, null, 1), l.shade(&lv, &.{}, kept, q, null, v, null, 1));
            try std.testing.expectEqual(l.waterGlint(&.{}, all, q, null, null, 1), l.waterGlint(&.{}, kept, q, null, null, 1));
            samples += 1;
            candidates += kept.count();
        }
    }
    try std.testing.expectEqual(@as(usize, 3), surfaces.count());
    try std.testing.expect(candidates < samples * EFFECTS / 4);
    std.debug.print("effect culling: {d} floor/wall/glint samples unchanged; {d} of {d} light candidates retained\n", .{ samples, candidates, samples * EFFECTS });
}

test "smooth water glints follow light direction and respect walls and memory" {
    try std.testing.expectApproxEqAbs(@as(f32, 1), smoothSpecular(.{ 0, -1, 1 }, GLINT_POWER), 1e-4);
    try std.testing.expect(smoothSpecular(.{ 1, -1, 1 }, GLINT_POWER) < 0.03);
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    for (&lv.tile) |*tile| {
        if (tile.* == .floor) tile.* = .shallows;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const flame = l.torch[0].flame();
    const at = [2]f32{ flame[0], flame[1] + flame[2] };
    const lit = lum(l.waterGlint(&.{0}, .initEmpty(), at, null, null, 1));
    try std.testing.expect(lit > 0.01 and lit < 0.2);
    try std.testing.expectEqual(@as(f32, 0), lum(l.waterGlint(&.{0}, .initEmpty(), .{ flame[0], 9.5 }, null, null, 1)));
    const before = lv.lit;
    l.bake(&lv, .{ .x = 18, .y = 10 }, .{ .x = 23, .y = 15 });
    var hits: usize = 0;
    for (l.glints) |pixel| {
        if (pixel.r > 0 or pixel.g > 0 or pixel.b > 0) hits += 1;
    }
    try std.testing.expect(hits > 0);
    try std.testing.expectEqualSlices(bool, &before, &lv.lit);
    @memset(&lv.lit, false);
    l.settle(&lv);
    l.bake(&lv, .{ .x = 18, .y = 10 }, .{ .x = 23, .y = 15 });
    for (l.glints) |pixel| try std.testing.expectEqual(rl.Color.blank, pixel);
    std.debug.print("smooth water: {d} glint texels, peak {d:.3}; wall and memory blocked; visibility unchanged\n", .{ hits, lit });
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

test "forest shadow edges project together under torches and the sky" {
    const a = [2]f32{ 20.5, 20.5 };
    var checked: usize = 0;
    for ([_]?[2]f32{ null, .{ 20.5, 17.3 }, .{ 15.5, 20.5 }, .{ 26.5, 25.5 } }) |source| {
        const cast = Cast{ .lean = .{ 40, -12 }, .len = 42, .solid = 1, .alpha = 0.7, .shade = SHADE_RGB, .source = source };
        for (0..2) |axis| {
            var b = a;
            b[axis] += 1;
            for (0..17) |i| {
                const across = @as(f32, @floatFromInt(i)) / 16;
                var auv = [2]f32{ across, across };
                var buv = auv;
                auv[axis] = 1;
                buv[axis] = 0;
                const left = forestTip(cast, a, auv, ART_H);
                const right = forestTip(cast, b, buv, ART_H);
                for (0..2) |k| try std.testing.expectApproxEqAbs(left[k], right[k], 1e-5);
                checked += 1;
            }
        }
    }
    std.debug.print("{d} shared forest shadow edge points agree under 3 torches and the sky\n", .{checked});
}

test "shadow casters keep their light outside sight and memory" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const centre = [2]f32{ 20.5, 13.5 };
    l.carrier = .{ 22.5, 14.5 };
    @memset(&lv.los, true);
    var checked: usize = 0;
    for ([_]?f32{ day.NOON, day.DEAD_OF_NIGHT, null }) |hour| {
        l.sky = if (hour) |h| sky.at(h) else null;
        @memset(&lv.lit, true);
        @memset(&lv.seen, true);
        l.settle(&lv);
        var before: [BODY_LIGHTS]Cast = undefined;
        const expected = casts(&l.onCaster(centre, false), centre, ART_H, &before);
        try std.testing.expect(expected.len > 0);
        for ([_]bool{ false, true }) |remembered_| {
            @memset(&lv.lit, false);
            @memset(&lv.seen, remembered_);
            l.settle(&lv);
            var after: [BODY_LIGHTS]Cast = undefined;
            const actual = casts(&l.onCaster(centre, false), centre, ART_H, &after);
            try std.testing.expectEqualSlices(Cast, expected, actual);
            try std.testing.expectEqual(@as(usize, 0), casts(&l.onBody(centre, false), centre, ART_H, &after).len);
            checked += actual.len;
        }
    }
    std.debug.print("{d} sun, moon and torch casts unchanged outside sight and memory; hidden bodies cast none through their draw lighting\n", .{checked});
}

test "a contact pool needs a light: memory's floor reaches nothing" {
    var lv = grid.openFloor();
    @memset(&lv.los, true);
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const centre = [2]f32{ 20.5, 13.5 };
    l.sky = null;
    l.carrier = null;
    l.settle(&lv);
    const dark = l.onCaster(centre, false);
    l.carrier = .{ 21.5, 13.5 };
    l.settle(&lv);
    const lantern = l.onCaster(centre, false);
    l.carrier = null;
    l.sky = sky.at(day.NOON);
    l.settle(&lv);
    const noon = l.onCaster(centre, false);
    std.debug.print("light reaching a body: dark {d:.3} (drawn {d:.3}), lantern {d:.3}, noon {d:.3}\n", .{ dark.reached(), dark.lit(), lantern.reached(), noon.reached() });
    try std.testing.expect(dark.reached() <= FAINT);
    try std.testing.expect(dark.lit() > FAINT);
    try std.testing.expect(lantern.reached() > FAINT);
    try std.testing.expect(noon.reached() > FAINT);
}

test "shadow receivers fade at sight and disappear in remembered or unseen ground" {
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        lv.seen[i] = p.x < 30;
        lv.lit[i] = p.x < 20;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.sky = sky.at(day.NOON);
    l.bake(&lv, .{ .x = 10, .y = 20 }, .{ .x = 40, .y = 21 });
    var live: usize = 0;
    var faded: usize = 0;
    var remembered_: usize = 0;
    var unseen: usize = 0;
    for (10 * SUB..40 * SUB) |x| {
        const c = l.map[20 * SUB * MAP_W + x];
        if (x < 18 * SUB) {
            try std.testing.expectEqual(@as(u8, 255), c.a);
            live += 1;
        } else if (x > 22 * SUB and x < 28 * SUB) {
            try std.testing.expectEqual(@as(u8, 0), c.a);
            try std.testing.expect(c.r > 0);
            remembered_ += 1;
        } else if (x >= 30 * SUB) {
            try std.testing.expectEqual(rl.Color.blank, c);
            unseen += 1;
        } else if (c.a > 0 and c.a < 255) faded += 1;
    }
    try std.testing.expect(faded > 0);
    std.debug.print("shadow receivers: {d} fully visible, {d} fading, {d} memory and {d} unseen texels with no live shadow\n", .{ live, faded, remembered_, unseen });
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
    while (frames < 600 and !done(lum(l.at(lv, none, q)))) : (frames += 1) l.step(lv, mathx.FRAME_DT);
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
    const ms = struct {
        fn of(frames: usize) f32 {
            return @as(f32, @floatFromInt(frames)) * mathx.FRAME_DT * 1000;
        }
    }.of;
    std.debug.print("fog: 95% of the way into sight in {d:.0} ms, out of it to memory in {d:.0} ms\n", .{ ms(up), ms(down) });
    try std.testing.expect(up > 0 and ms(up) < 333);
    try std.testing.expect(down > up and ms(down) < 1000);
    for (0..600) |_| l.step(&lv, mathx.FRAME_DT);
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
    l.sky = sky.at(day.NOON);
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
    for (0..4) |_| l.step(&lv, mathx.FRAME_DT);
    l.bake(&lv, .{ .x = 0, .y = 0 }, grid.SIZE);
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
        const want = texelOf(l.at(&lv, torches, q), l.viewAt(q).lit);
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
    const minute: usize = @intFromFloat(@round(60 / mathx.FRAME_DT));
    while (i < minute) : (i += 1) {
        const v = flicker(@as(f32, @floatFromInt(i)) * mathx.FRAME_DT, 7);
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
    var s = Shine{ .ambient = MEMORY };
    s.add(.{ .drawn = .{ 40.5, 30.5 }, .ground = .{ 40.5, 30.5 }, .colour = splat(1), .casts = true });
    var last: f32 = 0;
    var worst: f32 = 0;
    for (0..201) |i| {
        const dx = (@as(f32, @floatFromInt(i)) - 100) / 100;
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(&s, .{ 40.5 + dx, 30.5 }, ART_H, &buf);
        const alpha = if (cs.len == 0) 0 else cs[0].alpha;
        if (i > 0) worst = @max(worst, @abs(alpha - last));
        if (@abs(dx) <= SHADOW_OVERHEAD) try std.testing.expectEqual(@as(f32, 0), alpha);
        last = alpha;
    }
    std.debug.print("torch shadow passing under the light: largest alpha step {d:.4}\n", .{worst});
    try std.testing.expect(worst < 0.04);
}

test "torch shadow crosses its light's horizontal line without flipping" {
    var s = Shine{ .ambient = MEMORY };
    s.add(.{ .drawn = .{ 43.5, 30.5 }, .ground = .{ 43.5, 30.5 }, .colour = splat(1), .casts = true });
    var last: ?[2]f32 = null;
    var worst: f32 = 0;
    for (0..41) |i| {
        const dy = (@as(f32, @floatFromInt(i)) - 20) / 1000;
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(&s, .{ 40.5, 30.5 + dy }, ART_H, &buf);
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
    l.sky = sky.at(day.DEAD_OF_NIGHT);
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
        lume.see(&lv, from, actor.row(.archer).sight, 0, &.{.{ .at = from, .reach = actor.row(.archer).light }});
        const l = try testLight(&lv);
        defer std.testing.allocator.destroy(l);
        l.sky = sky.at(day.DEAD_OF_NIGHT);
        const to = from.add(.{ .x = 1, .y = 1 });
        lume.see(&lv, to, actor.row(.archer).sight, 0, &.{.{ .at = to, .reach = actor.row(.archer).light }});
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

test "cinema lighting stays subtle and leaves night and indoor light unchanged" {
    var lv = grid.openFloor();
    lv.set(.{ .x = 20, .y = 20 }, .shrub);
    lv.set(.{ .x = 21, .y = 20 }, .swamp_tree);
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.carrier = null;
    var changed: usize = 0;
    var lowest: f32 = 1;
    var highest: f32 = 1;
    for ([_]?sky.Sky{ null, sky.at(day.NOON), sky.at(day.DEAD_OF_NIGHT) }) |k| {
        l.sky = k;
        for (0..100) |i| {
            const q = [2]f32{ 17 + @as(f32, @floatFromInt(i % 10)) * 0.5, 18 + @as(f32, @floatFromInt(i / 10)) * 0.5 };
            l.composed = false;
            const plain = l.at(&lv, &.{}, q);
            l.composed = true;
            const composed = l.at(&lv, &.{}, q);
            if (k == null or k.?.moon == 1) {
                try std.testing.expectEqual(plain, composed);
            } else {
                const ratio = lum(composed) / lum(plain);
                lowest = @min(lowest, ratio);
                highest = @max(highest, ratio);
                try std.testing.expect(ratio > 0.75 and ratio < 1.1);
                changed += @intFromBool(@abs(ratio - 1) > 0.002);
            }
        }
    }
    try std.testing.expect(changed > 50);
    std.debug.print("cinema lighting: {d} daylight samples changed, {d:.1}-{d:.1}% of baseline; 200 night/indoor samples identical\n", .{ changed, lowest * 100, highest * 100 });
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

test "the carried light reaches no remembered floor behind a wall" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    lv.lightless();
    lv.seen = @splat(true);
    const at = P{ .x = 30, .y = TORCH_AT.y + 1 };
    lume.see(&lv, at, actor.row(.archer).sight, 0, &.{.{ .at = at, .reach = actor.row(.archer).light }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const wy: f32 = @floatFromInt(TORCH_AT.y);
    const spots = [_][2]f32{ .{ 30.5, wy - EDGE_EPS }, .{ 31.5, wy - 0.5 } };
    var dark: [spots.len]f32 = undefined;
    for (spots, &dark) |q, *d| d.* = lum(l.at(&lv, &.{}, q));
    l.carrier = mathx.centre(at);
    std.debug.print("carried light added behind a wall:", .{});
    for (spots, dark) |q, d| {
        const v = lum(l.at(&lv, &.{}, q)) - d;
        std.debug.print(" {d:.4}", .{v});
        try std.testing.expectApproxEqAbs(@as(f32, 0), v, 1e-5);
    }
    const front = lum(l.at(&lv, &.{}, .{ 30.5, wy + 1 + EDGE_EPS }));
    std.debug.print(", at its front {d:.4}\n", .{front - lum(MEMORY)});
    try std.testing.expect(front > lum(MEMORY) + 0.05);
}

test "daylight reaches no remembered floor behind a wall in sight" {
    var lv = grid.openFloor();
    var x: i32 = 1;
    while (x < grid.W - 1) : (x += 1) lv.set(.{ .x = x, .y = TORCH_AT.y }, .wall);
    gen.shapeWalls(&lv);
    for (0..grid.CELLS) |i| {
        lv.seen[i] = true;
        lv.lit[i] = grid.Level.of(i).y >= TORCH_AT.y;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.sky = sky.at(day.NOON);
    const wy: f32 = @floatFromInt(TORCH_AT.y);
    std.debug.print("noon behind a wall in sight, over memory:", .{});
    for ([_][2]f32{ .{ 30.5, wy - 1.5 }, .{ 30.5, wy - 0.5 }, .{ 30.5, wy - EDGE_EPS } }) |q| {
        const v = lum(l.at(&lv, &.{}, q)) - lum(MEMORY);
        std.debug.print(" {d:.4}", .{v});
        try std.testing.expectApproxEqAbs(@as(f32, 0), v, 1e-5);
    }
    const front = lum(l.at(&lv, &.{}, .{ 30.5, wy + 1.5 }));
    std.debug.print(", in front {d:.4}\n", .{front - lum(MEMORY)});
    try std.testing.expect(front > lum(MEMORY) + 0.1);
}

test "a cell is clear exactly when every cell within its fade's reach is wholly remembered" {
    var lv = grid.openFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var rng = mathx.Rng.init(0xC1EA);
    const r = VOID_REACH;
    var n: usize = 0;
    for (0..20) |_| {
        for (&l.memory) |*m| m.* = if (rng.percent(97)) 1 else 0.5;
        l.soften();
        for (0..grid.CELLS) |i| {
            const c = grid.Level.of(i);
            var want = c.x >= r and c.y >= r and c.x + r < grid.W and c.y + r < grid.H;
            var box = grid.Cells.around(c, r);
            while (box.next()) |p| want = want and l.memoryAt(p) >= 1;
            try std.testing.expectEqual(want, l.clear[i]);
            if (want) n += 1;
        }
    }
    std.debug.print("20 memories: {d} cells clear, each as the box round it says\n", .{n});
    try std.testing.expect(n > 0);
}

test "sight has no step where it ends along a wall, nor as it eases out behind one" {
    var lv = grid.openFloor();
    var x: i32 = 1;
    while (x < grid.W - 1) : (x += 1) lv.set(.{ .x = x, .y = TORCH_AT.y }, .wall);
    gen.shapeWalls(&lv);
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        lv.seen[i] = true;
        lv.lit[i] = p.y >= TORCH_AT.y and p.x <= 30;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const fy: f32 = @floatFromInt(TORCH_AT.y + 1);
    const step = l.sightAt(31 + EDGE_EPS, fy + 0.5) - l.sightAt(31 - EDGE_EPS, fy + 0.5);
    const behind = grid.Level.idx(.{ .x = 20, .y = TORCH_AT.y - 1 });
    l.sight[behind] = 2 * mathx.SETTLE;
    l.soften();
    const easing = l.sightAt(20.5, fy - 1.5);
    l.sight[behind] = 0;
    l.soften();
    const gone = l.sightAt(20.5, fy - 1.5);
    std.debug.print("sight across its edge along a wall: {d:.4}; behind a wall, easing out {d:.4}, then gone {d:.4}\n", .{ step, easing, gone });
    try std.testing.expectApproxEqAbs(@as(f32, 0), step, 1e-3);
    try std.testing.expectApproxEqAbs(gone, easing, 1e-2);
}

test "sight has no step where open ground meets a shrub at its edge" {
    var lv = grid.openFloor();
    const shrub = P{ .x = 30, .y = 20 };
    lv.set(shrub, .shrub);
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        lv.seen[i] = true;
        lv.lit[i] = p.x <= shrub.x or p.y != shrub.y;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const y: f32 = @as(f32, @floatFromInt(shrub.y)) + 0.5;
    const x: f32 = @floatFromInt(shrub.x + 1);
    const past = l.sightAt(x + EDGE_EPS, y);
    const step = past - l.sightAt(x - EDGE_EPS, y);
    const own = l.open_sight[grid.Level.idx(.{ .x = shrub.x + 1, .y = shrub.y })];
    std.debug.print("sight across a shrub's edge where sight ends: {d:.4}; just past it {d:.4}, its ground's own {d:.4}\n", .{ step, past, own });
    try std.testing.expectApproxEqAbs(@as(f32, 0), step, 1e-3);
    try std.testing.expectApproxEqAbs(own, past, 1e-3);
}

test "sight has no step through a shrub clump, nor as the ground behind a hedge is first seen" {
    var lv = grid.openFloor();
    for ([_]P{ .{ .x = 30, .y = 20 }, .{ .x = 31, .y = 20 }, .{ .x = 30, .y = 21 }, .{ .x = 31, .y = 21 } }) |p| lv.set(p, .shrub);
    for (0..grid.CELLS) |i| {
        lv.seen[i] = true;
        lv.lit[i] = grid.Level.of(i).y <= 20;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const step = l.sightAt(30.6, 20.5 + EDGE_EPS) - l.sightAt(30.6, 20.5 - EDGE_EPS);
    var hedge = grid.openFloor();
    var y: i32 = 1;
    while (y < grid.H - 1) : (y += 1) hedge.set(.{ .x = 30, .y = y }, .shrub);
    for (0..grid.CELLS) |i| {
        hedge.seen[i] = grid.Level.of(i).x <= 30;
        hedge.lit[i] = hedge.seen[i];
    }
    const h = try testLight(&hedge);
    defer std.testing.allocator.destroy(h);
    const unseen = h.sightAt(30.6, 20.5);
    const behind = grid.Level.idx(.{ .x = 31, .y = 20 });
    h.sight[behind] = 2 * mathx.SETTLE;
    h.memory[behind] = 2 * mathx.SETTLE;
    h.soften();
    const glimpsed = h.sightAt(30.6, 20.5);
    std.debug.print("sight through a shrub clump's middle: {d:.4}; behind a hedge, unseen {d:.4}, first glimpsed {d:.4}\n", .{ step, unseen, glimpsed });
    try std.testing.expectApproxEqAbs(@as(f32, 0), step, 1e-2);
    try std.testing.expectApproxEqAbs(unseen, glimpsed, 1e-2);
}

test "a shrub in sight at the edge of what was ever seen is not dimmed toward the cells never seen" {
    var lv = grid.openFloor();
    const shrub = P{ .x = 30, .y = 20 };
    lv.set(shrub, .shrub);
    for (0..grid.CELLS) |i| {
        lv.seen[i] = grid.Level.of(i).x >= shrub.x;
        lv.lit[i] = lv.seen[i];
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const v = l.sightAt(@as(f32, @floatFromInt(shrub.x)) + EDGE_EPS, @as(f32, @floatFromInt(shrub.y)) + 0.5);
    std.debug.print("sight at a shrub's unexplored edge: {d:.4}\n", .{v});
    try std.testing.expectApproxEqAbs(@as(f32, 1), v, 1e-3);
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
    l.step(&lv, mathx.FRAME_DT);
    const first = l.flames(&lv, &buf)[0].memory;
    for (0..120) |_| l.step(&lv, mathx.FRAME_DT);
    const settled = l.flames(&lv, &buf)[0].memory;
    std.debug.print("a torch coming into sight: its remembered flame at {d:.3} the first frame, {d:.3} two seconds on\n", .{ first, settled });
    try std.testing.expect(first < 0.3);
    try std.testing.expectEqual(@as(f32, 1), settled);
}

fn castAlpha(l: *const Light, at: [2]f32, carrier: bool) [2]f32 {
    var buf: [BODY_LIGHTS]Cast = undefined;
    const cs = casts(&l.onBody(at, carrier), at, ART_H, &buf);
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
        l.step(&lv, mathx.FRAME_DT);
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
    try std.testing.expect(lum(carrying.ambient) > lum(MEMORY + CARRY) * 0.95);
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
        const cs = casts(&s, mathx.centre(c), ART_H, &out[i]);
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
        const cs = casts(&l.onBody(at, false), at, ART_H, &buf);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        const u = l.sky.?.across();
        const want = ART_H * l.sky.?.reach();
        std.debug.print("at {d:.1}h a body's shadow leans {d:.1},{d:.1} px, the ground's {d:.1},{d:.1}\n", .{ hour, cs[0].lean[0], cs[0].lean[1], -u[0] * want, -u[1] * want });
        for (0..2) |k| try std.testing.expectApproxEqAbs(-u[k] * want, cs[0].lean[k], 1e-2);
    }
}

test "skipping the sun's march where nothing that casts is near changes nothing it would have found" {
    const procgen = @import("../map/procgen.zig");
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
                try std.testing.expectEqual(sunlit(&lv, SunRay.of(k), q[0], q[1], z), l.sunAt(&lv, &SunRay.of(k), q[0], q[1], z));
                const b = Light.sunBox(SunRay.of(k), q[0], q[1], z);
                if (l.castersIn(b) == 0) skipped += 1;
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
            const cs = casts(&l.onBody(at, false), at, ART_H, &buf);
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
    for ([_]f32{ day.NOON, day.DEAD_OF_NIGHT }, 0..) |h, i| {
        l.sky = sky.at(h);
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(&l.onBody(foe, false), foe, ART_H, &buf);
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
    try std.testing.expect(lum(behind) < lum(toward) * 0.9 and behind[2] / behind[0] > toward[2] / toward[0]);
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
    for ([_]f32{ day.SUNRISE, 8, day.NOON }, &silhouette_at) |h, *k| {
        l.sky = sky.at(h);
        var buf: [BODY_LIGHTS]Cast = undefined;
        const cs = casts(&l.onBody(at, false), at, ART_H, &buf);
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
        for (casts(&l.onBody(at, false), at, ART_H, &buf)) |c| longest = @max(longest, c.len / ART_H);
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
