const std = @import("std");
const rl = @import("raylib");

const Box = struct { x: i32, y: i32, w: i32, h: i32 };

fn boxOf(at: rl.Vector2, w: f32, h: f32, scale: f32) Box {
    const width = @max(1, @round(w)) * scale;
    const height = @max(1, @round(h)) * scale;
    return .{ .x = @intFromFloat(@round(at.x - width * 0.5)), .y = @intFromFloat(@round(at.y - height * 0.5)), .w = @intFromFloat(width), .h = @intFromFloat(height) };
}

fn fill(b: Box, col: rl.Color) void {
    if (b.w > 0 and b.h > 0 and col.a > 0) rl.drawRectangle(b.x, b.y, b.w, b.h, col);
}

const Filler = struct {
    col: rl.Color,

    fn put(f: Filler, b: Box) void {
        fill(b, f.col);
    }
};

/// Boxes that touch end to end in one row or column, put as one.
fn Run(comptime Sink: type) type {
    return struct {
        sink: Sink,
        box: ?Box = null,

        fn add(r: *@This(), b: Box) void {
            if (r.box) |*run| {
                if (b.y == run.y and b.h == run.h and (b.x == run.x + run.w or b.x + b.w == run.x)) {
                    run.x = @min(run.x, b.x);
                    run.w += b.w;
                    return;
                }
                if (b.x == run.x and b.w == run.w and (b.y == run.y + run.h or b.y + b.h == run.y)) {
                    run.y = @min(run.y, b.y);
                    run.h += b.h;
                    return;
                }
                r.sink.put(run.*);
            }
            r.box = b;
        }

        fn flush(r: *@This()) void {
            if (r.box) |rest| r.sink.put(rest);
            r.box = null;
        }
    };
}

pub fn rect(at: rl.Vector2, w: f32, h: f32, scale: f32, col: rl.Color) void {
    fill(boxOf(at, w, h, scale), col);
}

fn fleckBoxes(at: rl.Vector2, r: f32, scale: f32) [3]Box {
    const size = @max(1, @round(r * 2));
    const none = Box{ .x = 0, .y = 0, .w = 0, .h = 0 };
    if (size <= 3) return .{ boxOf(at, size, size, scale), none, none };
    const middle = boxOf(at, size, size - 2, scale);
    const cap = boxOf(at, size - 2, size, scale);
    return .{
        middle,
        .{ .x = cap.x, .y = cap.y, .w = cap.w, .h = middle.y - cap.y },
        .{ .x = cap.x, .y = middle.y + middle.h, .w = cap.w, .h = cap.y + cap.h - middle.y - middle.h },
    };
}

pub fn fleck(at: rl.Vector2, r: f32, scale: f32, col: rl.Color) void {
    if (col.a == 0) return;
    for (fleckBoxes(at, r, scale)) |b| fill(b, col);
}

fn trace(a: rl.Vector2, b: rl.Vector2, width: f32, scale: f32, sink: anytype) void {
    const d = b.subtract(a);
    const steps: usize = @intFromFloat(@ceil(@max(@abs(d.x), @abs(d.y)) / scale));
    var last: ?Box = null;
    var run = Run(@TypeOf(sink)){ .sink = sink };
    for (0..steps + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(1, steps)));
        const box = boxOf(.{ .x = a.x + d.x * t, .y = a.y + d.y * t }, width, width, scale);
        if (last) |l| if (l.x == box.x and l.y == box.y) continue;
        run.add(box);
        last = box;
    }
    run.flush();
}

pub fn line(a: rl.Vector2, b: rl.Vector2, width: f32, scale: f32, col: rl.Color) void {
    if (col.a == 0) return;
    trace(a, b, width, scale, Filler{ .col = col });
}

const Canvas = struct {
    covered: [64][64]u8 = @splat(@splat(0)),
    rects: usize = 0,

    fn add(c: *Canvas, b: Box) void {
        c.rects += 1;
        var y = b.y;
        while (y < b.y + b.h) : (y += 1) {
            var x = b.x;
            while (x < b.x + b.w) : (x += 1) c.covered[@intCast(y)][@intCast(x)] += 1;
        }
    }

    const Sink = struct {
        c: *Canvas,

        fn put(s: Sink, b: Box) void {
            s.c.add(b);
        }
    };
};

test "a fleck covers each of its pixels once" {
    var drawn: usize = 0;
    for ([_]f32{ 2, 2.5, 3, 4.5 }) |r| {
        for ([_]f32{ 1, 2 }) |scale| {
            var canvas = Canvas{};
            for (fleckBoxes(.{ .x = 20.3, .y = 19.6 }, r, scale)) |b| canvas.add(b);
            const size: usize = @intFromFloat(@round(r * 2) * scale);
            const corner: usize = @intFromFloat(scale * scale);
            var cells: usize = 0;
            for (canvas.covered) |row| for (row) |c| {
                try std.testing.expect(c <= 1);
                cells += c;
            };
            try std.testing.expectEqual(size * size - 4 * corner, cells);
            drawn += cells;
        }
    }
    std.debug.print("flecks: {d} pixels over 8 sizes and scales, none drawn twice, corners cut\n", .{drawn});
}

test "a thin line covers each pixel once, its touching stamps put as one" {
    const from = rl.Vector2{ .x = 5.4, .y = 8.2 };
    var stamps: usize = 0;
    var rects: usize = 0;
    for ([_]rl.Vector2{ .{ .x = 50.1, .y = 12.7 }, .{ .x = 9.3, .y = 58.6 }, .{ .x = 40.5, .y = 41.2 }, .{ .x = 5.4, .y = 8.2 } }) |to| {
        var canvas = Canvas{};
        trace(from, to, 1, 1, Canvas.Sink{ .c = &canvas });
        var cells: usize = 0;
        for (canvas.covered) |row| for (row) |c| {
            try std.testing.expect(c <= 1);
            cells += c;
        };
        const d = to.subtract(from);
        const major: usize = @intFromFloat(@ceil(@max(@abs(d.x), @abs(d.y))));
        try std.testing.expect(cells >= major and cells <= major + 1);
        stamps += cells;
        rects += canvas.rects;
    }
    try std.testing.expect(rects < stamps);
    std.debug.print("thin lines: {d} pixels, each once, in {d} rects\n", .{ stamps, rects });
}
