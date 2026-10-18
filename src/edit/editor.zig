const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const lume = @import("../map/lume.zig");
const terrain = @import("../map/biome/terrain.zig");
const scatter = @import("../map/feature/scatter.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
const look = @import("../gfx/look.zig");
const dual = @import("../gfx/ground.zig");
const font = @import("../gfx/font.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");

const P = mathx.P;
const Desk = input.Desk;

const PANEL_W: i32 = 340;
const PAD: i32 = 12;
const ROW_H: i32 = 26;
const NODE_H: i32 = 46;
const GAP: i32 = 6;
const SECTION_GAP: i32 = GAP * 3;
const BLOCK_GAP: i32 = GAP * 2;
const ROW_STEP: i32 = ROW_H + GAP;
const TEXT: i32 = font.BODY;
const SMALL = font.SMALL;
const HEAD: i32 = 24;

comptime {
    std.debug.assert(font.isNative(HEAD));
}
const INNER_W: i32 = PANEL_W - PAD * 2;
const ZOOMS = [_]f32{ 8, 16, 32, 64 };
const ZOOM_AT = zoomOf(16);
const BRUSHES = [_]i32{ 1, 2, 3, 5 };

fn zoomOf(px: f32) usize {
    return std.mem.indexOfScalar(f32, &ZOOMS, px).?;
}

const PAN_PX_S: f32 = 900;
const SAY_S: f32 = 4;
const LINE: usize = 200;
const UNDO_CAP: usize = 24;
const PATH_FIELD_MAX: usize = 256;
const FIELD_MAX: usize = 32;
/// A press that moves this far is a drag, not a click.
const DRAG_PX: i32 = 4;
/// Door numbers crowd their glyph below this many pixels a cell.
const LABEL_PX: f32 = 32;
const LABEL_PAD = P{ .x = 2, .y = 1 };
const GLYPH_OF_CELL: f32 = @as(f32, @floatFromInt(look.GLYPH_PX)) / @as(f32, @floatFromInt(look.SPRITE_PX));
const THUMB: i32 = 2;
const BOX_W: i32 = grid.W * THUMB;
const BOX_TOP: i32 = TEXT + 2 * TITLE_DY;
const BOX_H: i32 = BOX_TOP + grid.H * THUMB;
const LINK_W: f32 = 2;
const DOT_R: f32 = 4;
/// Pixels past a door's dot a press still takes it.
const DOT_SLOP: f32 = 3;
const MODAL_W: i32 = 600;
const MODAL_HEAD: i32 = PAD + HEAD + PAD;
const MODAL_ROWS: usize = 12;
const MODAL_BTN_W: i32 = 150;
const LABEL_W: i32 = 96;
const STEP_W: i32 = 24;
const STEP_PITCH: i32 = STEP_W + GAP;
const SHIFT_STEP: i32 = 5;
const WEIGHT_W: i32 = 30;
const MEMBER_W: i32 = 24;
const MEMBER_GAP: i32 = 2;
const WEIGHT_SPAN: i32 = 2 * STEP_W + WEIGHT_W;
const BRUSH_W: i32 = 48;
const BRUSH_SPAN: i32 = 2 * STEP_W + BRUSH_W;
const MEMBERS_X: i32 = WEIGHT_SPAN + BLOCK_GAP;
const MAKEUP_TOOLS_X: i32 = INNER_W - @as(i32, MAKEUP_TOOLS.len) * STEP_PITCH + GAP;
const TORCH_STEP: i32 = 10;
const TEXT_DY: i32 = @divTrunc(ROW_H - TEXT, 2);
const SMALL_DY: i32 = @divTrunc(ROW_H - SMALL, 2);
const TITLE_DY: i32 = 3;
const NODE_GAP: i32 = 2;
const DETAIL_DY: i32 = TEXT + 1;

comptime {
    std.debug.assert(atlas.GRAPH_STEP.x > BOX_W and atlas.GRAPH_STEP.y > BOX_H);
    std.debug.assert(FIELD_MAX >= atlas.NAME_MAX and FIELD_MAX <= atlas.STEM_MAX);
    std.debug.assert(PATH_FIELD_MAX >= atlas.PATH_MAX);
    std.debug.assert(MEMBERS_X + @as(i32, pack.MAKEUP_MAX) * (MEMBER_W + MEMBER_GAP) <= MAKEUP_TOOLS_X);
}

const PANEL_BG = look.EDIT_PANEL;
const ROW_ON = look.EDIT_ROW_ON;
const ON = look.EDIT_ON;
const HOVER = look.EDIT_HOVER;
const PICKED = look.EDIT_PICKED;
const UNLINKED = look.EDIT_UNLINKED;
const WARN = look.EDIT_WARN;
const START = look.body(actor.HERO);
const START_MARK = [_]u8{ START.ch, ' ' };

fn kindName(k: actor.Kind) [:0]const u8 {
    return switch (k) {
        inline else => |f| comptime menu.capital(actor.row(f).name),
    };
}

const Tool = union(enum) {
    paint,
    barrel,
    torch,
    foe: actor.Kind,
    door,
    link,
    start,

    fn fits(t: Tool, nd: *const atlas.Node) bool {
        return !nd.unrolled() or !t.generated();
    }

    fn eql(a: Tool, b: Tool) bool {
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

    fn broad(t: Tool) bool {
        return t == .paint;
    }

    fn look_(t: Tool) look.Look {
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

    fn name(t: Tool) [:0]const u8 {
        return switch (t) {
            .foe => |k| kindName(k),
            inline else => |_, tag| comptime menu.named(tag),
        };
    }

    fn tip(t: Tool) [:0]const u8 {
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
            .link => "click a door, then the door it leads to on any node; " ++ Desk.ERASE_CAPTION ++ " unlinks",
            .start => "where the map begins, and " ++ Desk.PLAY_CAPTION ++ " plays from",
        };
    }
};

const TOOLS = blk: {
    var out: []const Tool = &.{};
    for (std.enums.values(std.meta.Tag(Tool))) |tag| {
        if (tag == .foe) {
            for (actor.FOES) |k| out = out ++ &[_]Tool{.{ .foe = k }};
        } else out = out ++ &[_]Tool{@unionInit(Tool, @tagName(tag), {})};
    }
    break :blk out[0..out.len].*;
};
const TORCH_RULE = "hangs on a wall with floor below it";
const PALETTE_RULE = Desk.PAINT_CAPTION ++ " first ink, " ++ Desk.ERASE_CAPTION ++ " second";
const FOE_RULE = "stands on open floor";
const NO_ROOM = "The node has no room for another {s}";
const UNGENERATED = blk: {
    var names: []const []const u8 = &.{};
    for (TOOLS) |t| {
        if (!t.generated()) names = names ++ &[_][]const u8{@tagName(t)};
    }
    break :blk menu.joined(names, .@"and");
};
const GENERATED = "A procgen node is generated; it takes only " ++ UNGENERATED ++ " (" ++ Desk.REROLL_CAPTION ++ " rolls it again)";

comptime {
    @setEvalBranchQuota(10_000);
    std.debug.assert(TOOLS.len == Desk.TOOL_KEYS.len);
    for (actor.FOES) |k| std.debug.assert(k.stocked());
}

/// How the paint tool lays its ink, in `Desk.SHAPE_KEYS`' order; a selection is any tool's.
const Shape = enum {
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

    fn tip(s: Shape) [:0]const u8 {
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

const SHAPES = std.enums.values(Shape);
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
const CRIB_MAP = Desk.PAINT_CAPTION ++ " place" ++ SEP ++ Desk.ERASE_CAPTION ++ " second ink or remove" ++ SEP ++ Desk.TOOLS_CAPTION ++
    " tool" ++ SEP ++ Desk.SHAPES_CAPTION ++ " shape" ++ SEP ++ Desk.PICK_CAPTION ++ " pick" ++ SEP ++ Desk.HELP_CAPTION ++ " every key";
const CRIB_GRAPH = Desk.PAINT_CAPTION ++ " open a node" ++ SEP ++ "drag it to move it, or a door's dot to another's to link them" ++ SEP ++
    Desk.ERASE_CAPTION ++ " on a dot unlinks" ++ SEP ++ Desk.GRAPH_CAPTION ++ " back to the map" ++ SEP ++ Desk.HELP_CAPTION ++ " every key";
const HelpSection = struct { head: [:0]const u8, lines: []const [:0]const u8 };
const HELP = [_]HelpSection{
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
        Desk.PLAY_CAPTION ++ " play from the start" ++ SEP ++ Desk.PLAY_HERE_CAPTION ++ " from the cursor, and either back" ++ SEP ++ Desk.FULLSCREEN_CAPTION ++ " fullscreen" ++ SEP ++
            Desk.BACK_CAPTION ++ " back a step",
    } },
};
const HELP_ROWS = blk: {
    var n: i32 = 0;
    for (HELP) |s| n += 1 + s.lines.len;
    break :blk n;
};
const STATUS_H: i32 = GAP * 2 + TEXT * 2 + GAP;

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

/// `key` in `crib` as a word of its own, not inside another key's caption.
fn namesKey(comptime crib: []const u8, comptime key: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, crib, from, key)) |i| : (from = i + 1) {
        const end = i + key.len;
        if (crib[i - 1] == ' ' and end < crib.len and (crib[end] == ' ' or crib[end] == ',')) return true;
    }
    return false;
}
const LINK_CANCELLED = "Link cancelled";

pub const Action = union(enum) { none, play: atlas.Start, leave, quit };

const View = enum {
    map,
    graph,

    fn other(v: View) View {
        return if (v == .map) .graph else .map;
    }
};
const Lower = enum {
    nodes,
    things,
    generator,
};
const Stroke = enum { none, paint, erase };
const Ink = enum {
    first,
    second,

    fn of(erase: bool) Ink {
        return if (erase) .second else .first;
    }
};
const INKS = std.enums.values(Ink);
/// Asked for, and done once any unsaved changes are saved or let go.
const Pending = enum { leave, quit, open, new };
const Modal = enum { none, confirm, name, open, help, objects };
const Naming = enum { new, save_as };

