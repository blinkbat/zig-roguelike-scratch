const std = @import("std");
const rl = @import("raylib");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const listing = @import("../map/listing.zig");
const lume = @import("../map/lume.zig");
const actor = @import("../play/actor.zig");
const look = @import("../gfx/look.zig");
const dual = @import("../gfx/ground.zig");
const font = @import("../gfx/font.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");
const panel = @import("panel.zig");
const editor = @import("editor.zig");
const Desk = input.Desk;
const SMALL = font.SMALL;
const HEAD = font.HEAD;
const ROW_ON = look.EDIT_ROW_ON;
const HOVER = look.EDIT_HOVER;
const SEP = menu.SEP;

pub fn drawModal(ed: *editor.Editor, g: *game.Game) void {
    var buf: [editor.LINE]u8 = undefined;
    game.character.veil(g);
    switch (ed.modal) {
        .help => return drawHelp(ed, g),
        .objects => return drawObjects(ed, g),
        .none, .confirm, .name, .open => {},
    }
    const body = modalBody(ed);
    var title_buf: [listing.PATH_MAX + editor.LINE]u8 = undefined;
    var dir_buf: [listing.PATH_MAX]u8 = undefined;
    const title: [:0]const u8 = switch (ed.modal) {
        .confirm => "Unsaved changes",
        .name => if (ed.naming == .new) "New map" else "Save the map as",
        .open => std.fmt.bufPrintZ(&title_buf, "Open: {s}", .{ed.listing.dirPath(&dir_buf)}) catch "Open",
        .none, .help, .objects => "",
    };
    const f = editor.modalFrame(g, editor.MODAL_W, editor.MODAL_HEAD + body + editor.ROW_H + editor.PAD, title, true);
    const x = f.x;
    var y = f.y;
    const buttons_y = y + body;
    const bx = f.buttonX();
    const inner = f.w - editor.PAD * 2;
    switch (ed.modal) {
        .confirm => {
            var fit_buf: [editor.LINE]u8 = undefined;
            editor.textFace(g).draw(editor.fitBefore(g, &buf, &fit_buf, ed.path(), " has changes that are not saved.", inner), x + editor.PAD, y, editor.TEXT, look.TEXT);
            std.debug.assert(y + editor.TEXT <= buttons_y);
            y = buttons_y;
            if (editor.buttonOn(ed, g, modalButton(bx, y, 2), editor.keyed("Save", Desk.ENTER_CAPTION), false, true, true, null) and ed.save()) ed.commit();
            if (editor.buttonOn(ed, g, modalButton(bx, y, 1), "Discard", false, true, true, null)) ed.commit();
            backButton(ed, g, bx, y, "Cancel");
        },
        .name => {
            fieldRow(ed, g, editor.row(x + editor.PAD, y, inner));
            y += editor.ROW_STEP;
            var pbuf: [listing.PATH_MAX]u8 = undefined;
            const note = if (ed.namedPath(&pbuf)) |p| std.fmt.bufPrintZ(&buf, "Makes {s}", .{p}) catch "" else "Type a name";
            panel.drawFit(g, note, SMALL, inner, false, x + editor.PAD, y, look.DIM);
            std.debug.assert(y + SMALL <= buttons_y);
            y = buttons_y;
            if (editor.buttonOn(ed, g, modalButton(bx, y, 1), editor.keyed("OK", Desk.ENTER_CAPTION), false, true, true, null)) ed.named();
            backButton(ed, g, bx, y, "Cancel");
        },
        .open => {
            if (ed.listing.n == 0) editor.textFace(g).draw(atlas.NO_MAPS, x + editor.PAD, y, editor.TEXT, look.DIM);
            for (ed.listed_top..@min(ed.listing.n, ed.listed_top + editor.MODAL_ROWS)) |i| {
                const label = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ switch (ed.listing.entry(i)) {
                    .up => "^  ",
                    .folder => "+  ",
                    .map => "   ",
                }, ed.listing.label(i) }) catch "";
                const r = editor.row(x + editor.PAD, y, inner);
                if (i == ed.listed_at) rl.drawRectangleLinesEx(r, 1, HOVER);
                if (editor.buttonOn(ed, g, r, label, std.mem.eql(u8, ed.listing.at(i), ed.path()), true, true, OPEN_TIPS.get(ed.listing.entry(i)))) {
                    return ed.openListed(i);
                }
                y += editor.ROW_H;
            }
            std.debug.assert(y + @as(i32, if (ed.listing.n == 0) editor.TEXT else 0) <= buttons_y);
            editor.textFace(g).draw(OPEN_CRIB, x + editor.PAD, buttons_y + editor.SMALL_DY, SMALL, look.DIM);
            backButton(ed, g, bx, buttons_y, "Cancel");
        },
        .none, .help, .objects => {},
    }
}

