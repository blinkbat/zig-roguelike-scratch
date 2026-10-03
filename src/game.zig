const std = @import("std");
const rl = @import("raylib");

const mathx = @import("core/mathx.zig");
const input = @import("core/input.zig");
const grid = @import("world/grid.zig");
const fov = @import("world/fov.zig");
const gen = @import("world/gen.zig");
const gas = @import("world/gas.zig");
const atlas = @import("world/atlas.zig");
const editor = @import("edit/editor.zig");
const menu = @import("ui/menu.zig");
const heroes = @import("play/hero.zig");
const naming = @import("ui/naming.zig");
const actor = @import("play/actor.zig");
const bow = @import("play/bow.zig");
const pack = @import("play/pack.zig");
const skillbar = @import("play/skillbar.zig");
const look = @import("gfx/look.zig");
const light = @import("gfx/light.zig");
const font = @import("gfx/font.zig");
const fx = @import("gfx/fx.zig");
const cloud = @import("gfx/cloud.zig");
const vignette = @import("gfx/vignette.zig");
const sky = @import("gfx/sky.zig");
const day = @import("world/day.zig");
const lume = @import("world/lume.zig");

const P = mathx.P;

const WINDOW_W: i32 = 1600;
const WINDOW_H: i32 = 900;
const CELL: i32 = 64;
const CELL_F: f32 = @floatFromInt(CELL);
const HALF_CELL: i32 = @divTrunc(CELL, 2);

