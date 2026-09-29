const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const look = @import("look.zig");

// EVERY CLOUD OF GAS AS DRAWN, after Brogue's `getCellAppearance`; out of sight it keeps what was last seen, as memory
// does. Drawn under the light map, which lights and fogs it. Nothing in the simulation reads it.

const P = mathx.P;

/// Texels per cell side: a cell is flat, and the step to the next blends over half a cell.
const SUB: i32 = 2;
const TEX_W: i32 = grid.W * SUB;
const TEX_H: i32 = grid.H * SUB;
const TEXELS: usize = @intCast(TEX_W * TEX_H);
const TINT_LO: f32 = 0.30;
const TINT_PER: f32 = 0.01;
const TINT_HI: f32 = 0.90;
/// Per second.
const EASE: f32 = 8.0;

pub fn tintOf(volume: u16) f32 {
    if (volume == 0) return 0;
    return @min(TINT_HI, TINT_LO + TINT_PER * @as(f32, @floatFromInt(volume)));
}

pub const Cloud = struct {
    tint: [grid.CELLS]f32,
    px: [TEXELS]rl.Color,
    stale: bool,
    /// The cells last baked into `px`.
    baked: [2]P,
    tex: ?rl.Texture2D,

    pub fn create(alloc: std.mem.Allocator) !*Cloud {
        const c = try alloc.create(Cloud);
        c.tex = null;
        c.baked = @splat(.{ .x = 0, .y = 0 });
        c.clear();
        return c;
    }

    pub fn clear(self: *Cloud) void {
        @memset(&self.tint, 0);
        self.stale = true;
    }

    /// As if long eased: the gas in sight, and nothing remembered.
    pub fn settle(self: *Cloud, lv: *const grid.Level) void {
        for (&self.tint, &lv.lit, &lv.gas) |*t, lit, v| t.* = if (lit) tintOf(v) else 0;
        self.stale = true;
    }

    pub fn step(self: *Cloud, lv: *const grid.Level, dt: f32) void {
        const k = 1 - @exp(-dt * EASE);
        for (&self.tint, &lv.lit, &lv.gas) |*t, lit, v| {
            const want = tintOf(v);
            if (!lit or t.* == want) continue;
            t.* = mathx.ease(t.*, want, k, k);
            self.stale = true;
        }
    }

    /// Needs a live GL context.
    pub fn load(self: *Cloud) void {
        const blank = rl.genImageColor(TEX_W, TEX_H, rl.Color.blank);
        defer rl.unloadImage(blank);
        self.tex = look.clamped(blank, .bilinear);
    }

    pub fn unload(self: *Cloud) void {
        if (self.tex) |t| rl.unloadTexture(t);
        self.tex = null;
    }

    /// Cells `lo` up to `hi` are on screen; `ox, oy` is where the floor's top-left corner lands.
    pub fn draw(self: *Cloud, lv: *const grid.Level, lo: P, hi: P, ox: i32, oy: i32, cell: i32) void {
        const tex = self.tex orelse return;
        if (std.mem.allEqual(f32, &self.tint, 0)) return;
        const view = filtered(lo, hi);
        if (self.stale or !view[0].eq(self.baked[0]) or !view[1].eq(self.baked[1])) {
            self.bake(lv, view);
            rl.updateTexture(tex, &self.px);
            self.stale = false;
        }
        rl.drawTexturePro(tex, look.whole(tex), look.floorRect(ox, oy, cell), .{ .x = 0, .y = 0 }, 0, rl.Color.white);
    }

    fn bake(self: *Cloud, lv: *const grid.Level, view: [2]P) void {
        var ty = view[0].y * SUB;
        while (ty < view[1].y * SUB) : (ty += 1) {
            var tx = view[0].x * SUB;
            while (tx < view[1].x * SUB) : (tx += 1) self.px[@intCast(ty * TEX_W + tx)] = look.fade(look.GAS, self.texel(lv, tx, ty));
        }
        self.baked = view;
    }

    /// A wall's texels take the tint of the open cell each faces, so gas meets a wall whole and none shows past it.
    fn texel(self: *const Cloud, lv: *const grid.Level, tx: i32, ty: i32) f32 {
        const c = P{ .x = @divFloor(tx, SUB), .y = @divFloor(ty, SUB) };
        if (lv.walkable(c)) return self.tint[grid.Level.idx(c)];
        const sx: i32 = if (@mod(tx, SUB) * 2 < SUB) -1 else 1;
        const sy: i32 = if (@mod(ty, SUB) * 2 < SUB) -1 else 1;
        return @max(self.openAt(lv, c.add(.{ .x = sx, .y = 0 })), self.openAt(lv, c.add(.{ .x = 0, .y = sy })));
    }

    fn openAt(self: *const Cloud, lv: *const grid.Level, p: P) f32 {
        if (!lv.walkable(p)) return 0;
        return self.tint[grid.Level.idx(p)];
    }
};

