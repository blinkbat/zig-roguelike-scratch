const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const light = @import("light.zig");
const sky = @import("sky.zig");

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
/// Drawn only over cells in sight now, not remembered ones.
pub const LIVE_ONLY = std.EnumSet(Effect).init(.{ .bloom = true, .atmosphere = true });

const Focus = struct { shader: rl.Shader, texel: i32, strength: i32 };

const Focused = look.Focused;
const Bloom = struct { shader: rl.Shader, field: i32, visibility: i32, glints: i32, origin: i32, cell: i32, screen: i32, direction: i32, extract: i32 };
const Air = struct { shader: rl.Shader, field: i32, visibility: i32, origin: i32, cell: i32, screen: i32, time: i32, daylight: i32, brightness: i32, direction: i32 };

const FOCUS_MAX: f32 = 0.24;
/// Rows from the hero that stay sharp, and from which scenery is softened fully.
const SHARP_ROWS: f32 = 3.5;
const SOFT_ROWS: f32 = 7.5;
/// From a flame or a spell's light, how far its glow blooms.
const EMISSIVE_REACH: f32 = 1.5;
/// The dimmest sky the water mist is still drawn under, as a share of a clear noon.
const AIR_DARKEST: f32 = 0.06;
/// Cells upwind the light shafts look for crowns.
const SHAFT_NEAR: f32 = 1.1;
const SHAFT_FAR: f32 = 2.3;
/// Cells past the view the field covers: the farthest shaft lookup, softened over one more.
const FIELD_MARGIN: i32 = @intFromFloat(@ceil(SHAFT_FAR + 1));

fn focusStrength(t: grid.Tile, at: [2]f32, hero: ?[2]f32) f32 {
    if (!look.SOFTENED.contains(t)) return 0;
    const h = hero orelse return 0;
    return FOCUS_MAX * mathx.smoothstep(SHARP_ROWS, SOFT_ROWS, @abs(at[1] - h[1]));
}

/// The field texture's channel for each fact about a cell: in sight now, water, near an emissive light, under a crown.
const FIELD = .{ .lit = "r", .water = "g", .emissive = "b", .crown = "a" };
const FIELD_DEFINES = std.fmt.comptimePrint("#define LIT {s}\n#define WATER {s}\n#define EMISSIVE {s}\n#define CROWN {s}\n", .{ FIELD.lit, FIELD.water, FIELD.emissive, FIELD.crown });

fn markEmissive(pixels: *[grid.CELLS]rl.Color, at: [2]f32) bool {
    var marked = false;
    var cells = grid.Box.around(mathx.cellOf(at), @intFromFloat(@ceil(EMISSIVE_REACH))).grown(0).cells();
    while (cells.next()) |p| {
        const pixel = &pixels[grid.Level.idx(p)];
        if (@field(pixel, FIELD.lit) == 0) continue;
        const q = mathx.centre(p);
        if (mathx.len(q[0] - at[0], q[1] - at[1]) >= EMISSIVE_REACH) continue;
        @field(pixel, FIELD.emissive) = 255;
        marked = true;
    }
    return marked;
}