/// `px` at the sprites' authored size, at `CELL`.
fn authored(comptime px: i32) i32 {
    return @divExact(CELL * px, look.SPRITE_PX);
}
const GLYPH: i32 = authored(look.GLYPH_PX);
const CARET: i32 = authored(30);
const TORCH_GLYPH: i32 = authored(30);
const TEXT: i32 = font.BODY;
const LINE_W: i32 = authored(2);
const OUTLINE_INSET: i32 = authored(1);
const BODY_BAR_INSET: i32 = authored(6);
const BODY_BAR_H: i32 = authored(4);
const BODY_BAR_LIFT: i32 = authored(2);
const CARET_PAD_X: i32 = authored(4);
const CARET_PAD_Y: i32 = authored(2);
const HUD_H: i32 = 124;
const HUD_PAD: i32 = 20;
const BAR_W: i32 = 280;
const BAR_H: i32 = 24;
const BAR_Y: i32 = 18;
const BAR_TEXT_X: i32 = 8;
const TALLY_Y: i32 = 54;
const TALLY_GAP: i32 = 24;
const HINT_Y: i32 = HUD_H - 32;
const HUD_EDGE: i32 = 2;
const LOG_Y: i32 = 14;
const TEXT_LINE: i32 = 26;
const LOG_FADE: f32 = 0.22;
const DEAD_TITLE_DY: i32 = -100;
const DEAD_SCORE_DY: i32 = -10;
const DEAD_HINT_DY: i32 = 30;
const SLOT_PX: i32 = 56;
const SLOT_MID: i32 = @divTrunc(SLOT_PX, 2);
const CLEAR_GLYPH: i32 = @divTrunc(SLOT_PX, 2);
const SLOT_GAP: i32 = 6;
const SLOT_STEP: i32 = SLOT_PX + SLOT_GAP;
const CARRIED_A: f32 = 0.35;
const GROUP_GAP: i32 = 20;
const SLOT_TEXT: i32 = 16;
const SLOT_GLYPH: i32 = 40;
const KEY_GAP: i32 = 2;
const SKILLS_Y: i32 = 12;
const SLOT_XS = blk: {
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
const SKILLS_W: i32 = SLOT_XS[SLOT_XS.len - 1] + SLOT_PX;
const PICKS: usize = 1 + skillbar.ACTS.len;
const BIND_TITLE: i32 = 40;
const BIND_TOP_DY: i32 = -230;
const BIND_ROWS_DY: i32 = BIND_TITLE + BIND_POP_DY + SLOT_PX;
const BIND_LABEL_GAP: i32 = 6;
const BIND_ROW_GAP: i32 = 24;
const BIND_ROW_H: i32 = TEXT + BIND_LABEL_GAP + SLOT_PX + KEY_GAP + SLOT_TEXT + BIND_ROW_GAP;
const BIND_POP_DY: i32 = 10;
const BIND_INFO_DY: i32 = 8;
const MINI: i32 = 3;
const MINI_W: i32 = grid.W * MINI;
const MINI_H: i32 = grid.H * MINI;
const MINI_PAD: i32 = 12;
/// Cells past the view a prop's shadow can reach into it from: the longest the sky throws, and a canopy's spread.
const CAST_MARGIN: i32 = 3;
const MINI_FRAME: i32 = 4;
const MINI_HERO_GROW: i32 = 1;
pub const SHOT_SEED: u64 = 0x5EED_1234;
const GOLD_LO: i32 = 3;
const GOLD_HI: i32 = 12;
const SHOTS_DIR = "shots";
const FLIGHT_S: f32 = 0.022;
const CAM_EASE: f32 = 12.0;
/// One walk repeat, so the glides of a held walk join end to end.
const GLIDE_S: f32 = input.Stepper.ARR;
/// Pixels, at the top of each glide's hop.
const HOP_PX: f32 = @floatFromInt(authored(10));
const SLIDE_S: f32 = GLIDE_S * 2;
const STAGGER_S: f32 = GLIDE_S * 0.5;
const BUMP_S: f32 = GLIDE_S;
/// Of the bump, the share out to the blow.
const BUMP_HIT: f32 = 0.5;
const BUMP_LANDS: f32 = BUMP_S * BUMP_HIT;
const BUMP_PX: f32 = CELL_F * 0.35;
/// A walk due this close to the turn's last glide ending is not held for it.
const PACE_SLACK: f32 = 1e-4;
/// Ease-out-back's overshoot constant: 1.165 carries a slide 5% past its cell (1.70158, the usual one, 10%).
const SLIDE_BACK: f32 = 1.165;
/// `gen.build` rolls from the bare seed; without the salt the packs replay the floor's rolls.
const PLAY_SALT: u64 = 0x9E37_79B9_7F4A_7C15;
const LINE_BUF: usize = 128;

const CONFIRM = menu.CONFIRM;
const BACK = menu.BACK;
const CHANGE = input.Button.x;
const REMOVE = input.Button.y;
const BINDS = skillbar.BINDS;

comptime {
    std.debug.assert(@mod(CELL, look.SPRITE_PX) == 0);
    std.debug.assert(GLYPH <= CELL);
    std.debug.assert(LOG_Y + @as(i32, @intCast(Log.SHOWN)) * TEXT_LINE <= HUD_H);
    std.debug.assert(SKILLS_Y + SLOT_PX + KEY_GAP + SLOT_TEXT <= HUD_H);
}

pub const Mode = enum { play, aim, bind, dead, pause };

pub const Back = enum { title, editor };

pub const Exit = enum { back, quit };

const PAUSE = menu.PAUSE;
const PauseRow = enum { resume_, restart, back, quit };
const PAUSE_ROWS = std.enums.values(PauseRow);

const Binds = struct {
    row: usize = 0,
    col: usize = 0,
    menu: Menu = .browse,

    const Menu = union(enum) { browse, pick: usize, carry: skillbar.Slot };

    fn slot(b: Binds) skillbar.Slot {
        return .{ .set = skillbar.SETS[b.row], .button = skillbar.SLOTS[b.col] };
    }

    fn move(b: *Binds, d: mathx.Dir) void {
        b.col = mathx.wrap(b.col, d.delta().x, skillbar.SLOTS.len);
        b.row = mathx.wrap(b.row, d.delta().y, skillbar.SETS.len);
    }

    fn colOf(button: input.Button) usize {
        return std.mem.indexOfScalar(input.Button, &skillbar.SLOTS, button).?;
    }
};

/// Picker cell 0 clears the slot; the rest are the acts in order. An empty slot opens it on the first act.
fn pickOf(a: ?skillbar.Act) usize {
    return 1 + std.mem.indexOfScalar(skillbar.Act, skillbar.ACTS, a orelse skillbar.ACTS[0]).?;
}

fn pickAct(i: usize) ?skillbar.Act {
    return if (i == 0) null else skillbar.ACTS[i - 1];
}

pub const Log = struct {
    pub const LINES: usize = 32;
    pub const SHOWN: usize = 4;
    pub const COLS: usize = 96;
    text: [LINES][COLS]u8 = undefined,
    len: [LINES]usize = [_]usize{0} ** LINES,
    head: usize = 0,
    n: usize = 0,

    pub fn say(self: *Log, comptime fmt: []const u8, args: anytype) void {
        const slot = &self.text[self.head];
        self.len[self.head] = if (std.fmt.bufPrintZ(slot, fmt, args)) |s| s.len else |_| blk: {
            slot[0] = 0;
            break :blk 0;
        };
        self.head = (self.head + 1) % LINES;
        self.n = @min(LINES, self.n + 1);
    }

    /// `back` 0 is the newest.
    pub fn line(self: *const Log, back: usize) ?[:0]const u8 {
        if (back >= self.n) return null;
        const i = (self.head + LINES - 1 - back) % LINES;
        return self.text[i][0..self.len[i] :0];
    }
};

/// Presentation only: the hit already resolved when this was made.
pub const Shot = struct {
    flight: bow.Flight,
    glyph: u8,
    t: f32 = 0,

    fn cell(self: Shot) ?P {
        const i: usize = @intFromFloat(self.t / FLIGHT_S);
        if (i >= self.flight.len) return null;
        return self.flight.path[i];
    }
};

/// Seconds from the loose until the arrow is at the `n`th cell of its flight.
fn flown(n: usize) f32 {
    return @as(f32, @floatFromInt(n)) * FLIGHT_S;
}

fn cellPx(p: P) rl.Vector2 {
    return .{ .x = @floatFromInt(p.x * CELL), .y = @floatFromInt(p.y * CELL) };
}

/// Presentation only: the body already stands on `to`.
pub const Glide = struct {
    from: rl.Vector2,
    to: P,
    t: f32,
    gait: look.Gait,
    /// Where a step taken mid-hop left the body, so it hops on from there instead of dropping to the floor.
    from_lift: f32 = 0,
    /// Pixels toward what a melee blow strikes, at the bump's height; null for a step.
    bump: ?rl.Vector2 = null,

    fn still(p: P, gait: look.Gait) Glide {
        var gl = Glide{ .from = cellPx(p), .to = p, .t = 0, .gait = gait };
        gl.t = gl.span();
        return gl;
    }

    fn toward(self: Glide, p: P, t: f32) Glide {
        return .{ .from = self.now(), .to = p, .t = t, .gait = self.gait, .from_lift = self.height() };
    }

    fn bumping(self: Glide, at: P, t: f32) Glide {
        const d = at.sub(self.to);
        const bump = rl.Vector2{ .x = @as(f32, @floatFromInt(d.x)) * BUMP_PX, .y = @as(f32, @floatFromInt(d.y)) * BUMP_PX };
        return .{ .from = self.now(), .to = self.to, .t = t, .gait = self.gait, .from_lift = self.height(), .bump = bump };
    }

    const Motion = enum { hop, slide, bump };

    fn motion(self: Glide) Motion {
        if (self.bump != null) return .bump;
        return switch (self.gait) {
            inline else => |gt| @field(Motion, @tagName(gt)),
        };
    }

    fn span(self: Glide) f32 {
        return switch (self.motion()) {
            .hop => GLIDE_S,
            .slide => SLIDE_S,
            .bump => BUMP_S,
        };
    }

    /// `t` is below 0 while the glide waits its turn.
    fn done(self: Glide) f32 {
        return std.math.clamp(self.t / self.span(), 0, 1);
    }

    fn now(self: Glide) rl.Vector2 {
        const at = self.ground();
        const b = self.bump orelse return at;
        const k = bumpOf(self.done());
        return .{ .x = at.x + b.x * k, .y = at.y + b.y * k };
    }

    /// Where the body is, its bump aside: the camera follows this.
    fn ground(self: Glide) rl.Vector2 {
        const k = switch (self.motion()) {
            .hop, .bump => self.done(),
            .slide => overshoot(self.done()),
        };
        const to = cellPx(self.to);
        return .{ .x = mathx.lerpF(self.from.x, to.x, k), .y = mathx.lerpF(self.from.y, to.y, k) };
    }

    fn height(self: Glide) f32 {
        const k = self.done();
        const hop: f32 = switch (self.motion()) {
            .hop => HOP_PX * 4 * k * (1 - k),
            .slide, .bump => 0,
        };
        return self.from_lift * (1 - k) + hop;
    }

    /// Pixels above the ground the body is drawn; its shadow, bar, light and the camera stay on the ground.
    fn lift(self: Glide) i32 {
        return mathx.roundTiesUp(self.height());
    }
};

fn bumpOf(k: f32) f32 {
    if (k < BUMP_HIT) {
        const u = k / BUMP_HIT;
        return u * u;
    }
    return 1 - mathx.smooth((k - BUMP_HIT) / (1 - BUMP_HIT));
}

/// Penner's ease-out-back.
fn overshoot(k: f32) f32 {
    const u = k - 1;
    return 1 + (SLIDE_BACK + 1) * u * u * u + SLIDE_BACK * u * u;
}

pub const Facing = enum { right, left };

const Bite = struct { blow: enum { hurt, kill, burst }, after: fx.After };

const Gassed = struct { kill: bool, after: fx.After };

/// `in` is set once the turn it was taken in has its stagger.
const Turning = struct { to: Facing, in: ?f32 = null };

pub const Visit = struct {
    lv: grid.Level,
    pool: actor.Pool,
    facing: [actor.MAX]Facing,

    fn of(g: *const Game) Visit {
        var v: Visit = undefined;
        inline for (std.meta.fields(Visit)) |f| @field(v, f.name) = @field(g, f.name);
        return v;
    }

    fn restore(v: *const Visit, g: *Game) void {
        inline for (std.meta.fields(Visit)) |f| @field(g, f.name) = @field(v, f.name);
    }
};

pub const Game = struct {
    mode: Mode = .play,
    paused_from: Mode = .play,
    pause_menu: menu.Menu = .{},
    back: Back = .title,
    exit: ?Exit = null,
    name: heroes.Name = heroes.Class.archer.unnamed(),
    /// A run in a save slot: death ends it, and the way out of the death screen is the way back.
    permadeath: bool = false,
    /// The hour, moved on a turn at a time.
    clock: day.Clock = .{},
    /// The node played is open to the sky, so the hour lights it.
    outdoors: bool = false,
    /// The hour as the sky is drawn: eased after `clock`, so the light never steps.
    hour_shown: f32 = day.Clock.hour(.{}),
    /// DEBUG: the hero keeps 1 hp whatever strikes it, so it never dies. Kept across runs, never saved.
    unkillable: bool = false,
    /// A turn was taken, or the run changed, since the run was last saved. Nothing in the simulation reads it.
    unsaved: bool = false,
    lv: grid.Level,
    pool: actor.Pool = .{},
    hero: u16 = grid.NO_ONE,
    /// The world being played; null plays one generated floor.
    world: ?*const atlas.Atlas = null,
    node: usize = 0,
    /// Indexed by node.
    visits: *[atlas.MAX_NODES]Visit,
    visited: std.StaticBitSet(atlas.MAX_NODES) = .initEmpty(),
    /// The door the archer stepped onto this turn, gone through once the turn is drawn.
    travel: ?atlas.Link = null,
    rng: mathx.Rng,
    seed: u64 = 0,
    kills: usize = 0,
    gold: i32 = 0,
    log: Log = .{},
    st: input.State = .{},
    bar: skillbar.Bar = .{},
    binds: Binds = .{},
    aim_by: input.Button = .x,
    mark: P = .{ .x = 0, .y = 0 },
    /// World pixels, eased toward the archer. Nothing in the simulation reads it.
    cam: rl.Vector2 = .{ .x = 0, .y = 0 },
    screen: P = .{ .x = WINDOW_W, .y = WINDOW_H },
    shot: ?Shot = null,
    /// Indexed by pool slot.
    glide: [actor.MAX]Glide = undefined,
    /// Indexed by pool slot. Presentation only: the last way a body stepped, struck or aimed across.
    facing: [actor.MAX]Facing = @splat(.right),
    /// Indexed by pool slot.
    turning: [actor.MAX]?Turning = @splat(null),
    /// The living foes as of the last turn, nearest the archer first: the order they act and are drawn acting in.
    order: [actor.MAX]u16 = undefined,
    order_n: usize = 0,
    /// Seconds until the last turn's slowest glide, arrow or flash ends; a walk waits for it.
    busy: f32 = 0,
    /// A walk that came due while `busy`.
    pending: ?mathx.Dir = null,
    /// Seconds in, when the kick or arrow the archer dealt this turn without stepping lands: the stagger's first place.
    lead: ?f32 = null,
    /// Indexed by pool slot: the foe's blow this turn, which lands at its place in the stagger.
    bit: [actor.MAX]?Bite = @splat(null),
    /// Indexed by pool slot: lands as the body arrives, or after the archer's part for one with no place in the stagger.
    gassed: [actor.MAX]?Gassed = @splat(null),
    /// Indexed by pool slot: the body as the picture has it, which catches up with it as each blow on it lands.
    pictured: [actor.MAX]fx.Body = undefined,
    /// The blows dealt so far, so the picture takes them in the order they were dealt.
    seq: u64 = 0,
    /// Indexed by pool slot: the slot a slime split off, until the blow that split it lands.
    split_from: [actor.MAX]?usize = @splat(null),
    fx: fx.Fx = .{},
    vignette: vignette.Vignette = .{},
    mini: Minimap = .{},
    sprites: look.Sprites = .{},
    face: font.Face = .{},
    light: *light.Light,
    cloud: *cloud.Cloud,
    /// Terrain only, so the turn's first chase fills it for every foe after.
    flowed: bool = false,
    flow: [grid.CELLS]i32,
    queue: [grid.CELLS]u32,

    pub fn archer(self: *Game) ?*actor.Actor {
        return self.pool.get(self.hero);
    }

    pub fn viewH(self: *const Game) i32 {
        return self.screen.y - HUD_H;
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

/// In `w`, or on one generated floor for none.
fn startRun(g: *Game, w: ?*const atlas.Atlas, seed: u64) void {
    g.world = w;
    g.visited = .initEmpty();
    g.node = 0;
    g.outdoors = false;
    g.seed = seed;
    g.rng = mathx.Rng.init(seed ^ PLAY_SALT);
    g.pool = .{};
    g.hero = grid.NO_ONE;
    g.clock = .{};
    g.hour_shown = g.clock.hour();
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
        out.writer().print("{s}{d} {s}s", .{ menu.listSep(i, actor.FOES.len), g.pool.tally(k).total, actor.row(k).name }) catch break;
    }
    g.log.say("{s} somewhere on this floor. Seed {d}.", .{ out.getWritten(), seed });
}

pub fn beginWorld(g: *Game, w: *const atlas.Atlas) void {
    beginWorldAt(g, w, w.start, freshSeed());
}

pub fn beginWorldAt(g: *Game, w: *const atlas.Atlas, from: atlas.Start, seed: u64) void {
    startRun(g, w, seed);
    freshRun(g);
    enter(g, from.node, from.at);
}

/// The archer is the first body in every node's pool, so its id is the same in each.
fn enter(g: *Game, n: usize, at: P) void {
    const w = g.world.?;
    const hp = if (g.archer()) |h| h.hp else actor.row(HERO).hp;
    g.node = n;
    g.outdoors = w.node[n].outdoor();
    const back = g.visited.isSet(n);
    if (back) {
        g.visits[n].restore(g);
        const hero = actor.Pool.slot(g.hero);
        g.lv.clear(g.pool.items[hero].at);
    } else w.node[n].stamp(&g.lv, rollOf(g.seed, n));
    const placing: []const atlas.Foe = if (back) &.{} else w.node[n].placed();
    const to = atlas.landing(&g.lv, at, placing) orelse at;
    if (back) {
        const hero = actor.Pool.slot(g.hero);
        g.pool.items[hero].at = to;
        g.lv.stand(to, g.hero);
    } else {
        spawnHero(g, to);
        switch (w.node[n].plan) {
            .procgen => |*pg| pack.place(&g.lv, &g.pool, &g.rng, to, &pg.foes),
            .bespoke => for (placing) |f| {
                if (g.lv.vacant(f.at)) _ = g.pool.spawn(&g.lv, actor.Actor.of(f.kind, f.at));
            },
        }
    }
    g.archer().?.hp = hp;
    g.unsaved = true;
    freshTurn(g);
    settle(g);
}

/// A procgen node's floor this run: the same for the run, another the next.
fn rollOf(run: u64, n: usize) u64 {
    return std.hash.Wyhash.hash(run, std.mem.asBytes(&n));
}

fn leadsTo(g: *const Game, p: P) ?atlas.Link {
    const w = g.world orelse return null;
    const k = g.lv.doorAt(p) orelse return null;
    return w.node[g.node].door[k].to;
}

fn goThrough(g: *Game, l: atlas.Link) void {
    g.visits[g.node] = Visit.of(g);
    g.visited.set(g.node);
    const walk = g.pending;
    const hero = actor.Pool.slot(g.hero);
    const facing = g.facing[hero];
    enter(g, l.node, g.world.?.node[l.node].door[l.door].at);
    g.pending = walk;
    g.facing[hero] = facing;
}

/// The run as it is left: each foe's turn taken, and a door stepped onto gone through, so it is never left on one.
pub fn leave(g: *Game) void {
    for (g.turning, &g.facing) |t, *f| {
        if (t) |u| f.* = u.to;
    }
    g.turning = @splat(null);
    const l = g.travel orelse return;
    goThrough(g, l);
}

fn restart(g: *Game) void {
    if (g.world) |w| beginWorld(g, w) else begin(g, freshSeed());
}

fn spawnHero(g: *Game, at: P) void {
    g.pool = .{};
    g.hero = g.pool.spawn(&g.lv, actor.Actor.of(HERO, at));
    g.facing = @splat(.right);
}

fn reset(g: *Game, hero: P) void {
    spawnHero(g, hero);
    freshRun(g);
    freshTurn(g);
}

fn freshRun(g: *Game) void {
    g.kills = 0;
    g.gold = 0;
    g.log = .{};
    g.mode = .play;
    g.vignette.clear();
}

fn freshTurn(g: *Game) void {
    g.shot = null;
    g.travel = null;
    g.order_n = 0;
    g.busy = 0;
    g.pending = null;
    g.lead = null;
    g.bit = @splat(null);
    g.gassed = @splat(null);
    g.split_from = @splat(null);
    g.turning = @splat(null);
    g.fx.clear();
    g.cloud.clear();
}

fn settle(g: *Game) void {
    castSight(g, g.archer().?.at);
    g.cloud.settle(&g.lv);
    snapGlide(g);
    catchUp(g);
    g.cam = camWant(g);
    g.light.settle(&g.lv);
    g.hour_shown = g.clock.hour();
    g.light.sky = skyNow(g);
    g.light.carrier = carrierAt(g);
}

/// A run read back from a save: its simulation as it was, its picture drawn afresh.
pub fn resumeRun(g: *Game) void {
    g.mode = .play;
    g.exit = null;
    g.unsaved = false;
    g.vignette.clear();
    g.outdoors = if (g.world) |w| w.node[g.node].outdoor() else false;
    freshTurn(g);
    settle(g);
}

pub fn freshSeed() u64 {
    return @bitCast(std.time.milliTimestamp());
}

/// What the archer sees from `from`: as far as its eyes reach, where the sky, a torch or a carried light lets it.
fn castSight(g: *Game, from: P) void {
    var carried: [actor.MAX]lume.Source = undefined;
    var n: usize = 0;
    for (g.pool.slice(), 0..) |a, i| {
        const r = actor.row(a.kind).light;
        if (!a.alive or r <= 0) continue;
        carried[n] = .{ .at = if (actor.Pool.idOf(i) == g.hero) from else a.at, .reach = r };
        n += 1;
    }
    const sight = actor.row(HERO).sight;
    lume.see(&g.lv, from, sight, lume.skyReach(g.outdoors, g.clock.hour(), sight), carried[0..n]);
}

const Move = enum { kick, step, blocked };

fn heroMove(g: *Game, d: mathx.Dir) Move {
    const h = g.archer() orelse return .blocked;
    if (g.lv.taken(h.at.add(d.delta())) and g.lv.passOk(h.at, d)) return .kick;
    return if (g.lv.stepOk(h.at, d, g.hero)) .step else .blocked;
}

fn facingOf(dx: i32) ?Facing {
    return if (dx < 0) .left else if (dx > 0) .right else null;
}

fn turnToward(g: *Game, id: u16, dx: i32) void {
    g.facing[actor.Pool.slot(id)] = facingOf(dx) orelse return;
}

fn turnLater(g: *Game, id: u16, dx: i32) void {
    g.turning[actor.Pool.slot(id)] = .{ .to = facingOf(dx) orelse return };
}

/// `late` seconds ago the walk came due.
fn heroStep(g: *Game, d: mathx.Dir, late: f32) void {
    const h = g.archer() orelse return;
    const to = h.at.add(d.delta());
    switch (heroMove(g, d)) {
        .kick => {
            const w = g.lv.who(to);
            const i = actor.Pool.slot(g.hero);
            g.glide[i] = g.glide[i].bumping(to, late);
            holdUntil(g, g.glide[i].span() - late);
            const s = Stroke{ .from = h.at, .wait = BUMP_LANDS - late };
            if (w != grid.NO_ONE) wound(g, w, g.rng.range(KICK.lo, KICK.hi), KICK.verb, s) else smash(g, to, KICK.verb, s);
            g.lead = s.wait;
        },
        .step => {
            g.pool.move(&g.lv, g.hero, to);
            g.travel = leadsTo(g, to);
        },
        .blocked => return,
    }
    turnToward(g, g.hero, d.delta().x);
    endTurn(g);
}

fn openAim(g: *Game, by: input.Button) void {
    const h = g.archer() orelse return;
    g.mark = bow.pick(&g.lv, &g.pool, h.at) orelse {
        g.log.say("Nothing in range.", .{});
        return;
    };
    turnToward(g, g.hero, g.mark.x - h.at.x);
    g.aim_by = by;
    g.mode = .aim;
}

const Use = struct { act: skillbar.Act, by: input.Button };

/// Since PoE2 0.2.0, pressing the modifier while a button is already held fires that button's secondary skill.
fn usedSkill(g: *Game) ?Use {
    const set = g.bar.active(g.st.down);
    for (skillbar.SLOTS) |b| {
        if (!g.st.hit(b)) continue;
        const a = g.bar.at(.{ .set = set, .button = b }) orelse continue;
        if (a != .secondary) return .{ .act = a, .by = b };
    }
    const m = g.bar.modifier orelse return null;
    if (!g.st.hit(m)) return null;
    for (skillbar.SLOTS) |b| {
        if (b == m or !g.st.held(b)) continue;
        const a = g.bar.at(.{ .set = .secondary, .button = b }) orelse continue;
        if (a != .secondary) return .{ .act = a, .by = b };
    }
    return null;
}

fn useSkill(g: *Game, u: Use) void {
    switch (u.act) {
        .shoot => openAim(g, u.by),
        .wait => endTurn(g),
        .secondary => {},
    }
}

fn closed(st: *const input.State) bool {
    return st.hit(BACK) or st.hit(BINDS);
}

/// What the hud names as cancelling a reticle opened by `by`, which shoots before anything closes it.
fn cancelOf(by: input.Button) input.Button {
    return if (by == BACK) BINDS else BACK;
}

fn openBinds(g: *Game) void {
    g.binds.menu = .browse;
    g.mode = .bind;
}

fn bindStep(g: *Game) void {
    const b = &g.binds;
    const here = b.slot();
    const was = g.bar;
    defer if (!std.meta.eql(was, g.bar)) {
        g.unsaved = true;
    };
    switch (b.menu) {
        .browse => {
            if (closed(&g.st)) {
                g.mode = .play;
            } else if (g.st.hit(CONFIRM)) {
                b.menu = if (g.bar.at(here) != null) .{ .carry = here } else .{ .pick = pickOf(null) };
            } else if (g.st.hit(CHANGE)) {
                b.menu = .{ .pick = pickOf(g.bar.at(here)) };
            } else if (g.st.hit(REMOVE)) {
                g.bar.clear(here);
            } else if (g.st.walk) |d| {
                b.move(d);
            }
        },
        .pick => |i| {
            if (g.st.hit(BACK)) {
                b.menu = .browse;
            } else if (g.st.hit(CONFIRM)) {
                if (pickAct(i)) |a| g.bar.bind(here, a) else g.bar.clear(here);
                b.menu = .browse;
            } else if (g.st.walk) |d| {
                b.menu = .{ .pick = mathx.wrap(i, d.delta().x, PICKS) };
            }
        },
        .carry => |from| {
            if (g.st.hit(BACK)) {
                b.menu = .browse;
            } else if (g.st.hit(CONFIRM)) {
                g.bar.swap(from, here);
                b.menu = .browse;
            } else if (g.st.walk) |d| {
                b.move(d);
            }
        },
    }
}

/// Over the archer's own cell, so the reticle reaches the far side of a corridor.
fn nudgeAim(g: *Game, d: mathx.Dir) void {
    const h = g.archer() orelse return;
    var to = g.mark.add(d.delta());
    if (to.eq(h.at)) to = to.add(d.delta());
    if (!bow.aimable(&g.lv, h.at, to)) return;
    g.mark = to;
    turnToward(g, g.hero, to.x - h.at.x);
}

fn confirmAim(g: *Game) void {
    const h = g.archer() orelse return;
    if (!bow.aimable(&g.lv, h.at, g.mark)) {
        g.log.say("Can't shoot there.", .{});
        return;
    }
    g.mode = .play;
    const to = g.mark;
    const f = bow.fly(&g.lv, h.at, to);
    g.shot = .{ .flight = f, .glyph = look.arrow(to.x - h.at.x, to.y - h.at.y) };
    holdUntil(g, flown(f.len));
    const s = Stroke{ .from = h.at, .wait = flown(f.len -| 1) };
    if (f.struck) |hit| switch (hit) {
        .body => |id| wound(g, id, g.rng.range(bow.DMG_LO, bow.DMG_HI), SHOOT, s),
        .barrel => |p| smash(g, p, SHOOT, s),
    } else g.log.say("{s}'s arrow finds nothing.", .{g.name.text()});
    g.lead = s.wait;
    endTurn(g);
}

const SHOOT = bow.VERB;
const HERO: actor.Kind = .archer;
const KICK = actor.row(HERO).blow.strike;

/// Where a blow came from, and how long until the picture reaches it.
const Stroke = struct { from: P, wait: f32 };

/// On the body in `slot`, or on the barrel at `at` when there is none.
fn strike(g: *Game, slot: ?usize, s: Stroke, at: P, lethal: bool, after: ?fx.After, gold: i32) void {
    const len = mathx.distEuclid(at, s.from);
    const dir: ?[2]f32 = if (len == 0) null else .{ @as(f32, @floatFromInt(at.x - s.from.x)) / len, @as(f32, @floatFromInt(at.y - s.from.y)) / len };
    const kind: ?actor.Kind = if (slot) |i| g.pool.items[i].kind else null;
    g.fx.strike(s.wait, .{ .slot = slot, .at = mathx.centre(at), .dir = dir, .matter = fx.matterOf(kind), .lethal = lethal, .after = after, .gold = gold });
    flashes(g, s.wait);
    const k = kind orelse return;
    if (lethal and k.bursts()) g.cloud.hold(s.wait);
}

fn sting(g: *Game, slot: usize, wait: f32, after: ?fx.After) void {
    g.fx.sting(wait, .{ .slot = slot, .after = after });
    flashes(g, wait);
}

fn snap(g: *Game, slot: usize) fx.Body {
    g.seq += 1;
    return fx.Body.of(g.pool.items[slot], g.seq);
}

fn flashes(g: *Game, wait: f32) void {
    holdUntil(g, wait + fx.FLASH_S);
}

fn holdUntil(g: *Game, t: f32) void {
    g.busy = @max(g.busy, t);
}

fn smash(g: *Game, p: P, comptime verb: []const u8, s: Stroke) void {
    if (!g.lv.breakBarrel(p)) return;
    const gold = g.rng.range(GOLD_LO, GOLD_HI);
    g.gold += gold;
    g.log.say("{s} " ++ verb ++ " the barrel. It breaks: {d} gold.", .{ g.name.text(), gold });
    strike(g, null, s, p, true, null, gold);
}

fn wound(g: *Game, id: u16, dmg: i32, comptime verb: []const u8, s: Stroke) void {
    const a = g.pool.get(id) orelse return;
    const kind = a.kind;
    const at = a.at;
    const i = actor.Pool.slot(id);
    const name = actor.row(kind).name;
    const lethal = hurt(g, id, dmg).lethal;
    g.log.say("{s} " ++ verb ++ " the {s} for {d}.{s}", .{ g.name.text(), name, dmg, if (lethal) " It dies." else "" });
    strike(g, i, s, at, lethal, afterBlow(g, id, lethal), 0);
    if (lethal) fell(g, kind, at);
}

/// The body as a blow left it, a slime it left under half its hp split.
fn afterBlow(g: *Game, id: u16, lethal: bool) fx.After {
    const other = if (lethal) null else split(g, id);
    return .{ .body = snap(g, actor.Pool.slot(id)), .reveals = other };
}

/// The new slime is not drawn until the blow that split it lands; the new slot, if it split.
fn split(g: *Game, id: u16) ?usize {
    const i = actor.Pool.slot(id);
    const name = actor.row(g.pool.items[i].kind).name;
    const other = g.pool.split(&g.lv, id, &g.rng) orelse return null;
    const o = actor.Pool.slot(other);
    const b = g.pool.items[o];
    g.split_from[o] = i;
    g.pictured[o] = fx.Body.of(b, g.seq);
    g.glide[o] = Glide.still(b.at, look.gait(b.kind));
    g.facing[o] = if (g.turning[i]) |t| t.to else g.facing[i];
    if (g.lv.isLit(g.pool.items[i].at)) g.log.say("The {s} splits in two!", .{name});
    return o;
}

fn fell(g: *Game, kind: actor.Kind, at: P) void {
    const name = actor.row(kind).name;
    g.kills += 1;
    if (kind.bursts()) {
        g.lv.addGas(at, gas.BURST);
        if (g.lv.isLit(at)) g.log.say("The {s} bursts, leaving a cloud of caustic gas!", .{name});
    }
    const family = kind.family();
    if (g.pool.tally(family).left == 0) g.log.say("The last {s} is dead.", .{actor.row(family).name});
}

fn heroDies(g: *Game) void {
    g.log.say("{s} dies.", .{g.name.text()});
    g.mode = .dead;
}

/// Brogue's order: the archer acts and the gas eats at it, the gas spreads, then each foe acts and the gas eats at it;
/// then the archer's sight again, for a light a foe carries has moved with it.
fn endTurn(g: *Game) void {
    const h = g.archer() orelse return;
    g.unsaved = true;
    g.clock.turn();
    defer {
        for (g.pool.slice()) |*a| a.waits = false;
    }
    castSight(g, h.at);
    g.flowed = false;
    orderFoes(g, h.at);
    gasHarm(g, g.hero);
    if (g.mode == .dead) return;
    gas.turn(&g.lv, &g.rng);
    for (g.order[0..g.order_n]) |id| {
        foeTurn(g, id);
        if (g.mode == .dead) return;
        gasHarm(g, id);
    }
    if (g.archer()) |a| castSight(g, a.at);
}

const Hurt = struct { dmg: i32, lethal: bool };

/// Every blow or sting on a body: all of `dmg`, but for an unkillable hero, who keeps 1 hp.
fn hurt(g: *Game, id: u16, dmg: i32) Hurt {
    const a = g.pool.get(id) orelse return .{ .dmg = 0, .lethal = false };
    const taken = if (id == g.hero and g.unkillable) std.math.clamp(a.hp - 1, 0, dmg) else dmg;
    return .{ .dmg = taken, .lethal = g.pool.damage(&g.lv, id, taken) };
}

fn gasHarm(g: *Game, id: u16) void {
    const a = g.pool.get(id) orelse return;
    if (!g.lv.gassy(a.at)) return;
    const kind = a.kind;
    const at = a.at;
    const h = hurt(g, id, gas.harm(a.max));
    const lethal = h.lethal;
    g.gassed[actor.Pool.slot(id)] = .{ .kill = lethal, .after = afterBlow(g, id, lethal) };
    if (id == g.hero) {
        g.log.say("The caustic gas eats at {s} for {d}.", .{ g.name.text(), h.dmg });
        if (lethal) heroDies(g);
        return;
    }
    if (!lethal) return;
    if (g.lv.isLit(at)) g.log.say("The {s} dies.", .{actor.row(kind).name});
    fell(g, kind, at);
}

fn orderFoes(g: *Game, from: P) void {
    g.order_n = 0;
    for (g.pool.slice(), 0..) |a, i| {
        const id = actor.Pool.idOf(i);
        if (id == g.hero or !a.alive or a.waits) continue;
        g.order[g.order_n] = id;
        g.order_n += 1;
    }
    const Near = struct {
        pool: *const actor.Pool,
        from: P,
        fn nearer(n: @This(), a: u16, b: u16) bool {
            const sa = actor.Pool.slot(a);
            const sb = actor.Pool.slot(b);
            const da = mathx.dist(n.pool.items[sa].at, n.from);
            const db = mathx.dist(n.pool.items[sb].at, n.from);
            return da < db or (da == db and a < b);
        }
    };
    std.mem.sort(u16, g.order[0..g.order_n], Near{ .pool = &g.pool, .from = from }, Near.nearer);
}

fn foeTurn(g: *Game, id: u16) void {
    const r = g.pool.get(id) orelse return;
    const h = g.archer() orelse return;
    const row = actor.row(r.kind);
    if (!r.awake) {
        if (!fov.sees(&g.lv, r.at, h.at, row.sight)) return;
        r.awake = true;
        turnLater(g, id, h.at.x - r.at.x);
        if (g.lv.isLit(r.at)) g.log.say("A {s} notices {s}.", .{ row.name, g.name.text() });
        return;
    }
    const flitted = if (row.flits and g.rng.chance(actor.FLIT)) actor.flit(&g.lv, r.at, id, g.hero, &g.rng) else null;
    const d = flitted orelse foeWay(g, r.at, id, h.at) orelse return;
    turnLater(g, id, d.delta().x);
    const to = r.at.add(d.delta());
    if (to.eq(h.at)) return reach(g, id, row);
    g.pool.move(&g.lv, id, to);
}

fn foeWay(g: *Game, at: P, id: u16, hero: P) ?mathx.Dir {
    if (mathx.dirTo(at, hero)) |d| {
        if (g.lv.passOk(at, d)) return d;
    }
    if (!g.flowed) {
        _ = grid.distances(&g.lv, hero, &g.flow, &g.queue);
        g.flowed = true;
    }
    return actor.chase(&g.lv, at, id, &g.flow);
}

fn reach(g: *Game, id: u16, row: actor.Row) void {
    const i = actor.Pool.slot(id);
    switch (row.blow) {
        .strike => |s| {
            const h = hurt(g, g.hero, g.rng.range(s.lo, s.hi));
            const lethal = h.lethal;
            g.log.say("The {s} {s} {s} for {d}.", .{ row.name, s.verb, g.name.text(), h.dmg });
            g.bit[i] = .{ .blow = if (lethal) .kill else .hurt, .after = afterBlow(g, g.hero, lethal) };
            if (lethal) heroDies(g);
        },
        .burst => {
            const a = g.pool.get(id).?.*;
            _ = g.pool.damage(&g.lv, id, a.hp);
            g.bit[i] = .{ .blow = .burst, .after = .{ .body = snap(g, i) } };
            fell(g, a.kind, a.at);
        },
    }
}

fn camAxis(centre: f32, view: f32, world: f32) f32 {
    if (view >= world) return (world - view) * 0.5;
    return std.math.clamp(centre - view * 0.5, 0, world - view);
}

/// Dead, a body stands until its killing blow lands, its flash is gone and its last step is drawn; split off, from
/// when the blow that split it lands.
fn standing(g: *Game, i: usize) bool {
    if (g.split_from[i] != null) return false;
    return g.pool.items[i].alive or g.fx.holds(i) or g.glide[i].done() < 1;
}

fn heroSlot(g: *const Game) ?usize {
    return if (g.hero == grid.NO_ONE) null else actor.Pool.slot(g.hero);
}

fn heroGlide(g: *Game) ?Glide {
    const i = heroSlot(g) orelse return null;
    return if (standing(g, i)) g.glide[i] else null;
}

fn heroNow(g: *Game) ?rl.Vector2 {
    return (heroGlide(g) orelse return null).now();
}

/// Where the body is drawn this frame, if it is: only over a cell in sight.
fn drawnAt(g: *Game, i: usize) ?rl.Vector2 {
    if (!standing(g, i)) return null;
    const at = g.glide[i].now();
    return if (g.lv.isLit(cellUnder(at))) at else null;
}

fn camWant(g: *Game) rl.Vector2 {
    const at = (heroGlide(g) orelse return g.cam).ground();
    const half: f32 = @floatFromInt(HALF_CELL);
    return .{
        .x = camAxis(at.x + half, @floatFromInt(g.screen.x), @floatFromInt(grid.W * CELL)),
        .y = camAxis(at.y + half, @floatFromInt(g.viewH()), @floatFromInt(grid.H * CELL)),
    };
}

fn snapGlide(g: *Game) void {
    for (g.pool.slice(), 0..) |a, i| g.glide[i] = Glide.still(a.at, look.gait(a.kind));
}

/// A body that moved this frame starts gliding `late` seconds ago, as of when its step was due; each one in sight
/// after the first a stagger behind the one before, the archer first and then the foes in the order they acted.
fn stepGlide(g: *Game, late: f32) void {
    var next: f32 = if (g.lead) |t| t + late + STAGGER_S else 0;
    const archer_done = stagger(g, g.hero, late, g.lead orelse 0, &next);
    g.lead = null;
    for (g.order[0..g.order_n]) |id| _ = stagger(g, id, late, archer_done, &next);
    for (g.pool.slice(), 0..) |a, i| {
        if (!g.glide[i].to.eq(a.at)) g.glide[i] = g.glide[i].toward(a.at, late);
    }
}

/// The gas's harm on a body with no place lands at `start`, once the archer's part is drawn, which may have burst
/// the bloat it came from. When this body's part is drawn.
fn stagger(g: *Game, id: u16, late: f32, start: f32, next: *f32) f32 {
    const i = actor.Pool.slot(id);
    const a = g.pool.items[i];
    const gl = &g.glide[i];
    const moved = !gl.to.eq(a.at);
    const bit = g.bit[i];
    const gassed = g.gassed[i];
    if (!moved and bit == null and gassed == null) {
        if (g.turning[i]) |*t| {
            if (t.in == null) t.in = start;
        }
        return start;
    }
    g.bit[i] = null;
    g.gassed[i] = null;
    const shown = g.lv.isLit(a.at);
    const placed = if (moved) shown or g.lv.isLit(gl.to) else shown and bit != null;
    const wait = if (placed) next.* else 0;
    if (placed) next.* += STAGGER_S;
    if (g.turning[i]) |*t| t.in = if (placed) wait - late else start;
    const hero = actor.Pool.slot(g.hero);
    const hero_at = g.pool.items[hero].at;
    var lands = if (placed) wait else start;
    if (moved) {
        gl.* = gl.toward(a.at, late - wait);
    } else if (bit != null) {
        gl.* = gl.bumping(hero_at, late - wait);
    }
    if (moved or bit != null) {
        lands = wait + gl.span() - late;
        if (placed) holdUntil(g, lands);
    }
    const hits = wait + BUMP_LANDS - late;
    if (bit) |b| switch (b.blow) {
        .hurt, .kill => strike(g, hero, .{ .from = a.at, .wait = hits }, hero_at, b.blow == .kill, b.after, 0),
        .burst => if (shown) strike(g, i, .{ .from = hero_at, .wait = hits }, a.at, true, b.after, 0),
    };
    const h = gassed orelse return lands;
    if (!shown and !placed) return lands;
    if (h.kill) strike(g, i, .{ .from = a.at, .wait = lands }, a.at, true, h.after, 0) else sting(g, i, lands, h.after);
    return lands;
}

/// The walk that `update` takes this frame, and how long ago it came due.
const Walk = struct { d: mathx.Dir, late: f32 };

/// The last turn is drawn out: its slowest glide, arrow or flash has ended.
pub fn quiet(g: *const Game) bool {
    return g.busy <= PACE_SLACK;
}

/// A walk due while the last turn is still gliding waits for it, the latest one standing in for any before it.
fn paced(g: *Game) ?Walk {
    if (g.st.walk) |d| {
        if (!quiet(g)) {
            g.pending = d;
            return null;
        }
        g.pending = null;
        return .{ .d = d, .late = g.st.late() };
    }
    const d = g.pending orelse return null;
    if (!quiet(g)) return null;
    g.pending = null;
    return .{ .d = d, .late = @max(0, -g.busy) };
}

/// What the last frames set going moves on before this frame deals any more, so a blow dealt now lands `wait` on.
pub fn update(g: *Game, dt: f32) void {
    g.busy -= dt;
    for (g.glide[0..g.pool.n]) |*gl| gl.t += dt;
    g.fx.step(&g.lv, dt);
    g.cloud.step(&g.lv, dt);
    if (g.shot) |*s| {
        s.t += dt;
        if (s.cell() == null) g.shot = null;
    }
    stepTurning(g, dt);
    var late: f32 = 0;
    const over = g.permadeath and g.mode == .dead;
    const pausable = switch (g.mode) {
        .play, .aim, .dead => true,
        .bind, .pause => false,
    };
    if (pausable and !over and g.st.hit(PAUSE)) {
        g.paused_from = g.mode;
        g.pause_menu = .{};
        g.mode = .pause;
        g.pending = null;
    } else switch (g.mode) {
        .play => {
            if (g.travel) |l| {
                if (g.st.walk) |d| g.pending = d;
                if (quiet(g)) goThrough(g, l);
            } else if (g.st.hit(BINDS)) {
                g.pending = null;
                openBinds(g);
            } else if (usedSkill(g)) |u| {
                g.pending = null;
                useSkill(g, u);
            } else if (paced(g)) |w| {
                late = w.late;
                heroStep(g, w.d, w.late);
            }
        },
        .aim => {
            if (g.st.hit(g.aim_by)) {
                confirmAim(g);
            } else if (closed(&g.st)) {
                g.mode = .play;
            } else if (g.st.walk) |d| {
                nudgeAim(g, d);
            }
        },
        .bind => bindStep(g),
        .dead => if (deathShown(g) and g.st.hit(CONFIRM)) {
            if (g.permadeath) g.exit = .back else restart(g);
        },
        .pause => pauseStep(g),
    }
    stepGlide(g, late);
    catchUp(g);
    stepVignette(g, dt);
    const want = camWant(g);
    const k = mathx.easing(dt, CAM_EASE);
    g.cam.x = mathx.lerpF(g.cam.x, want.x, k);
    g.cam.y = mathx.lerpF(g.cam.y, want.y, k);
    g.hour_shown = day.wrapHour(g.hour_shown + day.toward(g.hour_shown, g.clock.hour()) * mathx.easing(dt, HOUR_EASE));
    g.light.sky = skyNow(g);
    g.light.step(&g.lv, dt);
    g.light.carrier = carrierAt(g);
}

/// The sky over the node played, if it is open to one.
fn skyNow(g: *const Game) ?sky.Sky {
    return if (g.outdoors) sky.at(g.hour_shown) else null;
}

/// Per second, how fast the sky drawn catches the hour a turn moved on.
const HOUR_EASE: f32 = 4;

fn pauseStep(g: *Game) void {
    if (menu.backed(&g.st)) {
        g.mode = g.paused_from;
        return;
    }
    const i = g.pause_menu.step(&g.st, PAUSE_ROWS.len) orelse return;
    g.mode = g.paused_from;
    switch (PAUSE_ROWS[i]) {
        .resume_ => {},
        .restart => restart(g),
        .back => g.exit = .back,
        .quit => g.exit = .quit,
    }
}

fn againLabel(g: *const Game) [:0]const u8 {
    return if (g.world != null) "Restart the world" else "New floor";
}

fn pauseLabel(g: *const Game, r: PauseRow) [:0]const u8 {
    return switch (r) {
        .resume_ => "Resume",
        .restart => againLabel(g),
        .back => switch (g.back) {
            .title => "Title",
            .editor => "Back to the editor",
        },
        .quit => "Quit",
    };
}

/// Over the top `h` pixels of the window.
pub fn veil(g: *const Game, h: i32) void {
    rl.drawRectangle(0, 0, g.screen.x, h, look.VEIL);
}

fn drawPause(g: *Game) void {
    veil(g, g.screen.y);
    var rows: [PAUSE_ROWS.len][:0]const u8 = undefined;
    for (PAUSE_ROWS, &rows) |r, *l| l.* = pauseLabel(g, r);
    menu.draw(g.face, g.screen, "PAUSED", &rows, g.pause_menu.at, null, "resume");
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

/// Each body as the latest-dealt blow landed on it left it, or as it is once none is left to land. A slime split off
/// another slides out of it as the blow that split it lands, and not before the one it split off is drawn.
fn catchUp(g: *Game) void {
    for (g.pool.slice(), 0..) |a, i| {
        if (!g.fx.pending(i)) {
            g.pictured[i] = fx.Body.of(a, g.seq);
        } else if (g.fx.landedOn(i)) |b| {
            if (b.seq > g.pictured[i].seq) g.pictured[i] = b;
        }
        const from = g.split_from[i] orelse continue;
        if (g.fx.revealing(i) or g.split_from[from] != null) continue;
        g.split_from[i] = null;
        g.glide[i] = g.glide[from].toward(a.at, 0);
        if (g.lv.isLit(g.pool.items[from].at) or g.lv.isLit(a.at)) holdUntil(g, g.glide[i].span());
    }
}

/// As drawn: a slime split off counts once the blow that split it lands, and a body dies as its killing blow lands.
fn tallyShown(g: *Game, k: actor.Kind) actor.Tally {
    var t = actor.Tally{};
    for (g.pool.slice(), 0..) |a, i| {
        if (a.kind.family() != k or g.split_from[i] != null) continue;
        t.total += 1;
        if (g.pictured[i].hp > 0) t.left += 1;
    }
    return t;
}

fn goldShown(g: *const Game) i32 {
    return g.gold - g.fx.goldDue();
}

fn deathShown(g: *const Game) bool {
    const dead = g.mode == .dead or (g.mode == .pause and g.paused_from == .dead);
    return dead and quiet(g);
}

/// Read off the archer's slot, not `archer()`, so the blow that kills it still reddens the view.
fn stepVignette(g: *Game, dt: f32) void {
    const max = actor.row(HERO).hp;
    const i = heroSlot(g) orelse return g.vignette.step(dt, 0, max, max);
    g.vignette.step(dt, g.fx.flashOf(i), g.pictured[i].hp, g.pictured[i].max);
}

/// The archer's middle as drawn, cells: the carried light glides with the body.
fn carrierAt(g: *Game) ?[2]f32 {
    return middle(heroNow(g) orelse return null);
}

fn middle(v: rl.Vector2) [2]f32 {
    return .{ v.x / CELL_F + 0.5, v.y / CELL_F + 0.5 };
}

/// The cell a body drawn with its corner at `v` stands in.
fn cellUnder(v: rl.Vector2) P {
    return mathx.cellOf(middle(v));
}

fn drawGlyph(g: *Game, ch: u8, sx: i32, sy: i32, col: rl.Color) void {
    g.face.glyph(ch, sx + HALF_CELL, sy + HALF_CELL, GLYPH, col);
}

fn textMid(g: *Game, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    menu.mid(g.face, g.screen, s, y, size, col);
}

const Cam = struct {
    x: i32,
    y: i32,
    at: rl.Vector2,

    fn of(g: *Game) Cam {
        return .{ .x = mathx.roundTiesDown(g.cam.x), .y = mathx.roundTiesDown(g.cam.y), .at = g.cam };
    }

    fn sx(c: Cam, p: P) i32 {
        return p.x * CELL - c.x;
    }

    fn sy(c: Cam, p: P) i32 {
        return p.y * CELL - c.y;
    }

    /// Rounds the offset from the camera once, so a body keeping pace with it holds still on screen.
    fn px(c: Cam, v: rl.Vector2) P {
        return .{ .x = mathx.roundTiesUp(v.x - c.at.x), .y = mathx.roundTiesUp(v.y - c.at.y) };
    }
};

fn spriteRect(t: rl.Texture2D, sx: i32, sy: i32) rl.Rectangle {
    const k = @max(1, @divTrunc(CELL, t.width));
    return .{
        .x = @floatFromInt(sx + @divTrunc(CELL - t.width * k, 2)),
        .y = @floatFromInt(sy + @divTrunc(CELL - t.height * k, 2)),
        .width = @floatFromInt(t.width * k),
        .height = @floatFromInt(t.height * k),
    };
}

fn drawSprite(t: rl.Texture2D, sx: i32, sy: i32) void {
    look.stretch(t, spriteRect(t, sx, sy), look.LIT);
}

fn outline(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangleLinesEx(.{
        .x = @floatFromInt(c.sx(p) + OUTLINE_INSET),
        .y = @floatFromInt(c.sy(p) + OUTLINE_INSET),
        .width = @floatFromInt(CELL - OUTLINE_INSET * 2),
        .height = @floatFromInt(CELL - OUTLINE_INSET * 2),
    }, @floatFromInt(LINE_W), col);
}

fn fillCell(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangle(c.sx(p), c.sy(p), CELL, CELL, col);
}

/// Remembered like terrain: nothing but the archer breaks one, and only in sight, as the blow lands.
fn barrelShownAt(g: *Game, p: P) bool {
    return g.lv.isSeen(p) and (g.lv.hasBarrel(p) or g.fx.breaking(p));
}

fn standsShownAt(g: *Game, p: P) bool {
    return shownAt(g, p, null);
}

fn shownAt(g: *Game, p: P, skip: ?usize) bool {
    for (0..g.pool.n) |i| {
        if (i == skip) continue;
        const at = drawnAt(g, i) orelse continue;
        if (cellUnder(at).eq(p)) return true;
    }
    return barrelShownAt(g, p);
}

fn bar(x: i32, y: i32, w: i32, h: i32, hp: i32, max: i32, back: rl.Color) void {
    rl.drawRectangle(x, y, w, h, back);
    rl.drawRectangle(x, y, @divTrunc(w * @max(0, hp), max), h, look.LIFE);
}

const Shown = struct {
    pic: fx.Body,
    slot: usize,
    s: P,
    mid: [2]f32,
    left: bool,
    shine: light.Shine,
};

const Prop = struct {
    s: P,
    mid: [2]f32,
    shine: light.Shine,
};

const Barrels = struct {
    g: *Game,
    c: Cam,
    cells: grid.Cells,

    fn of(g: *Game, c: Cam, lo: P, hi: P) Barrels {
        return .{ .g = g, .c = c, .cells = grid.Cells.of(lo, hi) };
    }

    fn next(self: *Barrels) ?Prop {
        while (self.cells.next()) |p| {
            if (!barrelShownAt(self.g, p)) continue;
            const mid = mathx.centre(p);
            return .{ .s = .{ .x = self.c.sx(p), .y = self.c.sy(p) }, .mid = mid, .shine = self.g.light.onBody(mid, false) };
        }
        return null;
    }
};

fn drawFigure(g: *Game, tex: ?rl.Texture2D, l: look.Look, s: P, left: bool, mid: [2]f32, shine: light.Shine, flash: f32) void {
    if (tex) |t| {
        g.light.drawBody(t, spriteRect(t, s.x, s.y), left, mid, shine, flash);
    } else drawGlyph(g, l.ch, s.x, s.y, shine.drawn(l.fg, flash));
}

/// The open ground and what lies under anything solid, then the solid, which covers the shadows cast between.
const Pass = enum { ground, solid };

/// At full light, over the seen cells from `lo` up to `hi`.
fn drawTerrain(g: *Game, c: Cam, lo: P, hi: P, pass: Pass, arrow_at: ?P) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        if (!g.lv.isSeen(p)) continue;
        const here = g.lv.at(p);
        const kind = switch (pass) {
            .ground => if (here.solid()) here.ground() orelse continue else here,
            .solid => if (here.solid()) here else continue,
        };
        defer if (g.lv.doorAt(p) != null) drawGlyph(g, look.DOOR.ch, c.sx(p), c.sy(p), look.DOOR.fg);
        if (g.sprites.tileOf(kind, g.lv.wallShape(p))) |t| {
            drawSprite(t, c.sx(p), c.sy(p));
            continue;
        }
        if (look.tileBg(kind)) |bg| fillCell(c, p, bg);
        if (kind != here or standsShownAt(g, p)) continue;
        if (arrow_at) |a| {
            if (a.eq(p)) continue;
        }
        const l = look.tile(kind);
        g.face.symbol(look.tileSym(kind), l.ch, c.sx(p) + HALF_CELL, c.sy(p) + HALF_CELL, GLYPH, l.fg);
    }
}

fn drawWorld(g: *Game) void {
    const c = Cam.of(g);
    const lo = P{ .x = @max(0, @divFloor(c.x, CELL)), .y = @max(0, @divFloor(c.y, CELL)) };
    const hi = P{
        .x = @min(grid.W, @divFloor(c.x + g.screen.x, CELL) + 1),
        .y = @min(grid.H, @divFloor(c.y + g.viewH(), CELL) + 1),
    };
    const arrow_at: ?P = if (g.shot) |s| s.cell() else null;
    const aim_from: ?P = if (g.mode != .aim) null else if (g.archer()) |a| a.at else null;

    var shown: [actor.MAX]Shown = undefined;
    var n: usize = 0;
    for (0..g.pool.n) |i| {
        const at = drawnAt(g, i) orelse continue;
        const mid = middle(at);
        shown[n] = .{
            .pic = g.pictured[i],
            .slot = i,
            .s = c.px(at),
            .mid = mid,
            .left = g.facing[i] == .left,
            .shine = g.light.onBody(mid, actor.Pool.idOf(i) == g.hero),
        };
        n += 1;
    }
    const bodies = shown[0..n];

    drawTerrain(g, c, lo, hi, .ground, arrow_at);
    const cast = grid.grown(lo, hi, CAST_MARGIN);
    if (g.sprites.barrel) |t| {
        var barrels = Barrels.of(g, c, cast[0], cast[1]);
        while (barrels.next()) |b| g.light.drawShadows(t, spriteRect(t, b.s.x, b.s.y), false, b.mid, b.shine);
    }
    var props = grid.Cells.of(cast[0], cast[1]);
    while (props.next()) |p| {
        const kind = g.lv.at(p);
        if (!look.stands(kind) or !g.lv.isSeen(p)) continue;
        const t = g.sprites.tileOf(kind, null) orelse continue;
        const mid = mathx.centre(p);
        const shine = g.light.onBody(mid, false);
        const rect = spriteRect(t, c.sx(p), c.sy(p));
        if (look.canopied(kind)) g.light.drawCanopy(t, rect, mid, shine) else g.light.drawShadows(t, rect, false, mid, shine);
    }
    for (bodies) |b| {
        const t = g.sprites.body(b.pic.kind) orelse continue;
        g.light.drawShadows(t, spriteRect(t, b.s.x, b.s.y), b.left, b.mid, b.shine);
    }
    g.cloud.draw(&g.lv, lo, hi, -c.x, -c.y, CELL);
    drawTerrain(g, c, lo, hi, .solid, arrow_at);
    g.fx.draw(@floatFromInt(-c.x), @floatFromInt(-c.y), CELL_F);
    g.light.bake(&g.lv, lo, hi);
    g.light.drawMap(-c.x, -c.y, CELL);

    if (aim_from) |from| {
        var cells = grid.Cells.of(lo, hi);
        while (cells.next()) |p| {
            if (bow.aimable(&g.lv, from, p)) fillCell(c, p, look.AIM_REACH);
        }
        const f = bow.fly(&g.lv, from, g.mark);
        for (f.path[0..f.len]) |p| fillCell(c, p, look.AIM_PATH);
    }

    var barrels = Barrels.of(g, c, lo, hi);
    while (barrels.next()) |b| drawFigure(g, g.sprites.barrel, look.BARREL, b.s, false, b.mid, b.shine, 0);
    for (bodies) |b| {
        const at = P{ .x = b.s.x, .y = b.s.y - g.glide[b.slot].lift() };
        drawFigure(g, g.sprites.body(b.pic.kind), look.body(b.pic.kind), at, b.left, b.mid, b.shine, g.fx.flashOf(b.slot));
    }

    drawTorches(g, c);

    for (bodies) |b| {
        if (!b.pic.kind.foe() or !b.pic.hurt()) continue;
        const y_bar = b.s.y + CELL - BODY_BAR_H - BODY_BAR_LIFT;
        bar(b.s.x + BODY_BAR_INSET, y_bar, CELL - BODY_BAR_INSET * 2, BODY_BAR_H, b.pic.hp, b.pic.max, look.BG);
    }

    if (g.mode == .aim) outline(c, g.mark, look.RETICLE);
    if (g.mode == .play and g.st.lean) drawLean(g, c);

    if (g.shot) |s| {
        if (s.cell()) |p| drawGlyph(g, s.glyph, c.sx(p), c.sy(p), look.ARROW);
    }
}

/// Over the light map, so each flame is its own light; a remembered one stays drawn, dim and unlit.
fn drawTorches(g: *Game, c: Cam) void {
    var buf: [grid.MAX_TORCHES]light.Flame = undefined;
    const flames = g.light.flames(&g.lv, &buf);
    for (flames) |f| {
        const x = mathx.roundTiesUp(f.at[0] * CELL_F) - c.x;
        const y = mathx.roundTiesUp(f.at[1] * CELL_F) - c.y;
        g.face.glyph(look.TORCH.ch, x, y, TORCH_GLYPH, look.fade(look.TORCH_DIM, f.memory));
        g.face.glyph(look.TORCH.ch, x, y, TORCH_GLYPH, look.fade(look.TORCH.fg, f.lit * @min(1, f.glow)));
    }
    g.light.drawGlows(flames, @floatFromInt(-c.x), @floatFromInt(-c.y), CELL_F);
}

/// `heroMove` as drawn: a body or barrel shown there is kicked, whatever the simulation already did to it.
fn leanShown(g: *Game, from: P, d: mathx.Dir) Move {
    if (!g.lv.passOk(from, d)) return .blocked;
    return if (shownAt(g, from.add(d.delta()), heroSlot(g))) .kick else .step;
}

fn drawLean(g: *Game, c: Cam) void {
    const h = g.archer() orelse return;
    for (input.DPAD) |button| {
        const d = input.leanOf(button);
        const p = h.at.add(d.delta());
        const col = switch (leanShown(g, h.at, d)) {
            .kick => look.LEAN_FOE,
            .step => look.LEAN_OPEN,
            .blocked => look.LEAN_BLOCKED,
        };
        outline(c, p, col);
        const ch = look.caret(button);
        if (g.lv.walkable(p) and !standsShownAt(g, p)) {
            drawGlyph(g, ch, c.sx(p), c.sy(p), col);
            continue;
        }
        const s = [_:0]u8{ch};
        const dx: i32 = if (d.delta().x > 0) CELL - g.face.width(&s, CARET) - CARET_PAD_X else CARET_PAD_X;
        const dy: i32 = if (d.delta().y > 0) CELL - CARET - CARET_PAD_Y else CARET_PAD_Y;
        g.face.text(&s, c.sx(p) + dx, c.sy(p) + dy, CARET, col);
    }
}

/// The seen cells, a texel each, drawn `MINI` times over in one quad. Needs a live GL context.
const Minimap = struct {
    tex: ?rl.Texture2D = null,
    px: [grid.CELLS]rl.Color = undefined,

    fn load(m: *Minimap) void {
        m.tex = look.canvas(grid.W, grid.H, rl.Color.blank);
        if (m.tex) |t| rl.setTextureFilter(t, .point);
    }

    fn unload(m: *Minimap) void {
        if (m.tex) |t| rl.unloadTexture(t);
        m.tex = null;
    }
};

fn miniOrigin(screen_w: i32) P {
    return .{ .x = screen_w - MINI_W - MINI_PAD, .y = MINI_PAD };
}

fn miniDot(o: P, p: P, grow: i32, col: rl.Color) void {
    rl.drawRectangle(o.x + p.x * MINI - grow, o.y + p.y * MINI - grow, MINI + grow * 2, MINI + grow * 2, col);
}

fn drawMinimap(g: *Game) void {
    const o = miniOrigin(g.screen.x);
    const f = MINI_FRAME;
    const fw = MINI_W + f * 2;
    const fh = MINI_H + f * 2;
    rl.drawRectangle(o.x - f, o.y - f, fw, fh, look.MINI_BG);
    rl.drawRectangleLines(o.x - f, o.y - f, fw, fh, look.EDGE);
    if (g.mini.tex) |t| {
        for (&g.mini.px, g.lv.tile, g.lv.seen, g.lv.lit) |*c, tile, seen, lit| c.* = if (seen) look.mini(tile, lit) else rl.Color.blank;
        rl.updateTexture(t, &g.mini.px);
        look.stretch(t, .{ .x = @floatFromInt(o.x), .y = @floatFromInt(o.y), .width = @floatFromInt(MINI_W), .height = @floatFromInt(MINI_H) }, rl.Color.white);
    }
    for (g.pool.slice(), 0..) |a, i| {
        if (!a.foe()) continue;
        const at = drawnAt(g, i) orelse continue;
        miniDot(o, cellUnder(at), 0, look.MINI_FOE);
    }
    if (heroNow(g)) |at| miniDot(o, cellUnder(at), MINI_HERO_GROW, look.MINI_HERO);
    const c = Cam.of(g);
    rl.drawRectangleLines(o.x + toMini(c.x), o.y + toMini(c.y), toMini(g.screen.x), toMini(g.viewH()), look.MINI_VIEW);
}

fn toMini(px: i32) i32 {
    return @divTrunc(px * MINI, CELL);
}

fn bindRowY(y0: i32, row: usize) i32 {
    return y0 + BIND_ROWS_DY + @as(i32, @intCast(row)) * BIND_ROW_H;
}

const SEP = menu.SEP;
const HINT_PLAY = input.LEAN_CAPTION ++ "+" ++ input.MOVE_CAPTION ++ " diagonal" ++ SEP ++ BINDS.caption() ++ " bind skills" ++ SEP ++ PAUSE.caption() ++ " pause";
const HINT_AIM = "{s} shoot" ++ SEP ++ "{s} cancel" ++ SEP ++ input.MOVE_CAPTION ++ " aim";
const LEGEND_EMPTY = CONFIRM.caption() ++ " select skill" ++ SEP ++ CHANGE.caption() ++ " select skill" ++ SEP ++ BACK.caption() ++ " close";
const LEGEND_BOUND = CONFIRM.caption() ++ " pick up" ++ SEP ++ CHANGE.caption() ++ " change skill" ++ SEP ++ REMOVE.caption() ++ " remove" ++ SEP ++ BACK.caption() ++ " close";
const LEGEND_CARRY = CONFIRM.caption() ++ " put down" ++ SEP ++ BACK.caption() ++ " cancel";
const LEGEND_PICK = CONFIRM.caption() ++ " bind" ++ SEP ++ BACK.caption() ++ " back";

fn skillsX(g: *Game) i32 {
    return @divTrunc(g.screen.x - SKILLS_W, 2);
}

const SlotLook = struct { act: ?skillbar.Act, key: ?input.Button, edge: rl.Color, faded: bool = false };

fn drawSlot(g: *Game, x: i32, y: i32, s: SlotLook) void {
    const a: f32 = if (s.faded) CARRIED_A else 1;
    rl.drawRectangle(x, y, SLOT_PX, SLOT_PX, look.fade(if (s.act == null) look.SLOT_EMPTY else look.SLOT_BG, a));
    rl.drawRectangleLinesEx(.{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(SLOT_PX),
        .height = @floatFromInt(SLOT_PX),
    }, @floatFromInt(LINE_W), look.fade(s.edge, a));
    if (s.act) |act| {
        const l = look.skill(act);
        g.face.glyph(l.ch, x + SLOT_MID, y + SLOT_MID, SLOT_GLYPH, look.fade(l.fg, a));
    }
    const k = (s.key orelse return).caption();
    g.face.draw(k, g.face.leftFor(k, x + SLOT_MID, SLOT_TEXT), y + SLOT_PX + KEY_GAP, SLOT_TEXT, look.fade(look.DIM, a));
}

fn drawSkills(g: *Game, top: i32) void {
    const set = g.bar.active(g.st.down);
    const x0 = skillsX(g);
    for (skillbar.SLOTS, SLOT_XS) |b, dx| {
        const held = g.st.held(b) and g.mode == .play;
        drawSlot(g, x0 + dx, top + SKILLS_Y, .{
            .act = g.bar.at(.{ .set = set, .button = b }),
            .key = b,
            .edge = if (held) look.SLOT_HELD else look.EDGE,
        });
    }
}

fn drawBinds(g: *Game) void {
    var buf: [LINE_BUF]u8 = undefined;
    const b = g.binds;
    const x0 = skillsX(g);
    const y0 = @divTrunc(g.viewH(), 2) + BIND_TOP_DY;
    veil(g, g.viewH());
    textMid(g, "BIND SKILLS", y0, BIND_TITLE, look.TEXT);
    var cursor = P{ .x = 0, .y = 0 };
    for (skillbar.SETS, 0..) |set, row| {
        const ry = bindRowY(y0, row);
        g.face.text(set.name(), x0, ry, TEXT, look.DIM);
        const sy = ry + TEXT + BIND_LABEL_GAP;
        for (skillbar.SLOTS, SLOT_XS, 0..) |key, dx, i| {
            const here = row == b.row and i == b.col;
            const carried = switch (b.menu) {
                .carry => |from| from.set == set and from.button == key,
                .browse, .pick => false,
            };
            if (here) cursor = .{ .x = x0 + dx, .y = sy };
            drawSlot(g, x0 + dx, sy, .{
                .act = g.bar.at(.{ .set = set, .button = key }),
                .key = key,
                .edge = if (here) look.SLOT_CURSOR else look.EDGE,
                .faded = carried,
            });
        }
    }
    const info_y = bindRowY(y0, skillbar.SETS.len) + BIND_INFO_DY;
    const pop_y = cursor.y - SLOT_PX - BIND_POP_DY;
    var shown: ?skillbar.Act = g.bar.at(b.slot());
    var legend: [:0]const u8 = if (shown == null) LEGEND_EMPTY else LEGEND_BOUND;
    switch (b.menu) {
        .browse => {},
        .carry => |from| {
            shown = g.bar.at(from);
            legend = LEGEND_CARRY;
            if (shown) |a| drawSlot(g, cursor.x, pop_y, .{ .act = a, .key = from.button, .edge = look.SLOT_CURSOR });
        },
        .pick => |pick| {
            legend = LEGEND_PICK;
            shown = pickAct(pick);
            const w = @as(i32, @intCast(PICKS)) * SLOT_STEP - SLOT_GAP;
            const px = cursor.x + @divTrunc(SLOT_PX - w, 2);
            for (0..PICKS) |i| {
                const x = px + @as(i32, @intCast(i)) * SLOT_STEP;
                const act = pickAct(i);
                const edge = if (i == pick) look.SLOT_CURSOR else if (act == null) look.SLOT_CLEAR else look.EDGE;
                drawSlot(g, x, pop_y, .{ .act = act, .key = null, .edge = edge });
                if (act == null) g.face.glyph(look.CLEAR.ch, x + SLOT_MID, pop_y + SLOT_MID, CLEAR_GLYPH, look.CLEAR.fg);
            }
        },
    }
    if (shown) |a| {
        textMid(g, a.name(), info_y, TEXT, look.TEXT);
        textMid(g, a.desc(), info_y + TEXT_LINE, TEXT, look.DIM);
    } else if (b.menu == .pick) {
        textMid(g, "Clear slot", info_y, TEXT, look.TEXT);
    }
    const hold = if (g.bar.modifier) |m| std.fmt.bufPrintZ(&buf, "Hold {s} for the Secondary Skill Set", .{m.caption()}) catch "" else "No button holds the Secondary Skill Set";
    textMid(g, hold, info_y + TEXT_LINE * 2, TEXT, look.DIM);
    textMid(g, legend, info_y + TEXT_LINE * 4, TEXT, look.DIM);
}

fn drawHud(g: *Game) void {
    const top = g.viewH();
    rl.drawRectangle(0, top, g.screen.x, HUD_H, look.BG);
    rl.drawRectangle(0, top, g.screen.x, HUD_EDGE, look.EDGE);

    var buf: [LINE_BUF]u8 = undefined;
    const shown: ?fx.Body = if (heroSlot(g)) |i| g.pictured[i] else null;
    const max = if (shown) |h| h.max else actor.row(HERO).hp;
    const hp = if (shown) |h| h.hp else 0;
    const bar_y = top + BAR_Y;
    bar(HUD_PAD, bar_y, BAR_W, BAR_H, hp, max, look.LIFE_BG);
    g.face.text(std.fmt.bufPrintZ(&buf, "{s}  HP {d}/{d}", .{ g.name.text(), @max(0, hp), max }) catch "", HUD_PAD + BAR_TEXT_X, bar_y + @divTrunc(BAR_H - TEXT, 2), TEXT, look.TEXT);
    var tally_x = HUD_PAD;
    for (actor.FOES) |k| {
        const t = tallyShown(g, k);
        const name = actor.row(k).name;
        const s = std.fmt.bufPrintZ(&buf, "{c}{s}s {d}/{d}", .{ std.ascii.toUpper(name[0]), name[1..], t.left, t.total }) catch "";
        g.face.text(s, tally_x, top + TALLY_Y, TEXT, look.DIM);
        tally_x += g.face.width(s, TEXT) + TALLY_GAP;
    }
    g.face.text(std.fmt.bufPrintZ(&buf, "Gold {d}", .{goldShown(g)}) catch "", tally_x, top + TALLY_Y, TEXT, look.COIN);
    const hint: [:0]const u8 = if (g.mode == .aim)
        std.fmt.bufPrintZ(&buf, HINT_AIM, .{ g.aim_by.caption(), cancelOf(g.aim_by).caption() }) catch ""
    else
        HINT_PLAY;
    g.face.text(hint, HUD_PAD, top + HINT_Y, TEXT, look.DIM);
    drawSkills(g, top);

    const log_x = skillsX(g) + SKILLS_W + HUD_PAD * 2;
    for (0..Log.SHOWN) |row| {
        const back = Log.SHOWN - 1 - row;
        const l = g.log.line(back) orelse continue;
        const a = 1.0 - @as(f32, @floatFromInt(back)) * LOG_FADE;
        g.face.text(l, log_x, top + LOG_Y + @as(i32, @intCast(row)) * TEXT_LINE, TEXT, look.fade(look.TEXT, a));
    }
}

fn drawDead(g: *Game) void {
    var buf: [LINE_BUF]u8 = undefined;
    const mid = @divTrunc(g.viewH(), 2);
    veil(g, g.viewH());
    const DIED = " DIED";
    var died: [heroes.Name.MAX + DIED.len + 1]u8 = undefined;
    const said = std.fmt.bufPrintZ(&died, "{s}" ++ DIED, .{g.name.text()}) catch "";
    _ = std.ascii.upperString(died[0..said.len], said);
    textMid(g, said, mid + DEAD_TITLE_DY, menu.TITLE, look.LIFE);
    textMid(g, std.fmt.bufPrintZ(&buf, "{d} foes killed. Seed {d}.", .{ g.kills, g.seed }) catch "", mid + DEAD_SCORE_DY, TEXT, look.TEXT);
    const again = if (g.permadeath) pauseLabel(g, .back) else againLabel(g);
    textMid(g, std.fmt.bufPrintZ(&buf, "{s}  {c}{s}", .{ CONFIRM.caption(), std.ascii.toLower(again[0]), again[1..] }) catch "", mid + DEAD_HINT_DY, TEXT, look.DIM);
}

pub fn drawFrame(g: *Game) void {
    rl.clearBackground(look.BG);
    drawWorld(g);
    g.vignette.draw(g.screen.x, g.viewH());
    drawMinimap(g);
    drawHud(g);
    if (g.mode == .bind) drawBinds(g);
    if (deathShown(g)) drawDead(g);
    if (g.mode == .pause) drawPause(g);
}

pub fn withGame(flags: rl.ConfigFlags, title: [:0]const u8, comptime body: fn (*Game) void) void {
    const alloc = std.heap.c_allocator;
    rl.setConfigFlags(flags);
    rl.initWindow(WINDOW_W, WINDOW_H, title);
    defer rl.closeWindow();
    input.claimKeys();
    const g = boot(alloc) catch |e| {
        std.debug.print("boot FAILED ({s})\n", .{@errorName(e)});
        return;
    };
    defer shut(alloc, g);
    g.sprites = look.Sprites.load();
    defer g.sprites.unload();
    g.face = font.Face.load(look.TILE_CODEPOINTS);
    defer g.face.unload();
    const figures = g.sprites.figures();
    g.light.load(&figures);
    defer g.light.unload();
    g.cloud.load();
    defer g.cloud.unload();
    g.vignette.load();
    defer g.vignette.unload();
    g.mini.load();
    defer g.mini.unload();
    body(g);
}

pub fn fullscreen() bool {
    return rl.isWindowState(.{ .borderless_windowed_mode = true });
}

pub fn syncScreen(g: *Game, toggle: bool) void {
    if (toggle) rl.toggleBorderlessWindowed();
    g.screen = .{ .x = rl.getScreenWidth(), .y = rl.getScreenHeight() };
}

pub fn frame(g: *Game) void {
    const dt = rl.getFrameTime();
    g.st.update(dt);
    syncScreen(g, g.st.fullscreen);
    update(g, dt);
    rl.beginDrawing();
    drawFrame(g);
    rl.endDrawing();
}

/// DEV ONLY. A render texture, not `takeScreenshot`: the batch is only guaranteed flushed at `endTextureMode`,
/// and the target is upside down.
pub fn shot() void {
    withGame(.{ .window_hidden = true }, "roguelike --shot", shoot);
}

fn renderTarget(g: *Game) ?rl.RenderTexture2D {
    return rl.loadRenderTexture(g.screen.x, g.screen.y) catch {
        std.debug.print("render texture FAILED\n", .{});
        return null;
    };
}

fn shoot(g: *Game) void {
    const target = renderTarget(g) orelse return;
    defer rl.unloadRenderTexture(target);
    std.fs.cwd().makePath(SHOTS_DIR) catch {};

    begin(g, SHOT_SEED);
    poseRat(g);
    g.st.lean = true;
    capture(g, target, SHOTS_DIR ++ "/lean.png");

    g.st.lean = false;
    openAim(g, .x);
    capture(g, target, SHOTS_DIR ++ "/aim.png");

    g.mode = .play;
    poseTorch(g);
    capture(g, target, SHOTS_DIR ++ "/torch.png");

    openBinds(g);
    g.binds.col = Binds.colOf(.x);
    g.binds.menu = .{ .pick = pickOf(g.bar.at(g.binds.slot())) };
    capture(g, target, SHOTS_DIR ++ "/bind.png");

    poseGas(g);
    capture(g, target, SHOTS_DIR ++ "/gas.png");

    g.paused_from = g.mode;
    g.mode = .pause;
    capture(g, target, SHOTS_DIR ++ "/pause.png");
    g.mode = g.paused_from;

    if (std.heap.c_allocator.create(atlas.Atlas)) |w| {
        defer std.heap.c_allocator.destroy(w);
        overviews(g, w);
        if (w.load(std.heap.c_allocator, atlas.worldPath(SHOT_BIOME))) {
            beginWorldAt(g, w, w.start, SHOT_SEED);
            capture(g, target, SHOTS_DIR ++ "/biome.png");
        } else |e| std.debug.print("biome shot: {s} did not load ({s})\n", .{ SHOT_BIOME, @errorName(e) });
        if (w.load(std.heap.c_allocator, atlas.worldPath(SHOT_OUTDOOR))) {
            for (SHOT_HOURS) |s| {
                beginWorldAt(g, w, w.start, SHOT_SEED);
                g.lv.seen = @splat(false);
                g.clock = day.Clock.at(s.hour);
                settle(g);
                capture(g, target, s.path);
            }
        } else |e| std.debug.print("sky shots: {s} did not load ({s})\n", .{ SHOT_OUTDOOR, @errorName(e) });
        begin(g, SHOT_SEED);
    } else |_| {}

    editor.shoot(g, target, SHOTS_DIR ++ "/edit.png", SHOTS_DIR ++ "/edit-graph.png", SHOTS_DIR ++ "/edit-gen.png");

    const entry = naming.Entry{ .name = heroes.Name.of("Arwen"), .row = 2, .col = 4 };
    rl.beginTextureMode(target);
    rl.clearBackground(look.BG);
    var title: [naming.TITLE_MAX]u8 = undefined;
    naming.draw(&entry, g.face, g.screen, naming.titleOf(.archer, &title));
    rl.endTextureMode();
    exportTarget(target, SHOTS_DIR ++ "/name.png");
}

const POSE_BURST = P{ .x = 25, .y = 15 };
const POSE_GAS_TURNS: usize = 3;

fn poseGas(g: *Game) void {
    arena(g, .{ .x = 18, .y = 16 }, &.{});
    g.outdoors = false;
    var x: i32 = 13;
    while (x <= 31) : (x += 1) {
        g.lv.set(.{ .x = x, .y = 10 }, .wall);
        g.lv.set(.{ .x = x, .y = 21 }, .wall);
    }
    var y: i32 = 10;
    while (y <= 21) : (y += 1) {
        g.lv.set(.{ .x = 13, .y = y }, .wall);
        if (y != POSE_BURST.y) g.lv.set(.{ .x = 31, .y = y }, .wall);
    }
    gen.shapeWalls(&g.lv);
    g.lv.addTorch(.{ .x = 22, .y = 10 });
    _ = g.pool.spawn(&g.lv, actor.Actor.of(.bloat, .{ .x = 16, .y = 12 }));
    g.lv.addGas(POSE_BURST, gas.BURST);
    for (0..POSE_GAS_TURNS) |_| gas.turn(&g.lv, &g.rng);
    settle(g);
}

const POSE_TORCH = P{ .x = 20, .y = 10 };

fn poseTorch(g: *Game) void {
    arena(g, .{ .x = 20, .y = 15 }, &.{ .{ .x = 17, .y = 12 }, .{ .x = 23, .y = 13 } });
    g.outdoors = false;
    var x: i32 = 12;
    while (x < 29) : (x += 1) g.lv.set(.{ .x = x, .y = POSE_TORCH.y }, .wall);
    g.lv.set(.{ .x = 22, .y = 12 }, .wall);
    gen.shapeWalls(&g.lv);
    g.lv.addTorch(POSE_TORCH);
    settle(g);
}

fn drawInto(g: *Game, target: rl.RenderTexture2D) void {
    rl.beginTextureMode(target);
    drawFrame(g);
    rl.endTextureMode();
}

const OVERVIEW_CELL: i32 = 10;
const OVERVIEW_MID: i32 = @divTrunc(OVERVIEW_CELL, 2);
/// A glyph a little bigger than its cell, so the font's side bearings leave no gaps.
const OVERVIEW_INK: i32 = OVERVIEW_CELL + 2;
/// The world `shots/biome.png` plays, from `atlas.DIR`.
const SHOT_BIOME = "qud_salt_marsh";
/// The world the sky is shot over, at each of these hours.
const SHOT_OUTDOOR = "wilds";
const SHOT_HOURS = [_]struct { hour: f32, path: [:0]const u8 }{
    .{ .hour = 7.0, .path = SHOTS_DIR ++ "/dawn.png" },
    .{ .hour = 12.0, .path = SHOTS_DIR ++ "/noon.png" },
    .{ .hour = 16.5, .path = SHOTS_DIR ++ "/day.png" },
    .{ .hour = 19.3, .path = SHOTS_DIR ++ "/dusk.png" },
    .{ .hour = 1.0, .path = SHOTS_DIR ++ "/night.png" },
};

/// DEV ONLY. Each world's start node rolled and drawn whole, a glyph a cell, into `shots/worlds/<name>.png`.
fn overviews(g: *Game, w: *atlas.Atlas) void {
    const target = rl.loadRenderTexture(grid.W * OVERVIEW_CELL, grid.H * OVERVIEW_CELL) catch return;
    defer rl.unloadRenderTexture(target);
    std.fs.cwd().makePath(SHOTS_DIR ++ "/worlds") catch {};
    var list = atlas.Listing{};
    list.scan();
    for (0..list.n) |i| {
        w.load(std.heap.c_allocator, list.at(i)) catch continue;
        w.node[w.start.node].stamp(&g.lv, SHOT_SEED +% i);
        rl.beginTextureMode(target);
        rl.clearBackground(look.BG);
        for (0..grid.CELLS) |k| {
            const p = grid.Level.of(k);
            const t = g.lv.tile[k];
            const x = p.x * OVERVIEW_CELL;
            const y = p.y * OVERVIEW_CELL;
            const under = t.ground() orelse t;
            if (look.tileBg(under)) |bg| rl.drawRectangle(x, y, OVERVIEW_CELL, OVERVIEW_CELL, bg);
            const l = look.tile(t);
            const cx = x + OVERVIEW_MID;
            const cy = y + OVERVIEW_MID;
            if (g.lv.barrel[k]) {
                g.face.glyph(look.BARREL.ch, cx, cy, OVERVIEW_INK, look.BARREL.fg);
            } else if (g.lv.door[k] != grid.NO_DOOR) {
                g.face.glyph(look.DOOR.ch, cx, cy, OVERVIEW_INK, look.DOOR.fg);
            } else g.face.symbol(look.tileSym(t), l.ch, cx, cy, OVERVIEW_INK, l.fg);
        }
        for (g.lv.torches()) |t| g.face.glyph(look.TORCH.ch, t.x * OVERVIEW_CELL + OVERVIEW_MID, t.y * OVERVIEW_CELL + OVERVIEW_MID, OVERVIEW_INK, look.TORCH.fg);
        rl.endTextureMode();
        var buf: [atlas.PATH_MAX + 32]u8 = undefined;
        const name = std.fmt.bufPrintZ(&buf, SHOTS_DIR ++ "/worlds/{s}.png", .{list.stem(i)}) catch continue;
        exportTarget(target, name);
    }
}

fn capture(g: *Game, target: rl.RenderTexture2D, path: [:0]const u8) void {
    drawInto(g, target);
    exportTarget(target, path);
}

pub fn exportTarget(target: rl.RenderTexture2D, path: [:0]const u8) void {
    var img = rl.loadImageFromTexture(target.texture) catch {
        std.debug.print("{s} FAILED\n", .{path});
        return;
    };
    defer rl.unloadImage(img);
    rl.imageFlipVertical(&img);
    // Blending leaves alpha in the target that a window never shows.
    rl.imageFormat(&img, .uncompressed_r8g8b8);
    std.debug.print("{s} {s}\n", .{ path, if (rl.exportImage(img, path)) "written" else "FAILED" });
}

pub fn bench() void {
    withGame(.{ .window_hidden = true }, "roguelike --bench", benchWalk);
}

const BENCH_FRAMES: usize = 3600;

fn benchWalk(g: *Game) void {
    const target = renderTarget(g) orelse return;
    defer rl.unloadRenderTexture(target);
    var t = std.time.Timer.start() catch {
        std.debug.print("timer FAILED\n", .{});
        return;
    };
    begin(g, SHOT_SEED);
    var rng = mathx.Rng.init(SHOT_SEED);
    var d: mathx.Dir = .e;
    const dt: f32 = 1.0 / 60.0;
    var sim = [_]u64{0} ** BENCH_FRAMES;
    var draw = [_]u64{0} ** BENCH_FRAMES;
    for (0..BENCH_FRAMES) |i| {
        if (g.mode == .dead) begin(g, SHOT_SEED +% i);
        const was = g.archer().?.at;
        t.reset();
        g.st.walk = g.st.step.tick(dt, 1, d.heading(), input.Stepper.SETTLE);
        update(g, dt);
        sim[i] = t.lap();
        drawInto(g, target);
        draw[i] = t.read();
        const tried = g.st.walk != null and g.pending == null;
        if (tried and g.archer() != null and g.archer().?.at.eq(was)) d = mathx.ALL_DIRS[rng.below(mathx.ALL_DIRS.len)];
    }
    for ([_][]u64{ &sim, &draw }, [_][]const u8{ "update", "draw" }) |xs, name| {
        std.mem.sort(u64, xs, {}, std.sort.asc(u64));
        var sum: u64 = 0;
        for (xs) |x| sum += x;
        const ms = struct {
            fn f(ns: u64) f64 {
                return @as(f64, @floatFromInt(ns)) / 1e6;
            }
        }.f;
        std.debug.print("{s}: mean {d:.3} ms, p99 {d:.3} ms, max {d:.3} ms\n", .{ name, ms(sum / xs.len), ms(xs[xs.len * 99 / 100]), ms(xs[xs.len - 1]) });
    }
}

const POSE_NEAR: i32 = 3;
const POSE_FAR: i32 = 5;

fn poseRat(g: *Game) void {
    const h = g.archer() orelse return;
    const rat = for (g.pool.slice(), 0..) |a, i| {
        if (a.kind == .rat) break actor.Pool.idOf(i);
    } else return;
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        const d = mathx.dist(p, h.at);
        if (d < POSE_NEAR or d > POSE_FAR or !bow.aimable(&g.lv, h.at, p) or g.lv.taken(p)) continue;
        g.pool.move(&g.lv, rat, p);
        break;
    }
    wound(g, rat, bow.DMG_LO, SHOOT, .{ .from = h.at, .wait = 0 });
    settle(g);
}

