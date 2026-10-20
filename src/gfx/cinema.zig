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

    pub const off: Options = .{
        .composed_lighting = false,
        .bloom = false,
        .atmosphere = false,
        .depth_of_field = false,
    };
};

const Focus = struct { shader: rl.Shader, texel: i32, strength: i32 };
const Bloom = struct { shader: rl.Shader, field: i32, visibility: i32, glints: i32, origin: i32, cell: i32, screen: i32, direction: i32, extract: i32 };
const Air = struct { shader: rl.Shader, field: i32, visibility: i32, origin: i32, cell: i32, screen: i32, time: i32, daylight: i32, brightness: i32, direction: i32 };

pub fn focusStrength(t: grid.Tile, at: [2]f32, hero: ?[2]f32) f32 {
    if (!look.canopy(t) and t != .tiny_shrub and t != .tall_grass and t != .shrooms) return 0;
    const h = hero orelse return 0;
    return 0.24 * mathx.smoothstep(3.5, 7.5, @abs(at[1] - h[1]));
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
        var cells = view.grown(4).cells();
        while (cells.next()) |p| {
            if (!lv.isLit(p)) continue;
            const t = lv.at(p);
            const at = mathx.centre(p);
            var emissive = false;
            for (flames) |f| {
                if (f.lit > look.CLEAR_A and mathx.len(at[0] - f.at[0], at[1] - f.at[1]) < 1.5) {
                    emissive = true;
                    break;
                }
            }
            if (!emissive) for (l.effects[0..l.effect_n]) |e| {
                if (mathx.len(at[0] - e.source.at[0], at[1] - (e.source.at[1] - e.source.at[2])) < 1.5) {
                    emissive = true;
                    break;
                }
            };
            pixels[grid.Level.idx(p)] = .{
                .r = 255,
                .g = if (look.reflects(t)) 255 else 0,
                .b = if (emissive) 255 else 0,
                .a = if (look.canopy(t)) 255 else 0,
            };
            self.active_bloom = self.active_bloom or look.reflects(t) or emissive;
        }
        rl.updateTexture(tex, &pixels);
    }

    pub fn beginScene(self: *Cinema, screen: mathx.P, outer: u32) bool {
        if (!self.options.bloom or !self.active_bloom or self.bloom == null or self.field == null) return false;
        return look.beginTarget(&self.scene, screen, outer, look.BG);
    }

    pub fn endScene(self: *Cinema, outer: u32, origin: [2]f32, cell: f32, l: *light.Light) void {
        rl.gl.rlDrawRenderBatchActive();
        rl.gl.rlEnableFramebuffer(outer);
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
            rl.gl.rlEnableFramebuffer(outer);
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
        look.setUniform(b.shader, b.origin, origin);
        look.setUniform(b.shader, b.cell, cell);
        look.setUniform(b.shader, b.screen, [2]f32{ @floatFromInt(scene.width), @floatFromInt(scene.height) });
        look.setUniform(b.shader, b.direction, direction);
        look.setUniform(b.shader, b.extract, extract);
    }

    pub fn beginFocus(self: *Cinema, t: grid.Tile, tex: rl.Texture2D, at: [2]f32, hero: ?[2]f32) bool {
        if (!self.options.depth_of_field) return false;
        const strength = focusStrength(t, at, hero);
        if (strength <= 0) return false;
        const f = self.focus orelse return false;
        rl.beginShaderMode(f.shader);
        look.setUniform(f.shader, f.texel, [2]f32{ 1 / @as(f32, @floatFromInt(tex.width)), 1 / @as(f32, @floatFromInt(tex.height)) });
        look.setUniform(f.shader, f.strength, strength);
        return true;
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
        look.setUniform(a.shader, a.origin, origin);
        look.setUniform(a.shader, a.cell, cell);
        look.setUniform(a.shader, a.screen, [2]f32{ @floatFromInt(screen.x), @floatFromInt(screen.y) });
        look.setUniform(a.shader, a.time, l.t.at());
        look.setUniform(a.shader, a.daylight, (1 - k.moon) * std.math.clamp(sky.luma(k.key), 0, 1));
        look.setUniform(a.shader, a.brightness, std.math.clamp(sky.brightness(k), 0.06, 1));
        look.setUniform(a.shader, a.direction, k.across());
        rl.drawRectangle(0, 0, screen.x, screen.y, rl.Color.white);
        rl.endShaderMode();
    }
};

fn drawTarget(t: rl.Texture2D) void {
    rl.drawTextureRec(t, look.rect(0, 0, t.width, -t.height), .{ .x = 0, .y = 0 }, rl.Color.white);
}

fn copyTarget(t: rl.Texture2D) void {
    rl.gl.rlSetBlendFactors(rl.gl.rl_one, rl.gl.rl_zero, rl.gl.rl_func_add);
    rl.beginBlendMode(.custom);
    drawTarget(t);
    rl.endBlendMode();
}