fn Text(comptime N: usize) type {
    return struct {
        const Self = @This();
        buf: [N]u8 = undefined,
        n: usize = 0,
        cap: usize = N,

        fn text(f: *const Self) []const u8 {
            return f.buf[0..f.n];
        }

        fn set(f: *Self, s: []const u8, cap: usize) void {
            f.cap = @min(cap, N);
            f.n = @min(s.len, f.cap);
            @memcpy(f.buf[0..f.n], s[0..f.n]);
        }

        fn put(f: *Self, s: []const u8) void {
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

/// A node's box dragged on the graph; `was` is where it stood, which `drop` puts it back to.
const Drag = struct { node: usize, grab: P, from: P, was: P, moved: bool = false };
const Span = struct { from: P, erase: bool, shape: Spanned };

const Board = struct {
    size: P = .{ .x = 0, .y = 0 },
    tile: [grid.CELLS]grid.Tile = undefined,
    barrel: [grid.CELLS]bool = undefined,
    torch: grid.Torches = .{},
    foe: [atlas.MAX_FOES]atlas.Foe = undefined,
    foe_n: usize = 0,

    fn at(b: *const Board, p: P) usize {
        return @intCast(p.y * b.size.x + p.x);
    }

    fn box(b: *const Board, lo: P) grid.Box {
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

const Seen = union(enum) {
    tile: grid.Tile,
    body: actor.Kind,
    barrel,
    torch,
    door,
};

const SEEN = blk: {
    var out: []const Seen = &.{};
    for (std.meta.fields(Seen)) |f| {
        if (f.type == void) {
            out = out ++ &[_]Seen{@unionInit(Seen, f.name, {})};
        } else for (std.enums.values(f.type)) |v| out = out ++ &[_]Seen{@unionInit(Seen, f.name, v)};
    }
    break :blk out[0..out.len].*;
};

const Popup = struct { slot: rl.Rectangle, which: Which };
const Which = union(enum) { algo, feature: usize };

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
    fn setPath(ed: *Editor, p: []const u8) void {
        var q = p;
        while (q.len > 2 and q[0] == '.' and (q[1] == '/' or q[1] == '\\')) q = q[2..];
        ed.file.put(q);
        std.mem.replaceScalar(u8, ed.file.buf[0..ed.file.n], '\\', '/');
    }

    fn plan(ed: *Editor) *atlas.Plan {
        return &ed.here().plan;
    }

    fn px(ed: *const Editor) f32 {
        return ZOOMS[ed.zoom];
    }

    fn brushSize(ed: *const Editor) i32 {
        return BRUSHES[ed.brush];
    }

    fn stepBrush(ed: *Editor, by: i32) void {
        ed.brush = mathx.nudge(ed.brush, std.math.sign(by), BRUSHES.len);
    }

    fn say(ed: *Editor, comptime fmt: []const u8, args: anytype) void {
        ed.said.say(fmt, args);
        ed.said_t = SAY_S;
    }

    /// A press begins a gesture; everything it changes is one undo.
    fn gesture(ed: *Editor) void {
        ed.scratch.* = ed.map.*;
        ed.banked = false;
    }

    fn bank(ed: *Editor) void {
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

    fn undo(ed: *Editor) void {
        ed.keepDrag();
        if (ed.hist_at == 0) return ed.say("Nothing to undo", .{});
        ed.hist_at -= 1;
        ed.swapStep(ed.hist_at);
        ed.dirty = ed.saved_at != ed.hist_at;
        ed.say("Undone ({d} more)", .{ed.hist_at});
    }

    fn redo(ed: *Editor) void {
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

    fn drop(ed: *Editor) void {
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

    fn setTool(ed: *Editor, t: Tool) void {
        if (!t.fits(ed.here())) return ed.say(GENERATED, .{});
        if (!t.eql(ed.tool)) ed.release();
        ed.tool = t;
    }

    fn setShape(ed: *Editor, s: Shape) void {
        if (s != ed.shape) ed.release();
        ed.shape = s;
        if (s != .select and !ed.tool.broad() and ed.paintable()) ed.setTool(.paint);
    }

    fn setView(ed: *Editor, v: View) void {
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

    /// The link tool's first door and a paste carry over: either may end on another node.
    fn select(ed: *Editor, n: usize) void {
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

    fn preview(ed: *Editor) void {
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

    fn shownFoes(ed: *const Editor) []const atlas.Foe {
        return ed.shown[0..ed.shown_n];
    }

    fn arrival(ed: *Editor) P {
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

    fn cutOff(ed: *const Editor, i: usize) bool {
        return !ed.lv.tile[i].solid() and ed.reach_dist[i] < 0;
    }

    fn standable(ed: *Editor, from: atlas.Start) bool {
        return ed.map.standable(from, &ed.thumb_lv);
    }

    fn doorAt(ed: *Editor, p: P) ?usize {
        return ed.here().doorAt(p);
    }

    fn nodeTitle(ed: *Editor, n: usize, buf: []u8) [:0]const u8 {
        var name: [atlas.TITLE_MAX]u8 = undefined;
        const mark: []const u8 = if (ed.map.start.node == n) &START_MARK else "";
        if (ed.renamingNode(n)) return std.fmt.bufPrintZ(buf, "{s}{d}  {s}" ++ menu.CARET, .{ mark, n, ed.field.text() }) catch "";
        return std.fmt.bufPrintZ(buf, "{s}{d}  {s}", .{ mark, n, ed.nodeName(n, &name) }) catch "";
    }

    fn renamingNode(ed: *const Editor, n: usize) bool {
        return ed.renaming and n == ed.node;
    }

    fn playStart(ed: *Editor) void {
        ed.action = .{ .play = ed.map.start };
    }

    fn nodeName(ed: *Editor, n: usize, buf: *[atlas.TITLE_MAX]u8) []const u8 {
        return ed.map.node[n].title(n, buf);
    }

    fn here(ed: *Editor) *atlas.Node {
        return &ed.map.node[ed.node];
    }

    fn paintable(ed: *Editor) bool {
        return @as(Tool, .paint).fits(ed.here());
    }

    fn rolled(ed: *Editor) ?*atlas.Procgen {
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

    fn generator(ed: *Editor) ?*atlas.Procgen {
        return if (ed.lower == .generator) ed.rolled() else null;
    }

    fn goTo(ed: *Editor, n: usize) void {
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

    fn commit(ed: *Editor) void {
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

    fn save(ed: *Editor) bool {
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

    fn ask(ed: *Editor, m: Modal) void {
        ed.drop();
        ed.modal = m;
        ed.fresh = true;
    }

    fn askName(ed: *Editor, n: Naming) void {
        ed.naming = n;
        ed.field.put("");
        ed.ask(.name);
    }

    fn askOpen(ed: *Editor) void {
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

    fn openListed(ed: *Editor, i: usize) void {
        if (ed.listing.open(i)) return ed.showListing();
        ed.pending_path.put(ed.listing.at(i));
        ed.modal = .none;
        ed.request(.open);
    }

    fn namedPath(ed: *const Editor, buf: []u8) ?[]const u8 {
        return atlas.pathFor(buf, atlas.folderOf(ed.path()), ed.field.text());
    }

    fn named(ed: *Editor) void {
        var buf: [atlas.PATH_MAX]u8 = undefined;
        const p = ed.namedPath(&buf) orelse return ed.say("Type a name of letters or digits", .{});
        if (std.fs.cwd().access(p, .{})) {
            return ed.say("{s} is there already; open it, or pick another name", .{p});
        } else |_| {}
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

    fn startRename(ed: *Editor) void {
        ed.drop();
        ed.gesture();
        ed.typeName();
    }

    fn typeName(ed: *Editor) void {
        ed.drop();
        ed.field.set(ed.here().name(), atlas.NAME_MAX);
        ed.renaming = true;
    }

    fn commitRename(ed: *Editor) void {
        ed.renaming = false;
        const nd = ed.here();
        const renamed = nd.rename(ed.field.text()) orelse return ed.say("A name is {d} letters at most", .{atlas.NAME_MAX});
        if (renamed) ed.bank();
    }

    fn canvas(g: *const game.Game) rl.Rectangle {
        return look.rect(PANEL_W, 0, @max(0, g.screen.x - PANEL_W), @max(0, g.screen.y - STATUS_H));
    }

    /// Where cell 0,0's corner lands, on a whole pixel so sprites never straddle one.
    fn origin(ed: *const Editor, c: rl.Rectangle) [2]f32 {
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

    fn dotUnder(ed: *const Editor, c: rl.Rectangle, m: P) ?atlas.Link {
        for (0..ed.map.node_n) |n| {
            for (0..ed.map.node[n].door_n) |k| {
                const l = atlas.Link{ .node = n, .door = k };
                if (rl.checkCollisionPointCircle(vec(m), ed.dotAt(c, l), DOT_R + DOT_SLOP)) return l;
            }
        }
        return null;
    }

    fn mouseCell(ed: *const Editor, c: rl.Rectangle) P {
        return ed.cellAt(c, ed.desk.mouse);
    }

    fn mouseIn(ed: *const Editor, r: rl.Rectangle) bool {
        return rl.checkCollisionPointRec(vec(ed.desk.mouse), r);
    }

    fn cellRect(ed: *const Editor, c: rl.Rectangle, p: P) rl.Rectangle {
        const o = ed.origin(c);
        return .{
            .x = o[0] + @as(f32, @floatFromInt(p.x)) * ed.px(),
            .y = o[1] + @as(f32, @floatFromInt(p.y)) * ed.px(),
            .width = ed.px(),
            .height = ed.px(),
        };
    }

    fn lookAt(ed: *Editor, c: rl.Rectangle, p: P) void {
        const at = mathx.centre(p);
        ed.cam = .{ at[0] - c.width / ed.px() * 0.5, at[1] - c.height / ed.px() * 0.5 };
    }

    fn boxAt(ed: *const Editor, c: rl.Rectangle, n: usize) rl.Rectangle {
        const pos = ed.map.node[n].pos;
        return .{
            .x = c.x + @as(f32, @floatFromInt(pos.x)) - ed.gcam[0],
            .y = c.y + @as(f32, @floatFromInt(pos.y)) - ed.gcam[1],
            .width = @floatFromInt(BOX_W),
            .height = @floatFromInt(BOX_H),
        };
    }

    fn boxUnder(ed: *const Editor, c: rl.Rectangle, m: P) ?usize {
        var n = ed.map.node_n;
        while (n > 0) {
            n -= 1;
            if (rl.checkCollisionPointRec(vec(m), ed.boxAt(c, n))) return n;
        }
        return null;
    }

    fn dotAt(ed: *const Editor, c: rl.Rectangle, l: atlas.Link) rl.Vector2 {
        const b = ed.boxAt(c, l.node);
        const d = ed.map.door(l).at;
        return .{
            .x = b.x + @as(f32, @floatFromInt(d.x * THUMB + @divTrunc(THUMB, 2))),
            .y = b.y + @as(f32, @floatFromInt(BOX_TOP + d.y * THUMB + @divTrunc(THUMB, 2))),
        };
    }
};

fn freshMap(w: *atlas.Atlas) void {
    w.* = .{};
    const n = w.add(.{ .bespoke = .{} }).?;
    const b = &w.node[n].plan.bespoke;
    var cells = grid.Box.centred(FRESH_ROOM.x, FRESH_ROOM.y).cells();
    while (cells.next()) |p| b.tile[grid.Level.idx(p)] = .floor;
    w.start = .{ .node = n, .at = grid.MIDDLE };
}

const FRESH_ROOM = P{ .x = 15, .y = 9 };

fn vec(p: P) rl.Vector2 {
    return .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
}

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
        if (d.zoom_in or d.zoom_out) zoom(ed, c, if (d.zoom_in) 1 else -1, .{ .x = @intFromFloat(c.x + c.width / 2), .y = @intFromFloat(c.y + c.height / 2) });
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

fn escape(ed: *Editor) void {
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

fn modalKeys(ed: *Editor) void {
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
        .objects => if (d.nav != 0) {
            ed.seen_at = mathx.wrap(ed.seen_at, d.nav, SEEN.len);
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

fn mapMouse(ed: *Editor, c: rl.Rectangle, over: bool) void {
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

const Ghost = struct {
    ed: *Editor,
    g: *game.Game,
    c: rl.Rectangle,
    ink: grid.Tile,
    view: grid.Box,

    fn of(ed: *Editor, g: *game.Game, c: rl.Rectangle, ink: grid.Tile) Ghost {
        return .{ .ed = ed, .g = g, .c = c, .ink = ink, .view = visible(ed, c) };
    }

    fn at(h: Ghost, p: P) void {
        if (h.view.holds(p)) ghostInk(h.ed, h.g, h.c, p, h.ink);
    }
};

fn eachBrushCell(ed: *const Editor, p: P, to: anytype) void {
    if (!ed.tool.broad()) return to.at(p);
    var cells = brushBox(p, ed.brushSize()).cells();
    while (cells.next()) |q| {
        if (grid.Level.inside(q)) to.at(q);
    }
}

fn eachSpanCell(ed: *const Editor, s: Span, end: P, to: anytype) void {
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

fn spanOf(ed: *Editor, shift: bool) ?Spanned {
    if (ed.shape == .select) return .select;
    if (!ed.tool.broad() or !ed.tool.fits(ed.here())) return null;
    if (shift) return .rect;
    return ed.shape.dragged();
}

fn laySpan(ed: *Editor, s: Span, to: P) void {
    eachSpanCell(ed, s, to, Laid{ .ed = ed, .erase = s.erase });
    if (s.shape != .select) return;
    const b = grid.Box.between(s.from, to);
    ed.selection = b;
    ed.say("{d} by {d} selected: {s} copies, {s} cuts, {s} clears", .{ b.width(), b.height(), Desk.COPY_CAPTION, Desk.CUT_CAPTION, Desk.DELETE_CAPTION });
}

fn fill(ed: *Editor, p: P, second: bool) void {
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

fn pickUp(ed: *Editor, p: P, second: bool) void {
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
    const t = ed.lv.at(p);
    ed.ink.set(.of(second), t);
    ed.setTool(.paint);
    ed.say("{s} is the {s} ink", .{ @tagName(t), @tagName(Ink.of(second)) });
}

fn brushBox(p: P, n: i32) grid.Box {
    return grid.Box.sized(p.sub(.{ .x = @divTrunc(n - 1, 2), .y = @divTrunc(n - 1, 2) }), n, n);
}

fn apply(ed: *Editor, p: P, erase: bool) void {
    if (erase) remove(ed, p) else place(ed, p);
}

fn graphMouse(ed: *Editor, c: rl.Rectangle, over: bool) void {
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

fn reroll(ed: *Editor) void {
    if (!ed.here().unrolled()) return ed.say("{s} rolls a procgen node's preview again; this one is painted", .{Desk.REROLL_CAPTION});
    ed.roll = std.hash.Wyhash.hash(ed.roll, "again");
    ed.restamp();
    ed.say("Rolled again: in play it is rolled afresh each run", .{});
}

fn scrollNodes(ed: *Editor, by: i32) void {
    ed.scroll = mathx.nudge(ed.scroll, by, (ed.map.node_n -| ed.node_rows) + 1);
}

fn paintTile(ed: *Editor, p: P, t: grid.Tile) void {
    const b = &ed.plan().bespoke;
    const i = grid.Level.idx(p);
    if (b.tile[i] == t or ed.doorAt(p) != null) return;
    b.tile[i] = t;
    ed.here().pruneAt(b, p);
    ed.changed();
}

fn putBarrel(ed: *Editor, b: *atlas.Bespoke, p: P) bool {
    const i = grid.Level.idx(p);
    if (b.barrel[i]) return true;
    if (!ed.here().barrelGoes(b, p)) return false;
    b.barrel[i] = true;
    ed.changed();
    return true;
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

fn place(ed: *Editor, p: P) void {
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
                return ed.say("Linking node {d} door {d}: click the door it leads to, on any node", .{ here.node, here.door });
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

fn remove(ed: *Editor, p: P) void {
    switch (ed.tool) {
        .paint => paintTile(ed, p, ed.ink.get(.second)),
        .barrel => takeBarrel(ed, &ed.plan().bespoke, p),
        .torch => takeTorch(ed, &ed.plan().bespoke, p),
        .foe => takeFoe(ed, &ed.plan().bespoke, p),
        .door => {
            const k = ed.doorAt(p) orelse return;
            ed.map.removeDoor(.{ .node = ed.node, .door = k });
            if (ed.painted()) |b| ed.here().pruneAt(b, p);
            ed.pick = null;
            ed.changed();
        },
        .link => {
            const k = ed.doorAt(p) orelse return;
            if (ed.here().door[k].to == null) return;
            ed.map.unlink(.{ .node = ed.node, .door = k });
            ed.relinked();
        },
        .start => {},
    }
}

fn copySelection(ed: *Editor, cut: bool) void {
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

fn startPaste(ed: *Editor) void {
    if (ed.board.size.x == 0) return ed.say("Nothing copied yet", .{});
    if (!ed.paintable()) return ed.say(GENERATED, .{});
    ed.drop();
    ed.pasting = true;
    ed.say("{s} lays the copy with its corner at the cursor; {s} or {s} puts it away", .{ Desk.PAINT_CAPTION, Desk.ERASE_CAPTION, Desk.BACK_CAPTION });
}

fn layBoard(ed: *Editor, at: P) void {
    const b = &ed.plan().bespoke;
    const bd = &ed.board;
    var left: usize = 0;
    var cells = bd.box(.{ .x = 0, .y = 0 }).cells();
    while (cells.next()) |q| {
        const p = at.add(q);
        if (!grid.Level.inside(p)) continue;
        const k = bd.at(q);
        paintTile(ed, p, bd.tile[k]);
        if (bd.barrel[k] and !putBarrel(ed, b, p)) left += 1;
    }
    for (bd.torch.slice()) |t| {
        const p = at.add(t);
        if (!grid.Level.inside(p)) {
            left += 1;
        } else if (!b.torch.has(p)) {
            if (ed.here().torchGoes(b, p) and b.torch.add(p)) ed.changed() else left += 1;
        }
    }
    for (bd.foe[0..bd.foe_n]) |f| {
        const p = at.add(f.at);
        if (!grid.Level.inside(p)) {
            left += 1;
        } else if (b.foeAt(p)) |i| {
            if (b.foe[i].kind != f.kind) left += 1;
        } else if (ed.here().foeGoes(b, p, f.kind) and b.addFoe(.{ .kind = f.kind, .at = p })) ed.changed() else left += 1;
    }
    if (left > 0) ed.say("Pasted; {d} torch(es), barrel(s) or foe(s) did not fit there", .{left}) else ed.say("Pasted", .{});
}

fn deleteNode(ed: *Editor) void {
    ed.map.remove(ed.node);
    ed.release();
    ed.forgetNode();
    ed.renaming = false;
    ed.clampSelection();
    ed.bank();
    ed.restamp();
}

fn addNode(ed: *Editor, plan: atlas.Plan) void {
    const n = ed.map.add(plan) orelse return ed.say("The map holds {d} nodes", .{atlas.MAX_NODES});
    ed.select(n);
    ed.changed();
    ed.typeName();
}

/// Modal controls alone are live under a modal; opening it suppresses hits for the frame.
fn hot(ed: *Editor, r: rl.Rectangle, live: bool, modal: bool, tip: ?[:0]const u8) struct { hot: bool, hit: bool } {
    const on_layer = !ed.fresh and ed.action == .none and (modal or (ed.modal == .none and ed.popup == null));
    const in_clip = if (ed.clip) |c| ed.mouseIn(c) else true;
    const h = live and on_layer and in_clip and ed.mouseIn(r);
    if (h and tip != null) ed.tip = tip;
    return .{ .hot = h, .hit = h and ed.desk.paint_hit };
}

fn button(ed: *Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return buttonOn(ed, g, r, label, on, live, false, tip);
}

fn buttonOn(ed: *Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, modal: bool, tip: ?[:0]const u8) bool {
    const h = hot(ed, r, live, modal, tip);
    plate(r, on, h.hot);
    const y: i32 = @intFromFloat(r.y);
    drawFit(g, label, TEXT, insetW(r), false, textX(r), y + @divTrunc(@as(i32, @intFromFloat(r.height)) - TEXT, 2), if (live) look.TEXT else look.DIM);
    return h.hit;
}

fn insetW(r: rl.Rectangle) i32 {
    return @as(i32, @intFromFloat(r.width)) - 2 * GAP;
}

fn textX(r: rl.Rectangle) i32 {
    return @as(i32, @intFromFloat(r.x)) + GAP;
}

/// `s` fitted ahead of `suffix`, which is kept whole.
fn fitBefore(g: *const game.Game, buf: []u8, fit_buf: []u8, s: []const u8, suffix: [:0]const u8, max: i32) [:0]const u8 {
    const head = g.face.fit(fit_buf, s, TEXT, max - g.face.width(suffix, TEXT), false);
    return std.fmt.bufPrintZ(buf, "{s}{s}", .{ head, suffix }) catch "";
}

fn plate(r: rl.Rectangle, on: bool, hot_: bool) void {
    if (on or hot_) rl.drawRectangleRec(r, ROW_ON);
    if (on) rl.drawRectangleLinesEx(r, 1, ON);
}

fn row(x: i32, y: i32, w: i32) rl.Rectangle {
    return look.rect(x, y, w, ROW_H);
}

fn slotOf(x0: i32, span: i32, y: i32, k: usize, n: usize) rl.Rectangle {
    const ni: i32 = @intCast(n);
    const w = @divTrunc(span - GAP * (ni - 1), ni);
    return row(x0 + @as(i32, @intCast(k)) * (w + GAP), y, w);
}

fn cellOfRow(y: i32, k: usize, n: usize) rl.Rectangle {
    return slotOf(PAD, INNER_W, y, k, n);
}

fn scissor(r: rl.Rectangle) void {
    rl.beginScissorMode(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height));
}

const Across = struct {
    y: i32,
    n: usize,
    k: usize = 0,

    fn next(a: *Across) rl.Rectangle {
        std.debug.assert(a.k < a.n);
        defer a.k += 1;
        return cellOfRow(a.y, a.k, a.n);
    }

    fn done(a: *const Across) void {
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
        .map => drawMap(ed, g, c),
        .graph => drawGraph(ed, g, c),
    }
    drawPanel(ed, g);
    drawStatus(ed, g, c);
    if (ed.popup != null) drawPopup(ed, g);
    if (ed.modal != .none) drawModal(ed, g);
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

fn retag(comptime U: type, v: *U, tag: std.meta.Tag(U)) void {
    if (tag != std.meta.activeTag(v.*)) v.* = U.of(tag);
}

fn refit(ed: *Editor, pg: *atlas.Procgen, was: atlas.Procgen) void {
    pg.* = pg.fit();
    if (!std.meta.eql(was, pg.*)) ed.changed();
}

fn drawTip(ed: *const Editor, g: *game.Game) void {
    const tip = ed.tip orelse return;
    var fit_buf: [LINE]u8 = undefined;
    const s = g.face.fit(&fit_buf, tip, SMALL, TIP_MAX_W, false);
    const size = tagSize(g, s, GAPS);
    const x = std.math.clamp(ed.desk.mouse.x + TIP_DX, 0, @max(0, g.screen.x - size.x));
    const y = if (ed.desk.mouse.y + TIP_DY + size.y > g.screen.y) ed.desk.mouse.y - TIP_DY - size.y else ed.desk.mouse.y + TIP_DY;
    drawTag(g, s, .{ .x = x, .y = y }, GAPS, PANEL_BG, look.EDGE);
}

const GAPS = P{ .x = GAP, .y = GAP };

fn tagSize(g: *game.Game, s: [:0]const u8, pad: P) P {
    return .{ .x = g.face.width(s, SMALL) + 2 * pad.x, .y = SMALL + 2 * pad.y };
}

fn drawTag(g: *game.Game, s: [:0]const u8, at: P, pad: P, bg: rl.Color, edge: ?rl.Color) void {
    const size = tagSize(g, s, pad);
    rl.drawRectangle(at.x, at.y, size.x, size.y, bg);
    if (edge) |e| rl.drawRectangleLines(at.x, at.y, size.x, size.y, e);
    g.face.draw(s, at.x + pad.x, at.y + pad.y, SMALL, look.TEXT);
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

    fn buttonX(f: Frame) i32 {
        return f.x + f.w - PAD - MODAL_BTN_W;
    }
};

fn modalFrame(g: *game.Game, want_w: i32, h: i32, title: [:0]const u8, keep_end: bool) Frame {
    const w = @min(want_w, g.screen.x - 2 * PAD);
    const x = @divTrunc(g.screen.x - w, 2);
    const y = @max(0, @divTrunc(g.screen.y - h, 2));
    framed(x, y, w, h);
    const top = y + PAD;
    drawFit(g, title, HEAD, w - 2 * PAD, keep_end, x + PAD, top, look.TEXT);
    return .{ .x = x, .w = w, .top = top, .y = y + MODAL_HEAD };
}

fn keyed(comptime what: []const u8, comptime key: []const u8) [:0]const u8 {
    return what ++ " (" ++ key ++ ")";
}

fn drawPanel(ed: *Editor, g: *game.Game) void {
    var buf: [LINE]u8 = undefined;
    rl.drawRectangle(0, 0, PANEL_W, g.screen.y, PANEL_BG);
    rl.drawRectangle(PANEL_W - 1, 0, 1, g.screen.y, look.EDGE);
    var y = PAD;
    var fit_buf: [LINE]u8 = undefined;
    g.face.draw(fitBefore(g, &buf, &fit_buf, ed.path(), if (ed.dirty) " *" else "", INNER_W), PAD, y, TEXT, look.TEXT);
    y += HEAD + GAP;
    var file = Across{ .y = y, .n = 4 };
    if (button(ed, g, file.next(), "New", false, true, keyed("New map", Desk.NEW_CAPTION))) ed.askName(.new);
    if (button(ed, g, file.next(), "Open", false, true, keyed("Open a map", Desk.OPEN_CAPTION))) ed.askOpen();
    if (button(ed, g, file.next(), "Save", false, true, keyed("Save", Desk.SAVE_CAPTION))) _ = ed.save();
    if (button(ed, g, file.next(), "Save as", false, true, keyed("Save under a new name", Desk.SAVE_AS_CAPTION))) ed.askName(.save_as);
    file.done();
    y += ROW_STEP;
    var views = Across{ .y = y, .n = std.enums.values(View).len + 2 };
    for (std.enums.values(View)) |v| {
        if (button(ed, g, views.next(), menu.named(v), ed.view == v, true, keyed("The map of one node, or every node and how they link", Desk.GRAPH_CAPTION))) ed.setView(v);
    }
    if (button(ed, g, views.next(), "Objects", false, true, keyed("Every tile and body, and what each is", Desk.OBJECTS_CAPTION))) ed.ask(.objects);
    if (button(ed, g, views.next(), "Keys", false, true, keyed("Every key", Desk.HELP_CAPTION))) ed.ask(.help);
    views.done();
    y += ROW_STEP;
    var acts = Across{ .y = y, .n = 4 };
    if (button(ed, g, acts.next(), "Undo", false, ed.hist_at > 0, keyed("Undo", Desk.UNDO_CAPTION))) ed.undo();
    if (button(ed, g, acts.next(), "Redo", false, ed.hist_at < ed.hist_len, keyed("Redo", Desk.REDO_CAPTION))) ed.redo();
    if (button(ed, g, acts.next(), "Play", false, true, "Play from the map start (" ++ Desk.PLAY_CAPTION ++ "); " ++ Desk.PLAY_CAPTION ++ " or " ++ Desk.PLAY_HERE_CAPTION ++ " comes back")) {
        ed.playStart();
    }
    if (button(ed, g, acts.next(), "Title", false, true, keyed("Back to the title", Desk.BACK_CAPTION))) ed.request(.leave);
    acts.done();
    y += ROW_H + SECTION_GAP;
    y = drawTools(ed, g, y);
    var adds = Across{ .y = y, .n = 2 };
    if (button(ed, g, adds.next(), "+ Bespoke", false, true, "A node you paint yourself")) addNode(ed, .{ .bespoke = .{} });
    if (button(ed, g, adds.next(), "+ Procgen", false, true, ADD_PROCGEN_TIP)) addNode(ed, .{ .procgen = .{} });
    adds.done();
    y += ROW_STEP;
    if (ed.renaming or ed.renamed) {
        fieldRow(ed, g, cellOfRow(y, 0, 1));
    } else {
        var node = Across{ .y = y, .n = 2 };
        if (button(ed, g, node.next(), "Rename", false, true, keyed("Name this node", Desk.RENAME_CAPTION))) ed.startRename();
        const armed = ed.delete_armed == ed.node;
        if (button(ed, g, node.next(), if (armed) "Delete it?" else "Delete", armed, ed.map.node_n > 1, if (armed) "Again deletes it; its doors' links go with it" else "Delete this node; it asks first")) {
            if (armed) deleteNode(ed) else ed.delete_armed = ed.node;
        }
        node.done();
    }
    y += ROW_H + SECTION_GAP;
    var tabs = Across{ .y = y, .n = std.enums.values(Lower).len };
    for (std.enums.values(Lower)) |l| {
        const live = l != .generator or ed.rolled() != null;
        if (button(ed, g, tabs.next(), menu.named(l), ed.lower == l and live, live, LOWER_TIPS.get(l))) {
            ed.lower = l;
            ed.gen_top = 0;
        }
    }
    tabs.done();
    y += ROW_H + BLOCK_GAP;
    ed.lower_top = y;
    switch (ed.lower) {
        .generator => if (ed.generator()) |pg| return drawGenerator(ed, g, y, pg),
        .things => return drawThings(ed, g, y),
        .nodes => {},
    }
    drawNodes(ed, g, y);
}

const LOWER_TIPS = std.EnumArray(Lower, [:0]const u8).init(.{
    .nodes = "Every node of the map",
    .things = "What is on this node and what is wrong with it; a row shows it on the map",
    .generator = "What this procgen node's floor, sky and foes are rolled from",
});

fn drawNodes(ed: *Editor, g: *game.Game, top: i32) void {
    var detail_buf: [LINE]u8 = undefined;
    const shown: i32 = @intFromFloat(lowerArea(g, top).height);
    ed.node_rows = @max(1, @as(usize, @intCast(@divTrunc(shown, NODE_H))));
    if (ed.revealed != ed.node) {
        ed.scroll = mathx.reveal(ed.scroll, ed.node, ed.node_rows);
        ed.revealed = ed.node;
    }
    ed.scroll = @min(ed.scroll, ed.map.node_n -| ed.node_rows);
    scissor(lowerArea(g, top));
    defer rl.endScissorMode();
    var y = top;
    for (ed.map.nodes()[ed.scroll..], ed.scroll..) |*nd, n| {
        if (y >= g.screen.y) break;
        const r = look.rect(PAD, y, INNER_W, NODE_H - NODE_GAP);
        const h = hot(ed, r, true, false, "Open this node");
        plate(r, n == ed.node, h.hot);
        drawNodeTitle(ed, g, n, r, y + TITLE_DY);
        g.face.draw(nodeDetail(nd, &detail_buf), textX(r), y + TITLE_DY + DETAIL_DY, SMALL, if (nd.unlinked() > 0) WARN else look.DIM);
        if (h.hit) ed.goTo(n);
        y += NODE_H;
    }
}

const ICON_H: i32 = 40;
const TOOL_ROW: usize = 5;
const SWATCH: i32 = 34;
const SWATCH_GAP: i32 = 3;
const PALETTE_COLS: usize = @intCast(@divTrunc(INNER_W + SWATCH_GAP, SWATCH + SWATCH_GAP));
const PALETTE = blk: {
    var tiles: []const grid.Tile = &.{};
    for (std.enums.values(grid.Tile)) |t| {
        if (t != .chest_open) tiles = tiles ++ &[_]grid.Tile{t};
    }
    break :blk tiles;
};

fn drawTools(ed: *Editor, g: *game.Game, top: i32) i32 {
    var buf: [LINE]u8 = undefined;
    var y = top;
    const rows = comptime std.math.divCeil(usize, TOOLS.len, TOOL_ROW) catch unreachable;
    for (TOOLS, Desk.TOOL_CAPTIONS, 0..) |t, key, i| {
        const r = slotOf(PAD, INNER_W, y + @as(i32, @intCast(i / TOOL_ROW)) * (ICON_H + GAP), i % TOOL_ROW, TOOL_ROW);
        const icon = rl.Rectangle{ .x = r.x, .y = r.y, .width = r.width, .height = ICON_H };
        const live = t.fits(ed.here());
        const h = hot(ed, icon, live, false, t.tip());
        plate(icon, t.eql(ed.tool), h.hot);
        const pic = rl.Rectangle{ .x = icon.x + (icon.width - ICON_PIC) / 2, .y = icon.y + 3, .width = ICON_PIC, .height = ICON_PIC };
        if (t == .paint) swatch(g, ed.ink.get(.first), pic) else figure(g, toolPicture(g, t), t.look_(), pic);
        if (!live) rl.drawRectangleRec(icon, UNLIVE);
        g.face.draw(key, @as(i32, @intFromFloat(icon.x)) + 3, @as(i32, @intFromFloat(icon.y)) + 1, SMALL, look.DIM);
        if (h.hit) ed.setTool(t);
    }
    y += @as(i32, @intCast(rows)) * (ICON_H + GAP) + GAP;
    var shapes = Across{ .y = y, .n = SHAPES.len };
    for (SHAPES, Desk.SHAPE_CAPTIONS) |s, key| {
        const r = shapes.next();
        const label = std.fmt.bufPrintZ(&buf, "{s} {s}", .{ key, SHAPE_LABELS.get(s) }) catch "";
        const live = s == .select or ed.tool.broad();
        const h = hot(ed, r, true, false, s.tip());
        plate(r, ed.shape == s and live, h.hot);
        g.face.drawMid(label, @as(i32, @intFromFloat(r.x + r.width / 2)), @as(i32, @intFromFloat(r.y)) + SMALL_DY, SMALL, if (live) look.TEXT else look.DIM);
        if (h.hit) ed.setShape(s);
    }
    shapes.done();
    y += ROW_STEP;
    rowLabel(g, y, "Brush");
    const n = ed.brushSize();
    const by = stepper(ed, g, row(PAD + LABEL_W, y, BRUSH_SPAN), std.fmt.bufPrintZ(&buf, "{d}x{d}", .{ n, n }) catch "", .{
        .{ .tip = keyed("Smaller", Desk.BRUSH_CAPTION), .live = ed.brush > 0 },
        .{ .tip = keyed("Bigger", Desk.BRUSH_CAPTION), .live = ed.brush < BRUSHES.len - 1 },
    });
    if (by != 0) ed.stepBrush(by);
    const inks_x = PAD + INNER_W - @as(i32, INKS.len) * (SWATCH + GAP) + GAP;
    for (INKS, 0..) |k, i| {
        const r = look.rect(inks_x + @as(i32, @intCast(i)) * (SWATCH + GAP), y - @divTrunc(SWATCH - ROW_H, 2), SWATCH, SWATCH);
        swatch(g, ed.ink.get(k), r);
        rl.drawRectangleLinesEx(r, INK_EDGE, INK_EDGES.get(k));
        _ = hot(ed, r, true, false, INK_TIPS.get(k));
    }
    g.face.draw("Inks", inks_x - g.face.width("Inks", SMALL) - GAP, y + SMALL_DY, SMALL, look.DIM);
    y += ROW_STEP + GAP;
    const swatches = Tiles{ .x = PAD, .y = y, .cols = PALETTE_COLS, .pitch = SWATCH + SWATCH_GAP, .size = SWATCH };
    for (PALETTE, 0..) |t, i| {
        const r = swatches.at(i);
        const h = hot(ed, r, true, false, PALETTE_TIPS.get(t));
        swatch(g, t, r);
        if (inkOf(ed, t)) |k| rl.drawRectangleLinesEx(r, INK_EDGE, INK_EDGES.get(k)) else if (h.hot) rl.drawRectangleLinesEx(r, 1, HOVER);
        const second = h.hot and ed.desk.erase_hit;
        if (h.hit or second) {
            ed.ink.set(.of(second), t);
            if (ed.shape == .select) ed.setShape(.brush) else ed.setShape(ed.shape);
        }
    }
    y += swatches.height(PALETTE.len) + SECTION_GAP;
    return y;
}

const Tiles = struct {
    x: i32,
    y: i32,
    cols: usize,
    pitch: i32,
    size: i32,

    fn at(t: Tiles, i: usize) rl.Rectangle {
        return look.rect(t.x + @as(i32, @intCast(i % t.cols)) * t.pitch, t.y + @as(i32, @intCast(i / t.cols)) * t.pitch, t.size, t.size);
    }

    fn height(t: Tiles, n: usize) i32 {
        return @as(i32, @intCast(std.math.divCeil(usize, n, t.cols) catch unreachable)) * t.pitch;
    }
};

const ICON_PIC: f32 = 30;
const SHAPE_LABELS = std.EnumArray(Shape, [:0]const u8).init(.{ .brush = "Brush", .line = "Line", .rect = "Rect", .box = "Box", .fill = "Fill", .select = "Sel" });
const INK_EDGES = std.EnumArray(Ink, rl.Color).init(.{ .first = ON, .second = WARN });
const INK_TIPS = std.EnumArray(Ink, [:0]const u8).init(.{
    .first = "The first ink: " ++ Desk.PAINT_CAPTION ++ " paints it; " ++ Desk.PAINT_CAPTION ++ " on the palette picks it",
    .second = "The second ink: " ++ Desk.ERASE_CAPTION ++ " paints it; " ++ Desk.ERASE_CAPTION ++ " on the palette picks it",
});

fn inkOf(ed: *const Editor, t: grid.Tile) ?Ink {
    for (INKS) |k| {
        if (ed.ink.get(k) == t) return k;
    }
    return null;
}
const PALETTE_TIPS = blk: {
    var tips = std.EnumArray(grid.Tile, [:0]const u8).initUndefined();
    for (std.enums.values(grid.Tile)) |t| {
        tips.set(t, menu.named(t) ++ ": " ++ PALETTE_RULE ++
            (if (t.solid()) "; blocks a step" else "") ++ (if (t.blind()) "; blocks sight" else ""));
    }
    break :blk tips;
};

fn drawThings(ed: *Editor, g: *game.Game, top: i32) void {
    var buf: [LINE]u8 = undefined;
    var name: [atlas.TITLE_MAX]u8 = undefined;
    var y = beginScroll(ed, g, top);
    defer endScroll(ed);
    const is = ed.issues;
    section(g, &y, "Problems");
    var wrong = false;
    if (is.start_walled) {
        wrong = true;
        thingRow(ed, g, &y, "The start is on solid ground", WARN, ed.map.start.at);
    }
    if (is.unlinked > 0) {
        wrong = true;
        thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{d} door(s) lead nowhere", .{is.unlinked}) catch "", WARN, null);
    }
    if (is.cut_off > 0) {
        wrong = true;
        thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{d} open cells no walk reaches (shaded)", .{is.cut_off}) catch "", WARN, is.reach_from);
    }
    if (is.foes_cut_off > 0) {
        wrong = true;
        thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{d} foe(s) no walk reaches", .{is.foes_cut_off}) catch "", WARN, null);
    }
    if (!wrong) thingRow(ed, g, &y, "Nothing wrong", look.DIM, null);
    y += BLOCK_GAP;
    section(g, &y, if (ed.here().unrolled()) "On this roll" else "On this node");
    if (ed.start_at) |s| thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "Start  {d},{d}", .{ s.x, s.y }) catch "", look.TEXT, s);
    for (ed.here().doors(), 0..) |d, k| {
        const line = if (d.to) |to|
            std.fmt.bufPrintZ(&buf, "Door {d}  {d},{d}  to {s}, door {d}", .{ k, d.at.x, d.at.y, ed.nodeName(to.node, &name), to.door }) catch ""
        else
            std.fmt.bufPrintZ(&buf, "Door {d}  {d},{d}  leads nowhere", .{ k, d.at.x, d.at.y }) catch "";
        thingRow(ed, g, &y, line, if (d.to == null) WARN else look.TEXT, d.at);
    }
    for (ed.shownFoes()) |f| thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{s}  {d},{d}", .{ kindName(f.kind), f.at.x, f.at.y }) catch "", look.TEXT, f.at);
    switch (ed.plan().*) {
        .bespoke => |*b| {
            for (b.torches()) |t| thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "Torch  {d},{d}", .{ t.x, t.y }) catch "", look.TEXT, t);
            for (&b.barrel, 0..) |*on, i| {
                if (!on.*) continue;
                const p = grid.Level.of(i);
                thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "Barrel  {d},{d}", .{ p.x, p.y }) catch "", look.TEXT, p);
            }
        },
        .procgen => {},
    }
    scrolledTo(ed, g, top, y);
}

fn clipped(ed: *const Editor, y: i32) bool {
    const c = ed.clip orelse return false;
    const top: f32 = @floatFromInt(y);
    return top + ROW_H <= c.y or top >= c.y + c.height;
}

fn thingRow(ed: *Editor, g: *game.Game, y: *i32, line: [:0]const u8, col: rl.Color, at: ?P) void {
    if (clipped(ed, y.*)) {
        y.* += ROW_H;
        return;
    }
    const r = row(PAD, y.*, INNER_W);
    const h = hot(ed, r, at != null, false, if (at != null) "Show it on the map" else null);
    plate(r, false, h.hot);
    drawFit(g, line, SMALL, insetW(r), false, textX(r), y.* + SMALL_DY, col);
    if (h.hit) {
        const p = at.?;
        ed.setView(.map);
        ed.lookAt(Editor.canvas(g), p);
        ed.flash = p;
        ed.flash_t = FLASH_S;
    }
    y.* += ROW_H;
}

const FLASH_S: f32 = 1.2;

fn toolPicture(g: *const game.Game, t: Tool) ?rl.Texture2D {
    return switch (t) {
        .barrel => g.sprites.barrel,
        .foe => |k| g.sprites.body(k),
        .start => g.sprites.body(actor.HERO),
        .paint, .torch, .door, .link => null,
    };
}

fn bareBg(t: grid.Tile) rl.Color {
    return look.tileBg(t) orelse look.BARE_WALL;
}

fn swatch(g: *game.Game, t: grid.Tile, r: rl.Rectangle) void {
    const u = look.under(t);
    if (u) |b| {
        if (g.sprites.tileOf(b, null)) |tex| sprite(tex, r) else if (look.tileBg(b)) |bg| rl.drawRectangleRec(r, bg);
    }
    if (g.sprites.tileOf(t, .{})) |tex| return sprite(tex, r);
    if (u == null) rl.drawRectangleRec(r, bareBg(t));
    tileGlyph(g, t, r);
}

fn drawFit(g: *const game.Game, s: []const u8, size: i32, max: i32, keep_end: bool, x: i32, y: i32, col: rl.Color) void {
    var fit_buf: [atlas.PATH_MAX + LINE]u8 = undefined;
    g.face.draw(g.face.fit(&fit_buf, s, size, max, keep_end), x, y, size, col);
}

fn drawNodeTitle(ed: *Editor, g: *const game.Game, n: usize, r: rl.Rectangle, y: i32) void {
    var buf: [LINE]u8 = undefined;
    const typing = ed.renamingNode(n);
    drawFit(g, ed.nodeTitle(n, &buf), TEXT, insetW(r), typing, textX(r), y, if (typing) look.RETICLE else look.TEXT);
}

fn lowerArea(g: *const game.Game, top: i32) rl.Rectangle {
    return look.rect(0, top, PANEL_W, @max(0, g.screen.y - top));
}

fn beginScroll(ed: *Editor, g: *const game.Game, top: i32) i32 {
    const area = lowerArea(g, top);
    ed.clip = area;
    scissor(area);
    ed.gen_top = std.math.clamp(ed.gen_top, 0, ed.gen_most);
    return top - ed.gen_top;
}

fn endScroll(ed: *Editor) void {
    rl.endScissorMode();
    ed.clip = null;
}

fn scrolledTo(ed: *Editor, g: *const game.Game, top: i32, end: i32) void {
    const shown: i32 = @intFromFloat(lowerArea(g, top).height);
    ed.gen_most = @max(0, end + PAD + ed.gen_top - top - shown);
}

fn drawGenerator(ed: *Editor, g: *game.Game, top: i32, pg: *atlas.Procgen) void {
    const was = pg.*;
    const fo = &pg.foes;
    var y = beginScroll(ed, g, top);
    defer endScroll(ed);
    if (nodeSwitch(ed, g, &y)) return;
    y += BLOCK_GAP;
    section(g, &y, "Base");
    choiceRow(ed, g, &y, atlas.Floor, &pg.floor, ALGO_CHOICE, .algo);
    switch (pg.floor) {
        inline else => |*fl, t| knobRows(ed, g, &y, fl, comptime rowsOf(t), true),
    }
    y += BLOCK_GAP;
    section(g, &y, "Features");
    var drop_feature: ?usize = null;
    for (pg.featuresMut(), 0..) |*ft, i| {
        if (button(ed, g, row(PAD + LABEL_W - STEP_W - GAP, y, STEP_W), DROP, false, true, "Take this feature away")) drop_feature = i;
        choiceRow(ed, g, &y, atlas.Feature, ft, FEATURE_CHOICE, .{ .feature = i });
        switch (ft.*) {
            inline else => |*fp, k| knobRows(ed, g, &y, fp, comptime featureRowsOf(k), true),
        }
        y += BLOCK_GAP;
    }
    if (drop_feature) |i| pg.dropFeature(i);
    if (button(ed, g, cellOfRow(y, 0, 1), "+ Feature", false, pg.feature_n < atlas.MAX_FEATURES, ADD_FEATURE_TIP)) _ = pg.addFeature(atlas.FIRST_FEATURE);
    y += ROW_H + SECTION_GAP;
    knobs(ed, g, &y, if (pg.floor.outdoor()) "Sky" else "Sky (this base is under a roof)", &pg.sky, &SKY_ROWS, pg.floor.outdoor());
    y += BLOCK_GAP;
    knobs(ed, g, &y, "Foes", fo, &FOE_ROWS, true);
    y += BLOCK_GAP;
    section(g, &y, "Makeups");
    var drop: ?usize = null;
    for (fo.makeup[0..fo.makeup_n], 0..) |*m, i| {
        if (drawMakeup(ed, g, y, m, fo.canDrop())) drop = i;
        y += ROW_STEP;
    }
    if (drop) |i| _ = fo.dropMakeup(i);
    if (button(ed, g, cellOfRow(y, 0, 1), "+ Makeup", false, fo.canAdd(), ADD_MAKEUP_TIP)) _ = fo.addMakeup();
    scrolledTo(ed, g, top, y + ROW_H);
    refit(ed, pg, was);
}

fn nodeSwitch(ed: *Editor, g: *game.Game, y: *i32) bool {
    var name: [atlas.TITLE_MAX]u8 = undefined;
    rowLabel(g, y.*, "Node");
    var procgen: usize = 0;
    for (ed.map.nodes()) |*nd| procgen += @intFromBool(nd.unrolled());
    const tip = "The next or last procgen node's generator";
    const by = stepper(ed, g, valueSlot(y.*, 0, 1), ed.nodeName(ed.node, &name), .{
        .{ .tip = tip, .live = procgen > 1 },
        .{ .tip = tip, .live = procgen > 1 },
    });
    y.* += ROW_STEP;
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

fn section(g: *game.Game, y: *i32, title: [:0]const u8) void {
    g.face.draw(title, PAD, y.*, TEXT, look.DIM);
    y.* += HEAD;
}

fn knobs(ed: *Editor, g: *game.Game, y: *i32, title: [:0]const u8, owner: anytype, comptime rows: []const Knob, live: bool) void {
    section(g, y, title);
    knobRows(ed, g, y, owner, rows, live);
}

fn knobRows(ed: *Editor, g: *game.Game, y: *i32, owner: anytype, comptime rows: []const Knob, live: bool) void {
    inline for (rows) |k| {
        knobRow(ed, g, y.*, owner, k, live);
        y.* += ROW_STEP;
    }
}

fn choiceRow(ed: *Editor, g: *game.Game, y: *i32, comptime U: type, v: *U, comptime c: Choice, which: Which) void {
    rowLabel(g, y.*, c.label);
    var tag = std.meta.activeTag(v.*);
    stepChoice(ed, g, y.*, std.meta.Tag(U), &tag, c.tip, true);
    retag(U, v, tag);
    const slot = valueSlot(y.*, 0, 1);
    const value = valueRect(slot);
    const h = hot(ed, value, true, false, "Every choice; " ++ c.tip);
    if (h.hot) rl.drawRectangleLinesEx(value, 1, HOVER);
    if (h.hit) {
        ed.drop();
        ed.popup = .{ .slot = value, .which = which };
        ed.fresh = true;
    }
    y.* += ROW_STEP;
}

fn drawMakeup(ed: *Editor, g: *game.Game, y: i32, m: *pack.Makeup, droppable: bool) bool {
    var buf: [8]u8 = undefined;
    const weight = stepper(ed, g, row(PAD, y, WEIGHT_SPAN), num(&buf, "x{d}", m.weight), .{
        .{ .tip = "Drawn less often against the others", .live = m.weight > pack.WEIGHT_MIN },
        .{ .tip = "Drawn more often against the others", .live = m.weight < pack.WEIGHT_MAX },
    });
    bump(u8, &m.weight, weight);
    var x = PAD + MEMBERS_X;
    for (0..pack.MAKEUP_MAX) |i| {
        const r = row(x, y, MEMBER_W);
        x += MEMBER_W + MEMBER_GAP;
        if (i >= m.n) continue;
        const h = hot(ed, r, true, false, if (i == 0) "The lead: click for the next foe" else "A member: click for the next foe");
        plate(r, false, h.hot);
        const l = look.body(m.kind[i]);
        g.face.glyph(l.ch, @intFromFloat(r.x + r.width / 2), @intFromFloat(r.y + r.height / 2), TEXT, l.fg);
        if (h.hit) m.turn(i);
    }
    var dropped = false;
    for (MAKEUP_TOOLS, 0..) |t, i| {
        const r = row(PAD + MAKEUP_TOOLS_X + @as(i32, @intCast(i)) * STEP_PITCH, y, STEP_W);
        const live = switch (t) {
            .grow => m.canGrow(),
            .shrink => m.canShrink(),
            .drop => droppable,
        };
        if (!button(ed, g, r, t.label(), false, live, t.tip())) continue;
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

const MAKEUP_TOOLS = std.enums.values(MakeupTool);

fn rowLabel(g: *game.Game, y: i32, s: [:0]const u8) void {
    g.face.draw(s, PAD, y + TEXT_DY, TEXT, look.TEXT);
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
const DECAY_ROW = Knob{ .field = "decay", .tips = &.{"Of the walls, how many have fallen to rubble"}, .fmt = PERCENT_FMT };
const COUNT_ROW = Knob{ .field = "count", .tips = &.{"How many"} };
const COUNT_MOST_ROW = Knob{ .field = "count", .tips = &.{"How many, at most"} };
const WIDTH_ROW = Knob{ .field = "width", .tips = &.{"Cells across"} };
const LITTER_ROW = Knob{ .field = "litter", .tips = &.{"Lone boulders, a thousandth of the open grass each"} };
const DECOR_ROW = Knob{ .field = "decor", .tips = &.{ "Tiny shrubs a cell at a time, a thousandth of the open grass each", "Tall grass in patches, a thousandth of the open grass each", "Shrooms a cell at a time, a thousandth of the open grass each" } };
const GRASS_ROWS = [_]Knob{ LITTER_ROW, DECOR_ROW };
const COURSE_ROW = Knob{ .field = "course", .tips = &.{"Across, down, or either"} };

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
    .{ .field = "rewards", .tips = &.{"Closed treasure chests at the ends of substantial remaining branches"} },
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
    .{ .field = "style", .tips = &.{"Built walls, rock, or a hedge maze"} },
    .{ .field = "chamber", .tips = &.{"Half-height of an open chamber at the heart, half again as wide; 0 for none"} },
    .{ .field = "braid", .tips = &.{"Of the dead ends, how many are knocked through into loops"}, .fmt = PERCENT_FMT },
};

const HALL_ROWS = [_]Knob{
    .{ .field = "style", .tips = &.{"Bare, pillared, grave alcoves, or a grove of plants"} },
    .{ .field = "margin", .tips = &.{"Wall between the hall and the map's edge"} },
};

const MAZE_ROWS = [_]Knob{
    .{ .field = "style", .tips = &.{"Caves, tombs, sewers, lava or ice"} },
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
    .{ .field = "wall", .tips = &.{"None, a stone wall or a fence round it"} },
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
    .{ .field = "template", .tips = &.{"Huts, compound, pillars, or any one per section"} },
    DECAY_ROW,
    .{ .field = "ground", .tips = &.{"The ground between and round the buildings"} },
};

fn rowsOf(comptime a: atlas.Algo) []const Knob {
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
    .{ .field = "light", .tips = &.{"How its daylight looks: clear, or a bleak overcast; shown only open to the sky"} },
    .{ .field = "weather", .tips = &.{"What falls from its sky: nothing, or a soft drizzle; shown only open to the sky"} },
};

const FOE_ROWS = [_]Knob{
    .{ .field = "packs", .tips = &.{"How many packs it places"} },
    .{ .field = "few", .label = "At least", .tips = &.{"Each foe any makeup holds has this many at least, while packs last"} },
    .{ .field = "reach", .tips = &.{"Cells from a pack's lead to the rest of it, at most"} },
    .{ .field = "gap", .tips = &.{"Cells from where the hero arrives to every foe, at least"} },
    .{ .field = "apart", .tips = &.{"Cells from one pack to every other, at least; 0 lets them crowd"} },
};

const ADD_PROCGEN_TIP = "A node the " ++ @tagName((atlas.Procgen{}).floor) ++ " generator rolls round its doors, anew each run";
const ADD_MAKEUP_TIP = "Another pack it may roll, a lone " ++ actor.row(pack.FIRST).name ++ " to begin";
const SHIFT_TIP = std.fmt.comptimePrint(" ({s} steps {d})", .{ Desk.SHIFT_CAPTION, SHIFT_STEP });

comptime {
    @setEvalBranchQuota(1_000_000);
    for (std.enums.values(atlas.Algo)) |a| covers(@FieldType(atlas.Floor, @tagName(a)), rowsOf(a), atlas.floorKnobs(a));
    for (std.enums.values(atlas.Kind)) |k| covers(@FieldType(atlas.Feature, @tagName(k)), featureRowsOf(k), atlas.featureKnobs(k));
    covers(@FieldType(atlas.Procgen, "foes"), &FOE_ROWS, atlas.FOE_KNOBS);
    covers(@FieldType(atlas.Procgen, "sky"), &SKY_ROWS, atlas.SKY_KNOBS);
}

fn covers(comptime T: type, comptime rows: []const Knob, comptime knobs_: []const []const u8) void {
    @setEvalBranchQuota(100_000);
    if (rows.len != knobs_.len) @compileError("a generator row is for no knob");
    for (knobs_) |name| {
        const r = for (rows) |r| {
            if (std.mem.eql(u8, r.field, name)) break r;
        } else @compileError(name ++ " has no row on the generator");
        if (r.tips.len != atlas.knobNumbers(@FieldType(T, name))) @compileError(name ++ " wants a tip for each number in it");
    }
}

fn knobRow(ed: *Editor, g: *game.Game, y: i32, owner: anytype, comptime k: Knob, live: bool) void {
    if (clipped(ed, y)) return;
    rowLabel(g, y, comptime k.caption());
    const v = &@field(owner.*, k.field);
    const T = @TypeOf(v.*);
    const n = comptime atlas.knobNumbers(T);
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

fn moves(owner: anytype, comptime k: Knob, comptime i: usize, by: i32) bool {
    var o = owner.*;
    const p = numberOf(&o, k, i);
    bump(@TypeOf(p.*), p, k.unit * by);
    if (@hasDecl(@TypeOf(o), "fit")) o = o.fit();
    return !std.meta.eql(o, owner.*);
}

fn stepNumber(ed: *Editor, g: *game.Game, y: i32, comptime i: usize, n: usize, v: anytype, comptime k: Knob, reach: [2]bool) void {
    var buf: [16]u8 = undefined;
    const tip = k.tips[i] ++ SHIFT_TIP;
    bump(@TypeOf(v.*), v, k.unit * stepper(ed, g, valueSlot(y, i, n), num(&buf, k.fmt, v.*), .{ .{ .tip = tip, .live = reach[0] }, .{ .tip = tip, .live = reach[1] } }));
}

fn stepChoice(ed: *Editor, g: *game.Game, y: i32, comptime T: type, v: *T, tip: [:0]const u8, live: bool) void {
    const by = stepper(ed, g, valueSlot(y, 0, 1), @tagName(v.*), .{ .{ .tip = tip, .live = live }, .{ .tip = tip, .live = live } });
    v.* = cycle(T, v.*, by);
}

fn valueSlot(y: i32, k: usize, n: usize) rl.Rectangle {
    return slotOf(PAD + LABEL_W, INNER_W - LABEL_W, y, k, n);
}

fn cycle(comptime T: type, v: T, by: i32) T {
    return mathx.stepIn(T, comptime std.enums.values(T), v, std.math.sign(by), null);
}

const Step = struct { tip: [:0]const u8, live: bool = true };

fn stepper(ed: *Editor, g: *game.Game, r: rl.Rectangle, value: []const u8, steps: [2]Step) i32 {
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const w: i32 = @intFromFloat(r.width);
    var by: i32 = 0;
    if (button(ed, g, row(x, y, STEP_W), "-", false, steps[0].live, steps[0].tip)) by = -1;
    if (button(ed, g, row(x + w - STEP_W, y, STEP_W), "+", false, steps[1].live, steps[1].tip)) by = 1;
    var fit_buf: [LINE]u8 = undefined;
    const shown = g.face.fit(&fit_buf, value, TEXT, @intFromFloat(valueRect(r).width), false);
    g.face.drawMid(shown, x + @divTrunc(w, 2), y + TEXT_DY, TEXT, look.TEXT);
    return if (ed.desk.shift) by * SHIFT_STEP else by;
}

fn valueRect(r: rl.Rectangle) rl.Rectangle {
    const pitch: f32 = @floatFromInt(STEP_PITCH);
    return .{ .x = r.x + pitch, .y = r.y, .width = r.width - 2 * pitch, .height = r.height };
}

/// The caller fits the result to its application-specific range.
fn bump(comptime T: type, v: *T, by: i32) void {
    const at: i64 = @intCast(v.*);
    const hi: i64 = @min(std.math.maxInt(T), std.math.maxInt(i64));
    v.* = @intCast(std.math.clamp(at + by, 0, hi));
}

fn drawStatus(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    var buf: [LINE + 1]u8 = undefined;
    var state_buf: [LINE + 1]u8 = undefined;
    const top: i32 = @intFromFloat(c.y + c.height);
    const x = PANEL_W + PAD;
    const w = @as(i32, @intFromFloat(c.width)) - 2 * PAD;
    rl.drawRectangle(PANEL_W, top, g.screen.x - PANEL_W, STATUS_H, PANEL_BG);
    rl.drawRectangle(PANEL_W, top, g.screen.x - PANEL_W, 1, look.EDGE);
    const state = toolState(ed, &state_buf);
    const state_w = g.face.width(state, TEXT);
    var y = top + GAP;
    drawFit(g, hover(ed, c, &buf), TEXT, w - state_w - BLOCK_GAP, false, x, y, look.TEXT);
    g.face.draw(state, x + w - state_w, y, TEXT, look.DIM);
    y += TEXT + GAP;
    const said = ed.said_t > 0;
    const line: []const u8 = if (said) ed.said.text() else if (ed.view == .map) CRIB_MAP else CRIB_GRAPH;
    drawFit(g, line, TEXT, w, false, x, y, if (said) look.RETICLE else look.DIM);
}

fn toolState(ed: *const Editor, buf: []u8) [:0]const u8 {
    const px: i32 = @intFromFloat(ed.px());
    if (ed.pasting) return std.fmt.bufPrintZ(buf, "Pasting {d}x{d}" ++ SEP ++ "{d} px", .{ ed.board.size.x, ed.board.size.y, px }) catch "";
    if (ed.shape == .select) return std.fmt.bufPrintZ(buf, "Select" ++ SEP ++ "{d} px", .{px}) catch "";
    const n = ed.brushSize();
    if (ed.tool.broad()) return std.fmt.bufPrintZ(buf, "{s} / {s}" ++ SEP ++ "{s} {d}x{d}" ++ SEP ++ "{d} px", .{ @tagName(ed.ink.get(.first)), @tagName(ed.ink.get(.second)), SHAPE_LABELS.get(ed.shape), n, n, px }) catch "";
    return std.fmt.bufPrintZ(buf, "{s}" ++ SEP ++ "{d} px", .{ ed.tool.name(), px }) catch "";
}

fn hover(ed: *Editor, c: rl.Rectangle, buf: []u8) [:0]const u8 {
    if (!ed.mouseIn(c)) return "";
    var a: [atlas.TITLE_MAX]u8 = undefined;
    if (ed.view == .graph) {
        if (ed.dotUnder(c, ed.desk.mouse)) |l| {
            const to = ed.map.door(l).to orelse return std.fmt.bufPrintZ(buf, "Node {d} door {d}: leads nowhere; drag to another door's dot to link it", .{ l.node, l.door }) catch "";
            return std.fmt.bufPrintZ(buf, "Node {d} door {d} leads to {s}, door {d}; {s} unlinks", .{ l.node, l.door, ed.nodeName(to.node, &a), to.door, Desk.ERASE_CAPTION }) catch "";
        }
        const n = ed.boxUnder(c, ed.desk.mouse) orelse return "";
        var d: [LINE]u8 = undefined;
        return std.fmt.bufPrintZ(buf, "{s} (node {d}): {s}", .{ ed.nodeName(n, &a), n, nodeDetail(&ed.map.node[n], &d) }) catch "";
    }
    const p = ed.mouseCell(c);
    if (!grid.Level.inside(p)) return "";
    const nd = ed.here();
    var out = std.io.fixedBufferStream(buf[0 .. buf.len - 1]);
    const wr = out.writer();
    wr.print("{d},{d}  {s}", .{ p.x, p.y, @tagName(ed.lv.at(p)) }) catch {};
    if (nd.unrolled()) wr.writeAll(" (this roll)") catch {};
    switch (nd.plan) {
        .bespoke => |*b| {
            const i = grid.Level.idx(p);
            if (b.barrel[i]) wr.writeAll(", a barrel") catch {};
            if (b.torch.has(p)) wr.writeAll(", a torch") catch {};
        },
        .procgen => {},
    }
    for (ed.shownFoes()) |f| {
        if (f.at.eq(p)) wr.print(", a {s}", .{actor.row(f.kind).name}) catch {};
    }
    if (ed.start_at) |s| {
        if (s.eq(p)) wr.writeAll(", the start") catch {};
    }
    if (nd.doorAt(p)) |k| {
        if (nd.door[k].to) |to| {
            wr.print(", door {d} to {s}, door {d} ({s} goes through)", .{ k, ed.nodeName(to.node, &a), to.door, Desk.GO_CAPTION }) catch {};
        } else wr.print(", door {d}, leading nowhere", .{k}) catch {};
    }
    const n = out.getWritten().len;
    buf[n] = 0;
    return buf[0..n :0];
}

fn nodeDetail(nd: *const atlas.Node, buf: []u8) [:0]const u8 {
    const kind = switch (nd.plan) {
        .bespoke => @tagName(nd.plan),
        .procgen => |*pg| @tagName(pg.floor),
    };
    const open = nd.unlinked();
    if (open == 0) return std.fmt.bufPrintZ(buf, "{s}, {d} doors", .{ kind, nd.door_n }) catch "";
    return std.fmt.bufPrintZ(buf, "{s}, {d} doors, {d} unlinked", .{ kind, nd.door_n, open }) catch "";
}

fn visible(ed: *const Editor, c: rl.Rectangle) grid.Box {
    const lo = mathx.P{ .x = @min(grid.W, @max(0, @as(i32, @intFromFloat(@floor(ed.cam[0]))))), .y = @min(grid.H, @max(0, @as(i32, @intFromFloat(@floor(ed.cam[1]))))) };
    return .{ .lo = lo, .hi = .{
        .x = @max(lo.x, @min(grid.W, @as(i32, @intFromFloat(@ceil(ed.cam[0] + c.width / ed.px()))) + 1)),
        .y = @max(lo.y, @min(grid.H, @as(i32, @intFromFloat(@ceil(ed.cam[1] + c.height / ed.px()))) + 1)),
    } };
}

fn drawCells(ed: *Editor, g: *game.Game, c: rl.Rectangle, v: grid.Box) void {
    var beds: dual.Beds = undefined;
    beds.fill(&ed.lv, v.lo, v.hi, false);
    g.sprites.drawGround(&beds, ed.origin(c), ed.px(), null);
    var cells = grid.Cells.of(v.lo, v.hi);
    while (cells.next()) |p| {
        const r = ed.cellRect(c, p);
        const here = ed.lv.at(p);
        if (look.glyphGround(here, &g.sprites)) tileGlyph(g, here, r);
        if (!look.standsOver(here)) continue;
        if (g.sprites.tileAt(&ed.lv, p)) |t| {
            sprite(t, r);
            continue;
        }
        if (look.tileBg(here) orelse if (here == .wall) look.BARE_WALL else null) |bg| rl.drawRectangleRec(r, bg);
        if (here != .wall) tileGlyph(g, here, r);
    }
}

fn drawMap(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    scissor(c);
    defer rl.endScissorMode();
    const v = visible(ed, c);
    drawCells(ed, g, c, v);
    if (ed.lower == .things and ed.issues.cut_off > 0) {
        var cells = grid.Cells.of(v.lo, v.hi);
        while (cells.next()) |p| {
            if (ed.cutOff(grid.Level.idx(p))) rl.drawRectangleRec(ed.cellRect(c, p), CUT_OFF);
        }
    }
    if (ed.px() >= GRID_PX) drawGrid(ed, c, v);
    const all = ed.cellRect(c, .{ .x = 0, .y = 0 });
    rl.drawRectangleLinesEx(look.grown(.{ .x = all.x, .y = all.y, .width = grid.W * ed.px(), .height = grid.H * ed.px() }, 1), 1, look.EDGE);
    var cells = grid.Cells.of(v.lo, v.hi);
    while (cells.next()) |p| {
        if (ed.lv.hasBarrel(p)) seenPicture(g, .barrel, ed.cellRect(c, p));
    }
    for (ed.lv.torches()) |t| seenPicture(g, .torch, ed.cellRect(c, t));
    for (ed.shownFoes()) |f| seenPicture(g, .{ .body = f.kind }, ed.cellRect(c, f.at));
    drawDoors(ed, g, c);
    if (ed.start_at) |s| figure(g, g.sprites.body(actor.HERO), START, ed.cellRect(c, s));
    if (ed.selection) |s| {
        outlineCells(ed, c, s, PICKED);
        fillCells(ed, c, s, SELECTED);
    }
    if (ed.flash_t > 0) {
        if (ed.flash) |p| {
            const r = ed.cellRect(c, p);
            rl.drawRectangleLinesEx(look.grown(r, FLASH_PX), PICK_EDGE, look.RETICLE);
        }
    }
    drawCursor(ed, g, c);
    if (ed.here().unrolled()) plaque(g, c, "One roll of this node (" ++ Desk.REROLL_CAPTION ++ " rolls another); play rolls it afresh each run");
}

const GRID_PX: f32 = 32;
const FLASH_PX: f32 = 4;
const GHOST_A: f32 = 0.5;
const GHOST = look.fade(look.LIT, GHOST_A);
const CUT_OFF = look.fade(WARN, 0.35);
const SELECTED = look.fade(PICKED, 0.15);
const GRID_INK = look.fade(look.EDGE, 0.35);
const UNLIVE = look.fade(look.BG, 0.6);
const DOOR_BACK = look.fade(look.BG, 0.55);
const PLAQUE_BG = look.fade(PANEL_BG, 0.85);
const INK_EDGE: f32 = 2;
const PICK_EDGE: f32 = 3;

fn drawGrid(ed: *const Editor, c: rl.Rectangle, v: grid.Box) void {
    const lo = ed.cellRect(c, v.lo);
    const hi = ed.cellRect(c, v.hi);
    var x = v.lo.x;
    while (x <= v.hi.x) : (x += 1) {
        const at = ed.cellRect(c, .{ .x = x, .y = v.lo.y }).x;
        rl.drawLineV(.{ .x = at, .y = lo.y }, .{ .x = at, .y = hi.y }, GRID_INK);
    }
    var y = v.lo.y;
    while (y <= v.hi.y) : (y += 1) {
        const at = ed.cellRect(c, .{ .x = v.lo.x, .y = y }).y;
        rl.drawLineV(.{ .x = lo.x, .y = at }, .{ .x = hi.x, .y = at }, GRID_INK);
    }
}

fn drawDoors(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    var buf: [8]u8 = undefined;
    for (ed.here().doors(), 0..) |d, k| {
        const r = ed.cellRect(c, d.at);
        rl.drawRectangleRec(r, DOOR_BACK);
        glyph(g, look.DOOR.ch, r, if (d.to == null) UNLINKED else look.DOOR.fg);
        rl.drawRectangleLinesEx(r, 1, if (d.to == null) WARN else look.DOOR.fg);
        if (ed.px() >= LABEL_PX) {
            const label = std.fmt.bufPrintZ(&buf, "{d}", .{k}) catch "";
            drawTag(g, label, .{ .x = @intFromFloat(r.x), .y = @intFromFloat(r.y) }, LABEL_PAD, PANEL_BG, null);
        }
        const pk = ed.pick orelse continue;
        if (pk.eq(.{ .node = ed.node, .door = k })) rl.drawRectangleLinesEx(r, PICK_EDGE, PICKED);
    }
}

fn drawCursor(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    const m = ed.mouseCell(c);
    if (ed.pasting) {
        if (!ed.mouseIn(c)) return;
        const bd = &ed.board;
        const view = visible(ed, c);
        var cells = bd.box(.{ .x = 0, .y = 0 }).cells();
        while (cells.next()) |q| {
            const p = m.add(q);
            const k = bd.at(q);
            if (view.holds(p)) ghostInk(ed, g, c, p, bd.tile[k]);
        }
        outlineCells(ed, c, bd.box(m), if (ed.paintable()) PICKED else WARN);
        return;
    }
    if (ed.span) |s| {
        const to = grid.Level.clamp(m);
        eachSpanCell(ed, s, to, Ghost.of(ed, g, c, ed.ink.get(.of(s.erase))));
        outlineCells(ed, c, grid.Box.between(s.from, to), PICKED);
        return;
    }
    if (!grid.Level.inside(m) or !ed.mouseIn(c)) return;
    if (ed.shape == .select) return outlineCells(ed, c, brushBox(m, 1), PICKED);
    if (ed.tool.broad()) {
        const erase = if (ed.stroke == .none) ed.desk.erase else ed.stroke == .erase;
        const ghost = Ghost.of(ed, g, c, ed.ink.get(.of(erase)));
        const begins = if (ed.stroke == .none) spanOf(ed, ed.desk.shift) else null;
        if (begins) |sh| {
            eachSpanCell(ed, .{ .from = m, .erase = erase, .shape = sh }, m, ghost);
            return outlineCells(ed, c, brushBox(m, if (sh == .line) ed.brushSize() else 1), HOVER);
        }
        if (ed.shape != .fill) eachBrushCell(ed, m, ghost);
        return outlineCells(ed, c, brushBox(m, if (ed.shape == .fill) 1 else ed.brushSize()), if (ed.tool.fits(ed.here())) HOVER else WARN);
    }
    const r = ed.cellRect(c, m);
    const ok = legal(ed, m);
    if (toolPicture(g, ed.tool)) |t| {
        look.stretch(t, r, GHOST);
    } else {
        const l = ed.tool.look_();
        glyph(g, l.ch, r, look.fade(l.fg, GHOST_A));
    }
    rl.drawRectangleLinesEx(r, INK_EDGE, if (ok) HOVER else WARN);
    if (!ok) rl.drawRectangleRec(r, CUT_OFF);
}

fn ghostInk(ed: *Editor, g: *game.Game, c: rl.Rectangle, p: P, t: grid.Tile) void {
    const r = ed.cellRect(c, p);
    if (ed.paintable() and ed.doorAt(p) == null) ghostTile(g, t, r) else rl.drawRectangleRec(r, CUT_OFF);
}

fn ghostTile(g: *game.Game, t: grid.Tile, r: rl.Rectangle) void {
    if (g.sprites.tileOf(t, .{})) |tex| return look.stretch(tex, r, GHOST);
    rl.drawRectangleRec(r, look.fade(bareBg(t), GHOST_A));
}

fn legal(ed: *Editor, p: P) bool {
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

fn boxRect(ed: *const Editor, c: rl.Rectangle, b: grid.Box) rl.Rectangle {
    const lo = ed.cellRect(c, b.lo);
    const hi = ed.cellRect(c, b.hi);
    return .{ .x = lo.x, .y = lo.y, .width = hi.x - lo.x, .height = hi.y - lo.y };
}

fn fillCells(ed: *const Editor, c: rl.Rectangle, b: grid.Box, col: rl.Color) void {
    rl.drawRectangleRec(boxRect(ed, c, b), col);
}

fn plaque(g: *game.Game, c: rl.Rectangle, s: [:0]const u8) void {
    drawTag(g, s, .{ .x = @as(i32, @intFromFloat(c.x)) + GAP, .y = @as(i32, @intFromFloat(c.y)) + GAP }, GAPS, PLAQUE_BG, null);
}

fn outlineCells(ed: *const Editor, c: rl.Rectangle, b: grid.Box, col: rl.Color) void {
    rl.drawRectangleLinesEx(boxRect(ed, c, b), 1, col);
}

fn drawGraph(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    scissor(c);
    defer rl.endScissorMode();
    for (0..ed.map.node_n) |n| {
        const b = ed.boxAt(c, n);
        rl.drawRectangleRec(b, PANEL_BG);
        if (thumb(ed, n)) |t| sprite(t, .{ .x = b.x, .y = b.y + @as(f32, @floatFromInt(BOX_TOP)), .width = @floatFromInt(BOX_W), .height = @floatFromInt(BOX_H - BOX_TOP) });
        drawNodeTitle(ed, g, n, b, @as(i32, @intFromFloat(b.y)) + TITLE_DY);
        rl.drawRectangleLinesEx(b, 1, if (n == ed.node) ON else look.EDGE);
    }
    for (ed.map.nodes(), 0..) |*nd, n| {
        for (nd.doors(), 0..) |d, k| {
            const here = atlas.Link{ .node = n, .door = k };
            const at = ed.dotAt(c, here);
            const to = d.to orelse {
                rl.drawCircleV(at, DOT_R, WARN);
                continue;
            };
            if (to.node > n or (to.node == n and to.door > k)) rl.drawLineEx(at, ed.dotAt(c, to), LINK_W, look.DOOR.fg);
            rl.drawCircleV(at, DOT_R, look.DOOR.fg);
        }
    }
    if (ed.dotUnder(c, ed.desk.mouse)) |l| rl.drawCircleLinesV(ed.dotAt(c, l), DOT_R + DOT_SLOP, look.RETICLE);
    if (ed.linking) |from| rl.drawLineEx(ed.dotAt(c, from), vec(ed.desk.mouse), LINK_W, PICKED);
}

fn thumb(ed: *Editor, n: usize) ?rl.Texture2D {
    if (!ed.thumb_ok.isSet(n)) {
        const lv = if (n == ed.node and !ed.stale) &ed.lv else blk: {
            ed.map.node[n].stamp(&ed.thumb_lv, ed.roll);
            break :blk &ed.thumb_lv;
        };
        var px: [grid.CELLS]rl.Color = undefined;
        for (&px, 0..) |*c, i| {
            c.* = if (look.Mark.of(lv, i)) |m|
                m.look().fg
            else if (if (lv.wallShape(grid.Level.of(i))) |s| s.solid() else false)
                look.BG
            else
                look.mini(lv.tile[i], true);
        }
        if (ed.thumbs[n] == null) {
            ed.thumbs[n] = look.canvas(grid.W, grid.H, look.BG, .point);
        }
        if (ed.thumbs[n]) |t| rl.updateTexture(t, &px);
        ed.thumb_ok.set(n);
    }
    return ed.thumbs[n];
}

fn drawModal(ed: *Editor, g: *game.Game) void {
    var buf: [LINE]u8 = undefined;
    game.veil(g);
    switch (ed.modal) {
        .help => return drawHelp(ed, g),
        .objects => return drawObjects(ed, g),
        .none, .confirm, .name, .open => {},
    }
    const body = modalBody(ed);
    var title_buf: [atlas.PATH_MAX + LINE]u8 = undefined;
    var dir_buf: [atlas.PATH_MAX]u8 = undefined;
    const title: [:0]const u8 = switch (ed.modal) {
        .confirm => "Unsaved changes",
        .name => if (ed.naming == .new) "New map" else "Save the map as",
        .open => std.fmt.bufPrintZ(&title_buf, "Open: {s}", .{ed.listing.dirPath(&dir_buf)}) catch "Open",
        .none, .help, .objects => "",
    };
    const f = modalFrame(g, MODAL_W, MODAL_HEAD + body + ROW_H + PAD, title, true);
    const x = f.x;
    var y = f.y;
    const buttons_y = y + body;
    const bx = f.buttonX();
    const inner = f.w - PAD * 2;
    switch (ed.modal) {
        .confirm => {
            var fit_buf: [LINE]u8 = undefined;
            g.face.draw(fitBefore(g, &buf, &fit_buf, ed.path(), " has changes that are not saved.", inner), x + PAD, y, TEXT, look.TEXT);
            std.debug.assert(y + TEXT <= buttons_y);
            y = buttons_y;
            if (buttonOn(ed, g, modalButton(bx, y, 2), keyed("Save", Desk.ENTER_CAPTION), false, true, true, null) and ed.save()) ed.commit();
            if (buttonOn(ed, g, modalButton(bx, y, 1), "Discard", false, true, true, null)) ed.commit();
            backButton(ed, g, bx, y, "Cancel");
        },
        .name => {
            fieldRow(ed, g, row(x + PAD, y, inner));
            y += ROW_STEP;
            var pbuf: [atlas.PATH_MAX]u8 = undefined;
            const note = if (ed.namedPath(&pbuf)) |p| std.fmt.bufPrintZ(&buf, "Makes {s}", .{p}) catch "" else "Type a name";
            drawFit(g, note, SMALL, inner, false, x + PAD, y, look.DIM);
            std.debug.assert(y + SMALL <= buttons_y);
            y = buttons_y;
            if (buttonOn(ed, g, modalButton(bx, y, 1), keyed("OK", Desk.ENTER_CAPTION), false, true, true, null)) ed.named();
            backButton(ed, g, bx, y, "Cancel");
        },
        .open => {
            if (ed.listing.n == 0) g.face.draw(atlas.NO_MAPS, x + PAD, y, TEXT, look.DIM);
            for (ed.listed_top..@min(ed.listing.n, ed.listed_top + MODAL_ROWS)) |i| {
                const label = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ switch (ed.listing.entry(i)) {
                    .up => "^  ",
                    .folder => "+  ",
                    .map => "   ",
                }, ed.listing.label(i) }) catch "";
                const r = row(x + PAD, y, inner);
                if (i == ed.listed_at) rl.drawRectangleLinesEx(r, 1, HOVER);
                if (buttonOn(ed, g, r, label, std.mem.eql(u8, ed.listing.at(i), ed.path()), true, true, OPEN_TIPS.get(ed.listing.entry(i)))) {
                    return ed.openListed(i);
                }
                y += ROW_H;
            }
            std.debug.assert(y + @as(i32, if (ed.listing.n == 0) TEXT else 0) <= buttons_y);
            g.face.draw(OPEN_CRIB, x + PAD, buttons_y + TEXT_DY, SMALL, look.DIM);
            backButton(ed, g, bx, buttons_y, "Cancel");
        },
        .none, .help, .objects => {},
    }
}

const OPEN_TIPS = std.EnumArray(atlas.Listing.Entry, [:0]const u8).init(.{
    .up = "The folder above (" ++ input.RUB_CAPTION ++ ")",
    .folder = "Into this folder",
    .map = "Open this map",
});
const OPEN_CRIB = Desk.NAV_CAPTION ++ " pick" ++ SEP ++ Desk.ENTER_CAPTION ++ " open" ++ SEP ++ input.RUB_CAPTION ++ " up";

const HELP_W: i32 = 1000;

fn drawHelp(ed: *Editor, g: *game.Game) void {
    const line_h = TEXT + GAP;
    const f = modalFrame(g, HELP_W, MODAL_HEAD + PAD + HELP_ROWS * line_h + ROW_H + PAD, "Every key", false);
    const x = f.x;
    const w = f.w;
    var y = f.y;
    for (HELP) |s| {
        drawFit(g, s.head, TEXT, w - 2 * PAD, false, x + PAD, y, look.DIM);
        y += line_h;
        for (s.lines) |l| {
            drawFit(g, l, TEXT, w - 2 * PAD, false, x + PAD, y, look.TEXT);
            y += line_h;
        }
    }
    backButton(ed, g, f.buttonX(), y, "Close");
}

const VIEW_W: i32 = 960;
const VIEW_COLS: usize = 7;
const VIEW_CELL: i32 = 72;
const VIEW_PIC: f32 = 48;
const VIEW_BIG: f32 = 192;

fn drawObjects(ed: *Editor, g: *game.Game) void {
    const grid_w = @as(i32, VIEW_COLS) * VIEW_CELL;
    const title = "Objects";
    var cells = Tiles{ .x = 0, .y = 0, .cols = VIEW_COLS, .pitch = VIEW_CELL, .size = VIEW_CELL - GAP };
    const cells_h = cells.height(SEEN.len);
    const f = modalFrame(g, VIEW_W, MODAL_HEAD + PAD + cells_h + ROW_STEP, title, false);
    const x = f.x;
    const w = f.w;
    const y = f.y;
    cells.x = x + PAD;
    cells.y = y;
    g.face.draw(Desk.NAV_CAPTION ++ " or a click picks one" ++ SEP ++ Desk.BACK_CAPTION ++ " closes", x + PAD + g.face.width(title, HEAD) + PAD, f.top + @divTrunc(HEAD - SMALL, 2), SMALL, look.DIM);
    for (SEEN, 0..) |s, i| {
        const r = cells.at(i);
        const hh = hot(ed, r, true, true, seenName(s));
        plate(r, i == ed.seen_at, hh.hot);
        seenPicture(g, s, .{ .x = r.x + (r.width - VIEW_PIC) / 2, .y = r.y + 4, .width = VIEW_PIC, .height = VIEW_PIC });
        if (hh.hit) ed.seen_at = i;
    }
    const s = SEEN[ed.seen_at];
    const dx = x + PAD + grid_w + PAD;
    var dy = y;
    seenPicture(g, s, .{ .x = @floatFromInt(dx), .y = @floatFromInt(dy), .width = VIEW_BIG, .height = VIEW_BIG });
    rl.drawRectangleLines(dx, dy, @intFromFloat(VIEW_BIG), @intFromFloat(VIEW_BIG), look.EDGE);
    dy += @as(i32, @intFromFloat(VIEW_BIG)) + PAD;
    g.face.draw(seenName(s), dx, dy, HEAD, look.TEXT);
    dy += HEAD + GAP;
    var facts = Facts{};
    seenFacts(s, &facts);
    for (facts.all()) |l| {
        drawFit(g, l, TEXT, x + w - PAD - dx, false, dx, dy, look.DIM);
        dy += TEXT + GAP;
    }
    backButton(ed, g, f.buttonX(), y + cells_h, "Close");
}

fn seenName(s: Seen) [:0]const u8 {
    return switch (s) {
        .tile => |t| menu.named(t),
        .body => |k| kindName(k),
        inline else => |_, tag| comptime menu.named(tag),
    };
}

fn seenPicture(g: *game.Game, s: Seen, r: rl.Rectangle) void {
    switch (s) {
        .tile => |t| swatch(g, t, r),
        .body => |k| figure(g, g.sprites.body(k), look.body(k), r),
        .barrel => figure(g, g.sprites.barrel, look.BARREL, r),
        .torch => glyph(g, look.TORCH.ch, r, look.TORCH.fg),
        .door => glyph(g, look.DOOR.ch, r, look.DOOR.fg),
    }
}

const FACTS_MAX: usize = 8;

const Facts = struct {
    buf: [FACTS_MAX][LINE]u8 = undefined,
    line: [FACTS_MAX][:0]const u8 = undefined,
    n: usize = 0,

    fn put(f: *Facts, comptime fmt: []const u8, args: anytype) void {
        if (f.n == FACTS_MAX) return;
        f.line[f.n] = std.fmt.bufPrintZ(&f.buf[f.n], fmt, args) catch "";
        f.n += 1;
    }

    fn all(f: *const Facts) []const [:0]const u8 {
        return f.line[0..f.n];
    }
};

fn seenFacts(s: Seen, f: *Facts) void {
    switch (s) {
        .tile => |t| {
            f.put("Letter '{c}' in a map file", .{t.letter()});
            f.put("{s}; {s}", .{ if (t.solid()) "Blocks a step" else "Walked on", if (t.blind()) "blocks sight" else "seen through" });
            if (t.liquid()) f.put("A liquid: gas spreads over it, a trail bridges it", .{});
            if (look.under(t)) |u| f.put("Drawn over the ground beside it, else {s}", .{@tagName(u)});
            if (dual.of(t)) |gr| if (look.GROUND_SHEETS.contains(gr)) f.put("Ground {s}: its edges meet the grounds below it", .{@tagName(gr)});
            if (look.stands(t)) f.put("Stands up and throws a shadow", .{});
            if (t == .chest) f.put("Opened by stepping toward it; contains gold, never broken by attacks", .{});
            if (t == .chest_open) f.put("Already opened and empty; may be walked over", .{});
        },
        .body => |k| {
            const r = actor.row(k);
            f.put("Movement: {s}", .{menu.named(r.movement)});
            if (r.foe_type) |kind| f.put("Foe type: {s}", .{menu.named(kind)});
            f.put("{d} hp, sees {d} cells", .{ r.hp, r.sight });
            switch (r.blow) {
                .strike => |st| {
                    f.put("Its blow: it {s} for {d} to {d}", .{ st.verb, st.lo, st.hi });
                    if (st.bleeds > 0) f.put("{d}% of its blows open a bleed", .{st.bleeds});
                },
                .burst => f.put("Bursts into caustic gas instead of striking", .{}),
            }
            if (r.light > 0) f.put("Carries a light {d} cells round", .{r.light});
            if (r.splits) |into| f.put("Splits into two {s}s under half its hp", .{actor.row(into).name});
            if (r.flits) f.put("Flits: {d:.0}% of its moves go a random way", .{actor.FLIT * 100});
            if (r.flees) f.put("Runs {d} turns when it sees a foe die within {d} cells", .{ actor.FLEE_TURNS, actor.FRIGHT_REACH });
            if (k.foe() and !k.stocked()) f.put("Only split off another; never placed", .{});
        },
        .barrel => {
            f.put("Stands on " ++ @tagName(grid.BARREL_GROUND) ++ "; one hit, shot or kicked, breaks it for gold", .{});
            f.put("Blocks a step and stops an arrow", .{});
        },
        .torch => f.put(menu.capital(TORCH_RULE) ++ "; lights {d} cells round", .{lume.TORCH_REACH}),
        .door => f.put("Leads both ways to one door on any node", .{}),
    }
}

fn modalBody(ed: *const Editor) i32 {
    return switch (ed.modal) {
        .confirm => ROW_H * 2 + PAD,
        .name => ROW_STEP + ROW_H + PAD,
        .open => @as(i32, @intCast(@max(1, @min(ed.listing.n, MODAL_ROWS)))) * ROW_H + PAD,
        .none, .help, .objects => 0,
    };
}

fn modalButton(bx: i32, y: i32, k: i32) rl.Rectangle {
    return row(bx - (MODAL_BTN_W + GAP) * k, y, MODAL_BTN_W);
}

fn fieldRow(ed: *Editor, g: *game.Game, r: rl.Rectangle) void {
    var buf: [LINE]u8 = undefined;
    rl.drawRectangleRec(r, ROW_ON);
    const typed = std.fmt.bufPrintZ(&buf, "{s}" ++ menu.CARET, .{ed.field.text()}) catch "";
    drawFit(g, typed, TEXT, insetW(r), true, textX(r), @as(i32, @intFromFloat(r.y)) + TEXT_DY, look.RETICLE);
}

fn backButton(ed: *Editor, g: *game.Game, bx: i32, y: i32, comptime label: []const u8) void {
    if (buttonOn(ed, g, modalButton(bx, y, 0), keyed(label, Desk.BACK_CAPTION), false, true, true, null)) ed.modal = .none;
}

fn sprite(t: rl.Texture2D, r: rl.Rectangle) void {
    look.stretch(t, r, look.LIT);
}

fn figure(g: *game.Game, tex: ?rl.Texture2D, l: look.Look, r: rl.Rectangle) void {
    if (tex) |t| sprite(t, r) else glyph(g, l.ch, r, l.fg);
}

const GlyphBox = struct { x: i32, y: i32, size: i32 };

fn inkIn(r: rl.Rectangle) GlyphBox {
    return .{ .x = @intFromFloat(r.x + r.width * 0.5), .y = @intFromFloat(r.y + r.height * 0.5), .size = @intFromFloat(r.width * GLYPH_OF_CELL) };
}

fn glyph(g: *game.Game, ch: u8, r: rl.Rectangle, col: rl.Color) void {
    const m = inkIn(r);
    g.face.glyph(ch, m.x, m.y, m.size, col);
}

fn tileGlyph(g: *game.Game, t: grid.Tile, r: rl.Rectangle) void {
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
        prepare(ed, g);
        rl.beginTextureMode(target);
        draw(ed, g);
        rl.endTextureMode();
        try game.exportTarget(target, p);
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
    ed.gen_top = ed.gen_most;
    draw(ed, g);
    rl.endTextureMode();
    try game.exportTarget(target, gen_path);
    ed.modal = .objects;
    for (SEEN, 0..) |s, i| {
        if (std.meta.eql(s, Seen{ .body = .slime })) ed.seen_at = i;
    }
    prepare(ed, g);
    rl.beginTextureMode(target);
    draw(ed, g);
    rl.endTextureMode();
    try game.exportTarget(target, objects_path);
}

fn testEditor() !*Editor {
    const ed = try Editor.create(std.testing.allocator);
    ed.map.* = .{};
    ed.setPath(atlas.mapPath("test_editor"));
    return ed;
}

fn testBespoke() !*Editor {
    const ed = try testEditor();
    _ = ed.map.add(.{ .bespoke = .{} });
    return ed;
}

fn dragFirstBox(ed: *Editor) P {
    const was = ed.map.node[0].pos;
    ed.view = .graph;
    ed.gesture();
    ed.drag = .{ .node = 0, .grab = .{ .x = 0, .y = 0 }, .from = .{ .x = 100, .y = 100 }, .was = was };
    ed.desk = .{ .paint = true, .mouse = .{ .x = 200, .y = 100 } };
    graphMouse(ed, TEST_CANVAS, true);
    return was;
}

fn mouseOn(ed: *const Editor, c: rl.Rectangle, p: P) P {
    const r = ed.cellRect(c, p);
    return .{ .x = @as(i32, @intFromFloat(r.x)) + 1, .y = @as(i32, @intFromFloat(r.y)) + 1 };
}

fn click(ed: *Editor, t: Tool, p: P) void {
    ed.gesture();
    ed.tool = t;
    place(ed, p);
}

fn paintClick(ed: *Editor, t: grid.Tile, p: P) void {
    ed.ink.set(.first, t);
    click(ed, .paint, p);
    ed.ink.set(.first, .floor);
}

test "painting a bespoke node: a door opens its wall and no wall paints over it" {
    const ed = try testEditor();
    defer ed.destroy();
    const w = ed.map;
    _ = w.add(.{ .bespoke = .{} });
    ed.tool = .paint;
    laySpan(ed, .{ .from = .{ .x = 4, .y = 5 }, .erase = false, .shape = .rect }, .{ .x = 9, .y = 5 });
    click(ed, .door, .{ .x = 10, .y = 5 });
    paintClick(ed, .wall, .{ .x = 10, .y = 5 });
    click(ed, .{ .foe = .rat }, .{ .x = 5, .y = 5 });
    click(ed, .{ .foe = .rat }, .{ .x = 5, .y = 9 });
    click(ed, .torch, .{ .x = 6, .y = 4 });
    click(ed, .torch, .{ .x = 6, .y = 3 });
    ed.gesture();
    ed.tool = .paint;
    remove(ed, .{ .x = 4, .y = 5 });
    ed.preview();
    try std.testing.expectEqual(grid.Tile.wall, ed.lv.at(.{ .x = 4, .y = 5 }));
    try std.testing.expect(ed.lv.walkable(.{ .x = 10, .y = 5 }));
    try std.testing.expectEqual(@as(?usize, 0), ed.lv.doorAt(.{ .x = 10, .y = 5 }));
    try std.testing.expectEqual(@as(usize, 1), w.node[0].plan.bespoke.foe_n);
    try std.testing.expectEqual(@as(usize, 1), ed.lv.torch.n);
    try std.testing.expect(ed.dirty);
    const map = look.Assets.of(&ed.lv);
    try std.testing.expect(std.meta.eql(map.merge(ed.assets), ed.assets));
    try std.testing.expect(ed.assets.bodies.contains(.rat) and ed.assets.bodies.contains(.slime_quarter) and ed.assets.barrel);
}

test "the link tool joins doors on two nodes, and a procgen node takes doors but no floor" {
    const ed = try testEditor();
    defer ed.destroy();
    const w = ed.map;
    _ = w.add(.{ .bespoke = .{} });
    _ = w.add(.{ .procgen = .{} });
    click(ed, .door, .{ .x = 3, .y = 3 });
    ed.select(1);
    click(ed, .door, .{ .x = 40, .y = 30 });
    click(ed, .link, .{ .x = 40, .y = 30 });
    ed.select(0);
    click(ed, .link, .{ .x = 3, .y = 3 });
    try std.testing.expectEqual(@as(?atlas.Link, .{ .node = 1, .door = 0 }), w.node[0].door[0].to);
    try std.testing.expectEqual(@as(?atlas.Link, .{ .node = 0, .door = 0 }), w.node[1].door[0].to);
    try std.testing.expect(!@as(Tool, .paint).fits(&w.node[1]));
    try std.testing.expect(@as(Tool, .door).fits(&w.node[1]));
    ed.select(1);
    ed.preview();
    try std.testing.expectEqual(@as(?usize, 0), ed.lv.doorAt(.{ .x = 40, .y = 30 }));
}

test "a gesture is one undo however much it paints, and redo puts it back" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.gesture();
    ed.tool = .paint;
    laySpan(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false, .shape = .rect }, .{ .x = 11, .y = 6 });
    ed.gesture();
    laySpan(ed, .{ .from = .{ .x = 2, .y = 8 }, .erase = false, .shape = .rect }, .{ .x = 3, .y = 8 });
    ed.gesture();
    try std.testing.expectEqual(@as(usize, 52), count(ed, .floor));
    try std.testing.expectEqual(@as(usize, 2), ed.hist_at);
    ed.undo();
    try std.testing.expectEqual(@as(usize, 50), count(ed, .floor));
    ed.undo();
    try std.testing.expectEqual(@as(usize, 0), count(ed, .floor));
    ed.redo();
    ed.redo();
    try std.testing.expectEqual(@as(usize, 52), count(ed, .floor));
    ed.undo();
    ed.gesture();
    laySpan(ed, .{ .from = .{ .x = 20, .y = 20 }, .erase = false, .shape = .rect }, .{ .x = 20, .y = 20 });
    try std.testing.expectEqual(ed.hist_at, ed.hist_len);
    try std.testing.expectEqual(@as(usize, 51), count(ed, .floor));
    std.debug.print("two strokes over 52 cells, then one after an undo: {d} undo steps\n", .{ed.hist_at});
}

test "undo keeps no more than its cap, dropping the oldest" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    for (0..UNDO_CAP + 5) |i| {
        ed.gesture();
        place(ed, .{ .x = @intCast(1 + i), .y = 1 });
    }
    try std.testing.expectEqual(UNDO_CAP, ed.hist_len);
    for (0..UNDO_CAP) |_| ed.undo();
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 5, .y = 1 }));
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 1 }));
}

test "undoing back to what was saved leaves nothing unsaved, and a press held through New lets go" {
    const ed = try testBespoke();
    defer ed.destroy();
    click(ed, .paint, .{ .x = 3, .y = 3 });
    ed.saved_at = ed.hist_at;
    ed.dirty = false;
    click(ed, .paint, .{ .x = 4, .y = 3 });
    ed.undo();
    try std.testing.expect(!ed.dirty);
    ed.undo();
    try std.testing.expect(ed.dirty);
    ed.redo();
    try std.testing.expect(!ed.dirty);
    ed.drag = .{ .node = 0, .grab = .{ .x = 0, .y = 0 }, .from = .{ .x = 0, .y = 0 }, .was = .{ .x = 0, .y = 0 } };
    ed.span = .{ .from = .{ .x = 1, .y = 1 }, .erase = false, .shape = .rect };
    ed.dirty = false;
    ed.request(.new);
    try std.testing.expect(ed.drag == null and ed.span == null);
}

const TEST_CANVAS = rl.Rectangle{ .x = 0, .y = 0, .width = 2000, .height = 2000 };

test "a fast stroke paints every cell it passes, and Esc mid-rectangle lets the press go" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ 0, 0 };
    ed.tool = .paint;
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 2 }) };
    ed.gesture();
    mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 12, .y = 2 }) };
    mapMouse(ed, c, true);
    const row_n = rowCount(ed, 2, .floor);
    mapMouse(ed, c, false);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 4 }) };
    mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 4, .y = 4 }));
    ed.desk = .{};
    mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .paint_hit = true, .shift = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 6 }) };
    ed.gesture();
    mapMouse(ed, c, true);
    try std.testing.expect(ed.span != null);
    escape(ed);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 8, .y = 6 }) };
    mapMouse(ed, c, true);
    const stray = tileAt(ed, .{ .x = 8, .y = 6 });
    std.debug.print("a stroke dragged 10 cells in one frame: {d} cells painted\n", .{row_n});
    try std.testing.expectEqual(@as(usize, 11), row_n);
    try std.testing.expectEqual(grid.Tile.wall, stray);
    try std.testing.expect(ed.standable(.{ .node = 0, .at = .{ .x = 30, .y = 30 } }));
    _ = ed.map.add(.{ .bespoke = .{} });
    try std.testing.expect(!ed.standable(.{ .node = 1, .at = .{ .x = 30, .y = 30 } }));
}