/// An open field at noon, so the archer's eyes reach as far as they ever do.
fn arena(g: *Game, hero: P, rats: []const P) void {
    g.lv = grid.openFloor();
    reset(g, hero);
    g.outdoors = true;
    g.clock = day.Clock.at(12);
    for (rats) |r| _ = g.pool.spawn(&g.lv, actor.Actor.of(.rat, r));
    settle(g);
}

/// As if the last turn's glides had all ended.
fn calm(g: *Game) void {
    g.busy = 0;
    g.pending = null;
}

fn press(g: *Game, a: input.Button) void {
    pressHolding(g, a, &.{});
}

fn nudge(g: *Game, d: mathx.Dir) void {
    calm(g);
    g.st = .{ .walk = d };
    update(g, 0);
}

const TEST_DT: f32 = 1.0 / 240.0;
const TEST_TOL: f32 = TEST_DT * 1.5;

/// Seconds of idle frames until `done(g, slot)`, a second at most.
fn framesUntil(g: *Game, slot: usize, comptime done: fn (*Game, usize) bool) f32 {
    g.st = .{};
    var t: f32 = 0;
    while (!done(g, slot) and t < 1) : (t += TEST_DT) update(g, TEST_DT);
    return t;
}

fn flashing(g: *Game, slot: usize) bool {
    return g.fx.flashOf(slot) > 0;
}

