const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const raster = @import("raster.zig");
const shaders = @import("shaders.zig");

pub const Options = struct {
    lens_blur: f32 = 0.10,
    perspective: f32 = 0.50,
    vignette: f32 = 0.85,
    saturation: f32 = 1,
    warmth: f32 = 0.10,
    film_grain: f32 = 0,
    scanlines: f32 = 0.60,
    chromatic_aberration: f32 = 0.30,
    sepia: f32 = 0.05,

    pub const neutral: Options = .{ .lens_blur = 0, .perspective = 0, .vignette = 0, .warmth = 0, .scanlines = 0, .chromatic_aberration = 0, .sepia = 0 };

    pub fn active(self: Options) bool {
        inline for (std.meta.fields(Options)) |f| {
            if (@field(self, f.name) != @field(neutral, f.name)) return true;
        }
        return false;
    }
};

const PERSPECTIVE: f32 = 0.10;
const Program = struct { shader: rl.Shader, screen: i32, direction: i32, lens_blur: i32, perspective: i32, vignette: i32, saturation: i32, warmth: i32, film_grain: i32, scanlines: i32, chromatic_aberration: i32, sepia: i32, finish: i32 };

pub const Lens = struct {
    options: Options = .{},
    program: ?Program = null,
    scene: ?rl.RenderTexture2D = null,
    spread: ?rl.RenderTexture2D = null,

    pub fn load(self: *Lens) void {
        self.program = shaders.program(Program, FS);
    }

    pub fn unload(self: *Lens) void {
        raster.unloadAll(self);
    }

    pub fn begin(self: *Lens, screen: mathx.P, outer: u32) bool {
        if (!self.options.active() or self.program == null) return false;
        return raster.beginTarget(&self.scene, screen, outer, rl.Color.black);
    }

    pub fn end(self: *Lens, outer: u32) void {
        raster.endTarget(outer);
        const scene = self.scene.?.texture;
        rl.setTextureFilter(scene, .bilinear);
        var source = scene;
        if (self.options.lens_blur > 0 and raster.beginTarget(&self.spread, .{ .x = scene.width, .y = scene.height }, outer, rl.Color.black)) {
            self.draw(scene, .{ 1, 0 }, false);
            raster.endTarget(outer);
            source = self.spread.?.texture;
            rl.setTextureFilter(source, .bilinear);
        }
        self.draw(source, .{ 0, 1 }, true);
    }

    fn draw(self: *const Lens, source: rl.Texture2D, direction: [2]f32, finish: bool) void {
        const p = self.program.?;
        raster.beginReplace();
        rl.beginShaderMode(p.shader);
        shaders.setUniform(p.shader, p.screen, raster.sizeOf(source));
        shaders.setUniform(p.shader, p.direction, direction);
        inline for (std.meta.fields(Options)) |f| shaders.setUniform(p.shader, @field(p, f.name), @field(self.options, f.name));
        shaders.setUniform(p.shader, p.finish, finish);
        raster.drawTarget(source);
        rl.endShaderMode();
        rl.endBlendMode();
    }

    pub fn sourcePoint(self: *const Lens, point: mathx.P, screen: mathx.P) mathx.P {
        if (self.options.perspective == 0 or self.program == null or self.scene == null) return point;
        return perspectivePoint(point, screen, self.options.perspective);
    }
};

fn perspectivePoint(point: mathx.P, screen: mathx.P, strength: f32) mathx.P {
    const width: f32 = @floatFromInt(screen.x);
    const height: f32 = @floatFromInt(screen.y);
    const x: f32 = @floatFromInt(point.x);
    const y: f32 = @floatFromInt(point.y);
    return .{ .x = @intFromFloat(@floor((x + 0.5 - width * 0.5) / (1 + PERSPECTIVE * strength * (y + 0.5) / height) + width * 0.5)), .y = point.y };
}

