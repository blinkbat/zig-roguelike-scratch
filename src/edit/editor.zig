const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../world/grid.zig");
const atlas = @import("../world/atlas.zig");
const actor = @import("../play/actor.zig");
const look = @import("../gfx/look.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");

const P = mathx.P;
const Desk = input.Desk;

const PANEL_W: i32 = 340;
const PAD: i32 = 12;
const ROW_H: i32 = 26;
const NODE_H: i32 = 46;
const GAP: i32 = 6;
const TEXT: i32 = 20;
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
/// A node's name, or "node 31" for one with none.
const NAME_BUF: usize = 32;
/// A press that moves this far is a drag, not a click.
const DRAG_PX: i32 = 4;
/// Door numbers are unreadable below this many pixels a cell.
const LABEL_PX: f32 = 16;
const GLYPH_OF_CELL: f32 = 0.9;
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

comptime {
    std.debug.assert(atlas.GRAPH_STEP.x > BOX_W and atlas.GRAPH_STEP.y > BOX_H);
    std.debug.assert(FIELD_MAX >= atlas.NAME_MAX and NAME_BUF >= atlas.NAME_MAX);
}

const PANEL_BG = look.SLOT_EMPTY;
const ROW_ON = look.SLOT_BG;
const HOVER = look.fade(look.TEXT, 0.6);
const PICKED = look.RETICLE;
const UNLINKED = look.DIM;
const WARN = look.LEAN_FOE;
const START = look.body(.archer);
const START_MARK = [_]u8{ START.ch, ' ' };
const VEIL = look.VEIL;

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
        return switch (t) {
            .rat => .rat,
            .slime => .slime,
            .bloat => .bloat,
            .floor, .wall, .barrel, .torch, .door, .link, .start => null,
        };
    }

    /// A procgen node's floor, torches, barrels and foes are the generator's.
    fn fits(t: Tool, plan: *const atlas.Plan) bool {
        return plan.* == .bespoke or switch (t) {
            .door, .link, .start => true,
            .floor, .wall, .barrel, .torch, .rat, .slime, .bloat => false,
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
            .floor => "Floor: paint open ground; right-click paints wall",
            .wall => "Wall: paint rock; right-click paints floor",
            .barrel => "Barrel: breaks for gold; right-click takes it away",
            .torch => "Torch: hangs on a wall with floor below it",
            .rat, .slime, .bloat => "Foe: stands on open floor; right-click takes any foe away",
            .door => "Door: any cell of any node; a procgen node's floor is rolled round its doors each run",
            .link => "Link: click a door, then the door it leads to on any node; right-click unlinks",
            .start => "Start: where the world begins, and F5 plays from",
        };
    }
};

const TOOLS = std.enums.values(Tool);

comptime {
    std.debug.assert(TOOLS.len == Desk.TOOL_KEYS.len);
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
    Desk.WHEEL_CAPTION ++ " over the node list scrolls it" ++ SEP ++ Desk.ENTER_CAPTION ++ " names a node" ++ SEP ++
        Desk.PLAY_CAPTION ++ " or " ++ Desk.PLAY_HERE_CAPTION ++ " back from playing" ++ SEP ++ Desk.FULLSCREEN_CAPTION ++ " fullscreen",
};
const STATUS_H: i32 = GAP * (@as(i32, CRIB_ALL.len) + 3) + TEXT * (@as(i32, CRIB_ALL.len) + 2);

/// What the editor asks of whatever runs it.
pub const Action = union(enum) { none, play: atlas.Start, leave, quit };

const View = enum { map, graph };
const Stroke = enum { none, paint, erase };
/// Asked for, and done once any unsaved changes are saved or let go.
const Pending = enum { leave, quit, open, new };
const Modal = enum { none, confirm, name, open };
const Naming = enum { new, save_as };

const Field = struct {
    buf: [FIELD_MAX]u8 = undefined,
    n: usize = 0,
    cap: usize = FIELD_MAX,

    fn text(f: *const Field) []const u8 {
        return f.buf[0..f.n];
    }

    fn set(f: *Field, s: []const u8, cap: usize) void {
        f.cap = cap;
        f.n = @min(s.len, cap);
        @memcpy(f.buf[0..f.n], s[0..f.n]);
    }

    fn feed(f: *Field, d: *const Desk) void {
        for (d.text()) |c| {
            if (f.n == f.cap) break;
            f.buf[f.n] = c;
            f.n += 1;
        }
        if (d.rub and f.n > 0) f.n -= 1;
    }
};

