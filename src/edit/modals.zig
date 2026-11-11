const sprite_assets = @import("../gfx/sprite_assets.zig");
const tool_catalog = @import("tool_catalog.zig");
const widgets = @import("widgets.zig");
const std = @import("std");
const rl = @import("raylib");
const input = @import("../core/input.zig");
const mathx = @import("../core/mathx.zig");
const atlas = @import("../map/atlas.zig");
const listing = @import("../map/listing.zig");
const lume = @import("../map/lume.zig");
const gas = @import("../map/gas.zig");
const actor = @import("../play/actor.zig");
const firebolt = @import("../play/firebolt.zig");
const windup = @import("../play/windup.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const dual = @import("../gfx/ground.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");
const panel = @import("panel.zig");
const editor = @import("editor.zig");
const effects = @import("effects.zig");
const text_panel = @import("text_panel.zig");
const Desk = input.Desk;
const DETAIL = widgets.DETAIL;
const TITLE = widgets.TITLE;
const ROW_ON = widgets.ROW_ON;
const SEP = menu.SEP;

pub fn drawModal(ed: *editor.Editor, g: *game.Game) void {
    game.character.veil(g);
    switch (ed.modal) {
        .none => {},
        .prompt => |p| drawPrompt(ed, g, p),
        .text => text_panel.draw(ed, g),
        .plot => editor.plot.draw(ed, g),
        .help => drawHelp(ed, g),
        .objects => drawObjects(ed, g),
        .effects => effects.draw(ed, g),
    }
}

fn drawPrompt(ed: *editor.Editor, g: *game.Game, prompt: editor.Prompt) void {
    var buf: [widgets.LINE]u8 = undefined;
    const body = promptBody(ed, prompt);
    var title_buf: [listing.PATH_MAX + widgets.LINE]u8 = undefined;
    var dir_buf: [listing.PATH_MAX]u8 = undefined;
    const title: [:0]const u8 = switch (prompt) {
        .confirm => "Unsaved changes",
        .name => if (ed.naming == .new) "New map" else "Save the map as",
        .open => std.fmt.bufPrintZ(&title_buf, "Open: {s}", .{ed.listing.dirPath(&dir_buf)}) catch "Open",
    };
    const f = widgets.modalFrame(&g.face, g.screen, widgets.MODAL_W, widgets.MODAL_HEAD + body + widgets.ROW_H + widgets.PAD, title, true);
    const x = f.x;
    var y = f.y;
    const buttons_y = y + body;
    const inner = f.w - widgets.PAD * 2;
    switch (prompt) {
        .confirm => {
            var fit_buf: [widgets.LINE]u8 = undefined;
            widgets.textFace(&g.face).draw(widgets.fitBefore(&g.face, &buf, &fit_buf, ed.path(), " has changes that are not saved.", inner), x + widgets.PAD, y, widgets.TEXT, look.TEXT);
            std.debug.assert(y + widgets.TEXT <= buttons_y);
            y = buttons_y;
            if (editor.modalButton(ed, g, f.button(y, 2), widgets.keyed("Save", Desk.ENTER_CAPTION), false, true, null) and ed.save()) ed.commit();
            if (editor.modalButton(ed, g, f.button(y, 1), "Discard", false, true, null)) ed.commit();
            backButton(ed, g, f, y, "Cancel");
        },
        .name => {
            fieldRow(ed, g, widgets.row(x + widgets.PAD, y, inner));
            y += widgets.ROW_STEP;
            var pbuf: [listing.PATH_MAX]u8 = undefined;
            const note = if (ed.namedPath(&pbuf)) |p| std.fmt.bufPrintZ(&buf, "Makes {s}", .{p}) catch "" else "Type a name";
            widgets.drawFit(&g.face, note, DETAIL, inner, false, x + widgets.PAD, y, look.DIM);
            std.debug.assert(y + DETAIL <= buttons_y);
            y = buttons_y;
            if (editor.modalButton(ed, g, f.button(y, 1), widgets.keyed("OK", Desk.ENTER_CAPTION), false, true, null)) ed.named();
            backButton(ed, g, f, y, "Cancel");
        },
        .open => {
            if (ed.listing.n == 0) widgets.textFace(&g.face).draw(atlas.NO_MAPS, x + widgets.PAD, y, widgets.TEXT, look.DIM);
            for (ed.listed_top..@min(ed.listing.n, ed.listed_top + widgets.MODAL_ROWS)) |i| {
                const label = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ switch (ed.listing.entry(i)) {
                    .up => "^  ",
                    .folder => "+  ",
                    .map => "   ",
                }, ed.listing.label(i) }) catch "";
                const r = widgets.row(x + widgets.PAD, y, inner);
                widgets.hoverEdge(r, i == ed.listed_at);
                if (editor.modalButton(ed, g, r, label, std.mem.eql(u8, ed.listing.at(i), ed.path()), true, OPEN_TIPS.get(ed.listing.entry(i)))) {
                    return ed.openListed(i);
                }
                y += widgets.ROW_H;
            }
            std.debug.assert(y + @as(i32, if (ed.listing.n == 0) widgets.TEXT else 0) <= buttons_y);
            widgets.textFace(&g.face).draw(OPEN_CRIB, x + widgets.PAD, buttons_y + widgets.DETAIL_DY, DETAIL, look.DIM);
            backButton(ed, g, f, buttons_y, "Cancel");
        },
    }
}