/// And a cell round them for the filter to reach.
fn filtered(lo: P, hi: P) [2]P {
    return .{
        .{ .x = @max(0, lo.x - 1), .y = @max(0, lo.y - 1) },
        .{ .x = @min(grid.W, hi.x + 1), .y = @min(grid.H, hi.y + 1) },
    };
}

test "Brogue's tint: 30% at the thinnest, a point a unit, 90% at most" {
    try std.testing.expectEqual(@as(f32, 0), tintOf(0));
    try std.testing.expectApproxEqAbs(@as(f32, 0.31), tintOf(1), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.70), tintOf(40), 1e-6);
    try std.testing.expectEqual(TINT_HI, tintOf(60));
    try std.testing.expectEqual(TINT_HI, tintOf(2000));
}

test "the drawn cloud eases to the gas in sight, and out of sight keeps what was last seen" {
    const alloc = std.testing.allocator;
    const c = try Cloud.create(alloc);
    defer alloc.destroy(c);
    var lv = grid.openFloor();
    const i = grid.Level.idx(.{ .x = 10, .y = 10 });
    lv.gas[i] = 40;
    lv.lit[i] = true;
    const dt: f32 = 1.0 / 240.0;
    var t: f32 = 0;
    while (c.tint[i] < tintOf(40) * 0.95) : (t += dt) c.step(&lv, dt);
    for (0..240) |_| c.step(&lv, dt);
    std.debug.print("gas cloud: 95% of the way to its tint in {d:.0} ms\n", .{t * 1000});
    try std.testing.expect(t > 0.2 and t < 0.6);
    try std.testing.expectEqual(tintOf(40), c.tint[i]);
    lv.lit[i] = false;
    lv.gas[i] = 0;
    for (0..240) |_| c.step(&lv, dt);
    try std.testing.expectEqual(tintOf(40), c.tint[i]);
    lv.lit[i] = true;
    for (0..480) |_| c.step(&lv, dt);
    try std.testing.expectEqual(@as(f32, 0), c.tint[i]);
}

test "a wall's texels carry the gas of the room they face up to it, and none shows in the corridor past it" {
    const alloc = std.testing.allocator;
    const c = try Cloud.create(alloc);
    defer alloc.destroy(c);
    var lv = grid.Level.blank();
    var y: i32 = 5;
    while (y < 10) : (y += 1) {
        var x: i32 = 5;
        while (x < 10) : (x += 1) {
            lv.set(.{ .x = x, .y = y }, .floor);
            c.tint[grid.Level.idx(.{ .x = x, .y = y })] = 0.8;
        }
        lv.set(.{ .x = 11, .y = y }, .floor);
    }
    const wall_x = 10 * SUB;
    try std.testing.expectEqual(@as(f32, 0.8), c.texel(&lv, wall_x, 7 * SUB));
    try std.testing.expectEqual(@as(f32, 0), c.texel(&lv, wall_x + SUB - 1, 7 * SUB));
    try std.testing.expectEqual(@as(f32, 0), c.texel(&lv, 11 * SUB, 7 * SUB));
    try std.testing.expectEqual(@as(f32, 0.8), c.texel(&lv, 7 * SUB, 4 * SUB + SUB - 1));
    try std.testing.expectEqual(@as(f32, 0), c.texel(&lv, 7 * SUB, 4 * SUB));
}
