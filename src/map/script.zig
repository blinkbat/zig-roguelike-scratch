const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const actor = @import("../play/actor.zig");
const P = mathx.P;

pub const NAME_MAX: usize = 20;
pub const WHO_MAX: usize = 24;
pub const SAY_MAX: usize = 240;
pub const ASK_MAX: usize = 60;
pub const NOTE_MAX: usize = 80;

pub const MAX_FLAGS: usize = 32;
pub const MAX_COUNTERS: usize = 32;
pub const MAX_TIMERS: usize = 16;
pub const MAX_FOLK: usize = 32;
pub const MAX_DIALOGS: usize = 12;
pub const MAX_LINES: usize = 10;
pub const MAX_CHOICES: usize = 4;
pub const LINE_ACTS: usize = 3;
pub const CHOICE_ACTS: usize = 2;
pub const MAX_TRIGGERS: usize = 48;
pub const MAX_CONDS: usize = 8;
pub const MAX_ACTS: usize = 8;
pub const NUMBER_MAX: i32 = 9999;
pub const NEAR_MAX: i32 = 20;
pub const PRIORITY_MAX: i8 = 99;
pub const END = "end";
pub const NONE = "-";

comptime {
    std.debug.assert(MAX_FOLK < std.math.maxInt(u8));
    std.debug.assert(@max(MAX_FLAGS, MAX_COUNTERS, MAX_TIMERS, MAX_DIALOGS, MAX_LINES, MAX_TRIGGERS) <= std.math.maxInt(u8));
}

/// Printable ascii without its ends' spaces, `N` at most.
pub fn Words(comptime N: usize) type {
    comptime std.debug.assert(N <= std.math.maxInt(u8));
    return struct {
        const Self = @This();
        pub const MAX = N;
        pub const COUNTED = .{.{ "buf", "n" }};
        buf: [N]u8 = @splat(0),
        n: u8 = 0,

        pub fn of(s: []const u8) Self {
            var w = Self{};
            _ = w.set(s);
            return w;
        }

        pub fn text(self: *const Self) []const u8 {
            return self.buf[0..self.n];
        }

        /// Refused, leaving it as it was, when too long or not plain.
        pub fn set(self: *Self, s: []const u8) bool {
            const t = std.mem.trim(u8, s, " ");
            if (t.len > N or !plain(t)) return false;
            self.buf = @splat(0);
            @memcpy(self.buf[0..t.len], t);
            self.n = @intCast(t.len);
            return true;
        }

        pub fn eql(self: *const Self, s: []const u8) bool {
            return std.mem.eql(u8, self.text(), s);
        }

        pub fn valid(self: *const Self) bool {
            return self.n <= N and plain(self.text()) and std.mem.eql(u8, std.mem.trim(u8, self.text(), " "), self.text());
        }
    };
}

pub const Name = Words(NAME_MAX);
pub const Who = Words(WHO_MAX);
pub const Say = Words(SAY_MAX);
pub const Ask = Words(ASK_MAX);
pub const Note = Words(NOTE_MAX);

pub fn plain(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isPrint(c)) return false;
    }
    return true;
}

/// One word the map file can read back: letters, digits, `_` and `-`, and never `end` or `-`.
pub fn token(s: []const u8) bool {
    if (s.len == 0 or s.len > NAME_MAX or std.mem.eql(u8, s, END) or std.mem.eql(u8, s, NONE)) return false;
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return true;
}

pub const Cmp = enum {
    lt,
    le,
    eq,
    ge,
    gt,

    pub fn tok(c: Cmp) []const u8 {
        return switch (c) {
            .lt => "<",
            .le => "<=",
            .eq => "=",
            .ge => ">=",
            .gt => ">",
        };
    }

    pub fn holds(c: Cmp, a: i64, b: i64) bool {
        return switch (c) {
            .lt => a < b,
            .le => a <= b,
            .eq => a == b,
            .ge => a >= b,
            .gt => a > b,
        };
    }
};

