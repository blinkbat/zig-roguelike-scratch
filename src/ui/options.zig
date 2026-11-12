const std = @import("std");
const rl = @import("raylib");
const menu = @import("menu.zig");
const cinema = @import("../gfx/cinema.zig");
const lens = @import("../gfx/lens.zig");
const window = @import("../core/window.zig");
const input = @import("../core/input.zig");
const mathx = @import("../core/mathx.zig");
const font = @import("../gfx/font.zig");
const sprites = @import("../gfx/sprites.zig");
const raster = @import("../gfx/raster.zig");
const look = @import("../gfx/look.zig");
const Prompt = @import("../gfx/prompt_icon.zig").Prompt;

pub const Page = enum { main, visuals, display };
pub const Row = enum { visuals, display, fullscreen, vsync, frame_limit, lens_blur, perspective, vignette, bloom, atmosphere, depth_of_field, saturation, warmth, sepia, film_grain, scanlines, chromatic_aberration, reset_to_defaults, set_all_to_0, debug };
pub fn rows(page: Page) []const Row {
    return switch (page) {
        .main => &.{ .visuals, .display, .debug },
        .display => &.{ .fullscreen, .vsync, .frame_limit },
        .visuals => &.{ .lens_blur, .perspective, .vignette, .bloom, .atmosphere, .depth_of_field, .saturation, .warmth, .sepia, .film_grain, .scanlines, .chromatic_aberration, .reset_to_defaults, .set_all_to_0 },
    };
}

pub fn index(page: Page, row: Row) usize {
    return std.mem.indexOfScalar(Row, rows(page), row).?;
}
const Range = struct { min: f32 = 0, max: f32 = 2, default: f32 = 0 };

fn range(row: Row) ?Range {
    var out: Range = switch (row) {
        .visuals, .display, .fullscreen, .vsync, .frame_limit, .reset_to_defaults, .set_all_to_0, .debug => return null,
        .bloom, .atmosphere, .depth_of_field, .saturation => .{ .default = 1 },
        .warmth => .{ .min = -1, .max = 1 },
        .sepia, .film_grain, .scanlines, .chromatic_aberration => .{ .max = 1 },
        else => .{},
    };
    const defaults: lens.Options = .{};
    inline for (std.meta.fields(lens.Options)) |f| {
        if (row == @field(Row, f.name)) out.default = @field(defaults, f.name);
    }
    return out;
}

pub fn value(c: *const cinema.Cinema, row: Row) f32 {
    inline for (std.meta.fields(lens.Options)) |f| {
        if (row == @field(Row, f.name)) return @field(c.lens.options, f.name);
    }
    inline for (std.meta.fields(cinema.Cinema.Strengths)) |f| {
        if (row == @field(Row, f.name)) return if (@field(c.options, f.name)) @field(c.strengths, f.name) else 0;
    }
    unreachable;
}

pub fn set(c: *cinema.Cinema, row: Row, requested: f32) void {
    const r = range(row) orelse return;
    const amount = std.math.clamp(@round(requested * 100) / 100, r.min, r.max);
    inline for (std.meta.fields(lens.Options)) |f| {
        if (row == @field(Row, f.name)) {
            @field(c.lens.options, f.name) = amount;
            return;
        }
    }
    inline for (std.meta.fields(cinema.Cinema.Strengths)) |f| {
        if (row == @field(Row, f.name)) {
            @field(c.options, f.name) = amount > 0;
            @field(c.strengths, f.name) = if (amount > 0) amount else 1;
            return;
        }
    }
}

pub fn reset(c: *cinema.Cinema) void {
    c.lens.options = .{};
    c.strengths = .{};
    inline for (std.meta.fields(cinema.Cinema.Strengths)) |f| @field(c.options, f.name) = true;
}

pub fn zero(c: *cinema.Cinema) void {
    for (rows(.visuals)) |row| if (range(row) != null) set(c, row, 0);
}

fn track(box: rl.Rectangle) rl.Rectangle {
    return .{ .x = box.x + box.width * 0.52, .y = box.y + box.height / 2 - 3, .width = box.width * 0.32, .height = 6 };
}

