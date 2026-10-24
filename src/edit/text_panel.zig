const std = @import("std");
const rl = @import("raylib");
const input = @import("../core/input.zig");
const mathx = @import("../core/mathx.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const raster = @import("../gfx/raster.zig");
const game = @import("../game.zig");
const editor = @import("editor.zig");
const panel = @import("panel.zig");
const catalog = @import("text_catalog.zig");

const PAD = editor.PAD;
const TEXT = editor.TEXT;
const DETAIL = editor.DETAIL;
const ROW = TEXT + 2 * DETAIL + 20;
const LINE = TEXT + 8;
const NAV_ROW = DETAIL + 20;
const Focus = enum { search, passage };
const Leave = enum { close, quit };
const HISTORY = 16;
const Revision = struct { buf: [catalog.MAX_TEXT + 1]u8, n: usize, cursor: usize, anchor: usize };
const Group = struct { category: []const u8, owner: []const u8, first: usize, end: usize, matches: usize = 0 };
const FontKey = struct {
    ordered: bool,
    font: ?rl.Font,
    data_font: ?rl.Font,
    native: @FieldType(font.Face, "native"),

    fn of(face: *const font.Face) FontKey {
        return .{ .ordered = face.ordered, .font = face.font, .data_font = face.data_font, .native = face.native };
    }
};

pub const Field = struct {
    buf: [catalog.MAX_TEXT + 1]u8 = @splat(0),
    n: usize = 0,
    cursor: usize = 0,
    anchor: usize = 0,
    starts: [catalog.MAX_TEXT + 2]usize = @splat(0),
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

    pub fn text(f: *const Field) [:0]const u8 {
        return f.buf[0..f.n :0];
    }

    pub fn set(f: *Field, s: []const u8) void {
        f.n = @min(s.len, catalog.MAX_TEXT);
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

    fn revision(f: *const Field) Revision {
        return .{ .buf = f.buf, .n = f.n, .cursor = f.cursor, .anchor = f.anchor };
    }

    fn remember(f: *Field) void {
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

    fn restoreRevision(f: *Field, by: i32) void {
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

    fn erase(f: *Field) bool {
        const lo = @min(f.cursor, f.anchor);
        const hi = @max(f.cursor, f.anchor);
        if (lo == hi) return false;
        f.layout_valid = false;
        std.mem.copyForwards(u8, f.buf[lo..], f.buf[hi .. f.n + 1]);
        f.n -= hi - lo;
        f.cursor = lo;
        f.anchor = lo;
        return true;
    }

    pub fn insert(f: *Field, s: []const u8) bool {
        if (s.len == 0) return true;
        for (s) |c| if (!catalog.supported(c)) return false;
        const removed = @max(f.cursor, f.anchor) - @min(f.cursor, f.anchor);
        var count: usize = 0;
        for (s) |c| if (c != '\r') {
            count += 1;
        };
        if (f.n - removed + count > catalog.MAX_TEXT) return false;
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

    fn layout(f: *Field, width: i32, key: FontKey, face: anytype) bool {
        if (f.layout_valid and f.layout_width == width and std.meta.eql(f.layout_font, key)) return false;
        var lines: usize = 0;
        var pos: usize = 0;
        var buf: [catalog.MAX_TEXT + 1]u8 = undefined;
        while (true) {
            f.starts[lines] = pos;
            var end = pos;
            while (end < f.n and f.buf[end] != '\n') {
                const next = end + 1;
                @memcpy(buf[0 .. next - pos], f.buf[pos..next]);
                buf[next - pos] = 0;
                if (end > pos and displayWidth(face, buf[0 .. next - pos :0]) > width) break;
                end = next;
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

    pub fn feed(f: *Field, d: *const input.Desk, multiline: bool) bool {
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
            var end = @min(f.n, f.starts[next + 1]);
            if (end > f.starts[next] and f.buf[end - 1] == '\n') end -= 1;
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
            var copied: [catalog.MAX_TEXT + 1]u8 = undefined;
            const lo = @min(f.cursor, f.anchor);
            const hi = @max(f.cursor, f.anchor);
            if (hi > lo) {
                @memcpy(copied[0 .. hi - lo], f.buf[lo..hi]);
                copied[hi - lo] = 0;
                input.copyText(copied[0 .. hi - lo :0]);
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
            if (!multiline and (std.mem.indexOfScalar(u8, s, '\n') != null or std.mem.indexOfScalar(u8, s, '\r') != null)) return false;
            if (!f.insert(s)) return false;
        }
        if (!f.insert(d.text())) return false;
        if (multiline and d.enter and !f.insert("\n")) return false;
        return true;
    }
};

pub const State = struct {
    data: ?*catalog.Catalog = null,
    search: Field = .{},
    draft: Field = .{},
    selected: ?usize = null,
    top: usize = 0,
    rows: usize = 7,
    focus: Focus = .search,
    author: catalog.Author = .unknown,
    leave: ?Leave = null,
    note: [256:0]u8 = @splat(0),
    note_n: usize = 0,
    passage_box: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    nav_box: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    list_box: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    category: ?[]const u8 = null,
    owner: ?[]const u8 = null,
    nav_top: usize = 0,
    nav_rows: usize = 1,
    nav_count: usize = 0,
    order: std.ArrayListUnmanaged(usize) = .{},
    groups: std.ArrayListUnmanaged(Group) = .{},
    results: std.ArrayListUnmanaged(usize) = .{},
    view_dirty: bool = true,

    pub fn deinit(s: *State, alloc: std.mem.Allocator) void {
        s.order.deinit(alloc);
        s.groups.deinit(alloc);
        s.results.deinit(alloc);
        if (s.data) |c| {
            c.deinit();
            alloc.destroy(c);
        }
        s.data = null;
    }

    fn say(s: *State, comptime fmt: []const u8, args: anytype) void {
        const line = std.fmt.bufPrintZ(&s.note, fmt, args) catch "Text operation failed.";
        s.note_n = line.len;
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
            if (std.ascii.indexOfIgnoreCase(value, q) != null) return true;
        }
        return false;
    }

    fn matches(s: *const State, e: catalog.Entry) bool {
        if (s.category) |category| if (!std.mem.eql(u8, category, e.category)) return false;
        if (s.owner) |owner| if (!std.mem.eql(u8, owner, e.owner)) return false;
        return s.queryMatches(e);
    }

    fn reindex(s: *State, alloc: std.mem.Allocator) !void {
        s.order.clearRetainingCapacity();
        s.groups.clearRetainingCapacity();
        s.results.clearRetainingCapacity();
        s.category = null;
        s.owner = null;
        s.nav_top = 0;
        const c = s.data orelse return;
        const entries = c.entries();
        try s.order.ensureTotalCapacity(alloc, entries.len);
        try s.groups.ensureTotalCapacity(alloc, entries.len);
        try s.results.ensureTotalCapacity(alloc, entries.len);
        for (entries, 0..) |_, i| s.order.appendAssumeCapacity(i);
        std.mem.sort(usize, s.order.items, entries, struct {
            fn less(es: []const catalog.Entry, x: usize, y: usize) bool {
                const a = es[x];
                const b = es[y];
                inline for (.{ "category", "owner", "role", "path" }) |field| {
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
                if (std.mem.eql(u8, previous.category, e.category) and std.mem.eql(u8, previous.owner, e.owner)) {
                    previous.end = at + 1;
                    continue;
                }
            }
            s.groups.appendAssumeCapacity(.{ .category = e.category, .owner = e.owner, .first = at, .end = at + 1 });
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
                if (s.matches(e)) s.results.appendAssumeCapacity(index);
            }
        }
        s.top = @min(s.top, s.results.items.len -| s.rows);
        s.view_dirty = false;
    }

    fn scope(s: *State, category: ?[]const u8, owner: ?[]const u8) void {
        if (s.dirty()) return s.say("Save or discard this passage before changing its group.", .{});
        const same_category = if (s.category) |previous| if (category) |next| std.mem.eql(u8, previous, next) else false else category == null;
        s.category = category;
        s.owner = owner;
        s.top = 0;
        if (!same_category) s.nav_top = 0;
        s.selected = null;
        s.focus = .search;
        s.view_dirty = true;
        s.note_n = 0;
    }

    fn pick(s: *State, i: usize) bool {
        if (s.selected == i) return true;
        if (s.dirty()) {
            s.say("Save or discard this passage before selecting another.", .{});
            return false;
        }
        s.selected = i;
        s.restore();
        s.note_n = 0;
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
    if (s.dirty()) return s.say("Save or discard this passage before reloading.", .{});
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
    if (c.warning.len > 0) s.say("{s}", .{c.warning}) else s.say("Loaded {d} passages. Saved wording takes effect after rebuilding.", .{c.entries().len});
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
        _ = s.pick(i);
        s.refresh();
        var owner_at: usize = 0;
        for (s.groups.items) |group| {
            if (!std.mem.eql(u8, group.category, entry.category)) continue;
            if (std.mem.eql(u8, group.owner, entry.owner)) break;
            owner_at += 1;
        }
        s.nav_top = owner_at -| 2;
        s.focus = .passage;
        return;
    }
    return error.TextPassageMissing;
}

pub fn requestClose(ed: *editor.Editor, quit: bool) void {
    const s = &ed.words;
    s.leave = if (quit) .quit else .close;
    if (s.dirty()) return;
    finishClose(ed);
}

fn finishClose(ed: *editor.Editor) void {
    const leave = ed.words.leave orelse return;
    ed.words.leave = null;
    ed.modal = .none;
    ed.fresh = true;
    if (leave == .quit) ed.request(.quit);
}

fn save(ed: *editor.Editor) void {
    const s = &ed.words;
    const c = s.data orelse return;
    const i = s.selected orelse return;
    const requested_author = s.author;
    const result = c.save(i, s.draft.text(), requested_author) catch |err| {
        s.say("Could not save: {s}. Your draft is still here.", .{@errorName(err)});
        return;
    };
    s.restore();
    s.view_dirty = true;
    if (result == .tags_not_saved) s.author = requested_author;
    if (result == .saved) s.say("Saved. Rebuild to apply wording changes.", .{}) else s.say("Source saved; author tags could not be saved.", .{});
    if (result == .saved and s.leave != null) finishClose(ed);
}

pub fn keys(ed: *editor.Editor) void {
    const s = &ed.words;
    const d = &ed.desk;
    if (d.back or d.erase_hit) {
        requestClose(ed, false);
        return;
    }
    if (s.leave != null) return;
    if (d.save) {
        save(ed);
        return;
    }
    if (s.focus == .search) {
        const old = std.hash.Wyhash.hash(0, s.search.text());
        if (!s.search.feed(d, false)) s.say("Search accepts plain ASCII text on one line.", .{});
        if (std.hash.Wyhash.hash(0, s.search.text()) != old) {
            s.top = 0;
            s.nav_top = 0;
            s.view_dirty = true;
        }
    } else if (s.selected) |i| {
        if (s.data.?.entries()[i].editable) {
            const was_dirty = s.dirty();
            const old = std.hash.Wyhash.hash(0, s.draft.text());
            if (!s.draft.feed(d, true)) s.say("Text must be ASCII and at most {d} characters.", .{catalog.MAX_TEXT});
            if (!was_dirty and std.hash.Wyhash.hash(0, s.draft.text()) != old) s.author = .you;
        } else {
            var nav = input.Desk{ .text_all = d.text_all, .text_left = d.text_left, .text_right = d.text_right, .text_home = d.text_home, .text_end = d.text_end, .shift = d.shift, .nav = d.nav, .copy = d.copy };
            _ = s.draft.feed(&nav, true);
        }
    }
    if (d.wheel == 0 and (d.nav == 0 or s.focus != .search)) return;
    s.refresh();
    const n = s.results.items.len;
    if (d.wheel != 0) {
        const by: i32 = if (d.wheel > 0) -3 else 3;
        if (raster.holds(s.passage_box, d.mouse)) {
            s.draft.scroll = mathx.nudge(s.draft.scroll, by, (s.draft.lines -| s.draft.rows) + 1);
            s.draft.reveal = false;
        } else if (raster.holds(s.nav_box, d.mouse)) {
            s.nav_top = mathx.nudge(s.nav_top, by, (s.nav_count -| s.nav_rows) + 1);
        } else if (raster.holds(s.list_box, d.mouse)) s.top = mathx.nudge(s.top, by, (n -| s.rows) + 1);
    }
    if (d.nav != 0 and s.focus == .search and n > 0) {
        var at: usize = 0;
        var found = false;
        for (s.results.items, 0..) |i, ordinal| if (s.selected == i) {
            at = ordinal;
            found = true;
            break;
        };
        const next = if (found) mathx.wrap(at, d.nav, n) else if (d.nav < 0) n - 1 else 0;
        if (s.pick(s.results.items[next])) s.top = mathx.reveal(s.top, next, s.rows);
    }
}

fn button(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, label: [:0]const u8, on: bool, live: bool) bool {
    return editor.buttonOn(ed, g, raster.rect(x, y, w, editor.ROW_H), label, on, live, true, null);
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

fn drawField(ed: *editor.Editor, g: *game.Game, f: *Field, r: rl.Rectangle, focused: bool, multiline: bool, editable: bool) void {
    rl.drawRectangleRec(r, look.EDIT_PANEL);
    rl.drawRectangleLinesEx(r, 1, if (focused) look.UI_FOCUS else look.EDGE);
    const hit = editor.hot(ed, r, true, true, null).hit;
    const x = @as(i32, @intFromFloat(r.x)) + editor.GAP;
    const y = @as(i32, @intFromFloat(r.y)) + editor.GAP;
    const width = @as(i32, @intFromFloat(r.width)) - 2 * editor.GAP;
    const rows: usize = @intCast(@max(1, @divTrunc(@as(i32, @intFromFloat(r.height)) - 2 * editor.GAP, LINE)));
    _ = f.layout(width, FontKey.of(&g.face), &g.face);
    const breaks = f.starts[0 .. f.lines + 1];
    const lines = f.lines;
    var buf: [catalog.MAX_TEXT + 1]u8 = undefined;
    var caret_line: usize = 0;
    for (breaks[0..lines], 0..) |pos, line| if (f.cursor >= pos) {
        caret_line = line;
    };
    f.rows = rows;
    if (f.reveal and focused) f.scroll = mathx.reveal(f.scroll, caret_line, rows);
    f.reveal = false;
    f.scroll = @min(f.scroll, lines -| rows);
    const first = f.scroll;
    rl.beginScissorMode(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height));
    defer rl.endScissorMode();
    for (first..@min(lines, first + rows)) |line| {
        const start = breaks[line];
        var end = breaks[line + 1];
        if (end > start and f.buf[end - 1] == '\n') end -= 1;
        const yy = y + @as(i32, @intCast(line - first)) * LINE;
        const lo = std.math.clamp(@min(f.cursor, f.anchor), start, end);
        const hi = std.math.clamp(@max(f.cursor, f.anchor), start, end);
        @memcpy(buf[0 .. end - start], f.buf[start..end]);
        buf[end - start] = 0;
        if (focused and hi > lo) {
            const held = buf[lo - start];
            buf[lo - start] = 0;
            const left = displayWidth(&g.face, buf[0 .. lo - start :0]);
            buf[lo - start] = held;
            const held_hi = buf[hi - start];
            buf[hi - start] = 0;
            const right = displayWidth(&g.face, buf[0 .. hi - start :0]);
            buf[hi - start] = held_hi;
            rl.drawRectangle(x + left, yy, right - left, LINE, look.EDIT_ROW_ON);
        }
        displayBytes(buf[0 .. end - start]);
        g.face.draw(buf[0 .. end - start :0], x, yy, TEXT, if (editable) look.TEXT else look.DIM);
        if (focused and caret_line == line) {
            const at = @min(f.cursor, end) - start;
            buf[at] = 0;
            rl.drawRectangle(x + displayWidth(&g.face, buf[0..at :0]), yy, 2, TEXT, look.UI_FOCUS);
        }
        if (hit and ed.desk.mouse.y >= yy and ed.desk.mouse.y < yy + LINE) {
            var at = start;
            while (at < end) : (at += 1) {
                @memcpy(buf[0 .. at + 1 - start], f.buf[start .. at + 1]);
                buf[at + 1 - start] = 0;
                if (x + displayWidth(&g.face, buf[0 .. at + 1 - start :0]) > ed.desk.mouse.x) break;
            }
            f.cursor = at;
            if (!ed.desk.shift) f.anchor = at;
            f.reveal = true;
        }
    }
    if (hit) ed.words.focus = if (multiline) .passage else .search;
}

fn scrollMark(r: rl.Rectangle, top: usize, rows: usize, count: usize) void {
    editor.scrollbar(.{ .x = r.x + r.width - 3, .y = r.y, .width = 3, .height = r.height }, top, rows, count);
}

fn navItem(ed: *editor.Editor, g: *game.Game, ordinal: usize, label: []const u8, count: usize, on: bool) bool {
    const s = &ed.words;
    if (ordinal < s.nav_top or ordinal >= s.nav_top + s.nav_rows) return false;
    const x: i32 = @intFromFloat(s.nav_box.x);
    const y = @as(i32, @intFromFloat(s.nav_box.y)) + @as(i32, @intCast(ordinal - s.nav_top)) * NAV_ROW;
    const w: i32 = @intFromFloat(s.nav_box.width);
    const r = raster.rect(x, y, w - editor.GAP, NAV_ROW - 4);
    const h = editor.hot(ed, r, s.leave == null, true, null);
    editor.plate(r, on, h.hot);
    var buf: [32]u8 = undefined;
    const number = std.fmt.bufPrintZ(&buf, "{d}", .{count}) catch "";
    const number_w = g.face.width(number, DETAIL);
    panel.drawFit(g, label, DETAIL, w - number_w - 3 * editor.GAP - 6, false, x + editor.GAP, y + 8, if (on) look.UI_GOLD else look.TEXT);
    g.face.draw(number, x + w - number_w - 2 * editor.GAP, y + 8, DETAIL, look.DIM);
    return h.hit;
}

fn drawNavigation(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, bottom: i32) void {
    const s = &ed.words;
    panel.drawFit(g, if (s.category) |category| category else "Features", TEXT, w, false, x, y, look.UI_GOLD);
    var yy = y + LINE;
    if (button(ed, g, x, yy, w - editor.GAP, if (s.category != null) "< All features" else "All text", s.category == null, s.leave == null)) s.scope(null, null);
    yy += editor.ROW_STEP;
    if (s.category != null) {
        if (button(ed, g, x, yy, w - editor.GAP, "All in this feature", s.owner == null, s.leave == null)) s.scope(s.category, null);
        yy += editor.ROW_STEP;
    }
    s.nav_box = raster.rect(x, yy, w, @max(0, bottom - yy));
    s.nav_rows = @intCast(@max(1, @divTrunc(bottom - yy, NAV_ROW)));
    var count: usize = 0;
    var previous: []const u8 = "";
    for (s.groups.items) |group| {
        if (group.matches == 0) continue;
        if (s.category) |category| {
            if (std.mem.eql(u8, category, group.category)) count += 1;
        } else if (!std.mem.eql(u8, previous, group.category)) {
            count += 1;
            previous = group.category;
        }
    }
    s.nav_count = count;
    s.nav_top = @min(s.nav_top, count -| s.nav_rows);
    var ordinal: usize = 0;
    if (s.category) |category| {
        for (s.groups.items) |group| {
            if (group.matches == 0 or !std.mem.eql(u8, category, group.category)) continue;
            const on = if (s.owner) |owner| std.mem.eql(u8, owner, group.owner) else false;
            if (navItem(ed, g, ordinal, group.owner, group.matches, on)) s.scope(category, group.owner);
            ordinal += 1;
        }
    } else {
        var at: usize = 0;
        while (at < s.groups.items.len) {
            const category = s.groups.items[at].category;
            var matches: usize = 0;
            while (at < s.groups.items.len and std.mem.eql(u8, category, s.groups.items[at].category)) : (at += 1) matches += s.groups.items[at].matches;
            if (matches == 0) continue;
            if (navItem(ed, g, ordinal, category, matches, false)) s.scope(category, null);
            ordinal += 1;
        }
    }
    scrollMark(s.nav_box, s.nav_top, s.nav_rows, s.nav_count);
}

pub fn draw(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.words;
    s.refresh();
    const height = @min(1080, g.screen.y - 2 * PAD);
    const f = editor.modalFrame(g, 1800, height, "Text editor", false);
    const x = f.x + PAD;
    const w = f.w - 2 * PAD;
    var y = f.y;
    var buf: [1024]u8 = undefined;
    panel.drawFit(g, "Search wording, feature, owner or source", DETAIL, w, false, x, y, if (s.focus == .search) look.UI_GOLD else look.DIM);
    y += DETAIL + 6;
    drawField(ed, g, &s.search, raster.rect(x, y, w - 294, LINE + 12), s.focus == .search, false, true);
    if (button(ed, g, x + w - 282, y + 4, 86, "Clear", false, s.search.n > 0)) {
        s.search.set("");
        s.view_dirty = true;
        s.top = 0;
        s.nav_top = 0;
        s.focus = .search;
    }
    if (button(ed, g, x + w - 188, y + 4, 90, "Reload", false, !s.dirty())) reload(ed);
    if (button(ed, g, x + w - 90, y + 4, 90, "Close", false, true)) requestClose(ed, false);
    y += LINE + 28;
    const nav_w = std.math.clamp(@divTrunc(w, 5), 180, 250);
    const list_x = x + nav_w + PAD;
    const list_w = std.math.clamp(@divTrunc(w, 4), 240, 360);
    const right_x = list_x + list_w + PAD;
    const right_w = x + w - right_x;
    const bottom = f.top - PAD + height - PAD - DETAIL - 8;
    rl.drawRectangle(list_x - @divTrunc(PAD, 2), y, 1, bottom - y, look.EDGE);
    rl.drawRectangle(right_x - @divTrunc(PAD, 2), y, 1, bottom - y, look.EDGE);
    drawNavigation(ed, g, x, y, nav_w, bottom);
    panel.drawFit(g, "Passages", TEXT, list_w, false, list_x, y, look.UI_GOLD);
    const list_y = y + LINE;
    s.rows = @intCast(@max(1, @divTrunc(bottom - list_y - DETAIL - 8, ROW)));
    s.top = @min(s.top, s.results.items.len -| s.rows);
    s.list_box = raster.rect(list_x, list_y, list_w, @as(i32, @intCast(s.rows)) * ROW);
    if (s.data) |c| {
        const end = @min(s.results.items.len, s.top + s.rows);
        for (s.results.items[s.top..end], 0..) |i, at| {
            const e = c.entries()[i];
            const yy = list_y + @as(i32, @intCast(at)) * ROW;
            const r = raster.rect(list_x, yy, list_w - editor.GAP, ROW - 6);
            const h = editor.hot(ed, r, s.leave == null, true, null);
            editor.plate(r, s.selected == i, h.hot);
            panel.drawFit(g, e.role, TEXT, list_w - 20, false, list_x + 6, yy + 4, if (s.selected == i) look.UI_GOLD else look.TEXT);
            panel.drawFit(g, e.owner, DETAIL, list_w - 20, false, list_x + 6, yy + TEXT + 8, look.DIM);
            var snippet: [catalog.MAX_TEXT + 1]u8 = undefined;
            const n = @min(e.text.len, catalog.MAX_TEXT);
            @memcpy(snippet[0..n], e.text[0..n]);
            for (snippet[0..n]) |*char| if (char.* < ' ') { char.* = ' '; };
            panel.drawFit(g, snippet[0..n], DETAIL, list_w - 20, false, list_x + 6, yy + TEXT + DETAIL + 12, look.TEXT);
            if (h.hit and s.pick(i)) s.focus = .passage;
        }
    }
    scrollMark(s.list_box, s.top, s.rows, s.results.items.len);
    const count_label = std.fmt.bufPrintZ(&buf, "{d} passages", .{s.results.items.len}) catch "";
    panel.drawFit(g, count_label, DETAIL, list_w, false, list_x, bottom - DETAIL, look.DIM);
    if (s.results.items.len == 0) {
        panel.drawFit(g, "No matching passages.", DETAIL, list_w, false, list_x + 6, list_y + 8, look.TEXT);
        panel.drawFit(g, "Clear search or choose another group.", DETAIL, list_w, false, list_x + 6, list_y + 36, look.DIM);
    }
    s.passage_box = raster.rect(0, 0, 0, 0);
    if (s.selected) |i| if (s.data) |c| {
        const e = c.entries()[i];
        panel.drawFit(g, e.owner, TEXT, right_w, false, right_x, y, look.TEXT);
        const breadcrumb = std.fmt.bufPrintZ(&buf, "{s}  >  {s}", .{ e.category, e.role }) catch "";
        panel.drawFit(g, breadcrumb, DETAIL, right_w, false, right_x, y + LINE, look.UI_GOLD);
        const source = std.fmt.bufPrintZ(&buf, "{s}:{d}", .{ e.path, e.line }) catch "";
        panel.drawFit(g, source, DETAIL, right_w, true, right_x, y + LINE + DETAIL + 6, look.DIM);
        panel.drawFit(g, e.context, DETAIL, right_w, true, right_x, y + LINE + 2 * (DETAIL + 6), look.DIM);
        var yy = y + LINE + 3 * (DETAIL + 6) + 4;
        const hint = std.fmt.bufPrintZ(&buf, "{s}  |  {d}/{d} characters", .{ if (e.editable) "Wording" else "Reference only", s.draft.n, e.max_len }) catch "";
        panel.drawFit(g, hint, DETAIL, right_w, false, right_x, yy, if (s.focus == .passage) look.UI_GOLD else look.DIM);
        yy += DETAIL + 8;
        const field_h = @max(LINE + 12, bottom - yy - (DETAIL + 8 + 2 * editor.ROW_STEP + DETAIL + 8));
        s.passage_box = raster.rect(right_x, yy, right_w, field_h);
        drawField(ed, g, &s.draft, s.passage_box, s.focus == .passage, true, e.editable);
        yy += field_h + 8;
        panel.drawFit(g, "Written by", DETAIL, right_w, false, right_x, yy, look.DIM);
        yy += DETAIL + 6;
        const tags = std.enums.values(catalog.Author);
        const tag_w = @divTrunc(right_w, @as(i32, @intCast(tags.len)));
        for (tags, 0..) |tag, at| {
            const label: [:0]const u8 = switch (tag) { .unknown => "Unknown", .you => "You", .ai => "AI", .mixed => "Mixed" };
            if (button(ed, g, right_x + @as(i32, @intCast(at)) * tag_w, yy, tag_w - 4, label, s.author == tag, e.editable and s.leave == null)) s.author = tag;
        }
        yy += editor.ROW_STEP;
        const save_w = @min(160, @divTrunc(right_w, 3));
        if (button(ed, g, right_x, yy, save_w, "Save passage", false, e.editable and s.dirty())) save(ed);
        if (button(ed, g, right_x + save_w + 6, yy, 100, "Discard", false, s.dirty())) {
            s.restore();
            s.note_n = 0;
            if (s.leave != null) finishClose(ed);
        }
        if (s.leave != null and button(ed, g, right_x + save_w + 112, yy, right_w - save_w - 112, "Keep editing", false, true)) s.leave = null;
        yy += editor.ROW_STEP;
        const status = if (s.leave != null) "Save or discard before leaving." else if (!e.editable) e.reason else if (s.dirty()) "Unsaved changes" else if (e.alias != null) "Display name; code identity stays fixed." else "Keep format placeholders and control markers intact.";
        panel.drawFit(g, status, DETAIL, right_w, false, right_x, yy, if (s.dirty()) look.UI_FOCUS else look.DIM);
    };
    if (s.selected == null) {
        panel.drawFit(g, "Choose a passage", TEXT, right_w, false, right_x, y, look.TEXT);
        _ = g.face.paragraph("Browse a feature, then its object or screen. Select a named field to see its wording and exact source.", right_x, y + LINE + 8, right_w, DETAIL, look.DIM);
    }
    const note = if (s.note_n > 0) s.note[0..s.note_n] else "Saved wording takes effect after rebuilding.";
    panel.drawFit(g, note, DETAIL, w, false, x, bottom + 8, look.UI_GOLD);
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
    std.debug.print("3 text edits checked: selected replacement, rejected non-ASCII, insertion with normalized newlines\n", .{});
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
        .{ .path = "src/play/fireball.zig", .line = 3, .text = "Fire follows.", .category = "Skills", .owner = "Fireball", .role = "Flavor", .context = "play.fireball.FLAVOR", .file = 0, .start = 0, .end = 0, .ordinal = 1 },
        .{ .path = "src/play/ward.zig", .line = 2, .text = "A magical shield.", .category = "Skills", .owner = "Mana shield", .role = "Description", .context = "play.ward.DESCRIPTION", .file = 0, .start = 0, .end = 0, .ordinal = 0 },
    }) |entry| try c.list.append(c.arena.allocator(), entry);
    const s = &ed.words;
    try s.reindex(alloc);
    try std.testing.expectEqual(@as(usize, 2), s.groups.items.len);
    try std.testing.expectEqual(@as(usize, 3), s.results.items.len);
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
    std.debug.print("text browser: semantic grouping, exact-context search, owner filtering and dirty navigation/scroll protection checked\n", .{});
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
    std.debug.print("3 selection cases retain text: select all, idle frame, shifted arrow\n", .{});
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
    std.debug.print("text navigation: 3 wrapped-line moves, shifted selection and protected-marker paste\n", .{});
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
    std.debug.print("text history: undo, redo and abandoned redo replacement checked\n", .{});
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
    std.debug.print("text wrapping: 120 idle frames avoid measurements; edits, resize, font changes, undo/redo and unchanged glyph bytes checked\n", .{});
}
