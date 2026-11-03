const std = @import("std");
const rl = @import("raylib");
const look = @import("look.zig");

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

/// A plus, `arm` long across and down, a pixel thick.
pub fn cross(at: rl.Vector2, arm: f32, scale: f32, col: rl.Color) void {
    rect(at, arm, 1, scale, col);
    rect(at, 1, arm, scale, col);
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

const HAZE_LAYERS = 3;
const HAZE_LUMPS = 3;

fn hazeEach(at: rl.Vector2, r: f32, scale: f32, turn: f32, sink: anytype) void {
    for (0..HAZE_LUMPS) |i| {
        const n: f32 = @floatFromInt(i);
        const a = turn + n * 2.4;
        const off = if (i == 0) 0 else r * 0.6 * scale;
        const lump = rl.Vector2{ .x = at.x + @cos(a) * off, .y = at.y + @sin(a) * off * 0.7 };
        const size = if (i == 0) r else r * (0.9 - 0.15 * n);
        for (0..HAZE_LAYERS) |k| {
            for (fleckBoxes(lump, size * (1 - @as(f32, @floatFromInt(k)) * 0.3), scale)) |b| sink.put(b);
        }
    }
}

/// A soft clump of vapour: offset lumps stacked from faint layers, so it thins toward its edge; `turn` varies the clump.
pub fn haze(at: rl.Vector2, r: f32, scale: f32, turn: f32, col: rl.Color) void {
    if (col.a == 0) return;
    const a = look.alphaOf(col);
    const each = 1 - std.math.pow(f32, 1 - a * 0.8, 1.0 / @as(f32, HAZE_LAYERS));
    hazeEach(at, r, scale, turn, Filler{ .col = .{ .r = col.r, .g = col.g, .b = col.b, .a = @intFromFloat(@max(1, each * 255)) } });
}

const Stamps = struct {
    a: rl.Vector2,
    d: rl.Vector2,
    steps: usize,
    width: f32,
    scale: f32,
    tall: bool,
    back: bool,

    fn of(a: rl.Vector2, b: rl.Vector2, width: f32, scale: f32) Stamps {
        const d = b.subtract(a);
        const tall = @abs(d.y) > @abs(d.x);
        return .{
            .a = a,
            .d = d,
            .steps = @intFromFloat(@ceil(@max(@abs(d.x), @abs(d.y)) / scale)),
            .width = width,
            .scale = scale,
            .tall = tall,
            .back = (if (tall) d.y else d.x) < 0,
        };
    }

    fn box(s: Stamps, i: usize) Box {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(1, s.steps)));
        return boxOf(.{ .x = s.a.x + s.d.x * t, .y = s.a.y + s.d.y * t }, s.width, s.width, s.scale);
    }

    /// The `i`th stamp in order along the major axis, as its major then minor corner.
    fn corner(s: Stamps, i: usize) [2]i32 {
        const b = s.box(if (s.back) s.steps - i else i);
        return if (s.tall) .{ b.y, b.x } else .{ b.x, b.y };
    }
};

/// The pixels the line's square stamps cover, each column (row, if tall) put once as the span of the stamps over it.
fn trace(a: rl.Vector2, b: rl.Vector2, width: f32, scale: f32, sink: anytype) void {
    const s = Stamps.of(a, b, width, scale);
    const size = s.box(0).w;
    var run = Run(@TypeOf(sink)){ .sink = sink };
    var lo: usize = 0;
    var hi: usize = 0;
    var first = s.corner(0);
    var last = first;
    var next = if (s.steps > 0) s.corner(1) else last;
    var c = first[0];
    const end = s.corner(s.steps)[0] + size;
    while (c < end) : (c += 1) {
        while (hi < s.steps and next[0] <= c) {
            hi += 1;
            last = next;
            if (hi < s.steps) next = s.corner(hi + 1);
        }
        while (lo < hi and first[0] + size <= c) {
            lo += 1;
            first = s.corner(lo);
        }
        const top = @min(first[1], last[1]);
        const span = @max(first[1], last[1]) + size - top;
        run.add(if (s.tall) .{ .x = top, .y = c, .w = span, .h = 1 } else .{ .x = c, .y = top, .w = 1, .h = span });
    }
    run.flush();
}

pub fn line(a: rl.Vector2, b: rl.Vector2, width: f32, scale: f32, col: rl.Color) void {
    if (col.a == 0) return;
    trace(a, b, width, scale, Filler{ .col = col });
}

/// The art pixels, `scale` screen pixels a side from `origin`, a pixel-wide line from `a` to `b` passes through, each once.
pub fn gridCells(a: rl.Vector2, b: rl.Vector2, origin: [2]f32, scale: f32, out: [][2]i32) [][2]i32 {
    var x, var y = artCell(a, origin, scale);
    const x1, const y1 = artCell(b, origin, scale);
    const dx: i32 = @intCast(@abs(x1 - x));
    const dy: i32 = -@as(i32, @intCast(@abs(y1 - y)));
    const sx: i32 = if (x < x1) 1 else -1;
    const sy: i32 = if (y < y1) 1 else -1;
    var err = dx + dy;
    var n: usize = 0;
    while (n < out.len) {
        out[n] = .{ x, y };
        n += 1;
        if (x == x1 and y == y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }
    }
    return out[0..n];
}

