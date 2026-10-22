const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const game = @import("../game.zig");
const mathx = @import("../core/mathx.zig");
const menu = @import("../ui/menu.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const cinema = @import("../gfx/cinema.zig");
const light = @import("../gfx/light.zig");

pub const Page = enum { main, gameplay, lighting, effects, display, diagnostics };
pub const Row = enum {
    gameplay,
    lighting,
    effects,
    display,
    diagnostics,
    restart_map,
    reveal_map,
    unkillable,
    composed_lighting,
    shadows,
    body_lighting,
    effect_lights,
    bloom,
    atmosphere,
    depth_of_field,
    water_reflections,
    water_glints,
    weather,
    fullscreen,
    vsync,
    frame_limit,
    performance_overlay,
};

pub const Visuals = struct {
    water_reflections: bool = true,
    weather: bool = true,
};

pub const State = struct {
    page: Page = .main,
    visuals: Visuals = .{},
    vsync: bool = true,
    limit: usize = 0,
    performance_overlay: bool = true,
};

const LIMITS = [_]i32{ 0, 30, 60, 120, 144 };

pub fn rows(page: Page) []const Row {
    return switch (page) {
        .main => &.{ .gameplay, .lighting, .effects, .display, .diagnostics },
        .gameplay => &.{ .restart_map, .reveal_map, .unkillable },
        .lighting => &.{ .composed_lighting, .shadows, .body_lighting, .effect_lights },
        .effects => &.{ .bloom, .atmosphere, .depth_of_field, .water_reflections, .water_glints, .weather },
        .display => &.{ .fullscreen, .vsync, .frame_limit },
        .diagnostics => &.{.performance_overlay},
    };
}

pub fn pageOf(row: Row) Page {
    for (std.enums.values(Page)) |page| {
        for (rows(page)) |r| if (r == row) return page;
    }
    unreachable;
}

comptime {
    var listed = std.EnumSet(Row).initEmpty();
    for (std.enums.values(Page)) |page| for (rows(page)) |r| {
        std.debug.assert(!listed.contains(r));
        listed.insert(r);
    };
    std.debug.assert(listed.count() == std.meta.fields(Row).len);
}

pub fn select(g: *game.Game, row: Row) void {
    open(g, pageOf(row));
    g.pause_menu.at = std.mem.indexOfScalar(Row, rows(g.debug.page), row).?;
}

pub fn open(g: *game.Game, page: Page) void {
    g.pause_page = .debug;
    g.debug.page = page;
    g.pause_menu = .{};
}

fn opens(row: Row) ?Page {
    return switch (row) {
        inline else => |r| if (comptime @hasField(Page, @tagName(r))) @field(Page, @tagName(r)) else null,
    };
}

pub const SWITCHES = .{ cinema.Options, light.Options, Visuals };

pub fn switches(g: *game.Game, comptime T: type) *T {
    return switch (T) {
        cinema.Options => &g.cinema.options,
        light.Options => &g.light.options,
        Visuals => &g.debug.visuals,
        else => @compileError("no Debug switches in " ++ @typeName(T)),
    };
}

fn switched(comptime row: Row) bool {
    inline for (SWITCHES) |T| {
        if (@hasField(T, @tagName(row))) return true;
    }
    return row == .unkillable or row == .performance_overlay;
}

pub fn option(g: *game.Game, row: Row) ?*bool {
    inline for (SWITCHES) |T| {
        inline for (std.meta.fields(T)) |f| {
            if (row == @field(Row, f.name)) return &@field(switches(g, T), f.name);
        }
    }
    return switch (row) {
        .unkillable => &g.unkillable,
        .performance_overlay => &g.debug.performance_overlay,
        else => null,
    };
}

pub fn syncDisplay(g: *const game.Game) void {
    if (g.debug.vsync) rl.setWindowState(.{ .vsync_hint = true }) else rl.clearWindowState(.{ .vsync_hint = true });
    rl.setTargetFPS(LIMITS[g.debug.limit]);
}

pub fn step(g: *game.Game) void {
    if (menu.backed(&g.st)) {
        if (g.debug.page == .main) {
            g.pause_page = .main;
            g.pause_menu.at = game.rowAt(game.PauseRow.debug);
        } else {
            const row: Row = switch (g.debug.page) {
                .main => unreachable,
                inline else => |page| @field(Row, @tagName(page)),
            };
            select(g, row);
        }
        return;
    }
    const entries = rows(g.debug.page);
    const row = entries[g.pause_menu.step(&g.st, entries.len) orelse return];
    if (option(g, row)) |on| {
        on.* = !on.*;
        if (row == .effect_lights) g.light.clearEffects();
        return;
    }
    if (opens(row)) |page| return open(g, page);
    switch (row) {
        .restart_map => game.restart(g),
        .reveal_map => game.character.toggleReveal(g),
        .fullscreen => game.syncScreen(g, true),
        .vsync => {
            g.debug.vsync = !g.debug.vsync;
            syncDisplay(g);
        },
        .frame_limit => {
            g.debug.limit = (g.debug.limit + 1) % LIMITS.len;
            syncDisplay(g);
        },
        inline else => |r| {
            if (comptime (!switched(r) and opens(r) == null)) @compileError("Debug row " ++ @tagName(r) ++ " does nothing");
            unreachable;
        },
    }
}

pub const LABEL_MAX: usize = 64;

pub fn label(g: *game.Game, comptime row: Row, buf: []u8) [:0]const u8 {
    const name = comptime menu.titled(@tagName(row));
    if (option(g, row)) |on| return menu.toggle(name, on.*);
    return switch (row) {
        .reveal_map => menu.toggle(name, g.light.reveal_map),
        .fullscreen => menu.toggle(name, game.fullscreen()),
        .vsync => menu.toggle("VSync", g.debug.vsync),
        .frame_limit => if (g.debug.limit == 0) "Frame Limit: Uncapped" else std.fmt.bufPrintZ(buf, "Frame Limit: {d} FPS", .{LIMITS[g.debug.limit]}) catch "Frame Limit",
        else => name,
    };
}

pub fn draw(g: *game.Game) void {
    if (g.debug.page == .diagnostics) return drawDiagnostics(g);
    const entries = rows(g.debug.page);
    var labels: [std.meta.fields(Row).len][]const u8 = undefined;
    var buf: [LABEL_MAX]u8 = undefined;
    for (entries, 0..) |row, i| labels[i] = switch (row) {
        inline else => |r| label(g, r, &buf),
    };
    const title = switch (g.debug.page) {
        .main => "DEBUG",
        inline else => |page| comptime menu.caps(menu.named(page)),
    };
    menu.draw(g.face, g.screen, title, labels[0..entries.len], g.pause_menu.at, null);
}

fn glString(id: c_uint) [:0]const u8 {
    const get: *const fn (c_uint) callconv(.c) ?[*:0]const u8 = @ptrCast(game.glfw.glfwGetProcAddress("glGetString") orelse return "Unavailable");
    return std.mem.span(get(id) orelse return "Unavailable");
}

const PANEL = mathx.P{ .x = 1040, .y = 540 };
const PAD: i32 = 28;
const INNER_W: i32 = PANEL.x - 2 * PAD;
const TITLE_Y: i32 = 24;
const TOGGLE_Y: i32 = 80;
const TOGGLE_H: i32 = 44;
const GL_Y: i32 = 150;
const STATS_Y: i32 = 288;
const LINE_STEP: i32 = 42;
const BACK_Y: i32 = 472;

fn lineY(top: i32, i: usize) i32 {
    return top + @as(i32, @intCast(i)) * LINE_STEP;
}

fn drawDiagnostics(g: *game.Game) void {
    const surface = menu.Surface.of(g.screen, PANEL);
    surface.beginPanel(&g.sprites, PANEL);
    defer rl.endMode2D();
    const face = surface.faceFor(g.face);
    var buf: [LABEL_MAX]u8 = undefined;
    face.draw("GRAPHICS DIAGNOSTICS", PAD, TITLE_Y, menu.ROW, look.UI_GOLD);
    menu.action(&face, look.rect(PAD, TOGGLE_Y, INNER_W, TOGGLE_H), look.Prompt.menuOf(&g.st, menu.CONFIRM), label(g, .performance_overlay, &buf));
    var line: menu.Note(512) = .{};
    for ([_]struct { name: []const u8, id: c_uint }{
        .{ .name = "Vendor", .id = 0x1F00 },
        .{ .name = "Renderer", .id = 0x1F01 },
        .{ .name = "OpenGL", .id = 0x1F02 },
    }, 0..) |info, i| {
        line.say("{s}: {s}", .{ info.name, glString(info.id) });
        const size = @min(font.BODY, @divTrunc(font.BODY * INNER_W, @max(1, face.width(line.text(), font.BODY))));
        face.draw(line.text(), PAD, lineY(GL_Y, i), size, look.TEXT);
    }
    line.say("Window: {d} x {d}    Framebuffer: {d} x {d}", .{ g.screen.x, g.screen.y, rl.getRenderWidth(), rl.getRenderHeight() });
    face.draw(line.text(), PAD, lineY(STATS_Y, 0), font.BODY, look.TEXT);
    line.say("Build: {s} / {s} / {s}", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch), @tagName(builtin.mode) });
    face.draw(line.text(), PAD, lineY(STATS_Y, 1), font.BODY, look.TEXT);
    face.draw(g.perf.text(), PAD, lineY(STATS_Y, 2), font.BODY, look.TEXT);
    face.draw("CPU time excludes frame pacing and is not a GPU timer.", PAD, lineY(STATS_Y, 3), menu.NOTE, look.DIM);
    menu.action(&face, look.rect(PAD, BACK_Y, menu.ACTION_WIDE.x, menu.ACTION_WIDE.y), look.Prompt.menuOf(&g.st, menu.BACK), "Back");
}
