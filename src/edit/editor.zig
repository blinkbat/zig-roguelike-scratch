const sprite_assets = @import("../gfx/sprite_assets.zig");
const tool_catalog = @import("tool_catalog.zig");
const name_field = @import("name_field.zig");
pub const kindName = tool_catalog.kindName;
pub const Tool = tool_catalog.Tool;
pub const TOOLS = tool_catalog.TOOLS;
pub const PALETTE_RULE = tool_catalog.PALETTE_RULE;
pub const GENERATED = tool_catalog.GENERATED;
pub const Shape = tool_catalog.Shape;
pub const SHAPES = tool_catalog.SHAPES;
pub const CRIB_MAP = tool_catalog.CRIB_MAP;
pub const CRIB_GRAPH = tool_catalog.CRIB_GRAPH;
pub const HELP = tool_catalog.HELP;
pub const HELP_COLUMNS = tool_catalog.HELP_COLUMNS;
pub const HELP_ROWS = tool_catalog.HELP_ROWS;
const START_MARK = tool_catalog.START_MARK;
const placement = @import("placement.zig");
const interaction = @import("interaction.zig");
const widgets = @import("widgets.zig");
const history = @import("history.zig");
const previews = @import("preview.zig");
const thumbnails = @import("thumbnails.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const listing = @import("../map/listing.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");
const knobs = @import("knobs.zig");
const canvas = @import("canvas.zig");
const modals = @import("modals.zig");
const panel = @import("panel.zig");
const text_panel = @import("text_panel.zig");
pub const plot = @import("plot.zig");
const effects_view = @import("effects.zig");

const P = mathx.P;
const Desk = input.Desk;

const NODE_H: i32 = 60;
pub const ZOOMS = [_]f32{ 8, 16, 32, 64 };
const ZOOM_AT = zoomOf(16);
pub const BRUSHES = [_]i32{ 1, 2, 3, 5 };

fn zoomOf(px: f32) usize {
    return std.mem.indexOfScalar(f32, &ZOOMS, px).?;
}

const SAY_S: f32 = 4;
const FLASH_S: f32 = 1.2;
pub const UNDO_CAP = history.CAPACITY;
const PATH_FIELD_MAX: usize = 256;
const FIELD_MAX: usize = 32;
const THUMB: i32 = 2;
pub const BOX_W: i32 = grid.W * THUMB;
pub const BOX_TOP: i32 = widgets.TEXT + 2 * TITLE_DY;
pub const BOX_H: i32 = BOX_TOP + grid.H * THUMB;
pub const DOT_R: f32 = 4;
/// Pixels past a door's dot a press still takes it.
pub const DOT_SLOP: f32 = 3;
pub const LABEL_W: i32 = 126;
pub const STATUS_H: i32 = widgets.GAP + 2 * widgets.LINE_STEP;
pub const TITLE_DY: i32 = 3;
const NODE_GAP: i32 = 2;
pub const NODE_DETAIL_DY: i32 = widgets.TEXT + 1;

comptime {
    std.debug.assert(atlas.GRAPH_STEP.x > BOX_W and atlas.GRAPH_STEP.y > BOX_H);
    std.debug.assert(FIELD_MAX >= atlas.NAME_MAX and FIELD_MAX <= listing.STEM_MAX);
    std.debug.assert(PATH_FIELD_MAX >= listing.PATH_MAX);
}

pub const Action = union(enum) { none, play: atlas.Start, fight: actor.Kind, playground, leave, quit };

pub const View = enum {
    map,
    graph,

    pub fn other(v: View) View {
        return if (v == .map) .graph else .map;
    }
};
/// The brush panel down the left.
pub const SIDE = widgets.Column{ .x = 0, .w = widgets.SIDE_W };
pub const Family = tool_catalog.Family;
pub const FAMILIES = tool_catalog.FAMILIES;
/// The tabs of the node's panel.
pub const Inspect = enum {
    things,
    generator,
};
/// The two scrolled panels either side of the canvas.
pub const Pane = enum { side, inspector };
pub const Band = struct { top: i32, bottom: i32 };
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
/// A framed question with its buttons along the foot.
pub const Prompt = enum { confirm, name, open };
pub const Modal = union(enum) { none, prompt: Prompt, help, objects, effects, text, plot: plot.Page };
const Naming = enum { new, save_as };

const Field = name_field.Text(FIELD_MAX);
const Path = name_field.Text(PATH_FIELD_MAX);

const Drag = struct { node: usize, grab: P, from: P, moved: bool = false };

pub const Seen = union(enum) {
    tile: grid.Tile,
    body: actor.Kind,
    barrel,
    torch,
    door,
    folk,
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
pub const Which = union(enum) { algo, feature: usize, node, file };
pub const CellAction = enum { play, go };
pub const CELL_ACTIONS = std.EnumArray(CellAction, struct { label: [:0]const u8, tip: [:0]const u8, armed: []const u8 }).init(.{
    .play = .{ .label = "Play here", .tip = "Choose a cell to play from", .armed = "a cell to play there" },
    .go = .{ .label = "Go through", .tip = "Choose a linked door to follow", .armed = "a linked door to go through" },
});

pub const Editor = struct {
    pub fn controls(ed: *Editor) widgets.Controls {
        return .{
            .pointer = ed.desk.mouse,
            .pressed = ed.desk.paint_hit,
            .accepting = !ed.fresh and ed.action == .none,
            .covered = ed.modal != .none or ed.popup != null,
            .clip = ed.clip,
            .tip = &ed.tip,
        };
    }

    alloc: std.mem.Allocator,
    map: *atlas.Atlas,
    history: history.History,
    file: Path = .{},
    node: usize = 0,
    tool: Tool = .paint,
    ink: std.EnumArray(Ink, grid.Tile) = .init(.{ .first = .floor, .second = .wall }),
    shape: Shape = .brush,
    brush: usize = 0,
    view: View = .map,
    family: Family = .terrain,
    /// The tool each tab last held, taken up again when it is opened.
    family_tool: std.EnumArray(Family, Tool) = blk: {
        var tools = std.EnumArray(Family, Tool).initUndefined();
        for (FAMILIES) |f| tools.set(f, f.first());
        break :blk tools;
    },
    /// Of the foes tab, the one type it lists; null lists every foe.
    foe_type: ?actor.FoeType = null,
    inspect: Inspect = .things,
    /// Each panel's scrolled area as last drawn, its scrolled pixels and how far it scrolls.
    pane: std.EnumArray(Pane, widgets.Scrolled) = .initFill(.{}),
    /// The node dropdown's first row shown.
    popup_top: usize = 0,
    /// Set while a scrolled area is drawn: nothing outside it is hot.
    clip: ?rl.Rectangle = null,
    /// The map's top-left, in cells.
    cam: [2]f32 = .{ 0, 0 },
    zoom: usize = ZOOM_AT,
    recentre: bool = true,
    /// The graph's top-left, in graph pixels.
    gcam: [2]f32 = .{ -widgets.PAD, -widgets.PAD },
    scene: previews.Scene = .{},
    thumbnails: thumbnails.Thumbnails = .{},
    selection: ?grid.Box = null,
    board: placement.Board = .{},
    /// The paste laid aside for its ghost.
    trial: atlas.Bespoke = undefined,
    paste_preview: placement.PastePreview = .{},
    pasting: bool = false,
    cell_action: ?CellAction = null,
    linking: ?atlas.Link = null,
    delete_armed: ?usize = null,
    popup: ?Popup = null,
    seen_at: usize = 0,
    /// A cell the Things list jumped to, lit a moment.
    flash: ?P = null,
    flash_t: f32 = 0,
    pick: ?atlas.Link = null,
    stroke: Stroke = .none,
    stroke_at: ?P = null,
    span: ?placement.Span = null,
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
    words: text_panel.State = .{},
    plot: plot.State = .{},
    /// Made the first time the effects viewer opens.
    effects: ?*effects_view.Viewer = null,
    listing: listing.Listing = .{},
    listed_top: usize = 0,
    listed_at: usize = 0,
    desk: Desk = .{},
    action: Action = .none,
    tip: ?[:0]const u8 = null,
    said: menu.Note(widgets.LINE) = .{},
    said_t: f32 = 0,

    pub fn create(alloc: std.mem.Allocator) !*Editor {
        const w = try alloc.create(atlas.Atlas);
        errdefer alloc.destroy(w);
        const s = try alloc.create(atlas.Atlas);
        errdefer alloc.destroy(s);
        const h = try alloc.create([UNDO_CAP]atlas.Atlas);
        errdefer alloc.destroy(h);
        const ed = try alloc.create(Editor);
        ed.* = .{ .alloc = alloc, .map = w, .history = .{ .transaction = .{ .before = s }, .states = h } };
        freshMap(w);
        return ed;
    }

    /// Needs the GL context that drew its thumbnails.
    pub fn destroy(ed: *Editor) void {
        ed.words.deinit(ed.alloc);
        ed.thumbnails.deinit();
        const alloc = ed.alloc;
        if (ed.effects) |v| alloc.destroy(v);
        alloc.destroy(ed.history.states);
        alloc.destroy(ed.history.transaction.before);
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
        ed.history.transaction.before.load(ed.alloc, p) catch |e| {
            if (e != error.FileNotFound) {
                ed.history.transaction.before.* = ed.map.*;
                return e;
            }
            freshMap(ed.history.transaction.before);
            fresh = true;
        };
        ed.map.* = ed.history.transaction.before.*;
        ed.setPath(p);
        ed.settle();
        ed.say("{s} {s}", .{ if (fresh) "New map; it saves to" else "Opened", p });
    }

    fn settle(ed: *Editor) void {
        ed.history.reset();
        ed.node = 0;
        ed.dropHeld();
        ed.modal = .none;
        ed.view = .map;
        ed.recentre = true;
        ed.pane.getPtr(.inspector).top = 0;
        ed.scene.reset();
        ed.fitTool();
        ed.restamp();
    }

    /// With '/' between folders, as `listing.Listing` writes its paths.
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

    pub fn say(ed: *Editor, comptime fmt: []const u8, args: anytype) void {
        ed.said.say(fmt, args);
        ed.said_t = SAY_S;
    }

    pub fn gesture(ed: *Editor) void {
        ed.history.begin(ed.map);
    }

    pub fn bank(ed: *Editor) void {
        ed.history.record();
    }

    pub fn changed(ed: *Editor) void {
        if (ed.map.pruneFolk(ed.node)) ed.say("Folk that no longer had open floor to stand on went", .{});
        ed.bank();
        ed.stale();
        ed.thumbnails.invalidate(ed.node);
    }

    fn stale(ed: *Editor) void {
        ed.scene.invalidate();
        ed.paste_preview.ready = false;
    }

    pub fn relinked(ed: *Editor) void {
        ed.bank();
        ed.scene.relinked(ed.here());
    }

    fn restamp(ed: *Editor) void {
        ed.stale();
        ed.thumbnails.invalidateAll();
    }

    fn dropHeld(ed: *Editor) void {
        ed.release();
        ed.forgetNode();
        ed.renaming = false;
    }

    fn changedHistory(ed: *Editor) void {
        ed.clampSelection();
        ed.restampSwapped();
    }

    fn restampSwapped(ed: *Editor) void {
        ed.stale();
        ed.thumbnails.changedMap(ed.map, ed.history.transaction.before);
    }

    pub fn undo(ed: *Editor) void {
        ed.keepDrag();
        if (ed.history.at == 0) return ed.say("Nothing to undo", .{});
        ed.dropHeld();
        _ = ed.history.undo(ed.map);
        ed.changedHistory();
        ed.say("Undone ({d} more)", .{ed.history.at});
    }

    pub fn redo(ed: *Editor) void {
        if (ed.history.at < ed.history.len) ed.drop() else ed.keepDrag();
        if (ed.history.at == ed.history.len) return ed.say("Nothing to redo", .{});
        ed.dropHeld();
        _ = ed.history.redo(ed.map);
        ed.changedHistory();
        ed.say("Redone ({d} more)", .{ed.history.len - ed.history.at});
    }

    pub fn keepDrag(ed: *Editor) void {
        if (ed.drag == null) return;
        ed.history.commitPreview();
        ed.drag = null;
    }

    pub fn holding(ed: *const Editor) bool {
        return ed.cell_action != null or ed.popup != null or ed.span != null or ed.stroke != .none or ed.drag != null or ed.linking != null;
    }

    pub fn drop(ed: *Editor) void {
        ed.letGo();
        ed.cell_action = null;
        if (ed.drag != null) ed.history.cancelPreview(ed.map);
        ed.drag = null;
        ed.linking = null;
        ed.popup = null;
        ed.delete_armed = null;
    }

    pub fn release(ed: *Editor) void {
        ed.drop();
        ed.pick = null;
        ed.pasting = false;
    }

    pub fn setTool(ed: *Editor, t: Tool) void {
        if (!t.fits(ed.here())) return ed.say(GENERATED, .{});
        if (!t.eql(ed.tool)) ed.release();
        if (t == .foe and !ed.foeShown(t.foe)) ed.foe_type = null;
        ed.hold(t);
    }

    pub fn takeTool(ed: *Editor, t: Tool) void {
        ed.leaveSelect();
        ed.setTool(t);
    }

    fn hold(ed: *Editor, t: Tool) void {
        ed.tool = t;
        ed.showFamily(t.family());
        ed.family_tool.set(t.family(), t);
    }

    /// Whether the foes tab lists it under the type it narrows to.
    pub fn foeShown(ed: *const Editor, k: actor.Kind) bool {
        const want = ed.foe_type orelse return true;
        return actor.row(k).foe_type == want;
    }

    /// Its tab in the brush panel, taking up the tool it last held where that fits.
    pub fn openFamily(ed: *Editor, f: Family) void {
        ed.showFamily(f);
        const t = ed.family_tool.get(f);
        if (t.fits(ed.here())) ed.setTool(t);
    }

    fn showFamily(ed: *Editor, f: Family) void {
        if (f != ed.family) ed.pane.getPtr(.side).top = 0;
        ed.family = f;
    }

    pub fn setInspect(ed: *Editor, i: Inspect) void {
        if (i == .generator and ed.rolled() == null) return;
        if (i != ed.inspect) ed.pane.getPtr(.inspector).top = 0;
        ed.inspect = i;
        ed.delete_armed = null;
    }

    pub fn setShape(ed: *Editor, s: Shape) void {
        if (s != ed.shape) ed.release();
        ed.shape = s;
        if (s != .select and !ed.tool.broad() and ed.paintable()) ed.setTool(.paint);
    }

    /// Leaving Select keeps the tool it was taken up with.
    pub fn toggleSelect(ed: *Editor) void {
        if (ed.shape != .select) return ed.setShape(.select);
        ed.leaveSelect();
    }

    pub fn leaveSelect(ed: *Editor) void {
        if (ed.shape != .select) return;
        ed.release();
        ed.shape = .brush;
    }

    pub fn setView(ed: *Editor, v: View) void {
        if (v != ed.view) ed.drop();
        ed.view = v;
    }

    fn clampSelection(ed: *Editor) void {
        ed.node = @min(ed.node, ed.map.node_n - 1);
        ed.fitTool();
    }

    fn fitTool(ed: *Editor) void {
        if (!ed.tool.fits(ed.here())) ed.hold(.door);
        if (ed.inspect == .generator and ed.rolled() == null) ed.inspect = .things;
    }

    /// Preserve paste across node selection; cancel pending links and gestures.
    pub fn select(ed: *Editor, n: usize) void {
        if (ed.renaming) ed.commitRename();
        ed.drop();
        ed.node = n;
        ed.scene.invalidate();
        ed.recentre = true;
        ed.pane.getPtr(.inspector).top = 0;
        ed.forgetNode();
        ed.fitTool();
    }

    fn forgetNode(ed: *Editor) void {
        ed.selection = null;
        ed.delete_armed = null;
    }

    pub fn preview(ed: *Editor) void {
        ed.scene.ensure(ed.map, ed.node);
    }

    pub fn arrival(ed: *const Editor) P {
        return previews.arrival(ed.map, ed.node);
    }

    pub fn standable(ed: *Editor, from: atlas.Start) bool {
        return ed.thumbnails.standable(ed.map, from);
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
        return ed.plan().procgenOf();
    }

    pub fn painted(ed: *Editor) ?*atlas.Bespoke {
        return ed.plan().bespokeOf();
    }

    pub fn goTo(ed: *Editor, n: usize) void {
        ed.select(n);
        ed.setView(.map);
    }

    /// Node `n`'s map, looking at `p` rather than refitted.
    pub fn visit(ed: *Editor, c: rl.Rectangle, n: usize, p: P) void {
        ed.goTo(n);
        ed.recentre = false;
        ed.lookAt(c, p);
    }

    /// This node's map, looking at `p` and lighting it a moment.
    pub fn showCell(ed: *Editor, c: rl.Rectangle, p: P) void {
        ed.setView(.map);
        ed.lookAt(c, p);
        ed.flash = p;
        ed.flash_t = FLASH_S;
    }

    pub fn request(ed: *Editor, p: Pending) void {
        ed.keepDrag();
        if (ed.renaming) ed.commitRename();
        ed.pending = p;
        if (!ed.history.dirty) return ed.commit();
        ed.ask(.{ .prompt = .confirm });
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
        ed.history.markSaved();
        ed.say("Saved {s}", .{ed.path()});
        return true;
    }

    pub fn ask(ed: *Editor, m: Modal) void {
        ed.keepDrag();
        ed.drop();
        ed.modal = m;
        ed.fresh = true;
    }

    pub fn askName(ed: *Editor, n: Naming) void {
        ed.naming = n;
        ed.field.put("");
        ed.ask(.{ .prompt = .name });
    }

    pub fn askOpen(ed: *Editor) void {
        ed.listing.scanAt(listing.folderOf(ed.path()));
        ed.showListing();
        ed.ask(.{ .prompt = .open });
    }

    pub fn showListing(ed: *Editor) void {
        ed.listed_top = 0;
        ed.listed_at = 0;
        for (0..ed.listing.n) |i| {
            if (!std.mem.eql(u8, ed.listing.at(i), ed.path())) continue;
            ed.listed_at = i;
            ed.listed_top = mathx.reveal(0, i, widgets.MODAL_ROWS);
        }
    }

    pub fn openListed(ed: *Editor, i: usize) void {
        if (ed.listing.open(i)) return ed.showListing();
        ed.pending_path.put(ed.listing.at(i));
        ed.modal = .none;
        ed.request(.open);
    }

    pub fn namedPath(ed: *const Editor, buf: []u8) ?[]const u8 {
        return listing.pathFor(buf, listing.folderOf(ed.path()), ed.field.text());
    }

    pub fn named(ed: *Editor) void {
        var buf: [listing.PATH_MAX]u8 = undefined;
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
        ed.keepDrag();
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
        return canvasOf(g.screen);
    }

    /// Between the brush panel and the node's, under the bar and over the status line.
    pub fn canvasOf(screen: P) rl.Rectangle {
        const left = SIDE.x + SIDE.w;
        const band = bandOf(screen);
        return raster.rect(left, band.top, @max(0, inspectorOf(screen).x - left), @max(0, band.bottom - band.top));
    }

    /// Under the bar and over the status line, where the panels and canvas stand.
    pub fn bandOf(screen: P) Band {
        return .{ .top = widgets.TOP_H, .bottom = screen.y - STATUS_H };
    }

    pub fn inspector(g: *const game.Game) widgets.Column {
        return inspectorOf(g.screen);
    }

    fn inspectorOf(screen: P) widgets.Column {
        return .{ .x = screen.x - widgets.INSPECT_W, .w = widgets.INSPECT_W };
    }

    pub fn paneScroll(ed: *Editor, p: Pane, box: rl.Rectangle) widgets.Scroll {
        return ed.pane.getPtr(p).at(box);
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

    pub fn putAwayPaste(ed: *Editor) void {
        ed.pasting = false;
        ed.say("Paste put away", .{});
    }

    pub fn letGo(ed: *Editor) void {
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
        return raster.holds(r, ed.desk.mouse);
    }

    pub fn cellRect(ed: *const Editor, c: rl.Rectangle, p: P) rl.Rectangle {
        return widgets.cellRect(ed.origin(c), p, ed.px());
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
            if (raster.holds(ed.boxAt(c, n), m)) return n;
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

const vec = raster.vec;

/// Caller updates `desk` and `g.screen` first; `closing` is the window close request.
pub fn frame(ed: *Editor, g: *game.Game, closing: bool) Action {
    ed.action = .none;
    if (closing) {
        if (ed.modal == .text) text_panel.requestClose(ed, true) else ed.request(.quit);
    }
    const c = Editor.canvas(g);
    if (ed.recentre) {
        ed.preview();
        interaction.fitView(ed, c);
        ed.recentre = false;
    }
    interaction.step(ed, c, g.screen.y, rl.getFrameTime());
    if (ed.modal == .effects) if (ed.effects) |v| v.step(rl.getFrameTime());
    prepare(ed, g);
    rl.beginDrawing();
    draw(ed, g);
    rl.endDrawing();
    ed.fresh = false;
    ed.renamed = false;
    if (ed.action == .play) launch(ed);
    return ed.action;
}

pub fn launch(ed: *Editor) void {
    for ([_]atlas.Start{ ed.action.play, ed.map.start }) |from| {
        if (ed.standable(from)) continue;
        var buf: [atlas.TITLE_MAX]u8 = undefined;
        ed.say(atlas.NO_FLOOR, .{ed.nodeName(from.node, &buf)});
        ed.action = .none;
        return;
    }
    ed.keepDrag();
    ed.drop();
}

pub fn reroll(ed: *Editor) void {
    if (!ed.here().unrolled()) return ed.say("{s} rolls a procgen node's preview again; this one is painted", .{Desk.REROLL_CAPTION});
    ed.scene.reroll();
    ed.restamp();
    ed.say("Rolled again: in play it is rolled afresh each run", .{});
}

pub fn deleteNode(ed: *Editor) void {
    ed.map.remove(ed.node);
    ed.dropHeld();
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

pub fn button(ed: *Editor, g: *const game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return widgets.button(ed.controls(), &g.face, r, label, on, live, tip);
}

pub fn modalButton(ed: *Editor, g: *const game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return widgets.modalButton(ed.controls(), &g.face, r, label, on, live, tip);
}

fn prepare(ed: *Editor, g: *game.Game) void {
    ed.preview();
    if (g.art == .editor) return;
    g.light.clearFigures();
    g.sprites.sync(sprite_assets.Assets.everything());
    g.art = .editor;
}

fn draw(ed: *Editor, g: *game.Game) void {
    rl.clearBackground(look.BG);
    ed.tip = null;
    const c = Editor.canvas(g);
    switch (ed.view) {
        .map => canvas.drawMap(ed, g, c),
        .graph => canvas.drawGraph(ed, g, c),
    }
    panel.drawTop(ed, g);
    panel.drawSide(ed, g);
    panel.drawInspector(ed, g);
    panel.drawStatus(ed, g, c);
    if (ed.popup != null) drawPopup(ed, g);
    if (ed.modal != .none) modals.drawModal(ed, g);
    drawTip(ed, g);
}

const POPUP_W: f32 = 200;
const FILE_MENU_W: f32 = 340;
const TIP_DX: i32 = 16;
const TIP_DY: i32 = 20;
const TIP_MAX_W: i32 = 520;

fn popupLen(ed: *const Editor, w: Which) usize {
    return switch (w) {
        .algo => std.enums.values(atlas.Algo).len,
        .feature => std.enums.values(atlas.Kind).len,
        .node => ed.map.node_n,
        .file => panel.FILE_ITEMS.len,
    };
}

pub fn popupRowH(w: Which) i32 {
    return switch (w) {
        .algo, .feature, .file => widgets.ROW_H,
        .node => NODE_H,
    };
}

/// Row `k` of `which`'s list in `box`.
pub fn popupRow(box: rl.Rectangle, which: Which, k: usize) rl.Rectangle {
    const h = popupRowH(which);
    const inset: i32 = switch (which) {
        .node => NODE_GAP,
        .algo, .feature, .file => 0,
    };
    return raster.rect(@intFromFloat(box.x), @as(i32, @intFromFloat(box.y)) + @as(i32, @intCast(k)) * h, @intFromFloat(box.width), h - inset);
}

fn popupW(w: Which) f32 {
    return switch (w) {
        .algo, .feature, .node => POPUP_W,
        .file => FILE_MENU_W,
    };
}

/// Of its rows, how many fit the screen at once; the wheel scrolls the rest.
pub fn popupShown(ed: *const Editor, w: Which, screen_h: i32) usize {
    const fit: usize = @intCast(@max(1, @divTrunc(screen_h - 2 * widgets.PAD, popupRowH(w))));
    return @min(popupLen(ed, w), fit);
}

pub fn popupRect(ed: *const Editor, p: Popup, screen_h: i32) rl.Rectangle {
    const h: f32 = @floatFromInt(@as(i32, @intCast(popupShown(ed, p.which, screen_h))) * popupRowH(p.which));
    const below = p.slot.y + p.slot.height;
    const sh: f32 = @floatFromInt(screen_h);
    return .{ .x = p.slot.x, .y = if (below + h > sh) @max(0, sh - h) else below, .width = @max(p.slot.width, popupW(p.which)), .height = h };
}

/// Drops `which`'s list below `slot`, its chosen row in view.
pub fn openPopup(ed: *Editor, slot: rl.Rectangle, which: Which, chosen: usize, screen_h: i32) void {
    ed.drop();
    ed.popup = .{ .slot = slot, .which = which };
    ed.popup_top = mathx.reveal(0, chosen, popupShown(ed, which, screen_h));
    ed.fresh = true;
}

fn drawPopup(ed: *Editor, g: *game.Game) void {
    const p = ed.popup.?;
    const box = popupRect(ed, p, g.screen.y);
    const y: i32 = @intFromFloat(box.y);
    const x: i32 = @intFromFloat(box.x);
    const w: i32 = @intFromFloat(box.width);
    widgets.framed(x, y, w, @intFromFloat(box.height));
    switch (p.which) {
        .file => panel.fileRows(ed, g, box),
        .node => {
            const shown = popupShown(ed, .node, g.screen.y);
            ed.popup_top = widgets.clampTop(ed.popup_top, ed.map.node_n, shown);
            for (ed.popup_top..ed.popup_top + shown, 0..) |n, k| {
                if (panel.nodeRow(ed, g, popupRow(box, .node, k), n, true)) {
                    ed.popup = null;
                    if (n == ed.node) ed.setView(.map) else ed.goTo(n);
                }
            }
            widgets.scrollbarIn(box, ed.popup_top, shown, ed.map.node_n);
        },
        .algo, .feature => knobs.choiceRows(ed, g, box, p.which),
    }
}

fn drawTip(ed: *const Editor, g: *game.Game) void {
    const tip = ed.tip orelse return;
    var fit_buf: [widgets.LINE]u8 = undefined;
    const s = widgets.textFace(&g.face).fit(&fit_buf, tip, widgets.DETAIL, TIP_MAX_W, false);
    const size = widgets.tagSize(&g.face, s, widgets.GAPS);
    const x = std.math.clamp(ed.desk.mouse.x + TIP_DX, 0, @max(0, g.screen.x - size.x));
    const y = if (ed.desk.mouse.y + TIP_DY + size.y > g.screen.y) ed.desk.mouse.y - TIP_DY - size.y else ed.desk.mouse.y + TIP_DY;
    widgets.drawTag(&g.face, s, .{ .x = x, .y = y }, widgets.GAPS, widgets.PANEL_BG, look.EDGE);
}

const SHOT_ZOOM = zoomOf(32);
const SHOT_BRUSH = std.mem.indexOfScalar(i32, &BRUSHES, 3).?;

/// DEV ONLY: the posed map's map mid link-pick, its graph, its procgen node's generator and the object viewer at those paths; its other panels, dropdowns, modals and pages beside them.
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
    placement.laySpan(ed, .{ .from = .{ .x = 8, .y = 6 }, .erase = false, .shape = .rect }, .{ .x = 23, .y = 15 });
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
        placement.place(ed, q.at);
    }
    try @import("../map/script_text.zig").readAlone(SHOT_SCRIPT, &ed.map.script, ed.map.node_n);
    for ([_]usize{ 1, 2 }) |n| {
        ed.select(n);
        ed.tool = .door;
        placement.place(ed, .{ .x = 5, .y = 5 });
        placement.place(ed, .{ .x = 60, .y = 40 });
    }
    ed.map.link(.{ .node = 1, .door = 1 }, .{ .node = 2, .door = 0 });
    ed.select(1);
    ed.tool = .link;
    placement.place(ed, .{ .x = 5, .y = 5 });
    ed.select(0);
    placement.place(ed, .{ .x = 24, .y = 10 });
    placement.place(ed, .{ .x = 16, .y = 16 });
    ed.tool = .paint;
    ed.cam = .{ 4, 2 };
    g.screen = .{ .x = target.texture.width, .y = target.texture.height };
    const hover_at = ed.cellRect(Editor.canvas(g), .{ .x = 14, .y = 13 });
    ed.desk.mouse = .{ .x = @as(i32, @intFromFloat(hover_at.x)) + 8, .y = @as(i32, @intFromFloat(hover_at.y)) + 8 };
    ed.said_t = 0;
    const dir = std.fs.path.dirname(map_path) orelse ".";
    for (std.enums.values(View), [_][:0]const u8{ map_path, graph_path }) |v, p| {
        ed.view = v;
        try snap(ed, g, target, p);
    }
    ed.view = .map;
    openPopup(ed, panel.nodeSlot(g), .node, ed.node, g.screen.y);
    try snapAs(ed, g, target, "{s}/edit-nodes.png", .{dir});
    openPopup(ed, panel.fileSlot(g), .file, 0, g.screen.y);
    try snapAs(ed, g, target, "{s}/edit-file.png", .{dir});
    ed.popup = null;
    render(ed, g, target);
    ed.pane.getPtr(.side).top = ed.pane.get(.side).most;
    try snapAs(ed, g, target, "{s}/edit-tools-palette.png", .{dir});
    ed.setTool(.{ .foe = .slime });
    ed.foe_type = actor.row(.slime).foe_type;
    try snapAs(ed, g, target, "{s}/edit-foes.png", .{dir});
    ed.foe_type = null;
    ed.setTool(.paint);
    ed.select(1);
    ed.setInspect(.generator);
    const fo = &ed.map.node[1].plan.procgen.foes;
    _ = fo.addMakeup();
    fo.makeup[fo.makeup_n - 1] = pack.Makeup.of(&.{ .slime, .bloat, .rat, .rat, .rat });
    fo.makeup[fo.makeup_n - 1].draw = .{ .weight = 3 };
    ed.desk.mouse = .{ .x = 0, .y = 0 };
    render(ed, g, target);
    try snapAs(ed, g, target, "{s}/edit-gen-top.png", .{dir});
    ed.pane.getPtr(.inspector).top = ed.pane.get(.inspector).most;
    try snap(ed, g, target, gen_path);
    ed.modal = .objects;
    ed.seen_at = seenIndex(.{ .body = .slime });
    try snap(ed, g, target, objects_path);
    ed.seen_at = seenIndex(.{ .body = .beefy_pib });
    try snapAs(ed, g, target, "{s}/edit-beefy-pib.png", .{dir});
    for (EFFECT_POSES) |q| {
        try effects_view.pose(ed, q.sample, q.seconds);
        try snapAs(ed, g, target, "{s}/edit-effects-{s}.png", .{ dir, q.name });
    }
    ed.modal = .help;
    try snapAs(ed, g, target, "{s}/edit-help.png", .{dir});
    ed.modal = .{ .plot = .dialogs };
    ed.plot.pick = .{ .folk = 0 };
    try snapAs(ed, g, target, "{s}/edit-folk.png", .{dir});
    ed.plot.pick = .{ .dialog = 0 };
    ed.plot.line = 0;
    try snapAs(ed, g, target, "{s}/edit-dialog.png", .{dir});
    ed.plot.focus = .{ .say = .{ .d = 0, .l = 0 } };
    ed.plot.field.set(ed.map.script.dialog[0].line[0].say.text());
    try snapAs(ed, g, target, "{s}/edit-dialog-typing.png", .{dir});
    ed.plot.focus = null;
    ed.modal = .{ .plot = .script };
    ed.plot.trigger = 0;
    try snapAs(ed, g, target, "{s}/edit-script.png", .{dir});
    ed.naming = .save_as;
    ed.field.put("The Warrens");
    ed.listing.scan();
    inline for (comptime std.enums.values(Prompt)) |prompt| {
        ed.modal = .{ .prompt = prompt };
        try snapAs(ed, g, target, "{s}/edit-" ++ @tagName(prompt) ++ ".png", .{dir});
    }
    text_panel.open(ed);
    try snapAs(ed, g, target, "{s}/edit-text-browse.png", .{dir});
    ed.words.top = std.math.maxInt(usize);
    try snapAs(ed, g, target, "{s}/edit-text-list-end.png", .{dir});
    try text_panel.poseContext(ed, "play.items.SPECS.war_bow.name");
    try snapAs(ed, g, target, "{s}/edit-text-item.png", .{dir});
    try text_panel.pose(ed);
    try snapAs(ed, g, target, "{s}/edit-text.png", .{dir});
    ed.words.author = .you;
    text_panel.requestClose(ed, false);
    try snapAs(ed, g, target, "{s}/edit-text-unsaved.png", .{dir});
}

pub const SHOT_SCRIPT =
    \\flag met_wenna
    \\counter coins
    \\dialog wenna
    \\line root
    \\who Old Wenna
    \\say You came down the well too? Nobody comes down the well. Mind the slime; it splits when you cut it.
    \\act flag met_wenna on
    \\ask What is down here? -> deeper
    \\ask Do you need anything? -> coins
    \\need flag met_wenna on
    \\gets counter coins add 5
    \\ask Goodbye. -> end
    \\line deeper
    \\say Rats. Slime. Worse, past the gate.
    \\then root
    \\line coins
    \\say Bring me five coins and I will tell you where the old gate key fell.
    \\then root
    \\folk 0 11 8 wenna Old Wenna
    \\folk 0 21 9 -
    \\trigger greet 5 once live
    \\when near 0 3
    \\when flag met_wenna off
    \\do text Someone hums by the cistern.
    \\do dialog wenna
    \\trigger cleared 0 once live
    \\when deaths rat >= 3
    \\when alive slime = 0
    \\do text The warrens fall quiet.
    \\do flag met_wenna flip
    \\
;

const EFFECT_POSES = [_]struct { name: []const u8, sample: effects_view.Sample, seconds: f32 }{
    .{ .name = "hit", .sample = .{ .hit = .blood }, .seconds = 0.12 },
    .{ .name = "fireball", .sample = .{ .missile = .fireball }, .seconds = 0.1 },
    .{ .name = "blast", .sample = .{ .missile = .fireball }, .seconds = 0.22 },
    .{ .name = "burning", .sample = .{ .mark = .burning }, .seconds = 1 },
    .{ .name = "level-up", .sample = .level_up, .seconds = 0.6 },
};

fn seenIndex(want: Seen) usize {
    for (SEEN, 0..) |s, i| {
        if (std.meta.eql(s, want)) return i;
    }
    unreachable;
}

fn render(ed: *Editor, g: *game.Game, target: rl.RenderTexture2D) void {
    prepare(ed, g);
    rl.beginTextureMode(target);
    draw(ed, g);
    rl.endTextureMode();
}

fn snapAs(ed: *Editor, g: *game.Game, target: rl.RenderTexture2D, comptime fmt: []const u8, args: anytype) !void {
    var path: [std.fs.max_path_bytes]u8 = undefined;
    try snap(ed, g, target, try std.fmt.bufPrintZ(&path, fmt, args));
}

fn snap(ed: *Editor, g: *game.Game, target: rl.RenderTexture2D, path: [:0]const u8) !void {
    render(ed, g, target);
    try game.shots.exportTarget(target, path);
}