const OPEN_TIPS = std.EnumArray(listing.Listing.Entry, [:0]const u8).init(.{
    .up = widgets.keyed("The folder above", input.RUB_CAPTION),
    .folder = "Into this folder",
    .map = "Open this map",
});
const OPEN_CRIB = Desk.NAV_CAPTION ++ " pick" ++ SEP ++ Desk.ENTER_CAPTION ++ " open" ++ SEP ++ input.RUB_CAPTION ++ " up";

const HELP_W: i32 = 1000;
const HELP_STEP: i32 = 28;

fn drawHelp(ed: *editor.Editor, g: *game.Game) void {
    const f = widgets.modalFrame(&g.face, g.screen, HELP_W, widgets.MODAL_HEAD + widgets.PAD + editor.HELP_ROWS * HELP_STEP + widgets.ROW_H + widgets.PAD, "Every key", false);
    const x = f.x;
    const w = f.w;
    var ys: [editor.HELP_COLUMNS]i32 = @splat(f.y);
    const column_w = @divTrunc(w - (editor.HELP_COLUMNS + 1) * widgets.PAD, editor.HELP_COLUMNS);
    for (editor.HELP) |s| {
        const cx = x + widgets.PAD + @as(i32, @intCast(s.column)) * (column_w + widgets.PAD);
        const y = ys[s.column];
        widgets.drawFit(&g.face, s.head, DETAIL, column_w, false, cx, y, look.UI_GOLD);
        for (s.lines, 1..) |l, k| widgets.drawFit(&g.face, l, DETAIL, column_w, false, cx, y + @as(i32, @intCast(k)) * HELP_STEP, look.TEXT);
        ys[s.column] = y + s.rows() * HELP_STEP;
    }
    backButton(ed, g, f, std.mem.max(i32, &ys), "Close");
}

const VIEW_W: i32 = 960;
const VIEW_COLS: usize = 7;
const VIEW_CELL: i32 = 72;
const VIEW_PIC: f32 = 48;
const VIEW_PIC_TOP: f32 = 4;
const VIEW_BIG: i32 = 160;

pub const OBJECTS_TITLE = "Objects";
pub const PICKS_ONE = Desk.NAV_CAPTION ++ " or " ++ Desk.PAINT_CAPTION ++ " picks one";
pub const CLOSES = Desk.BACK_CAPTION ++ " closes";

fn drawObjects(ed: *editor.Editor, g: *game.Game) void {
    const chrome = widgets.MODAL_HEAD + widgets.PAD + widgets.ROW_STEP;
    const pitch = @min(VIEW_CELL, @divTrunc(g.screen.y - chrome, widgets.rowsOf(editor.SEEN.len, VIEW_COLS)));
    const grid_w = @as(i32, VIEW_COLS) * pitch;
    const title = OBJECTS_TITLE;
    var cells = panel.Tiles{ .x = 0, .y = 0, .cols = VIEW_COLS, .pitch = pitch, .size = pitch - widgets.GAP };
    const cells_h = cells.height(editor.SEEN.len);
    const f = widgets.modalFrame(&g.face, g.screen, VIEW_W, chrome + cells_h, title, false);
    const x = f.x;
    const w = f.w;
    const y = f.y;
    cells.x = x + widgets.PAD;
    cells.y = y;
    widgets.titleHint(&g.face, f, title, PICKS_ONE ++ SEP ++ CLOSES);
    for (editor.SEEN, 0..) |s, i| {
        const r = cells.at(i);
        const hh = widgets.plateHit(ed.controls(), r, i == ed.seen_at, true, true, seenName(s));
        seenPicture(g, s, widgets.pictureIn(r, VIEW_PIC, VIEW_PIC_TOP));
        if (hh.hit) ed.seen_at = i;
    }
    const s = editor.SEEN[ed.seen_at];
    const dx = x + widgets.PAD + grid_w + widgets.PAD;
    var dy = y;
    seenPicture(g, s, raster.rect(dx, dy, VIEW_BIG, VIEW_BIG));
    rl.drawRectangleLines(dx, dy, VIEW_BIG, VIEW_BIG, look.EDGE);
    dy += VIEW_BIG + widgets.PAD;
    widgets.textFace(&g.face).draw(seenName(s), dx, dy, TITLE, look.TEXT);
    dy += TITLE + widgets.GAP;
    var facts = Facts{};
    seenFacts(s, &facts);
    for (facts.all()) |l| {
        widgets.drawFit(&g.face, l, DETAIL, x + w - widgets.PAD - dx, false, dx, dy, look.TEXT);
        dy += widgets.DETAIL_STEP;
    }
    backButton(ed, g, f, y + cells_h, "Close");
    if (seenFoe(s) != null) {
        if (editor.modalButton(ed, g, f.button(y + cells_h, 1), widgets.keyed("Fight", Desk.ENTER_CAPTION), false, true, "Fight this foe in an arena; return through the pause menu")) fightSeen(ed);
    }
}

