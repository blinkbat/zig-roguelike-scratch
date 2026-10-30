const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const sky = @import("sky.zig");
const lume = @import("../map/lume.zig");
const shadow = @import("shadow.zig");
const light_gpu = @import("light_gpu.zig");
const visibility = @import("light_visibility.zig");

const model = @import("light_model.zig");

const P = model.P;
pub const Rgb = model.Rgb;
const mix = model.mix;
pub const SUB = model.SUB;
pub const MAP_W = model.MAP_W;
pub const MAP_H = model.MAP_H;
const NONE_BAKED = model.NONE_BAKED;
pub const TEXELS = model.TEXELS;
pub const Layer = model.Layer;
pub const UNSEEN = model.UNSEEN;
pub const OVERBRIGHT = model.OVERBRIGHT;
pub const REACH = model.REACH;
pub const WALL_H = model.WALL_H;
const FACE_H = model.FACE_H;
pub const BODY_Z = model.BODY_Z;
pub const CARRY = model.CARRY;
const MOON_CARRY = model.MOON_CARRY;
const CARRY_R = model.CARRY_R;
const CARRY_CEILING = model.CARRY_CEILING;
const CARRY_FACE_WRAP = model.CARRY_FACE_WRAP;
pub const MEMORY = model.MEMORY;
pub const FAINT = model.FAINT;
pub const VOID_REACH = model.VOID_REACH;
const CORNERS_W = model.CORNERS_W;
const CORNERS_H = model.CORNERS_H;
pub const FLICKER = model.FLICKER;
pub const KNEE = model.KNEE;
pub const BODY_LIGHTS = model.BODY_LIGHTS;
pub const FLASH_RGB = model.FLASH_RGB;
pub const SHADE_RGB = model.SHADE_RGB;
pub const SHADOW_MAX = model.SHADOW_MAX;
pub const SHADOW_TAPS = model.SHADOW_TAPS;
pub const SUN_SOFT = model.SUN_SOFT;
pub const SUN_EDGE = model.SUN_EDGE;
const SUN_LAMP_D = model.SUN_LAMP_D;
pub const CASTERS = model.CASTERS;
pub const sunlit = model.sunlit;
const clouded = model.clouded;
const reaching = model.reaching;
pub const SunRay = model.SunRay;
const cloudIn = model.cloudIn;
const sunFacing = model.sunFacing;
pub const Surface = model.Surface;
pub const topOf = model.topOf;
const offset = model.offset;
pub const offMiddle = model.offMiddle;
pub const Spot = model.Spot;
pub const TorchIx = model.TorchIx;
pub const LIGHTS = model.LIGHTS;
const PLANT_LIGHTS = model.PLANT_LIGHTS;
const Torch = model.Torch;
const Mount = model.Mount;
const upright = model.upright;
pub const GLINT_POWER = model.GLINT_POWER;
const SUN_GLINT = model.SUN_GLINT;
const CARRY_GLINT = model.CARRY_GLINT;
const TORCH_GLINT = model.TORCH_GLINT;
const EFFECT_GLINT = model.EFFECT_GLINT;
pub const smoothSpecular = model.smoothSpecular;
const remembered = model.remembered;
pub const carryFade = model.carryFade;
const wrapped = model.wrapped;
pub const texel = model.texel;
pub const mask = model.mask;
pub const flicker = model.flicker;
const faceCos = model.faceCos;
const splat = model.splat;
const rgbOf = model.rgbOf;
pub const colourOf = model.colourOf;
pub const texelOf = model.texelOf;
const skyDepth = model.skyDepth;
pub const castShare = model.castShare;
pub const Shine = model.Shine;
pub const Flame = model.Flame;
const COMPOSED_KEY = model.COMPOSED_KEY;
const COMPOSED_AMBIENT = model.COMPOSED_AMBIENT;
const PATCH_LIFT = model.PATCH_LIFT;
const PATCH_CLOUD = model.PATCH_CLOUD;
const DAPPLE_WAVE = model.DAPPLE_WAVE;
const DAPPLE_MIN = model.DAPPLE_MIN;
const DAPPLE_SPAN = model.DAPPLE_SPAN;
const DAPPLE_REACH = model.DAPPLE_REACH;
const DAPPLE_COVER = model.DAPPLE_COVER;
pub const Emission = model.Emission;
pub const EFFECTS = model.EFFECTS;
pub const EffectSet = model.EffectSet;
const EFFECT_REACH = model.EFFECT_REACH;
pub const EFFECT_SPAN = model.EFFECT_SPAN;
const Effect = model.Effect;
pub const Options = model.Options;

