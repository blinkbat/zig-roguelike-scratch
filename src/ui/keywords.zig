const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const wording = @import("../core/wording.zig");
const resilience = @import("../play/resilience.zig");
const font = @import("../gfx/font.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const sprite = @import("../gfx/sprites.zig");
const menu = @import("menu.zig");

pub const Term = struct { title: [:0]const u8, body: []const u8 };
pub const STATUS_TERMS = blk: {
    var out: [std.enums.values(resilience.Tag).len]Term = undefined;
    for (std.enums.values(resilience.Tag), &out) |tag, *term| {
        var body: []const u8 = tag.description() ++ "\n";
        var members = tag.members().iterator();
        var first = true;
        while (members.next()) |kind| {
            body = body ++ (if (first) "" else ", ") ++ wording.named(kind);
            first = false;
        }
        term.* = .{ .title = wording.named(tag), .body = body ++ "." };
    }
    break :blk out;
};

const MAX: usize = 32;
const PAD = 14;
const GAP = 10;
const WIDTH = 360;
const MARGIN = 8;
const HIT_SLOP = 3;
const LINE = font.SMALL_LINE;
const Link = struct { term: Term, box: rl.Rectangle };

pub const State = struct {
    links: [MAX]Link = undefined,
    n: usize = 0,
    focus: ?usize = null,
    hover: ?usize = null,
    dismissed: ?usize = null,
    root: ?rl.Rectangle = null,
    popup: ?rl.Rectangle = null,
    keep_root: bool = false,
    screen: mathx.P = .{ .x = 0, .y = 0 },

    pub fn resized(self: *State, screen: mathx.P) void {
        if (!self.screen.eq(screen)) self.* = .{};
    }

    fn shut(self: *State) void {
        self.hover = null;
        self.popup = null;
    }

    pub fn beginFrame(self: *State, st: *const input.State, screen: mathx.P) void {
        self.resized(screen);
        self.screen = screen;
        self.keep_root = self.keepsRoot(st);
        self.n = 0;
        self.root = null;
    }

    fn keepsRoot(self: *const State, st: *const input.State) bool {
        if (self.root == null) return false;
        if (self.focus != null) return true;
        if (st.device.pad()) return false;
        const p = st.pointer orelse return false;
        return raster.holds(raster.grown(self.root.?, GAP), p) or self.overPopup(p);
    }

    fn overPopup(self: *const State, p: mathx.P) bool {
        return if (self.popup) |box| raster.holds(raster.grown(box, GAP), p) else false;
    }

    pub fn at(self: *const State, p: mathx.P) ?usize {
        var i = self.n;
        while (i > 0) {
            i -= 1;
            if (raster.holds(raster.grown(self.links[i].box, HIT_SLOP), p)) return i;
        }
        return null;
    }

    pub fn step(self: *State, st: *const input.State) bool {
        if (!st.focused) {
            self.focus = null;
            self.shut();
            return false;
        }
        if (self.n == 0) {
            self.focus = null;
            return false;
        }
        if (self.focus != null) {
            if (menu.backed(st) or st.hit(menu.INSPECT)) {
                self.dismissed = self.focus;
                self.focus = null;
                self.shut();
                return true;
            }
            if (st.pointing()) {
                self.focus = null;
                self.hover = self.at(st.pointer.?);
                return true;
            }
            if (st.walk) |d| {
                var boxes: [MAX]rl.Rectangle = undefined;
                for (self.links[0..self.n], boxes[0..self.n]) |link, *box| box.* = link.box;
                const from = @min(self.focus.?, self.n - 1);
                const delta = d.delta();
                self.focus = menu.nearest(boxes[from], boxes[0..self.n], d) orelse mathx.wrap(from, if (delta.x != 0) delta.x else delta.y, self.n);
            }
            return true;
        }
        if (st.hit(menu.INSPECT)) {
            self.dismissed = null;
            self.focus = 0;
            self.hover = null;
            return true;
        }
        if (self.popup != null and menu.backed(st)) {
            self.dismissed = self.hover;
            self.shut();
            return true;
        }
        if (!st.device.pad()) if (st.pointer) |p| {
            if (self.at(p) != null or self.overPopup(p) or self.keepsRoot(st)) {
                return st.click or st.right_click or st.scroll != 0;
            }
        };
        return false;
    }

    pub fn register(self: *State, term: Term, box: rl.Rectangle) void {
        if (self.n == MAX) return;
        self.links[self.n] = .{ .term = term, .box = box };
        self.n += 1;
    }

    pub fn text(self: *State, face: *const font.Face, line: [:0]const u8, x: i32, y: i32, px: i32, colour: rl.Color, terms: []const Term, on: menu.Surface) void {
        face.text(line, x, y, px, colour);
        var from: usize = 0;
        while (from < line.len) {
            var matched = false;
            for (terms) |term| {
                const end = from + term.title.len;
                if (term.title.len == 0 or end > line.len or !std.mem.eql(u8, line[from..end], term.title)) continue;
                if ((from > 0 and wordByte(line[from - 1])) or (end < line.len and wordByte(line[end]))) continue;
                var prefix_buf: [font.WRAP_COLS_MAX + 1]u8 = undefined;
                const prefix = std.fmt.bufPrintZ(&prefix_buf, "{s}", .{line[0..from]}) catch break;
                const left = x + face.width(prefix, px);
                const w = face.width(term.title, px);
                face.text(term.title, left, y, px, look.UI_FOCUS);
                rl.drawLine(left, y + px + 1, left + w, y + px + 1, look.UI_GOLD);
                self.register(term, on.rectOf(raster.rect(left, y, w, px + 3)));
                from = end;
                matched = true;
                break;
            }
            if (!matched) from += 1;
        }
    }

    pub fn draw(self: *State, face: *const font.Face, sprites: *const sprite.Sprites, screen: mathx.P, st: *const input.State) void {
        if (self.n == 0) {
            self.focus = null;
            self.shut();
            return;
        }
        if (self.focus) |i| self.focus = @min(i, self.n - 1);
        var selected = self.focus;
        if (selected == null and !st.device.pad()) {
            if (st.pointer) |p| {
                selected = self.at(p);
                if (selected == null and self.overPopup(p)) selected = self.hover;
            }
        }
        const i = selected orelse {
            self.dismissed = null;
            self.shut();
            return;
        };
        if (self.dismissed == i) {
            self.popup = null;
            return;
        }
        self.dismissed = null;
        if (i >= self.n) {
            self.shut();
            return;
        }
        self.hover = i;
        const link = self.links[i];
        rl.drawRectangleLinesEx(raster.grown(link.box, HIT_SLOP), 1, look.UI_FOCUS);
        var wrapped: font.Wrapped = undefined;
        var lines: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
        const width = @min(WIDTH, screen.x - 2 * MARGIN);
        const n = wrapBody(face, link.term.body, width - 2 * PAD, &wrapped, &lines);
        const height = 2 * PAD + font.BODY + GAP + @as(i32, @intCast(n)) * LINE;
        const box = popupBox(screen, link.box, width, height);
        self.popup = box;
        const x = raster.left(box);
        const y = raster.top(box);
        sprite.layeredBacking(sprites, x, y, width, height, .definition);
        face.text(link.term.title, x + PAD, y + PAD, font.BODY, look.UI_FOCUS);
        var top = y + PAD + font.BODY + GAP;
        for (lines[0..n]) |line| {
            face.text(line, x + PAD, top, font.SMALL, look.TEXT);
            top += LINE;
        }
    }
};

fn wordByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn wrapBody(face: anytype, body: []const u8, width: i32, buf: *font.Wrapped, lines: *[font.WRAP_LINES_MAX][:0]const u8) usize {
    var n: usize = 0;
    var rows = std.mem.splitScalar(u8, body, '\n');
    while (rows.next()) |row| {
        n = font.wrapAppend(face, row, font.SMALL, width, buf, lines, n);
        if (n == font.WRAP_LINES_MAX) break;
    }
    return n;
}

fn popupBox(screen: mathx.P, anchor: rl.Rectangle, width: i32, height: i32) rl.Rectangle {
    const right = raster.right(anchor) + GAP;
    const left = raster.left(anchor) - GAP - width;
    const x = if (right + width <= screen.x - MARGIN) right else if (left >= MARGIN) left else raster.left(anchor);
    const y = if (raster.top(anchor) - GAP - height >= MARGIN) raster.top(anchor) - GAP - height else raster.bottom(anchor) + GAP;
    return raster.rect(std.math.clamp(x, MARGIN, @max(MARGIN, screen.x - MARGIN - width)), std.math.clamp(y, MARGIN, @max(MARGIN, screen.y - MARGIN - height)), width, height);
}

test "keyword focus consumes navigation and dismissal while preserving its host" {
    var state = State{};
    state.register(STATUS_TERMS[0], raster.rect(100, 100, 60, 20));
    state.register(STATUS_TERMS[1], raster.rect(200, 100, 60, 20));
    try std.testing.expect(state.step(&.{ .pressed = .initOne(menu.INSPECT) }));
    try std.testing.expectEqual(@as(?usize, 0), state.focus);
    try std.testing.expect(state.step(&.{ .walk = .e, .pressed = .initOne(.a) }));
    try std.testing.expectEqual(@as(?usize, 1), state.focus);
    try std.testing.expect(state.step(&.{ .pressed = .initOne(.b) }));
    try std.testing.expectEqual(@as(?usize, null), state.focus);
    try std.testing.expect(!state.step(&.{ .walk = .e }));
}

test "keyword hit regions follow scaled panels and popups remain inside the screen" {
    const on = menu.Surface{ .scale = 1.25, .offset = .{ .x = 160, .y = 40 } };
    var state = State{};
    const box = on.rectOf(raster.rect(100, 100, 60, 20));
    state.register(STATUS_TERMS[0], box);
    try std.testing.expectEqual(@as(?usize, 0), state.at(raster.middleAt(box)));
    try std.testing.expectEqual(@as(?usize, null), state.at(.{ .x = 110, .y = 110 }));
    for (@import("../core/window.zig").SCREENS) |screen| {
        for ([_]mathx.P{ .{ .x = 0, .y = 0 }, .{ .x = screen.x - 20, .y = screen.y - 20 } }) |p| {
            const popup = popupBox(screen, raster.rect(p.x, p.y, 20, 20), WIDTH, 180);
            try std.testing.expect(popup.x >= MARGIN and popup.y >= MARGIN);
            try std.testing.expect(raster.right(popup) <= screen.x - MARGIN and raster.bottom(popup) <= screen.y - MARGIN);
        }
    }
}

test "keyword hover retains its parent and dismisses only its definition" {
    var state = State{
        .screen = .{ .x = 1280, .y = 720 },
        .root = raster.rect(100, 300, 380, 150),
        .popup = raster.rect(300, 150, 360, 140),
        .hover = 0,
    };
    state.register(STATUS_TERMS[0], raster.rect(120, 400, 60, 20));
    const keys = input.State{ .device = .keys, .pointer = .{ .x = 140, .y = 410 } };
    try std.testing.expect(state.keepsRoot(&keys));
    const inside = input.State{ .device = .keys, .pointer = .{ .x = 620, .y = 180 }, .click = true };
    try std.testing.expect(state.keepsRoot(&inside));
    try std.testing.expect(state.step(&inside));
    try std.testing.expect(!state.keepsRoot(&.{ .device = .keys, .pointer = .{ .x = 800, .y = 500 } }));
    try std.testing.expect(state.step(&.{ .device = .keys, .pressed = .initOne(.b) }));
    try std.testing.expect(state.popup == null and state.root != null);
    try std.testing.expectEqual(@as(?usize, 0), state.dismissed);
    state.focus = 0;
    state.beginFrame(&keys, .{ .x = 1920, .y = 1080 });
    try std.testing.expect(state.focus == null and state.n == 0 and state.root == null);
}
