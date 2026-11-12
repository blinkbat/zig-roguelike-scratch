const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const damage = @import("../play/damage.zig");
const items = @import("../play/items.zig");
const skillbar = @import("../play/skillbar.zig");
const resilience = @import("../play/resilience.zig");
const font = @import("font.zig");
const ground = @import("ground.zig");
const sky = @import("sky.zig");
const shaders = @import("shaders.zig");

pub const SPRITE_PX: i32 = 64;

pub fn pxScale(cell: f32) f32 {
    return cell / SPRITE_PX;
}
/// A faced wall's bottom rows of brick, as `tools/tile_art/export_walls.lua` paints them.
pub const WALL_FACE_PX: i32 = 23;
pub const GLYPH_PX: i32 = 60;

pub const Look = struct {
    ch: u8,
    fg: rl.Color,
};

const Shadow = enum { silhouette, canopy };

const STANDS = std.EnumArray(grid.Tile, ?Shadow).initDefault(@as(?Shadow, null), .{
    .shrub = .canopy,
    .swamp_tree = .canopy,
    .large_tree = .canopy,
    .tiny_shrub = .canopy,
    .boulder = .silhouette,
    .fungus = .silhouette,
    .tall_grass = .silhouette,
    .shrooms = .silhouette,
    .chest = .silhouette,
    .chest_open = .silhouette,
    .caravan = .silhouette,
});

pub fn stands(t: grid.Tile) bool {
    return STANDS.get(t) != null;
}

pub fn canopied(t: grid.Tile) bool {
    return STANDS.get(t) == .canopy;
}

pub fn tall(t: grid.Tile) bool {
    return t == .large_tree or t == .caravan;
}

pub fn occludes(t: grid.Tile) bool {
    return tall(t) or t == .reeds;
}

pub fn castsPicture(t: grid.Tile) bool {
    return stands(t) or occludes(t);
}

const OCCLUDED_A: f32 = 0.4;

pub const Occlusion = struct {
    body: [2]f32 = .{ 0, 0 },
    hidden: f32 = 0,

    pub fn set(self: Occlusion, p: anytype) void {
        shaders.setUniform(p.shader, p.body, self.body);
        shaders.setUniform(p.shader, p.hidden, self.hidden);
    }
};

const OCCLUSION_RADIUS = [2]f32{ 0.6, 0.85 };
const OCCLUSION_INNER: f32 = 0.35;

pub const OCCLUSION_FS = shaders.glslConsts(.{ .OCCLUDED_A = OCCLUDED_A, .OCCLUSION_RADIUS = OCCLUSION_RADIUS, .OCCLUSION_INNER = OCCLUSION_INNER }) ++
    \\uniform vec2 body;
    \\uniform float hidden;
    \\float occlusionAt(vec2 p) {
    \\    float distance = length((p - body) / OCCLUSION_RADIUS);
    \\    float aperture = 1.0 - smoothstep(OCCLUSION_INNER, 1.0, distance);
    \\    return mix(1.0, OCCLUDED_A, hidden * aperture);
    \\}
;

pub fn occlusionAlpha(hidden: f32) f32 {
    return mathx.lerpF(1, OCCLUDED_A, hidden);
}

pub fn tileRect(t: grid.Tile, tex: rl.Texture2D, cell: rl.Rectangle) rl.Rectangle {
    const width = cell.width * @as(f32, @floatFromInt(t.wide()));
    const height = width * @as(f32, @floatFromInt(tex.height)) / @as(f32, @floatFromInt(tex.width));
    return .{ .x = cell.x, .y = cell.y + if (tall(t)) cell.height - height else (cell.height - height) / 2, .width = width, .height = height };
}

pub fn rgb(hex: u24) rl.Color {
    return .{ .r = @intCast(hex >> 16), .g = @intCast((hex >> 8) & 0xff), .b = @intCast(hex & 0xff), .a = 255 };
}

pub fn fade(c: rl.Color, a: f32) rl.Color {
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = @intFromFloat(@as(f32, @floatFromInt(c.a)) * std.math.clamp(a, 0, 1)) };
}

pub fn mixed(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const k = std.math.clamp(t, 0, 1);
    const ch = struct {
        fn of(p: u8, q: u8, w: f32) u8 {
            return @intFromFloat(@round(mathx.lerpF(@floatFromInt(p), @floatFromInt(q), w)));
        }
    };
    return .{ .r = ch.of(a.r, b.r, k), .g = ch.of(a.g, b.g, k), .b = ch.of(a.b, b.b, k), .a = a.a };
}