test "a stroke leaving the map paints up to its edge, and it ends with the button that began it" {
    const ed = try testBespoke();
    defer ed.destroy();
    const b = &ed.map.node[0].plan.bespoke;
    const c = TEST_CANVAS;
    ed.cam = .{ -4, 0 };
    ed.tool = .paint;
    ed.gesture();
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 5, .y = 10 }) };
    mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = -3, .y = 10 }) };
    mapMouse(ed, c, true);
    const row_n = rowCount(ed, 10, .floor);
    ed.desk = .{ .paint = true, .erase = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 20, .y = 20 }) };
    mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 10 }) };
    mapMouse(ed, c, true);
    std.debug.print("a stroke from x 5 to x -3 in one frame: {d} cells painted to the edge\n", .{row_n});
    try std.testing.expectEqual(@as(usize, 6), row_n);
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 4, .y = 10 }));
    click(ed, .torch, .{ .x = 3, .y = 9 });
    try std.testing.expectEqual(@as(usize, 1), b.torch.n);
    paintClick(ed, .wall, .{ .x = 3, .y = 10 });
    try std.testing.expectEqual(@as(usize, 0), b.torch.n);
    ed.tool = .paint;
    ed.desk = .{ .shift = true, .paint = true, .erase = true, .paint_hit = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 8, .y = 8 }) };
    mapMouse(ed, c, true);
    try std.testing.expect(!ed.span.?.erase);
}

