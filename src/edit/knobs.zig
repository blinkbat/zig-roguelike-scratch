const widgets = @import("widgets.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const atlas = @import("../map/atlas.zig");
const atlas_text = @import("../map/atlas_text.zig");
const grid = @import("../map/grid.zig");
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
const menu = @import("../ui/menu.zig");
const wording = @import("../core/wording.zig");
const game = @import("../game.zig");
const panel = @import("panel.zig");
const editor = @import("editor.zig");
const Desk = input.Desk;

/// In the node's panel, scrolled within `box`.
pub fn drawGenerator(ed: *editor.Editor, g: *game.Game, box: rl.Rectangle, pg: *atlas.Procgen) void {
    const was = pg.*;
    const fo = &pg.foes;
    const col = column(g);
    var y = panel.beginPane(ed, .inspector, box);
    section(g, &y, "Base");
    choiceRow(ed, g, &y, atlas.Floor, &pg.floor, ALGO_CHOICE, .algo);
    switch (pg.floor) {
        inline else => |*fl, t| knobRows(ed, g, &y, fl, comptime rowsOf(t), true),
    }
    y += widgets.BLOCK_GAP;
    section(g, &y, "Features");
    var drop_feature: ?usize = null;
    for (pg.featuresMut(), 0..) |*ft, i| {
        if (editor.button(ed, g, widgets.row(col.left() + editor.LABEL_W - widgets.STEP_PITCH, y, widgets.STEP_W), widgets.DROP, false, true, "Take this feature away")) drop_feature = i;
        choiceRow(ed, g, &y, atlas.Feature, ft, FEATURE_CHOICE, .{ .feature = i });
        switch (ft.*) {
            inline else => |*fp, k| knobRows(ed, g, &y, fp, comptime featureRowsOf(k), true),
        }
        y += widgets.BLOCK_GAP;
    }
    if (drop_feature) |i| pg.dropFeature(i);
    if (editor.button(ed, g, col.row(y), "+ Feature", false, pg.feature_n < atlas.MAX_FEATURES, ADD_FEATURE_TIP)) _ = pg.addFeature(atlas.FIRST_FEATURE);
    y += widgets.ROW_H + widgets.SECTION_GAP;
    knobs(ed, g, &y, if (pg.floor.outdoor()) "Sky" else "Sky (this base is under a roof)", &pg.sky, &SKY_ROWS, pg.floor.outdoor());
    y += widgets.BLOCK_GAP;
    knobs(ed, g, &y, "Foes", fo, &FOE_ROWS, true);
    y += widgets.BLOCK_GAP;
    knobs(ed, g, &y, "Allies", &pg.post, &POST_ROWS, true);
    y += widgets.BLOCK_GAP;
    knobs(ed, g, &y, "Night raids", &pg.raid, &RAID_ROWS, true);
    y += widgets.BLOCK_GAP;
    section(g, &y, "Makeups");
    var drop: ?usize = null;
    for (fo.makeup[0..fo.makeup_n], 0..) |*m, i| {
        if (drawMakeup(ed, g, y, m, fo.canDrop())) drop = i;
        y += widgets.ROW_STEP;
    }
    if (drop) |i| _ = fo.dropMakeup(i);
    if (editor.button(ed, g, col.row(y), "+ Makeup", false, fo.canAdd(), ADD_MAKEUP_TIP)) _ = fo.addMakeup();
    panel.closePane(ed, .inspector, y + widgets.ROW_H);
    refit(ed, pg, was);
}

pub fn choiceRows(ed: *editor.Editor, g: *game.Game, box: rl.Rectangle, which: editor.Which) void {
    const pg = ed.rolled() orelse {
        ed.popup = null;
        return;
    };
    const was = pg.*;
    switch (which) {
        .feature => |i| if (i < pg.feature_n) popupRows(ed, g, atlas.Feature, &pg.feature[i], box, which),
        .algo, .node, .file => popupRows(ed, g, atlas.Floor, &pg.floor, box, which),
    }
    if (ed.popup == null) refit(ed, pg, was);
}

fn popupRows(ed: *editor.Editor, g: *game.Game, comptime U: type, v: *U, box: rl.Rectangle, which: editor.Which) void {
    for (std.enums.values(std.meta.Tag(U)), 0..) |t, k| {
        if (editor.modalButton(ed, g, editor.popupRow(box, which, k), @tagName(t), t == std.meta.activeTag(v.*), true, null)) {
            retag(U, v, t);
            ed.popup = null;
        }
    }
}

fn retag(comptime U: type, v: *U, tag: std.meta.Tag(U)) void {
    if (tag != std.meta.activeTag(v.*)) v.* = U.of(tag);
}

fn refit(ed: *editor.Editor, pg: *atlas.Procgen, was: atlas.Procgen) void {
    pg.* = pg.fit();
    if (!std.meta.eql(was, pg.*)) ed.changed();
}

/// The generator's rows stand in the node's panel.
fn column(g: *const game.Game) widgets.Column {
    return editor.Editor.inspector(g);
}

fn section(g: *game.Game, y: *i32, title: [:0]const u8) void {
    widgets.heading(&g.face, title, column(g).left(), y.* + widgets.GAP);
    y.* += SECTION_H;
}

const SECTION_H: i32 = widgets.HEADING_H + 2 * widgets.GAP;

fn knobs(ed: *editor.Editor, g: *game.Game, y: *i32, title: [:0]const u8, owner: anytype, comptime rows: []const Knob, live: bool) void {
    section(g, y, title);
    knobRows(ed, g, y, owner, rows, live);
}

fn knobRows(ed: *editor.Editor, g: *game.Game, y: *i32, owner: anytype, comptime rows: []const Knob, live: bool) void {
    inline for (rows) |k| {
        if (comptime k.parts.len > 0) {
            section(g, y, k.caption());
            inline for (k.parts, 0..) |part, i| {
                if (!panel.clipped(ed, y.*)) {
                    panel.rowLabel(g, column(g), y.*, comptime wording.spoken(part), widgets.TEXT);
                    stepNumber(ed, g, y.*, owner, k, i, 1, live);
                }
                y.* += widgets.ROW_STEP;
            }
        } else {
            knobRow(ed, g, y.*, owner, k, live);
            y.* += widgets.ROW_STEP;
        }
    }
}

fn choiceRow(ed: *editor.Editor, g: *game.Game, y: *i32, comptime U: type, v: *U, comptime c: Choice, which: editor.Which) void {
    panel.rowLabel(g, column(g), y.*, c.label, widgets.TEXT);
    var tag = std.meta.activeTag(v.*);
    stepChoice(ed, g, y.*, std.meta.Tag(U), &tag, c.tip, true);
    retag(U, v, tag);
    const slot = valueSlot(g, y.*, 0, 1);
    const value = widgets.stepValue(slot);
    if (valueHit(ed, value, "Every choice; " ++ c.tip)) editor.openPopup(ed, value, which, @intFromEnum(tag), g.screen.y);
    y.* += widgets.ROW_STEP;
}

fn valueHit(ed: *editor.Editor, value: rl.Rectangle, tip: [:0]const u8) bool {
    const h = widgets.hot(ed.controls(), value, true, false, tip);
    widgets.hoverEdge(value, h.hot);
    return h.hit;
}

const DrawStep = struct { fmt: []const u8, tips: [2][:0]const u8, min: u8, max: u8 };
const DRAW_STEPS = std.EnumArray(std.meta.Tag(pack.Draw), DrawStep).init(.{
    .weight = .{ .fmt = "x{d}", .tips = .{ "Drawn less often against the others", "Drawn more often against the others" }, .min = pack.WEIGHT_MIN, .max = pack.WEIGHT_MAX },
    .count = .{ .fmt = "={d}", .tips = .{ "One fewer of these packs", "One more of these packs" }, .min = pack.COUNT_MIN, .max = pack.COUNT_MAX },
});

fn drawMakeup(ed: *editor.Editor, g: *game.Game, y: i32, m: *pack.Makeup, droppable: bool) bool {
    var buf: [8]u8 = undefined;
    const x = column(g).left();
    const span = widgets.row(x, y, DRAW_SPAN);
    switch (m.draw) {
        inline else => |*n, tag| {
            const s = comptime DRAW_STEPS.get(tag);
            bump(u8, n, stepper(ed, g, span, num(&buf, s.fmt, n.*), .{
                .{ .tip = s.tips[0], .live = n.* > s.min },
                .{ .tip = s.tips[1], .live = n.* < s.max },
            }));
        },
    }
    const flip_tip: [:0]const u8 = switch (m.draw) {
        .weight => "Drawn by weight; " ++ Desk.PAINT_CAPTION ++ " for an exact count of packs",
        .count => "Exactly this many packs; " ++ Desk.PAINT_CAPTION ++ " to draw by weight",
    };
    if (valueHit(ed, widgets.stepValue(span), flip_tip)) m.draw = m.draw.flipped();
    var members = widgets.Lay{ .x = x + MEMBERS_X, .y = y, .gap = MEMBER_GAP };
    for (0..pack.MAKEUP_MAX) |i| {
        const r = members.take(MEMBER_W);
        if (i >= m.n) continue;
        const h = widgets.hot(ed.controls(), r, true, false, if (i == 0) "The lead: " ++ Desk.PAINT_CAPTION ++ " for the next foe" else "A member: " ++ Desk.PAINT_CAPTION ++ " for the next foe");
        widgets.plate(r, false, h.hot);
        const l = look.body(m.kind[i]);
        const at = raster.middleAt(r);
        g.face.glyph(l.ch, at.x, at.y, widgets.TEXT, l.fg);
        if (h.hit) m.turn(i);
    }
    var dropped = false;
    var tools = widgets.Lay{ .x = x + MAKEUP_TOOLS_X, .y = y };
    for (MAKEUP_TOOLS) |t| {
        const r = tools.take(widgets.STEP_W);
        const live = switch (t) {
            .where => true,
            .grow => m.canGrow(),
            .shrink => m.canShrink(),
            .drop => droppable,
        };
        const where = Where.of(m);
        if (!editor.button(ed, g, r, t.label(where), t == .where and where != .anywhere, live, t.tip(where))) continue;
        switch (t) {
            .where => where.next().set(m),
            .grow => _ = m.grow(),
            .shrink => _ = m.shrink(),
            .drop => dropped = true,
        }
    }
    return dropped;
}

/// Where a makeup's lead stands: by a door, or in one of `pack.Lair`.
const Where = enum {
    anywhere,
    exit,
    nook,
    pond,
    hearth,

    fn of(m: *const pack.Makeup) Where {
        if (m.exit) return .exit;
        return switch (m.lair) {
            inline else => |l| @field(Where, @tagName(l)),
        };
    }

    fn set(w: Where, m: *pack.Makeup) void {
        m.exit = w == .exit;
        m.lair = switch (w) {
            .exit => .anywhere,
            inline else => |l| @field(pack.Lair, @tagName(l)),
        };
    }

    fn next(w: Where) Where {
        return mathx.cycle(Where, w, 1);
    }

    fn label(w: Where) [:0]const u8 {
        return switch (w) {
            .anywhere => "A",
            .exit => "E",
            .nook => "N",
            .pond => "P",
            .hearth => "F",
        };
    }

    fn phrase(w: Where) [:0]const u8 {
        return switch (w) {
            .anywhere => "anywhere",
            .exit => "by a door",
            .nook => "at a winding path's end",
            .pond => "in or by a pond",
            .hearth => "by a campfire",
        };
    }

    fn tip(w: Where) [:0]const u8 {
        return switch (w) {
            inline else => |x| comptime "The lead stands " ++ x.phrase() ++ "; " ++ Desk.PAINT_CAPTION ++ " for " ++ x.next().phrase(),
        };
    }
};

const MakeupTool = enum {
    where,
    grow,
    shrink,
    drop,

    fn label(t: MakeupTool, w: Where) [:0]const u8 {
        return switch (t) {
            .where => w.label(),
            .grow => "+",
            .shrink => "-",
            .drop => widgets.DROP,
        };
    }

    fn tip(t: MakeupTool, w: Where) [:0]const u8 {
        return switch (t) {
            .where => w.tip(),
            .grow => "One more in the pack",
            .shrink => "One fewer in the pack",
            .drop => "Delete this makeup; the last one stays",
        };
    }
};

const MAKEUP_TOOLS = std.enums.values(MakeupTool);
const DRAW_W: i32 = 36;
const MEMBER_W: i32 = 24;
const MEMBER_GAP: i32 = 2;
const DRAW_SPAN: i32 = widgets.stepperW(DRAW_W);
const MEMBERS_X: i32 = DRAW_SPAN + widgets.BLOCK_GAP;
const MAKEUP_TOOLS_X: i32 = widgets.INSPECT_INNER_W - @as(i32, MAKEUP_TOOLS.len) * widgets.STEP_PITCH + widgets.GAP;

comptime {
    std.debug.assert(MEMBERS_X + @as(i32, pack.MAKEUP_MAX) * (MEMBER_W + MEMBER_GAP) <= MAKEUP_TOOLS_X);
}

fn num(buf: []u8, comptime fmt: []const u8, v: anytype) [:0]const u8 {
    return std.fmt.bufPrintZ(buf, fmt, .{v}) catch "";
}

const Knob = struct {
    field: [:0]const u8,
    label: ?[:0]const u8 = null,
    tips: []const [:0]const u8,
    parts: []const [:0]const u8 = &.{},
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
const LITTER_ROW = structRow("litter", carve.Litter, .{ .boulders = "Lone boulders, a thousandth of the open grass each" });
const DECOR_ROW = structRow("decor", carve.Decor, .{
    .tiny_shrubs = "Tiny shrubs a cell at a time, a thousandth of the open grass each",
    .tall_grass = "Tall grass in patches, a thousandth of the open grass each",
    .shrooms = "Shrooms a cell at a time, a thousandth of the open grass each",
});
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

const TEE_ROWS = [_]Knob{
    .{ .field = "bar", .tips = &.{"Rows the crossbar along the bottom is tall"} },
    .{ .field = "stem", .tips = &.{"Cells the stem rising from the camp is wide"} },
    .{ .field = "fray", .tips = &.{"Cells the T's edge wanders in or out"} },
    .{ .field = "forest", .tips = &.{"Cells of the crossbar, from the west, given to woods"} },
    .{ .field = "thicket", .tips = &.{"Of the woods' grass at the west edge, how much is shrub; it thins toward the camp"}, .fmt = PERCENT_FMT },
    .{ .field = "trees", .tips = &.{"Lone large trees, a thousandth of the woods' grass each"} },
    .{ .field = "camp", .tips = &.{"The camp's radius, where the stem meets the crossbar"} },
    .{ .field = "carts", .tips = &.{"Caravan carts in the camp, at most"} },
    .{ .field = "barrels", .tips = &.{"Barrels beside the carts, at most"} },
    .{ .field = "chests", .tips = &.{"Chests in the camp, at most"} },
    .{ .field = "river", .tips = &.{"Cells the river to the east is wide; 0 for none"} },
    .{ .field = "bank", .tips = &.{"Cells of land past the river"} },
    .{ .field = "bridge", .tips = &.{"Cells the bridge over the river is wide"} },
    .{ .field = "path", .tips = &.{"Cells the dirt paths are wide"} },
    .{ .field = "spurs", .tips = &.{"Winding trails off the T into the forest, each ending narrow or in a small glade"} },
    .{ .field = "pond", .tips = &.{"The crescent pond's radius; 0 for none"} },
    .{ .field = "pond_chests", .label = "Pond chests", .tips = &.{"Chests standing out in the pond, each waded out to"} },
    .{ .field = "camps", .label = "Goblin camps", .tips = &.{"Small goblin camps, off the roads and away from the carts"} },
} ++ GRASS_ROWS;

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
        .tee => &TEE_ROWS,
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
    .{ .field = "water_clear", .label = "Off water", .tips = &.{"None within this many cells of water or shallows; 0 allows any"} },
    .{ .field = "land_range", .label = "Near land", .tips = &.{"Within this many cells of dry ground other than what it lays on; 0 allows any distance"} },
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
    .{ .field = "light", .tips = &.{listing(climate.Light, 2, "Its daylight at the clearest: clear, or always a bleak overcast; shown only open to the sky")} },
    .{ .field = "weather", .tips = &.{listing(climate.Weather, 5, "How its sky changes: clear; a steady drizzle; coastal squalls and sea fog; thunderstorms; or long fogs. Rain dampens fire")} },
};

pub const FOE_ROWS = [_]Knob{
    .{ .field = "packs", .tips = &.{"How many packs it places"} },
    .{ .field = "few", .label = "At least", .tips = &.{"Each foe any makeup holds has this many at least, while packs last"} },
    .{ .field = "reach", .tips = &.{"Cells from a pack's lead to the rest of it, at most"} },
    .{ .field = "gap", .tips = &.{"Cells from where the hero arrives to every foe, at least"} },
    .{ .field = "apart", .tips = &.{"Cells from one pack to every other, at least; 0 lets them crowd"} },
};

const POST_ROWS = [_]Knob{
    .{ .field = "guards", .tips = &.{"Caravan guards posted beside its carts, at most"} },
};

const RAID_ROWS = [_]Knob{
    .{ .field = "raiders", .label = "Raiders", .tips = &.{"Goblins that come in each night, each at its own time between dusk and dawn, while the hero is here"} },
    .{ .field = "raid_door", .label = "From door", .tips = &.{"The door they come in by, counted from 0"} },
};

pub const ADD_PROCGEN_TIP = "A node the " ++ @tagName((atlas.Procgen{}).floor) ++ " generator rolls round its doors, anew each run";
const ADD_MAKEUP_TIP = "Another pack it may roll, a lone " ++ actor.row(pack.FIRST).name ++ " to begin";
const SHIFT_TIP = std.fmt.comptimePrint(" ({s} steps {d})", .{ Desk.SHIFT_CAPTION, widgets.SHIFT_STEP });

comptime {
    @setEvalBranchQuota(1_000_000);
    for (std.enums.values(atlas.Algo)) |a| covers(@FieldType(atlas.Floor, @tagName(a)), rowsOf(a), atlas_text.floorKnobs(a));
    for (std.enums.values(atlas.Kind)) |k| covers(@FieldType(atlas.Feature, @tagName(k)), featureRowsOf(k), atlas_text.featureKnobs(k));
    covers(@FieldType(atlas.Procgen, "foes"), &FOE_ROWS, atlas_text.FOE_KNOBS);
    covers(@FieldType(atlas.Procgen, "sky"), &SKY_ROWS, atlas_text.SKY_KNOBS);
    covers(@FieldType(atlas.Procgen, "post"), &POST_ROWS, atlas_text.POST_KNOBS);
    covers(@FieldType(atlas.Procgen, "raid"), &RAID_ROWS, atlas_text.RAID_KNOBS);
}

fn structRow(comptime field: [:0]const u8, comptime T: type, comptime tips: anytype) Knob {
    const parts = std.meta.fieldNames(T);
    if (std.meta.fields(@TypeOf(tips)).len != parts.len) @compileError(field ++ " wants a tip for each member");
    var ordered: [parts.len][:0]const u8 = undefined;
    for (parts, 0..) |part, i| ordered[i] = @field(tips, part);
    const labels = ordered;
    return .{ .field = field, .tips = &labels, .parts = parts };
}

fn covers(comptime T: type, comptime rows: []const Knob, comptime knobs_: []const []const u8) void {
    @setEvalBranchQuota(100_000);
    if (rows.len != knobs_.len) @compileError("a generator row is for no knob");
    for (knobs_) |name| {
        const r = rowNamed(rows, name) orelse @compileError(name ++ " has no row on the generator");
        const K = @FieldType(T, name);
        if (r.tips.len != atlas_text.knobNumbers(K)) @compileError(name ++ " wants a tip for each number in it");
        if (@typeInfo(K) == .@"struct" and K != mathx.P) {
            if (r.parts.len != r.tips.len) @compileError(name ++ " wants named member tips");
            for (std.meta.fieldNames(K), r.parts) |part, tip_part| {
                if (!std.mem.eql(u8, part, tip_part)) @compileError(name ++ "." ++ part ++ " has another's tip");
            }
        }
    }
}

test "structured generator tips follow fields independently of wording and declaration order" {
    const decor = comptime structRow("decor", carve.Decor, .{ .shrooms = "Fungi", .tiny_shrubs = "Small bushes", .tall_grass = "Long blades" });
    const litter = comptime structRow("litter", carve.Litter, .{ .boulders = "Loose stones" });
    comptime covers(struct { decor: carve.Decor, litter: carve.Litter }, &.{ decor, litter }, &.{ "decor", "litter" });
    try std.testing.expectEqualStrings("Small bushes", decor.tips[0]);
    try std.testing.expectEqualStrings("Long blades", decor.tips[1]);
    try std.testing.expectEqualStrings("Fungi", decor.tips[2]);
    try std.testing.expectEqualStrings("Loose stones", litter.tips[0]);
    std.debug.print("generator tips: 4 rewritten passages retain their field mapping, including reordered declarations\n", .{});
}

pub fn rowNamed(comptime rows: []const Knob, comptime field: []const u8) ?Knob {
    for (rows) |r| {
        if (std.mem.eql(u8, r.field, field)) return r;
    }
    return null;
}

fn knobRow(ed: *editor.Editor, g: *game.Game, y: i32, owner: anytype, comptime k: Knob, live: bool) void {
    if (panel.clipped(ed, y)) return;
    panel.rowLabel(g, column(g), y, comptime k.caption(), widgets.TEXT);
    const v = &@field(owner.*, k.field);
    const T = @TypeOf(v.*);
    const n = comptime atlas_text.knobNumbers(T);
    switch (@typeInfo(T)) {
        .@"enum" => stepChoice(ed, g, y, T, v, k.tips[0], live),
        .int, .array, .@"struct" => inline for (0..n) |i| stepNumber(ed, g, y, owner, k, i, n, live),
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

fn stepNumber(ed: *editor.Editor, g: *game.Game, y: i32, owner: anytype, comptime k: Knob, comptime i: usize, n: usize, live: bool) void {
    var buf: [16]u8 = undefined;
    const tip = k.tips[i] ++ SHIFT_TIP;
    const steps = [2]widgets.Step{ .{ .tip = tip, .live = live and moves(owner, k, i, -1) }, .{ .tip = tip, .live = live and moves(owner, k, i, 1) } };
    const v = numberOf(owner, k, i);
    bump(@TypeOf(v.*), v, k.unit * stepper(ed, g, valueSlot(g, y, if (k.parts.len > 0) 0 else i, n), num(&buf, k.fmt, v.*), steps));
}

fn stepChoice(ed: *editor.Editor, g: *game.Game, y: i32, comptime T: type, v: *T, tip: [:0]const u8, live: bool) void {
    const by = stepper(ed, g, valueSlot(g, y, 0, 1), @tagName(v.*), .{ .{ .tip = tip, .live = live }, .{ .tip = tip, .live = live } });
    v.* = cycle(T, v.*, by);
}

fn valueSlot(g: *const game.Game, y: i32, k: usize, n: usize) rl.Rectangle {
    const col = column(g);
    return widgets.slotOf(col.left() + editor.LABEL_W, col.inner() - editor.LABEL_W, y, k, n);
}

fn cycle(comptime T: type, v: T, by: i32) T {
    if (by == 0) return v;
    const values = comptime std.enums.values(T);
    var next = mathx.stepIn(T, values, v, std.math.sign(by), null);
    while (!grid.knobbable(T, next)) next = mathx.stepIn(T, values, next, std.math.sign(by), null);
    return next;
}

test "generator tile choices skip opened containers and wide props in both directions" {
    var checked: usize = 0;
    for (std.enums.values(grid.Tile)) |tile| {
        try std.testing.expectEqual(tile, cycle(grid.Tile, tile, 0));
        for ([_]i32{ -1, 1 }) |by| {
            const next = cycle(grid.Tile, tile, by);
            try std.testing.expect(next.single());
            if (tile.single()) try std.testing.expectEqual(tile, cycle(grid.Tile, next, -by));
            checked += 1;
        }
    }
    try std.testing.expectEqual(grid.Tile.swamp_tree, cycle(grid.Tile, .chest, 1));
    try std.testing.expectEqual(grid.Tile.chest, cycle(grid.Tile, .swamp_tree, -1));
    var last = grid.Tile.wall;
    for (std.enums.values(grid.Tile)) |t| {
        if (t.single()) last = t;
    }
    try std.testing.expectEqual(grid.Tile.wall, cycle(grid.Tile, last, 1));
    std.debug.print("generator tile choices: {d} forward/back steps exclude opened containers and wide props; idle choices preserved\n", .{checked});
}

pub fn stepper(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, value: []const u8, steps: [2]widgets.Step) i32 {
    return widgets.stepper(ed.controls(), &g.face, r, value, widgets.KNOB_ARROWS, steps, ed.desk.shift);
}

/// The caller fits the result to its application-specific range.
fn bump(comptime T: type, v: *T, by: i32) void {
    const at: i64 = @intCast(v.*);
    const hi: i64 = @min(std.math.maxInt(T), std.math.maxInt(i64));
    v.* = @intCast(std.math.clamp(at + by, 0, hi));
}
