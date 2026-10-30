const std = @import("std");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const hero = @import("../play/hero.zig");
const attr = @import("../play/attrs.zig");
const items = @import("../play/items.zig");
const damage = @import("../play/damage.zig");
const resilience = @import("../play/resilience.zig");
const terrain = @import("../play/terrain.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const consumable = @import("../play/consumable.zig");
const wording = @import("../core/wording.zig");
const P = mathx.P;

pub const Page = enum {
    equipment,
    inventory,
    stats,
    passives,
    skills,
    nearby,
    loot,

    pub fn of(key_page: input.CharacterPage) Page {
        return switch (key_page) {
            inline else => |page| @field(Page, @tagName(page)),
        };
    }

    pub fn shortcut(self: Page) ?input.CharacterPage {
        return switch (self) {
            .nearby, .loot => null,
            inline else => |page| @field(input.CharacterPage, @tagName(page)),
        };
    }

    /// Container selection and loot open without the character tabs.
    pub fn direct(self: Page) bool {
        return self.shortcut() == null;
    }
};
pub const PAGES = blk: {
    const keyed = std.enums.values(input.CharacterPage);
    var out: [keyed.len]Page = undefined;
    for (keyed, &out) |k, *p| p.* = Page.of(k);
    break :blk out;
};
pub const Nearby = union(enum) {
    loot: struct { index: usize, item: items.Item },
    supply: struct { index: usize, kind: consumable.Kind },
    gold: items.Coins,
    bag: P,
    chest: P,
    door: P,

    pub fn command(n: Nearby) Command {
        return switch (n) {
            .loot => |l| .{ .pickup = l.index },
            .supply => |s| .{ .take_supply = s.index },
            .gold => |pile| .{ .take_gold = pile.at },
            .bag, .chest => |at| .{ .open_loot = at },
            .door => |at| .{ .travel = at },
        };
    }

    pub fn item(n: Nearby) ?items.Item {
        return switch (n) {
            .loot => |l| l.item,
            .supply, .gold, .bag, .chest, .door => null,
        };
    }

    pub fn supplyOf(n: Nearby) ?consumable.Kind {
        return switch (n) {
            .supply => |s| s.kind,
            .loot, .gold, .bag, .chest, .door => null,
        };
    }

    pub fn label(n: Nearby, buf: []u8) [:0]const u8 {
        return switch (n) {
            .loot => |l| l.item.name(buf),
            .supply => |s| wording.named(s.kind),
            .gold => |pile| std.fmt.bufPrintZ(buf, "{d} gold", .{pile.amount}) catch "Gold",
            .chest => "Treasure chest",
            .bag => "Item bag",
            .door => "Door",
        };
    }
};
pub const Vital = struct { now: i32 = 0, max: i32 = 0 };
/// Armour and dodge as combat resolves them where the hero stands, terrain and sunder included.
pub const Defence = struct { dodge: u32, armour: i32 };
pub const View = struct {
    class: hero.Class,
    name: []const u8,
    inventory: *const items.Inventory,
    growth: *const progress.State,
    /// Class and passives, before gear.
    base: attr.Attrs,
    gold: i32 = 0,
    nearby: []const Nearby = &.{},
    device: input.Device = .keys,
    chest: bool = false,
    life: Vital = .{},
    mana: Vital = .{},
    resists: damage.Resists = .initFill(0),
    status_resist: std.EnumArray(resilience.Kind, resilience.Standing) = .initFill(.{}),
    steady: u8 = 0,
    environment: terrain.Modifiers = .{},
    /// Null with no hero standing: the sheet's own, without terrain or sunder.
    defence: ?Defence = null,

    pub fn stats(v: View) attr.Attrs {
        var out = v.inventory.gear.stats(v.base);
        if (v.defence) |d| out.armour = d.armour;
        return out;
    }

    pub fn dodge(v: View) u32 {
        return if (v.defence) |d| d.dodge else v.stats().dodge();
    }
};
pub const Command = union(enum) {
    close,
    equip: struct { index: usize, slot: items.Slot },
    unequip: items.Slot,
    drop: usize,
    passive: usize,
    skill: skillbar.Act,
    pickup: usize,
    take_supply: usize,
    use: consumable.Kind,
    take_gold: P,
    take_all,
    open_loot: P,
    travel: P,
    bindings: skillbar.Act,

    pub fn verb(c: Command) [:0]const u8 {
        return verbOf(std.meta.activeTag(c));
    }
};
pub fn verbOf(c: std.meta.Tag(Command)) [:0]const u8 {
    return switch (c) {
        .close => "Close",
        .equip => "Equip",
        .unequip => "Unequip",
        .drop => "Drop",
        .passive, .skill => unreachable,
        .pickup, .take_supply => "Take item",
        .use => "Use",
        .take_gold => "Take gold",
        .take_all => "Take all",
        .open_loot => "Loot",
        .travel => "Travel",
        .bindings => "Bind skill",
    };
}