test "a click off the map ends the stroke held through it" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ 0, 0 };
    ed.tool = .paint;
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 2 }) };
    ed.gesture();
    mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .erase = true, .erase_hit = true, .mouse = .{ .x = -5, .y = -5 } };
    ed.gesture();
    mapMouse(ed, c, false);
    ed.desk = .{ .paint = true, .erase = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 2 }) };
    mapMouse(ed, c, true);
    try std.testing.expectEqual(@as(usize, 1), ed.hist_at);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 4, .y = 2 }));
}

test "a rectangle begun off the map fills from its edge" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ -4, -4 };
    ed.tool = .paint;
    ed.gesture();
    ed.desk = .{ .shift = true, .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = -2, .y = -2 }) };
    mapMouse(ed, c, true);
    ed.desk = .{ .shift = true, .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 4 }) };
    mapMouse(ed, c, true);
    ed.desk = .{ .mouse = mouseOn(ed, c, .{ .x = 4, .y = 4 }) };
    mapMouse(ed, c, true);
    const n = count(ed, .floor);
    std.debug.print("a rectangle from -2,-2 to 4,4: {d} cells of floor\n", .{n});
    try std.testing.expectEqual(@as(usize, 25), n);
}

test "a click on the frame a rectangle is let go is an undo of its own" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ 0, 0 };
    ed.tool = .paint;
    ed.desk = .{ .shift = true, .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 2 }) };
    ed.gesture();
    mapMouse(ed, c, true);
    ed.desk = .{ .erase = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 6, .y = 4 }) };
    ed.gesture();
    mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 4 }));
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 5, .y = 4 }));
    ed.undo();
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 6, .y = 4 }));
}