const FS = shaders.FS_HEAD ++ shaders.glslConsts(.{ .PERSPECTIVE = PERSPECTIVE }) ++
    \\uniform vec2 screen;
    \\uniform vec2 direction;
    \\uniform float lens_blur;
    \\uniform float perspective;
    \\uniform float vignette;
    \\uniform float saturation;
    \\uniform float warmth;
    \\uniform float film_grain;
    \\uniform float scanlines;
    \\uniform float chromatic_aberration;
    \\uniform float sepia;
    \\uniform int finish;
    \\vec4 sampleScene(vec2 uv) {
    \\    return texture(texture0, clamp(uv, 0.5 / screen, vec2(1.0) - 0.5 / screen));
    \\}
    \\void main() {
    \\    vec2 uv = fragTexCoord;
    \\    float y = 1.0 - uv.y;
    \\    if (finish != 0) uv.x = (uv.x - 0.5) / (1.0 + PERSPECTIVE * perspective * y) + 0.5;
    \\    float farBlur = 1.0 - smoothstep(0.03, 0.36, y);
    \\    float nearBlur = smoothstep(0.64, 0.98, y);
    \\    float radius = (farBlur * 4.0 + nearBlur * 1.6) * lens_blur * screen.y / 720.0;
    \\    vec4 c = sampleScene(uv);
    \\    if (radius > 0.01) {
    \\        float spacing = max(1.0, radius / 6.0);
    \\        vec2 d = direction * spacing / screen;
    \\        float total = 1.0;
    \\        int taps = int(ceil(radius * 3.0 / spacing));
    \\        for (int i = 1; i <= 18; ++i) {
    \\            if (i > taps) break;
    \\            float offset = float(i);
    \\            float weight = exp(-0.5 * pow(offset * spacing / radius, 2.0));
    \\            c += (sampleScene(uv + d * offset) + sampleScene(uv - d * offset)) * weight;
    \\            total += 2.0 * weight;
    \\        }
    \\        c /= total;
    \\    }
    \\    if (finish != 0) {
    \\        vec2 edge = (fragTexCoord - 0.5) * 2.0;
    \\        if (chromatic_aberration > 0.0) {
    \\            vec2 shift = edge * dot(edge, edge) * chromatic_aberration * 3.0 / screen;
    \\            c.r = mix(c.r, sampleScene(uv + shift).r, chromatic_aberration);
    \\            c.b = mix(c.b, sampleScene(uv - shift).b, chromatic_aberration);
    \\        }
    \\        float lum = dot(c.rgb, LUMA);
    \\        c.rgb = mix(vec3(lum), c.rgb, saturation);
    \\        c.rgb *= vec3(1.0 + warmth * 0.18, 1.0 + warmth * 0.03, 1.0 - warmth * 0.18);
    \\        vec3 antique = vec3(dot(c.rgb, vec3(0.393, 0.769, 0.189)), dot(c.rgb, vec3(0.349, 0.686, 0.168)), dot(c.rgb, vec3(0.272, 0.534, 0.131)));
    \\        c.rgb = mix(c.rgb, antique, sepia);
    \\        float grain = fract(sin(dot(floor(gl_FragCoord.xy), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    \\        c.rgb *= 1.0 + grain * film_grain * 0.35;
    \\        c.rgb *= 1.0 - scanlines * 0.30 * mod(floor(gl_FragCoord.y), 2.0);
    \\        c.rgb *= 1.0 - vignette * 0.16 * smoothstep(0.35, 1.65, dot(edge, edge));
    \\        c.rgb = clamp(c.rgb, 0.0, 1.0);
    \\    }
    \\    finalColor = c;
    \\}
;

test "perspective pointer mapping matches the projected source at multiple sizes" {
    for ([_]mathx.P{ .{ .x = 1280, .y = 720 }, .{ .x = 1920, .y = 1080 } }) |screen| {
        for ([_]f32{ 0, 0.25, 1, 2 }) |strength| {
            for ([_]i32{ 0, @divTrunc(screen.y, 2), screen.y - 1 }) |y| {
                for ([_]i32{ 0, @divTrunc(screen.x, 2), screen.x - 1 }) |x| {
                    const source = perspectivePoint(.{ .x = x, .y = y }, screen, strength);
                    const scale = 1 + PERSPECTIVE * strength * (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(screen.y));
                    const middle = @as(f32, @floatFromInt(screen.x)) * 0.5;
                    const projected = (@as(f32, @floatFromInt(source.x)) + 0.5 - middle) * scale + middle;
                    try std.testing.expect(@abs(projected - (@as(f32, @floatFromInt(x)) + 0.5)) <= scale);
                    try std.testing.expectEqual(y, source.y);
                    try std.testing.expect(source.x >= 0 and source.x < screen.x);
                }
            }
        }
    }
}
