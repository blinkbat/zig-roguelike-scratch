const widgets = @import("widgets.zig");
const std = @import("std");
const Note = @import("../core/text.zig").Note;
const rl = @import("raylib");
const input = @import("../core/input.zig");
const mathx = @import("../core/mathx.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const raster = @import("../gfx/raster.zig");
const game = @import("../game.zig");
const editor = @import("editor.zig");
const interaction = @import("interaction.zig");
const catalog = @import("text_catalog.zig");

const PAD = widgets.PAD;
const TEXT = widgets.TEXT;
const DETAIL = widgets.DETAIL;
const ROW_PAD: i32 = 20;
const ENTRY_H = TEXT + 2 * DETAIL + ROW_PAD;
const SNIPPET_MAX: usize = 160;
const LEAD: i32 = 8;
const LINE_H: i32 = TEXT + LEAD;
const ROW_INSET: i32 = 4;
const BUTTON_GAP: i32 = 4;
const COUNT_PAD: i32 = 6;
const TOOL_GAP: i32 = 8;
const CLOSE_W: i32 = 90;
const RELOAD_W: i32 = 90;
const CLEAR_W: i32 = 86;
const SEARCH_GAP: i32 = 28;
const NAV_MIN_W: i32 = 180;
const NAV_MAX_W: i32 = 250;
const LIST_MIN_W: i32 = 240;
const LIST_MAX_W: i32 = 360;
const SAVE_W: i32 = 160;
const DISCARD_W: i32 = 100;
const NAV_PARTS: i32 = 5;
const LIST_PARTS: i32 = 4;
const WHEEL_ROWS: i32 = 3;
const HINT_GAP: i32 = 4;
const PAGE_LINE: usize = 1024;
const NAV_INDENT: i32 = 14;
const NAV_LEAD: usize = 3;
const SCROLL_ROOM: i32 = 8;
const DISCARD_FIRST = "Save or discard this passage before ";
const KEEP_GROUP = DISCARD_FIRST ++ "changing its group.";
const REBUILD = "Saved wording takes effect after rebuilding.";

pub fn fieldHeight(rows: i32) i32 {
    return rows * LINE_H + 2 * widgets.GAP;
}
const NAV_ROW = DETAIL + ROW_PAD;
const Focus = enum { search, passage };
const Leave = enum { close, quit };
const HISTORY = 16;
const Group = struct {
    category: []const u8,
    role: []const u8,
    owner: []const u8,
    first: usize,
    end: usize,
    matches: usize = 0,
    category_open: bool = false,
    role_open: bool = false,

    fn holds(g: Group, e: catalog.Entry) bool {
        return std.mem.eql(u8, g.category, e.category) and std.mem.eql(u8, g.role, e.role) and std.mem.eql(u8, g.owner, e.owner);
    }
};
const Depth = enum(u8) { category, role, owner };
const TreeRow = struct { group: usize, depth: Depth, matches: usize };
const Run = struct { end: usize, matches: usize };

fn runOf(groups: []const Group, start: usize, end: usize, comptime field: []const u8) Run {
    var at = start;
    var matches: usize = 0;
    while (at < end and std.mem.eql(u8, @field(groups[start], field), @field(groups[at], field))) : (at += 1) matches += groups[at].matches;
    return .{ .end = at, .matches = matches };
}
const FontKey = struct {
    ordered: bool,
    font: ?rl.Font,
    data_font: ?rl.Font,
    native: @FieldType(font.Face, "native"),

    fn of(face: *const font.Face) FontKey {
        return .{ .ordered = face.ordered, .font = face.font, .data_font = face.data_font, .native = face.native };
    }
};

const Field = FieldOf(catalog.MAX_TEXT, catalog.supported);

pub fn FieldOf(comptime N: usize, comptime accepts: fn (u8) bool) type {
    return struct {
        const Self = @This();
        pub const MAX = N;
        const Revision = struct { buf: [N + 1]u8, n: usize, cursor: usize, anchor: usize };

        buf: [N + 1]u8 = @splat(0),
        n: usize = 0,
        cap: usize = N,
        cursor: usize = 0,
        anchor: usize = 0,
        starts: [N + 2]usize = @splat(0),
        lines: usize = 1,
        rows: usize = 1,
        scroll: usize = 0,
        reveal: bool = true,
        layout_valid: bool = false,
        layout_width: i32 = 0,
        layout_font: FontKey = undefined,
        history: [HISTORY]Revision = undefined,
        history_base: usize = 0,
        history_n: usize = 0,
        history_at: usize = 0,

        pub fn text(f: *const Self) [:0]const u8 {
            return f.buf[0..f.n :0];
        }

        pub fn set(f: *Self, s: []const u8) void {
            f.n = @min(s.len, f.cap);
            @memcpy(f.buf[0..f.n], s[0..f.n]);
            f.buf[f.n] = 0;
            f.cursor = f.n;
            f.anchor = f.n;
            f.scroll = 0;
            f.reveal = true;
            f.layout_valid = false;
            f.lines = 1;
            f.starts[0] = 0;
            f.starts[1] = f.n;
            f.history_base = 0;
            f.history_at = 0;
            f.history_n = 1;
            f.history[0] = f.revision();
        }

        pub fn limit(f: *Self, cap: usize) void {
            f.cap = @min(cap, N);
        }

        fn revision(f: *const Self) Revision {
            return .{ .buf = f.buf, .n = f.n, .cursor = f.cursor, .anchor = f.anchor };
        }

        fn remember(f: *Self) void {
            if (f.history_n > 0) {
                const previous = &f.history[(f.history_base + f.history_at) % HISTORY];
                if (std.mem.eql(u8, previous.buf[0..previous.n], f.text())) return;
                f.history_n = f.history_at + 1;
            }
            if (f.history_n == HISTORY) {
                f.history_base = (f.history_base + 1) % HISTORY;
                f.history_n -= 1;
            }
            f.history[(f.history_base + f.history_n) % HISTORY] = f.revision();
            f.history_at = f.history_n;
            f.history_n += 1;
        }

        fn restoreRevision(f: *Self, by: i32) void {
            if (f.history_n == 0) return;
            f.history_at = mathx.nudge(f.history_at, by, f.history_n);
            const r = &f.history[(f.history_base + f.history_at) % HISTORY];
            f.buf = r.buf;
            f.n = r.n;
            f.cursor = r.cursor;
            f.anchor = r.anchor;
            f.reveal = true;
            f.layout_valid = false;
        }

        fn lineEnd(f: *const Self, line: usize) usize {
            const end = @min(f.n, f.starts[line + 1]);
            return if (end > f.starts[line] and f.buf[end - 1] == '\n') end - 1 else end;
        }

        fn picked(f: *const Self) struct { lo: usize, hi: usize } {
            return .{ .lo = @min(f.cursor, f.anchor), .hi = @max(f.cursor, f.anchor) };
        }

        fn erase(f: *Self) bool {
            const held = f.picked();
            if (held.lo == held.hi) return false;
            f.layout_valid = false;
            std.mem.copyForwards(u8, f.buf[held.lo..], f.buf[held.hi .. f.n + 1]);
            f.n -= held.hi - held.lo;
            f.cursor = held.lo;
            f.anchor = held.lo;
            return true;
        }

        pub fn insert(f: *Self, s: []const u8) bool {
            if (s.len == 0) return true;
            for (s) |c| if (!accepts(c)) return false;
            const held = f.picked();
            const removed = held.hi - held.lo;
            var count: usize = 0;
            for (s) |c| if (c != '\r') {
                count += 1;
            };
            if (f.n - removed + count > f.cap) return false;
            _ = f.erase();
            std.mem.copyBackwards(u8, f.buf[f.cursor + count .. f.n + count + 1], f.buf[f.cursor .. f.n + 1]);
            for (s) |c| {
                if (c == '\r') continue;
                f.buf[f.cursor] = c;
                f.cursor += 1;
            }
            f.n += count;
            f.anchor = f.cursor;
            f.layout_valid = false;
            return true;
        }

        fn layout(f: *Self, width: i32, key: FontKey, face: anytype) bool {
            if (f.layout_valid and f.layout_width == width and std.meta.eql(f.layout_font, key)) return false;
            var lines: usize = 0;
            var pos: usize = 0;
            var buf: [N + 1]u8 = undefined;
            while (true) {
                f.starts[lines] = pos;
                var end = pos;
                var last_space: ?usize = null;
                while (end < f.n and f.buf[end] != '\n') {
                    const next = end + 1;
                    @memcpy(buf[0 .. next - pos], f.buf[pos..next]);
                    buf[next - pos] = 0;
                    if (end > pos and displayWidth(face, buf[0 .. next - pos :0]) > width) break;
                    if (f.buf[end] == ' ') last_space = next;
                    end = next;
                }
                if (end < f.n and f.buf[end] != '\n') {
                    if (last_space) |space| if (space > pos) {
                        end = space;
                    };
                }
                lines += 1;
                if (end == f.n) break;
                pos = end + @as(usize, if (f.buf[end] == '\n') 1 else 0);
            }
            f.starts[lines] = f.n;
            f.lines = lines;
            f.layout_width = width;
            f.layout_font = key;
            f.layout_valid = true;
            return true;
        }

        pub fn feed(f: *Self, d: *const input.Desk, multiline: bool) bool {
            if (d.undo or d.redo) {
                f.restoreRevision(if (d.undo) -1 else 1);
                return true;
            }
            defer f.remember();
            if (d.text_all or d.text_left or d.text_right or d.text_home or d.text_end or d.rub or d.text_delete or d.paste or d.cut or d.text().len > 0 or (multiline and (d.enter or d.nav != 0))) f.reveal = true;
            if (d.text_all) {
                f.anchor = 0;
                f.cursor = f.n;
            }
            if (multiline and d.nav != 0) {
                var line: usize = 0;
                while (line + 1 < f.lines and f.starts[line + 1] <= f.cursor) : (line += 1) {}
                const column = f.cursor - f.starts[line];
                const next = mathx.nudge(line, d.nav, f.lines);
                var end = f.lineEnd(next);
                if (next + 1 < f.lines and end == f.starts[next + 1] and end > f.starts[next]) end -= 1;
                f.cursor = @min(end, f.starts[next] + column);
                if (!d.shift) f.anchor = f.cursor;
            }
            if (d.text_left or d.text_right or d.text_home or d.text_end) {
                if (d.text_home) f.cursor = 0 else if (d.text_end) f.cursor = f.n else if (!d.shift and f.anchor != f.cursor) {
                    f.cursor = if (d.text_left) @min(f.anchor, f.cursor) else @max(f.anchor, f.cursor);
                } else if (d.text_left) f.cursor -|= 1 else f.cursor = @min(f.n, f.cursor + 1);
                if (!d.shift) f.anchor = f.cursor;
            }
            if (d.copy or d.cut) {
                var copied: [N + 1]u8 = undefined;
                const held = f.picked();
                if (held.hi > held.lo) {
                    @memcpy(copied[0 .. held.hi - held.lo], f.buf[held.lo..held.hi]);
                    copied[held.hi - held.lo] = 0;
                    input.copyText(copied[0 .. held.hi - held.lo :0]);
                    if (d.cut) _ = f.erase();
                }
            }
            if (d.rub) {
                if (!f.erase() and f.cursor > 0) {
                    f.anchor = f.cursor - 1;
                    _ = f.erase();
                }
            }
            if (d.text_delete) {
                if (!f.erase() and f.cursor < f.n) {
                    f.anchor = f.cursor + 1;
                    _ = f.erase();
                }
            }
            if (d.paste_text) |s| {
                if (!multiline and !catalog.oneLine(s)) return false;
                if (!f.insert(s)) return false;
            }
            if (!f.insert(d.text())) return false;
            if (multiline and d.enter and !f.insert("\n")) return false;
            return true;
        }
    };
}

pub const State = struct {
    data: ?*catalog.Catalog = null,
    search: Field = .{},
    draft: Field = .{},
    selected: ?usize = null,
    top: usize = 0,
    rows: usize = 7,
    focus: Focus = .search,
    author: catalog.Author = .unknown,
    typed_author: bool = false,
    leave: ?Leave = null,
    note: Note(255) = .{},
    passage_box: rl.Rectangle = widgets.NO_BOX,
    nav_box: rl.Rectangle = widgets.NO_BOX,
    list_box: rl.Rectangle = widgets.NO_BOX,
    category: ?[]const u8 = null,
    owner: ?[]const u8 = null,
    role: ?[]const u8 = null,
    nav_top: usize = 0,
    nav_rows: usize = 1,
    nav_count: usize = 0,
    order: std.ArrayListUnmanaged(usize) = .{},
    groups: std.ArrayListUnmanaged(Group) = .{},
    tree: std.ArrayListUnmanaged(TreeRow) = .{},
    results: std.ArrayListUnmanaged(usize) = .{},
    view_dirty: bool = true,

    pub fn deinit(s: *State, alloc: std.mem.Allocator) void {
        s.order.deinit(alloc);
        s.groups.deinit(alloc);
        s.tree.deinit(alloc);
        s.results.deinit(alloc);
        if (s.data) |c| {
            c.deinit();
            alloc.destroy(c);
        }
        s.data = null;
    }

    fn say(s: *State, comptime fmt: []const u8, args: anytype) void {
        s.note.say(fmt, args);
    }

    pub fn dirty(s: *const State) bool {
        const c = s.data orelse return false;
        const i = s.selected orelse return false;
        if (i >= c.entries().len) return false;
        const e = c.entries()[i];
        if (!e.editable) return false;
        return !std.mem.eql(u8, s.draft.text(), e.text) or s.author != e.author;
    }

    fn queryMatches(s: *const State, e: catalog.Entry) bool {
        const q = s.search.text();
        if (q.len == 0) return true;
        for ([_][]const u8{ e.text, e.path, e.category, e.owner, e.role, e.context }) |value| {
            if (q.len <= value.len and std.ascii.indexOfIgnoreCasePosLinear(value, 0, q) != null) return true;
        }
        return false;
    }

    fn inScope(s: *const State, e: catalog.Entry) bool {
        if (s.category) |category| if (!std.mem.eql(u8, category, e.category)) return false;
        if (s.owner) |owner| if (!std.mem.eql(u8, owner, e.owner)) return false;
        if (s.role) |role| if (!std.mem.eql(u8, role, e.role)) return false;
        return true;
    }

    fn reindex(s: *State, alloc: std.mem.Allocator) !void {
        s.order.clearRetainingCapacity();
        s.groups.clearRetainingCapacity();
        s.results.clearRetainingCapacity();
        s.category = null;
        s.owner = null;
        s.role = null;
        s.nav_top = 0;
        const c = s.data orelse return;
        const entries = c.entries();
        try s.order.ensureTotalCapacity(alloc, entries.len);
        try s.groups.ensureTotalCapacity(alloc, entries.len);
        try s.tree.ensureTotalCapacity(alloc, entries.len * std.enums.values(Depth).len);
        try s.results.ensureTotalCapacity(alloc, entries.len);
        for (entries, 0..) |_, i| s.order.appendAssumeCapacity(i);
        std.mem.sort(usize, s.order.items, entries, struct {
            fn less(es: []const catalog.Entry, x: usize, y: usize) bool {
                const a = es[x];
                const b = es[y];
                inline for (.{ "category", "role", "owner", "path" }) |field| {
                    const cmp = std.mem.order(u8, @field(a, field), @field(b, field));
                    if (cmp != .eq) return cmp == .lt;
                }
                if (a.line != b.line) return a.line < b.line;
                return x < y;
            }
        }.less);
        for (s.order.items, 0..) |index, at| {
            const e = entries[index];
            if (s.groups.items.len > 0) {
                const previous = &s.groups.items[s.groups.items.len - 1];
                if (previous.holds(e)) {
                    previous.end = at + 1;
                    continue;
                }
            }
            s.groups.appendAssumeCapacity(.{ .category = e.category, .role = e.role, .owner = e.owner, .first = at, .end = at + 1 });
        }
        s.view_dirty = true;
        s.refresh();
    }

    fn refresh(s: *State) void {
        if (!s.view_dirty) return;
        s.results.clearRetainingCapacity();
        const c = s.data orelse return;
        for (s.groups.items) |*group| {
            group.matches = 0;
            for (s.order.items[group.first..group.end]) |index| {
                const e = c.entries()[index];
                if (!s.queryMatches(e)) continue;
                group.matches += 1;
                if (s.inScope(e)) s.results.appendAssumeCapacity(index);
            }
        }
        s.top = widgets.clampTop(s.top, s.results.items.len, s.rows);
        s.view_dirty = false;
    }

    fn searched(s: *State) void {
        s.top = 0;
        s.nav_top = 0;
        s.view_dirty = true;
    }

    fn scope(s: *State, category: ?[]const u8, owner: ?[]const u8) void {
        if (s.dirty()) return s.say(KEEP_GROUP, .{});
        const same_category = if (s.category) |previous| if (category) |next| std.mem.eql(u8, previous, next) else false else category == null;
        s.category = category;
        s.owner = owner;
        s.role = null;
        s.top = 0;
        if (!same_category) s.nav_top = 0;
        s.selected = null;
        s.focus = .search;
        s.view_dirty = true;
        s.note.clear();
    }

    fn buildTree(s: *State) void {
        s.tree.clearRetainingCapacity();
        const groups = s.groups.items;
        var category: usize = 0;
        while (category < groups.len) {
            const in_category = runOf(groups, category, groups.len, "category");
            if (in_category.matches > 0) {
                s.tree.appendAssumeCapacity(.{ .group = category, .depth = .category, .matches = in_category.matches });
                if (groups[category].category_open) {
                    var role = category;
                    while (role < in_category.end) {
                        const in_role = runOf(groups, role, in_category.end, "role");
                        if (in_role.matches > 0) {
                            s.tree.appendAssumeCapacity(.{ .group = role, .depth = .role, .matches = in_role.matches });
                            if (groups[role].role_open) {
                                for (role..in_role.end) |i| if (groups[i].matches > 0) {
                                    s.tree.appendAssumeCapacity(.{ .group = i, .depth = .owner, .matches = groups[i].matches });
                                };
                            }
                        }
                        role = in_role.end;
                    }
                }
            }
            category = in_category.end;
        }
    }

    fn selectTree(s: *State, row: TreeRow) void {
        if (s.dirty()) return s.say(KEEP_GROUP, .{});
        const group = &s.groups.items[row.group];
        switch (row.depth) {
            .category => group.category_open = !group.category_open,
            .role => group.role_open = !group.role_open,
            .owner => {},
        }
        const top = s.nav_top;
        s.scope(group.category, if (row.depth == .owner) group.owner else null);
        s.role = if (row.depth != .category) group.role else null;
        s.nav_top = top;
    }

    fn pick(s: *State, i: usize) bool {
        if (s.selected == i) return true;
        if (s.dirty()) {
            s.say(DISCARD_FIRST ++ "selecting another.", .{});
            return false;
        }
        s.selected = i;
        s.restore();
        s.note.clear();
        return true;
    }

    fn restore(s: *State) void {
        const c = s.data orelse return;
        const i = s.selected orelse return;
        if (i >= c.entries().len) {
            s.selected = null;
            return;
        }
        const e = c.entries()[i];
        s.draft.set(e.text);
        s.author = e.author;
        s.typed_author = false;
    }
};

pub fn open(ed: *editor.Editor) void {
    const s = &ed.words;
    if (s.data == null) {
        const c = ed.alloc.create(catalog.Catalog) catch {
            ed.say("The text editor ran out of memory.", .{});
            return;
        };
        c.* = catalog.Catalog.init(ed.alloc);
        s.data = c;
        reload(ed);
    }
    s.leave = null;
    ed.ask(.text);
}

fn reload(ed: *editor.Editor) void {
    const s = &ed.words;
    if (s.dirty()) return s.say(DISCARD_FIRST ++ "reloading.", .{});
    const c = s.data orelse return;
    c.load(@import("assets").source_root) catch |err| {
        s.selected = null;
        s.say("Could not load project text: {s}", .{@errorName(err)});
        return;
    };
    s.selected = null;
    s.top = 0;
    s.reindex(ed.alloc) catch {
        s.say("Could not organize project text: out of memory.", .{});
        return;
    };
    if (c.warning.len > 0) s.say("{s}", .{c.warning}) else s.say("Loaded {d} passages. " ++ REBUILD, .{c.entries().len});
}

pub fn pose(ed: *editor.Editor) !void {
    try poseContext(ed, "play.fireball.DESCRIPTION");
}

pub fn poseContext(ed: *editor.Editor, context: []const u8) !void {
    open(ed);
    const s = &ed.words;
    const c = s.data orelse return error.TextCatalogMissing;
    s.search.set("");
    for (c.entries(), 0..) |entry, i| {
        if (!std.mem.startsWith(u8, entry.context, context) or !entry.editable) continue;
        s.scope(entry.category, entry.owner);
        s.role = entry.role;
        _ = s.pick(i);
        s.refresh();
        for (s.groups.items) |*group| {
            if (!std.mem.eql(u8, group.category, entry.category)) continue;
            group.category_open = true;
            if (std.mem.eql(u8, group.role, entry.role)) group.role_open = true;
        }
        s.buildTree();
        for (s.tree.items, 0..) |row, at| {
            if (row.depth == .owner and s.groups.items[row.group].holds(entry)) {
                s.nav_top = at -| NAV_LEAD;
                break;
            }
        }
        s.focus = .passage;
        return;
    }
    return error.TextPassageMissing;
}

pub fn requestClose(ed: *editor.Editor, quit: bool) void {
    const s = &ed.words;
    s.leave = if (quit or s.leave == .quit) .quit else .close;
    if (s.dirty()) return;
    finishClose(ed);
}

fn finishClose(ed: *editor.Editor) void {
    const leave = ed.words.leave orelse return;
    ed.words.leave = null;
    ed.closeModal();
    if (leave == .quit) ed.request(.quit);
}

fn save(ed: *editor.Editor) void {
    const s = &ed.words;
    const c = s.data orelse return;
    const i = s.selected orelse return;
    if (!s.dirty()) return;
    const result = c.save(i, s.draft.text(), s.author) catch |err| {
        s.say("Could not save: {s}. Your draft is still here.", .{@errorName(err)});
        return;
    };
    s.restore();
    s.view_dirty = true;
    if (result == .saved) {
        s.say("Saved. Rebuild to apply wording changes.", .{});
        finishClose(ed);
    } else {
        s.say("Source saved; author tags could not be saved.", .{});
        s.leave = null;
    }
}

pub fn keys(ed: *editor.Editor) void {
    const s = &ed.words;
    const d = &ed.desk;
    if (interaction.backed(d)) {
        requestClose(ed, false);
        return;
    }
    if (d.save) {
        save(ed);
        return;
    }
    if (s.leave != null) return;
    if (s.focus == .search) {
        const old = catalog.hash(s.search.text());
        if (!s.search.feed(d, false)) s.say("Search accepts plain ASCII text on one line.", .{});
        if (catalog.hash(s.search.text()) != old) s.searched();
    } else if (s.selected) |i| {
        const e = s.data.?.entries()[i];
        if (e.editable) {
            const was_dirty = s.dirty();
            const old = catalog.hash(s.draft.text());
            if (!s.draft.feed(d, e.alias == null)) s.say("Text must be ASCII{s} and at most {d} characters.", .{ if (e.alias != null) " on one line" else "", catalog.MAX_TEXT });
            if (!was_dirty and catalog.hash(s.draft.text()) != old) {
                s.author = .you;
                s.typed_author = true;
            }
            if (s.typed_author and std.mem.eql(u8, s.draft.text(), e.text)) {
                s.author = e.author;
                s.typed_author = false;
            }
        } else {
            var nav = d.navigationOnly();
            _ = s.draft.feed(&nav, true);
        }
    }
    if (d.wheel == 0 and (d.nav == 0 or s.focus != .search)) return;
    s.refresh();
    const n = s.results.items.len;
    if (d.wheel != 0) {
        const by = WHEEL_ROWS * d.notch();
        if (raster.holds(s.passage_box, d.mouse)) {
            s.draft.scroll = widgets.scrollTop(s.draft.scroll, by, s.draft.lines, s.draft.rows);
            s.draft.reveal = false;
        } else if (raster.holds(s.nav_box, d.mouse)) {
            s.nav_top = widgets.scrollTop(s.nav_top, by, s.nav_count, s.nav_rows);
        } else if (raster.holds(s.list_box, d.mouse)) s.top = widgets.scrollTop(s.top, by, n, s.rows);
    }
    if (d.nav != 0 and s.focus == .search and n > 0) {
        const at = if (s.selected) |sel| std.mem.indexOfScalar(usize, s.results.items, sel) else null;
        const next = if (at) |a| mathx.wrap(a, d.nav, n) else if (d.nav < 0) n - 1 else 0;
        if (s.pick(s.results.items[next])) s.top = mathx.reveal(s.top, next, s.rows);
    }
}

fn button(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool) bool {
    return editor.modalButton(ed, g, r, label, on, live, null);
}

fn displayBytes(s: []u8) void {
    for (s) |*c| {
        if (c.* == input.GLYPH_OPEN) c.* = '[';
        if (c.* == input.GLYPH_CLOSE) c.* = ']';
        if (c.* == '\t') c.* = ' ';
    }
}

fn displayWidth(face: anytype, s: [:0]u8) i32 {
    displayBytes(s);
    return face.width(s, TEXT);
}

fn widthTo(face: anytype, buf: []u8, n: usize) i32 {
    const held = buf[n];
    buf[n] = 0;
    defer buf[n] = held;
    return displayWidth(face, buf[0..n :0]);
}

pub fn drawField(ed: *editor.Editor, g: *game.Game, f: anytype, r: rl.Rectangle, focused: bool, editable: bool) bool {
    const origin = widgets.well(r, focused);
    const hit = widgets.hot(ed.controls(), r, true, true, null).hit;
    const x = origin.x;
    const y = origin.y;
    const width = widgets.insetW(r) - SCROLL_ROOM;
    const rows = widgets.rowsIn(raster.height(r) - fieldHeight(0), LINE_H);
    _ = f.layout(width, FontKey.of(&g.face), &g.face);
    const breaks = f.starts[0 .. f.lines + 1];
    const lines = f.lines;
    var buf: [@TypeOf(f.*).MAX + 1]u8 = undefined;
    var caret_line: usize = 0;
    for (breaks[0..lines], 0..) |pos, line| if (f.cursor >= pos) {
        caret_line = line;
    };
    f.rows = rows;
    if (f.reveal and focused) f.scroll = mathx.reveal(f.scroll, caret_line, rows);
    f.reveal = false;
    f.scroll = widgets.clampTop(f.scroll, lines, rows);
    widgets.scrollbarIn(r, f.scroll, rows, lines);
    const first = f.scroll;
    widgets.scissorIn(ed.clip, r);
    defer widgets.reclip(ed.clip);
    for (first..@min(lines, first + rows)) |line| {
        const start = breaks[line];
        const end = f.lineEnd(line);
        const yy = y + @as(i32, @intCast(line - first)) * LINE_H;
        const held = f.picked();
        const lo = std.math.clamp(held.lo, start, end);
        const hi = std.math.clamp(held.hi, start, end);
        @memcpy(buf[0 .. end - start], f.buf[start..end]);
        buf[end - start] = 0;
        if (focused and hi > lo) {
            const left = widthTo(&g.face, &buf, lo - start);
            rl.drawRectangle(x + left, yy, widthTo(&g.face, &buf, hi - start) - left, LINE_H, widgets.ROW_ON);
        }
        displayBytes(buf[0 .. end - start]);
        g.face.draw(buf[0 .. end - start :0], x, yy, TEXT, if (editable) look.TEXT else look.DIM);
        if (focused and caret_line == line) {
            rl.drawRectangle(x + widthTo(&g.face, &buf, @min(f.cursor, end) - start), yy, 2, TEXT, look.UI_FOCUS);
        }
        if (hit and ed.desk.mouse.y >= yy and ed.desk.mouse.y < yy + LINE_H) {
            var at = start;
            while (at < end) : (at += 1) {
                if (x + widthTo(&g.face, &buf, at + 1 - start) > ed.desk.mouse.x) break;
            }
            f.cursor = at;
            if (!ed.desk.shift) f.anchor = at;
            f.reveal = true;
        }
    }
    return hit;
}

fn navItem(ed: *editor.Editor, g: *game.Game, ordinal: usize, label: []const u8, count: usize, on: bool, depth: Depth) bool {
    const s = &ed.words;
    if (ordinal < s.nav_top or ordinal >= s.nav_top + s.nav_rows) return false;
    const indent = @as(i32, @intFromEnum(depth)) * NAV_INDENT;
    const x = raster.left(s.nav_box) + indent;
    const y = raster.top(s.nav_box) + @as(i32, @intCast(ordinal - s.nav_top)) * NAV_ROW;
    const w = raster.width(s.nav_box) - indent;
    const r = raster.rect(x, y, w - widgets.GAP, NAV_ROW - BUTTON_GAP);
    const h = widgets.plateHit(ed.controls(), r, on, s.leave == null, true, null);
    var buf: [32]u8 = undefined;
    const number = std.fmt.bufPrintZ(&buf, "{d}", .{count}) catch "";
    const number_w = widgets.drawRight(&g.face, number, DETAIL, x + w - widgets.GAP, y + LEAD, look.DIM);
    widgets.drawFit(&g.face, label, DETAIL, w - number_w - 3 * widgets.GAP - COUNT_PAD, false, x + widgets.GAP, y + LEAD, if (on) look.UI_GOLD else look.TEXT);
    return h.hit;
}

fn drawNavigation(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, bottom: i32) void {
    const s = &ed.words;
    widgets.drawFit(&g.face, "Text library", TEXT, w, false, x, y, look.UI_GOLD);
    var yy = y + LINE_H;
    if (button(ed, g, widgets.row(x, yy, w - widgets.GAP), "All text", s.category == null, s.leave == null)) s.scope(null, null);
    yy += widgets.ROW_STEP;
    s.nav_box = raster.rect(x, yy, w, @max(0, bottom - yy));
    s.nav_rows = widgets.rowsIn(bottom - yy, NAV_ROW);
    s.buildTree();
    const count = s.tree.items.len;
    s.nav_count = count;
    s.nav_top = widgets.clampTop(s.nav_top, count, s.nav_rows);
    for (s.tree.items, 0..) |row, ordinal| {
        const group = s.groups.items[row.group];
        const label = switch (row.depth) {
            .category => group.category,
            .role => group.role,
            .owner => group.owner,
        };
        const expanded = if (row.depth == .category) group.category_open else group.role_open;
        var buf: [PAGE_LINE]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ if (row.depth == .owner) "" else if (expanded) "- " else "+ ", label }) catch "";
        const on = s.category != null and std.mem.eql(u8, s.category.?, group.category) and
            (if (row.depth == .category) s.role == null and s.owner == null else s.role != null and std.mem.eql(u8, s.role.?, group.role) and
                (if (row.depth == .role) s.owner == null else s.owner != null and std.mem.eql(u8, s.owner.?, group.owner)));
        if (navItem(ed, g, ordinal, text, row.matches, on, row.depth)) s.selectTree(row);
    }
    widgets.scrollbarIn(s.nav_box, s.nav_top, s.nav_rows, s.nav_count);
}