const OPEN_TIPS = std.EnumArray(listing.Listing.Entry, [:0]const u8).init(.{
    .up = "The folder above (" ++ input.RUB_CAPTION ++ ")",
    .folder = "Into this folder",
    .map = "Open this map",
});
const OPEN_CRIB = Desk.NAV_CAPTION ++ " pick" ++ SEP ++ Desk.ENTER_CAPTION ++ " open" ++ SEP ++ input.RUB_CAPTION ++ " up";

const HELP_W: i32 = 1000;
const HELP_STEP: i32 = 24;

fn drawHelp(ed: *editor.Editor, g: *game.Game) void {
    const f = editor.modalFrame(g, HELP_W, editor.MODAL_HEAD + editor.PAD + editor.HELP_ROWS * HELP_STEP + editor.ROW_H + editor.PAD, "Every key", false);
    const x = f.x;
    const w = f.w;
    var ys = [_]i32{ f.y, f.y };
    const column_w = @divTrunc(w - 3 * editor.PAD, 2);
    for (editor.HELP) |s| {
        const cx = x + editor.PAD + @as(i32, @intCast(s.column)) * (column_w + editor.PAD);
        var y = ys[s.column];
        panel.drawFit(g, s.head, font.SMALL, column_w, false, cx, y, look.UI_GOLD);
        y += HELP_STEP;
        for (s.lines) |l| {
            panel.drawFit(g, l, font.SMALL, column_w, false, cx, y, look.TEXT);
            y += HELP_STEP;
        }
        ys[s.column] = y + HELP_STEP;
    }
    backButton(ed, g, f.buttonX(), @max(ys[0], ys[1]), "Close");
}

const VIEW_W: i32 = 960;
const VIEW_COLS: usize = 7;
const VIEW_CELL: i32 = 72;
const VIEW_PIC: f32 = 48;
const VIEW_PIC_TOP: f32 = 4;
const VIEW_BIG: f32 = 192;

