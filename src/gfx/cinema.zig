const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const raster = @import("raster.zig");
const shaders = @import("shaders.zig");
const light = @import("light.zig");
const sky = @import("sky.zig");
const climate = @import("../map/climate.zig");
const day = @import("../map/day.zig");
const light_visibility = @import("light_visibility.zig");

pub const Options = struct {
    composed_lighting: bool = true,
    bloom: bool = true,
    atmosphere: bool = true,
    depth_of_field: bool = true,

    pub const off: Options = blk: {
        var o: Options = .{};
        for (std.meta.fields(Options)) |f| @field(o, f.name) = false;
        break :blk o;
    };
};
pub const Effect = std.meta.FieldEnum(Options);
pub const LIVE_ONLY = std.EnumSet(Effect).init(.{ .bloom = true, .atmosphere = true });

const Focus = struct { shader: rl.Shader, texel: i32, strength: i32 };

const Focused = look.Focused;
const Bloom = struct { shader: rl.Shader, field: i32, visibility: i32, glints: i32, origin: i32, cell: i32, screen: i32, direction: i32, extract: i32, amount: i32 };
const Air = struct { shader: rl.Shader, field: i32, weather: i32, sight: i32, visibility: i32, origin: i32, cell: i32, screen: i32, time: i32, sunlight: i32, shaftlight: i32, brightness: i32, reflections: i32, beams: i32, amount: i32 };
const Grade = struct { shader: rl.Shader, visibility: i32, origin: i32, cell: i32, screen: i32 };

const MEMORY_GREY: f32 = 0.9;
const MEMORY_BRIGHTNESS: f32 = 0.7;

const FOCUS_MAX: f32 = 0.24;
/// Screen pixels between the bloom blur's taps, across then down.
const BLOOM_STEP: f32 = 2.0;
/// Rows from the hero that stay sharp, and from which scenery is softened fully.
const SHARP_ROWS: f32 = 3.5;
const SOFT_ROWS: f32 = 7.5;
const EMISSIVE_REACH: f32 = 1.5;
/// The dimmest sky the water mist is still drawn under, as a share of a clear noon.
const AIR_DARKEST: f32 = 0.06;
const SHAFT_NEAR: f32 = 1.1;
const SHAFT_SLANT: f32 = 0.48;
const SHAFT_SPACING = [2]f32{ 2.8, 3.6 };
const SHAFT_REACH = [2]f32{ 4.0, 10.5 };
const SHAFT_WIDTH = [2]f32{ 0.16, 0.82 };
const SHAFT_REFLECT: f32 = 0.42;
const SHAFT_SWAY: f32 = 0.025;
const SHAFT_POOL_WIDTH: f32 = 1.65;
const SHAFT_POOL_DEPTH = [2]f32{ 0.24, 0.32 };
const SHAFT_POOL_MAX = SHAFT_POOL_DEPTH[0] + SHAFT_WIDTH[1] * SHAFT_POOL_DEPTH[1];
const SHAFT_ROWS: i32 = @intFromFloat(@ceil(SHAFT_REACH[1] / SHAFT_SPACING[1]));
const SHAFT_REFLECT_ROWS: i32 = @intFromFloat(@ceil(SHAFT_REACH[1] * SHAFT_REFLECT / SHAFT_SPACING[1]));
const SHAFT_POOL_ROWS: i32 = @intFromFloat(@ceil(SHAFT_POOL_MAX / SHAFT_SPACING[1]));
const SHAFT_COLS: i32 = @intFromFloat(@ceil((SHAFT_WIDTH[1] * SHAFT_POOL_WIDTH + SHAFT_POOL_MAX * SHAFT_SLANT + SHAFT_SWAY) / SHAFT_SPACING[0]));
const SHAFT_REFLECT_COLS: i32 = 1 + @as(i32, @intFromFloat(@ceil((2 * SHAFT_SLANT * SHAFT_REACH[1] * SHAFT_REFLECT + SHAFT_WIDTH[1] + SHAFT_SWAY) / SHAFT_SPACING[0])));
const FIELD_MARGIN: i32 = @intFromFloat(@ceil(@max(SHAFT_REACH[1], SHAFT_REACH[1] * SHAFT_SLANT + SHAFT_WIDTH[1] * SHAFT_POOL_WIDTH) + SHAFT_NEAR));
const BLOOM_GAIN: f32 = 0.22;
/// Peak opacity of the water mist, the canopy's light shafts and the large dust motes in them.
const MIST_GAIN: f32 = 0.065;
const SHAFT_GAIN: f32 = 0.14;
const DUST_GAIN: f32 = 0.64;
const DUST_SMALL_GAIN: f32 = 1.45;
const SHAFT_MORNING = [2]f32{ day.SUNRISE + 2, day.SUNRISE + 4 };
const SHAFT_EVENING = [2]f32{ day.SUNSET - 4, day.SUNSET - 2 };
const SHAFT_EMPTY: f32 = 0.19;
const SHAFT_REFLECT_GAIN: f32 = 0.45;
const SHAFT_POOL_GAIN: f32 = 0.65;
/// In cells; each holds at most one mote.
const DUST_SIZE = [2]f32{ 0.65, 1.6 };
/// Of the dust cells, the share with no mote: a seed below this.
const DUST_EMPTY: f32 = 0.36;
const DUST_LARGE: f32 = 0.91;
/// In cells; each holds at most one leaf, which falls its height in a lifetime.
const LEAF_SIZE = [2]f32{ 2.2, 3.2 };
const LEAF_EMPTY: f32 = 0.45;
/// Lifetimes a second.
const LEAF_FALL = [2]f32{ 0.07, 0.11 };
/// Radians a second of the side-to-side swoop; its reach in cells, the rise at each end, and the tilt there.
const LEAF_SWING = [2]f32{ 1.5, 2.3 };
const LEAF_SWAY: f32 = 0.3;
const LEAF_LIFT: f32 = 0.12;
const LEAF_TILT: f32 = 0.7;
/// In sprite pixels from the middle to the tip, and the blade's depth.
const LEAF_LENGTH: f32 = 1.6;
const LEAF_WIDTH: f32 = 0.8;
const LEAF_STEM: f32 = 0.55;
const LEAF_GAIN: f32 = 0.8;
const LEAF_SHADE: f32 = 0.35;
const LEAF_DIM: f32 = 0.4;
/// Cells a second the mist drifts east.
const AIR_DRIFT: f32 = 0.025;
/// In the thickest weather mist, how many times over the water mist thickens, and the peak opacity of the mist over land.
const WEATHER_MIST_WATER: f32 = 2;
const WEATHER_MIST_LAND: f32 = 0.11;