pub const Cinema = struct {
    options: Options = .{},
    focus: ?Focus = null,
    bloom: ?Bloom = null,
    air: ?Air = null,
    field: ?rl.Texture2D = null,
    scene: ?rl.RenderTexture2D = null,
    spread: ?rl.RenderTexture2D = null,
    active_bloom: bool = false,

    pub fn load(self: *Cinema) void {
        self.focus = look.program(Focus, FOCUS_FS);
        self.bloom = look.program(Bloom, BLOOM_FS);
        self.air = look.program(Air, AIR_FS);
        self.field = look.canvas(grid.W, grid.H, rl.Color.blank, .point);
    }

    pub fn unload(self: *Cinema) void {
        look.unloadAll(self);
    }

    pub fn prepare(self: *Cinema, lv: *const grid.Level, l: *const light.Light, view: grid.Box, flames: []const light.Flame) void {
        self.active_bloom = false;
        if (!self.options.bloom and !self.options.atmosphere) return;
        const tex = self.field orelse return;
        var pixels: [grid.CELLS]rl.Color = @splat(rl.Color.blank);
        var cells = view.grown(FIELD_MARGIN).cells();
        while (cells.next()) |p| {
            if (!lv.isLit(p)) continue;
            const t = lv.at(p);
            const pixel = &pixels[grid.Level.idx(p)];
            @field(pixel, FIELD.lit) = 255;
            if (look.reflects(t)) @field(pixel, FIELD.water) = 255;
            if (look.crowned(t)) @field(pixel, FIELD.crown) = 255;
            self.active_bloom = self.active_bloom or look.reflects(t);
        }
        for (flames) |f| {
            if (f.live() and markEmissive(&pixels, f.at)) self.active_bloom = true;
        }
        for (l.effects[0..l.effect_n]) |*e| {
            if (markEmissive(&pixels, e.source.drawn())) self.active_bloom = true;
        }
        rl.updateTexture(tex, &pixels);
    }

    pub fn beginScene(self: *Cinema, screen: mathx.P, outer: u32) bool {
        if (!self.options.bloom or !self.active_bloom or self.bloom == null or self.field == null) return false;
        return look.beginTarget(&self.scene, screen, outer, look.FOG);
    }

    pub fn endScene(self: *Cinema, outer: u32, origin: [2]f32, cell: f32, l: *light.Light) void {
        look.endTarget(outer);
        const scene = self.scene.?.texture;
        const size = mathx.P{ .x = scene.width, .y = scene.height };
        const b = self.bloom.?;
        const visibility = l.mapTexture();
        const glints = l.glintTexture();
        if (visibility != null and glints != null and look.beginTarget(&self.spread, size, outer, rl.Color.black)) {
            rl.beginShaderMode(b.shader);
            self.bindBloom(b, origin, cell, visibility.?, glints.?, scene, .{ 2.0, 0 }, 1);
            drawTarget(scene);
            rl.endShaderMode();
            look.endTarget(outer);
            copyTarget(scene);
            rl.beginBlendMode(.additive);
            rl.beginShaderMode(b.shader);
            self.bindBloom(b, origin, cell, visibility.?, glints.?, scene, .{ 0, 2.0 }, 0);
            drawTarget(self.spread.?.texture);
            rl.endShaderMode();
            rl.endBlendMode();
        } else copyTarget(scene);
    }

    fn bindBloom(self: *Cinema, b: Bloom, origin: [2]f32, cell: f32, visibility: rl.Texture2D, glints: rl.Texture2D, scene: rl.Texture2D, direction: [2]f32, extract: i32) void {
        rl.setShaderValueTexture(b.shader, b.field, self.field.?);
        rl.setShaderValueTexture(b.shader, b.visibility, visibility);
        rl.setShaderValueTexture(b.shader, b.glints, glints);
        look.setMapView(b, origin, cell, .{ @floatFromInt(scene.width), @floatFromInt(scene.height) });
        look.setUniform(b.shader, b.direction, direction);
        look.setUniform(b.shader, b.extract, extract);
    }

    pub fn beginFocus(self: *Cinema, t: grid.Tile, tex: rl.Texture2D, at: [2]f32, hero: ?[2]f32) ?Focused {
        if (!self.options.depth_of_field) return null;
        const strength = focusStrength(t, at, hero);
        if (strength <= 0) return null;
        const f = self.focus orelse return null;
        const focused = Focused{ .texel = .{ 1 / @as(f32, @floatFromInt(tex.width)), 1 / @as(f32, @floatFromInt(tex.height)) }, .strength = strength };
        rl.beginShaderMode(f.shader);
        focused.set(f.shader, f.texel, f.strength);
        return focused;
    }

    pub fn drawAir(self: *Cinema, l: *light.Light, origin: [2]f32, cell: f32, screen: mathx.P) void {
        if (!self.options.atmosphere) return;
        const k = l.sky orelse return;
        const a = self.air orelse return;
        const field = self.field orelse return;
        const visibility = l.mapTexture() orelse return;
        rl.beginShaderMode(a.shader);
        rl.setShaderValueTexture(a.shader, a.field, field);
        rl.setShaderValueTexture(a.shader, a.visibility, visibility);
        look.setMapView(a, origin, cell, .{ @floatFromInt(screen.x), @floatFromInt(screen.y) });
        look.setUniform(a.shader, a.time, l.t.at());
        look.setUniform(a.shader, a.daylight, k.sun() * std.math.clamp(sky.luma(k.key), 0, 1));
        look.setUniform(a.shader, a.brightness, std.math.clamp(sky.brightness(k), AIR_DARKEST, 1));
        look.setUniform(a.shader, a.direction, k.across());
        rl.drawRectangle(0, 0, screen.x, screen.y, rl.Color.white);
        rl.endShaderMode();
    }
};

const drawTarget = look.drawTarget;

fn copyTarget(t: rl.Texture2D) void {
    rl.gl.rlSetBlendFactors(rl.gl.rl_one, rl.gl.rl_zero, rl.gl.rl_func_add);
    rl.beginBlendMode(.custom);
    drawTarget(t);
    rl.endBlendMode();
}

const FOCUS_FS = look.FS_HEAD ++ look.FOCUS_TAPS ++
    \\void main() {
    \\    vec4 c = focused();
    \\    finalColor = vec4(c.rgb / max(c.a, 0.0001), c.a) * fragColor;
    \\}
;

const FIELD_FS = look.MAP_VIEW_FS ++ FIELD_DEFINES ++
    \\uniform sampler2D field;
    \\uniform sampler2D visibility;
    \\vec4 fieldAt(vec2 p) {
    \\    if (!insideMap(p)) return vec4(0.0);
    \\    return texture(field, (floor(p) + 0.5) / CELLS);
    \\}
    \\float liveAt(vec2 p) {
    \\    return fieldAt(p).LIT * texture(visibility, p / CELLS).a;
    \\}
    \\
;