fn facesLeft(g: *Game, slot: usize) bool {
    return g.facing[slot] == .left;
}

fn gone(g: *Game, slot: usize) bool {
    return drawnAt(g, slot) == null;
}

fn drawn(g: *Game, slot: usize) bool {
    return !gone(g, slot);
}

/// Gas thick enough to sting for many turns.
const TEST_GAS = 100;
const SLIME_HALF = actor.row(.slime_half).hp;

/// Idle frames until the last turn is drawn out and every foe is drawn turned.
fn drawnOut(g: *Game) void {
    g.st = .{};
    var t: f32 = 0;
    while (t < 2 and (g.busy > 0 or turningAny(g))) : (t += TEST_DT) update(g, TEST_DT);
}

fn turningAny(g: *Game) bool {
    for (g.turning) |t| {
        if (t != null) return true;
    }
    return false;
}

fn samePx(a: rl.Vector2, b: rl.Vector2) bool {
    return @abs(a.x - b.x) < 1e-3 and @abs(a.y - b.y) < 1e-3;
}

fn reddened(g: *Game, _: usize) bool {
    return g.vignette.alpha() > 0;
}

fn pressHolding(g: *Game, a: input.Button, held: []const input.Button) void {
    calm(g);
    g.st = .{};
    g.st.pressed.insert(a);
    g.st.down.insert(a);
    for (held) |h| g.st.down.insert(h);
    update(g, 0);
}

