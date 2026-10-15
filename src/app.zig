const std = @import("std");
const rl = @import("raylib");
const game = @import("game.zig");
const editor = @import("edit/editor.zig");
const atlas = @import("world/atlas.zig");
const menu = @import("ui/menu.zig");
const naming = @import("ui/naming.zig");
const look = @import("gfx/look.zig");
const hero = @import("play/hero.zig");
const save = @import("save.zig");
const input = @import("core/input.zig");
const skillbar = @import("play/skillbar.zig");

const Scene = enum { title, play, edit };
const Page = enum { main, world, class, name, load, options, debug };
const MainRow = enum {
    new,
    worlds,
    load,
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
const DebugRow = enum {
    unkillable,

    fn note(r: DebugRow) [:0]const u8 {
        return switch (r) {
            .unkillable => comptime std.fmt.comptimePrint("{s} keeps the hero on {d} hp whatever strikes it", .{ menu.named(DebugRow.unkillable), game.UNKILLABLE_HP }),
        };
    }
};
const DEBUG_ROWS = std.enums.values(DebugRow);
const DELETE = menu.REMOVE;

const NAME = "roguelike";
const LINE = menu.NOTE_MAX;

const App = struct {
    alloc: std.mem.Allocator,
    g: *game.Game,
    world: *atlas.Atlas,
    ed: ?*editor.Editor = null,
    edit_path: []const u8,
    scene: Scene = .title,
    page: Page = .main,
    title: menu.Menu = .{},
    worlds: menu.Menu = .{},
    listing: atlas.Listing = .{},
    /// The world picked in Worlds; null plays `atlas.START`.
    chosen: ?[]const u8 = null,
    chosen_buf: [atlas.PATH_MAX]u8 = undefined,
    classes: menu.Menu = .{},
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
    note: menu.Note(menu.NOTE_MAX) = .{},

    fn say(app: *App, comptime fmt: []const u8, args: anytype) void {
        app.note.say(fmt, args);
    }

    fn toTitle(app: *App) void {
        app.scene = .title;
        app.goPage(.main);
    }

    fn goPage(app: *App, p: Page) void {
        app.note.clear();
        app.page = p;
    }

    fn choose(app: *App, path: []const u8) void {
        const n = @min(path.len, app.chosen_buf.len);
        @memcpy(app.chosen_buf[0..n], path[0..n]);
        app.chosen = app.chosen_buf[0..n];
    }

    fn fromClass(app: *App) void {
        if (app.chosen == null) return app.toTitle();
        app.goPage(.world);
    }

    /// On the world it last had open, read afresh; the first time on `edit_path`.
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

    fn slotFree(app: *App) bool {
        app.rescan();
        return save.free(&app.list) != null;
    }

    fn newRun(app: *App, name: hero.Name) void {
        const g = app.g;
        const slot = save.free(&app.list) orelse return app.toTitle();
        const path = app.chosen orelse atlas.START;
        g.class = app.class;
        if (app.world.load(app.alloc, path)) {
            if (!app.world.standable(app.world.start, &g.lv)) {
                app.toTitle();
                return app.say(atlas.NO_FLOOR, .{path});
            }
            game.beginWorld(g, app.world);
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
        save.load(app.alloc, slot, app.g, app.world) catch |e| return app.say("Slot {d} did not load ({s})", .{ save.number(slot), @errorName(e) });
        app.inSlot(slot, null);
    }

    fn inSlot(app: *App, slot: usize, fresh: ?hero.Name) void {
        app.leaveRun();
        app.play(.title, fresh);
        app.autosave = save.Autosave.init(app.alloc, slot);
    }

    fn playTest(app: *App, from: atlas.Start) void {
        app.leaveRun();
        app.g.class = hero.DEFAULT;
        game.beginWorldAt(app.g, app.ed.?.world, from, game.freshSeed());
        app.g.st.device = .keys;
        app.play(.editor, hero.DEFAULT.unnamed());
    }

    fn play(app: *App, back: game.Back, fresh: ?hero.Name) void {
        const g = app.g;
        if (fresh) |name| {
            g.name = name;
            g.bar = skillbar.Bar.of(g.class);
        }
        g.permadeath = back == .title;
        g.back = back;
        app.scene = .play;
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
            if (closing or d.play or d.play_here) {
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
        g.st.playing = false;
        g.st.update(rl.getFrameTime());
        g.st.spend(skillbar.BINDS);
        game.syncScreen(g, g.st.fullscreen);
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(look.BG);
        const note = app.note.text();
        const back = menu.backed(&g.st);
        switch (app.page) {
            .main => {
                const rows = comptime blk: {
                    var ls: [MAIN_ROWS.len][]const u8 = undefined;
                    for (MAIN_ROWS, &ls) |r, *l| l.* = menu.named(r);
                    break :blk ls;
                };
                const picked = app.title.step(&g.st, MAIN_ROWS.len);
                menu.draw(g.face, g.screen, comptime menu.caps(NAME), &rows, app.title.at, note);
                switch (MAIN_ROWS[picked orelse return true]) {
                    .new => {
                        if (!app.slotFree()) return app.refuse();
                        app.chosen = null;
                        app.goPage(.class);
                    },
                    .worlds => {
                        if (!app.slotFree()) return app.refuse();
                        app.listing.scan();
                        if (app.listing.n == 0) {
                            app.say(atlas.NO_WORLDS, .{});
                        } else app.goPage(.world);
                    },
                    .load => {
                        app.rescan();
                        app.goPage(.load);
                    },
                    .options => {
                        app.goPage(.options);
                    },
                    .editor => app.toEdit(),
                    .quit => return false,
                }
            },
            .world => {
                var rows: [atlas.Listing.MAX][]const u8 = undefined;
                const n = app.listing.n;
                if (n == 0) {
                    app.toTitle();
                    return true;
                }
                for (rows[0..n], 0..) |*l, i| l.* = app.listing.label(i);
                const picked = app.worlds.step(&g.st, n);
                var where: [atlas.PATH_MAX + 1]u8 = undefined;
                var dir: [atlas.PATH_MAX]u8 = undefined;
                const shown = if (app.listing.entry(app.worlds.at) == .up) std.fmt.bufPrintZ(&where, "Up from {s}", .{app.listing.dirPath(&dir)}) catch "" else app.listing.at(app.worlds.at);
                menu.draw(g.face, g.screen, "CHOOSE A WORLD", rows[0..n], app.worlds.at, shown);
                if (back) {
                    if (app.listing.up()) {
                        app.worlds = .{};
                    } else app.toTitle();
                } else if (picked) |i| {
                    if (app.listing.open(i)) {
                        app.worlds = .{};
                    } else {
                        app.choose(app.listing.at(i));
                        app.goPage(.class);
                    }
                }
            },
            .class => {
                var rows: [hero.CLASSES.len][]const u8 = undefined;
                for (hero.CLASSES, &rows) |c, *l| l.* = c.title();
                const picked = app.classes.step(&g.st, rows.len);
                menu.draw(g.face, g.screen, "CHOOSE A HERO", &rows, app.classes.at, hero.CLASSES[app.classes.at].blurb());
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
                const outcome = app.entry.step(&g.st);
                naming.draw(&app.entry, g.face, g.screen, title);
                switch (outcome orelse return true) {
                    .back => app.goPage(.class),
                    .done => app.newRun(app.entry.name.done()),
                }
            },
            .load => {
                var lines: [save.SLOTS][LINE]u8 = undefined;
                var rows: [save.SLOTS][]const u8 = undefined;
                for (&app.list, &lines, &rows, 0..) |*s, *b, *l, i| l.* = slotLine(s, b, i);
                const was = app.loads.at;
                const picked = app.loads.step(&g.st, rows.len);
                if (app.loads.at != was) {
                    app.armed = null;
                    app.note.clear();
                }
                menu.draw(g.face, g.screen, comptime menu.caps(menu.named(MainRow.load)), &rows, app.loads.at, note);
                const at = app.loads.at;
                if (back) {
                    app.toTitle();
                } else if (g.st.hit(DELETE) and app.list[at] != .empty) {
                    if (app.armed == at) {
                        const gone = save.remove(at);
                        app.rescan();
                        if (gone) |_| app.say("Slot {d} deleted", .{save.number(at)}) else |e| app.say("Slot {d} did not delete ({s})", .{ save.number(at), @errorName(e) });
                    } else {
                        app.armed = at;
                        app.say("Delete slot {d}? It cannot be undone", .{save.number(at)});
                    }
                } else if (picked) |i| {
                    app.armed = null;
                    switch (app.list[i]) {
                        .run => app.loadRun(i),
                        .empty => app.say("Slot {d} is empty", .{save.number(i)}),
                        .unreadable => |why| app.say("Slot {d}: {s}, it will not load", .{ save.number(i), why.caption() }),
                    }
                }
            },
            .options => {
                const full = game.fullscreen();
                var rows: [OPTION_ROWS.len][]const u8 = undefined;
                for (OPTION_ROWS, &rows) |r, *l| l.* = switch (r) {
                    .fullscreen => menu.toggle(menu.named(OptionRow.fullscreen), full),
                    .debug => menu.named(r),
                };
                const picked = app.options.step(&g.st, rows.len);
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
                for (DEBUG_ROWS, &rows) |r, *l| l.* = switch (r) {
                    .unkillable => menu.toggle(menu.named(DebugRow.unkillable), g.unkillable),
                };
                const picked = app.debugs.step(&g.st, rows.len);
                menu.draw(g.face, g.screen, comptime menu.caps(menu.named(OptionRow.debug)), &rows, app.debugs.at, DEBUG_ROWS[app.debugs.at].note());
                if (back) {
                    app.goPage(.options);
                } else if (picked) |i| switch (DEBUG_ROWS[i]) {
                    .unkillable => g.unkillable = !g.unkillable,
                };
            },
        }
        return true;
    }

    fn refuse(app: *App) bool {
        app.say("All {d} save slots hold a run: {s} is where one is deleted", .{ save.SLOTS, menu.named(MainRow.load) });
        return true;
    }
};

fn slotLine(s: *const save.Slot, buf: *[LINE]u8, i: usize) [:0]const u8 {
    var sum: [LINE]u8 = undefined;
    const what: []const u8 = switch (s.*) {
        .empty => "Empty",
        .unreadable => |why| why.caption(),
        .run => |*r| r.line(&sum),
    };
    return std.fmt.bufPrintZ(buf, "{d}" ++ menu.SEP ++ "{s}", .{ save.number(i), what }) catch "";
}

var start_edit: ?[]const u8 = null;

/// `edit` opens the editor on that world first; null opens the title.
pub fn run(edit: ?[]const u8) !void {
    start_edit = edit;
    try game.withGame(.{ .vsync_hint = true }, NAME, body);
}

fn body(g: *game.Game) !void {
    const alloc = std.heap.c_allocator;
    const w = try alloc.create(atlas.Atlas);
    defer alloc.destroy(w);
    const plain = if (start_edit) |p| atlas.plain(p) else true;
    var app = App{ .alloc = alloc, .g = g, .world = w, .edit_path = if (plain) start_edit orelse atlas.MAIN else atlas.MAIN };
    defer if (app.ed) |e| e.destroy();
    defer app.leaveRun();
    app.toTitle();
    if (!plain) {
        app.say("The world to edit is named in letters the game cannot draw; {s} opens {s}", .{ menu.named(MainRow.editor), atlas.MAIN });
    } else if (start_edit != null) app.toEdit();
    while (app.frame()) {}
}
