const std = @import("std");
const items = @import("play/items.zig");
const progress = @import("play/progress.zig");
const journal = @import("ui/journal.zig");
pub const ossuary = @import("play/ossuary.zig");
const rl = @import("raylib");

const mathx = @import("core/mathx.zig");
const input = @import("core/input.zig");
const grid = @import("map/grid.zig");
const gen = @import("map/gen.zig");
const atlas = @import("map/atlas.zig");
const menu = @import("ui/menu.zig");
const hud = @import("ui/hud.zig");
const book = @import("ui/book.zig");
const heroes = @import("play/hero.zig");
const actor = @import("play/actor.zig");
const turn_clock = @import("play/clock.zig");
const pack = @import("play/pack.zig");
const skillbar = @import("play/skillbar.zig");
const look = @import("gfx/look.zig");
const raster = @import("gfx/raster.zig");
const prompt_icon = @import("gfx/prompt_icon.zig");
const light = @import("gfx/light.zig");
const shadow = @import("gfx/shadow.zig");
const font = @import("gfx/font.zig");
const fx = @import("gfx/fx.zig");
const cloud = @import("gfx/cloud.zig");
const cinema = @import("gfx/cinema.zig");
const vignette = @import("gfx/vignette.zig");
const sky = @import("gfx/sky.zig");
const weather = @import("gfx/weather.zig");
const climate = @import("map/climate.zig");
pub const shots = @import("game/shots.zig");
pub const scene = @import("game/scene.zig");
pub const overlay = @import("game/overlay.zig");
pub const character = @import("game/character.zig");
pub const debugging = @import("game/debug.zig");
pub const combat = @import("game/combat.zig");
pub const harness = @import("game/harness.zig");
pub const mouseControls = @import("game/mouse.zig");
const window = @import("core/window.zig");
const binds = @import("game/binds.zig");
const skills = @import("game/skills.zig");
pub const presentation = @import("game/presentation.zig");
pub const simulation = @import("game/sim.zig");
pub const epitaph = @import("game/epitaph.zig");

const P = mathx.P;

pub const WINDOW = P{ .x = window.WINDOW_W, .y = window.WINDOW_H };
/// Screens the shots and layout tests cover besides the window's.
pub const SCREEN_720 = P{ .x = 1280, .y = 720 };
pub const SCREEN_1080 = P{ .x = 1920, .y = 1080 };
pub const SCREEN_1440 = P{ .x = 2560, .y = 1440 };
pub const SCREENS = [_]P{ SCREEN_720, SCREEN_1080, SCREEN_1440 };
pub const CELL: i32 = 64;
pub const CELL_F: f32 = @floatFromInt(CELL);
pub const HALF_CELL: i32 = @divTrunc(CELL, 2);
pub const MAP_PX = P{ .x = grid.W * CELL, .y = grid.H * CELL };

pub fn authored(comptime px: i32) i32 {
    return @divExact(CELL * px, look.SPRITE_PX);
}
pub const GLYPH: i32 = authored(look.GLYPH_PX);
pub const LINE_W: i32 = authored(2);
const DEAD_TITLE_DY: i32 = -200;
const DEAD_STORY_DY: i32 = -120;
const DEAD_STORY_LINES: usize = 7;
const DEAD_SCORE_DY: i32 = DEAD_STORY_DY + @as(i32, DEAD_STORY_LINES) * font.BODY_LINE + 16;
const DEAD_ACTION_DY: i32 = DEAD_SCORE_DY + 50;
pub const SLOT_PX: i32 = 48;
pub const SLOT_GAP: i32 = 8;
pub const SLOT_STEP: i32 = SLOT_PX + SLOT_GAP;
const GROUP_GAP: i32 = 16;
pub const KEY_GAP: i32 = 6;
pub const PROMPT_PX: i32 = 25;
pub const SLOT_XS = blk: {
    var xs: [skillbar.SLOTS.len]i32 = undefined;
    var x: i32 = 0;
    var i: usize = 0;
    for (skillbar.GROUPS, 0..) |grp, gi| {
        if (gi > 0) x += GROUP_GAP - SLOT_GAP;
        for (grp) |_| {
            xs[i] = x;
            x += SLOT_STEP;
            i += 1;
        }
    }
    break :blk xs;
};
pub const SKILLS_W: i32 = SLOT_XS[SLOT_XS.len - 1] + SLOT_PX;
pub const SLOT_COLUMN_H: i32 = SLOT_PX + KEY_GAP + PROMPT_PX;
/// Cells past the view a prop's shadow can reach into it from.
pub const CAST_MARGIN: i32 = @intFromFloat(@ceil(shadow.CAST_REACH));
const CAM_EASE: f32 = 12.0;
/// One walk repeat, so the hops of a walk, held or routed, join end to end.
pub const GLIDE_S: f32 = input.Stepper.ARR;
/// What slides, staggers and bumps are paced by, apart from the walk.
const BEAT_S: f32 = 0.13;
/// Pixels, at the top of each glide's hop.
pub const HOP_PX: f32 = @floatFromInt(authored(10));
pub const SLIDE_S: f32 = BEAT_S * 2;
pub const STAGGER_S: f32 = BEAT_S * 0.5;
pub const BUMP_S: f32 = BEAT_S;
/// Of the bump, the share out to the blow.
pub const BUMP_HIT: f32 = 0.5;
pub const BUMP_LANDS: f32 = BUMP_S * BUMP_HIT;
/// From a spell cast round the hero to its blows landing.
pub const CAST_S: f32 = BUMP_LANDS;
/// From one body a bolt leaps on from to the next.
pub const ZAP_S: f32 = 0.08;
pub const BUMP_PX: f32 = CELL_F * 0.35;
/// Ease-out-back's overshoot constant: 1.165 carries a slide 5% past its cell (1.70158, the usual one, 10%).
pub const SLIDE_BACK: f32 = 1.165;
/// `gen.build` rolls from the bare seed; without the salt the packs replay the floor's rolls.
const PLAY_SALT: u64 = 0x9E37_79B9_7F4A_7C15;
/// Loot rolls on its own stream, so a drop does not shift the fight's rolls.
const LOOT_SALT: u64 = 0x10_07_A11;
/// Reach of Interact: underfoot and the cells beside the hero.
pub const INTERACT_REACH: i32 = 1;
const NEARBY_MAX = items.GROUND_MAX + grid.Cells.square(INTERACT_REACH);
pub const NearbyBuf = [NEARBY_MAX]book.Nearby;