fn drawObjects(ed: *editor.Editor, g: *game.Game) void {
    const grid_w = @as(i32, VIEW_COLS) * VIEW_CELL;
    const title = "Objects";
    var cells = panel.Tiles{ .x = 0, .y = 0, .cols = VIEW_COLS, .pitch = VIEW_CELL, .size = VIEW_CELL - editor.GAP };
    const cells_h = cells.height(editor.SEEN.len);
    const f = editor.modalFrame(g, VIEW_W, editor.MODAL_HEAD + editor.PAD + cells_h + editor.ROW_STEP, title, false);
    const x = f.x;
    const w = f.w;
    const y = f.y;
    cells.x = x + editor.PAD;
    cells.y = y;
    editor.textFace(g).draw(Desk.NAV_CAPTION ++ " or " ++ Desk.PAINT_CAPTION ++ " picks one" ++ SEP ++ Desk.BACK_CAPTION ++ " closes", x + editor.PAD + editor.textFace(g).width(title, HEAD) + editor.PAD, f.top + @divTrunc(HEAD - SMALL, 2), SMALL, look.DIM);
    for (editor.SEEN, 0..) |s, i| {
        const r = cells.at(i);
        const hh = editor.hot(ed, r, true, true, seenName(s));
        editor.plate(r, i == ed.seen_at, hh.hot);
        seenPicture(g, s, editor.pictureIn(r, VIEW_PIC, VIEW_PIC_TOP));
        if (hh.hit) ed.seen_at = i;
    }
    const s = editor.SEEN[ed.seen_at];
    const dx = x + editor.PAD + grid_w + editor.PAD;
    var dy = y;
    seenPicture(g, s, .{ .x = @floatFromInt(dx), .y = @floatFromInt(dy), .width = VIEW_BIG, .height = VIEW_BIG });
    rl.drawRectangleLines(dx, dy, @intFromFloat(VIEW_BIG), @intFromFloat(VIEW_BIG), look.EDGE);
    dy += @as(i32, @intFromFloat(VIEW_BIG)) + editor.PAD;
    editor.textFace(g).draw(seenName(s), dx, dy, HEAD, look.TEXT);
    dy += HEAD + editor.GAP;
    var facts = Facts{};
    seenFacts(s, &facts);
    for (facts.all()) |l| {
        panel.drawFit(g, l, font.SMALL, x + w - editor.PAD - dx, false, dx, dy, look.TEXT);
        dy += font.SMALL + 4;
    }
    backButton(ed, g, f.buttonX(), y + cells_h, "Close");
    if (seenFoe(s) != null) {
        if (editor.buttonOn(ed, g, modalButton(f.buttonX(), y + cells_h, 1), editor.keyed("Fight", Desk.ENTER_CAPTION), false, true, true, "Fight this foe in an arena; return through the pause menu")) fightSeen(ed);
    }
}

pub fn seenFoe(s: editor.Seen) ?actor.Kind {
    return switch (s) {
        .body => |kind| if (kind.foe()) kind else null,
        .tile, .barrel, .torch, .door => null,
    };
}

pub fn fightSeen(ed: *editor.Editor) void {
    const kind = seenFoe(editor.SEEN[ed.seen_at]) orelse return;
    ed.action = .{ .fight = kind };
}

fn seenName(s: editor.Seen) [:0]const u8 {
    return switch (s) {
        .tile => |t| menu.named(t),
        .body => |k| editor.kindName(k),
        inline else => |_, tag| comptime menu.named(tag),
    };
}

pub fn seenPicture(g: *game.Game, s: editor.Seen, r: rl.Rectangle) void {
    switch (s) {
        .tile => |t| panel.swatch(g, t, r),
        .body => |k| panel.toolFigure(g, .{ .foe = k }, r),
        inline .barrel, .torch, .door => |_, tag| panel.toolFigure(g, @unionInit(editor.Tool, @tagName(tag), {}), r),
    }
}

const FACTS_MAX: usize = 8;

