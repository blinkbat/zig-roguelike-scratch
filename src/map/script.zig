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

fn nameOf(it: anytype) *const Name {
    return if (comptime @TypeOf(it.*) == Name) it else &it.name;
}

/// Where `name` is among `items`: names, or anything holding its own in `name`.
pub fn indexOfName(items: anytype, name: []const u8) ?u8 {
    for (items, 0..) |*it, i| {
        if (nameOf(it).eql(name)) return @intCast(i);
    }
    return null;
}

pub fn renameIn(items: anytype, i: u8, name: []const u8) bool {
    if (!token(name)) return false;
    if (indexOfName(items, name)) |at| return at == i;
    const it = &items[i];
    if (comptime @TypeOf(it.*) == Name) it.* = Name.of(name) else it.name = Name.of(name);
    return true;
}

/// No two of `items` go by one name.
fn distinct(items: anytype) bool {
    for (items, 0..) |*it, i| {
        if (indexOfName(items[0..i], nameOf(it).text()) != null) return false;
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

    /// Offered whatever holds.
    pub fn always(self: *const Choice) bool {
        const g = self.gate orelse return true;
        return g.kind == .always;
    }
};

const Lines = std.StaticBitSet(MAX_LINES);

/// The end, or a line in `ending`.
fn endsAt(next: ?u8, ending: *const Lines) bool {
    const n = next orelse return true;
    return n < MAX_LINES and ending.isSet(n);
}

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

    /// Goes on to `then` when no choice is offered, as every gated one may not be.
    pub fn thenUsed(self: *const Line) bool {
        for (self.choices()) |*c| {
            if (c.always()) return false;
        }
        return true;
    }

    fn goesOn(self: *const Line, ending: *const Lines) bool {
        for (self.choices()) |*c| {
            if (c.gate) |g| if (g.kind == .never) continue;
            if (endsAt(c.next, ending)) return true;
        }
        return self.thenUsed() and endsAt(self.then, ending);
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
        return indexOfName(self.lines(), name);
    }

    /// Some way from its first line comes to an end, taking every gate as one that may hold or not.
    pub fn ends(self: *const Dialog) bool {
        var ending = Lines.initEmpty();
        var grew = true;
        while (grew) {
            grew = false;
            for (self.lines(), 0..) |*l, i| {
                if (ending.isSet(i) or !l.goesOn(&ending)) continue;
                ending.set(i);
                grew = true;
            }
        }
        return self.line_n == 0 or ending.isSet(0);
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
            inline else => |tag| @field(self, @tagName(tag))[0..@field(self, @tagName(tag) ++ "_n")],
        };
    }

    fn tableOf(self: *Script, t: Table) struct { items: []Name, n: *u8 } {
        return switch (t) {
            inline else => |tag| .{ .items = &@field(self, @tagName(tag)), .n = &@field(self, @tagName(tag) ++ "_n") },
        };
    }

    /// How many names table `t` holds at most.
    pub fn tableMax(t: Table) usize {
        return switch (t) {
            inline else => |tag| @typeInfo(@FieldType(Script, @tagName(tag))).array.len,
        };
    }

    pub fn find(self: *const Script, t: Table, name: []const u8) ?u8 {
        return indexOfName(self.names(t), name);
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
        return self.declare(t, freshName(&nb, @tagName(t), InTable{ .script = self, .table = t }, InTable.find));
    }

    pub fn rename(self: *Script, t: Table, i: u8, name: []const u8) bool {
        const tb = self.tableOf(t);
        return renameIn(tb.items[0..tb.n.*], i, name);
    }

    pub fn tableUsers(self: *const Script, t: Table, i: u8) usize {
        return self.refUsers(.{ .table = t }, i);
    }

    /// The conditions and actions whose `slot` is `i` of what `r` names.
    fn refUsers(self: *const Script, r: Ref, i: u8) usize {
        var n: usize = 0;
        var conds = self.condIter();
        while (conds.next()) |c| {
            if (refersTo(condRef(c.kind), r) and c.slot == i) n += 1;
        }
        var acts = self.actIter();
        while (acts.next()) |a| {
            if (refersTo(actRef(a.kind), r) and a.slot == i) n += 1;
        }
        return n;
    }

    /// Every `slot` past `i` of what `r` names moved down one, as `i` goes.
    fn lowerRefs(self: *Script, r: Ref, i: u8) void {
        var conds = self.condIterMut();
        while (conds.next()) |c| {
            if (refersTo(condRef(c.kind), r) and c.slot > i) c.slot -= 1;
        }
        var acts = self.actIterMut();
        while (acts.next()) |a| {
            if (refersTo(actRef(a.kind), r) and a.slot > i) a.slot -= 1;
        }
    }

    /// Refused while anything names it.
    pub fn undeclare(self: *Script, t: Table, i: u8) bool {
        if (self.tableUsers(t, i) > 0) return false;
        const tb = self.tableOf(t);
        cut(Name, tb.items, tb.n, i);
        self.lowerRefs(.{ .table = t }, i);
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

    /// Every condition it was named in can no longer hold.
    pub fn dropFolk(self: *Script, i: u8) void {
        cut(Folk, &self.folk, &self.folk_n, i);
        var conds = self.condIterMut();
        while (conds.next()) |c| {
            if (!refersTo(condRef(c.kind), .folk)) continue;
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

    /// Dialogs no way through ends, which never open.
    pub fn endless(self: *const Script) usize {
        var n: usize = 0;
        for (self.dialogs()) |*d| n += @intFromBool(!d.ends());
        return n;
    }

    /// Dialog `d` has a first line, and a way through it ends.
    pub fn opens(self: *const Script, d: u8) bool {
        return d < self.dialog_n and self.dialog[d].line_n > 0 and self.dialog[d].ends();
    }

    pub fn findDialog(self: *const Script, name: []const u8) ?u8 {
        return indexOfName(self.dialogs(), name);
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
        return n + self.refUsers(.dialog, d);
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
        self.lowerRefs(.dialog, d);
        return true;
    }

    pub fn triggers(self: *const Script) []const Trigger {
        return self.trigger[0..self.trigger_n];
    }

    pub fn findTrigger(self: *const Script, name: []const u8) ?u8 {
        return indexOfName(self.triggers(), name);
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
            for (all) |*nm| {
                if (!nm.valid() or !token(nm.text())) return false;
            }
            if (!distinct(all)) return false;
        }
        for (self.folks(), 0..) |*f, i| {
            if (f.node >= node_n or !grid.Level.inside(f.at) or !f.name.valid()) return false;
            if (f.dialog) |d| if (d >= self.dialog_n) return false;
            for (self.folks()[0..i]) |*other| if (other.node == f.node and other.at.eq(f.at)) return false;
        }
        for (self.dialogs()) |*d| {
            if (!d.name.valid() or !token(d.name.text()) or d.line_n == 0 or d.line_n > MAX_LINES) return false;
            for (d.lines()) |*l| {
                if (!l.name.valid() or !token(l.name.text()) or !l.who.valid() or !l.say.valid()) return false;
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
            if (!distinct(d.lines())) return false;
        }
        if (!distinct(self.dialogs())) return false;
        for (self.triggers()) |*t| {
            if (!t.name.valid() or !token(t.name.text()) or t.cond_n > MAX_CONDS or t.act_n > MAX_ACTS) return false;
            if (t.priority < -PRIORITY_MAX or t.priority > PRIORITY_MAX) return false;
            for (t.conds()) |*c| if (!self.condFits(c, node_n)) return false;
            for (t.acts()) |*a| if (!self.actFits(a)) return false;
        }
        return distinct(self.triggers());
    }

    fn slotFits(self: *const Script, r: ?Ref, slot: u8) bool {
        const ref = r orelse return true;
        return slot < switch (ref) {
            .table => |t| self.names(t).len,
            .folk => self.folk_n,
            .dialog => self.dialog_n,
        };
    }

    fn condFits(self: *const Script, c: *const Cond, node_n: usize) bool {
        if (!self.slotFits(condRef(c.kind), c.slot)) return false;
        if (c.n < -NUMBER_MAX or c.n > NUMBER_MAX) return false;
        return switch (c.kind) {
            .always, .never, .flag, .counter, .timer, .elapsed, .talked => true,
            .region => c.node < node_n and grid.Level.inside(c.from) and grid.Level.inside(c.to),
            .near => c.n >= 0 and c.n <= NEAR_MAX,
            .deaths, .alive => c.foe.stocked(),
        };
    }

    fn actFits(self: *const Script, a: *const Act) bool {
        if (!self.slotFits(actRef(a.kind), a.slot) or !a.note.valid()) return false;
        if (a.n < -NUMBER_MAX or a.n > NUMBER_MAX) return false;
        return switch (a.kind) {
            .timer, .wait => a.n >= 0,
            .dialog, .text, .flag, .counter, .preserve => true,
        };
    }
};

const InTable = struct {
    script: *const Script,
    table: Table,

    fn find(in: InTable, name: []const u8) ?u8 {
        return in.script.find(in.table, name);
    }
};

/// What a condition's or action's `slot` indexes.
pub const Ref = union(enum) { table: Table, folk, dialog };

pub fn condRef(k: CondKind) ?Ref {
    return switch (k) {
        inline .flag, .counter, .timer => |t| .{ .table = @field(Table, @tagName(t)) },
        .near => .folk,
        .talked => .dialog,
        .always, .never, .elapsed, .region, .deaths, .alive => null,
    };
}

pub fn actRef(k: ActKind) ?Ref {
    return switch (k) {
        inline .flag, .counter, .timer => |t| .{ .table = @field(Table, @tagName(t)) },
        .dialog => .dialog,
        .text, .wait, .preserve => null,
    };
}

fn refersTo(have: ?Ref, r: Ref) bool {
    const h = have orelse return false;
    return std.meta.eql(h, r);
}

comptime {
    for (std.enums.values(ActKind)) |k| std.debug.assert(!refersTo(actRef(k), .folk));
}

pub fn condTable(k: CondKind) ?Table {
    const r = condRef(k) orelse return null;
    return switch (r) {
        .table => |t| t,
        .folk, .dialog => null,
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
    mathx.removeAt(T, items, n, i, .{});
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