const CONFIRM = menu.CONFIRM;
const BACK = menu.BACK;
const CHARACTER = menu.CHARACTER;

comptime {
    std.debug.assert(@mod(CELL, look.SPRITE_PX) == 0);
    std.debug.assert(GLYPH <= CELL);
    std.debug.assert(SKILLS_W <= hud.SKILLS_MAX_W);
    std.debug.assert(hud.PLATE_PAD + SLOT_COLUMN_H <= hud.PLATE_H);
    std.debug.assert(prompt_icon.labelPx(PROMPT_PX) == font.LABEL);
}

pub const Mode = enum { play, aim, bind, dead, pause, inspect };

pub const Spot = union(enum) {
    life,
    mana,
    log,
    /// Of `skillbar.SLOTS`.
    slot: usize,
    status: fx.Status,
};

pub const Back = enum { title, editor };

pub const Exit = enum { back, quit };

const PAUSE = menu.PAUSE;
pub const PausePage = enum { main, debug, character };
pub const PauseRow = enum { resume_, debug, back, quit };
pub const PAUSE_ROWS = std.enums.values(PauseRow);

pub fn rowAt(row: anytype) usize {
    const Row = @TypeOf(row);
    return std.mem.indexOfScalar(Row, std.enums.values(Row), row).?;
}

pub const Log = journal.Log;

/// Coordinates input, the simulation, its picture and the graphics that draw it.
pub const Game = struct {
    sim: simulation.Simulation,
    pic: presentation.Presentation = .{},
    mode: Mode = .play,
    /// Drawn in place of `.dead` until the lethal turn is.
    died_in: Mode = .play,
    pause_menu: menu.Menu = .{},
    pause_page: PausePage = .main,
    debug: debugging.State = .{},
    character: book.Book = .{},
    /// What Character's Nearby page lists, filled afresh each step and draw; too big for the stack each frame.
    nearby: NearbyBuf = undefined,
    back: Back = .title,
    exit: ?Exit = null,
    /// Saved runs return to their caller on death instead of restarting.
    permadeath: bool = false,
    /// Where a saved run's hero is entombed if renowned enough; the app owns and writes it.
    hall: ?*ossuary.Hall = null,
    /// How the hero died, written as it happened.
    epitaph: ?ossuary.Entry = null,
    perf: debugging.Perf = .{},
    st: input.State = .{},
    mouse: mouseControls.State = .{},
    bar: skillbar.Bar = .{},
    binds: binds.Binds = .{},
    aim_by: input.Button = .x,
    aim_act: skillbar.Act = .shoot,
    aim_set: skillbar.Set = .primary,
    mark: P = .{ .x = 0, .y = 0 },
    /// Kept between inspections, so the next opens where the last left off.
    inspecting: Spot = .{ .slot = 0 },
    /// Map pixels, eased toward the hero. Nothing in the simulation reads it.
    cam: rl.Vector2 = .{ .x = 0, .y = 0 },
    screen: P = WINDOW,
    /// The framebuffer a frame draws into: the window's, or a texture's. Asking GL stalls it.
    framebuffer: u32 = 0,
    /// The latest walk, skill or interaction asked for while `busy`.
    pending: ?Queued = null,
    vignette: vignette.Vignette = .{},
    cinema: cinema.Cinema = .{},
    rain: weather.Weather = .{},
    mini: scene.Minimap = .{},
    sprites: look.Sprites = .{},
    graphics_ready: bool = false,
    art_ready: bool = false,
    face: font.Face = .{},
    light: *light.Light,
    cloud: *cloud.Cloud,
};

