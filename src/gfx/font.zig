const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");

const TTF = "Balthazar-Regular.ttf";
const DATA_TTF = "SourceSans3-Regular.ttf";
const ATLAS_PX: i32 = 96;
/// Drawn from its own point-filtered atlas, not the mipmapped one.
const NATIVE_SIZES = [_]i32{ TINY, LABEL, SMALL, BODY, HEAD };
const SHADOW_A: u16 = 200;
/// Text size per pixel the shadow sits down and right.
const SHADOW_STEP: i32 = 14;
pub const BODY: i32 = 20;
pub const SMALL: i32 = 16;
pub const HEAD: i32 = 24;
pub const TINY: i32 = 12;
pub const LABEL: i32 = 15;

const ASCII_LO: i32 = ' ';
const ASCII_N: usize = '~' + 1 - ASCII_LO;
const SYMBOLS_MAX: usize = 16;
pub const ELLIPSIS = "...";

/// Until `load` succeeds, raylib's built-in font stands in.
pub const Face = struct {
    font: ?rl.Font = null,
    data_font: ?rl.Font = null,
    native: [NATIVE_SIZES.len]?rl.Font = @splat(null),
    /// `load`'s symbols, whose glyphs follow the ASCII in the atlas; none when the atlas came out in another order.
    symbols: [SYMBOLS_MAX]i32 = undefined,
    symbol_n: usize = 0,
    ordered: bool = false,

    /// Printable ASCII and `symbols`. Needs a live GL context.
    pub fn load(comptime symbols: []const i32) Face {
        comptime std.debug.assert(symbols.len <= SYMBOLS_MAX);
        const all = comptime blk: {
            var cps: [ASCII_N + symbols.len]i32 = undefined;
            for (0..ASCII_N) |i| cps[i] = ASCII_LO + @as(i32, @intCast(i));
            for (symbols, ASCII_N..) |s, i| cps[i] = s;
            break :blk cps;
        };
        var cps = all;
        var f = rl.loadFontFromMemory(".ttf", @embedFile(TTF), ATLAS_PX, &cps) catch return .{};
        rl.genTextureMipmaps(&f.texture);
        rl.setTextureFilter(f.texture, .trilinear);
        var face = Face{ .font = f };
        if (!orderedGlyphs(f, &all)) return face;
        @memcpy(face.symbols[0..symbols.len], symbols);
        face.symbol_n = symbols.len;
        face.ordered = true;
        var ascii_cps = all[0..ASCII_N].*;
        if (rl.loadFontFromMemory(".ttf", @embedFile(DATA_TTF), ATLAS_PX, &ascii_cps)) |loaded| {
            var data = loaded;
            if (orderedGlyphs(data, &ascii_cps)) {
                rl.genTextureMipmaps(&data.texture);
                rl.setTextureFilter(data.texture, .trilinear);
                face.data_font = data;
            } else rl.unloadFont(data);
        } else |_| {}
        for (NATIVE_SIZES, &face.native) |size, *held| {
            const small = rl.loadFontFromMemory(".ttf", if (size <= SMALL) @embedFile(DATA_TTF) else @embedFile(TTF), size, &ascii_cps) catch continue;
            if (!orderedGlyphs(small, &ascii_cps)) {
                rl.unloadFont(small);
                continue;
            }
            rl.setTextureFilter(small.texture, .point);
            held.* = small;
        }
        return face;
    }

    /// The font to walk `s` glyph by glyph at `size`; null where raylib's own text calls draw it.
    fn walkable(self: *const Face, s: []const u8, size: i32) ?rl.Font {
        if (!self.ordered or !printable(s)) return null;
        const fallback = if (size <= SMALL) self.data_font orelse self.font else self.font;
        for (NATIVE_SIZES, &self.native) |px, *held| {
            if (px == size) return held.* orelse fallback;
        }
        return fallback;
    }

    fn indexOf(self: *const Face, cp: i32) ?usize {
        if (!self.ordered) return null;
        if (cp >= ASCII_LO and cp < ASCII_LO + ASCII_N) return @intCast(cp - ASCII_LO);
        for (self.symbols[0..self.symbol_n], ASCII_N..) |s, i| {
            if (s == cp) return i;
        }
        return null;
    }

    pub fn mipmapped(self: Face) Face {
        var out = self;
        out.native = @splat(null);
        return out;
    }

    pub fn unload(self: *Face) void {
        for (&self.native) |*held| {
            if (held.*) |f| rl.unloadFont(f);
            held.* = null;
        }
        if (self.font) |f| rl.unloadFont(f);
        if (self.data_font) |f| rl.unloadFont(f);
        self.font = null;
        self.data_font = null;
    }

    /// raylib's MeasureTextEx with zero spacing.
    pub fn width(self: *const Face, s: [:0]const u8, size: i32) i32 {
        const f = self.walkable(s, size) orelse {
            const whole = self.font orelse return rl.measureText(s, size);
            return @intFromFloat(rl.measureTextEx(whole, s, @floatFromInt(size), 0).x);
        };
        var w: f32 = 0;
        for (s) |c| w += measured(f, ascii(c));
        return @intFromFloat(w * scaleOf(f, size));
    }

    /// raylib's DrawTextEx with zero spacing.
    pub fn draw(self: *const Face, s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
        const at = rl.Vector2{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
        const f = self.walkable(s, size) orelse {
            const whole = self.font orelse return rl.drawText(s, x, y, size, col);
            return rl.drawTextEx(whole, s, at, @floatFromInt(size), 0, col);
        };
        const scale = scaleOf(f, size);
        var off: f32 = 0;
        for (s) |c| {
            const i = ascii(c);
            if (c != ' ') put(f, i, at.x + off, at.y, scale, col);
            off += advance(f, i, scale);
        }
    }

    /// `s` whole, or as much of it as fits in `max` px beside "..." (its end kept when `keep_end`), in `buf`, which must not hold `s`.
    pub fn fit(self: *const Face, buf: []u8, s: []const u8, size: i32, max: i32, keep_end: bool) [:0]const u8 {
        const whole = std.fmt.bufPrintZ(buf, "{s}", .{s}) catch "";
        if (whole.len == s.len and self.width(whole, size) <= max) return whole;
        var n = @min(s.len, buf.len -| (ELLIPSIS.len + 1));
        while (true) : (n -= 1) {
            const t = elided(buf, if (keep_end) s[s.len - n ..] else s[0..n], keep_end) catch return whole;
            if (n == 0 or self.width(t, size) <= max) return t;
        }
    }

    /// `s` wrapped to `w`, a line every `size + LEADING` from `y`; returns the y below it.
    pub fn paragraph(self: *const Face, s: []const u8, x: i32, y: i32, w: i32, size: i32, col: rl.Color) i32 {
        return self.paragraphWith(draw, s, x, y, w, size, col);
    }

    /// `paragraph`, each line drawn by `line` at `x`.
    pub fn paragraphWith(self: *const Face, comptime line: fn (*const Face, [:0]const u8, i32, i32, i32, rl.Color) void, s: []const u8, x: i32, y: i32, w: i32, size: i32, col: rl.Color) i32 {
        const step = size + LEADING;
        var buf: Wrapped = undefined;
        var lines: [WRAP_LINES_MAX][:0]const u8 = undefined;
        const n = wrap(self, s, size, w, &buf, &lines);
        for (lines[0..n], 0..) |l, i| line(self, l, x, y + @as(i32, @intCast(i)) * step, size, col);
        return y + @as(i32, @intCast(n)) * step;
    }

    /// `draw`, its left on `x` and its middle on `cy`.
    pub fn drawMiddle(self: *const Face, s: [:0]const u8, x: i32, cy: i32, size: i32, col: rl.Color) void {
        self.draw(s, x, topFor(cy, size), size, col);
    }

    fn leftFor(self: *const Face, s: [:0]const u8, cx: i32, size: i32) i32 {
        return cx - @divTrunc(self.width(s, size), 2);
    }

    /// `draw`, its middle on `cx`.
    pub fn drawMid(self: *const Face, s: [:0]const u8, cx: i32, y: i32, size: i32, col: rl.Color) void {
        self.draw(s, self.leftFor(s, cx, size), y, size, col);
    }

    /// `text`, its middle on `cx`.
    pub fn textMid(self: *const Face, s: [:0]const u8, cx: i32, y: i32, size: i32, col: rl.Color) void {
        self.text(s, self.leftFor(s, cx, size), y, size, col);
    }

    /// One character, its middle on `cx`, `cy`.
    pub fn glyph(self: *const Face, ch: u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
        const s = [_:0]u8{ch};
        self.centred(&s, cx, cy, size, col);
    }

    /// `draw`, its middle on `cx`, `cy`.
    pub fn centred(self: *const Face, s: [:0]const u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
        self.drawMid(s, cx, topFor(cy, size), size, col);
    }

    /// `text`, its middle on `cx`, `cy`.
    pub fn textCentred(self: *const Face, s: [:0]const u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
        self.textMid(s, cx, topFor(cy, size), size, col);
    }

    fn topFor(cy: i32, size: i32) i32 {
        return cy - @divTrunc(size, 2);
    }

    /// One symbol, UTF-8, its middle on `cx`, `cy`; `alt` where the font has no atlas.
    pub fn symbol(self: *const Face, sym: [:0]const u8, alt: u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
        const f = self.font orelse return self.glyph(alt, cx, cy, size, col);
        const cp = std.unicode.utf8Decode(sym) catch null;
        const i = self.indexOf(cp orelse -1) orelse return self.centred(sym, cx, cy, size, col);
        const scale = scaleOf(f, size);
        const x: f32 = @floatFromInt(cx - @divTrunc(@as(i32, @intFromFloat(measured(f, i) * scale)), 2));
        put(f, i, x, @floatFromInt(topFor(cy, size)), scale, col);
    }

    /// Over a drop shadow, for text on the hud.
    pub fn text(self: *const Face, s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
        const off = shadowDrop(size);
        self.draw(s, x + off, y + off, size, shadowOf(col));
        self.draw(s, x, y, size, col);
    }

    /// `text` lit from above like struck metal: brighter over the top, `col` through the middle, deeper at the foot.
    pub fn engraved(self: *const Face, s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
        const f = self.walkable(s, size) orelse return self.text(s, x, y, size, col);
        const off = shadowDrop(size) + ENGRAVE_DROP;
        self.draw(s, x + off, y + off, size, shadowOf(col));
        const ink = Ink.of(col, @floatFromInt(y), @floatFromInt(size));
        const scale = scaleOf(f, size);
        var at: f32 = @floatFromInt(x);
        rl.gl.rlSetTexture(f.texture.id);
        defer rl.gl.rlSetTexture(0);
        rl.gl.rlBegin(rl.gl.rl_quads);
        defer rl.gl.rlEnd();
        for (s) |c| {
            const i = ascii(c);
            if (c != ' ') putInked(f, i, at, ink.top, scale, ink);
            at += advance(f, i, scale);
        }
    }

    /// `engraved`, its middle on `cx`.
    pub fn engravedMid(self: *const Face, s: [:0]const u8, cx: i32, y: i32, size: i32, col: rl.Color) void {
        self.engraved(s, self.leftFor(s, cx, size), y, size, col);
    }
};

fn shadowDrop(size: i32) i32 {
    return @max(@divTrunc(size, SHADOW_STEP), 1);
}

fn shadowOf(col: rl.Color) rl.Color {
    return .{ .r = 0, .g = 0, .b = 0, .a = @intCast(SHADOW_A * col.a / 255) };
}

/// Extra pixels an engraved line's shadow drops past `text`'s.
const ENGRAVE_DROP: i32 = 1;
/// Of the line's height, where the lit top gives way to the ink itself.
const ENGRAVE_MID: f32 = 0.45;
const ENGRAVE_LIT: f32 = 0.45;
const ENGRAVE_DEEP: f32 = 0.35;

const Ink = struct {
    lit: rl.Color,
    mid: rl.Color,
    deep: rl.Color,
    top: f32,
    size: f32,

    fn of(col: rl.Color, top: f32, size: f32) Ink {
        return .{ .lit = mixed(col, rl.Color.white, ENGRAVE_LIT), .mid = col, .deep = mixed(col, rl.Color.black, ENGRAVE_DEEP), .top = top, .size = size };
    }

    fn split(ink: Ink) f32 {
        return ink.top + ink.size * ENGRAVE_MID;
    }

    fn at(ink: Ink, y: f32) rl.Color {
        const t = std.math.clamp((y - ink.top) / ink.size, 0, 1);
        if (t <= ENGRAVE_MID) return mixed(ink.lit, ink.mid, t / ENGRAVE_MID);
        return mixed(ink.mid, ink.deep, (t - ENGRAVE_MID) / (1 - ENGRAVE_MID));
    }
};

fn mixed(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const k = std.math.clamp(t, 0, 1);
    const ch = struct {
        fn of(p: u8, q: u8, w: f32) u8 {
            return @intFromFloat(@round(mathx.lerpF(@floatFromInt(p), @floatFromInt(q), w)));
        }
    };
    return .{ .r = ch.of(a.r, b.r, k), .g = ch.of(a.g, b.g, k), .b = ch.of(a.b, b.b, k), .a = a.a };
}

/// `put` as raw quads inside an open `rl_quads` batch, coloured down the line by `ink`, split where its gradient bends.
fn putInked(f: rl.Font, i: usize, x: f32, y: f32, scale: f32, ink: Ink) void {
    const src, const dst = placed(f, i, x, y, scale);
    const tw: f32 = @floatFromInt(f.texture.width);
    const th: f32 = @floatFromInt(f.texture.height);
    const bottom = dst.y + dst.height;
    const bend = ink.split();
    if (bend > dst.y and bend < bottom) {
        band(src, dst, tw, th, dst.y, bend, ink);
        band(src, dst, tw, th, bend, bottom, ink);
    } else band(src, dst, tw, th, dst.y, bottom, ink);
}

fn band(src: rl.Rectangle, dst: rl.Rectangle, tw: f32, th: f32, y0: f32, y1: f32, ink: Ink) void {
    const left = src.x / tw;
    const right = (src.x + src.width) / tw;
    const upper = (src.y + (y0 - dst.y) / dst.height * src.height) / th;
    const lower = (src.y + (y1 - dst.y) / dst.height * src.height) / th;
    const c0 = ink.at(y0);
    const c1 = ink.at(y1);
    rl.gl.rlNormal3f(0, 0, 1);
    rl.gl.rlColor4ub(c0.r, c0.g, c0.b, c0.a);
    rl.gl.rlTexCoord2f(left, upper);
    rl.gl.rlVertex2f(dst.x, y0);
    rl.gl.rlColor4ub(c1.r, c1.g, c1.b, c1.a);
    rl.gl.rlTexCoord2f(left, lower);
    rl.gl.rlVertex2f(dst.x, y1);
    rl.gl.rlTexCoord2f(right, lower);
    rl.gl.rlVertex2f(dst.x + dst.width, y1);
    rl.gl.rlColor4ub(c0.r, c0.g, c0.b, c0.a);
    rl.gl.rlTexCoord2f(right, upper);
    rl.gl.rlVertex2f(dst.x + dst.width, y0);
}

test "an engraved line is lit at its top, its own ink through the middle and deeper at its foot" {
    const col = rl.Color{ .r = 188, .g = 160, .b = 107, .a = 255 };
    const ink = Ink.of(col, 100, 54);
    const top = ink.at(100);
    const mid = ink.at(ink.split());
    const foot = ink.at(154);
    std.debug.print("engraved ink, red channel: top {d}, middle {d}, foot {d}\n", .{ top.r, mid.r, foot.r });
    try std.testing.expect(top.r > mid.r and mid.r > foot.r);
    try std.testing.expectEqual(col, mid);
    try std.testing.expectEqual(col.a, foot.a);
}

/// `kept` in `buf` with "..." where the rest was cut: before it when `keep_end`, else after.
pub fn elided(buf: []u8, kept: []const u8, keep_end: bool) std.fmt.BufPrintError![:0]u8 {
    return if (keep_end) std.fmt.bufPrintZ(buf, ELLIPSIS ++ "{s}", .{kept}) else std.fmt.bufPrintZ(buf, "{s}" ++ ELLIPSIS, .{kept});
}

/// Between wrapped lines of text, past the text's size.
pub const LEADING: i32 = 4;
pub const SMALL_LINE: i32 = SMALL + LEADING;
pub const BODY_LINE: i32 = BODY + LEADING;
pub const WRAP_LINES_MAX: usize = 18;
pub const WRAP_COLS_MAX: usize = 96;
/// `wrap`'s lines, each nul-terminated.
pub const Wrapped = [WRAP_LINES_MAX][WRAP_COLS_MAX + 1]u8;

/// Each line in `buf` is nul-terminated; wrapping breaks only at spaces.
pub fn wrap(face: anytype, body: []const u8, size: i32, w: i32, buf: *Wrapped, lines: *[WRAP_LINES_MAX][:0]const u8) usize {
    var n: usize = 0;
    var words = std.mem.tokenizeScalar(u8, body, ' ');
    var len: usize = 0;
    while (words.next()) |word| {
        if (n == WRAP_LINES_MAX) break;
        const line = &buf[n];
        const with = len + @intFromBool(len > 0) + word.len;
        if (with <= WRAP_COLS_MAX) {
            var try_buf: [WRAP_COLS_MAX + 1]u8 = undefined;
            @memcpy(try_buf[0..len], line[0..len]);
            if (len > 0) try_buf[len] = ' ';
            @memcpy(try_buf[with - word.len .. with], word);
            try_buf[with] = 0;
            if (len == 0 or face.width(try_buf[0..with :0], size) <= w) {
                @memcpy(line[0 .. with + 1], try_buf[0 .. with + 1]);
                len = with;
                lines[n] = line[0..len :0];
                continue;
            }
        }
        if (len > 0) n += 1;
        if (n == WRAP_LINES_MAX) break;
        const fit = @min(word.len, WRAP_COLS_MAX);
        @memcpy(buf[n][0..fit], word[0..fit]);
        buf[n][fit] = 0;
        len = fit;
        lines[n] = buf[n][0..len :0];
    }
    return if (len > 0) @min(n + 1, WRAP_LINES_MAX) else n;
}

fn orderedGlyphs(f: rl.Font, cps: []const i32) bool {
    if (f.glyphCount != cps.len) return false;
    for (cps, 0..) |cp, i| {
        if (f.glyphs[i].value != cp) return false;
    }
    return true;
}

fn printable(s: []const u8) bool {
    for (s) |c| {
        if (c < ASCII_LO or c >= ASCII_LO + ASCII_N) return false;
    }
    return true;
}

fn ascii(c: u8) usize {
    return @intCast(c - ASCII_LO);
}

fn scaleOf(f: rl.Font, size: i32) f32 {
    return @as(f32, @floatFromInt(size)) / @as(f32, @floatFromInt(f.baseSize));
}

/// Glyph `i`'s advance as raylib's MeasureTextEx sums it, unscaled.
fn measured(f: rl.Font, i: usize) f32 {
    const g = f.glyphs[i];
    return if (g.advanceX > 0) @floatFromInt(g.advanceX) else f.recs[i].width + @as(f32, @floatFromInt(g.offsetX));
}

/// Glyph `i`'s pen advance as raylib's DrawTextEx steps it.
fn advance(f: rl.Font, i: usize, scale: f32) f32 {
    const g = f.glyphs[i];
    return if (g.advanceX == 0) f.recs[i].width * scale else @as(f32, @floatFromInt(g.advanceX)) * scale;
}

/// Glyph `i`'s padded atlas source and screen destination, as raylib's DrawTextCodepoint places them.
fn placed(f: rl.Font, i: usize, x: f32, y: f32, scale: f32) struct { rl.Rectangle, rl.Rectangle } {
    const g = f.glyphs[i];
    const r = f.recs[i];
    const pad: f32 = @floatFromInt(f.glyphPadding);
    const src = rl.Rectangle{ .x = r.x - pad, .y = r.y - pad, .width = r.width + 2 * pad, .height = r.height + 2 * pad };
    const dst = rl.Rectangle{
        .x = x + @as(f32, @floatFromInt(g.offsetX)) * scale - pad * scale,
        .y = y + @as(f32, @floatFromInt(g.offsetY)) * scale - pad * scale,
        .width = src.width * scale,
        .height = src.height * scale,
    };
    return .{ src, dst };
}

/// raylib's DrawTextCodepoint, glyph `i` already found.
fn put(f: rl.Font, i: usize, x: f32, y: f32, scale: f32, col: rl.Color) void {
    const src, const dst = placed(f, i, x, y, scale);
    rl.drawTexturePro(f.texture, src, dst, .{ .x = 0, .y = 0 }, 0, col);
}