fn focusStrength(t: grid.Tile, at: [2]f32, hero: ?[2]f32) f32 {
    if (!look.SOFTENED.contains(t)) return 0;
    const h = hero orelse return 0;
    return FOCUS_MAX * mathx.smoothstep(SHARP_ROWS, SOFT_ROWS, @abs(at[1] - h[1]));
}

const FIELD = .{ .lit = "r", .water = "g", .emissive = "b", .crown = "a" };
const WEATHER = .{ .beam = "r", .mist = "g", .seen = "a" };
const FIELD_DEFINES = shaders.channelDefines(FIELD) ++ shaders.channelDefines(WEATHER);

fn markEmissive(pixels: *[grid.CELLS]rl.Color, at: [2]f32) bool {
    var marked = false;
    var cells = grid.Box.around(mathx.cellOf(at), @intFromFloat(@ceil(EMISSIVE_REACH))).grown(0).cells();
    while (cells.next()) |p| {
        const pixel = &pixels[grid.Level.idx(p)];
        if (@field(pixel, FIELD.lit) == 0) continue;
        if (light.offMiddle(p, at) >= EMISSIVE_REACH) continue;
        @field(pixel, FIELD.emissive) = 255;
        marked = true;
    }
    return marked;
}

pub const Cinema = struct {
    pub const Strengths = struct { bloom: f32 = 1, atmosphere: f32 = 1, depth_of_field: f32 = 1 };
    strengths: Strengths = .{},
    lens: @import("lens.zig").Lens = .{},
    options: Options = .{},
    focus: ?Focus = null,
    bloom: ?Bloom = null,
    air: ?Air = null,
    grade: ?Grade = null,
    field: ?rl.Texture2D = null,
    weather_field: ?rl.Texture2D = null,
    sight_field: ?rl.Texture2D = null,
    /// The visibility fields `sight_field` holds.
    sight_of: ?struct { from: *const light_visibility.Visibility, revision: u32 } = null,
    field_pixels: [grid.CELLS]rl.Color = undefined,
    weather_pixels: [grid.CELLS]rl.Color = undefined,
    sight_pixels: light_visibility.SightPixels = undefined,
    scene: ?rl.RenderTexture2D = null,
    spread: ?rl.RenderTexture2D = null,
    active_bloom: bool = false,
    active_air: bool = false,
    active_beams: bool = false,

    pub fn load(self: *Cinema) void {
        self.lens.load();
        self.focus = shaders.program(Focus, FOCUS_FS);
        self.bloom = shaders.program(Bloom, BLOOM_FS);
        self.air = shaders.program(Air, AIR_FS);
        self.grade = shaders.program(Grade, GRADE_FS);
        self.field = raster.canvas(grid.W, grid.H, rl.Color.blank, .point);
        self.weather_field = raster.canvas(grid.W, grid.H, rl.Color.blank, .point);
        var sight_pixels: light_visibility.SightPixels = @splat(.{});
        self.sight_of = null;
        self.sight_field = raster.clamped(raster.image(&sight_pixels, grid.W, grid.H, .uncompressed_r32g32b32a32), .point);
    }

    pub fn unload(self: *Cinema) void {
        self.lens.unload();
        raster.unloadAll(self);
    }

    pub fn prepare(self: *Cinema, lv: *const grid.Level, l: *const light.Light, view: grid.Box, flames: []const light.Flame, blend: *const climate.Blend, weather: climate.Local) void {
        self.active_bloom = false;
        self.active_air = false;
        self.active_beams = false;
        const air_on = self.airs(l);
        if (!self.options.bloom and !air_on) return;
        const tex = self.field orelse return;
        const pixels = &self.field_pixels;
        @memset(pixels, rl.Color.blank);
        const weather_pixels = &self.weather_pixels;
        if (air_on) @memset(weather_pixels, rl.Color.blank);
        var cells = view.grown(FIELD_MARGIN).cells();
        while (cells.next()) |p| {
            if (!lv.isSeen(p)) continue;
            const t = lv.at(p);
            const i = grid.Level.idx(p);
            const pixel = &pixels[i];
            @field(pixel, FIELD.lit) = if (lv.isLit(p)) 255 else 0;
            if (look.reflects(t)) {
                @field(pixel, FIELD.water) = 255;
                self.active_bloom = true;
                self.active_air = air_on;
            }
            if (look.crowned(t)) @field(pixel, FIELD.crown) = 255;
            if (air_on) {
                const local = blend.cell(weather, i);
                const beam = unitByte(local.get(.beams));
                const mist = unitByte(local.get(.mist));
                self.active_beams = self.active_beams or beam > 0;
                self.active_air = self.active_air or beam > 0 or mist > 0;
                const cell = &weather_pixels[i];
                @field(cell, WEATHER.beam) = beam;
                @field(cell, WEATHER.mist) = mist;
                @field(cell, WEATHER.seen) = 255;
            }
        }
        for (flames) |f| {
            if (f.live() and markEmissive(pixels, f.at)) self.active_bloom = true;
        }
        for (l.effects[0..l.effect_n]) |*e| {
            if (markEmissive(pixels, e.source.drawn())) self.active_bloom = true;
        }
        rl.updateTexture(tex, pixels);
        if (!self.active_air) return;
        if (self.weather_field) |w| rl.updateTexture(w, weather_pixels);
        const s = self.sight_field orelse return;
        const v = &l.visibility;
        if (self.sight_of) |was| if (was.from == v and was.revision == v.revision) return;
        v.sightPixels(&self.sight_pixels);
        rl.updateTexture(s, &self.sight_pixels);
        self.sight_of = .{ .from = v, .revision = v.revision };
    }

    fn blooms(self: *const Cinema) bool {
        return self.options.bloom and self.active_bloom and self.bloom != null and self.field != null;
    }

    fn airs(self: *const Cinema, l: *const light.Light) bool {
        return self.options.atmosphere and self.strengths.atmosphere > 0 and l.sky != null;
    }

    pub fn beginScene(self: *Cinema, screen: mathx.P, outer: u32) bool {
        if (!self.blooms() and self.grade == null) return false;
        return raster.beginTarget(&self.scene, screen, outer, look.FOG);
    }

    pub fn endScene(self: *Cinema, outer: u32, origin: [2]f32, cell: f32, l: *light.Light) void {
        raster.endTarget(outer);
        const scene = self.scene.?.texture;
        const size = raster.extentOf(scene);
        const visibility = l.mapTexture();
        const glints = l.glintTexture();
        const view = shaders.MapView.at(origin, cell, size);
        if (self.blooms() and visibility != null and glints != null and raster.beginTarget(&self.spread, size, outer, rl.Color.black)) {
            const b = self.bloom.?;
            rl.beginShaderMode(b.shader);
            self.bindBloom(b, view, visibility.?, glints.?, .{ BLOOM_STEP, 0 }, true);
            drawTarget(scene);
            rl.endShaderMode();
            raster.endTarget(outer);
            self.composite(scene, view, visibility);
            rl.beginBlendMode(.additive);
            rl.beginShaderMode(b.shader);
            self.bindBloom(b, view, visibility.?, glints.?, .{ 0, BLOOM_STEP }, false);
            drawTarget(self.spread.?.texture);
            rl.endShaderMode();
            rl.endBlendMode();
        } else self.composite(scene, view, visibility);
    }

    fn composite(self: *const Cinema, scene: rl.Texture2D, view: shaders.MapView, visibility: ?rl.Texture2D) void {
        const g = self.grade orelse return copyTarget(scene);
        const v = visibility orelse return copyTarget(scene);
        raster.beginReplace();
        rl.beginShaderMode(g.shader);
        shaders.setMapView(g, view);
        rl.setShaderValueTexture(g.shader, g.visibility, v);
        drawTarget(scene);
        rl.endShaderMode();
        rl.endBlendMode();
    }

    fn bindBloom(self: *Cinema, b: Bloom, view: shaders.MapView, visibility: rl.Texture2D, glints: rl.Texture2D, direction: [2]f32, extract: bool) void {
        setField(b, self.field.?, visibility, view);
        rl.setShaderValueTexture(b.shader, b.glints, glints);
        shaders.setFields(b, .{ .direction = direction, .extract = extract, .amount = self.strengths.bloom });
    }

    pub fn beginFocus(self: *Cinema, t: grid.Tile, tex: rl.Texture2D, at: [2]f32, hero: ?[2]f32) ?Focused {
        const focused = self.focusOf(t, tex, at, hero) orelse return null;
        const f = self.focus.?;
        rl.beginShaderMode(f.shader);
        focused.set(f);
        return focused;
    }

    pub fn focusOf(self: *const Cinema, t: grid.Tile, tex: rl.Texture2D, at: [2]f32, hero: ?[2]f32) ?Focused {
        if (!self.options.depth_of_field) return null;
        const strength = focusStrength(t, at, hero) * self.strengths.depth_of_field;
        if (strength <= 0) return null;
        if (self.focus == null) return null;
        const size = raster.sizeOf(tex);
        return Focused{ .texel = .{ 1 / size[0], 1 / size[1] }, .strength = strength };
    }

    pub fn drawAir(self: *Cinema, l: *light.Light, origin: [2]f32, cell: f32, screen: mathx.P, hour: f32, reflections: bool) void {
        if (!self.active_air or !self.airs(l)) return;
        const k = l.sky.?;
        const a = self.air orelse return;
        const field = self.field orelse return;
        const visibility = l.mapTexture() orelse return;
        const weather = self.weather_field orelse return;
        const sight = self.sight_field orelse return;
        raster.beginBlend(rl.gl.rl_one, rl.gl.rl_one_minus_src_color, rl.gl.rl_func_add);
        rl.beginShaderMode(a.shader);
        setField(a, field, visibility, .at(origin, cell, screen));
        rl.setShaderValueTexture(a.shader, a.weather, weather);
        rl.setShaderValueTexture(a.shader, a.sight, sight);
        const sunlight = k.sun() * std.math.clamp(sky.luma(k.key), 0, 1);
        const h = day.wrapHour(hour);
        const beam_day = mathx.smoothstep(SHAFT_MORNING[0], SHAFT_MORNING[1], h) * (1 - mathx.smoothstep(SHAFT_EVENING[0], SHAFT_EVENING[1], h));
        shaders.setFields(a, .{
            .time = l.t.at(),
            .sunlight = sunlight,
            .shaftlight = sunlight * beam_day,
            .brightness = std.math.clamp(sky.brightness(k), AIR_DARKEST, 1),
            .amount = self.strengths.atmosphere,
            .reflections = reflections,
            .beams = self.active_beams,
        });
        rl.drawRectangle(0, 0, screen.x, screen.y, rl.Color.white);
        rl.endShaderMode();
        rl.endBlendMode();
    }
};