pub fn boot(alloc: std.mem.Allocator) !*Game {
    const l = try light.Light.create(alloc);
    errdefer alloc.destroy(l);
    const c = try cloud.Cloud.create(alloc);
    errdefer alloc.destroy(c);
    const v = try alloc.create([atlas.MAX_NODES]simulation.Visit);
    errdefer alloc.destroy(v);
    const g = try alloc.create(Game);
    g.* = .{
        .sim = .{
            .lv = grid.Level.blank(),
            .rng = mathx.Rng.init(1),
            .visits = v,
            .flow = undefined,
            .queue = undefined,
        },
        .light = l,
        .cloud = c,
    };
    return g;
}

fn visitOf(g: *const Game) simulation.Visit {
    return .{ .lv = g.sim.lv, .pool = g.sim.pool, .facing = g.pic.facing, .ground = g.sim.ground };
}

fn revisit(g: *Game, v: *const simulation.Visit) void {
    g.sim.lv = v.lv;
    g.sim.pool = v.pool;
    g.pic.facing = v.facing;
    g.sim.ground = v.ground;
}

pub fn shut(alloc: std.mem.Allocator, g: *Game) void {
    alloc.destroy(g.sim.visits);
    alloc.destroy(g.cloud);
    alloc.destroy(g.light);
    alloc.destroy(g);
}

fn startRun(g: *Game, w: ?*const atlas.Atlas, seed: u64) void {
    toDefaults(&g.sim, &.{ "visited", "node", "outdoors", "pool", "hero", "clock" });
    toDefaults(g, &.{"character"});
    g.sim.map = w;
    g.sim.seed = seed;
    g.sim.rng = mathx.Rng.init(seed ^ PLAY_SALT);
    g.sim.unsaved = true;
}

pub fn begin(g: *Game, seed: u64) void {
    startRun(g, null, seed);
    const floor = gen.build(&g.sim.lv, seed);
    reset(g, floor.start);
    pack.place(&g.sim.lv, &g.sim.pool, &g.sim.rng, floor.start, &.{});
    settle(g);
    var buf: [Log.COLS]u8 = undefined;
    var out = std.io.fixedBufferStream(&buf);
    for (actor.FOES, 0..) |k, i| {
        out.writer().print("{s}{d} {s}", .{ menu.listSep(i, actor.FOES.len, .@"and"), g.sim.pool.tally(k).total, actor.plural(k) }) catch break;
    }
    g.sim.log.say("{s} somewhere on this floor. Seed {d}.", .{ out.getWritten(), seed });
}

pub fn beginMap(g: *Game, w: *const atlas.Atlas) void {
    beginMapAt(g, w, w.start, freshSeed());
}

pub fn beginMapAt(g: *Game, w: *const atlas.Atlas, from: atlas.Start, seed: u64) void {
    startRun(g, w, seed);
    freshRun(g);
    enter(g, from.node, from.at);
}

/// The hero occupies the first pool slot on every node, preserving its id.
fn enter(g: *Game, n: usize, at: P) void {
    const w = g.sim.map.?;
    var carried = actor.Actor.of(g.sim.class.kind(), at);
    if (g.sim.heroActor()) |h| carried = h.*;
    g.sim.node = n;
    g.sim.outdoors = g.sim.outdoorsNow();
    const back = g.sim.visited.isSet(n);
    if (back) {
        revisit(g, &g.sim.visits[n]);
        const hero = g.sim.heroSlot().?;
        g.sim.lv.clear(g.sim.pool.items[hero].at);
    } else w.node[n].stamp(&g.sim.lv, rollOf(g.sim.seed, n));
    const placing: []const atlas.Foe = if (back) &.{} else w.node[n].placed();
    const to = atlas.landing(&g.sim.lv, at, placing) orelse at;
    if (back) {
        const hero = g.sim.heroSlot().?;
        g.sim.pool.items[hero].at = to;
        g.sim.lv.stand(to, g.sim.hero);
    } else {
        g.sim.ground = .{};
        spawnHero(g, to);
        switch (w.node[n].plan) {
            .procgen => |*pg| pack.place(&g.sim.lv, &g.sim.pool, &g.sim.rng, to, &pg.foes),
            .bespoke => for (placing) |f| {
                if (g.sim.lv.vacant(f.at)) _ = g.sim.pool.spawn(&g.sim.lv, actor.Actor.of(f.kind, f.at));
            },
        }
    }
    const h = g.sim.heroActor().?;
    carried.at = h.at;
    h.* = carried;
    combat.arrive(g, h.at);
    g.sim.unsaved = true;
    freshTurn(g);
    settle(g);
}

