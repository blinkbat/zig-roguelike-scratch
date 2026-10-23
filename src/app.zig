const std = @import("std");
const rl = @import("raylib");
const game = @import("game.zig");
const window = @import("core/window.zig");
const editor = @import("edit/editor.zig");
const atlas = @import("map/atlas.zig");
const listing = @import("map/listing.zig");
const spar = @import("map/spar.zig");
const actor = @import("play/actor.zig");
const menu = @import("ui/menu.zig");
const naming = @import("ui/naming.zig");
const stage = @import("ui/stage.zig");
const look = @import("gfx/look.zig");
const font = @import("gfx/font.zig");
const shaders = @import("gfx/shaders.zig");
const shots = @import("game/shots.zig");
const raster = @import("gfx/raster.zig");
const prompt_icon = @import("gfx/prompt_icon.zig");
const hero = @import("play/hero.zig");
const ossuary = @import("play/ossuary.zig");
const save = @import("save.zig");
const input = @import("core/input.zig");
const skillbar = @import("play/skillbar.zig");
const mathx = @import("core/mathx.zig");

const Scene = enum { title, play, edit };
const Page = enum { main, map, class, name, load, ossuary, bones, options, debug };
const MainRow = enum {
    new,
    maps,
    load,
    ossuary,
    options,
    editor,
    quit,
};
const MAIN_ROWS = std.enums.values(MainRow);
const OptionRow = enum {
    fullscreen,
    debug,
};
const OPTION_ROWS = std.enums.values(OptionRow);
const DEBUG_ROWS = [_]struct { row: game.debugging.Row, note: [:0]const u8 }{
    .{ .row = .unkillable, .note = std.fmt.comptimePrint("{s} keeps the hero on {d} hp whatever strikes it", .{ menu.titled(@tagName(game.debugging.Row.unkillable)), game.combat.UNKILLABLE_HP }) },
};
const DELETE = menu.REMOVE;

const NAME = "Cistern";
const LINE = menu.NOTE_MAX;
const SaveAction = union(enum) { load: usize, remove: usize };
const OSSUARY = "Revered Ossuary";
const NO_BONES = "No hero's bones lie here yet";
const BONES_SCALE: i32 = 3;
const BONES_GAP: i32 = 12;
const BONES_RANK = "Level {d} {s}" ++ menu.SEP ++ "Renown {d}";
const CHOOSE_MAP = "CHOOSE A MAP";
const DELETE_W: f32 = 188;
const DELETE_INSET: f32 = 2;

fn mainLabel(r: MainRow) [:0]const u8 {
    return if (r == .ossuary) OSSUARY else menu.named(r);
}

fn saveRowBox(screen: mathx.P, i: usize) rl.Rectangle {
    return menu.rowBox(screen, .{ .from = 0, .len = save.SLOTS }, i);
}

fn saveDeleteBox(screen: mathx.P, i: usize) rl.Rectangle {
    const row = saveRowBox(screen, i);
    const width = @min(DELETE_W, row.width / 2);
    return .{ .x = row.x + row.width - width, .y = row.y + DELETE_INSET, .width = width, .height = row.height - 2 * DELETE_INSET };
}

