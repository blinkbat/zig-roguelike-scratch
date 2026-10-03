const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../world/grid.zig");
const atlas = @import("../world/atlas.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
const look = @import("../gfx/look.zig");
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
const TEXT: i32 = font.BODY;
const SMALL: i32 = 16;
const HEAD: i32 = 24;
const INNER_W: i32 = PANEL_W - PAD * 2;
const ZOOMS = [_]f32{ 8, 16, 32, 64 };
const ZOOM_AT: usize = 1;
const BRUSHES = [_]i32{ 1, 2, 3, 5 };
const PAN_PX_S: f32 = 900;
const SAY_S: f32 = 4;
const LINE: usize = 200;
const UNDO_CAP: usize = 24;
const PATH_MAX: usize = 256;
const FIELD_MAX: usize = 32;
/// A press that moves this far is a drag, not a click.
const DRAG_PX: i32 = 4;
/// Door numbers are unreadable below this many pixels a cell.
const LABEL_PX: f32 = 16;
const GLYPH_OF_CELL: f32 = @as(f32, @floatFromInt(look.GLYPH_PX)) / @as(f32, @floatFromInt(look.SPRITE_PX));
const LABEL_OF_CELL: f32 = 0.4;
const THUMB: i32 = 2;
const BOX_W: i32 = grid.W * THUMB;
const BOX_TOP: i32 = 26;
const BOX_H: i32 = BOX_TOP + grid.H * THUMB;
const LINK_W: f32 = 2;
const DOT_R: f32 = 4;
const MODAL_W: i32 = 600;
const MODAL_ROWS: usize = 12;
const MODAL_BTN_W: i32 = 150;
const LABEL_W: i32 = 96;
const STEP_W: i32 = 24;
const SHIFT_STEP: i32 = 5;
const WEIGHT_W: i32 = 30;
const MEMBER_W: i32 = 24;
const MEMBER_GAP: i32 = 2;
const WEIGHT_SPAN: i32 = 2 * STEP_W + WEIGHT_W;
const MEMBERS_X: i32 = WEIGHT_SPAN + 2 * GAP;
const MAKEUP_TOOLS_X: i32 = INNER_W - @as(i32, MAKEUP_TOOLS.len) * (STEP_W + GAP) + GAP;
const TORCH_STEP: i32 = 10;
const TOOL_COLS: usize = 2;
const TEXT_DY: i32 = @divTrunc(ROW_H - TEXT, 2);
const TITLE_DY: i32 = 3;
const NODE_GAP: i32 = 2;
const DETAIL_DY: i32 = TEXT + 1;

comptime {
    std.debug.assert(atlas.GRAPH_STEP.x > BOX_W and atlas.GRAPH_STEP.y > BOX_H);
    std.debug.assert(FIELD_MAX >= atlas.NAME_MAX);
    std.debug.assert(MEMBERS_X + @as(i32, pack.MAKEUP_MAX) * (MEMBER_W + MEMBER_GAP) <= MAKEUP_TOOLS_X);
}

const PANEL_BG = look.EDIT_PANEL;
const ROW_ON = look.EDIT_ROW_ON;
const ON = look.EDIT_ON;
const HOVER = look.EDIT_HOVER;
const PICKED = look.EDIT_PICKED;
const UNLINKED = look.EDIT_UNLINKED;
const WARN = look.EDIT_WARN;
const START = look.body(.archer);
const START_MARK = [_]u8{ START.ch, ' ' };

const Tool = enum {
    floor,
    wall,
    barrel,
    torch,
    rat,
    slime,
    bloat,
    door,
    link,
    start,

    fn foe(t: Tool) ?actor.Kind {
        return std.meta.stringToEnum(actor.Kind, @tagName(t));
    }

    fn fits(t: Tool, nd: *const atlas.Node) bool {
        return !nd.unrolled() or !t.generated();
    }

    /// A procgen node's floor, torches, barrels and foes are the generator's.
    fn generated(t: Tool) bool {
        return switch (t) {
            .door, .link, .start => false,
            .floor, .wall, .barrel, .torch, .rat, .slime, .bloat => true,
        };
    }

    /// Held down it paints every cell it passes; the rest act once a click.
    fn strokes(t: Tool) bool {
        return switch (t) {
            .floor, .wall, .barrel => true,
            .torch, .rat, .slime, .bloat, .door, .link, .start => false,
        };
    }

    /// Takes the brush's size and a shift-dragged rectangle.
    fn broad(t: Tool) bool {
        return switch (t) {
            .floor, .wall => true,
            .barrel, .torch, .rat, .slime, .bloat, .door, .link, .start => false,
        };
    }

    fn name(t: Tool) [:0]const u8 {
        return switch (t) {
            .floor => "Floor",
            .wall => "Wall",
            .barrel => "Barrel",
            .torch => "Torch",
            .rat => "Rat",
            .slime => "Slime",
            .bloat => "Bloat",
            .door => "Door",
            .link => "Link",
            .start => "Start",
        };
    }

    fn tip(t: Tool) [:0]const u8 {
        return switch (t) {
            .floor => "Floor: paint open ground; " ++ Desk.ERASE_CAPTION ++ " paints wall",
            .wall => "Wall: paint rock; " ++ Desk.ERASE_CAPTION ++ " paints floor",
            .barrel => "Barrel: breaks for gold; " ++ Desk.ERASE_CAPTION ++ " takes it away",
            .torch => "Torch: " ++ TORCH_RULE,
            .rat, .slime, .bloat => "Foe: " ++ FOE_RULE ++ "; " ++ Desk.ERASE_CAPTION ++ " takes any foe away",
            .door => "Door: any cell of any node; a procgen node's floor is rolled round its doors each run",
            .link => "Link: click a door, then the door it leads to on any node; " ++ Desk.ERASE_CAPTION ++ " unlinks",
            .start => "Start: where the world begins, and " ++ Desk.PLAY_CAPTION ++ " plays from",
        };
    }
};

const TOOLS = std.enums.values(Tool);
const TORCH_RULE = "hangs on a wall with floor below it";
const FOE_RULE = "stands on open floor";
/// "door, link and start": the tools a procgen node takes.
const UNGENERATED = blk: {
    var names: []const []const u8 = &.{};
    for (TOOLS) |t| {
        if (!t.generated()) names = names ++ &[_][]const u8{@tagName(t)};
    }
    var s: []const u8 = "";
    for (names, 0..) |nm, i| s = s ++ menu.listSep(i, names.len) ++ nm;
    break :blk s;
};

comptime {
    std.debug.assert(TOOLS.len == Desk.TOOL_KEYS.len);
    for (actor.FOES) |k| std.debug.assert(@hasField(Tool, @tagName(k)));
}

const SEP = menu.SEP;
const CRIB_MAP = Desk.PAINT_CAPTION ++ " place" ++ SEP ++ Desk.ERASE_CAPTION ++ " remove" ++ SEP ++ Desk.RECT_CAPTION ++
    " rectangle" ++ SEP ++ Desk.BRUSH_CAPTION ++ " brush" ++ SEP ++ Desk.TOOLS_CAPTION ++ " tool" ++ SEP ++
    Desk.GO_CAPTION ++ " through a door" ++ SEP ++ Desk.WHEEL_CAPTION ++ " zoom";
const CRIB_GRAPH = Desk.PAINT_CAPTION ++ " open a node" ++ SEP ++ "drag to move it" ++ SEP ++ Desk.GRAPH_CAPTION ++ " back to the map";
const CRIB_ALL = [_][:0]const u8{
    Desk.PAN_CAPTION ++ " pan" ++ SEP ++ Desk.GRAPH_CAPTION ++ " graph" ++ SEP ++ Desk.RENAME_CAPTION ++ " rename" ++ SEP ++
        Desk.UNDO_CAPTION ++ " undo" ++ SEP ++ Desk.REDO_CAPTION ++ " redo" ++ SEP ++ Desk.BACK_CAPTION ++ " back",
    Desk.SAVE_CAPTION ++ " save" ++ SEP ++ Desk.SAVE_AS_CAPTION ++ " save as" ++ SEP ++ Desk.OPEN_CAPTION ++ " open" ++ SEP ++
        Desk.NEW_CAPTION ++ " new" ++ SEP ++ Desk.PLAY_CAPTION ++ " play from the start" ++ SEP ++ Desk.PLAY_HERE_CAPTION ++ " from the cursor",
    Desk.WHEEL_CAPTION ++ " over the node list or generator scrolls it" ++ SEP ++ Desk.ENTER_CAPTION ++ " names a node" ++ SEP ++
        Desk.PLAY_CAPTION ++ " or " ++ Desk.PLAY_HERE_CAPTION ++ " back from playing" ++ SEP ++ Desk.FULLSCREEN_CAPTION ++ " fullscreen",
};
const STATUS_H: i32 = GAP * (@as(i32, CRIB_ALL.len) + 3) + TEXT * (@as(i32, CRIB_ALL.len) + 2);

comptime {
    @setEvalBranchQuota(100_000);
    var crib: []const u8 = CRIB_MAP ++ CRIB_GRAPH;
    for (CRIB_ALL) |l| crib = crib ++ l;
    for (@typeInfo(Desk).@"struct".decls) |d| {
        if (!std.mem.endsWith(u8, d.name, "_CAPTION")) continue;
        if (std.mem.indexOf(u8, crib, @as([]const u8, @field(Desk, d.name))) == null) @compileError("the crib never names " ++ d.name);
    }
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
/// What the panel shows under the node commands.
const Lower = enum { nodes, generator };
const Stroke = enum { none, paint, erase };
/// Asked for, and done once any unsaved changes are saved or let go.
const Pending = enum { leave, quit, open, new };
const Modal = enum { none, confirm, name, open };
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
const Path = Text(PATH_MAX);

const Drag = struct { node: usize, grab: P, from: P, moved: bool = false };
const Rect = struct { from: P, erase: bool };

pub const Editor = struct {
    alloc: std.mem.Allocator,
    world: *atlas.Atlas,
    /// The world as the gesture under way found it: banked on its first change. `open` parses into it and
    /// `swapStep` swaps through it.
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
    tool: Tool = .floor,
    brush: usize = 0,
    view: View = .map,
    lower: Lower = .nodes,
    /// Pixels of the generator scrolled off the top of its part of the panel, and the most there are.
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
    /// Node rows scrolled off the top of the list.
    scroll: usize = 0,
    /// The node as it will be played, less its foes: drawn, never read by an edit.
    lv: grid.Level = undefined,
    stale: bool = true,
    start_at: ?P = null,
    thumb_lv: grid.Level = undefined,
    thumbs: [atlas.MAX_NODES]?rl.Texture2D = @splat(null),
    thumb_ok: std.StaticBitSet(atlas.MAX_NODES) = .initEmpty(),
    /// The link tool's first door.
    pick: ?atlas.Link = null,
    dirty: bool = false,
    stroke: Stroke = .none,
    /// The cell the stroke last reached, so a fast mouse paints every cell between.
    stroke_at: ?P = null,
    rect: ?Rect = null,
    drag: ?Drag = null,
    modal: Modal = .none,
    /// A modal opened or closed this frame: no click lands until the next.
    fresh: bool = false,
    pending: Pending = .leave,
    pending_path: Path = .{},
    naming: Naming = .new,
    renaming: bool = false,
    /// A click ended the rename this frame: its field's row takes it, not the buttons that row gives way to.
    renamed: bool = false,
    field: Field = .{},
    listing: atlas.Listing = .{},
    /// Listed worlds scrolled off the top of the open modal.
    listed_top: usize = 0,
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
        ed.* = .{ .alloc = alloc, .world = w, .scratch = s, .hist = h };
        freshWorld(w);
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
        alloc.destroy(ed.world);
        alloc.destroy(ed);
    }

    fn path(ed: *const Editor) []const u8 {
        return ed.file.text();
    }

    /// Loads `p`, or starts a world there when it is not yet; a file that does not parse is left alone.
    pub fn open(ed: *Editor, p: []const u8) !void {
        if (p.len > PATH_MAX) return error.NameTooLong;
        ed.scratch.load(ed.alloc, p) catch |e| {
            if (e != error.FileNotFound) {
                ed.scratch.* = ed.world.*;
                return e;
            }
            freshWorld(ed.scratch);
        };
        ed.world.* = ed.scratch.*;
        ed.setPath(p);
        ed.settle();
        ed.say("{s} {s}", .{ if (std.fs.cwd().access(p, .{})) "Opened" else |_| "New world; it saves to", p });
    }

    fn settle(ed: *Editor) void {
        ed.hist_len = 0;
        ed.hist_at = 0;
        ed.saved_at = 0;
        ed.banked = true;
        ed.node = 0;
        ed.scroll = 0;
        ed.pick = null;
        ed.drop();
        ed.dirty = false;
        ed.renaming = false;
        ed.modal = .none;
        ed.view = .map;
        ed.recentre = true;
        ed.restamp();
    }

    fn setPath(ed: *Editor, p: []const u8) void {
        ed.file.set(p, PATH_MAX);
    }

    fn plan(ed: *Editor) *atlas.Plan {
        return &ed.here().plan;
    }

    fn px(ed: *const Editor) f32 {
        return ZOOMS[ed.zoom];
    }

    /// Where and how big a glyph in the cell `r` is drawn.
    fn inkOf(ed: *const Editor, r: rl.Rectangle) struct { x: i32, y: i32, size: i32 } {
        const half = ed.px() * 0.5;
        return .{ .x = @intFromFloat(r.x + half), .y = @intFromFloat(r.y + half), .size = @intFromFloat(ed.px() * GLYPH_OF_CELL) };
    }

    fn brushSize(ed: *const Editor) i32 {
        return BRUSHES[ed.brush];
    }

    fn say(ed: *Editor, comptime fmt: []const u8, args: anytype) void {
        ed.said.say(fmt, args);
        ed.said_t = SAY_S;
    }

    /// A press begins a gesture; everything it changes is one undo.
    fn gesture(ed: *Editor) void {
        ed.scratch.* = ed.world.*;
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

    /// The `k`th step from the oldest kept.
    fn kept(ed: *Editor, k: usize) *atlas.Atlas {
        return &ed.hist[(ed.hist_base + k) % UNDO_CAP];
    }

    fn changed(ed: *Editor) void {
        ed.bank();
        ed.stale = true;
        ed.thumb_ok.unset(ed.node);
    }

    /// Every node may have changed, or moved to another index.
    fn restamp(ed: *Editor) void {
        ed.stale = true;
        ed.thumb_ok = .initEmpty();
    }

    /// The world and the step swap places, so the same step redoes it.
    fn swapStep(ed: *Editor, k: usize) void {
        ed.scratch.* = ed.world.*;
        ed.world.* = ed.kept(k).*;
        ed.kept(k).* = ed.scratch.*;
        ed.banked = true;
        ed.drop();
        ed.pick = null;
        ed.clampSelection();
        ed.restamp();
    }

    fn undo(ed: *Editor) void {
        if (ed.hist_at == 0) return ed.say("Nothing to undo", .{});
        ed.hist_at -= 1;
        ed.swapStep(ed.hist_at);
        ed.dirty = ed.saved_at != ed.hist_at;
        ed.say("Undone ({d} more)", .{ed.hist_at});
    }

    fn redo(ed: *Editor) void {
        if (ed.hist_at == ed.hist_len) return ed.say("Nothing to redo", .{});
        ed.swapStep(ed.hist_at);
        ed.hist_at += 1;
        ed.dirty = ed.saved_at != ed.hist_at;
        ed.say("Redone ({d} more)", .{ed.hist_len - ed.hist_at});
    }

    fn drop(ed: *Editor) void {
        ed.stroke = .none;
        ed.stroke_at = null;
        ed.rect = null;
        ed.drag = null;
    }

    fn setTool(ed: *Editor, t: Tool) void {
        if (t != ed.tool) {
            ed.drop();
            ed.pick = null;
        }
        ed.tool = t;
    }

    fn setView(ed: *Editor, v: View) void {
        if (v != ed.view) ed.drop();
        ed.view = v;
    }

    fn clampSelection(ed: *Editor) void {
        ed.node = @min(ed.node, ed.world.node_n - 1);
        ed.scroll = @min(ed.scroll, ed.world.node_n - 1);
    }

    fn select(ed: *Editor, n: usize) void {
        if (ed.renaming) ed.commitRename();
        ed.drop();
        ed.node = n;
        ed.stale = true;
        ed.recentre = true;
    }

    fn preview(ed: *Editor) void {
        if (!ed.stale) return;
        ed.here().sketch(&ed.lv);
        ed.start_at = ed.startOn();
        ed.stale = false;
    }

    /// Where the hero starts on the open node, when it starts there.
    fn startOn(ed: *Editor) ?P {
        const s = ed.world.start;
        if (s.node != ed.node) return null;
        return if (ed.here().unrolled()) s.at else atlas.landing(&ed.lv, s.at, ed.here().placed());
    }

    fn standable(ed: *Editor, from: atlas.Start) bool {
        return ed.world.standable(from, &ed.thumb_lv);
    }

    fn doorAt(ed: *Editor, p: P) ?usize {
        return ed.here().doorAt(p);
    }

    /// Its number and name, marked when the world starts there.
    fn nodeTitle(ed: *Editor, n: usize, buf: []u8) [:0]const u8 {
        var name: [atlas.TITLE_MAX]u8 = undefined;
        const mark: []const u8 = if (ed.world.start.node == n) &START_MARK else "";
        if (ed.renamingNode(n)) return std.fmt.bufPrintZ(buf, "{s}{d}  {s}" ++ menu.CARET, .{ mark, n, ed.field.text() }) catch "";
        return std.fmt.bufPrintZ(buf, "{s}{d}  {s}", .{ mark, n, ed.nodeName(n, &name) }) catch "";
    }

    fn renamingNode(ed: *const Editor, n: usize) bool {
        return ed.renaming and n == ed.node;
    }

    fn playStart(ed: *Editor) void {
        ed.action = .{ .play = ed.world.start };
    }

    fn nodeName(ed: *Editor, n: usize, buf: *[atlas.TITLE_MAX]u8) []const u8 {
        return ed.world.node[n].title(n, buf);
    }

    fn here(ed: *Editor) *atlas.Node {
        return &ed.world.node[ed.node];
    }

    fn rolled(ed: *Editor) ?*atlas.Procgen {
        return switch (ed.plan().*) {
            .procgen => |*pg| pg,
            .bespoke => null,
        };
    }

    fn goTo(ed: *Editor, n: usize) void {
        ed.select(n);
        ed.setView(.map);
    }

    pub fn request(ed: *Editor, p: Pending) void {
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
            .open => ed.open(p) catch |e| ed.say("{s} did not load ({s})", .{ p, @errorName(e) }),
            .new => {
                freshWorld(ed.world);
                ed.setPath(p);
                ed.settle();
                ed.say("New world; {s} saves it to {s}", .{ Desk.SAVE_CAPTION, p });
            },
        }
    }

    fn save(ed: *Editor) bool {
        ed.world.save(ed.alloc, ed.path()) catch |e| {
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
        ed.field.set("", FIELD_MAX);
        ed.ask(.name);
    }

    fn askOpen(ed: *Editor) void {
        ed.listing.scan();
        ed.listed_top = 0;
        ed.ask(.open);
    }

    fn named(ed: *Editor) void {
        var buf: [atlas.PATH_MAX]u8 = undefined;
        const p = atlas.pathFor(&buf, ed.field.text()) orelse return ed.say("Type a name of letters or digits", .{});
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
                ed.pending_path.set(p, PATH_MAX);
                ed.request(.new);
            },
        }
    }

    fn startRename(ed: *Editor) void {
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
        return .{
            .x = @floatFromInt(PANEL_W),
            .y = 0,
            .width = @floatFromInt(@max(0, g.screen.x - PANEL_W)),
            .height = @floatFromInt(@max(0, g.screen.y - STATUS_H)),
        };
    }

    fn cellAt(ed: *const Editor, c: rl.Rectangle, m: P) P {
        return mathx.cellOf(.{
            ed.cam[0] + (@as(f32, @floatFromInt(m.x)) - c.x) / ed.px(),
            ed.cam[1] + (@as(f32, @floatFromInt(m.y)) - c.y) / ed.px(),
        });
    }

    fn cellRect(ed: *const Editor, c: rl.Rectangle, p: P) rl.Rectangle {
        return .{
            .x = c.x + (@as(f32, @floatFromInt(p.x)) - ed.cam[0]) * ed.px(),
            .y = c.y + (@as(f32, @floatFromInt(p.y)) - ed.cam[1]) * ed.px(),
            .width = ed.px(),
            .height = ed.px(),
        };
    }

    fn lookAt(ed: *Editor, c: rl.Rectangle, p: P) void {
        ed.cam = .{
            @as(f32, @floatFromInt(p.x)) + 0.5 - c.width / ed.px() * 0.5,
            @as(f32, @floatFromInt(p.y)) + 0.5 - c.height / ed.px() * 0.5,
        };
    }

    fn boxAt(ed: *const Editor, c: rl.Rectangle, n: usize) rl.Rectangle {
        const pos = ed.world.node[n].pos;
        return .{
            .x = c.x + @as(f32, @floatFromInt(pos.x)) - ed.gcam[0],
            .y = c.y + @as(f32, @floatFromInt(pos.y)) - ed.gcam[1],
            .width = @floatFromInt(BOX_W),
            .height = @floatFromInt(BOX_H),
        };
    }

    fn boxUnder(ed: *const Editor, c: rl.Rectangle, m: P) ?usize {
        var n = ed.world.node_n;
        while (n > 0) {
            n -= 1;
            if (rl.checkCollisionPointRec(vec(m), ed.boxAt(c, n))) return n;
        }
        return null;
    }

    fn dotAt(ed: *const Editor, c: rl.Rectangle, l: atlas.Link) rl.Vector2 {
        const b = ed.boxAt(c, l.node);
        const d = ed.world.node[l.node].door[l.door].at;
        return .{
            .x = b.x + @as(f32, @floatFromInt(d.x * THUMB + @divTrunc(THUMB, 2))),
            .y = b.y + @as(f32, @floatFromInt(BOX_TOP + d.y * THUMB + @divTrunc(THUMB, 2))),
        };
    }
};