const GOLD = rgb(0xc9a24a);
const FOE = rgb(0xe0503a);
const SHADE = rgb(0x3e3c46);

pub const BG = rgb(0x07070a);
pub const FOG = rgb(0x0a0a0a);
pub const LIT = rl.Color.white;
const FLOOR_BG = rgb(0x121116);
const GRASS_BG = rgb(0x111a0e);
pub const BARE_WALL = rgb(0x1e1c24);
pub const TEXT = rgb(0xd8cdb4);
pub const DIM = rgb(0x8c8672);
pub const LIFE = rgb(0x9c2f2a);
pub const FIRE = rgb(0xff8a32);
pub const FIRE_CORE = rgb(0xffe6a0);
pub const FLAME_FILL = rgb(0xff5a14);
pub const LEVEL_GOLD = rgb(0xe6c57c);
pub const LEVEL_CORE = rgb(0xffedbd);
pub const LEVEL_BODY_TINT = [3]f32{ 1, 0.72, 0.28 };
pub const BLEED = rgb(0xd8483a);
pub const EDGE = rgb(0x4a4438);
pub const UI_GOLD = rgb(0xbca06b);
pub const UI_FOCUS = rgb(0xd0b581);
pub const LOSS = rgb(0xe18c83);
const ARROW = rgb(0xe6dcb4);
pub const VEIL = fade(BG, 0.72);

pub fn inkTile(face: *const font.Face, t: grid.Tile, cx: i32, cy: i32, size: i32) void {
    const l = TILES.getPtrConst(t);
    face.symbol(l.sym, l.ch, cx, cy, size, l.fg);
}

pub fn tile(t: grid.Tile) Look {
    const l = TILES.getPtrConst(t);
    return .{ .ch = l.ch, .fg = l.fg };
}

pub fn tileBg(t: grid.Tile) ?rl.Color {
    return TILES.getPtrConst(t).bg;
}

pub fn under(t: grid.Tile) ?grid.Tile {
    return t.ground() orelse if (t.upright() and tileBg(t) == null) .floor else null;
}

const CROWNS = std.EnumSet(grid.Tile).init(.{ .shrub = true, .swamp_tree = true, .large_tree = true });
pub const SOFTENED = CROWNS.unionWith(grid.LITTER_TILES);

comptime {
    for (std.enums.values(grid.Tile)) |t| {
        if (SOFTENED.contains(t) and !stands(t)) @compileError(@tagName(t) ++ " is softened but stands in no STANDS row");
        if (CROWNS.contains(t) and !canopied(t)) @compileError(@tagName(t) ++ " is a crown but no .canopy STANDS row");
    }
}

pub fn crowned(t: grid.Tile) bool {
    return CROWNS.contains(t);
}

pub fn veiled(t: grid.Tile) bool {
    return t != .wall and t != .rock;
}

pub fn standsOver(t: grid.Tile) bool {
    return ground.of(t) == null;
}

const TileLook = struct { sym: [:0]const u8, ch: u8, fg: rl.Color, bg: ?rl.Color, mini: rl.Color, mini_dim: rl.Color };

const TREE_INK = .{ .fg = rgb(0x788650), .mini = rgb(0x667247), .mini_dim = rgb(0x343b29) };
const SHRUB_INK = rgb(0x6f9a4a);
const STONE_INK = rgb(0x8a7f6a);
const HIDE_INK = rgb(0xb07a4e);
const PIB_INK = rgb(0xe89aa6);
const OPEN_CHEST_INK = rgb(0x96724d);

