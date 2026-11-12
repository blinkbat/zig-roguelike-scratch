const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const sky = @import("sky.zig");
const shaders = @import("shaders.zig");
const lume = @import("../map/lume.zig");
const actor = @import("../play/actor.zig");
const visibility = @import("light_visibility.zig");
const ground = @import("ground.zig");

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
pub const FACE_H: f32 = 1 - FACE_FROM;
const FLAME_Z: f32 = 0.6;
/// Above the plant's own caster height, so no lit point sits on the light.
const PLANT_Z: f32 = 0.6;
/// Flame offset from its wall, preventing edge-on lighting of neighbouring bricks.
const STANDOFF: f32 = 0.3;
const FLOOR_WRAP: f32 = 1.0;
const FACE_WRAP: f32 = 0.35;
const FACE_GAIN: f32 = 1.25;
const CEILING_CATCH: f32 = 0.2;
pub const BODY_Z: f32 = 0.4;

pub const CARRY: Rgb = .{ 0.92, 0.88, 0.80 };
pub const MOON_CARRY: Rgb = .{ 0.52, 0.68, 1.0 };
/// At night the carried light warms toward this at its carrier's feet, by up to `NIGHT_GLOW_SHARE`, and is moonlit again this many cells out.
pub const NIGHT_GLOW: Rgb = .{ 0.85, 0.66, 0.45 };
pub const NIGHT_GLOW_SHARE: f32 = 0.35;
pub const NIGHT_GLOW_R: f32 = 3;
/// A cell past what the hero's light lets it see, so its glow fades out on the edge of sight.
pub const CARRY_R: f32 = carryR(actor.row(actor.HERO).light);

pub fn carryR(light: i32) f32 {
    return @floatFromInt(light + 1);
}
const CARRY_FADE: f32 = 0.3;
pub const CARRY_CEILING: f32 = 0.7;
pub const CARRY_FACE_WRAP: f32 = 0.6;

/// The light remembered terrain is drawn under, after Brogue's memory colour.
pub const MEMORY = rgbOf(look.rgb(0x2b2f4e));
const FLAME: Rgb = .{ 1.30, 0.80, 0.40 };
/// Per channel, the power the flicker is raised to, so a flame whitens as it flares.
const FLAME_SHIFT: Rgb = .{ 1.0, 1.6, 2.4 };
const PLANT_LIGHT: Rgb = .{ 0.52, 0.68, 0.92 };
/// Of its light, what a plant still casts in full day; all of it at night.
const PLANT_DAY: f32 = 0.2;

pub fn plantShare(daylight: f32) f32 {
    return mathx.lerpF(1, PLANT_DAY, daylight);
}
/// A glowing plant breathes rather than flickers: its share either way, and breaths a second.
const PULSE: f32 = 0.08;
const PULSE_HZ: f32 = 0.3;
pub const FAINT: f32 = 0.002;
const TINT_DIRECT: f32 = 0.6;
pub const FLICKER: f32 = 0.14;
const FLICKER_BANDS = [_]struct { hz: f32, weight: f32 }{
    .{ .hz = 1.5, .weight = 0.6 },
    .{ .hz = 5.0, .weight = 0.3 },
    .{ .hz = 11.0, .weight = 0.1 },
};
/// Channels above the knee roll off toward the ceiling, the brightest any light makes the art, however many sources stack.
const KNEE: f32 = 1.1;
const CEILING: f32 = 1.4;
const ROLL: f32 = CEILING - KNEE;

comptime {
    std.debug.assert(KNEE < CEILING and CEILING <= OVERBRIGHT);
}