pub const Light = struct {
    options: Options = .{},
    effects: [EFFECTS]Effect = undefined,
    effect_n: usize = 0,
    visibility: visibility.Visibility,
    torch: [LIGHTS]Torch,
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
        l.visibility.reset();
        @memset(&l.scratch.tile, .floor);
        @memset(&l.scratch.los, false);
        l.grounded();
        for (std.enums.values(Layer)) |k| @memset(l.texels.getPtr(k), UNSEEN.get(k));
        l.baked = .{ 0, MAP_H };
        l.visibility.soften();
        return l;
    }

    pub fn settle(self: *Light, lv: *const grid.Level) void {
        self.effect_n = 0;
        self.scratch = lv.*;
        self.grounded();
        self.countCasters(lv);
        self.torch_n = 0;
        for (lv.torches()) |w| self.hang(lv, .{ .wall = w });
        for (lv.tile, 0..) |t, i| {
            if (self.torch_n == lv.torches().len + PLANT_LIGHTS) break;
            if (t.glows()) self.hang(lv, .{ .plant = grid.Level.of(i) });
        }
        self.visibility.snap(lv, self.reveal_map);
        self.t = .{};
        self.fan();
    }

    fn hang(self: *Light, lv: *const grid.Level, mount: Mount) void {
        var t = Torch{ .mount = mount, .reach = undefined, .open = undefined, .seed = @as(u32, @intCast(self.torch_n)) *% 0x27D4EB2F +% 0x165667B1 };
        var pool: [grid.CELLS]bool = @splat(false);
        lume.torchPool(lv, t.floor(), &pool);
        var box = t.box().cells();
        while (box.next()) |p| {
            const k = t.texel(p);
            t.reach[k] = mask(grid.cellOr(bool, &pool, p, false));
            t.open[k] = t.reach[k] * grid.cellOr(f32, &self.visibility.see_through, p, 0);
        }
        self.torch[self.torch_n] = t;
        self.torch_n += 1;
    }

    /// A glowing plant gone from `p`: its light and its shadow with it.
    pub fn uproot(self: *Light, lv: *const grid.Level, p: P) void {
        for (self.torch[0..self.torch_n], 0..) |*t, i| {
            if (t.mount != .plant or !t.mount.plant.eq(p)) continue;
            _ = mathx.swapRemove(Torch, &self.torch, &self.torch_n, i);
            break;
        }
        self.scratch.tile[grid.Level.idx(p)] = lv.at(p);
        self.countCasters(&self.scratch);
    }

    pub fn step(self: *Light, lv: *const grid.Level, dt: f32) void {
        self.scratch.los = lv.los;
        self.visibility.step(lv, dt, self.reveal_map);
        self.t.step(dt);
        self.fan();
    }

    pub fn reveal(self: *Light, lv: *const grid.Level, enabled: bool) void {
        self.reveal_map = enabled;
        self.visibility.reveal(lv, enabled);
    }

    /// Drawn as terrain: explored, or everything while the debug reveal is on.
    pub fn remembers(self: *const Light, lv: *const grid.Level, p: P) bool {
        return self.reveal_map or lv.isSeen(p);
    }

    fn fan(self: *Light) void {
        for (self.torch[0..self.torch_n]) |*t| t.fan(self.t.at());
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
        self.visibility.terrain(&self.scratch);
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

    pub fn sightAt(self: *const Light, x: f32, y: f32) f32 {
        return self.visibility.sightAt(x, y);
    }

    pub fn memoryAt(self: *const Light, point: P) f32 {
        return self.visibility.memoryAt(point);
    }

    pub fn near(self: *const Light, view: grid.Box, out: *[LIGHTS]TorchIx) []const TorchIx {
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
        const reach = if (fogged) visibility.sampleOccluded(&self.visibility.sight, &self.visibility.carry_open, x, y) else self.carryReach(x, y);
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
            open[i] = reach[i] * grid.cellOr(f32, &self.visibility.see_through, p, 0);
        }
        return visibility.occluded(&reach, &open, 2, 2, x - 0.5 - @as(f32, @floatFromInt(corner.x)), y - 0.5 - @as(f32, @floatFromInt(corner.y)));
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
        const cover = visibility.sample(&self.canopy, q[0], q[1]);
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
        const fade = self.visibility.fadeOf(c);
        const ray = self.sunRay();
        const cloud = if (ray != null) self.cloudAt(q) else 1;
        return self.shade(lv, torches, self.effectsNear(c), q, null, self.visibility.viewIn(q, &fade), if (ray) |*r| r else null, cloud);
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
        var ids: [LIGHTS]TorchIx = undefined;
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
        const fade = self.visibility.fadeOf(c);
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

        const patch = visibility.Patch.of(&self.visibility, c);
        const ground = self.visibility.groundAt(c);
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
                const v = fade.view(patch.sightAt(ground, q[0], q[1]), q);
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

    const View = visibility.View;

    pub fn viewAt(self: *const Light, point: [2]f32) View {
        return self.visibility.viewAt(point);
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
    pub fn flames(self: *const Light, lv: *const grid.Level, out: *[LIGHTS]Flame) []const Flame {
        var n: usize = 0;
        for (self.torch[0..self.torch_n]) |*t| {
            if (t.mount == .wall and !self.remembers(lv, t.mount.wall)) continue;
            if (!self.remembers(lv, t.floor())) continue;
            const d = t.drawn();
            const v = self.viewAt(d);
            const face = self.viewAt(mathx.centre(t.floor()));
            out[n] = .{ .kind = t.mount, .at = d, .foot = t.flame()[1], .glow = t.glow, .lit = @min(v.lit, face.lit), .memory = v.memory };
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

    pub fn drawMap(self: *Light, ox: i32, oy: i32, cell: i32) void {
        self.uploadMap();
        self.gpu.drawMap(ox, oy, cell);
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
        self.gpu.uploadRows(&self.texels, self.baked);
        self.baked = NONE_BAKED;
    }

    pub fn drawBody(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, shine: *const Shine, flash: f32, fade_bounds: [2]f32) void {
        self.gpu.drawBody(tex, dest, left, centre, shine, flash, fade_bounds, self.options.body_lighting);
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
        return self.gpu.beginMirrorFade(bounds);
    }

    pub const beginShadows = shadow.beginShadows;
    pub const endShadows = shadow.endShadows;
    pub const drawShadows = shadow.drawShadows;
    pub const drawCanopy = shadow.drawCanopy;
    pub const drawForestShadows = shadow.drawForestShadows;

    pub fn drawGlows(self: *const Light, sources: []const Flame, ox: f32, oy: f32, cell: f32) void {
        self.gpu.drawGlows(sources, ox, oy, cell);
    }
};

pub const glowAt = light_gpu.glowAt;
pub const flashed = model.flashed;