const TILES = std.EnumArray(grid.Tile, TileLook).init(.{
    .wall = .{ .sym = "#", .ch = '#', .fg = rgb(0x9a8e78), .bg = null, .mini = STONE_INK, .mini_dim = rgb(0x46434c) },
    .floor = .{ .sym = "·", .ch = '.', .fg = rgb(0x5e5a50), .bg = FLOOR_BG, .mini = rgb(0x3a3830), .mini_dim = rgb(0x1c1c22) },
    .grass = .{ .sym = "\"", .ch = '"', .fg = rgb(0x4f7a3a), .bg = GRASS_BG, .mini = rgb(0x2e4426), .mini_dim = rgb(0x182016) },
    .shrub = .{ .sym = "¥", .ch = '&', .fg = SHRUB_INK, .bg = null, .mini = rgb(0x5e8a3e), .mini_dim = rgb(0x2e3c2a) },
    .rock = .{ .sym = "#", .ch = '#', .fg = rgb(0x8a7e6c), .bg = rgb(0x262220), .mini = rgb(0x6e6558), .mini_dim = rgb(0x38332e) },
    .dirt = .{ .sym = "·", .ch = '.', .fg = rgb(0x8a6a44), .bg = rgb(0x1a140e), .mini = rgb(0x4a3a28), .mini_dim = rgb(0x231c14) },
    .sand = .{ .sym = "·", .ch = '.', .fg = rgb(0xd8c084), .bg = rgb(0x2e2716), .mini = rgb(0x8a7a50), .mini_dim = rgb(0x403a28) },
    .snow = .{ .sym = "°", .ch = '*', .fg = rgb(0xe6eef2), .bg = rgb(0x2c3036), .mini = rgb(0x9aa2a8), .mini_dim = rgb(0x464a50) },
    .water = .{ .sym = "≈", .ch = '~', .fg = rgb(0x4a80d0), .bg = rgb(0x0e1a36), .mini = rgb(0x24508a), .mini_dim = rgb(0x142640) },
    .shallows = .{ .sym = "~", .ch = '~', .fg = rgb(0x78b0d4), .bg = rgb(0x14283c), .mini = rgb(0x3e6e8e), .mini_dim = rgb(0x1e3444) },
    .bridge = .{ .sym = "=", .ch = '=', .fg = rgb(0xa87c48), .bg = rgb(0x1e160e), .mini = rgb(0x7a5a36), .mini_dim = rgb(0x3a2c1c) },
    .reeds = .{ .sym = "¦", .ch = '|', .fg = rgb(0xa8b24a), .bg = null, .mini = rgb(0x6a7030), .mini_dim = rgb(0x32361a) },
    .rubble = .{ .sym = "•", .ch = ',', .fg = STONE_INK, .bg = rgb(0x18161a), .mini = rgb(0x4e4840), .mini_dim = rgb(0x26241f) },
    .fence = .{ .sym = "∏", .ch = '#', .fg = rgb(0x9a6638), .bg = null, .mini = rgb(0x7a5030), .mini_dim = rgb(0x3a2818) },
    .lava = .{ .sym = "≈", .ch = '~', .fg = rgb(0xff8a30), .bg = rgb(0x501406), .mini = rgb(0xc8501a), .mini_dim = rgb(0x5a240c) },
    .fungus = .{ .sym = "¶", .ch = 'T', .fg = rgb(0xb882e0), .bg = null, .mini = rgb(0x7a4e9a), .mini_dim = rgb(0x3a2a48) },
    .chasm = .{ .sym = "·", .ch = ':', .fg = rgb(0x24222a), .bg = rgb(0x030305), .mini = rgb(0x0c0c10), .mini_dim = rgb(0x060608) },
    .ice = .{ .sym = "·", .ch = '_', .fg = rgb(0xb8e4f4), .bg = rgb(0x1c3440), .mini = rgb(0x7ab0c8), .mini_dim = rgb(0x3a5462) },
    .grave = .{ .sym = "†", .ch = '+', .fg = rgb(0xc8c4b8), .bg = null, .mini = rgb(0x8a8680), .mini_dim = rgb(0x44423e) },
    .crop = .{ .sym = "¥", .ch = '"', .fg = rgb(0xd8b84a), .bg = rgb(0x1e1a0a), .mini = rgb(0x8a7a30), .mini_dim = rgb(0x403a18) },
    .tiny_shrub = .{ .sym = "'", .ch = '\'', .fg = SHRUB_INK, .bg = null, .mini = rgb(0x4e7436), .mini_dim = rgb(0x26341f) },
    .boulder = .{ .sym = "o", .ch = 'o', .fg = rgb(0x9a8e90), .bg = null, .mini = rgb(0x7a7072), .mini_dim = rgb(0x3c3638) },
    .tall_grass = .{ .sym = "\"", .ch = '"', .fg = rgb(0x7aa84e), .bg = null, .mini = rgb(0x3a5630), .mini_dim = rgb(0x1c2818) },
    .shrooms = .{ .sym = "•", .ch = ',', .fg = rgb(0xd8ccb4), .bg = null, .mini = rgb(0x3c4a30), .mini_dim = rgb(0x1e241a) },
    .chest = .{ .sym = "C", .ch = 'C', .fg = GOLD, .bg = null, .mini = GOLD, .mini_dim = rgb(0x66502b) },
    .chest_open = .{ .sym = "O", .ch = 'O', .fg = OPEN_CHEST_INK, .bg = null, .mini = OPEN_CHEST_INK, .mini_dim = rgb(0x443422) },
    .swamp_tree = .{ .sym = "S", .ch = 'S', .fg = TREE_INK.fg, .bg = null, .mini = TREE_INK.mini, .mini_dim = TREE_INK.mini_dim },
    .large_tree = .{ .sym = "L", .ch = 'L', .fg = TREE_INK.fg, .bg = null, .mini = TREE_INK.mini, .mini_dim = TREE_INK.mini_dim },
    .glow_plant = .{ .sym = "&", .ch = '&', .fg = rgb(0x9fd2ff), .bg = null, .mini = rgb(0x7fb2e0), .mini_dim = rgb(0x2e4256) },
    .caravan = .{ .sym = "H", .ch = 'H', .fg = CARAVAN_INK.fg, .bg = null, .mini = CARAVAN_INK.mini, .mini_dim = CARAVAN_INK.mini_dim },
    .caravan_part = .{ .sym = "h", .ch = 'h', .fg = CARAVAN_INK.fg, .bg = null, .mini = CARAVAN_INK.mini, .mini_dim = CARAVAN_INK.mini_dim },
    .stone_bridge = .{ .sym = "=", .ch = '=', .fg = STONE_INK, .bg = rgb(0x1c1a18), .mini = rgb(0x6e665a), .mini_dim = rgb(0x34302a) },
});

