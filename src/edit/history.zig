const std = @import("std");
const atlas = @import("../map/atlas.zig");
const mathx = @import("../core/mathx.zig");
const wire = @import("../core/wire.zig");

pub const CAPACITY: usize = 24;

const Code = wire.Codec(struct {
    pub const countField = wire.counted;
});

const Snapshot = struct {
    nodes: []atlas.Node,
    start: atlas.Start,
    script: std.ArrayList(u8),

    fn capture(alloc: std.mem.Allocator, map: *const atlas.Atlas) !Snapshot {
        const nodes = try alloc.dupe(atlas.Node, map.node[0..map.node_n]);
        errdefer alloc.free(nodes);
        var script = std.ArrayList(u8).init(alloc);
        errdefer script.deinit();
        try Code.write(&script, &map.script);
        return .{ .nodes = nodes, .start = map.start, .script = script };
    }

    fn restore(self: *const Snapshot, map: *atlas.Atlas) void {
        @memcpy(map.node[0..self.nodes.len], self.nodes);
        map.node_n = self.nodes.len;
        map.start = self.start;
        Code.read(self.script.items, &map.script) catch unreachable;
    }

    fn deinit(self: *Snapshot) void {
        self.script.allocator.free(self.nodes);
        self.script.deinit();
    }

    fn bytes(self: *const Snapshot) usize {
        return self.nodes.len * @sizeOf(atlas.Node) + self.script.capacity;
    }
};

test "compact history preserves long text and unfinished references through undo and redo" {
    const alloc = std.testing.allocator;
    const map = try alloc.create(atlas.Atlas);
    defer alloc.destroy(map);
    map.* = .{};
    _ = map.add(.{ .bespoke = .{} });
    const before = try alloc.create(atlas.Atlas);
    defer alloc.destroy(before);
    var history = History{ .alloc = alloc, .transaction = .{ .before = before } };
    defer history.deinit();
    map.script.dialog_n = 1;
    const dialog = &map.script.dialog[0];
    dialog.line_n = 1;
    const line = &dialog.line[0];
    @memset(&line.say.buf, 'x');
    line.say.buf[19] = '\n';
    line.say.n = line.say.buf.len;
    line.choice_n = 1;
    line.choice[0].next = 15;
    try std.testing.expect(line.choice[0].ask.set("First reply\nSecond reply"));
    try std.testing.checkAllAllocationFailures(alloc, struct {
        fn capture(a: std.mem.Allocator, source: *const atlas.Atlas) !void {
            var snapshot = try Snapshot.capture(a, source);
            defer snapshot.deinit();
        }
    }.capture, .{map});
    const original_pos = map.node[0].pos;
    try history.begin(map);
    try std.testing.expect(line.say.set("Shorter"));
    line.choice[0].next = null;
    map.node[0].pos.x += 20;
    history.record();
    history.markSaved();
    try std.testing.expect(history.retainedBytes() < @sizeOf(atlas.Atlas) / 10);
    try std.testing.expect(try history.undo(map));
    try std.testing.expectEqual(line.say.buf.len, line.say.n);
    for (line.say.text(), 0..) |c, i| try std.testing.expectEqual(@as(u8, if (i == 19) '\n' else 'x'), c);
    try std.testing.expectEqual(@as(?u8, 15), line.choice[0].next);
    try std.testing.expectEqualStrings("First reply\nSecond reply", line.choice[0].ask.text());
    try std.testing.expectEqual(original_pos, map.node[0].pos);
    try std.testing.expect(history.dirty);
    try std.testing.expect(try history.redo(map));
    try std.testing.expectEqualStrings("Shorter", line.say.text());
    try std.testing.expectEqual(@as(?u8, null), line.choice[0].next);
    try std.testing.expectEqual(original_pos.x + 20, map.node[0].pos.x);
    try std.testing.expect(!history.dirty);
}

test "history allocation failures preserve open gestures redo and saved positions" {
    const alloc = std.testing.allocator;
    const map = try alloc.create(atlas.Atlas);
    defer alloc.destroy(map);
    map.* = .{};
    _ = map.add(.{ .procgen = .{} });
    const before = try alloc.create(atlas.Atlas);
    defer alloc.destroy(before);
    var history = History{ .alloc = alloc, .transaction = .{ .before = before } };
    defer history.deinit();
    try history.begin(map);
    map.node[0].pos.x += 1;
    history.record();
    history.markSaved();
    for (0..2) |fail_at| {
        var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = fail_at });
        history.alloc = failing.allocator();
        try std.testing.expectError(error.OutOfMemory, history.undo(map));
        try std.testing.expectEqual(@as(usize, 1), history.at);
        try std.testing.expectEqual(@as(?usize, 1), history.saved_at);
        try std.testing.expect(!history.dirty);
    }
    history.alloc = alloc;
    try std.testing.expect(try history.undo(map));
    try history.begin(map);
    const position = map.node[0].pos;
    const retained = history.retainedBytes();
    for (0..2) |fail_at| {
        var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = fail_at });
        history.alloc = failing.allocator();
        try std.testing.expectError(error.OutOfMemory, history.begin(map));
        try std.testing.expectEqual(position, map.node[0].pos);
        try std.testing.expectEqual(retained, history.retainedBytes());
        try std.testing.expectEqual(.open, history.transaction.state);
        failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = fail_at });
        try std.testing.expectError(error.OutOfMemory, history.redo(map));
        try std.testing.expectEqual(position, map.node[0].pos);
        try std.testing.expectEqual(@as(usize, 0), history.at);
        try std.testing.expectEqual(@as(usize, 1), history.len);
        try std.testing.expectEqual(@as(?usize, 1), history.saved_at);
    }
    history.alloc = alloc;
    history.cancelPreview(map);
    try std.testing.expect(try history.redo(map));
    try std.testing.expectEqual(position.x + 1, map.node[0].pos.x);
    history.reset();
    try std.testing.expectEqual(@as(usize, 0), history.retainedBytes());
}