const App = struct {
    alloc: std.mem.Allocator,
    g: *game.Game,
    map: *atlas.Atlas,
    ed: ?*editor.Editor = null,
    edit_path: []const u8,
    scene: Scene = .title,
    page: Page = .main,
    title: menu.Menu = .{},
    maps: menu.Menu = .{},
    listing: listing.Listing = .{},
    /// The map picked in Maps; null plays `atlas.START`.
    chosen: ?[]const u8 = null,
    chosen_buf: [listing.PATH_MAX]u8 = undefined,
    classes: stage.Lineup = .{},
    loads: menu.Menu = .{},
    options: menu.Menu = .{},
    debugs: menu.Menu = .{},
    class: hero.Class = hero.DEFAULT,
    entry: naming.Entry = .{},
    list: [save.SLOTS]save.Slot = @splat(.empty),
    armed: ?usize = null,
    /// The run being played in a slot; null for a play-test.
    autosave: ?save.Autosave = null,
    undeleted: ?anyerror = null,
    hall: ossuary.Hall = .{},
    unburied: ?anyerror = null,
    /// The hall on disk could not be read, so nothing may overwrite it.
    unread: ?anyerror = null,
    bones: menu.Menu = .{},
    note: menu.Note(LINE) = .{},

    fn say(app: *App, comptime fmt: []const u8, args: anytype) void {
        app.note.say(fmt, args);
    }

    fn toTitle(app: *App) void {
        app.scene = .title;
        app.goPage(.main);
    }

    fn goPage(app: *App, p: Page) void {
        game.holdWalk(app.g);
        app.note.clear();
        app.page = p;
    }

    fn folderOpened(app: *App) void {
        game.holdWalk(app.g);
        app.maps = .{};
    }

    fn choose(app: *App, path: []const u8) void {
        const n = @min(path.len, app.chosen_buf.len);
        @memcpy(app.chosen_buf[0..n], path[0..n]);
        app.chosen = app.chosen_buf[0..n];
    }

    fn fromClass(app: *App) void {
        if (app.chosen == null) return app.toTitle();
        app.goPage(.map);
    }

    fn toEdit(app: *App) void {
        const again = if (app.ed) |e| e.path().len > 0 else false;
        const ed = app.ed orelse blk: {
            const e = editor.Editor.create(app.alloc) catch return app.say("The editor did not start (out of memory)", .{});
            app.ed = e;
            break :blk e;
        };
        (if (again) ed.reopen() else ed.open(app.edit_path)) catch |e| {
            app.toTitle();
            return app.say(atlas.NOT_LOADED ++ "; the editor will not open over it", .{ if (again) ed.path() else app.edit_path, @errorName(e) });
        };
        app.scene = .edit;
    }

    fn rescan(app: *App) void {
        app.list = save.slots(app.alloc);
        app.armed = null;
    }

    fn saveStep(app: *App, st: *const input.State, screen: mathx.P) ?SaveAction {
        const was = app.loads.at;
        const picked = app.loads.step(st, save.SLOTS);
        if (st.scroll != 0) app.loads.at = mathx.nudge(app.loads.at, -st.scroll, save.SLOTS);
        var action: ?SaveAction = if (picked) |i| .{ .load = i } else null;
        if (st.pointing() and st.walk == null and st.scroll == 0) {
            for (0..save.SLOTS) |i| if (raster.holds(saveRowBox(screen, i), st.pointer.?)) {
                app.loads.at = i;
                if (st.click) {
                    if (raster.holds(saveDeleteBox(screen, i), st.pointer.?)) {
                        if (app.list[i] != .empty) action = .{ .remove = i };
                    } else action = .{ .load = i };
                }
                break;
            };
        }
        if (app.loads.at != was) {
            app.armed = null;
            app.note.clear();
        }
        if (st.hit(DELETE) and app.list[app.loads.at] != .empty) action = .{ .remove = app.loads.at };
        return action;
    }

    fn confirmDelete(app: *App, at: usize) bool {
        if (app.armed == at) return true;
        app.armed = at;
        app.say("Delete slot {d}? It cannot be undone", .{save.number(at)});
        return false;
    }

    fn drawSaves(app: *const App) void {
        const g = app.g;
        const first = saveRowBox(g.screen, 0);
        menu.heading(g.face, g.screen, comptime menu.caps(menu.named(MainRow.load)), menu.titleY(first), menu.TITLE, look.TEXT, look.UI_GOLD);
        var line: [LINE]u8 = undefined;
        var fit: [LINE + 1]u8 = undefined;
        for (&app.list, 0..) |*slot, i| {
            const row = saveRowBox(g.screen, i);
            const remove = saveDeleteBox(g.screen, i);
            const on = app.loads.at == i;
            if (on) rl.drawRectangleRec(.{ .x = row.x, .y = row.y, .width = remove.x - row.x - menu.ACTION_GAP, .height = row.height }, look.PICK_BG);
            const text = g.face.fit(&fit, slotLine(slot, &line, i), menu.ROW, @as(i32, @intFromFloat(remove.x - row.x)) - 2 * menu.ACTION_GAP, false);
            g.face.text(text, @as(i32, @intFromFloat(row.x)) + menu.ACTION_GAP, menu.rowTextY(row), menu.ROW, if (on) look.UI_FOCUS else look.DIM);
            if (slot.* != .empty) menu.action(&g.face, remove, prompt_icon.Prompt.menuOf(&g.st, DELETE), if (app.armed == i) "Delete it?" else "Delete save");
        }
        menu.mid(g.face, g.screen, app.note.text(), menu.noteY(first, save.SLOTS), menu.NOTE, look.DIM);
    }

    fn slotFree(app: *App) bool {
        app.rescan();
        return save.free(&app.list) != null;
    }

    fn newRun(app: *App, name: hero.Name) void {
        const g = app.g;
        const slot = save.free(&app.list) orelse return app.toTitle();
        const path = app.chosen orelse atlas.START;
        g.sim.class = app.class;
        if (app.map.load(app.alloc, path)) {
            if (!app.map.standable(app.map.start, &g.sim.lv)) {
                app.toTitle();
                return app.say(atlas.NO_FLOOR, .{path});
            }
            game.beginMap(g, app.map);
        } else |e| {
            if (app.chosen != null or e != error.FileNotFound) {
                app.toTitle();
                return app.say(atlas.NOT_LOADED, .{ path, @errorName(e) });
            }
            game.begin(g, game.freshSeed());
        }
        app.inSlot(slot, name);
        app.autosave.?.flush(g);
    }

    fn loadRun(app: *App, slot: usize) void {
        save.load(app.alloc, slot, app.g, app.map) catch |e| return app.say("Slot {d} did not load ({s})", .{ save.number(slot), @errorName(e) });
        app.inSlot(slot, null);
    }

    fn inSlot(app: *App, slot: usize, fresh: ?hero.Name) void {
        app.leaveRun();
        app.play(.title, fresh);
        app.autosave = save.Autosave.init(app.alloc, slot);
    }

    fn playTest(app: *App, from: atlas.Start) void {
        app.leaveRun();
        app.testOn(app.ed.?.map, from);
    }

    fn fight(app: *App, kind: actor.Kind) void {
        app.leaveRun();
        spar.author(app.map, kind);
        app.testOn(app.map, app.map.start);
    }

    fn testOn(app: *App, map: *const atlas.Atlas, from: atlas.Start) void {
        app.g.sim.class = hero.DEFAULT;
        game.beginMapAt(app.g, map, from, game.freshSeed());
        app.g.st.device = .keys;
        app.play(.editor, hero.DEFAULT.unnamed());
    }

    fn play(app: *App, back: game.Back, fresh: ?hero.Name) void {
        const g = app.g;
        if (fresh) |name| g.sim.name = name;
        g.permadeath = back == .title;
        g.hall = if (back == .title and app.unread == null) &app.hall else null;
        g.back = back;
        game.holdWalk(g);
        app.scene = .play;
    }

    /// A write that fails waits for the return to title to try again, and to say so.
    fn bury(app: *App) void {
        if (!app.hall.dirty or app.unburied != null) return;
        ossuary.write(&app.hall) catch |e| {
            app.unburied = e;
        };
    }

    fn reburied(app: *App) void {
        app.unburied = null;
        app.bury();
        if (app.unburied) |e| app.say(ossuary.NOT_WRITTEN, .{@errorName(e)});
    }

    fn leaveRun(app: *App) void {
        if (app.autosave) |*a| {
            game.leave(app.g);
            if (a.close(app.g)) |e| app.say(save.NOT_WRITTEN, .{@errorName(e)});
        }
        app.autosave = null;
    }

    /// False once the app should close.
    fn frame(app: *App) bool {
        const g = app.g;
        const closing = rl.windowShouldClose();
        if (app.scene != .title) {
            if (app.ed) |e| e.desk.update();
        }
        if (app.scene == .play and g.back == .editor) {
            const d = &app.ed.?.desk;
            if (closing or d.play_here) {
                d.play = false;
                d.play_here = false;
                app.scene = .edit;
            }
        } else if (closing and app.scene != .edit) {
            app.leaveRun();
            return false;
        }
        switch (app.scene) {
            .title => return app.titleFrame(),
            .play => {
                game.frame(g);
                app.bury();
                if (app.autosave) |*a| {
                    if (g.mode == .dead) {
                        app.undeleted = a.end();
                        a.deinit();
                        app.autosave = null;
                    } else a.step(g, rl.getFrameTime());
                }
                const exit = g.exit orelse return true;
                g.exit = null;
                switch (exit) {
                    .back => switch (g.back) {
                        .title => {
                            app.toTitle();
                            app.leaveRun();
                            if (app.undeleted) |e| app.say(save.NOT_DELETED, .{@errorName(e)});
                            app.undeleted = null;
                            app.reburied();
                        },
                        .editor => app.scene = .edit,
                    },
                    .quit => if (g.back == .editor) {
                        app.scene = .edit;
                        app.ed.?.request(.quit);
                        return app.ed.?.action != .quit;
                    } else {
                        app.leaveRun();
                        return false;
                    },
                }
            },
            .edit => {
                game.syncScreen(g, app.ed.?.desk.fullscreen);
                switch (editor.frame(app.ed.?, g, closing)) {
                    .none => {},
                    .play => |from| app.playTest(from),
                    .fight => |kind| app.fight(kind),
                    .leave => app.toTitle(),
                    .quit => return false,
                }
            },
        }
        return true;
    }

    fn titleFrame(app: *App) bool {
        const g = app.g;
        g.st.typing = app.page == .name;
        g.st.context = .menu;
        g.st.sets = false;
        g.st.update(rl.getFrameTime());
        app.classes.tick(rl.getFrameTime());
        game.syncScreen(g, g.st.fullscreen);
        rl.beginDrawing();
        defer rl.endDrawing();
        return app.titleStep();
    }

    fn titleStep(app: *App) bool {
        const g = app.g;
        rl.clearBackground(look.BG);
        const note = app.note.text();
        const back = menu.backedAt(&g.st, g.screen);
        if (app.page != .main) menu.drawBack(&g.face, g.screen, &g.st);
        switch (app.page) {
            .main => {
                const rows = comptime blk: {
                    var ls: [MAIN_ROWS.len][]const u8 = undefined;
                    for (MAIN_ROWS, &ls) |r, *l| l.* = mainLabel(r);
                    break :blk ls;
                };
                const picked = app.title.stepAt(&g.st, MAIN_ROWS.len, g.screen);
                menu.draw(g.face, g.screen, comptime menu.caps(NAME), &rows, app.title.at, note);
                switch (MAIN_ROWS[picked orelse return true]) {
                    .new => {
                        if (!app.slotFree()) return app.refuse();
                        app.chosen = null;
                        app.goPage(.class);
                    },
                    .maps => {
                        if (!app.slotFree()) return app.refuse();
                        app.listing.scan();
                        if (app.listing.n == 0) {
                            app.say(atlas.NO_MAPS, .{});
                        } else app.goPage(.map);
                    },
                    .load => {
                        app.rescan();
                        app.goPage(.load);
                    },
                    .ossuary => app.goPage(.ossuary),
                    .options => {
                        app.goPage(.options);
                    },
                    .editor => app.toEdit(),
                    .quit => return false,
                }
            },
            .map => {
                var rows: [listing.Listing.MAX][]const u8 = undefined;
                const n = app.listing.n;
                if (n == 0) {
                    app.toTitle();
                    return true;
                }
                for (rows[0..n], 0..) |*l, i| l.* = app.listing.label(i);
                const picked = app.maps.stepAt(&g.st, n, g.screen);
                var where: [listing.PATH_MAX + 1]u8 = undefined;
                var dir: [listing.PATH_MAX]u8 = undefined;
                const shown = if (app.listing.entry(app.maps.at) == .up) std.fmt.bufPrintZ(&where, "Up from {s}", .{app.listing.dirPath(&dir)}) catch "" else app.listing.at(app.maps.at);
                menu.draw(g.face, g.screen, CHOOSE_MAP, rows[0..n], app.maps.at, shown);
                if (back) {
                    if (app.listing.up()) {
                        app.folderOpened();
                    } else app.toTitle();
                } else if (picked) |i| {
                    if (app.listing.open(i)) {
                        app.folderOpened();
                    } else {
                        app.choose(app.listing.at(i));
                        app.goPage(.class);
                    }
                }
            },
            .class => {
                app.loadHeroes();
                const picked = app.classes.step(&g.st, g.screen);
                app.classes.draw(g.face, &g.sprites, g.screen, "CHOOSE A HERO");
                if (back) {
                    app.fromClass();
                } else if (picked) |i| {
                    app.class = hero.CLASSES[i];
                    app.entry = .{};
                    app.goPage(.name);
                }
            },
            .name => {
                var buf: [naming.TITLE_MAX]u8 = undefined;
                const title = naming.titleOf(app.class, &buf);
                const outcome = app.entry.stepAt(&g.st, g.screen);
                app.loadHeroes();
                stage.beside(&g.sprites, app.class.kind(), naming.gridBox(g.screen), g.screen);
                naming.draw(&app.entry, g.face, g.screen, title, g.st.device);
                switch (outcome orelse return true) {
                    .back => app.goPage(.class),
                    .done => app.newRun(app.entry.name.done()),
                }
            },
            .load => {
                const action = app.saveStep(&g.st, g.screen);
                app.drawSaves();
                if (back) {
                    app.toTitle();
                } else if (action) |a| switch (a) {
                    .remove => |at| if (app.confirmDelete(at)) {
                        const gone = save.remove(at);
                        app.rescan();
                        if (gone) |_| app.say("Slot {d} deleted", .{save.number(at)}) else |e| app.say("Slot {d} did not delete ({s})", .{ save.number(at), @errorName(e) });
                    },
                    .load => |i| {
                        app.armed = null;
                        switch (app.list[i]) {
                            .run => app.loadRun(i),
                            .empty => app.say("Slot {d} is empty", .{save.number(i)}),
                            .unreadable => |why| app.say("Slot {d}: {s}, it will not load", .{ save.number(i), why.caption() }),
                        }
                    },
                };
            },
            .ossuary => {
                const bones = app.hall.slice();
                var lines: [ossuary.MAX][LINE]u8 = undefined;
                var rows: [ossuary.MAX][]const u8 = undefined;
                for (bones, rows[0..bones.len], lines[0..bones.len], 0..) |*e, *l, *b, i| l.* = boneLine(e, b, i);
                const picked = app.bones.stepAt(&g.st, bones.len, g.screen);
                menu.draw(g.face, g.screen, comptime menu.caps(OSSUARY), rows[0..bones.len], app.bones.at, if (bones.len == 0) NO_BONES else note);
                if (back) {
                    app.toTitle();
                } else if (picked != null) app.goPage(.bones);
            },
            .bones => {
                app.loadHeroes();
                if (app.hall.n > 0) app.drawBones(&app.hall.slice()[@min(app.bones.at, app.hall.n - 1)]);
                if (back or app.hall.n == 0) app.goPage(.ossuary);
            },
            .options => {
                const full = window.fullscreen();
                var rows: [OPTION_ROWS.len][]const u8 = undefined;
                for (OPTION_ROWS, &rows) |r, *l| l.* = switch (r) {
                    .fullscreen => menu.toggle(menu.named(OptionRow.fullscreen), full),
                    .debug => menu.named(r),
                };
                const picked = app.options.stepAt(&g.st, rows.len, g.screen);
                menu.draw(g.face, g.screen, comptime menu.caps(menu.named(MainRow.options)), &rows, app.options.at, null);
                if (back) {
                    app.toTitle();
                } else if (picked) |i| switch (OPTION_ROWS[i]) {
                    .fullscreen => game.syncScreen(g, true),
                    .debug => app.goPage(.debug),
                };
            },
            .debug => {
                var rows: [DEBUG_ROWS.len][]const u8 = undefined;
                var bufs: [DEBUG_ROWS.len][game.debugging.LABEL_MAX]u8 = undefined;
                inline for (DEBUG_ROWS, &rows, &bufs) |d, *l, *b| l.* = game.debugging.label(g, d.row, b);
                const picked = app.debugs.stepAt(&g.st, rows.len, g.screen);
                menu.draw(g.face, g.screen, comptime menu.caps(menu.named(OptionRow.debug)), &rows, app.debugs.at, DEBUG_ROWS[app.debugs.at].note);
                if (back) {
                    app.goPage(.options);
                } else if (picked) |i| {
                    if (game.debugging.option(g, DEBUG_ROWS[i].row)) |on| on.* = !on.*;
                }
            },
        }
        return true;
    }

    fn loadHeroes(app: *App) void {
        if (!stage.loadHeroes(&app.g.sprites)) return;
        app.g.art_ready = false;
        if (app.ed) |e| e.assets_stale = true;
    }

    fn refuse(app: *App) bool {
        app.say("All {d} save slots hold a run: {s} is where one is deleted", .{ save.SLOTS, menu.named(MainRow.load) });
        return true;
    }

    fn drawBones(app: *const App, e: *const ossuary.Entry) void {
        const g = app.g;
        const w = menu.listWidth(g.screen);
        const pad = menu.PANEL_PAD;
        var wrapped: font.Wrapped = undefined;
        var lines: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
        const n = font.wrap(&g.face, e.text(), font.BODY, w - 2 * pad, &wrapped, &lines);
        const panel_h = 2 * pad + BONES_SCALE * look.SPRITE_PX + 2 * BONES_GAP + font.BODY_LINE + @as(i32, @intCast(n)) * font.BODY_LINE;
        const lead = -menu.titleY(raster.rect(0, 0, 0, 0));
        const x = @divTrunc(g.screen.x - w, 2);
        const top = @divTrunc(g.screen.y - lead - panel_h, 2) + lead;
        var name: [hero.Name.MAX + 1]u8 = undefined;
        menu.heading(g.face, g.screen, menu.shout(&name, "{s}", .{e.name.text()}), top - lead, menu.TITLE, look.TEXT, look.UI_GOLD);
        rl.drawRectangleRec(raster.rect(x, top, w, panel_h), look.CARD_BG);
        var y = top + pad + BONES_SCALE * look.SPRITE_PX;
        stage.figure(&g.sprites, e.class.kind(), .{ .x = @divTrunc(g.screen.x, 2), .y = y }, BONES_SCALE, 1);
        y += BONES_GAP;
        var stats: [LINE + 1]u8 = undefined;
        const said = std.fmt.bufPrintZ(&stats, BONES_RANK ++ menu.SEP ++ "Kills {d}" ++ menu.SEP ++ hero.GOLD_FMT, .{ e.level, e.class.title(), e.renown, e.kills, e.gold }) catch "";
        menu.mid(g.face, g.screen, said, y, font.BODY, look.UI_GOLD);
        y += font.BODY_LINE + BONES_GAP;
        for (lines[0..n]) |l| {
            g.face.text(l, x + pad, y, font.BODY, look.TEXT);
            y += font.BODY_LINE;
        }
    }
};

