const rl = @import("raylib");

const TTF = "Balthazar-Regular.ttf";
/// One atlas this big, mipmapped, reads clean at every size drawn.
const ATLAS_PX: i32 = 96;
const SHADOW_A: u16 = 200;
/// Text size per pixel the shadow sits down and right.
const SHADOW_STEP: i32 = 14;
/// Body text: the hud's, the menus' notes, the editor's.
pub const BODY: i32 = 20;

/// Until `load` succeeds, raylib's built-in font stands in.
pub const Face = struct {
    font: ?rl.Font = null,

    /// Needs a live GL context.
    pub fn load() Face {
        var f = rl.loadFontFromMemory(".ttf", @embedFile(TTF), ATLAS_PX, null) catch return .{};
        rl.genTextureMipmaps(&f.texture);
        rl.setTextureFilter(f.texture, .trilinear);
        return .{ .font = f };
    }

    pub fn unload(self: *Face) void {
        if (self.font) |f| rl.unloadFont(f);
        self.font = null;
    }

    pub fn width(self: Face, s: [:0]const u8, size: i32) i32 {
        const f = self.font orelse return rl.measureText(s, size);
        return @intFromFloat(rl.measureTextEx(f, s, @floatFromInt(size), 0).x);
    }

    pub fn draw(self: Face, s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
        const f = self.font orelse return rl.drawText(s, x, y, size, col);
        rl.drawTextEx(f, s, .{ .x = @floatFromInt(x), .y = @floatFromInt(y) }, @floatFromInt(size), 0, col);
    }

    /// Where `s` starts with its middle on `cx`.
    pub fn leftFor(self: Face, s: [:0]const u8, cx: i32, size: i32) i32 {
        return cx - @divTrunc(self.width(s, size), 2);
    }

    /// One character, its middle on `cx`, `cy`.
    pub fn glyph(self: Face, ch: u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
        const s = [_:0]u8{ch};
        self.draw(&s, self.leftFor(&s, cx, size), cy - @divTrunc(size, 2), size, col);
    }

    /// Over a drop shadow, for text on the hud.
    pub fn text(self: Face, s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
        const off = @max(@divTrunc(size, SHADOW_STEP), 1);
        self.draw(s, x + off, y + off, size, .{ .r = 0, .g = 0, .b = 0, .a = @intCast(SHADOW_A * col.a / 255) });
        self.draw(s, x, y, size, col);
    }
};
