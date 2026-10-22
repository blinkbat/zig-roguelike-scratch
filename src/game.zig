const std = @import("std");
const items = @import("play/items.zig");
const progress = @import("play/progress.zig");
const passives = @import("play/passives.zig");
const journal = @import("ui/journal.zig");
const rl = @import("raylib");

const mathx = @import("core/mathx.zig");
const input = @import("core/input.zig");
const grid = @import("map/grid.zig");
const gen = @import("map/gen.zig");
const atlas = @import("map/atlas.zig");
const editor = @import("edit/editor.zig");
const menu = @import("ui/menu.zig");
const hud = @import("ui/hud.zig");
const book = @import("ui/book.zig");
const heroes = @import("play/hero.zig");
const actor = @import("play/actor.zig");
const bow = @import("play/bow.zig");
const attrs = @import("play/attrs.zig");
const turn_clock = @import("play/clock.zig");
const chain = @import("play/chain.zig");
const flask = @import("play/flask.zig");
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
const day = @import("map/day.zig");
const lume = @import("map/lume.zig");
pub const shots = @import("game/shots.zig");
pub const scene = @import("game/scene.zig");
pub const overlay = @import("game/overlay.zig");
pub const character = @import("game/character.zig");
pub const debugging = @import("game/debug.zig");
pub const combat = @import("game/combat.zig");
pub const harness = @import("game/harness.zig");
pub const mouseControls = @import("game/mouse.zig");
const window = @import("core/window.zig");
const glide = @import("game/glide.zig");
const binds = @import("game/binds.zig");
const skills = @import("game/skills.zig");

const P = mathx.P;

pub const WINDOW = P{ .x = window.WINDOW_W, .y = window.WINDOW_H };
/// Screens the shots and layout tests cover besides the window's.
pub const SCREEN_720 = P{ .x = 1280, .y = 720 };
pub const SCREEN_1080 = P{ .x = 1920, .y = 1080 };
pub const SCREEN_1440 = P{ .x = 2560, .y = 1440 };
pub const CELL: i32 = 64;
pub const CELL_F: f32 = @floatFromInt(CELL);
pub const HALF_CELL: i32 = @divTrunc(CELL, 2);
pub const MAP_PX = P{ .x = grid.W * CELL, .y = grid.H * CELL };

pub fn authored(comptime px: i32) i32 {
    return @divExact(CELL * px, look.SPRITE_PX);
}
pub const GLYPH: i32 = authored(look.GLYPH_PX);
pub const LINE_W: i32 = authored(2);
const DEAD_TITLE_DY: i32 = -100;
const DEAD_SCORE_DY: i32 = -10;
const DEAD_ACTION_DY: i32 = 40;
pub const SLOT_PX: i32 = 48;
pub const SLOT_GAP: i32 = 8;
pub const SLOT_STEP: i32 = SLOT_PX + SLOT_GAP;
const GROUP_GAP: i32 = 16;
pub const KEY_GAP: i32 = 6;
pub const PROMPT_PX: i32 = 22;
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
pub const PICK_MARGIN: i32 = 16;
/// Cells past the view a prop's shadow can reach into it from.
pub const CAST_MARGIN: i32 = @intFromFloat(@ceil(shadow.CAST_REACH));
const FLIGHT_S: f32 = 0.022;
const CAM_EASE: f32 = 12.0;
/// One walk repeat, so the glides of a held walk join end to end.
pub const GLIDE_S: f32 = input.Stepper.ARR;
/// Pixels, at the top of each glide's hop.
pub const HOP_PX: f32 = @floatFromInt(authored(10));
pub const SLIDE_S: f32 = GLIDE_S * 2;
pub const STAGGER_S: f32 = GLIDE_S * 0.5;
pub const BUMP_S: f32 = GLIDE_S;
/// Of the bump, the share out to the blow.
pub const BUMP_HIT: f32 = 0.5;
pub const BUMP_LANDS: f32 = BUMP_S * BUMP_HIT;
/// From a spell cast round the hero to its blows landing.
pub const CAST_S: f32 = BUMP_LANDS;
/// From one body a bolt leaps on from to the next.
pub const ZAP_S: f32 = 0.08;
pub const BUMP_PX: f32 = CELL_F * 0.35;
/// A walk due this close to the turn's last glide ending is not held for it.
const PACE_SLACK: f32 = 1e-4;
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

/// Presentation only: the hit already resolved when this was made.
const Shot = struct {
    flight: bow.Flight,
    from: P,
    act: skillbar.Act = .shoot,
    t: f32 = 0,
    trail_t: f32 = 0,

    /// When the missile reaches its last cell, as its hit is presented.
    pub fn lands(self: *const Shot) f32 {
        return flown(self.flight.len -| 1);
    }

    pub fn ends(self: *const Shot) f32 {
        return flown(self.flight.len);
    }

    pub fn position(self: *const Shot, time: f32) [2]f32 {
        const a = mathx.centre(self.from);
        if (self.flight.len == 0) return a;
        const b = mathx.centre(self.flight.path[self.flight.len - 1]);
        const duration = self.lands();
        const k = if (duration > 0) std.math.clamp(time / duration, 0, 1) else 1;
        return mathx.lerp2(a, b, k);
    }

    pub fn direction(self: *const Shot) [2]f32 {
        const a = mathx.centre(self.from);
        const b = self.position(flown(self.flight.len));
        const len = @max(0.001, mathx.len(b[0] - a[0], b[1] - a[1]));
        return .{ (b[0] - a[0]) / len, (b[1] - a[1]) / len };
    }
};

const TRAIL_PER_CELL: usize = 12;

pub fn flown(n: usize) f32 {
    return @as(f32, @floatFromInt(n)) * FLIGHT_S;
}