const Path = struct {
    buf: [PATH_MAX]u8 = undefined,
    n: usize = 0,

    fn text(p: *const Path) []const u8 {
        return p.buf[0..p.n];
    }

    fn set(p: *Path, s: []const u8) void {
        p.n = @min(s.len, PATH_MAX);
        @memcpy(p.buf[0..p.n], s[0..p.n]);
    }
};

const Drag = struct { node: usize, grab: P, from: P, moved: bool = false };
const Rect = struct { from: P, erase: bool };

pub const Editor = struct {
    alloc: std.mem.Allocator,
    world: *atlas.Atlas,
    /// The world as the gesture under way found it: banked on its first change.
    scratch: *atlas.Atlas,
    hist: *[UNDO_CAP]atlas.Atlas,
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
    thumb_lv: grid.Level = undefined,
    thumbs: [atlas.MAX_NODES]?rl.Texture2D = @splat(null),
    thumb_ok: std.StaticBitSet(atlas.MAX_NODES) = .initEmpty(),
    /// The link tool's first door.
    pick: ?atlas.Link = null,
    dirty: bool = false,
    stroke: Stroke = .none,
    rect: ?Rect = null,
    drag: ?Drag = null,
    modal: Modal = .none,
    /// A modal opened this frame takes no click until the next.
    fresh: bool = false,
    pending: Pending = .leave,
    pending_path: Path = .{},
    naming: Naming = .new,
    renaming: bool = false,
    field: Field = .{},
    listing: atlas.Listing = .{},
    /// Listed worlds scrolled off the top of the open modal.
    listed_top: usize = 0,
    desk: Desk = .{},
    action: Action = .none,
    tip: ?[:0]const u8 = null,
    said: [LINE]u8 = undefined,
    said_n: usize = 0,
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
        ed.file.set(p);
    }

    fn plan(ed: *Editor) *atlas.Plan {
        return &ed.world.node[ed.node].plan;
    }

    fn px(ed: *const Editor) f32 {
        return ZOOMS[ed.zoom];
    }

    fn brushSize(ed: *const Editor) i32 {
        return BRUSHES[ed.brush];
    }

    fn say(ed: *Editor, comptime fmt: []const u8, args: anytype) void {
        ed.said_n = (std.fmt.bufPrint(&ed.said, fmt, args) catch &ed.said).len;
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
            std.mem.copyForwards(atlas.Atlas, ed.hist[0 .. UNDO_CAP - 1], ed.hist[1..UNDO_CAP]);
            ed.hist_len -= 1;
            if (ed.saved_at) |s| ed.saved_at = if (s == 0) null else s - 1;
        }
        ed.hist[ed.hist_len] = ed.scratch.*;
        ed.hist_len += 1;
        ed.hist_at = ed.hist_len;
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
        ed.world.* = ed.hist[k];
        ed.hist[k] = ed.scratch.*;
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

    /// Lets go of whatever press is under way: a stroke, a rectangle, a box being dragged.
    fn drop(ed: *Editor) void {
        ed.stroke = .none;
        ed.rect = null;
        ed.drag = null;
    }

    fn setTool(ed: *Editor, t: Tool) void {
        if (t != ed.tool) ed.rect = null;
        ed.tool = t;
    }

    /// Onto a node there still is, after the world lost some.
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
        ed.world.node[ed.node].sketch(&ed.lv);
        ed.stale = false;
    }

    fn doorAt(ed: *Editor, p: P) ?usize {
        return ed.world.node[ed.node].doorAt(p);
    }

    /// Its number and name, marked when the world starts there.
    fn nodeTitle(ed: *Editor, n: usize, buf: []u8) [:0]const u8 {
        var name: [NAME_BUF]u8 = undefined;
        const mark: []const u8 = if (ed.world.start.node == n) &START_MARK else "";
        return std.fmt.bufPrintZ(buf, "{s}{d}  {s}", .{ mark, n, ed.nodeName(n, &name) }) catch "";
    }

    fn nodeName(ed: *Editor, n: usize, buf: []u8) []const u8 {
        const nd = &ed.world.node[n];
        if (nd.label_n > 0) return nd.name();
        return std.fmt.bufPrint(buf, "node {d}", .{n}) catch "node";
    }

    pub fn request(ed: *Editor, p: Pending) void {
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
        ed.world.save(ed.path()) catch |e| {
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
        var buf: [PATH_MAX]u8 = undefined;
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
                ed.pending_path.set(p);
                ed.request(.new);
            },
        }
    }

    fn startRename(ed: *Editor) void {
        ed.gesture();
        ed.field.set(ed.world.node[ed.node].name(), atlas.NAME_MAX);
        ed.renaming = true;
    }

    fn commitRename(ed: *Editor) void {
        ed.renaming = false;
        const nd = &ed.world.node[ed.node];
        if (std.mem.eql(u8, nd.name(), std.mem.trim(u8, ed.field.text(), " "))) return;
        if (!nd.rename(ed.field.text())) return ed.say("A name is {d} letters at most", .{atlas.NAME_MAX});
        ed.bank();
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
        ed.lookAt(c, .{ .x = @divTrunc(grid.W, 2), .y = @divTrunc(grid.H, 2) });
        ed.recentre = false;
    }
    step(ed, g, rl.getFrameTime());
    rl.beginDrawing();
    draw(ed, g);
    rl.endDrawing();
    ed.fresh = false;
    return ed.action;
}

