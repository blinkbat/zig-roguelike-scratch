const rl = @import("raylib");
const ground = @import("ground.zig");
const shaders = @import("shaders.zig");
const light_model = @import("light_model.zig");
const look = @import("look.zig");

pub const WaterShader = struct { shader: rl.Shader, origin: i32, cell: i32, screen: i32, depth: i32, visibility: i32, glints: i32, mirror: i32, memory: i32, mirrored: i32, shimmer: i32, seconds: i32 };
pub const WaterFaceShader = struct { shader: rl.Shader, screen: i32, depth: i32 };

pub const BankCapShader = struct { shader: rl.Shader, land: i32, region: i32, mask_region: i32, offset: i32, solid: i32, textured: i32 };

pub const BANK_CAP_FS = shaders.FS_HEAD ++
    \\uniform sampler2D land;
    \\uniform vec4 region;
    \\uniform vec4 mask_region;
    \\uniform vec2 offset;
    \\uniform vec4 solid;
    \\uniform int textured;
    \\void main() {
    \\    float coverage = texture(texture0, fragTexCoord).a;
    \\    if (coverage < CLEAR_A) discard;
    \\    vec2 uv = fract((fragTexCoord - mask_region.xy) / mask_region.zw + offset);
    \\    vec4 ground = textured != 0 ? texture(land, region.xy + uv * region.zw) : solid;
    \\    finalColor = ground * fragColor;
    \\    finalColor.a *= coverage;
    \\}
;

pub const SceneryShader = struct { shader: rl.Shader, origin: i32, cell: i32, screen: i32, lightmap: i32, fogmap: i32, body: i32, hidden: i32, texel: i32, strength: i32 };

pub const FadeShader = struct { shader: rl.Shader, bounds: i32, minimum: i32 };
pub const SCENERY_FS = shaders.FS_HEAD ++ look.FOCUS_TAPS ++ shaders.MAP_VIEW_FS ++ look.OCCLUSION_FS ++ shaders.glslConsts(.{ .FOG_RGB = look.rgbOf(look.FOG), .OVERBRIGHT = light_model.OVERBRIGHT }) ++
    \\uniform sampler2D lightmap;
    \\uniform sampler2D fogmap;
    \\void main() {
    \\    vec2 p = cellAtFrag();
    \\    if (!insideMap(p)) discard;
    \\    vec2 uv = p / CELLS;
    \\    vec4 art = focused();
    \\    vec3 lit = texture(lightmap, uv).rgb * OVERBRIGHT;
    \\    vec3 fog = FOG_RGB * texture(fogmap, uv).a;
    \\    finalColor = vec4(unpremultiplied(art) * lit + fog, art.a * occlusionAt(p));
    \\}
;

pub const FADE_FS = shaders.FS_HEAD ++
    \\uniform vec2 bounds;
    \\uniform float minimum;
    \\void main() {
    \\    vec4 ink = texture(texture0, fragTexCoord) * fragColor;
    \\    ink.a *= mix(1.0, minimum, smoothstep(bounds.x, bounds.y, gl_FragCoord.y));
    \\    finalColor = ink;
    \\}
;

pub const ShineShader = struct { shader: rl.Shader, sweep: i32 };
pub const SHINE_FS = shaders.FS_HEAD ++ shaders.glslConsts(.{ .SHINE_WIDTH = look.SHINE_WIDTH, .SHINE_SLANT = look.SHINE_SLANT, .SHINE_GAIN = look.SHINE_GAIN }) ++
    \\uniform float sweep;
    \\void main() {
    \\    vec4 tex = texture(texture0, fragTexCoord);
    \\    float along = (fragTexCoord.x + fragTexCoord.y * SHINE_SLANT) / (1.0 + SHINE_SLANT);
    \\    float band = 1.0 - smoothstep(0.0, SHINE_WIDTH, abs(along - sweep));
    \\    finalColor = vec4(fragColor.rgb, tex.a * fragColor.a * band * SHINE_GAIN);
    \\}
;