pub fn draw(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.words;
    s.refresh();
    const page = widgets.pageFrame(&g.face, g.screen, "Text editor");
    const f = page.frame;
    const col = page.column();
    const x = col.left();
    const w = col.inner();
    var y = f.y;
    var buf: [PAGE_LINE]u8 = undefined;
    widgets.drawFit(&g.face, "Search wording, concern, owner or source", DETAIL, w, false, x, y, if (s.focus == .search) look.UI_GOLD else look.DIM);
    y += widgets.DETAIL_STEP;
    var tools = widgets.LayEnd{ .right = x + w, .y = y + ROW_INSET, .gap = TOOL_GAP };
    const close_r = tools.take(CLOSE_W);
    const reload_r = tools.take(RELOAD_W);
    const clear_r = tools.take(CLEAR_W);
    if (drawField(ed, g, &s.search, raster.rect(x, y, raster.left(clear_r) - PAD - x, fieldHeight(1)), s.focus == .search, true)) s.focus = .search;
    if (button(ed, g, clear_r, "Clear", false, s.search.n > 0)) {
        s.search.set("");
        s.searched();
        s.focus = .search;
    }
    if (button(ed, g, reload_r, "Reload", false, !s.dirty())) reload(ed);
    if (button(ed, g, close_r, "Close", false, true)) requestClose(ed, false);
    y += LINE_H + SEARCH_GAP;
    const bottom = page.bottom - DETAIL - LEAD;
    const nav_w = widgets.share(w, NAV_PARTS, NAV_MIN_W, NAV_MAX_W);
    const list_x = widgets.besides(x, nav_w, y, bottom);
    const list_w = widgets.share(w, LIST_PARTS, LIST_MIN_W, LIST_MAX_W);
    const right_x = widgets.besides(list_x, list_w, y, bottom);
    const right_w = x + w - right_x;
    drawNavigation(ed, g, x, y, nav_w, bottom);
    widgets.drawFit(&g.face, "Passages", TEXT, list_w, false, list_x, y, look.UI_GOLD);
    const list_y = y + LINE_H;
    s.rows = widgets.rowsIn(bottom - list_y - DETAIL - LEAD, ENTRY_H);
    s.top = widgets.clampTop(s.top, s.results.items.len, s.rows);
    s.list_box = raster.rect(list_x, list_y, list_w, @as(i32, @intCast(s.rows)) * ENTRY_H);
    if (s.data) |c| {
        const entry_w = list_w - ROW_PAD;
        const end = @min(s.results.items.len, s.top + s.rows);
        for (s.results.items[s.top..end], 0..) |i, at| {
            const e = c.entries()[i];
            const yy = list_y + @as(i32, @intCast(at)) * ENTRY_H;
            const r = raster.rect(list_x, yy, list_w - widgets.GAP, ENTRY_H - widgets.GAP);
            const h = widgets.plateHit(ed.controls(), r, s.selected == i, s.leave == null, true, null);
            widgets.drawFit(&g.face, e.role, TEXT, entry_w, false, list_x + widgets.GAP, yy + ROW_INSET, if (s.selected == i) look.UI_GOLD else look.TEXT);
            widgets.drawFit(&g.face, e.owner, DETAIL, entry_w, false, list_x + widgets.GAP, yy + LINE_H, look.DIM);
            var snippet: [SNIPPET_MAX]u8 = undefined;
            const n = @min(e.text.len, SNIPPET_MAX);
            @memcpy(snippet[0..n], e.text[0..n]);
            for (snippet[0..n]) |*char| if (char.* < ' ') {
                char.* = ' ';
            };
            widgets.drawFit(&g.face, snippet[0..n], DETAIL, entry_w, false, list_x + widgets.GAP, yy + LINE_H + DETAIL + ROW_INSET, look.TEXT);
            if (h.hit and s.pick(i)) s.focus = .passage;
        }
    }
    widgets.scrollbarIn(s.list_box, s.top, s.rows, s.results.items.len);
    const count_label = std.fmt.bufPrintZ(&buf, "{d} passages", .{s.results.items.len}) catch "";
    widgets.drawFit(&g.face, count_label, DETAIL, list_w, false, list_x, bottom - DETAIL, look.DIM);
    if (s.results.items.len == 0) {
        widgets.drawFit(&g.face, "No matching passages.", DETAIL, list_w, false, list_x + widgets.GAP, list_y + LEAD, look.TEXT);
        widgets.drawFit(&g.face, "Clear search or choose another group.", DETAIL, list_w, false, list_x + widgets.GAP, list_y + LEAD + DETAIL + LEAD, look.DIM);
    }
    s.passage_box = widgets.NO_BOX;
    if (s.selected) |i| if (s.data) |c| {
        const e = c.entries()[i];
        widgets.drawFit(&g.face, e.owner, TEXT, right_w, false, right_x, y, look.TEXT);
        const breadcrumb = std.fmt.bufPrintZ(&buf, "{s}  >  {s}", .{ e.category, e.role }) catch "";
        widgets.drawFit(&g.face, breadcrumb, DETAIL, right_w, false, right_x, y + LINE_H, look.UI_GOLD);
        const source = std.fmt.bufPrintZ(&buf, "{s}:{d}", .{ e.path, e.line }) catch "";
        widgets.drawFit(&g.face, source, DETAIL, right_w, true, right_x, y + LINE_H + widgets.DETAIL_STEP, look.DIM);
        widgets.drawFit(&g.face, e.context, DETAIL, right_w, true, right_x, y + LINE_H + 2 * widgets.DETAIL_STEP, look.DIM);
        var yy = y + LINE_H + 3 * widgets.DETAIL_STEP + HINT_GAP;
        const hint = std.fmt.bufPrintZ(&buf, "{s}  |  {d}/{d} characters", .{ if (e.editable) "Wording" else "Reference only", s.draft.n, catalog.MAX_TEXT }) catch "";
        widgets.drawFit(&g.face, hint, DETAIL, right_w, false, right_x, yy, if (s.focus == .passage) look.UI_GOLD else look.DIM);
        yy += DETAIL + LEAD;
        const field_h = @max(fieldHeight(1), bottom - yy - (DETAIL + LEAD + 2 * widgets.ROW_STEP + DETAIL + LEAD));
        s.passage_box = raster.rect(right_x, yy, right_w, field_h);
        if (drawField(ed, g, &s.draft, s.passage_box, s.focus == .passage, e.editable)) s.focus = .passage;
        yy += field_h + LEAD;
        widgets.drawFit(&g.face, "Written by", DETAIL, right_w, false, right_x, yy, look.DIM);
        yy += widgets.DETAIL_STEP;
        const tags = std.enums.values(catalog.Author);
        const tag_w = @divTrunc(right_w, @as(i32, @intCast(tags.len)));
        for (tags, 0..) |tag, at| {
            const label: [:0]const u8 = switch (tag) {
                .unknown => "Unknown",
                .you => "You",
                .ai => "AI",
                .mixed => "Mixed",
            };
            if (button(ed, g, widgets.row(right_x + @as(i32, @intCast(at)) * tag_w, yy, tag_w - BUTTON_GAP), label, s.author == tag, e.editable and s.leave == null)) {
                s.author = tag;
                s.typed_author = false;
            }
        }
        yy += widgets.ROW_STEP;
        const save_w = @min(SAVE_W, @divTrunc(right_w, 3));
        var foot = widgets.Lay{ .x = right_x, .y = yy };
        if (button(ed, g, foot.take(save_w), "Save passage", false, e.editable and s.dirty())) save(ed);
        if (button(ed, g, foot.take(DISCARD_W), "Discard", false, s.dirty())) {
            s.restore();
            s.note.clear();
            if (s.leave != null) finishClose(ed);
        }
        if (s.leave != null and button(ed, g, foot.take(right_x + right_w - foot.x), "Keep editing", false, true)) s.leave = null;
        yy += widgets.ROW_STEP;
        const status = if (s.leave != null) "Save or discard before leaving." else if (!e.editable) e.reason else if (s.dirty()) "Unsaved changes" else if (e.alias != null) "Display name; code identity stays fixed." else "Keep format placeholders and control markers intact.";
        widgets.drawFit(&g.face, status, DETAIL, right_w, false, right_x, yy, if (s.dirty()) look.UI_FOCUS else look.DIM);
    };
    if (s.selected == null) {
        widgets.drawFit(&g.face, "Choose a passage", TEXT, right_w, false, right_x, y, look.TEXT);
        _ = g.face.paragraph("Expand a concern, then a text type and owner. Select a passage to edit its wording.", right_x, y + LINE_H + LEAD, right_w, DETAIL, look.DIM);
    }
    const note = if (s.note.n > 0) s.note.text() else REBUILD;
    widgets.drawFit(&g.face, note, DETAIL, w, false, x, bottom + LEAD, look.UI_GOLD);
}

