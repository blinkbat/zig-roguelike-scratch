const std = @import("std");
const game = @import("game.zig");

pub fn main() void {
    const alloc = std.heap.c_allocator;
    const argv = std.process.argsAlloc(alloc) catch return game.play();
    defer std.process.argsFree(alloc, argv);
    for (argv[1..]) |a| {
        // DEV ONLY.
        if (std.mem.eql(u8, a, "--shot")) return game.shot();
        if (std.mem.eql(u8, a, "--bench")) return game.bench();
    }
    game.play();
}

test {
    _ = @import("core/mathx.zig");
    _ = @import("core/input.zig");
    _ = @import("world/grid.zig");
    _ = @import("world/fov.zig");
    _ = @import("world/gen.zig");
    _ = @import("play/actor.zig");
    _ = @import("play/bow.zig");
    _ = @import("gfx/look.zig");
    _ = @import("gfx/font.zig");
    _ = @import("gfx/light.zig");
    _ = @import("game.zig");
}
