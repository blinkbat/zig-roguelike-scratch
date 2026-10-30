const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const actor = @import("../play/actor.zig");
const script = @import("script.zig");
const P = mathx.P;
const Tokens = std.mem.TokenIterator(u8, .scalar);
const Script = script.Script;

pub const Error = error{ BadLine, TooMany, BadLink };

/// Each script line's first word; the map's other words and knobs must not take one.
pub const Word = enum { flag, counter, timer, dialog, line, who, say, act, ask, need, gets, then, folk, trigger, when, do };
const ARROW = " -> ";
const NONE = script.NONE;
const ONCE = [2][]const u8{ "repeats", "once" };
const PARKED = [2][]const u8{ "live", "parked" };
const ON = [2][]const u8{ "off", "on" };
const DONE = [2][]const u8{ "running", "done" };

fn says(comptime w: Word) []const u8 {
    return firstWord(w);
}

/// A map-text line's first word as written, its space included.
pub fn firstWord(comptime w: anytype) []const u8 {
    return @tagName(w) ++ " ";
}

pub fn write(s: *const Script, w: anytype) !void {
    inline for (comptime std.enums.values(script.Table)) |t| {
        for (s.names(t)) |*nm| try w.print(@tagName(t) ++ " {s}\n", .{nm.text()});
    }
    for (s.dialogs()) |*d| {
        try w.print(says(.dialog) ++ "{s}\n", .{d.name.text()});
        for (d.lines()) |*l| {
            try w.print(says(.line) ++ "{s}\n", .{l.name.text()});
            if (l.who.n > 0) try w.print(says(.who) ++ "{s}\n", .{l.who.text()});
            if (l.say.n > 0) try w.print(says(.say) ++ "{s}\n", .{l.say.text()});
            for (l.acts()) |*a| try putAct(w, s, .act, a);
            for (l.choices()) |*c| {
                try w.print(says(.ask) ++ "{s}" ++ ARROW ++ "{s}\n", .{ c.ask.text(), target(d, c.next) });
                if (c.gate) |*g| try putCond(w, s, .need, g);
                for (c.acts()) |*a| try putAct(w, s, .gets, a);
            }
            if (l.then) |t| try w.print(says(.then) ++ "{s}\n", .{d.line[t].name.text()});
        }
    }
    for (s.folks()) |*f| {
        try w.print(says(.folk) ++ "{d} {d} {d} {s}", .{ f.node, f.at.x, f.at.y, if (f.dialog) |d| s.dialog[d].name.text() else NONE });
        if (f.name.n > 0) try w.print(" {s}", .{f.name.text()});
        try w.writeByte('\n');
    }
    for (s.triggers()) |*t| {
        try w.print(says(.trigger) ++ "{s} {d} {s} {s}\n", .{ t.name.text(), t.priority, ONCE[@intFromBool(t.once)], PARKED[@intFromBool(t.parked)] });
        for (t.conds()) |*c| try putCond(w, s, .when, c);
        for (t.acts()) |*a| try putAct(w, s, .do, a);
    }
}

fn target(d: *const script.Dialog, next: ?u8) []const u8 {
    return if (next) |n| d.line[n].name.text() else script.END;
}

fn putCond(w: anytype, s: *const Script, comptime lead: Word, c: *const script.Cond) !void {
    try w.writeAll(says(lead));
    try w.writeAll(@tagName(c.kind));
    switch (c.kind) {
        .always, .never => {},
        .flag => try w.print(" {s} {s}", .{ s.flag[c.slot].text(), ON[@intFromBool(c.on)] }),
        .counter => try w.print(" {s} {s} {d}", .{ s.counter[c.slot].text(), c.cmp.tok(), c.n }),
        .timer => try w.print(" {s} {s}", .{ s.timer[c.slot].text(), DONE[@intFromBool(c.on)] }),
        .elapsed => try w.print(" {s} {d}", .{ c.cmp.tok(), c.n }),
        .region => try w.print(" {d} {d} {d} {d} {d}", .{ c.node, c.from.x, c.from.y, c.to.x, c.to.y }),
        .near => try w.print(" {d} {d}", .{ c.slot, c.n }),
        .talked => try w.print(" {s}", .{s.dialog[c.slot].name.text()}),
        .deaths, .alive => try w.print(" {s} {s} {d}", .{ @tagName(c.foe), c.cmp.tok(), c.n }),
    }
    try w.writeByte('\n');
}

