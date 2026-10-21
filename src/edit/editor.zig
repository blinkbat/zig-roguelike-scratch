const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const menu = @import("../ui/menu.zig");
const prompt_text = @import("../gfx/prompt_text.zig");

pub fn textFace(g: *const game.Game) prompt_text.Face {
    return .{ .face = &g.face };
}
const game = @import("../game.zig");
pub const knobs = @import("knobs.zig");
pub const canvas = @import("canvas.zig");
pub const modals = @import("modals.zig");
pub const panel = @import("panel.zig");

const P = mathx.P;
const Desk = input.Desk;

pub const PANEL_W: i32 = 340;
pub const PAD: i32 = 12;
pub const ROW_H: i32 = 26;
pub const NODE_H: i32 = 46;
pub const GAP: i32 = 6;
pub const SECTION_GAP: i32 = GAP * 3;
pub const BLOCK_GAP: i32 = GAP * 2;
pub const ROW_STEP: i32 = ROW_H + GAP;
pub const TEXT: i32 = font.BODY;
const SMALL = font.SMALL;
const HEAD = font.HEAD;
pub const INNER_W: i32 = PANEL_W - PAD * 2;
const ZOOMS = [_]f32{ 8, 16, 32, 64 };
const ZOOM_AT = zoomOf(16);
pub const BRUSHES = [_]i32{ 1, 2, 3, 5 };

fn zoomOf(px: f32) usize {
    return std.mem.indexOfScalar(f32, &ZOOMS, px).?;
}

const PAN_PX_S: f32 = 900;
const SAY_S: f32 = 4;
pub const LINE: usize = 200;
pub const UNDO_CAP: usize = 24;
const PATH_FIELD_MAX: usize = 256;
const FIELD_MAX: usize = 32;
/// A press that moves this far is a drag, not a click.
const DRAG_PX: i32 = 4;
/// Door numbers crowd their glyph below this many pixels a cell.
pub const LABEL_PX: f32 = 32;
pub const LABEL_PAD = P{ .x = 2, .y = 1 };
const GLYPH_OF_CELL: f32 = @as(f32, @floatFromInt(look.GLYPH_PX)) / @as(f32, @floatFromInt(look.SPRITE_PX));
const THUMB: i32 = 2;
pub const BOX_W: i32 = grid.W * THUMB;
pub const BOX_TOP: i32 = TEXT + 2 * TITLE_DY;
pub const BOX_H: i32 = BOX_TOP + grid.H * THUMB;
pub const LINK_W: f32 = 2;
pub const DOT_R: f32 = 4;
/// Pixels past a door's dot a press still takes it.
pub const DOT_SLOP: f32 = 3;
pub const MODAL_W: i32 = 600;
pub const MODAL_HEAD: i32 = PAD + HEAD + PAD;
pub const MODAL_ROWS: usize = 12;
pub const MODAL_BTN_W: i32 = 150;
pub const LABEL_W: i32 = 96;
pub const STEP_W: i32 = 24;
pub const STEP_PITCH: i32 = STEP_W + GAP;
pub const SHIFT_STEP: i32 = 5;
const WEIGHT_W: i32 = 30;
pub const MEMBER_W: i32 = 24;
pub const MEMBER_GAP: i32 = 2;
pub const WEIGHT_SPAN: i32 = 2 * STEP_W + WEIGHT_W;
const BRUSH_W: i32 = 48;
pub const BRUSH_SPAN: i32 = 2 * STEP_W + BRUSH_W;
pub const MEMBERS_X: i32 = WEIGHT_SPAN + BLOCK_GAP;
pub const MAKEUP_TOOLS_X: i32 = INNER_W - @as(i32, knobs.MAKEUP_TOOLS.len) * STEP_PITCH + GAP;
pub const TORCH_STEP: i32 = 10;
pub const TEXT_DY: i32 = @divTrunc(ROW_H - TEXT, 2);
pub const SMALL_DY: i32 = @divTrunc(ROW_H - SMALL, 2);
pub const TITLE_DY: i32 = 3;
pub const NODE_GAP: i32 = 2;
pub const DETAIL_DY: i32 = TEXT + 1;

comptime {
    std.debug.assert(atlas.GRAPH_STEP.x > BOX_W and atlas.GRAPH_STEP.y > BOX_H);
    std.debug.assert(FIELD_MAX >= atlas.NAME_MAX and FIELD_MAX <= atlas.STEM_MAX);
    std.debug.assert(PATH_FIELD_MAX >= atlas.PATH_MAX);
    std.debug.assert(MEMBERS_X + @as(i32, pack.MAKEUP_MAX) * (MEMBER_W + MEMBER_GAP) <= MAKEUP_TOOLS_X);
}

