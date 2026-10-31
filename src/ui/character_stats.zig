const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const hero = @import("../play/hero.zig");
const attr = @import("../play/attrs.zig");
const items = @import("../play/items.zig");
const damage = @import("../play/damage.zig");
const resilience = @import("../play/resilience.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const hud = @import("hud.zig");
const layout = @import("character_layout.zig");
const character_view = @import("character_view.zig");
const View = character_view.View;
const Vital = character_view.Vital;

/// What the sheet reads: the view's attributes, with combat's own dodge.
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
            .style => |s| attributes.increase(s),
            .thorns => attributes.thorns,
            .gold_find => attributes.gold_find,
            .item_rarity => attributes.item_rarity,
        };
    }

    fn percent(measure: Measure) bool {
        return switch (measure) {
            .attribute, .thorns => false,
            .reduction, .weapon_crit, .spell_crit, .physical, .element, .dodge, .style, .gold_find, .item_rarity => true,
        };
    }

    /// Its Stats page row.
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
            .style => |s| s.label(),
            .thorns => "Physical thorns damage",
            .gold_find => "Gold collected bonus",
            .item_rarity => "Item rarity bonus",
        };
    }
};
const STAT_W = 440;
const STATS_X = 40;
/// A section's title to its rule and to its first row, and row to row.
const SECTION_RULE = 22;
const SECTION_ROWS = 32;
const STAT_ROW = font.BODY_LINE;
const HEADLINE = font.HEAD + 4;
const HEADLINE_ROW = HEADLINE + 8;
const CHANCE_ROW = font.LABEL + 3;
const SECTION_GAP = 12;
const CRIT_GAP = 20;
/// Between a row's label and its value, at the least.
const ROW_GAP = 16;
/// Between one skill's chances to afflict.
const CHANCE_GAP = 18;
/// The lowest a column may reach: the right one stops above the actions.
const LEFT_FOOT = layout.FOOT_Y;
const RIGHT_FOOT = layout.ACTION_Y - SECTION_GAP;

/// The sheet's type, fanciest first: what the player came to read, then what builds it, then the rest.
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

    fn step(t: Tier) i32 {
        return if (t == .headline) HEADLINE_ROW else STAT_ROW;
    }

    /// The display face engraved for the first two, the data face for the rest.
    fn put(t: Tier, face: *const font.Face, s: [:0]const u8, x: i32, y: i32, col: rl.Color) void {
        if (t == .plain) face.draw(s, x, y, t.size(), col) else face.engraved(s, x, y, t.size(), col);
    }

    fn label(t: Tier) Tier {
        return if (t == .headline) .key else t;
    }

    /// Its label beside its value shares their baseline.
    fn labelDrop(t: Tier) i32 {
        return @divTrunc((t.size() - t.label().size()) * 3, 4);
    }
};

/// Nothing to read in a zero, so it recedes.
fn quiet(n: i32, col: rl.Color) rl.Color {
    return if (n == 0) look.DIM else if (n < 0) look.LOSS else col;
}