test "missiles move continuously to the existing impact time in every direction" {
    const lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    var checked: usize = 0;
    for (mathx.ALL_DIRS) |d| {
        const delta = d.delta();
        const to = P{ .x = from.x + delta.x * 6, .y = from.y + delta.y * 6 };
        const shot_ = Shot{ .from = from, .flight = bow.fly(&lv, from, to) };
        const lands = shot_.lands();
        try std.testing.expectEqual(mathx.centre(from), shot_.position(0));
        try std.testing.expectEqual(mathx.centre(to), shot_.position(lands));
        const a = shot_.position(lands * 0.4);
        const b = shot_.position(lands * 0.41);
        const moved = mathx.len(b[0] - a[0], b[1] - a[1]);
        try std.testing.expect(moved > 0 and moved < 0.1);
        checked += 1;
    }
    std.debug.print("smooth missiles: {d} directions, sub-tile motion, exact arrival at presented impact\n", .{checked});
}

pub const Facing = enum { right, left };

const Bite = union(enum) { hurt: fx.After, kill: fx.After, burst: fx.After, miss };

/// Presentation debts land at the body's stagger, or after the hero when it has no stagger.
const Owed = struct {
    bit: ?Bite = null,
    arrow: ?bow.Flight = null,
    gassed: ?Harm = null,
    burned: ?Harm = null,
    bled: ?Harm = null,
    worn: ?fx.After = null,
    swept: ?Swept = null,

    pub fn any(o: *const Owed) bool {
        inline for (std.meta.fields(Owed)) |f| {
            if (@field(o, f.name) != null) return true;
        }
        return false;
    }
};

/// What a foe's sweep struck besides the hero, landing with its blow on the hero; a null slot is a barrel.
pub const Swept = struct {
    hit: [actor.SWEEP_CELLS]Swipe = undefined,
    n: usize = 0,
};
pub const Swipe = struct { slot: ?usize, at: P, lethal: bool, after: ?fx.After = null };

comptime {
    std.debug.assert(fx.DUE >= actor.MAX * (std.meta.fields(Owed).len + actor.SWEEP_CELLS) + @max(2, chain.JUMPS));
}

const Harm = struct { kill: bool, after: fx.After };

/// The ticks a body's turn has run, which a half split off it mid-turn has had too.
pub const Ran = std.EnumSet(Tick);
pub const Tick = std.meta.FieldEnum(Owed);

/// `in` is set once the turn it was taken in has its stagger.
const Turning = struct { to: Facing, in: ?f32 = null };

const Visit = struct {
    lv: grid.Level,
    pool: actor.Pool,
    facing: [actor.MAX]Facing,
    ground: items.Ground,

    fn of(g: *const Game) Visit {
        var v: Visit = undefined;
        inline for (std.meta.fields(Visit)) |f| @field(v, f.name) = @field(g, f.name);
        return v;
    }

    fn restore(v: *const Visit, g: *Game) void {
        inline for (std.meta.fields(Visit)) |f| @field(g, f.name) = @field(v, f.name);
    }
};

pub const Flasks = std.EnumArray(flask.Kind, flask.Flask);

pub const Game = struct {
    mode: Mode = .play,
    /// Drawn in place of `.dead` until the lethal turn is.
    died_in: Mode = .play,
    pause_menu: menu.Menu = .{},
    pause_page: PausePage = .main,
    debug: debugging.State = .{},
    character: book.Book = .{},
    /// What Character's Nearby page lists, filled afresh each step and draw; too big for the stack each frame.
    nearby: NearbyBuf = undefined,
    inventory: items.Inventory = .{},
    growth: progress.State = progress.State.of(heroes.DEFAULT),
    ground: items.Ground = .{},
    loot_rng: mathx.Rng = mathx.Rng.init(1),
    back: Back = .title,
    exit: ?Exit = null,
    name: heroes.Name = heroes.DEFAULT.unnamed(),
    /// Set before a run begins.
    class: heroes.Class = heroes.DEFAULT,
    /// Saved runs return to their caller on death instead of restarting.
    permadeath: bool = false,
    clock: day.Clock = .{},
    outdoors: bool = false,
    hour_shown: f32 = day.Clock.hour(.{}),
    perf: debugging.Perf = .{},
    /// Kept across runs, never saved.
    unkillable: bool = false,
    unsaved: bool = false,
    lv: grid.Level,
    pool: actor.Pool = .{},
    hero: u16 = grid.NO_ONE,
    /// The map being played; null plays one generated floor.
    map: ?*const atlas.Atlas = null,
    node: usize = 0,
    /// Indexed by node.
    visits: *[atlas.MAX_NODES]Visit,
    visited: std.StaticBitSet(atlas.MAX_NODES) = .initEmpty(),
    /// The door the hero stepped onto this turn, gone through once the turn is drawn.
    travel: ?atlas.Link = null,
    rng: mathx.Rng,
    seed: u64 = 0,
    kills: usize = 0,
    gold: i32 = 0,
    mana: i32 = heroes.DEFAULT.attrs().mana(),
    mana_recovery: i32 = 0,
    flasks: Flasks = .initFill(.{}),
    /// Kill refills appear only when the killing blow lands.
    flasks_shown: Flasks = .initFill(.{}),
    /// Spent shield mana held for blows not yet presented.
    mana_held: i32 = 0,
    /// Turns until each can be used again.
    cooldown: std.EnumArray(skillbar.Act, u8) = .initFill(0),
    /// The hero stepped or leapt since the last turn ended, which tears a bleed wider.
    stepped: bool = false,
    displaced: std.StaticBitSet(actor.MAX) = .initEmpty(),
    /// Gold the hero took this turn, still drawn until the hero is drawn there.
    gold_taken: ?items.Coins = null,
    /// `xpLevels` as of the last drawn turn, and the bar easing toward it.
    xp_aim: f32 = 0,
    xp_shown: f32 = 0,
    life_fill: f32 = 1,
    mana_fill: f32 = 1,
    /// `growth` and `gold` as of the last drawn turn, for the character book.
    growth_shown: progress.State = .{},
    gold_shown: i32 = 0,
    log: Log = .{},
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
    shot: ?Shot = null,
    foe_shots: [actor.MAX]?Shot = @splat(null),
    /// Indexed by pool slot.
    glide: [actor.MAX]glide.Glide = undefined,
    /// Indexed by pool slot. Presentation only: the last way a body stepped, struck or aimed across.
    facing: [actor.MAX]Facing = @splat(.right),
    turning: [actor.MAX]?Turning = @splat(null),
    /// Living foes at turn start, nearest first; also their presentation order.
    order: [actor.MAX]u16 = undefined,
    order_n: usize = 0,
    /// Seconds until the last turn's slowest glide, arrow or flash ends; a walk waits for it.
    busy: f32 = 0,
    /// The latest walk, skill or interaction asked for while `busy`.
    pending: ?Queued = null,
    /// Seconds until the hero's non-walking action lands; starts the foe stagger.
    lead: ?f32 = null,
    owed: [actor.MAX]Owed = @splat(.{}),
    ran: [actor.MAX]Ran = @splat(Ran.initEmpty()),
    /// Pool-indexed presentation state, updated when each blow lands.
    pictured: [actor.MAX]fx.Body = undefined,
    /// The blows dealt so far, so the picture takes them in the order they were dealt.
    seq: u64 = 0,
    /// Indexed by pool slot: the slot a slime split off, until the blow that split it lands.
    split_from: [actor.MAX]?usize = @splat(null),
    /// Indexed by pool slot: gold a death added to its cell's pile, kept off the drawn pile until that death is drawn.
    dropped_gold: [actor.MAX]i32 = @splat(0),
    fx: fx.Fx = .{},
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
    /// Terrain only, so the turn's first chase fills it for every foe after.
    flowed: bool = false,
    flow: [grid.CELLS]i32,
    queue: [grid.CELLS]u32,

    pub fn heroActor(self: *Game) ?*actor.Actor {
        return self.pool.get(self.hero);
    }
};