test "a skill fires from whatever button holds it, and the secondary set only with its modifier held" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.bar.clear(.{ .set = .primary, .button = .x });
    g.bar.bind(.{ .set = .secondary, .button = .rb }, .shoot);
    press(g, .x);
    press(g, .rb);
    try std.testing.expectEqual(Mode.play, g.mode);
    pressHolding(g, .rb, &.{.lb});
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expectEqual(input.Button.rb, g.aim_by);
    press(g, .x);
    try std.testing.expect(!g.pool.get(2).?.hurt());
    press(g, .rb);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expect(g.pool.get(2).?.hurt());
}

test "pressing the modifier while a button is already held fires that button's secondary skill" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.bar.bind(.{ .set = .secondary, .button = .y }, .shoot);
    pressHolding(g, .lb, &.{.y});
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expectEqual(input.Button.y, g.aim_by);
}

test "the bind screen picks, carries and removes bindings, and spends no turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    g.pool.get(2).?.awake = true;
    press(g, .view);
    try std.testing.expectEqual(Mode.bind, g.mode);
    g.binds.col = Binds.colOf(.y);
    press(g, .a);
    nudge(g, .e);
    press(g, .a);
    try std.testing.expectEqual(@as(?skillbar.Act, skillbar.ACTS[1]), g.bar.at(.{ .set = .primary, .button = .y }));
    g.binds.col = Binds.colOf(.x);
    press(g, .a);
    nudge(g, .s);
    press(g, .a);
    try std.testing.expectEqual(@as(?skillbar.Act, null), g.bar.at(.{ .set = .primary, .button = .x }));
    try std.testing.expectEqual(@as(?skillbar.Act, .shoot), g.bar.at(.{ .set = .secondary, .button = .x }));
    press(g, .y);
    try std.testing.expectEqual(@as(?skillbar.Act, null), g.bar.at(.{ .set = .secondary, .button = .x }));
    press(g, .b);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(P{ .x = 30, .y = 20 }, g.pool.get(2).?.at);
}

test "a new floor has every pack placed, no foe in sight or on a barrel" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    for (0..40) |i| {
        begin(g, 0xF00D +% i *% 7919);
        var placed: usize = 0;
        for (actor.FOES) |k| {
            const t = g.pool.tally(k);
            try std.testing.expectEqual(t.total, t.left);
            placed += t.total;
        }
        try std.testing.expect(placed >= pack.PER_FLOOR);
        const h = g.archer().?;
        for (g.pool.slice()[1..]) |a| {
            try std.testing.expect(!g.lv.isLit(a.at));
            try std.testing.expect(!g.lv.hasBarrel(a.at));
            try std.testing.expect(mathx.dist(a.at, h.at) >= pack.GAP);
        }
    }
}

test "a rat that sees you notices, closes and bites" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    var noticed: ?usize = null;
    var contact: ?usize = null;
    for (0..12) |turn| {
        endTurn(g);
        const r = g.pool.get(2).?;
        if (noticed == null and r.awake) noticed = turn;
        if (contact == null and mathx.dist(r.at, g.archer().?.at) == 1) contact = turn;
    }
    const lost = actor.row(HERO).hp - g.archer().?.hp;
    std.debug.print("rat 6 away: noticed turn {?d}, adjacent turn {?d}, hero lost {d} hp by turn 12\n", .{ noticed, contact, lost });
    try std.testing.expectEqual(@as(?usize, 0), noticed);
    try std.testing.expectEqual(@as(?usize, 5), contact);
    try std.testing.expect(lost > 0);
}

test "a slime beside you slams you in melee harder than a rat bites" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = g.pool.spawn(&g.lv, actor.Actor.of(.slime, .{ .x = 21, .y = 20 }));
    g.pool.get(id).?.awake = true;
    snapGlide(g);
    endTurn(g);
    const slam = actor.row(.slime).blow.strike;
    const lost = actor.row(HERO).hp - g.archer().?.hp;
    std.debug.print("slime slam: {d} hp\n", .{lost});
    try std.testing.expect(lost >= slam.lo and lost <= slam.hi);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.pool.get(id).?.at);
}

test "a body faces right until it steps, aims or turns on someone to its left, and straight up or down keeps it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 16, .y = 20 }, .{ .x = 25, .y = 20 } });
    const hero = actor.Pool.slot(g.hero);
    for (g.facing[0..g.pool.n]) |f| try std.testing.expectEqual(Facing.right, f);
    nudge(g, .w);
    drawnOut(g);
    try std.testing.expectEqual(Facing.left, g.facing[hero]);
    try std.testing.expectEqual(Facing.right, g.facing[actor.Pool.slot(2)]);
    try std.testing.expectEqual(Facing.left, g.facing[actor.Pool.slot(3)]);
    nudge(g, .n);
    try std.testing.expectEqual(Facing.left, g.facing[hero]);
    nudge(g, .e);
    try std.testing.expectEqual(Facing.right, g.facing[hero]);
    press(g, .x);
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expect(g.mark.x < g.archer().?.at.x);
    try std.testing.expectEqual(Facing.left, g.facing[hero]);
}