test "a door on a wall taken away takes the torch it held up" {
    const ed = try testBespoke();
    defer ed.destroy();
    const b = &ed.map.node[0].plan.bespoke;
    const door = P{ .x = 6, .y = 5 };
    const torch = lume.torchWall(door);
    _ = ed.map.addDoor(0, door);
    try std.testing.expect(b.torch.add(torch));
    try std.testing.expect(ed.here().torchFits(b, torch));
    ed.gesture();
    ed.tool = .door;
    remove(ed, door);
    try std.testing.expectEqual(@as(usize, 0), b.torch.n);
}

test "the other button pressed mid graph drag puts the box back, and leaves no undo" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    const was = dragFirstBox(ed);
    try std.testing.expect(!ed.map.node[0].pos.eq(was));
    ed.desk = .{ .paint = true, .erase = true, .erase_hit = true, .mouse = .{ .x = 300, .y = 100 } };
    ed.drop();
    ed.desk = .{ .paint = true, .erase = true, .mouse = .{ .x = 400, .y = 100 } };
    graphMouse(ed, c, true);
    ed.desk = .{ .mouse = .{ .x = 400, .y = 100 } };
    graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(usize, 0), ed.hist_at);
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expect(!ed.dirty);
}

test "leaving with unsaved changes asks first, and leaving a saved map does not" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.request(.leave);
    try std.testing.expect(ed.action == .leave);
    ed.action = .none;
    click(ed, .paint, .{ .x = 3, .y = 3 });
    ed.request(.leave);
    try std.testing.expectEqual(Modal.confirm, ed.modal);
    try std.testing.expect(ed.action == .none);
    ed.commit();
    try std.testing.expect(ed.action == .leave);
}

