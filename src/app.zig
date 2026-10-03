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

const Scene = enum { title, play, edit };
const Page = enum { main, world, class, name, load, options, debug };
const MainRow = enum {
    new,
    load,
    options,
    editor,
    quit,

    fn label(r: MainRow) [:0]const u8 {
        return switch (r) {
            .new => "New",
            .load => "Load",
            .options => "Options",
            .editor => "Editor",
            .quit => "Quit",
        };
    }
};
const MAIN_ROWS = std.enums.values(MainRow);
const OptionRow = enum {
    fullscreen,
    debug,

    fn label(r: OptionRow) [:0]const u8 {
        return switch (r) {
            .fullscreen => "Fullscreen",
            .debug => "Debug",
        };
    }
};
const OPTION_ROWS = std.enums.values(OptionRow);
const DebugRow = enum {
    unkillable,

    fn label(r: DebugRow) [:0]const u8 {
        return switch (r) {
            .unkillable => "Unkillable",
        };
    }
};
const DEBUG_ROWS = std.enums.values(DebugRow);
const DELETE = input.Button.y;
const NAME = "roguelike";
const LINE: usize = 160;

/// A page's title: the row that opens it, in capitals.
fn caps(comptime s: []const u8) [:0]const u8 {
    var b: [s.len:0]u8 = undefined;
    for (s, 0..) |c, i| b[i] = std.ascii.toUpper(c);
    const out = b;
    return &out;
}

