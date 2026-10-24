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
const ROW = 52;
const LINE = 24;
const Focus = enum { search, passage };
const Leave = enum { close, quit };
const HISTORY = 16;
const Revision = struct { buf: [catalog.MAX_TEXT + 1]u8, n: usize, cursor: usize, anchor: usize };
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

    pub fn deinit(s: *State, alloc: std.mem.Allocator) void {
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

    fn matches(s: *const State, e: catalog.Entry) bool {
        const q = s.search.text();
        return q.len == 0 or std.ascii.indexOfIgnoreCase(e.text, q) != null or std.ascii.indexOfIgnoreCase(e.path, q) != null;
    }

    fn count(s: *const State) usize {
        const c = s.data orelse return 0;
        var n: usize = 0;
        for (c.entries()) |e| if (s.matches(e)) {
            n += 1;
        };
        return n;
    }

    fn pick(s: *State, i: usize) void {
        if (s.selected == i) return;
        if (s.dirty()) return s.say("Save or discard this passage before selecting another.", .{});
        s.selected = i;
        s.restore();
        s.note_n = 0;
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
    if (c.warning.len > 0) s.say("{s}", .{c.warning}) else s.say("Loaded {d} passages. Saved wording takes effect after rebuilding.", .{c.entries().len});
}

pub fn pose(ed: *editor.Editor) !void {
    open(ed);
    const s = &ed.words;
    const c = s.data orelse return error.TextCatalogMissing;
    s.search.set("fireball.zig");
    for (c.entries(), 0..) |entry, i| {
        if (!s.matches(entry) or !entry.editable or entry.text.len < 40) continue;
        s.pick(i);
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
        if (std.hash.Wyhash.hash(0, s.search.text()) != old) s.top = 0;
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
    const n = s.count();
    if (d.wheel != 0) {
        const by: i32 = if (d.wheel > 0) -3 else 3;
        if (raster.holds(s.passage_box, d.mouse)) {
            s.draft.scroll = mathx.nudge(s.draft.scroll, by, (s.draft.lines -| s.draft.rows) + 1);
            s.draft.reveal = false;
        } else s.top = mathx.nudge(s.top, by, (n -| s.rows) + 1);
    }
    if (d.nav != 0 and s.focus == .search and n > 0) {
        var at: usize = 0;
        var ordinal: usize = 0;
        for (s.data.?.entries(), 0..) |e, i| {
            if (!s.matches(e)) continue;
            if (s.selected == i) at = ordinal;
            ordinal += 1;
        }
        const next = mathx.wrap(at, d.nav, n);
        ordinal = 0;
        for (s.data.?.entries(), 0..) |e, i| {
            if (!s.matches(e)) continue;
            if (ordinal == next) {
                s.pick(i);
                break;
            }
            ordinal += 1;
        }
        s.top = mathx.reveal(s.top, next, s.rows);
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
    return face.width(s, font.SMALL);
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
        g.face.draw(buf[0 .. end - start :0], x, yy, font.SMALL, if (editable) look.TEXT else look.DIM);
        if (focused and caret_line == line) {
            const at = @min(f.cursor, end) - start;
            buf[at] = 0;
            rl.drawRectangle(x + displayWidth(&g.face, buf[0..at :0]), yy, 1, font.SMALL, look.UI_FOCUS);
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

pub fn draw(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.words;
    const height = @max(400, @min(760, g.screen.y - 2 * PAD));
    const f = editor.modalFrame(g, 1200, height, "Player-facing text", false);
    const x = f.x + PAD;
    const w = f.w - 2 * PAD;
    var y = f.y;
    var buf: [512]u8 = undefined;
    panel.drawFit(g, "Find wording or source file", font.SMALL, w, false, x, y, look.DIM);
    y += LINE;
    drawField(ed, g, &s.search, raster.rect(x, y, w - 208, 36), s.focus == .search, false, true);
    if (button(ed, g, x + w - 200, y + 5, 94, "Reload", false, !s.dirty())) reload(ed);
    if (button(ed, g, x + w - 100, y + 5, 100, "Close", false, true)) requestClose(ed, false);
    y += 48;
    const left = @divTrunc(w * 2, 5);
    const right_x = x + left + PAD;
    const right_w = w - left - PAD;
    const bottom = f.top - PAD + height - PAD;
    s.rows = @intCast(@max(1, @divTrunc(bottom - y - 2 * LINE, ROW)));
    var ordinal: usize = 0;
    var drawn: usize = 0;
    if (s.data) |c| for (c.entries(), 0..) |e, i| {
        if (!s.matches(e)) continue;
        defer ordinal += 1;
        if (ordinal < s.top or drawn >= s.rows) continue;
        const yy = y + @as(i32, @intCast(drawn)) * ROW;
        const r = raster.rect(x, yy, left, ROW - 4);
        const h = editor.hot(ed, r, true, true, null);
        editor.plate(r, s.selected == i, h.hot);
        var snippet: [catalog.MAX_TEXT + 1]u8 = undefined;
        const snippet_n = @min(e.text.len, catalog.MAX_TEXT);
        @memcpy(snippet[0..snippet_n], e.text[0..snippet_n]);
        for (snippet[0..snippet_n]) |*char| if (char.* < ' ') {
            char.* = ' ';
        };
        panel.drawFit(g, snippet[0..snippet_n], font.SMALL, left - 12, false, x + 6, yy + 3, look.TEXT);
        const provenance = std.fmt.bufPrintZ(&buf, "{s}:{d}  |  {s}", .{ e.path, e.line, @tagName(e.author) }) catch "";
        panel.drawFit(g, provenance, font.LABEL, left - 12, true, x + 6, yy + 25, look.DIM);
        if (h.hit and s.leave == null) s.pick(i);
        drawn += 1;
    };
    const count_label = std.fmt.bufPrintZ(&buf, "{d} matching passages", .{s.count()}) catch "";
    panel.drawFit(g, count_label, font.SMALL, left, false, x, bottom - LINE, look.DIM);
    if (s.selected) |i| if (s.data) |c| {
        const e = c.entries()[i];
        const source = std.fmt.bufPrintZ(&buf, "{s}:{d}", .{ e.path, e.line }) catch "";
        panel.drawFit(g, source, font.SMALL, right_w, true, right_x, y, look.UI_GOLD);
        var yy = y + LINE + 4;
        const hint = std.fmt.bufPrintZ(&buf, "Keep placeholders intact. {d}/{d} characters.", .{ s.draft.n, e.max_len }) catch "";
        panel.drawFit(g, if (e.editable) hint else e.reason, font.SMALL, right_w, false, right_x, yy, look.DIM);
        yy += LINE + 4;
        const field_h = @max(80, bottom - yy - 6 * LINE - 24);
        s.passage_box = raster.rect(right_x, yy, right_w, field_h);
        drawField(ed, g, &s.draft, s.passage_box, s.focus == .passage, true, e.editable);
        yy += field_h + 10;
        const tags = std.enums.values(catalog.Author);
        const tag_w = @divTrunc(right_w, @as(i32, @intCast(tags.len)));
        for (tags, 0..) |tag, at| {
            const label: [:0]const u8 = switch (tag) {
                .unknown => "Unknown",
                .you => "You",
                .ai => "AI",
                .mixed => "Mixed",
            };
            if (button(ed, g, right_x + @as(i32, @intCast(at)) * tag_w, yy, tag_w - 4, label, s.author == tag, e.editable and s.leave == null)) s.author = tag;
        }
        yy += 36;
        if (button(ed, g, right_x, yy, 130, "Save passage", false, e.editable and s.dirty())) save(ed);
        if (button(ed, g, right_x + 138, yy, 100, "Discard", false, s.dirty())) {
            s.restore();
            s.note_n = 0;
            if (s.leave != null) finishClose(ed);
        }
        if (s.leave != null) {
            if (button(ed, g, right_x + 246, yy, @max(90, right_w - 246), "Keep editing", false, true)) s.leave = null;
        }
        yy += 36;
        if (s.leave != null) panel.drawFit(g, "Unsaved passage: save or discard before leaving.", font.SMALL, right_w, false, right_x, yy, look.UI_FOCUS) else panel.drawFit(g, if (s.dirty()) "Unsaved changes" else "Saved wording is applied on the next build.", font.SMALL, right_w, false, right_x, yy, look.DIM);
    };
    if (s.selected == null) panel.drawFit(g, "Select a passage to rewrite it and set its author tag.", font.SMALL, right_w, false, right_x, y + LINE, look.DIM);
    panel.drawFit(g, s.note[0..s.note_n], font.SMALL, right_w, false, right_x, bottom - LINE, look.UI_GOLD);
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
