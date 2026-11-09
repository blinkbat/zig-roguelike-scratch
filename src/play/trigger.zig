const std = @import("std");
const mathx = @import("../core/mathx.zig");
const actor = @import("actor.zig");
const log = @import("log.zig");
const script = @import("../map/script.zig");
const P = mathx.P;
const Script = script.Script;

/// What the conditions read of the run as it stands.
pub const World = struct {
    node: usize = 0,
    hero: P = .{ .x = 0, .y = 0 },
    /// Living, by family, on the hero's node.
    alive: std.EnumArray(actor.Kind, u32) = .initFill(0),
};

pub const Timer = struct { left: i32 = 0, armed: bool = false };

/// A trigger's place in its own list.
pub const Run = struct {
    fired: bool = false,
    running: bool = false,
    at: u8 = 0,
    wait: i32 = 0,
    /// Waiting on the conversation its `dialog` asked for.
    held: bool = false,
    preserved: bool = false,
    /// The turn it last finished, so a kept trigger runs at most once a turn.
    last: ?u32 = null,
};

pub const QUEST_BEGUN = "New quest: {s}.";
pub const QUEST_MOVED = "Quest updated: {s}.";
pub const QUEST_DONE = "Quest complete: {s}.";

/// The conversation on screen.
pub const Talk = struct {
    pub const WAS = .{.{ "npc", "folk" }};
    dialog: u8,
    line: u8 = 0,
    cursor: u8 = 0,
    npc: ?u8 = null,
};

/// A quest's place in the run; its stage stays when it is done.
pub const Progress = struct {
    state: script.QuestState = .unstarted,
    stage: u8 = 0,
};