/// One procgen node.
fn freshWorld(w: *atlas.Atlas) void {
    w.* = .{};
    _ = w.add(.{ .procgen = .{} });
}

fn vec(p: P) rl.Vector2 {
    return .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
}

/// One frame: reads `desk` and `g.screen`, which the caller updated, and draws. `closing` is the window's close button.
pub fn frame(ed: *Editor, g: *game.Game, closing: bool) Action {
    ed.action = .none;
    if (closing) ed.request(.quit);
    const c = Editor.canvas(g);
    if (ed.recentre) {
        ed.preview();
        ed.lookAt(c, grid.MIDDLE);
        ed.recentre = false;
    }
    step(ed, g, rl.getFrameTime());
    rl.beginDrawing();
    draw(ed, g);
    rl.endDrawing();
    ed.fresh = false;
    ed.renamed = false;
    if (ed.action == .play) ed.drop();
    if (ed.action == .play and !ed.standable(ed.action.play)) {
        var buf: [atlas.TITLE_MAX]u8 = undefined;
        ed.say(atlas.NO_FLOOR, .{ed.nodeName(ed.action.play.node, &buf)});
        ed.action = .none;
    }
    return ed.action;
}

fn step(ed: *Editor, g: *game.Game, dt: f32) void {
    const d = &ed.desk;
    ed.said_t -= dt;
    if (ed.modal != .none) {
        modalKeys(ed);
        if (ed.modal == .none) ed.fresh = true;
        return;
    }
    if (ed.renaming) {
        ed.field.feed(d);
        if (d.back) {
            ed.renaming = false;
        } else if (d.enter or d.clicked()) {
            ed.commitRename();
            ed.renamed = d.clicked();
        }
        if (ed.renaming or !d.clicked()) return;
    } else if (d.back) {
        if (d.clicked()) ed.gesture();
        return escape(ed);
    }
    const c = Editor.canvas(g);
    if (d.play) ed.playStart();
    const over = rl.checkCollisionPointRec(vec(d.mouse), c);
    if (d.play_here) playHere(ed, c, over);
    if (d.save) _ = ed.save();
    if (d.save_as) ed.askName(.save_as);
    if (d.open) ed.askOpen();
    if (d.new) ed.askName(.new);
    if (d.undo) ed.undo();
    if (d.redo) ed.redo();
    if (d.graph) ed.setView(ed.view.other());
    if (d.rename) ed.startRename();
    if (d.go) goThrough(ed, c, over);
    if (d.smaller) ed.brush -|= 1;
    if (d.bigger) ed.brush = @min(ed.brush + 1, BRUSHES.len - 1);
    if (d.tool) |i| ed.setTool(TOOLS[i]);
    if (ed.modal != .none) return;
    if (d.clicked()) ed.gesture();
    const pan = [2]f32{ @floatFromInt(d.pan.x), @floatFromInt(d.pan.y) };
    const moved = [2]f32{ @floatFromInt(d.moved.x), @floatFromInt(d.moved.y) };
    switch (ed.view) {
        .map => {
            for (0..2) |k| {
                ed.cam[k] += pan[k] * PAN_PX_S * dt / ed.px();
                if (d.grab) ed.cam[k] -= moved[k] / ed.px();
            }
            if (d.wheel != 0 and over) zoom(ed, c, if (d.wheel > 0) 1 else -1);
            mapMouse(ed, c, over);
        },
        .graph => {
            for (0..2) |k| {
                ed.gcam[k] += pan[k] * PAN_PX_S * dt;
                if (d.grab) ed.gcam[k] -= moved[k];
            }
            graphMouse(ed, c, over);
        },
    }
    if (d.wheel != 0 and d.mouse.x < PANEL_W) {
        const up = d.wheel > 0;
        if (ed.lower == .generator and ed.rolled() != null) {
            ed.gen_top = std.math.clamp(ed.gen_top + if (up) -ROW_H else ROW_H, 0, ed.gen_most);
        } else scrollNodes(ed, if (up) -1 else 1);
    }
}