fn drag(c: *cinema.Cinema, row: Row, box: rl.Rectangle, x: i32) void {
    const r = range(row).?;
    const rail = track(box);
    set(c, row, r.min + std.math.clamp((@as(f32, @floatFromInt(x)) - rail.x) / rail.width, 0, 1) * (r.max - r.min));
}

pub fn step(c: *cinema.Cinema, selection: *menu.Menu, st: *const input.State, screen: mathx.P, page: Page, display: *window.Display) ?Row {
    const entries = rows(page);
    if (!st.left_down or st.pointer == null or !st.focused or st.walk != null or st.scroll != 0) selection.dragging = null;
    if (selection.dragging) |i| {
        drag(c, entries[i], menu.rowBox(screen, menu.window(screen.y, entries.len, selection.at), i), st.pointer.?.x);
        return null;
    }
    const win = menu.window(screen.y, entries.len, @min(selection.at, entries.len - 1));
    const picked = selection.stepAt(st, entries.len, screen);
    const row = entries[selection.at];
    if (range(row)) |r| {
        if (st.click and picked != null) {
            const box = menu.rowBox(screen, win, selection.at);
            const rail = track(box);
            const p = st.pointer.?;
            if (@as(f32, @floatFromInt(p.x)) >= rail.x - 8) {
                drag(c, row, box, p.x);
                selection.dragging = selection.at;
            }
        } else if (st.walk) |d| {
            if (d.delta().x != 0) set(c, row, value(c, row) + @as(f32, @floatFromInt(d.delta().x)) * 0.05);
        } else if (st.hit(menu.CHANGE)) {
            set(c, row, r.default);
        } else if (picked != null) {
            set(c, row, if (value(c, row) != r.default) r.default else if (row == .saturation) 0 else if (row == .warmth) 0.5 else if (r.default > 0) 0 else 1);
        }
        return null;
    }
    if (picked == null) return null;
    if (row == .reset_to_defaults) {
        reset(c);
        return null;
    }
    if (row == .set_all_to_0) {
        zero(c);
        return null;
    }
    if (row == .vsync or row == .frame_limit) {
        if (row == .vsync) display.vsync = !display.vsync else display.limit = mathx.wrap(display.limit, 1, window.Display.LIMITS.len);
        display.sync();
        return null;
    }
    return row;
}

