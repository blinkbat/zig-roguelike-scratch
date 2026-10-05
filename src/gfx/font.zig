const std = @import("std");
const rl = @import("raylib");

const TTF = "Balthazar-Regular.ttf";
/// One atlas this big, mipmapped, reads clean at every size drawn.
const ATLAS_PX: i32 = 96;
const SHADOW_A: u16 = 200;
/// Text size per pixel the shadow sits down and right.
const SHADOW_STEP: i32 = 14;
pub const BODY: i32 = 20;
pub const SMALL: i32 = 16;
const ASCII_LO: i32 = 32;
const ASCII_N: usize = 95;
const SYMBOLS_MAX: usize = 16;
const ELLIPSIS = "...";

/// Until `load` succeeds, raylib's built-in font stands in.
pub const Face = struct {
    font: ?rl.Font = null,
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
        if (f.glyphCount != all.len) return face;
        for (all, 0..) |cp, i| {
            if (f.glyphs[i].value != cp) return face;
        }
        @memcpy(face.symbols[0..symbols.len], symbols);
        face.symbol_n = symbols.len;
        face.ordered = true;
        return face;
    }

    /// Its glyph's place in the atlas, found without raylib's search of every glyph.
    fn indexOf(self: *const Face, cp: i32) ?usize {
        if (!self.ordered) return null;
        if (cp >= ASCII_LO and cp < ASCII_LO + ASCII_N) return @intCast(cp - ASCII_LO);
        for (self.symbols[0..self.symbol_n], ASCII_N..) |s, i| {
            if (s == cp) return i;
        }
        return null;
    }

    pub fn unload(self: *Face) void {
        if (self.font) |f| rl.unloadFont(f);
        self.font = null;
    }

    /// raylib's MeasureTextEx at no spacing, its glyph search skipped for printable ASCII.
    pub fn width(self: *const Face, s: [:0]const u8, size: i32) i32 {
        const f = self.font orelse return rl.measureText(s, size);
        if (!self.ordered or !printable(s)) return @intFromFloat(rl.measureTextEx(f, s, @floatFromInt(size), 0).x);
        var w: f32 = 0;
        for (s) |c| w += measured(f, ascii(c));
        return @intFromFloat(w * scaleOf(f, size));
    }

    /// raylib's DrawTextEx at no spacing, its glyph search skipped for printable ASCII.
    pub fn draw(self: *const Face, s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
        const f = self.font orelse return rl.drawText(s, x, y, size, col);
        const at = rl.Vector2{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
        if (!self.ordered or !printable(s)) return rl.drawTextEx(f, s, at, @floatFromInt(size), 0, col);
        const scale = scaleOf(f, size);
        var off: f32 = 0;
        for (s) |c| {
            const i = ascii(c);
            if (c != ' ') put(f, i, at.x + off, at.y, scale, col);
            const g = f.glyphs[i];
            off += if (g.advanceX == 0) f.recs[i].width * scale else @as(f32, @floatFromInt(g.advanceX)) * scale;
        }
    }

    /// `s` whole, or as much of it as fits in `max` px beside "..." (its end kept when `keep_end`), in `buf`, which must not hold `s`.
    pub fn fit(self: *const Face, buf: []u8, s: []const u8, size: i32, max: i32, keep_end: bool) [:0]const u8 {
        const whole = std.fmt.bufPrintZ(buf, "{s}", .{s}) catch "";
        if (whole.len == s.len and self.width(whole, size) <= max) return whole;
        var n = @min(s.len, buf.len -| (ELLIPSIS.len + 1));
        while (true) : (n -= 1) {
            const t = (if (keep_end)
                std.fmt.bufPrintZ(buf, ELLIPSIS ++ "{s}", .{s[s.len - n ..]})
            else
                std.fmt.bufPrintZ(buf, "{s}" ++ ELLIPSIS, .{s[0..n]})) catch return whole;
            if (n == 0 or self.width(t, size) <= max) return t;
        }
    }

    /// Where `s` starts with its middle on `cx`.
    pub fn leftFor(self: *const Face, s: [:0]const u8, cx: i32, size: i32) i32 {
        return cx - @divTrunc(self.width(s, size), 2);
    }

    /// One character, its middle on `cx`, `cy`.
    pub fn glyph(self: *const Face, ch: u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
        const s = [_:0]u8{ch};
        self.centred(&s, cx, cy, size, col);
    }

    fn centred(self: *const Face, s: [:0]const u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
        self.draw(s, self.leftFor(s, cx, size), topFor(cy, size), size, col);
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
        const off = @max(@divTrunc(size, SHADOW_STEP), 1);
        self.draw(s, x + off, y + off, size, .{ .r = 0, .g = 0, .b = 0, .a = @intCast(SHADOW_A * col.a / 255) });
        self.draw(s, x, y, size, col);
    }
};

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

/// raylib's DrawTextCodepoint, glyph `i` already found.
fn put(f: rl.Font, i: usize, x: f32, y: f32, scale: f32, col: rl.Color) void {
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
    rl.drawTexturePro(f.texture, src, dst, .{ .x = 0, .y = 0 }, 0, col);
}