comptime {
    for (std.meta.fields(Cinema.Strengths)) |f| {
        if (!@hasField(Options, f.name)) @compileError("Cinema.Strengths." ++ f.name ++ " names no Options effect");
    }
}

fn setField(p: anytype, field: rl.Texture2D, visibility: rl.Texture2D, view: shaders.MapView) void {
    rl.setShaderValueTexture(p.shader, p.field, field);
    rl.setShaderValueTexture(p.shader, p.visibility, visibility);
    shaders.setMapView(p, view);
}

const drawTarget = raster.drawTarget;

fn unitByte(v: f32) u8 {
    return @intFromFloat(std.math.clamp(v, 0, 1) * 255);
}

fn copyTarget(t: rl.Texture2D) void {
    raster.beginReplace();
    drawTarget(t);
    rl.endBlendMode();
}

const FOCUS_FS = shaders.FS_HEAD ++ look.FOCUS_TAPS ++
    \\void main() {
    \\    vec4 c = focused();
    \\    finalColor = vec4(unpremultiplied(c), c.a) * fragColor;
    \\}
;

const FIELD_FS = shaders.MAP_VIEW_FS ++ FIELD_DEFINES ++
    \\uniform sampler2D field;
    \\uniform sampler2D visibility;
    \\vec4 fieldAt(vec2 p) {
    \\    return mapTexel(field, p);
    \\}
    \\float liveAt(vec2 p) {
    \\    return mapAlpha(visibility, p, 0.0);
    \\}
    \\
