const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const fov = @import("../world/fov.zig");
const look = @import("look.zig");

// EVERY LIGHT IN THE GAME. Terrain draws at full brightness and one pass of the light map lights it; a body is lit per
// pixel from the sides that face its lights, and lays a shadow away from each. Nothing in the simulation reads any of it.

const P = mathx.P;
pub const Rgb = @Vector(3, f32);

/// Light-map texels per cell side.
pub const SUB: i32 = 4;
const MAP_W: i32 = grid.W * SUB;
const MAP_H: i32 = grid.H * SUB;
const TEXELS: usize = @intCast(MAP_W * MAP_H);
/// The map is drawn with (DST_COLOR, SRC_COLOR) blending, so a texel stores half the light and reaches twice the art.
const OVERBRIGHT: f32 = 2.0;

/// Cells: a torch lights nothing past this.
pub const REACH: i32 = 7;
const SPAN: i32 = REACH * 2 + 1;
/// Cells: the inverse square's reference distance.
const FALLOFF_D0: f32 = 2.5;
/// A wall is this tall; its brick face fills the cell below `FACE_FROM`, so the face is drawn foreshortened.
const WALL_H: f32 = 1.0;
const FACE_FROM: f32 = 0.6;
const FLAME_Z: f32 = 0.6;
/// How far the flame stands out from its wall, so the bricks beside it are not lit edge-on.
const STANDOFF: f32 = 0.3;
const FLOOR_WRAP: f32 = 1.0;
const FACE_WRAP: f32 = 0.35;
const FACE_GAIN: f32 = 1.25;
const CEILING_CATCH: f32 = 0.2;
const BODY_Z: f32 = 0.4;

/// The archer's own light, carried at the body's centre: it fades linearly to `CARRY_FADE` at `CARRY_R` cells.
const CARRY: Rgb = .{ 0.92, 0.88, 0.80 };
const CARRY_R: f32 = 9.0;
const CARRY_FADE: f32 = 0.3;
const CARRY_Z: f32 = 0.8;
const CARRY_CEILING: f32 = 0.7;
const CARRY_FACE_WRAP: f32 = 0.6;

/// Light in view that no source gives.
const AMBIENT: Rgb = .{ 0.10, 0.11, 0.17 };
const FLAME: Rgb = .{ 1.30, 0.80, 0.40 };
/// Per second, toward more light and toward less.
const REVEAL: f32 = 14.0;
const FORGET: f32 = 5.0;
/// The blurred memory is exactly half on the line between a seen cell and an unseen one.
const VOID_LO: f32 = 0.5;
const VOID_HI: f32 = 0.95;
/// Smooth noise at each rate, weighted, swinging the flame this far either way: a slow breath and a quick lick on top.
const FLICKER: f32 = 0.14;
const FLICKER_HZ = [3]f32{ 1.5, 5.0, 11.0 };
const FLICKER_WEIGHT = [3]f32{ 0.6, 0.3, 0.1 };
/// Per channel, light past this bends toward a square root instead of clipping (Brogue's `adjustedLightValue`).
const KNEE: f32 = 1.5;

pub const BODY_LIGHTS: usize = 4;
/// Texels toward the viewer, for the side-lighting of a body.
const BODY_LIGHT_Z: f32 = 40.0;
const SHADOWS: usize = 2;
const SHADOW_MAX: f32 = 0.7;
/// A light giving less of a body's light than this casts no shadow of it.
const SHADOW_SHARE: f32 = 0.2;
/// Of the body's drawn height.
const SHADOW_LEN_LO: f32 = 0.3;
const SHADOW_LEN_HI: f32 = 0.8;
const SHADOW_LEN_PER_CELL: f32 = 0.12;
/// Up or down the screen a shadow is flattened by this, and never leans flatter than `SHADOW_RISE_MIN` of its length.
const SHADOW_SQUASH: f32 = 0.55;
const SHADOW_RISE_MIN: f32 = 0.3;
/// Texels of blur room round a shadow's silhouette.
const SHADOW_PAD: f32 = 4;
const CONTACT_W: f32 = 0.62;
const CONTACT_H: f32 = 0.2;
const CONTACT_A: f32 = 0.45;
const GLOW_PX: i32 = 64;
const GLOW_CORE: f32 = 0.45;
const GLOW_HALO: f32 = 2.6;
const GLOW_CORE_A: f32 = 0.85;
const GLOW_HALO_A: f32 = 0.2;
const GLOW_TINT: Rgb = .{ 1.0, 0.52, 0.22 };

const MEMORY = rgbOf(look.REMEMBERED);

const Surface = enum { floor, face, ceiling };