fn boneLine(e: *const ossuary.Entry, buf: *[LINE]u8, i: usize) []const u8 {
    return std.fmt.bufPrint(buf, "{d}" ++ menu.SEP ++ "{s}" ++ menu.SEP ++ BONES_RANK, .{ i + 1, e.name.text(), e.level, e.class.title(), e.renown }) catch "";
}

fn slotLine(s: *const save.Slot, buf: *[LINE]u8, i: usize) [:0]const u8 {
    var sum: [LINE]u8 = undefined;
    const what: []const u8 = switch (s.*) {
        .empty => "Empty",
        .unreadable => |why| why.caption(),
        .run => |*r| r.line(&sum),
    };
    return std.fmt.bufPrintZ(buf, "{d}" ++ menu.SEP ++ "{s}", .{ save.number(i), what }) catch "";
}

/// About half the spotlight's way from one hero to the next.
const HEROES_MID_DT: f32 = 0.08;

pub fn shootHeroes(g: *game.Game) !void {
    try std.fs.cwd().makePath("shots/heroes");
    const alloc = std.heap.c_allocator;
    const map = try alloc.create(atlas.Atlas);
    defer alloc.destroy(map);
    var app = App{ .alloc = alloc, .g = g, .map = map, .edit_path = atlas.MAIN, .class = .wizard };
    app.entry.name = hero.Name.of("Arwen");
    g.st = .{ .device = .keys };
    const screen = g.screen;
    defer g.screen = screen;
    inline for (game.SCREENS) |size| {
        g.screen = size;
        const target = try rl.loadRenderTexture(size.x, size.y);
        defer rl.unloadRenderTexture(target);
        const at = std.fmt.comptimePrint("-{d}p.png", .{size.y});
        app.page = .class;
        app.classes = .on(0);
        try shootPage(&app, target, "shots/heroes/class" ++ at);
        _ = app.classes.step(&.{ .walk = .e }, size);
        app.classes.tick(HEROES_MID_DT);
        try shootPage(&app, target, "shots/heroes/class-moving" ++ at);
        app.page = .name;
        try shootPage(&app, target, "shots/heroes/name" ++ at);
    }
}

