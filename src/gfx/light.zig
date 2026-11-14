const sprite_assets = @import("sprite_assets.zig");
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
const dual = @import("ground.zig");

pub const SUB = model.SUB;
const BODY_Z = model.BODY_Z;
pub const offMiddle = model.offMiddle;
pub const LIGHTS = model.LIGHTS;
pub const carryR = model.carryR;
pub const Shine = model.Shine;
pub const Flame = model.Flame;
pub const Emission = model.Emission;
pub const Reach = model.Reach;
pub const Options = model.Options;

/// Each light hung steps its flicker seed on by this from the first's.
const TORCH_SEED_STEP: u32 = 0x27D4EB2F;
const TORCH_SEED_BASE: u32 = 0x165667B1;

pub const Light = struct {
    options: Options = .{},
    effects: [model.EFFECTS]model.Effect = undefined,
    effect_n: usize = 0,
    visibility: visibility.Visibility,
    torch: [LIGHTS]model.Torch,
    torch_n: usize = 0,
    /// Lights hung since the level settled; each takes its flicker seed from it, never shared after an uproot.
    hung: u32 = 0,
    /// The hero's centre as drawn, cells.
    carrier: ?[2]f32 = null,
    /// Cells round the carrier its light fades out by.
    carry_r: f32 = model.CARRY_R,
    sky: ?sky.Sky = null,
    /// Integral image of caster counts at cell corners.
    casting: [grid.CORNERS_W * grid.CORNERS_H]u16,
    clouds: [grid.CORNERS_W * grid.CORNERS_H]f32,
    /// Cached inclusive cloud corners and sample time in seconds.
    clouds_held: ?struct { box: grid.Box, t: f32 } = null,
    t: mathx.Seconds = .{},
    texels: std.EnumArray(model.Layer, [model.TEXELS]rl.Color),
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
    /// Per light-map texel, `dapplingAt` its centre: fixed while the crowns are.
    dappling: [model.TEXELS]f32,
    banks: dual.Banks,

    /// Initialize fields separately to avoid a temporary larger than the thread stack.
    pub fn create(alloc: std.mem.Allocator) !*Light {
        const l = try alloc.create(Light);
        mathx.defaults(l);
        @memset(&l.casting, 0);
        mathx.defaults(&l.banks);
        l.visibility.reset();
        @memset(&l.scratch.tile, .floor);
        @memset(&l.scratch.flames, 0);
        @memset(&l.scratch.los, false);
        l.grounded();
        for (std.enums.values(model.Layer)) |k| @memset(l.texels.getPtr(k), model.UNSEEN.get(k));
        l.baked = .{ 0, model.MAP_H };
        l.visibility.soften();
        return l;
    }

    pub fn settle(self: *Light, lv: *const grid.Level) void {
        self.effect_n = 0;
        self.scratch = lv.*;
        self.grounded();
        self.countCasters(lv);
        self.torch_n = 0;
        self.hung = 0;
        for (lv.torches()) |w| self.hang(lv, .{ .wall = w });
        self.hangPlants(lv);
        self.visibility.snap(lv, self.reveal_map);
        self.t = .{};
        self.fan();
    }

    fn hang(self: *Light, lv: *const grid.Level, mount: model.Mount) void {
        const t = &self.torch[self.torch_n];
        t.* = model.Torch{ .mount = mount, .reach = undefined, .open = undefined, .seed = self.hung *% TORCH_SEED_STEP +% TORCH_SEED_BASE };
        self.hung +%= 1;
        self.torch_n += 1;
        self.pour(lv, t);
    }

    fn pour(self: *const Light, lv: *const grid.Level, t: *model.Torch) void {
        var pool: [grid.CELLS]bool = @splat(false);
        lume.torchPool(lv, t.floor(), &pool);
        var box = t.box().cells();
        while (box.next()) |p| {
            const k = t.texel(p);
            t.reach[k] = model.mask(grid.cellOr(bool, &pool, p, false));
            t.open[k] = self.visibility.openAt(p, t.reach[k]);
        }
    }

    pub fn uproot(self: *Light, lv: *const grid.Level, p: model.P) void {
        if (self.plantAt(p)) |i| _ = mathx.swapRemove(model.Torch, &self.torch, &self.torch_n, i);
        self.hangPlants(lv);
    }

    fn retile(self: *Light, lv: *const grid.Level) void {
        self.scratch.tile = lv.tile;
        self.scratch.flames = lv.flames;
        self.countCasters(&self.scratch);
        self.visibility.terrain(&self.scratch);
        self.visibility.soften();
        for (self.torch[0..self.torch_n]) |*t| self.pour(lv, t);
    }

    fn hangPlants(self: *Light, lv: *const grid.Level) void {
        var glows = lv.glowing();
        while (glows.next()) |q| {
            if (self.plantAt(q) == null) self.hang(lv, .{ .plant = q });
        }
    }

    fn plantAt(self: *const Light, p: model.P) ?usize {
        for (self.torch[0..self.torch_n], 0..) |*t, i| {
            if (t.mount == .plant and t.mount.plant.eq(p)) return i;
        }
        return null;
    }

    pub fn follow(self: *Light, lv: *const grid.Level) void {
        if (!std.mem.eql(grid.Tile, &self.scratch.tile, &lv.tile) or !std.mem.eql(u8, &self.scratch.flames, &lv.flames)) self.retile(lv);
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

    fn remembers(self: *const Light, lv: *const grid.Level, p: model.P) bool {
        return self.reveal_map or lv.isSeen(p);
    }

    fn fan(self: *Light) void {
        const plant = if (self.sky) |k| model.plantShare(k.daylight) else 1;
        for (self.torch[0..self.torch_n]) |*t| t.fan(self.t.at(), plant);
    }

    pub const TEXELS_W: usize = @intCast(model.MAP_W);

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
            var neighbours = grid.Cells.around(p, model.DAPPLE_REACH);
            var cover: f32 = 0;
            while (neighbours.next()) |q| {
                if (!look.crowned(self.scratch.at(q))) continue;
                const d = p.sub(q);
                cover += 1 / @as(f32, @floatFromInt(1 + d.x * d.x + d.y * d.y));
            }
            self.canopy[grid.Level.idx(p)] = @min(1, cover * model.DAPPLE_COVER);
        }
        for (&self.dappling, 0..) |*d, i| d.* = self.dapplingAt(texelCentreOf(i));
    }

    pub fn sightAt(self: *const Light, x: f32, y: f32) f32 {
        return self.visibility.sightAt(x, y);
    }

    pub fn memoryAt(self: *const Light, point: model.P) f32 {
        return self.visibility.memoryAt(point);
    }

    pub fn near(self: *const Light, view: grid.Box, out: *[LIGHTS]model.TorchIx) []const model.TorchIx {
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
        if (flat >= self.carry_r) return null;
        const reach = if (fogged) visibility.sampleOccluded(&self.visibility.sight, &self.visibility.carry_open, x, y) else self.carryReach(x, y);
        return .{ .at = c, .flat = flat, .dy = dy, .k = model.carryFade(flat, self.carry_r) * share * reach };
    }

    fn carried(self: *const Light, s: model.Spot) model.Rgb {
        const f = self.carryToward(s.x, s.y, true) orelse return model.splat(0);
        const facing = switch (s.surface) {
            .floor => 1,
            .face => model.wrapped(model.faceCos(f.dy, f.flat), model.CARRY_FACE_WRAP),
            .ceiling => model.CARRY_CEILING,
        };
        return self.carryColourAt(f.flat) * model.splat(f.k * facing);
    }

    fn carryReach(self: *const Light, x: f32, y: f32) f32 {
        const corner = mathx.cellOf(.{ x - 0.5, y - 0.5 });
        var reach: [4]f32 = undefined;
        var open: [4]f32 = undefined;
        for (0..4) |i| {
            const p = corner.add(mathx.unslot(i, 2));
            reach[i] = model.mask(self.scratch.inLos(p));
            open[i] = self.visibility.openAt(p, reach[i]);
        }
        const uv = visibility.fieldUv(corner, x, y);
        return visibility.occluded(&reach, &open, 2, 2, uv[0], uv[1]);
    }

    fn countCasters(self: *Light, lv: *const grid.Level) void {
        const w = grid.CORNERS_W;
        @memset(self.casting[0..w], 0);
        for (0..grid.ROWS) |y| {
            var row: u16 = 0;
            self.casting[(y + 1) * w] = 0;
            for (0..grid.COLS) |x| {
                row += @intFromBool(model.casterOf(lv.tile[y * grid.COLS + x]) != null);
                self.casting[(y + 1) * w + x + 1] = self.casting[y * w + x + 1] + row;
            }
        }
    }

    pub fn sunAt(self: *const Light, lv: *const grid.Level, ray: *const model.SunRay, x: f32, y: f32, z: f32) f32 {
        return self.sunOver(lv, dual.LiveBanks{ .lv = lv }, ray, x, y, z);
    }

    fn sunOver(self: *const Light, lv: *const grid.Level, banks: anytype, ray: *const model.SunRay, x: f32, y: f32, z: f32) f32 {
        if (!self.options.shadows or sky.upright(ray.flat)) return 1;
        const bank = model.bankSunlit(lv, banks, ray.*, x, y, z);
        const b = sunBox(ray.*, x, y, z);
        if (self.castersIn(b) == 0) return bank;
        return @min(bank, model.sunlit(lv, ray.*, x, y, z));
    }

    pub fn sunBox(ray: model.SunRay, x: f32, y: f32, z: f32) grid.Box {
        const far = ray.far(z);
        return grid.Box.between(mathx.cellOf(.{ x, y }), mathx.cellOf(ray.along(x, y, far))).grown(1);
    }

    pub fn castersIn(self: *const Light, box: grid.Box) u16 {
        const w = grid.CORNERS_W;
        const clip = box.grown(0);
        if (clip.hi.x <= clip.lo.x or clip.hi.y <= clip.lo.y) return 0;
        const a: usize = @intCast(clip.lo.x);
        const b: usize = @intCast(clip.lo.y);
        const c: usize = @intCast(clip.hi.x);
        const d: usize = @intCast(clip.hi.y);
        return self.casting[d * w + c] + self.casting[b * w + a] - self.casting[b * w + c] - self.casting[d * w + a];
    }

    fn carryShare(self: *const Light) f32 {
        return if (self.sky) |k| k.carry else 1;
    }

    fn ambientOf(self: *const Light) model.Rgb {
        return if (self.profile()) |k| k.ambient else model.splat(0);
    }

    fn profile(self: *const Light) ?sky.Sky {
        var k = self.sky orelse return null;
        if (self.composed) {
            k.key *= model.mix(model.splat(1), model.COMPOSED_KEY, k.sun());
            k.ambient *= model.mix(model.splat(1), model.COMPOSED_AMBIENT, k.sun());
        }
        return k;
    }

    fn sunRay(self: *const Light) ?model.SunRay {
        return if (self.profile()) |k| model.SunRay.of(k) else null;
    }

    /// The sun the clouds let through at `q`, composed; from the cached dappling when `q` is light-map texel `map_at`'s centre.
    fn composedAt(self: *const Light, map_at: ?usize, q: [2]f32, cloud: f32) f32 {
        const k = self.sky orelse return cloud;
        if (!self.composed or k.sun() == 0) return cloud;
        const dappling = if (map_at) |i| self.dappling[i] else self.dapplingAt(q);
        const patch = model.PATCH_LIFT - (1 - cloud) * model.PATCH_CLOUD - dappling;
        return mathx.lerpF(cloud, patch, k.sun());
    }

    fn dapplingAt(self: *const Light, q: [2]f32) f32 {
        const cover = visibility.sample(&self.canopy, q[0], q[1]);
        if (cover == 0) return 0;
        const dapple = 0.5 + 0.5 * @sin(q[0] * model.DAPPLE_WAVE[0] + q[1] * model.DAPPLE_WAVE[1] + @sin(q[1] * model.DAPPLE_WAVE[2]));
        return cover * (model.DAPPLE_MIN + model.DAPPLE_SPAN * dapple);
    }

    pub fn base(self: *const Light) model.Rgb {
        return @max(self.memoryFloor(), self.ambientOf());
    }

    pub fn memoryFloor(self: *const Light) model.Rgb {
        return model.memoryUnder(self.moon());
    }

    fn moon(self: *const Light) f32 {
        return if (self.sky) |k| k.moon else 0;
    }

    fn carryColour(self: *const Light) model.Rgb {
        return if (self.sky) |k| model.mix(model.CARRY, model.MOON_CARRY, k.moon) else model.CARRY;
    }

    fn carryColourAt(self: *const Light, flat: f32) model.Rgb {
        const warm = self.moon() * model.NIGHT_GLOW_SHARE * (1 - mathx.smoothstep(0, model.NIGHT_GLOW_R, flat));
        return model.mix(self.carryColour(), model.NIGHT_GLOW, warm);
    }

    /// Before a frame's `emit`s: effect lights last one frame.
    pub fn clearEffects(self: *Light) void {
        self.effect_n = 0;
    }

    pub fn emit(self: *Light, lv: *const grid.Level, source: Emission) void {
        if (!self.options.effect_lights) return;
        const origin = mathx.cellOf(.{ source.at[0], source.at[1] });
        if (self.effect_n == model.EFFECTS or source.gain <= model.FAINT or source.radius <= 0 or !lv.isLit(origin)) return;
        const e = &self.effects[self.effect_n];
        self.effect_n += 1;
        e.source = source;
        e.source.radius = @min(source.radius, model.EFFECT_REACH - 1);
        e.origin = origin;
        @memset(&e.reach, false);
        var cells = grid.Cells.around(origin, @intFromFloat(@ceil(e.source.radius)));
        while (cells.next()) |p| {
            e.reach[e.texel(p).?] = grid.Level.inside(p) and grid.clearLine(lv, origin, p);
        }
    }

    pub fn effectsNear(self: *const Light, c: model.P) model.EffectSet {
        var kept = model.EffectSet.initEmpty();
        const x: f32 = @floatFromInt(c.x);
        const y: f32 = @floatFromInt(c.y);
        for (self.effects[0..self.effect_n], 0..) |*e, i| {
            const s = e.source;
            if (s.at[0] + s.radius <= x or s.at[0] - s.radius >= x + 1 or
                s.at[1] + s.radius <= y or s.at[1] - s.radius >= y + 1 + model.FACE_H) continue;
            kept.set(i);
        }
        return kept;
    }

    /// `q` is in cells.
    pub fn at(self: *const Light, lv: *const grid.Level, torches: []const model.TorchIx, q: [2]f32) model.Rgb {
        const c = mathx.cellOf(q);
        const fade = self.visibility.fadeOf(c);
        const ray = self.sunRay();
        const cloud = if (ray != null) self.cloudAt(q) else 1;
        return self.shade(lv, torches, self.effectsNear(c), q, null, self.visibility.viewIn(q, &fade), if (ray) |*r| r else null, cloud);
    }

    /// `cloud` is the share of the sky's light the clouds let through, read only with a `ray`.
    pub fn shade(self: *const Light, lv: *const grid.Level, torches: []const model.TorchIx, effects: model.EffectSet, q: [2]f32, map_at: ?usize, v: View, ray: ?*const model.SunRay, cloud: f32) model.Rgb {
        return self.shadeWithSun(lv, dual.LiveBanks{ .lv = lv }, torches, effects, q, map_at, v, ray, cloud, self.floors()).colour;
    }

    const Shaded = struct { colour: model.Rgb, sun: ?f32 = null };

    const Floors = struct { memory: model.Rgb, view: model.Rgb };

    fn floors(self: *const Light) Floors {
        const memory = self.memoryFloor();
        return .{ .memory = memory, .view = @max(memory, self.ambientOf()) };
    }

    fn shadeWithSun(self: *const Light, lv: *const grid.Level, banks: anytype, torches: []const model.TorchIx, effects: model.EffectSet, q: [2]f32, map_at: ?usize, v: View, ray: ?*const model.SunRay, cloud: f32, under: Floors) Shaded {
        const sight = v.sight;
        const memory = v.memory;
        if (memory <= model.FAINT) return .{ .colour = @splat(0) };
        var sun: ?f32 = null;
        const floor = under.memory;
        var view = under.view;
        if (sight > model.FAINT) {
            const s = model.Spot.of(lv, q);
            view += self.carried(s);
            var props: model.Rgb = @splat(0);
            for (torches) |i| {
                const t = &self.torch[i];
                props = @max(props, t.colour * model.splat(t.shine(s)));
            }
            view += props;
            if (ray) |r| {
                const facing = model.sunFacing(r.k, s);
                if (facing > 0 or r.night > 0) {
                    const on = self.sunOver(lv, banks, r, s.x, s.y, s.z);
                    if (s.x == q[0] and s.y == q[1] and s.z == 0) sun = on;
                    if (facing > 0) view += r.k.key * model.splat(facing * model.reaching(on, self.composedAt(map_at, q, cloud)));
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
                        .face, .ceiling => model.upright(s.surface, e.source.at[0] - s.x, e.source.at[1] - s.y),
                    };
                    view += model.rgbOf(e.source.col) * model.splat(strength * facing);
                }
            }
        }
        return .{ .colour = model.remembered(floor, view, sight, memory), .sun = sun };
    }

    /// Cells `lo` up to `hi`, and a texel round them for the filter.
    pub fn bake(self: *Light, lv: *const grid.Level, lo: model.P, hi: model.P) void {
        var ids: [LIGHTS]model.TorchIx = undefined;
        const torches = self.near((grid.Box{ .lo = lo, .hi = hi }).grown(1), &ids);
        const t0 = model.P{ .x = @max(0, lo.x * SUB - 1), .y = @max(0, lo.y * SUB - 1) };
        const t1 = model.P{ .x = @min(model.MAP_W, hi.x * SUB + 1), .y = @min(model.MAP_H, hi.y * SUB + 1) };
        const ray = self.sunRay();
        if (ray != null) self.banks.sync(lv);
        self.baked = .{ @min(self.baked[0], t0.y), @max(self.baked[1], t1.y) };
        const c0 = model.P{ .x = @divFloor(t0.x, SUB), .y = @divFloor(t0.y, SUB) };
        if (ray != null) self.cloudsOver(c0, .{ .x = std.math.divCeil(i32, t1.x, SUB) catch unreachable, .y = std.math.divCeil(i32, t1.y, SUB) catch unreachable });
        const same_terrain = std.mem.eql(grid.Tile, &lv.tile, &self.scratch.tile);
        const under = self.floors();
        var c = model.P{ .x = 0, .y = c0.y };
        while (c.y * SUB < t1.y) : (c.y += 1) {
            c.x = c0.x;
            while (c.x * SUB < t1.x) : (c.x += 1) self.bakeCell(lv, torches, c, t0, t1, ray, same_terrain, under);
        }
    }

    /// The corners from `lo` to `hi`, both inclusive.
    fn cloudsOver(self: *Light, lo: model.P, hi: model.P) void {
        const t = self.t.at();
        var y = lo.y;
        while (y <= hi.y) : (y += 1) {
            var x = lo.x;
            while (x <= hi.x) : (x += 1) self.clouds[cornerAt(.{ .x = x, .y = y })] = model.clouded(@floatFromInt(x), @floatFromInt(y), t);
        }
        self.clouds_held = .{ .box = .{ .lo = lo, .hi = hi }, .t = t };
    }

    fn cornerAt(p: model.P) usize {
        return @as(usize, @intCast(p.y)) * grid.CORNERS_W + @as(usize, @intCast(p.x));
    }

    fn cloudAt(self: *const Light, q: [2]f32) f32 {
        const c = mathx.cellOf(q);
        return model.cloudIn(self.cloudCorners(c), c, q);
    }

    fn cloudCorners(self: *const Light, c: model.P) [4]f32 {
        const t = self.t.at();
        if (self.clouds_held) |h| {
            if (h.t == t and h.box.holds(c)) return self.heldCorners(c);
        }
        const cx: f32 = @floatFromInt(c.x);
        const cy: f32 = @floatFromInt(c.y);
        return .{
            model.clouded(cx, cy, t),
            model.clouded(cx + 1, cy, t),
            model.clouded(cx, cy + 1, t),
            model.clouded(cx + 1, cy + 1, t),
        };
    }

    pub fn heldCorners(self: *const Light, c: model.P) [4]f32 {
        const k = cornerAt(c);
        return .{ self.clouds[k], self.clouds[k + 1], self.clouds[k + grid.CORNERS_W], self.clouds[k + grid.CORNERS_W + 1] };
    }

    fn bakeCell(self: *Light, lv: *const grid.Level, torches: []const model.TorchIx, c: model.P, t0: model.P, t1: model.P, ray: ?model.SunRay, same_terrain: bool, under: Floors) void {
        const fade = self.visibility.fadeOf(c);
        const dark = if (fade.flat) |v| v == 0 else false;
        const x0 = @max(t0.x, c.x * SUB);
        const x1 = @min(t1.x, (c.x + 1) * SUB);
        const y0 = @max(t0.y, c.y * SUB);
        const y1 = @min(t1.y, (c.y + 1) * SUB);
        if (dark) {
            var y = y0;
            while (y < y1) : (y += 1) {
                const first: usize = @intCast(y * model.MAP_W + x0);
                const last: usize = @intCast(y * model.MAP_W + x1);
                inline for (comptime std.enums.values(model.Layer)) |k| @memset(self.texels.getPtr(k)[first..last], model.UNSEEN.get(k));
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
                const i: usize = @intCast(ty * model.MAP_W + tx);
                glints[i] = model.UNSEEN.get(.glints);
                const q = texelCentre(@intCast(tx), @intCast(ty));
                const v = fade.view(patch.sightAt(ground, q[0], q[1]), q);
                fog[i] = look.fade(rl.Color.white, 1 - v.memory);
                const cloud = if (ray != null) model.cloudIn(corners, c, q) else 1;
                const shaded = self.shadeWithSun(lv, &self.banks, torches, effects, q, i, v, if (ray) |*r| r else null, cloud, under);
                map[i] = model.texelOf(shaded.colour, v.lit);
                if (self.options.water_glints and wet and v.lit > model.FAINT)
                    glints[i] = look.colourOf(self.waterGlintWithSun(torches, effects, q, i, if (ray) |*r| r else null, cloud, if (same_terrain) shaded.sun else null), 1);
            }
        }
    }

    pub fn waterGlint(self: *const Light, torches: []const model.TorchIx, effects: model.EffectSet, q: [2]f32, map_at: ?usize, ray: ?*const model.SunRay, cloud: f32) model.Rgb {
        return self.waterGlintWithSun(torches, effects, q, map_at, ray, cloud, null);
    }

    fn waterGlintWithSun(self: *const Light, torches: []const model.TorchIx, effects: model.EffectSet, q: [2]f32, map_at: ?usize, ray: ?*const model.SunRay, cloud: f32, sun: ?f32) model.Rgb {
        var gleam: model.Rgb = @splat(0);
        if (ray) |r| {
            const on = sun orelse self.sunAt(&self.scratch, r, q[0], q[1], 0);
            gleam += r.k.key * model.splat(r.glint * model.reaching(on, self.composedAt(map_at, q, cloud)) * model.SUN_GLINT);
        }
        if (self.carryToward(q[0], q[1], true)) |f|
            gleam += self.carryColour() * model.splat(model.smoothSpecular(.{ f.at[0] - q[0], f.at[1] - q[1], BODY_Z }, model.GLINT_POWER) * f.k * model.CARRY_GLINT);
        for (torches) |i| {
            const t = &self.torch[i];
            const r = t.toward(q[0], q[1], 0) orelse continue;
            gleam += t.colour * model.splat(model.smoothSpecular(r.d, model.GLINT_POWER) * r.k * model.TORCH_GLINT);
        }
        var it = effects.iterator(.{});
        while (it.next()) |i| {
            const e = &self.effects[i];
            const s = e.source;
            const k = e.strength(q[0], q[1], 0);
            if (k <= model.FAINT) continue;
            gleam += model.rgbOf(s.col) * model.splat(model.smoothSpecular(model.offset(s.at, q[0], q[1], 0), model.GLINT_POWER) * k * model.EFFECT_GLINT);
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
        const night: model.Rgb = if (self.sunRay()) |ray| self.sunOnBody(&s, &ray, centre, lit) else model.splat(1);
        const floor = self.memoryFloor();
        s.ambient = model.remembered(floor, self.base() * night, v.sight, v.memory);
        s.floor = model.remembered(floor, (self.base() - self.ambientOf()) * night, v.sight, v.memory);
        if (self.carryToward(centre[0], centre[1], fogged)) |f| {
            const k = f.k * lit;
            if (carrier) {
                s.ambient += self.carryColourAt(f.flat) * model.splat(k) * night;
            } else if (k > model.FAINT) {
                s.add(.{ .drawn = f.at, .ground = f.at, .colour = self.carryColourAt(f.flat) * model.splat(k), .casts = false });
            }
        }
        for (self.torch[0..self.torch_n]) |*t| {
            const r = t.toward(centre[0], centre[1], BODY_Z) orelse continue;
            const k = r.k * lit;
            if (k <= model.FAINT) continue;
            const fl = t.flame();
            s.add(.{ .drawn = t.drawn(), .ground = .{ fl[0], fl[1] }, .colour = t.colour * model.splat(k), .casts = true });
        }
        for (s.lamp[0..s.n]) |*l| l.colour *= night;
        for (self.effects[0..self.effect_n]) |*e| {
            const k = e.strength(centre[0], centre[1], BODY_Z) * lit;
            if (k <= model.FAINT) continue;
            const p = e.source.at;
            s.add(.{ .drawn = e.source.drawn(), .ground = .{ p[0], p[1] }, .colour = model.rgbOf(e.source.col) * model.splat(k), .casts = true });
        }
        return s;
    }

    fn sunOnBody(self: *const Light, s: *Shine, ray: *const model.SunRay, centre: [2]f32, lit: f32) model.Rgb {
        const k = ray.k;
        const sun = self.sunAt(&self.scratch, ray, centre[0], centre[1], BODY_Z);
        const cloud = self.cloudAt(centre);
        const on = model.reaching(sun, self.composedAt(null, centre, cloud));
        if (lit > 0) s.add(.{
            .drawn = ray.along(centre[0], centre[1], model.SUN_LAMP_D),
            .ground = ray.along(centre[0], centre[1], 1),
            .colour = k.key * model.splat(lit * on),
            .casts = !sky.upright(ray.flat),
            .sky = .{ .reach = k.reach(), .depth = model.skyDepth(k, sun * cloud) * lit, .shade = ray.shade },
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

    pub fn syncFigures(self: *Light, figures: *const [sprite_assets.FIGURES]?rl.Texture2D) void {
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
        self.baked = model.NONE_BAKED;
    }

    pub fn drawBody(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, shine: *const Shine, flash: f32, opacity: f32, fade_bounds: [2]f32) void {
        self.gpu.drawBody(tex, dest, left, centre, shine, flash, opacity, fade_bounds, self.options.body_lighting);
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

    pub fn drawGlows(self: *Light, sources: []const Flame, ox: f32, oy: f32, cell: f32, screen: model.P, outer: u32) void {
        self.gpu.drawGlows(sources, ox, oy, cell, screen, outer);
    }
};

pub const glowAt = light_gpu.glowAt;