pub fn seenFoe(s: editor.Seen) ?actor.Kind {
    return switch (s) {
        .body => |kind| if (kind.foe()) kind else null,
        .tile, .barrel, .torch, .door, .npc => null,
    };
}

pub fn fightSeen(ed: *editor.Editor) void {
    const kind = seenFoe(editor.SEEN[ed.seen_at]) orelse return;
    ed.action = .{ .fight = kind };
}

fn seenTool(s: editor.Seen) ?editor.Tool {
    return switch (s) {
        .tile => null,
        .body => |k| .{ .foe = k },
        inline .barrel, .torch, .door, .npc => |_, tag| @unionInit(editor.Tool, @tagName(tag), {}),
    };
}

fn seenName(s: editor.Seen) [:0]const u8 {
    if (seenTool(s)) |t| return t.name();
    return menu.named(s.tile);
}

fn seenPicture(g: *game.Game, s: editor.Seen, r: rl.Rectangle) void {
    if (seenTool(s)) |t| return panel.toolFigure(g, t, r);
    panel.swatch(g, s.tile, r);
}

const FACTS_MAX: usize = 8;

const Facts = struct {
    buf: [FACTS_MAX][widgets.LINE]u8 = undefined,
    line: [FACTS_MAX][:0]const u8 = undefined,
    n: usize = 0,

    fn put(f: *Facts, comptime fmt: []const u8, args: anytype) void {
        std.debug.assert(f.n < FACTS_MAX);
        f.line[f.n] = std.fmt.bufPrintZ(&f.buf[f.n], fmt, args) catch "";
        f.n += 1;
    }

    fn all(f: *const Facts) []const [:0]const u8 {
        return f.line[0..f.n];
    }
};