/// SC1's switches, counters and timers, each trigger's progress, quests and the one conversation that may be up.
pub const Runtime = struct {
    flags: [script.MAX_FLAGS]bool = @splat(false),
    counters: [script.MAX_COUNTERS]i32 = @splat(0),
    timers: [script.MAX_TIMERS]Timer = @splat(.{}),
    deaths: std.EnumArray(actor.Kind, u32) = .initFill(0),
    turns: u32 = 0,
    talked: [script.MAX_DIALOGS]bool = @splat(false),
    runs: [script.MAX_TRIGGERS]Run = @splat(.{}),
    /// A dialog a trigger asked for, opened once the turn is drawn.
    asked: ?u8 = null,
    talk: ?Talk = null,
    quests: [script.MAX_QUESTS]Progress = @splat(.{}),
    /// Where each NPC placed on its node's roll was first stood this run.
    spots: script.Stood = @splat(null),

    pub fn died(self: *Runtime, k: actor.Kind) void {
        self.deaths.getPtr(k.family()).* +|= 1;
    }

    /// NPC `i` stands while what it `shows` holds.
    pub fn shows(self: *const Runtime, s: *const Script, i: usize, w: World) bool {
        const c = s.npc[i].shows orelse return true;
        return self.holds(s, &c, w);
    }

    /// Where NPC `i` stands, once it has stood anywhere.
    pub fn spotOf(self: *const Runtime, s: *const Script, i: usize) ?P {
        return s.standsAt(i, &self.spots);
    }

    /// A spent turn: timers and waits count down, then every trigger is looked at.
    pub fn turn(self: *Runtime, s: *const Script, w: World, l: *log.Log) void {
        self.turns +|= 1;
        for (&self.timers) |*t| {
            if (t.armed and t.left > 0) t.left -= 1;
        }
        for (&self.runs) |*r| {
            if (r.running and r.wait > 0) r.wait -= 1;
        }
        self.evaluate(s, w, l);
    }

    /// Without time passing: on arrival, and once a conversation closes.
    pub fn evaluate(self: *Runtime, s: *const Script, w: World, l: *log.Log) void {
        var buf: [script.MAX_TRIGGERS]u8 = undefined;
        for (ordered(s, &buf)) |ti| {
            const t = &s.trigger[ti];
            const r = &self.runs[ti];
            if (t.parked) continue;
            if (r.running) {
                self.advance(s, ti, l);
                continue;
            }
            if (t.once and r.fired) continue;
            if (r.last) |last| if (last == self.turns) continue;
            if (!self.satisfied(s, t, w)) continue;
            r.* = .{ .fired = r.fired, .running = true, .last = r.last };
            self.advance(s, ti, l);
        }
    }

    fn satisfied(self: *const Runtime, s: *const Script, t: *const script.Trigger, w: World) bool {
        if (t.cond_n == 0) return false;
        for (t.conds()) |*c| {
            if (!self.holds(s, c, w)) return false;
        }
        return true;
    }

    pub fn holds(self: *const Runtime, s: *const Script, c: *const script.Cond, w: World) bool {
        return switch (c.kind) {
            .always => true,
            .never => false,
            .flag => self.flags[c.slot] == c.on,
            .counter => c.cmp.holds(self.counters[c.slot], c.n),
            .timer => self.timers[c.slot].armed and (self.timers[c.slot].left == 0) == c.on,
            .elapsed => c.cmp.holds(self.turns, c.n),
            .region => w.node == c.node and c.region().holds(w.hero),
            .near => blk: {
                const at = self.spotOf(s, c.slot) orelse break :blk false;
                break :blk s.npc[c.slot].node == w.node and mathx.dist(at, w.hero) <= c.n;
            },
            .talked => self.talked[c.slot],
            .deaths => c.cmp.holds(self.deaths.get(c.foe.family()), c.n),
            .alive => c.cmp.holds(w.alive.get(c.foe.family()), c.n),
            .quest => self.quests[c.slot].state == c.state,
            .stage => c.cmp.holds(self.quests[c.slot].stage, c.n),
        };
    }

    fn advance(self: *Runtime, s: *const Script, ti: usize, l: *log.Log) void {
        const r = &self.runs[ti];
        if (r.held or r.wait > 0) return;
        const t = &s.trigger[ti];
        while (r.at < t.act_n) {
            const a = &t.act[r.at];
            switch (a.kind) {
                .dialog => {
                    if (!s.opens(a.slot)) {
                        r.at += 1;
                        continue;
                    }
                    if (self.asked != null or self.talk != null) return;
                    r.at += 1;
                    r.held = true;
                    self.asked = a.slot;
                    return;
                },
                .wait => {
                    r.at += 1;
                    r.wait = a.n;
                    if (r.wait > 0) return;
                },
                .preserve => {
                    r.at += 1;
                    r.preserved = true;
                },
                .text, .flag, .counter, .timer, .quest => {
                    r.at += 1;
                    self.apply(s, a, l);
                },
            }
        }
        r.running = false;
        r.last = self.turns;
        if (!r.preserved) r.fired = true;
    }

    pub fn apply(self: *Runtime, s: *const Script, a: *const script.Act, l: *log.Log) void {
        switch (a.kind) {
            .dialog, .wait, .preserve => {},
            .quest => self.advanceQuest(s, a, l),
            .text => l.say("{s}", .{a.note.text()}),
            .flag => self.flags[a.slot] = switch (a.setop) {
                .off => false,
                .on => true,
                .flip => !self.flags[a.slot],
            },
            .counter => {
                const at = &self.counters[a.slot];
                at.* = switch (a.countop) {
                    .set => a.n,
                    .add => at.* +| a.n,
                    .sub => at.* -| a.n,
                };
            },
            .timer => self.timers[a.slot] = .{ .left = a.n, .armed = true },
        }
    }

    /// A finished quest stays finished; a stage it already stands at says nothing.
    fn advanceQuest(self: *Runtime, s: *const Script, a: *const script.Act, l: *log.Log) void {
        const q = &self.quests[a.slot];
        const title = s.quest[a.slot].titled();
        if (q.state == .done) return;
        switch (a.questop) {
            .done => {
                q.state = .done;
                l.say(QUEST_DONE, .{title});
            },
            .stage => {
                const n: u8 = @intCast(a.n);
                if (q.state == .active and q.stage == n) return;
                const was = q.state;
                q.* = .{ .state = .active, .stage = n };
                if (was == .unstarted) l.say(QUEST_BEGUN, .{title}) else l.say(QUEST_MOVED, .{title});
            },
        }
    }

    /// The dialog a trigger asked for, taken to be opened.
    pub fn takeAsked(self: *Runtime) ?u8 {
        const d = self.asked orelse return null;
        self.asked = null;
        return d;
    }

    /// Opens dialog `d` at its first line, its actions done; refused while one is up, or when a line it reaches has no way to an end.
    pub fn open(self: *Runtime, s: *const Script, d: u8, npc: ?u8, l: *log.Log) bool {
        if (self.talk != null or !s.opens(d)) return false;
        self.talk = .{ .dialog = d, .npc = npc };
        self.enter(s, l);
        return true;
    }

    fn enter(self: *Runtime, s: *const Script, l: *log.Log) void {
        const t = &self.talk.?;
        t.cursor = 0;
        for (s.dialog[t.dialog].line[t.line].acts()) |*a| self.apply(s, a, l);
    }

    pub fn lineOf(self: *const Runtime, s: *const Script) ?*const script.Line {
        const t = self.talk orelse return null;
        return &s.dialog[t.dialog].line[t.line];
    }

    /// Who the line names, else whoever was spoken to; empty when neither.
    pub fn speaker(self: *const Runtime, s: *const Script) []const u8 {
        const ln = self.lineOf(s) orelse return "";
        if (ln.who.n > 0) return ln.who.text();
        const f = self.talk.?.npc orelse return "";
        return s.npc[f].called();
    }

    /// The choices whose gates hold, in order; a hidden one is not offered at all.
    pub fn offered(self: *const Runtime, s: *const Script, w: World, out: *[script.MAX_CHOICES]u8) []const u8 {
        const ln = self.lineOf(s) orelse return out[0..0];
        var n: usize = 0;
        for (ln.choices(), 0..) |*c, i| {
            if (c.gate) |*g| if (!self.holds(s, g, w)) continue;
            _ = mathx.push(u8, out, &n, @intCast(i));
        }
        return out[0..n];
    }

    pub fn moveCursor(self: *Runtime, s: *const Script, w: World, by: i32) void {
        var buf: [script.MAX_CHOICES]u8 = undefined;
        const n = self.offered(s, w, &buf).len;
        if (n == 0) return;
        const t = &self.talk.?;
        t.cursor = @intCast(mathx.nudge(t.cursor, by, n));
    }

    /// Takes offered row `row`, or goes on from a line with nothing offered; past the end, nothing.
    pub fn pick(self: *Runtime, s: *const Script, row: usize, w: World, l: *log.Log) void {
        const ln = self.lineOf(s) orelse return;
        var buf: [script.MAX_CHOICES]u8 = undefined;
        const shown = self.offered(s, w, &buf);
        if (shown.len == 0) return self.go(s, ln.then, w, l);
        if (row >= shown.len) return;
        const c = &ln.choice[shown[row]];
        for (c.acts()) |*a| self.apply(s, a, l);
        self.go(s, c.next, w, l);
    }

    pub fn confirm(self: *Runtime, s: *const Script, w: World, l: *log.Log) void {
        const t = self.talk orelse return;
        self.pick(s, t.cursor, w, l);
    }

    fn go(self: *Runtime, s: *const Script, next: ?u8, w: World, l: *log.Log) void {
        const n = next orelse return self.close(s, w, l);
        self.talk.?.line = n;
        self.enter(s, l);
    }

    /// Left only through one of its endings, so `talked` means it was heard out; the lists it held go on.
    fn close(self: *Runtime, s: *const Script, w: World, l: *log.Log) void {
        self.talked[self.talk.?.dialog] = true;
        self.talk = null;
        for (&self.runs) |*r| r.held = false;
        self.evaluate(s, w, l);
    }
};