pub fn rollOf(run: u64, n: usize) u64 {
    return std.hash.Wyhash.hash(run, std.mem.asBytes(&n));
}

fn goThrough(g: *Game, l: atlas.Link) void {
    g.sim.visits[g.sim.node] = visitOf(g);
    g.sim.visited.set(g.sim.node);
    const walk = g.pending;
    const hero = g.sim.heroSlot().?;
    const facing = g.pic.facing[hero];
    const level_up = g.pic.fx.level_up;
    var title: [atlas.TITLE_MAX]u8 = undefined;
    g.sim.log.say("Entered {s}.", .{g.sim.map.?.node[l.node].title(l.node, &title)});
    enter(g, l.node, g.sim.map.?.door(l).at);
    g.pending = walk;
    g.pic.facing[hero] = facing;
    g.pic.fx.level_up = level_up;
}

/// Finish pending facing changes and door travel before leaving a run.
pub fn leave(g: *Game) void {
    g.pic.turnNow();
    const l = g.sim.travel orelse return;
    goThrough(g, l);
}

pub fn restart(g: *Game) void {
    if (g.sim.map) |w| beginMap(g, w) else begin(g, freshSeed());
}

fn spawnHero(g: *Game, at: P) void {
    toDefaults(&g.sim, &.{"pool"});
    g.pic.freshFacing();
    g.sim.hero = g.sim.pool.spawn(&g.sim.lv, actor.Actor.of(g.sim.class.kind(), at));
}

pub fn reset(g: *Game, hero: P) void {
    spawnHero(g, hero);
    freshRun(g);
    freshTurn(g);
}

pub fn toDefaults(s: anytype, comptime fields: []const []const u8) void {
    const T = @TypeOf(s.*);
    @setEvalBranchQuota(20_000);
    inline for (fields) |f| @field(s, f) = comptime std.meta.fieldInfo(T, @field(std.meta.FieldEnum(T), f)).defaultValue().?;
}

fn freshRun(g: *Game) void {
    toDefaults(&g.sim, &.{ "kills", "gold", "mana_recovery", "flasks", "cooldown", "stepped", "log", "chronicle", "inventory", "ground" });
    toDefaults(g, &.{ "mode", "epitaph" });
    g.pic.freshRun();
    g.sim.growth = progress.State.of(g.sim.class);
    g.bar = g.sim.growth.bar(g.sim.class);
    g.sim.loot_rng = mathx.Rng.init(g.sim.seed ^ LOOT_SALT);
    g.pic.settleXp(&g.sim);
    if (g.sim.heroActor()) |h| {
        h.max = g.sim.lifeMax();
        h.hp = h.max;
    }
    g.sim.mana = g.sim.manaMax();
    g.vignette.clear();
}

fn freshTurn(g: *Game) void {
    g.mouse = .{};
    toDefaults(&g.sim, &.{ "travel", "order_n", "displaced" });
    toDefaults(g, &.{"pending"});
    g.pic.freshTurn();
    g.cloud.clear();
}

pub fn settle(g: *Game) void {
    g.art_ready = false;
    g.sim.chronicle.restart(epitaph.turnStart(g));
    castSight(g, g.sim.heroActor().?.at);
    g.cloud.settle(&g.sim.lv);
    g.pic.snapGlide(&g.sim.pool);
    g.pic.catchUp(&g.sim);
    g.pic.settleResources(&g.sim);
    g.cam = camWant(g);
    g.light.settle(&g.sim.lv);
    g.pic.hour_shown = g.sim.clock.hour();
    g.light.sky = skyNow(g);
    g.light.carrier = g.pic.carrierAt(&g.sim);
}

pub fn resumeRun(g: *Game) void {
    gen.restoreShapes(&g.sim.lv);
    var visits = g.sim.visited.iterator(.{});
    while (visits.next()) |n| gen.restoreShapes(&g.sim.visits[n].lv);
    toDefaults(g, &.{ "mode", "exit", "character", "epitaph" });
    toDefaults(&g.sim, &.{ "unsaved", "chronicle" });
    g.sim.outdoors = g.sim.outdoorsNow();
    freshTurn(g);
    g.pic.settleXp(&g.sim);
    settle(g);
    if (g.pic.heroShown(&g.sim)) |h| g.vignette.settle(h.hp, h.max) else g.vignette.clear();
}

