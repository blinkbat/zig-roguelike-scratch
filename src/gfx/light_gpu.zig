const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const look = @import("look.zig");
const raster = @import("raster.zig");
const shaders = @import("shaders.zig");
const sky = @import("sky.zig");
const shadow = @import("shadow.zig");
const light = @import("light_model.zig");
const Rgb = sky.Rgb;
const splat = sky.splat;

const STREAK_PX = [2]i32{ 64, 16 };

const GLOW_PX: i32 = 64;
const MIRROR_HEAD = shaders.FS_HEAD ++
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

const BODY_FS = MIRROR_HEAD ++ shaders.glslConsts(.{ .LIGHTS = light.BODY_LIGHTS, .KNEE = light.KNEE, .FLASH = light.FLASH_RGB }) ++
    \\uniform sampler2D normals;
    \\uniform vec2 size;
    \\uniform float flip;
    \\uniform vec3 ambient;
    \\uniform vec3 emission;
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
    \\    finalColor = vec4(mix(c.rgb * light + sheen + emission, FLASH, flash), c.a) * fragColor;
    \\    finalColor.a *= mirrorFade();
    \\}
;

const POOL_HEAD = shaders.FS_HEAD ++
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

const RECEIVER_FS = shaders.FS_HEAD ++ shaders.MAP_VIEW_FS ++
    \\uniform sampler2D lightmap;
    \\void main() {
    \\    vec2 p = cellAtPixel(targetPixel(fragTexCoord));
    \\    float sight = texture(lightmap, p / CELLS).a * float(insideMap(p));
    \\    vec3 shadow = texture(texture0, fragTexCoord).rgb;
    \\    finalColor = vec4(mix(vec3(1.0), shadow, sight), 1.0);
    \\}
;

const ReceiverShader = struct {
    shader: rl.Shader,
    lightmap: i32,
    origin: i32,
    cell: i32,
    screen: i32,
};

const SHADOW_FS = POOL_HEAD ++ shaders.glslConsts(.{ .TAPS = light.SHADOW_TAPS }) ++
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
    emission: i32,
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

pub const NO_FIGURES: [look.FIGURES]?rl.Texture2D = @splat(null);