pub fn boot(alloc: std.mem.Allocator) !*Game {
    const l = try light.Light.create(alloc);
    errdefer alloc.destroy(l);
    const c = try cloud.Cloud.create(alloc);
    errdefer alloc.destroy(c);
    const v = try alloc.create([atlas.MAX_NODES]Visit);
    errdefer alloc.destroy(v);
    const g = try alloc.create(Game);
    g.* = .{
        .lv = grid.Level.blank(),
        .rng = mathx.Rng.init(1),
        .visits = v,
        .light = l,
        .cloud = c,
        .flow = undefined,
        .queue = undefined,
    };
    return g;
}

pub fn shut(alloc: std.mem.Allocator, g: *Game) void {
    alloc.destroy(g.visits);
    alloc.destroy(g.cloud);
    alloc.destroy(g.light);
    alloc.destroy(g);
}

fn startRun(g: *Game, w: ?*const atlas.Atlas, seed: u64) void {
    toDefaults(g, &.{ "visited", "node", "outdoors", "pool", "hero", "clock", "character" });
    g.map = w;
    g.seed = seed;
    g.rng = mathx.Rng.init(seed ^ PLAY_SALT);
    g.unsaved = true;
}

pub fn begin(g: *Game, seed: u64) void {
    startRun(g, null, seed);
    const floor = gen.build(&g.lv, seed);
    reset(g, floor.start);
    pack.place(&g.lv, &g.pool, &g.rng, floor.start, &.{});
    settle(g);
    var buf: [Log.COLS]u8 = undefined;
    var out = std.io.fixedBufferStream(&buf);
    for (actor.FOES, 0..) |k, i| {
        out.writer().print("{s}{d} {s}", .{ menu.listSep(i, actor.FOES.len, .@"and"), g.pool.tally(k).total, actor.plural(k) }) catch break;
    }
    g.log.say("{s} somewhere on this floor. Seed {d}.", .{ out.getWritten(), seed });
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
    const w = g.map.?;
    var carried = actor.Actor.of(g.class.kind(), at);
    if (g.heroActor()) |h| carried = h.*;
    g.node = n;
    g.outdoors = outdoorsNow(g);
    const back = g.visited.isSet(n);
    if (back) {
        g.visits[n].restore(g);
        const hero = heroSlot(g).?;
        g.lv.clear(g.pool.items[hero].at);
    } else w.node[n].stamp(&g.lv, rollOf(g.seed, n));
    const placing: []const atlas.Foe = if (back) &.{} else w.node[n].placed();
    const to = atlas.landing(&g.lv, at, placing) orelse at;
    if (back) {
        const hero = heroSlot(g).?;
        g.pool.items[hero].at = to;
        g.lv.stand(to, g.hero);
    } else {
        g.ground = .{};
        spawnHero(g, to);
        switch (w.node[n].plan) {
            .procgen => |*pg| pack.place(&g.lv, &g.pool, &g.rng, to, &pg.foes),
            .bespoke => for (placing) |f| {
                if (g.lv.vacant(f.at)) _ = g.pool.spawn(&g.lv, actor.Actor.of(f.kind, f.at));
            },
        }
    }
    const h = g.heroActor().?;
    carried.at = h.at;
    h.* = carried;
    combat.arrive(g, h.at);
    g.unsaved = true;
    freshTurn(g);
    settle(g);
}

pub fn rollOf(run: u64, n: usize) u64 {
    return std.hash.Wyhash.hash(run, std.mem.asBytes(&n));
}