test "a step moves the hour on a turn's minutes, a bump into a wall does not, and the sky drawn eases after it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.set(.{ .x = 19, .y = 20 }, .wall);
    const was = g.clock.minute;
    nudge(g, .w);
    try std.testing.expectEqual(was, g.clock.minute);
    nudge(g, .e);
    try std.testing.expectEqual(was + day.TURN_MINUTES, g.clock.minute);
    const behind = day.toward(g.hour_shown, g.clock.hour());
    g.st = .{};
    var t: f32 = 0;
    while (day.toward(g.hour_shown, g.clock.hour()) > behind / 100 and t < 2) : (t += TEST_DT) update(g, TEST_DT);
    std.debug.print("a step: {d:.3} h ahead of the sky drawn, caught up in {d:.2} s\n", .{ behind, t });
    try std.testing.expect(behind > 0 and t < 2);
}

test "underground a rat past the archer's light is out of sight and out of the bow's reach until a torch lights it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const hero = P{ .x = 20, .y = 20 };
    const rat_at = P{ .x = 27, .y = 20 };
    arena(g, hero, &.{rat_at});
    try std.testing.expect(g.lv.isLit(rat_at) and bow.aimable(&g.lv, hero, rat_at));
    g.outdoors = false;
    settle(g);
    try std.testing.expect(!g.lv.isLit(rat_at) and g.lv.inLos(rat_at));
    try std.testing.expect(bow.pick(&g.lv, &g.pool, hero) == null);
    try std.testing.expect(fov.sees(&g.lv, rat_at, hero, actor.row(.rat).sight));
    const wall = rat_at.add(mathx.Dir.n.delta());
    g.lv.set(wall, .wall);
    g.lv.addTorch(wall);
    settle(g);
    try std.testing.expect(g.lv.isLit(rat_at) and bow.aimable(&g.lv, hero, rat_at));
}

test "the archer sees further by day than by night out of doors, and as little at midnight as underground" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 40, .y = 30 }, &.{});
    var seen: [4]usize = undefined;
    for ([_]f32{ 12, 19.5, 0 }, 0..) |h, i| {
        g.clock = day.Clock.at(h);
        settle(g);
        seen[i] = std.mem.count(bool, &g.lv.lit, &.{true});
    }
    g.outdoors = false;
    settle(g);
    seen[3] = std.mem.count(bool, &g.lv.lit, &.{true});
    std.debug.print("cells in the archer's sight: {d} at noon, {d} at dusk, {d} at midnight, {d} underground\n", .{ seen[0], seen[1], seen[2], seen[3] });
    try std.testing.expect(seen[0] > seen[1] and seen[1] > seen[2]);
    try std.testing.expectEqual(seen[3], seen[2]);
}

test "a step into a wall turns no one and spends no turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.pool.get(2).?.awake = true;
    g.lv.set(.{ .x = 19, .y = 20 }, .wall);
    nudge(g, .w);
    try std.testing.expectEqual(Facing.right, g.facing[actor.Pool.slot(g.hero)]);
    try std.testing.expectEqual(P{ .x = 25, .y = 20 }, g.pool.get(2).?.at);
}

test "X opens aim on the nearest rat and nothing is spent until X again" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 27, .y = 20 }, .{ .x = 23, .y = 22 } });
    press(g, .x);
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expectEqual(P{ .x = 23, .y = 22 }, g.mark);
    try std.testing.expect(!g.pool.get(3).?.awake);
    try std.testing.expect(!g.pool.get(3).?.hurt());
    press(g, .x);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expect(g.pool.get(3).?.hurt());
    try std.testing.expect(!g.pool.get(2).?.hurt());
}

test "B cancels aim and costs no turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.pool.get(2).?.awake = true;
    press(g, .x);
    press(g, .b);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(P{ .x = 25, .y = 20 }, g.pool.get(2).?.at);
}

test "the reticle walks only onto cells the arrow can reach" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 20 + bow.RANGE, .y = 20 }});
    g.lv.set(.{ .x = 20 + bow.RANGE, .y = 19 }, .wall);
    castSight(g, .{ .x = 20, .y = 20 });
    press(g, .x);
    nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 20 + bow.RANGE, .y = 20 }, g.mark);
    nudge(g, .n);
    try std.testing.expectEqual(P{ .x = 20 + bow.RANGE, .y = 20 }, g.mark);
    nudge(g, .w);
    try std.testing.expectEqual(P{ .x = 19 + bow.RANGE, .y = 20 }, g.mark);
}

test "two arrows kill a rat at range, and the first wakes it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    press(g, .x);
    press(g, .x);
    const r = g.pool.get(2).?;
    try std.testing.expect(r.awake and r.hp > 0 and r.hp <= actor.row(.rat).hp - bow.DMG_LO);
    try std.testing.expectEqual(@as(i32, 26), r.at.x);
    press(g, .x);
    press(g, .x);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(2));
    try std.testing.expectEqual(@as(usize, 1), g.kills);
}

test "X with nothing in sight stays in play and spends no turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 40, .y = 20 }});
    g.pool.get(2).?.awake = true;
    press(g, .x);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(@as(i32, 40), g.pool.get(2).?.at.x);
}

test "a kicked barrel breaks for gold where it stood, and the archer stays put" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 21, .y = 20 };
    g.lv.putBarrel(at);
    nudge(g, .e);
    std.debug.print("kicked barrel: {d} gold\n", .{g.gold});
    try std.testing.expect(!g.lv.hasBarrel(at));
    try std.testing.expect(g.gold >= GOLD_LO and g.gold <= GOLD_HI);
    try std.testing.expectEqual(P{ .x = 20, .y = 20 }, g.archer().?.at);
    nudge(g, .e);
    try std.testing.expectEqual(at, g.archer().?.at);
}

test "X aims at a barrel when no rat is in reach, and the arrow breaks it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    g.lv.putBarrel(at);
    press(g, .x);
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expectEqual(at, g.mark);
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    press(g, .x);
    try std.testing.expect(!g.lv.hasBarrel(at));
    try std.testing.expect(g.gold >= GOLD_LO);
}

test "the camera never shows past the edge of the floor, and centres it on a screen bigger than it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    begin(g, 4321);
    const world_w = @as(f32, @floatFromInt(grid.W)) * CELL_F;
    const world_h = @as(f32, @floatFromInt(grid.H)) * CELL_F;
    for ([_]P{ .{ .x = WINDOW_W, .y = WINDOW_H }, .{ .x = 2560, .y = 1440 } }) |screen| {
        g.screen = screen;
        for ([_]P{ .{ .x = 0, .y = 0 }, .{ .x = grid.W - 1, .y = grid.H - 1 }, .{ .x = 48, .y = 32 } }) |p| {
            g.archer().?.at = p;
            snapGlide(g);
            const v = camWant(g);
            try std.testing.expect(v.x >= 0 and v.y >= 0);
            try std.testing.expect(v.x + @as(f32, @floatFromInt(screen.x)) <= world_w);
            try std.testing.expect(v.y + @as(f32, @floatFromInt(g.viewH())) <= world_h);
        }
    }
    g.screen = .{ .x = grid.W * CELL + 200, .y = grid.H * CELL + HUD_H + 100 };
    const v = camWant(g);
    try std.testing.expectEqual((world_w - @as(f32, @floatFromInt(g.screen.x))) * 0.5, v.x);
    try std.testing.expectEqual((world_h - @as(f32, @floatFromInt(g.viewH()))) * 0.5, v.y);
}

test "packs land on the floor as the floor is, not where its own rolls put the rooms" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const inRoom = struct {
        fn f(fl: gen.Floor, p: P) bool {
            for (fl.rooms[0..fl.room_n]) |r| {
                if (r.holds(p)) return true;
            }
            return false;
        }
    }.f;
    var lv: grid.Level = undefined;
    var foes: usize = 0;
    var foes_in: usize = 0;
    var open: usize = 0;
    var open_in: usize = 0;
    for (0..200) |i| {
        const seed: u64 = 0x1234 +% i *% 104729;
        begin(g, seed);
        const f = gen.build(&lv, seed);
        for (g.pool.slice()[1..]) |a| {
            foes += 1;
            if (inRoom(f, a.at)) foes_in += 1;
        }
        for (0..grid.CELLS) |c| {
            const p = grid.Level.of(c);
            if (!lv.walkable(p) or lv.hasBarrel(p) or mathx.dist(p, f.start) < pack.GAP) continue;
            open += 1;
            if (inRoom(f, p)) open_in += 1;
        }
    }
    const want = open_in * 100 / open;
    const got = foes_in * 100 / foes;
    std.debug.print("200 floors: {d}% of the open floor a foe may take is in a room, {d}% of foes are\n", .{ want, got });
    try std.testing.expect(got <= want + 5 and got + 5 >= want);
}

test "a held walk glides at one steady speed and the camera follows it without surging" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    for ([_]f32{ 60, 144 }) |hz| {
        arena(g, .{ .x = 20, .y = 32 }, &.{});
        g.st = .{};
        const dt = 1.0 / hz;
        const hero = actor.Pool.slot(g.hero);
        var last = [2]f32{ g.glide[hero].now().x, g.cam.x };
        var lo = [2]f32{ std.math.floatMax(f32), std.math.floatMax(f32) };
        var hi = [2]f32{ 0, 0 };
        var on_last: i32 = 0;
        var on_dir: i32 = 0;
        var flips: usize = 0;
        var t: f32 = 0;
        while (t < 2.0) : (t += dt) {
            g.st.walk = g.st.step.tick(dt, 1, mathx.Dir.e.heading(), input.Stepper.SETTLE);
            update(g, dt);
            const now = [2]f32{ g.glide[hero].now().x, g.cam.x };
            if (t > 0.8) {
                for (0..2) |k| {
                    lo[k] = @min(lo[k], now[k] - last[k]);
                    hi[k] = @max(hi[k], now[k] - last[k]);
                }
            }
            const on = Cam.of(g).px(g.glide[hero].now()).x;
            if (on != on_last) {
                const dir: i32 = if (on > on_last) 1 else -1;
                if (t > input.Stepper.SETTLE + input.Stepper.DAS + GLIDE_S and on_dir != 0 and dir != on_dir) flips += 1;
                on_dir = dir;
            }
            on_last = on;
            last = now;
        }
        std.debug.print("held walk at {d} Hz: body {d:.3}-{d:.3} px/frame, camera {d:.3}-{d:.3} px/frame, archer's screen x reverses {d} times\n", .{ hz, lo[0], hi[0], lo[1], hi[1], flips });
        try std.testing.expect(lo[0] > 0 and hi[0] - lo[0] < 0.05);
        try std.testing.expect(lo[1] > 0 and hi[1] - lo[1] < 0.5);
        try std.testing.expectEqual(@as(usize, 0), flips);
    }
}

test "every step is one hop that peaks mid-glide and lands as the glide ends, and the ground under it does not bob" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 32 }, &.{.{ .x = 50, .y = 32 }});
    g.pool.get(2).?.awake = true;
    g.st = .{};
    const hero = actor.Pool.slot(g.hero);
    const dt = TEST_DT;
    var peaks = [_]i32{0} ** actor.MAX;
    var steps: usize = 0;
    var hops: usize = 0;
    var high = false;
    const ground = [2]f32{ g.glide[hero].now().y, g.cam.y };
    var bobbed = false;
    var t: f32 = 0;
    var was = g.archer().?.at;
    while (t < 1.5) : (t += dt) {
        g.st.walk = g.st.step.tick(dt, 1, mathx.Dir.e.heading(), input.Stepper.SETTLE);
        update(g, dt);
        if (!g.archer().?.at.eq(was)) steps += 1;
        was = g.archer().?.at;
        const up = g.glide[hero].lift() * 2 > @as(i32, HOP_PX);
        if (up and !high) hops += 1;
        high = up;
        for (g.glide[0..g.pool.n], 0..) |gl, i| peaks[i] = @max(peaks[i], gl.lift());
        if (g.glide[hero].now().y != ground[0] or g.cam.y != ground[1]) bobbed = true;
    }
    for (0..60) |_| {
        g.st.walk = g.st.step.tick(dt, 0, 0, input.Stepper.SETTLE);
        update(g, dt);
    }
    std.debug.print("hop: {d} steps, {d} hops, the archer peaks {d} px and the rat {d} px\n", .{ steps, hops, peaks[hero], peaks[actor.Pool.slot(2)] });
    try std.testing.expect(steps > 5);
    try std.testing.expectEqual(steps, hops);
    try std.testing.expectEqual(@as(i32, HOP_PX), peaks[hero]);
    try std.testing.expectEqual(@as(i32, HOP_PX), peaks[actor.Pool.slot(2)]);
    for (g.glide[0..g.pool.n]) |gl| try std.testing.expectEqual(@as(i32, 0), gl.lift());
    try std.testing.expect(!bobbed);
}

test "a step taken mid-hop hops on from the height the body was at" {
    var gl = Glide.still(.{ .x = 5, .y = 5 }, .hop);
    gl = gl.toward(.{ .x = 6, .y = 5 }, 0);
    var worst: f32 = 0;
    var t: f32 = 0;
    const dt = TEST_DT;
    while (t < GLIDE_S * 3) : (t += dt) {
        const before = gl.height();
        gl.t += dt;
        if (@abs(t - GLIDE_S * 0.4) < dt * 0.5) gl = gl.toward(.{ .x = 7, .y = 5 }, 0);
        worst = @max(worst, @abs(gl.height() - before));
    }
    std.debug.print("hop cut short by a step: the biggest jump in height between {d} Hz frames {d:.2} px\n", .{ 1 / dt, worst });
    try std.testing.expect(worst < HOP_PX * 0.2);
    try std.testing.expectEqual(@as(i32, 0), gl.lift());
}

test "a slime slides without hopping, a little past its cell, and settles exactly on it" {
    var gl = Glide.still(.{ .x = 5, .y = 5 }, look.gait(.slime));
    gl = gl.toward(.{ .x = 6, .y = 5 }, 0);
    const to = cellPx(.{ .x = 6, .y = 5 }).x;
    var past: f32 = 0;
    var peak_at: f32 = 0;
    var t: f32 = 0;
    while (t < gl.span() * 1.5) : (t += TEST_DT) {
        gl.t = t;
        try std.testing.expectEqual(@as(i32, 0), gl.lift());
        if (gl.now().x - to > past) {
            past = gl.now().x - to;
            peak_at = gl.done();
        }
    }
    std.debug.print("slime slide: {d:.1} px past its cell at {d:.0}% of the glide\n", .{ past, peak_at * 100 });
    try std.testing.expectApproxEqAbs(CELL_F * 0.05, past, 0.3);
    try std.testing.expectEqual(to, gl.now().x);
}

test "foes act nearest first, so the one behind in a corridor follows the one ahead" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 20 }, .{ .x = 24, .y = 20 } });
    var x: i32 = 21;
    while (x < 30) : (x += 1) {
        g.lv.set(.{ .x = x, .y = 19 }, .wall);
        g.lv.set(.{ .x = x, .y = 21 }, .wall);
    }
    for (g.pool.slice()[1..]) |*a| a.awake = true;
    endTurn(g);
    std.debug.print("corridor: nearer rat to {d}, the one behind to {d}\n", .{ g.pool.get(3).?.at.x, g.pool.get(2).?.at.x });
    try std.testing.expectEqualSlices(u16, &.{ 3, 2 }, g.order[0..g.order_n]);
    try std.testing.expectEqual(@as(i32, 23), g.pool.get(3).?.at.x);
    try std.testing.expectEqual(@as(i32, 24), g.pool.get(2).?.at.x);
}

test "a turn's glides start the archer first, then each foe in sight a stagger behind, and the next walk waits for the last" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 27, .y = 20 }, .{ .x = 24, .y = 23 } });
    _ = g.pool.spawn(&g.lv, actor.Actor.of(.slime, .{ .x = 26, .y = 17 }));
    for (g.pool.slice()[1..]) |*a| a.awake = true;
    settle(g);
    nudge(g, .e);
    const t = [_]f32{ g.glide[0].t, g.glide[actor.Pool.slot(3)].t, g.glide[actor.Pool.slot(4)].t, g.glide[actor.Pool.slot(2)].t };
    std.debug.print("glide starts: archer {d:.3} s, then {d:.3}, {d:.3}, {d:.3}; the turn is busy {d:.3} s\n", .{ -t[0], -t[1], -t[2], -t[3], g.busy });
    try std.testing.expectEqualSlices(u16, &.{ 3, 4, 2 }, g.order[0..g.order_n]);
    for (t, 0..) |v, i| try std.testing.expectApproxEqAbs(-STAGGER_S * @as(f32, @floatFromInt(i)), v, 1e-6);
    try std.testing.expectApproxEqAbs(STAGGER_S * 2 + SLIDE_S, g.busy, 1e-6);
    const at = g.archer().?.at;
    g.st = .{ .walk = .e };
    update(g, 0);
    try std.testing.expectEqual(at, g.archer().?.at);
    g.st = .{};
    var waited: f32 = 0;
    while (g.archer().?.at.eq(at) and waited < 1) : (waited += TEST_DT) update(g, TEST_DT);
    std.debug.print("a walk pressed mid-turn steps {d:.3} s later\n", .{waited});
    try std.testing.expect(!g.archer().?.at.eq(at));
    try std.testing.expectApproxEqAbs(STAGGER_S * 2 + SLIDE_S, waited, TEST_TOL);
}

test "an arrow's rat flashes when the arrow gets there, not when the hit resolves" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    press(g, .x);
    press(g, .x);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.pool.get(2).?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.fx.flashOf(rat));
    const t = framesUntil(g, rat, flashing);
    std.debug.print("arrow 5 cells out: the rat flashes {d:.3} s after the shot, the arrow reaches it at {d:.3} s\n", .{ t, flown(4) });
    try std.testing.expectApproxEqAbs(flown(4), t, TEST_TOL);
}

test "after an arrow the foes act a stagger after it lands, so the rat it strikes is still under it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    g.pool.get(2).?.awake = true;
    press(g, .x);
    press(g, .x);
    const lands = flown(6);
    const starts = -g.glide[actor.Pool.slot(2)].t;
    std.debug.print("an arrow 7 cells out lands {d:.3} s in, and the rat it struck steps at {d:.3} s\n", .{ lands, starts });
    try std.testing.expect(g.pool.get(2).?.hurt());
    try std.testing.expectEqual(@as(i32, 26), g.pool.get(2).?.at.x);
    try std.testing.expectApproxEqAbs(lands + STAGGER_S, starts, 1e-6);
}

test "a body the arrow kills stands until the arrow reaches it and its flash is gone" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 20 + bow.RANGE, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    press(g, .x);
    press(g, .x);
    const rat = actor.Pool.slot(2);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(2));
    try std.testing.expect(drawnAt(g, rat) != null);
    const t = framesUntil(g, rat, gone);
    const lands = flown(bow.RANGE - 1);
    std.debug.print("a rat an arrow kills {d} cells out is drawn {d:.3} s on; the arrow lands at {d:.3} s\n", .{ bow.RANGE, t, lands });
    try std.testing.expectApproxEqAbs(lands + fx.FLASH_S, t, TEST_TOL);
}

test "the bite that kills the archer leaves it standing and followed until it lands, and the veil waits for the turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    g.pool.get(2).?.awake = true;
    g.archer().?.hp = 1;
    nudge(g, .e);
    try std.testing.expectEqual(Mode.dead, g.mode);
    const hero = actor.Pool.slot(g.hero);
    try std.testing.expect(drawnAt(g, hero) != null and carrierAt(g) != null);
    const t = framesUntil(g, hero, gone);
    std.debug.print("a killing bite a stagger in: the archer stands {d:.3} s, the turn is over at {d:.3} s\n", .{ t, t + g.busy });
    try std.testing.expectApproxEqAbs(STAGGER_S + BUMP_LANDS + fx.FLASH_S, t, TEST_TOL);
    try std.testing.expect(carrierAt(g) == null and g.busy <= 0);
}