fn putAct(w: anytype, s: *const Script, comptime lead: Word, a: *const script.Act) !void {
    try w.writeAll(says(lead));
    try w.writeAll(@tagName(a.kind));
    switch (a.kind) {
        .preserve => {},
        .dialog => try w.print(" {s}", .{s.dialog[a.slot].name.text()}),
        .text => if (a.note.n > 0) try w.print(" {s}", .{a.note.text()}),
        .flag => try w.print(" {s} {s}", .{ s.flag[a.slot].text(), @tagName(a.setop) }),
        .counter => try w.print(" {s} {s} {d}", .{ s.counter[a.slot].text(), @tagName(a.countop), a.n }),
        .timer => try w.print(" {s} {d}", .{ s.timer[a.slot].text(), a.n }),
        .wait => try w.print(" {d}", .{a.n}),
    }
    try w.writeByte('\n');
}

/// The dialogs and lines a file declares, read ahead so a reference may come before what it names.
const Index = struct {
    dialog: [script.MAX_DIALOGS]script.Name = @splat(.{}),
    dialog_n: usize = 0,
    line: [script.MAX_DIALOGS][script.MAX_LINES]script.Name = @splat(@splat(.{})),
    line_n: [script.MAX_DIALOGS]usize = @splat(0),

    fn of(text: []const u8) Error!Index {
        var ix = Index{};
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw| {
            var f = std.mem.tokenizeScalar(u8, std.mem.trimRight(u8, raw, "\r"), ' ');
            const word = std.meta.stringToEnum(Word, f.next() orelse continue) orelse continue;
            switch (word) {
                .dialog => {
                    const name = try nameOf(&f);
                    if (ix.findDialog(name) != null) return error.BadLine;
                    if (ix.dialog_n == script.MAX_DIALOGS) return error.TooMany;
                    ix.dialog[ix.dialog_n] = script.Name.of(name);
                    ix.dialog_n += 1;
                },
                .line => {
                    if (ix.dialog_n == 0) return error.BadLine;
                    const d = ix.dialog_n - 1;
                    const name = try nameOf(&f);
                    if (ix.findLine(d, name) != null) return error.BadLine;
                    if (ix.line_n[d] == script.MAX_LINES) return error.TooMany;
                    ix.line[d][ix.line_n[d]] = script.Name.of(name);
                    ix.line_n[d] += 1;
                },
                else => {},
            }
        }
        return ix;
    }

    fn findDialog(ix: *const Index, name: []const u8) ?u8 {
        return script.indexOfName(ix.dialog[0..ix.dialog_n], name);
    }

    fn findLine(ix: *const Index, d: usize, name: []const u8) ?u8 {
        return script.indexOfName(ix.line[d][0..ix.line_n[d]], name);
    }
};