fn shootPage(app: *App, target: rl.RenderTexture2D, path: [:0]const u8) !void {
    rl.beginTextureMode(target);
    _ = app.titleStep();
    rl.endTextureMode();
    try game.shots.exportTarget(target, path);
}

var start_edit: ?[]const u8 = null;

test "mouse save deletion stays tied to its row through intermediate movement and needs two presses" {
    const alloc = std.testing.allocator;
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    const map = try alloc.create(atlas.Atlas);
    defer alloc.destroy(map);
    var app = App{ .alloc = alloc, .g = g, .map = map, .edit_path = atlas.MAIN, .list = @splat(.{ .unreadable = .damaged }) };
    var checked: usize = 0;
    for ([_]mathx.P{ game.SCREEN_720, game.SCREEN_1440 }) |screen| {
        for (0..save.SLOTS) |target| {
            for (0..save.SLOTS) |crossed| {
                _ = app.saveStep(&.{ .pointer = raster.middleAt(saveRowBox(screen, crossed)), .mouse_moved = true }, screen);
            }
            const box = saveDeleteBox(screen, target);
            try std.testing.expect(box.x >= 0 and box.x + box.width <= @as(f32, @floatFromInt(screen.x)));
            const click = input.State{ .pointer = raster.middleAt(box), .click = true };
            const first = app.saveStep(&click, screen).?;
            try std.testing.expectEqual(target, first.remove);
            try std.testing.expect(!app.confirmDelete(first.remove));
            _ = app.saveStep(&.{ .pointer = click.pointer, .mouse_moved = true }, screen);
            const second = app.saveStep(&click, screen).?;
            try std.testing.expectEqual(target, second.remove);
            try std.testing.expect(app.confirmDelete(second.remove));
            app.armed = null;
            checked += 1;
        }
        app.loads.at = 0;
        const remove = app.saveStep(&.{ .pressed = .initOne(DELETE) }, screen).?;
        try std.testing.expectEqual(@as(usize, 0), remove.remove);
        try std.testing.expect(!app.confirmDelete(remove.remove));
        _ = app.saveStep(&.{ .pointer = raster.middleAt(saveRowBox(screen, 1)), .mouse_moved = true }, screen);
        try std.testing.expect(app.armed == null);
        app.list[2] = .empty;
        try std.testing.expect(app.saveStep(&.{ .pointer = raster.middleAt(saveDeleteBox(screen, 2)), .click = true }, screen) == null);
        const row = saveRowBox(screen, 2);
        const load = app.saveStep(&.{ .pointer = .{ .x = @as(i32, @intFromFloat(row.x)) + 20, .y = raster.middleAt(row).y }, .click = true }, screen).?;
        try std.testing.expectEqual(@as(usize, 2), load.load);
        app.list[2] = .{ .unreadable = .damaged };
    }
    std.debug.print("mouse save actions: {d} row-specific confirmations, keyboard deletion, disarming and empty rows; no save I/O\n", .{checked});
}