const CARAVAN_INK = .{ .fg = rgb(0xd8c8a4), .mini = rgb(0x9a7a52), .mini_dim = rgb(0x46382a) };

comptime {
    for (TILES.values) |l| std.debug.assert(l.sym.len != 1 or l.sym[0] == l.ch);
}

pub const TILE_CODEPOINTS = blk: {
    var out: []const i32 = &.{};
    for (TILES.values) |l| {
        const cp: i32 = std.unicode.utf8Decode(l.sym) catch unreachable;
        if (cp < 0x80) continue;
        const have = for (out) |o| {
            if (o == cp) break true;
        } else false;
        if (!have) out = out ++ &[_]i32{cp};
    }
    break :blk out;
};

pub const TORCH = Look{ .ch = 'i', .fg = rgb(0xffc46a) };
pub const TORCH_DIM = rgb(0x4a4238);
const WOOD = rl.Color{ .r = 120, .g = 82, .b = 46, .a = 230 };
pub const TORCH_HANDLE = WOOD;
pub const BARREL = Look{ .ch = '0', .fg = rgb(0x8a5a32) };
pub const NPC = Look{ .ch = '@', .fg = rgb(0xd8a860) };
pub const DOOR = Look{ .ch = '+', .fg = rgb(0xb89a5a) };
pub const Mark = enum {
    door,
    barrel,

    pub fn of(lv: *const grid.Level, i: usize) ?Mark {
        if (lv.door[i] != grid.NO_DOOR) return .door;
        if (lv.barrel[i]) return .barrel;
        return null;
    }

    pub fn look(m: Mark) Look {
        return switch (m) {
            .door => DOOR,
            .barrel => BARREL,
        };
    }
};

