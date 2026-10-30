const std = @import("std");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const actor = @import("../play/actor.zig");
const look = @import("../gfx/look.zig");
const menu = @import("../ui/menu.zig");
const Desk = input.Desk;

pub const SHIFT_STEP: i32 = 5;
pub const TORCH_RULE = "hangs on a wall with floor below it";
pub const BARREL_RULE = "stands on " ++ @tagName(grid.BARREL_GROUND) ++ " and breaks for gold";
pub const FOE_RULE = "stands on open floor; a swimmer in water, a mimic on bare ground";
pub const FOLK_RULE = "talks; stands on open floor no foe or barrel holds";
pub const Spanned = enum { line, rect, box, select };

const START = look.body(actor.HERO);
pub const START_MARK = [_]u8{ START.ch, ' ' };

pub fn kindName(k: actor.Kind) [:0]const u8 {
    return switch (k) {
        inline else => |f| comptime menu.capital(actor.row(f).name),
    };
}

pub const Tool = union(enum) {
    paint,
    barrel,
    torch,
    foe: actor.Kind,
    folk,
    door,
    link,
    start,

    pub fn fits(tool: Tool, node: *const atlas.Node) bool {
        return !node.unrolled() or !tool.generated();
    }

    pub fn eql(a: Tool, b: Tool) bool {
        return std.meta.eql(a, b);
    }

    fn generated(tool: Tool) bool {
        return switch (tool) {
            .door, .link, .start => false,
            .paint, .barrel, .torch, .foe, .folk => true,
        };
    }

    pub fn strokes(tool: Tool) bool {
        return switch (tool) {
            .paint, .barrel => true,
            .torch, .foe, .folk, .door, .link, .start => false,
        };
    }

    pub fn broad(tool: Tool) bool {
        return tool == .paint;
    }

    pub fn look_(tool: Tool) look.Look {
        return switch (tool) {
            .paint => .{ .ch = '#', .fg = look.TEXT },
            .barrel => look.BARREL,
            .torch => look.TORCH,
            .foe => |k| look.body(k),
            .folk => look.FOLK,
            .door => look.DOOR,
            .link => .{ .ch = '=', .fg = look.DOOR.fg },
            .start => START,
        };
    }

    pub fn name(tool: Tool) [:0]const u8 {
        return switch (tool) {
            .foe => |k| kindName(k),
            inline else => |_, tag| comptime menu.named(tag),
        };
    }

    pub fn tip(tool: Tool) [:0]const u8 {
        return switch (tool) {
            .foe => "Foe: " ++ comptime rule(.{ .foe = actor.FOES[0] }),
            inline else => |_, tag| comptime blk: {
                @setEvalBranchQuota(10_000);
                const k = @unionInit(Tool, @tagName(tag), {});
                break :blk k.name() ++ ": " ++ k.rule();
            },
        };
    }

    fn rule(tool: Tool) [:0]const u8 {
        return switch (tool) {
            .paint => Desk.PAINT_CAPTION ++ " paints the palette's first tile, " ++ Desk.ERASE_CAPTION ++ " its second, in the shape picked",
            .barrel => BARREL_RULE ++ "; " ++ Desk.ERASE_CAPTION ++ " takes it away",
            .torch => TORCH_RULE,
            .foe => FOE_RULE ++ "; " ++ Desk.ERASE_CAPTION ++ " takes any foe away",
            .folk => FOLK_RULE ++ "; " ++ Desk.PAINT_CAPTION ++ " on one gives it words, " ++ Desk.ERASE_CAPTION ++ " takes it away",
            .door => "any cell of any node; a procgen node's floor is rolled round its doors each run",
            .link => Desk.PAINT_CAPTION ++ " a door, then the door it leads to on any node; " ++ Desk.ERASE_CAPTION ++ " unlinks",
            .start => "where the map begins, and " ++ Desk.PLAY_CAPTION ++ " plays from",
        };
    }
};