/// One column of the sheet, top down; `dry` lays it out without drawing to check it fits.
const Column = struct {
    face: *const font.Face,
    x: i32,
    y: i32 = layout.CONTENT_TOP,
    dry: bool = false,
    cramped: bool = false,

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
        column.fits(column.face.width(label, tier.label().size()) + ROW_GAP + column.face.width(value, tier.size()));
        if (!column.dry) {
            tier.label().put(column.face, label, column.x, column.y + tier.labelDrop(), look.TEXT);
            tier.put(column.face, value, column.x + STAT_W - column.face.width(value, tier.size()), column.y, col);
        }
        column.y += tier.step();
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

    /// A skill's name, then its hit coloured part by part, then what it may afflict.
    fn skill(column: *Column, act: skillbar.Act, hit: progress.Hit, effect: items.WeaponEffect) void {
        var physical: menu.Note(24) = .{};
        var element: menu.Note(40) = .{};
        if (hit.physical.hi > 0) physical.say("{d}-{d}", .{ hit.physical.lo, hit.physical.hi });
        if (hit.element) |e| element.say("{d}-{d} {s}", .{ e.lo, e.hi, menu.word(act.element().?) });
        const join: [:0]const u8 = if (physical.n > 0 and element.n > 0) " + " else "";
        const parts = [_]struct { [:0]const u8, rl.Color }{
            .{ physical.text(), look.PHYSICAL },
            .{ join, look.DIM },
            .{ element.text(), look.arrowInk(act) },
        };
        const tier = Tier.key;
        var w: i32 = 0;
        for (parts) |p| w += column.face.width(p[0], tier.size());
        column.fits(column.face.width(act.name(), tier.label().size()) + ROW_GAP + w);
        if (!column.dry) {
            tier.label().put(column.face, act.name(), column.x, column.y + tier.labelDrop(), look.TEXT);
            var at = column.x + STAT_W - w;
            for (parts) |p| {
                tier.put(column.face, p[0], at, column.y, p[1]);
                at += column.face.width(p[0], tier.size());
            }
        }
        column.y += tier.step();
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
fn chancesOf(act: skillbar.Act, hit: progress.Hit, effect: items.WeaponEffect) std.EnumArray(resilience.Kind, u32) {
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

const DEFENCES = [_]Measure{ .reduction, .dodge };
const CRITS = [_]Measure{ .weapon_crit, .spell_crit };

/// What the player reads at a glance: life, mana and each skill's hit, then what builds them.
fn sheet(face: *const font.Face, view: View, dry: bool) [2]Column {
    const figures = Figures.of(view);
    const attributes = figures.attrs;
    var left = Column{ .face = face, .x = STATS_X, .dry = dry };
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

    var right = Column{ .face = face, .x = layout.DETAIL_X, .dry = dry };
    right.heading("DAMAGE");
    for (skillbar.kit(view.class)) |act| if (act.attack() != null and act.supplyOf() == null and view.growth.unlocked(act)) {
        right.skill(act, view.growth.preparedHit(attributes, view.inventory.gear, act, view.steady).?, view.inventory.gear.onHit(act.attack().?));
    };
    right.y += CRIT_GAP;
    for (CRITS) |measure| right.stat(measure, figures, .plain, look.TEXT);
    return .{ left, right };
}

/// D2's Advanced Stats: every bonus, recovery and resistance, zeros included.
fn advancedSheet(face: *const font.Face, view: View, dry: bool) [2]Column {
    const figures = Figures.of(view);
    const attributes = figures.attrs;
    var left = Column{ .face = face, .x = STATS_X, .dry = dry };
    left.heading("DAMAGE MODIFIERS");
    for (attr.STYLES) |s| left.stat(.{ .style = s }, figures, .plain, quiet(attributes.increase(s), look.TEXT));
    left.stat(.physical, figures, .plain, quiet(attributes.physical_bonus, look.PHYSICAL));
    for (std.enums.values(damage.Element)) |e| left.stat(.{ .element = e }, figures, .plain, quiet(attributes.element_bonus.get(e), look.elementInk(e)));
    var text: menu.Note(48) = .{};
    text.say("{d}%", .{attr.CRIT_MULTI});
    left.entry("Critical damage multiplier", text.text(), .plain, look.TEXT);
    left.stat(.thorns, figures, .plain, quiet(attributes.thorns, look.PHYSICAL));
    left.y += SECTION_GAP;
    left.heading("RECOVERY AND LOOT");
    const perks = view.inventory.gear.perks(view.growth.perks());
    text.say("{d} / {d} turns", .{ hero.manaRegen(perks), hero.MANA_REGEN_TURNS });
    left.entry("Mana recovery", text.text(), .plain, look.MANA_TEXT);
    text.say("{d}", .{perks.life_on_hit});
    left.entry("Life on hit", text.text(), .plain, quiet(perks.life_on_hit, look.LIFE_TEXT));
    text.say("{d}", .{perks.life_on_kill});
    left.entry("Life on kill", text.text(), .plain, quiet(perks.life_on_kill, look.LIFE_TEXT));
    text.say("+{d}%", .{perks.life_flask});
    left.entry("Life flask recovery", text.text(), .plain, quiet(perks.life_flask, look.LIFE_TEXT));
    left.stat(.gold_find, figures, .plain, quiet(attributes.gold_find, look.UI_GOLD));
    left.stat(.item_rarity, figures, .plain, quiet(attributes.item_rarity, look.MAGIC));

    var right = Column{ .face = face, .x = layout.DETAIL_X, .dry = dry };
    right.heading("RESISTANCES");
    for (std.enums.values(damage.Element)) |e| {
        const n = view.resists.get(e);
        text.say("{d}%", .{n});
        right.entry(resistanceLabel(e), text.text(), .plain, quiet(n, look.elementInk(e)));
    }
    right.y += SECTION_GAP;
    right.heading("STATUS RESISTANCE");
    for (std.enums.values(resilience.Kind)) |k| {
        const measure = view.status_resist.get(k);
        if (measure.turns > 0) text.say("{d}%, {d} turn{s}", .{ measure.percent, measure.turns, mathx.plural(measure.turns) }) else text.say("{d}%", .{measure.percent});
        right.entry(resistanceLabel(k), text.text(), .plain, quiet(measure.percent, look.ailmentInk(k)));
    }
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

pub fn drawAdvanced(face: *const font.Face, view: View) void {
    _ = advancedSheet(face, view, false);
}

/// Every class with every skill learned keeps both sheets' rows inside their columns and above the actions.
pub fn verify(face: *const font.Face) !void {
    var checked: usize = 0;
    for (hero.CLASSES) |class| {
        var growth = progress.State.of(class);
        for (progress.skills(class)) |s| growth.ranks.set(s.act, progress.RANKS);
        var inv = items.Inventory{};
        inv.gear.slots.set(.right_hand, .{ .kind = .axe });
        var view = View{ .class = class, .name = "", .inventory = &inv, .growth = &growth, .base = growth.attributes(class) };
        view.life = .{ .now = 999, .max = 999 };
        view.mana = .{ .now = 999, .max = 999 };
        for (std.enums.values(resilience.Kind)) |k| view.status_resist.set(k, .{ .percent = 100, .turns = resilience.EXPIRY });
        for ([_][2]Column{ sheet(face, view, true), advancedSheet(face, view, true) }) |cols| {
            for (cols, [_]i32{ LEFT_FOOT, RIGHT_FOOT }) |col, foot| {
                if (col.cramped or col.y > foot) {
                    std.debug.print("stats overflow {s}: column at x {d} reaches {d} of {d}, cramped {}\n", .{ @tagName(class), col.x, col.y, foot, col.cramped });
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
    std.debug.print("status chances: bash 50% + mace 20% = {d}% stun; pure lightning ignores the weapon at {d}%\n", .{ bash.get(.stun), spark.get(.stun) });
}