pub const CondKind = enum { always, never, flag, counter, timer, elapsed, region, near, talked, deaths, alive };

/// Each kind reads only its own fields; `slot` indexes the table its kind names.
pub const Cond = struct {
    kind: CondKind = .always,
    slot: u8 = 0,
    /// A flag set, or a timer run out.
    on: bool = true,
    cmp: Cmp = .ge,
    n: i32 = 0,
    foe: actor.Kind = actor.FOES[0],
    node: u8 = 0,
    from: P = .{ .x = 0, .y = 0 },
    to: P = .{ .x = 0, .y = 0 },

    pub fn region(self: *const Cond) grid.Box {
        return grid.Box.between(self.from, self.to);
    }
};

pub const ActKind = enum {
    dialog,
    text,
    flag,
    counter,
    timer,
    wait,
    preserve,

    /// What a conversation's own lines may do; the rest steer a trigger's list.
    pub fn spoken(k: ActKind) bool {
        return switch (k) {
            .text, .flag, .counter, .timer => true,
            .dialog, .wait, .preserve => false,
        };
    }
};
pub const SPOKEN_ACTS = blk: {
    var out: []const ActKind = &.{};
    for (std.enums.values(ActKind)) |k| {
        if (k.spoken()) out = out ++ &[_]ActKind{k};
    }
    break :blk out[0..out.len].*;
};

pub const Setop = enum { off, on, flip };
pub const Countop = enum { set, add, sub };

pub const Act = struct {
    kind: ActKind = .preserve,
    slot: u8 = 0,
    setop: Setop = .on,
    countop: Countop = .set,
    /// A counter's amount, or a timer's or wait's turns.
    n: i32 = 0,
    note: Note = .{},
};

pub const Trigger = struct {
    pub const COUNTED = .{ .{ "cond", "cond_n" }, .{ "act", "act_n" } };
    name: Name = .{},
    /// Higher runs first among those ready on the same turn; file order breaks ties.
    priority: i8 = 0,
    once: bool = true,
    parked: bool = false,
    cond: [MAX_CONDS]Cond = @splat(.{}),
    cond_n: u8 = 0,
    act: [MAX_ACTS]Act = @splat(.{}),
    act_n: u8 = 0,

    pub fn conds(self: *const Trigger) []const Cond {
        return self.cond[0..self.cond_n];
    }

    pub fn acts(self: *const Trigger) []const Act {
        return self.act[0..self.act_n];
    }
};

pub const Choice = struct {
    pub const COUNTED = .{.{ "act", "act_n" }};
    ask: Ask = .{},
    /// A line of the same dialog; null ends the conversation.
    next: ?u8 = null,
    /// Hidden while this does not hold.
    gate: ?Cond = null,
    act: [CHOICE_ACTS]Act = @splat(.{}),
    act_n: u8 = 0,

    pub fn acts(self: *const Choice) []const Act {
        return self.act[0..self.act_n];
    }
};

pub const Line = struct {
    pub const COUNTED = .{ .{ "choice", "choice_n" }, .{ "act", "act_n" } };
    name: Name = .{},
    /// Blank: whoever was spoken to.
    who: Who = .{},
    say: Say = .{},
    choice: [MAX_CHOICES]Choice = @splat(.{}),
    choice_n: u8 = 0,
    /// Where a line without choices goes on; null ends the conversation.
    then: ?u8 = null,
    /// Done when the line is shown.
    act: [LINE_ACTS]Act = @splat(.{}),
    act_n: u8 = 0,

    pub fn choices(self: *const Line) []const Choice {
        return self.choice[0..self.choice_n];
    }

    pub fn acts(self: *const Line) []const Act {
        return self.act[0..self.act_n];
    }
};