fn escape(ed: *Editor) void {
    if (ed.rect != null) {
        ed.drop();
    } else if (ed.pick != null) {
        ed.pick = null;
        ed.say(LINK_CANCELLED, .{});
    } else if (ed.view == .graph) {
        ed.setView(.map);
    } else ed.request(.leave);
}

fn modalKeys(ed: *Editor) void {
    const d = &ed.desk;
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
        .open => if (d.wheel != 0) {
            ed.listed_top = if (d.wheel > 0) ed.listed_top -| 1 else @min(ed.listed_top + 1, ed.listing.n -| MODAL_ROWS);
        },
        .none => {},
    }
}

fn playHere(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const p = ed.cellAt(c, ed.desk.mouse);
    if (ed.view != .map or !grid.Level.inside(p) or !over) {
        return ed.say("{s} plays from the cell under the cursor on a map", .{Desk.PLAY_HERE_CAPTION});
    }
    ed.action = .{ .play = .{ .node = ed.node, .at = p } };
}

fn goThrough(ed: *Editor, c: rl.Rectangle, over: bool) void {
    if (ed.view != .map) return;
    const door = if (over) ed.doorAt(ed.cellAt(c, ed.desk.mouse)) else null;
    const k = door orelse return ed.say("{s} goes through the door under the cursor", .{Desk.GO_CAPTION});
    const to = ed.here().door[k].to orelse return ed.say("Door {d} leads nowhere yet", .{k});
    ed.select(to.node);
    ed.recentre = false;
    ed.lookAt(c, ed.world.node[to.node].door[to.door].at);
    var buf: [atlas.TITLE_MAX]u8 = undefined;
    ed.say("Through door {d} to {s}, door {d}", .{ k, ed.nodeName(to.node, &buf), to.door });
}

fn mapMouse(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const d = &ed.desk;
    const p = ed.cellAt(c, d.mouse);
    const held = switch (ed.stroke) {
        .none => d.paint or d.erase,
        .paint => d.paint,
        .erase => d.erase,
    };
    if (!held) {
        if (ed.rect) |r| fillRect(ed, r, clampCell(p));
        ed.drop();
    }
    if (over and d.clicked()) {
        ed.drop();
        ed.stroke = if (d.paint_hit) .paint else .erase;
        if (d.shift and ed.tool.broad() and ed.tool.fits(ed.here()) and grid.Level.inside(p)) ed.rect = .{ .from = p, .erase = ed.stroke == .erase };
    }
    if (!over) ed.stroke_at = null;
    if (ed.rect != null or !over or ed.stroke == .none) return;
    const hit = if (ed.stroke == .paint) d.paint_hit else d.erase_hit;
    if (!hit and !ed.tool.strokes()) return;
    if (!ed.tool.fits(ed.here())) {
        if (hit and grid.Level.inside(p)) ed.say("A procgen node is generated; it takes only " ++ UNGENERATED, .{});
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
    const erase = ed.stroke == .erase;
    if (!ed.tool.broad()) return apply(ed, p, erase);
    const box = brushBox(p, ed.brushSize());
    fillRect(ed, .{ .from = box.lo, .erase = erase }, box.hi);
}

/// The `n` by `n` cells a brush with its middle on `p` covers.
fn brushBox(p: P, n: i32) struct { lo: P, hi: P } {
    const lo = p.sub(.{ .x = @divTrunc(n - 1, 2), .y = @divTrunc(n - 1, 2) });
    return .{ .lo = lo, .hi = lo.add(.{ .x = n - 1, .y = n - 1 }) };
}

fn clampCell(p: P) P {
    return .{ .x = std.math.clamp(p.x, 0, grid.W - 1), .y = std.math.clamp(p.y, 0, grid.H - 1) };
}

fn fillRect(ed: *Editor, r: Rect, to: P) void {
    const lo = P{ .x = @min(r.from.x, to.x), .y = @min(r.from.y, to.y) };
    const hi = P{ .x = @max(r.from.x, to.x) + 1, .y = @max(r.from.y, to.y) + 1 };
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        if (grid.Level.inside(p)) apply(ed, p, r.erase);
    }
}

fn apply(ed: *Editor, p: P, erase: bool) void {
    if (erase) remove(ed, p) else place(ed, p);
}

fn graphMouse(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const d = &ed.desk;
    if (over and d.paint_hit) {
        if (ed.boxUnder(c, d.mouse)) |n| {
            const b = ed.boxAt(c, n);
            ed.drag = .{ .node = n, .from = d.mouse, .grab = d.mouse.sub(.{ .x = @intFromFloat(b.x), .y = @intFromFloat(b.y) }) };
        }
    }
    const dr = if (ed.drag) |*x| x else return;
    if (d.paint) {
        if (!dr.moved and mathx.dist(d.mouse, dr.from) > DRAG_PX) dr.moved = true;
        if (!dr.moved) return;
        const lim: i32 = @intCast(atlas.POS_MAX);
        const at = P{
            .x = std.math.clamp(d.mouse.x - dr.grab.x - @as(i32, @intFromFloat(c.x)) + @as(i32, @intFromFloat(ed.gcam[0])), -lim, lim),
            .y = std.math.clamp(d.mouse.y - dr.grab.y - @as(i32, @intFromFloat(c.y)) + @as(i32, @intFromFloat(ed.gcam[1])), -lim, lim),
        };
        const nd = &ed.world.node[dr.node];
        if (nd.pos.eq(at)) return;
        nd.pos = at;
        ed.bank();
        return;
    }
    if (!dr.moved) ed.goTo(dr.node);
    ed.drag = null;
}

fn zoom(ed: *Editor, c: rl.Rectangle, by: i32) void {
    const next = std.math.clamp(@as(i32, @intCast(ed.zoom)) + by, 0, @as(i32, ZOOMS.len - 1));
    const m = [2]f32{ @as(f32, @floatFromInt(ed.desk.mouse.x)) - c.x, @as(f32, @floatFromInt(ed.desk.mouse.y)) - c.y };
    const was = ed.px();
    ed.zoom = @intCast(next);
    for (0..2) |k| ed.cam[k] += m[k] / was - m[k] / ed.px();
}

fn scrollNodes(ed: *Editor, by: i32) void {
    const most: i32 = @intCast(ed.world.node_n -| 1);
    ed.scroll = @intCast(std.math.clamp(@as(i32, @intCast(ed.scroll)) + by, 0, most));
}

fn paintTile(ed: *Editor, p: P, t: grid.Tile) void {
    const b = &ed.plan().bespoke;
    const i = grid.Level.idx(p);
    if (b.tile[i] == t or ed.doorAt(p) != null) return;
    b.tile[i] = t;
    if (t.solid()) {
        b.barrel[i] = false;
        if (b.foeAt(p)) |f| b.dropFoe(f);
        if (b.torchAt(p.add(mathx.Dir.n.delta()))) |k| b.dropTorch(k);
    } else if (b.torchAt(p)) |k| b.dropTorch(k);
    ed.changed();
}

fn place(ed: *Editor, p: P) void {
    const i = grid.Level.idx(p);
    switch (ed.tool) {
        .floor => paintTile(ed, p, .floor),
        .wall => paintTile(ed, p, .wall),
        .barrel => {
            const b = &ed.plan().bespoke;
            if (b.barrel[i] or !ed.here().barrelFits(b, p) or b.foeAt(p) != null) return;
            b.barrel[i] = true;
            ed.changed();
        },
        .torch => {
            const b = &ed.plan().bespoke;
            if (!ed.here().torchFits(b, p)) return ed.say("A torch " ++ TORCH_RULE, .{});
            if (!b.addTorch(p)) return ed.say("That wall holds a torch, or the node holds {d}", .{grid.MAX_TORCHES});
            ed.changed();
        },
        .rat, .slime, .bloat => {
            const b = &ed.plan().bespoke;
            const k = ed.tool.foe().?;
            if (!ed.here().foeFits(b, p)) return ed.say("A foe " ++ FOE_RULE, .{});
            if (b.foeAt(p)) |f| {
                if (b.foe[f].kind == k) return;
                b.foe[f].kind = k;
            } else if (!b.addFoe(.{ .kind = k, .at = p })) return ed.say("The node holds {d} foes", .{atlas.MAX_FOES});
            ed.changed();
        },
        .door => {
            const k = ed.world.addDoor(ed.node, p) orelse return ed.say("That cell is a door or a map corner, or the node holds {d}", .{grid.MAX_DOORS});
            switch (ed.plan().*) {
                .bespoke => |*b| {
                    b.tile[i] = .floor;
                    b.barrel[i] = false;
                    if (b.foeAt(p)) |f| b.dropFoe(f);
                    if (b.torchAt(p)) |t| b.dropTorch(t);
                },
                .procgen => {},
            }
            ed.say("Door {d}; the {s} tool joins it to another", .{ k, Tool.link.name() });
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
            if (std.meta.eql(from, here)) return ed.say(LINK_CANCELLED, .{});
            if (ed.world.node[from.node].door[from.door].to) |t| {
                if (std.meta.eql(t, here)) return ed.say("Those doors lead to each other already", .{});
            }
            ed.world.link(from, here);
            ed.say("Node {d} door {d} and node {d} door {d} lead to each other", .{ from.node, from.door, here.node, here.door });
            ed.changed();
            ed.thumb_ok.unset(from.node);
        },
        .start => {
            if (ed.world.start.node == ed.node and ed.world.start.at.eq(p)) return;
            ed.world.start = .{ .node = ed.node, .at = p };
            ed.changed();
        },
    }
}

fn remove(ed: *Editor, p: P) void {
    const i = grid.Level.idx(p);
    switch (ed.tool) {
        .floor => if (ed.plan().bespoke.tile[i] == .floor) paintTile(ed, p, .wall),
        .wall => if (ed.plan().bespoke.tile[i] == .wall) paintTile(ed, p, .floor),
        .barrel => {
            const b = &ed.plan().bespoke;
            if (!b.barrel[i]) return;
            b.barrel[i] = false;
            ed.changed();
        },
        .torch => {
            const b = &ed.plan().bespoke;
            b.dropTorch(b.torchAt(p) orelse return);
            ed.changed();
        },
        .rat, .slime, .bloat => {
            const b = &ed.plan().bespoke;
            b.dropFoe(b.foeAt(p) orelse return);
            ed.changed();
        },
        .door => {
            const k = ed.doorAt(p) orelse return;
            ed.world.removeDoor(.{ .node = ed.node, .door = k });
            ed.pick = null;
            ed.changed();
            ed.restamp();
        },
        .link => {
            const k = ed.doorAt(p) orelse return;
            if (ed.here().door[k].to == null) return;
            ed.world.unlink(.{ .node = ed.node, .door = k });
            ed.changed();
            ed.restamp();
        },
        .start => {},
    }
}

fn deleteNode(ed: *Editor) void {
    ed.world.remove(ed.node);
    ed.pick = null;
    ed.drop();
    ed.renaming = false;
    ed.clampSelection();
    ed.bank();
    ed.restamp();
}

fn addNode(ed: *Editor, plan: atlas.Plan) void {
    const n = ed.world.add(plan) orelse return ed.say("The world holds {d} nodes", .{atlas.MAX_NODES});
    ed.select(n);
    ed.changed();
    ed.typeName();
}

/// Hot and clicked this frame. Under a modal only the modal's own are live, and not the frame it opened.
fn hot(ed: *Editor, r: rl.Rectangle, live: bool, modal: bool, tip: ?[:0]const u8) struct { hot: bool, hit: bool } {
    const on_layer = !ed.fresh and (modal or ed.modal == .none);
    const in_clip = if (ed.clip) |c| rl.checkCollisionPointRec(vec(ed.desk.mouse), c) else true;
    const h = live and on_layer and in_clip and rl.checkCollisionPointRec(vec(ed.desk.mouse), r);
    if (h and tip != null) ed.tip = tip;
    return .{ .hot = h, .hit = h and ed.desk.paint_hit };
}