test "text field replaces selections, preserves drafts on invalid paste, and inserts at cursor" {
    var f = Field{};
    f.set("A rat bites.");
    f.anchor = 2;
    f.cursor = 5;
    try std.testing.expect(f.insert("slime"));
    try std.testing.expectEqualStrings("A slime bites.", f.text());
    try std.testing.expect(!f.insert("\xc3\xa9"));
    try std.testing.expectEqualStrings("A slime bites.", f.text());
    f.cursor = 0;
    f.anchor = 0;
    try std.testing.expect(f.insert("Look!\r\n"));
    try std.testing.expectEqualStrings("Look!\nA slime bites.", f.text());
}

test "text browser groups semantic owners and protects a dirty passage during navigation" {
    const alloc = std.testing.allocator;
    const ed = try editor.Editor.create(alloc);
    defer ed.destroy();
    const c = try alloc.create(catalog.Catalog);
    c.* = catalog.Catalog.init(alloc);
    ed.words.data = c;
    for ([_]catalog.Entry{
        .{ .path = "src/play/fireball.zig", .line = 2, .text = "A fiery burst.", .category = "Skills", .owner = "Fireball", .role = "Description", .context = "play.fireball.DESCRIPTION", .file = 0, .start = 0, .end = 0, .ordinal = 0 },
        .{ .path = "src/play/fireball.zig", .line = 3, .text = "Fire follows.", .category = "Skills", .owner = "Fireball", .role = "Status", .context = "play.fireball.STATUS", .file = 0, .start = 0, .end = 0, .ordinal = 1 },
        .{ .path = "src/play/ward.zig", .line = 2, .text = "A magical shield.", .category = "Skills", .owner = "Mana shield", .role = "Description", .context = "play.ward.DESCRIPTION", .file = 0, .start = 0, .end = 0, .ordinal = 0 },
    }) |entry| try c.list.append(c.arena.allocator(), entry);
    const s = &ed.words;
    try s.reindex(alloc);
    try std.testing.expectEqual(@as(usize, 3), s.groups.items.len);
    try std.testing.expectEqual(@as(usize, 3), s.results.items.len);
    s.buildTree();
    try std.testing.expectEqual(@as(usize, 1), s.tree.items.len);
    s.selectTree(s.tree.items[0]);
    s.refresh();
    s.buildTree();
    try std.testing.expectEqual(@as(usize, 3), s.tree.items.len);
    s.selectTree(s.tree.items[1]);
    s.refresh();
    s.buildTree();
    try std.testing.expectEqual(@as(usize, 5), s.tree.items.len);
    try std.testing.expectEqual(Depth.owner, s.tree.items[2].depth);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, s.results.items);
    s.scope(null, null);
    s.search.set("play.ward");
    s.view_dirty = true;
    s.refresh();
    try std.testing.expectEqualSlices(usize, &.{2}, s.results.items);
    s.search.set("");
    s.scope("Skills", "Fireball");
    s.refresh();
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, s.results.items);
    try std.testing.expect(s.pick(0));
    try std.testing.expect(s.draft.insert("!"));
    s.rows = 1;
    s.top = 0;
    ed.desk = .{ .nav = 1 };
    keys(ed);
    try std.testing.expectEqual(@as(?usize, 0), s.selected);
    try std.testing.expectEqual(@as(usize, 0), s.top);
    s.scope("Skills", "Mana shield");
    try std.testing.expectEqualStrings("Fireball", s.owner.?);
    try std.testing.expectEqualStrings("A fiery burst.!", s.draft.text());
}