fn fixtureHall() ossuary.Hall {
    const Bones = struct { name: []const u8, class: hero.Class, level: u16, kills: u32, renown: u32, said: []const u8 };
    const all = [_]Bones{
        .{ .name = "Arwen the Bold", .class = .archer, .level = 14, .kills = 212, .renown = 9120, .said = "Arwen the Bold, a level 14 archer, was slain by a bandit crossbowman on The Strand after 3 days below, having felled 212 foes and gathered 4310 gold. Her last arrow found its mark a heartbeat too late, and the bolt that answered it did not miss. " ++ ossuary.ENTOMBED },
        .{ .name = "Merrow", .class = .wizard, .level = 9, .kills = 96, .renown = 4410, .said = "Merrow, a level 9 wizard, choked in a bloat's gas in the Cistern after 2 days below, having felled 96 foes. " ++ ossuary.ENTOMBED },
        .{ .name = "Sir Gallant-Rhys", .class = .knight, .level = 7, .kills = 61, .renown = 2875, .said = "Sir Gallant-Rhys, a level 7 knight, was overrun by rats in the Wilds, having felled 61 foes. " ++ ossuary.ENTOMBED },
        .{ .name = "Pell", .class = .archer, .level = 2, .kills = 4, .renown = 120, .said = "Pell, a level 2 archer, was bitten to death by a rat on the first floor. " ++ ossuary.ENTOMBED },
    };
    var hall = ossuary.Hall{};
    for (all, 0..) |b, i| {
        var e = ossuary.Entry{ .name = hero.Name.of(b.name), .class = b.class, .level = b.level, .kills = b.kills, .gold = @intCast(b.kills * 20), .renown = b.renown, .seed = i };
        e.say(b.said);
        _ = hall.entomb(e);
    }
    return hall;
}

