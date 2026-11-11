const std = @import("std");
const rl = @import("raylib");
const attr = @import("../play/attrs.zig");
const affixes = @import("../play/affixes.zig");
const item_bases = @import("../play/item_bases.zig");
const items = @import("../play/items.zig");
const damage = @import("../play/damage.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const layout = @import("character_layout.zig");
const consumable = @import("../play/consumable.zig");
const skillbar = @import("../play/skillbar.zig");

const TWO_HANDED = "Two-handed";
const ONE_HANDED = "One-handed";
pub const EMPTY_SLOT = "Empty slot";
const CONSUMABLE = "Consumable";
pub const CARRIED_FMT = "{d} carried";

const CARD_LINE = font.SMALL_LINE;
const CARD_RULE = 20;
const CARD_NAME = 32;
const CARD_EMPTY = 35;
const SLOT_Y = 84;
const SLOT_STATS_GAP = 11;
const CARD_STATS = SLOT_Y + font.LABEL + SLOT_STATS_GAP;
const MODS_ABOVE = 6;
const MODS_BELOW = 10;
const CardText = menu.Note(120);

const CardLine = union(enum) {
    damage: damage.Base,
    unarmed,
    armour: i16,
    block: i16,
    innate: item_bases.Innate,
    requires: struct { at: attr.Attr, n: i32, available: i32, met: bool },

    fn text(line: CardLine, out: *CardText) [:0]const u8 {
        switch (line) {
            .damage => |hit| out.say(damage.PHYSICAL_FMT, .{ hit.lo, hit.hi }),
            .unarmed => return "No weapon damage",
            .armour => |n| out.say("{d}% " ++ attr.REDUCTION_LABEL, .{n}),
            .block => |n| out.say(item_bases.BLOCK_FMT[1..], .{n}),
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
            .damage, .armour, .block, .innate => font.SMALL,
        };
    }

    fn ink(line: CardLine) rl.Color {
        return switch (line) {
            .damage, .armour, .block, .innate => look.TEXT,
            .unarmed => look.DIM,
            .requires => |r| if (r.met) look.DIM else look.LOSS,
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
    fn of(spec: item_bases.Spec, slot: item_bases.Slot, available: ?attr.Attrs) CardLines {
        var out: CardLines = .{};
        if (spec.damage) |hit| {
            out.add(.{ .damage = hit });
        } else if (slot == .right_hand) out.add(.unarmed);
        if (spec.armour > 0) out.add(.{ .armour = spec.armour });
        if (spec.block > 0) out.add(.{ .block = spec.block });
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

fn footOf(lines: usize, mods: usize) i32 {
    const n: i32 = @intCast(lines);
    const m: i32 = @intCast(mods);
    return CARD_STATS + n * CARD_LINE + (if (m > 0) MODS_ABOVE + MODS_BELOW + m * CARD_LINE else 0);
}

pub fn height(face: *const font.Face, width: i32, maybe: ?items.Item, slot: item_bases.Slot) i32 {
    const item = maybe orelse return SLOT_Y + font.LABEL;
    var shown: Mods = undefined;
    var rows: usize = 0;
    var text: CardText = .{};
    if (item.magical()) for (modsOf(item, &shown)) |m| {
        rows += wrappedRows(face, modifierText(item, m, &text), width);
    };
    return footOf(CardLines.of(item_bases.spec(item.kind), slot, null).n, rows);
}

fn modifierText(item: items.Item, mod: affixes.Mod, text: *CardText) [:0]const u8 {
    text.clear();
    for (item.mods) |rolled| if (rolled) |a| {
        if (a.kind == mod) a.write(text.writer());
    };
    return text.text();
}

fn wrappedRows(face: *const font.Face, text: []const u8, width: i32) usize {
    return font.lineCount(face, text, font.SMALL, width);
}

const Mods = [affixes.MODS.len]affixes.Mod;

fn modsOf(item: items.Item, out: *Mods) []const affixes.Mod {
    var n: usize = 0;
    for (affixes.MODS) |m| if (item.value(m) != 0) {
        out[n] = m;
        n += 1;
    };
    return out[0..n];
}

comptime {
    const mods = affixes.AFFIXES_MAX;
    for (std.enums.values(item_bases.Kind)) |k| {
        const s = item_bases.spec(k);
        for (s.slots) |slot| {
            if (footOf(CardLines.of(s, slot, null).n, mods) > layout.CARD_H) @compileError(s.name ++ "'s card can run past CARD_H");
        }
    }
}

fn head(face: *const font.Face, x: i32, y: i32, width: i32, caption: ?[:0]const u8) void {
    if (caption) |c| face.draw(c, x, y, font.LABEL, look.DIM);
    rule(x, y + CARD_RULE, width);
}

fn rule(x: i32, y: i32, width: i32) void {
    rl.drawLine(x, y, x + width, y, look.EDGE);
}

pub fn drawSupply(face: *const font.Face, x: i32, y: i32, width: i32, k: consumable.Kind, carried: u8, caption: ?[:0]const u8) void {
    head(face, x, y, width, caption);
    _ = face.paragraph(menu.named(k), x, y + CARD_NAME, width, font.BODY, look.itemInk(.normal));
    face.draw(CONSUMABLE, x, y + SLOT_Y, font.LABEL, look.DIM);
    const act = skillbar.Act.ofSupply(k);
    const top = face.paragraph(act.desc(), x, y + CARD_STATS, width, font.SMALL, look.TEXT);
    var line: menu.Note(40) = .{};
    line.say(CARRIED_FMT ++ ", 1 turn to use", .{carried});
    face.draw(line.text(), x, top + MODS_BELOW, font.LABEL, look.DIM);
}

pub fn draw(face: *const font.Face, x: i32, y: i32, width: i32, maybe: ?items.Item, slot: item_bases.Slot, available: attr.Attrs, caption: ?[:0]const u8) void {
    head(face, x, y, width, caption);
    const item = maybe orelse {
        face.draw(EMPTY_SLOT, x, y + CARD_EMPTY, font.BODY, look.DIM);
        face.draw(slot.name(), x, y + SLOT_Y, font.LABEL, look.DIM);
        return;
    };
    const spec = item_bases.spec(item.kind);
    const ink = look.itemInk(item.rarity());
    var name_buf: [items.NAME_MAX]u8 = undefined;
    _ = face.paragraph(item.name(&name_buf), x, y + CARD_NAME, width, font.BODY, ink);
    var base_buf: [items.NAME_MAX]u8 = undefined;
    if (item.rarity() == .rare) face.draw(items.baseName(item.kind, &base_buf), x, y + CARD_NAME + font.BODY_LINE, font.LABEL, look.TEXT);
    var metadata: menu.Note(100) = .{};
    const slot_name = if (slot == .right_hand) (if (spec.two_handed) TWO_HANDED else ONE_HANDED) else slot.name();
    if (spec.damage != null) metadata.say("{s}  /  {s}", .{ slot_name, menu.named(spec.style.attr()) }) else metadata.say("{s}", .{slot_name});
    face.draw(metadata.text(), x, y + SLOT_Y, font.LABEL, look.DIM);
    var top = y + CARD_STATS;
    var text: CardText = .{};
    const stats = CardLines.of(spec, slot, available);
    for (stats.lines()) |line| {
        face.draw(line.text(&text), x, top, line.size(), line.ink());
        top += CARD_LINE;
    }
    if (item.magical()) {
        top += MODS_ABOVE;
        rule(x, top, width);
        top += MODS_BELOW;
        var shown: Mods = undefined;
        for (modsOf(item, &shown)) |m| {
            top = face.paragraph(modifierText(item, m, &text), x, top, width, font.SMALL, ink);
        }
    }
}

pub fn verify(face: *const font.Face) !void {
    try verifyFace(face);
    const scaled = face.mipmapped();
    try verifyFace(&scaled);
}

fn verifyFace(face: *const font.Face) !void {
    var count: usize = 0;
    var text: CardText = .{};
    for (std.enums.values(item_bases.Kind)) |kind| {
        const spec = item_bases.spec(kind);
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
    for ([_]i32{ layout.CARD_W, layout.DETAIL_W }) |width| {
        var rows: [affixes.MODS.len]usize = @splat(0);
        for (affixes.AFFIXES, &rows) |roll, *most| {
            for (std.enums.values(damage.Element)) |element| {
                var value = roll.lo;
                while (value <= roll.hi) : (value += 1) {
                    text.clear();
                    (affixes.Affix{ .kind = roll.kind, .value = @intCast(value), .element = element }).write(text.writer());
                    most.* = @max(most.*, wrappedRows(face, text.text(), width));
                }
            }
        }
        for (std.enums.values(item_bases.Kind)) |kind| {
            var largest: [affixes.AFFIXES_MAX]usize = @splat(0);
            for (affixes.MODS, rows) |mod, n| {
                if (!mod.allows(kind)) continue;
                var left = n;
                for (&largest) |*row| if (left > row.*) {
                    std.mem.swap(usize, &left, row);
                };
            }
            var total: usize = 0;
            for (largest) |n| total += n;
            for (item_bases.spec(kind).slots) |slot| {
                const foot = footOf(CardLines.of(item_bases.spec(kind), slot, null).n, total);
                if (foot > layout.CARD_H) {
                    std.debug.print("wrapped card overflow {s}: {d}px at {d}px wide\n", .{ @tagName(kind), foot, width });
                    return error.ItemCardOverflow;
                }
            }
        }
    }
    var rare_buf: [items.NAME_MAX]u8 = undefined;
    for (std.enums.values(affixes.RareName.First)) |first| {
        for (std.enums.values(affixes.RareName.Last)) |last| {
            const name = (affixes.RareName{ .first = first, .last = last }).name(&rare_buf);
            if (face.width(name, font.BODY) > layout.CARD_W) return error.ItemCardOverflow;
        }
    }
}
