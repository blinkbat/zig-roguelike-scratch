const std = @import("std");
const script = @import("../map/script.zig");
const Script = script.Script;

pub const LineAt = struct { d: u8, l: u8 };
pub const StageAt = struct { q: u8, k: u8 };
pub const ChoiceAt = struct { d: u8, l: u8, c: u8 };
pub const TableAt = struct { t: script.Table, i: u8 };
pub const ActAt = union(enum) {
    trigger: struct { t: u8, a: u8 },
    line: struct { at: LineAt, a: u8 },
    choice: struct { at: ChoiceAt, a: u8 },
};
pub const Focus = union(enum) {
    npc: u8,
    dialog: u8,
    line: LineAt,
    who: LineAt,
    say: LineAt,
    ask: ChoiceAt,
    trigger: u8,
    table: TableAt,
    note: ActAt,
    quest: u8,
    title: u8,
    stage: StageAt,

    pub fn multiline(f: Focus) bool {
        return f == .say or f == .ask;
    }
};
pub const Target = struct { words: Words, unique: ?Unique = null };

pub const Words = union(enum) {
    name: *script.Name,
    who: *script.Who,
    say: *script.Say,
    ask: *script.Ask,
    note: *script.Note,
    title: *script.Title,

    pub fn text(w: Words) []const u8 {
        return switch (w) {
            inline else => |p| p.text(),
        };
    }

    pub fn most(w: Words) usize {
        return switch (w) {
            inline else => |p| @TypeOf(p.*).MAX,
        };
    }

    pub fn set(w: Words, s: []const u8) bool {
        return switch (w) {
            inline else => |p| p.set(s),
        };
    }
};

pub const Unique = union(enum) { dialog: u8, line: LineAt, trigger: u8, table: TableAt, quest: u8 };

pub fn target(m: *Script, f: Focus) ?Target {
    return switch (f) {
        .npc => |i| if (i < m.npc_n) .{ .words = .{ .who = &m.npc[i].name } } else null,
        .dialog => |i| if (i < m.dialog_n) .{ .words = .{ .name = &m.dialog[i].name }, .unique = .{ .dialog = i } } else null,
        .line => |at| if (lineOf(m, at)) |ln| .{ .words = .{ .name = &ln.name }, .unique = .{ .line = at } } else null,
        .who => |at| if (lineOf(m, at)) |ln| .{ .words = .{ .who = &ln.who } } else null,
        .say => |at| if (lineOf(m, at)) |ln| .{ .words = .{ .say = &ln.say } } else null,
        .ask => |at| if (choiceOf(m, at)) |c| .{ .words = .{ .ask = &c.ask } } else null,
        .trigger => |i| if (i < m.trigger_n) .{ .words = .{ .name = &m.trigger[i].name }, .unique = .{ .trigger = i } } else null,
        .table => |at| if (at.i < m.names(at.t).len) .{ .words = .{ .name = tableName(m, at) }, .unique = .{ .table = at } } else null,
        .note => |at| if (actOf(m, at)) |a| .{ .words = .{ .note = &a.note } } else null,
        .quest => |i| if (i < m.quest_n) .{ .words = .{ .name = &m.quest[i].name }, .unique = .{ .quest = i } } else null,
        .title => |i| if (i < m.quest_n) .{ .words = .{ .title = &m.quest[i].title } } else null,
        .stage => |at| if (at.q < m.quest_n and at.k < m.quest[at.q].stage_n) .{ .words = .{ .note = &m.quest[at.q].stage[at.k] } } else null,
    };
}

pub fn put(m: *Script, t: Target, s: []const u8) bool {
    const u = t.unique orelse return t.words.set(s);
    return switch (u) {
        .dialog => |i| script.renameIn(m.dialog[0..m.dialog_n], i, s),
        .line => |at| script.renameIn(m.dialog[at.d].line[0..m.dialog[at.d].line_n], at.l, s),
        .trigger => |i| script.renameIn(m.trigger[0..m.trigger_n], i, s),
        .table => |at| m.rename(at.t, at.i, s),
        .quest => |i| script.renameIn(m.quest[0..m.quest_n], i, s),
    };
}

fn tableName(m: *Script, at: TableAt) *script.Name {
    return switch (at.t) {
        inline else => |t| &@field(m.*, @tagName(t))[at.i],
    };
}

pub fn lineOf(m: *Script, at: LineAt) ?*script.Line {
    if (at.d >= m.dialog_n or at.l >= m.dialog[at.d].line_n) return null;
    return &m.dialog[at.d].line[at.l];
}

fn choiceOf(m: *Script, at: ChoiceAt) ?*script.Choice {
    const ln = lineOf(m, .{ .d = at.d, .l = at.l }) orelse return null;
    return if (at.c < ln.choice_n) &ln.choice[at.c] else null;
}

pub const ActList = struct { items: []script.Act, n: *u8 };

pub fn listOf(m: *Script, at: ActAt) ?ActList {
    return switch (at) {
        .trigger => |t| if (t.t < m.trigger_n) .{ .items = &m.trigger[t.t].act, .n = &m.trigger[t.t].act_n } else null,
        .line => |l| if (lineOf(m, l.at)) |ln| .{ .items = &ln.act, .n = &ln.act_n } else null,
        .choice => |c| if (choiceOf(m, c.at)) |ch| .{ .items = &ch.act, .n = &ch.act_n } else null,
    };
}

pub fn actOf(m: *Script, at: ActAt) ?*script.Act {
    const list = listOf(m, at) orelse return null;
    const a = switch (at) {
        inline else => |p| p.a,
    };
    return if (a < list.n.*) &list.items[a] else null;
}

pub const WORDS_MAX = blk: {
    var most: usize = 0;
    for (std.meta.fields(Words)) |f| most = @max(most, std.meta.Child(f.type).MAX);
    break :blk most;
};

pub fn plainChar(c: u8) bool {
    return c == '\n' or c == '\r' or script.plain(&[_]u8{c});
}

test "plot fields reject stale references and duplicate names without changing the script" {
    const model = try script.testScript();
    defer std.testing.allocator.destroy(model);
    const first = model.addDialog("first").?;
    const second = model.addDialog("second").?;
    const field = target(model, .{ .dialog = second }).?;
    try std.testing.expect(!put(model, field, "first"));
    try std.testing.expectEqualStrings("second", model.dialog[second].name.text());
    try std.testing.expect(put(model, field, "renamed"));
    try std.testing.expectEqualStrings("renamed", model.dialog[second].name.text());
    try std.testing.expect(target(model, .{ .dialog = model.dialog_n }) == null);
    try std.testing.expect(target(model, .{ .say = .{ .d = first, .l = model.dialog[first].line_n } }) == null);
    try std.testing.expect(target(model, .{ .ask = .{ .d = first, .l = 0, .c = model.dialog[first].line[0].choice_n } }) == null);
}
