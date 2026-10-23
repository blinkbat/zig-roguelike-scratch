const std = @import("std");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const menu = @import("../ui/menu.zig");
const skillbar = @import("../play/skillbar.zig");
const raster = @import("../gfx/raster.zig");
const overlay = @import("overlay.zig");
const character = @import("character.zig");
const game = @import("../game.zig");
const P = mathx.P;
const CONFIRM = menu.CONFIRM;
const CHANGE = menu.CHANGE;
const REMOVE = menu.REMOVE;
const CHARACTER = menu.CHARACTER;

pub const Binds = struct {
    row: usize = 0,
    col: usize = 0,
    menu: Menu = .browse,
    assigning: ?skillbar.Act = null,

    pub const Menu = union(enum) { browse, pick: usize };

    pub fn slot(b: Binds) skillbar.Slot {
        return .{ .set = skillbar.SETS[b.row], .button = skillbar.SLOTS[b.col] };
    }

    fn move(b: *Binds, d: mathx.Dir) void {
        b.col = mathx.wrap(b.col, d.delta().x, skillbar.SLOTS.len);
        b.row = mathx.wrap(b.row, d.delta().y, skillbar.SETS.len);
    }

    pub fn colOf(button: input.Button) usize {
        return std.mem.indexOfScalar(input.Button, &skillbar.SLOTS, button).?;
    }

    pub fn openPick(b: *Binds, kit: []const skillbar.Act, bar: *const skillbar.Bar) void {
        b.menu = .{ .pick = pickOf(kit, bar.at(b.slot())) };
    }
};

/// Picker cell 0 clears the slot; the rest are the class's acts in order. An empty slot opens it on the first act.
pub fn pickOf(kit: []const skillbar.Act, a: ?skillbar.Act) usize {
    return 1 + (std.mem.indexOfScalar(skillbar.Act, kit, a orelse kit[0]) orelse 0);
}

pub fn pickAct(kit: []const skillbar.Act, i: usize) ?skillbar.Act {
    return if (i == 0) null else kit[i - 1];
}

pub fn picksOf(kit: []const skillbar.Act) usize {
    return kit.len + 1;
}

pub const PICK_MARGIN: i32 = 16;
pub const PICK_COLS: usize = @intCast(@divTrunc(game.SKILLS_W + game.SLOT_GAP, game.SLOT_STEP));

pub fn pickRows(n: usize) usize {
    return (n + PICK_COLS - 1) / PICK_COLS;
}

pub fn pickStep(i: usize, d: P, n: usize) usize {
    const at = mathx.wrap(i, d.x, n);
    const row = mathx.nudge(at / PICK_COLS, d.y, pickRows(n));
    return @min(row * PICK_COLS + at % PICK_COLS, n - 1);
}

pub fn pickWindow(top_y: i32, bottom_y: i32, n: usize, at: usize) menu.Window {
    const rows = pickRows(n);
    const room: usize = @intCast(@max(1, @divTrunc(bottom_y - game.SLOT_GAP - top_y - PICK_MARGIN, game.SLOT_STEP) + 1));
    return menu.Window.of(rows, at / PICK_COLS, room);
}

/// Opened from Character's skills, and backs out to them.
pub fn openBinds(g: *game.Game) void {
    g.binds.menu = .browse;
    g.binds.assigning = null;
    g.mode = .bind;
}

pub fn bindStep(g: *game.Game) void {
    if (g.st.hit(CHARACTER)) {
        g.mode = .play;
        return;
    }
    if (character.padToGame(g)) return;
    var state = g.st;
    const b = &g.binds;
    var kit_buf: skillbar.KitBuf = undefined;
    const kit = g.sim.growth.kit(g.sim.class, &kit_buf);
    if (state.pointing()) if (state.pointer) |pointer| {
        const panel = overlay.bindPanel(g);
        const p = overlay.bindSurface(g, panel).point(pointer);
        for (overlay.BIND_ACTIONS, 0..) |action, i| {
            if (!action.shown(b)) continue;
            if (state.click and raster.holds(overlay.bindActionBox(panel, i), p)) state.pressed.insert(action.button);
        }
        if (b.menu == .browse and state.click) {
            for (skillbar.SETS, 0..) |_, row| for (0..skillbar.SLOTS.len) |col| {
                if (raster.holds(overlay.bindSlotBox(row, col), p)) {
                    b.row = row;
                    b.col = col;
                }
            };
        } else if (b.menu == .pick and state.click) {
            const picker = overlay.bindPicker(b.*, picksOf(kit));
            for (picker.first()..picker.end()) |i| {
                if (raster.holds(picker.cell(i), p)) {
                    b.menu = .{ .pick = i };
                    state.pressed.insert(CONFIRM);
                }
            }
        }
    };
    const here = b.slot();
    const was = g.bar;
    defer if (!std.meta.eql(was, g.bar)) {
        g.sim.unsaved = true;
    };
    switch (b.menu) {
        .browse => {
            if (menu.backed(&state)) {
                g.mode = .pause;
            } else if (state.hit(CONFIRM)) {
                if (b.assigning) |act| {
                    g.bar.bind(here, act);
                    g.character.message.say("{s} bound.", .{act.name()});
                    g.mode = .pause;
                } else b.openPick(kit, &g.bar);
            } else if (state.hit(CHANGE)) {
                b.assigning = null;
                b.openPick(kit, &g.bar);
            } else if (state.hit(REMOVE)) {
                g.bar.clear(here);
            } else if (state.walk) |d| {
                b.move(d);
            }
        },
        .pick => |i| {
            if (menu.backed(&state)) {
                b.menu = .browse;
            } else if (state.hit(CONFIRM)) {
                if (pickAct(kit, i)) |a| g.bar.bind(here, a) else g.bar.clear(here);
                b.menu = .browse;
            } else if (state.walk) |d| {
                b.menu = .{ .pick = pickStep(i, d.delta(), picksOf(kit)) };
            } else if (state.scroll != 0) {
                b.menu = .{ .pick = mathx.nudge(i, -state.scroll * @as(i32, @intCast(PICK_COLS)), picksOf(kit)) };
            }
        },
    }
}