fn step(ed: *Editor, g: *game.Game, dt: f32) void {
    const d = &ed.desk;
    ed.said_t -= dt;
    if (ed.modal != .none) return modalKeys(ed);
    if (ed.renaming) {
        ed.field.feed(d);
        if (d.back) {
            ed.renaming = false;
        } else if (d.enter or d.paint_hit or d.erase_hit) ed.commitRename();
        if (ed.renaming or !(d.paint_hit or d.erase_hit)) return;
    } else if (d.back) return escape(ed);
    const c = Editor.canvas(g);
    if (d.play) ed.action = .{ .play = ed.world.start };
    if (d.play_here) playHere(ed, c);
    if (d.save) _ = ed.save();
    if (d.save_as) ed.askName(.save_as);
    if (d.open) ed.askOpen();
    if (d.new) ed.askName(.new);
    if (d.undo) ed.undo();
    if (d.redo) ed.redo();
    if (d.graph) ed.view = if (ed.view == .map) .graph else .map;
    if (d.rename) ed.startRename();
    if (d.go) goThrough(ed, c);
    if (d.smaller) ed.brush -|= 1;
    if (d.bigger) ed.brush = @min(ed.brush + 1, BRUSHES.len - 1);
    if (d.tool) |i| ed.setTool(TOOLS[i]);
    if (ed.modal != .none) return;
    if (ed.view != .graph) ed.drag = null;
    if (ed.view != .map) ed.rect = null;
    if (d.paint_hit or d.erase_hit) ed.gesture();
    const over = rl.checkCollisionPointRec(vec(d.mouse), c);
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
    if (d.wheel != 0 and d.mouse.x < PANEL_W) scrollNodes(ed, if (d.wheel > 0) -1 else 1);
}