pub fn body(k: actor.Kind) Look {
    return switch (k) {
        .archer => .{ .ch = '@', .fg = rgb(0x7cc86e) },
        .wizard => .{ .ch = '@', .fg = rgb(0x8f9cf2) },
        .knight => .{ .ch = '@', .fg = rgb(0xd6d9e0) },
        .rat => .{ .ch = 'r', .fg = HIDE_INK },
        .slime, .slime_half, .slime_quarter => .{ .ch = 's', .fg = rgb(0x6fae5a) },
        .bloat => .{ .ch = 'b', .fg = CAUSTIC_BLOAT },
        .pib => .{ .ch = 'p', .fg = PIB_INK },
        .beefy_pib => .{ .ch = 'P', .fg = PIB_INK },
        .bandit_crossbowman => .{ .ch = 'c', .fg = HIDE_INK },
        .bandit_netter => .{ .ch = 'T', .fg = rgb(0xffeb3b) },
        .bandit_shieldbearer => .{ .ch = 'S', .fg = rgb(0x4d7cff) },
        .frost_wisp => .{ .ch = 'W', .fg = rgb(0x4ff0ff) },
        .pyre_bloat => .{ .ch = 'B', .fg = rgb(0xff3b3b) },
        .pib_shaman => .{ .ch = 'Y', .fg = rgb(0xc77dff) },
        .bog_leech => .{ .ch = 'L', .fg = rgb(0x8cff3f) },
        .mimic => .{ .ch = 'M', .fg = rgb(0xff9f1c) },
        .goblin => .{ .ch = 'g', .fg = rgb(0x9bc53d) },
        .sluice_crab => .{ .ch = 'C', .fg = rgb(0x5fb3a8) },
        .chain_gaoler => .{ .ch = 'J', .fg = rgb(0xa8a29a) },
        .cinder_imp => .{ .ch = 'i', .fg = rgb(0xff7a1a) },
        .skeleton => .{ .ch = 'Z', .fg = rgb(0xe8e2cf) },
        .caravan_guard => .{ .ch = 'G', .fg = rgb(0x7cc86e) },
    };
}

pub const GLYPH_SHADOW = rl.Color{ .r = 0, .g = 0, .b = 0, .a = DROP_SHADOW_A };
pub const GLYPH_SHADOW_PX: i32 = 4;
const DROP_SHADOW_A: u8 = 200;

/// Brogue's `poisonGasColor`, the caustic bloat's.
const CAUSTIC_BLOAT = rgb(0xbf40d9);
pub const GAS = rgb(0xd0609a);
pub const HEALING_GAS = rgb(0x2ed6c0);
pub const STEAM = rgb(0xe6e8ea);
const SMOKE = rgb(0x5a5652);

pub fn gasInk(g: grid.Gas) rl.Color {
    return switch (g) {
        .caustic => GAS,
        .healing => HEALING_GAS,
        .steam => STEAM,
        .smoke => SMOKE,
    };
}

pub const BLOOD = rl.Color{ .r = 112, .g = 22, .b = 16, .a = GORE_A };
pub const OOZE = rl.Color{ .r = 70, .g = 120, .b = 72, .a = GORE_A };
pub const SPLINTER = WOOD;
pub const ICHOR = rl.Color{ .r = CAUSTIC_BLOAT.r / 2, .g = CAUSTIC_BLOAT.g / 2, .b = CAUSTIC_BLOAT.b / 2, .a = GORE_A };
const GORE_A: u8 = 220;
pub const CONTACT = rl.Color{ .r = 255, .g = 244, .b = 214, .a = 180 };
pub const JUKE_TRAIL = rl.Color{ .r = 196, .g = 212, .b = 218, .a = 140 };
pub const JUKE_DUST = rl.Color{ .r = 184, .g = 161, .b = 125, .a = 170 };
pub const SWEEP = rl.Color{ .r = 232, .g = 226, .b = 208, .a = 200 };
pub const WATER_DROP = rl.Color{ .r = 214, .g = 232, .b = 252, .a = 205 };
pub const RIPPLE = rgb(0x9db6d4);
pub const DIRT_DUST = rl.Color{ .r = 200, .g = 182, .b = 148, .a = 170 };
pub const SAND_DUST = rl.Color{ .r = 238, .g = 226, .b = 192, .a = 160 };

pub fn stepDust(t: grid.Tile) ?rl.Color {
    return switch (ground.of(t) orelse return null) {
        .dirt => DIRT_DUST,
        .sand => SAND_DUST,
        .chasm, .lava, .water, .shallows, .ice, .snow, .crop, .grass, .rubble, .bridge, .cobble => null,
    };
}
pub const NET = rgb(0xd6c496);
pub const RAIN = rgb(0xc4d0e2);
pub const MIST_TINT = [3]f32{ 0.48, 0.58, 0.68 };
pub const SHAFT_TINT = [3]f32{ 1.0, 0.87, 0.64 };

pub const Gait = enum { hop, slide };

pub fn gait(k: actor.Kind) Gait {
    return switch (k) {
        .archer, .wizard, .knight, .rat, .pib, .beefy_pib, .bandit_crossbowman, .bandit_netter, .bandit_shieldbearer, .pib_shaman, .mimic, .goblin, .chain_gaoler, .cinder_imp, .skeleton, .caravan_guard => .hop,
        .slime, .slime_half, .slime_quarter, .bloat, .frost_wisp, .pyre_bloat, .bog_leech, .sluice_crab => .slide,
    };
}