test "text field on one line refuses the breaks and tabs a display alias cannot save" {
    var f = Field{};
    f.set("Bow");
    try std.testing.expect(!f.feed(&.{ .paste_text = "Long\tbow" }, false));
    try std.testing.expect(!f.feed(&.{ .paste_text = "Long\nbow" }, false));
    try std.testing.expect(f.feed(&.{ .enter = true }, false));
    try std.testing.expectEqualStrings("Bow", f.text());
    try std.testing.expect(catalog.oneLine(f.text()));
    try std.testing.expect(f.feed(&.{ .paste_text = "\tbow" }, true));
    try std.testing.expectEqualStrings("Bow\tbow", f.text());
}

test "text field selection survives select all, shift arrows and idle frames" {
    var f = Field{};
    f.set("A rat bites.");
    try std.testing.expect(f.feed(&.{ .text_all = true }, true));
    try std.testing.expectEqual(@as(usize, 0), f.anchor);
    try std.testing.expectEqual(f.n, f.cursor);
    try std.testing.expect(f.feed(&.{}, true));
    try std.testing.expectEqualStrings("A rat bites.", f.text());
    f.anchor = f.n;
    try std.testing.expect(f.feed(&.{ .shift = true, .text_left = true }, true));
    try std.testing.expectEqual(f.n - 1, f.cursor);
    try std.testing.expectEqualStrings("A rat bites.", f.text());
}