test "leaving or closing mid graph drag keeps the move and asks before discarding it" {
    for ([_]Pending{ .leave, .quit }) |pending| {
        const ed = try testBespoke();
        defer ed.destroy();
        const was = dragFirstBox(ed);
        const moved = ed.map.node[0].pos;
        try std.testing.expect(!moved.eq(was));
        ed.request(pending);
        try std.testing.expectEqual(Modal.confirm, ed.modal);
        try std.testing.expect(ed.action == .none);
        try std.testing.expect(ed.drag == null);
        try std.testing.expectEqual(moved, ed.map.node[0].pos);
        try std.testing.expect(ed.dirty);
        ed.modal = .none;
        ed.undo();
        try std.testing.expectEqual(was, ed.map.node[0].pos);
        try std.testing.expect(!ed.dirty);
    }
    std.debug.print("2 departure paths preserve an active graph move, prompt, and undo to the saved state\n", .{});
}

test "a rename is one undo, and deleting a node renumbers the list round it" {
    const ed = try testEditor();
    defer ed.destroy();
    for (0..3) |_| _ = ed.map.add(.{ .bespoke = .{} });
    ed.select(1);
    ed.startRename();
    ed.field.set("Crypt", atlas.NAME_MAX);
    ed.commitRename();
    try std.testing.expectEqualStrings("Crypt", ed.map.node[1].name());
    ed.select(0);
    ed.gesture();
    deleteNode(ed);
    try std.testing.expectEqualStrings("Crypt", ed.map.node[0].name());
    ed.undo();
    ed.undo();
    try std.testing.expectEqual(@as(usize, 3), ed.map.node_n);
    try std.testing.expectEqual(@as(usize, 0), ed.map.node[1].label.n);
}

