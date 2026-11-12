const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const hero = @import("../play/hero.zig");
const attr = @import("../play/attrs.zig");
const inventory = @import("../play/inventory.zig");
const item_bases = @import("../play/item_bases.zig");
const damage = @import("../play/damage.zig");
const resilience = @import("../play/resilience.zig");
const progress = @import("../play/progress.zig");
const tactics = @import("../play/tactics.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const hud = @import("hud.zig");
const layout = @import("character_layout.zig");
const character_view = @import("character_view.zig");
const View = character_view.View;
const Vital = character_view.Vital;

const Figures = struct {
    attrs: attr.Attrs,
    dodge: u32,

    fn of(view: View) Figures {
        return .{ .attrs = view.stats(), .dodge = view.dodge() };
    }
};

const Measure = union(enum) {
    attribute: attr.Attr,
    reduction,
    weapon_crit,
    spell_crit,
    physical,
    element: damage.Element,
    dodge,
    block,
    style: attr.Style,
    thorns,
    gold_find,
    item_rarity,

    fn of(measure: Measure, figures: Figures) i32 {
        const attributes = figures.attrs;
        return switch (measure) {
            .attribute => |at| attributes.get(at),
            .reduction => attributes.reduction(),
            .weapon_crit => @intCast(attributes.critWith(attributes.weapon_crit_bonus)),
            .spell_crit => @intCast(attributes.critWith(attributes.spell_crit_bonus)),
            .physical => attributes.physical_bonus,
            .element => |e| attributes.element_bonus.get(e),
            .dodge => @intCast(figures.dodge),
            .block => @intCast(attributes.blockChance()),
            .style => |s| attributes.increase(s),
            .thorns => attributes.thorns,
            .gold_find => attributes.gold_find,
            .item_rarity => attributes.item_rarity,
        };
    }

    fn percent(measure: Measure) bool {
        return switch (measure) {
            .attribute, .thorns => false,
            .reduction, .weapon_crit, .spell_crit, .physical, .element, .dodge, .block, .style, .gold_find, .item_rarity => true,
        };
    }

    fn title(measure: Measure) [:0]const u8 {
        return switch (measure) {
            .attribute => |at| menu.named(at),
            .reduction => comptime menu.capital(attr.REDUCTION_LABEL),
            .weapon_crit => comptime menu.capital(attr.WEAPON_CRIT_LABEL),
            .spell_crit => comptime menu.capital(attr.SPELL_CRIT_LABEL),
            .physical => comptime menu.capital(attr.PHYSICAL_LABEL) ++ " bonus",
            .element => |e| switch (e) {
                inline else => |t| comptime menu.named(t) ++ " damage bonus",
            },
            .dodge => "Chance to dodge",
            .block => "Chance to block",
            .style => |s| s.label(),
            .thorns => "Physical thorns damage",
            .gold_find => "Gold collected bonus",
            .item_rarity => "Item rarity bonus",
        };
    }
};
const STAT_W = 440;
const STATS_X = 40;
const SECTION_RULE = 22;
const SECTION_ROWS = 32;
const STAT_ROW = font.BODY_LINE;
const TIGHT_ROW = font.SMALL + 2;
const HEADLINE = font.HEAD_LINE;
const HEADLINE_ROW = HEADLINE + 8;
const CHANCE_ROW = font.LABEL + 3;
const SECTION_GAP = 12;
const CRIT_GAP = 20;
const ROW_GAP = 16;
const CHANCE_GAP = 18;
const LEFT_FOOT = layout.FOOT_Y;
const RIGHT_FOOT = layout.ACTION_Y - SECTION_GAP;

const Tier = enum {
    headline,
    key,
    plain,

    fn size(t: Tier) i32 {
        return switch (t) {
            .headline => HEADLINE,
            .key => font.BODY,
            .plain => font.SMALL,
        };
    }

    fn put(t: Tier, face: *const font.Face, s: [:0]const u8, x: i32, y: i32, col: rl.Color) void {
        if (t == .plain) face.draw(s, x, y, t.size(), col) else face.engraved(s, x, y, t.size(), col);
    }

    fn label(t: Tier) Tier {
        return if (t == .headline) .key else t;
    }

    fn labelDrop(t: Tier) i32 {
        return @divTrunc((t.size() - t.label().size()) * 3, 4);
    }
};

fn quiet(n: i32, col: rl.Color) rl.Color {
    return if (n == 0) look.DIM else if (n < 0) look.LOSS else col;
}

const Part = struct { [:0]const u8, rl.Color };

/// One column of the sheet, top down; `dry` lays it out without drawing to check it fits.
const Column = struct {
    face: *const font.Face,
    x: i32,
    foot: i32,
    y: i32 = layout.CONTENT_TOP,
    dry: bool = false,
    cramped: bool = false,
    row: i32 = STAT_ROW,

    fn left(face: *const font.Face, dry: bool, row: i32) Column {
        return .{ .face = face, .x = STATS_X, .foot = LEFT_FOOT, .dry = dry, .row = row };
    }

    fn right(face: *const font.Face, dry: bool, row: i32) Column {
        return .{ .face = face, .x = layout.DETAIL_X, .foot = RIGHT_FOOT, .dry = dry, .row = row };
    }

    fn step(column: *const Column, tier: Tier) i32 {
        return if (tier == .headline) HEADLINE_ROW else column.row;
    }

    fn heading(column: *Column, title: [:0]const u8) void {
        if (!column.dry) {
            column.face.draw(title, column.x, column.y, font.SMALL, look.UI_FOCUS);
            rl.drawLine(column.x, column.y + SECTION_RULE, column.x + STAT_W, column.y + SECTION_RULE, look.EDGE);
        }
        column.y += SECTION_ROWS;
    }

    fn fits(column: *Column, w: i32) void {
        if (w > STAT_W) column.cramped = true;
    }

    fn entry(column: *Column, label: [:0]const u8, value: [:0]const u8, tier: Tier, col: rl.Color) void {
        column.line(label, &.{.{ value, col }}, tier);
    }

    fn line(column: *Column, label: [:0]const u8, parts: []const Part, tier: Tier) void {
        var w: i32 = 0;
        for (parts) |p| w += column.face.width(p[0], tier.size());
        column.fits(column.face.width(label, tier.label().size()) + ROW_GAP + w);
        if (!column.dry) {
            tier.label().put(column.face, label, column.x, column.y + tier.labelDrop(), look.TEXT);
            var at = column.x + STAT_W - w;
            for (parts) |p| {
                tier.put(column.face, p[0], at, column.y, p[1]);
                at += column.face.width(p[0], tier.size());
            }
        }
        column.y += column.step(tier);
    }

    fn amount(column: *Column, label: [:0]const u8, comptime fmt: []const u8, n: i32, ink: rl.Color) void {
        var text: menu.Note(48) = .{};
        text.say(fmt, .{n});
        column.entry(label, text.text(), .plain, quiet(n, ink));
    }

    fn stat(column: *Column, measure: Measure, figures: Figures, tier: Tier, col: rl.Color) void {
        var text: menu.Note(48) = .{};
        text.say("{s}{d}{s}", .{ if (measure == .style) "+" else "", measure.of(figures), if (measure.percent()) "%" else "" });
        column.entry(measure.title(), text.text(), tier, col);
    }

    fn vital(column: *Column, label: [:0]const u8, view: Vital, col: rl.Color) void {
        var text: menu.Note(32) = .{};
        text.say("{d} / {d}", .{ view.now, view.max });
        column.entry(label, text.text(), .headline, col);
    }

    fn skill(column: *Column, act: skillbar.Act, hit: progress.Hit, effect: item_bases.WeaponEffect) void {
        var physical: menu.Note(24) = .{};
        var element: menu.Note(40) = .{};
        if (hit.physical.hi > 0) physical.say("{d}-{d}", .{ hit.physical.lo, hit.physical.hi });
        if (hit.element) |e| element.say("{d}-{d} {s}", .{ e.lo, e.hi, menu.word(act.element().?) });
        var imbued: menu.Note(24) = .{};
        if (hit.imbued) |f| imbued.say("{d}-{d} {s}", .{ f.lo, f.hi, menu.word(tactics.Imbue.IMBUES) });
        const join: [:0]const u8 = if (physical.n > 0 and element.n > 0) " + " else "";
        const fire_join: [:0]const u8 = if (imbued.n > 0) " + " else "";
        column.line(act.name(), &.{
            .{ physical.text(), look.PHYSICAL },
            .{ join, look.DIM },
            .{ element.text(), look.arrowInk(act) },
            .{ fire_join, look.DIM },
            .{ imbued.text(), look.elementInk(tactics.Imbue.IMBUES) },
        }, .key);
        const chances = chancesOf(act, hit, effect);
        var any = false;
        var at = column.x;
        for (std.enums.values(resilience.Kind)) |k| {
            const pc = chances.get(k);
            if (pc == 0) continue;
            any = true;
            var text: menu.Note(32) = .{};
            text.say("{d}% {s}", .{ pc, menu.word(k) });
            if (!column.dry) column.face.draw(text.text(), at, column.y, font.LABEL, look.ailmentInk(k));
            at += column.face.width(text.text(), font.LABEL) + CHANCE_GAP;
        }
        if (!any) return;
        column.fits(at - CHANCE_GAP - column.x);
        column.y += CHANCE_ROW;
    }
};

/// Each ailment a hit may bring, the skill's own roll first and the weapon's only if that missed, as combat rolls them.
fn chancesOf(act: skillbar.Act, hit: progress.Hit, effect: item_bases.WeaponEffect) std.EnumArray(resilience.Kind, u32) {
    var out = std.EnumArray(resilience.Kind, u32).initFill(0);
    if (act.ailment()) |ail| out.set(ail.kind, ail.chance);
    if (hit.physical.hi > 0) {
        for (std.enums.values(resilience.Kind)) |k| {
            const skill = out.get(k);
            out.set(k, skill + ((mathx.PERCENT - skill) * effect.chance(k) + mathx.PERCENT / 2) / mathx.PERCENT);
        }
    }
    return out;
}

const DEFENCES = [_]Measure{ .reduction, .dodge, .block };
const PER_TURNS_FMT = "{d} / {d} turns";
const CRITS = [_]Measure{ .weapon_crit, .spell_crit };

fn sheet(face: *const font.Face, view: View, dry: bool) [2]Column {
    const figures = Figures.of(view);
    const attributes = figures.attrs;
    var left = Column.left(face, dry, STAT_ROW);
    left.heading("SURVIVAL");
    left.vital(hud.LIFE, view.life, look.LIFE_TEXT);
    left.vital(hud.MANA, view.mana, look.MANA_TEXT);
    for (DEFENCES) |measure| left.stat(measure, figures, .plain, look.TEXT);
    var note: menu.Note(100) = .{};
    left.y += SECTION_GAP;
    left.heading("ATTRIBUTES");
    for (attr.ATTRS) |at| {
        left.stat(.{ .attribute = at }, figures, .key, look.TEXT);
    }
    left.y += SECTION_GAP;
    left.heading("PROGRESSION");
    note.say("{d} passive, {d} skill", .{ view.growth.passive_points, view.growth.active_points });
    left.entry("Unspent points", note.text(), .plain, quiet(@as(i32, view.growth.passive_points) + view.growth.active_points, look.UI_FOCUS));
    var gold: menu.Note(24) = .{};
    gold.say("{d}", .{view.gold});
    left.entry("Gold", gold.text(), .plain, look.LEVEL_GOLD);

    var right = Column.right(face, dry, STAT_ROW);
    right.heading("DAMAGE");
    for (skillbar.kit(view.class)) |act| if (act.attack() != null and act.supplyOf() == null and view.growth.unlocked(act)) {
        right.skill(act, view.growth.preparedHit(attributes, view.inventory.gear, act, view.readied).?, view.growth.onHit(view.inventory.gear, act.attack().?, view.readied));
    };
    right.y += CRIT_GAP;
    for (CRITS) |measure| right.stat(measure, figures, .plain, look.TEXT);
    return .{ left, right };
}

fn advancedSheet(face: *const font.Face, view: View, dry: bool) [2]Column {
    const figures = Figures.of(view);
    const attributes = figures.attrs;
    var left = Column.left(face, dry, TIGHT_ROW);
    left.heading("DAMAGE MODIFIERS");
    for (attr.STYLES) |s| left.stat(.{ .style = s }, figures, .plain, quiet(attributes.increase(s), look.TEXT));
    left.stat(.physical, figures, .plain, quiet(attributes.physical_bonus, look.PHYSICAL));
    for (std.enums.values(damage.Element)) |e| left.stat(.{ .element = e }, figures, .plain, quiet(attributes.element_bonus.get(e), look.elementInk(e)));
    var text: menu.Note(48) = .{};
    text.say("{d}%", .{attributes.critMulti()});
    left.entry("Critical damage multiplier", text.text(), .plain, look.TEXT);
    left.stat(.thorns, figures, .plain, quiet(attributes.thorns, look.PHYSICAL));
    left.y += SECTION_GAP;
    left.heading("RECOVERY AND LOOT");
    const perks = view.inventory.gear.perks(view.growth.perks());
    text.say(PER_TURNS_FMT, .{ hero.manaRegen(perks), hero.MANA_REGEN_TURNS });
    left.entry("Mana recovery", text.text(), .plain, look.MANA_TEXT);
    const mending = view.inventory.gear.lifeRegen();
    text.say(PER_TURNS_FMT, .{ mending, hero.LIFE_REGEN_TURNS });
    left.entry("Life recovery", text.text(), .plain, quiet(mending, look.LIFE_TEXT));
    left.amount("Life on hit", "{d}", perks.life_on_hit, look.LIFE_TEXT);
    left.amount("Damage leeched as life", "{d}%", view.inventory.gear.leech(), look.LIFE_TEXT);
    left.amount("Life on kill", "{d}", perks.life_on_kill, look.LIFE_TEXT);
    left.amount("Life flask recovery", "+{d}%", perks.life_flask, look.LIFE_TEXT);
    left.amount("Mana on kill", "{d}", view.inventory.gear.manaOnKill(), look.MANA_TEXT);
    left.amount("Mana flask recovery", "+{d}%", view.inventory.gear.draughts(perks).mana, look.MANA_TEXT);
    left.stat(.gold_find, figures, .plain, quiet(attributes.gold_find, look.UI_GOLD));
    left.stat(.item_rarity, figures, .plain, quiet(attributes.item_rarity, look.MAGIC));

    var right = Column.right(face, dry, TIGHT_ROW);
    right.heading("RESISTANCES");
    for (std.enums.values(damage.Element)) |e| right.amount(resistanceLabel(e), "{d}%", view.resists.get(e), look.elementInk(e));
    right.y += SECTION_GAP;
    right.heading("STATUS RESISTANCE");
    for (std.enums.values(resilience.Kind)) |k| {
        const measure = view.status_resist.get(k);
        if (measure.turns > 0) text.say("{d}%, {d} turn{s}", .{ measure.percent, measure.turns, mathx.plural(measure.turns) }) else text.say("{d}%", .{measure.percent});
        right.entry(resistanceLabel(k), text.text(), .plain, quiet(measure.percent, look.ailmentInk(k)));
    }
    var groups_width: i32 = 0;
    for (@import("keywords.zig").STATUS_TERMS) |term| groups_width += face.width(term.title, font.SMALL) + 18;
    right.fits(groups_width);
    right.y += font.SMALL;
    return .{ left, right };
}

fn resistanceLabel(e: anytype) [:0]const u8 {
    return switch (e) {
        inline else => |t| comptime menu.named(t) ++ " resistance",
    };
}

pub fn draw(face: *const font.Face, view: View) void {
    _ = sheet(face, view, false);
}

pub fn drawAdvanced(face: *const font.Face, view: View, on: menu.Surface) void {
    const keywords = @import("keywords.zig");
    const cols = advancedSheet(face, view, false);
    const y = cols[1].y - font.SMALL;
    var x = cols[1].x;
    for (keywords.STATUS_TERMS) |term| {
        if (view.keywords) |links| {
            links.text(face, term.title, x, y, font.SMALL, look.UI_FOCUS, &.{term}, on);
        } else face.text(term.title, x, y, font.SMALL, look.UI_FOCUS);
        x += face.width(term.title, font.SMALL) + 18;
    }
}

pub fn verify(face: *const font.Face) !void {
    var checked: usize = 0;
    for (hero.CLASSES) |class| {
        var growth = progress.State.of(class);
        for (progress.skills(class)) |s| growth.ranks.set(s.act, progress.RANKS);
        var inv = inventory.Inventory{};
        inv.gear.slots.set(.right_hand, .{ .kind = .axe });
        var view = View{ .class = class, .name = "", .inventory = &inv, .growth = &growth, .base = growth.attributes(class) };
        view.life = .{ .now = 999, .max = 999 };
        view.mana = .{ .now = 999, .max = 999 };
        for (std.enums.values(resilience.Kind)) |k| view.status_resist.set(k, .{ .percent = 100, .turns = resilience.EXPIRY });
        for ([_][2]Column{ sheet(face, view, true), advancedSheet(face, view, true) }) |cols| {
            for (cols) |col| {
                if (col.cramped or col.y > col.foot) {
                    std.debug.print("stats overflow {s}: column at x {d} reaches {d} of {d}, cramped {}\n", .{ @tagName(class), col.x, col.y, col.foot, col.cramped });
                    return error.StatsOverflow;
                }
                checked += 1;
            }
        }
    }
    std.debug.print("stats typography: {d} columns fit, main and advanced, every class fully learned\n", .{checked});
}

test "a skill's status chances combine its own roll with the weapon's second roll" {
    const bash = chancesOf(.shield_bash, .{ .physical = .{ .lo = 1, .hi = 2 }, .element = null, .style = .heavy }, .{ .stun = 20, .bleed = 10 });
    try std.testing.expectEqual(@as(u32, 60), bash.get(.stun));
    try std.testing.expectEqual(@as(u32, 10), bash.get(.bleed));
    const spark = chancesOf(.spark, .{ .physical = .{ .lo = 0, .hi = 0 }, .element = .{ .lo = 1, .hi = 3 }, .style = .spell }, .{ .stun = 20 });
    try std.testing.expectEqual(@as(u32, 50), spark.get(.stun));
}
