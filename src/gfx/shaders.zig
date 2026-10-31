const std = @import("std");
const rl = @import("raylib");
const grid = @import("../map/grid.zig");
const sky = @import("sky.zig");
const look = @import("look.zig");

/// Shaders `shader` has failed to compile since the process started.
pub var shader_failures: u32 = 0;

/// Null when it does not compile: raylib then hands back its default shader rather than an error.
pub fn shader(fs: [:0]const u8) ?rl.Shader {
    const s = rl.loadShaderFromMemory(null, fs) catch {
        shader_failures += 1;
        return null;
    };
    if (s.id != rl.gl.rlGetShaderIdDefault()) return s;
    shader_failures += 1;
    return null;
}

/// For headless runs, after everything they draw has loaded.
pub fn expectShaders() error{ShaderFailed}!void {
    if (shader_failures > 0) return error.ShaderFailed;
}

fn uniforms(comptime T: type, s: rl.Shader) T {
    var u: T = undefined;
    u.shader = s;
    inline for (std.meta.fields(T)) |f| {
        if (comptime std.mem.eql(u8, f.name, "shader")) continue;
        @field(u, f.name) = rl.getShaderLocation(s, f.name);
    }
    return u;
}

/// Shader uniforms and `T`'s fields must match in both directions at compile time.
pub fn program(comptime T: type, comptime fs: [:0]const u8) ?T {
    comptime {
        @setEvalBranchQuota(100_000);
        for (std.meta.fields(T)) |f| {
            if (!std.mem.eql(u8, f.name, "shader") and !declares(fs, f.name)) @compileError("no uniform " ++ f.name ++ " in the shader for " ++ @typeName(T));
        }
        var lines = std.mem.splitScalar(u8, fs, '\n');
        while (lines.next()) |l| {
            const name = uniformOf(l) orelse continue;
            if (!std.mem.eql(u8, name, "texture0") and !@hasField(T, name)) @compileError("uniform " ++ name ++ " has no field in " ++ @typeName(T));
        }
    }
    return uniforms(T, shader(fs) orelse return null);
}

/// `value` to the uniform at `loc`, its GLSL type read off its Zig type.
pub fn setUniform(s: rl.Shader, loc: i32, value: anytype) void {
    rl.setShaderValue(s, loc, &value, comptime uniformType(@TypeOf(value)));
}

/// The first `n` of `values` to the uniform array at `loc`.
pub fn setUniforms(s: rl.Shader, loc: i32, values: anytype, n: i32) void {
    rl.setShaderValueV(s, loc, values, comptime uniformType(std.meta.Elem(@TypeOf(values.*))), n);
}

fn uniformType(comptime T: type) rl.ShaderUniformDataType {
    return switch (T) {
        f32 => .float,
        [2]f32 => .vec2,
        [3]f32 => .vec3,
        [4]f32 => .vec4,
        i32 => .int,
        else => @compileError("no uniform type for " ++ @typeName(T)),
    };
}

fn declares(comptime fs: []const u8, comptime name: []const u8) bool {
    var lines = std.mem.splitScalar(u8, fs, '\n');
    while (lines.next()) |l| {
        if (std.mem.eql(u8, uniformOf(l) orelse continue, name)) return true;
    }
    return false;
}

fn uniformOf(comptime l: []const u8) ?[]const u8 {
    const line = std.mem.trim(u8, l, " \t\r");
    if (!std.mem.startsWith(u8, line, "uniform ")) return null;
    const end = std.mem.indexOfAny(u8, line, "[;") orelse return null;
    const head = std.mem.trimRight(u8, line[0..end], " ");
    const at = std.mem.lastIndexOfScalar(u8, head, ' ') orelse return null;
    return head[at + 1 ..];
}