pub const Reader = struct {
    index: Index,
    dialog: ?u8 = null,
    line: ?u8 = null,
    choice: ?u8 = null,
    trigger: ?u8 = null,

    pub fn of(text: []const u8) Error!Reader {
        return .{ .index = try Index.of(text) };
    }

    /// Reads the rest of `f`, the line `word` began.
    pub fn take(r: *Reader, s: *Script, word: Word, f: *Tokens) Error!void {
        switch (word) {
            inline .flag, .counter, .timer => |t| {
                const table = @field(script.Table, @tagName(t));
                const name = try nameOf(f);
                if (s.find(table, name) != null) return error.BadLine;
                _ = s.declare(table, name) orelse return error.TooMany;
            },
            .dialog => {
                r.leave();
                if (s.dialog_n == script.MAX_DIALOGS) return error.TooMany;
                s.dialog[s.dialog_n] = .{ .name = script.Name.of(try nameOf(f)) };
                r.dialog = s.dialog_n;
                s.dialog_n += 1;
            },
            .line => {
                const d = try r.dialogOf(s);
                if (d.line_n == script.MAX_LINES) return error.TooMany;
                d.line[d.line_n] = .{ .name = script.Name.of(try nameOf(f)) };
                r.line = d.line_n;
                r.choice = null;
                d.line_n += 1;
            },
            .who => {
                const l = try r.lineOf(s);
                if (l.who.n > 0 or !l.who.set(rest(f))) return error.BadLine;
            },
            .say => {
                const l = try r.lineOf(s);
                if (l.say.n > 0 or !l.say.set(rest(f))) return error.BadLine;
            },
            .act => {
                const l = try r.lineOf(s);
                if (l.act_n == script.LINE_ACTS) return error.TooMany;
                l.act[l.act_n] = try spokenAct(s, f);
                l.act_n += 1;
            },
            .ask => {
                const l = try r.lineOf(s);
                const all = rest(f);
                const unasked = ARROW[1..];
                const ask_n, const next_at = if (std.mem.lastIndexOf(u8, all, ARROW)) |split|
                    .{ split, split + ARROW.len }
                else if (std.mem.startsWith(u8, all, unasked)) .{ 0, unasked.len } else return error.BadLine;
                if (l.choice_n == script.MAX_CHOICES) return error.TooMany;
                var c = script.Choice{ .next = try r.lineNamed(std.mem.trim(u8, all[next_at..], " ")) };
                if (!c.ask.set(all[0..ask_n])) return error.BadLine;
                l.choice[l.choice_n] = c;
                r.choice = l.choice_n;
                l.choice_n += 1;
            },
            .need => {
                const c = try r.choiceOf(s);
                if (c.gate != null) return error.BadLine;
                c.gate = try r.cond(s, f);
            },
            .gets => {
                const c = try r.choiceOf(s);
                if (c.act_n == script.CHOICE_ACTS) return error.TooMany;
                c.act[c.act_n] = try spokenAct(s, f);
                c.act_n += 1;
            },
            .then => {
                const l = try r.lineOf(s);
                if (l.then != null) return error.BadLine;
                l.then = try r.lineNamed(f.next() orelse return error.BadLine) orelse return error.BadLine;
            },
            .folk => {
                r.leave();
                var folk = script.Folk{ .node = try int(u8, f), .at = try cell(f) };
                const talk = f.next() orelse return error.BadLine;
                if (!std.mem.eql(u8, talk, NONE)) folk.dialog = r.index.findDialog(talk) orelse return error.BadLink;
                if (!folk.name.set(rest(f))) return error.BadLine;
                if (s.folk_n == script.MAX_FOLK) return error.TooMany;
                _ = s.addFolk(folk) orelse return error.BadLine;
            },
            .trigger => {
                r.leave();
                if (s.trigger_n == script.MAX_TRIGGERS) return error.TooMany;
                var t = script.Trigger{ .name = script.Name.of(try nameOf(f)) };
                t.priority = try int(i8, f);
                t.once = try pick(f, ONCE);
                t.parked = try pick(f, PARKED);
                s.trigger[s.trigger_n] = t;
                r.trigger = s.trigger_n;
                s.trigger_n += 1;
            },
            .when => {
                const t = &s.trigger[r.trigger orelse return error.BadLine];
                if (t.cond_n == script.MAX_CONDS) return error.TooMany;
                t.cond[t.cond_n] = try r.cond(s, f);
                t.cond_n += 1;
            },
            .do => {
                const t = &s.trigger[r.trigger orelse return error.BadLine];
                if (t.act_n == script.MAX_ACTS) return error.TooMany;
                t.act[t.act_n] = try r.act(s, f);
                t.act_n += 1;
            },
        }
    }

    fn leave(r: *Reader) void {
        r.dialog = null;
        r.line = null;
        r.choice = null;
        r.trigger = null;
    }

    fn dialogOf(r: *Reader, s: *Script) Error!*script.Dialog {
        return &s.dialog[r.dialog orelse return error.BadLine];
    }

    fn lineOf(r: *Reader, s: *Script) Error!*script.Line {
        const d = try r.dialogOf(s);
        return &d.line[r.line orelse return error.BadLine];
    }

    fn choiceOf(r: *Reader, s: *Script) Error!*script.Choice {
        const l = try r.lineOf(s);
        return &l.choice[r.choice orelse return error.BadLine];
    }

    /// `end` is none.
    fn lineNamed(r: *const Reader, name: []const u8) Error!?u8 {
        if (std.mem.eql(u8, name, script.END)) return null;
        return r.index.findLine(r.dialog.?, name) orelse error.BadLink;
    }

    fn cond(r: *const Reader, s: *const Script, f: *Tokens) Error!script.Cond {
        var c = script.Cond{ .kind = try value(script.CondKind, f) };
        switch (c.kind) {
            .always, .never => {},
            .flag => {
                c.slot = try slotOf(s, .flag, f);
                c.on = try pick(f, ON);
            },
            .counter => {
                c.slot = try slotOf(s, .counter, f);
                c.cmp = try cmpOf(f);
                c.n = try int(i32, f);
            },
            .timer => {
                c.slot = try slotOf(s, .timer, f);
                c.on = try pick(f, DONE);
            },
            .elapsed => {
                c.cmp = try cmpOf(f);
                c.n = try int(i32, f);
            },
            .region => {
                c.node = try int(u8, f);
                c.from = try cell(f);
                c.to = try cell(f);
            },
            .near => {
                c.slot = try int(u8, f);
                c.n = try int(i32, f);
            },
            .talked => c.slot = r.index.findDialog(f.next() orelse return error.BadLine) orelse return error.BadLink,
            .deaths, .alive => {
                c.foe = try value(actor.Kind, f);
                c.cmp = try cmpOf(f);
                c.n = try int(i32, f);
            },
        }
        return c;
    }

    fn act(r: *const Reader, s: *const Script, f: *Tokens) Error!script.Act {
        var a = script.Act{ .kind = try value(script.ActKind, f) };
        switch (a.kind) {
            .preserve => {},
            .dialog => a.slot = r.index.findDialog(f.next() orelse return error.BadLine) orelse return error.BadLink,
            .text => if (!a.note.set(rest(f))) return error.BadLine,
            .flag => {
                a.slot = try slotOf(s, .flag, f);
                a.setop = try value(script.Setop, f);
            },
            .counter => {
                a.slot = try slotOf(s, .counter, f);
                a.countop = try value(script.Countop, f);
                a.n = try int(i32, f);
            },
            .timer => {
                a.slot = try slotOf(s, .timer, f);
                a.n = try int(i32, f);
            },
            .wait => a.n = try int(i32, f),
        }
        return a;
    }
};