;

const BLOOM_FS = shaders.FS_HEAD ++ FIELD_FS ++ shaders.glslConsts(.{ .BLOOM_GAIN = BLOOM_GAIN }) ++
    \\uniform sampler2D glints;
    \\uniform vec2 direction;
    \\uniform int extract;
    \\uniform float amount;
    \\vec3 sampleLight(vec2 uv) {
    \\    uv = insetUv(uv, screen);
    \\    vec3 c = texture(texture0, uv).rgb;
    \\    if (extract == 0) return c;
    \\    vec2 p = cellAtPixel(targetPixel(uv));
    \\    vec4 f = fieldAt(p);
    \\    float high = max(c.r, max(c.g, c.b));
    \\    float lum = dot(c, LUMA);
    \\    float core = max(smoothstep(0.80, 1.0, lum), smoothstep(0.92, 1.0, high) * 0.65);
    \\    vec3 glint = texture(glints, p / CELLS).rgb;
    \\    float water = f.WATER * smoothstep(0.015, 0.12, max(glint.r, max(glint.g, glint.b)));
    \\    return c * core * max(water, f.EMISSIVE) * liveAt(p);
    \\}
    \\void main() {
    \\    vec2 d = direction / screen;
    \\    vec3 sum = sampleLight(fragTexCoord) * 0.227027;
    \\    sum += (sampleLight(fragTexCoord + d) + sampleLight(fragTexCoord - d)) * 0.194595;
    \\    sum += (sampleLight(fragTexCoord + d * 2.0) + sampleLight(fragTexCoord - d * 2.0)) * 0.121622;
    \\    sum += (sampleLight(fragTexCoord + d * 3.0) + sampleLight(fragTexCoord - d * 3.0)) * 0.054054;
    \\    sum += (sampleLight(fragTexCoord + d * 4.0) + sampleLight(fragTexCoord - d * 4.0)) * 0.016216;
    \\    vec2 p = cellAtFrag();
    \\    float gain = extract != 0 ? 1.0 : BLOOM_GAIN * amount * liveAt(p);
    \\    finalColor = vec4(sum * gain, 1.0);
    \\}