pub fn freshSeed() u64 {
    return @bitCast(std.time.milliTimestamp());
}

pub fn castSight(g: *Game, from: P) void {
    g.sim.see(from);
    g.mini.stale = true;
}

pub const Move = enum { kick, open, loot, step, blocked };

pub fn heroMove(g: *Game, d: mathx.Dir) Move {
    const h = g.sim.heroActor() orelse return .blocked;
    return moveOf(g, h.at, d, g.sim.lv.taken(h.at.add(d.delta())));
}

/// A step from `from` toward `d`, `occupied` saying whether a body or barrel stands where it lands.
pub fn moveOf(g: *const Game, from: P, d: mathx.Dir, occupied: bool) Move {
    if (opensChest(g, from, d)) return .open;
    if (!g.sim.lv.passOk(from, d)) return .blocked;
    if (occupied) return .kick;
    return if (character.lootReached(g, from, from.add(d.delta()))) .loot else .step;
}

fn opensChest(g: *const Game, from: P, d: mathx.Dir) bool {
    return g.sim.lv.at(from.add(d.delta())).opened() != null;
}

/// `late` seconds ago the walk came due.
pub fn heroStep(g: *Game, d: mathx.Dir, late: f32) void {
    const h = g.sim.heroActor() orelse return;
    const to = h.at.add(d.delta());
    switch (heroMove(g, d)) {
        .kick => {
            const w = g.sim.lv.who(to);
            const s = heroBump(g, h.at, to, late);
            switch (g.sim.class) {
                inline else => |c| {
                    const blow = comptime c.strike();
                    if (w != grid.NO_ONE) combat.wound(g, w, combat.heroRoll(g, .melee, combat.kickRaw(&g.sim.rng, &g.sim.inventory.gear, blow)), blow.verb, s) else combat.smash(g, to, blow.verb, s);
                },
            }
            g.pic.lead = s.wait;
        },
        .open => {
            character.openLoot(g, to);
            return;
        },
        .loot => {
            heroTo(g, to);
            character.openLoot(g, to);
        },
        .step => heroTo(g, to),
        .blocked => return,
    }
    g.pic.turnToward(g.sim.hero, d.delta().x);
    combat.endTurn(g);
}

/// `late` seconds into the bump; the hit lands at its apex.
pub fn heroBump(g: *Game, from: P, at: P, late: f32) presentation.Stroke {
    _ = g.pic.bumpHeld(g.sim.heroSlot().?, at, late);
    return .{ .from = from, .wait = BUMP_LANDS - late };
}

pub fn heroTo(g: *Game, to: P) void {
    g.sim.pool.move(&g.sim.lv, g.sim.hero, to);
    combat.arrive(g, to);
    g.sim.stepped = true;
    g.sim.travel = g.sim.leadsTo(to);
}

pub fn syncStats(g: *Game) void {
    const h = g.sim.heroActor() orelse return;
    h.max = g.sim.lifeMax();
    h.hp = @min(h.hp, h.max);
    g.sim.mana = @min(g.sim.mana, g.sim.manaMax());
    g.pic.settleHero(&g.sim, 0);
}

fn characterShown(g: *const Game) bool {
    return g.mode == .pause and g.pause_page == .character;
}

/// Character is open with its tabs, not as the Nearby list.
fn bookOpen(g: *const Game) bool {
    return characterShown(g) and !g.character.direct();
}

fn camAxis(centre: f32, view: f32, map: f32) f32 {
    if (view >= map) return (map - view) * 0.5;
    return std.math.clamp(centre - view * 0.5, 0, map - view);
}

pub fn camWant(g: *const Game) rl.Vector2 {
    const at = (g.pic.heroGlide(&g.sim) orelse return g.cam).ground();
    const half: f32 = @floatFromInt(HALF_CELL);
    return .{
        .x = camAxis(at.x + half, @floatFromInt(g.screen.x), @floatFromInt(MAP_PX.x)),
        .y = camAxis(at.y + half, @floatFromInt(g.screen.y), @floatFromInt(MAP_PX.y + hud.COVER)),
    };
}

const Walk = struct { d: mathx.Dir, late: f32 };
pub const Queued = union(enum) { walk: mathx.Dir, skill: skills.Use, interact };

/// A held walk repeating does not displace a queued action.
fn queueWalk(g: *Game, d: mathx.Dir) void {
    if (g.pending) |q| {
        if (q != .walk and g.st.repeating()) return;
    }
    g.pending = .{ .walk = d };
}

