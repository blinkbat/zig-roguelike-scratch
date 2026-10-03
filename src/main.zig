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
    _ = @import("world/carve.zig");
    _ = @import("world/procgen.zig");
    _ = @import("world/biome/cavern.zig");
    _ = @import("world/biome/caves.zig");
    _ = @import("world/biome/dunes.zig");
    _ = @import("world/biome/hall.zig");
    _ = @import("world/biome/keep.zig");
    _ = @import("world/biome/labyrinth.zig");
    _ = @import("world/biome/maze.zig");
    _ = @import("world/biome/open.zig");
    _ = @import("world/biome/site.zig");
    _ = @import("world/biome/strata.zig");
    _ = @import("world/biome/terrain.zig");
    _ = @import("world/biome/topology.zig");
    _ = @import("world/biome/town.zig");
    _ = @import("world/biome/wilds.zig");
    _ = @import("world/feature/border.zig");
    _ = @import("world/feature/buildings.zig");
    _ = @import("world/feature/farms.zig");
    _ = @import("world/feature/lake.zig");
    _ = @import("world/feature/river.zig");
    _ = @import("world/feature/road.zig");
    _ = @import("world/feature/scatter.zig");
    _ = @import("world/feature/setpiece.zig");
    _ = @import("world/gas.zig");
    _ = @import("world/day.zig");
    _ = @import("world/lume.zig");
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
    _ = @import("gfx/sky.zig");
    _ = @import("gfx/vignette.zig");
    _ = @import("gfx/light.zig");
    _ = @import("ui/menu.zig");
    _ = @import("ui/naming.zig");
    _ = @import("game.zig");
    _ = @import("edit/editor.zig");
    _ = @import("save.zig");
    _ = @import("app.zig");
}