pub const Dialog = struct {
    pub const COUNTED = .{.{ "line", "line_n" }};
    name: Name = .{},
    line: [MAX_LINES]Line = @splat(.{}),
    line_n: u8 = 0,

    pub fn lines(self: *const Dialog) []const Line {
        return self.line[0..self.line_n];
    }

    pub fn findLine(self: *const Dialog, name: []const u8) ?u8 {
        for (self.lines(), 0..) |*l, i| {
            if (l.name.eql(name)) return @intCast(i);
        }
        return null;
    }

    pub fn addLine(self: *Dialog) ?u8 {
        if (self.line_n == MAX_LINES) return null;
        var nb: [NAME_MAX]u8 = undefined;
        const at = self.line_n;
        self.line[at] = .{ .name = Name.of(freshName(&nb, "line", self, Dialog.findLine)) };
        self.line_n += 1;
        return at;
    }

    /// Lines `a` and `b` change places, every way into either following it; the first line is where it opens.
    pub fn swapLines(self: *Dialog, a: u8, b: u8) void {
        std.mem.swap(Line, &self.line[a], &self.line[b]);
        for (self.line[0..self.line_n]) |*ln| {
            swapped(&ln.then, a, b);
            for (ln.choice[0..ln.choice_n]) |*c| swapped(&c.next, a, b);
        }
    }

    /// Every way into line `l` ends the conversation instead, and the lines after it close up.
    pub fn dropLine(self: *Dialog, l: u8) void {
        cut(Line, &self.line, &self.line_n, l);
        for (self.line[0..self.line_n]) |*ln| {
            lowered(&ln.then, l);
            for (ln.choice[0..ln.choice_n]) |*c| lowered(&c.next, l);
        }
    }
};

fn swapped(at: *?u8, a: u8, b: u8) void {
    const v = at.* orelse return;
    if (v == a) at.* = b else if (v == b) at.* = a;
}

fn lowered(at: *?u8, gone: u8) void {
    const v = at.* orelse return;
    if (v == gone) at.* = null else if (v > gone) at.* = v - 1;
}

/// A body that talks: not a foe, it neither fights nor moves.
pub const Folk = struct {
    node: u8 = 0,
    at: P = .{ .x = 0, .y = 0 },
    /// Blank: `STRANGER`.
    name: Who = .{},
    dialog: ?u8 = null,

    pub fn called(self: *const Folk) []const u8 {
        return if (self.name.n > 0) self.name.text() else STRANGER;
    }
};
pub const STRANGER = "Stranger";

pub const Table = enum { flag, counter, timer };