pub const BODY_LIGHTS: usize = 4;
/// A pale flash remains visible over red bodies.
const FLASH_RGB = Rgb{ 0.88, 0.38, 0.30 };
/// Texels toward the viewer, for the side-lighting of a body.
pub const BODY_LIGHT_Z: f32 = 40.0;
/// The rise is per texel out; the rim reach is in texels.
pub const BODY_WRAP: f32 = 0.4;
pub const BODY_RISE: f32 = 0.7;
pub const BODY_RIM: f32 = 0.8;
pub const BODY_RIM_REACH: f32 = 2.0;
pub const BODY_SHEEN: f32 = 0.12;
/// Overlapping shadows take the channelwise minimum.
pub const SHADE_RGB = Rgb{ 0.42, 0.45, 0.54 };
const MOON_SHADE_RGB = Rgb{ 0.34, 0.40, 0.62 };
pub const SHADOW_MAX: f32 = 0.85;
const SHADOW_FULL: f32 = 0.5;
pub const SHADOW_TAPS: i32 = 3;
pub const GLOW_CORE: f32 = 0.45;
pub const GLOW_HALO: f32 = 2.6;
pub const GLOW_CORE_A: f32 = 0.85;
pub const GLOW_HALO_A: f32 = 0.2;
const GLOW_TINT: Rgb = .{ 1.0, 0.52, 0.22 };
const PLANT_TINT: Rgb = rgbOf(look.tile(.glow_plant).fg);
/// Cells between ray samples.
const SUN_STEP: f32 = 0.1;
pub const SUN_SOFT: f32 = 0.7;
pub const SUN_EDGE: f32 = 0.2;
const SUN_SHADE: f32 = 0.45;
const SUN_SHADOW_A: f32 = 0.4;
const SKY_SHADOW = SHADOW_MAX * SUN_SHADOW_A;
pub const SUN_LAMP_D: f32 = 3;

/// Height and optional circular radius in cells; null radius fills a square cell.
const Caster = struct { h: f32, r: ?f32 = null };

pub const CASTERS = std.EnumArray(grid.Tile, ?Caster).initDefault(@as(?Caster, null), .{
    .wall = .{ .h = WALL_H },
    .rock = .{ .h = WALL_H },
    .grave = .{ .h = 0.5, .r = 0.28 },
    .fence = .{ .h = 0.5 },
    .gate = .{ .h = WALL_H },
    .locked_gate = .{ .h = WALL_H },
    .crop = .{ .h = 0.4 },
    .glow_plant = .{ .h = 0.5, .r = 0.28 },
});

comptime {
    for (std.enums.values(grid.Tile)) |t| {
        if (t.uprightWhole()) std.debug.assert((CASTERS.get(t) != null) != look.castsPicture(t));
        if (t.glows()) std.debug.assert(PLANT_Z > (CASTERS.get(t) orelse continue).h);
    }
}

const CAST_TALLEST: f32 = blk: {
    var most: f32 = 0;
    for (CASTERS.values) |c| most = @max(most, if (c) |k| k.h else 0);
    break :blk most;
};

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

const BANK_FOOT_SHADE: f32 = 0.35;
const BANK_FOOT_PX: f32 = 3;

/// `banks` reads `lv`'s terrain: a `ground.LiveBanks` or a `*const ground.Banks` synced to it. No rim shades ground north of it.
pub fn bankSunlit(lv: *const grid.Level, banks: anytype, ray: SunRay, x: f32, y: f32, z: f32) f32 {
    if (z != 0 or sky.upright(ray.flat)) return 1;
    const cell = mathx.cellOf(.{ x, y });
    const here = lv.at(cell);
    const height = ground.bankHeight(here);
    if (height == 0) return 1;
    if (banks.lip(.{ x, y })) |lip| {
        if (y < lip) return 1;
    }
    var lit: f32 = 1;
    if (banks.foot(.{ x, y })) |foot| {
        if (y >= foot) lit = 1 - BANK_FOOT_SHADE * (1 - mathx.smoothstep(0, BANK_FOOT_PX / look.SPRITE_PX, y - foot));
    }
    const far = height / ray.rise;
    var distance: f32 = SUN_STEP * 0.25;
    while (distance < far) : (distance += SUN_STEP * 0.5) {
        const q = [2]f32{ x + ray.u[0] * distance, y + ray.u[1] * distance };
        const p = mathx.cellOf(q);
        if (!grid.Level.inside(p)) break;
        if (p.y > cell.y) continue;
        var bed = banks.bed(p) orelse continue;
        if (banks.lip(q)) |lip| {
            if (q[1] < lip) {
                if (lip > y) continue;
                bed = banks.bed(p.add(.{ .x = 0, .y = -1 })) orelse continue;
            }
        }
        if (!ground.bankAbove(bed.tile(), here)) continue;
        const drop = height - ground.bankHeight(bed.tile());
        lit = @min(lit, 1 - smooth(std.math.clamp((drop - distance * ray.rise) / (SUN_SOFT * drop), 0, 1)));
        if (lit == 0) return 0;
    }
    return lit;
}

