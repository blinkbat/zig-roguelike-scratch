const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const atlas = @import("../map/atlas.zig");
const atlas_text = @import("../map/atlas_text.zig");
const carve = @import("../map/carve.zig");
const terrain = @import("../map/biome/terrain.zig");
const labyrinth = @import("../map/biome/labyrinth.zig");
const hall = @import("../map/biome/hall.zig");
const maze = @import("../map/biome/maze.zig");
const town = @import("../map/biome/town.zig");
const site = @import("../map/biome/site.zig");
const climate = @import("../map/climate.zig");
const scatter = @import("../map/feature/scatter.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const font = @import("../gfx/font.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");
const panel = @import("panel.zig");
const editor = @import("editor.zig");
const Desk = input.Desk;
const HEAD = font.HEAD;
const HOVER = look.EDIT_HOVER;

pub fn drawGenerator(ed: *editor.Editor, g: *game.Game, top: i32, pg: *atlas.Procgen) void {
    const was = pg.*;
    const fo = &pg.foes;
    var y = panel.beginScroll(ed, g, top);
    defer panel.endScroll(ed);
    if (nodeSwitch(ed, g, &y)) return;
    y += editor.BLOCK_GAP;
    section(g, &y, "Base");
    choiceRow(ed, g, &y, atlas.Floor, &pg.floor, ALGO_CHOICE, .algo);
    switch (pg.floor) {
        inline else => |*fl, t| knobRows(ed, g, &y, fl, comptime rowsOf(t), true),
    }
    y += editor.BLOCK_GAP;
    section(g, &y, "Features");
    var drop_feature: ?usize = null;
    for (pg.featuresMut(), 0..) |*ft, i| {
        if (editor.button(ed, g, editor.row(editor.PAD + editor.LABEL_W - editor.STEP_W - editor.GAP, y, editor.STEP_W), DROP, false, true, "Take this feature away")) drop_feature = i;
        choiceRow(ed, g, &y, atlas.Feature, ft, FEATURE_CHOICE, .{ .feature = i });
        switch (ft.*) {
            inline else => |*fp, k| knobRows(ed, g, &y, fp, comptime featureRowsOf(k), true),
        }
        y += editor.BLOCK_GAP;
    }
    if (drop_feature) |i| pg.dropFeature(i);
    if (editor.button(ed, g, editor.cellOfRow(y, 0, 1), "+ Feature", false, pg.feature_n < atlas.MAX_FEATURES, ADD_FEATURE_TIP)) _ = pg.addFeature(atlas.FIRST_FEATURE);
    y += editor.ROW_H + editor.SECTION_GAP;
    knobs(ed, g, &y, if (pg.floor.outdoor()) "Sky" else "Sky (this base is under a roof)", &pg.sky, &SKY_ROWS, pg.floor.outdoor());
    y += editor.BLOCK_GAP;
    knobs(ed, g, &y, "Foes", fo, &FOE_ROWS, true);
    y += editor.BLOCK_GAP;
    section(g, &y, "Makeups");
    var drop: ?usize = null;
    for (fo.makeup[0..fo.makeup_n], 0..) |*m, i| {
        if (drawMakeup(ed, g, y, m, fo.canDrop())) drop = i;
        y += editor.ROW_STEP;
    }
    if (drop) |i| _ = fo.dropMakeup(i);
    if (editor.button(ed, g, editor.cellOfRow(y, 0, 1), "+ Makeup", false, fo.canAdd(), ADD_MAKEUP_TIP)) _ = fo.addMakeup();
    panel.scrolledTo(ed, g, top, y + editor.ROW_H);
    editor.refit(ed, pg, was);
}

fn nodeSwitch(ed: *editor.Editor, g: *game.Game, y: *i32) bool {
    var name: [atlas.TITLE_MAX]u8 = undefined;
    rowLabel(g, y.*, "Node");
    var procgen: usize = 0;
    for (ed.map.nodes()) |*nd| procgen += @intFromBool(nd.unrolled());
    const tip = "The next or last procgen node's generator";
    const by = stepper(ed, g, valueSlot(y.*, 0, 1), ed.nodeName(ed.node, &name), .{
        .{ .tip = tip, .live = procgen > 1 },
        .{ .tip = tip, .live = procgen > 1 },
    });
    y.* += editor.ROW_STEP;
    if (by == 0) return false;
    var n = ed.node;
    while (true) {
        n = mathx.wrap(n, std.math.sign(by), ed.map.node_n);
        if (ed.map.node[n].unrolled()) break;
    }
    if (n == ed.node) return false;
    ed.select(n);
    return true;
}

pub fn section(g: *game.Game, y: *i32, title: [:0]const u8) void {
    editor.textFace(g).draw(title, editor.PAD, y.*, editor.TEXT, look.DIM);
    y.* += HEAD;
}

fn knobs(ed: *editor.Editor, g: *game.Game, y: *i32, title: [:0]const u8, owner: anytype, comptime rows: []const Knob, live: bool) void {
    section(g, y, title);
    knobRows(ed, g, y, owner, rows, live);
}

fn knobRows(ed: *editor.Editor, g: *game.Game, y: *i32, owner: anytype, comptime rows: []const Knob, live: bool) void {
    inline for (rows) |k| {
        knobRow(ed, g, y.*, owner, k, live);
        y.* += editor.ROW_STEP;
    }
}

fn choiceRow(ed: *editor.Editor, g: *game.Game, y: *i32, comptime U: type, v: *U, comptime c: Choice, which: editor.Which) void {
    rowLabel(g, y.*, c.label);
    var tag = std.meta.activeTag(v.*);
    stepChoice(ed, g, y.*, std.meta.Tag(U), &tag, c.tip, true);
    editor.retag(U, v, tag);
    const slot = valueSlot(y.*, 0, 1);
    const value = valueRect(slot);
    const h = editor.hot(ed, value, true, false, "Every choice; " ++ c.tip);
    if (h.hot) rl.drawRectangleLinesEx(value, 1, HOVER);
    if (h.hit) {
        ed.drop();
        ed.popup = .{ .slot = value, .which = which };
        ed.fresh = true;
    }
    y.* += editor.ROW_STEP;
}

fn drawMakeup(ed: *editor.Editor, g: *game.Game, y: i32, m: *pack.Makeup, droppable: bool) bool {
    var buf: [8]u8 = undefined;
    const weight = stepper(ed, g, editor.row(editor.PAD, y, editor.WEIGHT_SPAN), num(&buf, "x{d}", m.weight), .{
        .{ .tip = "Drawn less often against the others", .live = m.weight > pack.WEIGHT_MIN },
        .{ .tip = "Drawn more often against the others", .live = m.weight < pack.WEIGHT_MAX },
    });
    bump(u8, &m.weight, weight);
    var x = editor.PAD + editor.MEMBERS_X;
    for (0..pack.MAKEUP_MAX) |i| {
        const r = editor.row(x, y, editor.MEMBER_W);
        x += editor.MEMBER_W + editor.MEMBER_GAP;
        if (i >= m.n) continue;
        const h = editor.hot(ed, r, true, false, if (i == 0) "The lead: " ++ Desk.PAINT_CAPTION ++ " for the next foe" else "A member: " ++ Desk.PAINT_CAPTION ++ " for the next foe");
        editor.plate(r, false, h.hot);
        const l = look.body(m.kind[i]);
        const at = raster.middleAt(r);
        g.face.glyph(l.ch, at.x, at.y, editor.TEXT, l.fg);
        if (h.hit) m.turn(i);
    }
    var dropped = false;
    for (MAKEUP_TOOLS, 0..) |t, i| {
        const r = editor.row(editor.PAD + editor.MAKEUP_TOOLS_X + @as(i32, @intCast(i)) * editor.STEP_PITCH, y, editor.STEP_W);
        const live = switch (t) {
            .grow => m.canGrow(),
            .shrink => m.canShrink(),
            .drop => droppable,
        };
        if (!editor.button(ed, g, r, t.label(), false, live, t.tip())) continue;
        switch (t) {
            .grow => _ = m.grow(),
            .shrink => _ = m.shrink(),
            .drop => dropped = true,
        }
    }
    return dropped;
}

const DROP = "x";

const MakeupTool = enum {
    grow,
    shrink,
    drop,

    fn label(t: MakeupTool) [:0]const u8 {
        return switch (t) {
            .grow => "+",
            .shrink => "-",
            .drop => DROP,
        };
    }

    fn tip(t: MakeupTool) [:0]const u8 {
        return switch (t) {
            .grow => "One more in the pack",
            .shrink => "One fewer in the pack",
            .drop => "Delete this makeup; the last one stays",
        };
    }
};

pub const MAKEUP_TOOLS = std.enums.values(MakeupTool);

pub fn rowLabel(g: *game.Game, y: i32, s: [:0]const u8) void {
    editor.textFace(g).draw(s, editor.PAD, y + editor.TEXT_DY, editor.TEXT, look.TEXT);
}

fn num(buf: []u8, comptime fmt: []const u8, v: anytype) [:0]const u8 {
    return std.fmt.bufPrintZ(buf, fmt, .{v}) catch "";
}

const Knob = struct {
    field: [:0]const u8,
    label: ?[:0]const u8 = null,
    tips: []const [:0]const u8,
    unit: i32 = 1,
    fmt: []const u8 = "{d}",

    fn caption(comptime k: Knob) [:0]const u8 {
        return k.label orelse comptime menu.capital(k.field);
    }
};

const PERCENT_FMT = "{d}%";
const TORCH_STEP: i32 = 10;
const DECAY_ROW = Knob{ .field = "decay", .tips = &.{"Of the walls, how many have fallen to rubble"}, .fmt = PERCENT_FMT };
const COUNT_ROW = Knob{ .field = "count", .tips = &.{"How many"} };
const COUNT_MOST_ROW = Knob{ .field = "count", .tips = &.{"How many, at most"} };
const WIDTH_ROW = Knob{ .field = "width", .tips = &.{"Cells across"} };
const LITTER_ROW = Knob{ .field = "litter", .tips = &.{"Lone boulders, a thousandth of the open grass each"} };
const DECOR_ROW = Knob{ .field = "decor", .tips = &.{ "Tiny shrubs a cell at a time, a thousandth of the open grass each", "Tall grass in patches, a thousandth of the open grass each", "Shrooms a cell at a time, a thousandth of the open grass each" } };
const GRASS_ROWS = [_]Knob{ LITTER_ROW, DECOR_ROW };
const COURSE_ROW = Knob{ .field = "course", .tips = &.{listing(carve.Course, 3, "Across, down, or either")} };

fn listing(comptime T: type, comptime n: usize, comptime tip: [:0]const u8) [:0]const u8 {
    if (std.meta.fields(T).len != n) @compileError(@typeName(T) ++ " has a member its tip does not name");
    return tip;
}

const ROOMS_ROWS = [_]Knob{
    .{ .field = "size", .tips = &.{ "Width of the box the rooms fall in, centred on the map", "Height of the box the rooms fall in, centred on the map" } },
    .{ .field = "rooms", .tips = &.{"The most rooms it rolls"} },
    .{ .field = "room_w", .label = "Room W", .tips = &.{ "The narrowest a room is rolled", "The widest a room is rolled" } },
    .{ .field = "room_h", .label = "Room H", .tips = &.{ "The shortest a room is rolled", "The tallest a room is rolled" } },
    .{ .field = "torches", .tips = &.{"Of the rooms, how many hang a torch"}, .unit = TORCH_STEP, .fmt = PERCENT_FMT },
    .{ .field = "barrels", .tips = &.{"The most barrels one room stacks"} },
};

const WILDS_ROWS = [_]Knob{
    .{ .field = "loops", .tips = &.{"Side branches to try reconnecting to another path"}, .fmt = PERCENT_FMT },
    .{ .field = "rewards", .tips = &.{"Chests in deep branches and sheltered spots, with scattered barrels for small gold rewards"} },
    .{ .field = "thicket", .tips = &.{"Of the ground, how much is sown with shrub before it is smoothed"}, .fmt = PERCENT_FMT },
    .{ .field = "smooth", .tips = &.{"Smoothing passes: more, rounder thickets and wider glades"} },
    .{ .field = "strays", .tips = &.{"Lone shrubs, a thousandth of the open grass each"} },
} ++ GRASS_ROWS;

const OPEN_ROWS = [_]Knob{
    .{ .field = "ground", .tips = &.{"The open ground, edge to edge"} },
    .{ .field = "edge", .tips = &.{"What rings the map and seals it"} },
} ++ GRASS_ROWS;

const CAVES_ROWS = [_]Knob{
    .{ .field = "fill", .tips = &.{"Of the ground, how much is sown with rock before it is smoothed"}, .fmt = PERCENT_FMT },
    .{ .field = "smooth", .tips = &.{"Smoothing passes: more, rounder caves"} },
    .{ .field = "spires", .tips = &.{"Lone rock spires, a thousandth of the open floor each"} },
};

const CAVERN_ROWS = [_]Knob{
    .{ .field = "chambers", .tips = &.{"Round chambers it digs, at most"} },
    .{ .field = "radius", .tips = &.{ "The smallest chamber's radius", "The largest chamber's radius" } },
    .{ .field = "fray", .tips = &.{"How much noise frays a chamber's edge"}, .fmt = PERCENT_FMT },
};

const STRATA_ROWS = [_]Knob{
    .{ .field = "sectors", .tips = &.{"Sectors across and down the map is cut into"} },
    .{ .field = "seeds", .tips = &.{"Deep points dropped in each sector, at most"} },
    .{ .field = "blur", .tips = &.{"Blur passes: more, rounder and wider pockets"} },
};

const LABYRINTH_ROWS = [_]Knob{
    .{ .field = "style", .tips = &.{listing(labyrinth.Style, 3, "Built walls, rock, or a hedge maze")} },
    .{ .field = "chamber", .tips = &.{"Half-height of an open chamber at the heart, half again as wide; 0 for none"} },
    .{ .field = "braid", .tips = &.{"Of the dead ends, how many are knocked through into loops"}, .fmt = PERCENT_FMT },
};

const HALL_ROWS = [_]Knob{
    .{ .field = "style", .tips = &.{listing(hall.Style, 4, "Bare, pillared, grave alcoves, or a grove of plants")} },
    .{ .field = "margin", .tips = &.{"Wall between the hall and the map's edge"} },
};

const MAZE_ROWS = [_]Knob{
    .{ .field = "style", .tips = &.{menu.capital(menu.joined(std.meta.fieldNames(maze.Style), .@"or"))} },
    .{ .field = "rooms", .tips = &.{"Rooms it sets, at most"} },
    .{ .field = "size", .tips = &.{"Cells on a room's side"} },
    .{ .field = "merge", .tips = &.{"A thousandth: how often a room is joined to each one already beside it"} },
};

const TOPOLOGY_ROWS = [_]Knob{
    .{ .field = "layout", .tips = &.{"The shape of its graph of spots"} },
    .{ .field = "filler", .tips = &.{"What fills between the paths"} },
    .{ .field = "ground", .tips = &.{"The paths' and clearings' ground"} },
    .{ .field = "clearing", .tips = &.{"A spot's clearing, half-width"} },
    .{ .field = "path", .tips = &.{"A path's width"} },
    .{ .field = "sides", .tips = &.{"Side paths off to dead-end clearings"} },
} ++ GRASS_ROWS;

const ZERO_TO_PERCENT = std.fmt.comptimePrint("0 to {d}", .{mathx.PERCENT});

const TERRAIN_ROWS = [_]Knob{
    .{ .field = "height", .tips = &.{ "Lowest elevation, " ++ ZERO_TO_PERCENT ++ std.fmt.comptimePrint("; under {d} is sea", .{terrain.SEA}), std.fmt.comptimePrint("Highest elevation; {d} and over is mountain", .{terrain.MOUNTAIN}) } },
    .{ .field = "rain", .tips = &.{ "Driest, " ++ ZERO_TO_PERCENT, "Wettest" } },
    .{ .field = "drain", .label = "Drainage", .tips = &.{ "Least drained, " ++ ZERO_TO_PERCENT, "Best drained" } },
    .{ .field = "heat", .tips = &.{ "Coldest, " ++ ZERO_TO_PERCENT ++ std.fmt.comptimePrint("; {d} and under is tundra or glacier", .{terrain.FROST}), "Hottest" } },
    .{ .field = "scale", .tips = &.{"Cells across a field's features"} },
    .{ .field = "rivers", .tips = &.{"Rivers running downhill from the heights"} },
} ++ GRASS_ROWS;

const KEEP_ROWS = [_]Knob{
    .{ .field = "size", .tips = &.{ "The curtain wall's width", "The curtain wall's height" } },
    .{ .field = "towers", .tips = &.{"A corner tower's half-width; 0 for none"} },
    .{ .field = "moat", .tips = &.{"The moat's width; 0 for none"} },
    .{ .field = "yard", .tips = &.{"The courtyard's ground"} },
    .{ .field = "outside", .tips = &.{"The ground outside the walls"} },
    .{ .field = "torches", .tips = &.{"Of the keep's top walls, how many hang a torch"}, .fmt = PERCENT_FMT },
    .{ .field = "barrels", .tips = &.{"Barrels in the keep, at most"} },
};

const TOWN_ROWS = [_]Knob{
    .{ .field = "wall", .tips = &.{listing(town.Wall, 3, "None, a stone wall or a fence round it")} },
    .{ .field = "block", .tips = &.{"A block's side between streets"} },
    .{ .field = "street", .tips = &.{"A street's width"} },
    .{ .field = "houses", .tips = &.{"Of each block's lots, how many are built on"}, .fmt = PERCENT_FMT },
    .{ .field = "canals", .tips = &.{"Of the streets, how many are canals"}, .fmt = PERCENT_FMT },
    .{ .field = "ground", .label = "Streets", .tips = &.{"The streets' ground"} },
    .{ .field = "outside", .tips = &.{"The ground round the town"} },
};

const DUNES_ROWS = [_]Knob{
    .{ .field = "ground", .tips = &.{"The open ground"} },
    .{ .field = "ridges", .tips = &.{"How wide a crest of the noise stands as ridge"} },
    .{ .field = "mesas", .tips = &.{"More stands as mesa, the highest ground first"}, .fmt = PERCENT_FMT },
    .{ .field = "scale", .tips = &.{"Cells across a dune"} },
};

const SITE_ROWS = [_]Knob{
    .{ .field = "template", .tips = &.{listing(site.Template, 4, "Huts, compound, pillars, or any one per section")} },
    DECAY_ROW,
    .{ .field = "ground", .tips = &.{"The ground between and round the buildings"} },
};

pub fn rowsOf(comptime a: atlas.Algo) []const Knob {
    return switch (a) {
        .rooms => &ROOMS_ROWS,
        .open => &OPEN_ROWS,
        .wilds => &WILDS_ROWS,
        .caves => &CAVES_ROWS,
        .cavern => &CAVERN_ROWS,
        .strata => &STRATA_ROWS,
        .labyrinth => &LABYRINTH_ROWS,
        .hall => &HALL_ROWS,
        .maze => &MAZE_ROWS,
        .topology => &TOPOLOGY_ROWS,
        .terrain => &TERRAIN_ROWS,
        .keep => &KEEP_ROWS,
        .town => &TOWN_ROWS,
        .dunes => &DUNES_ROWS,
        .site => &SITE_ROWS,
    };
}

const RIVER_ROWS = [_]Knob{
    .{ .field = "fill", .tips = &.{"What it runs with: water, lava, a chasm; rock makes a cliff"} },
    WIDTH_ROW,
    .{ .field = "bank", .tips = &.{"What lines it either side"} },
    COURSE_ROW,
    COUNT_ROW,
    .{ .field = "fords", .tips = &.{"Crossings laid over it: shallows, a bridge, or a gap"} },
};

const LAKE_ROWS = [_]Knob{
    .{ .field = "fill", .tips = &.{"Water, lava, rock for a mesa, a chasm for a pit"} },
    COUNT_MOST_ROW,
    .{ .field = "size", .tips = &.{"The biggest one's half-width"} },
    .{ .field = "ring", .tips = &.{"What rings each"} },
    .{ .field = "island", .tips = &.{"Of them, how many keep an island at their heart"}, .fmt = PERCENT_FMT },
};

const ROAD_ROWS = [_]Knob{
    .{ .field = "paving", .tips = &.{"What it is laid with"} },
    WIDTH_ROW,
    COURSE_ROW,
    COUNT_ROW,
    .{ .field = "wander", .tips = &.{"How much it bends, of a river's bending"}, .fmt = PERCENT_FMT },
};

const SCATTER_ROWS = [_]Knob{
    .{ .field = "tile", .tips = &.{"What it lays"} },
    .{ .field = "on", .tips = &.{"What it lays it on"} },
    .{ .field = "amount", .tips = &.{std.fmt.comptimePrint("A thousandth of those cells; {d} lays it on all of them", .{scatter.AMOUNT_MAX})} },
    .{ .field = "clump", .tips = &.{"Clumps this many cells across; 0 lays it a cell at a time"} },
    .{ .field = "water_range", .label = "Near water", .tips = &.{"Within this many cells of water or shallows; 0 allows any distance"} },
};

const BORDER_ROWS = [_]Knob{
    .{ .field = "tile", .tips = &.{"What rings the map"} },
    .{ .field = "width", .tips = &.{"Cells deep, at least"} },
    .{ .field = "rough", .tips = &.{"Cells more it frays inward, at most"} },
};

const BUILDINGS_ROWS = [_]Knob{
    COUNT_MOST_ROW,
    .{ .field = "size", .tips = &.{ "The shortest side, walls and all", "The longest side" } },
    DECAY_ROW,
    .{ .field = "walls", .tips = &.{"What they are walled with"} },
    .{ .field = "floor", .tips = &.{"What they are floored with"} },
    .{ .field = "barrels", .tips = &.{"The most barrels one stacks"} },
    .{ .field = "torches", .tips = &.{"Of them, how many hang a torch"}, .fmt = PERCENT_FMT },
};

const FARMS_ROWS = [_]Knob{
    .{ .field = "count", .tips = &.{"Fields, at most"} },
    .{ .field = "size", .tips = &.{ "The shortest side, fence and all", "The longest side" } },
    .{ .field = "crop", .tips = &.{"What grows in the rows"} },
    .{ .field = "furrow", .tips = &.{"What lies between the rows"} },
    .{ .field = "fence", .tips = &.{"What fences each field"} },
};

const SETPIECE_ROWS = [_]Knob{
    .{ .field = "piece", .tips = &.{"The hand-drawn piece it stamps"} },
    COUNT_MOST_ROW,
    .{ .field = "apart", .tips = &.{"Cells of margin round each"} },
};

const COAST_ROWS = [_]Knob{
    .{ .field = "side", .tips = &.{"The edge the sea lies along"} },
    .{ .field = "sea", .tips = &.{"Cells of deep water in from the edge"} },
    .{ .field = "shore", .tips = &.{"Cells of shallows past the deep water"} },
    .{ .field = "beach", .tips = &.{"Cells of sand past the shallows"} },
    .{ .field = "rough", .tips = &.{"Cells each line wanders either way, at most"} },
};

fn featureRowsOf(comptime k: atlas.Kind) []const Knob {
    return switch (k) {
        .river => &RIVER_ROWS,
        .lake => &LAKE_ROWS,
        .road => &ROAD_ROWS,
        .scatter => &SCATTER_ROWS,
        .border => &BORDER_ROWS,
        .buildings => &BUILDINGS_ROWS,
        .farms => &FARMS_ROWS,
        .setpiece => &SETPIECE_ROWS,
        .coast => &COAST_ROWS,
    };
}

const Choice = struct { label: [:0]const u8, tip: [:0]const u8 };
const ALGO_CHOICE = Choice{ .label = "Algorithm", .tip = "The base its floor is rolled from; changing it starts that base afresh" };
const FEATURE_CHOICE = Choice{ .label = "Feature", .tip = "What this feature lays over the base; changing it starts that feature afresh" };
const ADD_FEATURE_TIP = "Lay another feature over the base: " ++ menu.joined(std.meta.fieldNames(atlas.Kind), .@"or");

const SKY_ROWS = [_]Knob{
    .{ .field = "light", .tips = &.{listing(climate.Light, 2, "How its daylight looks: clear, or a bleak overcast; shown only open to the sky")} },
    .{ .field = "weather", .tips = &.{listing(climate.Weather, 2, "What falls from its sky: nothing, or a soft drizzle; shown only open to the sky")} },
};

pub const FOE_ROWS = [_]Knob{
    .{ .field = "packs", .tips = &.{"How many packs it places"} },
    .{ .field = "few", .label = "At least", .tips = &.{"Each foe any makeup holds has this many at least, while packs last"} },
    .{ .field = "reach", .tips = &.{"Cells from a pack's lead to the rest of it, at most"} },
    .{ .field = "gap", .tips = &.{"Cells from where the hero arrives to every foe, at least"} },
    .{ .field = "apart", .tips = &.{"Cells from one pack to every other, at least; 0 lets them crowd"} },
};

pub const ADD_PROCGEN_TIP = "A node the " ++ @tagName((atlas.Procgen{}).floor) ++ " generator rolls round its doors, anew each run";
const ADD_MAKEUP_TIP = "Another pack it may roll, a lone " ++ actor.row(pack.FIRST).name ++ " to begin";
const SHIFT_TIP = std.fmt.comptimePrint(" ({s} steps {d})", .{ Desk.SHIFT_CAPTION, editor.SHIFT_STEP });

comptime {
    @setEvalBranchQuota(1_000_000);
    for (std.enums.values(atlas.Algo)) |a| covers(@FieldType(atlas.Floor, @tagName(a)), rowsOf(a), atlas_text.floorKnobs(a));
    for (std.enums.values(atlas.Kind)) |k| covers(@FieldType(atlas.Feature, @tagName(k)), featureRowsOf(k), atlas_text.featureKnobs(k));
    covers(@FieldType(atlas.Procgen, "foes"), &FOE_ROWS, atlas_text.FOE_KNOBS);
    covers(@FieldType(atlas.Procgen, "sky"), &SKY_ROWS, atlas_text.SKY_KNOBS);
}

fn covers(comptime T: type, comptime rows: []const Knob, comptime knobs_: []const []const u8) void {
    @setEvalBranchQuota(100_000);
    if (rows.len != knobs_.len) @compileError("a generator row is for no knob");
    for (knobs_) |name| {
        const r = rowNamed(rows, name) orelse @compileError(name ++ " has no row on the generator");
        const K = @FieldType(T, name);
        if (r.tips.len != atlas_text.knobNumbers(K)) @compileError(name ++ " wants a tip for each number in it");
        if (@typeInfo(K) == .@"struct" and K != mathx.P) {
            for (std.meta.fieldNames(K), r.tips) |part, tip| {
                var spoken = part[0..part.len].*;
                std.mem.replaceScalar(u8, &spoken, '_', ' ');
                if (std.ascii.indexOfIgnoreCase(tip, &spoken) == null) @compileError(name ++ "." ++ part ++ " has another's tip");
            }
        }
    }
}

pub fn rowNamed(comptime rows: []const Knob, comptime field: []const u8) ?Knob {
    for (rows) |r| {
        if (std.mem.eql(u8, r.field, field)) return r;
    }
    return null;
}

fn knobRow(ed: *editor.Editor, g: *game.Game, y: i32, owner: anytype, comptime k: Knob, live: bool) void {
    if (panel.clipped(ed, y)) return;
    rowLabel(g, y, comptime k.caption());
    const v = &@field(owner.*, k.field);
    const T = @TypeOf(v.*);
    const n = comptime atlas_text.knobNumbers(T);
    switch (@typeInfo(T)) {
        .@"enum" => stepChoice(ed, g, y, T, v, k.tips[0], live),
        .int, .array, .@"struct" => inline for (0..n) |i| {
            const reach = [2]bool{ live and moves(owner, k, i, -1), live and moves(owner, k, i, 1) };
            stepNumber(ed, g, y, i, n, numberOf(owner, k, i), k, reach);
        },
        else => @compileError(@typeName(T) ++ " is no knob"),
    }
}

fn Number(comptime T: type, comptime i: usize) type {
    return switch (@typeInfo(T)) {
        .int => T,
        .array => |a| a.child,
        .@"struct" => |s| s.fields[i].type,
        else => @compileError(@typeName(T) ++ " is no knob"),
    };
}

fn numberOf(owner: anytype, comptime k: Knob, comptime i: usize) *Number(@TypeOf(@field(owner.*, k.field)), i) {
    const v = &@field(owner.*, k.field);
    return switch (@typeInfo(@TypeOf(v.*))) {
        .int => v,
        .array => &v[i],
        .@"struct" => |s| &@field(v.*, s.fields[i].name),
        else => unreachable,
    };
}

pub fn moves(owner: anytype, comptime k: Knob, comptime i: usize, by: i32) bool {
    var o = owner.*;
    const p = numberOf(&o, k, i);
    bump(@TypeOf(p.*), p, k.unit * by);
    return !std.meta.eql(carve.fitted(o), owner.*);
}

fn stepNumber(ed: *editor.Editor, g: *game.Game, y: i32, comptime i: usize, n: usize, v: anytype, comptime k: Knob, reach: [2]bool) void {
    var buf: [16]u8 = undefined;
    const tip = k.tips[i] ++ SHIFT_TIP;
    bump(@TypeOf(v.*), v, k.unit * stepper(ed, g, valueSlot(y, i, n), num(&buf, k.fmt, v.*), .{ .{ .tip = tip, .live = reach[0] }, .{ .tip = tip, .live = reach[1] } }));
}

fn stepChoice(ed: *editor.Editor, g: *game.Game, y: i32, comptime T: type, v: *T, tip: [:0]const u8, live: bool) void {
    const by = stepper(ed, g, valueSlot(y, 0, 1), @tagName(v.*), .{ .{ .tip = tip, .live = live }, .{ .tip = tip, .live = live } });
    v.* = cycle(T, v.*, by);
}

fn valueSlot(y: i32, k: usize, n: usize) rl.Rectangle {
    return editor.slotOf(editor.PAD + editor.LABEL_W, editor.INNER_W - editor.LABEL_W, y, k, n);
}

fn cycle(comptime T: type, v: T, by: i32) T {
    return mathx.stepIn(T, comptime std.enums.values(T), v, std.math.sign(by), null);
}

const Step = struct { tip: [:0]const u8, live: bool = true };

pub fn stepper(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, value: []const u8, steps: [2]Step) i32 {
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const w: i32 = @intFromFloat(r.width);
    var by: i32 = 0;
    if (editor.button(ed, g, editor.row(x, y, editor.STEP_W), "-", false, steps[0].live, steps[0].tip)) by = -1;
    if (editor.button(ed, g, editor.row(x + w - editor.STEP_W, y, editor.STEP_W), "+", false, steps[1].live, steps[1].tip)) by = 1;
    var fit_buf: [editor.LINE]u8 = undefined;
    const shown = editor.textFace(g).fit(&fit_buf, value, editor.TEXT, @intFromFloat(valueRect(r).width), false);
    editor.textFace(g).drawMid(shown, x + @divTrunc(w, 2), y + editor.TEXT_DY, editor.TEXT, look.TEXT);
    return if (ed.desk.shift) by * editor.SHIFT_STEP else by;
}

fn valueRect(r: rl.Rectangle) rl.Rectangle {
    const pitch: f32 = @floatFromInt(editor.STEP_PITCH);
    return .{ .x = r.x + pitch, .y = r.y, .width = r.width - 2 * pitch, .height = r.height };
}

/// The caller fits the result to its application-specific range.
fn bump(comptime T: type, v: *T, by: i32) void {
    const at: i64 = @intCast(v.*);
    const hi: i64 = @min(std.math.maxInt(T), std.math.maxInt(i64));
    v.* = @intCast(std.math.clamp(at + by, 0, hi));
}