comptime {
    const captured = [_][]const u8{ "node", "node_n", "start", "script" };
    const names = std.meta.fieldNames(atlas.Atlas);
    if (names.len != captured.len) @compileError("History snapshots must capture every Atlas field");
    for (names, captured) |name, want| if (!std.mem.eql(u8, name, want)) @compileError("History snapshots must capture every Atlas field");
}

const Transaction = struct {
    before: *atlas.Atlas,
    state: enum { closed, open, recorded } = .closed,
    changed: bool = false,

    fn begin(self: *Transaction, map: *const atlas.Atlas) void {
        self.before.* = map.*;
        self.state = .open;
        self.changed = false;
    }

    pub fn previewNode(self: *Transaction, map: *atlas.Atlas, node: usize, to: mathx.P) void {
        map.node[node].pos = to;
        self.changed = !self.before.node[node].pos.eq(to);
    }

    fn cancel(self: *Transaction, map: *atlas.Atlas) void {
        if (self.state == .open) map.* = self.before.*;
        self.close();
    }

    fn close(self: *Transaction) void {
        self.state = .closed;
        self.changed = false;
    }
};

pub const History = struct {
    alloc: std.mem.Allocator,
    transaction: Transaction,
    states: [CAPACITY]?Snapshot = @splat(null),
    pending: ?Snapshot = null,
    base: usize = 0,
    len: usize = 0,
    at: usize = 0,
    saved_at: ?usize = 0,
    dirty: bool = false,

    pub fn deinit(self: *History) void {
        self.discardPending();
        for (&self.states) |*state| discard(state);
    }

    fn discard(state: *?Snapshot) void {
        if (state.*) |*snapshot| snapshot.deinit();
        state.* = null;
    }

    fn discardPending(self: *History) void {
        discard(&self.pending);
    }

    pub fn retainedBytes(self: *const History) usize {
        var bytes: usize = 0;
        if (self.pending) |*snapshot| bytes += snapshot.bytes();
        for (&self.states) |*state| if (state.*) |*snapshot| {
            bytes += snapshot.bytes();
        };
        return bytes;
    }

    pub fn reset(self: *History) void {
        self.deinit();
        self.base = 0;
        self.len = 0;
        self.at = 0;
        self.saved_at = 0;
        self.dirty = false;
        self.transaction.close();
    }

    pub fn begin(self: *History, map: *const atlas.Atlas) !void {
        const pending = try Snapshot.capture(self.alloc, map);
        self.discardPending();
        self.pending = pending;
        self.transaction.begin(map);
    }

    pub fn record(self: *History) void {
        self.dirty = true;
        self.transaction.changed = true;
        if (self.transaction.state != .open) {
            if (self.saved_at == self.at) self.saved_at = null;
            return;
        }
        self.transaction.state = .recorded;
        for (self.at..self.len) |i| discard(self.kept(i));
        self.len = self.at;
        if (self.saved_at) |s| if (s > self.len) {
            self.saved_at = null;
        };
        if (self.len == CAPACITY) {
            discard(self.kept(0));
            self.base = (self.base + 1) % CAPACITY;
            self.len -= 1;
            if (self.saved_at) |s| self.saved_at = if (s == 0) null else s - 1;
        }
        self.kept(self.len).* = self.pending.?;
        self.pending = null;
        self.len += 1;
        self.at = self.len;
    }

    pub fn commitPreview(self: *History) void {
        if (self.transaction.changed) self.record();
        self.discardPending();
        self.transaction.state = .closed;
    }

    pub fn cancelPreview(self: *History, map: *atlas.Atlas) void {
        self.transaction.cancel(map);
        self.discardPending();
    }

    pub fn markSaved(self: *History) void {
        self.saved_at = self.at;
        self.dirty = false;
    }

    fn kept(self: *History, index: usize) *?Snapshot {
        return &self.states[(self.base + index) % CAPACITY];
    }

    fn swap(self: *History, map: *atlas.Atlas, index: usize) !void {
        const outgoing = try Snapshot.capture(self.alloc, map);
        const scratch = self.transaction.before;
        scratch.* = map.*;
        const state = self.kept(index);
        state.*.?.restore(map);
        discard(state);
        state.* = outgoing;
        self.discardPending();
        self.transaction.close();
    }

    pub fn undo(self: *History, map: *atlas.Atlas) !bool {
        if (self.at == 0) return false;
        try self.swap(map, self.at - 1);
        self.at -= 1;
        self.dirty = self.saved_at != self.at;
        return true;
    }

    pub fn redo(self: *History, map: *atlas.Atlas) !bool {
        if (self.at == self.len) return false;
        try self.swap(map, self.at);
        self.at += 1;
        self.dirty = self.saved_at != self.at;
        return true;
    }
};