/// Where a light-map texel sits in the world: the screen shows a wall's face and ceiling lifted off the ground.
const Spot = struct {
    x: f32,
    y: f32,
    z: f32,
    surface: Surface,

    fn of(lv: *const grid.Level, q: [2]f32) Spot {
        const cell = P{ .x = @intFromFloat(@floor(q[0])), .y = @intFromFloat(@floor(q[1])) };
        if (lv.at(cell) == .floor) return .{ .x = q[0], .y = q[1], .z = 0, .surface = .floor };
        const fy = q[1] - @floor(q[1]);
        const top: f32 = @floatFromInt(cell.y);
        if (faced(lv.wallShape(cell)) and fy >= FACE_FROM) {
            return .{ .x = q[0], .y = top + 1, .z = (1 - fy) / (1 - FACE_FROM) * WALL_H, .surface = .face };
        }
        return .{ .x = q[0], .y = q[1] + (1 - FACE_FROM), .z = WALL_H, .surface = .ceiling };
    }
};

fn faced(s: ?grid.WallShape) bool {
    return switch (s orelse return false) {
        .top, .block_bl, .block_br, .post => true,
        else => false,
    };
}

const Torch = struct {
    wall: P,
    /// 1 where the flame's light gets to, over the box of cells centred on the floor below the flame.
    reach: [SPAN * SPAN]f32,
    seed: u32,
    colour: Rgb = FLAME,
    glow: f32 = 1,

    /// On the ground plane, standing off the face of its wall.
    fn flame(t: Torch) [3]f32 {
        return .{ @as(f32, @floatFromInt(t.wall.x)) + 0.5, @as(f32, @floatFromInt(t.wall.y)) + 1 + STANDOFF, FLAME_Z };
    }

    /// Where the flame is drawn: up its wall's foreshortened face.
    fn drawn(t: Torch) [2]f32 {
        const face_h = 1 - FACE_FROM;
        return .{ @as(f32, @floatFromInt(t.wall.x)) + 0.5, @as(f32, @floatFromInt(t.wall.y)) + 1 - FLAME_Z / WALL_H * face_h };
    }

    fn reached(t: *const Torch, x: f32, y: f32) f32 {
        const u = x - @as(f32, @floatFromInt(t.wall.x - REACH)) - 0.5;
        const v = y - @as(f32, @floatFromInt(t.wall.y + 1 - REACH)) - 0.5;
        return bilinear(&t.reach, SPAN, SPAN, u, v, 0);
    }

    fn shine(t: *const Torch, s: Spot) f32 {
        const f = t.flame();
        const dx = f[0] - s.x;
        const dy = f[1] - s.y;
        const dz = f[2] - s.z;
        const flat2 = dx * dx + dy * dy;
        const d2 = flat2 + dz * dz;
        if (d2 >= @as(f32, @floatFromInt(REACH * REACH))) return 0;
        const o = t.reached(s.x, s.y);
        if (o <= 0) return 0;
        const facing = switch (s.surface) {
            .floor => wrapped(dz / @sqrt(d2), FLOOR_WRAP),
            .face => wrapped(dy / @sqrt(@max(flat2, 1e-4)), FACE_WRAP) * FACE_GAIN,
            .ceiling => CEILING_CATCH,
        };
        return falloff(d2) * facing * o;
    }
};