test "a foe whose bite kills the archer is not then killed by the gas it stands in" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    g.pool.get(2).?.awake = true;
    g.pool.get(2).?.hp = 1;
    g.archer().?.hp = 1;
    g.lv.addGas(.{ .x = 21, .y = 20 }, TEST_GAS);
    press(g, .b);
    try std.testing.expectEqual(Mode.dead, g.mode);
    try std.testing.expect(g.pool.get(2) != null);
    try std.testing.expectEqual(@as(usize, 0), g.kills);
    try std.testing.expectEqualStrings("Archer dies.", g.log.line(0).?);
}

test "a bite lands on the archer at the height of the biter's bump, from its place in the turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    for (g.pool.slice()[1..]) |*a| a.awake = true;
    nudge(g, .e);
    const hero = actor.Pool.slot(g.hero);
    try std.testing.expect(g.archer().?.hurt());
    const t = framesUntil(g, hero, flashing);
    std.debug.print("the biting rat is first in the turn: it sets off {d:.3} s in, the archer flashes {d:.3} s in\n", .{ STAGGER_S, t });
    try std.testing.expectEqualSlices(u16, &.{ 3, 2 }, g.order[0..g.order_n]);
    const bump = g.glide[actor.Pool.slot(3)].bump orelse return error.NoBump;
    try std.testing.expect(bump.x < 0 and bump.y == 0);
    try std.testing.expectApproxEqAbs(STAGGER_S + BUMP_LANDS, t, TEST_TOL);
}

test "a kick bumps the rat and lands at the bump's height, and the rat bites back a stagger after" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    arena(g, at, &.{.{ .x = 21, .y = 20 }});
    g.pool.get(2).?.awake = true;
    const cam = g.cam;
    nudge(g, .e);
    const hero = actor.Pool.slot(g.hero);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.pool.get(2).?.hurt() and g.archer().?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.fx.flashOf(rat));
    g.st = .{};
    var bumped: f32 = 0;
    var bumped_at: f32 = 0;
    var rat_hit: ?f32 = null;
    var t: f32 = 0;
    while (t < BUMP_S) : (t += TEST_DT) {
        update(g, TEST_DT);
        const off = g.glide[hero].now().x - cellPx(at).x;
        if (off > bumped) {
            bumped = off;
            bumped_at = t + TEST_DT;
        }
        if (rat_hit == null and flashing(g, rat)) rat_hit = t + TEST_DT;
        try std.testing.expectEqual(cellPx(at), g.glide[hero].ground());
    }
    try std.testing.expect(samePx(g.glide[hero].now(), cellPx(at)));
    const bitten = t + framesUntil(g, hero, flashing);
    std.debug.print("a kick: the archer bumps {d:.1} px toward the rat at {d:.3} s, the rat flashes at {d:.3} s and bites back at {d:.3} s, the camera {d:.1} px off\n", .{ bumped, bumped_at, rat_hit.?, bitten, @abs(g.cam.x - cam.x) });
    try std.testing.expectApproxEqAbs(BUMP_PX, bumped, 0.5);
    try std.testing.expectApproxEqAbs(BUMP_LANDS, bumped_at, TEST_TOL);
    try std.testing.expectApproxEqAbs(BUMP_LANDS, rat_hit.?, TEST_TOL);
    try std.testing.expectApproxEqAbs(BUMP_LANDS + STAGGER_S + BUMP_LANDS, bitten, TEST_TOL);
    try std.testing.expectEqual(cam, g.cam);
}

test "the lean shows a kick on the rat a kick killed until it falls" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    arena(g, at, &.{.{ .x = 21, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    nudge(g, .e);
    try std.testing.expect(g.pool.get(2) == null);
    try std.testing.expectEqual(Move.kick, leanShown(g, at, .e));
    drawnOut(g);
    try std.testing.expectEqual(Move.step, leanShown(g, at, .e));
}

test "a kick dealt in a frame of play is no further into its bump than its blow is to landing" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    calm(g);
    g.st = .{ .walk = .e };
    update(g, 1.0 / 60.0);
    const t = g.glide[actor.Pool.slot(g.hero)].t;
    std.debug.print("a kick dealt in a 60 fps frame: {d:.4} s into its bump as the frame ends\n", .{t});
    try std.testing.expectEqual(@as(f32, 0), t);
}

test "only the bite that kills the archer lands as a killing blow" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var deaths: usize = 0;
    var hurts: usize = 0;
    for (0..40) |i| {
        arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 }, .{ .x = 20, .y = 21 } });
        g.rng = mathx.Rng.init(i);
        for (g.pool.slice()[1..]) |*a| a.awake = true;
        g.archer().?.hp = actor.row(.rat).blow.strike.hi + 1;
        endTurn(g);
        var kills: usize = 0;
        for (g.bit) |b| {
            if ((b orelse continue).blow == .kill) kills += 1;
        }
        try std.testing.expectEqual(@as(usize, if (g.mode == .dead) 1 else 0), kills);
        if (g.mode != .dead) continue;
        deaths += 1;
        for (g.bit) |b| {
            if ((b orelse continue).blow == .hurt) hurts += 1;
        }
    }
    std.debug.print("three rats on a {d} hp archer: {d} of 40 turns kill, with {d} bites before the killing ones that only hurt\n", .{ actor.row(.rat).blow.strike.hi + 1, deaths, hurts });
    try std.testing.expect(deaths > 0 and hurts >= deaths);
}

test "a body at rest lands on its tile's pixel whatever fraction the camera is at" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const p = P{ .x = 17, .y = 9 };
    var f: f32 = -3;
    while (f < 3) : (f += 0.125) {
        g.cam = .{ .x = 500 + f, .y = 300 - f };
        const c = Cam.of(g);
        try std.testing.expectEqual(P{ .x = c.sx(p), .y = c.sy(p) }, c.px(cellPx(p)));
    }
}

test "the minimap fits in the top right, clear of the hud" {
    for ([_]P{ .{ .x = WINDOW_W, .y = WINDOW_H }, .{ .x = 1920, .y = 1080 }, .{ .x = 2560, .y = 1440 } }) |screen| {
        const o = miniOrigin(screen.x);
        try std.testing.expect(o.x > @divTrunc(screen.x, 2));
        try std.testing.expect(o.y + MINI_H + MINI_FRAME < screen.y - HUD_H);
    }
}

fn spawnAt(g: *Game, k: actor.Kind, at: P, awake: bool) u16 {
    const id = g.pool.spawn(&g.lv, actor.Actor.of(k, at));
    g.pool.get(id).?.awake = awake;
    snapGlide(g);
    return id;
}

test "a bloat beside the archer bursts on it about two turns in three, and never bites" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const TRIES: usize = 300;
    const at = P{ .x = 21, .y = 20 };
    var bursts: usize = 0;
    for (0..TRIES) |i| {
        arena(g, .{ .x = 20, .y = 20 }, &.{});
        const id = spawnAt(g, .bloat, at, true);
        g.rng = mathx.Rng.init(i);
        endTurn(g);
        try std.testing.expect(!g.archer().?.hurt());
        if (g.pool.get(id) != null) continue;
        bursts += 1;
        try std.testing.expectEqual(gas.BURST, g.lv.gasAt(at));
    }
    std.debug.print("an awake bloat beside the archer bursts on {d} of {d} turns\n", .{ bursts, TRIES });
    try std.testing.expect(bursts * 100 > TRIES * 60 and bursts * 100 < TRIES * 80);
}

test "a bloat with no way to the archer still flits a third of its turns" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const TRIES: usize = 300;
    const hero = P{ .x = 20, .y = 20 };
    const at = P{ .x = 30, .y = 20 };
    var moved: usize = 0;
    for (0..TRIES) |i| {
        arena(g, hero, &.{});
        for (mathx.ALL_DIRS) |d| g.lv.set(hero.add(d.delta()), .wall);
        const id = spawnAt(g, .bloat, at, true);
        g.rng = mathx.Rng.init(i);
        endTurn(g);
        if (!g.pool.get(id).?.at.eq(at)) moved += 1;
    }
    std.debug.print("a bloat walled off from the archer flits on {d} of {d} turns\n", .{ moved, TRIES });
    try std.testing.expect(moved * 100 > TRIES * 25 and moved * 100 < TRIES * 42);
}

test "an arrow bursts a bloat where it floats, and its gas reaches the archer and eats at it every turn after" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = spawnAt(g, .bloat, .{ .x = 24, .y = 20 }, false);
    g.pool.get(id).?.hp = 1;
    press(g, .x);
    press(g, .x);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(id));
    try std.testing.expectEqual(@as(usize, 1), g.kills);
    const per = gas.harm(actor.row(HERO).hp);
    var first: ?usize = null;
    for (1..11) |turn| {
        const before = g.archer().?.hp;
        press(g, .b);
        const lost = before - g.archer().?.hp;
        if (first == null and lost > 0) first = turn;
        try std.testing.expectEqual(if (first == null) 0 else per, lost);
        if (lost > 0) try std.testing.expect(g.fx.flashOf(actor.Pool.slot(g.hero)) > 0);
    }
    std.debug.print("a bloat shot 4 cells off: its gas first eats at the archer {?d} turns after, {d} hp a turn\n", .{ first, per });
    try std.testing.expectEqual(@as(?usize, 3), first);
}

test "a bloat caught in another's gas bursts too" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const near = spawnAt(g, .bloat, .{ .x = 27, .y = 20 }, false);
    const far = spawnAt(g, .bloat, .{ .x = 28, .y = 21 }, false);
    g.pool.get(near).?.hp = 1;
    press(g, .x);
    press(g, .x);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(near));
    var waited: usize = 0;
    while (g.pool.get(far) != null and waited < 20) : (waited += 1) press(g, .b);
    std.debug.print("a bloat beside one shot dead bursts {d} turns later\n", .{waited});
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(far));
    try std.testing.expectEqual(@as(usize, 2), g.kills);
}

test "a foe the gas kills out of sight leaves nothing drawn and nothing said" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 40, .y = 20 }});
    g.lv.addGas(.{ .x = 40, .y = 20 }, TEST_GAS);
    g.pool.get(2).?.hp = 1;
    const said = g.log.n;
    press(g, .b);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(2));
    try std.testing.expectEqual(@as(usize, 1), g.kills);
    try std.testing.expectEqual(@as(usize, 0), g.fx.due_n);
    for (g.fx.motes) |m| try std.testing.expect(m.life <= 0);
    try std.testing.expectEqualStrings("The last rat is dead.", g.log.line(0).?);
    try std.testing.expectEqual(said + 1, g.log.n);
}

test "a foe the gas kills after it steps keeps its place in the turn, and its death lands as it arrives" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    const was = g.pool.get(2).?.at;
    g.pool.get(2).?.awake = true;
    g.pool.get(2).?.hp = 1;
    g.lv.addGas(was, TEST_GAS);
    nudge(g, .w);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(2));
    try std.testing.expect(!g.pool.items[actor.Pool.slot(2)].at.eq(was));
    const t = framesUntil(g, actor.Pool.slot(2), flashing);
    std.debug.print("a rat that steps and dies in the gas: its death lands {d:.3} s into the turn, its hop ends at {d:.3} s\n", .{ t, STAGGER_S + GLIDE_S });
    try std.testing.expectApproxEqAbs(STAGGER_S + GLIDE_S, t, TEST_TOL);
}

test "an arrow that bursts a bloat eats at a sleeping foe with its gas as it lands, not before" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const bloat = spawnAt(g, .bloat, .{ .x = 27, .y = 20 }, false);
    const rat = spawnAt(g, .rat, .{ .x = 28, .y = 21 }, false);
    g.pool.get(bloat).?.hp = 1;
    press(g, .x);
    press(g, .x);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(bloat));
    try std.testing.expect(g.pool.get(rat).?.hurt());
    const lands = flown(6);
    const t = framesUntil(g, actor.Pool.slot(rat), flashing);
    std.debug.print("a bloat shot 7 cells out: the arrow lands {d:.3} s in, and its gas stings the rat beside it {d:.3} s in\n", .{ lands, t });
    try std.testing.expectApproxEqAbs(lands, t, TEST_TOL);
}

test "a bloat's cloud is drawn from when its burst lands" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const Burst = struct {
        const at = P{ .x = 27, .y = 20 };
        fn clouded(game: *Game, _: usize) bool {
            return game.cloud.tint[grid.Level.idx(at)] > 0;
        }
    };
    const bloat = spawnAt(g, .bloat, Burst.at, false);
    g.pool.get(bloat).?.hp = 1;
    press(g, .x);
    press(g, .x);
    try std.testing.expect(g.lv.gasAt(Burst.at) > 0 and !Burst.clouded(g, 0));
    const t = framesUntil(g, 0, Burst.clouded);
    std.debug.print("a bloat shot 7 cells out: the arrow lands {d:.3} s in, its cloud first drawn {d:.3} s in\n", .{ flown(6), t });
    try std.testing.expectApproxEqAbs(flown(6), t, TEST_TOL);
}

test "a foe stepping out of sight takes its place in the turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const rat = actor.Pool.slot(2);
    var x: i32 = 18;
    while (x <= 26) : (x += 1) g.lv.set(.{ .x = x, .y = 21 }, .wall);
    castSight(g, .{ .x = 20, .y = 20 });
    const dark = P{ .x = 22, .y = 22 };
    try std.testing.expect(!g.lv.isLit(dark));
    g.pool.move(&g.lv, 2, dark);
    g.order[0] = 2;
    g.order_n = 1;
    g.lead = 0;
    stepGlide(g, 0);
    std.debug.print("a rat stepping out of sight a stagger after a kick sets off {d:.3} s in\n", .{-g.glide[rat].t});
    try std.testing.expectApproxEqAbs(STAGGER_S, -g.glide[rat].t, 1e-6);
}

test "a barrel the arrow breaks stands until the arrow reaches it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const Gone = struct {
        const at = P{ .x = 20 + bow.RANGE, .y = 20 };
        fn f(game: *Game, _: usize) bool {
            return !barrelShownAt(game, at);
        }
    };
    g.lv.putBarrel(Gone.at);
    press(g, .x);
    press(g, .x);
    try std.testing.expect(!g.lv.hasBarrel(Gone.at) and !Gone.f(g, 0));
    const t = framesUntil(g, 0, Gone.f);
    const lands = flown(bow.RANGE - 1);
    std.debug.print("a barrel shot {d} cells out breaks {d:.3} s on; the arrow lands at {d:.3} s\n", .{ bow.RANGE, t, lands });
    try std.testing.expectApproxEqAbs(lands, t, TEST_TOL);
}

test "a foe's hp as drawn, the archer's and the low glow drop as the blow lands, not as it resolves" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    const rat = actor.Pool.slot(2);
    press(g, .x);
    press(g, .x);
    try std.testing.expect(g.pool.get(2).?.hurt());
    try std.testing.expectEqual(actor.row(.rat).hp, g.pictured[rat].hp);
    const Drop = struct {
        fn f(game: *Game, i: usize) bool {
            return game.pictured[i].hp < actor.row(.rat).hp;
        }
    };
    const t = framesUntil(g, rat, Drop.f);
    std.debug.print("an arrow 7 cells out: the rat's bar drops {d:.3} s in, as it lands at {d:.3} s\n", .{ t, flown(6) });
    try std.testing.expectApproxEqAbs(flown(6), t, TEST_TOL);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    for (g.pool.slice()[1..]) |*a| a.awake = true;
    const low = @divTrunc(actor.row(HERO).hp, 3);
    g.archer().?.hp = low;
    catchUp(g);
    nudge(g, .e);
    const hero = actor.Pool.slot(g.hero);
    try std.testing.expect(g.archer().?.hp < low);
    try std.testing.expectEqual(low, g.pictured[hero].hp);
    try std.testing.expectEqual(@as(f32, 0), g.vignette.alpha());
    const r = framesUntil(g, hero, reddened);
    std.debug.print("a bite on an archer at a third of its hp: the view reddens {d:.3} s in, as it lands at {d:.3} s\n", .{ r, STAGGER_S + BUMP_LANDS });
    try std.testing.expectApproxEqAbs(STAGGER_S + BUMP_LANDS, r, TEST_TOL);
}

test "an arrow that splits a slime shows it as the arrow lands, the new half sliding out of it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 27, .y = 20 };
    const id = spawnAt(g, .slime, at, false);
    g.pool.get(id).?.hp = SLIME_HALF + 1;
    catchUp(g);
    press(g, .x);
    press(g, .x);
    const slime = actor.Pool.slot(id);
    const other = slime + 1;
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.get(id).?.kind);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.items[other].kind);
    try std.testing.expectEqual(actor.Kind.slime, g.pictured[slime].kind);
    try std.testing.expect(drawnAt(g, other) == null);
    try std.testing.expectEqual(fx.Body.of(g.pool.items[other], g.pictured[other].seq), g.pictured[other]);
    try std.testing.expectEqualStrings("The slime splits in two!", g.log.line(0).?);
    const t = framesUntil(g, other, drawn);
    const lands = flown(6);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pictured[slime].kind);
    try std.testing.expect(samePx(g.glide[other].now(), cellPx(at)));
    try std.testing.expect(g.busy >= SLIDE_S);
    const slid = framesUntil(g, other, struct {
        fn f(game: *Game, i: usize) bool {
            return game.glide[i].done() >= 1;
        }
    }.f);
    std.debug.print("an arrow 7 cells out splits a slime: the new half shows {d:.3} s in, as it lands at {d:.3} s, and slides out over {d:.3} s\n", .{ t, lands, slid });
    try std.testing.expectApproxEqAbs(lands, t, TEST_TOL);
    try std.testing.expectApproxEqAbs(SLIDE_S, slid, TEST_TOL);
    try std.testing.expect(samePx(g.glide[other].now(), cellPx(g.pool.items[other].at)));
    try std.testing.expectEqual(actor.Tally{ .left = 2, .total = 2 }, g.pool.tally(.slime));
}

test "a slime split this turn acts from the next, and one a blow kills outright splits nothing" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = spawnAt(g, .slime, .{ .x = 21, .y = 20 }, true);
    g.pool.get(id).?.hp = SLIME_HALF;
    nudge(g, .e);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.get(id).?.kind);
    try std.testing.expectEqualSlices(u16, &.{id}, g.order[0..g.order_n]);
    const other = id + 1;
    try std.testing.expect(!g.pool.get(other).?.waits);
    press(g, .b);
    try std.testing.expectEqual(@as(usize, 2), g.order_n);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const one = spawnAt(g, .slime, .{ .x = 25, .y = 20 }, false);
    g.pool.get(one).?.hp = bow.DMG_LO;
    press(g, .x);
    press(g, .x);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(one));
    try std.testing.expectEqual(actor.Tally{ .left = 0, .total = 1 }, g.pool.tally(.slime));
    try std.testing.expectEqualStrings("The last slime is dead.", g.log.line(0).?);
}

/// Long enough that most of a turn's blows land before the next, so splits show.
const SOAK_DT: f32 = 0.1;