pub fn mini(t: grid.Tile, lit: bool) rl.Color {
    const l = TILES.getPtrConst(t);
    return if (lit) l.mini else l.mini_dim;
}

pub const AIM_REACH = fade(GOLD, 0.10);
pub const AIM_PATH = fade(GOLD, 0.28);
/// A braced foe's line: where its charge or hook will go.
pub const BRACED = fade(rgb(0xe0503c), 0.32);
pub const CHAIN = rgb(0x9a958c);
pub const COLD = rgb(0x8cddf5);
const PIN = rgb(0xc8c2b4);
const SHOCK = rgb(0xb48cff);
const SUNDER = rgb(0xb5652e);
const BLIND = rgb(0x8a96a3);
const CONFUSION = rgb(0x9ad46b);
const ENFEEBLE = rgb(0xa58bb8);
const MAIM = rgb(0xc9805e);
const FEAR = rgb(0xe39bc4);
pub const WARD = rgb(0x6fa8f0);
pub const MAGIC = WARD;
const RARE = rgb(0xe8d15a);

pub fn itemInk(rarity: items.Rarity) rl.Color {
    return switch (rarity) {
        .normal => rl.Color.white,
        .magic => MAGIC,
        .rare => RARE,
    };
}
const AIM_AREA_A: f32 = 0.24;
pub const RETICLE = rgb(0xe8c25a);

pub fn aimArea(a: skillbar.Act) rl.Color {
    return fade(arrowInk(a), AIM_AREA_A);
}

pub fn aimElement(e: damage.Element) rl.Color {
    return fade(elementInk(e), AIM_AREA_A);
}
pub const RETICLE_BLOCKED = SHADE;
pub const LEAN_OPEN = GOLD;
pub const LEAN_FOE = FOE;
pub const LEAN_BLOCKED = SHADE;

pub fn arrowInk(a: skillbar.Act) rl.Color {
    return elementInk(a.element() orelse return PHYSICAL);
}

pub fn elementInk(e: damage.Element) rl.Color {
    return switch (e) {
        .fire => FIRE,
        .cold => COLD,
        .lightning => LIGHTNING,
        .chaos => ARROW,
    };
}

pub const LIGHTNING = rgb(0xf4e872);
pub const LIGHTNING_CORE = FIRE_CORE;
pub const PHYSICAL = ARROW;
pub const LIFE_TEXT = rgb(0xe0645a);
pub const MANA_TEXT = rgb(0x6e9ce8);

pub fn ailmentInk(k: resilience.Kind) rl.Color {
    return switch (k) {
        .stun => LIGHTNING,
        .burn => elementInk(.fire),
        .bleed => BLEED,
        .chill => elementInk(.cold),
        .pin => PIN,
        .shock => SHOCK,
        .sunder => SUNDER,
        .blind => BLIND,
        .confusion => CONFUSION,
        .enfeeble => ENFEEBLE,
        .maim => MAIM,
        .fright => FEAR,
    };
}

const PANEL = rgb(0x0e0d12);
const RAISED = rgb(0x1a1820);

pub const SLOT_BG = RAISED;
pub const SLOT_EMPTY = PANEL;
pub const SLOT_HELD = UI_GOLD;
pub const SLOT_CURSOR = UI_FOCUS;
pub const SLOT_CLEAR = FOE;
pub const PICK_BG = PANEL;
pub const ROW_ON = RAISED;
pub const CLEAR = Look{ .ch = 'x', .fg = SLOT_CLEAR };

pub const CLEAR_A: f32 = 0.004;
pub const FADED_A: f32 = 0.35;

/// A shader drawing over it again (the gas veil) softens its own alpha alike.
pub const Focused = struct {
    texel: [2]f32 = .{ 0, 0 },
    strength: f32 = 0,

    pub const sharp: Focused = .{};

    pub fn set(self: Focused, p: anytype) void {
        shaders.setUniform(p.shader, p.texel, self.texel);
        shaders.setUniform(p.shader, p.strength, self.strength);
    }
};