pub fn draw(face: font.Face, art: *const sprites.Sprites, screen: mathx.P, c: *const cinema.Cinema, selected: usize, st: *const input.State, page: Page, display: window.Display) void {
    const entries = rows(page);
    const win = menu.window(screen.y, entries.len, selected);
    const first = menu.rowBox(screen, win, win.from);
    menu.pageHeading(face, screen, switch (page) {
        .main => "OPTIONS",
        .visuals => "VISUALS",
        .display => "DISPLAY",
    }, menu.titleY(first));
    menu.listPanel(art, .{ .x = first.x, .y = first.y, .width = first.width, .height = @floatFromInt(win.len * menu.ROW_STEP) });
    for (entries[win.from..][0..win.len], win.from..) |row, i| {
        const box = menu.rowBox(screen, win, i);
        const ink = menu.rowInk(i == selected);
        const x = menu.pick(face, box, i == selected);
        var label_buf: [64]u8 = undefined;
        const label = switch (row) {
            .fullscreen => menu.toggle(menu.named(Row.fullscreen), window.fullscreen()),
            .vsync => menu.toggle("VSync", display.vsync),
            .frame_limit => if (window.Display.LIMITS[display.limit] == 0) "Frame limit: Uncapped" else std.fmt.bufPrintZ(&label_buf, "Frame limit: {d} FPS", .{window.Display.LIMITS[display.limit]}) catch "",
            inline else => |r| menu.named(r),
        };
        var fitted: [96]u8 = undefined;
        const text_width = if (range(row) != null) @as(i32, @intFromFloat(track(box).x)) - x - 16 else raster.width(box) - (x - raster.left(box)) - 16;
        face.text(face.fit(&fitted, label, font.BODY, text_width, false), x, menu.rowTextY(box) + 4, font.BODY, ink);
        if (range(row)) |r| {
            const amount = value(c, row);
            const rail = track(box);
            const t = (amount - r.min) / (r.max - r.min);
            rl.drawRectangleRec(rail, look.EDGE);
            rl.drawRectangleRec(.{ .x = rail.x, .y = rail.y, .width = rail.width * t, .height = rail.height }, ink);
            rl.drawRectangleRec(.{ .x = rail.x + rail.width * t - 3, .y = rail.y - 4, .width = 6, .height = 14 }, ink);
            var buf: [24]u8 = undefined;
            const number = std.fmt.bufPrintZ(&buf, "{d:.0}%", .{amount * 100}) catch "";
            face.centred(number, raster.right(box) - 48, raster.middleAt(box).y, font.SMALL, ink);
        }
    }
    if (page != .visuals) return;
    const bottom = raster.top(first) + @as(i32, @intCast(win.len)) * menu.ROW_STEP + 28;
    const movement: Prompt = if (st.device.pad()) .dpad else .arrows;
    var x = movement.drawFrom(&face, raster.left(first) + 20, bottom, 24, 1);
    face.text("Adjust", x + 8, bottom - 10, font.SMALL, look.DIM);
    x = Prompt.menuOf(st, menu.CHANGE).drawFrom(&face, x + 90, bottom, 24, 1);
    face.text("Reset value", x + 8, bottom - 10, font.SMALL, look.DIM);
    var count: [24]u8 = undefined;
    face.centred(std.fmt.bufPrintZ(&count, "{d} / {d}", .{ selected + 1, entries.len }) catch "", raster.right(first) - 48, bottom, font.SMALL, look.DIM);
}

test "visual sliders clamp, reset and drag without changing other effects" {
    var c: cinema.Cinema = .{};
    var selection: menu.Menu = .{ .at = 0 };
    var display: window.Display = .{};
    const screen = mathx.P{ .x = 1280, .y = 720 };
    _ = step(&c, &selection, &.{ .walk = .e }, screen, .visuals, &display);
    try std.testing.expectApproxEqAbs(@as(f32, 0.15), c.lens.options.lens_blur, 0.0001);
    try std.testing.expectEqual(@as(f32, 0.5), c.lens.options.perspective);
    set(&c, .warmth, -5);
    try std.testing.expectEqual(@as(f32, -1), value(&c, .warmth));
    set(&c, .bloom, 7);
    try std.testing.expectEqual(@as(f32, 2), value(&c, .bloom));
    const box = menu.rowBox(screen, menu.window(screen.y, rows(.visuals).len, selection.at), selection.at);
    const rail = track(box);
    _ = step(&c, &selection, &.{ .click = true, .left_down = true, .pointer = .{ .x = @intFromFloat(rail.x + rail.width / 2), .y = raster.middleAt(box).y } }, screen, .visuals, &display);
    try std.testing.expectApproxEqAbs(@as(f32, 1), value(&c, .lens_blur), 0.02);
    _ = step(&c, &selection, &.{ .left_down = true, .pointer = .{ .x = screen.x, .y = 0 } }, screen, .visuals, &display);
    try std.testing.expectEqual(@as(f32, 2), value(&c, .lens_blur));
    _ = step(&c, &selection, &.{ .left_released = true, .dragging = true, .pointer = .{ .x = 0, .y = 0 } }, screen, .visuals, &display);
    try std.testing.expect(selection.dragging == null);
    try std.testing.expectEqual(@as(f32, 2), value(&c, .lens_blur));
    reset(&c);
    try std.testing.expectEqualDeep(lens.Options{}, c.lens.options);
    try std.testing.expect(c.lens.options.active());
    try std.testing.expectEqual(@as(f32, 1), value(&c, .bloom));
    zero(&c);
    for (rows(.visuals)) |row| if (range(row) != null) try std.testing.expectEqual(@as(f32, 0), value(&c, row));
    try std.testing.expect(!lens.Options.neutral.active());
}