test "undo and redo disarm deletion when a node index changes owners" {
    const ed = try testEditor();
    defer ed.destroy();
    for ([_][]const u8{ "First", "Second", "Third" }) |name| {
        const n = ed.map.add(.{ .bespoke = .{} }).?;
        _ = ed.map.node[n].rename(name);
    }
    ed.gesture();
    deleteNode(ed);
    ed.select(1);
    ed.delete_armed = ed.node;
    try std.testing.expectEqualStrings("Third", ed.here().name());
    ed.undo();
    try std.testing.expectEqualStrings("Second", ed.here().name());
    try std.testing.expect(ed.delete_armed == null);
    ed.delete_armed = ed.node;
    ed.redo();
    try std.testing.expectEqualStrings("Third", ed.here().name());
    try std.testing.expect(ed.delete_armed == null);
    ed.delete_armed = ed.node;
    escape(ed);
    try std.testing.expect(ed.delete_armed == null);
    try std.testing.expectEqual(Action.none, ed.action);
    try std.testing.expectEqual(Modal.none, ed.modal);
    std.debug.print("2 history swaps changed the selected node and cleared its deletion confirmation\n", .{});
}

test "a node added is named as it is added, one undo for both" {
    const ed = try testBespoke();
    defer ed.destroy();
    const before = ed.map.node_n;
    ed.gesture();
    addNode(ed, .{ .procgen = .{} });
    try std.testing.expect(ed.renaming);
    var buf: [LINE]u8 = undefined;
    ed.field.set("Pit", atlas.NAME_MAX);
    try std.testing.expect(std.mem.endsWith(u8, ed.nodeTitle(ed.node, &buf), "Pit" ++ menu.CARET));
    ed.commitRename();
    try std.testing.expectEqualStrings("Pit", ed.map.node[before].name());
    ed.undo();
    try std.testing.expectEqual(before, ed.map.node_n);
}