pub fn shootMenus(g: *game.Game, target: rl.RenderTexture2D) !void {
    const alloc = std.heap.c_allocator;
    const map = try alloc.create(atlas.Atlas);
    defer alloc.destroy(map);
    var app = App{ .alloc = alloc, .g = g, .map = map, .edit_path = atlas.MAIN };
    app.listing.scan();
    app.entry.name = hero.Name.of("Arwen");
    app.list[0] = .{ .unreadable = .damaged };
    app.list[1] = .{ .unreadable = .other_build };
    app.armed = 1;
    app.list[2] = .{ .run = .{ .name = hero.Name.of("Arwen the Bold"), .hp = 118, .max = 120, .gold = 12345, .node = null } };
    app.hall = fixtureHall();
    g.st = .{ .device = .keys };
    inline for (comptime std.enums.values(Page)) |page| {
        app.page = page;
        try shootPage(&app, target, "shots/mouse/title-" ++ @tagName(page) ++ ".png");
    }
    const screen = g.screen;
    inline for (game.SCREENS) |size| {
        g.screen = size;
        const sized = try rl.loadRenderTexture(size.x, size.y);
        defer rl.unloadRenderTexture(sized);
        inline for (.{ Page.main, Page.load, Page.ossuary, Page.bones }) |page| {
            app.page = page;
            try shootPage(&app, sized, std.fmt.comptimePrint("shots/mouse/title-{s}-{d}p.png", .{ @tagName(page), size.y }));
        }
    }
    g.screen = screen;
    var empty = App{ .alloc = alloc, .g = g, .map = map, .edit_path = atlas.MAIN, .page = .ossuary };
    try shootPage(&empty, target, "shots/mouse/title-ossuary-empty.png");
    var longest: [listing.STEM_MAX + 1]u8 = @splat('W');
    longest[listing.STEM_MAX] = 0;
    rl.beginTextureMode(target);
    rl.clearBackground(look.BG);
    menu.draw(g.face, g.screen, CHOOSE_MAP, &.{longest[0..listing.STEM_MAX :0]}, 0, null);
    rl.endTextureMode();
    try game.shots.exportTarget(target, "shots/mouse/title-long-row.png");
}