const FOCUS_CENTRE_W = 0.4;
const FOCUS_SIDE_W = (1 - FOCUS_CENTRE_W) / 4.0;
pub const FOCUS_WEIGHTS = shaders.glslConsts(.{ .FOCUS_CENTRE_W = FOCUS_CENTRE_W, .FOCUS_SIDE_W = FOCUS_SIDE_W }) ++
    \\vec4 crossBlur(vec4 centre, vec4 sides) {
    \\    return centre * FOCUS_CENTRE_W + sides * FOCUS_SIDE_W;
    \\}
    \\
;
pub const FOCUS_TAPS = FOCUS_WEIGHTS ++
    \\uniform vec2 texel;
    \\uniform float strength;
    \\vec4 tap(vec2 offset) {
    \\    vec4 c = texture(texture0, clamp(fragTexCoord + offset * texel, texel * 0.5, vec2(1.0) - texel * 0.5));
    \\    return vec4(c.rgb * c.a, c.a);
    \\}
    \\vec4 focused() {
    \\    vec4 base = tap(vec2(0.0));
    \\    vec4 blur = crossBlur(base, tap(vec2(1.0, 0.0)) + tap(vec2(-1.0, 0.0)) + tap(vec2(0.0, 1.0)) + tap(vec2(0.0, -1.0)));
    \\    return mix(base, blur, strength);
    \\}
    \\vec3 unpremultiplied(vec4 c) {
    \\    return c.rgb / max(c.a, 0.0001);
    \\}
    \\
;

const SHINE_PERIOD_S: f32 = 7;
const SHINE_WIPE_S: f32 = 0.9;
pub const SHINE_WIDTH: f32 = 0.12;
pub const SHINE_SLANT: f32 = 0.6;
pub const SHINE_GAIN: f32 = 0.18;
pub const LOOT_GLOW: f32 = 0.1;
const SHINE_SEED: u64 = 0x5417E;
const SHINE_PHASES = 1000;
pub fn shineSweep(seconds: f32, p: mathx.P) ?f32 {
    const phase = mathx.cellHash(SHINE_SEED, p) % SHINE_PHASES;
    const t = @mod(seconds + @as(f32, @floatFromInt(phase)) / SHINE_PHASES * SHINE_PERIOD_S, SHINE_PERIOD_S);
    if (t >= SHINE_WIPE_S) return null;
    return mathx.lerpF(-SHINE_WIDTH, 1 + SHINE_WIDTH, t / SHINE_WIPE_S);
}

/// Of the shallows' colours, what deep water's art keeps: `tools/tile_art/deepen_water.lua`.
pub const WATER_DEEP_PERCENT = 60;
pub const WATER_DEEP: f32 = mathx.fraction(WATER_DEEP_PERCENT);
pub const WATER_SHALLOW: f32 = 1;

pub fn waterDepth(gr: ground.Ground) ?f32 {
    return switch (gr) {
        .water => WATER_DEEP,
        .shallows => WATER_SHALLOW,
        .chasm, .lava, .ice, .snow, .sand, .dirt, .crop, .grass, .rubble, .bridge, .cobble => null,
    };
}

pub const REFLECTIVE = blk: {
    var set = std.EnumSet(ground.Ground).initEmpty();
    for (std.enums.values(ground.Ground)) |gr| {
        if (waterDepth(gr) != null) set.insert(gr);
    }
    break :blk set;
};

pub fn reflects(t: grid.Tile) bool {
    return REFLECTIVE.contains(ground.of(t) orelse return false);
}

pub fn alphaOf(c: rl.Color) f32 {
    return @as(f32, @floatFromInt(c.a)) / 255;
}

pub fn rgbOf(c: rl.Color) sky.Rgb {
    return sky.Rgb{ @floatFromInt(c.r), @floatFromInt(c.g), @floatFromInt(c.b) } / sky.splat(255);
}

pub fn rgbaOf(c: rl.Color) [4]f32 {
    const tone = rgbOf(c);
    return .{ tone[0], tone[1], tone[2], alphaOf(c) };
}

pub fn colourOf(c: sky.Rgb, a: f32) rl.Color {
    const k = @max(sky.splat(0), @min(sky.splat(1), c)) * sky.splat(255) + sky.splat(0.5);
    return .{ .r = @intFromFloat(k[0]), .g = @intFromFloat(k[1]), .b = @intFromFloat(k[2]), .a = @intFromFloat(std.math.clamp(a, 0, 1) * 255 + 0.5) };
}