test "text field walks wrapped lines and pastes protected control markers" {
    var f = Field{};
    f.set("Long first line\nNext line");
    f.starts[0] = 0;
    f.starts[1] = 11;
    f.starts[2] = 16;
    f.starts[3] = f.n;
    f.lines = 3;
    f.cursor = 2;
    f.anchor = 2;
    try std.testing.expect(f.feed(&.{ .nav = 1, .shift = true }, true));
    try std.testing.expectEqual(@as(usize, 13), f.cursor);
    try std.testing.expectEqual(@as(usize, 2), f.anchor);
    try std.testing.expect(f.feed(&.{ .nav = 1 }, true));
    try std.testing.expectEqual(@as(usize, 18), f.cursor);
    try std.testing.expectEqual(f.cursor, f.anchor);
    f.set("01234567890123456789012345");
    f.starts[0] = 0;
    f.starts[1] = 10;
    f.starts[2] = 15;
    f.starts[3] = f.n;
    f.lines = 3;
    f.cursor = 9;
    f.anchor = 9;
    try std.testing.expect(f.feed(&.{ .nav = 1 }, true));
    try std.testing.expectEqual(@as(usize, 14), f.cursor);
    f.set("Use ");
    try std.testing.expect(f.insert("\x1eEnter\x1f"));
    try std.testing.expectEqualStrings("Use \x1eEnter\x1f", f.text());
}