pub const Script = struct {
    pub const COUNTED = .{
        .{ "flag", "flag_n" },
        .{ "counter", "counter_n" },
        .{ "timer", "timer_n" },
        .{ "folk", "folk_n" },
        .{ "dialog", "dialog_n" },
        .{ "trigger", "trigger_n" },
    };
    flag: [MAX_FLAGS]Name = @splat(.{}),
    flag_n: u8 = 0,
    counter: [MAX_COUNTERS]Name = @splat(.{}),
    counter_n: u8 = 0,
    timer: [MAX_TIMERS]Name = @splat(.{}),
    timer_n: u8 = 0,
    folk: [MAX_FOLK]Folk = @splat(.{}),
    folk_n: u8 = 0,
    dialog: [MAX_DIALOGS]Dialog = @splat(.{}),
    dialog_n: u8 = 0,
    trigger: [MAX_TRIGGERS]Trigger = @splat(.{}),
    trigger_n: u8 = 0,

    pub fn names(self: *const Script, t: Table) []const Name {
        return switch (t) {
            .flag => self.flag[0..self.flag_n],
            .counter => self.counter[0..self.counter_n],
            .timer => self.timer[0..self.timer_n],
        };
    }

    fn tableOf(self: *Script, t: Table) struct { items: []Name, n: *u8 } {
        return switch (t) {
            .flag => .{ .items = &self.flag, .n = &self.flag_n },
            .counter => .{ .items = &self.counter, .n = &self.counter_n },
            .timer => .{ .items = &self.timer, .n = &self.timer_n },
        };
    }

    pub fn find(self: *const Script, t: Table, name: []const u8) ?u8 {
        for (self.names(t), 0..) |*nm, i| {
            if (nm.eql(name)) return @intCast(i);
        }
        return null;
    }

    pub fn declare(self: *Script, t: Table, name: []const u8) ?u8 {
        if (!token(name) or self.find(t, name) != null) return null;
        const tb = self.tableOf(t);
        if (tb.n.* == tb.items.len) return null;
        tb.items[tb.n.*] = Name.of(name);
        tb.n.* += 1;
        return tb.n.* - 1;
    }

    /// A fresh `flag1`-style name in table `t`.
    pub fn coin(self: *Script, t: Table) ?u8 {
        var nb: [NAME_MAX]u8 = undefined;
        var i: usize = 1;
        while (i <= MAX_FLAGS + MAX_COUNTERS) : (i += 1) {
            const nm = std.fmt.bufPrint(&nb, "{s}{d}", .{ @tagName(t), i }) catch return null;
            if (self.find(t, nm) == null) return self.declare(t, nm);
        }
        return null;
    }

    pub fn rename(self: *Script, t: Table, i: u8, name: []const u8) bool {
        if (!token(name)) return false;
        if (self.find(t, name)) |at| return at == i;
        self.tableOf(t).items[i] = Name.of(name);
        return true;
    }

    pub fn tableUsers(self: *const Script, t: Table, i: u8) usize {
        var n: usize = 0;
        var conds = self.condIter();
        while (conds.next()) |c| {
            if (condTable(c.kind) == t and c.slot == i) n += 1;
        }
        var acts = self.actIter();
        while (acts.next()) |a| {
            if (actTable(a.kind) == t and a.slot == i) n += 1;
        }
        return n;
    }

    /// Refused while anything names it.
    pub fn undeclare(self: *Script, t: Table, i: u8) bool {
        if (self.tableUsers(t, i) > 0) return false;
        const tb = self.tableOf(t);
        cut(Name, tb.items, tb.n, i);
        var conds = self.condIterMut();
        while (conds.next()) |c| {
            if (condTable(c.kind) == t and c.slot > i) c.slot -= 1;
        }
        var acts = self.actIterMut();
        while (acts.next()) |a| {
            if (actTable(a.kind) == t and a.slot > i) a.slot -= 1;
        }
        return true;
    }

    pub fn folks(self: *const Script) []const Folk {
        return self.folk[0..self.folk_n];
    }

    pub fn folkAt(self: *const Script, node: usize, p: P) ?u8 {
        for (self.folks(), 0..) |*f, i| {
            if (f.node == node and f.at.eq(p)) return @intCast(i);
        }
        return null;
    }

    pub fn addFolk(self: *Script, f: Folk) ?u8 {
        if (self.folk_n == MAX_FOLK or self.folkAt(f.node, f.at) != null) return null;
        self.folk[self.folk_n] = f;
        self.folk_n += 1;
        return self.folk_n - 1;
    }

    /// Every `near` it was named in can no longer hold.
    pub fn dropFolk(self: *Script, i: u8) void {
        cut(Folk, &self.folk, &self.folk_n, i);
        var conds = self.condIterMut();
        while (conds.next()) |c| {
            if (c.kind != .near) continue;
            if (c.slot == i) c.* = .{ .kind = .never } else if (c.slot > i) c.slot -= 1;
        }
    }

    /// Node `n` went: its folk with it, and every region drawn on it can no longer hold.
    pub fn dropNode(self: *Script, n: usize) void {
        var i: usize = self.folk_n;
        while (i > 0) {
            i -= 1;
            if (self.folk[i].node == n) self.dropFolk(@intCast(i));
        }
        for (self.folk[0..self.folk_n]) |*f| {
            if (f.node > n) f.node -= 1;
        }
        var conds = self.condIterMut();
        while (conds.next()) |c| {
            if (c.kind != .region) continue;
            if (c.node == n) c.* = .{ .kind = .never } else if (c.node > n) c.node -= 1;
        }
    }

    pub fn dialogs(self: *const Script) []const Dialog {
        return self.dialog[0..self.dialog_n];
    }

    pub fn findDialog(self: *const Script, name: []const u8) ?u8 {
        for (self.dialogs(), 0..) |*d, i| {
            if (d.name.eql(name)) return @intCast(i);
        }
        return null;
    }

    /// A new dialog of one empty line, named after `stem` when it can be.
    pub fn addDialog(self: *Script, stem: []const u8) ?u8 {
        if (self.dialog_n == MAX_DIALOGS) return null;
        var nb: [NAME_MAX]u8 = undefined;
        const at = self.dialog_n;
        const name = if (token(stem) and self.findDialog(stem) == null) stem else freshName(&nb, "dialog", self, Script.findDialog);
        self.dialog[at] = .{ .name = Name.of(name) };
        _ = self.dialog[at].addLine();
        self.dialog_n += 1;
        return at;
    }

    pub fn dialogUsers(self: *const Script, d: u8) usize {
        var n: usize = 0;
        for (self.folks()) |f| {
            if (f.dialog == d) n += 1;
        }
        var conds = self.condIter();
        while (conds.next()) |c| {
            if (c.kind == .talked and c.slot == d) n += 1;
        }
        var acts = self.actIter();
        while (acts.next()) |a| {
            if (a.kind == .dialog and a.slot == d) n += 1;
        }
        return n;
    }

    /// Refused while anything names it, so no reference is left pointing past the end.
    pub fn dropDialog(self: *Script, d: u8) bool {
        if (self.dialogUsers(d) > 0) return false;
        cut(Dialog, &self.dialog, &self.dialog_n, d);
        for (self.folk[0..self.folk_n]) |*f| {
            if (f.dialog) |fd| if (fd > d) {
                f.dialog = fd - 1;
            };
        }
        var conds = self.condIterMut();
        while (conds.next()) |c| {
            if (c.kind == .talked and c.slot > d) c.slot -= 1;
        }
        var acts = self.actIterMut();
        while (acts.next()) |a| {
            if (a.kind == .dialog and a.slot > d) a.slot -= 1;
        }
        return true;
    }

    pub fn triggers(self: *const Script) []const Trigger {
        return self.trigger[0..self.trigger_n];
    }

    pub fn findTrigger(self: *const Script, name: []const u8) ?u8 {
        for (self.triggers(), 0..) |*t, i| {
            if (t.name.eql(name)) return @intCast(i);
        }
        return null;
    }

    pub fn addTrigger(self: *Script) ?u8 {
        if (self.trigger_n == MAX_TRIGGERS) return null;
        var nb: [NAME_MAX]u8 = undefined;
        const at = self.trigger_n;
        self.trigger[at] = .{ .name = Name.of(freshName(&nb, "trigger", self, Script.findTrigger)) };
        self.trigger[at].cond[0] = .{ .kind = .always };
        self.trigger[at].cond_n = 1;
        self.trigger_n += 1;
        return at;
    }

    pub fn dropTrigger(self: *Script, i: u8) void {
        cut(Trigger, &self.trigger, &self.trigger_n, i);
    }

    pub fn condIter(self: *const Script) CondIter(*const Script, *const Cond) {
        return .{ .s = self };
    }

    pub fn condIterMut(self: *Script) CondIter(*Script, *Cond) {
        return .{ .s = self };
    }

    pub fn actIter(self: *const Script) ActIter(*const Script, *const Act) {
        return .{ .s = self };
    }

    pub fn actIterMut(self: *Script) ActIter(*Script, *Act) {
        return .{ .s = self };
    }

    /// Every index in range, every name readable back and every text plain; `node_n` nodes on the map.
    pub fn valid(self: *const Script, node_n: usize) bool {
        if (self.flag_n > MAX_FLAGS or self.counter_n > MAX_COUNTERS or self.timer_n > MAX_TIMERS) return false;
        if (self.folk_n > MAX_FOLK or self.dialog_n > MAX_DIALOGS or self.trigger_n > MAX_TRIGGERS) return false;
        for (std.enums.values(Table)) |t| {
            const all = self.names(t);
            for (all, 0..) |*nm, i| {
                if (!nm.valid() or !token(nm.text())) return false;
                for (all[0..i]) |*other| if (other.eql(nm.text())) return false;
            }
        }
        for (self.folks(), 0..) |*f, i| {
            if (f.node >= node_n or !grid.Level.inside(f.at) or !f.name.valid()) return false;
            if (f.dialog) |d| if (d >= self.dialog_n) return false;
            for (self.folks()[0..i]) |*other| if (other.node == f.node and other.at.eq(f.at)) return false;
        }
        for (self.dialogs(), 0..) |*d, di| {
            if (!d.name.valid() or !token(d.name.text()) or d.line_n == 0 or d.line_n > MAX_LINES) return false;
            for (self.dialogs()[0..di]) |*other| if (other.name.eql(d.name.text())) return false;
            for (d.lines(), 0..) |*l, li| {
                if (!l.name.valid() or !token(l.name.text()) or !l.who.valid() or !l.say.valid()) return false;
                for (d.lines()[0..li]) |*other| if (other.name.eql(l.name.text())) return false;
                if (l.choice_n > MAX_CHOICES or l.act_n > LINE_ACTS) return false;
                if (l.then) |t| if (t >= d.line_n) return false;
                for (l.acts()) |*a| if (!a.kind.spoken() or !self.actFits(a)) return false;
                for (l.choices()) |*c| {
                    if (!c.ask.valid() or c.act_n > CHOICE_ACTS) return false;
                    if (c.next) |nx| if (nx >= d.line_n) return false;
                    if (c.gate) |*gt| if (!self.condFits(gt, node_n)) return false;
                    for (c.acts()) |*a| if (!a.kind.spoken() or !self.actFits(a)) return false;
                }
            }
        }
        for (self.triggers(), 0..) |*t, ti| {
            if (!t.name.valid() or !token(t.name.text()) or t.cond_n > MAX_CONDS or t.act_n > MAX_ACTS) return false;
            if (t.priority < -PRIORITY_MAX or t.priority > PRIORITY_MAX) return false;
            for (self.triggers()[0..ti]) |*other| if (other.name.eql(t.name.text())) return false;
            for (t.conds()) |*c| if (!self.condFits(c, node_n)) return false;
            for (t.acts()) |*a| if (!self.actFits(a)) return false;
        }
        return true;
    }

    fn slotFits(self: *const Script, t: ?Table, slot: u8) bool {
        return if (t) |tb| slot < self.names(tb).len else true;
    }

    fn condFits(self: *const Script, c: *const Cond, node_n: usize) bool {
        if (!self.slotFits(condTable(c.kind), c.slot)) return false;
        if (c.n < -NUMBER_MAX or c.n > NUMBER_MAX) return false;
        return switch (c.kind) {
            .always, .never, .flag, .counter, .timer, .elapsed => true,
            .region => c.node < node_n and grid.Level.inside(c.from) and grid.Level.inside(c.to),
            .near => c.slot < self.folk_n and c.n >= 0 and c.n <= NEAR_MAX,
            .talked => c.slot < self.dialog_n,
            .deaths, .alive => c.foe.stocked(),
        };
    }

    fn actFits(self: *const Script, a: *const Act) bool {
        if (!self.slotFits(actTable(a.kind), a.slot) or !a.note.valid()) return false;
        if (a.n < -NUMBER_MAX or a.n > NUMBER_MAX) return false;
        return switch (a.kind) {
            .dialog => a.slot < self.dialog_n,
            .timer, .wait => a.n >= 0,
            .text, .flag, .counter, .preserve => true,
        };
    }
};