/// Drawn and read in one call, so what is shown is what a click hits.
fn button(ed: *Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return buttonOn(ed, g, r, label, on, live, false, tip);
}

fn buttonOn(ed: *Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, modal: bool, tip: ?[:0]const u8) bool {
    const h = hot(ed, r, live, modal, tip);
    plate(r, on, h.hot);
    const y: i32 = @intFromFloat(r.y);
    g.face.draw(label, @as(i32, @intFromFloat(r.x)) + GAP, y + @divTrunc(@as(i32, @intFromFloat(r.height)) - TEXT, 2), TEXT, if (live) look.TEXT else look.DIM);
    return h.hit;
}

fn plate(r: rl.Rectangle, on: bool, hot_: bool) void {
    if (on or hot_) rl.drawRectangleRec(r, ROW_ON);
    if (on) rl.drawRectangleLinesEx(r, 1, ON);
}

fn row(x: i32, y: i32, w: i32) rl.Rectangle {
    return .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(ROW_H) };
}

/// The `k`th of `n` equal slots across `span` pixels from `x0`.
fn slotOf(x0: i32, span: i32, y: i32, k: usize, n: usize) rl.Rectangle {
    const ni: i32 = @intCast(n);
    const w = @divTrunc(span - GAP * (ni - 1), ni);
    return row(x0 + @as(i32, @intCast(k)) * (w + GAP), y, w);
}

/// `n` buttons across the panel, the `k`th.
fn cellOfRow(y: i32, k: usize, n: usize) rl.Rectangle {
    return slotOf(PAD, INNER_W, y, k, n);
}

fn scissor(r: rl.Rectangle) void {
    rl.beginScissorMode(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height));
}

/// `n` buttons across the panel, taken left to right.
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

fn draw(ed: *Editor, g: *game.Game) void {
    rl.clearBackground(look.BG);
    ed.tip = null;
    const c = Editor.canvas(g);
    switch (ed.view) {
        .map => drawMap(ed, g, c),
        .graph => drawGraph(ed, g, c),
    }
    drawPanel(ed, g);
    if (ed.modal != .none) drawModal(ed, g);
    drawStatus(ed, g, c);
}

/// File, then view, then tools, then node commands, then the node list or the open node's generator, which scroll.
fn drawPanel(ed: *Editor, g: *game.Game) void {
    var buf: [LINE]u8 = undefined;
    rl.drawRectangle(0, 0, PANEL_W, g.screen.y, PANEL_BG);
    rl.drawRectangle(PANEL_W - 1, 0, 1, g.screen.y, look.EDGE);
    var y = PAD;
    g.face.draw(std.fmt.bufPrintZ(&buf, "{s}{s}", .{ ed.path(), if (ed.dirty) " *" else "" }) catch "", PAD, y, TEXT, look.TEXT);
    y += HEAD + GAP;
    var file = Across{ .y = y, .n = 4 };
    if (button(ed, g, file.next(), "New", false, true, "New world (" ++ Desk.NEW_CAPTION ++ ")")) ed.askName(.new);
    if (button(ed, g, file.next(), "Open", false, true, "Open a world (" ++ Desk.OPEN_CAPTION ++ ")")) ed.askOpen();
    if (button(ed, g, file.next(), "Save", false, true, "Save (" ++ Desk.SAVE_CAPTION ++ ")")) _ = ed.save();
    if (button(ed, g, file.next(), "Save as", false, true, "Save under a new name (" ++ Desk.SAVE_AS_CAPTION ++ ")")) ed.askName(.save_as);
    file.done();
    y += ROW_H + GAP;
    var views = Across{ .y = y, .n = 4 };
    const other: [:0]const u8 = if (ed.view == .map) "Graph" else "Map";
    if (button(ed, g, views.next(), other, false, true, "The map of one node, or every node and how they link (" ++ Desk.GRAPH_CAPTION ++ ")")) {
        ed.setView(ed.view.other());
    }
    if (button(ed, g, views.next(), "Undo", false, ed.hist_at > 0, "Undo (" ++ Desk.UNDO_CAPTION ++ ")")) ed.undo();
    if (button(ed, g, views.next(), "Play", false, true, "Play from the world start (" ++ Desk.PLAY_CAPTION ++ "); " ++ Desk.PLAY_CAPTION ++ " or " ++ Desk.PLAY_HERE_CAPTION ++ " comes back")) {
        ed.playStart();
    }
    if (button(ed, g, views.next(), "Title", false, true, "Back to the title (" ++ Desk.BACK_CAPTION ++ ")")) ed.request(.leave);
    views.done();
    y += ROW_H + GAP * 3;
    const rows = (TOOLS.len + TOOL_COLS - 1) / TOOL_COLS;
    for (TOOLS, Desk.TOOL_CAPTIONS, 0..) |t, key, i| {
        const n = ed.brushSize();
        const label = if (t.broad())
            std.fmt.bufPrintZ(&buf, "{s}  {s}  {d}x{d}", .{ key, t.name(), n, n }) catch ""
        else
            std.fmt.bufPrintZ(&buf, "{s}  {s}", .{ key, t.name() }) catch "";
        const r = cellOfRow(y + @as(i32, @intCast(i % rows)) * ROW_H, i / rows, TOOL_COLS);
        if (button(ed, g, r, label, t == ed.tool, t.fits(ed.here()), t.tip())) ed.setTool(t);
    }
    y += @as(i32, @intCast(rows)) * ROW_H + GAP * 3;
    var adds = Across{ .y = y, .n = 2 };
    if (button(ed, g, adds.next(), "+ Bespoke", false, true, "A node you paint yourself")) addNode(ed, .{ .bespoke = .{} });
    if (button(ed, g, adds.next(), "+ Procgen", false, true, "A node the rooms generator rolls round its doors, anew each run")) {
        addNode(ed, .{ .procgen = .{} });
    }
    adds.done();
    y += ROW_H + GAP;
    if (ed.renaming or ed.renamed) {
        fieldRow(ed, g, cellOfRow(y, 0, 1));
    } else {
        var node = Across{ .y = y, .n = 2 };
        if (button(ed, g, node.next(), "Rename", false, true, "Name this node (" ++ Desk.RENAME_CAPTION ++ ")")) ed.startRename();
        if (button(ed, g, node.next(), "Delete", false, ed.world.node_n > 1, "Delete this node; its doors' links go with it")) deleteNode(ed);
        node.done();
    }
    y += ROW_H + GAP * 3;
    const rolled = ed.rolled();
    var tabs = Across{ .y = y, .n = 2 };
    if (button(ed, g, tabs.next(), "Nodes", ed.lower == .nodes or rolled == null, true, "Every node of the world")) ed.lower = .nodes;
    if (button(ed, g, tabs.next(), "Generator", ed.lower == .generator and rolled != null, rolled != null, "What this procgen node's floor and foes are rolled from")) {
        ed.lower = .generator;
    }
    tabs.done();
    y += ROW_H + GAP * 2;
    if (ed.lower == .generator) {
        if (rolled) |pg| return drawGenerator(ed, g, y, pg);
    }
    rl.beginScissorMode(0, y, PANEL_W, @max(0, g.screen.y - y));
    defer rl.endScissorMode();
    var detail_buf: [LINE]u8 = undefined;
    for (ed.world.nodes()[ed.scroll..], ed.scroll..) |*nd, n| {
        if (y >= g.screen.y) break;
        const r = rl.Rectangle{ .x = @floatFromInt(PAD), .y = @floatFromInt(y), .width = @floatFromInt(INNER_W), .height = @floatFromInt(NODE_H - NODE_GAP) };
        const on = n == ed.node;
        const h = hot(ed, r, true, false, "Open this node");
        plate(r, on, h.hot);
        g.face.draw(ed.nodeTitle(n, &buf), PAD + GAP, y + TITLE_DY, TEXT, titleColor(ed, n));
        g.face.draw(nodeDetail(nd, &detail_buf), PAD + GAP, y + TITLE_DY + DETAIL_DY, SMALL, if (nd.unlinked() > 0) WARN else look.DIM);
        if (h.hit) ed.goTo(n);
        y += NODE_H;
    }
}

/// A procgen node's floor, then its foes, a row a setting, scrolled by the wheel; every click is one undo.
fn drawGenerator(ed: *Editor, g: *game.Game, top: i32, pg: *atlas.Procgen) void {
    const was = pg.*;
    const fo = &pg.foes;
    const shown = @max(0, g.screen.y - top);
    ed.clip = .{ .x = 0, .y = @floatFromInt(top), .width = @floatFromInt(PANEL_W), .height = @floatFromInt(shown) };
    scissor(ed.clip.?);
    defer {
        rl.endScissorMode();
        ed.clip = null;
    }
    ed.gen_top = std.math.clamp(ed.gen_top, 0, ed.gen_most);
    var y = top - ed.gen_top;
    section(g, &y, "Base");
    choiceRow(ed, g, &y, atlas.Floor, &pg.floor, ALGO_CHOICE);
    switch (pg.floor) {
        inline else => |*fl, t| knobRows(ed, g, &y, fl, comptime rowsOf(t)),
    }
    y += GAP * 2;
    section(g, &y, "Features");
    var drop_feature: ?usize = null;
    for (pg.feature[0..pg.feature_n], 0..) |*ft, i| {
        if (button(ed, g, row(PAD + LABEL_W - STEP_W - GAP, y, STEP_W), "x", false, true, "Take this feature away")) drop_feature = i;
        choiceRow(ed, g, &y, atlas.Feature, ft, FEATURE_CHOICE);
        switch (ft.*) {
            inline else => |*fp, k| knobRows(ed, g, &y, fp, comptime featureRowsOf(k)),
        }
        y += GAP * 2;
    }
    if (drop_feature) |i| pg.dropFeature(i);
    if (button(ed, g, cellOfRow(y, 0, 1), "+ Feature", false, pg.feature_n < atlas.MAX_FEATURES, ADD_FEATURE_TIP)) _ = pg.addFeature(atlas.FIRST_FEATURE);
    y += ROW_H + GAP * 3;
    knobs(ed, g, &y, "Foes", fo, &FOE_ROWS);
    y += GAP * 2;
    section(g, &y, "Makeups");
    var drop: ?usize = null;
    for (fo.makeup[0..fo.makeup_n], 0..) |*m, i| {
        if (drawMakeup(ed, g, y, m, fo.canDrop())) drop = i;
        y += ROW_H + GAP;
    }
    if (drop) |i| _ = fo.dropMakeup(i);
    if (button(ed, g, cellOfRow(y, 0, 1), "+ Makeup", false, fo.canAdd(), ADD_MAKEUP_TIP)) _ = fo.addMakeup();
    ed.gen_most = @max(0, y + ROW_H + PAD + ed.gen_top - top - shown);
    pg.floor = pg.floor.fit();
    for (pg.feature[0..pg.feature_n]) |*ft| ft.* = ft.fit();
    fo.* = fo.fit();
    if (!std.meta.eql(was, pg.*)) ed.changed();
}

fn section(g: *game.Game, y: *i32, title: [:0]const u8) void {
    g.face.draw(title, PAD, y.*, TEXT, look.DIM);
    y.* += HEAD;
}

/// A titled run of knob rows, one a field of `owner`.
fn knobs(ed: *Editor, g: *game.Game, y: *i32, title: [:0]const u8, owner: anytype, comptime rows: []const Knob) void {
    section(g, y, title);
    knobRows(ed, g, y, owner, rows);
}

fn knobRows(ed: *Editor, g: *game.Game, y: *i32, owner: anytype, comptime rows: []const Knob) void {
    inline for (rows) |k| {
        knobRow(ed, g, y.*, owner, k);
        y.* += ROW_H + GAP;
    }
}

/// Which arm of the union `v` is, stepped round them; a new arm starts afresh.
fn choiceRow(ed: *Editor, g: *game.Game, y: *i32, comptime U: type, v: *U, comptime c: Choice) void {
    rowLabel(g, y.*, c.label);
    var tag = std.meta.activeTag(v.*);
    stepChoice(ed, g, y.*, std.meta.Tag(U), &tag, c.tip);
    if (tag != std.meta.activeTag(v.*)) v.* = U.of(tag);
    y.* += ROW_H + GAP;
}