;

const GRADE_FS = shaders.FS_HEAD ++ shaders.MAP_VIEW_FS ++ shaders.glslConsts(.{ .MEMORY_GREY = MEMORY_GREY, .MEMORY_BRIGHTNESS = MEMORY_BRIGHTNESS }) ++
    \\uniform sampler2D visibility;
    \\void main() {
    \\    vec4 c = texture(texture0, fragTexCoord);
    \\    vec2 p = cellAtFrag();
    \\    float live = mapAlpha(visibility, p, 1.0);
    \\    vec3 remembered = saturated(c.rgb, 1.0 - MEMORY_GREY) * MEMORY_BRIGHTNESS;
    \\    finalColor = vec4(mix(remembered, c.rgb, live), c.a);
    \\}
;

const AIR_FS = shaders.FS_HEAD ++ FIELD_FS ++ light_visibility.SIGHT_FS ++ shaders.glslConsts(.{
    .PIXELS = @as(f32, @floatFromInt(look.SPRITE_PX)),
    .SHAFT_NEAR = SHAFT_NEAR,
    .SHAFT_SLANT = SHAFT_SLANT,
    .SHAFT_SPACING = SHAFT_SPACING,
    .SHAFT_REACH = SHAFT_REACH,
    .SHAFT_WIDTH = SHAFT_WIDTH,
    .SHAFT_REFLECT = SHAFT_REFLECT,
    .SHAFT_SWAY = SHAFT_SWAY,
    .SHAFT_POOL_WIDTH = SHAFT_POOL_WIDTH,
    .SHAFT_POOL_DEPTH = SHAFT_POOL_DEPTH,
    .SHAFT_POOL_MAX = SHAFT_POOL_MAX,
    .SHAFT_ROWS = SHAFT_ROWS,
    .SHAFT_REFLECT_ROWS = SHAFT_REFLECT_ROWS,
    .SHAFT_POOL_ROWS = SHAFT_POOL_ROWS,
    .SHAFT_COLS = SHAFT_COLS,
    .SHAFT_REFLECT_COLS = SHAFT_REFLECT_COLS,
    .MIST_TINT = look.MIST_TINT,
    .SHAFT_TINT = look.SHAFT_TINT,
    .MIST_GAIN = MIST_GAIN,
    .SHAFT_GAIN = SHAFT_GAIN,
    .DUST_GAIN = DUST_GAIN,
    .DUST_SMALL_GAIN = DUST_SMALL_GAIN,
    .DUST_EMPTY = DUST_EMPTY,
    .DUST_LARGE = DUST_LARGE,
    .DUST_SIZE = DUST_SIZE,
    .LEAF_SIZE = LEAF_SIZE,
    .LEAF_EMPTY = LEAF_EMPTY,
    .LEAF_FALL = LEAF_FALL,
    .LEAF_SWING = LEAF_SWING,
    .LEAF_SWAY = LEAF_SWAY,
    .LEAF_LIFT = LEAF_LIFT,
    .LEAF_TILT = LEAF_TILT,
    .LEAF_LENGTH = LEAF_LENGTH,
    .LEAF_WIDTH = LEAF_WIDTH,
    .LEAF_STEM = LEAF_STEM,
    .LEAF_GAIN = LEAF_GAIN,
    .LEAF_SHADE = LEAF_SHADE,
    .LEAF_DIM = LEAF_DIM,
    .LEAF_GOLD = look.LEAF_GOLD,
    .LEAF_GREEN = look.LEAF_GREEN,
    .LEAF_RUST = look.LEAF_RUST,
    .SHAFT_EMPTY = SHAFT_EMPTY,
    .SHAFT_REFLECT_GAIN = SHAFT_REFLECT_GAIN,
    .SHAFT_POOL_GAIN = SHAFT_POOL_GAIN,
    .AIR_DRIFT = AIR_DRIFT,
    .WEATHER_MIST_WATER = WEATHER_MIST_WATER,
    .WEATHER_MIST_LAND = WEATHER_MIST_LAND,
}) ++
    \\uniform float time;
    \\uniform float sunlight;
    \\uniform float shaftlight;
    \\uniform float brightness;
    \\uniform int reflections;
    \\uniform int beams;
    \\uniform sampler2D weather;
    \\uniform sampler2D sight;
    \\uniform float amount;
    \\
