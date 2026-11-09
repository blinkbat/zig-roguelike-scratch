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
pub const TITLE_MAX: usize = 32;

pub const MAX_QUESTS: usize = 12;
pub const MAX_STAGES: usize = 8;
pub const MAX_FLAGS: usize = 32;
pub const MAX_COUNTERS: usize = 32;
pub const MAX_TIMERS: usize = 16;
pub const MAX_NPCS: usize = 32;
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
pub const NEAR_DEFAULT: i32 = 2;
pub const PRIORITY_MAX: i8 = 99;
pub const END = "end";
pub const NONE = "-";

comptime {
    std.debug.assert(MAX_NPCS < std.math.maxInt(u8));
    std.debug.assert(@max(MAX_FLAGS, MAX_COUNTERS, MAX_TIMERS, MAX_DIALOGS, MAX_LINES, MAX_TRIGGERS, MAX_QUESTS, MAX_STAGES) <= std.math.maxInt(u8));
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
pub const Title = Words(TITLE_MAX);

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

/// The least and most a number may hold, both included.
pub const Span = struct {
    lo: i32,
    hi: i32,

    pub fn holds(s: Span, n: i64) bool {
        return n >= s.lo and n <= s.hi;
    }

    pub fn clamp(s: Span, n: i32) i32 {
        return std.math.clamp(n, s.lo, s.hi);
    }
};

const SIGNED_SPAN = Span{ .lo = -NUMBER_MAX, .hi = NUMBER_MAX };
const COUNT_SPAN = Span{ .lo = 0, .hi = NUMBER_MAX };
pub const PRIORITY = Span{ .lo = -PRIORITY_MAX, .hi = PRIORITY_MAX };

pub const CondKind = enum {
    always,
    never,
    flag,
    counter,
    timer,
    elapsed,
    region,
    near,
    talked,
    deaths,
    alive,
    quest,
    stage,

    /// What its `n` may hold.
    pub fn span(k: CondKind) Span {
        return switch (k) {
            .always, .never, .flag, .counter, .timer, .region, .talked, .quest => SIGNED_SPAN,
            .elapsed, .deaths, .alive => COUNT_SPAN,
            .near => .{ .lo = 0, .hi = NEAR_MAX },
            .stage => STAGE_SPAN,
        };
    }
};

/// Where a quest stands in a run: not yet given, under way at some stage, or finished.
pub const QuestState = enum { unstarted, active, done };

/// A quest's stage, counted from 1; 0 before it begins.
pub const STAGE_SPAN = Span{ .lo = 0, .hi = MAX_STAGES };

/// Each kind reads only its own fields; `slot` indexes the table its kind names.
pub const Cond = struct {
    kind: CondKind = .always,
    slot: u8 = 0,
    /// A flag set, or a timer run out.
    on: bool = true,
    state: QuestState = .active,
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
    quest,

    /// What a conversation's own lines may do; the rest steer a trigger's list.
    pub fn spoken(k: ActKind) bool {
        return switch (k) {
            .text, .flag, .counter, .timer, .quest => true,
            .dialog, .wait, .preserve => false,
        };
    }

    /// What its `n` may hold.
    pub fn span(k: ActKind) Span {
        return switch (k) {
            .dialog, .text, .flag, .counter, .preserve => SIGNED_SPAN,
            .timer, .wait => COUNT_SPAN,
            .quest => .{ .lo = 1, .hi = MAX_STAGES },
        };
    }
};

pub const Setop = enum { off, on, flip };
pub const Countop = enum { set, add, sub };
/// Brings a quest to stage `n`, beginning it if it had not begun, or finishes it.
pub const Questop = enum { stage, done };

pub const Act = struct {
    kind: ActKind = .preserve,
    slot: u8 = 0,
    setop: Setop = .on,
    countop: Countop = .set,
    questop: Questop = .stage,
    /// A counter's amount, a timer's or wait's turns, or a quest's stage.
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

    pub fn possible(self: *const Choice) bool {
        const g = self.gate orelse return true;
        return g.kind != .never;
    }
};

const Lines = std.StaticBitSet(MAX_LINES);
const EXITS = MAX_CHOICES + 1;

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

    fn exits(self: *const Line, out: *[EXITS]?u8) []const ?u8 {
        var n: usize = 0;
        for (self.choices()) |*c| {
            if (c.possible()) _ = mathx.push(?u8, out, &n, c.next);
        }
        if (self.thenUsed()) _ = mathx.push(?u8, out, &n, self.then);
        return out[0..n];
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

    /// Every line reachable from its first has some way to an end, taking every gate as one that may hold or not.
    pub fn ends(self: *const Dialog) bool {
        if (self.line_n == 0) return true;
        var ending = Lines.initEmpty();
        var grew = true;
        while (grew) {
            grew = false;
            for (self.lines(), 0..) |*l, i| {
                if (ending.isSet(i) or !self.goesOn(l, &ending)) continue;
                ending.set(i);
                grew = true;
            }
        }
        var reached = Lines.initEmpty();
        reached.set(0);
        var todo: [MAX_LINES]u8 = undefined;
        todo[0] = 0;
        var n: usize = 1;
        var buf: [EXITS]?u8 = undefined;
        while (n > 0) {
            n -= 1;
            const at = todo[n];
            if (!ending.isSet(at)) return false;
            for (self.line[at].exits(&buf)) |next| self.reach(next, &reached, &todo, &n);
        }
        return true;
    }

    fn lineOf(self: *const Dialog, next: ?u8) ?u8 {
        const at = next orelse return null;
        return if (at < self.line_n) at else null;
    }

    fn goesOn(self: *const Dialog, l: *const Line, ending: *const Lines) bool {
        var buf: [EXITS]?u8 = undefined;
        for (l.exits(&buf)) |next| {
            if (next == null) return true;
            if (self.lineOf(next)) |at| if (ending.isSet(at)) return true;
        }
        return false;
    }

    fn reach(self: *const Dialog, next: ?u8, reached: *Lines, todo: *[MAX_LINES]u8, n: *usize) void {
        const at = self.lineOf(next) orelse return;
        if (reached.isSet(at)) return;
        reached.set(at);
        _ = mathx.push(u8, todo, n, at);
    }

    pub fn addLine(self: *Dialog) ?u8 {
        var nb: [NAME_MAX]u8 = undefined;
        const line = Line{ .name = Name.of(freshName(&nb, "line", self, Dialog.findLine)) };
        if (!mathx.push(Line, &self.line, &self.line_n, line)) return null;
        return self.line_n - 1;
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

/// A stage past `gone` moves down onto the one it became, held to `keep`.
fn shiftStage(n: *i32, gone: i32, keep: Span) void {
    if (n.* > gone) n.* -= 1;
    n.* = keep.clamp(n.*);
}

fn swapped(at: *?u8, a: u8, b: u8) void {
    const v = at.* orelse return;
    if (v == a) at.* = b else if (v == b) at.* = a;
}

fn lowered(at: *?u8, gone: u8) void {
    const v = at.* orelse return;
    at.* = renumbered(v, gone);
}

/// Index `at` once the item at `gone` is removed from its list: null for that item, one less past it.
pub fn renumbered(at: anytype, gone: usize) ?@TypeOf(at) {
    if (at == gone) return null;
    return if (at > gone) at - 1 else at;
}

/// Where an NPC stands: a painted cell, or a place found afresh on each roll of its node.
pub const Spot = union(enum) {
    at: P,
    /// Beside the first of these props with free ground round it.
    by: grid.Tile,
    /// The open ground the longest walk from the node's doors.
    far,
};

/// A prop an NPC may stand `by`: upright, neither a shaped wall nor an opened chest; a wide prop by its head.
pub fn besideable(t: grid.Tile) bool {
    return t.upright() and !t.shaped() and !t.isPart() and !t.isOpened();
}

/// The prop an NPC placed beside `t` stands `by`: a wide prop's head for any of its pieces, null where none may.
pub fn besideOf(t: grid.Tile) ?grid.Tile {
    const head = t.whole();
    return if (besideable(head)) head else null;
}

/// Where each NPC placed on its node's roll stands, once it has.
pub const Stood = [MAX_NPCS]?P;

/// A body that talks: not a foe, it neither fights nor moves.
pub const Npc = struct {
    node: u8 = 0,
    spot: Spot = .far,
    /// Blank: `STRANGER`.
    name: Who = .{},
    dialog: ?u8 = null,
    /// Stands only while this holds.
    shows: ?Cond = null,
    /// Drawn as this body's picture; null, as a person.
    looks: ?actor.Kind = null,

    pub fn called(self: *const Npc) []const u8 {
        return if (self.name.n > 0) self.name.text() else STRANGER;
    }

    pub fn cell(self: *const Npc) ?P {
        return switch (self.spot) {
            .at => |p| p,
            .by, .far => null,
        };
    }
};
pub const STRANGER = "Stranger";

/// A quest the journal lists: its title, and what each stage asks.
pub const Quest = struct {
    pub const COUNTED = .{.{ "stage", "stage_n" }};
    name: Name = .{},
    title: Title = .{},
    stage: [MAX_STAGES]Note = @splat(.{}),
    stage_n: u8 = 0,

    pub fn stages(self: *const Quest) []const Note {
        return self.stage[0..self.stage_n];
    }

    /// The stages a `stage` condition (from 0) or a `quest` action (from 1) may name.
    pub fn reach(self: *const Quest, lo: i32) Span {
        return .{ .lo = lo, .hi = @max(lo, self.stage_n) };
    }

    /// What stage `n` asks; empty past its last stage.
    pub fn asks(self: *const Quest, n: i32) []const u8 {
        if (n < 1 or n > self.stage_n) return "";
        return self.stage[@intCast(n - 1)].text();
    }

    /// Blank: its name.
    pub fn titled(self: *const Quest) []const u8 {
        return if (self.title.n > 0) self.title.text() else self.name.text();
    }
};

pub const Table = enum { flag, counter, timer };

pub const Script = struct {
    pub const COUNTED = .{
        .{ "flag", "flag_n" },
        .{ "counter", "counter_n" },
        .{ "timer", "timer_n" },
        .{ "npc", "npc_n" },
        .{ "dialog", "dialog_n" },
        .{ "trigger", "trigger_n" },
        .{ "quest", "quest_n" },
    };
    pub const WAS = .{ .{ "npc", "folk" }, .{ "npc_n", "folk_n" } };
    flag: [MAX_FLAGS]Name = @splat(.{}),
    flag_n: u8 = 0,
    counter: [MAX_COUNTERS]Name = @splat(.{}),
    counter_n: u8 = 0,
    timer: [MAX_TIMERS]Name = @splat(.{}),
    timer_n: u8 = 0,
    npc: [MAX_NPCS]Npc = @splat(.{}),
    npc_n: u8 = 0,
    dialog: [MAX_DIALOGS]Dialog = @splat(.{}),
    dialog_n: u8 = 0,
    trigger: [MAX_TRIGGERS]Trigger = @splat(.{}),
    trigger_n: u8 = 0,
    quest: [MAX_QUESTS]Quest = @splat(.{}),
    quest_n: u8 = 0,

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
        if (!mathx.push(Name, tb.items, tb.n, Name.of(name))) return null;
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
            if (refersTo(condRef(c.kind), r)) c.slot = renumbered(c.slot, i) orelse c.slot;
        }
        var acts = self.actIterMut();
        while (acts.next()) |a| {
            if (refersTo(actRef(a.kind), r)) a.slot = renumbered(a.slot, i) orelse a.slot;
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

    pub fn npcs(self: *const Script) []const Npc {
        return self.npc[0..self.npc_n];
    }

    /// The NPC painted at `p` on node `node`; one placed afresh on each roll is never there.
    pub fn npcAt(self: *const Script, node: usize, p: P) ?u8 {
        for (self.npcs(), 0..) |*f, i| {
            const at = f.cell() orelse continue;
            if (f.node == node and at.eq(p)) return @intCast(i);
        }
        return null;
    }

    /// Where NPC `i` stands: its painted cell, else where `stood` keeps it on this roll.
    pub fn standsAt(self: *const Script, i: usize, stood: *const Stood) ?P {
        return self.npc[i].cell() orelse stood[i];
    }

    /// Drops every NPC `which.drops(npc)` picks, last first so each index still names its NPC; whether any went.
    pub fn dropNpcsWhere(self: *Script, which: anytype) bool {
        var dropped = false;
        var i: usize = self.npc_n;
        while (i > 0) {
            i -= 1;
            if (!which.drops(i, &self.npc[i])) continue;
            self.dropNpc(@intCast(i));
            dropped = true;
        }
        return dropped;
    }

    pub fn addNpc(self: *Script, f: Npc) ?u8 {
        if (f.cell()) |at| if (self.npcAt(f.node, at) != null) return null;
        if (!mathx.push(Npc, &self.npc, &self.npc_n, f)) return null;
        return self.npc_n - 1;
    }

    /// Every condition it was named in can no longer hold.
    pub fn dropNpc(self: *Script, i: u8) void {
        cut(Npc, &self.npc, &self.npc_n, i);
        var conds = self.condIterMut();
        while (conds.next()) |c| {
            if (!refersTo(condRef(c.kind), .npc)) continue;
            if (renumbered(c.slot, i)) |s| c.slot = s else c.* = .{ .kind = .never };
        }
    }

    /// Node `n` went: its NPCs with it, and every region drawn on it can no longer hold.
    pub fn dropNode(self: *Script, n: usize) void {
        _ = self.dropNpcsWhere(struct {
            node: usize,
            pub fn drops(on: @This(), _: usize, npc: *const Npc) bool {
                return npc.node == on.node;
            }
        }{ .node = n });
        for (self.npc[0..self.npc_n]) |*f| f.node = renumbered(f.node, n) orelse f.node;
        var conds = self.condIterMut();
        while (conds.next()) |c| {
            if (c.kind != .region) continue;
            if (renumbered(c.node, n)) |at| c.node = at else c.* = .{ .kind = .never };
        }
    }

    pub fn dialogs(self: *const Script) []const Dialog {
        return self.dialog[0..self.dialog_n];
    }

    /// Dialogs with a reachable line no way out of, which never open.
    pub fn endless(self: *const Script) usize {
        var n: usize = 0;
        for (self.dialogs()) |*d| n += @intFromBool(!d.ends());
        return n;
    }

    /// Dialog `d` has a first line, and every line reachable from it has a way to an end.
    pub fn opens(self: *const Script, d: u8) bool {
        return d < self.dialog_n and self.dialog[d].line_n > 0 and self.dialog[d].ends();
    }

    pub fn findDialog(self: *const Script, name: []const u8) ?u8 {
        return indexOfName(self.dialogs(), name);
    }

    /// A new dialog of one empty line, named after `stem` when it can be.
    pub fn addDialog(self: *Script, stem: []const u8) ?u8 {
        var nb: [NAME_MAX]u8 = undefined;
        const name = if (token(stem) and self.findDialog(stem) == null) stem else freshName(&nb, "dialog", self, Script.findDialog);
        if (!mathx.push(Dialog, &self.dialog, &self.dialog_n, .{ .name = Name.of(name) })) return null;
        const at = self.dialog_n - 1;
        _ = self.dialog[at].addLine();
        return at;
    }

    pub fn dialogUsers(self: *const Script, d: u8) usize {
        var n: usize = 0;
        for (self.npcs()) |f| {
            if (f.dialog == d) n += 1;
        }
        return n + self.refUsers(.dialog, d);
    }

    /// Refused while anything names it, so no reference is left pointing past the end.
    pub fn dropDialog(self: *Script, d: u8) bool {
        if (self.dialogUsers(d) > 0) return false;
        cut(Dialog, &self.dialog, &self.dialog_n, d);
        for (self.npc[0..self.npc_n]) |*f| lowered(&f.dialog, d);
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
        var nb: [NAME_MAX]u8 = undefined;
        var t = Trigger{ .name = Name.of(freshName(&nb, "trigger", self, Script.findTrigger)) };
        t.cond[0] = .{ .kind = .always };
        t.cond_n = 1;
        if (!mathx.push(Trigger, &self.trigger, &self.trigger_n, t)) return null;
        return self.trigger_n - 1;
    }

    pub fn dropTrigger(self: *Script, i: u8) void {
        cut(Trigger, &self.trigger, &self.trigger_n, i);
    }

    pub fn quests(self: *const Script) []const Quest {
        return self.quest[0..self.quest_n];
    }

    pub fn findQuest(self: *const Script, name: []const u8) ?u8 {
        return indexOfName(self.quests(), name);
    }

    /// A new quest of one blank stage.
    pub fn addQuest(self: *Script) ?u8 {
        var nb: [NAME_MAX]u8 = undefined;
        var q = Quest{ .name = Name.of(freshName(&nb, "quest", self, Script.findQuest)) };
        q.stage_n = 1;
        if (!mathx.push(Quest, &self.quest, &self.quest_n, q)) return null;
        return self.quest_n - 1;
    }

    pub fn questUsers(self: *const Script, q: u8) usize {
        return self.refUsers(.quest, q);
    }

    /// Refused while anything names it.
    pub fn dropQuest(self: *Script, q: u8) bool {
        if (self.questUsers(q) > 0) return false;
        cut(Quest, &self.quest, &self.quest_n, q);
        self.lowerRefs(.quest, q);
        return true;
    }

    /// Stage `k` (from 0) of quest `q` goes; whatever named a later stage names the one it became,
    /// and nothing names a stage past the last.
    pub fn dropStage(self: *Script, q: u8, k: u8) void {
        const qs = &self.quest[q];
        cut(Note, &qs.stage, &qs.stage_n, k);
        const gone: i32 = @as(i32, k) + 1;
        var conds = self.condIterMut();
        while (conds.next()) |c| {
            if (c.kind == .stage and c.slot == q) shiftStage(&c.n, gone, qs.reach(STAGE_SPAN.lo));
        }
        var acts = self.actIterMut();
        while (acts.next()) |a| {
            if (a.kind == .quest and a.slot == q) shiftStage(&a.n, gone, qs.reach(ActKind.span(.quest).lo));
        }
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
        if (!bounded(self)) return false;
        for (std.enums.values(Table)) |t| {
            const all = self.names(t);
            for (all) |*nm| {
                if (!nm.valid() or !token(nm.text())) return false;
            }
            if (!distinct(all)) return false;
        }
        for (self.npcs(), 0..) |*f, i| {
            if (f.node >= node_n or !f.name.valid()) return false;
            if (f.dialog) |d| if (d >= self.dialog_n) return false;
            if (f.shows) |*c| if (!self.condFits(c, node_n)) return false;
            if (f.spot == .by and !besideable(f.spot.by)) return false;
            const at = f.cell() orelse continue;
            if (!grid.Level.inside(at)) return false;
            if ((self.npcAt(f.node, at) orelse return false) != i) return false;
        }
        for (self.quests()) |*q| {
            if (!q.name.valid() or !token(q.name.text()) or !q.title.valid() or !bounded(q)) return false;
            for (q.stages()) |*st| if (!st.valid()) return false;
        }
        if (!distinct(self.quests())) return false;
        for (self.dialogs()) |*d| {
            if (!d.name.valid() or !token(d.name.text()) or d.line_n == 0 or !bounded(d)) return false;
            for (d.lines()) |*l| {
                if (!l.name.valid() or !token(l.name.text()) or !l.who.valid() or !l.say.valid()) return false;
                if (!bounded(l)) return false;
                if (l.then) |t| if (t >= d.line_n) return false;
                for (l.acts()) |*a| if (!a.kind.spoken() or !self.actFits(a)) return false;
                for (l.choices()) |*c| {
                    if (!c.ask.valid() or !bounded(c)) return false;
                    if (c.next) |nx| if (nx >= d.line_n) return false;
                    if (c.gate) |*gt| if (!self.condFits(gt, node_n)) return false;
                    for (c.acts()) |*a| if (!a.kind.spoken() or !self.actFits(a)) return false;
                }
            }
            if (!distinct(d.lines())) return false;
        }
        if (!distinct(self.dialogs())) return false;
        for (self.triggers()) |*t| {
            if (!t.name.valid() or !token(t.name.text()) or !bounded(t)) return false;
            if (!PRIORITY.holds(t.priority)) return false;
            for (t.conds()) |*c| if (!self.condFits(c, node_n)) return false;
            for (t.acts()) |*a| if (!self.actFits(a)) return false;
        }
        return distinct(self.triggers());
    }

    /// How many entries the list `r` names holds.
    pub fn refLen(self: *const Script, r: Ref) usize {
        return switch (r) {
            .table => |t| self.names(t).len,
            .npc => self.npc_n,
            .dialog => self.dialog_n,
            .quest => self.quest_n,
        };
    }

    fn slotFits(self: *const Script, r: ?Ref, slot: u8) bool {
        return slot < self.refLen(r orelse return true);
    }

    fn condFits(self: *const Script, c: *const Cond, node_n: usize) bool {
        if (!self.slotFits(condRef(c.kind), c.slot)) return false;
        if (!c.kind.span().holds(c.n)) return false;
        return switch (c.kind) {
            .always, .never, .flag, .counter, .timer, .elapsed, .talked, .near, .quest => true,
            .stage => self.quest[c.slot].reach(STAGE_SPAN.lo).holds(c.n),
            .region => c.node < node_n and grid.Level.inside(c.from) and grid.Level.inside(c.to),
            .deaths, .alive => c.foe.stocked(),
        };
    }

    fn actFits(self: *const Script, a: *const Act) bool {
        if (!self.slotFits(actRef(a.kind), a.slot) or !a.note.valid()) return false;
        if (a.kind == .quest and a.questop == .stage and !self.quest[a.slot].reach(ActKind.span(.quest).lo).holds(a.n)) return false;
        return a.kind.span().holds(a.n);
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
pub const Ref = union(enum) { table: Table, npc, dialog, quest };

pub fn condRef(k: CondKind) ?Ref {
    return switch (k) {
        inline .flag, .counter, .timer => |t| .{ .table = @field(Table, @tagName(t)) },
        .near => .npc,
        .talked => .dialog,
        .quest, .stage => .quest,
        .always, .never, .elapsed, .region, .deaths, .alive => null,
    };
}

pub fn actRef(k: ActKind) ?Ref {
    return switch (k) {
        inline .flag, .counter, .timer => |t| .{ .table = @field(Table, @tagName(t)) },
        .dialog => .dialog,
        .quest => .quest,
        .text, .wait, .preserve => null,
    };
}

fn refersTo(have: ?Ref, r: Ref) bool {
    const h = have orelse return false;
    return std.meta.eql(h, r);
}

comptime {
    for (std.enums.values(ActKind)) |k| std.debug.assert(!refersTo(actRef(k), .npc));
}

pub fn condTable(k: CondKind) ?Table {
    const r = condRef(k) orelse return null;
    return switch (r) {
        .table => |t| t,
        .npc, .dialog, .quest => null,
    };
}

/// Every condition in a script: the triggers', each dialog's choice gates, then what each NPC stands while.
pub fn CondIter(comptime S: type, comptime C: type) type {
    return struct {
        s: S,
        trigger: usize = 0,
        cond: usize = 0,
        dialog: usize = 0,
        line: usize = 0,
        choice: usize = 0,
        npc: usize = 0,

        pub fn next(self: *@This()) ?C {
            return self.spoken() orelse while (self.npc < self.s.npc_n) {
                self.npc += 1;
                if (self.s.npc[self.npc - 1].shows) |*c| break c;
            } else null;
        }

        fn spoken(self: *@This()) ?C {
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

fn bounded(x: anytype) bool {
    inline for (@TypeOf(x.*).COUNTED) |c| {
        if (@field(x, c[1]) > @field(x, c[0]).len) return false;
    }
    return true;
}

test "dropping an NPC, a node or a line leaves no reference past the end" {
    var s = Script{};
    _ = s.addNpc(.{ .node = 0, .spot = .{ .at = .{ .x = 3, .y = 3 } } }).?;
    _ = s.addNpc(.{ .node = 1, .spot = .{ .at = .{ .x = 4, .y = 4 } } }).?;
    _ = s.addNpc(.{ .node = 2, .spot = .{ .at = .{ .x = 5, .y = 5 } } }).?;
    const t = s.addTrigger().?;
    s.trigger[t].cond[0] = .{ .kind = .near, .slot = 2, .n = 3 };
    s.trigger[t].cond[1] = .{ .kind = .region, .node = 1, .from = .{ .x = 0, .y = 0 }, .to = .{ .x = 9, .y = 9 } };
    s.trigger[t].cond[2] = .{ .kind = .region, .node = 2 };
    s.trigger[t].cond_n = 3;
    s.dropNode(1);
    try std.testing.expectEqual(@as(u8, 2), s.npc_n);
    try std.testing.expectEqual(@as(u8, 1), s.npc[1].node);
    try std.testing.expectEqual(@as(u8, 1), s.trigger[t].cond[0].slot);
    try std.testing.expectEqual(CondKind.never, s.trigger[t].cond[1].kind);
    try std.testing.expectEqual(@as(u8, 1), s.trigger[t].cond[2].node);
    s.dropNpc(1);
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
    std.debug.print("script references: node, NPC and line removal renumber or retire every reference\n", .{});
}

test "a quest cannot go while named, and dropping a stage moves later references down onto the one it became" {
    var s = Script{};
    const q = s.addQuest().?;
    _ = s.addQuest().?;
    s.quest[q].stage_n = 3;
    const t = s.addTrigger().?;
    s.trigger[t].cond[0] = .{ .kind = .stage, .slot = q, .cmp = .ge, .n = 3 };
    s.trigger[t].act[0] = .{ .kind = .quest, .slot = q, .n = 2 };
    s.trigger[t].act[1] = .{ .kind = .quest, .slot = q, .n = 1 };
    s.trigger[t].act_n = 2;
    try std.testing.expectEqual(@as(usize, 3), s.questUsers(q));
    try std.testing.expect(!s.dropQuest(q));
    s.dropStage(q, 1);
    try std.testing.expectEqual(@as(u8, 2), s.quest[q].stage_n);
    try std.testing.expectEqual(@as(i32, 2), s.trigger[t].cond[0].n);
    try std.testing.expectEqual(@as(i32, 2), s.trigger[t].act[0].n);
    try std.testing.expectEqual(@as(i32, 1), s.trigger[t].act[1].n);
    const f = s.coin(.flag).?;
    _ = s.addNpc(.{ .shows = .{ .kind = .flag, .slot = f } }).?;
    try std.testing.expectEqual(@as(usize, 1), s.tableUsers(.flag, f));
    try std.testing.expect(s.dropQuest(1));
    s.dropTrigger(t);
    try std.testing.expect(s.dropQuest(q));
    try std.testing.expect(s.valid(1));
}

test "dropping a quest's last stage leaves nothing naming a stage past it" {
    var s = Script{};
    const q = s.addQuest().?;
    s.quest[q].stage_n = 2;
    const t = s.addTrigger().?;
    s.trigger[t].cond[0] = .{ .kind = .stage, .slot = q, .cmp = .ge, .n = 2 };
    s.trigger[t].act[0] = .{ .kind = .quest, .slot = q, .n = 2 };
    s.trigger[t].act_n = 1;
    s.dropStage(q, 1);
    try std.testing.expectEqual(@as(u8, 1), s.quest[q].stage_n);
    try std.testing.expectEqual(@as(i32, 1), s.trigger[t].cond[0].n);
    try std.testing.expectEqual(@as(i32, 1), s.trigger[t].act[0].n);
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