const Facts = struct {
    buf: [FACTS_MAX][editor.LINE]u8 = undefined,
    line: [FACTS_MAX][:0]const u8 = undefined,
    n: usize = 0,

    fn put(f: *Facts, comptime fmt: []const u8, args: anytype) void {
        if (f.n == FACTS_MAX) return;
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
            if (look.under(t)) |u| f.put("Drawn over the ground beside it, else {s}", .{@tagName(u)});
            if (dual.of(t)) |gr| if (look.GROUND_SHEETS.contains(gr)) f.put("Ground {s}: its edges meet the grounds below it", .{@tagName(gr)});
            if (look.stands(t)) f.put("Stands up and throws a shadow", .{});
            if (t.opened() != null) {
                f.put("Opened by stepping toward it or interacting", .{});
                f.put("Contains gold and items; never broken by attacks", .{});
            }
            if (t.isOpened()) f.put("Already opened; may hold items and be walked over", .{});
        },
        .body => |k| {
            const r = actor.row(k);
            if (r.foe_type) |kind| f.put("{s}  /  {s}", .{ menu.named(kind), menu.named(r.movement) }) else f.put("{s}", .{menu.named(r.movement)});
            f.put("Life {d}  /  Sight {d} cells", .{ r.hp, r.sight });
            if (r.armour > 0 or r.stun_resist > 0) f.put("Physical reduction {d}%  /  Stun resist {d}%", .{ r.armour, r.stun_resist });
            switch (r.blow) {
                .strike => |st| {
                    f.put("{d}-{d} physical damage ({s})", .{ st.hit.lo, st.hit.hi, st.verb });
                    if (st.bleeds > 0) f.put("{d}% of its blows open a bleed", .{st.bleeds});
                    if (st.stuns > 0) f.put("{d}% of its blows stun, friend or foe", .{st.stuns});
                },
                .burst => f.put("Bursts into caustic gas instead of striking", .{}),
            }
            if (r.sweep_every > 0) f.put("Sweeps {d} adjacent cells every {d} turns", .{ actor.SWEEP_CELLS, r.sweep_every });
            if (r.ranged) |ranged| {
                f.put("Fires arrows up to {d} cells along a clear line", .{ranged.range});
                f.put("Backs away within {d} cells; shoots if cornered", .{ranged.retreat});
            }
            if (r.light > 0) f.put("Carries a light {d} cells round", .{r.light});
            if (r.splits) |into| f.put("Splits into two {s}s under half its hp", .{actor.row(into).name});
            if (r.flits) f.put("Flits: {d:.0}% of its moves go a random way", .{actor.FLIT * 100});
            if (r.flees) f.put("Runs {d} turns when it sees a foe die within {d} cells", .{ actor.FLEE_TURNS, actor.FRIGHT_REACH });
            if (k.foe() and !k.stocked()) f.put("Only split off another; never placed", .{});
        },
        .barrel => {
            f.put("Stands on " ++ @tagName(grid.BARREL_GROUND) ++ "; one hit, shot or kicked, breaks it for gold", .{});
            f.put("Blocks a step and stops an arrow", .{});
        },
        .torch => f.put(menu.capital(editor.TORCH_RULE) ++ "; lights {d} cells round", .{lume.TORCH_REACH}),
        .door => f.put("Leads both ways to one door on any node", .{}),
    }
}

fn modalBody(ed: *const editor.Editor) i32 {
    return switch (ed.modal) {
        .confirm => editor.ROW_H * 2 + editor.PAD,
        .name => editor.ROW_STEP + editor.ROW_H + editor.PAD,
        .open => @as(i32, @intCast(@max(1, @min(ed.listing.n, editor.MODAL_ROWS)))) * editor.ROW_H + editor.PAD,
        .none, .help, .objects => 0,
    };
}

fn modalButton(bx: i32, y: i32, k: i32) rl.Rectangle {
    return editor.row(bx - (editor.MODAL_BTN_W + editor.GAP) * k, y, editor.MODAL_BTN_W);
}

pub fn fieldRow(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle) void {
    var buf: [editor.LINE]u8 = undefined;
    rl.drawRectangleRec(r, ROW_ON);
    const typed = std.fmt.bufPrintZ(&buf, "{s}" ++ menu.CARET, .{ed.field.text()}) catch "";
    panel.drawFit(g, typed, editor.TEXT, editor.insetW(r), true, editor.textX(r), @as(i32, @intFromFloat(r.y)) + editor.TEXT_DY, look.UI_FOCUS);
}

fn backButton(ed: *editor.Editor, g: *game.Game, bx: i32, y: i32, comptime label: []const u8) void {
    if (editor.buttonOn(ed, g, modalButton(bx, y, 0), editor.keyed(label, Desk.BACK_CAPTION), false, true, true, null)) ed.modal = .none;
}