const BLOOM_FS = look.FS_HEAD ++ FIELD_FS ++
    \\uniform sampler2D glints;
    \\uniform vec2 direction;
    \\uniform int extract;
    \\vec3 sampleLight(vec2 uv) {
    \\    uv = clamp(uv, 0.5 / screen, vec2(1.0) - 0.5 / screen);
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
    \\    float gain = extract != 0 ? 1.0 : 0.22 * liveAt(p);
    \\    finalColor = vec4(sum * gain, 1.0);
    \\}
;

const AIR_FS = look.FS_HEAD ++ FIELD_FS ++ look.glslConsts(.{ .SHAFT_NEAR = SHAFT_NEAR, .SHAFT_FAR = SHAFT_FAR }) ++
    \\uniform float time;
    \\uniform float daylight;
    \\uniform float brightness;
    \\uniform vec2 direction;
    \\float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    \\float noise(vec2 p) {
    \\    vec2 i = floor(p), f = fract(p);
    \\    f = f * f * (3.0 - 2.0 * f);
    \\    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
    \\}
    \\vec4 softField(vec2 p) {
    \\    vec2 i = floor(p - 0.5), f = smoothstep(vec2(0.0), vec2(1.0), fract(p - 0.5));
    \\    return mix(mix(fieldAt(i), fieldAt(i + vec2(1.0, 0.0)), f.x), mix(fieldAt(i + vec2(0.0, 1.0)), fieldAt(i + vec2(1.0)), f.x), f.y);
    \\}
    \\void main() {
    \\    vec2 p = cellAtFrag();
    \\    float live = liveAt(p);
    \\    if (live < CLEAR_A) { finalColor = vec4(0.0); return; }
    \\    vec4 f = softField(p);
    \\    float mist = f.WATER * (0.35 + 0.65 * noise(p * vec2(0.7, 2.2) + vec2(time * 0.025, time * 0.012)));
    \\    mist *= 0.065 * brightness;
    \\    float trees = (softField(p + direction * SHAFT_NEAR).CROWN + softField(p + direction * SHAFT_FAR).CROWN) * 0.5;
    \\    float band = dot(p, vec2(-direction.y, direction.x));
    \\    float shafts = pow(max(0.0, sin(band * 4.7 + noise(p * 0.3) * 2.0)), 10.0);
    \\    shafts *= trees * (1.0 - f.CROWN) * daylight * 0.035;
    \\    vec2 drift = vec2(time * 0.025, sin(time * 0.18) * 0.06);
    \\    vec2 dustCell = floor(p - drift);
    \\    float seed = hash(dustCell);
    \\    vec2 dotAt = vec2(seed, hash(dustCell + 19.0)) * 0.7 + 0.15;
    \\    float dust = (1.0 - smoothstep(0.008, 0.024, length(fract(p - drift) - dotAt))) * step(0.88, seed);
    \\    dust *= daylight * (0.25 + trees) * 0.20 * (0.6 + 0.4 * sin(time * 0.7 + seed * 20.0));
    \\    float alpha = (mist + shafts + dust) * live;
    \\    vec3 tint = (vec3(0.48, 0.58, 0.68) * mist + vec3(1.0, 0.87, 0.64) * (shafts + dust)) / max(mist + shafts + dust, 0.00001);
    \\    finalColor = vec4(tint, alpha);
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
    std.debug.print("cinema focus: {d} scenery kinds soften only beyond {d} rows of the hero; ground and interactables stay sharp\n", .{ focused, SHARP_ROWS });
}

test "cinema emissive bounds preserve fractional lights and visible map edges" {
    const width: f32 = @floatFromInt(grid.W);
    const height: f32 = @floatFromInt(grid.H);
    const offsets = [_]f32{ -1.5, -0.01, 0, 0.5, 1.49, 1.5, 20.01, 20.5, height - 0.5, height + 0.01, width - 0.5, width + 0.01 };
    var checked: usize = 0;
    for (offsets) |x| {
        for (offsets) |y| {
            var pixels: [grid.CELLS]rl.Color = undefined;
            for (&pixels, 0..) |*pixel, i| {
                pixel.* = .{ .r = if (i % 5 == 0) 0 else 255, .g = 97, .b = 0, .a = 39 };
            }
            const marked = markEmissive(&pixels, .{ x, y });
            var expected_count: usize = 0;
            for (pixels, 0..) |pixel, i| {
                const q = mathx.centre(grid.Level.of(i));
                const expected = i % 5 != 0 and mathx.len(q[0] - x, q[1] - y) < EMISSIVE_REACH;
                try std.testing.expectEqual(@as(u8, if (expected) 255 else 0), pixel.b);
                try std.testing.expectEqual(@as(u8, if (i % 5 == 0) 0 else 255), pixel.r);
                try std.testing.expectEqual(@as(u8, 97), pixel.g);
                try std.testing.expectEqual(@as(u8, 39), pixel.a);
                expected_count += @intFromBool(expected);
                checked += 1;
            }
            try std.testing.expectEqual(expected_count > 0, marked);
        }
    }
    std.debug.print("cinema emissive bounds: {d} cells match full-map distance checks; hidden cells and other channels stay unchanged\n", .{checked});
}