const WATER_SATURATION: f32 = 0.8;
const MIRROR_DEEP: f32 = 0.42;
const MIRROR_SHALLOW: f32 = 0.28;
const MIRROR_TINT = [3]f32{ 0.8, 0.9, 1.0 };
const WATER_HIGHLIGHT = [2]f32{ 0.62, 0.82 };
const WATER_SHIMMER: f32 = 0.32;
const SHIMMER_DRIFT = [2][2]f32{ .{ 0.26, -0.16 }, .{ -0.21, 0.30 } };
const SHIMMER_SCALE = [2]f32{ 1.9, 3.7 };
const SHIMMER_WEIGHT = [2]f32{ 0.55, 0.45 };
const SHIMMER_OFFSET: f32 = 19.7;
const SHIMMER_SPAN = [2]f32{ 0.25, 0.75 };
const WATER_SCREEN_FADE = [2]f32{ 1.1, 0.45 };
const WATER_SCREEN_FADE_DEEP: f32 = 0.05;
const WATER_FADE_FS = shaders.glslConsts(.{
    .SCREEN_FADE = WATER_SCREEN_FADE,
    .SCREEN_FADE_DEEP = WATER_SCREEN_FADE_DEEP,
    .DEEP = look.WATER_DEEP,
    .SHALLOW = look.WATER_SHALLOW,
}) ++
    \\float waterFade(float depth, float screenHeight) {
    \\    float shallow = smoothstep(DEEP, SHALLOW, depth);
    \\    return mix(SCREEN_FADE.x, mix(SCREEN_FADE_DEEP, SCREEN_FADE.y, shallow), clamp(1.0 - gl_FragCoord.y / screenHeight, 0.0, 1.0));
    \\}
    \\
;
pub const WATER_FACE_FS = shaders.FS_HEAD ++ WATER_FADE_FS ++
    \\uniform vec2 screen;
    \\uniform float depth;
    \\void main() {
    \\    vec4 art = texture(texture0, fragTexCoord) * fragColor;
    \\    finalColor = vec4(clamp(art.rgb * waterFade(depth, screen.y), 0.0, 1.0), art.a);
    \\}
;
pub const WATER_FS = shaders.FS_HEAD ++ WATER_FADE_FS ++ shaders.glslConsts(.{
    .SATURATION = WATER_SATURATION,
    .OVERBRIGHT = light_model.OVERBRIGHT,
    .MIRROR_DEEP = MIRROR_DEEP,
    .MIRROR_SHALLOW = MIRROR_SHALLOW,
    .MIRROR_TINT = MIRROR_TINT,
    .HIGHLIGHT = WATER_HIGHLIGHT,
    .SHIMMER = WATER_SHIMMER,
    .DRIFT_A = SHIMMER_DRIFT[0],
    .DRIFT_B = SHIMMER_DRIFT[1],
    .SWELL_SCALE = SHIMMER_SCALE,
    .SWELL_WEIGHT = SHIMMER_WEIGHT,
    .SWELL_OFFSET = SHIMMER_OFFSET,
    .SWELL_SPAN = SHIMMER_SPAN,
}) ++ shaders.MAP_VIEW_FS ++
    \\uniform float depth;
    \\uniform sampler2D visibility;
    \\uniform sampler2D glints;
    \\uniform sampler2D mirror;
    \\uniform sampler2D memory;
    \\uniform int mirrored;
    \\uniform int shimmer;
    \\uniform float seconds;
    \\
++ shaders.SIN_HASH_FS ++ shaders.VALUE_NOISE_FS ++
    \\float swell(vec2 at) {
    \\    float n = noise(at * SWELL_SCALE.x + DRIFT_A * seconds) * SWELL_WEIGHT.x + noise(at * SWELL_SCALE.y + DRIFT_B * seconds + SWELL_OFFSET) * SWELL_WEIGHT.y;
    \\    return smoothstep(SWELL_SPAN.x, SWELL_SPAN.y, n) * 2.0 - 1.0;
    \\}
    \\void main() {
    \\    vec4 art = texture(texture0, fragTexCoord) * fragColor;
    \\    vec2 at = cellAtFrag();
    \\    vec4 light = texture(visibility, at / CELLS);
    \\    vec4 reflected = vec4(0.0);
    \\    if (mirrored != 0) {
    \\        vec2 uv = gl_FragCoord.xy / screen;
    \\        vec4 remembered = texture(memory, uv);
    \\        remembered.rgb *= light.rgb * OVERBRIGHT;
    \\        reflected = mix(remembered, texture(mirror, uv), light.a);
    \\    }
    \\    float shallow = smoothstep(DEEP, SHALLOW, depth);
    \\    float strength = mix(MIRROR_DEEP, MIRROR_SHALLOW, shallow);
    \\    vec3 shine = reflected.rgb * MIRROR_TINT * strength;
    \\    shine = mix(vec3(dot(shine, LUMA)), shine, SATURATION);
    \\    shine += texture(glints, at / CELLS).rgb * light.a;
    \\    vec3 base = art.rgb * (1.0 - reflected.a * strength);
    \\    if (shimmer != 0) base *= 1.0 + SHIMMER * smoothstep(HIGHLIGHT.x, HIGHLIGHT.y, dot(art.rgb / depth, LUMA)) * swell(at) * light.a;
    \\    float fade = waterFade(depth, screen.y);
    \\    finalColor = vec4(clamp((base + shine / max(light.rgb * OVERBRIGHT, vec3(0.06))) * fade, 0.0, 1.0), art.a);
    \\}
;
