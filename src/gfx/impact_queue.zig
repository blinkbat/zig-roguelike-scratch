const std = @import("std");
const mathx = @import("../core/mathx.zig");
const actor = @import("../play/actor.zig");
const chain = @import("../play/chain.zig");
const state = @import("effect_state.zig");

pub const FLASH_S: f32 = 0.16;
pub const FLASH_GAIN: f32 = 0.75;
pub const DEATH_S: f32 = 0.22;
/// Of `DEATH_S`, the first part, over which it darkens wholly before it fades.
pub const DEATH_DARKEN: f32 = 0.35;
/// The light left on a wholly darkened body, per channel.
pub const DEATH_RGB = [3]f32{ 0.65, 0.35, 0.32 };

pub const Dying = struct { dark: f32 = 0, alpha: f32 = 1 };

/// The kinds of turn effect a body can owe: `presentation.Owed`'s fields.
pub const OWED_KINDS: usize = 16;
/// A burst and a puff.
const LOOSE_DUE: usize = 2;
/// Capacity for every body's turn effects, hero hit and sweep, plus a burst and a puff, or chain jumps.
const DUE: usize = actor.MAX * (OWED_KINDS + actor.SWEEP_CELLS) + @max(LOOSE_DUE, chain.JUMPS);

pub const Event = union(enum) {
    blow: state.Blow,
    sting: state.Sting,
    settle: state.Settle,
    burst: state.Burst,
    zap: state.Zap,
    puff: state.Puff,
    shimmer: state.Shimmer,
    whirl: [2]f32,

    pub fn on(d: *const Event) ?actor.ActorSlot {
        return switch (d.*) {
            .blow => |*b| switch (b.impact) {
                .actor => |a| a.slot,
                .barrel => null,
            },
            .sting => |*s| s.slot,
            .settle => |*s| s.slot,
            .burst, .zap, .puff, .shimmer, .whirl => null,
        };
    }

    fn blowOf(d: *const Event) ?*const state.Blow {
        return switch (d.*) {
            .blow => |*b| b,
            .sting, .settle, .burst, .zap, .puff, .shimmer, .whirl => null,
        };
    }

    fn onBarrel(d: *const Event) bool {
        const b = d.blowOf() orelse return false;
        return b.impact == .barrel;
    }

    pub fn after(d: *const Event) ?state.After {
        return switch (d.*) {
            .blow => |*b| switch (b.impact) {
                .actor => |a| a.after,
                .barrel => null,
            },
            .sting => |*s| s.after,
            .settle => |*s| s.after,
            .burst, .zap, .puff, .shimmer, .whirl => null,
        };
    }
};

pub const Ready = struct { event: Event, late: f32 };