++ shaders.SIN_HASH_FS ++ shaders.VALUE_NOISE_FS ++
    \\vec4 softField(vec2 p) {
    \\    vec2 i = floor(p - 0.5), f = smoothstep(vec2(0.0), vec2(1.0), fract(p - 0.5));
    \\    return mapBilerp(field, i, f);
    \\}
    \\float treesAt(vec2 p) {
    \\    return max(max(fieldAt(p + vec2(SHAFT_NEAR, 0.0)).CROWN, fieldAt(p - vec2(SHAFT_NEAR, 0.0)).CROWN),
    \\               max(fieldAt(p + vec2(0.0, SHAFT_NEAR)).CROWN, fieldAt(p - vec2(0.0, SHAFT_NEAR)).CROWN));
    \\}
    \\float canopyAt(vec2 p) {
    \\    return max(fieldAt(p).CROWN, treesAt(p));
    \\}
    \\vec2 artPixel(vec2 p) {
    \\    return (floor(p * PIXELS) + 0.5) / PIXELS;
    \\}
    \\float lifeFade(float age, float rise, float fall) {
    \\    return smoothstep(0.0, rise, age) * (1.0 - smoothstep(fall, 1.0, age));
    \\}
    \\vec3 clearingLight(vec2 p, bool reflected) {
    \\    vec2 slanted = vec2(p.x + p.y * SHAFT_SLANT, p.y);
    \\    vec2 spacing = SHAFT_SPACING;
    \\    vec2 patch = floor(slanted / spacing);
    \\    vec3 light = vec3(0.0);
    \\    for (int y = -SHAFT_REFLECT_ROWS; y <= SHAFT_ROWS; ++y) {
    \\        if ((reflected && y > 0) || (!reflected && y < -SHAFT_POOL_ROWS)) continue;
    \\        for (int x = -SHAFT_REFLECT_COLS; x <= SHAFT_COLS; ++x) {
    \\            if (!reflected && x < -SHAFT_COLS) continue;
    \\            vec2 id = patch + vec2(float(x), float(y));
    \\            float seed = hash(id + 71.0);
    \\            if (seed < SHAFT_EMPTY) continue;
    \\            vec2 base = (id + vec2(0.15 + seed * 0.7, 0.15 + hash(id + 29.0) * 0.8)) * spacing;
    \\            float height = base.y - slanted.y;
    \\            float reach = mix(SHAFT_REACH.x, SHAFT_REACH.y, hash(id + 13.0));
    \\            float side = slanted.x - base.x;
    \\            if (reflected) {
    \\                height = -height;
    \\                side -= height * (2.0 * SHAFT_SLANT);
    \\                reach *= SHAFT_REFLECT;
    \\            }
    \\            float width = mix(SHAFT_WIDTH.x, SHAFT_WIDTH.y, pow(hash(id + 47.0), 1.4));
    \\            float sway = sin(time * 0.19 + seed * 31.0 + height * 0.28) * SHAFT_SWAY;
    \\            side += sway * clamp(height / reach, 0.0, 1.0);
    \\            if (height < -SHAFT_POOL_MAX || height > reach || abs(side) > width * SHAFT_POOL_WIDTH + SHAFT_POOL_MAX * SHAFT_SLANT) continue;
    \\            vec2 ground = vec2(base.x - base.y * SHAFT_SLANT, base.y);
    \\            if (!insideMap(ground)) continue;
    \\            vec4 floorField = fieldAt(ground);
    \\            float weatherBeam = cellTexel(weather, ground).BEAM;
    \\            float clearing = treesAt(ground) * (1.0 - floorField.CROWN) * (1.0 - floorField.WATER) * weatherBeam;
    \\            float fade = smoothstep(0.0, 0.85 + hash(id + 91.0) * 0.65, height) * pow(max(0.0, 1.0 - height / reach), 1.1);
    \\            float ray = 1.0 - step(width, abs(side));
    \\            float pulse = 0.97 + 0.03 * sin(time * 0.23 + seed * 43.0);
    \\            float gain = (0.38 + hash(id + 103.0) * 0.80) * pulse;
    \\            light.x += clearing * fade * ray * gain;
    \\            light.y = max(light.y, clearing * fade);
    \\            if (!reflected) {
    \\                vec2 pool = vec2((p.x - ground.x) / (width * SHAFT_POOL_WIDTH), (p.y - ground.y) / (SHAFT_POOL_DEPTH.x + width * SHAFT_POOL_DEPTH.y));
    \\                float landing = max(0.0, 1.0 - dot(pool, pool));
    \\                light.z += clearing * landing * landing * gain * SHAFT_POOL_GAIN;
    \\            }
    \\        }
    \\    }
    \\    return light;
    \\}
    \\void main() {
    \\    vec2 p = cellAtFrag();
    \\    float live = min(liveAt(p), exactSight(sight, p));
    \\    if (live < CLEAR_A) { finalColor = vec4(0.0); return; }
    \\    vec4 weatherCell = cellTexel(weather, p);
    \\    if (weatherCell.SEEN < 0.5) { finalColor = vec4(0.0); return; }
    \\    vec4 f = softField(p);
    \\    float weather_mist = weatherCell.MIST;
    \\    float mist = f.WATER * (0.35 + 0.65 * noise(p * vec2(0.7, 2.2) + vec2(time * AIR_DRIFT, time * 0.012)));
    \\    mist *= MIST_GAIN * (1.0 + weather_mist * WEATHER_MIST_WATER);
    \\    mist += weather_mist * WEATHER_MIST_LAND * (0.4 + 0.6 * noise(p * vec2(0.35, 0.9) + vec2(time * AIR_DRIFT * 1.6, time * 0.008)));
    \\    mist *= brightness;
    \\    float shafts = 0.0, dust = 0.0, leaf = 0.0;
    \\    vec3 leafTint = vec3(0.0);
    \\    if (beams != 0 && sunlight > 0.0) {
    \\        vec2 pixel = artPixel(p);
    \\        vec3 clearing = clearingLight(pixel, false);
    \\        shafts = (clearing.x * (1.0 - f.CROWN * 0.45) + clearing.z * (1.0 - fieldAt(p).CROWN) * (1.0 - fieldAt(p).WATER)) * shaftlight * SHAFT_GAIN;
    \\        if (reflections != 0 && fieldAt(p).WATER > 0.5) {
    \\            vec2 waterPixel = pixel;
    \\            waterPixel.x += floor(sin(pixel.y * 23.0 + time * 1.2) * 4.0) / PIXELS;
    \\            float ripple = 0.65 + 0.35 * sin(pixel.y * 38.0 - time * 1.6);
    \\            shafts += clearingLight(waterPixel, true).x * shaftlight * SHAFT_GAIN * SHAFT_REFLECT_GAIN * ripple;
    \\        }
    \\        vec2 dustSize = DUST_SIZE;
    \\        vec2 dustCell = floor(pixel / dustSize);
    \\        float seed = hash(dustCell);
    \\        float age = fract(time * (0.055 + seed * 0.035) + hash(dustCell + 19.0));
    \\        vec2 dotAt = (dustCell + vec2(0.2 + seed * 0.6, 1.0 - age)) * dustSize;
    \\        dotAt.x += sin(time * 0.65 + seed * 20.0) * 0.055;
    \\        dotAt = artPixel(dotAt);
    \\        vec2 delta = abs(pixel - dotAt);
    \\        bool large = seed > DUST_LARGE;
    \\        dust = (1.0 - step((large ? 1.5 : 0.5) / PIXELS, max(delta.x, delta.y))) * step(DUST_EMPTY, seed);
    \\        dust *= large ? 1.0 : DUST_SMALL_GAIN;
    \\        dust *= max(canopyAt(dotAt) * 0.65 * weatherCell.BEAM, clearing.y) * sunlight * DUST_GAIN;
    \\        dust *= lifeFade(age, 0.12, 0.75);
    \\        vec2 leafSize = LEAF_SIZE;
    \\        vec2 leafCell = floor(pixel / leafSize);
    \\        if (hash(leafCell + 53.0) >= LEAF_EMPTY) {
    \\            float leafAge = fract(time * mix(LEAF_FALL.x, LEAF_FALL.y, hash(leafCell + 61.0)) + hash(leafCell + 67.0));
    \\            float sway = sin(time * mix(LEAF_SWING.x, LEAF_SWING.y, hash(leafCell + 73.0)) + hash(leafCell + 59.0) * 40.0);
    \\            vec2 leafAt = leafCell * leafSize + vec2(leafSize.x * (0.3 + 0.4 * hash(leafCell + 79.0)) + sway * LEAF_SWAY,
    \\                LEAF_LIFT + 0.1 + leafAge * (leafSize.y - LEAF_LIFT - 0.2) - LEAF_LIFT * sway * sway);
    \\            leafAt = artPixel(leafAt);
    \\            vec2 d = (pixel - leafAt) * PIXELS;
    \\            float turn = -LEAF_TILT * sway;
    \\            float tc = cos(turn), ts = sin(turn);
    \\            float u = (d.x * tc + d.y * ts) * (hash(leafCell + 83.0) < 0.5 ? -1.0 : 1.0);
    \\            float v = d.y * tc - d.x * ts;
    \\            float blade = step(abs(u), LEAF_LENGTH) * step(-0.5 - LEAF_WIDTH * (1.0 - u * u / (LEAF_LENGTH * LEAF_LENGTH)), v) * step(v, 0.5);
    \\            float stem = step(-LEAF_LENGTH - 1.0, u) * (1.0 - step(-LEAF_LENGTH, u)) * step(abs(v), 0.5);
    \\            float shape = max(blade, stem * LEAF_STEM);
    \\            if (shape > 0.0) {
    \\                float hue = hash(leafCell + 89.0);
    \\                leafTint = mix(LEAF_GOLD, hue < 0.5 ? LEAF_GREEN : LEAF_RUST, fract(hue * 2.0));
    \\                float shine = max(canopyAt(leafAt) * LEAF_SHADE * weatherCell.BEAM * sunlight, min(clearing.x, 1.0) * shaftlight);
    \\                float bright = mix(LEAF_DIM, 1.0, hash(leafCell + 97.0)) * (0.75 + 0.25 * sway * sway);
    \\                float fade = lifeFade(leafAge, 0.18, 0.65);
    \\                leaf = shape * shine * bright * fade * LEAF_GAIN;
    \\            }
    \\        }
    \\    }
    \\    float alpha = (mist + shafts + dust + leaf) * live * amount;
    \\    vec3 tint = (MIST_TINT * mist + SHAFT_TINT * (shafts + dust) + leafTint * leaf) / max(mist + shafts + dust + leaf, 0.00001);
    \\    finalColor = vec4(tint * alpha, 0.0);
    \\}
