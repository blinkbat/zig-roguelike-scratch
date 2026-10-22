const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const game = @import("../game.zig");
const menu = @import("../ui/menu.zig");
const look = @import("../gfx/look.zig");
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

pub fn select(g: *game.Game, row: Row) void {
    g.pause_page = .debug;
    g.debug.page = pageOf(row);
    g.pause_menu.at = std.mem.indexOfScalar(Row, rows(g.debug.page), row).?;
}

fn option(g: *game.Game, row: Row) ?*bool {
    inline for (.{ .{ cinema.Options, &g.cinema.options }, .{ light.Options, &g.light.options }, .{ Visuals, &g.debug.visuals } }) |group| {
        inline for (std.meta.fields(group[0])) |f| {
            if (row == @field(Row, f.name)) return &@field(group[1], f.name);
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
    switch (row) {
        .gameplay, .lighting, .effects, .display, .diagnostics => {
            g.debug.page = switch (row) {
                inline .gameplay, .lighting, .effects, .display, .diagnostics => |r| @field(Page, @tagName(r)),
                else => unreachable,
            };
            g.pause_menu = .{};
        },
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
        else => unreachable,
    }
}

fn label(g: *game.Game, comptime row: Row, buf: []u8) [:0]const u8 {
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
    var buf: [64]u8 = undefined;
    for (entries, 0..) |row, i| labels[i] = switch (row) {
        inline else => |r| label(g, r, &buf),
    };
    const title = switch (g.debug.page) {
        .main => "DEBUG",
        inline else => |page| comptime menu.caps(menu.named(page)),
    };
    menu.draw(g.face, g.screen, title, labels[0..entries.len], g.pause_menu.at, null);
}

const GLProc = *const fn () callconv(.c) void;
extern fn glfwGetProcAddress(name: [*:0]const u8) ?GLProc;

fn glString(id: c_uint) [:0]const u8 {
    const get: *const fn (c_uint) callconv(.c) ?[*:0]const u8 = @ptrCast(glfwGetProcAddress("glGetString") orelse return "Unavailable");
    return std.mem.span(get(id) orelse return "Unavailable");
}

fn drawDiagnostics(g: *game.Game) void {
    const surface = menu.Surface.of(g.screen, .{ .x = 1040, .y = 540 });
    surface.beginPanel(&g.sprites, .{ .x = 1040, .y = 540 });
    defer rl.endMode2D();
    const face = surface.faceFor(g.face);
    face.draw("GRAPHICS DIAGNOSTICS", 28, 24, 28, look.UI_GOLD);
    menu.action(&face, look.rect(28, 80, 984, 44), look.Prompt.menuOf(&g.st, menu.CONFIRM), menu.toggle("Performance Overlay", g.debug.performance_overlay));
    var line: menu.Note(512) = .{};
    for ([_]struct { name: []const u8, id: c_uint }{
        .{ .name = "Vendor", .id = 0x1F00 },
        .{ .name = "Renderer", .id = 0x1F01 },
        .{ .name = "OpenGL", .id = 0x1F02 },
    }, 0..) |info, i| {
        line.say("{s}: {s}", .{ info.name, glString(info.id) });
        const size = @min(20, @divTrunc(20 * 984, @max(1, face.width(line.text(), 20))));
        face.draw(line.text(), 28, 150 + @as(i32, @intCast(i)) * 42, size, look.TEXT);
    }
    line.say("Window: {d} x {d}    Framebuffer: {d} x {d}", .{ g.screen.x, g.screen.y, rl.getRenderWidth(), rl.getRenderHeight() });
    face.draw(line.text(), 28, 288, 20, look.TEXT);
    line.say("Build: {s} / {s} / {s}", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch), @tagName(builtin.mode) });
    face.draw(line.text(), 28, 330, 20, look.TEXT);
    face.draw(g.perf.buf[0..g.perf.len :0], 28, 372, 20, look.TEXT);
    face.draw("CPU time excludes frame pacing and is not a GPU timer.", 28, 414, 18, look.DIM);
    menu.action(&face, look.rect(28, 472, 220, 40), look.Prompt.menuOf(&g.st, menu.BACK), "Back");
}