pub fn leadsTo(g: *const Game, p: P) ?atlas.Link {
    const w = g.map orelse return null;
    const k = g.lv.doorAt(p) orelse return null;
    return w.door(.{ .node = g.node, .door = k }).to;
}

fn goThrough(g: *Game, l: atlas.Link) void {
    g.visits[g.node] = Visit.of(g);
    g.visited.set(g.node);
    const walk = g.pending;
    const hero = heroSlot(g).?;
    const facing = g.facing[hero];
    const level_up = g.fx.level_up;
    var title: [atlas.TITLE_MAX]u8 = undefined;
    g.log.say("Entered {s}.", .{g.map.?.node[l.node].title(l.node, &title)});
    enter(g, l.node, g.map.?.door(l).at);
    g.pending = walk;
    g.facing[hero] = facing;
    g.fx.level_up = level_up;
}

/// Finish pending facing changes and door travel before leaving a run.
pub fn leave(g: *Game) void {
    for (g.turning, &g.facing) |t, *f| {
        if (t) |u| f.* = u.to;
    }
    g.turning = @splat(null);
    const l = g.travel orelse return;
    goThrough(g, l);
}

pub fn restart(g: *Game) void {
    if (g.map) |w| beginMap(g, w) else begin(g, freshSeed());
}

fn spawnHero(g: *Game, at: P) void {
    toDefaults(g, &.{ "pool", "facing" });
    g.hero = g.pool.spawn(&g.lv, actor.Actor.of(g.class.kind(), at));
}

pub fn reset(g: *Game, hero: P) void {
    spawnHero(g, hero);
    freshRun(g);
    freshTurn(g);
}

fn toDefaults(g: *Game, comptime fields: []const []const u8) void {
    @setEvalBranchQuota(20_000);
    inline for (fields) |f| @field(g, f) = comptime std.meta.fieldInfo(Game, @field(std.meta.FieldEnum(Game), f)).defaultValue().?;
}

fn freshRun(g: *Game) void {
    toDefaults(g, &.{ "kills", "gold", "mana_held", "mana_recovery", "flasks", "flasks_shown", "cooldown", "stepped", "log", "mode", "inventory", "ground" });
    g.growth = progress.State.of(g.class);
    g.bar = g.growth.bar(g.class);
    g.loot_rng = mathx.Rng.init(g.seed ^ LOOT_SALT);
    settleXp(g);
    if (g.heroActor()) |h| {
        h.max = lifeMax(g);
        h.hp = h.max;
    }
    g.mana = manaMax(g);
    g.vignette.clear();
}

fn freshTurn(g: *Game) void {
    g.mouse = .{};
    toDefaults(g, &.{ "shot", "foe_shots", "travel", "order_n", "busy", "pending", "lead", "owed", "split_from", "dropped_gold", "turning", "displaced", "gold_taken" });
    g.fx.clear();
    g.cloud.clear();
}

pub fn settle(g: *Game) void {
    g.art_ready = false;
    castSight(g, g.heroActor().?.at);
    g.cloud.settle(&g.lv);
    snapGlide(g);
    catchUp(g);
    overlay.settleResources(g);
    g.cam = camWant(g);
    g.light.settle(&g.lv);
    g.hour_shown = g.clock.hour();
    g.light.sky = skyNow(g);
    g.light.carrier = carrierAt(g);
}

pub fn resumeRun(g: *Game) void {
    gen.restoreShapes(&g.lv);
    var visits = g.visited.iterator(.{});
    while (visits.next()) |n| gen.restoreShapes(&g.visits[n].lv);
    toDefaults(g, &.{ "mode", "exit", "unsaved", "character" });
    g.outdoors = outdoorsNow(g);
    freshTurn(g);
    settleXp(g);
    settle(g);
    if (heroShown(g)) |h| g.vignette.settle(h.hp, h.max) else g.vignette.clear();
}

fn outdoorsNow(g: *const Game) bool {
    const w = g.map orelse return false;
    return w.node[g.node].outdoor();
}

pub fn freshSeed() u64 {
    return @bitCast(std.time.milliTimestamp());
}

pub fn castSight(g: *Game, from: P) void {
    var carried: [actor.MAX]lume.Source = undefined;
    var n: usize = 0;
    for (g.pool.slice(), 0..) |a, i| {
        const r = actor.row(a.kind).light;
        if (!a.alive or r <= 0) continue;
        carried[n] = .{ .at = if (isHero(g, i)) from else a.at, .reach = r };
        n += 1;
    }
    const sight = heroRow(g).sight;
    lume.see(&g.lv, from, sight, lume.skyReach(g.outdoors, g.clock.hour(), sight), carried[0..n]);
    g.mini.stale = true;
}

pub const Move = enum { kick, open, loot, step, blocked };

pub fn heroMove(g: *Game, d: mathx.Dir) Move {
    const h = g.heroActor() orelse return .blocked;
    return moveOf(g, h.at, d, g.lv.taken(h.at.add(d.delta())));
}

/// A step from `from` toward `d`, `occupied` saying whether a body or barrel stands where it lands.
pub fn moveOf(g: *const Game, from: P, d: mathx.Dir, occupied: bool) Move {
    if (opensChest(g, from, d)) return .open;
    if (!g.lv.passOk(from, d)) return .blocked;
    if (occupied) return .kick;
    return if (character.lootReached(g, from, from.add(d.delta()))) .loot else .step;
}

fn opensChest(g: *const Game, from: P, d: mathx.Dir) bool {
    return g.lv.at(from.add(d.delta())).opened() != null;
}

fn facingOf(dx: i32) ?Facing {
    return if (dx < 0) .left else if (dx > 0) .right else null;
}

pub fn turnToward(g: *Game, id: u16, dx: i32) void {
    g.facing[actor.Pool.slot(id)] = facingOf(dx) orelse return;
}