pub fn condTable(k: CondKind) ?Table {
    return switch (k) {
        .flag => .flag,
        .counter => .counter,
        .timer => .timer,
        .always, .never, .elapsed, .region, .near, .talked, .deaths, .alive => null,
    };
}

pub fn actTable(k: ActKind) ?Table {
    return switch (k) {
        .flag => .flag,
        .counter => .counter,
        .timer => .timer,
        .dialog, .text, .wait, .preserve => null,
    };
}

/// Every condition in a script: the triggers', then each dialog's choice gates.
pub fn CondIter(comptime S: type, comptime C: type) type {
    return struct {
        s: S,
        trigger: usize = 0,
        cond: usize = 0,
        dialog: usize = 0,
        line: usize = 0,
        choice: usize = 0,

        pub fn next(self: *@This()) ?C {
            while (self.trigger < self.s.trigger_n) {
                const t = &self.s.trigger[self.trigger];
                if (self.cond < t.cond_n) {
                    self.cond += 1;
                    return &t.cond[self.cond - 1];
                }
                self.trigger += 1;
                self.cond = 0;
            }
            while (self.dialog < self.s.dialog_n) {
                const d = &self.s.dialog[self.dialog];
                while (self.line < d.line_n) {
                    const l = &d.line[self.line];
                    while (self.choice < l.choice_n) {
                        const c = &l.choice[self.choice];
                        self.choice += 1;
                        if (c.gate) |*g| return g;
                    }
                    self.line += 1;
                    self.choice = 0;
                }
                self.dialog += 1;
                self.line = 0;
            }
            return null;
        }
    };
}