test "an editor arena uses a separate map and never opens a save slot" {
    const alloc = std.testing.allocator;
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    const w = try alloc.create(atlas.Atlas);
    defer alloc.destroy(w);
    const ed = try editor.Editor.create(alloc);
    defer ed.destroy();
    ed.dirty = true;
    ed.hist_at = 2;
    ed.hist_len = 3;
    const tiles = ed.map.node[0].plan.bespoke.tile;
    var app = App{ .alloc = alloc, .g = g, .map = w, .ed = ed, .edit_path = atlas.MAIN, .scene = .edit };
    app.fight(.slime);
    try std.testing.expectEqual(Scene.play, app.scene);
    try std.testing.expectEqual(game.Back.editor, g.back);
    try std.testing.expect(!g.permadeath and app.autosave == null);
    try std.testing.expect(g.sim.map == w and g.sim.map != ed.map);
    try std.testing.expect(ed.dirty and ed.hist_at == 2 and ed.hist_len == 3);
    try std.testing.expectEqualSlices(@import("map/grid.zig").Tile, &tiles, &ed.map.node[0].plan.bespoke.tile);
    try std.testing.expectEqual(@as(usize, 2), g.sim.pool.n);
    try std.testing.expectEqual(actor.Kind.slime, g.sim.pool.items[1].kind);
    try std.testing.expect(g.sim.lv.isLit(spar.FOE));
    std.debug.print("arena launch: selected slime visible, no save slot, edited tiles and undo position unchanged\n", .{});
}

