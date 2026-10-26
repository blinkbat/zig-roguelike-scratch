const atlas = @import("../map/atlas.zig");
const mathx = @import("../core/mathx.zig");

pub const CAPACITY: usize = 24;

pub const Transaction = struct {
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
        self.state = .closed;
        self.changed = false;
    }
};

pub const History = struct {
    transaction: Transaction,
    states: *[CAPACITY]atlas.Atlas,
    base: usize = 0,
    len: usize = 0,
    at: usize = 0,
    saved_at: ?usize = 0,
    dirty: bool = false,

    pub fn reset(self: *History) void {
        self.base = 0;
        self.len = 0;
        self.at = 0;
        self.saved_at = 0;
        self.dirty = false;
        self.transaction.state = .closed;
        self.transaction.changed = false;
    }

    pub fn begin(self: *History, map: *const atlas.Atlas) void {
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
        self.len = self.at;
        if (self.saved_at) |s| if (s > self.len) {
            self.saved_at = null;
        };
        if (self.len == CAPACITY) {
            self.base = (self.base + 1) % CAPACITY;
            self.len -= 1;
            if (self.saved_at) |s| self.saved_at = if (s == 0) null else s - 1;
        }
        self.kept(self.len).* = self.transaction.before.*;
        self.len += 1;
        self.at = self.len;
    }

    pub fn commitPreview(self: *History) void {
        if (self.transaction.changed) self.record();
        self.transaction.state = .closed;
    }

    pub fn cancelPreview(self: *History, map: *atlas.Atlas) void {
        self.transaction.cancel(map);
    }

    pub fn markSaved(self: *History) void {
        self.saved_at = self.at;
        self.dirty = false;
    }

    fn kept(self: *History, index: usize) *atlas.Atlas {
        return &self.states[(self.base + index) % CAPACITY];
    }

    fn swap(self: *History, map: *atlas.Atlas, index: usize) void {
        const scratch = self.transaction.before;
        scratch.* = map.*;
        map.* = self.kept(index).*;
        self.kept(index).* = scratch.*;
        self.transaction.state = .closed;
        self.transaction.changed = false;
    }

    pub fn undo(self: *History, map: *atlas.Atlas) bool {
        if (self.at == 0) return false;
        self.at -= 1;
        self.swap(map, self.at);
        self.dirty = self.saved_at != self.at;
        return true;
    }

    pub fn redo(self: *History, map: *atlas.Atlas) bool {
        if (self.at == self.len) return false;
        self.swap(map, self.at);
        self.at += 1;
        self.dirty = self.saved_at != self.at;
        return true;
    }
};