fn spokenAct(s: *const Script, f: *Tokens) Error!script.Act {
    const r = Reader{ .index = .{} };
    const a = try r.act(s, f);
    return if (a.kind.spoken()) a else error.BadLine;
}

fn nameOf(f: *Tokens) Error![]const u8 {
    const name = f.next() orelse return error.BadLine;
    return if (script.token(name)) name else error.BadLine;
}

/// The rest of the line, read as it is written, leaving nothing after it.
fn rest(f: *Tokens) []const u8 {
    const all = f.rest();
    f.index = f.buffer.len;
    return all;
}

fn slotOf(s: *const Script, t: script.Table, f: *Tokens) Error!u8 {
    return s.find(t, f.next() orelse return error.BadLine) orelse error.BadLink;
}

fn pick(f: *Tokens, words: [2][]const u8) Error!bool {
    const w = f.next() orelse return error.BadLine;
    for (words, [2]bool{ false, true }) |want, b| {
        if (std.mem.eql(u8, w, want)) return b;
    }
    return error.BadLine;
}

fn cmpOf(f: *Tokens) Error!script.Cmp {
    const w = f.next() orelse return error.BadLine;
    for (std.enums.values(script.Cmp)) |c| {
        if (std.mem.eql(u8, w, c.tok())) return c;
    }
    return error.BadLine;
}

pub fn value(comptime T: type, f: *Tokens) Error!T {
    return std.meta.stringToEnum(T, f.next() orelse return error.BadLine) orelse error.BadLine;
}

/// Written plainly, as `{d}` writes it: no sign but a minus, no leading zero.
pub fn int(comptime T: type, f: *Tokens) Error!T {
    const word = f.next() orelse return error.BadLine;
    const n = std.fmt.parseInt(T, word, 10) catch return error.BadLine;
    var buf: [24]u8 = undefined;
    if (!std.mem.eql(u8, word, std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable)) return error.BadLine;
    return n;
}

pub fn point(f: *Tokens) Error!P {
    return .{ .x = try int(i32, f), .y = try int(i32, f) };
}

/// A `point` on the map.
pub fn cell(f: *Tokens) Error!P {
    const p = try point(f);
    return if (grid.Level.inside(p)) p else error.BadLine;
}

pub const SAMPLE =
    \\flag met_wenna
    \\counter coins
    \\timer dusk
    \\dialog wenna
    \\line root
    \\who Old Wenna
    \\say You came down the well too? Nobody comes down the well.
    \\act flag met_wenna on
    \\ask What is down here? -> deeper
    \\need flag met_wenna on
    \\gets counter coins add 2
    \\ask Goodbye. -> end
    \\line deeper
    \\say Rats. Slime. Worse, past the gate.
    \\act text Wenna points down the dark passage.
    \\then root
    \\folk 0 6 5 wenna Old Wenna
    \\folk 0 7 5 -
    \\trigger greet 5 once live
    \\when near 0 2
    \\when flag met_wenna off
    \\do text Someone hums by the cistern.
    \\do dialog wenna
    \\do flag met_wenna on
    \\trigger tally 0 repeats parked
    \\when deaths rat >= 3
    \\when alive slime = 0
    \\when counter coins < 10
    \\when timer dusk done
    \\when elapsed > 40
    \\when region 0 1 1 9 9
    \\when talked wenna
    \\when always
    \\do counter coins sub 1
    \\do timer dusk 20
    \\do wait 2
    \\do flag met_wenna flip
    \\do preserve
    \\trigger idle -3 once live
    \\when never
    \\