pub const TOOLS = blk: {
    var out: []const Tool = &.{};
    for (std.enums.values(std.meta.Tag(Tool))) |tag| {
        if (tag == .foe) {
            for (actor.FOES) |k| out = out ++ &[_]Tool{.{ .foe = k }};
        } else out = out ++ &[_]Tool{@unionInit(Tool, @tagName(tag), {})};
    }
    break :blk out[0..out.len].*;
};
pub const PALETTE_RULE = Desk.PAINT_CAPTION ++ " first ink, " ++ Desk.ERASE_CAPTION ++ " second";
const UNGENERATED = blk: {
    var names: []const []const u8 = &.{};
    for (TOOLS) |tool| {
        if (!tool.generated()) names = names ++ &[_][]const u8{@tagName(tool)};
    }
    break :blk menu.joined(names, .@"and");
};
pub const GENERATED = "A procgen node is generated; it takes only " ++ UNGENERATED ++ " (" ++ Desk.REROLL_CAPTION ++ " rolls it again)";

comptime {
    @setEvalBranchQuota(10_000);
    std.debug.assert(TOOLS.len == Desk.TOOL_KEYS.len);
    for (actor.FOES) |k| std.debug.assert(k.stocked());
}

/// How the paint tool lays its ink, in `Desk.SHAPE_KEYS`' order; a selection is any tool's.
pub const Shape = enum {
    brush,
    line,
    rect,
    box,
    fill,
    select,

    fn noun(s: Shape) [:0]const u8 {
        return switch (s) {
            .rect => "rectangle",
            inline else => |tool| @tagName(tool),
        };
    }

    pub fn tip(s: Shape) [:0]const u8 {
        return switch (s) {
            inline else => |tool| comptime menu.capital(tool.noun()) ++ ": " ++ tool.rule(),
        };
    }

    fn rule(s: Shape) [:0]const u8 {
        return switch (s) {
            .brush => "paints every cell it passes, the brush's size",
            .line => "drag from one end to the other",
            .rect => "drag corner to corner, filled",
            .box => "drag corner to corner, its edge alone",
            .fill => "the ground of one tile joined to the cell clicked",
            .select => "drag a rectangle; " ++ Desk.COPY_CAPTION ++ " copies, " ++ Desk.CUT_CAPTION ++ " cuts, " ++ Desk.DELETE_CAPTION ++ " clears it, " ++ Desk.PASTE_CAPTION ++ " pastes",
        };
    }

    pub fn dragged(s: Shape) ?Spanned {
        return switch (s) {
            inline .line, .rect, .box, .select => |tool| @field(Spanned, @tagName(tool)),
            .brush, .fill => null,
        };
    }
};

pub const SHAPES = std.enums.values(Shape);
const SHAPE_NOUNS = blk: {
    var nouns: [SHAPES.len][:0]const u8 = undefined;
    for (SHAPES, &nouns) |sh, *n| n.* = sh.noun();
    break :blk menu.joined(nouns, .@"or");
};

comptime {
    const named = std.meta.fields(@TypeOf(Desk.SHAPE_KEYS_BY));
    std.debug.assert(SHAPES.len == named.len);
    for (SHAPES, named) |s, f| std.debug.assert(std.mem.eql(u8, @tagName(s), f.name));
}

const SEP = menu.SEP;
pub const CRIB_MAP = Desk.PAINT_CAPTION ++ " place" ++ SEP ++ Desk.ERASE_CAPTION ++ " second ink or remove" ++ SEP ++ Desk.TOOLS_CAPTION ++
    " tool" ++ SEP ++ Desk.SHAPES_CAPTION ++ " shape" ++ SEP ++ Desk.PICK_CAPTION ++ " pick" ++ SEP ++ Desk.HELP_CAPTION ++ " every key";
pub const CRIB_GRAPH = Desk.PAINT_CAPTION ++ " open a node" ++ SEP ++ "drag it to move it, or a door's dot to another's to link them" ++ SEP ++
    Desk.ERASE_CAPTION ++ " on a dot unlinks" ++ SEP ++ Desk.GRAPH_CAPTION ++ " back to the map" ++ SEP ++ Desk.HELP_CAPTION ++ " every key";