/// Higher priority first, file order breaking ties.
fn ordered(s: *const Script, buf: *[script.MAX_TRIGGERS]u8) []const u8 {
    const ord = buf[0..s.trigger_n];
    for (ord, 0..) |*o, i| o.* = @intCast(i);
    std.sort.insertion(u8, ord, s, before);
    return ord;
}

fn before(s: *const Script, a: u8, b: u8) bool {
    return s.trigger[a].priority > s.trigger[b].priority;
}

const script_text = @import("../map/script_text.zig");

const Test = struct {
    s: Script = .{},
    rt: Runtime = .{},
    l: log.Log = .{},

    fn of(text: []const u8) !*Test {
        const t = try std.testing.allocator.create(Test);
        t.* = .{};
        script_text.readAlone(text, &t.s, 2) catch |e| {
            std.testing.allocator.destroy(t);
            return e;
        };
        return t;
    }

    fn done(t: *Test) void {
        std.testing.allocator.destroy(t);
    }

    fn counter(t: *const Test, name: []const u8) i32 {
        return t.rt.counters[t.s.find(.counter, name).?];
    }

    fn flag(t: *const Test, name: []const u8) bool {
        return t.rt.flags[t.s.find(.flag, name).?];
    }

    fn turns(t: *Test, n: usize, w: World) void {
        for (0..n) |_| t.rt.turn(&t.s, w, &t.l);
    }
};