test "slimes split in fights on real floors, and every body keeps a cell of its own" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var splits: usize = 0;
    var most: usize = 0;
    var quarters: usize = 0;
    const FLOORS: usize = 20;
    for (0..FLOORS) |f| {
        begin(g, 0x511E +% f *% 7919);
        for (g.pool.slice()) |*a| a.awake = true;
        g.archer().?.hp = 1000;
        g.archer().?.max = 1000;
        var rng = mathx.Rng.init(f);
        for (0..300) |_| {
            const n = g.pool.n;
            press(g, .x);
            if (g.mode == .aim) press(g, .x) else nudge(g, mathx.ALL_DIRS[rng.below(mathx.ALL_DIRS.len)]);
            update(g, SOAK_DT);
            for (0..g.pool.n) |i| {
                if (drawnAt(g, i) == null) continue;
                const pic = g.pictured[i];
                try std.testing.expect(pic.max > 0 and pic.hp <= pic.max and pic.kind.family() == g.pool.items[i].kind.family());
            }
            splits += g.pool.n - n;
            most = @max(most, g.pool.n);
            var standing_n: usize = 0;
            for (g.pool.slice(), 0..) |a, i| {
                if (!a.alive) continue;
                standing_n += 1;
                try std.testing.expectEqual(actor.Pool.idOf(i), g.lv.who(a.at));
                try std.testing.expect(a.hp > 0 and a.hp <= a.max);
            }
            var taken: usize = 0;
            for (&g.lv.occupant) |*o| {
                if (o.* != grid.NO_ONE) taken += 1;
            }
            try std.testing.expectEqual(standing_n, taken);
        }
        for (g.pool.slice()) |a| {
            if (a.kind == .slime_quarter) quarters += 1;
        }
    }
    std.debug.print("{d} floors of 300 turns with every foe awake: {d} splits, {d} quarter slimes made, at most {d} bodies of {d}\n", .{ FLOORS, splits, quarters, most, actor.MAX });
    try std.testing.expect(splits > FLOORS and quarters > 0);
    try std.testing.expect(most <= actor.MAX);
}

test "each bite on the archer drops its hp as drawn as that bite lands" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 } });
    for (g.pool.slice()[1..]) |*a| a.awake = true;
    press(g, .b);
    const hero = actor.Pool.slot(g.hero);
    const full = actor.row(HERO).hp;
    const hp = g.archer().?.hp;
    try std.testing.expectEqual(full, g.pictured[hero].hp);
    const One = struct {
        fn f(game: *Game, i: usize) bool {
            return game.pictured[i].hp < actor.row(HERO).hp;
        }
    };
    const Both = struct {
        fn f(game: *Game, i: usize) bool {
            return game.pictured[i].hp == game.pool.items[i].hp;
        }
    };
    const t1 = framesUntil(g, hero, One.f);
    const first = g.pictured[hero].hp;
    try std.testing.expect(first > hp);
    const t2 = t1 + framesUntil(g, hero, Both.f);
    std.debug.print("two rats bite an archer of {d} hp: drawn on {d} as the first lands {d:.3} s in, on {d} as the second lands {d:.3} s in\n", .{ full, first, t1, hp, t2 });
    try std.testing.expectApproxEqAbs(BUMP_LANDS, t1, TEST_TOL);
    try std.testing.expectApproxEqAbs(STAGGER_S + BUMP_LANDS, t2, TEST_TOL);
}

test "a slime an arrow splits shows split as the arrow lands, though the gas eats at it later in the turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = spawnAt(g, .slime, at, true);
    g.pool.get(id).?.hp = SLIME_HALF + 1;
    for ([_]P{ at, .{ .x = 24, .y = 20 } }) |p| g.lv.addGas(p, TEST_GAS);
    catchUp(g);
    press(g, .x);
    press(g, .x);
    const slime = actor.Pool.slot(id);
    const other = slime + 1;
    try std.testing.expect(!g.pool.items[slime].at.eq(at));
    const t = framesUntil(g, other, drawn);
    const lands = flown(4);
    std.debug.print("an arrow 5 cells out splits a slime in gas: the new half shows {d:.3} s in, as the arrow lands at {d:.3} s, the gas still to land on the slime\n", .{ t, lands });
    try std.testing.expectApproxEqAbs(lands, t, TEST_TOL);
    try std.testing.expect(g.fx.pending(slime));
    try std.testing.expectEqual(actor.Kind.slime_half, g.pictured[slime].kind);
}

test "a split nobody sees holds no one's walk" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 40, .y = 20 };
    const id = spawnAt(g, .slime, at, false);
    g.pool.get(id).?.hp = SLIME_HALF + 1;
    g.lv.addGas(at, TEST_GAS);
    catchUp(g);
    press(g, .b);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.get(id).?.kind);
    try std.testing.expectEqual(@as(?usize, null), g.split_from[actor.Pool.slot(id) + 1]);
    try std.testing.expect(g.busy <= 0);
}

test "a foe the gas kills as it steps out of sight is drawn stepping out, not gone from where it stood" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const rat = actor.Pool.slot(2);
    var x: i32 = 18;
    while (x <= 26) : (x += 1) g.lv.set(.{ .x = x, .y = 21 }, .wall);
    castSight(g, .{ .x = 20, .y = 20 });
    const dark = P{ .x = 22, .y = 22 };
    try std.testing.expect(!g.lv.isLit(dark));
    g.pool.move(&g.lv, 2, dark);
    _ = g.pool.damage(&g.lv, 2, actor.row(.rat).hp);
    g.gassed[rat] = .{ .kill = true, .after = .{ .body = fx.Body.of(g.pool.items[rat], 0) } };
    g.order[0] = 2;
    g.order_n = 1;
    g.lead = 0;
    stepGlide(g, 0);
    try std.testing.expect(drawnAt(g, rat) != null);
    const t = framesUntil(g, rat, gone);
    std.debug.print("a rat the gas kills stepping out of sight a stagger in: drawn until {d:.3} s, its hop {d:.3} to {d:.3} s\n", .{ t, STAGGER_S, STAGGER_S + GLIDE_S });
    try std.testing.expect(t > STAGGER_S and t < STAGGER_S + GLIDE_S);
}

test "a foe with no place in the turn is stung as the archer's step lands, not before" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const at = P{ .x = 28, .y = 20 };
    arena(g, .{ .x = 20, .y = 20 }, &.{at});
    g.lv.addGas(at, TEST_GAS);
    nudge(g, .w);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.pool.get(2).?.hurt() and g.pool.get(2).?.at.eq(at));
    const t = framesUntil(g, rat, flashing);
    std.debug.print("a still rat in gas as the archer steps: stung {d:.3} s in, the step lands at {d:.3} s\n", .{ t, GLIDE_S });
    try std.testing.expectApproxEqAbs(GLIDE_S, t, TEST_TOL);
}

test "a foe is drawn turning at its place in the turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 20 } });
    for (g.pool.slice()[1..]) |*a| a.awake = true;
    press(g, .b);
    const far = actor.Pool.slot(3);
    try std.testing.expectEqual(Facing.right, g.facing[far]);
    const t = framesUntil(g, far, facesLeft);
    std.debug.print("the second rat in the turn is drawn turning {d:.3} s in\n", .{t});
    try std.testing.expectApproxEqAbs(STAGGER_S, t, TEST_TOL);
}

test "a kick due late in a frame puts the foes a stagger after it lands, late once" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 20, .y = 21 } });
    for (g.pool.slice()[1..]) |*a| a.awake = true;
    const late: f32 = 0.05;
    calm(g);
    g.st = .{ .walk = .e };
    g.st.step.late = late;
    update(g, 0);
    const t = framesUntil(g, actor.Pool.slot(g.hero), reddened);
    std.debug.print("a kick due {d:.3} s late: the first bite lands {d:.3} s on\n", .{ late, t });
    try std.testing.expectApproxEqAbs(2 * BUMP_LANDS + STAGGER_S - late, t, TEST_TOL);
}

test "a run left mid-turn keeps the way its foes were turning" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 20 } });
    for (g.pool.slice()[1..]) |*a| a.awake = true;
    press(g, .b);
    const far = actor.Pool.slot(3);
    try std.testing.expectEqual(Facing.right, g.facing[far]);
    leave(g);
    std.debug.print("a rat turning as the run is left faces {s}\n", .{@tagName(g.facing[far])});
    try std.testing.expectEqual(Facing.left, g.facing[far]);
}

test "a foe that notices the archer turns to it once the archer's step is drawn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 24, .y = 20 }});
    nudge(g, .w);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.pool.get(2).?.awake);
    const t = framesUntil(g, rat, facesLeft);
    std.debug.print("a rat noticing the archer turns {d:.3} s in, the step lands at {d:.3} s\n", .{ t, GLIDE_S });
    try std.testing.expectApproxEqAbs(GLIDE_S, t, TEST_TOL);
}

test "a slime split off one not yet drawn waits for it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const p = actor.Pool.slot(spawnAt(g, .slime_half, .{ .x = 25, .y = 20 }, false));
    const c = actor.Pool.slot(spawnAt(g, .slime_half, .{ .x = 26, .y = 20 }, false));
    const d = actor.Pool.slot(spawnAt(g, .slime_quarter, .{ .x = 27, .y = 20 }, false));
    g.split_from[c] = p;
    g.split_from[d] = c;
    const wait: f32 = 0.1;
    g.fx.strike(wait, .{ .slot = p, .at = .{ 25.5, 20.5 }, .dir = null, .matter = .ooze, .lethal = false, .after = .{ .body = fx.Body.of(g.pool.items[p], 1), .reveals = c } });
    catchUp(g);
    try std.testing.expect(g.split_from[c] != null and g.split_from[d] != null);
    const t = framesUntil(g, d, drawn);
    try std.testing.expectApproxEqAbs(wait, t, TEST_TOL);
    try std.testing.expect(drawnAt(g, c) != null);
}

test "the dead archer's floor restarts only once the death is shown" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    g.pool.get(2).?.awake = true;
    g.archer().?.hp = 1;
    nudge(g, .e);
    try std.testing.expectEqual(Mode.dead, g.mode);
    g.st = .{};
    g.st.pressed.insert(CONFIRM);
    update(g, 0);
    try std.testing.expectEqual(Mode.dead, g.mode);
    _ = framesUntil(g, 0, struct {
        fn f(game: *Game, _: usize) bool {
            return deathShown(game);
        }
    }.f);
    press(g, CONFIRM);
    try std.testing.expectEqual(Mode.play, g.mode);
}

test "the reticle crosses the archer to the far side of a corridor" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 15, .y = 20 } });
    var x: i32 = 10;
    while (x <= 30) : (x += 1) {
        g.lv.set(.{ .x = x, .y = 19 }, .wall);
        g.lv.set(.{ .x = x, .y = 21 }, .wall);
    }
    castSight(g, .{ .x = 20, .y = 20 });
    press(g, .x);
    try std.testing.expectEqual(P{ .x = 23, .y = 20 }, g.mark);
    for (0..3) |_| nudge(g, .w);
    try std.testing.expectEqual(P{ .x = 19, .y = 20 }, g.mark);
}

test "the view's edge reddens as a bite lands on the archer, not before, and as the gas eats at it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    for (g.pool.slice()[1..]) |*a| a.awake = true;
    nudge(g, .e);
    try std.testing.expect(g.archer().?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.vignette.alpha());
    const t = framesUntil(g, actor.Pool.slot(g.hero), reddened);
    std.debug.print("a bite bumped a stagger into the turn reddens the view {d:.3} s in\n", .{t});
    try std.testing.expectApproxEqAbs(STAGGER_S + BUMP_LANDS, t, TEST_TOL);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.addGas(.{ .x = 20, .y = 20 }, TEST_GAS);
    press(g, .b);
    try std.testing.expect(g.archer().?.hurt());
    try std.testing.expect(framesUntil(g, actor.Pool.slot(g.hero), reddened) < TEST_TOL);
}

test "gas left to eat at the archer kills it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.addGas(.{ .x = 20, .y = 20 }, TEST_GAS);
    g.archer().?.hp = 1;
    press(g, .b);
    try std.testing.expectEqual(Mode.dead, g.mode);
    try std.testing.expectEqualStrings("Archer dies.", g.log.line(0).?);
    try std.testing.expect(framesUntil(g, actor.Pool.slot(g.hero), reddened) < TEST_TOL);
}

test "an unkillable archer keeps 1 hp through gas and bites that would kill it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 } });
    for ([_]u16{ 2, 3 }) |id| g.pool.get(id).?.awake = true;
    g.unkillable = true;
    g.lv.addGas(.{ .x = 20, .y = 20 }, TEST_GAS);
    g.archer().?.hp = 2;
    for (0..20) |_| press(g, .b);
    std.debug.print("an unkillable archer after 20 turns in gas between two rats: {d} hp\n", .{g.archer().?.hp});
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(@as(i32, 1), g.archer().?.hp);
}

test "a bloat that bursts on the archer takes its place in the turn as a bite does, and its spray lands there" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var seed: u64 = 0;
    while (seed < 50) : (seed += 1) {
        arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 19, .y = 20 }});
        g.pool.get(2).?.awake = true;
        const id = spawnAt(g, .bloat, .{ .x = 21, .y = 20 }, true);
        g.rng = mathx.Rng.init(seed);
        press(g, .b);
        if (g.pool.get(id) == null) break;
    } else return error.NeverBurst;
    try std.testing.expectEqualSlices(u16, &.{ 2, 3 }, g.order[0..g.order_n]);
    try std.testing.expectApproxEqAbs(STAGGER_S + BUMP_LANDS + fx.FLASH_S, g.busy, 1e-6);
    try std.testing.expectEqual(@as(usize, 2), g.fx.due_n);
    const busy = g.busy;
    const t = framesUntil(g, actor.Pool.slot(3), flashing);
    std.debug.print("a rat bites, then a bloat bursts on the archer: the burst lands {d:.3} s in, the turn is busy {d:.3} s\n", .{ t, busy });
    try std.testing.expectApproxEqAbs(STAGGER_S + BUMP_LANDS, t, TEST_TOL);
}

fn idle(g: *Game) void {
    calm(g);
    g.st = .{};
    update(g, 0);
}

test "a door takes the archer to the door it leads to, and a node left is found as it was" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    const room = w.add(.{ .bespoke = .{} }).?;
    const cave = w.add(.{ .procgen = .{} }).?;
    const b = &w.node[room].plan.bespoke;
    var x: i32 = 2;
    while (x <= 12) : (x += 1) b.tile[grid.Level.idx(.{ .x = x, .y = 5 })] = .floor;
    const slime = P{ .x = 2, .y = 5 };
    _ = b.addFoe(.{ .kind = .slime, .at = slime });
    const d0 = w.addDoor(room, .{ .x = 12, .y = 5 }).?;
    const d1 = w.addDoor(cave, .{ .x = 30, .y = 30 }).?;
    w.link(.{ .node = room, .door = d0 }, .{ .node = cave, .door = d1 });
    w.start = .{ .node = room, .at = .{ .x = 10, .y = 5 } };
    beginWorld(g, w);
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    _ = g.pool.damage(&g.lv, g.hero, 5);
    nudge(g, .e);
    nudge(g, .e);
    try std.testing.expect(g.travel != null);
    idle(g);
    try std.testing.expectEqual(cave, g.node);
    try std.testing.expectEqual(P{ .x = 30, .y = 30 }, g.archer().?.at);
    try std.testing.expectEqual(actor.row(HERO).hp - 5, g.archer().?.hp);
    try std.testing.expect(g.pool.n > 1);
    const off = for (mathx.ALL_DIRS) |d| {
        if (!d.diagonal() and g.lv.stepOk(g.archer().?.at, d, g.hero)) break d;
    } else return error.DoorWalledIn;
    nudge(g, off);
    nudge(g, mathx.dirTo(off.delta(), .{ .x = 0, .y = 0 }).?);
    idle(g);
    try std.testing.expectEqual(room, g.node);
    try std.testing.expectEqual(P{ .x = 12, .y = 5 }, g.archer().?.at);
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    try std.testing.expectEqual(slime, g.pool.items[1].at);
    try std.testing.expect(g.lv.isSeen(.{ .x = 10, .y = 5 }));
    std.debug.print("through a door and back: node {d}, the slime still at {d},{d}\n", .{ g.node, slime.x, slime.y });
}

test "a procgen node rolls another floor round the same doors each run, and two nodes differ in one run" {
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    const n = w.add(.{ .procgen = .{} }).?;
    const door = P{ .x = 30, .y = 30 };
    _ = w.addDoor(n, door);
    var lv: [3]grid.Level = undefined;
    w.node[n].stamp(&lv[0], rollOf(1, n));
    w.node[n].stamp(&lv[1], rollOf(2, n));
    w.node[n].stamp(&lv[2], rollOf(1, n + 1));
    var differ = [2]usize{ 0, 0 };
    for (0..grid.CELLS) |i| {
        if (lv[0].tile[i] != lv[1].tile[i]) differ[0] += 1;
        if (lv[0].tile[i] != lv[2].tile[i]) differ[1] += 1;
    }
    std.debug.print("one procgen node, two runs: {d} cells differ; two nodes of one run: {d}\n", .{ differ[0], differ[1] });
    for (lv) |l| try std.testing.expectEqual(@as(?usize, 0), l.doorAt(door));
    try std.testing.expect(differ[0] > 0 and differ[1] > 0);
}

test "a door keeps the low glow, the archer's facing and a walk pressed while the door turn is drawn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    const a = w.add(.{ .bespoke = .{} }).?;
    const b = w.add(.{ .bespoke = .{} }).?;
    for ([_]usize{ a, b }) |n| {
        var x: i32 = 2;
        while (x <= 12) : (x += 1) w.node[n].plan.bespoke.tile[grid.Level.idx(.{ .x = x, .y = 5 })] = .floor;
    }
    _ = w.node[b].plan.bespoke.addFoe(.{ .kind = .rat, .at = .{ .x = 11, .y = 5 } });
    const da = w.addDoor(a, .{ .x = 2, .y = 5 }).?;
    const db = w.addDoor(b, .{ .x = 11, .y = 5 }).?;
    w.link(.{ .node = a, .door = da }, .{ .node = b, .door = db });
    w.start = .{ .node = a, .at = .{ .x = 3, .y = 5 } };
    beginWorld(g, w);
    _ = g.pool.damage(&g.lv, g.hero, actor.row(HERO).hp - 1);
    g.st = .{};
    for (0..480) |_| update(g, TEST_DT);
    const low = g.vignette.low;
    nudge(g, .w);
    g.st = .{ .walk = .w };
    update(g, TEST_DT);
    g.st = .{};
    while (g.node == a) update(g, TEST_DT);
    try std.testing.expectEqual(Facing.left, g.facing[actor.Pool.slot(g.hero)]);
    try std.testing.expect(!g.archer().?.at.eq(.{ .x = 11, .y = 5 }));
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    std.debug.print("through a door on 1 hp: the low glow {d:.3} before, {d:.3} after, a walk queued: {}\n", .{ low, g.vignette.low, g.pending != null });
    try std.testing.expect(g.pending != null);
    try std.testing.expectApproxEqAbs(low, g.vignette.low, 0.05);
}

test "the pause menu spends no turn, and its way out leads back to where the game was started from" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    g.pool.get(2).?.awake = true;
    press(g, .pause);
    try std.testing.expectEqual(Mode.pause, g.mode);
    press(g, .pause);
    try std.testing.expectEqual(Mode.play, g.mode);
    for (std.enums.values(Back)) |back| {
        g.back = back;
        press(g, .pause);
        for (0..std.mem.indexOfScalar(PauseRow, PAUSE_ROWS, .back).?) |_| nudge(g, .s);
        press(g, .a);
        try std.testing.expectEqual(@as(?Exit, .back), g.exit);
        try std.testing.expectEqual(Mode.play, g.mode);
        g.exit = null;
    }
    try std.testing.expectEqual(P{ .x = 26, .y = 20 }, g.pool.get(2).?.at);
}