/// Its weight, its members from the lead, then its tools: true when it is to be deleted.
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
        const k = m.kind[i];
        g.face.glyph(look.body(k).ch, @intFromFloat(r.x + r.width / 2), @intFromFloat(r.y + r.height / 2), TEXT, look.body(k).fg);
        if (h.hit) m.turn(i);
    }
    var dropped = false;
    for (MAKEUP_TOOLS, 0..) |t, i| {
        const r = row(PAD + MAKEUP_TOOLS_X + @as(i32, @intCast(i)) * (STEP_W + GAP), y, STEP_W);
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

const MakeupTool = enum {
    grow,
    shrink,
    drop,

    fn label(t: MakeupTool) [:0]const u8 {
        return switch (t) {
            .grow => "+",
            .shrink => "-",
            .drop => "x",
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

/// One row of the generator: a field of the base's, a feature's or the foes' params, a tip for each number in it.
const Knob = struct { field: []const u8, label: [:0]const u8, tips: []const [:0]const u8, unit: i32 = 1, fmt: []const u8 = "{d}" };

const FLOOR_ROWS = [_]Knob{
    .{ .field = "size", .label = "Size", .tips = &.{ "Width of the box the rooms fall in, centred on the map", "Height of the box the rooms fall in, centred on the map" } },
    .{ .field = "rooms", .label = "Rooms", .tips = &.{"The most rooms it rolls"} },
    .{ .field = "room_w", .label = "Room W", .tips = &.{ "The narrowest a room is rolled", "The widest a room is rolled" } },
    .{ .field = "room_h", .label = "Room H", .tips = &.{ "The shortest a room is rolled", "The tallest a room is rolled" } },
    .{ .field = "torches", .label = "Torches", .tips = &.{"Of the rooms, how many hang a torch"}, .unit = TORCH_STEP, .fmt = "{d}%" },
    .{ .field = "barrels", .label = "Barrels", .tips = &.{"The most barrels one room stacks"} },
};

const WILDS_ROWS = [_]Knob{
    .{ .field = "thicket", .label = "Thicket", .tips = &.{"Of the ground, how much is sown with shrub before it is smoothed"}, .fmt = "{d}%" },
    .{ .field = "smooth", .label = "Smooth", .tips = &.{"Smoothing passes: more, rounder thickets and wider glades"} },
    .{ .field = "strays", .label = "Strays", .tips = &.{"Lone shrubs, a thousandth of the open grass each"} },
    .{ .field = "litter", .label = "Litter", .tips = &.{ "Lone tiny shrubs, a thousandth of the open grass each", "Lone boulders, a thousandth of the open grass each" } },
};

const OPEN_ROWS = [_]Knob{
    .{ .field = "ground", .label = "Ground", .tips = &.{"The open ground, edge to edge"} },
    .{ .field = "edge", .label = "Edge", .tips = &.{"What rings the map and seals it"} },
    .{ .field = "litter", .label = "Litter", .tips = &.{ "Lone tiny shrubs, a thousandth of the open grass each", "Lone boulders, a thousandth of the open grass each" } },
};

const CAVES_ROWS = [_]Knob{
    .{ .field = "fill", .label = "Fill", .tips = &.{"Of the ground, how much is sown with rock before it is smoothed"}, .fmt = "{d}%" },
    .{ .field = "smooth", .label = "Smooth", .tips = &.{"Smoothing passes: more, rounder caves"} },
    .{ .field = "spires", .label = "Spires", .tips = &.{"Lone rock spires, a thousandth of the open floor each"} },
};

const CAVERN_ROWS = [_]Knob{
    .{ .field = "chambers", .label = "Chambers", .tips = &.{"Round chambers it digs, at most"} },
    .{ .field = "radius", .label = "Radius", .tips = &.{ "The smallest chamber's radius", "The largest chamber's radius" } },
    .{ .field = "fray", .label = "Fray", .tips = &.{"How much noise frays a chamber's edge"}, .fmt = "{d}%" },
};

const STRATA_ROWS = [_]Knob{
    .{ .field = "sectors", .label = "Sectors", .tips = &.{"Sectors across and down the map is cut into"} },
    .{ .field = "seeds", .label = "Seeds", .tips = &.{"Deep points dropped in each sector, at most"} },
    .{ .field = "blur", .label = "Blur", .tips = &.{"Blur passes: more, rounder and wider pockets"} },
};

const LABYRINTH_ROWS = [_]Knob{
    .{ .field = "style", .label = "Style", .tips = &.{"Built walls, rock, or a hedge maze"} },
    .{ .field = "chamber", .label = "Chamber", .tips = &.{"Half-width of an open chamber at the heart; 0 for none"} },
    .{ .field = "braid", .label = "Braid", .tips = &.{"Of the dead ends, how many are knocked through into loops"}, .fmt = "{d}%" },
};

const HALL_ROWS = [_]Knob{
    .{ .field = "style", .label = "Style", .tips = &.{"Bare, pillared, grave alcoves, or a grove of plants"} },
    .{ .field = "margin", .label = "Margin", .tips = &.{"Rock between the hall and the map's edge"} },
};

const MAZE_ROWS = [_]Knob{
    .{ .field = "style", .label = "Style", .tips = &.{"Caves, tombs, sewers, lava or ice"} },
    .{ .field = "rooms", .label = "Rooms", .tips = &.{"Rooms it sets, at most"} },
    .{ .field = "size", .label = "Size", .tips = &.{"Cells on a room's side"} },
    .{ .field = "merge", .label = "Merge", .tips = &.{"A thousandth: how often a room is joined to each one already beside it"} },
};

const TOPOLOGY_ROWS = [_]Knob{
    .{ .field = "layout", .label = "Layout", .tips = &.{"The shape of its graph of spots"} },
    .{ .field = "filler", .label = "Filler", .tips = &.{"What fills between the paths"} },
    .{ .field = "ground", .label = "Ground", .tips = &.{"The paths' and clearings' ground"} },
    .{ .field = "clearing", .label = "Clearing", .tips = &.{"A spot's clearing, half-width"} },
    .{ .field = "path", .label = "Path", .tips = &.{"A path's width"} },
    .{ .field = "sides", .label = "Sides", .tips = &.{"Side paths off to dead-end clearings"} },
    .{ .field = "litter", .label = "Litter", .tips = &.{ "Lone tiny shrubs, a thousandth of the open grass each", "Lone boulders, a thousandth of the open grass each" } },
};

const TERRAIN_ROWS = [_]Knob{
    .{ .field = "height", .label = "Height", .tips = &.{ "Lowest elevation, 0 to 100; under 20 is sea", "Highest elevation; 90 and over is mountain" } },
    .{ .field = "rain", .label = "Rain", .tips = &.{ "Driest, 0 to 100", "Wettest" } },
    .{ .field = "drain", .label = "Drainage", .tips = &.{ "Least drained, 0 to 100", "Best drained" } },
    .{ .field = "heat", .label = "Heat", .tips = &.{ "Coldest, 0 to 100; 10 and under is tundra or glacier", "Hottest" } },
    .{ .field = "scale", .label = "Scale", .tips = &.{"Cells across a field's features"} },
    .{ .field = "rivers", .label = "Rivers", .tips = &.{"Rivers running downhill from the heights"} },
    .{ .field = "litter", .label = "Litter", .tips = &.{ "Lone tiny shrubs, a thousandth of the open grass each", "Lone boulders, a thousandth of the open grass each" } },
};

const KEEP_ROWS = [_]Knob{
    .{ .field = "size", .label = "Size", .tips = &.{ "The curtain wall's width", "The curtain wall's height" } },
    .{ .field = "towers", .label = "Towers", .tips = &.{"A corner tower's half-width; 0 for none"} },
    .{ .field = "moat", .label = "Moat", .tips = &.{"The moat's width; 0 for none"} },
    .{ .field = "yard", .label = "Yard", .tips = &.{"The courtyard's ground"} },
    .{ .field = "outside", .label = "Outside", .tips = &.{"The ground outside the walls"} },
    .{ .field = "torches", .label = "Torches", .tips = &.{"Of the keep's top walls, how many hang a torch"}, .fmt = "{d}%" },
    .{ .field = "barrels", .label = "Barrels", .tips = &.{"Barrels in the keep, at most"} },
};

const TOWN_ROWS = [_]Knob{
    .{ .field = "wall", .label = "Wall", .tips = &.{"None, a stone wall or a fence round it"} },
    .{ .field = "block", .label = "Block", .tips = &.{"A block's side between streets"} },
    .{ .field = "street", .label = "Street", .tips = &.{"A street's width"} },
    .{ .field = "houses", .label = "Houses", .tips = &.{"Of each block's lots, how many are built on"}, .fmt = "{d}%" },
    .{ .field = "canals", .label = "Canals", .tips = &.{"Of the streets, how many are canals"}, .fmt = "{d}%" },
    .{ .field = "ground", .label = "Streets", .tips = &.{"The streets' ground"} },
    .{ .field = "outside", .label = "Outside", .tips = &.{"The ground round the town"} },
};

const DUNES_ROWS = [_]Knob{
    .{ .field = "ground", .label = "Ground", .tips = &.{"The open ground"} },
    .{ .field = "ridges", .label = "Ridges", .tips = &.{"How wide a crest of the noise stands as ridge"} },
    .{ .field = "mesas", .label = "Mesas", .tips = &.{"Of the highest ground, how much stands as mesa"} },
    .{ .field = "scale", .label = "Scale", .tips = &.{"Cells across a dune"} },
};

const SITE_ROWS = [_]Knob{
    .{ .field = "template", .label = "Template", .tips = &.{"Huts, compound, pillars, or any one per section"} },
    .{ .field = "decay", .label = "Decay", .tips = &.{"Of the walls, how many have fallen to rubble"}, .fmt = "{d}%" },
    .{ .field = "ground", .label = "Ground", .tips = &.{"The ground between and round the buildings"} },
};

fn rowsOf(comptime a: atlas.Algo) []const Knob {
    return switch (a) {
        .rooms => &FLOOR_ROWS,
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
    .{ .field = "fill", .label = "Fill", .tips = &.{"What it runs with: water, lava, a chasm; rock makes a cliff"} },
    .{ .field = "width", .label = "Width", .tips = &.{"Cells across"} },
    .{ .field = "bank", .label = "Bank", .tips = &.{"What lines it either side"} },
    .{ .field = "course", .label = "Course", .tips = &.{"Across, down, or either"} },
    .{ .field = "count", .label = "Count", .tips = &.{"How many"} },
    .{ .field = "fords", .label = "Fords", .tips = &.{"Crossings laid over it: shallows, a bridge, or a gap"} },
};

const LAKE_ROWS = [_]Knob{
    .{ .field = "fill", .label = "Fill", .tips = &.{"Water, lava, rock for a mesa, a chasm for a pit"} },
    .{ .field = "count", .label = "Count", .tips = &.{"How many, at most"} },
    .{ .field = "size", .label = "Size", .tips = &.{"The biggest one's half-width"} },
    .{ .field = "ring", .label = "Ring", .tips = &.{"What rings each"} },
    .{ .field = "island", .label = "Island", .tips = &.{"Of them, how many keep an island at their heart"}, .fmt = "{d}%" },
};

const ROAD_ROWS = [_]Knob{
    .{ .field = "paving", .label = "Paving", .tips = &.{"What it is laid with"} },
    .{ .field = "width", .label = "Width", .tips = &.{"Cells across"} },
    .{ .field = "course", .label = "Course", .tips = &.{"Across, down, or either"} },
    .{ .field = "count", .label = "Count", .tips = &.{"How many"} },
    .{ .field = "wander", .label = "Wander", .tips = &.{"How much it bends, of a river's bending"}, .fmt = "{d}%" },
};

const SCATTER_ROWS = [_]Knob{
    .{ .field = "tile", .label = "Tile", .tips = &.{"What it lays"} },
    .{ .field = "on", .label = "On", .tips = &.{"What it lays it on"} },
    .{ .field = "amount", .label = "Amount", .tips = &.{"A thousandth of those cells; 1000 lays it on all of them"} },
    .{ .field = "clump", .label = "Clump", .tips = &.{"Clumps this many cells across; 0 lays it a cell at a time"} },
};

const BORDER_ROWS = [_]Knob{
    .{ .field = "tile", .label = "Tile", .tips = &.{"What rings the map"} },
    .{ .field = "width", .label = "Width", .tips = &.{"Cells deep, at least"} },
    .{ .field = "rough", .label = "Rough", .tips = &.{"Cells more it frays inward, at most"} },
};

const BUILDINGS_ROWS = [_]Knob{
    .{ .field = "count", .label = "Count", .tips = &.{"How many, at most"} },
    .{ .field = "size", .label = "Size", .tips = &.{ "The shortest side, walls and all", "The longest side" } },
    .{ .field = "decay", .label = "Decay", .tips = &.{"Of the walls, how many have fallen to rubble"}, .fmt = "{d}%" },
    .{ .field = "walls", .label = "Walls", .tips = &.{"What they are walled with"} },
    .{ .field = "floor", .label = "Floor", .tips = &.{"What they are floored with"} },
    .{ .field = "barrels", .label = "Barrels", .tips = &.{"The most barrels one stacks"} },
    .{ .field = "torches", .label = "Torches", .tips = &.{"Of them, how many hang a torch"}, .fmt = "{d}%" },
};

const FARMS_ROWS = [_]Knob{
    .{ .field = "count", .label = "Count", .tips = &.{"Fields, at most"} },
    .{ .field = "size", .label = "Size", .tips = &.{ "The shortest side, fence and all", "The longest side" } },
    .{ .field = "crop", .label = "Crop", .tips = &.{"What grows in the rows"} },
    .{ .field = "furrow", .label = "Furrow", .tips = &.{"What lies between the rows"} },
    .{ .field = "fence", .label = "Fence", .tips = &.{"What fences each field"} },
};

const SETPIECE_ROWS = [_]Knob{
    .{ .field = "piece", .label = "Piece", .tips = &.{"The hand-drawn piece it stamps"} },
    .{ .field = "count", .label = "Count", .tips = &.{"How many, at most"} },
    .{ .field = "apart", .label = "Apart", .tips = &.{"Cells of margin round each"} },
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
    };
}

const Choice = struct { label: [:0]const u8, tip: [:0]const u8 };
const ALGO_CHOICE = Choice{ .label = "Algorithm", .tip = "The base its floor is rolled from; changing it starts that base afresh" };
const FEATURE_CHOICE = Choice{ .label = "Feature", .tip = "What this feature lays over the base; changing it starts that feature afresh" };
const ADD_FEATURE_TIP = blk: {
    const kinds = std.enums.values(atlas.Kind);
    var s: [:0]const u8 = "Lay another feature over the base:";
    for (kinds, 0..) |k, i| s = s ++ (if (i == 0) " " else if (i + 1 == kinds.len) " or " else ", ") ++ @tagName(k);
    break :blk s;
};

const FOE_ROWS = [_]Knob{
    .{ .field = "packs", .label = "Packs", .tips = &.{"How many packs it places"} },
    .{ .field = "few", .label = "At least", .tips = &.{"Each foe any makeup holds has this many at least, while packs last"} },
    .{ .field = "reach", .label = "Reach", .tips = &.{"Cells from a pack's lead to the rest of it, at most"} },
    .{ .field = "gap", .label = "Gap", .tips = &.{"Cells from where the hero arrives to every foe, at least"} },
    .{ .field = "apart", .label = "Apart", .tips = &.{"Cells from one pack to every other, at least; 0 lets them crowd"} },
};

const ADD_MAKEUP_TIP = "Another pack it may roll, a lone " ++ actor.row(pack.FIRST).name ++ " to begin";
const SHIFT_TIP = std.fmt.comptimePrint(" ({s} steps {d})", .{ Desk.SHIFT_CAPTION, SHIFT_STEP });

comptime {
    @setEvalBranchQuota(1_000_000);
    for (std.enums.values(atlas.Algo)) |a| covers(@FieldType(atlas.Floor, @tagName(a)), rowsOf(a), atlas.floorKnobs(a));
    for (std.enums.values(atlas.Kind)) |k| covers(@FieldType(atlas.Feature, @tagName(k)), featureRowsOf(k), atlas.featureKnobs(k));
    covers(@FieldType(atlas.Procgen, "foes"), &FOE_ROWS, atlas.FOE_KNOBS);
}

/// A row for each of `T`'s knobs and no other, and a tip for each number in it.
fn covers(comptime T: type, comptime rows: []const Knob, comptime knobs_: []const []const u8) void {
    @setEvalBranchQuota(100_000);
    if (rows.len != knobs_.len) @compileError("a generator row is for no knob");
    for (knobs_) |name| {
        const r = for (rows) |r| {
            if (std.mem.eql(u8, r.field, name)) break r;
        } else @compileError(name ++ " has no row on the generator");
        if (r.tips.len != numbers(@FieldType(T, name))) @compileError(name ++ " wants a tip for each number in it");
    }
}

fn numbers(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .int, .@"enum" => 1,
        .array => |a| a.len,
        .@"struct" => |s| s.fields.len,
        else => @compileError(@typeName(T) ++ " is no knob"),
    };
}

fn knobRow(ed: *Editor, g: *game.Game, y: i32, owner: anytype, comptime k: Knob) void {
    rowLabel(g, y, k.label);
    const v = &@field(owner.*, k.field);
    const T = @TypeOf(v.*);
    const n = comptime numbers(T);
    switch (@typeInfo(T)) {
        .int => stepNumber(ed, g, y, 0, n, T, v, k),
        .@"enum" => stepChoice(ed, g, y, T, v, k.tips[0]),
        .array => |a| inline for (0..n) |i| stepNumber(ed, g, y, i, n, a.child, &v[i], k),
        .@"struct" => |s| inline for (s.fields, 0..) |f, i| stepNumber(ed, g, y, i, n, f.type, &@field(v.*, f.name), k),
        else => unreachable,
    }
}

fn stepNumber(ed: *Editor, g: *game.Game, y: i32, comptime i: usize, n: usize, comptime T: type, v: *T, comptime k: Knob) void {
    var buf: [16]u8 = undefined;
    const tip = k.tips[i] ++ SHIFT_TIP;
    const r = slotOf(PAD + LABEL_W, INNER_W - LABEL_W, y, i, n);
    bump(T, v, k.unit * stepper(ed, g, r, num(&buf, k.fmt, v.*), .{ .{ .tip = tip }, .{ .tip = tip } }));
}

/// `- name +`, round the choices.
fn stepChoice(ed: *Editor, g: *game.Game, y: i32, comptime T: type, v: *T, tip: [:0]const u8) void {
    var buf: [32]u8 = undefined;
    const r = slotOf(PAD + LABEL_W, INNER_W - LABEL_W, y, 0, 1);
    const by = stepper(ed, g, r, num(&buf, "{s}", @tagName(v.*)), .{ .{ .tip = tip }, .{ .tip = tip } });
    v.* = cycle(T, v.*, by);
}

fn cycle(comptime T: type, v: T, by: i32) T {
    const all = comptime std.enums.values(T);
    const at = std.mem.indexOfScalar(T, all, v).?;
    return all[mathx.wrap(at, std.math.sign(by), all.len)];
}

const Step = struct { tip: [:0]const u8, live: bool = true };

/// `- value +` across `r`, the minus then the plus: the step it was clicked by, if it was.
fn stepper(ed: *Editor, g: *game.Game, r: rl.Rectangle, value: [:0]const u8, steps: [2]Step) i32 {
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const w: i32 = @intFromFloat(r.width);
    var by: i32 = 0;
    if (button(ed, g, row(x, y, STEP_W), "-", false, steps[0].live, steps[0].tip)) by = -1;
    if (button(ed, g, row(x + w - STEP_W, y, STEP_W), "+", false, steps[1].live, steps[1].tip)) by = 1;
    g.face.draw(value, g.face.leftFor(value, x + @divTrunc(w, 2), TEXT), y + TEXT_DY, TEXT, look.TEXT);
    return if (ed.desk.shift) by * SHIFT_STEP else by;
}

/// By `by`, not below 0; the range is the caller's to fit.
fn bump(comptime T: type, v: *T, by: i32) void {
    const at: i64 = @intCast(v.*);
    const hi: i64 = @min(std.math.maxInt(T), std.math.maxInt(i64));
    v.* = @intCast(std.math.clamp(at + by, 0, hi));
}

fn drawStatus(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    var buf: [LINE + 1]u8 = undefined;
    const top = g.screen.y - STATUS_H;
    rl.drawRectangle(PANEL_W, top, g.screen.x - PANEL_W, STATUS_H, PANEL_BG);
    rl.drawRectangle(PANEL_W, top, g.screen.x - PANEL_W, 1, look.EDGE);
    const line = if (ed.said_t > 0)
        ed.said.text()
    else if (ed.tip) |t| t else hover(ed, c, &buf);
    var y = top + GAP;
    g.face.draw(line, PANEL_W + PAD, y, TEXT, look.TEXT);
    y += TEXT + GAP * 2;
    g.face.draw(if (ed.view == .map) CRIB_MAP else CRIB_GRAPH, PANEL_W + PAD, y, TEXT, look.DIM);
    for (CRIB_ALL) |crib| {
        y += TEXT + GAP;
        g.face.draw(crib, PANEL_W + PAD, y, TEXT, look.DIM);
    }
    std.debug.assert(y + TEXT == top + STATUS_H);
}

fn hover(ed: *Editor, c: rl.Rectangle, buf: []u8) [:0]const u8 {
    if (!rl.checkCollisionPointRec(vec(ed.desk.mouse), c)) return "";
    var a: [atlas.TITLE_MAX]u8 = undefined;
    if (ed.view == .graph) {
        const n = ed.boxUnder(c, ed.desk.mouse) orelse return "";
        var d: [LINE]u8 = undefined;
        return std.fmt.bufPrintZ(buf, "{s} (node {d}): {s}", .{ ed.nodeName(n, &a), n, nodeDetail(&ed.world.node[n], &d) }) catch "";
    }
    const p = ed.cellAt(c, ed.desk.mouse);
    if (!grid.Level.inside(p)) return "";
    const nd = ed.here();
    const k = nd.doorAt(p) orelse
        return std.fmt.bufPrintZ(buf, "{d},{d}  {s}", .{ p.x, p.y, if (nd.unrolled()) "rolled each run" else @tagName(ed.lv.at(p)) }) catch "";
    const to = nd.door[k].to orelse
        return std.fmt.bufPrintZ(buf, "{d},{d}  door {d}, unlinked", .{ p.x, p.y, k }) catch "";
    return std.fmt.bufPrintZ(buf, "{d},{d}  door {d} leads to {s} (node {d}) door {d}; {s} goes through", .{ p.x, p.y, k, ed.nodeName(to.node, &a), to.node, to.door, Desk.GO_CAPTION }) catch "";
}

fn nodeDetail(nd: *const atlas.Node, buf: []u8) [:0]const u8 {
    const kind = switch (nd.plan) {
        .bespoke => "bespoke",
        .procgen => |pg| @tagName(pg.floor),
    };
    const open = nd.unlinked();
    if (open == 0) return std.fmt.bufPrintZ(buf, "{s}, {d} doors", .{ kind, nd.door_n }) catch "";
    return std.fmt.bufPrintZ(buf, "{s}, {d} doors, {d} unlinked", .{ kind, nd.door_n, open }) catch "";
}

fn visible(ed: *const Editor, c: rl.Rectangle) struct { lo: P, hi: P } {
    return .{
        .lo = .{ .x = @max(0, @as(i32, @intFromFloat(@floor(ed.cam[0])))), .y = @max(0, @as(i32, @intFromFloat(@floor(ed.cam[1])))) },
        .hi = .{
            .x = @min(grid.W, @as(i32, @intFromFloat(@ceil(ed.cam[0] + c.width / ed.px()))) + 1),
            .y = @min(grid.H, @as(i32, @intFromFloat(@ceil(ed.cam[1] + c.height / ed.px()))) + 1),
        },
    };
}

fn drawMap(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    ed.preview();
    scissor(c);
    defer rl.endScissorMode();
    const v = visible(ed, c);
    const unrolled = ed.here().unrolled();
    var cells = grid.Cells.of(v.lo, v.hi);
    while (cells.next()) |p| {
        const r = ed.cellRect(c, p);
        if (unrolled) {
            rl.drawRectangleRec(r, look.UNROLLED);
        } else {
            if (ed.lv.at(p).ground()) |u| {
                if (g.sprites.tileOf(u, null)) |t| sprite(t, r) else if (look.tileBg(u)) |bg| rl.drawRectangleRec(r, bg);
            }
            if (g.sprites.tileAt(&ed.lv, p)) |t| {
                sprite(t, r);
            } else {
                const t = ed.lv.at(p);
                if (look.tileBg(t) orelse if (t.ground() == null) look.BARE_WALL else null) |bg| rl.drawRectangleRec(r, bg);
                if (t != .wall) tileGlyph(ed, g, t, r);
            }
        }
        if (ed.lv.hasBarrel(p)) {
            if (g.sprites.barrel) |t| sprite(t, r) else glyph(ed, g, look.BARREL.ch, r, look.BARREL.fg);
        }
    }
    for (ed.lv.torches()) |t| glyph(ed, g, look.TORCH.ch, ed.cellRect(c, t), look.TORCH.fg);
    switch (ed.plan().*) {
        .bespoke => |*b| for (b.foes()) |f| {
            const r = ed.cellRect(c, f.at);
            if (g.sprites.body(f.kind)) |t| sprite(t, r) else glyph(ed, g, look.body(f.kind).ch, r, look.body(f.kind).fg);
        },
        .procgen => {},
    }
    var buf: [8]u8 = undefined;
    for (ed.here().doors(), 0..) |d, k| {
        const r = ed.cellRect(c, d.at);
        glyph(ed, g, look.DOOR.ch, r, if (d.to == null) UNLINKED else look.DOOR.fg);
        if (ed.px() >= LABEL_PX) {
            const size: i32 = @intFromFloat(ed.px() * LABEL_OF_CELL);
            g.face.text(std.fmt.bufPrintZ(&buf, "{d}", .{k}) catch "", @intFromFloat(r.x + 1), @intFromFloat(r.y), size, look.TEXT);
        }
        const pk = ed.pick orelse continue;
        if (std.meta.eql(pk, atlas.Link{ .node = ed.node, .door = k })) rl.drawRectangleLinesEx(r, 2, PICKED);
    }
    if (ed.start_at) |s| glyph(ed, g, START.ch, ed.cellRect(c, s), START.fg);
    const m = ed.cellAt(c, ed.desk.mouse);
    if (ed.rect) |r| {
        outlineCells(ed, c, r.from, clampCell(m), PICKED);
    } else if (grid.Level.inside(m)) {
        const box = brushBox(m, if (ed.tool.broad() and ed.tool.fits(ed.here())) ed.brushSize() else 1);
        outlineCells(ed, c, box.lo, box.hi, HOVER);
    }
}

fn outlineCells(ed: *const Editor, c: rl.Rectangle, a: P, b: P, col: rl.Color) void {
    const lo = ed.cellRect(c, .{ .x = @min(a.x, b.x), .y = @min(a.y, b.y) });
    const hi = ed.cellRect(c, .{ .x = @max(a.x, b.x), .y = @max(a.y, b.y) });
    rl.drawRectangleLinesEx(.{ .x = lo.x, .y = lo.y, .width = hi.x + hi.width - lo.x, .height = hi.y + hi.height - lo.y }, 1, col);
}

fn drawGraph(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    scissor(c);
    defer rl.endScissorMode();
    var buf: [LINE]u8 = undefined;
    for (0..ed.world.node_n) |n| {
        const b = ed.boxAt(c, n);
        rl.drawRectangleRec(b, PANEL_BG);
        if (thumb(ed, n)) |t| sprite(t, .{ .x = b.x, .y = b.y + @as(f32, @floatFromInt(BOX_TOP)), .width = @floatFromInt(BOX_W), .height = @floatFromInt(BOX_H - BOX_TOP) });
        g.face.draw(ed.nodeTitle(n, &buf), @as(i32, @intFromFloat(b.x)) + GAP, @as(i32, @intFromFloat(b.y)) + TITLE_DY, TEXT, titleColor(ed, n));
        rl.drawRectangleLinesEx(b, 1, if (n == ed.node) ON else look.EDGE);
    }
    for (ed.world.nodes(), 0..) |*nd, n| {
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
}

/// The node's floor as it will be played, a pixel or two a cell; drawn anew only when the node changed.
fn thumb(ed: *Editor, n: usize) ?rl.Texture2D {
    if (!ed.thumb_ok.isSet(n)) {
        ed.world.node[n].sketch(&ed.thumb_lv);
        var px: [grid.CELLS]rl.Color = undefined;
        const unrolled = ed.world.node[n].unrolled();
        for (&px, 0..) |*c, i| {
            const lv = &ed.thumb_lv;
            c.* = if (lv.door[i] != grid.NO_DOOR)
                look.DOOR.fg
            else if (unrolled)
                look.UNROLLED
            else if (lv.barrel[i])
                look.BARREL.fg
            else if ((lv.shape[i] orelse .top) == .solid)
                look.BG
            else
                look.mini(lv.tile[i], true);
        }
        if (ed.thumbs[n] == null) {
            ed.thumbs[n] = look.canvas(grid.W, grid.H, look.BG);
            if (ed.thumbs[n]) |t| rl.setTextureFilter(t, .point);
        }
        if (ed.thumbs[n]) |t| rl.updateTexture(t, &px);
        ed.thumb_ok.set(n);
    }
    return ed.thumbs[n];
}

fn drawModal(ed: *Editor, g: *game.Game) void {
    var buf: [LINE]u8 = undefined;
    game.veil(g, g.screen.y);
    const body = modalBody(ed);
    const h = PAD + HEAD + PAD + body + ROW_H + PAD;
    const x = @divTrunc(g.screen.x - MODAL_W, 2);
    var y = @divTrunc(g.screen.y - h, 2);
    rl.drawRectangle(x, y, MODAL_W, h, PANEL_BG);
    rl.drawRectangleLines(x, y, MODAL_W, h, look.EDGE);
    y += PAD;
    const title: [:0]const u8 = switch (ed.modal) {
        .confirm => "Unsaved changes",
        .name => if (ed.naming == .new) "New world" else "Save the world as",
        .open => if (ed.listing.n > MODAL_ROWS) "Open a world (" ++ Desk.WHEEL_CAPTION ++ " scrolls)" else "Open a world",
        .none => "",
    };
    g.face.draw(title, x + PAD, y, HEAD, look.TEXT);
    y += HEAD + PAD;
    const buttons_y = y + body;
    const bx = x + MODAL_W - PAD - MODAL_BTN_W;
    switch (ed.modal) {
        .confirm => {
            g.face.draw(std.fmt.bufPrintZ(&buf, "{s} has changes that are not saved.", .{ed.path()}) catch "", x + PAD, y, TEXT, look.TEXT);
            y += ROW_H * 2 + PAD;
            std.debug.assert(y == buttons_y);
            if (buttonOn(ed, g, modalButton(bx, y, 2), "Save (" ++ Desk.ENTER_CAPTION ++ ")", false, true, true, null) and ed.save()) ed.commit();
            if (buttonOn(ed, g, modalButton(bx, y, 1), "Discard", false, true, true, null)) ed.commit();
            cancelButton(ed, g, bx, y);
        },
        .name => {
            fieldRow(ed, g, row(x + PAD, y, MODAL_W - PAD * 2));
            y += ROW_H + GAP;
            var pbuf: [atlas.PATH_MAX]u8 = undefined;
            const note = if (atlas.pathFor(&pbuf, ed.field.text())) |p| std.fmt.bufPrintZ(&buf, "Makes {s}", .{p}) catch "" else "Type a name";
            g.face.draw(note, x + PAD, y, SMALL, look.DIM);
            y += ROW_H + PAD;
            std.debug.assert(y == buttons_y);
            if (buttonOn(ed, g, modalButton(bx, y, 1), "OK (" ++ Desk.ENTER_CAPTION ++ ")", false, true, true, null)) ed.named();
            cancelButton(ed, g, bx, y);
        },
        .open => {
            if (ed.listing.n == 0) {
                g.face.draw("No worlds in " ++ atlas.DIR ++ " yet", x + PAD, y, TEXT, look.DIM);
                y += ROW_H;
            }
            for (ed.listed_top..@min(ed.listing.n, ed.listed_top + MODAL_ROWS)) |i| {
                const p = ed.listing.at(i);
                const label = std.fmt.bufPrintZ(&buf, "{s}", .{p}) catch "";
                if (buttonOn(ed, g, row(x + PAD, y, MODAL_W - PAD * 2), label, std.mem.eql(u8, p, ed.path()), true, true, null)) {
                    ed.pending_path.set(p, PATH_MAX);
                    ed.modal = .none;
                    ed.request(.open);
                    return;
                }
                y += ROW_H;
            }
            y += PAD;
            std.debug.assert(y == buttons_y);
            cancelButton(ed, g, bx, y);
        },
        .none => {},
    }
}

/// Pixels between a modal's title and its buttons, as `drawModal` lays them out.
fn modalBody(ed: *const Editor) i32 {
    return switch (ed.modal) {
        .confirm => ROW_H * 2 + PAD,
        .name => ROW_H + GAP + ROW_H + PAD,
        .open => @as(i32, @intCast(@max(1, @min(ed.listing.n, MODAL_ROWS)))) * ROW_H + PAD,
        .none => 0,
    };
}

/// The `k`th of a modal's buttons leftward from the one at `bx`.
fn modalButton(bx: i32, y: i32, k: i32) rl.Rectangle {
    return row(bx - (MODAL_BTN_W + GAP) * k, y, MODAL_BTN_W);
}

fn fieldRow(ed: *Editor, g: *game.Game, r: rl.Rectangle) void {
    var buf: [LINE]u8 = undefined;
    rl.drawRectangleRec(r, ROW_ON);
    g.face.draw(std.fmt.bufPrintZ(&buf, "{s}" ++ menu.CARET, .{ed.field.text()}) catch "", @as(i32, @intFromFloat(r.x)) + GAP, @as(i32, @intFromFloat(r.y)) + TEXT_DY, TEXT, look.RETICLE);
}

fn titleColor(ed: *const Editor, n: usize) rl.Color {
    return if (ed.renamingNode(n)) look.RETICLE else look.TEXT;
}

fn cancelButton(ed: *Editor, g: *game.Game, bx: i32, y: i32) void {
    if (buttonOn(ed, g, modalButton(bx, y, 0), "Cancel (" ++ Desk.BACK_CAPTION ++ ")", false, true, true, null)) ed.modal = .none;
}

fn sprite(t: rl.Texture2D, r: rl.Rectangle) void {
    look.stretch(t, r, rl.Color.white);
}

fn glyph(ed: *const Editor, g: *game.Game, ch: u8, r: rl.Rectangle, col: rl.Color) void {
    const m = ed.inkOf(r);
    g.face.glyph(ch, m.x, m.y, m.size, col);
}

fn tileGlyph(ed: *const Editor, g: *game.Game, t: grid.Tile, r: rl.Rectangle) void {
    const m = ed.inkOf(r);
    g.face.symbol(look.tileSym(t), look.tile(t).ch, m.x, m.y, m.size, look.tile(t).fg);
}

/// DEV ONLY: the posed world's map mid link-pick, its graph, then its procgen node's generator.
pub fn shoot(g: *game.Game, target: rl.RenderTexture2D, map_path: [:0]const u8, graph_path: [:0]const u8, gen_path: [:0]const u8) void {
    const ed = Editor.create(std.heap.c_allocator) catch return;
    defer ed.destroy();
    const w = ed.world;
    w.* = .{};
    _ = w.add(.{ .bespoke = .{} });
    _ = w.add(.{ .procgen = .{} });
    _ = w.add(.{ .procgen = .{} });
    _ = w.node[0].rename("Gatehouse");
    _ = w.node[1].rename("The Warrens");
    ed.setPath(atlas.worldPath("test_shot"));
    ed.zoom = 2;
    ed.brush = 2;
    ed.tool = .floor;
    fillRect(ed, .{ .from = .{ .x = 8, .y = 6 }, .erase = false }, .{ .x = 23, .y = 15 });
    const posed = [_]struct { t: Tool, at: P }{
        .{ .t = .torch, .at = .{ .x = 14, .y = 5 } },
        .{ .t = .barrel, .at = .{ .x = 8, .y = 6 } },
        .{ .t = .rat, .at = .{ .x = 18, .y = 10 } },
        .{ .t = .slime, .at = .{ .x = 20, .y = 12 } },
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
    ed.world.link(.{ .node = 1, .door = 1 }, .{ .node = 2, .door = 0 });
    ed.select(1);
    ed.tool = .link;
    place(ed, .{ .x = 5, .y = 5 });
    ed.select(0);
    place(ed, .{ .x = 24, .y = 10 });
    place(ed, .{ .x = 16, .y = 16 });
    ed.tool = .floor;
    ed.cam = .{ 4, 2 };
    g.screen = .{ .x = target.texture.width, .y = target.texture.height };
    const hover_at = ed.cellRect(Editor.canvas(g), .{ .x = 14, .y = 13 });
    ed.desk.mouse = .{ .x = @as(i32, @intFromFloat(hover_at.x)) + 8, .y = @as(i32, @intFromFloat(hover_at.y)) + 8 };
    ed.said_t = 0;
    for ([_]View{ .map, .graph }, [_][:0]const u8{ map_path, graph_path }) |v, p| {
        ed.view = v;
        rl.beginTextureMode(target);
        draw(ed, g);
        rl.endTextureMode();
        game.exportTarget(target, p);
    }
    ed.view = .map;
    ed.select(1);
    ed.lower = .generator;
    const fo = &ed.world.node[1].plan.procgen.foes;
    _ = fo.addMakeup();
    fo.makeup[fo.makeup_n - 1] = pack.Makeup.of(&.{ .slime, .bloat, .rat, .rat, .rat });
    fo.makeup[fo.makeup_n - 1].weight = 3;
    ed.desk.mouse = .{ .x = 0, .y = 0 };
    rl.beginTextureMode(target);
    draw(ed, g);
    ed.gen_top = ed.gen_most;
    draw(ed, g);
    rl.endTextureMode();
    game.exportTarget(target, gen_path);
}

fn testEditor() !*Editor {
    const ed = try Editor.create(std.testing.allocator);
    ed.world.* = .{};
    ed.setPath(atlas.worldPath("test_editor"));
    return ed;
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

test "painting a bespoke node: a door opens its wall and no wall paints over it" {
    const ed = try testEditor();
    defer ed.destroy();
    const w = ed.world;
    _ = w.add(.{ .bespoke = .{} });
    ed.tool = .floor;
    fillRect(ed, .{ .from = .{ .x = 4, .y = 5 }, .erase = false }, .{ .x = 9, .y = 5 });
    click(ed, .door, .{ .x = 10, .y = 5 });
    click(ed, .wall, .{ .x = 10, .y = 5 });
    click(ed, .rat, .{ .x = 5, .y = 5 });
    click(ed, .rat, .{ .x = 5, .y = 9 });
    click(ed, .torch, .{ .x = 6, .y = 4 });
    click(ed, .torch, .{ .x = 6, .y = 3 });
    ed.gesture();
    ed.tool = .floor;
    remove(ed, .{ .x = 4, .y = 5 });
    ed.preview();
    try std.testing.expectEqual(grid.Tile.wall, ed.lv.at(.{ .x = 4, .y = 5 }));
    try std.testing.expect(ed.lv.walkable(.{ .x = 10, .y = 5 }));
    try std.testing.expectEqual(@as(?usize, 0), ed.lv.doorAt(.{ .x = 10, .y = 5 }));
    try std.testing.expectEqual(@as(usize, 1), w.node[0].plan.bespoke.foe_n);
    try std.testing.expectEqual(@as(usize, 1), ed.lv.torch_n);
    try std.testing.expect(ed.dirty);
}

test "the link tool joins doors on two nodes, and a procgen node takes doors but no floor" {
    const ed = try testEditor();
    defer ed.destroy();
    const w = ed.world;
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
    try std.testing.expect(!Tool.floor.fits(&w.node[1]));
    try std.testing.expect(Tool.door.fits(&w.node[1]));
    ed.select(1);
    ed.preview();
    try std.testing.expectEqual(@as(?usize, 0), ed.lv.doorAt(.{ .x = 40, .y = 30 }));
}

test "a gesture is one undo however much it paints, and redo puts it back" {
    const ed = try testEditor();
    defer ed.destroy();
    _ = ed.world.add(.{ .bespoke = .{} });
    const b = &ed.world.node[0].plan.bespoke;
    const open = struct {
        fn n(bs: *const atlas.Bespoke) usize {
            var k: usize = 0;
            for (bs.tile) |t| {
                if (t == .floor) k += 1;
            }
            return k;
        }
    }.n;
    ed.gesture();
    ed.tool = .floor;
    fillRect(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false }, .{ .x = 11, .y = 6 });
    ed.gesture();
    fillRect(ed, .{ .from = .{ .x = 2, .y = 8 }, .erase = false }, .{ .x = 3, .y = 8 });
    ed.gesture();
    try std.testing.expectEqual(@as(usize, 52), open(b));
    try std.testing.expectEqual(@as(usize, 2), ed.hist_at);
    ed.undo();
    try std.testing.expectEqual(@as(usize, 50), open(&ed.world.node[0].plan.bespoke));
    ed.undo();
    try std.testing.expectEqual(@as(usize, 0), open(&ed.world.node[0].plan.bespoke));
    ed.redo();
    ed.redo();
    try std.testing.expectEqual(@as(usize, 52), open(&ed.world.node[0].plan.bespoke));
    ed.undo();
    ed.gesture();
    fillRect(ed, .{ .from = .{ .x = 20, .y = 20 }, .erase = false }, .{ .x = 20, .y = 20 });
    try std.testing.expectEqual(ed.hist_at, ed.hist_len);
    try std.testing.expectEqual(@as(usize, 51), open(&ed.world.node[0].plan.bespoke));
    std.debug.print("two strokes over 52 cells, then one after an undo: {d} undo steps\n", .{ed.hist_at});
}

test "undo keeps no more than its cap, dropping the oldest" {
    const ed = try testEditor();
    defer ed.destroy();
    _ = ed.world.add(.{ .bespoke = .{} });
    ed.tool = .floor;
    for (0..UNDO_CAP + 5) |i| {
        ed.gesture();
        place(ed, .{ .x = @intCast(1 + i), .y = 1 });
    }
    try std.testing.expectEqual(UNDO_CAP, ed.hist_len);
    for (0..UNDO_CAP) |_| ed.undo();
    try std.testing.expectEqual(grid.Tile.floor, ed.world.node[0].plan.bespoke.tile[grid.Level.idx(.{ .x = 5, .y = 1 })]);
    try std.testing.expectEqual(grid.Tile.wall, ed.world.node[0].plan.bespoke.tile[grid.Level.idx(.{ .x = 6, .y = 1 })]);
}

test "undoing back to what was saved leaves nothing unsaved, and a press held through New lets go" {
    const ed = try testEditor();
    defer ed.destroy();
    _ = ed.world.add(.{ .bespoke = .{} });
    click(ed, .floor, .{ .x = 3, .y = 3 });
    ed.saved_at = ed.hist_at;
    ed.dirty = false;
    click(ed, .floor, .{ .x = 4, .y = 3 });
    ed.undo();
    try std.testing.expect(!ed.dirty);
    ed.undo();
    try std.testing.expect(ed.dirty);
    ed.redo();
    try std.testing.expect(!ed.dirty);
    ed.drag = .{ .node = 0, .grab = .{ .x = 0, .y = 0 }, .from = .{ .x = 0, .y = 0 } };
    ed.rect = .{ .from = .{ .x = 1, .y = 1 }, .erase = false };
    ed.dirty = false;
    ed.request(.new);
    try std.testing.expect(ed.drag == null and ed.rect == null);
}

test "a fast stroke paints every cell it passes, and Esc mid-rectangle lets the press go" {
    const ed = try testEditor();
    defer ed.destroy();
    _ = ed.world.add(.{ .bespoke = .{} });
    const c = rl.Rectangle{ .x = 0, .y = 0, .width = 2000, .height = 2000 };
    ed.cam = .{ 0, 0 };
    ed.tool = .floor;
    const at = struct {
        fn f(e: *Editor, p: P) P {
            return mouseOn(e, .{ .x = 0, .y = 0, .width = 2000, .height = 2000 }, p);
        }
    }.f;
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = at(ed, .{ .x = 2, .y = 2 }) };
    ed.gesture();
    mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = at(ed, .{ .x = 12, .y = 2 }) };
    mapMouse(ed, c, true);
    var row_n: usize = 0;
    var x: i32 = 0;
    while (x < grid.W) : (x += 1) {
        if (ed.world.node[0].plan.bespoke.tile[grid.Level.idx(.{ .x = x, .y = 2 })] == .floor) row_n += 1;
    }
    mapMouse(ed, c, false);
    ed.desk = .{ .paint = true, .mouse = at(ed, .{ .x = 4, .y = 4 }) };
    mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.floor, ed.world.node[0].plan.bespoke.tile[grid.Level.idx(.{ .x = 4, .y = 4 })]);
    ed.desk = .{};
    mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .paint_hit = true, .shift = true, .mouse = at(ed, .{ .x = 2, .y = 6 }) };
    ed.gesture();
    mapMouse(ed, c, true);
    try std.testing.expect(ed.rect != null);
    escape(ed);
    ed.desk = .{ .paint = true, .mouse = at(ed, .{ .x = 8, .y = 6 }) };
    mapMouse(ed, c, true);
    const stray = ed.world.node[0].plan.bespoke.tile[grid.Level.idx(.{ .x = 8, .y = 6 })];
    std.debug.print("a stroke dragged 10 cells in one frame: {d} cells painted\n", .{row_n});
    try std.testing.expectEqual(@as(usize, 11), row_n);
    try std.testing.expectEqual(grid.Tile.wall, stray);
    try std.testing.expect(ed.standable(.{ .node = 0, .at = .{ .x = 30, .y = 30 } }));
    _ = ed.world.add(.{ .bespoke = .{} });
    try std.testing.expect(!ed.standable(.{ .node = 1, .at = .{ .x = 30, .y = 30 } }));
}

test "a stroke leaving the map paints up to its edge, and it ends with the button that began it" {
    const ed = try testEditor();
    defer ed.destroy();
    _ = ed.world.add(.{ .bespoke = .{} });
    const b = &ed.world.node[0].plan.bespoke;
    const c = rl.Rectangle{ .x = 0, .y = 0, .width = 2000, .height = 2000 };
    ed.cam = .{ -4, 0 };
    ed.tool = .floor;
    ed.gesture();
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 5, .y = 10 }) };
    mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = -3, .y = 10 }) };
    mapMouse(ed, c, true);
    var row_n: usize = 0;
    var x: i32 = 0;
    while (x < grid.W) : (x += 1) {
        if (b.tile[grid.Level.idx(.{ .x = x, .y = 10 })] == .floor) row_n += 1;
    }
    ed.desk = .{ .paint = true, .erase = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 20, .y = 20 }) };
    mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 10 }) };
    mapMouse(ed, c, true);
    std.debug.print("a stroke from x 5 to x -3 in one frame: {d} cells painted to the edge\n", .{row_n});
    try std.testing.expectEqual(@as(usize, 6), row_n);
    try std.testing.expectEqual(grid.Tile.floor, b.tile[grid.Level.idx(.{ .x = 4, .y = 10 })]);
    click(ed, .torch, .{ .x = 3, .y = 9 });
    try std.testing.expectEqual(@as(usize, 1), b.torch_n);
    click(ed, .wall, .{ .x = 3, .y = 10 });
    try std.testing.expectEqual(@as(usize, 0), b.torch_n);
    ed.tool = .floor;
    ed.desk = .{ .shift = true, .paint = true, .erase = true, .paint_hit = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 8, .y = 8 }) };
    mapMouse(ed, c, true);
    try std.testing.expect(!ed.rect.?.erase);
}