/// Every action in a script: the triggers', then each dialog line's and choice's.
pub fn ActIter(comptime S: type, comptime A: type) type {
    return struct {
        s: S,
        trigger: usize = 0,
        dialog: usize = 0,
        line: usize = 0,
        /// Into a line: its own actions, then each choice's in turn.
        part: usize = 0,
        act: usize = 0,

        pub fn next(self: *@This()) ?A {
            while (self.trigger < self.s.trigger_n) {
                const t = &self.s.trigger[self.trigger];
                if (self.act < t.act_n) {
                    self.act += 1;
                    return &t.act[self.act - 1];
                }
                self.trigger += 1;
                self.act = 0;
            }
            while (self.dialog < self.s.dialog_n) {
                const d = &self.s.dialog[self.dialog];
                while (self.line < d.line_n) {
                    const l = &d.line[self.line];
                    while (self.part <= l.choice_n) {
                        const n = if (self.part == 0) l.act_n else l.choice[self.part - 1].act_n;
                        if (self.act < n) {
                            self.act += 1;
                            return if (self.part == 0) &l.act[self.act - 1] else &l.choice[self.part - 1].act[self.act - 1];
                        }
                        self.part += 1;
                        self.act = 0;
                    }
                    self.line += 1;
                    self.part = 0;
                }
                self.dialog += 1;
                self.line = 0;
            }
            return null;
        }
    };
}