test "text field undo and redo retain edits and replace an abandoned redo" {
    var f = Field{};
    f.set("Bow");
    var d = input.Desk{};
    d.typed.n = 1;
    d.typed.buf[0] = '!';
    try std.testing.expect(f.feed(&d, true));
    try std.testing.expectEqualStrings("Bow!", f.text());
    try std.testing.expect(f.feed(&.{ .undo = true }, true));
    try std.testing.expectEqualStrings("Bow", f.text());
    try std.testing.expect(f.feed(&.{ .redo = true }, true));
    try std.testing.expectEqualStrings("Bow!", f.text());
    try std.testing.expect(f.feed(&.{ .undo = true }, true));
    d.typed.buf[0] = '?';
    try std.testing.expect(f.feed(&d, true));
    try std.testing.expect(f.feed(&.{ .redo = true }, true));
    try std.testing.expectEqualStrings("Bow?", f.text());
}

test "text field wrap cache retains idle measurements and invalidates edits width and fonts" {
    const Measure = struct {
        calls: usize = 0,
        fn width(m: *@This(), text: [:0]const u8, _: i32) i32 {
            m.calls += 1;
            for (text) |c| std.debug.assert(c != input.GLYPH_OPEN and c != input.GLYPH_CLOSE and c != '\t');
            return @intCast(text.len);
        }
    };
    var measure = Measure{};
    var key = FontKey.of(&.{});
    var f = Field{};
    f.set("abcd\nEF");
    try std.testing.expect(f.layout(3, key, &measure));
    try std.testing.expectEqualSlices(usize, &.{ 0, 3, 5, 7 }, f.starts[0 .. f.lines + 1]);
    const calls = measure.calls;
    for (0..60) |_| try std.testing.expect(!f.layout(3, key, &measure));
    try std.testing.expectEqual(calls, measure.calls);
    try std.testing.expect(f.feed(&.{ .text_left = true }, true));
    try std.testing.expect(!f.layout(3, key, &measure));
    try std.testing.expect(f.insert("!"));
    try std.testing.expect(f.layout(3, key, &measure));
    f.anchor = f.cursor - 1;
    try std.testing.expect(f.erase());
    try std.testing.expect(f.layout(3, key, &measure));
    try std.testing.expect(f.layout(4, key, &measure));
    try std.testing.expectEqualSlices(usize, &.{ 0, 5, 7 }, f.starts[0 .. f.lines + 1]);
    key.native[1] = std.mem.zeroes(rl.Font);
    try std.testing.expect(f.layout(4, key, &measure));
    key.native[1].?.texture.id = 1;
    try std.testing.expect(f.layout(4, key, &measure));
    f.set("Use \x1eEnter\x1f\t now");
    try std.testing.expect(f.layout(30, key, &measure));
    try std.testing.expectEqualStrings("Use \x1eEnter\x1f\t now", f.text());
    var d = input.Desk{};
    d.typed.n = 1;
    d.typed.buf[0] = '!';
    try std.testing.expect(f.feed(&d, true));
    try std.testing.expect(f.layout(30, key, &measure));
    try std.testing.expect(f.feed(&.{ .undo = true }, true));
    try std.testing.expect(f.layout(30, key, &measure));
    try std.testing.expect(f.feed(&.{ .redo = true }, true));
    try std.testing.expect(f.layout(30, key, &measure));
    f.set("x" ** catalog.MAX_TEXT);
    try std.testing.expect(f.layout(60, key, &measure));
    const long_calls = measure.calls;
    for (0..60) |_| try std.testing.expect(!f.layout(60, key, &measure));
    try std.testing.expectEqual(long_calls, measure.calls);
}
