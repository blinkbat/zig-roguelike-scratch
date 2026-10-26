const std = @import("std");
const actor = @import("actor.zig");
const skillbar = @import("skillbar.zig");

/// What took life off the hero.
pub const Source = union(enum) {
    foe: actor.Kind,
    gas,
    burn,
    bleed,
};

pub const Hurt = struct {
    by: Source,
    dmg: i32,
    /// Life before it.
    before: i32,
    /// The blow rolled its highest.
    best: bool = false,
    /// A bleed torn wider by moving.
    torn: bool = false,
};

pub const AttackOrigin = union(enum) { chosen, reaction: actor.ActorId };

pub const Dealt = struct { to: actor.Kind, killed: bool, origin: AttackOrigin = .chosen };

pub const Event = union(enum) {
    hurt: Hurt,
    stunned: actor.Kind,
    dealt: Dealt,
    missed: struct { origin: AttackOrigin = .chosen },
    used: skillbar.Act,
    /// A bloat burst beside the hero.
    burst,
};

pub const FLASK: skillbar.Act = .life_flask;
pub const WARD: skillbar.Act = .mana_shield;

/// The hero as a turn began.
pub const Start = struct {
    hp: i32,
    max: i32,
    /// A bound `FLASK` could be drunk.
    flask: bool = false,
    /// A bound `WARD` could be cast.
    ward: bool = false,
    /// A bound `WARD` was ready but for the mana.
    starved: bool = false,
};

pub const EVENTS: usize = 32;

pub const Turn = struct {
    number: u32,
    start: Start,
    events: [EVENTS]Event = undefined,
    n: usize = 0,

    pub fn slice(self: *const Turn) []const Event {
        return self.events[0..self.n];
    }

    pub fn lastHurt(self: *const Turn) ?Hurt {
        var i = self.n;
        while (i > 0) {
            i -= 1;
            if (self.events[i] == .hurt) return self.events[i].hurt;
        }
        return null;
    }
};

pub const Milestone = struct {
    turn: u32,
    what: union(enum) { level, cleared: actor.Kind, chest },
};

/// Turns kept, all of which a report reads.
pub const KEPT: usize = 5;

/// The hero's last few turns as they happened, for the death report; not saved.
pub const Chronicle = struct {
    turns: [KEPT]Turn = undefined,
    head: usize = 0,
    n: usize = 0,
    count: u32 = 0,
    milestone: ?Milestone = null,

    pub fn begin(self: *Chronicle, start: Start) void {
        if (self.n > 0) self.head = (self.head + 1) % KEPT;
        self.n = @min(KEPT, self.n + 1);
        self.count += 1;
        self.turns[self.head] = .{ .number = self.count, .start = start };
    }

    /// The turn under way takes `start` if nothing has happened in it yet.
    pub fn restart(self: *Chronicle, start: Start) void {
        const t = self.current() orelse return self.begin(start);
        if (t.n == 0) t.start = start;
    }

    pub fn current(self: *Chronicle) ?*Turn {
        return if (self.n == 0) null else &self.turns[self.head];
    }

    /// Past `EVENTS` in one turn the rest go unrecorded, but harm takes the last place so the killing blow is kept.
    pub fn note(self: *Chronicle, e: Event) void {
        const t = self.current() orelse return;
        if (t.n == EVENTS) {
            if (e == .hurt) t.events[EVENTS - 1] = e;
            return;
        }
        t.events[t.n] = e;
        t.n += 1;
    }

    /// A level gained outranks anything else that turn.
    pub fn mark(self: *Chronicle, what: @FieldType(Milestone, "what")) void {
        if (self.milestone) |m| {
            if (m.turn == self.count and m.what == .level and what != .level) return;
        }
        self.milestone = .{ .turn = self.count, .what = what };
    }

    /// The kept turns, oldest first.
    pub fn recent(self: *const Chronicle, out: *[KEPT]Turn) []const Turn {
        for (0..self.n) |i| out[i] = self.turns[(self.head + KEPT + 1 + i - self.n) % KEPT];
        return out[0..self.n];
    }
};

test "the chronicle keeps the last turns in order and a quiet turn can be restarted" {
    var c = Chronicle{};
    const s = Start{ .hp = 10, .max = 10 };
    c.restart(s);
    c.restart(.{ .hp = 9, .max = 10 });
    try std.testing.expectEqual(@as(u32, 1), c.count);
    try std.testing.expectEqual(@as(i32, 9), c.current().?.start.hp);
    for (0..KEPT + 3) |i| {
        c.note(.{ .hurt = .{ .by = .{ .foe = .rat }, .dmg = @intCast(i), .before = 20 } });
        c.begin(s);
    }
    c.restart(s);
    try std.testing.expectEqual(@as(u32, KEPT + 4), c.count);
    var buf: [KEPT]Turn = undefined;
    const last = c.recent(&buf);
    try std.testing.expectEqual(KEPT, last.len);
    for (last[0 .. last.len - 1], last[1..]) |a, b| try std.testing.expectEqual(a.number + 1, b.number);
    try std.testing.expectEqual(c.count, last[last.len - 1].number);
    try std.testing.expectEqual(@as(i32, KEPT + 2), last[last.len - 2].events[0].hurt.dmg);
    for (0..EVENTS + 4) |_| c.note(.{ .missed = .{} });
    try std.testing.expectEqual(EVENTS, c.current().?.n);
    c.note(.{ .hurt = .{ .by = .gas, .dmg = 7, .before = 7 } });
    try std.testing.expectEqual(@as(i32, 7), c.current().?.events[EVENTS - 1].hurt.dmg);
    std.debug.print("chronicle: {d} turns begun, last {d} read back in order, {d} events a turn at most\n", .{ c.count, last.len, EVENTS });
}