/// `stem` and the first number after it that `taken` finds free.
fn freshName(buf: *[NAME_MAX]u8, stem: []const u8, owner: anytype, comptime taken: anytype) []const u8 {
    var i: usize = 1;
    while (true) : (i += 1) {
        const nm = std.fmt.bufPrint(buf, "{s}{d}", .{ stem, i }) catch return stem;
        if (taken(owner, nm) == null) return nm;
    }
}

pub fn cut(comptime T: type, items: []T, n: *u8, i: usize) void {
    std.mem.copyForwards(T, items[i .. n.* - 1], items[i + 1 .. n.*]);
    n.* -= 1;
    items[n.*] = .{};
}

test "dropping a folk, a node or a line leaves no reference past the end" {
    var s = Script{};
    _ = s.addFolk(.{ .node = 0, .at = .{ .x = 3, .y = 3 } }).?;
    _ = s.addFolk(.{ .node = 1, .at = .{ .x = 4, .y = 4 } }).?;
    _ = s.addFolk(.{ .node = 2, .at = .{ .x = 5, .y = 5 } }).?;
    const t = s.addTrigger().?;
    s.trigger[t].cond[0] = .{ .kind = .near, .slot = 2, .n = 3 };
    s.trigger[t].cond[1] = .{ .kind = .region, .node = 1, .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 9, .y = 9 } };
    s.trigger[t].cond[2] = .{ .kind = .region, .node = 2 };
    s.trigger[t].cond_n = 3;
    s.dropNode(1);
    try std.testing.expectEqual(@as(u8, 2), s.folk_n);
    try std.testing.expectEqual(@as(u8, 1), s.folk[1].node);
    try std.testing.expectEqual(@as(u8, 1), s.trigger[t].cond[0].slot);
    try std.testing.expectEqual(CondKind.never, s.trigger[t].cond[1].kind);
    try std.testing.expectEqual(@as(u8, 1), s.trigger[t].cond[2].node);
    s.dropFolk(1);
    try std.testing.expectEqual(CondKind.never, s.trigger[t].cond[0].kind);

    const d = s.addDialog("hello").?;
    _ = s.dialog[d].addLine().?;
    _ = s.dialog[d].addLine().?;
    s.dialog[d].line[0].then = 2;
    s.dialog[d].line[0].choice[0] = .{ .next = 1 };
    s.dialog[d].line[0].choice_n = 1;
    s.dialog[d].dropLine(1);
    try std.testing.expectEqual(@as(?u8, 1), s.dialog[d].line[0].then);
    try std.testing.expectEqual(@as(?u8, null), s.dialog[d].line[0].choice[0].next);
    s.dialog[d].swapLines(0, 1);
    try std.testing.expectEqual(@as(?u8, 0), s.dialog[d].line[1].then);
    try std.testing.expect(s.valid(2));
    std.debug.print("script references: node, folk and line removal renumber or retire every reference\n", .{});
}