const GROUND_WRAP: f32 = 0.5;
const CLOUD_SCALE: f32 = 14;
const CLOUD_DRIFT = [2]f32{ 0.35, 0.12 };
const CLOUD_COVER: f32 = 0.52;
const CLOUD_SOFT: f32 = 0.3;
const CLOUD_DEPTH: f32 = 0.18;
const CLOUD_OCTAVES = [2]f32{ 0.65, 0.35 };
const CLOUD_LACUNARITY: f32 = 2.3;

pub fn clouded(x: f32, y: f32, t: f32) f32 {
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

pub fn reaching(sun: f32, cloud: f32) f32 {
    return shaded(sun) * cloud;
}

fn faceCatch(cos: f32) f32 {
    return wrapped(cos, FACE_WRAP) * FACE_GAIN;
}

pub const SunRay = struct {
    k: sky.Sky,
    flat: f32,
    u: [2]f32,
    rise: f32,
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

const PLANT_LIGHTS: usize = grid.MAX_GLOWS;
pub const LIGHTS: usize = grid.MAX_TORCHES + PLANT_LIGHTS;
pub const TorchIx = std.math.IntFittingRange(0, LIGHTS - 1);

const Kind = enum { wall, plant };

pub const Mount = union(Kind) {
    wall: P,
    plant: P,
};

pub const Torch = struct {
    mount: Mount,
    /// Centred on the floor below the flame.
    reach: [grid.Cells.square(REACH)]f32,
    open: [grid.Cells.square(REACH)]f32,
    seed: u32,
    colour: Rgb = FLAME,
    glow: f32 = 1,

    pub fn floor(t: *const Torch) P {
        return switch (t.mount) {
            .wall => |w| lume.torchFloor(w),
            .plant => |p| p,
        };
    }

    /// On the ground plane.
    pub fn flame(t: *const Torch) [3]f32 {
        return switch (t.mount) {
            .wall => |w| .{ mathx.centre(w)[0], @as(f32, @floatFromInt(t.floor().y)) + STANDOFF, FLAME_Z },
            .plant => |p| .{ mathx.centre(p)[0], mathx.centre(p)[1], PLANT_Z },
        };
    }

    pub fn drawn(t: *const Torch) [2]f32 {
        return switch (t.mount) {
            .wall => |w| .{ mathx.centre(w)[0], faceY(@floatFromInt(w.y), FLAME_Z) },
            .plant => |p| mathx.centre(p),
        };
    }

    pub fn fan(t: *Torch, s: f32, plant: f32) void {
        switch (t.mount) {
            .wall => {
                t.glow = flicker(s, t.seed);
                var shift: Rgb = undefined;
                for (0..3) |k| shift[k] = std.math.pow(f32, t.glow, FLAME_SHIFT[k]);
                t.colour = FLAME * shift;
            },
            .plant => {
                t.glow = pulse(s, t.seed) * plant;
                t.colour = PLANT_LIGHT * splat(t.glow);
            },
        }
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
const VIEWER: Rgb = .{ 0, std.math.sqrt1_2, std.math.sqrt1_2 };
const SUN_GLINT_POWER: u32 = 24;
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

pub fn remembered(floor: Rgb, view: Rgb, sight: f32, memory: f32) Rgb {
    return mix(floor, view, sight) * splat(memory);
}

const NIGHT_MEMORY: f32 = 0.65;

pub fn memoryUnder(moon: f32) Rgb {
    return MEMORY * splat(mathx.lerpF(1, NIGHT_MEMORY, moon));
}

/// Windowed inverse square: exactly nothing at `REACH`.
fn falloff(d2: f32) f32 {
    const r = d2 / REACH2;
    const w = std.math.clamp(1 - r * r, 0, 1);
    return w * w / (1 + d2 / (FALLOFF_D0 * FALLOFF_D0));
}

pub fn carryFade(d: f32, r: f32) f32 {
    return @max(0, @min(carryAlong(d, r), carryAlong(r - 1, r) * (r - d)));
}

fn carryAlong(d: f32, r: f32) f32 {
    return 1 - (1 - CARRY_FADE) * d / r;
}

pub fn wrapped(cos: f32, wrap: f32) f32 {
    return @max(0, (cos + wrap) / (1 + wrap));
}

pub const texel = visibility.texel;
pub const mask = visibility.mask;

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

fn pulse(t: f32, seed: u32) f32 {
    return 1 + PULSE * @sin((t * PULSE_HZ + hash(0, seed)) * mathx.TAU);
}

fn knee(c: Rgb) Rgb {
    var out = c;
    for (0..3) |i| {
        if (c[i] > KNEE) out[i] = KNEE + ROLL * (1 - @exp(-(c[i] - KNEE) / ROLL));
    }
    return out;
}

test "light rolls off past the knee and never reaches the ceiling, however much stacks" {
    try std.testing.expectEqual(@as(f32, 0.8), knee(splat(0.8))[0]);
    var was: f32 = KNEE;
    for ([_]f32{ 1.2, 1.5, 2, 4, 16 }) |c| {
        const k = knee(splat(c))[0];
        try std.testing.expect(k > was and k <= CEILING);
        was = k;
    }
}

pub const TONE_FS = shaders.glslConsts(.{ .KNEE = KNEE, .ROLL = ROLL, .FLASH = FLASH_RGB }) ++
    \\vec3 knee(vec3 c) {
    \\    return mix(c, KNEE + ROLL * (1.0 - exp(-(c - KNEE) / ROLL)), step(KNEE, c));
    \\}
    \\vec3 flashed(vec3 c, float k) {
    \\    return mix(c, FLASH, k);
    \\}
    \\
;

const smooth = mathx.smooth;

pub fn faceCos(dy: f32, flat: f32) f32 {
    return dy / @max(flat, FACE_EPS);
}

const FACE_EPS: f32 = 1e-2;

pub const splat = sky.splat;

pub const rgbOf = look.rgbOf;
const colourOf = look.colourOf;

pub fn texelOf(c: Rgb, sight: f32) rl.Color {
    return colourOf(knee(c) / splat(OVERBRIGHT), sight);
}

const lum = sky.luma;

/// Cells: `drawn` as on screen, `ground` where it stands.
const Lamp = struct {
    drawn: [2]f32,
    ground: [2]f32,
    colour: Rgb,
    casts: bool,
    sky: ?SkyCast = null,
};

const SkyCast = struct { reach: f32, depth: f32, shade: Rgb };

pub fn skyDepth(k: sky.Sky, lit: f32) f32 {
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
    floor: Rgb = @splat(0),
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

    pub fn drawn(self: *const Shine, c: rl.Color, flash: f32) rl.Color {
        return flashed(recolour(c, rgbOf(self.tint(c)) + self.emission * splat(self.sight)), flash);
    }
};

fn recolour(c: rl.Color, rgb: Rgb) rl.Color {
    return colourOf(rgb, look.alphaOf(c));
}

pub const Flame = struct {
    kind: Kind,
    at: [2]f32,
    foot: f32,
    glow: f32,
    lit: f32,
    memory: f32,

    pub fn live(f: Flame) bool {
        return f.lit > FAINT;
    }

    pub fn tint(f: Flame) Rgb {
        return switch (f.kind) {
            .wall => GLOW_TINT,
            .plant => PLANT_TINT,
        };
    }
};

pub const COMPOSED_KEY: Rgb = .{ 1.035, 1.005, 0.96 };
pub const COMPOSED_AMBIENT: Rgb = .{ 0.94, 0.98, 1.04 };
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

    pub fn onBody(at: [2]f32, col: rl.Color, radius: f32, gain: f32) Emission {
        return .{ .at = .{ at[0], at[1], BODY_Z }, .col = col, .radius = radius, .gain = gain };
    }

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

fn flashed(c: rl.Color, k: f32) rl.Color {
    const from = rgbOf(c);
    return recolour(c, mix(from, FLASH_RGB, k));
}