test "every condition must hold, and a trigger with none never fires" {
    const t = try Test.of(
        \\flag a
        \\flag b
        \\counter hits
        \\trigger both 0 once live
        \\when flag a on
        \\when flag b on
        \\do counter hits add 1
        \\trigger naked 0 once live
        \\do counter hits add 100
    );
    defer t.done();
    t.turns(1, .{});
    try std.testing.expectEqual(@as(i32, 0), t.counter("hits"));
    t.rt.flags[0] = true;
    t.turns(1, .{});
    try std.testing.expectEqual(@as(i32, 0), t.counter("hits"));
    t.rt.flags[1] = true;
    t.turns(3, .{});
    try std.testing.expectEqual(@as(i32, 1), t.counter("hits"));
}

test "a kept trigger runs once a turn, however often it is looked at; a parked one never" {
    const t = try Test.of(
        \\counter a
        \\counter b
        \\counter c
        \\trigger once 0 once live
        \\when always
        \\do counter a add 1
        \\trigger kept 0 repeats live
        \\when always
        \\do counter b add 1
        \\trigger draft 0 repeats parked
        \\when always
        \\do counter c add 1
    );
    defer t.done();
    for (0..4) |_| {
        t.turns(1, .{});
        t.rt.evaluate(&t.s, .{}, &t.l);
        t.rt.evaluate(&t.s, .{}, &t.l);
    }
    try std.testing.expectEqual(@as(i32, 1), t.counter("a"));
    try std.testing.expectEqual(@as(i32, 4), t.counter("b"));
    try std.testing.expectEqual(@as(i32, 0), t.counter("c"));
}

test "priority decides who runs first, and file order breaks the tie" {
    const t = try Test.of(
        \\counter seq
        \\trigger low 1 once live
        \\when always
        \\do counter seq set 1
        \\trigger high 9 once live
        \\when always
        \\do counter seq set 2
        \\trigger tie 1 once live
        \\when always
        \\do counter seq add 10
    );
    defer t.done();
    t.turns(1, .{});
    try std.testing.expectEqual(@as(i32, 11), t.counter("seq"));
}

test "a wait holds its own list for its turns and nothing else" {
    const t = try Test.of(
        \\counter a
        \\counter b
        \\trigger slow 0 once live
        \\when always
        \\do counter a set 1
        \\do wait 2
        \\do counter a set 2
        \\trigger quick 0 once live
        \\when always
        \\do counter b set 1
    );
    defer t.done();
    t.turns(1, .{});
    try std.testing.expectEqual(@as(i32, 1), t.counter("a"));
    try std.testing.expectEqual(@as(i32, 1), t.counter("b"));
    t.turns(1, .{});
    try std.testing.expectEqual(@as(i32, 1), t.counter("a"));
    t.turns(1, .{});
    try std.testing.expectEqual(@as(i32, 2), t.counter("a"));
}