pub const Gpu = struct {
    /// `ox, oy` is where the map's top-left corner lands on screen.
    pub fn drawMap(self: *const Gpu, ox: i32, oy: i32, cell: i32) void {
        const tex = self.layers.get(.map) orelse return;
        raster.beginBlend(rl.gl.rl_dst_color, rl.gl.rl_src_color, rl.gl.rl_func_add);
        raster.overFloor(tex, ox, oy, cell);
        rl.endBlendMode();
        if (self.layers.get(.fog)) |fog| {
            rl.beginBlendMode(.additive);
            raster.stretch(fog, raster.floorRect(ox, oy, cell), look.FOG);
            rl.endBlendMode();
        }
    }

    pub fn uploadRows(self: *const Gpu, texels: *const std.EnumArray(light.Layer, [light.TEXELS]rl.Color), rows: [2]i32) void {
        if (self.layers.get(.map) == null) return;
        const from, const to = rows;
        if (to > from) {
            const rect = raster.rect(0, from, light.MAP_W, to - from);
            for (std.enums.values(light.Layer)) |k| {
                if (self.layers.get(k)) |t| rl.updateTextureRec(t, rect, &texels.getPtrConst(k)[@intCast(from * light.MAP_W)]);
            }
        }
    }

    /// `centre` is its middle, cells; `flash` is how far toward `FLASH_RGB` it is drawn.
    pub fn drawBody(self: *const Gpu, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: [2]f32, s: *const light.Shine, flash: f32, fade_bounds: [2]f32, enabled: bool) void {
        const size = raster.sizeOf(tex);
        const w, const h = size;
        const src = raster.rect(0, 0, if (left) -tex.width else tex.width, tex.height);
        const normals = self.art(tex).normals;
        const sh = self.body;
        if (!enabled or sh == null or normals == null) {
            const fading = self.beginMirrorFade(fade_bounds);
            defer if (fading) rl.endShaderMode();
            raster.blit(tex, src, dest, s.drawn(rl.Color.white, flash));
            return;
        }
        var pos: [light.BODY_LIGHTS][3]f32 = undefined;
        var col: [light.BODY_LIGHTS][3]f32 = undefined;
        for (s.lamp[0..s.n], 0..) |l, i| {
            pos[i] = .{ (l.drawn[0] - centre[0]) * w, (l.drawn[1] - centre[1]) * h, light.BODY_LIGHT_Z };
            col[i] = l.colour;
        }
        const flip: f32 = if (left) -1 else 1;
        const ambient: [3]f32 = s.ambient;
        const emission: [3]f32 = s.emission * splat(s.sight);
        const n: i32 = @intCast(s.n);
        const b = sh.?;
        rl.beginShaderMode(b.shader);
        defer rl.endShaderMode();
        shaders.setUniform(b.shader, b.size, size);
        shaders.setUniform(b.shader, b.flip, flip);
        shaders.setUniform(b.shader, b.ambient, ambient);
        shaders.setUniform(b.shader, b.emission, emission);
        shaders.setUniform(b.shader, b.count, n);
        shaders.setUniform(b.shader, b.flash, flash);
        shaders.setUniform(b.shader, b.fade_bounds, fade_bounds);
        rl.setShaderValueTexture(b.shader, b.normals, normals.?);
        if (s.n > 0) {
            shaders.setUniforms(b.shader, b.lpos, &pos, n);
            shaders.setUniforms(b.shader, b.lcol, &col, n);
        }
        raster.blit(tex, src, dest, rl.Color.white);
        rl.gl.rlDrawRenderBatchActive();
    }

    pub fn beginMirrorFade(self: *const Gpu, bounds: [2]f32) bool {
        if (bounds[0] >= bounds[1]) return false;
        const s = self.mirror_fade orelse return false;
        rl.beginShaderMode(s.shader);
        shaders.setUniform(s.shader, s.fade_bounds, bounds);
        return true;
    }

    pub fn drawGlows(self: *const Gpu, flames_: []const light.Flame, ox: f32, oy: f32, cell: f32) void {
        const g = self.glow orelse return;
        rl.beginBlendMode(.additive);
        defer rl.endBlendMode();
        for (flames_) |f| {
            if (!f.live()) continue;
            const x = ox + f.at[0] * cell;
            const y = oy + f.at[1] * cell;
            glowAt(g, x, y, cell * light.GLOW_HALO, cell * light.GLOW_HALO, light.colourOf(f.tint(), light.GLOW_HALO_A * f.glow * f.lit));
            if (f.kind == .wall) glowAt(g, x, y, cell * light.GLOW_CORE, cell * light.GLOW_CORE, light.colourOf(f.tint(), light.GLOW_CORE_A * f.glow * f.lit));
        }
    }

    layers: std.EnumArray(light.Layer, ?rl.Texture2D) = .initFill(null),
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

    pub fn load() Gpu {
        var g = Gpu{};
        for (std.enums.values(light.Layer)) |k| g.layers.set(k, raster.canvas(light.MAP_W, light.MAP_H, light.UNSEEN.get(k), .bilinear));
        g.glow = raster.radial(GLOW_PX, glowAlpha);
        g.streak = raster.field(STREAK_PX[0], STREAK_PX[1], shadow.streakAlpha);
        g.body = shaders.program(BodyShader, BODY_FS);
        g.mirror_fade = shaders.program(MirrorShader, MIRROR_FS);
        g.shadow = shaders.program(ShadowShader, SHADOW_FS);
        g.receiver = shaders.program(ReceiverShader, RECEIVER_FS);
        g.shade = shaders.shader(SHADE_FS);
        return g;
    }

    pub fn syncFigures(g: *Gpu, figures: *const [look.FIGURES]?rl.Texture2D) void {
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

    pub fn unload(g: *Gpu) void {
        look.unloadAll(g);
        g.syncFigures(&NO_FIGURES);
    }

    pub fn art(g: *const Gpu, t: rl.Texture2D) Art {
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
            const gx = light.texel(&height, w, h, x + 1, y) - light.texel(&height, w, h, x - 1, y);
            const gy = light.texel(&height, w, h, x, y + 1) - light.texel(&height, w, h, x, y - 1);
            const n = Rgb{ -gx * BEVEL_DEPTH, -gy * BEVEL_DEPTH, 1 };
            px[@intCast(y * w + x)] = light.colourOf(sky.unit(n) * splat(0.5) + splat(0.5), 1);
        }
    }
    return raster.clamped(raster.rgba(&px, w, h), .point);
}

fn glowAlpha(r: f32) f32 {
    const r2 = @min(1, r * r);
    return (1 - r2) * (1 - r2) * @exp(-3 * r2);
}

pub fn glowAt(g: rl.Texture2D, x: f32, y: f32, rx: f32, ry: f32, c: rl.Color) void {
    raster.stretch(g, .{ .x = x - rx, .y = y - ry, .width = rx * 2, .height = ry * 2 }, c);
}