/// Windowed inverse square: full near the flame, a long tail, and exactly nothing at `REACH`.
fn falloff(d2: f32) f32 {
    const r = d2 / @as(f32, @floatFromInt(REACH * REACH));
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

fn hash(n: i32, seed: u32) f32 {
    var x: u32 = @bitCast(n);
    x = (x ^ seed) *% 0x9E3779B1;
    x ^= x >> 15;
    x *%= 0x85EBCA77;
    x ^= x >> 13;
    return @as(f32, @floatFromInt(x >> 8)) / @as(f32, 1 << 24);
}

/// Smooth value noise in 0..1.
fn noise(t: f32, seed: u32) f32 {
    const i = @floor(t);
    const f = t - i;
    const n: i32 = @intFromFloat(i);
    return mathx.lerpF(hash(n, seed), hash(n +% 1, seed), f * f * (3 - 2 * f));
}

pub fn flicker(t: f32, seed: u32) f32 {
    var n: f32 = 0;
    for (FLICKER_HZ, FLICKER_WEIGHT, 0..) |hz, w, i| n += w * (noise(t * hz, seed ^ (@as(u32, @intCast(i)) *% 0x5BD1E995)) * 2 - 1);
    return 1 + FLICKER * n;
}

fn knee(c: Rgb) Rgb {
    var out = c;
    for (0..3) |i| {
        if (c[i] > KNEE) out[i] = KNEE * @sqrt(c[i] / KNEE);
    }
    return out;
}

/// Memory as it meets what was never seen: black exactly at that edge and full a cell in, so no cell stops hard.
fn edge(m: f32) f32 {
    const t = std.math.clamp((m - VOID_LO) / (VOID_HI - VOID_LO), 0, 1);
    return t * t * (3 - 2 * t);
}

fn ease(v: f32, want: f32, up: f32, down: f32) f32 {
    return v + (want - v) * (if (want > v) up else down);
}

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

fn lum(c: Rgb) f32 {
    return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722;
}

/// What lights one body: the light where it stands that comes from nowhere in particular, and the lights round it.
pub const Shine = struct {
    ambient: Rgb = @splat(0),
    n: usize = 0,
    /// Each light as drawn on screen, where it stands on the ground, and what reaches the body, cells.
    drawn: [BODY_LIGHTS][2]f32 = undefined,
    ground: [BODY_LIGHTS][2]f32 = undefined,
    colour: [BODY_LIGHTS]Rgb = undefined,

    fn add(self: *Shine, drawn: [2]f32, ground: [2]f32, c: Rgb) void {
        var i = self.n;
        if (self.n == BODY_LIGHTS) {
            i = 0;
            for (1..BODY_LIGHTS) |k| {
                if (lum(self.colour[k]) < lum(self.colour[i])) i = k;
            }
            if (lum(c) <= lum(self.colour[i])) return;
        } else self.n += 1;
        self.drawn[i] = drawn;
        self.ground[i] = ground;
        self.colour[i] = c;
    }

    fn total(self: Shine) Rgb {
        var c: Rgb = @splat(0);
        for (self.colour[0..self.n]) |l| c += l;
        return c;
    }

    /// `c` under one light for the whole body, for a body with nothing to light per pixel.
    pub fn tint(self: Shine, c: rl.Color) rl.Color {
        return colourOf(rgbOf(c) * (self.ambient + self.total() * splat(0.6)), @as(f32, @floatFromInt(c.a)) / 255);
    }
};

pub const Flame = struct { at: [2]f32, glow: f32, sight: f32 };

pub const Light = struct {
    sight: [grid.CELLS]f32,
    memory: [grid.CELLS]f32,
    soft_sight: [grid.CELLS]f32,
    soft_memory: [grid.CELLS]f32,
    blur: [grid.CELLS]f32,
    torch: [grid.MAX_TORCHES]Torch,
    torch_n: usize,
    /// The archer's centre as drawn, cells.
    carrier: ?[2]f32,
    t: f32,
    map: [TEXELS]rl.Color,
    scratch: grid.Level,
    gpu: Gpu,

    /// Set field by field: built as one value, it is a temporary bigger than a thread's stack.
    pub fn create(alloc: std.mem.Allocator) !*Light {
        const l = try alloc.create(Light);
        l.torch_n = 0;
        l.carrier = null;
        l.t = 0;
        l.gpu = .{};
        @memset(&l.sight, 0);
        @memset(&l.memory, 0);
        @memset(&l.map, rl.Color.black);
        l.soften();
        return l;
    }

    /// A new floor: the torches' reach, and the fog as it stands with nothing to ease from.
    pub fn settle(self: *Light, lv: *const grid.Level) void {
        self.scratch = lv.*;
        self.torch_n = 0;
        for (lv.torches(), 0..) |w, i| {
            var t = Torch{ .wall = w, .reach = undefined, .seed = @as(u32, @intCast(i)) *% 0x27D4EB2F +% 0x165667B1 };
            fov.cast(&self.scratch, w.add(mathx.Dir.s.delta()), REACH);
            var j: usize = 0;
            var y: i32 = -REACH;
            while (y <= REACH) : (y += 1) {
                var x: i32 = -REACH;
                while (x <= REACH) : (x += 1) {
                    t.reach[j] = if (self.scratch.isLit(.{ .x = w.x + x, .y = w.y + 1 + y })) 1 else 0;
                    j += 1;
                }
            }
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
        const up = 1 - @exp(-dt * REVEAL);
        const down = 1 - @exp(-dt * FORGET);
        for (0..grid.CELLS) |i| {
            self.sight[i] = ease(self.sight[i], if (lv.lit[i]) 1 else 0, up, down);
            self.memory[i] = ease(self.memory[i], if (lv.seen[i]) 1 else 0, up, down);
        }
        self.soften();
        self.t += dt;
        self.fan();
    }

    fn fan(self: *Light) void {
        for (self.torch[0..self.torch_n]) |*t| {
            t.glow = flicker(self.t, t.seed);
            t.colour = FLAME * Rgb{ t.glow, std.math.pow(f32, t.glow, 1.6), std.math.pow(f32, t.glow, 2.4) };
        }
    }

    /// Memory twice, so its fade into the unseen runs further in from the only edge it may not cross.
    fn soften(self: *Light) void {
        blur121(&self.sight, &self.blur, &self.soft_sight);
        blur121(&self.memory, &self.blur, &self.soft_memory);
        blur121(&self.soft_memory, &self.blur, &self.soft_memory);
    }

    /// Sight and memory at a point on the screen, cells.
    fn fog(self: *const Light, x: f32, y: f32) [2]f32 {
        return .{
            bilinear(&self.soft_sight, grid.W, grid.H, x - 0.5, y - 0.5, 0),
            edge(bilinear(&self.soft_memory, grid.W, grid.H, x - 0.5, y - 0.5, 0)),
        };
    }

    fn near(self: *const Light, lo: P, hi: P, out: *[grid.MAX_TORCHES]u8) []const u8 {
        var n: usize = 0;
        for (self.torch[0..self.torch_n], 0..) |t, i| {
            if (t.wall.x + REACH < lo.x or t.wall.x - REACH > hi.x or t.wall.y + 1 + REACH < lo.y or t.wall.y + 1 - REACH > hi.y) continue;
            out[n] = @intCast(i);
            n += 1;
        }
        return out[0..n];
    }

    fn carried(self: *const Light, s: Spot) f32 {
        const c = self.carrier orelse return 0;
        const dx = c[0] - s.x;
        const dy = c[1] - s.y;
        const flat = @sqrt(dx * dx + dy * dy);
        const facing = switch (s.surface) {
            .floor => 1,
            .face => wrapped(dy / @max(flat, 1e-2), CARRY_FACE_WRAP),
            .ceiling => CARRY_CEILING,
        };
        return carryFade(flat) * facing;
    }

    /// The light at a point on the screen, cells, as it lands on whatever terrain is drawn there.
    pub fn at(self: *const Light, lv: *const grid.Level, torches: []const u8, q: [2]f32) Rgb {
        const f = self.fog(q[0], q[1]);
        if (f[1] <= 0.002) return @splat(0);
        var view = AMBIENT;
        if (f[0] > 0.002) {
            const s = Spot.of(lv, q);
            view += CARRY * splat(self.carried(s));
            for (torches) |i| {
                const t = &self.torch[i];
                view += t.colour * splat(t.shine(s));
            }
        }
        return (MEMORY + (view - MEMORY) * splat(f[0])) * splat(f[1]);
    }

    /// Fills the light map over the cells from `lo` up to `hi`, and a texel round them for the filter.
    pub fn bake(self: *Light, lv: *const grid.Level, lo: P, hi: P) void {
        var ids: [grid.MAX_TORCHES]u8 = undefined;
        const torches = self.near(lo.sub(.{ .x = 1, .y = 1 }), hi.add(.{ .x = 1, .y = 1 }), &ids);
        const tx0 = @max(0, lo.x * SUB - 1);
        const ty0 = @max(0, lo.y * SUB - 1);
        const tx1 = @min(MAP_W, hi.x * SUB + 1);
        const ty1 = @min(MAP_H, hi.y * SUB + 1);
        const sub: f32 = @floatFromInt(SUB);
        var ty = ty0;
        while (ty < ty1) : (ty += 1) {
            var tx = tx0;
            while (tx < tx1) : (tx += 1) {
                const q = [2]f32{ (@as(f32, @floatFromInt(tx)) + 0.5) / sub, (@as(f32, @floatFromInt(ty)) + 0.5) / sub };
                self.map[@intCast(ty * MAP_W + tx)] = colourOf(knee(self.at(lv, torches, q)) / splat(OVERBRIGHT), 1);
            }
        }
    }

    /// `centre` is the body's middle on the ground, cells. The carried light lights its own `carrier` flat, from nowhere.
    pub fn onBody(self: *const Light, centre: [2]f32, carrier: bool) Shine {
        const f = self.fog(centre[0], centre[1]);
        var s = Shine{ .ambient = MEMORY + (AMBIENT - MEMORY) * splat(f[0]) };
        if (self.carrier) |c| {
            const dx = c[0] - centre[0];
            const dy = c[1] - centre[1];
            const k = carryFade(@sqrt(dx * dx + dy * dy)) * f[0];
            if (carrier) s.ambient += CARRY * splat(k) else if (k > 0.002) s.add(c, c, CARRY * splat(k));
        }
        for (self.torch[0..self.torch_n]) |*t| {
            const fl = t.flame();
            const dx = fl[0] - centre[0];
            const dy = fl[1] - centre[1];
            const dz = fl[2] - BODY_Z;
            const d2 = dx * dx + dy * dy + dz * dz;
            if (d2 >= @as(f32, @floatFromInt(REACH * REACH))) continue;
            const k = falloff(d2) * t.reached(centre[0], centre[1]) * f[0];
            if (k <= 0.002) continue;
            s.add(t.drawn(), .{ fl[0], fl[1] }, t.colour * splat(k));
        }
        return s;
    }

    pub fn flames(self: *const Light, out: *[grid.MAX_TORCHES]Flame) []const Flame {
        for (self.torch[0..self.torch_n], 0..) |t, i| {
            const d = t.drawn();
            out[i] = .{ .at = d, .glow = t.glow, .sight = self.fog(d[0], d[1])[0] };
        }
        return out[0..self.torch_n];
    }

    // ---- gpu ------------------------------------------------------------------------------------------------

    /// Needs a live GL context, so it is loaded after the window opens and never in a test.
    pub fn load(self: *Light, bodies: []const ?rl.Texture2D) void {
        self.gpu = Gpu.load(bodies);
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
        rl.drawTexturePro(tex, .{ .x = 0, .y = 0, .width = @floatFromInt(MAP_W), .height = @floatFromInt(MAP_H) }, .{
            .x = @floatFromInt(ox),
            .y = @floatFromInt(oy),
            .width = @floatFromInt(grid.W * cell),
            .height = @floatFromInt(grid.H * cell),
        }, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
    }

    /// A body's sprite at `dest`, lit per pixel from the sides that face its lights. `centre` is its middle, cells.
    pub fn drawBody(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: Shine) void {
        const w: f32 = @floatFromInt(tex.width);
        const h: f32 = @floatFromInt(tex.height);
        const src = rl.Rectangle{ .x = 0, .y = 0, .width = if (left) -w else w, .height = h };
        const normals = self.gpu.art(tex).normals;
        const sh = self.gpu.body;
        if (sh == null or normals == null) {
            rl.drawTexturePro(tex, src, dest, .{ .x = 0, .y = 0 }, 0, s.tint(rl.Color.white));
            return;
        }
        var pos: [BODY_LIGHTS][3]f32 = undefined;
        var col: [BODY_LIGHTS][3]f32 = undefined;
        for (0..s.n) |i| {
            pos[i] = .{ (s.drawn[i][0] - centre[0]) * w, (s.drawn[i][1] - centre[1]) * h, BODY_LIGHT_Z };
            col[i] = s.colour[i];
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
        rl.setShaderValueTexture(b.shader, b.normals, normals.?);
        if (s.n > 0) {
            rl.setShaderValueV(b.shader, b.lpos, &pos, .vec3, n);
            rl.setShaderValueV(b.shader, b.lcol, &col, .vec3, n);
        }
        rl.drawTexturePro(tex, src, dest, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
        rl.gl.rlDrawRenderBatchActive();
    }

    /// Under a body at `dest`: a soft contact shadow, and its silhouette laid on the floor away from its strongest lights.
    /// Drawn before the walls, which cover whatever of it reaches them.
    pub fn drawShadows(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: Shine) void {
        const foot_row = self.gpu.art(tex).foot;
        const scale = dest.height / @as(f32, @floatFromInt(tex.height));
        const fx = dest.x + dest.width * 0.5;
        const fy = dest.y + foot_row * scale;
        const lit = lum(s.ambient + s.total());
        if (lit <= 0) return;
        if (self.gpu.glow) |g| {
            const w = dest.width * CONTACT_W;
            const h = dest.width * CONTACT_H;
            const a = CONTACT_A * @min(1, lit / lum(CARRY));
            rl.drawTexturePro(g, .{ .x = 0, .y = 0, .width = @floatFromInt(g.width), .height = @floatFromInt(g.height) }, .{
                .x = fx - w * 0.5,
                .y = fy - h * 0.5,
                .width = w,
                .height = h,
            }, .{ .x = 0, .y = 0 }, 0, colourOf(@splat(0), a));
        }
        const sh = self.gpu.shadow orelse return;
        const size = [2]f32{ @floatFromInt(tex.width), @floatFromInt(tex.height) };
        const foot = foot_row / size[1];
        rl.beginShaderMode(sh.shader);
        defer rl.endShaderMode();
        rl.setShaderValue(sh.shader, sh.size, &size, .vec2);
        rl.setShaderValue(sh.shader, sh.foot, &foot, .float);
        var order: [BODY_LIGHTS]usize = .{ 0, 1, 2, 3 };
        std.mem.sort(usize, order[0..s.n], s, struct {
            fn brighter(by: Shine, a: usize, b: usize) bool {
                return lum(by.colour[a]) > lum(by.colour[b]);
            }
        }.brighter);
        for (order[0..@min(s.n, SHADOWS)]) |i| {
            const share = lum(s.colour[i]) / lit;
            if (share < SHADOW_SHARE) continue;
            const dx = centre[0] - s.ground[i][0];
            const dy = centre[1] - s.ground[i][1];
            const d = @sqrt(dx * dx + dy * dy);
            if (d < 0.05) continue;
            const len = foot_row * scale * std.math.clamp(SHADOW_LEN_LO + SHADOW_LEN_PER_CELL * d, SHADOW_LEN_LO, SHADOW_LEN_HI);
            const down: f32 = if (dy >= 0) 1 else -1;
            const rise = down * @max(@abs(dy / d) * SHADOW_SQUASH, SHADOW_RISE_MIN);
            silhouette(tex, fx, fy, .{ dx / d * len, rise * len }, dest.width, foot, left, SHADOW_MAX * share);
        }
        rl.gl.rlDrawRenderBatchActive();
    }

    /// Additive: a hot core on each flame and a wide haze, pulsing with it and faded with the fog.
    pub fn drawGlows(self: *const Light, flames_: []const Flame, ox: f32, oy: f32, cell: f32) void {
        const g = self.gpu.glow orelse return;
        rl.beginBlendMode(.additive);
        defer rl.endBlendMode();
        for (flames_) |f| {
            if (f.sight <= 0.01) continue;
            const x = ox + f.at[0] * cell;
            const y = oy + f.at[1] * cell;
            glowAt(g, x, y, cell * GLOW_HALO, colourOf(GLOW_TINT, GLOW_HALO_A * f.glow * f.sight));
            glowAt(g, x, y, cell * GLOW_CORE, colourOf(GLOW_TINT, GLOW_CORE_A * f.glow * f.sight));
        }
    }
};

fn glowAt(g: rl.Texture2D, x: f32, y: f32, r: f32, c: rl.Color) void {
    rl.drawTexturePro(g, .{ .x = 0, .y = 0, .width = @floatFromInt(g.width), .height = @floatFromInt(g.height) }, .{
        .x = x - r,
        .y = y - r,
        .width = r * 2,
        .height = r * 2,
    }, .{ .x = 0, .y = 0 }, 0, c);
}

/// The sprite laid on the floor: its feet stay a level line as wide as it is, and its height leans along `lean`, pixels
/// from the feet to the top of its head. Leaning down the screen makes the quad a mirror image, so its corners go the
/// other way round to keep the winding the rasteriser does not cull.
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
    rl.gl.rlColor4ub(0, 0, 0, @intFromFloat(std.math.clamp(alpha, 0, 1) * 255));
    for (0..4) |k| {
        const v = corners[if (mirrored) 3 - k else k];
        rl.gl.rlTexCoord2f(v[0], v[1]);
        rl.gl.rlVertex2f(v[2], v[3]);
    }
    rl.gl.rlEnd();
    rl.gl.rlSetTexture(0);
}

fn blur121(src: *const [grid.CELLS]f32, tmp: *[grid.CELLS]f32, out: *[grid.CELLS]f32) void {
    const w: usize = @intCast(grid.W);
    const h: usize = @intCast(grid.H);
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

const BODY_FS =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\uniform sampler2D texture0;
    \\uniform sampler2D normals;
    \\uniform vec2 size;
    \\uniform float flip;
    \\uniform vec3 ambient;
    \\uniform int count;
    \\uniform vec3 lpos[4];
    \\uniform vec3 lcol[4];
    \\out vec4 finalColor;
    \\const float WRAP = 0.4;
    \\const float RISE = 0.7;
    \\const float RIM = 0.8;
    \\const float RIM_REACH = 2.0;
    \\const float SHEEN = 0.12;
    \\const float KNEE = 1.5;
    \\float alphaAt(vec2 px) {
    \\    if (px.x < 0.0 || px.y < 0.0 || px.x >= size.x || px.y >= size.y) return 0.0;
    \\    return texture(texture0, px / size).a;
    \\}
    \\void main() {
    \\    vec2 px = floor(fragTexCoord * size) + 0.5;
    \\    vec4 c = texture(texture0, px / size);
    \\    if (c.a < 0.004) discard;
    \\    vec3 n = texture(normals, px / size).xyz * 2.0 - 1.0;
    \\    n.x *= flip;
    \\    n = normalize(n);
    \\    vec2 p = vec2((px.x - size.x * 0.5) * flip, px.y - size.y * 0.5);
    \\    vec3 light = ambient;
    \\    vec3 sheen = vec3(0.0);
    \\    for (int i = 0; i < 4; i++) {
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
    \\    finalColor = vec4(c.rgb * light + sheen, c.a) * fragColor;
    \\}
;

const SHADOW_FS =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\uniform sampler2D texture0;
    \\uniform vec2 size;
    \\uniform float foot;
    \\out vec4 finalColor;
    \\const float SOFT_FOOT = 0.6;
    \\const float SOFT_TIP = 3.0;
    \\float alphaAt(vec2 uv) {
    \\    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > foot) return 0.0;
    \\    return texture(texture0, uv).a;
    \\}
    \\void main() {
    \\    float spread = mix(SOFT_TIP, SOFT_FOOT, clamp(fragTexCoord.y / foot, 0.0, 1.0));
    \\    float a = 0.0;
    \\    for (int i = -2; i <= 2; i++) {
    \\        for (int j = -2; j <= 2; j++) {
    \\            a += alphaAt(fragTexCoord + vec2(float(i), float(j)) * spread * 0.5 / size);
    \\        }
    \\    }
    \\    finalColor = vec4(0.0, 0.0, 0.0, a / 25.0 * fragColor.a);
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
};

const ShadowShader = struct {
    shader: rl.Shader,
    size: i32,
    foot: i32,
};

/// What the lighting reads off a body's sprite, once, when it loads.
const Art = struct {
    id: u32,
    /// Texel rows from the sprite's top to just under its lowest opaque row.
    foot: f32,
    normals: ?rl.Texture2D,
};

/// Texels in from the silhouette over which a body's edge rounds off, and how steeply.
const BEVEL_PX: i32 = 5;
const BEVEL_DEPTH: f32 = 2.0;
/// The largest sprite side a body's normals are built for.
const ART_MAX: i32 = 128;

const Gpu = struct {
    map: ?rl.Texture2D = null,
    glow: ?rl.Texture2D = null,
    body: ?BodyShader = null,
    shadow: ?ShadowShader = null,
    arts: [8]Art = undefined,
    art_n: usize = 0,

    fn load(bodies: []const ?rl.Texture2D) Gpu {
        var g = Gpu{};
        const blank = rl.genImageColor(MAP_W, MAP_H, rl.Color.black);
        defer rl.unloadImage(blank);
        if (rl.loadTextureFromImage(blank)) |t| {
            rl.setTextureFilter(t, .bilinear);
            rl.setTextureWrap(t, .clamp);
            g.map = t;
        } else |_| {}
        g.glow = glowTexture();
        if (rl.loadShaderFromMemory(null, BODY_FS)) |s| {
            g.body = .{
                .shader = s,
                .size = rl.getShaderLocation(s, "size"),
                .flip = rl.getShaderLocation(s, "flip"),
                .ambient = rl.getShaderLocation(s, "ambient"),
                .count = rl.getShaderLocation(s, "count"),
                .lpos = rl.getShaderLocation(s, "lpos"),
                .lcol = rl.getShaderLocation(s, "lcol"),
                .normals = rl.getShaderLocation(s, "normals"),
            };
        } else |_| {}
        if (rl.loadShaderFromMemory(null, SHADOW_FS)) |s| {
            g.shadow = .{ .shader = s, .size = rl.getShaderLocation(s, "size"), .foot = rl.getShaderLocation(s, "foot") };
        } else |_| {}
        for (bodies) |b| {
            const t = b orelse continue;
            if (g.art_n == g.arts.len) break;
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

    fn art(g: Gpu, t: rl.Texture2D) Art {
        for (g.arts[0..g.art_n]) |a| {
            if (a.id == t.id) return a;
        }
        return .{ .id = t.id, .foot = @floatFromInt(t.height), .normals = null };
    }
};

fn artOf(t: rl.Texture2D) Art {
    var a = Art{ .id = t.id, .foot = @floatFromInt(t.height), .normals = null };
    if (t.width > ART_MAX or t.height > ART_MAX) return a;
    const img = rl.loadImageFromTexture(t) catch return a;
    defer rl.unloadImage(img);
    var solid: [ART_MAX * ART_MAX]bool = undefined;
    for (0..@intCast(t.height)) |y| {
        for (0..@intCast(t.width)) |x| solid[y * ART_MAX + x] = rl.getImageColor(img, @intCast(x), @intCast(y)).a > 25;
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
        if (solid[@intCast(y * ART_MAX + x)]) return true;
    }
    return false;
}

/// Laigter's soft bevel: each opaque texel's distance to the nearest clear one (outside the sprite counts as clear),
/// raised on a quarter circle over `BEVEL_PX`, and the normal of that height by central differences.
fn bevelNormals(solid: *const [ART_MAX * ART_MAX]bool, w: i32, h: i32) ?rl.Texture2D {
    var height: [ART_MAX * ART_MAX]f32 = undefined;
    const reach = BEVEL_PX + 1;
    var y: i32 = 0;
    while (y < h) : (y += 1) {
        var x: i32 = 0;
        while (x < w) : (x += 1) {
            const i: usize = @intCast(y * ART_MAX + x);
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
                    const clear = sx < 0 or sy < 0 or sx >= w or sy >= h or !solid[@intCast(sy * ART_MAX + sx)];
                    if (clear) near2 = @min(near2, dx * dx + dy * dy);
                }
            }
            const t = std.math.clamp((@sqrt(@as(f32, @floatFromInt(near2))) - 0.5) / @as(f32, @floatFromInt(BEVEL_PX)), 0, 1);
            height[i] = @sqrt(1 - (t - 1) * (t - 1));
        }
    }
    var px: [ART_MAX * ART_MAX]rl.Color = undefined;
    const at = struct {
        fn f(hs: *const [ART_MAX * ART_MAX]f32, hw: i32, hh: i32, x: i32, yy: i32) f32 {
            if (x < 0 or yy < 0 or x >= hw or yy >= hh) return 0;
            return hs[@intCast(yy * ART_MAX + x)];
        }
    }.f;
    y = 0;
    while (y < h) : (y += 1) {
        var x: i32 = 0;
        while (x < w) : (x += 1) {
            const gx = at(&height, w, h, x + 1, y) - at(&height, w, h, x - 1, y);
            const gy = at(&height, w, h, x, y + 1) - at(&height, w, h, x, y - 1);
            const n = Rgb{ -gx * BEVEL_DEPTH, -gy * BEVEL_DEPTH, 1 };
            const unit = n / splat(@sqrt(@reduce(.Add, n * n)));
            px[@intCast(y * w + x)] = colourOf(unit * splat(0.5) + splat(0.5), 1);
        }
    }
    const img = rl.Image{ .data = &px, .width = w, .height = h, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    const t = rl.loadTextureFromImage(img) catch return null;
    rl.setTextureFilter(t, .point);
    rl.setTextureWrap(t, .clamp);
    return t;
}

/// White, its alpha a smooth bump from 1 at the centre to 0 at the rim.
fn glowTexture() ?rl.Texture2D {
    var px: [GLOW_PX * GLOW_PX]rl.Color = undefined;
    const half: f32 = @as(f32, @floatFromInt(GLOW_PX)) * 0.5;
    for (0..GLOW_PX) |y| {
        for (0..GLOW_PX) |x| {
            const dx = (@as(f32, @floatFromInt(x)) + 0.5 - half) / half;
            const dy = (@as(f32, @floatFromInt(y)) + 0.5 - half) / half;
            const r2 = @min(1, dx * dx + dy * dy);
            const a = (1 - r2) * (1 - r2) * @exp(-3 * r2);
            px[y * GLOW_PX + x] = .{ .r = 255, .g = 255, .b = 255, .a = @intFromFloat(a * 255) };
        }
    }
    const img = rl.Image{ .data = &px, .width = GLOW_PX, .height = GLOW_PX, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    const t = rl.loadTextureFromImage(img) catch return null;
    rl.setTextureFilter(t, .bilinear);
    rl.setTextureWrap(t, .clamp);
    return t;
}

// ---- tests ----------------------------------------------------------------------------------------------

const gen = @import("../world/gen.zig");

const TORCH_AT = P{ .x = 20, .y = 10 };

/// Open floor under a wall along row 10 with a torch on it, every cell in sight.
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

/// Luminance over what a lit cell with no source in it gets.
fn added(l: *const Light, lv: *const grid.Level, q: [2]f32) f32 {
    var ids: [grid.MAX_TORCHES]u8 = undefined;
    return lum(l.at(lv, l.near(.{ .x = 0, .y = 0 }, .{ .x = grid.W, .y = grid.H }, &ids), q)) - lum(AMBIENT);
}

fn flameY() f32 {
    return @as(f32, @floatFromInt(TORCH_AT.y)) + 1 + STANDOFF;
}

test "a torch pools light on the floor below it, fading to nothing at its reach" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const x = @as(f32, @floatFromInt(TORCH_AT.x)) + 0.5;
    std.debug.print("torchlight on the floor by cells from the flame:", .{});
    var last = std.math.floatMax(f32);
    for ([_]f32{ 0.25, 1, 2, 3, 4, 5, 6, 7 }) |r| {
        const v = added(l, &lv, .{ x, flameY() + r });
        std.debug.print(" {d}:{d:.3}", .{ r, v });
        try std.testing.expect(v <= last);
        last = v;
    }
    std.debug.print("\n", .{});
    try std.testing.expect(added(l, &lv, .{ x, flameY() + 0.25 }) > 0.6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), last, 1e-5);
}

test "a brick face by its torch catches far more than the ceiling above it, and one turned away catches none" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{.{ .x = 26, .y = 14 }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const own = added(l, &lv, .{ 20.5, 10.875 });
    const ceiling = added(l, &lv, .{ 20.5, 10.25 });
    const along = added(l, &lv, .{ 23.5, 10.875 });
    const along_ceiling = added(l, &lv, .{ 23.5, 10.25 });
    const away = added(l, &lv, .{ 26.5, 14.875 });
    std.debug.print("torchlight: its own face {d:.3} and the ceiling above {d:.3}, a face 3 along {d:.3} and its ceiling {d:.3}, a face turned away {d:.3}\n", .{ own, ceiling, along, along_ceiling, away });
    try std.testing.expect(own > ceiling * 3);
    try std.testing.expect(own > along);
    try std.testing.expect(along > along_ceiling * 1.5);
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
    var ids: [grid.MAX_TORCHES]u8 = undefined;
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

test "remembered ground fades to black exactly at the edge of what was ever seen" {
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| lv.seen[i] = grid.Level.of(i).x < 20;
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const full = lum(l.at(&lv, &.{}, .{ 15.5, 30.5 }));
    const at_edge = lum(l.at(&lv, &.{}, .{ 20.0, 30.5 }));
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

test "the carried light fades across the view and leaves its edge above memory" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.carrier = .{ 40.5, 30.5 };
    std.debug.print("carried light on the floor by cells out:", .{});
    var last = std.math.floatMax(f32);
    for ([_]f32{ 0, 2, 4, 6, 8 }) |d| {
        const v = lum(l.at(&lv, &.{}, .{ 40.5 + d, 30.5 }));
        std.debug.print(" {d}:{d:.3}", .{ d, v });
        try std.testing.expect(v < last);
        last = v;
    }
    std.debug.print(", memory {d:.3}\n", .{lum(MEMORY)});
    try std.testing.expect(last > lum(MEMORY));
}

test "a body takes its torch's light from where the flame is drawn, and none from behind a pillar" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{.{ .x = 20, .y = 13 }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const open = l.onBody(.{ 23.5, 13.5 }, false);
    try std.testing.expectEqual(@as(usize, 1), open.n);
    try std.testing.expect(open.drawn[0][0] < 23.5 and open.drawn[0][1] < 13.5);
    try std.testing.expectEqual(@as(usize, 0), l.onBody(.{ 20.5, 15.5 }, false).n);
    l.carrier = .{ 30.5, 20.5 };
    const near_carrier = l.onBody(.{ 33.5, 20.5 }, false);
    const carrying = l.onBody(.{ 30.5, 20.5 }, true);
    std.debug.print("a rat 3 east of the archer has {d} light(s), the archer {d} and ambient {d:.3}\n", .{ near_carrier.n, carrying.n, lum(carrying.ambient) });
    try std.testing.expectEqual(@as(usize, 1), near_carrier.n);
    try std.testing.expect(near_carrier.drawn[0][0] < 33.5);
    try std.testing.expectEqual(@as(usize, 0), carrying.n);
    try std.testing.expect(lum(carrying.ambient) > lum(AMBIENT + CARRY) * 0.95);
}