fn tileAt(ed: *Editor, p: P) grid.Tile {
    return ed.map.node[ed.node].plan.bespoke.tile[grid.Level.idx(p)];
}

fn rowCount(ed: *Editor, y: i32, t: grid.Tile) usize {
    var n: usize = 0;
    var x: i32 = 0;
    while (x < grid.W) : (x += 1) n += @intFromBool(tileAt(ed, .{ .x = x, .y = y }) == t);
    return n;
}

fn count(ed: *Editor, t: grid.Tile) usize {
    var n: usize = 0;
    for (ed.map.node[ed.node].plan.bespoke.tile) |x| n += @intFromBool(x == t);
    return n;
}

test "a line, a box and a fill lay the inks, each one undo, and the eyedropper picks a tile or what stands on it" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    ed.gesture();
    laySpan(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false, .shape = .line }, .{ .x = 12, .y = 7 });
    const line = count(ed, .floor);
    ed.gesture();
    laySpan(ed, .{ .from = .{ .x = 20, .y = 20 }, .erase = false, .shape = .box }, .{ .x = 29, .y = 25 });
    const boxed = count(ed, .floor) - line;
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 24, .y = 22 }));
    ed.gesture();
    ed.ink = .init(.{ .first = .water, .second = .wall });
    fill(ed, .{ .x = 24, .y = 22 }, false);
    const filled = count(ed, .water);
    ed.gesture();
    fill(ed, .{ .x = 21, .y = 20 }, true);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 21, .y = 20 }));
    std.debug.print("a line 2,2 to 12,7: {d} cells; a 10x6 box: {d}; filled inside it: {d} cells of water\n", .{ line, boxed, filled });
    try std.testing.expectEqual(@as(usize, 11), line);
    try std.testing.expectEqual(@as(usize, 28), boxed);
    try std.testing.expectEqual(@as(usize, 32), filled);
    try std.testing.expectEqual(@as(usize, 4), ed.hist_at);
    click(ed, .{ .foe = .pib }, .{ .x = 2, .y = 2 });
    ed.tool = .paint;
    ed.preview();
    pickUp(ed, .{ .x = 22, .y = 22 }, true);
    try std.testing.expectEqual(grid.Tile.water, ed.ink.get(.second));
    pickUp(ed, .{ .x = 2, .y = 2 }, false);
    try std.testing.expect(ed.tool.eql(.{ .foe = .pib }));
}

test "a selection copied pastes with what stood on it, and cut leaves the second ink" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    ed.gesture();
    laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .rect }, .{ .x = 9, .y = 8 });
    click(ed, .{ .foe = .rat }, .{ .x = 6, .y = 6 });
    click(ed, .barrel, .{ .x = 4, .y = 4 });
    click(ed, .torch, .{ .x = 5, .y = 3 });
    ed.gesture();
    laySpan(ed, .{ .from = .{ .x = 4, .y = 3 }, .erase = false, .shape = .select }, .{ .x = 9, .y = 8 });
    copySelection(ed, false);
    try std.testing.expectEqual(P{ .x = 6, .y = 6 }, ed.board.size);
    startPaste(ed);
    try std.testing.expect(ed.pasting);
    ed.gesture();
    layBoard(ed, .{ .x = 30, .y = 20 });
    const b = &ed.map.node[0].plan.bespoke;
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 32, .y = 23 }));
    try std.testing.expect(b.foeAt(.{ .x = 32, .y = 23 }) != null);
    try std.testing.expect(b.barrel[grid.Level.idx(.{ .x = 30, .y = 21 })]);
    try std.testing.expect(b.torch.has(.{ .x = 31, .y = 20 }));
    ed.gesture();
    layBoard(ed, .{ .x = 30, .y = 20 });
    try std.testing.expectEqualStrings("Pasted", ed.said.text());
    const pasted = ed.hist_at;
    copySelection(ed, true);
    try std.testing.expectEqual(pasted + 1, ed.hist_at);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 6 }));
    try std.testing.expectEqual(@as(?usize, null), b.foeAt(.{ .x = 6, .y = 6 }));
    std.debug.print("6x6 copied and pasted at 30,20 with its rat, barrel and torch; cut leaves {d} foe(s)\n", .{b.foe_n});
    try std.testing.expectEqual(@as(usize, 1), b.foe_n);
}

test "a door's dot dragged onto another's on the graph links them, and the other button on one unlinks it" {
    const ed = try testBespoke();
    defer ed.destroy();
    _ = ed.map.add(.{ .bespoke = .{} });
    _ = ed.map.addDoor(0, .{ .x = 10, .y = 10 });
    _ = ed.map.addDoor(1, .{ .x = 20, .y = 20 });
    const c = TEST_CANVAS;
    ed.view = .graph;
    const a = ed.dotAt(c, .{ .node = 0, .door = 0 });
    const b = ed.dotAt(c, .{ .node = 1, .door = 0 });
    ed.gesture();
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = .{ .x = @intFromFloat(a.x), .y = @intFromFloat(a.y) } };
    graphMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = .{ .x = @intFromFloat(b.x), .y = @intFromFloat(b.y) } };
    graphMouse(ed, c, true);
    ed.desk = .{ .mouse = .{ .x = @intFromFloat(b.x), .y = @intFromFloat(b.y) } };
    graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(?atlas.Link, .{ .node = 1, .door = 0 }), ed.map.node[0].door[0].to);
    try std.testing.expectEqual(@as(usize, 1), ed.hist_at);
    ed.gesture();
    ed.desk = .{ .erase = true, .erase_hit = true, .mouse = .{ .x = @intFromFloat(a.x), .y = @intFromFloat(a.y) } };
    graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(?atlas.Link, null), ed.map.node[1].door[0].to);
    try std.testing.expectEqual(@as(usize, 2), ed.hist_at);
}

test "Open lists the edited map's folder and Esc goes up a folder before it closes; a new name goes beside the map" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.setPath(".\\" ++ comptime atlas.mapPath("qud\\qud_strata"));
    try std.testing.expectEqualStrings(atlas.DIR ++ "/qud/qud_strata" ++ atlas.EXT, ed.path());
    ed.askOpen();
    try std.testing.expectEqualStrings("qud/", ed.listing.here());
    try std.testing.expectEqualStrings(ed.path(), ed.listing.at(ed.listed_at));
    ed.desk = .{ .back = true };
    modalKeys(ed);
    try std.testing.expectEqual(Modal.open, ed.modal);
    try std.testing.expectEqual(@as(usize, 0), ed.listing.here().len);
    modalKeys(ed);
    try std.testing.expectEqual(Modal.none, ed.modal);
    ed.field.put("Bog");
    var buf: [atlas.PATH_MAX]u8 = undefined;
    try std.testing.expectEqualStrings(atlas.DIR ++ "/qud/bog" ++ atlas.EXT, ed.namedPath(&buf).?);
}

test "a full procgen preview keeps the hero's place in the pool, as play does" {
    const ed = try testEditor();
    defer ed.destroy();
    var foes = pack.Spec{ .packs = pack.PACKS_MAX, .few = 0, .gap = 0, .makeup_n = 1 };
    foes.makeup[0] = pack.Makeup.of(&(.{.rat} ** pack.MAKEUP_MAX));
    const n = ed.map.add(.{ .procgen = .{ .floor = .{ .wilds = .{} }, .foes = foes } }).?;
    ed.select(n);
    ed.preview();
    try std.testing.expectEqual(actor.MAX - actor.most(actor.HERO), ed.shown_n);
    try std.testing.expect(ed.lv.vacant(ed.arrival()) or ed.lv.at(ed.arrival()).solid());
}

test "a procgen node shows a roll of it with its packs, and a bespoke one counts the ground no walk reaches" {
    const ed = try testEditor();
    defer ed.destroy();
    const n = ed.map.add(.{ .procgen = .{ .floor = .{ .wilds = .{} } } }).?;
    ed.select(n);
    ed.preview();
    const open = ed.lv.openCount();
    const foes = ed.shown_n;
    const first = ed.lv.tile;
    reroll(ed);
    ed.preview();
    try std.testing.expect(!std.mem.eql(grid.Tile, &first, &ed.lv.tile));
    const b = ed.map.add(.{ .bespoke = .{} }).?;
    ed.select(b);
    ed.tool = .paint;
    ed.gesture();
    laySpan(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false, .shape = .rect }, .{ .x = 6, .y = 6 });
    laySpan(ed, .{ .from = .{ .x = 20, .y = 2 }, .erase = false, .shape = .rect }, .{ .x = 22, .y = 4 });
    ed.map.start = .{ .node = b, .at = .{ .x = 3, .y = 3 } };
    click(ed, .{ .foe = .rat }, .{ .x = 21, .y = 3 });
    ed.preview();
    std.debug.print("a wilds roll: {d} open cells, {d} foes placed; two rooms apart: {d} cells and {d} foe cut off\n", .{ open, foes, ed.issues.cut_off, ed.issues.foes_cut_off });
    try std.testing.expect(open > 0 and foes > 0);
    try std.testing.expectEqual(@as(usize, 9), ed.issues.cut_off);
    try std.testing.expectEqual(@as(usize, 1), ed.issues.foes_cut_off);
    try std.testing.expect(!ed.issues.start_walled);
}

test "undo mid graph drag takes the drag back as its own step, and the map after it is unsaved" {
    const ed = try testBespoke();
    defer ed.destroy();
    const was = dragFirstBox(ed);
    ed.undo();
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expect(ed.drag == null);
    ed.redo();
    try std.testing.expect(!ed.map.node[0].pos.eq(was));
    try std.testing.expect(ed.dirty);
}

test "a graph drag put back keeps what there was to redo" {
    const ed = try testBespoke();
    defer ed.destroy();
    _ = ed.map.add(.{ .bespoke = .{} });
    ed.select(1);
    for (0..UNDO_CAP) |_| {
        ed.gesture();
        ed.map.node[1].pos.x += 1;
        ed.bank();
    }
    ed.undo();
    ed.undo();
    const hist = .{ ed.hist_base, ed.hist_len, ed.hist_at };
    const was = dragFirstBox(ed);
    try std.testing.expect(!ed.map.node[0].pos.eq(was));
    ed.drop();
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expectEqual(hist, .{ ed.hist_base, ed.hist_len, ed.hist_at });
    ed.redo();
    ed.redo();
    try std.testing.expectEqual(ed.hist_len, ed.hist_at);
}

test "redo mid graph drag puts the box back and redoes" {
    const ed = try testBespoke();
    defer ed.destroy();
    _ = ed.map.add(.{ .bespoke = .{} });
    ed.gesture();
    ed.map.node[1].pos.x += 40;
    ed.bank();
    const moved = ed.map.node[1].pos;
    ed.undo();
    const was = dragFirstBox(ed);
    ed.redo();
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expect(ed.map.node[1].pos.eq(moved));
    try std.testing.expectEqual(ed.hist_len, ed.hist_at);
}

test "Esc mid stroke ends it, and a paste hanging off the map lays what lands on it" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ 0, 0 };
    ed.tool = .paint;
    ed.selection = grid.Box.sized(.{ .x = 0, .y = 0 }, 2, 2);
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 2 }) };
    ed.gesture();
    mapMouse(ed, c, true);
    escape(ed);
    try std.testing.expect(ed.selection != null);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 6, .y = 2 }) };
    mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 2 }));
    ed.desk = .{};
    mapMouse(ed, c, true);
    ed.gesture();
    laySpan(ed, .{ .from = .{ .x = 10, .y = 10 }, .erase = false, .shape = .rect }, .{ .x = 12, .y = 12 });
    ed.gesture();
    laySpan(ed, .{ .from = .{ .x = 10, .y = 10 }, .erase = false, .shape = .select }, .{ .x = 12, .y = 12 });
    copySelection(ed, false);
    startPaste(ed);
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = -1, .y = -1 }) };
    ed.gesture();
    mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 0, .y = 0 }));
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 1, .y = 1 }));
}

test "a graph drag let go of where it began leaves no undo and nothing unsaved" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    const was = dragFirstBox(ed);
    try std.testing.expect(!ed.map.node[0].pos.eq(was));
    const back = P{ .x = was.x + @as(i32, @intFromFloat(c.x - ed.gcam[0])), .y = was.y + @as(i32, @intFromFloat(c.y - ed.gcam[1])) };
    ed.desk = .{ .paint = true, .mouse = back };
    graphMouse(ed, c, true);
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    ed.desk = .{ .mouse = back };
    graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(usize, 0), ed.hist_at);
    try std.testing.expect(!ed.dirty);
}

test "deleting a node leaves the next unarmed and nothing selected, and the cursor refuses a foe with no room" {
    const ed = try testEditor();
    defer ed.destroy();
    for (0..3) |_| _ = ed.map.add(.{ .bespoke = .{} });
    ed.select(1);
    ed.delete_armed = 1;
    ed.selection = grid.Box.sized(.{ .x = 1, .y = 1 }, 2, 2);
    ed.gesture();
    deleteNode(ed);
    try std.testing.expectEqual(@as(?usize, null), ed.delete_armed);
    try std.testing.expect(ed.selection == null);
    ed.tool = .paint;
    ed.gesture();
    const room = grid.Box.sized(.{ .x = 2, .y = 2 }, 40, 3);
    laySpan(ed, .{ .from = room.lo, .erase = false, .shape = .rect }, room.hi.sub(.{ .x = 1, .y = 1 }));
    var cells = room.cells();
    while (cells.next()) |p| {
        if (!actor.roomFor(ed.map.node[ed.node].plan.bespoke.bodies(), .rat)) break;
        click(ed, .{ .foe = .rat }, p);
    }
    ed.tool = .{ .foe = .slime };
    try std.testing.expect(!legal(ed, .{ .x = 2, .y = 2 }));
    ed.tool = .{ .foe = .pib };
    try std.testing.expect(legal(ed, .{ .x = 2, .y = 2 }));
}

test "a knob's step is dim where its owner's fit would take it back" {
    var spec = pack.Spec{ .reach = pack.REACH_MAX };
    const reach = comptime for (FOE_ROWS) |k| {
        if (std.mem.eql(u8, k.field, "reach")) break k;
    } else unreachable;
    try std.testing.expect(!moves(&spec, reach, 0, 1));
    try std.testing.expect(moves(&spec, reach, 0, -1));
    spec.reach = pack.REACH_MIN;
    try std.testing.expect(!moves(&spec, reach, 0, -1));
}