pub const Queue = struct {
    flash: [actor.MAX]f32 = @splat(0),
    /// Indexed by pool slot: seconds left of a foe's death fade.
    dying: [actor.MAX]f32 = @splat(0),
    due: [DUE]struct { t: f32, what: Event } = undefined,
    due_n: usize = 0,
    barrels_due: usize = 0,
    reveals_due: usize = 0,
    /// Indexed by pool slot: the body as the latest-dealt of the blows landed on it left it.
    landed: [actor.MAX]?state.Body = @splat(null),
    mana_landed: i32 = 0,
    pub fn dyingOf(self: *const Queue, slot: actor.ActorSlot) Dying {
        if (self.dying[slot.index] <= 0) return .{};
        const k = self.dying[slot.index] / DEATH_S;
        return .{ .dark = @min(1, (1 - k) / DEATH_DARKEN), .alpha = @min(1, k / (1 - DEATH_DARKEN)) };
    }

    pub fn pending(self: *const Queue, slot: actor.ActorSlot) bool {
        return self.landsIn(slot) > 0;
    }

    pub fn landedOn(self: *const Queue, slot: actor.ActorSlot) ?state.Body {
        return self.landed[slot.index];
    }

    pub fn revealing(self: *const Queue, slot: actor.ActorSlot) bool {
        return self.revealsIn(slot) > 0;
    }

    /// Seconds until the blow that reveals the slot lands; 0 when none is due.
    pub fn revealsIn(self: *const Queue, slot: actor.ActorSlot) f32 {
        if (self.reveals_due == 0) return 0;
        return self.lastDue(slot, revealed);
    }

    fn revealed(e: *const Event) ?actor.ActorSlot {
        return (e.after() orelse return null).reveals;
    }

    fn tally(self: *Queue, what: *const Event, comptime up: bool) void {
        stepCount(&self.barrels_due, what.onBarrel(), up);
        stepCount(&self.reveals_due, revealed(what) != null, up);
    }

    fn stepCount(n: *usize, on: bool, comptime up: bool) void {
        if (!on) return;
        if (up) n.* += 1 else n.* -= 1;
    }

    fn lastDue(self: *const Queue, slot: actor.ActorSlot, comptime target: fn (*const Event) ?actor.ActorSlot) f32 {
        var t: f32 = 0;
        for (self.due[0..self.due_n]) |*d| {
            const s = target(&d.what) orelse continue;
            if (s.index == slot.index) t = @max(t, d.t);
        }
        return t;
    }

    pub fn holds(self: *const Queue, slot: actor.ActorSlot) bool {
        return self.flash[slot.index] > 0 or self.pending(slot);
    }

    pub fn landsIn(self: *const Queue, slot: actor.ActorSlot) f32 {
        return self.lastDue(slot, Event.on);
    }

    pub fn heldIn(self: *const Queue, slot: actor.ActorSlot) f32 {
        const lands = self.landsIn(slot);
        const due = if (lands > 0) lands + FLASH_S else 0;
        return @max(self.flash[slot.index], due);
    }

    pub fn breaking(self: *const Queue, p: mathx.P) bool {
        if (self.barrels_due == 0) return false;
        for (self.due[0..self.due_n]) |*d| {
            if (d.what.onBarrel() and d.what.blowOf().?.impact.barrel.eq(p)) return true;
        }
        return false;
    }

    pub fn flashOf(self: *const Queue, slot: actor.ActorSlot) f32 {
        const k = std.math.clamp(self.flash[slot.index] / FLASH_S, 0, 1);
        return FLASH_GAIN * k * (2 - k);
    }

    pub fn land(self: *Queue, what: Event, late: f32) void {
        const slot = (what.on() orelse return).index;
        switch (what) {
            .blow, .sting => self.flash[slot] = @max(self.flash[slot], FLASH_S - late),
            .settle, .burst, .zap, .puff, .shimmer, .whirl => {},
        }
        const a = what.after() orelse return;
        self.mana_landed += a.mana;
        if (self.landed[slot]) |was| {
            if (was.seq >= a.body.seq) return;
        }
        const died = a.body.down() and !(if (self.landed[slot]) |was| was.down() else false);
        if (died and !a.body.kind.hero()) self.dying[slot] = @max(0, DEATH_S - late);
        self.landed[slot] = a.body;
    }

    pub fn clear(self: *Queue) void {
        self.* = .{};
    }

    /// Drops what landed on a slot's former body before a new one takes it.
    pub fn forget(self: *Queue, slot: actor.ActorSlot) void {
        self.flash[slot.index] = 0;
        self.dying[slot.index] = 0;
        self.landed[slot.index] = null;
    }

    pub fn count(self: *const Queue) usize {
        return self.due_n;
    }

    pub fn hasBarrels(self: *const Queue) bool {
        return self.barrels_due > 0;
    }

    pub fn isDying(self: *const Queue, slot: actor.ActorSlot) bool {
        return self.dying[slot.index] > 0;
    }

    pub fn takeMana(self: *Queue) i32 {
        defer self.mana_landed = 0;
        return self.mana_landed;
    }

    pub fn schedule(self: *Queue, wait: f32, what: Event) ?Ready {
        if (wait <= 0 or self.due_n == DUE) return .{ .event = what, .late = @max(0, -wait) };
        self.due[self.due_n] = .{ .t = wait, .what = what };
        self.due_n += 1;
        self.tally(&what, true);
        return null;
    }

    pub fn advance(self: *Queue, dt: f32) void {
        for (&self.flash) |*remaining| remaining.* = @max(0, remaining.* - dt);
        for (&self.dying) |*remaining| remaining.* = @max(0, remaining.* - dt);
        for (self.due[0..self.due_n]) |*event| event.t -= dt;
    }

    pub fn ready(self: *Queue) ReadyIterator {
        return .{ .queue = self };
    }
};

