const std = @import("std");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const actor = @import("../play/actor.zig");
const script = @import("../map/script.zig");
const editor = @import("editor.zig");
const Editor = editor.Editor;
const Desk = input.Desk;
const P = mathx.P;

const tool_catalog = @import("tool_catalog.zig");
const TORCH_RULE = tool_catalog.TORCH_RULE;
const FOE_RULE = tool_catalog.FOE_RULE;
const FOLK_RULE = tool_catalog.FOLK_RULE;
pub const NO_ROOM = "The node has no room for another {s}";
pub const LINKING = "Linking node {d} door {d}: ";
pub const LINK_CANCELLED = "Link cancelled";

pub const Spanned = tool_catalog.Spanned;
pub const Span = struct { from: P, erase: bool, shape: Spanned };

pub const Board = struct {
    size: P = .{ .x = 0, .y = 0 },
    cells: atlas.Bespoke = .{},

    pub fn box(b: *const Board, lo: P) grid.Box {
        return grid.Box.sized(lo, b.size.x, b.size.y);
    }
};

pub const PastePreview = struct {
    ready: bool = false,
    at: P = undefined,
    node: usize = undefined,
    source: atlas.Node = undefined,
    board: Board = undefined,
    result: Pasted = undefined,

    fn matches(self: *const PastePreview, ed: *Editor, at: P) bool {
        return self.ready and self.node == ed.node and self.at.eq(at) and
            std.mem.eql(u8, std.mem.asBytes(&self.source), std.mem.asBytes(ed.here())) and
            std.mem.eql(u8, std.mem.asBytes(&self.board), std.mem.asBytes(&ed.board));
    }
};

pub fn brushAt(ed: *Editor, p: P) void {
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
    const folk_before = ed.map.script.folk_n;
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
    const folk_went = ed.map.script.folk_n < folk_before;
    ed.say("Filled {d} cells of {s} with {s}{s}", .{ filled, @tagName(from), @tagName(to), if (folk_went) "; folk standing there went" else "" });
}

pub fn pickUp(ed: *Editor, p: P, second: bool) void {
    if (!grid.Level.inside(p)) return;
    ed.stroke = .none;
    const nd = ed.here();
    const i = grid.Level.idx(p);
    const picked: ?editor.Tool = if (ed.map.script.folkAt(ed.node, p) != null) .folk else switch (nd.plan) {
        .bespoke => |*b| if (b.foeAt(p)) |f| .{ .foe = b.foe[f].kind } else if (b.barrel[i]) .barrel else if (b.torch.has(p)) .torch else if (nd.doorAt(p) != null) .door else null,
        .procgen => if (nd.doorAt(p) != null) .door else null,
    };
    if (picked) |t| {
        ed.setTool(t);
        return ed.say("Picked up the {s} tool", .{t.name()});
    }
    ed.preview();
    if (!ed.paintable()) return ed.say(editor.GENERATED, .{});
    const t = ed.scene.lv.at(p);
    ed.ink.set(.of(second), t);
    ed.setTool(.paint);
    ed.say("{s} is the {s} ink", .{ @tagName(t), @tagName(editor.Ink.of(second)) });
}

pub fn brushBox(p: P, n: i32) grid.Box {
    return grid.Box.sized(p.sub(.{ .x = @divTrunc(n - 1, 2), .y = @divTrunc(n - 1, 2) }), n, n);
}

fn apply(ed: *Editor, p: P, erase: bool) void {
    if (erase) remove(ed, p) else place(ed, p);
}