/// Esc backs out one step at a time, the last out of the editor.
fn escape(ed: *Editor) void {
    if (ed.rect != null) {
        ed.rect = null;
    } else if (ed.pick != null) {
        ed.pick = null;
        ed.say("Link cancelled", .{});
    } else if (ed.view == .graph) {
        ed.view = .map;
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

fn playHere(ed: *Editor, c: rl.Rectangle) void {
    const p = ed.cellAt(c, ed.desk.mouse);
    if (ed.view != .map or !grid.Level.inside(p) or !rl.checkCollisionPointRec(vec(ed.desk.mouse), c)) {
        return ed.say("{s} plays from the cell under the cursor on a map", .{Desk.PLAY_HERE_CAPTION});
    }
    ed.action = .{ .play = .{ .node = ed.node, .at = p } };
}

fn goThrough(ed: *Editor, c: rl.Rectangle) void {
    if (ed.view != .map) return;
    const k = ed.doorAt(ed.cellAt(c, ed.desk.mouse)) orelse return ed.say("{s} goes through the door under the cursor", .{Desk.GO_CAPTION});
    const to = ed.world.node[ed.node].door[k].to orelse return ed.say("Door {d} leads nowhere yet", .{k});
    ed.select(to.node);
    ed.recentre = false;
    ed.lookAt(c, ed.world.node[to.node].door[to.door].at);
    var buf: [NAME_BUF]u8 = undefined;
    ed.say("Through door {d} to {s}, door {d}", .{ k, ed.nodeName(to.node, &buf), to.door });
}

fn mapMouse(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const d = &ed.desk;
    const p = ed.cellAt(c, d.mouse);
    if (!d.paint and !d.erase) {
        if (ed.rect) |r| fillRect(ed, r, clampCell(p));
        ed.rect = null;
        ed.stroke = .none;
    }
    if (over and (d.paint_hit or d.erase_hit)) {
        ed.stroke = if (d.paint_hit) .paint else .erase;
        if (d.shift and ed.tool.broad() and ed.tool.fits(ed.plan()) and grid.Level.inside(p)) ed.rect = .{ .from = p, .erase = d.erase_hit };
    }
    if (ed.rect != null or !over or ed.stroke == .none or !grid.Level.inside(p)) return;
    const hit = if (ed.stroke == .paint) d.paint_hit else d.erase_hit;
    if (!hit and !ed.tool.strokes()) return;
    if (!ed.tool.fits(ed.plan())) {
        if (hit) ed.say("A procgen node's floor, torches, barrels and foes are generated; it takes doors, links and the start", .{});
        return;
    }
    if (!ed.tool.broad()) return apply(ed, p, ed.stroke == .erase);
    const box = brushBox(p, ed.brushSize());
    fillRect(ed, .{ .from = box.lo, .erase = ed.stroke == .erase }, box.hi);
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
    var y = @min(r.from.y, to.y);
    while (y <= @max(r.from.y, to.y)) : (y += 1) {
        var x = @min(r.from.x, to.x);
        while (x <= @max(r.from.x, to.x)) : (x += 1) {
            const p = P{ .x = x, .y = y };
            if (grid.Level.inside(p)) apply(ed, p, r.erase);
        }
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
    if (!dr.moved) {
        ed.select(dr.node);
        ed.view = .map;
    }
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
    switch (t) {
        .wall => {
            b.barrel[i] = false;
            if (b.foeAt(p)) |f| b.dropFoe(f);
        },
        .floor => if (b.torchAt(p)) |k| b.dropTorch(k),
    }
    ed.changed();
}

fn place(ed: *Editor, p: P) void {
    const i = grid.Level.idx(p);
    switch (ed.tool) {
        .floor => paintTile(ed, p, .floor),
        .wall => paintTile(ed, p, .wall),
        .barrel => {
            const b = &ed.plan().bespoke;
            if (b.barrel[i] or !ed.world.node[ed.node].barrelFits(b, p) or b.foeAt(p) != null) return;
            b.barrel[i] = true;
            ed.changed();
        },
        .torch => {
            const b = &ed.plan().bespoke;
            if (!ed.world.node[ed.node].torchFits(b, p)) return ed.say("A torch hangs on a wall with floor below it", .{});
            if (!b.addTorch(p)) return ed.say("That wall holds a torch, or the node holds {d}", .{grid.MAX_TORCHES});
            ed.changed();
        },
        .rat, .slime, .bloat => {
            const b = &ed.plan().bespoke;
            const k = ed.tool.foe().?;
            if (b.tile[i] != .floor or b.barrel[i] or ed.doorAt(p) != null) return ed.say("A foe stands on open floor", .{});
            if (b.foeAt(p)) |f| {
                if (b.foe[f].kind == k) return;
                b.foe[f].kind = k;
            } else if (!b.addFoe(.{ .kind = k, .at = p })) return ed.say("The node holds {d} foes", .{atlas.MAX_FOES});
            ed.changed();
        },
        .door => {
            const k = ed.world.addDoor(ed.node, p) orelse return ed.say("That cell is a door, or the node holds {d}", .{grid.MAX_DOORS});
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
            if (from.node == here.node and from.door == here.door) return ed.say("Link cancelled", .{});
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
        .floor => paintTile(ed, p, .wall),
        .wall => paintTile(ed, p, .floor),
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
            if (ed.world.node[ed.node].door[k].to == null) return;
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
}

/// Hot and clicked this frame. Under a modal only the modal's own are live, and not the frame it opened.
fn hot(ed: *Editor, r: rl.Rectangle, live: bool, modal: bool, tip: ?[:0]const u8) struct { hot: bool, hit: bool } {
    const on_layer = if (modal) !ed.fresh else ed.modal == .none;
    const h = live and on_layer and rl.checkCollisionPointRec(vec(ed.desk.mouse), r);
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

/// Under a row that is picked or hovered.
fn plate(r: rl.Rectangle, on: bool, hot_: bool) void {
    if (on or hot_) rl.drawRectangleRec(r, ROW_ON);
    if (on) rl.drawRectangleLinesEx(r, 1, look.SLOT_HELD);
}

fn row(x: i32, y: i32, w: i32) rl.Rectangle {
    return .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(ROW_H) };
}

/// `n` buttons across the panel, the `k`th.
fn cellOfRow(y: i32, k: usize, n: usize) rl.Rectangle {
    const ni: i32 = @intCast(n);
    const w = @divTrunc(INNER_W - GAP * (ni - 1), ni);
    return row(PAD + @as(i32, @intCast(k)) * (w + GAP), y, w);
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
    if (ed.modal != .none) drawModal(ed, g);
    drawStatus(ed, g, c);
}

/// File, then view, then tools, then node commands, then the node list, which scrolls.
fn drawPanel(ed: *Editor, g: *game.Game) void {
    var buf: [LINE]u8 = undefined;
    rl.drawRectangle(0, 0, PANEL_W, g.screen.y, PANEL_BG);
    rl.drawRectangle(PANEL_W - 1, 0, 1, g.screen.y, look.EDGE);
    var y = PAD;
    g.face.draw(std.fmt.bufPrintZ(&buf, "{s}{s}", .{ ed.path(), if (ed.dirty) " *" else "" }) catch "", PAD, y, TEXT, look.TEXT);
    y += HEAD + GAP;
    if (button(ed, g, cellOfRow(y, 0, 4), "New", false, true, "New world (" ++ Desk.NEW_CAPTION ++ ")")) ed.askName(.new);
    if (button(ed, g, cellOfRow(y, 1, 4), "Open", false, true, "Open a world (" ++ Desk.OPEN_CAPTION ++ ")")) ed.askOpen();
    if (button(ed, g, cellOfRow(y, 2, 4), "Save", false, true, "Save (" ++ Desk.SAVE_CAPTION ++ ")")) _ = ed.save();
    if (button(ed, g, cellOfRow(y, 3, 4), "Save as", false, true, "Save under a new name (" ++ Desk.SAVE_AS_CAPTION ++ ")")) ed.askName(.save_as);
    y += ROW_H + GAP;
    const other: [:0]const u8 = if (ed.view == .map) "Graph" else "Map";
    if (button(ed, g, cellOfRow(y, 0, 4), other, false, true, "The map of one node, or every node and how they link (" ++ Desk.GRAPH_CAPTION ++ ")")) {
        ed.view = if (ed.view == .map) .graph else .map;
    }
    if (button(ed, g, cellOfRow(y, 1, 4), "Undo", false, ed.hist_at > 0, "Undo (" ++ Desk.UNDO_CAPTION ++ ")")) ed.undo();
    if (button(ed, g, cellOfRow(y, 2, 4), "Play", false, true, "Play from the world start (" ++ Desk.PLAY_CAPTION ++ "); " ++ Desk.PLAY_CAPTION ++ " or " ++ Desk.PLAY_HERE_CAPTION ++ " comes back")) {
        ed.action = .{ .play = ed.world.start };
    }
    if (button(ed, g, cellOfRow(y, 3, 4), "Title", false, true, "Back to the title (" ++ Desk.BACK_CAPTION ++ ")")) ed.request(.leave);
    y += ROW_H + GAP * 3;
    const rows = (TOOLS.len + 1) / 2;
    for (TOOLS, Desk.TOOL_KEYS, 0..) |t, k, i| {
        const key = k.name;
        const n = ed.brushSize();
        const label = if (t.broad())
            std.fmt.bufPrintZ(&buf, "{s}  {s}  {d}x{d}", .{ key, t.name(), n, n }) catch ""
        else
            std.fmt.bufPrintZ(&buf, "{s}  {s}", .{ key, t.name() }) catch "";
        const r = cellOfRow(y + @as(i32, @intCast(i % rows)) * ROW_H, i / rows, 2);
        if (button(ed, g, r, label, t == ed.tool, t.fits(ed.plan()), t.tip())) ed.setTool(t);
    }
    y += @as(i32, @intCast(rows)) * ROW_H + GAP * 3;
    if (button(ed, g, cellOfRow(y, 0, 2), "+ Bespoke", false, true, "A node you paint yourself")) addNode(ed, .{ .bespoke = .{} });
    if (button(ed, g, cellOfRow(y, 1, 2), "+ Procgen", false, true, "A node the rooms generator rolls round its doors, anew each run")) {
        addNode(ed, .{ .procgen = .{} });
    }
    y += ROW_H + GAP;
    if (button(ed, g, cellOfRow(y, 0, 2), "Rename", false, true, "Name this node (" ++ Desk.RENAME_CAPTION ++ ")")) ed.startRename();
    if (button(ed, g, cellOfRow(y, 1, 2), "Delete", false, ed.world.node_n > 1, "Delete this node; its doors' links go with it")) deleteNode(ed);
    y += ROW_H + GAP * 3;
    rl.beginScissorMode(0, y, PANEL_W, @max(0, g.screen.y - y));
    defer rl.endScissorMode();
    var detail_buf: [LINE]u8 = undefined;
    for (ed.world.nodes()[ed.scroll..], ed.scroll..) |*nd, n| {
        if (y >= g.screen.y) break;
        const r = rl.Rectangle{ .x = @floatFromInt(PAD), .y = @floatFromInt(y), .width = @floatFromInt(INNER_W), .height = @floatFromInt(NODE_H - 2) };
        const on = n == ed.node;
        const h = hot(ed, r, true, false, "Open this node");
        plate(r, on, h.hot);
        const title = if (on and ed.renaming)
            std.fmt.bufPrintZ(&buf, "{d}  {s}_", .{ n, ed.field.text() }) catch ""
        else
            ed.nodeTitle(n, &buf);
        g.face.draw(title, PAD + GAP, y + 3, TEXT, if (on and ed.renaming) look.RETICLE else look.TEXT);
        g.face.draw(nodeDetail(nd, &detail_buf), PAD + GAP, y + 4 + TEXT, SMALL, if (nd.unlinked() > 0) WARN else look.DIM);
        if (h.hit) {
            ed.select(n);
            ed.view = .map;
        }
        y += NODE_H;
    }
}

fn drawStatus(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    var buf: [LINE + 1]u8 = undefined;
    const top = g.screen.y - STATUS_H;
    rl.drawRectangle(PANEL_W, top, g.screen.x - PANEL_W, STATUS_H, PANEL_BG);
    rl.drawRectangle(PANEL_W, top, g.screen.x - PANEL_W, 1, look.EDGE);
    const line = if (ed.said_t > 0)
        std.fmt.bufPrintZ(&buf, "{s}", .{ed.said[0..ed.said_n]}) catch ""
    else if (ed.tip) |t| t else hover(ed, c, &buf);
    var y = top + GAP;
    g.face.draw(line, PANEL_W + PAD, y, TEXT, look.TEXT);
    y += TEXT + GAP * 2;
    g.face.draw(if (ed.view == .map) CRIB_MAP else CRIB_GRAPH, PANEL_W + PAD, y, TEXT, look.DIM);
    for (CRIB_ALL) |crib| {
        y += TEXT + GAP;
        g.face.draw(crib, PANEL_W + PAD, y, TEXT, look.DIM);
    }
}

fn hover(ed: *Editor, c: rl.Rectangle, buf: []u8) [:0]const u8 {
    if (!rl.checkCollisionPointRec(vec(ed.desk.mouse), c)) return "";
    var a: [NAME_BUF]u8 = undefined;
    if (ed.view == .graph) {
        const n = ed.boxUnder(c, ed.desk.mouse) orelse return "";
        var d: [LINE]u8 = undefined;
        return std.fmt.bufPrintZ(buf, "{s} (node {d}): {s}", .{ ed.nodeName(n, &a), n, nodeDetail(&ed.world.node[n], &d) }) catch "";
    }
    const p = ed.cellAt(c, ed.desk.mouse);
    if (!grid.Level.inside(p)) return "";
    const nd = &ed.world.node[ed.node];
    const k = nd.doorAt(p) orelse
        return std.fmt.bufPrintZ(buf, "{d},{d}  {s}", .{ p.x, p.y, if (nd.plan == .procgen) "rolled each run" else @tagName(ed.lv.at(p)) }) catch "";
    const to = nd.door[k].to orelse
        return std.fmt.bufPrintZ(buf, "{d},{d}  door {d}, unlinked", .{ p.x, p.y, k }) catch "";
    return std.fmt.bufPrintZ(buf, "{d},{d}  door {d} leads to {s} (node {d}) door {d}; {s} goes through", .{ p.x, p.y, k, ed.nodeName(to.node, &a), to.node, to.door, Desk.GO_CAPTION }) catch "";
}

/// What it is generated by and how its doors stand.
fn nodeDetail(nd: *const atlas.Node, buf: []u8) [:0]const u8 {
    const kind = switch (nd.plan) {
        .bespoke => "bespoke",
        .procgen => |pg| @tagName(pg.algo),
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
    rl.beginScissorMode(@intFromFloat(c.x), @intFromFloat(c.y), @intFromFloat(c.width), @intFromFloat(c.height));
    defer rl.endScissorMode();
    const v = visible(ed, c);
    var y = v.lo.y;
    while (y < v.hi.y) : (y += 1) {
        var x = v.lo.x;
        while (x < v.hi.x) : (x += 1) {
            const p = P{ .x = x, .y = y };
            const r = ed.cellRect(c, p);
            if (ed.plan().* == .procgen) {
                rl.drawRectangleRec(r, look.UNROLLED);
            } else if (g.sprites.tileAt(&ed.lv, p)) |t| {
                sprite(t, r);
            } else {
                rl.drawRectangleRec(r, if (ed.lv.at(p) == .wall) look.ROCK else look.FLOOR_BG);
            }
            if (ed.lv.hasBarrel(p)) {
                if (g.sprites.barrel) |t| sprite(t, r) else glyph(ed, g, look.BARREL.ch, r, look.BARREL.fg);
            }
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
    for (ed.world.node[ed.node].doors(), 0..) |d, k| {
        const r = ed.cellRect(c, d.at);
        glyph(ed, g, look.DOOR.ch, r, if (d.to == null) UNLINKED else look.DOOR.fg);
        if (ed.px() >= LABEL_PX) {
            const size: i32 = @intFromFloat(ed.px() * LABEL_OF_CELL);
            g.face.text(std.fmt.bufPrintZ(&buf, "{d}", .{k}) catch "", @intFromFloat(r.x + 1), @intFromFloat(r.y), size, look.TEXT);
        }
        const pk = ed.pick orelse continue;
        if (pk.node == ed.node and pk.door == k) rl.drawRectangleLinesEx(r, 2, PICKED);
    }
    if (ed.world.start.node == ed.node) {
        const at = switch (ed.plan().*) {
            .bespoke => |*b| atlas.landing(&ed.lv, ed.world.start.at, b.foes()),
            .procgen => ed.world.start.at,
        };
        if (at) |s| glyph(ed, g, START.ch, ed.cellRect(c, s), START.fg);
    }
    const m = ed.cellAt(c, ed.desk.mouse);
    if (ed.rect) |r| {
        outlineCells(ed, c, r.from, clampCell(m), PICKED);
    } else if (grid.Level.inside(m)) {
        const box = brushBox(m, if (ed.tool.broad() and ed.tool.fits(ed.plan())) ed.brushSize() else 1);
        outlineCells(ed, c, box.lo, box.hi, HOVER);
    }
}

fn outlineCells(ed: *const Editor, c: rl.Rectangle, a: P, b: P, col: rl.Color) void {
    const lo = ed.cellRect(c, .{ .x = @min(a.x, b.x), .y = @min(a.y, b.y) });
    const hi = ed.cellRect(c, .{ .x = @max(a.x, b.x), .y = @max(a.y, b.y) });
    rl.drawRectangleLinesEx(.{ .x = lo.x, .y = lo.y, .width = hi.x + hi.width - lo.x, .height = hi.y + hi.height - lo.y }, 1, col);
}

fn drawGraph(ed: *Editor, g: *game.Game, c: rl.Rectangle) void {
    rl.beginScissorMode(@intFromFloat(c.x), @intFromFloat(c.y), @intFromFloat(c.width), @intFromFloat(c.height));
    defer rl.endScissorMode();
    var buf: [LINE]u8 = undefined;
    for (0..ed.world.node_n) |n| {
        const b = ed.boxAt(c, n);
        rl.drawRectangleRec(b, PANEL_BG);
        if (thumb(ed, n)) |t| sprite(t, .{ .x = b.x, .y = b.y + @as(f32, @floatFromInt(BOX_TOP)), .width = @floatFromInt(BOX_W), .height = @floatFromInt(BOX_H - BOX_TOP) });
        g.face.draw(ed.nodeTitle(n, &buf), @as(i32, @intFromFloat(b.x)) + GAP, @as(i32, @intFromFloat(b.y)) + 3, TEXT, look.TEXT);
        rl.drawRectangleLinesEx(b, 1, if (n == ed.node) look.SLOT_HELD else look.EDGE);
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
        const unrolled = ed.world.node[n].plan == .procgen;
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
    rl.drawRectangle(0, 0, g.screen.x, g.screen.y, VEIL);
    const lines: i32 = switch (ed.modal) {
        .open => @intCast(@max(1, @min(ed.listing.n, MODAL_ROWS))),
        .confirm, .name, .none => 2,
    };
    const h = PAD * 4 + HEAD + lines * ROW_H + ROW_H + GAP * 2;
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
    const bx = x + MODAL_W - PAD - MODAL_BTN_W;
    switch (ed.modal) {
        .confirm => {
            g.face.draw(std.fmt.bufPrintZ(&buf, "{s} has changes that are not saved.", .{ed.path()}) catch "", x + PAD, y, TEXT, look.TEXT);
            y += ROW_H * 2 + PAD;
            if (buttonOn(ed, g, modalButton(bx, y, 2), "Save (" ++ Desk.ENTER_CAPTION ++ ")", false, true, true, null) and ed.save()) ed.commit();
            if (buttonOn(ed, g, modalButton(bx, y, 1), "Discard", false, true, true, null)) ed.commit();
            cancelButton(ed, g, bx, y);
        },
        .name => {
            const f = row(x + PAD, y, MODAL_W - PAD * 2);
            rl.drawRectangleRec(f, ROW_ON);
            g.face.draw(std.fmt.bufPrintZ(&buf, "{s}_", .{ed.field.text()}) catch "", x + PAD + GAP, y + @divTrunc(ROW_H - TEXT, 2), TEXT, look.RETICLE);
            y += ROW_H + GAP;
            var pbuf: [PATH_MAX]u8 = undefined;
            const note = if (atlas.pathFor(&pbuf, ed.field.text())) |p| std.fmt.bufPrintZ(&buf, "Makes {s}", .{p}) catch "" else "Type a name";
            g.face.draw(note, x + PAD, y, SMALL, look.DIM);
            y += ROW_H + PAD;
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
                    ed.pending_path.set(p);
                    ed.modal = .none;
                    ed.request(.open);
                    return;
                }
                y += ROW_H;
            }
            y += PAD;
            cancelButton(ed, g, bx, y);
        },
        .none => {},
    }
}

/// The `k`th of a modal's buttons leftward from the one at `bx`.
fn modalButton(bx: i32, y: i32, k: i32) rl.Rectangle {
    return row(bx - (MODAL_BTN_W + GAP) * k, y, MODAL_BTN_W);
}

fn cancelButton(ed: *Editor, g: *game.Game, bx: i32, y: i32) void {
    if (buttonOn(ed, g, modalButton(bx, y, 0), "Cancel (" ++ Desk.BACK_CAPTION ++ ")", false, true, true, null)) ed.modal = .none;
}

fn sprite(t: rl.Texture2D, r: rl.Rectangle) void {
    look.stretch(t, r, rl.Color.white);
}

fn glyph(ed: *const Editor, g: *game.Game, ch: u8, r: rl.Rectangle, col: rl.Color) void {
    const half = ed.px() * 0.5;
    g.face.glyph(ch, @intFromFloat(r.x + half), @intFromFloat(r.y + half), @intFromFloat(ed.px() * GLYPH_OF_CELL), col);
}

/// DEV ONLY: a bespoke room linked to a procgen node, the link tool mid-pick; then the same world as a graph.
pub fn shoot(g: *game.Game, target: rl.RenderTexture2D, map_path: [:0]const u8, graph_path: [:0]const u8) void {
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
}

fn testEditor() !*Editor {
    const ed = try Editor.create(std.testing.allocator);
    ed.world.* = .{};
    ed.setPath(atlas.worldPath("test_editor"));
    return ed;
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
    try std.testing.expect(!Tool.floor.fits(&w.node[1].plan));
    try std.testing.expect(Tool.door.fits(&w.node[1].plan));
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