/// GLSL `const`s named for `values`' fields: floats at full precision, integers, and two- to four-float vectors.
pub fn glslConsts(comptime values: anytype) [:0]const u8 {
    comptime {
        var out: [:0]const u8 = "";
        for (std.meta.fields(@TypeOf(values))) |f| {
            const v = @field(values, f.name);
            out = out ++ switch (@typeInfo(@TypeOf(v))) {
                .int, .comptime_int => std.fmt.comptimePrint("const int {s} = {d};\n", .{ f.name, v }),
                .float, .comptime_float => "const float " ++ f.name ++ " = " ++ glslFloat(v) ++ ";\n",
                .array, .vector => glslVec(f.name, v),
                else => @compileError(f.name ++ " is no GLSL constant"),
            };
        }
        return out;
    }
}

fn glslVec(comptime name: []const u8, comptime v: anytype) [:0]const u8 {
    const n = switch (@typeInfo(@TypeOf(v))) {
        inline .array, .vector => |a| a.len,
        else => unreachable,
    };
    if (n < 2 or n > 4) @compileError(name ++ " has no GLSL vector of its length");
    const kind = std.fmt.comptimePrint("vec{d}", .{n});
    var parts: [:0]const u8 = glslFloat(v[0]);
    for (1..n) |i| parts = parts ++ ", " ++ glslFloat(v[i]);
    return "const " ++ kind ++ " " ++ name ++ " = " ++ kind ++ "(" ++ parts ++ ");\n";
}

fn glslFloat(comptime v: anytype) [:0]const u8 {
    const s = std.fmt.comptimePrint("{d}", .{@as(f32, v)});
    return if (std.mem.indexOfAny(u8, s, ".e") == null) s ++ ".0" else s;
}

/// What every fragment shader opens with: raylib's inputs and output, `CLEAR_A`, the map's size in cells and `sky.LUMA`.
pub const FS_HEAD =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\uniform sampler2D texture0;
    \\out vec4 finalColor;
    \\
++ glslConsts(.{ .CLEAR_A = look.CLEAR_A, .CELLS = [2]f32{ grid.W, grid.H }, .LUMA = sky.LUMA });

/// The map's place on screen: `cellAtFrag()` is the map position under the fragment, in cells, `cellAtPixel` under a y-down screen pixel,
/// `targetPixel` the y-down screen pixel at a render target's uv, and `insideMap` whether a map position lies on the map.
pub const MAP_VIEW_FS =
    \\uniform vec2 origin;
    \\uniform float cell;
    \\uniform vec2 screen;
    \\vec2 cellAtPixel(vec2 pixel) {
    \\    return (pixel - origin) / cell;
    \\}
    \\vec2 cellAtFrag() {
    \\    return cellAtPixel(vec2(gl_FragCoord.x, screen.y - gl_FragCoord.y));
    \\}
    \\vec2 targetPixel(vec2 uv) {
    \\    return vec2(uv.x, 1.0 - uv.y) * screen;
    \\}
    \\bool insideMap(vec2 c) {
    \\    return all(greaterThanEqual(c, vec2(0.0))) && all(lessThan(c, CELLS));
    \\}
    \\
;

pub const SIN_HASH_FS =
    \\float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    \\
;

/// `noise(p)`: value noise over the `float hash(vec2)` declared before it.
pub const VALUE_NOISE_FS =
    \\float noise(vec2 p) {
    \\    vec2 i = floor(p);
    \\    vec2 f = fract(p);
    \\    vec2 u = f * f * (3.0 - 2.0 * f);
    \\    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
    \\}
    \\
;

/// `MAP_VIEW_FS`'s uniforms: where the map's top-left corner lands, a cell's pixels, and the target's size.
pub const MapView = struct {
    origin: [2]f32,
    cell: f32,
    screen: [2]f32,

    pub fn of(ox: i32, oy: i32, cell: i32, w: i32, h: i32) MapView {
        return .{ .origin = .{ @floatFromInt(ox), @floatFromInt(oy) }, .cell = @floatFromInt(cell), .screen = .{ @floatFromInt(w), @floatFromInt(h) } };
    }
};

/// Sets `MAP_VIEW_FS`'s uniforms on a program with `origin`, `cell` and `screen` locations.
pub fn setMapView(p: anytype, v: MapView) void {
    setUniform(p.shader, p.origin, v.origin);
    setUniform(p.shader, p.cell, v.cell);
    setUniform(p.shader, p.screen, v.screen);
}