const FOCUS_FS = look.FS_HEAD ++
    \\uniform vec2 texel;
    \\uniform float strength;
    \\vec4 tap(vec2 offset) {
    \\    vec4 c = texture(texture0, clamp(fragTexCoord + offset * texel, texel * 0.5, vec2(1.0) - texel * 0.5));
    \\    return vec4(c.rgb * c.a, c.a);
    \\}
    \\void main() {
    \\    vec4 base = tap(vec2(0.0));
    \\    vec4 blur = base * 0.4;
    \\    blur += (tap(vec2(1.0, 0.0)) + tap(vec2(-1.0, 0.0)) + tap(vec2(0.0, 1.0)) + tap(vec2(0.0, -1.0))) * 0.15;
    \\    vec4 c = mix(base, blur, strength);
    \\    finalColor = vec4(c.rgb / max(c.a, 0.0001), c.a) * fragColor;
    \\}
;

const FIELD_FS =
    \\uniform sampler2D field;
    \\uniform sampler2D visibility;
    \\uniform vec2 origin;
    \\uniform float cell;
    \\uniform vec2 screen;
    \\vec4 fieldAt(vec2 p) {
    \\    if (any(lessThan(p, vec2(0.0))) || any(greaterThanEqual(p, CELLS))) return vec4(0.0);
    \\    return texture(field, (floor(p) + 0.5) / CELLS);
    \\}
    \\float liveAt(vec2 p) {
    \\    return fieldAt(p).r * texture(visibility, p / CELLS).a;
    \\}
    \\
;

const BLOOM_FS = look.FS_HEAD ++ FIELD_FS ++
    \\uniform sampler2D glints;
    \\uniform vec2 direction;
    \\uniform int extract;
    \\vec3 sampleLight(vec2 uv) {
    \\    vec3 c = texture(texture0, uv).rgb;
    \\    if (extract == 0) return c;
    \\    vec2 p = (vec2(uv.x, 1.0 - uv.y) * screen - origin) / cell;
    \\    vec4 f = fieldAt(p);
    \\    float high = max(c.r, max(c.g, c.b));
    \\    float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
    \\    float core = max(smoothstep(0.80, 1.0, lum), smoothstep(0.92, 1.0, high) * 0.65);
    \\    vec3 glint = texture(glints, p / CELLS).rgb;
    \\    float water = f.g * smoothstep(0.015, 0.12, max(glint.r, max(glint.g, glint.b)));
    \\    return c * core * max(water, f.b) * liveAt(p);
    \\}
    \\void main() {
    \\    vec2 d = direction / screen;
    \\    vec3 sum = sampleLight(fragTexCoord) * 0.227027;
    \\    sum += (sampleLight(fragTexCoord + d) + sampleLight(fragTexCoord - d)) * 0.194595;
    \\    sum += (sampleLight(fragTexCoord + d * 2.0) + sampleLight(fragTexCoord - d * 2.0)) * 0.121622;
    \\    sum += (sampleLight(fragTexCoord + d * 3.0) + sampleLight(fragTexCoord - d * 3.0)) * 0.054054;
    \\    sum += (sampleLight(fragTexCoord + d * 4.0) + sampleLight(fragTexCoord - d * 4.0)) * 0.016216;
    \\    vec2 p = (vec2(gl_FragCoord.x, screen.y - gl_FragCoord.y) - origin) / cell;
    \\    float gain = extract != 0 ? 1.0 : 0.22 * liveAt(p);
    \\    finalColor = vec4(sum * gain, 1.0);
    \\}
;

const AIR_FS = look.FS_HEAD ++ FIELD_FS ++
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
    \\    vec2 p = (vec2(gl_FragCoord.x, screen.y - gl_FragCoord.y) - origin) / cell;
    \\    float live = liveAt(p);
    \\    if (live < CLEAR_A) { finalColor = vec4(0.0); return; }
    \\    vec4 f = softField(p);
    \\    float mist = f.g * (0.35 + 0.65 * noise(p * vec2(0.7, 2.2) + vec2(time * 0.025, time * 0.012)));
    \\    mist *= 0.065 * brightness;
    \\    float trees = (softField(p + direction * 1.1).a + softField(p + direction * 2.3).a) * 0.5;
    \\    float band = dot(p, vec2(-direction.y, direction.x));
    \\    float shafts = pow(max(0.0, sin(band * 4.7 + noise(p * 0.3) * 2.0)), 10.0);
    \\    shafts *= trees * (1.0 - f.a) * daylight * 0.035;
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
            try std.testing.expect(t == .shrub or t == .swamp_tree or t == .tiny_shrub or t == .tall_grass or t == .shrooms);
            try std.testing.expect(far <= 0.24);
        }
    }
    try std.testing.expectEqual(@as(usize, 5), focused);
    std.debug.print("cinema focus: {d} scenery kinds soften only beyond the sharp 7-cell band; ground and interactables stay sharp\n", .{focused});
}