pub fn premultiplied(c: sky.Rgb, a: f32) rl.Color {
    const k = std.math.clamp(a, 0, 1);
    return colourOf(c * sky.splat(k), k);
}

const BACKING_A: f32 = 0.7;
pub const BACKING = fade(rgb(0x101114), BACKING_A);
pub const MINI_BG = fade(FOG, BACKING_A);
pub const MINI_HERO = rgb(0x9cf08a);
pub const MINI_FOE = FOE;
pub const MINI_VIEW = fade(GOLD, 0.7);
pub const DAY_SUN = LEVEL_GOLD;
pub const DAY_MOON = rgb(0xc9cfdc);
pub const DAY_PATH = fade(UI_GOLD, 0.45);
pub const DAY_SHADOW = fade(BG, 0.75);

pub const EDIT_PANEL = PANEL;
pub const EDIT_ROW_ON = ROW_ON;
pub const EDIT_ON = UI_GOLD;
pub const EDIT_PICKED = UI_FOCUS;
pub const EDIT_WARN = FOE;
pub const EDIT_HOVER = fade(TEXT, 0.6);
pub const EDIT_UNLINKED = DIM;

pub const PROMPT_BODY = rgb(0x1b1713);
pub const PROMPT_FACE = rgb(0x28221c);
pub const PROMPT_EDGE = rgb(0x6a604e);
pub const PROMPT_LIP = rgb(0x0c0a08);
pub const PROMPT_INK = rgb(0xe2d2b4);
pub const XBOX_A = rgb(0x5eb242);
pub const XBOX_B = rgb(0xd63e34);
pub const XBOX_X = rgb(0x2e78cd);
pub const XBOX_Y = UI_FOCUS;
pub const SONY_CROSS = rgb(0x7cb2e8);
pub const SONY_CIRCLE = rgb(0xea6060);
pub const SONY_SQUARE = rgb(0xd686c4);
pub const SONY_TRIANGLE = rgb(0x40c4a0);

test "a cell's shine crosses once a period, corner to corner, and neighbours shine at other times" {
    const dt = mathx.TEST_DT;
    const p = mathx.P{ .x = 10, .y = 10 };
    var shining: usize = 0;
    var last: ?f32 = null;
    var t: f32 = 0;
    const frames: usize = @intFromFloat(SHINE_PERIOD_S / dt);
    for (0..frames) |_| {
        t += dt;
        const s = shineSweep(t, p) orelse {
            last = null;
            continue;
        };
        shining += 1;
        try std.testing.expect(s >= -SHINE_WIDTH and s <= 1 + SHINE_WIDTH);
        if (last) |l| try std.testing.expect(s > l);
        last = s;
    }
    const share = @as(f32, @floatFromInt(shining)) / @as(f32, @floatFromInt(frames));
    try std.testing.expectApproxEqAbs(SHINE_WIPE_S / SHINE_PERIOD_S, share, 0.01);
    var together: usize = 0;
    for (0..20) |x| {
        if ((shineSweep(1, .{ .x = @intCast(x), .y = 0 }) != null) == (shineSweep(1, .{ .x = @intCast(x + 1), .y = 0 }) != null)) together += 1;
    }
    try std.testing.expect(together < 20);
}

test "every glyph is printable ascii" {
    const inked = struct {
        fn f(c: u8) bool {
            return std.ascii.isPrint(c) and c != ' ';
        }
    }.f;
    for (std.enums.values(grid.Tile)) |t| try std.testing.expect(inked(TILES.get(t).ch));
    for (std.enums.values(actor.Kind)) |k| try std.testing.expect(inked(body(k).ch));
    try std.testing.expect(inked(TORCH.ch));
    try std.testing.expect(inked(BARREL.ch));
    try std.testing.expect(inked(DOOR.ch));
    try std.testing.expect(inked(CLEAR.ch));
}

test "floor shows through a wall's gaps; a tile with its own ground or background keeps it" {
    try std.testing.expectEqual(@as(?grid.Tile, .floor), under(.wall));
    try std.testing.expectEqual(@as(?grid.Tile, .grass), under(.shrub));
    try std.testing.expectEqual(@as(?grid.Tile, .dirt), under(.swamp_tree));
    try std.testing.expectEqual(@as(?grid.Tile, null), under(.rock));
    try std.testing.expectEqual(@as(?grid.Tile, null), under(.floor));
    try std.testing.expectEqual(@as(?grid.Tile, null), under(.water));
}