test "leaving with unsaved changes asks first, and leaving a saved world does not" {
    const ed = try testEditor();
    defer ed.destroy();
    _ = ed.world.add(.{ .bespoke = .{} });
    ed.request(.leave);
    try std.testing.expect(ed.action == .leave);
    ed.action = .none;
    click(ed, .floor, .{ .x = 3, .y = 3 });
    ed.request(.leave);
    try std.testing.expectEqual(Modal.confirm, ed.modal);
    try std.testing.expect(ed.action == .none);
    ed.commit();
    try std.testing.expect(ed.action == .leave);
}

test "a rename is one undo, and deleting a node renumbers the list round it" {
    const ed = try testEditor();
    defer ed.destroy();
    for (0..3) |_| _ = ed.world.add(.{ .bespoke = .{} });
    ed.select(1);
    ed.startRename();
    ed.field.set("Crypt", atlas.NAME_MAX);
    ed.commitRename();
    try std.testing.expectEqualStrings("Crypt", ed.world.node[1].name());
    ed.select(0);
    ed.gesture();
    deleteNode(ed);
    try std.testing.expectEqualStrings("Crypt", ed.world.node[0].name());
    ed.undo();
    ed.undo();
    try std.testing.expectEqual(@as(usize, 3), ed.world.node_n);
    try std.testing.expectEqual(@as(usize, 0), ed.world.node[1].label_n);
}

test "a node added is named as it is added, one undo for both" {
    const ed = try testEditor();
    defer ed.destroy();
    _ = ed.world.add(.{ .bespoke = .{} });
    const before = ed.world.node_n;
    ed.gesture();
    addNode(ed, .{ .procgen = .{} });
    try std.testing.expect(ed.renaming);
    var buf: [LINE]u8 = undefined;
    ed.field.set("Pit", atlas.NAME_MAX);
    try std.testing.expect(std.mem.endsWith(u8, ed.nodeTitle(ed.node, &buf), "Pit_"));
    ed.commitRename();
    try std.testing.expectEqualStrings("Pit", ed.world.node[before].name());
    ed.undo();
    try std.testing.expectEqual(before, ed.world.node_n);
}