test "a named table entry or dialog cannot be dropped while anything names it" {
    var s = Script{};
    const f = s.coin(.flag).?;
    const g = s.coin(.flag).?;
    try std.testing.expectEqualStrings("flag2", s.flag[g].text());
    const d = s.addDialog("talk").?;
    const t = s.addTrigger().?;
    s.trigger[t].act[0] = .{ .kind = .flag, .slot = g };
    s.trigger[t].act[1] = .{ .kind = .dialog, .slot = d };
    s.trigger[t].act_n = 2;
    s.dialog[d].line[0].choice[0] = .{ .gate = .{ .kind = .flag, .slot = g } };
    s.dialog[d].line[0].choice_n = 1;
    try std.testing.expectEqual(@as(usize, 2), s.tableUsers(.flag, g));
    try std.testing.expect(!s.undeclare(.flag, g));
    try std.testing.expect(!s.dropDialog(d));
    try std.testing.expect(s.undeclare(.flag, f));
    try std.testing.expectEqual(@as(u8, 0), s.trigger[t].act[0].slot);
    try std.testing.expectEqual(@as(u8, 0), s.dialog[d].line[0].choice[0].gate.?.slot);
    try std.testing.expect(!s.rename(.flag, 0, "has space"));
    try std.testing.expect(!s.rename(.flag, 0, END));
    try std.testing.expect(s.rename(.flag, 0, "gate_open"));
    try std.testing.expect(s.valid(1));
    std.debug.print("script tables: in-use flag and dialog refused; free flag dropped and later slots renumbered\n", .{});
}