/// A pixel-wide line snapped to the art-pixel grid `scale` screen pixels a side from `origin`; `from_second` leaves out its first pixel, so joined segments put each pixel once.
pub fn gridLine(a: rl.Vector2, b: rl.Vector2, origin: [2]f32, scale: f32, col: rl.Color, from_second: bool) void {
    if (col.a == 0) return;
    var buf: [512][2]i32 = undefined;
    const cells = gridCells(a, b, origin, scale, &buf);
    for (cells[@min(cells.len, @intFromBool(from_second))..]) |c| {
        const x = artEdge(origin[0], c[0], scale);
        const y = artEdge(origin[1], c[1], scale);
        fill(.{ .x = @intFromFloat(x), .y = @intFromFloat(y), .w = @intFromFloat(artEdge(origin[0], c[0] + 1, scale) - x), .h = @intFromFloat(artEdge(origin[1], c[1] + 1, scale) - y) }, col);
    }
}

fn artCell(v: rl.Vector2, origin: [2]f32, scale: f32) [2]i32 {
    return .{ @intFromFloat(@floor((v.x - origin[0]) / scale)), @intFromFloat(@floor((v.y - origin[1]) / scale)) };
}

fn artEdge(o: f32, c: i32, scale: f32) f32 {
    return @round(o + @as(f32, @floatFromInt(c)) * scale);
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

test "a haze is densest at its core, one faint layer at its edge, and clumps differently by turn" {
    var first = Canvas{};
    var second = Canvas{};
    hazeEach(.{ .x = 32, .y = 32 }, 4, 2, 0, Canvas.Sink{ .c = &first });
    hazeEach(.{ .x = 32, .y = 32 }, 4, 2, 1.3, Canvas.Sink{ .c = &second });
    var core: u8 = 0;
    var edge: usize = 0;
    var covered: usize = 0;
    var differ: usize = 0;
    for (first.covered, second.covered) |row, other| for (row, other) |c, d| {
        core = @max(core, c);
        edge += @intFromBool(c == 1);
        covered += @intFromBool(c > 0);
        differ += @intFromBool((c > 0) != (d > 0));
    };
    try std.testing.expect(core >= HAZE_LAYERS and edge > 0 and differ > 0);
    std.debug.print("haze: {d} pixels, {d} at one layer, {d} layers deep at the core, {d} pixels differ by turn\n", .{ covered, edge, core, differ });
}

test "a line of any width and scale covers its stamps' pixels once each, in fewer rects than pixels" {
    var pixels: usize = 0;
    var rects: usize = 0;
    var overlapped: usize = 0;
    for ([_]f32{ 1, 2, 3 }) |width| for ([_]f32{ 1, 2 }) |scale| {
        for ([_][2]rl.Vector2{
            .{ .{ .x = 5.4, .y = 8.2 }, .{ .x = 50.1, .y = 12.7 } },
            .{ .{ .x = 5.4, .y = 8.2 }, .{ .x = 9.3, .y = 52.6 } },
            .{ .{ .x = 5.4, .y = 8.2 }, .{ .x = 40.5, .y = 41.2 } },
            .{ .{ .x = 50.1, .y = 40.7 }, .{ .x = 8.6, .y = 9.3 } },
            .{ .{ .x = 30.2, .y = 50.5 }, .{ .x = 36.7, .y = 7.1 } },
            .{ .{ .x = 5.4, .y = 8.2 }, .{ .x = 5.4, .y = 8.2 } },
        }) |ends| {
            var canvas = Canvas{};
            trace(ends[0], ends[1], width, scale, Canvas.Sink{ .c = &canvas });
            var stamped = Canvas{};
            const s = Stamps.of(ends[0], ends[1], width, scale);
            for (0..s.steps + 1) |i| stamped.add(s.box(i));
            for (canvas.covered, stamped.covered) |row, want| for (row, want) |c, w| {
                try std.testing.expect(c <= 1);
                try std.testing.expectEqual(@intFromBool(w > 0), c);
                pixels += c;
                overlapped += @intFromBool(w > 1);
            };
            rects += canvas.rects;
        }
    };
    try std.testing.expect(rects < pixels);
    std.debug.print("lines: {d} pixels, each once, in {d} rects; {d} of them stamped more than once\n", .{ pixels, rects, overlapped });
}

test "a grid line steps one art pixel at a time from the cell under one end to the cell under the other" {
    var buf: [128][2]i32 = undefined;
    var total: usize = 0;
    for ([_][2]f32{ .{ 0, 0 }, .{ 0.4, 0.7 } }) |origin| for ([_]f32{ 1, 2 }) |scale| {
        for ([_][2]rl.Vector2{
            .{ .{ .x = 5.4, .y = 8.2 }, .{ .x = 50.1, .y = 12.7 } },
            .{ .{ .x = 50.1, .y = 40.7 }, .{ .x = 8.6, .y = 9.3 } },
            .{ .{ .x = 30.2, .y = 50.5 }, .{ .x = 36.7, .y = 7.1 } },
            .{ .{ .x = 5.4, .y = 8.2 }, .{ .x = 5.9, .y = 8.6 } },
        }) |ends| {
            const cells = gridCells(ends[0], ends[1], origin, scale, &buf);
            try std.testing.expectEqual(artCell(ends[0], origin, scale), cells[0]);
            try std.testing.expectEqual(artCell(ends[1], origin, scale), cells[cells.len - 1]);
            for (cells[1..], cells[0 .. cells.len - 1]) |c, prev| {
                try std.testing.expect(@max(@abs(c[0] - prev[0]), @abs(c[1] - prev[1])) == 1);
            }
            const span = artCell(ends[1], origin, scale);
            const start = artCell(ends[0], origin, scale);
            try std.testing.expectEqual(@max(@abs(span[0] - start[0]), @abs(span[1] - start[1])) + 1, @as(u32, @intCast(cells.len)));
            total += cells.len;
        }
    };
    std.debug.print("grid lines: {d} art pixels, one step apart, the fewest that join each pair of ends\n", .{total});
}