test "a dialog action holds its list until the conversation is heard out, and a second waits its turn" {
    const t = try Test.of(
        \\flag done
        \\flag after
        \\dialog first
        \\line root
        \\say Well met.
        \\dialog second
        \\line root
        \\say Again.
        \\trigger talk 5 once live
        \\when always
        \\do dialog first
        \\do flag done on
        \\trigger next 0 once live
        \\when always
        \\do dialog second
        \\trigger heard 0 once live
        \\when talked first
        \\do flag after on
    );
    defer t.done();
    t.turns(1, .{});
    try std.testing.expectEqual(@as(?u8, 0), t.rt.takeAsked());
    try std.testing.expect(t.rt.open(&t.s, 0, null, &t.l));
    t.turns(1, .{});
    try std.testing.expect(!t.flag("done"));
    try std.testing.expectEqual(@as(?u8, null), t.rt.asked);
    t.rt.confirm(&t.s, .{}, &t.l);
    try std.testing.expect(t.rt.talk == null);
    try std.testing.expect(t.flag("done"));
    try std.testing.expect(t.flag("after"));
    try std.testing.expectEqual(@as(?u8, 1), t.rt.takeAsked());
}

test "a timer nobody started is neither running nor done, and one runs out in its turns" {
    const t = try Test.of(
        \\flag rang
        \\flag ticking
        \\timer dusk
        \\trigger ring 0 once live
        \\when timer dusk done
        \\do flag rang on
        \\trigger tick 0 once live
        \\when timer dusk running
        \\do flag ticking on
        \\trigger start 0 once live
        \\when elapsed >= 2
        \\do timer dusk 3
    );
    defer t.done();
    t.turns(1, .{});
    try std.testing.expect(!t.flag("rang") and !t.flag("ticking"));
    t.turns(2, .{});
    try std.testing.expect(t.flag("ticking") and !t.flag("rang"));
    t.turns(1, .{});
    try std.testing.expect(!t.flag("rang"));
    t.turns(1, .{});
    try std.testing.expect(t.flag("rang"));
}

test "region and near read the hero's own node; deaths and alive count a whole family" {
    const t = try Test.of(
        \\flag inside
        \\flag close
        \\flag cleared
        \\npc 1 10 10 -
        \\trigger box 0 once live
        \\when region 1 2 2 4 4
        \\do flag inside on
        \\trigger met 0 once live
        \\when near 0 2
        \\do flag close on
        \\trigger slimes 0 once live
        \\when deaths slime >= 3
        \\when alive slime = 0
        \\do flag cleared on
    );
    defer t.done();
    t.turns(1, .{ .node = 0, .hero = .{ .x = 3, .y = 3 } });
    t.turns(1, .{ .node = 1, .hero = .{ .x = 13, .y = 8 } });
    try std.testing.expect(!t.flag("inside") and !t.flag("close"));
    t.turns(1, .{ .node = 1, .hero = .{ .x = 4, .y = 2 } });
    try std.testing.expect(t.flag("inside"));
    t.turns(1, .{ .node = 1, .hero = .{ .x = 12, .y = 12 } });
    try std.testing.expect(t.flag("close"));
    var w = World{};
    w.alive.set(.slime, 1);
    t.rt.died(.slime);
    t.rt.died(.slime_half);
    t.rt.died(.slime_quarter);
    t.turns(1, w);
    try std.testing.expect(!t.flag("cleared"));
    w.alive.set(.slime, 0);
    t.turns(1, w);
    try std.testing.expect(t.flag("cleared"));
}