pub fn linkDoors(ed: *Editor, from: atlas.Link, to: atlas.Link) void {
    if (from.eq(to)) return ed.say(LINK_CANCELLED, .{});
    if (ed.map.door(from).to) |t| {
        if (t.eq(to)) return ed.say("Those doors lead to each other already", .{});
    }
    ed.map.link(from, to);
    ed.relinked();
    ed.say("Node {d} door {d} and node {d} door {d} lead to each other", .{ from.node, from.door, to.node, to.door });
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

fn barrelInto(map: *const atlas.Atlas, n: usize, b: *atlas.Bespoke, p: P) Put {
    const i = grid.Level.idx(p);
    if (b.barrel[i]) return .there;
    if (!map.barrelGoes(n, b, p)) return .refused;
    b.barrel[i] = true;
    return .laid;
}

fn putBarrel(ed: *Editor, b: *atlas.Bespoke, p: P) bool {
    const put = barrelInto(ed.map, ed.node, b, p);
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

fn takeFolk(ed: *Editor, p: P) void {
    ed.map.script.dropFolk(ed.map.script.folkAt(ed.node, p) orelse return);
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
            const there = b.foeAt(p);
            if (there) |f| if (b.foe[f].kind == k) return;
            if (!ed.map.foeGoes(ed.node, b, p, k)) {
                if (!b.roomAt(p, k)) return ed.say(NO_ROOM, .{actor.row(k).name});
                return ed.say("A foe " ++ FOE_RULE, .{});
            }
            if (there) |f| b.foe[f].kind = k else _ = b.addFoe(.{ .kind = k, .at = p });
            ed.changed();
        },
        .folk => {
            if (ed.map.script.folkAt(ed.node, p)) |f| return editor.plot.openFolk(ed, f);
            if (!ed.map.folkFits(ed.node, p)) return ed.say("Folk " ++ FOLK_RULE, .{});
            const f = ed.map.script.addFolk(.{ .node = @intCast(ed.node), .at = p }) orelse return ed.say("The map holds {d} folk", .{script.MAX_FOLK});
            ed.changed();
            editor.plot.openFolk(ed, f);
        },
        .door => {
            const k = ed.map.addDoor(ed.node, p) orelse return ed.say("That cell is a door, or the node holds {d}", .{grid.MAX_DOORS});
            if (ed.painted()) |b| {
                b.tile[grid.Level.idx(p)] = .floor;
                ed.here().pruneAt(b, p);
            }
            ed.say("Door {d}; the {s} tool joins it to another", .{ k, @as(editor.Tool, .link).name() });
            ed.changed();
        },
        .link => {
            const k = ed.doorAt(p) orelse return ed.say("Link from a door", .{});
            const here = atlas.Link{ .node = ed.node, .door = k };
            const from = ed.pick orelse {
                ed.pick = here;
                return ed.say(LINKING ++ Desk.PAINT_CAPTION ++ " the destination door on any node", .{ here.node, here.door });
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
        .folk => takeFolk(ed, p),
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
    const s = ed.selection orelse return ed.say("Nothing selected: {s} then drag", .{Desk.SHAPE_CAPTIONS[@intFromEnum(editor.Shape.select)]});
    const b = ed.painted() orelse return ed.say("A procgen node's cells are rolled; there is nothing to copy", .{});
    const bd = &ed.board;
    bd.* = .{ .size = s.hi.sub(s.lo) };
    var cells = s.cells();
    while (cells.next()) |p| {
        const at = grid.Level.idx(p.sub(s.lo));
        const i = grid.Level.idx(p);
        bd.cells.tile[at] = b.tile[i];
        bd.cells.barrel[at] = b.barrel[i];
    }
    for (b.torches()) |t| {
        if (s.holds(t)) _ = bd.cells.torch.add(t.sub(s.lo));
    }
    for (b.foes()) |f| {
        if (s.holds(f.at)) _ = bd.cells.addFoe(.{ .kind = f.kind, .at = f.at.sub(s.lo) });
    }
    if (cut) return clearSelection(ed);
    ed.say("Copied {d} by {d}: {s} pastes", .{ bd.size.x, bd.size.y, Desk.PASTE_CAPTION });
}

pub fn clearSelection(ed: *Editor) void {
    const s = ed.selection orelse return;
    const b = ed.painted() orelse return ed.say(editor.GENERATED, .{});
    ed.drop();
    ed.gesture();
    var cells = s.cells();
    while (cells.next()) |p| {
        takeBarrel(ed, b, p);
        takeTorch(ed, b, p);
        takeFoe(ed, b, p);
        takeFolk(ed, p);
        paintTile(ed, p, ed.ink.get(.second));
    }
    ed.say("Cleared to {s}", .{@tagName(ed.ink.get(.second))});
}

pub fn startPaste(ed: *Editor) void {
    if (ed.board.size.x == 0) return ed.say("Nothing copied yet", .{});
    if (!ed.paintable()) return ed.say(editor.GENERATED, .{});
    ed.drop();
    ed.pasting = true;
    ed.say("{s} lays the copy with its corner at the cursor; {s} or {s} puts it away", .{ Desk.PAINT_CAPTION, Desk.ERASE_CAPTION, Desk.BACK_CAPTION });
}

pub fn layBoard(ed: *Editor, at: P) void {
    const laid = layInto(ed.map, ed.node, &ed.plan().bespoke, &ed.board, at);
    if (laid.left > 0) ed.say("Pasted; {d} torch(es), barrel(s) or foe(s) did not fit there", .{laid.left}) else ed.say("Pasted", .{});
    if (laid.changed) ed.changed();
}

pub const Pasted = struct { left: usize = 0, changed: bool = false };

pub fn layAside(ed: *Editor, at: P) Pasted {
    const cached = &ed.paste_preview;
    if (cached.matches(ed, at)) return cached.result;
    ed.trial = ed.plan().bespoke;
    const result = layInto(ed.map, ed.node, &ed.trial, &ed.board, at);
    @memcpy(std.mem.asBytes(&cached.source), std.mem.asBytes(ed.here()));
    @memcpy(std.mem.asBytes(&cached.board), std.mem.asBytes(&ed.board));
    cached.at = at;
    cached.node = ed.node;
    cached.result = result;
    cached.ready = true;
    return result;
}

/// The copy laid into `b` with its corner at `at`; the paste's ghost lays it aside the same way.
fn layInto(map: *const atlas.Atlas, n: usize, b: *atlas.Bespoke, bd: *const Board, at: P) Pasted {
    const nd = &map.node[n];
    var laid: Pasted = .{};
    var cells = bd.box(.{ .x = 0, .y = 0 }).cells();
    while (cells.next()) |q| {
        const p = at.add(q);
        const k = grid.Level.idx(q);
        if (!grid.Level.inside(p)) {
            if (bd.cells.barrel[k]) laid.left += 1;
            continue;
        }
        if (paintInto(nd, b, p, bd.cells.tile[k])) laid.changed = true;
        if (!bd.cells.barrel[k]) continue;
        switch (barrelInto(map, n, b, p)) {
            .there => {},
            .laid => laid.changed = true,
            .refused => laid.left += 1,
        }
    }
    for (bd.cells.torches()) |t| {
        const p = at.add(t);
        if (!grid.Level.inside(p)) {
            laid.left += 1;
        } else if (!b.torch.has(p)) {
            if (nd.torchGoes(b, p) and b.torch.add(p)) laid.changed = true else laid.left += 1;
        }
    }
    for (bd.cells.foes()) |f| {
        const p = at.add(f.at);
        if (!grid.Level.inside(p)) {
            laid.left += 1;
        } else if (b.foeAt(p)) |i| {
            if (b.foe[i].kind != f.kind) laid.left += 1;
        } else if (map.foeGoes(n, b, p, f.kind) and b.addFoe(.{ .kind = f.kind, .at = p })) laid.changed = true else laid.left += 1;
    }
    return laid;
}

pub fn legal(ed: *Editor, p: P) bool {
    const nd = ed.here();
    if (!ed.tool.fits(nd)) return false;
    return switch (ed.tool) {
        .paint, .start => true,
        .barrel => ed.map.barrelGoes(ed.node, &nd.plan.bespoke, p),
        .torch => nd.torchGoes(&nd.plan.bespoke, p),
        .foe => |k| ed.map.foeGoes(ed.node, &nd.plan.bespoke, p, k),
        .folk => ed.map.folkGoes(ed.node, p) or ed.map.script.folkAt(ed.node, p) != null,
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
        .folk => ed.map.script.folkAt(ed.node, p) != null,
        .door => nd.doorAt(p) != null,
        .link => if (nd.doorAt(p)) |k| nd.door[k].to != null else false,
        .start => false,
    };
}
