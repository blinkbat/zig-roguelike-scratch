const std = @import("std");
const game = @import("game.zig");
const app = @import("app.zig");
const atlas = @import("world/atlas.zig");

pub fn main() void {
    const alloc = std.heap.c_allocator;
    const argv = std.process.argsAlloc(alloc) catch return app.run(null);
    defer std.process.argsFree(alloc, argv);
    for (argv[1..], 1..) |a, i| {
        if (std.mem.eql(u8, a, "--edit")) return app.run(if (i + 1 < argv.len) argv[i + 1] else atlas.MAIN);
        // DEV ONLY.
        if (std.mem.eql(u8, a, "--shot")) return game.shot();
        if (std.mem.eql(u8, a, "--bench")) return game.bench();
    }
    app.run(null);
}

test {
    _ = @import("core/mathx.zig");
    _ = @import("core/input.zig");
    _ = @import("core/store.zig");
    _ = @import("world/grid.zig");
    _ = @import("world/fov.zig");
    _ = @import("world/gen.zig");
    _ = @import("world/gas.zig");
    _ = @import("world/atlas.zig");
    _ = @import("play/actor.zig");
    _ = @import("play/bow.zig");
    _ = @import("play/pack.zig");
    _ = @import("play/skillbar.zig");
    _ = @import("play/hero.zig");
    _ = @import("gfx/look.zig");
    _ = @import("gfx/font.zig");
    _ = @import("gfx/fx.zig");
    _ = @import("gfx/cloud.zig");
    _ = @import("gfx/vignette.zig");
    _ = @import("gfx/light.zig");
    _ = @import("ui/menu.zig");
    _ = @import("ui/naming.zig");
    _ = @import("game.zig");
    _ = @import("edit/editor.zig");
    _ = @import("save.zig");
    _ = @import("app.zig");
}