/// With anything near, the press is Interact's, not its button's skill, and waits for quiet like one.
fn queueInteract(g: *Game) bool {
    if (!g.st.interact or !character.anyNearby(g)) return false;
    g.pending = .interact;
    return true;
}

/// A frame that cannot take a turn queues its press for the next, as while busy.
fn queuePress(g: *Game) void {
    if (queueInteract(g)) {} else if (g.st.hit(skillbar.INSPECT)) {
        character.openInspect(g);
    } else if (skills.usedSkill(g)) |u| {
        g.pending = .{ .skill = u };
    } else if (g.st.walk) |d| queueWalk(g, d);
}

fn interacted(g: *Game) bool {
    if (queueInteract(g) and !g.pic.quiet()) return true;
    if (takeQueued(g, .interact) == null) return false;
    return character.openNearby(g);
}

fn skillDue(g: *Game) ?skills.Use {
    if (skills.usedSkill(g)) |u| g.pending = .{ .skill = u };
    return takeQueued(g, .skill);
}

fn paced(g: *Game) ?Walk {
    if (g.st.walk) |d| {
        if (!g.pic.quiet()) {
            queueWalk(g, d);
            return null;
        }
        g.pending = null;
        return .{ .d = d, .late = @min(g.st.late(), g.pic.sinceQuiet()) };
    }
    return .{ .d = takeQueued(g, .walk) orelse return null, .late = g.pic.sinceQuiet() };
}

fn takeQueued(g: *Game, comptime tag: std.meta.Tag(Queued)) ?std.meta.TagPayload(Queued, tag) {
    const q = g.pending orelse return null;
    if (q != tag or !g.pic.quiet()) return null;
    g.pending = null;
    return @field(q, @tagName(tag));
}

/// A stunned hero's next turn passes once the stunning one is drawn, wherever a turn could be spent.
fn stunnedTurn(g: *Game) bool {
    if (!g.pic.quiet() or g.sim.travel != null) return false;
    if (g.mode != .play and !characterShown(g)) return false;
    const h = g.sim.heroActor() orelse return false;
    if (!h.clock.owes()) return false;
    h.clock.pass(turn_clock.TURN);
    combat.endTurn(g);
    return true;
}

/// Advance presentation before new actions so their effects start at the correct delay.
pub fn update(g: *Game, dt: f32) void {
    if (!g.st.focused) holdWalk(g);
    mouseControls.prepare(g);
    if (playShown(g) or g.mode == .aim or g.mode == .inspect) {
        if (g.st.pointer) |p| {
            if (raster.holds(journal.box(g.screen), p) and g.st.scroll != 0) g.sim.log.move(g.st.scroll);
        }
    }
    const death_drawn = deathShown(g);
    g.pic.advance(&g.sim, dt);
    if (g.pic.quiet()) {
        g.sim.log.release();
        g.pic.gold_taken = null;
        drawnTurn(g);
    }
    g.cloud.step(&g.sim.lv, dt);
    g.pic.stepMotion(&g.sim, dt);
    var late: f32 = 0;
    const was = screenOf(g);
    if (g.mode != .dead and g.st.character_page != null) {
        const page = book.Page.of(g.st.character_page.?);
        if (bookOpen(g) and g.character.page == page) {
            g.mode = .play;
        } else {
            character.openCharacter(g);
            g.character.choose(page);
            g.character.enter(character.bookView(g, &g.nearby));
        }
    } else if (g.mode != .dead and g.st.hit(CHARACTER) and (g.mode == .play or (g.mode == .pause and !bookOpen(g)))) {
        character.openCharacter(g);
    } else if (g.mode == .play and g.st.hit(PAUSE)) {
        character.openPause(g);
    } else if (stunnedTurn(g)) {
        if (g.mode == .play) queuePress(g);
    } else switch (g.mode) {
        .play => {
            if (g.sim.travel) |l| {
                queuePress(g);
                if (g.pic.quiet()) goThrough(g, l);
            } else if (interacted(g)) {} else if (g.st.hit(skillbar.INSPECT)) {
                character.openInspect(g);
            } else if (skillDue(g)) |u| {
                skills.useSkill(g, u);
            } else if (mouseControls.step(g)) {} else if (paced(g)) |w| {
                late = w.late;
                heroStep(g, w.d, w.late);
            }
        },
        .aim => {
            const clicked = mouseControls.aim(g);
            if (menu.closed(&g.st)) {
                g.mode = .play;
            } else if (g.st.hit(CONFIRM) or clicked) {
                skills.confirmAim(g);
            } else if (g.st.walk) |d| {
                skills.nudgeAim(g, d);
            }
        },
        .bind => binds.bindStep(g),
        .inspect => overlay.inspectStep(g),
        .dead => if (death_drawn and (dismissed(&g.st) or g.st.clicked(deadBox(g.screen)))) {
            if (g.permadeath) g.exit = .back else restart(g);
        },
        .pause => character.pauseStep(g),
    }
    if (characterShown(g) or g.mode == .inspect) if (g.sim.travel) |l| if (g.pic.quiet()) goThrough(g, l);
    if (!std.meta.eql(was, screenOf(g))) holdWalk(g);
    g.pic.stepGlide(&g.sim, g.cloud, late);
    g.pic.catchUp(&g.sim);
    g.pic.splashSteps(&g.sim);
    stepVignette(g, dt);
    const want = camWant(g);
    const k = mathx.easing(dt, CAM_EASE);
    g.cam = g.cam.lerp(want, k);
    g.pic.ease(&g.sim, dt);
    g.light.sky = skyNow(g);
    g.light.step(&g.sim.lv, dt);
    g.light.carrier = g.pic.carrierAt(&g.sim);
    if (g.debug.visuals.weather) g.rain.step(dt, weatherNow(g), g.screen.x, g.screen.y, CELL_F);
}