const ReadyIterator = struct {
    queue: *Queue,
    index: usize = 0,

    pub fn next(self: *ReadyIterator) ?Ready {
        const queue = self.queue;
        while (self.index < queue.due_n) {
            const pending = queue.due[self.index];
            if (pending.t > 0) {
                self.index += 1;
                continue;
            }
            queue.due_n -= 1;
            queue.due[self.index] = queue.due[queue.due_n];
            queue.tally(&pending.what, false);
            return .{ .event = pending.what, .late = -pending.t };
        }
        return null;
    }
};

test "overdue impacts retain simulation order and release each mana debt once" {
    var queue = Queue{};
    const target = actor.ActorSlot.fromIndex(3);
    const child = actor.ActorSlot.fromIndex(4);
    const sequences = [_]u64{ 3, 1, 2 };
    for (sequences) |seq| {
        const after = state.After{
            .body = .{ .kind = .slime, .hp = @intCast(10 - seq), .max = 10, .seq = seq },
            .reveals = if (seq == 3) child else null,
            .mana = @intCast(seq),
        };
        try std.testing.expect(queue.schedule(@as(f32, @floatFromInt(seq)) * 0.01, .{ .settle = .{ .slot = target, .after = after } }) == null);
    }
    try std.testing.expect(queue.pending(target) and queue.revealing(child));
    queue.advance(0.1);
    var ready = queue.ready();
    var count: usize = 0;
    while (ready.next()) |event| {
        queue.land(event.event, event.late);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(u64, 3), queue.landedOn(target).?.seq);
    try std.testing.expectEqual(@as(i32, 7), queue.landedOn(target).?.hp);
    try std.testing.expectEqual(@as(i32, 6), queue.takeMana());
    try std.testing.expectEqual(@as(i32, 0), queue.takeMana());
    try std.testing.expect(!queue.pending(target) and !queue.revealing(child));
}

test "a full impact queue preserves pending barrels and returns overflow for immediate delivery" {
    var queue = Queue{};
    const at = mathx.P{ .x = 20, .y = 20 };
    const event = Event{ .blow = .{ .impact = .{ .barrel = at }, .dir = null, .matter = .wood } };
    for (0..DUE) |_| try std.testing.expect(queue.schedule(1, event) == null);
    const overflow = queue.schedule(2, event).?;
    try std.testing.expectEqual(@as(f32, 0), overflow.late);
    try std.testing.expectEqual(DUE, queue.count());
    try std.testing.expect(queue.hasBarrels() and queue.breaking(at));
    queue.advance(0.5);
    var early = queue.ready();
    try std.testing.expect(early.next() == null);
    queue.advance(0.5);
    var ready = queue.ready();
    var count: usize = 0;
    while (ready.next()) |_| count += 1;
    try std.testing.expectEqual(DUE, count);
    try std.testing.expectEqual(@as(usize, 0), queue.count());
    try std.testing.expect(!queue.hasBarrels() and !queue.breaking(at));
    try std.testing.expect(queue.schedule(1, event) == null);
    queue.clear();
    try std.testing.expectEqual(@as(usize, 0), queue.count());
    try std.testing.expect(!queue.hasBarrels());
}