/// `edit` opens the editor on that map first; null opens the title.
pub fn run(edit: ?[]const u8) !void {
    start_edit = edit;
    try withGame(.{ .vsync_hint = true, .window_resizable = true }, NAME, body, false);
}

pub fn withGame(flags: rl.ConfigFlags, title: [:0]const u8, comptime inner: fn (*game.Game) anyerror!void, comptime startup_shown: bool) !void {
    var startup = try std.time.Timer.start();
    const alloc = std.heap.c_allocator;
    rl.setConfigFlags(flags);
    rl.initWindow(window.WINDOW_W, window.WINDOW_H, title);
    if (!rl.isWindowReady()) return error.WindowFailed;
    defer rl.closeWindow();
    input.claimKeys();
    input.mapPads();
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    g.debug.vsync = flags.vsync_hint;
    defer game.unloadGraphics(g);
    g.face = font.Face.load(look.TILE_CODEPOINTS);
    defer g.face.unload();
    if (startup_shown) std.debug.print("startup: {d:.3} ms, {d} map textures\n", .{ shots.ms(startup.read()), g.sprites.count() });
    try inner(g);
}

const Headless = struct { flag: [:0]const u8, body: fn (*game.Game) anyerror!void, startup_shown: bool = false };

pub const HEADLESS = [_]Headless{
    .{ .flag = "--shot", .body = shots.shoot },
    .{ .flag = "--shot-ui", .body = shots.shootUi },
    .{ .flag = "--shot-debug", .body = shots.shootDebug },
    .{ .flag = "--shot-cinema", .body = shots.shootCinema },
    .{ .flag = "--bench", .body = shots.benchWalk, .startup_shown = true },
};

pub fn headless(comptime h: Headless) !void {
    try withGame(.{ .window_hidden = true }, NAME ++ " " ++ h.flag, h.body, h.startup_shown);
    try shaders.expectShaders();
}

fn body(g: *game.Game) !void {
    const alloc = std.heap.c_allocator;
    const w = try alloc.create(atlas.Atlas);
    defer alloc.destroy(w);
    const plain = if (start_edit) |p| atlas.plain(p) else true;
    const hall = ossuary.load();
    var app = App{ .alloc = alloc, .g = g, .map = w, .edit_path = if (plain) start_edit orelse atlas.MAIN else atlas.MAIN, .hall = hall catch .{}, .unread = if (hall) |_| null else |e| e };
    defer if (app.ed) |e| e.destroy();
    defer app.leaveRun();
    defer app.reburied();
    app.toTitle();
    if (app.unread) |e| app.say(ossuary.NOT_READ, .{@errorName(e)});
    if (!plain) {
        app.say("The map to edit is named in letters the game cannot draw; {s} opens {s}", .{ menu.named(MainRow.editor), atlas.MAIN });
    } else if (start_edit != null) app.toEdit();
    while (app.frame()) {}
}