fn seenFacts(s: editor.Seen, f: *Facts) void {
    switch (s) {
        .tile => |t| {
            f.put("Letter '{c}' in a map file", .{t.letter()});
            f.put("{s}; {s}", .{ if (t.solid()) "Blocks a step" else "Walked on", if (t.blind()) "blocks sight" else "seen through" });
            if (t.liquid()) f.put("A liquid: gas spreads over it, a trail bridges it", .{});
            if (t.wet()) f.put("Fire landing on it boils off as " ++ gas.STEAM_NAME, .{});
            if (t.burns()) f.put("Catches fire, spreads it and burns down to dirt", .{});
            if (look.under(t)) |u| f.put("Drawn over the ground beside it, else {s}", .{@tagName(u)});
            if (dual.of(t)) |gr| if (sprite_assets.GROUND_SHEETS.contains(gr)) f.put("Ground {s}: its edges meet the grounds below it", .{@tagName(gr)});
            if (look.castsPicture(t)) f.put("Stands up and throws a shadow", .{});
            if (t.opened() != null) {
                f.put("Opened by stepping toward it or interacting", .{});
                f.put("Contains gold and items; never broken by attacks", .{});
            }
            if (t.isOpened()) f.put("Already opened; may hold items and be walked over", .{});
            if (t.bursts()) f.put("Bursts into " ++ gas.HEALING_NAME ++ " when the hero steps into it or strikes it", .{});
        },
        .body => |k| {
            const r = actor.row(k);
            if (r.foe_type) |kind| f.put("{s}  /  {s}", .{ menu.named(kind), menu.named(r.movement) }) else f.put("{s}", .{menu.named(r.movement)});
            f.put("Life {d}  /  Sight {d} cells", .{ r.hp, r.sight });
            if (r.armour > 0 or r.stun_resist > 0) f.put("Physical reduction {d}%  /  Stun resist {d}%", .{ r.armour, r.stun_resist });
            switch (r.blow) {
                .strike => |st| {
                    f.put("{d}-{d} {s} damage ({s})", .{ st.hit.lo, st.hit.hi, if (st.element) |e| @tagName(e) else "physical", st.verb });
                    if (st.bleeds > 0) f.put("{d}% of its blows open a bleed", .{st.bleeds});
                    if (st.stuns > 0) f.put("{d}% of its blows stun, friend or foe", .{st.stuns});
                },
                .burst => |b| switch (b) {
                    .gas => f.put("Bursts into " ++ gas.NAME ++ " instead of striking", .{}),
                    .fire => f.put("Bursts into flame instead of striking, setting the bodies beside it alight", .{}),
                },
            }
            if (r.sweep_every > 0) f.put("Sweeps {d} adjacent cells every {d} turns", .{ actor.SWEEP_CELLS, r.sweep_every });
            if (r.ranged) |ranged| {
                f.put("Fires arrows up to {d} cells along a clear line", .{ranged.range});
                f.put("Backs away within {d} cells; shoots if cornered", .{ranged.retreat});
            }
            if (r.charges) |c| {
                f.put("Braces a turn at {d}-{d} cells on an open line, then charges {d} cells", .{ windup.NEAREST, c.range, c.rush });
                f.put("{d}-{d} damage on contact; stopped short, it loses a turn and its reduction", .{ c.blow.hit.lo, c.blow.hit.hi });
            }
            if (r.hooks) |h| f.put("Braces, then hooks along the line {d} cells every {d} turns, pulling 1 cell", .{ h.range, h.every });
            if (r.hurls) |h| {
                f.put("{d}-{d} {s} firebolt, {d} cells a turn up to {d}; hits any body", .{ h.hit.lo, h.hit.hi, @tagName(firebolt.ELEMENT), h.speed, h.range });
                f.put("{d}% to burn; moves after each throw, keeps {d} cells off", .{ h.burns, r.keeps });
            }
            if (r.light > 0) f.put("Carries a light {d} cells round", .{r.light});
            if (r.splits) |into| f.put("Splits into two {s}s under half its hp", .{actor.row(into).name});
            if (r.flits) f.put("Flits: {d:.0}% of its moves go a random way", .{actor.FLIT * mathx.PERCENT});
            if (r.flees) f.put("Runs {d} turns when it sees a foe die within {d} cells", .{ actor.FLEE_TURNS, actor.FRIGHT_REACH });
            if (k.foe() and !k.stocked()) f.put("Only split off another; never placed", .{});
        },
        .barrel => {
            f.put(menu.capital(tool_catalog.BARREL_RULE) ++ " in one hit, shot or kicked", .{});
            f.put("Blocks a step and stops an arrow", .{});
        },
        .torch => f.put(menu.capital(tool_catalog.TORCH_RULE) ++ "; lights {d} cells round", .{lume.TORCH_REACH}),
        .door => f.put("Leads both ways to one door on any node", .{}),
        .npc => {
            f.put(menu.capital(tool_catalog.NPC_RULE) ++ ", on a painted node", .{});
            f.put("On a rolled node: beside a prop, or far from the doors, found afresh each roll", .{});
            f.put("Never fights or moves", .{});
            f.put("Bump it or interact beside it to open its dialog; no turn passes", .{});
            f.put("Blocks a step; arrows and blasts pass it by", .{});
        },
    }
}

test "editor object viewer facts fit its lines for every object" {
    var most: usize = 0;
    for (editor.SEEN) |s| {
        var f = Facts{};
        seenFacts(s, &f);
        most = @max(most, f.n);
    }
    try std.testing.expect(most <= FACTS_MAX);
}

fn promptBody(ed: *const editor.Editor, prompt: editor.Prompt) i32 {
    return switch (prompt) {
        .confirm => widgets.ROW_H * 2 + widgets.PAD,
        .name => widgets.ROW_STEP + widgets.ROW_H + widgets.PAD,
        .open => @as(i32, @intCast(@max(1, @min(ed.listing.n, widgets.MODAL_ROWS)))) * widgets.ROW_H + widgets.PAD,
    };
}

pub fn fieldRow(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle) void {
    var buf: [widgets.LINE]u8 = undefined;
    rl.drawRectangleRec(r, ROW_ON);
    if (ed.field.selected) rl.drawRectangleLinesEx(r, 2, look.UI_FOCUS);
    const typed = std.fmt.bufPrintZ(&buf, "{s}" ++ menu.CARET, .{ed.field.text()}) catch "";
    widgets.drawFit(&g.face, typed, widgets.TEXT, widgets.insetW(r), true, widgets.textX(r), widgets.midY(r, widgets.TEXT), look.UI_FOCUS);
}

pub fn backButton(ed: *editor.Editor, g: *game.Game, f: widgets.Frame, y: i32, comptime label: []const u8) void {
    if (backPressed(ed, g, f, y, label, null)) ed.closeModal();
}

pub fn backPressed(ed: *editor.Editor, g: *game.Game, f: widgets.Frame, y: i32, comptime label: []const u8, tip: ?[:0]const u8) bool {
    return editor.modalButton(ed, g, f.button(y, 0), widgets.keyed(label, Desk.BACK_CAPTION), false, true, tip);
}