pub fn turnLater(g: *Game, id: u16, dx: i32) void {
    g.turning[actor.Pool.slot(id)] = .{ .to = facingOf(dx) orelse return };
}

/// A bump's roll before attributes: the melee weapon's, or the body's own blow.
pub fn kickRaw(rng: *mathx.Rng, gear: *const items.Gear, blow: actor.Strike) i32 {
    return if (gear.weapon(.melee)) |b| b.roll(rng) else blow.roll(rng);
}

/// `late` seconds ago the walk came due.
pub fn heroStep(g: *Game, d: mathx.Dir, late: f32) void {
    const h = g.heroActor() orelse return;
    const to = h.at.add(d.delta());
    switch (heroMove(g, d)) {
        .kick => {
            const w = g.lv.who(to);
            const s = heroBump(g, h.at, to, late);
            switch (g.class) {
                inline else => |c| {
                    const blow = comptime c.strike();
                    if (w != grid.NO_ONE) combat.wound(g, w, combat.heroRoll(g, .melee, kickRaw(&g.rng, &g.inventory.gear, blow)), blow.verb, s) else combat.smash(g, to, blow.verb, s);
                },
            }
            g.lead = s.wait;
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
    turnToward(g, g.hero, d.delta().x);
    combat.endTurn(g);
}

/// `late` seconds into the bump; the hit lands at its apex.
pub fn heroBump(g: *Game, from: P, at: P, late: f32) combat.Stroke {
    const i = heroSlot(g).?;
    _ = combat.glideHeld(g, i, g.glide[i].bumping(at, late));
    return .{ .from = from, .wait = BUMP_LANDS - late };
}

pub fn heroTo(g: *Game, to: P) void {
    g.pool.move(&g.lv, g.hero, to);
    combat.arrive(g, to);
    g.stepped = true;
    g.travel = leadsTo(g, to);
}

pub fn heroAttrs(g: *const Game) attrs.Attrs {
    return g.inventory.gear.stats(g.growth.attributes(g.class));
}

pub fn syncStats(g: *Game) void {
    const h = g.heroActor() orelse return;
    h.max = lifeMax(g);
    h.hp = @min(h.hp, h.max);
    g.mana = @min(g.mana, manaMax(g));
    combat.settleHero(g, 0);
}

fn characterShown(g: *const Game) bool {
    return g.mode == .pause and g.pause_page == .character;
}

/// Character is open with its tabs, not as the Nearby list.
fn bookOpen(g: *const Game) bool {
    return characterShown(g) and !g.character.direct();
}

pub fn lifeMax(g: *const Game) i32 {
    return heroAttrs(g).life();
}

pub fn manaMax(g: *const Game) i32 {
    return heroAttrs(g).mana();
}

pub fn gainMana(g: *Game, n: i32) void {
    g.mana = @min(manaMax(g), g.mana + n);
}

pub fn manaRegen(g: *const Game) i32 {
    return heroes.MANA_REGEN + heroPerks(g).mana_regen;
}

pub fn heroPerks(g: *const Game) passives.Perks {
    return g.inventory.gear.perks(g.growth.perks());
}

pub fn manaShown(g: *const Game) i32 {
    return @min(manaMax(g), g.mana + g.mana_held);
}

pub fn heroRow(g: *const Game) actor.Row {
    return actor.row(g.class.kind());
}

pub fn sayAt(g: *Game, at: P, comptime fmt: []const u8, args: anytype) void {
    sayAs(g, .status, at, fmt, args);
}

/// Logged only if `at` is in sight.
pub fn sayAs(g: *Game, kind: journal.Kind, at: P, comptime fmt: []const u8, args: anytype) void {
    if (g.lv.isLit(at)) g.log.push(kind, fmt, args);
}

fn camAxis(centre: f32, view: f32, map: f32) f32 {
    if (view >= map) return (map - view) * 0.5;
    return std.math.clamp(centre - view * 0.5, 0, map - view);
}

/// Dead bodies remain until their killing blow, flash and glide finish.
pub fn standing(g: *Game, i: usize) bool {
    if (g.split_from[i] != null) return false;
    return g.pool.items[i].alive or g.fx.holds(i) or g.glide[i].done() < 1;
}

pub fn heroSlot(g: *const Game) ?usize {
    return if (g.hero == grid.NO_ONE) null else actor.Pool.slot(g.hero);
}

pub fn isHero(g: *const Game, slot: usize) bool {
    return actor.Pool.idOf(slot) == g.hero;
}

pub fn heroShown(g: *const Game) ?fx.Body {
    const i = heroSlot(g) orelse return null;
    return g.pictured[i];
}

fn heroGlide(g: *Game) ?glide.Glide {
    const i = heroSlot(g) orelse return null;
    return if (standing(g, i)) g.glide[i] else null;
}

pub fn heroNow(g: *Game) ?rl.Vector2 {
    return (heroGlide(g) orelse return null).now();
}

pub fn drawnAt(g: *Game, i: usize) ?rl.Vector2 {
    if (!standing(g, i)) return null;
    const at = g.glide[i].now();
    return if (g.lv.isLit(cellUnder(at))) at else null;
}

pub fn drawnCell(g: *Game, i: usize) ?P {
    return cellUnder(drawnAt(g, i) orelse return null);
}

pub fn casterAt(g: *Game, i: usize, area: grid.Box) ?rl.Vector2 {
    if (!standing(g, i)) return null;
    const at = g.glide[i].now();
    return if (area.holds(cellUnder(at))) at else null;
}

pub fn camWant(g: *Game) rl.Vector2 {
    const at = (heroGlide(g) orelse return g.cam).ground();
    const half: f32 = @floatFromInt(HALF_CELL);
    return .{
        .x = camAxis(at.x + half, @floatFromInt(g.screen.x), @floatFromInt(MAP_PX.x)),
        .y = camAxis(at.y + half, @floatFromInt(g.screen.y), @floatFromInt(MAP_PX.y + hud.COVER)),
    };
}

pub fn snapGlide(g: *Game) void {
    for (g.pool.slice(), 0..) |*a, i| g.glide[i] = glide.Glide.rest(a);
}

/// `late` is seconds since the glides started; visible foes follow the hero in acting order.
pub fn stepGlide(g: *Game, late: f32) void {
    var next: f32 = if (g.lead) |t| t + late + STAGGER_S else 0;
    const hero = heroSlot(g).?;
    const warded = g.owed[hero].worn;
    g.owed[hero].worn = null;
    const hero_done = stagger(g, g.hero, late, g.lead orelse 0, &next);
    g.lead = null;
    var part: [actor.MAX]f32 = @splat(hero_done);
    for (g.order[0..g.order_n]) |id| part[actor.Pool.slot(id)] = stagger(g, id, late, hero_done, &next);
    for (g.owed[0..g.pool.n], 0..) |*o, i| {
        if (!o.any()) continue;
        const start = if (g.split_from[i]) |p| @max(hero_done, part[p], g.fx.revealsIn(i)) else hero_done;
        part[i] = stagger(g, actor.Pool.idOf(i), late, start, &next);
    }
    if (warded) |c| g.fx.settle(std.mem.max(f32, part[0..g.pool.n]), .{ .slot = hero, .after = c });
    for (g.pool.slice(), 0..) |*a, i| {
        if (!g.glide[i].to.eq(a.at)) g.glide[i] = g.glide[i].toward(a.at, late);
    }
}

/// How far through a step in shallows its splash is drawn: the foot coming down.
pub const SPLASH_AT: f32 = 0.85;

fn splashSteps(g: *Game) void {
    for (g.glide[0..g.pool.n], 0..) |*gl, i| {
        if (gl.splashed or gl.done() < SPLASH_AT) continue;
        gl.splashed = true;
        if (gl.bump != null or std.meta.eql(gl.from, glide.cellPx(gl.to))) continue;
        if (g.pictured[i].down() or actor.row(g.pictured[i].kind).movement == .flying) continue;
        const at = drawnAt(g, i) orelse continue;
        if (g.lv.at(cellUnder(at)) == .shallows) g.fx.splash(middle(at));
    }
}

/// Completion time; unplaced bodies wait for the hero and knockback slide.
fn stagger(g: *Game, id: u16, late: f32, start: f32, next: *f32) f32 {
    comptime for (std.enums.values(Tick)) |t| switch (t) {
        .bit, .arrow, .gassed, .burned, .bled, .worn, .swept => {},
    };
    const i = actor.Pool.slot(id);
    const a = g.pool.items[i];
    const gl = &g.glide[i];
    const moved = !gl.to.eq(a.at);
    if (!moved and !g.owed[i].any()) {
        if (g.turning[i]) |*t| {
            if (t.in == null) t.in = start;
        }
        return start;
    }
    const owed = g.owed[i];
    g.owed[i] = .{};
    const bit = owed.bit;
    const shown = g.lv.isLit(a.at);
    const placed = if (moved) shown or g.lv.isLit(gl.to) else (shown or owed.arrow != null) and bit != null;
    var wait = if (placed) next.* else 0;
    if (placed and id != g.hero and (moved or bit != null)) wait = @max(wait, late + gl.left());
    if (placed and moved and id != g.hero) wait = @max(wait, late + clearIn(g, i, a.at));
    if (placed) next.* = wait + STAGGER_S;
    if (g.turning[i]) |*t| t.in = if (placed) wait - late else start;
    const hero = heroSlot(g).?;
    const hero_at = g.pool.items[hero].at;
    var lands = if (placed) wait else if (moved) start else @max(start, gl.left());
    if (moved) {
        gl.* = gl.toward(a.at, late - wait);
    } else if (bit != null and owed.arrow == null) {
        gl.* = gl.bumping(hero_at, late - wait);
    }
    if ((moved or (bit != null and owed.arrow == null)) and placed) {
        lands = gl.left();
        combat.holdUntil(g, lands);
    }
    var hits = wait + BUMP_LANDS - late;
    if (owed.arrow) |flight| {
        const release = @max(start, wait - late);
        const s = Shot{ .from = a.at, .flight = flight, .t = -release };
        g.foe_shots[i] = s;
        hits = release + s.lands();
        lands = release + s.ends();
        next.* = @max(next.*, lands + late);
        combat.holdUntil(g, lands);
    }
    if (bit) |b| switch (b) {
        .hurt, .kill => |after| combat.strike(g, hero, .{ .from = a.at, .wait = hits }, hero_at, b == .kill, after),
        .burst => |after| combat.strike(g, i, .{ .from = hero_at, .wait = hits }, a.at, true, after),
        .miss => {},
    };
    if (owed.swept) |*sw| for (sw.hit[0..sw.n]) |h| combat.strike(g, h.slot, .{ .from = a.at, .wait = hits }, h.at, h.lethal, h.after);
    lands = @max(lands, g.fx.landsIn(i));
    if (owed.worn) |c| g.fx.settle(lands, .{ .slot = i, .after = c });
    const mark: ?[2]f32 = if (shown) mathx.centre(a.at) else null;
    const drip: ?fx.Drip = if (mark) |m| .{ .at = m, .matter = fx.matterOf(a.kind) } else null;
    const in_view = shown or placed;
    if (owed.gassed) |h| harmShown(g, a.at, lands, h, false, in_view, .{ .slot = i });
    if (owed.burned) |h| harmShown(g, a.at, lands, h, true, in_view, .{ .slot = i, .fire_at = mark });
    if (owed.bled) |h| harmShown(g, a.at, lands, h, false, in_view, .{ .slot = i, .drip = drip });
    return lands;
}

/// Wait for deaths at the destination and witnessed deaths that caused flight.
fn clearIn(g: *Game, slot: usize, to: P) f32 {
    var t: f32 = if (g.fx.speech[slot].after) |fallen| g.fx.landsIn(fallen) else 0;
    if (!g.lv.isLit(to)) return t;
    for (g.pool.slice(), 0..) |a, j| {
        if (a.alive or !a.at.eq(to) or !standing(g, j)) continue;
        t = @max(t, @max(g.fx.heldIn(j), g.glide[j].left()));
    }
    return t;
}

fn harmShown(g: *Game, at: P, lands: f32, h: Harm, fire: bool, in_view: bool, s: fx.Sting) void {
    if (h.kill) {
        combat.strike(g, s.slot, .{ .from = at, .wait = lands, .fire = fire }, at, true, h.after);
    } else if (in_view) {
        var shown = s;
        shown.after = h.after;
        combat.sting(g, lands, shown);
    } else g.fx.settle(lands, .{ .slot = s.slot, .after = h.after });
}

const Walk = struct { d: mathx.Dir, late: f32 };
pub const Queued = union(enum) { walk: mathx.Dir, skill: skills.Use, interact };

pub fn quiet(g: *const Game) bool {
    return g.busy <= PACE_SLACK;
}

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
    if (queueInteract(g) and !quiet(g)) return true;
    if (takeQueued(g, .interact) == null) return false;
    return character.openNearby(g);
}

fn skillDue(g: *Game) ?skills.Use {
    if (skills.usedSkill(g)) |u| g.pending = .{ .skill = u };
    return takeQueued(g, .skill);
}

fn paced(g: *Game) ?Walk {
    if (g.st.walk) |d| {
        if (!quiet(g)) {
            queueWalk(g, d);
            return null;
        }
        g.pending = null;
        return .{ .d = d, .late = @min(g.st.late(), sinceQuiet(g)) };
    }
    return .{ .d = takeQueued(g, .walk) orelse return null, .late = sinceQuiet(g) };
}

fn takeQueued(g: *Game, comptime tag: std.meta.Tag(Queued)) ?std.meta.TagPayload(Queued, tag) {
    const q = g.pending orelse return null;
    if (q != tag or !quiet(g)) return null;
    g.pending = null;
    return @field(q, @tagName(tag));
}

/// A stunned hero's next turn passes once the stunning one is drawn, wherever a turn could be spent.
fn stunnedTurn(g: *Game) bool {
    if (!quiet(g) or g.travel != null) return false;
    if (g.mode != .play and !characterShown(g)) return false;
    const h = g.heroActor() orelse return false;
    if (!h.clock.owes()) return false;
    h.clock.pass(turn_clock.TURN);
    combat.endTurn(g);
    return true;
}

/// Seconds since the last turn was drawn out.
pub fn sinceQuiet(g: *const Game) f32 {
    return @max(0, -g.busy);
}

/// Advance presentation before new actions so their effects start at the correct delay.
pub fn update(g: *Game, dt: f32) void {
    if (!g.st.focused) holdWalk(g);
    mouseControls.prepare(g);
    if (playShown(g) or g.mode == .aim or g.mode == .inspect) {
        if (g.st.pointer) |p| {
            if (raster.holds(journal.box(g.screen), p) and g.st.scroll != 0) g.log.move(g.st.scroll);
        }
    }
    const death_drawn = deathShown(g);
    g.busy -= dt;
    for (g.glide[0..g.pool.n]) |*gl| gl.t += dt;
    g.fx.step(&g.lv, dt);
    catchUp(g);
    if (quiet(g)) {
        g.log.release();
        g.gold_taken = null;
        drawnTurn(g);
    }
    g.cloud.step(&g.lv, dt);
    splashSteps(g);
    if (g.shot) |*s| {
        s.t += dt;
        const end = @min(s.t, s.lands());
        const gap = s.lands() / @as(f32, @floatFromInt(@max(1, s.flight.len * TRAIL_PER_CELL)));
        const heading = s.direction();
        while (s.trail_t < end) : (s.trail_t += gap) g.fx.trail(&g.lv, s.position(s.trail_t), heading, s.act, s.t - s.trail_t);
        if (s.t >= s.ends()) g.shot = null;
    }
    for (&g.foe_shots) |*pending| {
        if (pending.*) |*s| {
            s.t += dt;
            if (s.t >= s.ends()) pending.* = null;
        }
    }
    stepTurning(g, dt);
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
            if (g.travel) |l| {
                queuePress(g);
                if (quiet(g)) goThrough(g, l);
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
    if (characterShown(g) or g.mode == .inspect) if (g.travel) |l| if (quiet(g)) goThrough(g, l);
    if (!std.meta.eql(was, screenOf(g))) holdWalk(g);
    stepGlide(g, late);
    catchUp(g);
    splashSteps(g);
    stepVignette(g, dt);
    const want = camWant(g);
    const k = mathx.easing(dt, CAM_EASE);
    g.cam = g.cam.lerp(want, k);
    g.hour_shown = day.wrapHour(g.hour_shown + day.toward(g.hour_shown, g.clock.hour()) * mathx.easing(dt, HOUR_EASE));
    g.xp_shown = mathx.ease(g.xp_shown, g.xp_aim, mathx.easing(dt, XP_EASE), 1);
    const resource_ease = mathx.easing(dt, RESOURCE_EASE);
    g.life_fill = mathx.ease(g.life_fill, overlay.lifeFill(g), resource_ease, resource_ease);
    g.mana_fill = mathx.ease(g.mana_fill, overlay.manaFill(g), resource_ease, resource_ease);
    g.light.sky = skyNow(g);
    g.light.step(&g.lv, dt);
    g.light.carrier = carrierAt(g);
    if (g.debug.visuals.weather) g.rain.step(dt, weatherNow(g), g.screen.x, g.screen.y, CELL_F);
}

fn skyNow(g: *const Game) ?sky.Sky {
    return if (g.outdoors) sky.under(g.hour_shown, climateNow(g).light) else null;
}

pub fn weatherNow(g: *const Game) ?climate.Weather {
    return if (g.outdoors) climateNow(g).weather else null;
}

fn climateNow(g: *const Game) climate.Climate {
    const w = g.map orelse return .{};
    return w.node[g.node].sky();
}

/// Per second, how fast the sky drawn catches the hour a turn moved on.
const HOUR_EASE: f32 = 4;
/// Per second, how fast the experience bar fills toward a drawn turn's experience.
const XP_EASE: f32 = 8;
/// Per second, how fast the life and mana orbs fill toward what is shown.
pub const RESOURCE_EASE = XP_EASE;

/// Levels gained so far, the current one's progress as the fraction.
pub fn xpLevels(g: *const Game) f32 {
    const xp: f32 = @floatFromInt(g.growth.xp);
    const needed: f32 = @floatFromInt(g.growth.needed());
    return @as(f32, @floatFromInt(g.growth.level - 1)) + xp / needed;
}

fn drawnTurn(g: *Game) void {
    if (g.growth.level > g.growth_shown.level and g.mode != .dead) {
        if (g.heroActor() != null) g.fx.levelUp();
    }
    showProgress(g);
}

fn showProgress(g: *Game) void {
    g.growth_shown = g.growth;
    g.gold_shown = g.gold;
    g.xp_aim = xpLevels(g);
}

pub fn settleXp(g: *Game) void {
    showProgress(g);
    g.xp_shown = g.xp_aim;
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

fn stepTurning(g: *Game, dt: f32) void {
    for (&g.turning, 0..) |*t, i| {
        if (t.*) |*u| {
            const left = (u.in orelse continue) - dt;
            u.in = left;
            if (left > PACE_SLACK) continue;
            g.facing[i] = u.to;
            t.* = null;
        }
    }
}

/// Reveal split halves at impact, after their parent becomes visible.
pub fn catchUp(g: *Game) void {
    var dying = false;
    for (g.pool.slice(), 0..) |a, i| {
        if (!g.fx.pending(i)) {
            g.pictured[i] = fx.Body.of(a, g.seq);
        } else if (g.fx.landedOn(i)) |b| {
            if (b.seq > g.pictured[i].seq) g.pictured[i] = b;
        }
        if (!a.alive and !g.pictured[i].down()) dying = true;
        const from = g.split_from[i] orelse continue;
        if (g.fx.revealing(i) or g.split_from[from] != null) continue;
        g.split_from[i] = null;
        g.glide[i] = g.glide[from].toward(a.at, -clearIn(g, i, a.at));
        if (g.lv.isLit(g.pool.items[from].at) or g.lv.isLit(a.at)) combat.holdUntil(g, g.glide[i].left());
    }
    if (!dying) g.flasks_shown = g.flasks;
    g.mana_held = @max(0, g.mana_held - g.fx.mana_landed);
    g.fx.mana_landed = 0;
    if (heroSlot(g)) |h| {
        if (!g.fx.pending(h)) g.mana_held = 0;
    }
    g.fx.react(g.pictured[0..g.pool.n]);
}

pub fn deathShown(g: *const Game) bool {
    return g.mode == .dead and quiet(g);
}

pub fn modeShown(g: *const Game) Mode {
    return if (g.mode == .dead and !quiet(g)) g.died_in else g.mode;
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
    const max = lifeMax(g);
    const i = heroSlot(g) orelse return g.vignette.step(dt, 0, max, max);
    g.vignette.step(dt, g.fx.flashOf(i), g.pictured[i].hp, g.pictured[i].max);
}

/// The hero's middle as drawn, cells: the carried light glides with the body.
pub fn carrierAt(g: *Game) ?[2]f32 {
    return middle(heroNow(g) orelse return null);
}

pub fn middle(v: rl.Vector2) [2]f32 {
    return .{ v.x / CELL_F + 0.5, v.y / CELL_F + 0.5 };
}

/// The cell a body drawn with its corner at `v` stands in.
pub fn cellUnder(v: rl.Vector2) P {
    return mathx.cellOf(middle(v));
}

fn textMid(g: *Game, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    menu.mid(g.face, g.screen, s, y, size, col);
}

fn drawDead(g: *Game) void {
    var buf: [menu.NOTE_MAX + 1]u8 = undefined;
    const mid = @divTrunc(g.screen.y, 2);
    character.veil(g);
    const DIED = " DIED";
    var died: [heroes.Name.MAX + DIED.len + 1]u8 = undefined;
    const said = menu.shout(&died, "{s}" ++ DIED, .{g.name.text()});
    menu.heading(g.face, g.screen, said, mid + DEAD_TITLE_DY, menu.TITLE, look.LIFE, look.LIFE);
    textMid(g, std.fmt.bufPrintZ(&buf, "{d} foes killed. Seed {d}.", .{ g.kills, g.seed }) catch "", mid + DEAD_SCORE_DY, font.BODY, look.TEXT);
    menu.action(&g.face, deadBox(g.screen), prompt_icon.Prompt.menuOf(&g.st, CONFIRM), if (g.permadeath) "Title" else "Restart");
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
    journal.draw(&g.face, &g.sprites, g.screen, &g.log);
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
    var need = look.Assets.of(&g.lv);
    need.barrel = need.barrel or g.fx.barrels_due > 0;
    for (g.pool.slice(), 0..) |a, i| {
        if (a.alive) need.body(a.kind);
        if (standing(g, i)) need.body(g.pictured[i].kind);
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