;

/// A script's lines with no map round them, for `node_n` nodes; every line must be a script line.
pub fn readAlone(text: []const u8, s: *Script, node_n: usize) Error!void {
    s.* = .{};
    var r = try Reader.of(text);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var f = std.mem.tokenizeScalar(u8, raw, ' ');
        const word = std.meta.stringToEnum(Word, f.next() orelse continue) orelse return error.BadLine;
        try r.take(s, word, &f);
        if (f.next() != null) return error.BadLine;
    }
    if (!s.valid(node_n)) return error.BadLine;
}

fn testRead(text: []const u8, s: *Script) Error!void {
    return readAlone(text, s, 1);
}

test "a script reads back to the same text, every condition and action kind with it" {
    const s = try std.testing.allocator.create(Script);
    defer std.testing.allocator.destroy(s);
    try testRead(SAMPLE, s);
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try write(s, buf.writer());
    try std.testing.expectEqualStrings(SAMPLE, buf.items);
    const d = &s.dialog[0];
    try std.testing.expectEqual(@as(?u8, 1), d.line[0].choice[0].next);
    try std.testing.expectEqual(@as(?u8, null), d.line[0].choice[1].next);
    try std.testing.expectEqual(@as(?u8, 0), d.line[1].then);
    try std.testing.expectEqual(@as(?u8, 0), s.folk[0].dialog);
    try std.testing.expectEqualStrings(script.STRANGER, s.folk[1].called());
    var conds = std.EnumSet(script.CondKind).initEmpty();
    var acts = std.EnumSet(script.ActKind).initEmpty();
    for (s.triggers()) |*t| {
        for (t.conds()) |c| conds.insert(c.kind);
        for (t.acts()) |a| acts.insert(a.kind);
    }
    try std.testing.expectEqual(std.enums.values(script.CondKind).len, conds.count());
    try std.testing.expectEqual(std.enums.values(script.ActKind).len, acts.count());
    std.debug.print("script text: {d} bytes, {d} condition and {d} action kinds round-trip canonically\n", .{ SAMPLE.len, std.enums.values(script.CondKind).len, std.enums.values(script.ActKind).len });
}

test "a script with a dangling name, a misplaced line or a trigger's action in a conversation is refused" {
    const s = try std.testing.allocator.create(Script);
    defer std.testing.allocator.destroy(s);
    const bad = [_][]const u8{
        "flag a\nflag a\n",
        "line root\n",
        "dialog d\nline a\nline a\n",
        "dialog d\nline a\nask Hi -> nowhere\n",
        "dialog d\nline a\nask Hi\n",
        "dialog d\nline a\nact wait 2\n",
        "dialog d\nline a\nact dialog d\n",
        "dialog d\nline a\nneed always\n",
        "dialog d\nline a\nthen a\nthen a\n",
        "dialog d\nline a\nsay one\nsay two\n",
        "trigger t 0 once live\nwhen flag nope on\n",
        "trigger t 0 once live\ndo dialog nope\n",
        "trigger t 0 sometimes live\n",
        "trigger t 100 once live\n",
        "trigger t 0 once live\nwhen counter c >= 1\n",
        "trigger t 0 once live\nwhen deaths slime_half >= 1\n",
        "trigger t 0 once live\nwhen near 0 2\n",
        "trigger t 0 once live\ndo wait -1\n",
        "trigger t 0 once live\nwhen elapsed >= 01\n",
        "when always\n",
        "folk 0 99 99 -\n",
        "folk 0 3 3 nope\n",
        "folk 0 3 3 -\nfolk 0 3 3 -\n",
        "folk 1 3 3 -\n",
        "dialog end\nline a\n",
        "dialog -\nline a\n",
        "dialog d\nline a\nask Hi -> end\ngets text " ++ "x" ** (script.NOTE_MAX + 1) ++ "\n",
    };
    for (bad) |t| try std.testing.expect(std.meta.isError(testRead(t, s)));
    try testRead("dialog d\nline a\nask Hi -> there -> end\n", s);
    try std.testing.expectEqualStrings("Hi -> there", s.dialog[0].line[0].choice[0].ask.text());
    try testRead("dialog d\nline a\nask  -> end\n", s);
    try std.testing.expectEqualStrings("", s.dialog[0].line[0].choice[0].ask.text());
    std.debug.print("script text: {d} malformed scripts refused; an arrow inside a choice's words kept, a wordless choice read back\n", .{bad.len});
}