fn skyNow(g: *const Game) ?sky.Sky {
    return if (g.sim.outdoors) sky.under(g.pic.hour_shown, g.sim.climateNow().light) else null;
}

pub fn weatherNow(g: *const Game) ?climate.Weather {
    return if (g.sim.outdoors) g.sim.climateNow().weather else null;
}

fn drawnTurn(g: *Game) void {
    if (g.sim.growth.level > g.pic.growth_shown.level and g.mode != .dead) {
        if (g.sim.heroActor() != null) g.pic.fx.levelUp();
    }
    g.pic.showProgress(&g.sim);
}

/// Whichever screen takes the way: a walk held across a change of it moves nothing on the new one.
const Screen = struct { mode: Mode, pause_page: PausePage, debug_page: debugging.Page, character_page: book.Page, binds: std.meta.Tag(binds.Binds.Menu) };

fn screenOf(g: *const Game) Screen {
    return .{ .mode = g.mode, .pause_page = g.pause_page, .debug_page = g.debug.page, .character_page = g.character.page, .binds = std.meta.activeTag(g.binds.menu) };
}

pub fn holdWalk(g: *Game) void {
    g.st.holdWalk();
    g.pending = null;
    g.mouse.stop();
}

pub fn deathShown(g: *const Game) bool {
    return g.mode == .dead and g.pic.quiet();
}

pub fn modeShown(g: *const Game) Mode {
    return if (g.mode == .dead and !g.pic.quiet()) g.died_in else g.mode;
}

pub fn playShown(g: *const Game) bool {
    return modeShown(g) == .play;
}

pub const DISMISS = [_]input.Button{ CONFIRM, PAUSE, BACK, .x };

fn dismissed(st: *const input.State) bool {
    for (DISMISS) |b| {
        if (st.hit(b)) return true;
    }
    return false;
}

/// Read the slot even after death so the lethal hit still reddens the view.
fn stepVignette(g: *Game, dt: f32) void {
    const max = g.sim.lifeMax();
    const i = g.sim.heroSlot() orelse return g.vignette.step(dt, 0, max, max);
    g.vignette.step(dt, g.pic.fx.flashOf(i), g.pic.pictured[i].hp, g.pic.pictured[i].max);
}

pub fn middle(v: rl.Vector2) [2]f32 {
    return .{ v.x / CELL_F + 0.5, v.y / CELL_F + 0.5 };
}

/// The cell a body drawn with its corner at `v` stands in.
pub fn cellUnder(v: rl.Vector2) P {
    return mathx.cellOf(middle(v));
}

fn drawDead(g: *Game) void {
    var buf: [menu.NOTE_MAX + 1]u8 = undefined;
    const mid = @divTrunc(g.screen.y, 2);
    character.veil(g);
    const DIED = " DIED";
    var died: [heroes.Name.MAX + DIED.len + 1]u8 = undefined;
    const said = menu.shout(&died, "{s}" ++ DIED, .{g.sim.name.text()});
    menu.heading(g.face, g.screen, said, mid + DEAD_TITLE_DY, menu.TITLE, look.LIFE, look.LIFE);
    if (g.epitaph) |*e| drawEpitaph(g, e.text(), mid + DEAD_STORY_DY);
    const s = &g.sim;
    const score = std.fmt.bufPrintZ(&buf, "Level {d}" ++ menu.SEP ++ "{d} foe{s} killed" ++ menu.SEP ++ "{d} gold" ++ menu.SEP ++ "Seed {d}", .{ s.growth.level, s.kills, mathx.plural(s.kills), s.gold, s.seed }) catch "";
    menu.mid(g.face, g.screen, score, mid + DEAD_SCORE_DY, font.BODY, look.DIM);
    menu.action(&g.face, deadBox(g.screen), prompt_icon.Prompt.menuOf(&g.st, CONFIRM), if (g.permadeath) "Title" else "Restart");
}