const PANEL_BG = look.EDIT_PANEL;
const ROW_ON = look.EDIT_ROW_ON;
const ON = look.EDIT_ON;
pub const START = look.body(actor.HERO);
const START_MARK = [_]u8{ START.ch, ' ' };

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
    door,
    link,
    start,

    pub fn fits(t: Tool, nd: *const atlas.Node) bool {
        return !nd.unrolled() or !t.generated();
    }

    pub fn eql(a: Tool, b: Tool) bool {
        return std.meta.eql(a, b);
    }

    fn generated(t: Tool) bool {
        return switch (t) {
            .door, .link, .start => false,
            .paint, .barrel, .torch, .foe => true,
        };
    }

    fn strokes(t: Tool) bool {
        return switch (t) {
            .paint, .barrel => true,
            .torch, .foe, .door, .link, .start => false,
        };
    }

    pub fn broad(t: Tool) bool {
        return t == .paint;
    }

    pub fn look_(t: Tool) look.Look {
        return switch (t) {
            .paint => .{ .ch = '#', .fg = look.TEXT },
            .barrel => look.BARREL,
            .torch => look.TORCH,
            .foe => |k| look.body(k),
            .door => look.DOOR,
            .link => .{ .ch = '=', .fg = look.DOOR.fg },
            .start => START,
        };
    }

    pub fn name(t: Tool) [:0]const u8 {
        return switch (t) {
            .foe => |k| kindName(k),
            inline else => |_, tag| comptime menu.named(tag),
        };
    }

    pub fn tip(t: Tool) [:0]const u8 {
        return switch (t) {
            .foe => "Foe: " ++ comptime rule(.{ .foe = actor.FOES[0] }),
            inline else => |_, tag| comptime blk: {
                @setEvalBranchQuota(10_000);
                const k = @unionInit(Tool, @tagName(tag), {});
                break :blk k.name() ++ ": " ++ k.rule();
            },
        };
    }

    fn rule(t: Tool) [:0]const u8 {
        return switch (t) {
            .paint => Desk.PAINT_CAPTION ++ " paints the palette's first tile, " ++ Desk.ERASE_CAPTION ++ " its second, in the shape picked",
            .barrel => "stands on " ++ @tagName(grid.BARREL_GROUND) ++ " and breaks for gold; " ++ Desk.ERASE_CAPTION ++ " takes it away",
            .torch => TORCH_RULE,
            .foe => FOE_RULE ++ "; " ++ Desk.ERASE_CAPTION ++ " takes any foe away",
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
pub const TORCH_RULE = "hangs on a wall with floor below it";
pub const PALETTE_RULE = Desk.PAINT_CAPTION ++ " first ink, " ++ Desk.ERASE_CAPTION ++ " second";
const FOE_RULE = "stands on open floor";
const NO_ROOM = "The node has no room for another {s}";
const UNGENERATED = blk: {
    var names: []const []const u8 = &.{};
    for (TOOLS) |t| {
        if (!t.generated()) names = names ++ &[_][]const u8{@tagName(t)};
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
            inline else => |t| @tagName(t),
        };
    }

    pub fn tip(s: Shape) [:0]const u8 {
        return switch (s) {
            inline else => |t| comptime menu.capital(t.noun()) ++ ": " ++ t.rule(),
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

    fn dragged(s: Shape) ?Spanned {
        return switch (s) {
            inline .line, .rect, .box, .select => |t| @field(Spanned, @tagName(t)),
            .brush, .fill => null,
        };
    }
};

const Spanned = enum { line, rect, box, select };

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
const HelpSection = struct { head: [:0]const u8, lines: []const [:0]const u8 };
pub const HELP = [_]HelpSection{
    .{ .head = "PAINTING", .lines = &.{
        Desk.PAINT_CAPTION ++ " places with the tool, or paints the first ink" ++ SEP ++ Desk.ERASE_CAPTION ++ " paints the second ink, or takes away",
        Desk.TOOLS_CAPTION ++ " tool" ++ SEP ++ Desk.SHAPES_CAPTION ++ " " ++ SHAPE_NOUNS ++ SEP ++ Desk.RECT_CAPTION ++ " a rectangle with any shape",
        Desk.BRUSH_CAPTION ++ " brush size" ++ SEP ++ Desk.PICK_CAPTION ++ " picks up what is under the cursor" ++ SEP ++ "the palette: " ++ PALETTE_RULE,
        Desk.COPY_CAPTION ++ " copy" ++ SEP ++ Desk.CUT_CAPTION ++ " cut" ++ SEP ++ Desk.PASTE_CAPTION ++ " paste, then " ++ Desk.PAINT_CAPTION ++ " lays it" ++ SEP ++ Desk.DELETE_CAPTION ++ " clears the selection",
        std.fmt.comptimePrint("{s} on a number's - or + steps it by {d}", .{ Desk.SHIFT_CAPTION, SHIFT_STEP }),
    } },
    .{ .head = "VIEW", .lines = &.{
        Desk.PAN_CAPTION ++ " pan" ++ SEP ++ Desk.WHEEL_CAPTION ++ " or " ++ Desk.ZOOM_CAPTION ++ " zoom" ++ SEP ++ Desk.FIT_CAPTION ++ " fit the map" ++ SEP ++ Desk.GRAPH_CAPTION ++ " graph",
        Desk.GO_CAPTION ++ " through the door under the cursor" ++ SEP ++ Desk.REROLL_CAPTION ++ " rolls a procgen node again" ++ SEP ++ Desk.OBJECTS_CAPTION ++ " every tile and body" ++ SEP ++
            Desk.HELP_CAPTION ++ " this list",
    } },
    .{ .head = "MAP", .lines = &.{
        Desk.SAVE_CAPTION ++ " save" ++ SEP ++ Desk.SAVE_AS_CAPTION ++ " save as" ++ SEP ++ Desk.OPEN_CAPTION ++ " open" ++ SEP ++ Desk.NEW_CAPTION ++ " new" ++ SEP ++
            Desk.UNDO_CAPTION ++ " undo" ++ SEP ++ Desk.REDO_CAPTION ++ " redo",
        Desk.RENAME_CAPTION ++ " rename the node" ++ SEP ++ Desk.ENTER_CAPTION ++ " names it" ++ SEP ++ Desk.NAV_CAPTION ++ " move through a list" ++ SEP ++ input.RUB_CAPTION ++ " a folder up",
        Desk.PLAY_CAPTION ++ " play from the start" ++ SEP ++ Desk.PLAY_HERE_CAPTION ++ " from the cursor, and back" ++ SEP ++ Desk.FULLSCREEN_CAPTION ++ " fullscreen" ++ SEP ++
            Desk.BACK_CAPTION ++ " back a step",
    } },
};
pub const HELP_ROWS = blk: {
    var n: i32 = 0;
    for (HELP) |s| n += 1 + s.lines.len;
    break :blk n;
};
pub const STATUS_H: i32 = GAP * 2 + TEXT * 2 + GAP;

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
const LINK_CANCELLED = "Link cancelled";

pub const Action = union(enum) { none, play: atlas.Start, fight: actor.Kind, leave, quit };

pub const View = enum {
    map,
    graph,

    fn other(v: View) View {
        return if (v == .map) .graph else .map;
    }
};
pub const Lower = enum {
    nodes,
    things,
    generator,
};
const Stroke = enum { none, paint, erase };
pub const Ink = enum {
    first,
    second,

    pub fn of(erase: bool) Ink {
        return if (erase) .second else .first;
    }
};
pub const INKS = std.enums.values(Ink);
/// Asked for, and done once any unsaved changes are saved or let go.
pub const Pending = enum { leave, quit, open, new };
pub const Modal = enum { none, confirm, name, open, help, objects };
const Naming = enum { new, save_as };

fn Text(comptime N: usize) type {
    return struct {
        const Self = @This();
        buf: [N]u8 = undefined,
        n: usize = 0,
        cap: usize = N,

        pub fn text(f: *const Self) []const u8 {
            return f.buf[0..f.n];
        }

        pub fn set(f: *Self, s: []const u8, cap: usize) void {
            f.cap = @min(cap, N);
            f.n = @min(s.len, f.cap);
            @memcpy(f.buf[0..f.n], s[0..f.n]);
        }

        pub fn put(f: *Self, s: []const u8) void {
            f.set(s, N);
        }

        fn feed(f: *Self, d: *const Desk) void {
            for (d.text()) |c| {
                if (f.n == f.cap) break;
                f.buf[f.n] = c;
                f.n += 1;
            }
            if (d.rub and f.n > 0) f.n -= 1;
        }
    };
}

const Field = Text(FIELD_MAX);
const Path = Text(PATH_FIELD_MAX);

/// Graph drag; cancellation restores `was`.
const Drag = struct { node: usize, grab: P, from: P, was: P, moved: bool = false };
const Span = struct { from: P, erase: bool, shape: Spanned };

const Board = struct {
    size: P = .{ .x = 0, .y = 0 },
    tile: [grid.CELLS]grid.Tile = undefined,
    barrel: [grid.CELLS]bool = undefined,
    torch: grid.Torches = .{},
    foe: [atlas.MAX_FOES]atlas.Foe = undefined,
    foe_n: usize = 0,

    pub fn at(b: *const Board, p: P) usize {
        return @intCast(p.y * b.size.x + p.x);
    }

    pub fn box(b: *const Board, lo: P) grid.Box {
        return grid.Box.sized(lo, b.size.x, b.size.y);
    }
};

const Issues = struct {
    unlinked: usize = 0,
    /// Open cells no walk from the start or a door reaches.
    cut_off: usize = 0,
    foes_cut_off: usize = 0,
    start_walled: bool = false,
    reach_from: ?P = null,
};

pub const Seen = union(enum) {
    tile: grid.Tile,
    body: actor.Kind,
    barrel,
    torch,
    door,
};

pub const SEEN = blk: {
    var out: []const Seen = &.{};
    for (std.meta.fields(Seen)) |f| {
        if (f.type == void) {
            out = out ++ &[_]Seen{@unionInit(Seen, f.name, {})};
        } else for (std.enums.values(f.type)) |v| out = out ++ &[_]Seen{@unionInit(Seen, f.name, v)};
    }
    break :blk out[0..out.len].*;
};

const Popup = struct { slot: rl.Rectangle, which: Which };
pub const Which = union(enum) { algo, feature: usize };

const PREVIEW_ROLL: u64 = 0x5EE;

pub const Editor = struct {
    alloc: std.mem.Allocator,
    map: *atlas.Atlas,
    /// Pre-gesture snapshot; also the parse and undo swap buffer.
    scratch: *atlas.Atlas,
    hist: *[UNDO_CAP]atlas.Atlas,
    /// A ring: the oldest step kept is at `hist_base`.
    hist_base: usize = 0,
    hist_len: usize = 0,
    hist_at: usize = 0,
    /// The step the file on disk matches; null once no step does.
    saved_at: ?usize = 0,
    banked: bool = true,
    file: Path = .{},
    node: usize = 0,
    tool: Tool = .paint,
    ink: std.EnumArray(Ink, grid.Tile) = .init(.{ .first = .floor, .second = .wall }),
    shape: Shape = .brush,
    brush: usize = 0,
    view: View = .map,
    lower: Lower = .nodes,
    lower_top: i32 = 0,
    node_rows: usize = 1,
    /// Scrolled pixels and maximum scroll in the generator or Things panel.
    gen_top: i32 = 0,
    gen_most: i32 = 0,
    /// Set while a part of the panel that scrolls is drawn: nothing outside it is hot.
    clip: ?rl.Rectangle = null,
    /// The map's top-left, in cells.
    cam: [2]f32 = .{ 0, 0 },
    zoom: usize = ZOOM_AT,
    recentre: bool = true,
    /// The graph's top-left, in graph pixels.
    gcam: [2]f32 = .{ -PAD, -PAD },
    scroll: usize = 0,
    /// The node the list last scrolled to show, so the wheel may scroll away from it.
    revealed: ?usize = null,
    /// Rendered preview; editing never reads it.
    lv: grid.Level = undefined,
    stale: bool = true,
    roll: u64 = PREVIEW_ROLL,
    rolled_foes: actor.Pool = .{},
    shown: [actor.MAX]atlas.Foe = undefined,
    shown_n: usize = 0,
    issues: Issues = .{},
    selection: ?grid.Box = null,
    board: Board = .{},
    /// The paste laid aside for its ghost.
    trial: atlas.Bespoke = undefined,
    pasting: bool = false,
    linking: ?atlas.Link = null,
    delete_armed: ?usize = null,
    popup: ?Popup = null,
    seen_at: usize = 0,
    /// A cell the Things list jumped to, lit a moment.
    flash: ?P = null,
    flash_t: f32 = 0,
    /// Persistent reachability scratch to avoid placing it on the stack.
    reach_dist: [grid.CELLS]i32 = undefined,
    reach_queue: [grid.CELLS]u32 = undefined,
    assets: look.Assets = look.Assets.everything(),
    assets_stale: bool = true,
    start_at: ?P = null,
    thumb_lv: grid.Level = undefined,
    thumbs: [atlas.MAX_NODES]?rl.Texture2D = @splat(null),
    thumb_ok: std.StaticBitSet(atlas.MAX_NODES) = .initEmpty(),
    pick: ?atlas.Link = null,
    dirty: bool = false,
    stroke: Stroke = .none,
    stroke_at: ?P = null,
    span: ?Span = null,
    drag: ?Drag = null,
    modal: Modal = .none,
    /// A modal opened or closed this frame: no click lands until the next.
    fresh: bool = false,
    pending: Pending = .leave,
    pending_path: Path = .{},
    naming: Naming = .new,
    renaming: bool = false,
    /// The rename field consumes its closing click; newly exposed buttons must not receive it.
    renamed: bool = false,
    field: Field = .{},
    listing: atlas.Listing = .{},
    listed_top: usize = 0,
    listed_at: usize = 0,
    desk: Desk = .{},
    action: Action = .none,
    tip: ?[:0]const u8 = null,
    said: menu.Note(LINE) = .{},
    said_t: f32 = 0,

    pub fn create(alloc: std.mem.Allocator) !*Editor {
        const w = try alloc.create(atlas.Atlas);
        errdefer alloc.destroy(w);
        const s = try alloc.create(atlas.Atlas);
        errdefer alloc.destroy(s);
        const h = try alloc.create([UNDO_CAP]atlas.Atlas);
        errdefer alloc.destroy(h);
        const ed = try alloc.create(Editor);
        ed.* = .{ .alloc = alloc, .map = w, .scratch = s, .hist = h };
        freshMap(w);
        return ed;
    }

    /// Needs the GL context that drew its thumbnails.
    pub fn destroy(ed: *Editor) void {
        for (ed.thumbs) |t| {
            if (t) |x| rl.unloadTexture(x);
        }
        const alloc = ed.alloc;
        alloc.destroy(ed.hist);
        alloc.destroy(ed.scratch);
        alloc.destroy(ed.map);
        alloc.destroy(ed);
    }

    pub fn path(ed: *const Editor) []const u8 {
        return ed.file.text();
    }

    /// The map it has open, read afresh from its file.
    pub fn reopen(ed: *Editor) !void {
        const keep = ed.file;
        return ed.open(keep.text());
    }

    /// Loads `p`, or starts a map there when it is not yet; a file that does not parse is left alone.
    pub fn open(ed: *Editor, p: []const u8) !void {
        if (p.len > PATH_FIELD_MAX) return error.NameTooLong;
        var fresh = false;
        ed.scratch.load(ed.alloc, p) catch |e| {
            if (e != error.FileNotFound) {
                ed.scratch.* = ed.map.*;
                return e;
            }
            freshMap(ed.scratch);
            fresh = true;
        };
        ed.map.* = ed.scratch.*;
        ed.setPath(p);
        ed.settle();
        ed.say("{s} {s}", .{ if (fresh) "New map; it saves to" else "Opened", p });
    }

    fn settle(ed: *Editor) void {
        ed.hist_len = 0;
        ed.hist_at = 0;
        ed.saved_at = 0;
        ed.banked = true;
        ed.node = 0;
        ed.scroll = 0;
        ed.release();
        ed.dirty = false;
        ed.renaming = false;
        ed.modal = .none;
        ed.view = .map;
        ed.recentre = true;
        ed.forgetNode();
        ed.gen_top = 0;
        ed.roll = PREVIEW_ROLL;
        ed.fitTool();
        ed.restamp();
    }

    /// With '/' between folders, as `atlas.Listing` writes its paths.
    pub fn setPath(ed: *Editor, p: []const u8) void {
        var q = p;
        while (q.len > 2 and q[0] == '.' and (q[1] == '/' or q[1] == '\\')) q = q[2..];
        ed.file.put(q);
        std.mem.replaceScalar(u8, ed.file.buf[0..ed.file.n], '\\', '/');
    }

    pub fn plan(ed: *Editor) *atlas.Plan {
        return &ed.here().plan;
    }

    pub fn px(ed: *const Editor) f32 {
        return ZOOMS[ed.zoom];
    }

    pub fn brushSize(ed: *const Editor) i32 {
        return BRUSHES[ed.brush];
    }

    pub fn stepBrush(ed: *Editor, by: i32) void {
        ed.brush = mathx.nudge(ed.brush, std.math.sign(by), BRUSHES.len);
    }

    fn say(ed: *Editor, comptime fmt: []const u8, args: anytype) void {
        ed.said.say(fmt, args);
        ed.said_t = SAY_S;
    }

    /// All changes between press and release form one undo step.
    pub fn gesture(ed: *Editor) void {
        ed.scratch.* = ed.map.*;
        ed.banked = false;
    }

    pub fn bank(ed: *Editor) void {
        ed.dirty = true;
        if (ed.banked) {
            if (ed.saved_at == ed.hist_at) ed.saved_at = null;
            return;
        }
        ed.banked = true;
        ed.hist_len = ed.hist_at;
        if (ed.saved_at) |s| {
            if (s > ed.hist_len) ed.saved_at = null;
        }
        if (ed.hist_len == UNDO_CAP) {
            ed.hist_base = (ed.hist_base + 1) % UNDO_CAP;
            ed.hist_len -= 1;
            if (ed.saved_at) |s| ed.saved_at = if (s == 0) null else s - 1;
        }
        ed.kept(ed.hist_len).* = ed.scratch.*;
        ed.hist_len += 1;
        ed.hist_at = ed.hist_len;
    }

    fn kept(ed: *Editor, k: usize) *atlas.Atlas {
        return &ed.hist[(ed.hist_base + k) % UNDO_CAP];
    }

    fn changed(ed: *Editor) void {
        ed.bank();
        ed.stale = true;
        ed.thumb_ok.unset(ed.node);
    }

    fn relinked(ed: *Editor) void {
        ed.bank();
        ed.issues.unlinked = ed.here().unlinked();
    }

    fn restamp(ed: *Editor) void {
        ed.stale = true;
        ed.thumb_ok = .initEmpty();
    }

    fn swapStep(ed: *Editor, k: usize) void {
        ed.release();
        ed.forgetNode();
        ed.scratch.* = ed.map.*;
        ed.map.* = ed.kept(k).*;
        ed.kept(k).* = ed.scratch.*;
        ed.banked = true;
        ed.clampSelection();
        ed.restampSwapped();
    }

    fn restampSwapped(ed: *Editor) void {
        if (ed.map.node_n != ed.scratch.node_n) return ed.restamp();
        ed.stale = true;
        for (ed.map.nodes(), ed.scratch.nodes(), 0..) |*now, *was, n| {
            if (!std.mem.eql(u8, std.mem.asBytes(now), std.mem.asBytes(was))) ed.thumb_ok.unset(n);
        }
    }

    pub fn undo(ed: *Editor) void {
        ed.keepDrag();
        if (ed.hist_at == 0) return ed.say("Nothing to undo", .{});
        ed.hist_at -= 1;
        ed.swapStep(ed.hist_at);
        ed.dirty = ed.saved_at != ed.hist_at;
        ed.say("Undone ({d} more)", .{ed.hist_at});
    }

    pub fn redo(ed: *Editor) void {
        if (ed.hist_at < ed.hist_len) ed.drop() else ed.keepDrag();
        if (ed.hist_at == ed.hist_len) return ed.say("Nothing to redo", .{});
        ed.swapStep(ed.hist_at);
        ed.hist_at += 1;
        ed.dirty = ed.saved_at != ed.hist_at;
        ed.say("Redone ({d} more)", .{ed.hist_len - ed.hist_at});
    }

    /// A box dragged on the graph kept where it stands, its own undo step.
    fn keepDrag(ed: *Editor) void {
        const dr = ed.drag orelse return;
        if (dr.moved and !ed.map.node[dr.node].pos.eq(dr.was)) ed.bank();
        ed.drag = null;
    }

    fn holding(ed: *const Editor) bool {
        return ed.popup != null or ed.span != null or ed.stroke != .none or ed.drag != null or ed.linking != null;
    }

    pub fn drop(ed: *Editor) void {
        ed.letGo();
        if (ed.drag) |dr| ed.map.node[dr.node].pos = dr.was;
        ed.drag = null;
        ed.linking = null;
        ed.popup = null;
    }

    fn release(ed: *Editor) void {
        ed.drop();
        ed.pick = null;
        ed.pasting = false;
    }

    pub fn setTool(ed: *Editor, t: Tool) void {
        if (!t.fits(ed.here())) return ed.say(GENERATED, .{});
        if (!t.eql(ed.tool)) ed.release();
        ed.tool = t;
    }

    pub fn setShape(ed: *Editor, s: Shape) void {
        if (s != ed.shape) ed.release();
        ed.shape = s;
        if (s != .select and !ed.tool.broad() and ed.paintable()) ed.setTool(.paint);
    }

    pub fn setView(ed: *Editor, v: View) void {
        if (v != ed.view) ed.drop();
        ed.view = v;
    }

    fn clampSelection(ed: *Editor) void {
        ed.node = @min(ed.node, ed.map.node_n - 1);
        ed.scroll = @min(ed.scroll, ed.map.node_n - 1);
        ed.fitTool();
    }

    fn fitTool(ed: *Editor) void {
        if (!ed.tool.fits(ed.here())) ed.tool = .door;
    }

    /// Preserve paste across node selection; cancel pending links and gestures.
    pub fn select(ed: *Editor, n: usize) void {
        if (ed.renaming) ed.commitRename();
        ed.drop();
        ed.node = n;
        ed.stale = true;
        ed.recentre = true;
        ed.gen_top = 0;
        ed.forgetNode();
        ed.fitTool();
    }

    fn forgetNode(ed: *Editor) void {
        ed.selection = null;
        ed.delete_armed = null;
    }

    pub fn preview(ed: *Editor) void {
        if (!ed.stale) return;
        const nd = ed.here();
        ed.rolled_foes = .{};
        switch (nd.plan) {
            .bespoke => nd.sketch(&ed.lv),
            .procgen => |*pg| {
                nd.stamp(&ed.lv, ed.roll);
                var rng = mathx.Rng.init(ed.roll);
                const at = atlas.landing(&ed.lv, ed.arrival(), nd.placed()) orelse ed.arrival();
                _ = ed.rolled_foes.spawn(&ed.lv, actor.Actor.of(actor.HERO, at));
                pack.place(&ed.lv, &ed.rolled_foes, &rng, at, &pg.foes);
                ed.lv.clear(at);
            },
        }
        ed.shown_n = 0;
        for (nd.placed()) |f| ed.show(f);
        for (ed.rolled_foes.slice()) |a| {
            if (a.foe()) ed.show(.{ .kind = a.kind, .at = a.at });
        }
        ed.start_at = ed.startOn();
        ed.issues = ed.issuesOf();
        ed.stale = false;
    }

    fn show(ed: *Editor, f: atlas.Foe) void {
        ed.shown[ed.shown_n] = f;
        ed.shown_n += 1;
    }

    pub fn shownFoes(ed: *const Editor) []const atlas.Foe {
        return ed.shown[0..ed.shown_n];
    }

    pub fn arrival(ed: *Editor) P {
        if (ed.map.start.node == ed.node) return ed.map.start.at;
        const ds = ed.here().doors();
        return if (ds.len > 0) ds[0].at else grid.MIDDLE;
    }

    fn startOn(ed: *Editor) ?P {
        const s = ed.map.start;
        if (s.node != ed.node) return null;
        return atlas.landing(&ed.lv, s.at, ed.here().placed());
    }

    fn issuesOf(ed: *Editor) Issues {
        const nd = ed.here();
        var is = Issues{ .unlinked = nd.unlinked() };
        const s = ed.map.start;
        if (s.node == ed.node) is.start_walled = !ed.lv.walkable(s.at);
        var flood: ?grid.Flood = null;
        if (ed.start_at) |at| flood = grid.Flood.init(&ed.lv, at, &ed.reach_dist, &ed.reach_queue);
        for (nd.doors()) |d| {
            if (!ed.lv.walkable(d.at)) continue;
            if (flood) |*f| {
                f.seed(d.at);
            } else flood = grid.Flood.init(&ed.lv, d.at, &ed.reach_dist, &ed.reach_queue);
        }
        if (flood) |*f| {
            while (f.next()) |_| {}
        } else @memset(&ed.reach_dist, -1);
        for (0..grid.CELLS) |i| {
            if (!ed.cutOff(i)) continue;
            is.cut_off += 1;
            if (is.reach_from == null) is.reach_from = grid.Level.of(i);
        }
        for (nd.placed()) |foe| {
            const i = grid.Level.idx(foe.at);
            if (ed.reach_dist[i] < 0) is.foes_cut_off += 1;
        }

        return is;
    }

    pub fn cutOff(ed: *const Editor, i: usize) bool {
        return !ed.lv.tile[i].solid() and ed.reach_dist[i] < 0;
    }

    pub fn standable(ed: *Editor, from: atlas.Start) bool {
        return ed.map.standable(from, &ed.thumb_lv);
    }

    pub fn doorAt(ed: *Editor, p: P) ?usize {
        return ed.here().doorAt(p);
    }

    pub fn nodeTitle(ed: *Editor, n: usize, buf: []u8) [:0]const u8 {
        var name: [atlas.TITLE_MAX]u8 = undefined;
        const mark: []const u8 = if (ed.map.start.node == n) &START_MARK else "";
        if (ed.renamingNode(n)) return std.fmt.bufPrintZ(buf, "{s}{d}  {s}" ++ menu.CARET, .{ mark, n, ed.field.text() }) catch "";
        return std.fmt.bufPrintZ(buf, "{s}{d}  {s}", .{ mark, n, ed.nodeName(n, &name) }) catch "";
    }

    pub fn renamingNode(ed: *const Editor, n: usize) bool {
        return ed.renaming and n == ed.node;
    }

    pub fn playStart(ed: *Editor) void {
        ed.action = .{ .play = ed.map.start };
    }

    pub fn nodeName(ed: *Editor, n: usize, buf: *[atlas.TITLE_MAX]u8) []const u8 {
        return ed.map.node[n].title(n, buf);
    }

    pub fn here(ed: *Editor) *atlas.Node {
        return &ed.map.node[ed.node];
    }

    pub fn paintable(ed: *Editor) bool {
        return @as(Tool, .paint).fits(ed.here());
    }

    pub fn rolled(ed: *Editor) ?*atlas.Procgen {
        return switch (ed.plan().*) {
            .procgen => |*pg| pg,
            .bespoke => null,
        };
    }

    fn painted(ed: *Editor) ?*atlas.Bespoke {
        return switch (ed.plan().*) {
            .bespoke => |*b| b,
            .procgen => null,
        };
    }

    pub fn generator(ed: *Editor) ?*atlas.Procgen {
        return if (ed.lower == .generator) ed.rolled() else null;
    }

    pub fn goTo(ed: *Editor, n: usize) void {
        ed.select(n);
        ed.setView(.map);
    }

    pub fn request(ed: *Editor, p: Pending) void {
        ed.keepDrag();
        if (ed.renaming) ed.commitRename();
        ed.pending = p;
        if (!ed.dirty) return ed.commit();
        ed.ask(.confirm);
    }

    pub fn commit(ed: *Editor) void {
        ed.modal = .none;
        const p = ed.pending_path.text();
        switch (ed.pending) {
            .leave => ed.action = .leave,
            .quit => ed.action = .quit,
            .open => ed.open(p) catch |e| ed.say(atlas.NOT_LOADED, .{ p, @errorName(e) }),
            .new => {
                freshMap(ed.map);
                ed.setPath(p);
                ed.settle();
                ed.say("New map; {s} saves it to {s}", .{ Desk.SAVE_CAPTION, p });
            },
        }
    }

    pub fn save(ed: *Editor) bool {
        ed.keepDrag();
        ed.map.save(ed.alloc, ed.path()) catch |e| {
            ed.say("{s} did not save ({s})", .{ ed.path(), @errorName(e) });
            return false;
        };
        ed.dirty = false;
        ed.saved_at = ed.hist_at;
        ed.say("Saved {s}", .{ed.path()});
        return true;
    }

    pub fn ask(ed: *Editor, m: Modal) void {
        ed.drop();
        ed.modal = m;
        ed.fresh = true;
    }

    pub fn askName(ed: *Editor, n: Naming) void {
        ed.naming = n;
        ed.field.put("");
        ed.ask(.name);
    }

    pub fn askOpen(ed: *Editor) void {
        ed.listing.scanAt(atlas.folderOf(ed.path()));
        ed.showListing();
        ed.ask(.open);
    }

    fn showListing(ed: *Editor) void {
        ed.listed_top = 0;
        ed.listed_at = 0;
        for (0..ed.listing.n) |i| {
            if (!std.mem.eql(u8, ed.listing.at(i), ed.path())) continue;
            ed.listed_at = i;
            ed.listed_top = mathx.reveal(0, i, MODAL_ROWS);
        }
    }

    pub fn openListed(ed: *Editor, i: usize) void {
        if (ed.listing.open(i)) return ed.showListing();
        ed.pending_path.put(ed.listing.at(i));
        ed.modal = .none;
        ed.request(.open);
    }

    pub fn namedPath(ed: *const Editor, buf: []u8) ?[]const u8 {
        return atlas.pathFor(buf, atlas.folderOf(ed.path()), ed.field.text());
    }

    pub fn named(ed: *Editor) void {
        var buf: [atlas.PATH_MAX]u8 = undefined;
        const p = ed.namedPath(&buf) orelse return ed.say("Type a name of letters or digits", .{});
        if (std.fs.cwd().access(p, .{})) {
            return ed.say("{s} is there already; open it, or pick another name", .{p});
        } else |e| if (e != error.FileNotFound) return ed.say("{s} could not be checked ({s})", .{ p, @errorName(e) });
        ed.modal = .none;
        switch (ed.naming) {
            .save_as => {
                const keep = ed.file;
                ed.setPath(p);
                if (!ed.save()) ed.file = keep;
            },
            .new => {
                ed.pending_path.put(p);
                ed.request(.new);
            },
        }
    }

    pub fn startRename(ed: *Editor) void {
        ed.drop();
        ed.gesture();
        ed.typeName();
    }

    fn typeName(ed: *Editor) void {
        ed.drop();
        ed.field.set(ed.here().name(), atlas.NAME_MAX);
        ed.renaming = true;
    }

    pub fn commitRename(ed: *Editor) void {
        ed.renaming = false;
        const nd = ed.here();
        const renamed = nd.rename(ed.field.text()) orelse return ed.say("A name is {d} letters at most", .{atlas.NAME_MAX});
        if (renamed) ed.bank();
    }

    pub fn canvas(g: *const game.Game) rl.Rectangle {
        return look.rect(PANEL_W, 0, @max(0, g.screen.x - PANEL_W), @max(0, g.screen.y - STATUS_H));
    }

    /// Screen origin rounded to whole pixels to keep sprites aligned.
    pub fn origin(ed: *const Editor, c: rl.Rectangle) [2]f32 {
        return .{ c.x - @round(ed.cam[0] * ed.px()), c.y - @round(ed.cam[1] * ed.px()) };
    }

    fn cellAt(ed: *const Editor, c: rl.Rectangle, m: P) P {
        const o = ed.origin(c);
        return mathx.cellOf(.{
            (@as(f32, @floatFromInt(m.x)) - o[0]) / ed.px(),
            (@as(f32, @floatFromInt(m.y)) - o[1]) / ed.px(),
        });
    }

    fn putAwayPaste(ed: *Editor) void {
        ed.pasting = false;
        ed.say("Paste put away", .{});
    }

    fn letGo(ed: *Editor) void {
        ed.stroke = .none;
        ed.stroke_at = null;
        ed.span = null;
    }

    pub fn dotUnder(ed: *const Editor, c: rl.Rectangle, m: P) ?atlas.Link {
        for (0..ed.map.node_n) |n| {
            for (0..ed.map.node[n].door_n) |k| {
                const l = atlas.Link{ .node = n, .door = k };
                if (rl.checkCollisionPointCircle(vec(m), ed.dotAt(c, l), DOT_R + DOT_SLOP)) return l;
            }
        }
        return null;
    }

    pub fn mouseCell(ed: *const Editor, c: rl.Rectangle) P {
        return ed.cellAt(c, ed.desk.mouse);
    }

    pub fn mouseIn(ed: *const Editor, r: rl.Rectangle) bool {
        return look.holds(r, ed.desk.mouse);
    }

    pub fn cellRect(ed: *const Editor, c: rl.Rectangle, p: P) rl.Rectangle {
        const o = ed.origin(c);
        return .{
            .x = o[0] + @as(f32, @floatFromInt(p.x)) * ed.px(),
            .y = o[1] + @as(f32, @floatFromInt(p.y)) * ed.px(),
            .width = ed.px(),
            .height = ed.px(),
        };
    }

    pub fn lookAt(ed: *Editor, c: rl.Rectangle, p: P) void {
        const at = mathx.centre(p);
        ed.cam = .{ at[0] - c.width / ed.px() * 0.5, at[1] - c.height / ed.px() * 0.5 };
    }

    pub fn boxAt(ed: *const Editor, c: rl.Rectangle, n: usize) rl.Rectangle {
        const pos = ed.map.node[n].pos;
        return .{
            .x = c.x + @as(f32, @floatFromInt(pos.x)) - ed.gcam[0],
            .y = c.y + @as(f32, @floatFromInt(pos.y)) - ed.gcam[1],
            .width = @floatFromInt(BOX_W),
            .height = @floatFromInt(BOX_H),
        };
    }

    pub fn boxUnder(ed: *const Editor, c: rl.Rectangle, m: P) ?usize {
        var n = ed.map.node_n;
        while (n > 0) {
            n -= 1;
            if (look.holds(ed.boxAt(c, n), m)) return n;
        }
        return null;
    }

    pub fn dotAt(ed: *const Editor, c: rl.Rectangle, l: atlas.Link) rl.Vector2 {
        const b = ed.boxAt(c, l.node);
        const d = ed.map.door(l).at;
        return .{
            .x = b.x + @as(f32, @floatFromInt(d.x * THUMB + @divTrunc(THUMB, 2))),
            .y = b.y + @as(f32, @floatFromInt(BOX_TOP + d.y * THUMB + @divTrunc(THUMB, 2))),
        };
    }
};

fn freshMap(w: *atlas.Atlas) void {
    const room = grid.Box.centred(FRESH_ROOM.x, FRESH_ROOM.y);
    _ = w.oneRoom(room, room.centre());
}

const FRESH_ROOM = P{ .x = 15, .y = 9 };

const vec = look.vec;

/// Caller updates `desk` and `g.screen` first; `closing` is the window close request.
pub fn frame(ed: *Editor, g: *game.Game, closing: bool) Action {
    ed.action = .none;
    if (closing) ed.request(.quit);
    const c = Editor.canvas(g);
    if (ed.recentre) {
        ed.preview();
        fitView(ed, c);
        ed.recentre = false;
    }
    step(ed, g, rl.getFrameTime());
    prepare(ed, g);
    rl.beginDrawing();
    draw(ed, g);
    rl.endDrawing();
    ed.fresh = false;
    ed.renamed = false;
    if (ed.action == .play) {
        for ([_]atlas.Start{ ed.action.play, ed.map.start }) |from| {
            if (ed.standable(from)) continue;
            var buf: [atlas.TITLE_MAX]u8 = undefined;
            ed.say(atlas.NO_FLOOR, .{ed.nodeName(from.node, &buf)});
            ed.action = .none;
            break;
        } else ed.drop();
    }
    return ed.action;
}

fn step(ed: *Editor, g: *game.Game, dt: f32) void {
    const d = &ed.desk;
    ed.said_t -= dt;
    ed.flash_t -= dt;
    if (ed.action != .none) return;
    if (ed.modal != .none) {
        modalKeys(ed);
        if (ed.modal == .none) ed.fresh = true;
        return;
    }
    const c = Editor.canvas(g);
    const over = ed.mouseIn(c);
    if (ed.renaming) {
        ed.field.feed(d);
        if (d.back or d.enter or d.clicked()) {
            if (d.back) ed.renaming = false else ed.commitRename();
            ed.renamed = d.clicked();
        }
        if (ed.renaming or !d.clicked() or over) return;
    } else if (d.back) {
        escape(ed);
        if (d.clicked()) ed.gesture();
        return;
    }
    if (d.play) ed.playStart();
    if (d.play_here) playHere(ed, c, over);
    if (ed.action != .none) return;
    const view = ed.view;
    const node = ed.node;
    if (d.save) _ = ed.save();
    if (d.save_as) ed.askName(.save_as);
    if (d.open) ed.askOpen();
    if (d.new) ed.askName(.new);
    if (d.help) ed.ask(.help);
    if (d.objects) ed.ask(.objects);
    if (d.undo) ed.undo();
    if (d.redo) ed.redo();
    if (d.graph) ed.setView(ed.view.other());
    if (d.rename) ed.startRename();
    if (d.go) goThrough(ed, c, over);
    if (d.reroll) reroll(ed);
    if (d.smaller) ed.stepBrush(-1);
    if (d.bigger) ed.stepBrush(1);
    if (d.tool) |i| ed.setTool(TOOLS[i]);
    if (d.shape) |i| ed.setShape(SHAPES[i]);
    if (ed.view == .map) {
        if (d.fit) fitView(ed, c);
        if (d.zoom_in or d.zoom_out) zoom(ed, c, if (d.zoom_in) 1 else -1, look.middleAt(c));
        if (d.copy) copySelection(ed, false);
        if (d.cut) copySelection(ed, true);
        if (d.delete) clearSelection(ed);
        if (d.paste) startPaste(ed);
    }
    if (d.erase_hit and (ed.drag != null or ed.linking != null)) return ed.drop();
    if (ed.modal != .none or ed.renaming) return;
    if (ed.popup) |pp| {
        if (d.clicked() and !ed.mouseIn(popupRect(pp, g.screen.y))) {
            ed.popup = null;
            ed.fresh = true;
        } else if (d.clicked()) ed.gesture();
        return;
    }
    if (d.clicked()) ed.gesture();
    if (d.clicked() and (ed.view != view or ed.node != node)) return;
    switch (ed.view) {
        .map => {
            panBy(&ed.cam, d, dt, ed.px());
            if (d.wheel != 0 and over) zoom(ed, c, if (d.wheel > 0) 1 else -1, d.mouse);
            mapMouse(ed, c, over);
            if (d.fullscreen) ed.stroke_at = null;
        },
        .graph => {
            panBy(&ed.gcam, d, dt, 1);
            graphMouse(ed, c, over);
        },
    }
    if (d.wheel != 0 and d.mouse.x < PANEL_W and d.mouse.y >= ed.lower_top) {
        const up = d.wheel > 0;
        if (ed.lower == .things or ed.generator() != null) {
            ed.gen_top = std.math.clamp(ed.gen_top + if (up) -ROW_H else ROW_H, 0, ed.gen_most);
        } else scrollNodes(ed, if (up) -1 else 1);
    }
}

/// `px` screen pixels a unit of `cam`.
fn panBy(cam: *[2]f32, d: *const Desk, dt: f32, px: f32) void {
    const pan = [2]f32{ @floatFromInt(d.pan.x), @floatFromInt(d.pan.y) };
    const moved = [2]f32{ @floatFromInt(d.moved.x), @floatFromInt(d.moved.y) };
    for (0..2) |k| {
        cam[k] += pan[k] * PAN_PX_S * dt / px;
        if (d.grab) cam[k] -= moved[k] / px;
    }
}

pub fn escape(ed: *Editor) void {
    if (ed.holding()) {
        ed.drop();
    } else if (ed.pasting) {
        ed.putAwayPaste();
    } else if (ed.pick != null) {
        ed.pick = null;
        ed.say(LINK_CANCELLED, .{});
    } else if (ed.delete_armed != null) {
        ed.delete_armed = null;
    } else if (ed.selection != null) {
        ed.selection = null;
    } else if (ed.view == .graph) {
        ed.setView(.map);
    } else ed.request(.leave);
}

pub fn modalKeys(ed: *Editor) void {
    const d = &ed.desk;
    if (ed.modal == .open and (d.back or d.rub) and ed.listing.up()) return ed.showListing();
    if (d.back) {
        ed.modal = .none;
        return;
    }
    switch (ed.modal) {
        .confirm => if (d.enter and ed.save()) ed.commit(),
        .name => {
            ed.field.feed(d);
            if (d.enter) ed.named();
        },
        .open => {
            if (d.wheel != 0) ed.listed_top = mathx.nudge(ed.listed_top, if (d.wheel > 0) -1 else 1, (ed.listing.n -| MODAL_ROWS) + 1);
            if (d.nav != 0 and ed.listing.n > 0) {
                ed.listed_at = mathx.wrap(ed.listed_at, d.nav, ed.listing.n);
                ed.listed_top = mathx.reveal(ed.listed_top, ed.listed_at, MODAL_ROWS);
            }
            if (d.enter and ed.listed_at < ed.listing.n) ed.openListed(ed.listed_at);
        },
        .objects => {
            if (d.nav != 0) ed.seen_at = mathx.wrap(ed.seen_at, d.nav, SEEN.len);
            if (d.enter) modals.fightSeen(ed);
        },
        .help, .none => {},
    }
}

fn playHere(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const p = ed.mouseCell(c);
    if (ed.view != .map or !grid.Level.inside(p) or !over) {
        return ed.say("{s} plays from the cell under the cursor on a map", .{Desk.PLAY_HERE_CAPTION});
    }
    ed.action = .{ .play = .{ .node = ed.node, .at = p } };
}

fn goThrough(ed: *Editor, c: rl.Rectangle, over: bool) void {
    if (ed.view != .map) return;
    const door = if (over) ed.doorAt(ed.mouseCell(c)) else null;
    const k = door orelse return ed.say("{s} goes through the door under the cursor", .{Desk.GO_CAPTION});
    const to = ed.here().door[k].to orelse return ed.say("Door {d} leads nowhere yet", .{k});
    ed.select(to.node);
    ed.recentre = false;
    ed.lookAt(c, ed.map.door(to).at);
    var buf: [atlas.TITLE_MAX]u8 = undefined;
    ed.say("Through door {d} to {s}, door {d}", .{ k, ed.nodeName(to.node, &buf), to.door });
}

pub fn mapMouse(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const d = &ed.desk;
    const p = ed.mouseCell(c);
    if (ed.pasting) {
        if (over and d.paint_hit) {
            if (ed.paintable()) layBoard(ed, p) else ed.say(GENERATED, .{});
        }
        if (over and d.erase_hit) ed.putAwayPaste();
        return;
    }
    const held = switch (ed.stroke) {
        .none => d.paint or d.erase,
        .paint => d.paint,
        .erase => d.erase,
    };
    if (!held) {
        if (ed.span) |s| {
            laySpan(ed, s, grid.Level.clamp(p));
            if (d.clicked()) ed.gesture();
        }
        ed.letGo();
    }
    if (over and d.clicked()) {
        ed.letGo();
        const second = !d.paint_hit;
        if (d.alt) return pickUp(ed, p, second);
        ed.stroke = if (second) .erase else .paint;
        if (spanOf(ed, d.shift)) |s| {
            ed.span = .{ .from = grid.Level.clamp(p), .erase = second, .shape = s };
            return;
        }
        if (ed.shape == .fill and ed.tool.broad()) {
            ed.stroke = .none;
            if (!ed.tool.fits(ed.here())) return ed.say(GENERATED, .{});
            if (grid.Level.inside(p)) fill(ed, p, second);
            return;
        }
    } else if (d.clicked() and ed.span == null) ed.letGo();
    if (!over) ed.stroke_at = null;
    if (ed.span != null or !over or ed.stroke == .none) return;
    const hit = if (ed.stroke == .paint) d.paint_hit else d.erase_hit;
    if (!hit and !ed.tool.strokes()) return;
    if (!ed.tool.fits(ed.here())) {
        if (hit and grid.Level.inside(p)) ed.say(GENERATED, .{});
        return;
    }
    if (hit or ed.stroke_at == null) {
        if (grid.Level.inside(p)) brushAt(ed, p);
    } else {
        var ray = grid.Ray.init(ed.stroke_at.?, p);
        while (ray.next()) |q| {
            if (grid.Level.inside(q)) brushAt(ed, q);
        }
    }
    ed.stroke_at = p;
}

fn brushAt(ed: *Editor, p: P) void {
    brushWith(ed, p, ed.stroke == .erase);
}

fn brushWith(ed: *Editor, p: P, erase: bool) void {
    eachBrushCell(ed, p, Laid{ .ed = ed, .erase = erase });
}

const Laid = struct {
    ed: *Editor,
    erase: bool,

    fn at(l: Laid, p: P) void {
        apply(l.ed, p, l.erase);
    }
};

pub const Ghost = struct {
    ed: *Editor,
    g: *game.Game,
    c: rl.Rectangle,
    ink: grid.Tile,
    view: grid.Box,

    pub fn of(ed: *Editor, g: *game.Game, c: rl.Rectangle, ink: grid.Tile) Ghost {
        return .{ .ed = ed, .g = g, .c = c, .ink = ink, .view = canvas.visible(ed, c) };
    }

    fn at(h: Ghost, p: P) void {
        if (h.view.holds(p)) canvas.ghostInk(h.ed, h.g, h.c, p, h.ink);
    }
};

pub fn eachBrushCell(ed: *const Editor, p: P, to: anytype) void {
    if (!ed.tool.broad()) return to.at(p);
    var cells = brushBox(p, ed.brushSize()).cells();
    while (cells.next()) |q| {
        if (grid.Level.inside(q)) to.at(q);
    }
}

pub fn eachSpanCell(ed: *const Editor, s: Span, end: P, to: anytype) void {
    const b = grid.Box.between(s.from, end);
    switch (s.shape) {
        .select => {},
        .rect, .box => {
            var cells = b.cells();
            while (cells.next()) |p| {
                if (grid.Level.inside(p) and (s.shape == .rect or b.onEdge(p))) to.at(p);
            }
        },
        .line => {
            eachBrushCell(ed, s.from, to);
            var ray = grid.Ray.init(s.from, end);
            while (ray.next()) |q| eachBrushCell(ed, q, to);
        },
    }
}

pub fn spanOf(ed: *Editor, shift: bool) ?Spanned {
    if (ed.shape == .select) return .select;
    if (!ed.tool.broad() or !ed.tool.fits(ed.here())) return null;
    if (shift) return .rect;
    return ed.shape.dragged();
}

pub fn laySpan(ed: *Editor, s: Span, to: P) void {
    eachSpanCell(ed, s, to, Laid{ .ed = ed, .erase = s.erase });
    if (s.shape != .select) return;
    const b = grid.Box.between(s.from, to);
    ed.selection = b;
    ed.say("{d} by {d} selected: {s} copies, {s} cuts, {s} clears", .{ b.width(), b.height(), Desk.COPY_CAPTION, Desk.CUT_CAPTION, Desk.DELETE_CAPTION });
}

pub fn fill(ed: *Editor, p: P, second: bool) void {
    const b = &ed.plan().bespoke;
    const at = grid.Level.idx(p);
    const from = b.tile[at];
    const to = ed.ink.get(.of(second));
    if (from == to) return;
    var seen = std.StaticBitSet(grid.CELLS).initEmpty();
    var queue: [grid.CELLS]u32 = undefined;
    var head: usize = 0;
    var tail: usize = 1;
    var filled: usize = 0;
    queue[0] = @intCast(at);
    seen.set(queue[0]);
    while (head < tail) : (head += 1) {
        const here = grid.Level.of(queue[head]);
        if (ed.doorAt(here) == null) filled += 1;
        paintTile(ed, here, to);
        for (mathx.CARDINALS) |d| {
            const q = here.add(d);
            if (!grid.Level.inside(q)) continue;
            const i = grid.Level.idx(q);
            if (seen.isSet(i) or b.tile[i] != from) continue;
            seen.set(i);
            queue[tail] = @intCast(i);
            tail += 1;
        }
    }
    ed.say("Filled {d} cells of {s} with {s}", .{ filled, @tagName(from), @tagName(to) });
}

pub fn pickUp(ed: *Editor, p: P, second: bool) void {
    if (!grid.Level.inside(p)) return;
    ed.stroke = .none;
    const nd = ed.here();
    const i = grid.Level.idx(p);
    const picked: ?Tool = switch (nd.plan) {
        .bespoke => |*b| if (b.foeAt(p)) |f| .{ .foe = b.foe[f].kind } else if (b.barrel[i]) .barrel else if (b.torch.has(p)) .torch else if (nd.doorAt(p) != null) .door else null,
        .procgen => if (nd.doorAt(p) != null) .door else null,
    };
    if (picked) |t| {
        ed.setTool(t);
        return ed.say("Picked up the {s} tool", .{t.name()});
    }
    ed.preview();
    if (!ed.paintable()) return ed.say(GENERATED, .{});
    const t = ed.lv.at(p);
    ed.ink.set(.of(second), t);
    ed.setTool(.paint);
    ed.say("{s} is the {s} ink", .{ @tagName(t), @tagName(Ink.of(second)) });
}

pub fn brushBox(p: P, n: i32) grid.Box {
    return grid.Box.sized(p.sub(.{ .x = @divTrunc(n - 1, 2), .y = @divTrunc(n - 1, 2) }), n, n);
}

fn apply(ed: *Editor, p: P, erase: bool) void {
    if (erase) remove(ed, p) else place(ed, p);
}

pub fn graphMouse(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const d = &ed.desk;
    if (ed.linking) |from| {
        if (d.paint) return;
        ed.linking = null;
        const to = (if (over) ed.dotUnder(c, d.mouse) else null) orelse return ed.say(LINK_CANCELLED, .{});
        return linkDoors(ed, from, to);
    }
    if (over and d.erase_hit) {
        if (ed.dotUnder(c, d.mouse)) |l| {
            if (ed.map.door(l).to == null) return;
            ed.map.unlink(l);
            ed.relinked();
            return ed.say("Node {d} door {d} unlinked", .{ l.node, l.door });
        }
    }
    if (over and d.paint_hit) {
        if (ed.dotUnder(c, d.mouse)) |l| {
            ed.linking = l;
            return ed.say("Linking node {d} door {d}: let go on the door it leads to", .{ l.node, l.door });
        }
        if (ed.boxUnder(c, d.mouse)) |n| {
            const was = ed.map.node[n].pos;
            ed.drag = .{ .node = n, .from = d.mouse, .was = was, .grab = graphAt(ed, c, d.mouse).sub(was) };
        }
    }
    const dr = if (ed.drag) |*x| x else return;
    if (d.paint) {
        if (!dr.moved and mathx.dist(d.mouse, dr.from) > DRAG_PX) dr.moved = true;
        if (!dr.moved) return;
        ed.map.node[dr.node].pos = atlas.clampPos(graphAt(ed, c, d.mouse).sub(dr.grab));
        return;
    }
    if (!dr.moved) {
        const n = dr.node;
        ed.drag = null;
        return ed.goTo(n);
    }
    ed.keepDrag();
}

/// The graph's place under the screen point `m`.
fn graphAt(ed: *const Editor, c: rl.Rectangle, m: P) P {
    return m.sub(.{ .x = @intFromFloat(c.x), .y = @intFromFloat(c.y) }).add(.{ .x = @intFromFloat(ed.gcam[0]), .y = @intFromFloat(ed.gcam[1]) });
}

fn linkDoors(ed: *Editor, from: atlas.Link, to: atlas.Link) void {
    if (from.eq(to)) return ed.say(LINK_CANCELLED, .{});
    if (ed.map.door(from).to) |t| {
        if (t.eq(to)) return ed.say("Those doors lead to each other already", .{});
    }
    ed.map.link(from, to);
    ed.relinked();
    ed.say("Node {d} door {d} and node {d} door {d} lead to each other", .{ from.node, from.door, to.node, to.door });
}

/// `anchor` stays over the same cell.
fn zoom(ed: *Editor, c: rl.Rectangle, by: i32, anchor: P) void {
    const m = [2]f32{ @as(f32, @floatFromInt(anchor.x)) - c.x, @as(f32, @floatFromInt(anchor.y)) - c.y };
    const was = ed.px();
    ed.zoom = mathx.nudge(ed.zoom, by, ZOOMS.len);
    for (0..2) |k| ed.cam[k] += m[k] / was - m[k] / ed.px();
    ed.stroke_at = null;
}

fn fitView(ed: *Editor, c: rl.Rectangle) void {
    ed.zoom = 0;
    for (ZOOMS, 0..) |z, i| {
        if (@as(f32, grid.W) * z <= c.width and @as(f32, grid.H) * z <= c.height) ed.zoom = i;
    }
    ed.lookAt(c, grid.MIDDLE);
    ed.stroke_at = null;
}

pub fn reroll(ed: *Editor) void {
    if (!ed.here().unrolled()) return ed.say("{s} rolls a procgen node's preview again; this one is painted", .{Desk.REROLL_CAPTION});
    ed.roll = std.hash.Wyhash.hash(ed.roll, "again");
    ed.restamp();
    ed.say("Rolled again: in play it is rolled afresh each run", .{});
}

fn scrollNodes(ed: *Editor, by: i32) void {
    ed.scroll = mathx.nudge(ed.scroll, by, (ed.map.node_n -| ed.node_rows) + 1);
}

fn paintTile(ed: *Editor, p: P, t: grid.Tile) void {
    if (paintInto(ed.here(), &ed.plan().bespoke, p, t)) ed.changed();
}

/// Whether `p`'s tile changed; a door keeps its own.
fn paintInto(nd: *const atlas.Node, b: *atlas.Bespoke, p: P, t: grid.Tile) bool {
    const i = grid.Level.idx(p);
    if (b.tile[i] == t or nd.doorAt(p) != null) return false;
    b.tile[i] = t;
    nd.pruneAt(b, p);
    return true;
}

const Put = enum { there, laid, refused };

fn barrelInto(nd: *const atlas.Node, b: *atlas.Bespoke, p: P) Put {
    const i = grid.Level.idx(p);
    if (b.barrel[i]) return .there;
    if (!nd.barrelGoes(b, p)) return .refused;
    b.barrel[i] = true;
    return .laid;
}

fn putBarrel(ed: *Editor, b: *atlas.Bespoke, p: P) bool {
    const put = barrelInto(ed.here(), b, p);
    if (put == .laid) ed.changed();
    return put != .refused;
}

fn takeBarrel(ed: *Editor, b: *atlas.Bespoke, p: P) void {
    const i = grid.Level.idx(p);
    if (!b.barrel[i]) return;
    b.barrel[i] = false;
    ed.changed();
}

fn takeTorch(ed: *Editor, b: *atlas.Bespoke, p: P) void {
    if (b.torch.remove(p)) ed.changed();
}

fn takeFoe(ed: *Editor, b: *atlas.Bespoke, p: P) void {
    b.dropFoe(b.foeAt(p) orelse return);
    ed.changed();
}

pub fn place(ed: *Editor, p: P) void {
    switch (ed.tool) {
        .paint => paintTile(ed, p, ed.ink.get(.first)),
        .barrel => {
            _ = putBarrel(ed, &ed.plan().bespoke, p);
        },
        .torch => {
            const b = &ed.plan().bespoke;
            if (!ed.here().torchFits(b, p)) return ed.say("A torch " ++ TORCH_RULE, .{});
            if (!b.torch.add(p)) return ed.say("That wall holds a torch, or the node holds {d}", .{grid.MAX_TORCHES});
            ed.changed();
        },
        .foe => |k| {
            const b = &ed.plan().bespoke;
            if (!ed.here().foeFits(b, p)) return ed.say("A foe " ++ FOE_RULE, .{});
            if (b.foeAt(p)) |f| {
                if (b.foe[f].kind == k) return;
                if (!b.roomAt(p, k)) return ed.say(NO_ROOM, .{actor.row(k).name});
                b.foe[f].kind = k;
            } else if (!b.addFoe(.{ .kind = k, .at = p })) return ed.say(NO_ROOM, .{actor.row(k).name});
            ed.changed();
        },
        .door => {
            const k = ed.map.addDoor(ed.node, p) orelse return ed.say("That cell is a door, or the node holds {d}", .{grid.MAX_DOORS});
            if (ed.painted()) |b| {
                b.tile[grid.Level.idx(p)] = .floor;
                ed.here().pruneAt(b, p);
            }
            ed.say("Door {d}; the {s} tool joins it to another", .{ k, @as(Tool, .link).name() });
            ed.changed();
        },
        .link => {
            const k = ed.doorAt(p) orelse return ed.say("Link from a door", .{});
            const here = atlas.Link{ .node = ed.node, .door = k };
            const from = ed.pick orelse {
                ed.pick = here;
                return ed.say("Linking node {d} door {d}: " ++ Desk.PAINT_CAPTION ++ " the destination door on any node", .{ here.node, here.door });
            };
            ed.pick = null;
            linkDoors(ed, from, here);
        },
        .start => {
            if (ed.map.start.node == ed.node and ed.map.start.at.eq(p)) return;
            ed.map.start = .{ .node = ed.node, .at = p };
            ed.changed();
        },
    }
}

pub fn remove(ed: *Editor, p: P) void {
    if (!removable(ed, p)) return;
    switch (ed.tool) {
        .paint => paintTile(ed, p, ed.ink.get(.second)),
        .barrel => takeBarrel(ed, &ed.plan().bespoke, p),
        .torch => takeTorch(ed, &ed.plan().bespoke, p),
        .foe => takeFoe(ed, &ed.plan().bespoke, p),
        .door => {
            ed.map.removeDoor(.{ .node = ed.node, .door = ed.doorAt(p).? });
            if (ed.painted()) |b| ed.here().pruneAt(b, p);
            ed.pick = null;
            ed.changed();
        },
        .link => {
            ed.map.unlink(.{ .node = ed.node, .door = ed.doorAt(p).? });
            ed.relinked();
        },
        .start => unreachable,
    }
}

pub fn copySelection(ed: *Editor, cut: bool) void {
    const s = ed.selection orelse return ed.say("Nothing selected: {s} then drag", .{Desk.SHAPE_CAPTIONS[@intFromEnum(Shape.select)]});
    const b = ed.painted() orelse return ed.say("A procgen node's cells are rolled; there is nothing to copy", .{});
    const bd = &ed.board;
    bd.* = .{ .size = s.hi.sub(s.lo) };
    var cells = s.cells();
    while (cells.next()) |p| {
        const at = bd.at(p.sub(s.lo));
        const i = grid.Level.idx(p);
        bd.tile[at] = b.tile[i];
        bd.barrel[at] = b.barrel[i];
    }
    for (b.torches()) |t| {
        if (s.holds(t)) _ = bd.torch.add(t.sub(s.lo));
    }
    for (b.foes()) |f| {
        if (!s.holds(f.at)) continue;
        bd.foe[bd.foe_n] = .{ .kind = f.kind, .at = f.at.sub(s.lo) };
        bd.foe_n += 1;
    }
    if (cut) return clearSelection(ed);
    ed.say("Copied {d} by {d}: {s} pastes", .{ bd.size.x, bd.size.y, Desk.PASTE_CAPTION });
}

fn clearSelection(ed: *Editor) void {
    const s = ed.selection orelse return;
    const b = ed.painted() orelse return ed.say(GENERATED, .{});
    ed.drop();
    ed.gesture();
    var cells = s.cells();
    while (cells.next()) |p| {
        takeBarrel(ed, b, p);
        takeTorch(ed, b, p);
        takeFoe(ed, b, p);
        paintTile(ed, p, ed.ink.get(.second));
    }
    ed.say("Cleared to {s}", .{@tagName(ed.ink.get(.second))});
}

pub fn startPaste(ed: *Editor) void {
    if (ed.board.size.x == 0) return ed.say("Nothing copied yet", .{});
    if (!ed.paintable()) return ed.say(GENERATED, .{});
    ed.drop();
    ed.pasting = true;
    ed.say("{s} lays the copy with its corner at the cursor; {s} or {s} puts it away", .{ Desk.PAINT_CAPTION, Desk.ERASE_CAPTION, Desk.BACK_CAPTION });
}

pub fn layBoard(ed: *Editor, at: P) void {
    const laid = layInto(ed.here(), &ed.plan().bespoke, &ed.board, at);
    if (laid.changed) ed.changed();
    if (laid.left > 0) ed.say("Pasted; {d} torch(es), barrel(s) or foe(s) did not fit there", .{laid.left}) else ed.say("Pasted", .{});
}

const Pasted = struct { left: usize = 0, changed: bool = false };

pub fn layAside(ed: *Editor, at: P) Pasted {
    ed.trial = ed.plan().bespoke;
    return layInto(ed.here(), &ed.trial, &ed.board, at);
}

/// The copy laid into `b` with its corner at `at`; the paste's ghost lays it aside the same way.
fn layInto(nd: *const atlas.Node, b: *atlas.Bespoke, bd: *const Board, at: P) Pasted {
    var laid: Pasted = .{};
    var cells = bd.box(.{ .x = 0, .y = 0 }).cells();
    while (cells.next()) |q| {
        const p = at.add(q);
        const k = bd.at(q);
        if (!grid.Level.inside(p)) {
            if (bd.barrel[k]) laid.left += 1;
            continue;
        }
        if (paintInto(nd, b, p, bd.tile[k])) laid.changed = true;
        if (!bd.barrel[k]) continue;
        switch (barrelInto(nd, b, p)) {
            .there => {},
            .laid => laid.changed = true,
            .refused => laid.left += 1,
        }
    }
    for (bd.torch.slice()) |t| {
        const p = at.add(t);
        if (!grid.Level.inside(p)) {
            laid.left += 1;
        } else if (!b.torch.has(p)) {
            if (nd.torchGoes(b, p) and b.torch.add(p)) laid.changed = true else laid.left += 1;
        }
    }
    for (bd.foe[0..bd.foe_n]) |f| {
        const p = at.add(f.at);
        if (!grid.Level.inside(p)) {
            laid.left += 1;
        } else if (b.foeAt(p)) |i| {
            if (b.foe[i].kind != f.kind) laid.left += 1;
        } else if (nd.foeGoes(b, p, f.kind) and b.addFoe(.{ .kind = f.kind, .at = p })) laid.changed = true else laid.left += 1;
    }
    return laid;
}

pub fn deleteNode(ed: *Editor) void {
    ed.map.remove(ed.node);
    ed.release();
    ed.forgetNode();
    ed.renaming = false;
    ed.clampSelection();
    ed.bank();
    ed.restamp();
}

pub fn addNode(ed: *Editor, plan: atlas.Plan) void {
    const n = ed.map.add(plan) orelse return ed.say("The map holds {d} nodes", .{atlas.MAX_NODES});
    ed.select(n);
    ed.changed();
    ed.typeName();
}

/// Modals disable underlying hits; opening one suppresses its own first-frame hits.
pub fn hot(ed: *Editor, r: rl.Rectangle, live: bool, modal: bool, tip: ?[:0]const u8) struct { hot: bool, hit: bool } {
    const on_layer = !ed.fresh and ed.action == .none and (modal or (ed.modal == .none and ed.popup == null));
    const in_clip = if (ed.clip) |c| ed.mouseIn(c) else true;
    const h = live and on_layer and in_clip and ed.mouseIn(r);
    if (h and tip != null) ed.tip = tip;
    return .{ .hot = h, .hit = h and ed.desk.paint_hit };
}

pub fn button(ed: *Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return buttonOn(ed, g, r, label, on, live, false, tip);
}

pub fn buttonOn(ed: *Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, modal: bool, tip: ?[:0]const u8) bool {
    const h = hot(ed, r, live, modal, tip);
    plate(r, on, h.hot);
    const y: i32 = @intFromFloat(r.y);
    panel.drawFit(g, label, TEXT, insetW(r), false, textX(r), y + @divTrunc(@as(i32, @intFromFloat(r.height)) - TEXT, 2), if (live) look.TEXT else look.DIM);
    return h.hit;
}

pub fn insetW(r: rl.Rectangle) i32 {
    return @as(i32, @intFromFloat(r.width)) - 2 * GAP;
}

pub fn textX(r: rl.Rectangle) i32 {
    return @as(i32, @intFromFloat(r.x)) + GAP;
}

/// `s` fitted ahead of `suffix`, which is kept whole.
pub fn fitBefore(g: *const game.Game, buf: []u8, fit_buf: []u8, s: []const u8, suffix: [:0]const u8, max: i32) [:0]const u8 {
    const head = textFace(g).fit(fit_buf, s, TEXT, max - textFace(g).width(suffix, TEXT), false);
    return std.fmt.bufPrintZ(buf, "{s}{s}", .{ head, suffix }) catch "";
}

pub fn plate(r: rl.Rectangle, on: bool, hot_: bool) void {
    if (on or hot_) rl.drawRectangleRec(r, ROW_ON);
    if (on) rl.drawRectangleLinesEx(r, 1, ON);
}

pub fn row(x: i32, y: i32, w: i32) rl.Rectangle {
    return look.rect(x, y, w, ROW_H);
}

pub fn slotOf(x0: i32, span: i32, y: i32, k: usize, n: usize) rl.Rectangle {
    const ni: i32 = @intCast(n);
    const w = @divTrunc(span - GAP * (ni - 1), ni);
    return row(x0 + @as(i32, @intCast(k)) * (w + GAP), y, w);
}

pub fn cellOfRow(y: i32, k: usize, n: usize) rl.Rectangle {
    return slotOf(PAD, INNER_W, y, k, n);
}

pub fn scissor(r: rl.Rectangle) void {
    rl.beginScissorMode(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height));
}

pub const Across = struct {
    y: i32,
    n: usize,
    k: usize = 0,

    pub fn next(a: *Across) rl.Rectangle {
        std.debug.assert(a.k < a.n);
        defer a.k += 1;
        return cellOfRow(a.y, a.k, a.n);
    }

    pub fn done(a: *const Across) void {
        std.debug.assert(a.k == a.n);
    }
};

fn prepare(ed: *Editor, g: *game.Game) void {
    ed.preview();
    if (!ed.assets_stale and !g.art_ready) return;
    g.light.clearFigures();
    g.sprites.sync(ed.assets);
    ed.assets_stale = false;
    g.art_ready = false;
}

fn draw(ed: *Editor, g: *game.Game) void {
    rl.clearBackground(look.BG);
    ed.tip = null;
    const c = Editor.canvas(g);
    switch (ed.view) {
        .map => canvas.drawMap(ed, g, c),
        .graph => canvas.drawGraph(ed, g, c),
    }
    panel.drawPanel(ed, g);
    panel.drawStatus(ed, g, c);
    if (ed.popup != null) drawPopup(ed, g);
    if (ed.modal != .none) modals.drawModal(ed, g);
    drawTip(ed, g);
}

const POPUP_W: f32 = 200;
const TIP_DX: i32 = 16;
const TIP_DY: i32 = 20;
const TIP_MAX_W: i32 = 520;

fn popupLen(w: Which) usize {
    return switch (w) {
        .algo => std.enums.values(atlas.Algo).len,
        .feature => std.enums.values(atlas.Kind).len,
    };
}

fn popupRect(p: Popup, screen_h: i32) rl.Rectangle {
    const h: f32 = @floatFromInt(@as(i32, @intCast(popupLen(p.which))) * ROW_H);
    const below = p.slot.y + p.slot.height;
    const sh: f32 = @floatFromInt(screen_h);
    return .{ .x = p.slot.x, .y = if (below + h > sh) @max(0, sh - h) else below, .width = @max(p.slot.width, POPUP_W), .height = h };
}

fn drawPopup(ed: *Editor, g: *game.Game) void {
    const p = ed.popup.?;
    const pg = ed.rolled() orelse {
        ed.popup = null;
        return;
    };
    const was = pg.*;
    const box = popupRect(p, g.screen.y);
    const y: i32 = @intFromFloat(box.y);
    const x: i32 = @intFromFloat(box.x);
    const w: i32 = @intFromFloat(box.width);
    framed(x, y, w, @intFromFloat(box.height));
    switch (p.which) {
        .algo => popupRows(ed, g, atlas.Floor, &pg.floor, x, y, w),
        .feature => |i| if (i < pg.feature_n) popupRows(ed, g, atlas.Feature, &pg.feature[i], x, y, w),
    }
    if (ed.popup == null) refit(ed, pg, was);
}

fn popupRows(ed: *Editor, g: *game.Game, comptime U: type, v: *U, x: i32, top: i32, w: i32) void {
    var y = top;
    for (std.enums.values(std.meta.Tag(U))) |t| {
        if (buttonOn(ed, g, row(x, y, w), @tagName(t), t == std.meta.activeTag(v.*), true, true, null)) {
            retag(U, v, t);
            ed.popup = null;
        }
        y += ROW_H;
    }
}

pub fn retag(comptime U: type, v: *U, tag: std.meta.Tag(U)) void {
    if (tag != std.meta.activeTag(v.*)) v.* = U.of(tag);
}

pub fn refit(ed: *Editor, pg: *atlas.Procgen, was: atlas.Procgen) void {
    pg.* = pg.fit();
    if (!std.meta.eql(was, pg.*)) ed.changed();
}

fn drawTip(ed: *const Editor, g: *game.Game) void {
    const tip = ed.tip orelse return;
    var fit_buf: [LINE]u8 = undefined;
    const s = textFace(g).fit(&fit_buf, tip, SMALL, TIP_MAX_W, false);
    const size = tagSize(g, s, GAPS);
    const x = std.math.clamp(ed.desk.mouse.x + TIP_DX, 0, @max(0, g.screen.x - size.x));
    const y = if (ed.desk.mouse.y + TIP_DY + size.y > g.screen.y) ed.desk.mouse.y - TIP_DY - size.y else ed.desk.mouse.y + TIP_DY;
    drawTag(g, s, .{ .x = x, .y = y }, GAPS, PANEL_BG, look.EDGE);
}

pub const GAPS = P{ .x = GAP, .y = GAP };

fn tagSize(g: *game.Game, s: [:0]const u8, pad: P) P {
    return .{ .x = textFace(g).width(s, SMALL) + 2 * pad.x, .y = SMALL + 2 * pad.y };
}

pub fn drawTag(g: *game.Game, s: [:0]const u8, at: P, pad: P, bg: rl.Color, edge: ?rl.Color) void {
    const size = tagSize(g, s, pad);
    rl.drawRectangle(at.x, at.y, size.x, size.y, bg);
    if (edge) |e| rl.drawRectangleLines(at.x, at.y, size.x, size.y, e);
    textFace(g).draw(s, at.x + pad.x, at.y + pad.y, SMALL, look.TEXT);
}

fn framed(x: i32, y: i32, w: i32, h: i32) void {
    rl.drawRectangle(x, y, w, h, PANEL_BG);
    rl.drawRectangleLines(x, y, w, h, look.EDGE);
}

const Frame = struct {
    x: i32,
    w: i32,
    top: i32,
    y: i32,

    pub fn buttonX(f: Frame) i32 {
        return f.x + f.w - PAD - MODAL_BTN_W;
    }
};

pub fn modalFrame(g: *game.Game, want_w: i32, h: i32, title: [:0]const u8, keep_end: bool) Frame {
    const w = @min(want_w, g.screen.x - 2 * PAD);
    const x = @divTrunc(g.screen.x - w, 2);
    const y = @max(0, @divTrunc(g.screen.y - h, 2));
    framed(x, y, w, h);
    const top = y + PAD;
    panel.drawFit(g, title, HEAD, w - 2 * PAD, keep_end, x + PAD, top, look.TEXT);
    return .{ .x = x, .w = w, .top = top, .y = y + MODAL_HEAD };
}

pub fn keyed(comptime what: []const u8, comptime key: []const u8) [:0]const u8 {
    return what ++ " (" ++ key ++ ")";
}

pub fn legal(ed: *Editor, p: P) bool {
    const nd = ed.here();
    if (!ed.tool.fits(nd)) return false;
    return switch (ed.tool) {
        .paint, .start => true,
        .barrel => nd.barrelGoes(&nd.plan.bespoke, p),
        .torch => nd.torchGoes(&nd.plan.bespoke, p),
        .foe => |k| nd.foeGoes(&nd.plan.bespoke, p, k),
        .door => nd.takesDoor(p),
        .link => nd.doorAt(p) != null,
    };
}

pub fn removable(ed: *Editor, p: P) bool {
    const nd = ed.here();
    if (!ed.tool.fits(nd)) return false;
    const i = grid.Level.idx(p);
    return switch (ed.tool) {
        .paint => true,
        .barrel => nd.plan.bespoke.barrel[i],
        .torch => nd.plan.bespoke.torch.has(p),
        .foe => nd.plan.bespoke.foeAt(p) != null,
        .door => nd.doorAt(p) != null,
        .link => if (nd.doorAt(p)) |k| nd.door[k].to != null else false,
        .start => false,
    };
}

/// A square picture `size` across, centred in a button `top` below its edge.
pub fn pictureIn(r: rl.Rectangle, size: f32, top: f32) rl.Rectangle {
    return .{ .x = r.x + (r.width - size) / 2, .y = r.y + top, .width = size, .height = size };
}

pub fn sprite(t: rl.Texture2D, r: rl.Rectangle) void {
    look.stretch(t, r, look.LIT);
}

pub fn figure(g: *game.Game, tex: ?rl.Texture2D, l: look.Look, r: rl.Rectangle) void {
    if (tex) |t| sprite(t, r) else glyph(g, l.ch, r, l.fg);
}

const GlyphBox = struct { x: i32, y: i32, size: i32 };

fn inkIn(r: rl.Rectangle) GlyphBox {
    const at = look.middleAt(r);
    return .{ .x = at.x, .y = at.y, .size = @intFromFloat(r.width * GLYPH_OF_CELL) };
}

pub fn glyph(g: *game.Game, ch: u8, r: rl.Rectangle, col: rl.Color) void {
    const m = inkIn(r);
    g.face.glyph(ch, m.x, m.y, m.size, col);
}

pub fn tileGlyph(g: *game.Game, t: grid.Tile, r: rl.Rectangle) void {
    const m = inkIn(r);
    look.inkTile(&g.face, t, m.x, m.y, m.size);
}

const SHOT_ZOOM = zoomOf(32);
const SHOT_BRUSH = std.mem.indexOfScalar(i32, &BRUSHES, 3).?;

/// DEV ONLY: the posed map's map mid link-pick, its graph, its procgen node's generator, then the object viewer.
pub fn shoot(g: *game.Game, target: rl.RenderTexture2D, map_path: [:0]const u8, graph_path: [:0]const u8, gen_path: [:0]const u8, objects_path: [:0]const u8) !void {
    const ed = try Editor.create(std.heap.c_allocator);
    defer ed.destroy();
    const w = ed.map;
    w.* = .{};
    _ = w.add(.{ .bespoke = .{} });
    _ = w.add(.{ .procgen = .{} });
    _ = w.add(.{ .procgen = .{} });
    _ = w.node[0].rename("Gatehouse");
    _ = w.node[1].rename("The Warrens");
    ed.setPath(atlas.mapPath("test_shot"));
    ed.zoom = SHOT_ZOOM;
    ed.brush = SHOT_BRUSH;
    ed.tool = .paint;
    laySpan(ed, .{ .from = .{ .x = 8, .y = 6 }, .erase = false, .shape = .rect }, .{ .x = 23, .y = 15 });
    const posed = [_]struct { t: Tool, at: P }{
        .{ .t = .torch, .at = .{ .x = 14, .y = 5 } },
        .{ .t = .barrel, .at = .{ .x = 8, .y = 6 } },
        .{ .t = .{ .foe = .rat }, .at = .{ .x = 18, .y = 10 } },
        .{ .t = .{ .foe = .slime }, .at = .{ .x = 20, .y = 12 } },
        .{ .t = .door, .at = .{ .x = 24, .y = 10 } },
        .{ .t = .door, .at = .{ .x = 16, .y = 16 } },
        .{ .t = .start, .at = .{ .x = 10, .y = 10 } },
    };
    for (posed) |q| {
        ed.tool = q.t;
        place(ed, q.at);
    }
    for ([_]usize{ 1, 2 }) |n| {
        ed.select(n);
        ed.tool = .door;
        place(ed, .{ .x = 5, .y = 5 });
        place(ed, .{ .x = 60, .y = 40 });
    }
    ed.map.link(.{ .node = 1, .door = 1 }, .{ .node = 2, .door = 0 });
    ed.select(1);
    ed.tool = .link;
    place(ed, .{ .x = 5, .y = 5 });
    ed.select(0);
    place(ed, .{ .x = 24, .y = 10 });
    place(ed, .{ .x = 16, .y = 16 });
    ed.tool = .paint;
    ed.cam = .{ 4, 2 };
    g.screen = .{ .x = target.texture.width, .y = target.texture.height };
    const hover_at = ed.cellRect(Editor.canvas(g), .{ .x = 14, .y = 13 });
    ed.desk.mouse = .{ .x = @as(i32, @intFromFloat(hover_at.x)) + 8, .y = @as(i32, @intFromFloat(hover_at.y)) + 8 };
    ed.said_t = 0;
    for (std.enums.values(View), [_][:0]const u8{ map_path, graph_path }) |v, p| {
        ed.view = v;
        try snap(ed, g, target, p);
    }
    ed.view = .map;
    ed.select(1);
    ed.lower = .generator;
    const fo = &ed.map.node[1].plan.procgen.foes;
    _ = fo.addMakeup();
    fo.makeup[fo.makeup_n - 1] = pack.Makeup.of(&.{ .slime, .bloat, .rat, .rat, .rat });
    fo.makeup[fo.makeup_n - 1].weight = 3;
    ed.desk.mouse = .{ .x = 0, .y = 0 };
    prepare(ed, g);
    rl.beginTextureMode(target);
    draw(ed, g);
    rl.endTextureMode();
    ed.gen_top = ed.gen_most;
    try snap(ed, g, target, gen_path);
    ed.modal = .objects;
    for (SEEN, 0..) |s, i| {
        if (std.meta.eql(s, Seen{ .body = .slime })) ed.seen_at = i;
    }
    try snap(ed, g, target, objects_path);
    ed.modal = .help;
    var path: [std.fs.max_path_bytes]u8 = undefined;
    try snap(ed, g, target, try std.fmt.bufPrintZ(&path, "{s}/edit-help.png", .{std.fs.path.dirname(map_path) orelse "."}));
}

fn snap(ed: *Editor, g: *game.Game, target: rl.RenderTexture2D, path: [:0]const u8) !void {
    prepare(ed, g);
    rl.beginTextureMode(target);
    draw(ed, g);
    rl.endTextureMode();
    try game.shots.exportTarget(target, path);
}