test "a conversation walks its lines: gates hide choices, numbering follows what is offered, actions land on arrival and pick" {
    const t = try Test.of(
        \\flag gate_open
        \\flag told
        \\counter coins
        \\dialog hunter
        \\line root
        \\who The Hunter
        \\say You have the look of one who walks a long road alone.
        \\ask The way north? -> north
        \\ask Through the gate. -> gate
        \\need flag gate_open on
        \\ask Nothing. -> end
        \\gets counter coins add 3
        \\line north
        \\say North the great gate stands shut.
        \\act flag told on
        \\then root
        \\line gate
        \\say Then go.
        \\npc 0 5 5 hunter Old Hunter
    );
    defer t.done();
    var buf: [script.MAX_CHOICES]u8 = undefined;
    try std.testing.expect(t.rt.open(&t.s, 0, 0, &t.l));
    try std.testing.expect(!t.rt.open(&t.s, 0, 0, &t.l));
    try std.testing.expectEqualStrings("The Hunter", t.rt.speaker(&t.s));
    try std.testing.expectEqual(@as(usize, 2), t.rt.offered(&t.s, .{}, &buf).len);
    t.rt.moveCursor(&t.s, .{}, 5);
    try std.testing.expectEqual(@as(u8, 1), t.rt.talk.?.cursor);
    t.rt.pick(&t.s, 0, .{}, &t.l);
    try std.testing.expect(t.flag("told"));
    try std.testing.expectEqualStrings("Old Hunter", t.rt.speaker(&t.s));
    t.rt.confirm(&t.s, .{}, &t.l);
    try std.testing.expectEqual(@as(u8, 0), t.rt.talk.?.line);
    t.rt.flags[t.s.find(.flag, "gate_open").?] = true;
    const shown = t.rt.offered(&t.s, .{}, &buf);
    try std.testing.expectEqual(@as(usize, 3), shown.len);
    try std.testing.expectEqual(@as(u8, 1), shown[1]);
    t.rt.pick(&t.s, 3, .{}, &t.l);
    try std.testing.expect(t.rt.talk != null);
    t.rt.pick(&t.s, 2, .{}, &t.l);
    try std.testing.expect(t.rt.talk == null);
    try std.testing.expectEqual(@as(i32, 3), t.counter("coins"));
    try std.testing.expect(t.rt.talked[0]);
}

test "a quest begins at a stage, moves on, finishes for good, and its conditions read where it stands" {
    const t = try Test.of(
        \\flag begun
        \\flag late
        \\flag finished
        \\quest pib The Stolen Pib
        \\stage Find it.
        \\stage Bring it back.
        \\trigger begun 0 once live
        \\when quest pib active
        \\do flag begun on
        \\trigger late 0 once live
        \\when stage pib >= 2
        \\do flag late on
        \\trigger finished 0 once live
        \\when quest pib done
        \\do flag finished on
    );
    defer t.done();
    const q = t.s.findQuest("pib").?;
    t.turns(1, .{});
    try std.testing.expect(!t.flag("begun"));
    t.rt.apply(&t.s, &.{ .kind = .quest, .slot = q, .n = 1 }, &t.l);
    t.rt.apply(&t.s, &.{ .kind = .quest, .slot = q, .n = 1 }, &t.l);
    t.turns(1, .{});
    try std.testing.expect(t.flag("begun") and !t.flag("late"));
    t.rt.apply(&t.s, &.{ .kind = .quest, .slot = q, .n = 2 }, &t.l);
    t.rt.apply(&t.s, &.{ .kind = .quest, .slot = q, .questop = .done, .n = 1 }, &t.l);
    t.rt.apply(&t.s, &.{ .kind = .quest, .slot = q, .n = 1 }, &t.l);
    t.turns(1, .{});
    try std.testing.expect(t.flag("late") and t.flag("finished"));
    try std.testing.expectEqual(Progress{ .state = .done, .stage = 2 }, t.rt.quests[q]);
    try std.testing.expectEqualStrings("New quest: The Stolen Pib.", t.l.line(2).?);
    try std.testing.expectEqualStrings("Quest updated: The Stolen Pib.", t.l.line(1).?);
    try std.testing.expectEqualStrings("Quest complete: The Stolen Pib.", t.l.line(0).?);
    try std.testing.expectEqual(@as(?[]const u8, null), t.l.line(3));
}

test "a counter saturates rather than wrapping, and a text action reaches the log" {
    const t = try Test.of(
        \\counter n
        \\trigger big 0 once live
        \\when always
        \\do counter n set 9999
        \\do text The gate grinds open somewhere to the north.
    );
    defer t.done();
    t.turns(1, .{});
    t.rt.counters[0] = std.math.maxInt(i32);
    t.rt.apply(&t.s, &.{ .kind = .counter, .countop = .add, .n = 5 }, &t.l);
    try std.testing.expectEqual(std.math.maxInt(i32), t.counter("n"));
    try std.testing.expectEqualStrings("The gate grinds open somewhere to the north.", t.l.line(0).?);
    std.debug.print("trigger runtime: saturating counter and text action checked\n", .{});
}
