const std = @import("std");
const rl = @import("raylib");
const attr = @import("../play/attrs.zig");
const items = @import("../play/items.zig");
const damage = @import("../play/damage.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const layout = @import("character_layout.zig");
const consumable = @import("../play/consumable.zig");
const skillbar = @import("../play/skillbar.zig");

pub const TWO_HANDED = "Two-handed";
pub const ONE_HANDED = "One-handed";
pub const EMPTY_SLOT = "Empty slot";
pub const CONSUMABLE = "Consumable";

const CARD_LINE = font.SMALL_LINE;
/// Down from a card's top: its rule, name (or "Empty slot"), slot and first stat line.
const CARD_RULE = 20;
const CARD_NAME = 32;
const CARD_EMPTY = 35;
pub const SLOT_Y = 84;
const SLOT_STATS_GAP = 11;
const CARD_STATS = SLOT_Y + font.LABEL + SLOT_STATS_GAP;
/// Above and below the modifiers' rule, and its inset from the card's sides.
const MODS_ABOVE = 6;
const MODS_BELOW = 10;
const MODS_INSET = 0;

const CardLine = union(enum) {
    damage: damage.Base,
    unarmed,
    armour: i16,
    innate: items.Innate,
    requires: struct { at: attr.Attr, n: i32, available: i32, met: bool },

    fn text(line: CardLine, out: *menu.Note(120)) [:0]const u8 {
        switch (line) {
            .damage => |hit| out.say(damage.PHYSICAL_FMT, .{ hit.lo, hit.hi }),
            .unarmed => return "No weapon damage",
            .armour => |n| out.say("{d}% " ++ attr.REDUCTION_LABEL, .{n}),
            .innate => |innate| {
                out.clear();
                innate.write(out.writer());
            },
            .requires => |r| if (r.met) out.say("Requires {d} {s}", .{ r.n, menu.named(r.at) }) else out.say("Requires {d} {s} ({d} available)", .{ r.n, menu.named(r.at), r.available }),
        }
        return out.text();
    }

    fn size(line: CardLine) i32 {
        return switch (line) {
            .requires, .unarmed => font.LABEL,
            .damage, .armour, .innate => font.SMALL,
        };
    }

    fn ink(line: CardLine) rl.Color {
        return switch (line) {
            .damage, .armour, .innate => look.TEXT,
            .unarmed => look.DIM,
            .requires => |r| if (r.met) look.DIM else layout.LOSS,
        };
    }
};

const CardLines = struct {
    all: [std.meta.fields(CardLine).len - 1 + attr.ATTRS.len]CardLine = undefined,
    n: usize = 0,

    fn add(self: *CardLines, line: CardLine) void {
        self.all[self.n] = line;
        self.n += 1;
    }

    /// `spec`'s lines for `slot`; with no `available`, every requirement is unmet by one, the most and widest lines it can have.
    fn of(spec: items.Spec, slot: items.Slot, available: ?attr.Attrs) CardLines {
        var out: CardLines = .{};
        if (spec.damage) |hit| {
            out.add(.{ .damage = hit });
        } else if (slot == .right_hand) out.add(.unarmed);
        if (spec.armour > 0) out.add(.{ .armour = spec.armour });
        if (spec.innate) |innate| {
            out.add(.{ .innate = innate });
        }
        inline for (attr.ATTRS) |at| {
            const required = @field(spec.needs, @tagName(at));
            if (required > 0) {
                const met = if (available) |a| a.get(at) >= required else false;
                out.add(.{ .requires = .{ .at = at, .n = required, .met = met, .available = if (available) |a| a.get(at) else required - 1 } });
            }
        }
        return out;
    }

    fn lines(self: *const CardLines) []const CardLine {
        return self.all[0..self.n];
    }
};

/// Down from a card's top to the foot of its last line, as `draw` lays out `lines` stat lines and `mods` modifiers.
fn footOf(lines: usize, mods: usize) i32 {
    const n: i32 = @intCast(lines);
    const m: i32 = @intCast(mods);
    return CARD_STATS + n * CARD_LINE + (if (m > 0) MODS_ABOVE + MODS_BELOW + m * CARD_LINE else 0);
}

/// Down from a card's top to the foot of what `draw` lays out for `maybe` in `slot`.
pub fn height(maybe: ?items.Item, slot: items.Slot) i32 {
    const item = maybe orelse return SLOT_Y + font.LABEL;
    var shown: Mods = undefined;
    return footOf(CardLines.of(items.spec(item.kind), slot, null).n, if (item.magical()) modsOf(item, &shown).len else 0);
}

const Mods = [items.MODS.len]items.Mod;

/// The modifier kinds a magical card lists for `item`, one line each, in `items.MODS` order.
fn modsOf(item: items.Item, out: *Mods) []const items.Mod {
    var n: usize = 0;
    for (items.MODS) |m| if (item.value(m) != 0) {
        out[n] = m;
        n += 1;
    };
    return out[0..n];
}

comptime {
    const mods = items.AFFIXES_MAX;
    for (std.enums.values(items.Kind)) |k| {
        const s = items.spec(k);
        for (s.slots) |slot| {
            if (footOf(CardLines.of(s, slot, null).n, mods) > layout.CARD_H) @compileError(s.name ++ "'s card can run past CARD_H");
        }
    }
}

fn head(face: *const font.Face, x: i32, y: i32, width: i32, caption: ?[:0]const u8) void {
    if (caption) |c| face.draw(c, x, y, font.LABEL, look.DIM);
    rl.drawLine(x, y + CARD_RULE, x + width, y + CARD_RULE, look.EDGE);
}

pub fn drawSupply(face: *const font.Face, x: i32, y: i32, width: i32, k: consumable.Kind, carried: u8, caption: ?[:0]const u8) void {
    head(face, x, y, width, caption);
    _ = face.paragraph(menu.named(k), x, y + CARD_NAME, width, font.BODY, look.itemInk(.normal));
    face.draw(CONSUMABLE, x, y + SLOT_Y, font.LABEL, look.DIM);
    const act = skillbar.Act.ofSupply(k);
    const top = face.paragraph(act.desc(), x, y + CARD_STATS, width, font.SMALL, look.TEXT);
    var line: menu.Note(40) = .{};
    line.say("{d} carried, 1 turn to use", .{carried});
    face.draw(line.text(), x, top + MODS_BELOW, font.LABEL, look.DIM);
}

pub fn draw(face: *const font.Face, x: i32, y: i32, width: i32, maybe: ?items.Item, slot: items.Slot, available: attr.Attrs, caption: ?[:0]const u8) void {
    head(face, x, y, width, caption);
    const item = maybe orelse {
        face.draw(EMPTY_SLOT, x, y + CARD_EMPTY, font.BODY, look.DIM);
        face.draw(slot.name(), x, y + SLOT_Y, font.LABEL, look.DIM);
        return;
    };
    const spec = items.spec(item.kind);
    const ink = look.itemInk(item.rarity());
    var name_buf: [items.NAME_MAX]u8 = undefined;
    _ = face.paragraph(item.name(&name_buf), x, y + CARD_NAME, width, font.BODY, ink);
    if (item.rarity() == .rare) face.draw(menu.namedOr(item.kind, spec.name), x, y + CARD_NAME + font.BODY_LINE, font.LABEL, look.TEXT);
    var metadata: menu.Note(100) = .{};
    const slot_name = if (slot == .right_hand) (if (spec.two_handed) TWO_HANDED else ONE_HANDED) else slot.name();
    if (spec.damage != null) metadata.say("{s}  /  {s}", .{ slot_name, menu.named(spec.style.attr()) }) else metadata.say("{s}", .{slot_name});
    face.draw(metadata.text(), x, y + SLOT_Y, font.LABEL, look.DIM);
    var top = y + CARD_STATS;
    var text: menu.Note(120) = .{};
    const stats = CardLines.of(spec, slot, available);
    for (stats.lines()) |line| {
        face.draw(line.text(&text), x, top, line.size(), line.ink());
        top += CARD_LINE;
    }
    if (item.magical()) {
        top += MODS_ABOVE;
        rl.drawLine(x + MODS_INSET, top, x + width - MODS_INSET, top, look.EDGE);
        top += MODS_BELOW;
        var shown: Mods = undefined;
        for (modsOf(item, &shown)) |m| {
            text.clear();
            for (item.mods) |rolled| if (rolled) |a| {
                if (a.kind == m) a.write(text.writer());
            };
            face.draw(text.text(), x, top, font.SMALL, ink);
            top += CARD_LINE;
        }
    }
}

pub fn verify(face: *const font.Face) !void {
    var count: usize = 0;
    var text: menu.Note(120) = .{};
    for (std.enums.values(items.Kind)) |kind| {
        const spec = items.spec(kind);
        for (spec.slots) |slot| {
            const rows = CardLines.of(spec, slot, null);
            for (rows.lines()) |line| {
                const value = line.text(&text);
                if (face.width(value, line.size()) > layout.CARD_W) {
                    std.debug.print("card overflow {s}: {s}\n", .{ spec.name, value });
                    return error.ItemCardOverflow;
                }
                count += 1;
            }
        }
    }
    std.debug.print("item typography: {d} property and requirement rows fit {d}px comparison cards\n", .{ count, layout.CARD_W });
    for (items.MODS) |mod| {
        text.clear();
        (items.Affix{ .kind = mod, .value = 25 }).write(text.writer());
        if (face.width(text.text(), font.SMALL) > layout.CARD_W) {
            std.debug.print("affix overflow: {s}\n", .{text.text()});
            return error.ItemCardOverflow;
        }
    }
    var rare_buf: [items.NAME_MAX]u8 = undefined;
    for (std.enums.values(items.RareName.First)) |first| {
        for (std.enums.values(items.RareName.Last)) |last| {
            const name = (items.RareName{ .first = first, .last = last }).name(&rare_buf);
            if (face.width(name, font.BODY) > layout.CARD_W) return error.ItemCardOverflow;
        }
    }
}