;

test "cinema focus preserves nearby scenery and every gameplay tile" {
    const h = [2]f32{ 20.5, 20.5 };
    var focused: usize = 0;
    for (std.enums.values(grid.Tile)) |t| {
        try std.testing.expectEqual(@as(f32, 0), focusStrength(t, .{ 20.5, 23.5 }, h));
        const far = focusStrength(t, .{ 20.5, 30.5 }, h);
        if (far > 0) {
            focused += 1;
            try std.testing.expect(look.SOFTENED.contains(t));
            try std.testing.expect(far <= FOCUS_MAX);
        }
    }
    try std.testing.expectEqual(look.SOFTENED.count(), focused);
}

test "cinema emissive bounds preserve fractional lights and visible map edges" {
    const width: f32 = @floatFromInt(grid.W);
    const height: f32 = @floatFromInt(grid.H);
    const offsets = [_]f32{ -1.5, -0.01, 0, 0.5, 1.49, 1.5, 20.01, 20.5, height - 0.5, height + 0.01, width - 0.5, width + 0.01 };
    for (offsets) |x| {
        for (offsets) |y| {
            var pixels: [grid.CELLS]rl.Color = undefined;
            for (&pixels, 0..) |*pixel, i| {
                @field(pixel, FIELD.lit) = if (i % 5 == 0) 0 else 255;
                @field(pixel, FIELD.water) = 97;
                @field(pixel, FIELD.emissive) = 0;
                @field(pixel, FIELD.crown) = 39;
            }
            const marked = markEmissive(&pixels, .{ x, y });
            var expected_count: usize = 0;
            for (pixels, 0..) |pixel, i| {
                const expected = i % 5 != 0 and light.offMiddle(grid.Level.of(i), .{ x, y }) < EMISSIVE_REACH;
                try std.testing.expectEqual(@as(u8, if (expected) 255 else 0), @field(pixel, FIELD.emissive));
                try std.testing.expectEqual(@as(u8, if (i % 5 == 0) 0 else 255), @field(pixel, FIELD.lit));
                try std.testing.expectEqual(@as(u8, 97), @field(pixel, FIELD.water));
                try std.testing.expectEqual(@as(u8, 39), @field(pixel, FIELD.crown));
                expected_count += @intFromBool(expected);
            }
            try std.testing.expectEqual(expected_count > 0, marked);
        }
    }
}