const App = struct {
    alloc: std.mem.Allocator,
    g: *game.Game,
    /// The world being played: read fresh from disk for New, or out of the save for Load.
    world: *atlas.Atlas,
    ed: ?*editor.Editor = null,
    edit_path: []const u8,
    scene: Scene = .title,
    page: Page = .main,
    title: menu.Menu = .{},
    worlds: menu.Menu = .{},
    /// The worlds New picks from; with none, it plays one generated floor.
    listing: atlas.Listing = .{},
    classes: menu.Menu = .{},
    loads: menu.Menu = .{},
    options: menu.Menu = .{},
    debugs: menu.Menu = .{},
    class: hero.Class = .archer,
    entry: naming.Entry = .{},
    list: [save.SLOTS]save.Slot = @splat(.empty),
    /// The slot the next press of `DELETE` deletes.
    armed: ?usize = null,
    /// The run being played in a slot; null for a play-test.
    autosave: ?save.Autosave = null,
    note: menu.Note(menu.NOTE_MAX) = .{},

    fn say(app: *App, comptime fmt: []const u8, args: anytype) void {
        app.note.say(fmt, args);
    }

    /// No world to pick: New plays one generated floor.
    fn generated(app: *const App) bool {
        return app.listing.n == 0;
    }

    fn toTitle(app: *App) void {
        app.scene = .title;
        app.page = .main;
        app.listing.scan();
        if (app.generated()) {
            app.say(atlas.NO_WORLDS ++ ": {s} makes one generated floor", .{MainRow.new.label()});
        } else app.say("{s} picks a world in {s}", .{ MainRow.new.label(), atlas.DIR });
    }

    /// Its world picked, or none to pick from.
    fn toClass(app: *App) void {
        app.note.clear();
        app.page = .class;
    }

    /// Back from choosing a hero: to the worlds, or the title when there were none.
    fn fromClass(app: *App) void {
        if (app.generated()) return app.toTitle();
        app.note.clear();
        app.page = .world;
    }

    fn toEdit(app: *App) void {
        const ed = app.ed orelse blk: {
            const e = editor.Editor.create(app.alloc) catch return app.say("The editor did not start (out of memory)", .{});
            app.ed = e;
            break :blk e;
        };
        ed.open(app.edit_path) catch |e| {
            app.toTitle();
            return app.say("{s} did not load ({s}); the editor will not open over it", .{ app.edit_path, @errorName(e) });
        };
        app.scene = .edit;
    }

    fn rescan(app: *App) void {
        app.list = save.slots();
        app.armed = null;
    }

    /// Into the first free slot, which New made sure of.
    fn newRun(app: *App, name: hero.Name) void {
        const g = app.g;
        const slot = save.free(&app.list) orelse return app.toTitle();
        if (app.generated()) {
            game.begin(g, game.freshSeed());
        } else {
            var buf: [atlas.PATH_MAX]u8 = undefined;
            const path = buf[0..app.listing.at(app.worlds.at).len];
            @memcpy(path, app.listing.at(app.worlds.at));
            app.world.load(app.alloc, path) catch |e| {
                app.toTitle();
                return app.say("{s} did not load ({s})", .{ path, @errorName(e) });
            };
            if (!app.world.standable(app.world.start, &g.lv)) {
                app.toTitle();
                return app.say(atlas.NO_FLOOR, .{path});
            }
            game.beginWorld(g, app.world);
        }
        app.inSlot(slot, name);
        app.autosave.?.flush(g);
    }

    fn loadRun(app: *App, slot: usize) void {
        save.load(app.alloc, slot, app.g, app.world) catch |e| return app.say("Slot {d} did not load ({s})", .{ save.number(slot), @errorName(e) });
        app.inSlot(slot, null);
    }

    /// A new run is named and its skill bar laid out afresh; a loaded one keeps its own.
    fn inSlot(app: *App, slot: usize, fresh: ?hero.Name) void {
        app.leaveRun();
        app.play(.title, fresh);
        app.autosave = save.Autosave.init(app.alloc, slot);
    }

    fn playTest(app: *App, from: atlas.Start) void {
        game.beginWorldAt(app.g, app.ed.?.world, from, game.freshSeed());
        app.leaveRun();
        app.play(.editor, hero.Class.archer.unnamed());
    }

    fn play(app: *App, back: game.Back, fresh: ?hero.Name) void {
        const g = app.g;
        if (fresh) |name| {
            g.name = name;
            g.bar = .{};
        }
        g.permadeath = back == .title;
        g.back = back;
        app.scene = .play;
    }

    /// Before the run is left: its last turns are written, through any door it stands on.
    fn leaveRun(app: *App) void {
        if (app.autosave) |*a| {
            game.leave(app.g);
            if (a.close(app.g)) |e| app.say("The last save did not write ({s})", .{@errorName(e)});
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
                        a.end(g);
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
        g.st.update(rl.getFrameTime());
        game.syncScreen(g, g.st.fullscreen);
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(look.BG);
        const note = app.note.text();
        const back = menu.backed(&g.st);
        switch (app.page) {
            .main => {
                var rows: [MAIN_ROWS.len][:0]const u8 = undefined;
                for (MAIN_ROWS, &rows) |r, *l| l.* = r.label();
                const picked = app.title.step(&g.st, MAIN_ROWS.len);
                menu.draw(g.face, g.screen, comptime caps(NAME), &rows, app.title.at, note, null);
                switch (MAIN_ROWS[picked orelse return true]) {
                    .new => {
                        app.rescan();
                        if (save.free(&app.list) == null) return app.refuse();
                        app.listing.scan();
                        app.note.clear();
                        app.page = if (app.generated()) .class else .world;
                    },
                    .load => {
                        app.rescan();
                        app.note.clear();
                        app.page = .load;
                    },
                    .options => {
                        app.note.clear();
                        app.page = .options;
                    },
                    .editor => app.toEdit(),
                    .quit => return false,
                }
            },
            .world => {
                var names: [atlas.Listing.MAX][atlas.PATH_MAX + 1]u8 = undefined;
                var rows: [atlas.Listing.MAX][:0]const u8 = undefined;
                const n = app.listing.n;
                for (names[0..n], rows[0..n], 0..) |*b, *l, i| l.* = std.fmt.bufPrintZ(b, "{s}", .{app.listing.stem(i)}) catch "";
                const picked = app.worlds.step(&g.st, n);
                var path: [atlas.PATH_MAX + 1]u8 = undefined;
                const where = std.fmt.bufPrintZ(&path, "{s}", .{app.listing.at(app.worlds.at)}) catch "";
                menu.draw(g.face, g.screen, "CHOOSE A WORLD", rows[0..n], app.worlds.at, where, menu.BACK_LABEL);
                if (back) {
                    app.toTitle();
                } else if (picked) |_| app.toClass();
            },
            .class => {
                var rows: [hero.CLASSES.len][:0]const u8 = undefined;
                for (hero.CLASSES, &rows) |c, *l| l.* = c.title();
                const picked = app.classes.step(&g.st, rows.len);
                menu.draw(g.face, g.screen, "CHOOSE A HERO", &rows, app.classes.at, hero.CLASSES[app.classes.at].blurb(), menu.BACK_LABEL);
                if (back) {
                    app.fromClass();
                } else if (picked) |i| {
                    app.class = hero.CLASSES[i];
                    app.entry = .{};
                    app.page = .name;
                }
            },
            .name => {
                var buf: [naming.TITLE_MAX]u8 = undefined;
                const title = naming.titleOf(app.class, &buf);
                const outcome = app.entry.step(&g.st);
                naming.draw(&app.entry, g.face, g.screen, title);
                switch (outcome orelse return true) {
                    .back => app.page = .class,
                    .done => app.newRun(app.entry.name.done()),
                }
            },
            .load => {
                var lines: [save.SLOTS][LINE]u8 = undefined;
                var rows: [save.SLOTS][:0]const u8 = undefined;
                for (&app.list, &lines, &rows, 0..) |*s, *b, *l, i| l.* = slotLine(s, b, i);
                const was = app.loads.at;
                const picked = app.loads.step(&g.st, rows.len);
                if (app.loads.at != was) {
                    app.armed = null;
                    app.note.clear();
                }
                menu.draw(g.face, g.screen, comptime caps(MainRow.load.label()), &rows, app.loads.at, note, menu.BACK_LABEL ++ menu.SEP ++ comptime DELETE.caption() ++ " delete");
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
                        app.say("{s} again deletes slot {d}; it cannot be undone", .{ DELETE.caption(), save.number(at) });
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
                var rows: [OPTION_ROWS.len][:0]const u8 = undefined;
                for (OPTION_ROWS, &rows) |r, *l| l.* = switch (r) {
                    .fullscreen => menu.toggle(OptionRow.fullscreen.label(), full),
                    .debug => r.label(),
                };
                const picked = app.options.step(&g.st, rows.len);
                menu.draw(g.face, g.screen, comptime caps(MainRow.options.label()), &rows, app.options.at, null, menu.BACK_LABEL);
                if (back) {
                    app.toTitle();
                } else if (picked) |i| switch (OPTION_ROWS[i]) {
                    .fullscreen => game.syncScreen(g, true),
                    .debug => app.page = .debug,
                };
            },
            .debug => {
                var rows: [DEBUG_ROWS.len][:0]const u8 = undefined;
                for (DEBUG_ROWS, &rows) |r, *l| l.* = switch (r) {
                    .unkillable => menu.toggle(DebugRow.unkillable.label(), g.unkillable),
                };
                const picked = app.debugs.step(&g.st, rows.len);
                menu.draw(g.face, g.screen, comptime caps(OptionRow.debug.label()), &rows, app.debugs.at, comptime DebugRow.unkillable.label() ++ " keeps the hero on 1 hp whatever strikes it", menu.BACK_LABEL);
                if (back) {
                    app.page = .options;
                } else if (picked) |i| switch (DEBUG_ROWS[i]) {
                    .unkillable => g.unkillable = !g.unkillable,
                };
            },
        }
        return true;
    }

    fn refuse(app: *App) bool {
        app.say("All {d} save slots hold a run: {s} is where one is deleted", .{ save.SLOTS, MainRow.load.label() });
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
pub fn run(edit: ?[]const u8) void {
    start_edit = edit;
    game.withGame(.{ .vsync_hint = true }, NAME, body);
}

fn body(g: *game.Game) void {
    const alloc = std.heap.c_allocator;
    const w = alloc.create(atlas.Atlas) catch return;
    defer alloc.destroy(w);
    const plain = if (start_edit) |p| atlas.plain(p) else true;
    var app = App{ .alloc = alloc, .g = g, .world = w, .edit_path = if (plain) start_edit orelse atlas.MAIN else atlas.MAIN };
    defer if (app.ed) |e| e.destroy();
    defer app.leaveRun();
    app.toTitle();
    if (!plain) {
        app.say("The world to edit is named in letters the game cannot draw; {s} opens {s}", .{ MainRow.editor.label(), atlas.MAIN });
    } else if (start_edit != null) app.toEdit();
    while (app.frame()) {}
}