const HelpSection = struct { head: [:0]const u8, column: usize = 0, lines: []const [:0]const u8 };
pub const HELP = [_]HelpSection{
    .{ .head = "PAINTING", .lines = &.{
        Desk.PAINT_CAPTION ++ " use tool / paint first ink",
        Desk.ERASE_CAPTION ++ " second ink / erase",
        Desk.TOOLS_CAPTION ++ " tool",
        Desk.SHAPES_CAPTION ++ " shape",
        SHAPE_NOUNS,
        Desk.RECT_CAPTION ++ " rectangle with any shape",
        Desk.BRUSH_CAPTION ++ " brush size",
        Desk.PICK_CAPTION ++ " pick from under cursor",
        "Palette: " ++ PALETTE_RULE,
        Desk.COPY_CAPTION ++ " copy" ++ SEP ++ Desk.CUT_CAPTION ++ " cut" ++ SEP ++ Desk.PASTE_CAPTION ++ " paste",
        Desk.PAINT_CAPTION ++ " place paste" ++ SEP ++ Desk.DELETE_CAPTION ++ " clear selection",
        std.fmt.comptimePrint("{s} on a number's - or + steps it by {d}", .{ Desk.SHIFT_CAPTION, SHIFT_STEP }),
    } },
    .{ .head = "VIEW", .column = 1, .lines = &.{
        Desk.PAN_CAPTION ++ " pan",
        Desk.WHEEL_CAPTION ++ " or " ++ Desk.ZOOM_CAPTION ++ " zoom" ++ SEP ++ Desk.FIT_CAPTION ++ " fit map",
        Desk.GRAPH_CAPTION ++ " graph" ++ SEP ++ Desk.GO_CAPTION ++ " through door at cursor",
        Desk.REROLL_CAPTION ++ " reroll procgen node",
        Desk.OBJECTS_CAPTION ++ " objects" ++ SEP ++ Desk.HELP_CAPTION ++ " this list",
    } },
    .{ .head = "MAP", .column = 1, .lines = &.{
        Desk.SAVE_CAPTION ++ " save" ++ SEP ++ Desk.SAVE_AS_CAPTION ++ " save as",
        Desk.OPEN_CAPTION ++ " open" ++ SEP ++ Desk.NEW_CAPTION ++ " new",
        Desk.UNDO_CAPTION ++ " undo" ++ SEP ++ Desk.REDO_CAPTION ++ " redo",
        Desk.RENAME_CAPTION ++ " rename node" ++ SEP ++ Desk.ENTER_CAPTION ++ " accept name",
        Desk.NAV_CAPTION ++ " browse list" ++ SEP ++ input.RUB_CAPTION ++ " folder up",
        Desk.PLAY_CAPTION ++ " play start" ++ SEP ++ Desk.PLAY_HERE_CAPTION ++ " play cursor / return",
        Desk.FULLSCREEN_CAPTION ++ " fullscreen" ++ SEP ++ Desk.BACK_CAPTION ++ " back",
    } },
};
pub const HELP_COLUMNS = 2;
pub const HELP_ROWS = blk: {
    var n: [HELP_COLUMNS]i32 = @splat(0);
    for (HELP) |s| n[s.column] += 2 + s.lines.len;
    break :blk std.mem.max(i32, &n);
};

comptime {
    @setEvalBranchQuota(200_000);
    var crib: []const u8 = "";
    for (HELP) |s| {
        for (s.lines) |l| crib = crib ++ " " ++ l ++ " ";
    }
    for (@typeInfo(Desk).@"struct".decls) |d| {
        if (!std.mem.endsWith(u8, d.name, "_CAPTION")) continue;
        if (!namesKey(crib, @field(Desk, d.name))) @compileError("the help never names " ++ d.name);
    }
}

fn namesKey(comptime crib: []const u8, comptime key: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, crib, from, key)) |i| : (from = i + 1) {
        const end = i + key.len;
        if (crib[i - 1] == ' ' and end < crib.len and (crib[end] == ' ' or crib[end] == ',')) return true;
    }
    return false;
}