/// Centred in its rows above the score, cut short past `DEAD_STORY_LINES`.
fn drawEpitaph(g: *Game, story: []const u8, top: i32) void {
    var wrapped: font.Wrapped = undefined;
    var rows: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
    const n = @min(DEAD_STORY_LINES, font.wrap(&g.face, story, font.BODY, menu.listWidth(g.screen), &wrapped, &rows));
    const y = top + @divTrunc(@as(i32, @intCast(DEAD_STORY_LINES - n)) * font.BODY_LINE, 2);
    for (rows[0..n], 0..) |row, i| g.face.textMid(row, @divTrunc(g.screen.x, 2), y + @as(i32, @intCast(i)) * font.BODY_LINE, font.BODY, look.TEXT);
}

pub fn deadBox(screen: P) rl.Rectangle {
    return raster.rect(@divTrunc(screen.x - menu.ACTION_WIDE.x, 2), @divTrunc(screen.y, 2) + DEAD_ACTION_DY, menu.ACTION_WIDE.x, menu.ACTION_WIDE.y);
}

pub fn drawFrame(g: *Game) void {
    rl.clearBackground(look.FOG);
    scene.drawMap(g);
    g.vignette.draw(g.screen.x, g.screen.y);
    scene.drawMinimap(g);
    scene.drawDayNight(g);
    overlay.drawHud(g);
    journal.draw(&g.face, &g.sprites, g.screen, &g.sim.log);
    overlay.drawTips(g);
    if (g.mode == .bind) overlay.drawBinds(g);
    if (deathShown(g)) drawDead(g);
    if (modeShown(g) == .pause) character.drawPause(g);
}

const GRAPHICS = .{ "light", "cloud", "vignette", "mini", "cinema" };

fn loadGraphics(g: *Game) void {
    g.sprites.loadCommon();
    inline for (GRAPHICS) |f| @field(g, f).load();
    g.graphics_ready = true;
}

pub fn unloadGraphics(g: *Game) void {
    g.sprites.unload();
    inline for (GRAPHICS) |f| @field(g, f).unload();
    g.graphics_ready = false;
    g.art_ready = false;
}

pub fn prepare(g: *Game) void {
    if (!g.graphics_ready) loadGraphics(g);
    if (g.art_ready) return;
    const need = mapAssets(g);
    g.sprites.sync(need);
    const figures = g.sprites.figures();
    g.light.syncFigures(&figures);
    g.art_ready = true;
}

pub fn mapAssets(g: *Game) look.Assets {
    var need = look.Assets.of(&g.sim.lv);
    need.barrel = need.barrel or g.pic.fx.barrels_due > 0;
    for (g.sim.pool.slice(), 0..) |a, i| {
        if (a.alive) need.body(a.kind);
        if (g.pic.standing(&g.sim, i)) need.body(g.pic.pictured[i].kind);
    }
    return need;
}

pub fn syncScreen(g: *Game, toggle: bool) void {
    if (toggle) {
        if (window.MONITOR_OWNED) window.toggleMonitorOwned() else rl.toggleBorderlessWindowed();
        debugging.syncDisplay(g);
    }
    g.screen = .{ .x = rl.getScreenWidth(), .y = rl.getScreenHeight() };
}

pub fn frame(g: *Game) void {
    const dt = rl.getFrameTime();
    g.st.context = switch (g.mode) {
        .play => .play,
        .aim => .target,
        .pause => if (characterShown(g) and g.character.treeActive()) .tree else .menu,
        .bind, .dead, .inspect => .menu,
    };
    g.st.sets = g.mode == .inspect;
    g.st.modifier = g.bar.modifier;
    g.st.aimed = if (g.mode == .aim) g.aim_by else null;
    g.st.update(dt);
    syncScreen(g, g.st.fullscreen);
    const began = std.time.Instant.now() catch null;
    update(g, dt);
    prepare(g);
    g.st.modifier = g.bar.modifier;
    rl.beginDrawing();
    drawFrame(g);
    if (began) |b| if (std.time.Instant.now()) |now| g.perf.add(dt, now.since(b)) else |_| {};
    if (g.debug.performance_overlay) g.perf.draw(&g.face);
    rl.endDrawing();
}
