const std = @import("std");
const rl = @import("raylib");

const mathx = @import("core/mathx.zig");
const input = @import("core/input.zig");
const grid = @import("world/grid.zig");
const fov = @import("world/fov.zig");
const gen = @import("world/gen.zig");
const carve = @import("world/carve.zig");
const gas = @import("world/gas.zig");
const atlas = @import("world/atlas.zig");
const editor = @import("edit/editor.zig");
const menu = @import("ui/menu.zig");
const hud = @import("ui/hud.zig");
const heroes = @import("play/hero.zig");
const naming = @import("ui/naming.zig");
const actor = @import("play/actor.zig");
const bow = @import("play/bow.zig");
const damage = @import("play/damage.zig");
const burning = @import("play/burning.zig");
const bleeding = @import("play/bleeding.zig");
const glacial = @import("play/glacial.zig");
const juke = @import("play/juke.zig");
const blink = @import("play/blink.zig");
const spark = @import("play/spark.zig");
const bash = @import("play/bash.zig");
const cleave = @import("play/cleave.zig");
const pinning = @import("play/pinning.zig");
const barbed = @import("play/barbed.zig");
const nova = @import("play/nova.zig");
const fireball = @import("play/fireball.zig");
const chain = @import("play/chain.zig");
const ward = @import("play/ward.zig");
const charge = @import("play/charge.zig");
const flask = @import("play/flask.zig");
const pack = @import("play/pack.zig");
const skillbar = @import("play/skillbar.zig");
const look = @import("gfx/look.zig");
const dual = @import("gfx/ground.zig");
const light = @import("gfx/light.zig");
const font = @import("gfx/font.zig");
const fx = @import("gfx/fx.zig");
const cloud = @import("gfx/cloud.zig");
const vignette = @import("gfx/vignette.zig");
const sky = @import("gfx/sky.zig");
const weather = @import("gfx/weather.zig");
const climate = @import("world/climate.zig");
const day = @import("world/day.zig");
const lume = @import("world/lume.zig");

const P = mathx.P;

const WINDOW_W: i32 = 1600;
const WINDOW_H: i32 = 900;
const CELL: i32 = 64;
const CELL_F: f32 = @floatFromInt(CELL);
const HALF_CELL: i32 = @divTrunc(CELL, 2);

fn authored(comptime px: i32) i32 {
    return @divExact(CELL * px, look.SPRITE_PX);
}
/// Screen pixels to a sprite's pixel.
const PX_SCALE: f32 = @floatFromInt(@divExact(CELL, look.SPRITE_PX));
const GLYPH: i32 = authored(look.GLYPH_PX);
const LEAN_GLYPH: i32 = authored(40);
const LEAN_MARK: i32 = authored(30);
const TORCH_GLYPH: i32 = authored(30);
const TEXT: i32 = font.BODY;
const LINE_W: i32 = authored(2);
const OUTLINE_INSET: i32 = authored(1);
const BODY_BAR_INSET: i32 = authored(6);
const BODY_BAR_H: i32 = authored(4);
const BODY_BAR_LIFT: i32 = authored(2);
const LEAN_PAD: i32 = authored(4);
const TEXT_LINE: i32 = 26;
const DEAD_TITLE_DY: i32 = -100;
const DEAD_SCORE_DY: i32 = -10;
const SLOT_PX: i32 = 56;
const SLOT_MID: i32 = @divTrunc(SLOT_PX, 2);
const CLEAR_GLYPH: i32 = @divTrunc(SLOT_PX, 2);
const SLOT_GAP: i32 = 10;
const SLOT_STEP: i32 = SLOT_PX + SLOT_GAP;
const CARRIED_A: f32 = 0.35;
const GROUP_GAP: i32 = 20;
const SLOT_TEXT = font.SMALL;
const KEY_GAP: i32 = 6;
const PROMPT_PX: i32 = 22;
/// From a slot's top right corner to its cooldown's turns, or a flask's drinks left.
const COOLDOWN_DX: i32 = 18;
const COOLDOWN_DY: i32 = 2;
const SLOT_EDGE_INSET: i32 = look.HUD_BORDER_CUT - 3;
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
const BIND_TITLE: i32 = 40;
const BIND_TOP_DY: i32 = -230;
const BIND_ROWS_DY: i32 = BIND_TITLE + BIND_POP_DY + SLOT_PX;
const BIND_LABEL_GAP: i32 = 6;
const BIND_ROW_GAP: i32 = 24;
const SLOT_COLUMN_H: i32 = SLOT_PX + KEY_GAP + PROMPT_PX;
const BIND_ROW_H: i32 = TEXT + BIND_LABEL_GAP + SLOT_COLUMN_H + BIND_ROW_GAP;
const BIND_POP_DY: i32 = 10;
const BIND_INFO_DY: i32 = 8;
const PICK_MARGIN: i32 = 16;
const MINI: i32 = 3;
const MINI_W: i32 = grid.W * MINI;
const MINI_H: i32 = grid.H * MINI;
const MINI_PAD: i32 = 12;
/// Cells past the view a prop's shadow can reach into it from.
const CAST_MARGIN: i32 = @intFromFloat(@ceil(light.CAST_REACH));
const MINI_FRAME: i32 = look.HUD_BORDER_CUT;
const MINI_HERO_GROW: i32 = 1;
const SHOT_SEED: u64 = 0x5EED_1234;
const GOLD_LO: i32 = 3;
const GOLD_HI: i32 = 12;
const SHOTS_DIR = "shots";
const SHOTS_WORLDS = SHOTS_DIR ++ "/worlds";
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
/// From a spell cast round the hero to its blows landing; from one body a bolt leaps on from to the next.
const CAST_S: f32 = BUMP_LANDS;
const ZAP_S: f32 = 0.08;
const BUMP_PX: f32 = CELL_F * 0.35;
/// A walk due this close to the turn's last glide ending is not held for it.
const PACE_SLACK: f32 = 1e-4;
/// Ease-out-back's overshoot constant: 1.165 carries a slide 5% past its cell (1.70158, the usual one, 10%).
const SLIDE_BACK: f32 = 1.165;
/// `gen.build` rolls from the bare seed; without the salt the packs replay the floor's rolls.
const PLAY_SALT: u64 = 0x9E37_79B9_7F4A_7C15;

const CONFIRM = menu.CONFIRM;
const BACK = menu.BACK;
const CHANGE = menu.CHANGE;
const REMOVE = menu.REMOVE;
const BINDS = skillbar.BINDS;

comptime {
    std.debug.assert(@mod(CELL, look.SPRITE_PX) == 0);
    std.debug.assert(GLYPH <= CELL);
    std.debug.assert(SKILLS_W <= hud.SKILLS_MAX_W);
    std.debug.assert(hud.PLATE_PAD + SLOT_COLUMN_H <= hud.PLATE_H);
    std.debug.assert(font.isNative(look.labelPx(PROMPT_PX)));
}

pub const Mode = enum { play, aim, bind, dead, pause, inspect };

const Spot = union(enum) {
    life,
    mana,
    /// Of `skillbar.SLOTS`.
    slot: usize,
    status: fx.Status,
};

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

    fn rowOf(s: skillbar.Set) usize {
        return std.mem.indexOfScalar(skillbar.Set, skillbar.SETS, s).?;
    }
};

/// Picker cell 0 clears the slot; the rest are the class's acts in order. An empty slot opens it on the first act.
fn pickOf(kit: []const skillbar.Act, a: ?skillbar.Act) usize {
    return 1 + (std.mem.indexOfScalar(skillbar.Act, kit, a orelse kit[0]) orelse 0);
}

fn pickAct(kit: []const skillbar.Act, i: usize) ?skillbar.Act {
    return if (i == 0) null else kit[i - 1];
}

fn picksOf(kit: []const skillbar.Act) usize {
    return kit.len + 1;
}

const PICK_COLS: usize = @intCast(@divTrunc(SKILLS_W + SLOT_GAP, SLOT_STEP));

fn pickRows(n: usize) usize {
    return (n + PICK_COLS - 1) / PICK_COLS;
}

fn pickStep(i: usize, d: P, n: usize) usize {
    const at = mathx.wrap(i, d.x, n);
    const row = mathx.nudge(at / PICK_COLS, d.y, pickRows(n));
    return @min(row * PICK_COLS + at % PICK_COLS, n - 1);
}

fn pickWindow(top_y: i32, bottom_y: i32, n: usize, at: usize) menu.Window {
    const rows = pickRows(n);
    const room: usize = @intCast(@max(1, @divTrunc(bottom_y - SLOT_GAP - top_y - PICK_MARGIN, SLOT_STEP) + 1));
    return menu.Window.of(rows, at / PICK_COLS, room);
}

pub const Log = struct {
    pub const LINES: usize = 32;
    pub const COLS: usize = 96;
    lines: [LINES]menu.Note(COLS - 1) = @splat(.{}),
    head: usize = 0,
    n: usize = 0,

    pub fn say(self: *Log, comptime fmt: []const u8, args: anytype) void {
        self.lines[self.head].say(fmt, args);
        self.head = (self.head + 1) % LINES;
        self.n = @min(LINES, self.n + 1);
    }

    /// `back` 0 is the newest.
    pub fn line(self: *const Log, back: usize) ?[:0]const u8 {
        if (back >= self.n) return null;
        return self.lines[(self.head + LINES - 1 - back) % LINES].text();
    }
};

/// Presentation only: the hit already resolved when this was made.
pub const Shot = struct {
    flight: bow.Flight,
    glyph: u8,
    act: skillbar.Act = .shoot,
    t: f32 = 0,

    fn cell(self: Shot) ?P {
        const i: usize = @intFromFloat(self.t / FLIGHT_S);
        if (i >= self.flight.len) return null;
        return self.flight.path[i];
    }
};

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
    splashed: bool = false,
    /// Where a step taken mid-hop left the body, so it hops on from there instead of dropping to the floor.
    from_lift: f32 = 0,
    /// Pixels toward what a melee blow strikes, at the bump's height; null for a step.
    bump: ?rl.Vector2 = null,
    /// The glide still drawn while this one waits its turn.
    prior: ?Prior = null,

    /// A glide's motion, `ahead` seconds further through than the one it precedes.
    const Prior = struct { from: rl.Vector2, to: P, gait: look.Gait, from_lift: f32, bump: ?rl.Vector2, ahead: f32 };

    comptime {
        for (std.meta.fields(Glide)) |f| {
            const own = std.mem.eql(u8, f.name, "t") or std.mem.eql(u8, f.name, "splashed") or std.mem.eql(u8, f.name, "prior");
            std.debug.assert(own or @hasField(Prior, f.name));
        }
    }

    fn still(p: P, gait: look.Gait) Glide {
        var gl = Glide{ .from = cellPx(p), .to = p, .t = 0, .gait = gait };
        gl.t = gl.span();
        return gl;
    }

    fn rest(a: *const actor.Actor) Glide {
        return still(a.at, look.gait(a.kind));
    }

    fn toward(self: Glide, p: P, t: f32) Glide {
        var then = self;
        if (t < 0) then.t -= t;
        var prior: ?Prior = null;
        if (t < 0 and self.left() > 0) {
            var was: Prior = undefined;
            inline for (std.meta.fields(Prior)) |f| {
                if (comptime !std.mem.eql(u8, f.name, "ahead")) @field(was, f.name) = @field(self, f.name);
            }
            was.ahead = self.t - t;
            prior = was;
        }
        return .{ .from = then.now(), .to = p, .t = t, .gait = self.gait, .from_lift = then.height(), .prior = prior };
    }

    fn waiting(self: Glide) ?Glide {
        if (self.t >= 0) return null;
        const p = self.prior orelse return null;
        var gl = Glide{ .from = undefined, .to = undefined, .t = self.t + p.ahead, .gait = undefined };
        inline for (std.meta.fields(Prior)) |f| {
            if (comptime !std.mem.eql(u8, f.name, "ahead")) @field(gl, f.name) = @field(p, f.name);
        }
        return gl;
    }

    fn bumping(self: Glide, at: P, t: f32) Glide {
        const d = at.sub(self.to);
        const bump = rl.Vector2{ .x = @as(f32, @floatFromInt(d.x)) * BUMP_PX, .y = @as(f32, @floatFromInt(d.y)) * BUMP_PX };
        var gl = self.toward(self.to, t);
        gl.bump = bump;
        return gl;
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

    fn left(self: Glide) f32 {
        return self.span() - self.t;
    }

    /// `t` is below 0 while the glide waits its turn.
    fn done(self: Glide) f32 {
        return std.math.clamp(self.t / self.span(), 0, 1);
    }

    fn now(self: Glide) rl.Vector2 {
        if (self.waiting()) |w| return w.now();
        const at = self.ground();
        const b = self.bump orelse return at;
        const k = bumpOf(self.done());
        return .{ .x = at.x + b.x * k, .y = at.y + b.y * k };
    }

    /// Where the body is, its bump aside: the camera follows this.
    fn ground(self: Glide) rl.Vector2 {
        if (self.waiting()) |w| return w.ground();
        const k = switch (self.motion()) {
            .hop, .bump => self.done(),
            .slide => overshoot(self.done()),
        };
        const to = cellPx(self.to);
        return .{ .x = mathx.lerpF(self.from.x, to.x, k), .y = mathx.lerpF(self.from.y, to.y, k) };
    }

    fn height(self: Glide) f32 {
        if (self.waiting()) |w| return w.height();
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
    return 1 - mathx.smoothstep(BUMP_HIT, 1, k);
}

/// Penner's ease-out-back.
fn overshoot(k: f32) f32 {
    const u = k - 1;
    return 1 + (SLIDE_BACK + 1) * u * u * u + SLIDE_BACK * u * u;
}

pub const Facing = enum { right, left };

const Bite = struct { blow: enum { hurt, kill, burst }, after: fx.After };

/// Presentation debts land at the body's stagger, or after the hero when it has no stagger.
const Owed = struct {
    bit: ?Bite = null,
    gassed: ?Harm = null,
    burned: ?Harm = null,
    bled: ?Harm = null,
    worn: ?fx.After = null,

    fn any(o: Owed) bool {
        inline for (std.meta.fields(Owed)) |f| {
            if (@field(o, f.name) != null) return true;
        }
        return false;
    }
};

comptime {
    std.debug.assert(fx.DUE >= actor.MAX * (std.meta.fields(Owed).len + 1) + @max(2, chain.JUMPS));
}

const Harm = struct { kill: bool, after: fx.After };

/// The ticks a body's turn has run, which a half split off it mid-turn has had too.
const Ran = std.EnumSet(Tick);
const Tick = std.meta.FieldEnum(Owed);

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

const Flasks = std.EnumArray(flask.Kind, flask.Flask);

pub const Game = struct {
    mode: Mode = .play,
    paused_from: Mode = .play,
    pause_menu: menu.Menu = .{},
    back: Back = .title,
    exit: ?Exit = null,
    name: heroes.Name = heroes.DEFAULT.unnamed(),
    /// Set before a run begins.
    class: heroes.Class = heroes.DEFAULT,
    /// A run in a save slot: death ends it, and the way out of the death screen is the way back.
    permadeath: bool = false,
    clock: day.Clock = .{},
    outdoors: bool = false,
    hour_shown: f32 = day.Clock.hour(.{}),
    /// Kept across runs, never saved.
    unkillable: bool = false,
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
    mana: i32 = heroes.MANA,
    flasks: Flasks = .initFill(.{}),
    /// The flasks as the hud has them: a kill's refill shows once the kill is drawn.
    flasks_shown: Flasks = .initFill(.{}),
    /// Mana a mana shield took for blows the picture has still to land, so the orb drops as they do.
    mana_held: i32 = 0,
    /// Turns until each can be used again.
    cooldown: std.EnumArray(skillbar.Act, u8) = .initFill(0),
    /// The hero stepped or leapt since the last turn ended, which tears a bleed wider.
    stepped: bool = false,
    displaced: std.StaticBitSet(actor.MAX) = .initEmpty(),
    log: Log = .{},
    st: input.State = .{},
    bar: skillbar.Bar = .{},
    binds: Binds = .{},
    aim_by: input.Button = .x,
    aim_act: skillbar.Act = .shoot,
    aim_set: skillbar.Set = .primary,
    mark: P = .{ .x = 0, .y = 0 },
    /// Kept between inspections, so the next opens where the last left off.
    inspecting: Spot = .{ .slot = 0 },
    /// World pixels, eased toward the archer. Nothing in the simulation reads it.
    cam: rl.Vector2 = .{ .x = 0, .y = 0 },
    screen: P = .{ .x = WINDOW_W, .y = WINDOW_H },
    /// The framebuffer a frame draws into: the window's, or a texture's. Asking GL stalls it.
    framebuffer: u32 = 0,
    shot: ?Shot = null,
    /// Indexed by pool slot.
    glide: [actor.MAX]Glide = undefined,
    /// Indexed by pool slot. Presentation only: the last way a body stepped, struck or aimed across.
    facing: [actor.MAX]Facing = @splat(.right),
    turning: [actor.MAX]?Turning = @splat(null),
    /// The living foes as of the last turn, nearest the archer first: the order they act and are drawn acting in.
    order: [actor.MAX]u16 = undefined,
    order_n: usize = 0,
    /// Seconds until the last turn's slowest glide, arrow or flash ends; a walk waits for it.
    busy: f32 = 0,
    /// A walk that came due while `busy`.
    pending: ?mathx.Dir = null,
    /// Seconds in, when the blow, shot or leap the hero dealt this turn without stepping lands: the stagger's first place.
    lead: ?f32 = null,
    owed: [actor.MAX]Owed = @splat(.{}),
    ran: [actor.MAX]Ran = @splat(Ran.initEmpty()),
    /// Indexed by pool slot: the body as the picture has it, which catches up with it as each blow on it lands.
    pictured: [actor.MAX]fx.Body = undefined,
    /// The blows dealt so far, so the picture takes them in the order they were dealt.
    seq: u64 = 0,
    /// Indexed by pool slot: the slot a slime split off, until the blow that split it lands.
    split_from: [actor.MAX]?usize = @splat(null),
    fx: fx.Fx = .{},
    vignette: vignette.Vignette = .{},
    rain: weather.Weather = .{},
    mini: Minimap = .{},
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

    pub fn archer(self: *Game) ?*actor.Actor {
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
    toDefaults(g, &.{ "visited", "node", "outdoors", "pool", "hero", "clock" });
    g.world = w;
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
    var carried = actor.Actor.of(g.class.kind(), at);
    if (g.archer()) |h| carried = h.*;
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
        spawnHero(g, to);
        switch (w.node[n].plan) {
            .procgen => |*pg| pack.place(&g.lv, &g.pool, &g.rng, to, &pg.foes),
            .bespoke => for (placing) |f| {
                if (g.lv.vacant(f.at)) _ = g.pool.spawn(&g.lv, actor.Actor.of(f.kind, f.at));
            },
        }
    }
    const h = g.archer().?;
    carried.at = h.at;
    h.* = carried;
    g.unsaved = true;
    freshTurn(g);
    settle(g);
}

fn rollOf(run: u64, n: usize) u64 {
    return std.hash.Wyhash.hash(run, std.mem.asBytes(&n));
}

fn leadsTo(g: *const Game, p: P) ?atlas.Link {
    const w = g.world orelse return null;
    const k = g.lv.doorAt(p) orelse return null;
    return w.door(.{ .node = g.node, .door = k }).to;
}

fn goThrough(g: *Game, l: atlas.Link) void {
    g.visits[g.node] = Visit.of(g);
    g.visited.set(g.node);
    const walk = g.pending;
    const hero = heroSlot(g).?;
    const facing = g.facing[hero];
    enter(g, l.node, g.world.?.door(l).at);
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
    toDefaults(g, &.{ "pool", "facing" });
    g.hero = g.pool.spawn(&g.lv, actor.Actor.of(g.class.kind(), at));
}

fn reset(g: *Game, hero: P) void {
    spawnHero(g, hero);
    freshRun(g);
    freshTurn(g);
}

fn toDefaults(g: *Game, comptime fields: []const []const u8) void {
    @setEvalBranchQuota(20_000);
    inline for (fields) |f| @field(g, f) = comptime std.meta.fieldInfo(Game, @field(std.meta.FieldEnum(Game), f)).defaultValue().?;
}

fn freshRun(g: *Game) void {
    toDefaults(g, &.{ "kills", "gold", "mana", "mana_held", "flasks", "flasks_shown", "cooldown", "stepped", "log", "mode" });
    g.vignette.clear();
}

fn freshTurn(g: *Game) void {
    toDefaults(g, &.{ "shot", "travel", "order_n", "busy", "pending", "lead", "owed", "split_from", "turning", "displaced" });
    g.fx.clear();
    g.cloud.clear();
}

fn settle(g: *Game) void {
    g.art_ready = false;
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

pub fn resumeRun(g: *Game) void {
    gen.restoreShapes(&g.lv);
    var visits = g.visited.iterator(.{});
    while (visits.next()) |n| gen.restoreShapes(&g.visits[n].lv);
    toDefaults(g, &.{ "mode", "exit", "unsaved" });
    g.outdoors = outdoorsNow(g);
    freshTurn(g);
    settle(g);
    if (heroShown(g)) |h| g.vignette.settle(h.hp, h.max) else g.vignette.clear();
}

fn outdoorsNow(g: *const Game) bool {
    const w = g.world orelse return false;
    return w.node[g.node].outdoor();
}

pub fn freshSeed() u64 {
    return @bitCast(std.time.milliTimestamp());
}

fn castSight(g: *Game, from: P) void {
    var carried: [actor.MAX]lume.Source = undefined;
    var n: usize = 0;
    for (g.pool.slice(), 0..) |a, i| {
        const r = actor.row(a.kind).light;
        if (!a.alive or r <= 0) continue;
        carried[n] = .{ .at = if (actor.Pool.idOf(i) == g.hero) from else a.at, .reach = r };
        n += 1;
    }
    const sight = heroRow(g).sight;
    lume.see(&g.lv, from, sight, lume.skyReach(g.outdoors, g.clock.hour(), sight), carried[0..n]);
    g.mini.stale = true;
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
            const s = heroBump(g, h.at, to, late);
            switch (g.class) {
                inline else => |c| {
                    const blow = comptime actor.row(c.kind()).blow.strike;
                    if (w != grid.NO_ONE) wound(g, w, blow.roll(&g.rng), blow.verb, s) else smash(g, to, blow.verb, s);
                },
            }
            g.lead = s.wait;
        },
        .step => heroTo(g, to),
        .blocked => return,
    }
    turnToward(g, g.hero, d.delta().x);
    endTurn(g);
}

/// The hero's bump from `from` at `at`, begun `late` seconds ago, and its blow, landing at the bump's height.
fn heroBump(g: *Game, from: P, at: P, late: f32) Stroke {
    const i = heroSlot(g).?;
    _ = glideHeld(g, i, g.glide[i].bumping(at, late));
    return .{ .from = from, .wait = BUMP_LANDS - late };
}

fn heroTo(g: *Game, to: P) void {
    g.pool.move(&g.lv, g.hero, to);
    g.stepped = true;
    g.travel = leadsTo(g, to);
}

fn openAim(g: *Game, by: input.Button, act: skillbar.Act) void {
    const h = g.archer() orelse return;
    aimAt(g, by, act, h.at, bow.pick(&g.lv, &g.pool, h.at));
}

fn openLeap(g: *Game, by: input.Button, act: skillbar.Act) void {
    const h = g.archer() orelse return;
    g.mark = h.at;
    aiming(g, by, act);
}

fn openSwing(g: *Game, by: input.Button, act: skillbar.Act) void {
    const h = g.archer() orelse return;
    var mark: ?P = null;
    for (mathx.ALL_DIRS) |d| {
        const p = h.at.add(d.delta());
        if (!act.aimable(&g.lv, h.at, p)) continue;
        const foe = if (g.pool.get(g.lv.who(p))) |a| a.foe() else false;
        if (foe or mark == null) mark = p;
        if (foe) break;
    }
    aimAt(g, by, act, h.at, mark);
}

fn aimAt(g: *Game, by: input.Button, act: skillbar.Act, from: P, mark: ?P) void {
    g.mark = mark orelse {
        g.log.say("Nothing in reach.", .{});
        return;
    };
    turnToward(g, g.hero, g.mark.x - from.x);
    aiming(g, by, act);
}

fn aiming(g: *Game, by: input.Button, act: skillbar.Act) void {
    g.aim_by = by;
    g.aim_act = act;
    g.mode = .aim;
}

const Blocked = enum { cooling, mana, empty };

fn blocked(g: *const Game, act: skillbar.Act, flasks: *const Flasks, mana: i32) ?Blocked {
    if (g.cooldown.get(act) > 0) return .cooling;
    if (act.flaskOf()) |k| {
        if (!flasks.get(k).full()) return .empty;
    }
    if (mana < act.cost()) return .mana;
    return null;
}

fn manaShown(g: *const Game) i32 {
    return @min(heroes.MANA, g.mana + g.mana_held);
}

fn ready(g: *Game, act: skillbar.Act) bool {
    if (!quiet(g)) return false;
    switch (blocked(g, act, &g.flasks, g.mana) orelse return true) {
        .cooling => {
            const left = g.cooldown.get(act);
            g.log.say("{s} is ready in {d} turn{s}.", .{ act.name(), left, plural(left) });
        },
        .mana => g.log.say("{s} needs {d} mana.", .{ act.name(), act.cost() }),
        .empty => g.log.say("{s} is empty.", .{act.name()}),
    }
    return false;
}

fn spend(g: *Game, act: skillbar.Act) void {
    g.mana -= act.cost();
    g.cooldown.set(act, act.cooldown());
}

fn plural(n: u8) []const u8 {
    return if (n == 1) "" else "s";
}

fn aimable(g: *const Game, from: P, to: P) bool {
    return g.aim_act.aimable(&g.lv, from, to);
}

fn leap(g: *Game, from: P, act: skillbar.Act) void {
    const to = g.mark;
    heroTo(g, to);
    g.glide[heroSlot(g).?] = Glide.rest(g.archer().?);
    turnToward(g, g.hero, to.x - from.x);
    g.fx.juke(from, to);
    if (g.travel != null) holdUntil(g, fx.JUKE_S);
    g.unsaved = true;
    castSight(g, to);
    if (act.free()) return;
    g.lead = 0;
    endTurn(g);
}

/// Its recovery starts at the end of the turn the drink takes.
fn drink(g: *Game, act: skillbar.Act, k: flask.Kind) void {
    const h = g.archer() orelse return;
    spend(g, act);
    g.flasks.getPtr(k).drink(switch (k) {
        .life => flask.lifeOf(h.max),
        .mana => flask.MANA_GAIN,
    });
    g.flasks_shown.set(k, g.flasks.get(k));
    g.log.say("{s} drinks a {s} flask.", .{ g.name.text(), @tagName(k) });
    endTurn(g);
}

fn recover(g: *Game) void {
    const h = g.archer() orelse return;
    const hp = h.hp;
    g.mana = @min(heroes.MANA, g.mana + heroes.MANA_REGEN);
    for (std.enums.values(flask.Kind)) |k| {
        const n = g.flasks.getPtr(k).tick();
        switch (k) {
            .life => h.hp = @min(h.max, h.hp + n),
            .mana => g.mana = @min(heroes.MANA, g.mana + n),
        }
    }
    if (h.hp != hp) settleNow(g, heroSlot(g).?);
}

const Use = struct { act: skillbar.Act, by: input.Button, set: skillbar.Set = .primary };

/// Since PoE2 0.2.0, pressing the modifier while a button is already held fires that button's secondary skill.
fn usedSkill(g: *Game) ?Use {
    const set = g.bar.active(g.st.down);
    for (skillbar.SLOTS) |b| {
        if (!g.st.hit(b)) continue;
        return skillOn(g, set, b) orelse continue;
    }
    const m = g.bar.modifier orelse return null;
    if (!g.st.hit(m)) return null;
    for (skillbar.SLOTS) |b| {
        if (b == m or !g.st.held(b)) continue;
        return skillOn(g, .secondary, b) orelse continue;
    }
    return null;
}

fn skillOn(g: *const Game, set: skillbar.Set, b: input.Button) ?Use {
    const a = g.bar.at(.{ .set = set, .button = b }) orelse return null;
    return if (a == .secondary) null else .{ .act = a, .by = b, .set = set };
}

fn useSkill(g: *Game, u: Use) void {
    if (!quiet(g)) return;
    const r = u.act.reticle() orelse return switch (u.act) {
        .wait => endTurn(g),
        .secondary => unreachable,
        inline else => |a| if (comptime a.reticle() != null)
            unreachable
        else if (comptime a.flaskOf()) |k| {
            if (ready(g, a)) drink(g, a, k);
        } else if (ready(g, a)) spell(g, a),
    };
    if (!ready(g, u.act)) return;
    g.aim_set = u.set;
    switch (r) {
        .bow => openAim(g, u.by, u.act),
        .leap => openLeap(g, u.by, u.act),
        .swing => openSwing(g, u.by, u.act),
        .rush => openRush(g, u.by, u.act),
    }
}

fn spell(g: *Game, comptime act: skillbar.Act) void {
    const M = skillbar.Act.skill(act);
    const h = g.archer() orelse return;
    spend(g, act);
    g.log.say("{s} casts {s}.", .{ g.name.text(), act.name() });
    if (comptime act.surrounds()) {
        const s = Stroke{ .from = h.at, .wait = CAST_S };
        holdUntil(g, s.wait);
        areaHit(g, act, h.at, M.around(&g.lv, h.at), s, null, false);
        g.lead = s.wait;
    } else if (comptime act.wards()) {
        h.ward.raise();
        settleNow(g, heroSlot(g).?);
        g.lead = 0;
    } else @compileError(@tagName(act) ++ " has no reticle and no use");
    endTurn(g);
}

const Struck = struct {
    id: [actor.MAX]u16 = undefined,
    n: usize = 0,

    fn slice(self: *const Struck) []const u16 {
        return self.id[0..self.n];
    }
};

/// The living foes in `area`, taken before any blow so a half split into it is spared.
fn foesIn(g: *Game, area: glacial.Cone) Struck {
    var out = Struck{};
    for (g.pool.slice(), 0..) |a, i| {
        if (!a.alive or !a.foe() or !area.has(a.at)) continue;
        out.id[out.n] = actor.Pool.idOf(i);
        out.n += 1;
    }
    return out;
}

fn openRush(g: *Game, by: input.Button, act: skillbar.Act) void {
    const h = g.archer() orelse return;
    var near = bow.Nearest{ .from = h.at };
    var cells = grid.Cells.around(h.at, act.reach());
    while (cells.next()) |p| {
        if (act.aimable(&g.lv, h.at, p)) near.offer(p);
    }
    aimAt(g, by, act, h.at, near.best);
}

fn rush(g: *Game, from: P, act: skillbar.Act) void {
    switch (act) {
        inline else => |a| if (comptime a.reticle() != .rush) unreachable else {
            const M = skillbar.Act.skill(a);
            const d = M.wayTo(from, g.mark).?;
            const stop = M.stop(from, g.mark);
            const i = heroSlot(g).?;
            heroTo(g, stop);
            const s = Stroke{ .from = stop, .wait = glideHeld(g, i, g.glide[i].toward(stop, 0)) };
            knock(g, a, d, s);
            turnToward(g, g.hero, d.delta().x);
            g.lead = s.wait;
        },
    }
    endTurn(g);
}

/// The press that closes on `BINDS` is spent, so holding it on does not open the binds again.
fn closed(st: *input.State) bool {
    if (!st.hit(BINDS)) return menu.backed(st);
    st.spend(BINDS);
    return true;
}

fn openBinds(g: *Game) void {
    g.binds.menu = .browse;
    g.mode = .bind;
}

fn bindStep(g: *Game) void {
    const b = &g.binds;
    const here = b.slot();
    const kit = skillbar.kit(g.class);
    const was = g.bar;
    defer if (!std.meta.eql(was, g.bar)) {
        g.unsaved = true;
    };
    switch (b.menu) {
        .browse => {
            if (closed(&g.st)) {
                g.mode = .play;
            } else if (g.st.hit(CONFIRM)) {
                b.menu = if (g.bar.at(here) != null) .{ .carry = here } else .{ .pick = pickOf(kit, null) };
            } else if (g.st.hit(CHANGE)) {
                b.menu = .{ .pick = pickOf(kit, g.bar.at(here)) };
            } else if (g.st.hit(REMOVE)) {
                g.bar.clear(here);
            } else if (g.st.walk) |d| {
                b.move(d);
            }
        },
        .pick => |i| {
            if (menu.backed(&g.st)) {
                b.menu = .browse;
            } else if (g.st.hit(CONFIRM)) {
                if (pickAct(kit, i)) |a| g.bar.bind(here, a) else g.bar.clear(here);
                b.menu = .browse;
            } else if (g.st.walk) |d| {
                b.menu = .{ .pick = pickStep(i, d.delta(), picksOf(kit)) };
            }
        },
        .carry => |from| {
            if (menu.backed(&g.st)) {
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
    switch (g.aim_act.reticle().?) {
        .leap, .rush => if (!juke.inReach(h.at, to, g.aim_act.reach()) or !grid.Level.inside(to)) return,
        .bow => {
            if (to.eq(h.at)) to = to.add(d.delta());
            if (!bow.aimable(&g.lv, h.at, to)) return;
        },
        .swing => to = h.at.add(d.delta()),
    }
    g.mark = to;
    turnToward(g, g.hero, to.x - h.at.x);
}

fn confirmAim(g: *Game) void {
    const h = g.archer() orelse return;
    const act = g.aim_act;
    if (!ready(g, act)) return;
    const reticle = act.reticle().?;
    if (!aimable(g, h.at, g.mark)) {
        switch (reticle) {
            .bow => g.log.say("Can't shoot there.", .{}),
            .leap => g.log.say("{s} needs a visible, empty landing within {d} tiles.", .{ act.name(), act.reach() }),
            .swing => g.log.say("Nothing to strike there.", .{}),
            .rush => g.log.say("{s} needs a foe in a straight open line {d} to {d} tiles away.", .{ act.name(), act.nearest(), act.reach() }),
        }
        return;
    }
    g.mode = .play;
    spend(g, act);
    const from = h.at;
    switch (reticle) {
        .bow => loose(g, from, act),
        .leap => leap(g, from, act),
        .swing => swing(g, from, act),
        .rush => rush(g, from, act),
    }
}

fn loose(g: *Game, from: P, act: skillbar.Act) void {
    const to = g.mark;
    const f = bow.fly(&g.lv, from, to);
    const glyph = if (act.bolt() != null) look.SPARK_GLYPH else look.arrow(to.x - from.x, to.y - from.y);
    g.shot = .{ .flight = f, .glyph = glyph, .act = act };
    holdUntil(g, flown(f.len));
    const s = Stroke{ .from = from, .wait = flown(f.len -| 1), .fire = act.element() == .fire };
    g.lead = s.wait;
    if (f.struck) |hit| switch (act) {
        inline else => |a| if (comptime a.reticle() != .bow) unreachable else if (comptime a.bursts()) burstHit(g, a, hit, f.impact().?, s) else switch (hit) {
            .body => |id| if (comptime a.chains())
                chainHit(g, a, id, s)
            else if (comptime !a.afflicts())
                wound(g, id, rollArrow(&g.rng, a, true).physical, SHOOT, s)
            else
                arrowHit(g, id, rollArrow(&g.rng, a, true), a, s),
            .barrel => |p| smash(g, p, barrelVerb(a), s),
        },
    } else g.log.say("{s}'s {s} finds nothing.", .{ g.name.text(), act.bolt() orelse "arrow" });
    endTurn(g);
}

fn barrelVerb(comptime act: skillbar.Act) []const u8 {
    return if (comptime act.bolt() != null) skillbar.Act.skill(act).VERB else SHOOT;
}

/// Choose targets before striking; each jump delays the next hit and the foes' stagger.
fn chainHit(g: *Game, comptime act: skillbar.Act, first: u16, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const c = M.chain(&g.lv, &g.pool, first);
    var from = s.from;
    var wait = s.wait;
    for (c.slice(), 0..) |id, k| {
        const slot = actor.Pool.slot(id);
        const at = g.pool.items[slot].at;
        if (k > 0) {
            g.fx.zap(wait, .{ .from = mathx.centre(from), .to = mathx.centre(at) });
            wait += ZAP_S;
        }
        arrowHit(g, id, rollArrow(&g.rng, act, true), act, .{ .from = from, .wait = wait });
        from = at;
    }
    holdUntil(g, wait);
    g.lead = wait;
}

fn swing(g: *Game, from: P, act: skillbar.Act) void {
    const d = mathx.dirTo(from, g.mark).?;
    const s = heroBump(g, from, g.mark, 0);
    switch (act) {
        inline else => |a| if (comptime a.reticle() != .swing)
            unreachable
        else if (comptime a.sweeps())
            sweep(g, skillbar.Act.skill(a), s)
        else if (comptime a.knocks())
            knock(g, a, d, s)
        else
            @compileError(@tagName(a) ++ " swings at nothing"),
    }
    turnToward(g, g.hero, d.delta().x);
    g.lead = s.wait;
    endTurn(g);
}

/// Every body and barrel in the arc round the mark; the bodies are taken first, so a half split into it is spared.
fn sweep(g: *Game, comptime M: type, s: Stroke) void {
    const arc = M.arc(&g.lv, s.from, g.mark);
    var struck: [M.WIDTH]u16 = undefined;
    for (arc.cells[0..arc.n], struck[0..arc.n]) |p, *w| w.* = g.lv.who(p);
    for (arc.cells[0..arc.n], struck[0..arc.n]) |p, w| {
        if (w != grid.NO_ONE) wound(g, w, M.roll(&g.rng), M.VERB, s) else smash(g, p, M.VERB, s);
    }
}

fn knock(g: *Game, comptime act: skillbar.Act, d: mathx.Dir, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const to = s.from.add(d.delta());
    const id = g.lv.who(to);
    if (id == grid.NO_ONE) return smash(g, to, M.VERB, s);
    const a = g.pool.get(id).?;
    const dmg = M.roll(&g.rng);
    const takes = if (comptime act.afflicts()) afflicted(g, a, M, dmg < a.hp, 0) else false;
    wound(g, id, dmg, M.VERB, s);
    if (g.pool.get(id) == null) return;
    const name = actor.row(a.kind).name;
    const back = if (a.pin.turns > 0) null else M.knocked(&g.lv, a.at, d, id);
    if (back) |b| {
        const i = actor.Pool.slot(id);
        g.pool.move(&g.lv, id, b);
        g.displaced.set(i);
        _ = glideHeld(g, i, g.glide[i].toward(b, -s.wait));
        sayAt(g, b, "The {s} is knocked back.", .{name});
    }
    if (takes) sayTakes(g, M, a.at, name);
}

fn sayTakes(g: *Game, comptime M: type, at: P, name: []const u8) void {
    sayAt(g, at, "The {s} " ++ M.TAKES ++ "!", .{name});
}

/// Rolled only for a blow that `lands` and leaves the body alive, before the blow, so a half split off takes it too.
fn afflicted(g: *Game, a: *actor.Actor, comptime M: type, lands: bool, resist: i16) bool {
    const takes = lands and M.procs(&g.rng, resist);
    if (takes) M.afflict(a, &g.rng);
    return takes;
}

const SHOOT = bow.VERB;
const IT_DIES = " It dies.";

/// Roll physical before elemental damage to preserve the seeded shot sequence.
fn rollArrow(rng: *mathx.Rng, comptime act: skillbar.Act, body: bool) damage.Damage {
    var hit = damage.Damage{ .physical = if (body and comptime act.bolt() == null) bow.roll(rng) else 0 };
    if (comptime act.element() != null) hit.elements.set(skillbar.Act.arrow(act).ELEMENT, skillbar.Act.arrow(act).roll(rng));
    return hit;
}

fn arrowHit(g: *Game, id: u16, blow: damage.Damage, comptime act: skillbar.Act, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const el = comptime act.element();
    const a = g.pool.get(id) orelse return;
    const dealt = blow.total(a.resists);
    const at = a.at;
    const name = actor.row(a.kind).name;
    const lands = if (el) |e| blow.afflicts(a.resists, e, a.hp) else dealt < a.hp;
    const takes = afflicted(g, a, M, lands, if (el) |e| a.resists.get(e) else 0);
    if (dealt > 0) wound(g, id, dealt, M.VERB, s);
    if (takes) sayTakes(g, M, at, name);
}

fn burstHit(g: *Game, comptime act: skillbar.Act, hit: bow.Hit, impact: P, s: Stroke) void {
    const M = skillbar.Act.arrow(act);
    const direct: ?u16 = switch (hit) {
        .body => |id| id,
        .barrel => null,
    };
    areaHit(g, act, impact, M.burst(&g.lv, s.from, impact), s, direct, hit == .barrel);
}

fn areaHit(g: *Game, comptime act: skillbar.Act, at: P, area: glacial.Cone, s: Stroke, direct: ?u16, barrel: bool) void {
    const struck = foesIn(g, area);
    g.fx.burst(s.wait, .{ .at = at, .area = area, .col = look.arrowInk(act) });
    const rolled = rollArrow(&g.rng, act, direct != null);
    if (barrel) smash(g, at, barrelVerb(act), s);
    for (struck.slice()) |id| {
        var blow = rolled;
        if (direct != id) blow.physical = 0;
        arrowHit(g, id, blow, act, s);
    }
}
const HERO = actor.HERO;

fn heroRow(g: *const Game) actor.Row {
    return actor.row(g.class.kind());
}

/// Where a blow came from, and how long until the picture reaches it.
const Stroke = struct { from: P, wait: f32, fire: bool = false };

fn strike(g: *Game, slot: ?usize, s: Stroke, at: P, lethal: bool, after: ?fx.After) void {
    const len = mathx.distEuclid(at, s.from);
    const dir: ?[2]f32 = if (len == 0) null else .{ @as(f32, @floatFromInt(at.x - s.from.x)) / len, @as(f32, @floatFromInt(at.y - s.from.y)) / len };
    const kind: ?actor.Kind = if (slot) |i| g.pool.items[i].kind else null;
    if (slot == null or slot == heroSlot(g) or g.lv.isLit(at)) {
        g.fx.strike(s.wait, .{ .slot = slot, .at = mathx.centre(at), .dir = dir, .matter = fx.matterOf(kind), .lethal = lethal, .after = after, .fire = s.fire });
        flashes(g, s.wait);
    } else if (after) |a| g.fx.settle(s.wait, .{ .slot = slot.?, .after = a });
    const k = kind orelse return;
    if (lethal and k.bursts()) g.cloud.hold(s.wait);
}

fn sting(g: *Game, wait: f32, s: fx.Sting) void {
    g.fx.sting(wait, s);
    flashes(g, wait);
}

fn snap(g: *Game, slot: usize) fx.Body {
    g.seq += 1;
    return fx.Body.of(g.pool.items[slot], g.seq);
}

fn settleNow(g: *Game, slot: usize) void {
    g.fx.settle(0, .{ .slot = slot, .after = .{ .body = snap(g, slot) } });
}

fn flashes(g: *Game, wait: f32) void {
    holdUntil(g, wait + fx.FLASH_S);
}

fn holdUntil(g: *Game, t: f32) void {
    g.busy = @max(g.busy, t);
}

/// Holds the turn until the glide ends; returns its remaining seconds.
fn glideHeld(g: *Game, slot: usize, gl: Glide) f32 {
    g.glide[slot] = gl;
    holdUntil(g, gl.left());
    return gl.left();
}

fn smash(g: *Game, p: P, comptime verb: []const u8, s: Stroke) void {
    if (!g.lv.breakBarrel(p)) return;
    const gold = g.rng.range(GOLD_LO, GOLD_HI);
    g.gold += gold;
    g.log.say("{s} " ++ verb ++ " the barrel. It breaks: {d} gold.", .{ g.name.text(), gold });
    strike(g, null, s, p, true, null);
}

fn wound(g: *Game, id: u16, dmg: i32, comptime verb: []const u8, s: Stroke) void {
    const a = g.pool.get(id) orelse return;
    const kind = a.kind;
    const at = a.at;
    const i = actor.Pool.slot(id);
    const name = actor.row(kind).name;
    const h = hurt(g, id, dmg);
    const lethal = h.lethal;
    sayAt(g, at, "{s} " ++ verb ++ " the {s} for {d}.{s}", .{ g.name.text(), name, dmg, if (lethal) IT_DIES else "" });
    strike(g, i, s, at, lethal, afterBlow(g, id, h));
    if (lethal) fell(g, id);
}

fn afterBlow(g: *Game, id: u16, h: Hurt) fx.After {
    const other = if (h.lethal) null else split(g, id);
    return .{ .body = snap(g, actor.Pool.slot(id)), .reveals = other, .mana = h.mana };
}

/// The new slime is not drawn until the blow that split it lands; the new slot, if it split.
fn split(g: *Game, id: u16) ?usize {
    const i = actor.Pool.slot(id);
    const name = actor.row(g.pool.items[i].kind).name;
    const other = g.pool.split(&g.lv, id, &g.rng) orelse return null;
    const o = actor.Pool.slot(other);
    const b = g.pool.items[o];
    g.split_from[o] = i;
    g.ran[o] = g.ran[i];
    g.pictured[o] = fx.Body.of(b, g.seq);
    g.glide[o] = Glide.rest(&b);
    g.facing[o] = if (g.turning[i]) |t| t.to else g.facing[i];
    sayAt(g, g.pool.items[i].at, "The {s} splits in two!", .{name});
    return o;
}

fn fell(g: *Game, id: u16) void {
    const fallen = actor.Pool.slot(id);
    const kind = g.pool.items[fallen].kind;
    const at = g.pool.items[fallen].at;
    const name = actor.row(kind).name;
    g.kills += 1;
    for (&g.flasks.values) |*f| f.fill(flask.PER_KILL);
    if (kind.bursts()) {
        g.lv.addGas(at, gas.BURST);
        sayAt(g, at, "The {s} bursts, leaving a cloud of caustic gas!", .{name});
    }
    const family = kind.family();
    if (g.pool.tally(family).left == 0) g.log.say("The last {s} is dead.", .{actor.row(family).name});
    scare(g, fallen);
}

fn scare(g: *Game, fallen: usize) void {
    const at = g.pool.items[fallen].at;
    for (g.pool.slice(), 0..) |*a, i| {
        const row = actor.row(a.kind);
        if (!a.alive or !row.flees or mathx.dist(a.at, at) > actor.FRIGHT_REACH or !grid.clearLine(&g.lv, a.at, at)) continue;
        const steady = a.fright == 0;
        a.fright = actor.FLEE_TURNS;
        a.awake = true;
        if (steady) {
            sayAt(g, a.at, "The {s} flees in terror!", .{row.name});
            g.fx.frighten(i, fallen);
        }
    }
}

fn sayAt(g: *Game, at: P, comptime fmt: []const u8, args: anytype) void {
    if (g.lv.isLit(at)) g.log.say(fmt, args);
}

fn heroDies(g: *Game) void {
    g.log.say("{s} dies.", .{g.name.text()});
    g.mode = .dead;
}

/// Brogue's turn order, then the archer's sight again, for a light a foe carries has moved with it.
fn endTurn(g: *Game) void {
    const h = g.archer() orelse return;
    g.unsaved = true;
    g.clock.turn();
    recover(g);
    for (&g.cooldown.values) |*c| c.* -|= 1;
    defer {
        for (g.pool.slice()) |*a| a.settle();
        g.ran = @splat(Ran.initEmpty());
        g.displaced = .initEmpty();
    }
    castSight(g, h.at);
    g.flowed = false;
    orderFoes(g, h.at);
    harmAfter(g, g.hero, g.stepped);
    g.stepped = false;
    if (g.mode == .dead) return;
    gas.turn(&g.lv, &g.rng);
    for (g.pool.slice()) |*a| {
        if (a.alive and a.foe()) a.clock.pass(actor.row(a.kind).pace);
    }
    for (g.order[0..g.order_n]) |id| {
        const i = actor.Pool.slot(id);
        const was = g.pool.items[i].at;
        foeTurn(g, id);
        if (g.mode == .dead) return;
        harmAfter(g, id, !g.pool.items[i].at.eq(was));
    }
    var i: usize = 0;
    while (i < g.pool.n) : (i += 1) {
        const a = g.pool.items[i];
        if (!a.alive or !a.waits) continue;
        const id = actor.Pool.idOf(i);
        _ = wearTurn(g, id);
        harmAfter(g, id, false);
    }
    if (g.archer()) |a| {
        a.ward.wear();
        castSight(g, a.at);
    }
}

const Hurt = struct { dmg: i32, lethal: bool, mana: i32 = 0 };

pub const UNKILLABLE_HP: i32 = 1;

fn hurt(g: *Game, id: u16, dmg: i32) Hurt {
    const a = g.pool.get(id) orelse return .{ .dmg = 0, .lethal = false };
    var left = dmg;
    if (id == g.hero) {
        const took = a.ward.takes(g.mana, dmg);
        if (took > 0) {
            g.mana -= took;
            g.mana_held += took;
            left -= took;
            g.log.say("The mana shield takes {d}.", .{took});
        }
    }
    const taken = if (id == g.hero and g.unkillable) std.math.clamp(a.hp - UNKILLABLE_HP, 0, left) else left;
    return .{ .dmg = taken, .lethal = g.pool.damage(&g.lv, id, taken), .mana = dmg - left };
}

fn harmAfter(g: *Game, id: u16, moved: bool) void {
    gasHarm(g, id);
    burnHarm(g, id);
    bleedHarm(g, id, moved or g.displaced.isSet(actor.Pool.slot(id)));
}

fn gasHarm(g: *Game, id: u16) void {
    const a = g.pool.get(id) orelse return;
    if (!g.lv.gassy(a.at) or ranAlready(g, id, .gassed)) return;
    _ = harmTick(g, id, gas.harm(a.max), .gassed, .{ .hero = "The caustic gas eats at {s} for {d}." });
}

/// Marks the tick run on `id` this turn; whether it already had been, by the body or the one it split off.
fn ranAlready(g: *Game, id: u16, comptime tick: Tick) bool {
    const r = &g.ran[actor.Pool.slot(id)];
    defer r.insert(tick);
    return r.contains(tick);
}

fn burnHarm(g: *Game, id: u16) void {
    const a = g.pool.get(id) orelse return;
    if (ranAlready(g, id, .burned)) return;
    const dmg = a.burn.tick(a.resists.get(burning.ELEMENT)) orelse return;
    if (dmg == 0) return;
    _ = harmTick(g, id, dmg, .burned, .{ .hero = "Burning sears {s} for {d}.", .foe = "Burning sears the {s} for {d}." });
}

fn bleedHarm(g: *Game, id: u16, moved: bool) void {
    const a = g.pool.get(id) orelse return;
    if (ranAlready(g, id, .bled)) return;
    const dmg = a.bleed.tick(moved) orelse return;
    const stopped = a.bleed.turns == 0;
    const foe = "The {s} bleeds for {d}.";
    const h = if (moved)
        harmTick(g, id, dmg, .bled, .{ .hero = "Moving tears {s}'s wound: it bleeds for {d}.", .foe = foe })
    else
        harmTick(g, id, dmg, .bled, .{ .hero = "{s} bleeds for {d}.", .foe = foe });
    if (id == g.hero and stopped and !h.lethal) g.log.say("{s} stops bleeding.", .{g.name.text()});
}

/// Each takes the name and the damage; a foe with no line of its own is said only to die.
const Said = struct { hero: []const u8, foe: ?[]const u8 = null };

fn harmTick(g: *Game, id: u16, dmg: i32, comptime owed: Tick, comptime said: Said) Hurt {
    const a = g.pool.get(id).?;
    const kind = a.kind;
    const at = a.at;
    const h = hurt(g, id, dmg);
    const hero = id == g.hero;
    const name = actor.row(kind).name;
    if (hero) {
        g.log.say(said.hero, .{ g.name.text(), h.dmg });
    } else if (comptime said.foe) |line| {
        sayAt(g, at, line ++ "{s}", .{ name, h.dmg, if (h.lethal) IT_DIES else "" });
    } else if (h.lethal) sayAt(g, at, "The {s} dies.", .{name});
    @field(g.owed[actor.Pool.slot(id)], @tagName(owed)) = .{ .kill = h.lethal, .after = afterBlow(g, id, h) };
    if (h.lethal) {
        if (hero) heroDies(g) else fell(g, id);
    }
    return h;
}

const Worn = struct { held: bool = false, skips: bool = false };

fn wearTurn(g: *Game, id: u16) Worn {
    const a = g.pool.get(id) orelse return .{};
    const i = actor.Pool.slot(id);
    if (ranAlready(g, id, .worn) or (a.pin.turns == 0 and a.chill.turns == 0)) return .{};
    const w = Worn{ .held = a.pin.hold(), .skips = a.chill.turns > 0 and a.chill.skip() };
    g.owed[i].worn = .{ .body = snap(g, i) };
    return w;
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
    const stalled = (g.pool.get(id) orelse return).clock.stalled;
    const worn = wearTurn(g, id);
    const held = worn.held;
    if (worn.skips or stalled) return;
    const r = g.pool.get(id) orelse return;
    const h = g.archer() orelse return;
    const row = actor.row(r.kind);
    if (!r.awake) {
        if (!fov.sees(&g.lv, r.at, h.at, row.sight)) return;
        r.awake = true;
        turnLater(g, id, h.at.x - r.at.x);
        sayAt(g, r.at, "A {s} notices {s}.", .{ row.name, g.name.text() });
        return;
    }
    if (r.fright > 0) {
        r.fright -= 1;
        if (if (held) null else actor.flee(&g.lv, r.at, id, flowTo(g, h.at))) |d| {
            turnLater(g, id, d.delta().x);
            g.pool.move(&g.lv, id, r.at.add(d.delta()));
        } else if (besideWay(g, r.at, h.at)) |d| {
            turnLater(g, id, d.delta().x);
            reach(g, id, row);
        }
        if (r.fright == 0) sayAt(g, r.at, "The {s} stops running.", .{row.name});
        return;
    }
    const flitted = if (!held and row.flits and g.rng.chance(actor.FLIT)) actor.flit(&g.lv, r.at, id, g.hero, &g.rng) else null;
    const d = flitted orelse foeWay(g, r.at, id, h.at) orelse return;
    const to = r.at.add(d.delta());
    if (held and !to.eq(h.at)) return;
    turnLater(g, id, d.delta().x);
    if (to.eq(h.at)) return reach(g, id, row);
    g.pool.move(&g.lv, id, to);
}

fn foeWay(g: *Game, at: P, id: u16, hero: P) ?mathx.Dir {
    return besideWay(g, at, hero) orelse actor.chase(&g.lv, at, id, flowTo(g, hero));
}

fn besideWay(g: *const Game, at: P, hero: P) ?mathx.Dir {
    const d = mathx.dirTo(at, hero) orelse return null;
    return if (g.lv.passOk(at, d)) d else null;
}

fn flowTo(g: *Game, hero: P) *const [grid.CELLS]i32 {
    if (!g.flowed) {
        _ = grid.distances(&g.lv, hero, &g.flow, &g.queue);
        g.flowed = true;
    }
    return &g.flow;
}

fn reach(g: *Game, id: u16, row: actor.Row) void {
    const i = actor.Pool.slot(id);
    switch (row.blow) {
        .strike => |s| {
            const h = hurt(g, g.hero, s.roll(&g.rng));
            const lethal = h.lethal;
            g.log.say("The {s} {s} {s} for {d}.", .{ row.name, s.verb, g.name.text(), h.dmg });
            if (!lethal and h.dmg > 0 and bleeding.procs(&g.rng, s.bleeds)) {
                const b = &g.archer().?.bleed;
                g.log.say("{s} {s}!", .{ g.name.text(), if (b.turns == 0) bleeding.TAKES else "bleeds anew" });
                b.start();
            }
            g.owed[i].bit = .{ .blow = if (lethal) .kill else .hurt, .after = afterBlow(g, g.hero, h) };
            if (lethal) heroDies(g);
        },
        .burst => {
            const a = g.pool.get(id).?.*;
            _ = g.pool.damage(&g.lv, id, a.hp);
            g.owed[i].bit = .{ .blow = .burst, .after = .{ .body = snap(g, i) } };
            fell(g, id);
        },
    }
}

fn camAxis(centre: f32, view: f32, world: f32) f32 {
    if (view >= world) return (world - view) * 0.5;
    return std.math.clamp(centre - view * 0.5, 0, world - view);
}

/// Dead, a body stands until its killing blow lands, its flash is gone and its last step is drawn.
fn standing(g: *Game, i: usize) bool {
    if (g.split_from[i] != null) return false;
    return g.pool.items[i].alive or g.fx.holds(i) or g.glide[i].done() < 1;
}

pub fn heroSlot(g: *const Game) ?usize {
    return if (g.hero == grid.NO_ONE) null else actor.Pool.slot(g.hero);
}

fn heroShown(g: *const Game) ?fx.Body {
    const i = heroSlot(g) orelse return null;
    return g.pictured[i];
}

fn heroGlide(g: *Game) ?Glide {
    const i = heroSlot(g) orelse return null;
    return if (standing(g, i)) g.glide[i] else null;
}

fn heroNow(g: *Game) ?rl.Vector2 {
    return (heroGlide(g) orelse return null).now();
}

fn drawnAt(g: *Game, i: usize) ?rl.Vector2 {
    if (!standing(g, i)) return null;
    const at = g.glide[i].now();
    return if (g.lv.isLit(cellUnder(at))) at else null;
}

fn casterAt(g: *Game, i: usize, area: grid.Box) ?rl.Vector2 {
    if (!standing(g, i)) return null;
    const at = g.glide[i].now();
    return if (area.holds(cellUnder(at))) at else null;
}

fn camWant(g: *Game) rl.Vector2 {
    const at = (heroGlide(g) orelse return g.cam).ground();
    const half: f32 = @floatFromInt(HALF_CELL);
    return .{
        .x = camAxis(at.x + half, @floatFromInt(g.screen.x), @floatFromInt(grid.W * CELL)),
        .y = camAxis(at.y + half, @floatFromInt(g.screen.y), @floatFromInt(grid.H * CELL + hud.COVER)),
    };
}

fn snapGlide(g: *Game) void {
    for (g.pool.slice(), 0..) |*a, i| g.glide[i] = Glide.rest(a);
}

/// `late` is seconds since the glides started; visible foes follow the hero in acting order.
fn stepGlide(g: *Game, late: f32) void {
    var next: f32 = if (g.lead) |t| t + late + STAGGER_S else 0;
    const archer_done = stagger(g, g.hero, late, g.lead orelse 0, &next);
    g.lead = null;
    var part: [actor.MAX]f32 = @splat(archer_done);
    for (g.order[0..g.order_n]) |id| part[actor.Pool.slot(id)] = stagger(g, id, late, archer_done, &next);
    for (g.owed[0..g.pool.n], 0..) |*o, i| {
        if (!o.any()) continue;
        const start = if (g.split_from[i]) |p| @max(archer_done, part[p]) else archer_done;
        part[i] = stagger(g, actor.Pool.idOf(i), late, start, &next);
    }
    for (g.pool.slice(), 0..) |*a, i| {
        if (!g.glide[i].to.eq(a.at)) g.glide[i] = g.glide[i].toward(a.at, late);
    }
}

/// How far through a step in shallows its splash is drawn: the foot coming down.
const SPLASH_AT: f32 = 0.85;

fn splashSteps(g: *Game) void {
    for (g.glide[0..g.pool.n], 0..) |*gl, i| {
        if (gl.splashed or gl.done() < SPLASH_AT) continue;
        gl.splashed = true;
        if (gl.bump != null or std.meta.eql(gl.from, cellPx(gl.to))) continue;
        if (g.pictured[i].down() or actor.row(g.pictured[i].kind).movement == .flying) continue;
        const at = drawnAt(g, i) orelse continue;
        if (g.lv.at(cellUnder(at)) == .shallows) g.fx.splash(middle(at));
    }
}

/// Returns this body's completion time; unplaced bodies wait for the hero and any knock slide.
fn stagger(g: *Game, id: u16, late: f32, start: f32, next: *f32) f32 {
    comptime for (std.enums.values(Tick)) |t| switch (t) {
        .bit, .gassed, .burned, .bled, .worn => {},
    };
    const i = actor.Pool.slot(id);
    const a = g.pool.items[i];
    const gl = &g.glide[i];
    const moved = !gl.to.eq(a.at);
    const owed = g.owed[i];
    if (!moved and !owed.any()) {
        if (g.turning[i]) |*t| {
            if (t.in == null) t.in = start;
        }
        return start;
    }
    g.owed[i] = .{};
    const bit = owed.bit;
    const shown = g.lv.isLit(a.at);
    const placed = if (moved) shown or g.lv.isLit(gl.to) else shown and bit != null;
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
    } else if (bit != null) {
        gl.* = gl.bumping(hero_at, late - wait);
    }
    if ((moved or bit != null) and placed) {
        lands = gl.left();
        holdUntil(g, lands);
    }
    const hits = wait + BUMP_LANDS - late;
    if (bit) |b| switch (b.blow) {
        .hurt, .kill => strike(g, hero, .{ .from = a.at, .wait = hits }, hero_at, b.blow == .kill, b.after),
        .burst => strike(g, i, .{ .from = hero_at, .wait = hits }, a.at, true, b.after),
    };
    if (owed.worn) |c| g.fx.settle(lands, .{ .slot = i, .after = c });
    const mark: ?[2]f32 = if (shown) mathx.centre(a.at) else null;
    const drip: ?fx.Drip = if (mark) |m| .{ .at = m, .matter = fx.matterOf(a.kind) } else null;
    const in_view = shown or placed;
    if (owed.gassed) |h| harmShown(g, a.at, lands, h, false, in_view, .{ .slot = i });
    if (owed.burned) |h| harmShown(g, a.at, lands, h, true, in_view, .{ .slot = i, .fire_at = mark });
    if (owed.bled) |h| harmShown(g, a.at, lands, h, false, in_view, .{ .slot = i, .drip = drip });
    return lands;
}

/// Seconds until the body in `slot` may set off for `to`: a body dead there is no longer drawn, and a death it flees is.
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
        strike(g, s.slot, .{ .from = at, .wait = lands, .fire = fire }, at, true, h.after);
    } else if (in_view) {
        var shown = s;
        shown.after = h.after;
        sting(g, lands, shown);
    } else g.fx.settle(lands, .{ .slot = s.slot, .after = h.after });
}

const Walk = struct { d: mathx.Dir, late: f32 };

pub fn quiet(g: *const Game) bool {
    return g.busy <= PACE_SLACK;
}

fn paced(g: *Game) ?Walk {
    if (g.st.walk) |d| {
        if (!quiet(g)) {
            g.pending = d;
            return null;
        }
        g.pending = null;
        return .{ .d = d, .late = @min(g.st.late(), sinceQuiet(g)) };
    }
    const d = g.pending orelse return null;
    if (!quiet(g)) return null;
    g.pending = null;
    return .{ .d = d, .late = sinceQuiet(g) };
}

/// Seconds since the last turn was drawn out.
fn sinceQuiet(g: *const Game) f32 {
    return @max(0, -g.busy);
}

/// What the last frames set going moves on before this frame deals any more, so a blow dealt now lands `wait` on.
pub fn update(g: *Game, dt: f32) void {
    g.busy -= dt;
    for (g.glide[0..g.pool.n]) |*gl| gl.t += dt;
    g.fx.step(&g.lv, dt);
    g.cloud.step(&g.lv, dt);
    splashSteps(g);
    if (g.shot) |*s| {
        s.t += dt;
        if (s.cell() == null) g.shot = null;
    }
    stepTurning(g, dt);
    var late: f32 = 0;
    const was = g.mode;
    if (g.mode == .play and g.st.hit(PAUSE)) {
        openPause(g);
    } else switch (g.mode) {
        .play => {
            if (g.travel) |l| {
                if (g.st.walk) |d| g.pending = d;
                if (quiet(g)) goThrough(g, l);
            } else if (g.st.long(BINDS)) {
                g.st.spend(BINDS);
                g.pending = null;
                openBinds(g);
            } else if (g.st.hit(skillbar.INSPECT)) {
                g.pending = null;
                g.mode = .inspect;
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
        .inspect => inspectStep(g),
        .dead => if (deathShown(g) and dismissed(&g.st)) {
            if (g.permadeath) g.exit = .back else restart(g);
        },
        .pause => pauseStep(g),
    }
    if (g.mode != .play) g.st.spend(BINDS);
    if (was != g.mode) holdWalk(g);
    stepGlide(g, late);
    catchUp(g);
    splashSteps(g);
    stepVignette(g, dt);
    const want = camWant(g);
    const k = mathx.easing(dt, CAM_EASE);
    g.cam.x = mathx.lerpF(g.cam.x, want.x, k);
    g.cam.y = mathx.lerpF(g.cam.y, want.y, k);
    g.hour_shown = day.wrapHour(g.hour_shown + day.toward(g.hour_shown, g.clock.hour()) * mathx.easing(dt, HOUR_EASE));
    g.light.sky = skyNow(g);
    g.light.step(&g.lv, dt);
    g.light.carrier = carrierAt(g);
    g.rain.step(dt, weatherNow(g), g.screen.x, g.screen.y, PX_SCALE);
}

fn skyNow(g: *const Game) ?sky.Sky {
    return if (g.outdoors) sky.under(g.hour_shown, climateNow(g).light) else null;
}

fn weatherNow(g: *const Game) ?climate.Weather {
    return if (g.outdoors) climateNow(g).weather else null;
}

fn climateNow(g: *const Game) climate.Climate {
    const w = g.world orelse return .{};
    return w.node[g.node].sky();
}

/// Per second, how fast the sky drawn catches the hour a turn moved on.
const HOUR_EASE: f32 = 4;

pub fn holdWalk(g: *Game) void {
    g.st.holdWalk();
    g.pending = null;
}

fn openPause(g: *Game) void {
    g.paused_from = g.mode;
    g.pause_menu = .{};
    g.mode = .pause;
    g.pending = null;
}

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

pub fn veil(g: *const Game) void {
    rl.drawRectangle(0, 0, g.screen.x, g.screen.y, look.VEIL);
}

fn drawPause(g: *Game) void {
    veil(g);
    var rows: [PAUSE_ROWS.len][]const u8 = undefined;
    for (PAUSE_ROWS, &rows) |r, *l| l.* = pauseLabel(g, r);
    menu.draw(g.face, g.screen, "PAUSED", &rows, g.pause_menu.at, null);
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

/// A slime split off another slides out as the blow that split it lands, and not before the one it split off is drawn.
fn catchUp(g: *Game) void {
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
        if (g.lv.isLit(g.pool.items[from].at) or g.lv.isLit(a.at)) holdUntil(g, g.glide[i].left());
    }
    if (!dying) g.flasks_shown = g.flasks;
    g.mana_held = @max(0, g.mana_held - g.fx.mana_landed);
    g.fx.mana_landed = 0;
    if (heroSlot(g)) |h| {
        if (!g.fx.pending(h)) g.mana_held = 0;
    }
    g.fx.react(g.pictured[0..g.pool.n]);
}

fn deathShown(g: *const Game) bool {
    return g.mode == .dead and quiet(g);
}

const DISMISS = [_]input.Button{ CONFIRM, PAUSE, BACK, .x };

fn dismissed(st: *const input.State) bool {
    for (DISMISS) |b| {
        if (st.hit(b)) return true;
    }
    return false;
}

/// Read off the archer's slot, not `archer()`, so the blow that kills it still reddens the view.
fn stepVignette(g: *Game, dt: f32) void {
    const max = heroRow(g).hp;
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
    return look.rect(sx + @divTrunc(CELL - t.width * k, 2), sy + @divTrunc(CELL - t.height * k, 2), t.width * k, t.height * k);
}

fn drawSprite(t: rl.Texture2D, sx: i32, sy: i32) void {
    look.stretch(t, spriteRect(t, sx, sy), look.LIT);
}

fn outline(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangleLinesEx(look.rect(c.sx(p) + OUTLINE_INSET, c.sy(p) + OUTLINE_INSET, CELL - OUTLINE_INSET * 2, CELL - OUTLINE_INSET * 2), @floatFromInt(LINE_W), col);
}

fn fillCell(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangle(c.sx(p), c.sy(p), CELL, CELL, col);
}

/// Remembered like terrain: nothing but the archer breaks one, and only in sight, as the blow lands.
fn barrelShownAt(g: *Game, p: P) bool {
    return g.lv.isSeen(p) and barrelPresent(g, p);
}

fn barrelPresent(g: *Game, p: P) bool {
    return g.lv.hasBarrel(p) or g.fx.breaking(p);
}

fn shownAt(g: *Game, stood: *const Stood, p: P) bool {
    return (grid.Level.inside(p) and stood.isSet(grid.Level.idx(p))) or barrelShownAt(g, p);
}

fn stoodNow(g: *Game) Stood {
    var stood = Stood.initEmpty();
    for (0..g.pool.n) |i| stand(&stood, cellUnder(drawnAt(g, i) orelse continue));
    return stood;
}

fn stand(stood: *Stood, under: P) void {
    if (grid.Level.inside(under)) stood.set(grid.Level.idx(under));
}

fn bar(x: i32, y: i32, w: i32, h: i32, v: i32, max: i32, back: rl.Color, fill: rl.Color) void {
    rl.drawRectangle(x, y, w, h, back);
    rl.drawRectangle(x, y, @divTrunc(w * v, max), h, fill);
}

const Shown = struct {
    pic: fx.Body,
    slot: usize,
    s: P,
    lifted: P,
    mid: [2]f32,
    left: bool,
    shine: light.Shine,
};

const Prop = struct {
    s: P,
    mid: [2]f32,
    shine: light.Shine,

    fn at(g: *Game, c: Cam, p: P, casting: bool) Prop {
        const mid = mathx.centre(p);
        return .{ .s = .{ .x = c.sx(p), .y = c.sy(p) }, .mid = mid, .shine = if (casting) g.light.onCaster(mid, false) else g.light.onBody(mid, false) };
    }
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
            if (barrelShownAt(self.g, p)) return Prop.at(self.g, self.c, p, false);
        }
        return null;
    }
};

fn drawFigure(g: *Game, tex: ?rl.Texture2D, l: look.Look, s: P, left: bool, mid: [2]f32, shine: *const light.Shine, flash: f32) void {
    if (tex) |t| {
        g.light.drawBody(t, spriteRect(t, s.x, s.y), left, mid, shine, flash);
    } else drawGlyph(g, l.ch, s.x, s.y, shine.drawn(l.fg, flash));
}

const Stood = std.StaticBitSet(grid.CELLS);

fn drawGroundPass(g: *Game, c: Cam, lo: P, hi: P, arrow_at: ?P, stood: *const Stood) void {
    var beds: dual.Beds = undefined;
    beds.fill(&g.lv, lo, hi, true);
    const water: ?look.WaterView = if (g.light.mapTexture()) |tex| .{
        .seconds = g.light.t.at(),
        .screen_h = @floatFromInt(g.screen.y),
        .visibility = tex,
    } else null;
    g.sprites.drawGround(&beds, .{ @floatFromInt(-c.x), @floatFromInt(-c.y) }, CELL_F, water);
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        if (!g.lv.isSeen(p)) continue;
        const here = g.lv.at(p);
        if (look.glyphGround(here, &g.sprites)) inkCell(g, c, p, here, arrow_at, stood);
        if (g.lv.doorAt(p) != null) drawGlyph(g, look.DOOR.ch, c.sx(p), c.sy(p), look.DOOR.fg);
    }
}

/// At full light, what stands on the seen cells from `lo` up to `hi`, over the shadows cast on the ground.
fn drawSolidPass(g: *Game, c: Cam, lo: P, hi: P, arrow_at: ?P, stood: *const Stood) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        if (!g.lv.isSeen(p)) continue;
        const here = g.lv.at(p);
        if (!look.standsOver(here)) continue;
        if (g.sprites.tileAt(&g.lv, p)) |t| {
            drawSprite(t, c.sx(p), c.sy(p));
            continue;
        }
        if (look.tileBg(here)) |bg| fillCell(c, p, bg);
        inkCell(g, c, p, here, arrow_at, stood);
    }
}

fn inkCell(g: *Game, c: Cam, p: P, here: grid.Tile, arrow_at: ?P, stood: *const Stood) void {
    if (shownAt(g, stood, p)) return;
    if (arrow_at) |a| {
        if (a.eq(p)) return;
    }
    look.inkTile(&g.face, here, c.sx(p) + HALF_CELL, c.sy(p) + HALF_CELL, GLYPH);
}

/// Every shadow cast into `view`, multiplied over what `framebuffer` holds; false with no shader for it.
fn shadowPass(g: *Game, c: Cam, view: grid.Box, framebuffer: u32) bool {
    if (!g.light.beginShadows(g.screen, framebuffer)) return false;
    drawShadows(g, c, view.grown(CAST_MARGIN));
    g.light.endShadows(-c.x, -c.y, CELL);
    return true;
}

fn drawShadows(g: *Game, c: Cam, cast: grid.Box) void {
    var props = cast.cells();
    while (props.next()) |p| {
        if (barrelPresent(g, p)) {
            if (g.sprites.barrel) |t| {
                const b = Prop.at(g, c, p, true);
                g.light.drawShadows(t, spriteRect(t, b.s.x, b.s.y), false, b.mid, &b.shine);
            }
        }
        const kind = g.lv.at(p);
        if (!look.stands(kind)) continue;
        const forest = look.forestAt(&g.lv, p);
        const t = g.sprites.tileAt(&g.lv, p) orelse continue;
        const pr = Prop.at(g, c, p, true);
        const rect = spriteRect(t, pr.s.x, pr.s.y);
        if (forest) {
            g.light.drawForestShadows(t, rect, pr.mid, &pr.shine, g.lv.tileShape(p) orelse .{});
        } else if (look.canopied(kind)) {
            g.light.drawCanopy(t, rect, pr.mid, &pr.shine);
        } else g.light.drawShadows(t, rect, false, pr.mid, &pr.shine);
    }
    for (0..g.pool.n) |i| {
        const at = casterAt(g, i, cast) orelse continue;
        const t = g.sprites.body(g.pictured[i].kind) orelse continue;
        const s = c.px(at);
        const mid = middle(at);
        const shine = g.light.onCaster(mid, actor.Pool.idOf(i) == g.hero);
        g.light.drawShadows(t, spriteRect(t, s.x, s.y), g.facing[i] == .left, mid, &shine);
    }
}

fn viewBox(g: *const Game, c: Cam) grid.Box {
    return .{
        .lo = .{ .x = @max(0, @divFloor(c.x, CELL)), .y = @max(0, @divFloor(c.y, CELL)) },
        .hi = .{
            .x = @min(grid.W, @divFloor(c.x + g.screen.x, CELL) + 1),
            .y = @min(grid.H, @divFloor(c.y + g.screen.y, CELL) + 1),
        },
    };
}

fn drawWorld(g: *Game) void {
    const c = Cam.of(g);
    const view = viewBox(g, c);
    const lo = view.lo;
    const hi = view.hi;
    const arrow_at: ?P = if (g.shot) |s| s.cell() else null;
    const aim_from: ?P = if (g.mode != .aim) null else if (g.archer()) |a| a.at else null;

    var shown: [actor.MAX]Shown = undefined;
    const stood = stoodNow(g);
    var n: usize = 0;
    for (0..g.pool.n) |i| {
        const at = drawnAt(g, i) orelse continue;
        const mid = middle(at);
        shown[n] = .{
            .pic = g.pictured[i],
            .slot = i,
            .s = c.px(at),
            .lifted = c.px(at).sub(.{ .x = 0, .y = g.glide[i].lift() }),
            .mid = mid,
            .left = g.facing[i] == .left,
            .shine = g.light.onBody(mid, actor.Pool.idOf(i) == g.hero),
        };
        n += 1;
    }
    const bodies = shown[0..n];

    g.light.bake(&g.lv, lo, hi);
    drawGroundPass(g, c, lo, hi, arrow_at, &stood);
    _ = shadowPass(g, c, view, g.framebuffer);
    g.cloud.draw(&g.lv, view, -c.x, -c.y, CELL);
    drawSolidPass(g, c, lo, hi, arrow_at, &stood);
    g.fx.draw(@floatFromInt(-c.x), @floatFromInt(-c.y), CELL_F);
    g.light.drawMap(-c.x, -c.y, CELL);

    if (aim_from) |from| {
        var cells = grid.Cells.of(lo, hi);
        while (cells.next()) |p| {
            if (aimable(g, from, p)) fillCell(c, p, look.AIM_REACH);
        }
        if (g.aim_act.reticle() == .bow) {
            const f = bow.fly(&g.lv, from, g.mark);
            for (f.path[0..f.len]) |p| fillCell(c, p, look.AIM_PATH);
            switch (g.aim_act) {
                inline else => |a| if (comptime a.bursts()) if (f.impact()) |at| {
                    const area = skillbar.Act.arrow(a).burst(&g.lv, from, at);
                    for (area.cells[0..area.n]) |p| {
                        if (g.lv.isSeen(p)) fillCell(c, p, look.aimArea(a));
                    }
                },
            }
        }
        switch (g.aim_act) {
            inline else => |a| if (comptime a.sweeps()) {
                const arc = skillbar.Act.skill(a).arc(&g.lv, from, g.mark);
                for (arc.cells[0..arc.n]) |p| fillCell(c, p, look.AIM_PATH);
            },
        }
    }

    var barrels = Barrels.of(g, c, lo, hi);
    while (barrels.next()) |b| drawFigure(g, g.sprites.barrel, look.BARREL, b.s, false, b.mid, &b.shine, 0);
    for (bodies) |*b| {
        const at = b.lifted;
        drawFigure(g, g.sprites.body(b.pic.kind), look.body(b.pic.kind), at, b.left, b.mid, &b.shine, g.fx.flashOf(b.slot));
        const x: f32 = @floatFromInt(at.x);
        const y: f32 = @floatFromInt(at.y);
        for (std.enums.values(fx.Status)) |s| {
            if (b.pic.status.get(s) == 0) continue;
            switch (s) {
                .bleeding => g.fx.drawBleeding(x, y, CELL_F, b.slot, b.shine.tint(s.ink())),
                .burning => g.fx.drawBurning(x, y, CELL_F, b.slot, b.shine.sight),
                .chilled => g.fx.drawChilled(x, y, CELL_F, b.slot, b.shine.tint(s.ink())),
                .pinned => g.fx.drawPinned(x, y, CELL_F, b.shine.tint(s.ink())),
                .warded => g.fx.drawWarded(x, y, CELL_F, b.shine.tint(s.ink())),
            }
        }
    }

    drawTorches(g, c);
    if (g.light.sky) |k| g.rain.draw(weatherNow(g), &g.light.sight, @floatFromInt(-c.x), @floatFromInt(-c.y), CELL_F, PX_SCALE, sky.brightness(k));

    for (bodies) |*b| {
        if (!b.pic.kind.foe() or !b.pic.hurt()) continue;
        const y_bar = b.s.y + CELL - BODY_BAR_H - BODY_BAR_LIFT;
        bar(b.s.x + BODY_BAR_INSET, y_bar, CELL - BODY_BAR_INSET * 2, BODY_BAR_H, b.pic.hp, b.pic.max, look.BG, look.LIFE);
    }

    if (aim_from) |from| outline(c, g.mark, if (aimable(g, from, g.mark)) look.RETICLE else look.RETICLE_BLOCKED);
    if (g.mode == .play and g.st.lean) drawLean(g, c, &stood);

    if (g.shot) |s| {
        if (s.cell()) |p| drawGlyph(g, s.glyph, c.sx(p), c.sy(p), look.arrowInk(s.act));
    }
    for (bodies) |*b| {
        g.fx.drawSpeech(&g.face, b.slot, b.lifted.x, b.lifted.y, CELL_F, b.shine.sight);
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
fn leanShown(g: *Game, stood: *const Stood, from: P, d: mathx.Dir) Move {
    if (!g.lv.passOk(from, d)) return .blocked;
    return if (shownAt(g, stood, from.add(d.delta()))) .kick else .step;
}

fn drawLean(g: *Game, c: Cam, stood: *const Stood) void {
    const at = cellUnder(heroNow(g) orelse return);
    for (input.DPAD) |button| {
        const d = input.leanOf(button);
        const p = at.add(d.delta());
        const col = switch (leanShown(g, stood, at, d)) {
            .kick => look.LEAN_FOE,
            .step => look.LEAN_OPEN,
            .blocked => look.LEAN_BLOCKED,
        };
        outline(c, p, col);
        if (g.lv.walkable(p) and !shownAt(g, stood, p)) {
            look.drawDirection(button, c.sx(p) + HALF_CELL, c.sy(p) + HALF_CELL, LEAN_GLYPH, col);
            continue;
        }
        const inset = LEAN_PAD + @divTrunc(LEAN_MARK, 2);
        const dx: i32 = if (d.delta().x > 0) CELL - inset else inset;
        const dy: i32 = if (d.delta().y > 0) CELL - inset else inset;
        look.drawDirection(button, c.sx(p) + dx, c.sy(p) + dy, LEAN_MARK, col);
    }
}

/// The seen cells, a texel each, drawn `MINI` times over in one quad. Needs a live GL context.
const Minimap = struct {
    tex: ?rl.Texture2D = null,
    px: [grid.CELLS]rl.Color = undefined,
    /// Set by `castSight`, the only change to what it shows.
    stale: bool = true,

    fn load(m: *Minimap) void {
        m.tex = look.canvas(grid.W, grid.H, rl.Color.blank, .point);
        m.stale = true;
    }

    fn unload(m: *Minimap) void {
        look.unloadAll(m);
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
    look.hudPanel(&g.sprites, o.x - f, o.y - f, fw, fh, look.MINI_BG, look.LIT);
    if (g.mini.tex) |t| {
        if (g.mini.stale) {
            for (&g.mini.px, &g.lv.tile, &g.lv.seen, &g.lv.lit) |*c, tile, seen, lit| c.* = if (seen) look.mini(tile, lit) else rl.Color.blank;
            rl.updateTexture(t, &g.mini.px);
            g.mini.stale = false;
        }
        look.stretch(t, look.rect(o.x, o.y, MINI_W, MINI_H), look.LIT);
    }
    for (g.pool.slice(), 0..) |a, i| {
        if (!a.foe()) continue;
        const at = drawnAt(g, i) orelse continue;
        miniDot(o, cellUnder(at), 0, look.MINI_FOE);
    }
    if (heroNow(g)) |at| miniDot(o, cellUnder(at), MINI_HERO_GROW, look.MINI_HERO);
    const v = miniView(Cam.of(g), g.screen);
    rl.drawRectangleLines(o.x + v.lo.x, o.y + v.lo.y, v.hi.x - v.lo.x, v.hi.y - v.lo.y, look.MINI_VIEW);
}

fn miniView(c: Cam, screen: P) grid.Box {
    return .{
        .lo = .{ .x = @max(0, toMini(c.x)), .y = @max(0, toMini(c.y)) },
        .hi = .{ .x = @min(MINI_W, toMini(c.x + screen.x)), .y = @min(MINI_H, toMini(c.y + screen.y)) },
    };
}

fn toMini(px: i32) i32 {
    return @divTrunc(px * MINI, CELL);
}

fn bindRowY(y0: i32, row: usize) i32 {
    return y0 + BIND_ROWS_DY + @as(i32, @intCast(row)) * BIND_ROW_H;
}

const SlotLook = struct { act: ?skillbar.Act, key: ?input.Button, edge: ?rl.Color = null, faded: bool = false };

fn drawSlot(g: *Game, x: i32, y: i32, s: SlotLook) void {
    const a: f32 = if (s.faded) CARRIED_A else 1;
    look.hudPanel(&g.sprites, x, y, SLOT_PX, SLOT_PX, look.fade(if (s.act == null) look.SLOT_EMPTY else look.SLOT_BG, a), look.fade(look.LIT, a));
    if (s.edge) |edge| {
        const inset = SLOT_EDGE_INSET;
        rl.drawRectangleLinesEx(look.rect(x + inset, y + inset, SLOT_PX - 2 * inset, SLOT_PX - 2 * inset), @floatFromInt(LINE_W), look.fade(edge, a));
    }
    if (s.act) |act| {
        const inset = @divTrunc(SLOT_PX - look.SKILL_PX, 2);
        look.drawSkill(&g.sprites, act, x + inset, y + inset, a);
    }
    const p = look.Prompt.of(&g.st, s.key orelse return);
    p.draw(&g.face, x + SLOT_MID, y + SLOT_PX + KEY_GAP + @divTrunc(PROMPT_PX, 2), PROMPT_PX, a);
}

/// While aiming, the set the reticle's skill was taken from, whatever is held now.
fn shownSet(g: *const Game) skillbar.Set {
    return if (g.mode == .aim) g.aim_set else g.bar.active(g.st.down);
}

const SlotShown = struct { act: skillbar.Act, cooling: u8, drinks: ?u8 };

fn slotShown(g: *const Game, i: usize) ?SlotShown {
    const act = g.bar.at(.{ .set = shownSet(g), .button = skillbar.SLOTS[i] }) orelse return null;
    return .{ .act = act, .cooling = g.cooldown.get(act), .drinks = if (act.flaskOf()) |k| g.flasks_shown.get(k).uses() else null };
}

fn hudLayout(g: *const Game) hud.Layout {
    return hud.Layout.of(g.screen, SKILLS_W);
}

fn slotBox(layout: hud.Layout, i: usize) rl.Rectangle {
    return look.rect(layout.skills.x + SLOT_XS[i], layout.skills.y, SLOT_PX, SLOT_PX);
}

fn drawSkills(g: *Game, layout: hud.Layout) void {
    for (skillbar.SLOTS, 0..) |b, i| {
        const box = slotBox(layout, i);
        const x: i32 = @intFromFloat(box.x);
        const y: i32 = @intFromFloat(box.y);
        const held = (g.st.held(b) and g.mode == .play) or (g.mode == .aim and g.aim_by == b);
        const s = slotShown(g, i);
        drawSlot(g, x, y, .{
            .act = if (s) |v| v.act else null,
            .key = b,
            .edge = if (held) look.SLOT_HELD else null,
            .faded = if (s) |v| blocked(g, v.act, &g.flasks_shown, manaShown(g)) != null else false,
        });
        const v = s orelse continue;
        if (v.cooling > 0 or v.drinks != null) {
            var buf: [16]u8 = undefined;
            const label = std.fmt.bufPrintZ(&buf, "{d}", .{v.drinks orelse v.cooling}) catch "";
            g.face.text(label, x + SLOT_PX - COOLDOWN_DX, y + COOLDOWN_DY, SLOT_TEXT, look.TEXT);
        }
    }
}

fn drawBinds(g: *Game) void {
    const b = g.binds;
    const layout = hudLayout(g);
    const x0 = layout.skills.x;
    const y0 = @divTrunc(layout.top, 2) + BIND_TOP_DY;
    veil(g);
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
                .edge = if (here) look.SLOT_CURSOR else null,
                .faded = carried,
            });
        }
    }
    const info_y = bindRowY(y0, skillbar.SETS.len) + BIND_INFO_DY;
    const pop_y = cursor.y - SLOT_PX - BIND_POP_DY;
    var shown: ?skillbar.Act = g.bar.at(b.slot());
    switch (b.menu) {
        .browse => {},
        .carry => |from| {
            shown = g.bar.at(from);
            if (shown) |a| drawSlot(g, cursor.x, pop_y, .{ .act = a, .key = from.button, .edge = look.SLOT_CURSOR });
        },
        .pick => |pick| {
            const kit = skillbar.kit(g.class);
            const picks = picksOf(kit);
            shown = pickAct(kit, pick);
            const win = pickWindow(y0 + BIND_TITLE, pop_y, picks, pick);
            const cols: i32 = @intCast(@min(picks, PICK_COLS));
            const w = cols * SLOT_STEP - SLOT_GAP;
            const px = std.math.clamp(cursor.x + @divTrunc(SLOT_PX - w, 2), x0, x0 + SKILLS_W - w);
            const py = pop_y - @as(i32, @intCast(win.len - 1)) * SLOT_STEP;
            const h = @as(i32, @intCast(win.len)) * SLOT_STEP - SLOT_GAP;
            rl.drawRectangle(px - SLOT_GAP, py - SLOT_GAP, w + 2 * SLOT_GAP, h + 2 * SLOT_GAP, look.PICK_BG);
            for (win.from * PICK_COLS..@min(picks, (win.from + win.len) * PICK_COLS)) |i| {
                const x = px + @as(i32, @intCast(i % PICK_COLS)) * SLOT_STEP;
                const y = py + @as(i32, @intCast(i / PICK_COLS - win.from)) * SLOT_STEP;
                const act = pickAct(kit, i);
                const edge: ?rl.Color = if (i == pick) look.SLOT_CURSOR else if (act == null) look.SLOT_CLEAR else null;
                drawSlot(g, x, y, .{ .act = act, .key = null, .edge = edge });
                if (act == null) g.face.glyph(look.CLEAR.ch, x + SLOT_MID, y + SLOT_MID, CLEAR_GLYPH, look.CLEAR.fg);
            }
        },
    }
    if (shown) |a| {
        textMid(g, a.name(), info_y, TEXT, look.TEXT);
        textMid(g, a.desc(), info_y + TEXT_LINE, TEXT, look.DIM);
    } else if (b.menu == .pick) {
        textMid(g, "Clear slot", info_y, TEXT, look.TEXT);
    }
}

const Life = struct { hp: i32, max: i32 };

fn lifeShown(g: *const Game) Life {
    const h = heroShown(g) orelse return .{ .hp = 0, .max = heroRow(g).hp };
    return .{ .hp = h.hp, .max = h.max };
}

fn drawHud(g: *Game) void {
    const layout = hudLayout(g);
    hud.frame(layout, &g.sprites);
    const life = lifeShown(g);
    hud.resources(layout, &g.face, life.hp, life.max, manaShown(g), heroes.MANA);
    drawSkills(g, layout);
    if (heroShown(g)) |h| hud.statuses(layout, &g.sprites, &g.face, h.status);
}

const Part = struct { spot: Spot, box: rl.Rectangle };
const ORBS = 2;
const SPOTS_MAX = ORBS + skillbar.SLOTS.len + @typeInfo(hud.Shown).array.len;

fn spotsOf(g: *const Game, out: *[SPOTS_MAX]Part) []const Part {
    const layout = hudLayout(g);
    var n: usize = 0;
    out[n] = .{ .spot = .life, .box = hud.orbBox(layout.life) };
    n += 1;
    for (0..skillbar.SLOTS.len) |i| {
        out[n] = .{ .spot = .{ .slot = i }, .box = slotBox(layout, i) };
        n += 1;
    }
    out[n] = .{ .spot = .mana, .box = hud.orbBox(layout.mana) };
    n += 1;
    if (heroShown(g)) |h| {
        var buf: hud.Shown = undefined;
        const shown = hud.shownStatuses(h.status, &buf);
        for (shown, 0..) |s, k| {
            out[n] = .{ .spot = .{ .status = s }, .box = hud.statusBox(layout, shown.len, k) };
            n += 1;
        }
    }
    return out[0..n];
}

fn spotAt(spots: []const Part, s: Spot) ?Part {
    for (spots) |x| {
        if (std.meta.eql(x.spot, s)) return x;
    }
    return null;
}

fn centreOf(r: rl.Rectangle) [2]f32 {
    return .{ r.x + r.width / 2, r.y + r.height / 2 };
}

fn toward(spots: []const Part, from: Part, d: mathx.Dir) ?Spot {
    const c = centreOf(from.box);
    const way = d.delta();
    const wx: f32 = @floatFromInt(way.x);
    const wy: f32 = @floatFromInt(way.y);
    var best: ?Spot = null;
    var best_score = std.math.floatMax(f32);
    for (spots) |s| {
        const p = centreOf(s.box);
        const vx = p[0] - c[0];
        const vy = p[1] - c[1];
        const along = vx * wx + vy * wy;
        if (along <= 0) continue;
        const score = along + 2 * @abs(vx * wy - vy * wx);
        if (score < best_score) {
            best_score = score;
            best = s.spot;
        }
    }
    return best;
}

fn inspectStep(g: *Game) void {
    if (menu.backed(&g.st) or g.st.hit(skillbar.INSPECT)) {
        g.mode = .play;
        return;
    }
    var buf: [SPOTS_MAX]Part = undefined;
    const spots = spotsOf(g, &buf);
    const here = inspected(g, spots);
    g.inspecting = here.spot;
    const d = g.st.walk orelse return;
    g.inspecting = toward(spots, here, d) orelse here.spot;
}

fn inspected(g: *const Game, spots: []const Part) Part {
    return spotAt(spots, g.inspecting) orelse spotAt(spots, .{ .slot = 0 }).?;
}

fn round(s: Spot) bool {
    return s == .life or s == .mana;
}

fn hovered(g: *const Game) ?Part {
    if (g.mode != .play and g.mode != .aim) return null;
    const p = g.st.pointer orelse return null;
    const at: rl.Vector2 = .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
    var buf: [SPOTS_MAX]Part = undefined;
    for (spotsOf(g, &buf)) |s| {
        const c = centreOf(s.box);
        const over = if (round(s.spot)) rl.checkCollisionPointCircle(at, .{ .x = c[0], .y = c[1] }, s.box.width / 2) else rl.checkCollisionPointRec(at, s.box);
        if (over) return s;
    }
    return null;
}

fn drawTips(g: *Game) void {
    if (g.mode == .inspect) {
        var buf: [SPOTS_MAX]Part = undefined;
        const spots = spotsOf(g, &buf);
        drawTip(g, inspected(g, spots));
    } else if (hovered(g)) |here| drawTip(g, here);
}

fn drawTip(g: *Game, here: Part) void {
    hud.focus(here.box, round(here.spot));
    var title_buf: [64]u8 = undefined;
    var body_buf: [menu.NOTE_MAX * 2]u8 = undefined;
    const tip = tipOf(g, here.spot, &title_buf, &body_buf);
    hud.tooltip(&g.face, hudLayout(g), g.screen, here.box, tip.title, tip.body);
}

const Tip = struct { title: [:0]const u8, body: []const u8 };

/// What the spot is and what it does, said without naming any key or button.
fn tipOf(g: *const Game, s: Spot, title_buf: []u8, body_buf: []u8) Tip {
    return switch (s) {
        .life => blk: {
            const life = lifeShown(g);
            break :blk .{
                .title = hud.LIFE,
                .body = std.fmt.bufPrint(body_buf, "{d} of {d}. Lost to blows, gas, fire and bleeding, and restored by a life flask. At none, the run ends.", .{ life.hp, life.max }) catch "",
            };
        },
        .mana => .{
            .title = hud.MANA,
            .body = std.fmt.bufPrint(body_buf, "{d} of {d}. Spent on skills; {d} returns every turn, and a mana flask restores more.", .{ manaShown(g), heroes.MANA, heroes.MANA_REGEN }) catch "",
        },
        .slot => |i| blk: {
            const v = slotShown(g, i) orelse break :blk .{ .title = "Empty", .body = "No skill is bound here." };
            const act = v.act;
            const extra = if (v.drinks) |n|
                std.fmt.bufPrint(body_buf, "{s} {d} drink{s} left.", .{ act.desc(), n, plural(n) })
            else if (v.cooling > 0)
                std.fmt.bufPrint(body_buf, "{s} Ready in {d} turn{s}.", .{ act.desc(), v.cooling, plural(v.cooling) })
            else
                std.fmt.bufPrint(body_buf, "{s}", .{act.desc()});
            break :blk .{ .title = act.name(), .body = extra catch act.desc() };
        },
        .status => |st| blk: {
            const turns = if (heroShown(g)) |h| h.status.get(st) else 0;
            break :blk .{
                .title = std.fmt.bufPrintZ(title_buf, "{s}, {d} turn{s}", .{ st.title(), turns, plural(turns) }) catch st.title(),
                .body = st.blurb(),
            };
        },
    };
}

fn drawDead(g: *Game) void {
    var buf: [menu.NOTE_MAX + 1]u8 = undefined;
    const mid = @divTrunc(g.screen.y, 2);
    veil(g);
    const DIED = " DIED";
    var died: [heroes.Name.MAX + DIED.len + 1]u8 = undefined;
    const said = menu.shout(&died, "{s}" ++ DIED, .{g.name.text()});
    textMid(g, said, mid + DEAD_TITLE_DY, menu.TITLE, look.LIFE);
    textMid(g, std.fmt.bufPrintZ(&buf, "{d} foes killed. Seed {d}.", .{ g.kills, g.seed }) catch "", mid + DEAD_SCORE_DY, TEXT, look.TEXT);
}

fn drawFrame(g: *Game) void {
    rl.clearBackground(look.BG);
    drawWorld(g);
    g.vignette.draw(g.screen.x, g.screen.y);
    drawMinimap(g);
    drawHud(g);
    drawTips(g);
    if (g.mode == .bind) drawBinds(g);
    if (deathShown(g)) drawDead(g);
    if (g.mode == .pause) drawPause(g);
}

const GRAPHICS = .{ "light", "cloud", "vignette", "mini" };

fn loadGraphics(g: *Game) void {
    g.sprites.loadCommon();
    inline for (GRAPHICS) |f| @field(g, f).load();
    g.graphics_ready = true;
}

/// Safe whether or not anything was loaded.
fn unloadGraphics(g: *Game) void {
    g.sprites.unload();
    inline for (GRAPHICS) |f| @field(g, f).unload();
    g.graphics_ready = false;
    g.art_ready = false;
}

fn prepare(g: *Game) void {
    if (!g.graphics_ready) loadGraphics(g);
    if (g.art_ready) return;
    const need = mapAssets(g);
    g.sprites.sync(need);
    const figures = g.sprites.figures();
    g.light.syncFigures(&figures);
    g.art_ready = true;
}

fn mapAssets(g: *Game) look.Assets {
    var need = look.Assets.of(&g.lv);
    need.barrel = need.barrel or g.fx.barrels_due > 0;
    for (g.pool.slice(), 0..) |a, i| {
        if (a.alive) need.body(a.kind);
        if (standing(g, i)) need.body(g.pictured[i].kind);
    }
    return need;
}

pub fn withGame(flags: rl.ConfigFlags, title: [:0]const u8, comptime body: fn (*Game) anyerror!void) !void {
    var startup = try std.time.Timer.start();
    const alloc = std.heap.c_allocator;
    rl.setConfigFlags(flags);
    rl.initWindow(WINDOW_W, WINDOW_H, title);
    if (!rl.isWindowReady()) return error.WindowFailed;
    defer rl.closeWindow();
    input.claimKeys();
    input.mapPads();
    const g = try boot(alloc);
    defer shut(alloc, g);
    defer unloadGraphics(g);
    g.face = font.Face.load(look.TILE_CODEPOINTS);
    defer g.face.unload();
    if (comptime body == benchWalk) std.debug.print("startup: {d:.3} ms, {d} map textures\n", .{ ms(startup.read()), g.sprites.count() });
    try body(g);
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
    g.st.playing = g.mode == .play or g.mode == .aim;
    g.st.sets = g.mode == .inspect;
    g.st.modifier = g.bar.modifier;
    g.st.update(dt);
    syncScreen(g, g.st.fullscreen);
    update(g, dt);
    prepare(g);
    g.st.modifier = g.bar.modifier;
    rl.beginDrawing();
    drawFrame(g);
    rl.endDrawing();
}

/// A render texture, not `takeScreenshot`: the batch is only guaranteed flushed at `endTextureMode`.
pub fn shot() !void {
    try withGame(.{ .window_hidden = true }, "roguelike --shot", shoot);
}

fn renderTarget(g: *Game) !rl.RenderTexture2D {
    return rl.loadRenderTexture(g.screen.x, g.screen.y);
}

fn shoot(g: *Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_DIR);

    begin(g, SHOT_SEED);
    poseRat(g);
    g.st.lean = true;
    try capture(g, target, SHOTS_DIR ++ "/lean.png");

    g.st.lean = false;
    openAim(g, boundTo(g, .shoot).by, .shoot);
    try capture(g, target, SHOTS_DIR ++ "/aim.png");

    g.mode = .play;
    poseTorch(g);
    try capture(g, target, SHOTS_DIR ++ "/torch.png");

    posePicker(g, boundTo(g, .shoot));
    try capture(g, target, SHOTS_DIR ++ "/bind.png");

    arena(g, .{ .x = 20, .y = 15 }, &.{.{ .x = 25, .y = 14 }});
    g.lv.set(.{ .x = 21, .y = 15 }, .water);
    _ = g.pool.damage(&g.lv, g.hero, 6);
    settle(g);
    openLeap(g, boundTo(g, .juke).by, .juke);
    g.mark = .{ .x = 23, .y = 15 };
    try capture(g, target, SHOTS_DIR ++ "/juke-aim.png");
    confirmAim(g);
    g.st = .{};
    update(g, 0.06);
    try capture(g, target, SHOTS_DIR ++ "/juke.png");

    arena(g, .{ .x = 20, .y = 15 }, &.{});
    _ = spawnAt(g, .slime, .{ .x = 28, .y = 15 }, false);
    settle(g);
    g.rng = procRng(.burning_arrow, 1);
    useSkill(g, boundTo(g, .burning_arrow));
    try capture(g, target, SHOTS_DIR ++ "/burning-aim.png");
    confirmAim(g);
    g.st = .{};
    update(g, 0.08);
    try capture(g, target, SHOTS_DIR ++ "/burning-arrow.png");
    update(g, 0.10);
    try capture(g, target, SHOTS_DIR ++ "/burning.png");

    arena(g, .{ .x = 20, .y = 15 }, &.{});
    _ = spawnAt(g, .slime, .{ .x = 26, .y = 15 }, false);
    _ = spawnAt(g, .slime, .{ .x = 27, .y = 14 }, false);
    _ = spawnAt(g, .slime, .{ .x = 28, .y = 16 }, false);
    settle(g);
    g.rng = procRng(.glacial_shot, 3);
    useSkill(g, boundTo(g, .glacial_shot));
    try capture(g, target, SHOTS_DIR ++ "/glacial-aim.png");
    confirmAim(g);
    g.st = .{};
    update(g, 0.05);
    try capture(g, target, SHOTS_DIR ++ "/glacial-arrow.png");
    update(g, 0.14);
    try capture(g, target, SHOTS_DIR ++ "/glacial.png");
    drawnOut(g);
    posePicker(g, boundTo(g, .glacial_shot));
    try capture(g, target, SHOTS_DIR ++ "/glacial-bind.png");

    poseFright(g);
    if (speechLeft(g) <= fx.SPEECH_FADE_S) return error.FrightUnspoken;
    try capture(g, target, SHOTS_DIR ++ "/pib-fright.png");
    update(g, speechLeft(g) - fx.SPEECH_FADE_S / 2);
    try capture(g, target, SHOTS_DIR ++ "/pib-fright-fade.png");

    poseGas(g);
    try capture(g, target, SHOTS_DIR ++ "/gas.png");

    openPause(g);
    try capture(g, target, SHOTS_DIR ++ "/pause.png");
    g.mode = g.paused_from;

    poseWaterSteps(g);
    try capture(g, target, SHOTS_DIR ++ "/water-steps.png");

    poseForest(g);
    try capture(g, target, SHOTS_DIR ++ "/forest.png");
    for ([_]struct { hour: f32, name: [:0]const u8 }{
        .{ .hour = MORNING, .name = SHOTS_DIR ++ "/shadows-morning.png" },
        .{ .hour = day.NOON, .name = SHOTS_DIR ++ "/shadows-noon.png" },
        .{ .hour = 17, .name = SHOTS_DIR ++ "/shadows-evening.png" },
        .{ .hour = day.DEAD_OF_NIGHT, .name = SHOTS_DIR ++ "/shadows-moon.png" },
    }) |study| {
        poseShadowStudy(g, study.hour, true);
        try capture(g, target, study.name);
    }
    poseShadowStudy(g, day.NOON, false);
    try capture(g, target, SHOTS_DIR ++ "/shadows-torch.png");
    for ([_]struct { hour: ?f32, path: [:0]const u8 }{
        .{ .hour = MORNING, .path = SHOTS_DIR ++ "/shadows-hidden-sun.png" },
        .{ .hour = 22.5, .path = SHOTS_DIR ++ "/shadows-hidden-moon.png" },
        .{ .hour = null, .path = SHOTS_DIR ++ "/shadows-hidden-torch.png" },
    }) |study| {
        poseHiddenShadows(g, study.hour);
        try checkHiddenShadowMask(g, target, true);
        try capture(g, target, study.path);
        @memset(&g.lv.lit, false);
        @memset(&g.lv.seen, true);
        g.light.settle(&g.lv);
        try checkHiddenShadowMask(g, target, false);
    }
    poseHiddenShadows(g, MORNING);
    g.cam.x = @floatFromInt(HIDDEN_SHADOW_X * CELL - g.screen.x);
    try checkHiddenShadowMask(g, target, true);
    try capture(g, target, SHOTS_DIR ++ "/shadows-offscreen.png");

    try shootHud(g);

    {
        const w = try std.heap.c_allocator.create(atlas.Atlas);
        defer std.heap.c_allocator.destroy(w);
        try overviews(g, w);
        {
            try w.load(std.heap.c_allocator, atlas.worldPath(SHOT_BIOME));
            beginWorldAt(g, w, w.start, SHOT_SEED);
            try capture(g, target, SHOTS_DIR ++ "/biome.png");
        }
        {
            try w.load(std.heap.c_allocator, atlas.START);
            beginWorldAt(g, w, w.start, SHOT_SEED);
            for (0..RAIN_FRAMES) |_| update(g, mathx.FRAME_DT);
            try capture(g, target, SHOTS_DIR ++ "/strand.png");
            try checkWaterShimmer(g);
            try shootWater(g, target);
        }
        {
            try w.load(std.heap.c_allocator, atlas.worldPath(SHOT_OUTDOOR));
            for (SHOT_HOURS) |s| {
                beginWorldAt(g, w, w.start, SHOT_SEED);
                g.lv.seen = @splat(false);
                g.clock = day.Clock.at(s.hour);
                settle(g);
                try capture(g, target, s.path);
            }
            g.clock = day.Clock.at(day.NOON);
            settle(g);
            g.clock = day.Clock.at(day.DEAD_OF_NIGHT);
            settle(g);
            try capture(g, target, SHOTS_DIR ++ "/night-memory.png");
        }
        begin(g, SHOT_SEED);
    }

    try editor.shoot(g, target, SHOTS_DIR ++ "/edit.png", SHOTS_DIR ++ "/edit-graph.png", SHOTS_DIR ++ "/edit-gen.png", SHOTS_DIR ++ "/edit-objects.png");

    const entry = naming.Entry{ .name = heroes.Name.of("Arwen"), .row = 2, .col = 4 };
    rl.beginTextureMode(target);
    rl.clearBackground(look.BG);
    var title: [naming.TITLE_MAX]u8 = undefined;
    naming.draw(&entry, g.face, g.screen, naming.titleOf(heroes.DEFAULT, &title));
    rl.endTextureMode();
    try exportTarget(target, SHOTS_DIR ++ "/name.png");
}

fn shootHud(g: *Game) !void {
    const screen = g.screen;
    defer g.screen = screen;
    var saved_bar: skillbar.Bar = .{};
    saved_bar = g.bar;
    defer g.bar = saved_bar;
    var saved_state: input.State = .{};
    saved_state = g.st;
    defer g.st = saved_state;
    const studies = [_]struct { screen: P, hp: i32, mana: i32, device: input.Device, path: [:0]const u8, ailing: bool = false, bind: ?[:0]const u8 = null }{
        .{ .screen = .{ .x = 1280, .y = 720 }, .hp = 100, .mana = 100, .device = .keys, .path = SHOTS_DIR ++ "/hud-full-1280.png", .bind = SHOTS_DIR ++ "/hud-bind-720.png" },
        .{ .screen = .{ .x = 1280, .y = 720 }, .hp = 75, .mana = 60, .device = .ps5, .path = SHOTS_DIR ++ "/hud-ps5-1280.png", .bind = SHOTS_DIR ++ "/hud-bind-ps5.png" },
        .{ .screen = .{ .x = 1600, .y = 900 }, .hp = 50, .mana = 35, .device = .xbox, .path = SHOTS_DIR ++ "/hud-partial-1600.png", .ailing = true },
        .{ .screen = .{ .x = 1920, .y = 1080 }, .hp = 10, .mana = 0, .device = .keys, .path = SHOTS_DIR ++ "/hud-critical-1920.png" },
        .{ .screen = .{ .x = 1600, .y = 900 }, .hp = 0, .mana = 0, .device = .keys, .path = SHOTS_DIR ++ "/hud-empty-1600.png" },
    };
    for (studies) |study| {
        g.screen = study.screen;
        poseForest(g);
        g.bar = skillbar.Bar.of(g.class);
        g.st = .{ .device = study.device, .modifier = g.bar.modifier };
        const body = &g.pictured[heroSlot(g).?];
        body.hp = @divTrunc(body.max * study.hp, mathx.PERCENT);
        g.mana = @divTrunc(heroes.MANA * study.mana, mathx.PERCENT);
        if (study.ailing) {
            body.status = .initDefault(0, .{ .bleeding = bleeding.TURNS, .burning = burning.TURNS, .chilled = glacial.TURNS - 1 });
            g.cooldown.set(.juke, juke.COOLDOWN);
        }
        const target = try renderTarget(g);
        defer rl.unloadRenderTexture(target);
        try capture(g, target, study.path);
        if (study.bind) |path| {
            posePicker(g, boundTo(g, .shoot));
            try capture(g, target, path);
        }
        if (study.ailing) {
            g.bar.bind(.{ .set = .secondary, .button = .x }, .glacial_shot);
            g.bar.bind(.{ .set = .secondary, .button = .b }, .burning_arrow);
            g.st.down.insert(g.bar.modifier.?);
            try capture(g, target, SHOTS_DIR ++ "/hud-secondary-pad.png");
            g.st.down = .initEmpty();
            posePicker(g, boundTo(g, .shoot));
            try capture(g, target, SHOTS_DIR ++ "/hud-bind-pad.png");
            g.mode = .inspect;
            g.inspecting = .{ .slot = Binds.colOf(.x) };
            try capture(g, target, SHOTS_DIR ++ "/hud-inspect-skill.png");
            g.inspecting = .{ .status = .burning };
            try capture(g, target, SHOTS_DIR ++ "/hud-inspect-status.png");
            g.inspecting = .mana;
            try capture(g, target, SHOTS_DIR ++ "/hud-inspect-mana.png");
            g.mode = .play;
        }
    }
    std.debug.print("HUD: {d} resource states captured, with every prompt device, the secondary set and the bind picker\n", .{studies.len});
    promptRoom(g);
}

const PROMPT_GAP_MIN: i32 = 4;

fn promptRoom(g: *const Game) void {
    var least: i32 = std.math.maxInt(i32);
    for (std.enums.values(input.Device)) |d| {
        const st = input.State{ .device = d, .modifier = g.bar.modifier };
        for (skillbar.SLOTS[0 .. skillbar.SLOTS.len - 1], skillbar.SLOTS[1..], SLOT_XS[0 .. SLOT_XS.len - 1], SLOT_XS[1..]) |a, b, xa, xb| {
            const wa = look.Prompt.of(&st, a).width(&g.face, PROMPT_PX);
            const wb = look.Prompt.of(&st, b).width(&g.face, PROMPT_PX);
            least = @min(least, xb - xa - @divTrunc(wa + wb, 2));
        }
    }
    std.debug.print("slot prompts: {d} px apart at the closest\n", .{least});
    std.debug.assert(least >= PROMPT_GAP_MIN);
}

fn boundTo(g: *const Game, act: skillbar.Act) Use {
    for (skillbar.SETS) |s| {
        if (g.bar.buttonOf(s, act)) |b| return .{ .act = act, .by = b, .set = s };
    }
    unreachable;
}

const POSE_BURST = P{ .x = 25, .y = 15 };
const MORNING: f32 = 9;
const POSE_GAS_TURNS: usize = 3;

fn posePicker(g: *Game, u: Use) void {
    openBinds(g);
    g.binds.row = Binds.rowOf(u.set);
    g.binds.col = Binds.colOf(u.by);
    g.binds.menu = .{ .pick = pickOf(skillbar.kit(g.class), g.bar.at(g.binds.slot())) };
}

/// Wall from `lo` to `hi`, both inclusive.
fn wallIn(lv: *grid.Level, lo: P, hi: P) void {
    carve.box(lv, grid.Box.between(lo, hi), .wall);
}

fn wallRow(lv: *grid.Level, y: i32, x0: i32, x1: i32) void {
    wallIn(lv, .{ .x = x0, .y = y }, .{ .x = x1, .y = y });
}

fn poseFright(g: *Game) void {
    const hero = P{ .x = 20, .y = 20 };
    arena(g, hero, &.{.{ .x = 23, .y = 20 }});
    const pibs = [fx.FRIGHT_WORDS.len]P{ .{ .x = 23, .y = 17 }, .{ .x = 26, .y = 19 }, .{ .x = 26, .y = 22 }, .{ .x = 21, .y = 23 } };
    var slots: [pibs.len]usize = undefined;
    for (pibs, &slots) |p, *s| s.* = actor.Pool.slot(spawnAt(g, .pib, p, false));
    settle(g);
    const wait: f32 = 0.2;
    wound(g, 2, actor.row(.rat).hp, SHOOT, .{ .from = hero, .wait = wait });
    g.lead = wait;
    endTurn(g);
    g.st = .{};
    update(g, 0);
    for (0..18) |_| update(g, mathx.FRAME_DT);
    for (slots, 0..) |s, i| g.fx.speech[s].word = i;
}

fn speechLeft(g: *const Game) f32 {
    var most: f32 = 0;
    for (g.fx.speech[0..g.pool.n]) |s| most = @max(most, s.life);
    return most;
}

fn poseGas(g: *Game) void {
    arena(g, .{ .x = 18, .y = 16 }, &.{});
    wallRow(&g.lv, 10, 13, 31);
    wallRow(&g.lv, 21, 13, 31);
    wallIn(&g.lv, .{ .x = 13, .y = 10 }, .{ .x = 13, .y = 21 });
    wallIn(&g.lv, .{ .x = 31, .y = 10 }, .{ .x = 31, .y = POSE_BURST.y - 1 });
    wallIn(&g.lv, .{ .x = 31, .y = POSE_BURST.y + 1 }, .{ .x = 31, .y = 21 });
    g.lv.addTorch(.{ .x = 22, .y = 10 });
    _ = g.pool.spawn(&g.lv, actor.Actor.of(.bloat, .{ .x = 16, .y = 12 }));
    g.lv.addGas(POSE_BURST, gas.BURST);
    for (0..POSE_GAS_TURNS) |_| gas.turn(&g.lv, &g.rng);
    posed(g, false);
}

const POSE_TORCH = P{ .x = 20, .y = 10 };

const Wader = struct { kind: actor.Kind, at: P };

const WADERS = [_]Wader{
    .{ .kind = .rat, .at = .{ .x = 23, .y = 20 } },
    .{ .kind = .bloat, .at = .{ .x = 26, .y = 20 } },
    .{ .kind = .pib, .at = .{ .x = 20, .y = 23 } },
    .{ .kind = .slime, .at = .{ .x = 23, .y = 23 } },
    .{ .kind = .slime_half, .at = .{ .x = 26, .y = 23 } },
    .{ .kind = .slime_quarter, .at = .{ .x = 23, .y = 17 } },
    .{ .kind = .wizard, .at = .{ .x = 20, .y = 17 } },
    .{ .kind = .knight, .at = .{ .x = 26, .y = 17 } },
};

comptime {
    var seen = std.EnumSet(actor.Kind).initOne(HERO);
    for (WADERS) |w| {
        std.debug.assert(!seen.contains(w.kind));
        seen.insert(w.kind);
    }
    std.debug.assert(seen.count() == std.enums.values(actor.Kind).len);
}

fn poseWaterSteps(g: *Game) void {
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    grassOver(&g.lv);
    var cells = grid.Cells.of(.{ .x = 17, .y = 15 }, .{ .x = 30, .y = 26 });
    while (cells.next()) |p| g.lv.set(p, if (p.x < 19) .water else .shallows);
    for (WADERS) |w| _ = spawnAt(g, w.kind, w.at, false);
    settle(g);
    g.st = .{};
    for (g.pool.slice(), 0..) |a, i| {
        const to = a.at.add(mathx.Dir.e.delta());
        g.pool.move(&g.lv, actor.Pool.idOf(i), to);
        g.glide[i] = g.glide[i].toward(to, g.glide[i].span() * (SPLASH_AT + 0.01));
    }
    update(g, 0);
    update(g, 0.055);
}

fn poseForest(g: *Game) void {
    arena(g, .{ .x = 24, .y = 18 }, &.{});
    grassOver(&g.lv);
    const rows = [_][]const u8{
        "...................",
        ".#####...####......",
        ".#...#...####..#...",
        ".#...#...####......",
        ".#.......#.....#...",
        ".#####...###.......",
        ".............#.....",
        ".#..#..#..#..#..#..",
        "...................",
    };
    for (rows, 0..) |row, y| {
        for (row, 0..) |ch, x| {
            if (ch == '#') g.lv.set(.{ .x = 16 + @as(i32, @intCast(x)), .y = 12 + @as(i32, @intCast(y)) }, .shrub);
        }
    }
    posed(g, g.outdoors);
}

fn poseShadowStudy(g: *Game, hour: f32, outdoors: bool) void {
    arena(g, .{ .x = 24, .y = 21 }, &.{.{ .x = 29, .y = 22 }});
    grassOver(&g.lv);
    wallRow(&g.lv, 16, 22, 26);
    if (!outdoors) g.lv.addTorch(.{ .x = 24, .y = 16 });
    const props = [_]struct { t: grid.Tile, p: P }{
        .{ .t = .wall, .p = .{ .x = 16, .y = 19 } },
        .{ .t = .wall, .p = .{ .x = 17, .y = 19 } },
        .{ .t = .rock, .p = .{ .x = 20, .y = 19 } },
        .{ .t = .shrub, .p = .{ .x = 23, .y = 19 } },
        .{ .t = .shrub, .p = .{ .x = 24, .y = 19 } },
        .{ .t = .shrub, .p = .{ .x = 25, .y = 19 } },
        .{ .t = .boulder, .p = .{ .x = 28, .y = 19 } },
        .{ .t = .fungus, .p = .{ .x = 31, .y = 19 } },
        .{ .t = .shrub, .p = .{ .x = 16, .y = 23 } },
        .{ .t = .shrub, .p = .{ .x = 19, .y = 23 } },
        .{ .t = .tiny_shrub, .p = .{ .x = 22, .y = 23 } },
        .{ .t = .tall_grass, .p = .{ .x = 24, .y = 24 } },
        .{ .t = .shrooms, .p = .{ .x = 26, .y = 23 } },
        .{ .t = .fence, .p = .{ .x = 17, .y = 16 } },
        .{ .t = .grave, .p = .{ .x = 20, .y = 16 } },
        .{ .t = .reeds, .p = .{ .x = 28, .y = 16 } },
        .{ .t = .crop, .p = .{ .x = 31, .y = 16 } },
    };
    for (props) |prop| g.lv.set(prop.p, prop.t);
    g.lv.putBarrel(.{ .x = 32, .y = 23 });
    _ = spawnAt(g, .slime, .{ .x = 31, .y = 22 }, false);
    studyAt(g, outdoors, hour);
    @memset(&g.lv.seen, true);
    @memset(&g.lv.lit, true);
    g.light.settle(&g.lv);
}

fn studyAt(g: *Game, outdoors: bool, hour: f32) void {
    g.clock = day.Clock.at(hour);
    posed(g, outdoors);
}

fn posed(g: *Game, outdoors: bool) void {
    g.outdoors = outdoors;
    gen.shapeWalls(&g.lv);
    settle(g);
}

fn poseTorch(g: *Game) void {
    arena(g, .{ .x = 20, .y = 15 }, &.{ .{ .x = 17, .y = 12 }, .{ .x = 23, .y = 13 } });
    wallRow(&g.lv, POSE_TORCH.y, 12, 28);
    g.lv.set(.{ .x = 22, .y = 12 }, .wall);
    g.lv.addTorch(POSE_TORCH);
    posed(g, false);
}

const HIDDEN_SHADOW_X: i32 = 27;
const Hidden = enum { forest, tree, barrel, actor };
const HIDDEN_SHADOW_ROWS = std.EnumArray(Hidden, i32).init(.{ .forest = 14, .tree = 17, .barrel = 20, .actor = 23 });

fn poseHiddenShadows(g: *Game, hour: ?f32) void {
    const x = HIDDEN_SHADOW_X;
    const row = HIDDEN_SHADOW_ROWS;
    arena(g, .{ .x = 22, .y = 19 }, &.{.{ .x = x, .y = row.get(.actor) }});
    grassOver(&g.lv);
    g.lv.set(.{ .x = x, .y = row.get(.forest) }, .shrub);
    g.lv.set(.{ .x = x, .y = row.get(.forest) + 1 }, .shrub);
    g.lv.set(.{ .x = x, .y = row.get(.tree) }, .shrub);
    g.lv.putBarrel(.{ .x = x, .y = row.get(.barrel) });
    if (hour == null) {
        wallRow(&g.lv, 12, 29, 31);
        g.lv.addTorch(.{ .x = 30, .y = 12 });
        wallRow(&g.lv, 18, 29, 31);
        g.lv.addTorch(.{ .x = 30, .y = 18 });
    }
    studyAt(g, hour != null, hour orelse day.NOON);
    for (0..grid.CELLS) |i| {
        const visible = grid.Level.of(i).x < x;
        g.lv.seen[i] = visible;
        g.lv.lit[i] = visible;
    }
    g.light.settle(&g.lv);
}

fn grassOver(lv: *grid.Level) void {
    for (&lv.tile) |*t| {
        if (t.* == .floor) t.* = .grass;
    }
}

fn waterSample(g: *Game, target: rl.RenderTexture2D, beds: *const dual.Beds, visibility: rl.Texture2D, seconds: ?f32, origin: [2]f32) !rl.Image {
    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color.blank);
    const view: ?look.WaterView = if (seconds) |t| .{ .seconds = t, .screen_h = @floatFromInt(target.texture.height), .visibility = visibility } else null;
    g.sprites.drawGround(beds, origin, CELL_F, view);
    rl.endTextureMode();
    return readTarget(target);
}

fn shootWater(g: *Game, target: rl.RenderTexture2D) !void {
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/water-shimmer");
    g.st = .{};
    const FRAMES = 40;
    const EVERY = 6;
    const before = g.light.t.at();
    const minute = g.clock;
    for (0..FRAMES) |i| {
        for (0..EVERY) |_| update(g, mathx.FRAME_DT);
        var path: [80]u8 = undefined;
        try capture(g, target, try std.fmt.bufPrintZ(&path, SHOTS_DIR ++ "/water-shimmer/{d:0>2}.png", .{i}));
    }
    const elapsed = g.light.t.at() - before;
    if (elapsed < FRAMES * EVERY * mathx.FRAME_DT - 0.01 or !std.meta.eql(minute, g.clock)) return error.WaterIdleClock;
    std.debug.print("water shimmer idle play: {d:.2} seconds in {d} rendered frames, no turn spent\n", .{ elapsed, FRAMES });
}

/// The least change in red, of 255, a highlight counts as visibly shimmering by.
const SHIMMER_PRONOUNCED: i32 = 8;

fn checkWaterShimmer(g: *Game) !void {
    const BANDS = [_]grid.Tile{ .water, .shallows, .grass };
    const BAND = 4;
    const ROWS = 2;
    const LATER: f32 = 1.25;
    const SHIFT = [2]i32{ 16, 8 };
    const width = BANDS.len * BAND * CELL;
    const height = ROWS * CELL;
    const target = try rl.loadRenderTexture(width, height);
    defer rl.unloadRenderTexture(target);
    var lv = grid.Level.blank();
    for (&lv.tile, 0..) |*t, i| {
        const x: usize = @intCast(grid.Level.of(i).x);
        t.* = BANDS[@min(x / BAND, BANDS.len - 1)];
    }
    var beds: dual.Beds = undefined;
    beds.fill(&lv, .{ .x = 0, .y = 0 }, .{ .x = BANDS.len * BAND, .y = ROWS }, false);
    var sight: [grid.CELLS]rl.Color = @splat(rl.Color.blank);
    @memset(sight[0..grid.COLS], rl.Color.white);
    const visibility = look.clamped(look.rgba(&sight, grid.W, grid.H), .point) orelse return error.WaterVisibilityMissing;
    defer rl.unloadTexture(visibility);
    const plain = try waterSample(g, target, &beds, visibility, null, .{ 0, 0 });
    defer rl.unloadImage(plain);
    const first = try waterSample(g, target, &beds, visibility, 0, .{ 0, 0 });
    defer rl.unloadImage(first);
    if (!rl.exportImage(first, SHOTS_DIR ++ "/water-shimmer-a.png")) return error.ExportFailed;
    const second = try waterSample(g, target, &beds, visibility, LATER, .{ 0, 0 });
    defer rl.unloadImage(second);
    if (!rl.exportImage(second, SHOTS_DIR ++ "/water-shimmer-b.png")) return error.ExportFailed;
    var changed = [_]usize{0} ** BANDS.len;
    var pronounced = [_]usize{0} ** BANDS.len;
    var fixed: usize = 0;
    var y: i32 = 0;
    while (y < height) : (y += 1) {
        var x: i32 = 0;
        while (x < width) : (x += 1) {
            const base = rl.getImageColor(plain, x, y);
            const a = rl.getImageColor(first, x, y);
            const b = rl.getImageColor(second, x, y);
            if (a.a != base.a or b.a != base.a) return error.WaterAlphaChanged;
            const in_band = @mod(x, BAND * CELL);
            if (in_band < HALF_CELL or in_band >= BAND * CELL - HALF_CELL) continue;
            const band: usize = @intCast(@divTrunc(x, BAND * CELL));
            const highlight = look.shimmers(dual.of(BANDS[band]).?, base);
            if (y >= CELL or !highlight) {
                if (!std.meta.eql(base, a) or !std.meta.eql(base, b)) return error.WaterChangedOutsideHighlights;
                fixed += 1;
            } else if (!std.meta.eql(a, b)) {
                changed[band] += 1;
                if (@abs(@as(i32, a.r) - b.r) >= SHIMMER_PRONOUNCED) pronounced[band] += 1;
            }
        }
    }
    if (changed[0] == 0 or changed[1] == 0) return error.WaterShimmerMissing;
    if (pronounced[0] < 100 or pronounced[1] < 100) return error.WaterShimmerTooFaint;
    const shifted = try waterSample(g, target, &beds, visibility, LATER, .{ -SHIFT[0], -SHIFT[1] });
    defer rl.unloadImage(shifted);
    var compared: usize = 0;
    y = 0;
    while (y < height - SHIFT[1]) : (y += 1) {
        var x: i32 = 0;
        while (x < width - SHIFT[0]) : (x += 1) {
            const a = rl.getImageColor(second, x + SHIFT[0], y + SHIFT[1]);
            const b = rl.getImageColor(shifted, x, y);
            if (@abs(@as(i32, a.r) - b.r) > 1 or @abs(@as(i32, a.g) - b.g) > 1 or @abs(@as(i32, a.b) - b.b) > 1 or a.a != b.a) return error.WaterMovesWithCamera;
            compared += 1;
        }
    }
    std.debug.print("water shimmer GPU: {d} deep and {d} shallow highlights changed; {d} base, outline, grass and memory pixels fixed; {d} camera samples agree\n", .{ changed[0], changed[1], fixed, compared });
    std.debug.print("water shimmer contrast: {d} deep and {d} shallow highlights changed by at least {d}/255\n", .{ pronounced[0], pronounced[1], SHIMMER_PRONOUNCED });
}

fn checkHiddenShadowMask(g: *Game, target: rl.RenderTexture2D, visible: bool) !void {
    prepare(g);
    const c = Cam.of(g);
    const view = viewBox(g, c);
    g.light.bake(&g.lv, view.lo, view.hi);
    {
        rl.beginTextureMode(target);
        defer rl.endTextureMode();
        rl.clearBackground(rl.Color.white);
        if (!shadowPass(g, c, view, target.id)) return error.ShadowShaderMissing;
    }
    const img = try readTarget(target);
    defer rl.unloadImage(img);
    var hits = std.EnumArray(Hidden, usize).initFill(0);
    var leaked: usize = 0;
    var y: i32 = 0;
    while (y < g.screen.y) : (y += 1) {
        var x: i32 = 0;
        while (x < g.screen.x) : (x += 1) {
            const rgb = rl.getImageColor(img, x, y);
            if (rgb.r >= 252 and rgb.g >= 252 and rgb.b >= 252) continue;
            const world_x = x + c.x;
            const world_y = y + c.y;
            if (!visible or world_x >= (HIDDEN_SHADOW_X + 1) * CELL) leaked += 1;
            if (world_x < (HIDDEN_SHADOW_X - 2) * CELL or world_x >= HIDDEN_SHADOW_X * CELL) continue;
            for (std.enums.values(Hidden)) |k| {
                const row = HIDDEN_SHADOW_ROWS.get(k);
                if (world_y >= (row - 1) * CELL and world_y < (row + 2) * CELL) hits.getPtr(k).* += 1;
            }
        }
    }
    std.debug.print("hidden shadow GPU check ({s}):", .{if (visible) "sight" else "memory"});
    for (std.enums.values(Hidden)) |k| std.debug.print(" {s} {d}", .{ @tagName(k), hits.get(k) });
    std.debug.print(" pixels; {d} outside visible ground\n", .{leaked});
    if (leaked != 0) return error.ShadowOutsideSight;
    if (visible) for (hits.values) |hit| {
        if (hit == 0) return error.HiddenShadowMissing;
    };
}

fn drawInto(g: *Game, target: rl.RenderTexture2D) void {
    prepare(g);
    rl.beginTextureMode(target);
    g.framebuffer = target.id;
    defer g.framebuffer = 0;
    drawFrame(g);
    rl.endTextureMode();
}

const OVERVIEW_CELL: i32 = 10;
const OVERVIEW_MID: i32 = @divTrunc(OVERVIEW_CELL, 2);
/// A glyph a little bigger than its cell, so the font's side bearings leave no gaps.
const OVERVIEW_INK: i32 = OVERVIEW_CELL + 2;
const SHOT_BIOME = "qud/qud_salt_marsh";
/// Frames the strand's shot lets its rain fall first, so drops and splashes are both under way.
const RAIN_FRAMES: usize = 90;
const SHOT_OUTDOOR = "wilds";
const SHOT_HOURS = [_]struct { hour: f32, path: [:0]const u8 }{
    .{ .hour = 7.0, .path = SHOTS_DIR ++ "/dawn.png" },
    .{ .hour = day.NOON, .path = SHOTS_DIR ++ "/noon.png" },
    .{ .hour = 16.5, .path = SHOTS_DIR ++ "/day.png" },
    .{ .hour = 19.3, .path = SHOTS_DIR ++ "/dusk.png" },
    .{ .hour = day.DEAD_OF_NIGHT, .path = SHOTS_DIR ++ "/night.png" },
};

fn overviews(g: *Game, w: *atlas.Atlas) !void {
    const target = try rl.loadRenderTexture(grid.W * OVERVIEW_CELL, grid.H * OVERVIEW_CELL);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_WORLDS);
    var list = atlas.Listing{};
    list.scanAll();
    for (0..list.n) |i| {
        try w.load(std.heap.c_allocator, list.at(i));
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
            const cx = x + OVERVIEW_MID;
            const cy = y + OVERVIEW_MID;
            if (look.Mark.of(&g.lv, k)) |m| {
                g.face.glyph(m.look().ch, cx, cy, OVERVIEW_INK, m.look().fg);
            } else look.inkTile(&g.face, t, cx, cy, OVERVIEW_INK);
        }
        for (g.lv.torches()) |t| g.face.glyph(look.TORCH.ch, t.x * OVERVIEW_CELL + OVERVIEW_MID, t.y * OVERVIEW_CELL + OVERVIEW_MID, OVERVIEW_INK, look.TORCH.fg);
        rl.endTextureMode();
        var buf: [atlas.PATH_MAX + 32]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, SHOTS_WORLDS ++ "/{s}.png", .{list.stem(i)});
        try exportTarget(target, name);
    }
}

fn capture(g: *Game, target: rl.RenderTexture2D, path: [:0]const u8) !void {
    drawInto(g, target);
    try exportTarget(target, path);
}

/// The target's pixels, top row first; the caller unloads it.
fn readTarget(target: rl.RenderTexture2D) !rl.Image {
    var img = try rl.loadImageFromTexture(target.texture);
    rl.imageFlipVertical(&img);
    return img;
}

pub fn exportTarget(target: rl.RenderTexture2D, path: [:0]const u8) !void {
    errdefer std.debug.print("{s} FAILED\n", .{path});
    var img = try readTarget(target);
    defer rl.unloadImage(img);
    // Blending leaves alpha in the target that a window never shows.
    rl.imageFormat(&img, .uncompressed_r8g8b8);
    if (!rl.exportImage(img, path)) return error.ExportFailed;
    std.debug.print("{s} written\n", .{path});
}

pub fn bench() !void {
    try withGame(.{ .window_hidden = true }, "roguelike --bench", benchWalk);
}

const BENCH_FRAMES: usize = 3600;

fn ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
}

fn benchWalk(g: *Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    var t = try std.time.Timer.start();
    begin(g, SHOT_SEED);
    prepare(g);
    std.debug.print("first map: {d:.3} ms, {d} map textures\n", .{ ms(t.read()), g.sprites.count() });
    var rng = mathx.Rng.init(SHOT_SEED);
    var d: mathx.Dir = .e;
    const dt = mathx.FRAME_DT;
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
        std.debug.print("{s}: mean {d:.3} ms, p99 {d:.3} ms, max {d:.3} ms\n", .{ name, ms(sum / xs.len), ms(xs[xs.len * 99 / 100]), ms(xs[xs.len - 1]) });
    }
    try benchAssets(g);
}

fn benchAssets(g: *Game) !void {
    const alloc = std.heap.c_allocator;
    const w = try alloc.create(atlas.Atlas);
    defer alloc.destroy(w);
    defer g.world = null;
    inline for ([_][]const u8{ SHOT_OUTDOOR, SHOT_BIOME, SHOT_OUTDOOR }) |name| {
        try w.load(alloc, atlas.worldPath(name));
        beginWorldAt(g, w, w.start, SHOT_SEED);
        var t = try std.time.Timer.start();
        prepare(g);
        const loaded = t.read();
        if (!std.meta.eql(mapAssets(g), g.sprites.resident())) return error.MissingMapAsset;
        const held = g.sprites;
        g.art_ready = false;
        t.reset();
        prepare(g);
        const reused = t.read();
        if (!std.meta.eql(held, g.sprites)) return error.ReloadedMapAsset;
        std.debug.print("assets {s}: {d} textures, {d:.3} ms; unchanged map {d:.3} ms, all textures reused\n", .{ name, g.sprites.count(), ms(loaded), ms(reused) });
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

fn arena(g: *Game, hero: P, rats: []const P) void {
    g.lv = grid.openFloor();
    reset(g, hero);
    g.outdoors = true;
    g.clock = day.Clock.at(day.NOON);
    for (rats) |r| _ = g.pool.spawn(&g.lv, actor.Actor.of(.rat, r));
    settle(g);
}

fn rngWhere(want: anytype) mathx.Rng {
    var seed: u64 = 0;
    while (true) : (seed += 1) {
        var rng = mathx.Rng.init(seed);
        if (want.holds(&rng)) return mathx.Rng.init(seed);
    }
}

/// An RNG matching `confirmAim` that afflicts the first `procs` body hits.
fn procRng(comptime act: skillbar.Act, procs: usize) mathx.Rng {
    const Procs = struct {
        n: usize,
        fn holds(p: @This(), rng: *mathx.Rng) bool {
            _ = rollArrow(rng, act, true);
            for (0..p.n) |_| {
                if (!skillbar.Act.arrow(act).procs(rng, 0)) return false;
            }
            return true;
        }
    };
    return rngWhere(Procs{ .n = procs });
}

test "skills cannot start a second turn while the first is still being drawn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const clock = g.clock;
    const hp = g.archer().?.hp;
    g.busy = 0.5;
    var bound: usize = 0;
    for (skillbar.SLOTS) |button| {
        const act = g.bar.at(.{ .set = .primary, .button = button }) orelse continue;
        if (act == .secondary) continue;
        bound += 1;
        g.st = .{ .pressed = .initOne(button) };
        update(g, 0);
        try std.testing.expectEqual(Mode.play, g.mode);
        try std.testing.expectEqual(clock, g.clock);
        try std.testing.expectEqual(hp, g.archer().?.hp);
        try std.testing.expectEqual(heroes.MANA, g.mana);
    }
    g.busy = 0;
    openAim(g, .x, .shoot);
    try std.testing.expectEqual(Mode.aim, g.mode);
    g.busy = 0.5;
    confirmAim(g);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expect(g.shot == null);
    g.busy = 0;
    confirmAim(g);
    try std.testing.expect(!std.meta.eql(clock, g.clock));
    try std.testing.expect(g.shot != null);
    std.debug.print("{d} bound skills blocked during animation; shooting resumes when quiet\n", .{bound});
}

fn wakeFoes(g: *Game) void {
    for (g.pool.slice()[1..]) |*a| a.awake = true;
}

fn toughenFoes(g: *Game) void {
    for (g.pool.slice()[1..]) |*a| toughen(a);
}

fn staggerOnly(g: *Game, id: u16) void {
    g.order[0] = id;
    g.order_n = 1;
    g.lead = 0;
    stepGlide(g, 0);
}

fn stepTo(g: *Game, id: u16, to: P) void {
    g.pool.move(&g.lv, id, to);
    stepGlide(g, 0);
}

const TRIES: usize = 300;

fn aboutRate(hits: usize, rate: f32) bool {
    const got = @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(TRIES));
    return @abs(got - rate) < 0.08;
}

fn deathDrawn(g: *Game, _: usize) bool {
    return deathShown(g);
}

fn calm(g: *Game) void {
    g.busy = 0;
    g.pending = null;
}

fn press(g: *Game, a: input.Button) void {
    pressHolding(g, a, &.{});
}

fn use(g: *Game, act: skillbar.Act) void {
    const u = boundTo(g, act);
    if (u.set == .secondary) pressHolding(g, u.by, &.{g.bar.modifier.?}) else press(g, u.by);
}

fn expectWithin(v: anytype, lo: @TypeOf(v), hi: @TypeOf(v)) !void {
    if (v < lo or v > hi) {
        std.debug.print("{d} is outside {d} to {d}\n", .{ v, lo, hi });
        return error.TestUnexpectedResult;
    }
}

fn nudge(g: *Game, d: mathx.Dir) void {
    calm(g);
    g.st = .{ .walk = d };
    update(g, 0);
}

fn walkFrame(g: *Game, dt: f32, d: ?mathx.Dir) void {
    g.st.walk = if (d) |w| g.st.step.tick(dt, 1, w.heading(), input.Stepper.SETTLE) else g.st.step.tick(dt, 0, 0, input.Stepper.SETTLE);
    update(g, dt);
}

const TEST_DT = mathx.TEST_DT;
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

const TEST_HP: i32 = 100;

fn toughen(a: *actor.Actor) void {
    a.hp = TEST_HP;
    a.max = TEST_HP;
}

const TEST_GAS = 100;
const SLIME_HALF = actor.row(.slime_half).hp;

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

test "glacial shot spends only on confirmation and bursts at the first body with delayed chill and cone damage" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{
        .{ .x = 26, .y = 20 },
        .{ .x = 27, .y = 19 },
        .{ .x = 28, .y = 20 },
        .{ .x = 25, .y = 21 },
        .{ .x = 27, .y = 21 },
    });
    toughenFoes(g);
    g.pool.get(6).?.resists.set(.cold, 100);
    g.lv.set(.{ .x = 27, .y = 20 }, .wall);
    settle(g);
    const clock = g.clock;
    g.mana = glacial.COST - 1;
    pressHolding(g, .x, &.{.lb});
    try std.testing.expectEqual(Mode.play, g.mode);
    g.mana = heroes.MANA;
    pressHolding(g, .x, &.{.lb});
    try std.testing.expectEqual(Mode.aim, g.mode);
    press(g, .b);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(heroes.MANA, g.mana);
    pressHolding(g, .x, &.{.lb});
    g.mark = g.archer().?.at;
    pressHolding(g, .x, &.{.lb});
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(heroes.MANA, g.mana);
    g.mark = .{ .x = 26, .y = 20 };
    g.rng = procRng(.glacial_shot, 1);
    pressHolding(g, .x, &.{.lb});
    const direct = g.pool.get(2).?;
    const splash = g.pool.get(3).?;
    const dealt = TEST_HP - direct.hp;
    try std.testing.expect(dealt >= bow.DMG_LO + glacial.COLD_LO and dealt <= bow.DMG_HI + glacial.COLD_HI);
    try expectWithin(TEST_HP - splash.hp, glacial.COLD_LO, glacial.COLD_HI);
    for ([_]u16{ 4, 5, 6 }) |id| try std.testing.expectEqual(TEST_HP, g.pool.get(id).?.hp);
    try std.testing.expectEqual(@as(u8, 0), g.pool.get(6).?.chill.turns);
    try std.testing.expectEqual(manaAfter(.glacial_shot), g.mana);
    try std.testing.expectEqual(glacial.TURNS - 1, direct.chill.turns);
    try std.testing.expectEqual(@as(u8, 0), g.pictured[actor.Pool.slot(2)].status.get(.chilled));
    try std.testing.expectEqual(TEST_HP, g.pictured[actor.Pool.slot(3)].hp);
    try std.testing.expectEqual(skillbar.Act.glacial_shot, g.shot.?.act);
    drawnOut(g);
    try std.testing.expectEqual(direct.chill.turns, g.pictured[actor.Pool.slot(2)].status.get(.chilled));
    try std.testing.expectEqual(splash.hp, g.pictured[actor.Pool.slot(3)].hp);
    std.debug.print("Glacial Shot: {d} direct, {d} cone damage; 3 protected targets untouched; mana {d}; chill shown at impact\n", .{ dealt, TEST_HP - splash.hp, g.mana });
}

test "glacial shot uses an intervening body or barrel and an empty shot has no cone" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    arena(g, from, &.{ .{ .x = 24, .y = 20 }, .{ .x = 28, .y = 20 } });
    const near = g.pool.get(2).?;
    near.resists.set(.cold, 100);
    pressHolding(g, .x, &.{.lb});
    g.mark = .{ .x = 28, .y = 20 };
    pressHolding(g, .x, &.{.lb});
    try std.testing.expect(near.hp >= actor.row(.rat).hp - bow.DMG_HI and near.hp <= actor.row(.rat).hp - bow.DMG_LO);
    try std.testing.expectEqual(@as(u8, 0), near.chill.turns);
    try std.testing.expectEqual(actor.row(.rat).hp, g.pool.get(3).?.hp);
    arena(g, from, &.{.{ .x = 26, .y = 20 }});
    const barrel = P{ .x = 24, .y = 20 };
    g.lv.putBarrel(barrel);
    pressHolding(g, .x, &.{.lb});
    pressHolding(g, .x, &.{.lb});
    try std.testing.expect(!g.lv.hasBarrel(barrel));
    try std.testing.expect(g.gold > 0);
    const splash = actor.row(.rat).hp - g.pool.get(2).?.hp;
    try expectWithin(splash, glacial.COLD_LO, glacial.COLD_HI);
    arena(g, from, &.{.{ .x = 26, .y = 21 }});
    pressHolding(g, .x, &.{.lb});
    g.mark = .{ .x = 25, .y = 20 };
    pressHolding(g, .x, &.{.lb});
    try std.testing.expect(g.shot.?.flight.struck == null);
    try std.testing.expectEqual(actor.row(.rat).hp, g.pool.get(2).?.hp);
    std.debug.print("Glacial Shot: first body intercepts, barrel bursts for {d} cold splash, empty shot has no explosion\n", .{splash});
}

test "glacial splash beyond sight does damage without naming the unseen foe in the log" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 29, .y = 20 }});
    const far = spawnAt(g, .bloat, .{ .x = 31, .y = 20 }, false);
    toughenFoes(g);
    settle(g);
    try std.testing.expect(!g.lv.isLit(g.pool.get(far).?.at));
    pressHolding(g, .x, &.{.lb});
    pressHolding(g, .x, &.{.lb});
    const lost = TEST_HP - g.pool.get(far).?.hp;
    try expectWithin(lost, glacial.COLD_LO, glacial.COLD_HI);
    for (0..g.log.n) |i| try std.testing.expect(std.mem.indexOf(u8, g.log.line(i).?, "bloat") == null);
    std.debug.print("unseen glacial splash: {d} damage, 0 log lines naming the hidden bloat\n", .{lost});
}

test "chill slows movement and attacks while idle frames preserve it and skipped turns still take burn and gas" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 28, .y = 20 }});
    const rat = g.pool.get(2).?;
    rat.awake = true;
    rat.chill.apply();
    for (0..glacial.TURNS) |i| {
        use(g, .wait);
        drawnOut(g);
        try std.testing.expectEqual(@as(i32, 28) - @as(i32, @intCast(@min(i + 1, glacial.CYCLE - 1))), rat.at.x);
    }
    try std.testing.expectEqual(@as(u8, 0), rat.chill.turns);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    const adjacent = g.pool.get(2).?;
    adjacent.awake = true;
    toughen(adjacent);
    adjacent.chill = .{ .turns = 2, .phase = glacial.CYCLE - 1 };
    adjacent.burn = .{ .turns = burning.TURNS };
    g.st = .{};
    update(g, 1);
    try std.testing.expectEqual(@as(u8, 2), adjacent.chill.turns);
    const hp = g.archer().?.hp;
    use(g, .wait);
    try std.testing.expectEqual(hp, g.archer().?.hp);
    try std.testing.expectEqual(TEST_HP - burning.PER_TURN, adjacent.hp);
    drawnOut(g);
    adjacent.chill = .{ .turns = 2, .phase = glacial.CYCLE - 1 };
    g.lv.addGas(adjacent.at, TEST_GAS * 10);
    use(g, .wait);
    try std.testing.expectEqual(TEST_HP - 2 * burning.PER_TURN - gas.harm(TEST_HP), adjacent.hp);
    std.debug.print("chill: 2 moves in 3 turns, attack skipped, idle duration unchanged, burning and gas still tick\n", .{});
}

test "glacial chill and its cadence follow slime splits without hitting newborn halves twice" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = splittable(g, .{ .x = 26, .y = 20 }, true);
    const a = g.pool.get(id).?;
    skipsNext(a);
    a.resists.set(.cold, -100);
    burstHit(g, .glacial_shot, .{ .body = id }, a.at, .{ .from = g.archer().?.at, .wait = 0.2 });
    try std.testing.expectEqual(@as(usize, 3), g.pool.n);
    const half = g.pool.get(id + 1).?;
    try std.testing.expectEqual(actor.Kind.slime_half, a.kind);
    try std.testing.expectEqual(a.hp, half.hp);
    try std.testing.expectEqual(glacial.TURNS, a.chill.turns);
    try std.testing.expectEqual(@as(u8, 2), a.chill.phase);
    try std.testing.expectEqual(a.chill, half.chill);
    try std.testing.expectEqual(@as(i16, -100), half.resists.get(.cold));
    try std.testing.expect(g.fx.revealing(actor.Pool.slot(id + 1)));
    std.debug.print("Glacial Shot split: 2 equal halves, chill duration {d} and cadence {d} inherited, one damage event each\n", .{ half.chill.turns, half.chill.phase });
}

test "burning arrow spends mana only on confirmation and shows burning when its hit lands" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 28, .y = 20 }});
    const rat = g.pool.get(2).?;
    toughen(rat);
    catchUp(g);
    g.rng = procRng(.burning_arrow, 1);
    const clock = g.clock;
    press(g, .a);
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expectEqual(heroes.MANA, g.mana);
    press(g, .b);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(heroes.MANA, g.mana);
    press(g, .a);
    press(g, .a);
    const dealt = TEST_HP - rat.hp;
    try std.testing.expect(dealt >= bow.DMG_LO + burning.FIRE_LO and dealt <= bow.DMG_HI + burning.FIRE_HI);
    try std.testing.expectEqual(manaAfter(.burning_arrow), g.mana);
    try std.testing.expectEqual(burning.TURNS, rat.burn.turns);
    try std.testing.expectEqual(@as(u8, 0), g.pictured[actor.Pool.slot(2)].status.get(.burning));
    try std.testing.expectEqual(skillbar.Act.burning_arrow, g.shot.?.act);
    drawnOut(g);
    try std.testing.expectEqual(burning.TURNS, g.pictured[actor.Pool.slot(2)].status.get(.burning));
    const before = rat.hp;
    for (0..burning.TURNS) |_| {
        use(g, .wait);
        drawnOut(g);
    }
    try std.testing.expectEqual(before - burning.PER_TURN * burning.TURNS, rat.hp);
    try std.testing.expectEqual(@as(u8, 0), g.pictured[actor.Pool.slot(2)].status.get(.burning));
    const after = rat.hp;
    use(g, .wait);
    try std.testing.expectEqual(after, rat.hp);
    std.debug.print("Burning Arrow: {d} on hit, then {d} over {d} later turns; mana {d}, flames delayed until impact\n", .{ dealt, before - after, burning.TURNS, manaAfter(.burning_arrow) });
}

test "burning arrow honors fire resistance, refuses insufficient mana and uses the first body in its path" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 27, .y = 20 } });
    const rat = g.pool.get(2).?;
    rat.resists.set(.fire, 100);
    g.mana = burning.COST - 1;
    press(g, .a);
    try std.testing.expectEqual(Mode.play, g.mode);
    g.mana = heroes.MANA;
    press(g, .a);
    g.mark = g.pool.get(3).?.at;
    press(g, .a);
    try std.testing.expect(rat.hp >= actor.row(.rat).hp - bow.DMG_HI and rat.hp <= actor.row(.rat).hp - bow.DMG_LO);
    try std.testing.expectEqual(@as(u8, 0), rat.burn.turns);
    try std.testing.expectEqual(actor.row(.rat).hp, g.pool.get(3).?.hp);
    std.debug.print("100% fire resistance: only physical arrow damage, no ignition; far target untouched\n", .{});
}

test "burning and gas both land in order, while a burning kill bursts a bloat" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const at = P{ .x = 28, .y = 20 };
    arena(g, .{ .x = 20, .y = 20 }, &.{at});
    const rat = g.pool.get(2).?;
    toughen(rat);
    rat.burn = .{ .turns = burning.TURNS };
    rat.resists.set(.fire, 50);
    g.lv.addGas(at, TEST_GAS);
    catchUp(g);
    use(g, .wait);
    try std.testing.expectEqual(TEST_HP - gas.harm(TEST_HP) - damage.resisted(burning.PER_TURN, 50), rat.hp);
    drawnOut(g);
    try std.testing.expectEqual(rat.hp, g.pictured[actor.Pool.slot(2)].hp);
    try std.testing.expectEqual(rat.burn.turns, g.pictured[actor.Pool.slot(2)].status.get(.burning));
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = spawnAt(g, .bloat, at, false);
    g.pool.get(id).?.burn = .{ .turns = 1 };
    burnHarm(g, id);
    try std.testing.expect(g.pool.get(id) == null);
    try std.testing.expectEqual(@as(usize, 1), g.kills);
    try std.testing.expectEqual(gas.BURST, g.lv.gasAt(at));
    std.debug.print("burning plus gas: both damage events shown; burning bloat death releases {d} gas\n", .{gas.BURST});
}

test "burning follows both slime halves without an extra application turn or tick" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = splittable(g, .{ .x = 28, .y = 20 }, false);
    const a = g.pool.get(id).?;
    a.burn.start();
    a.resists.set(.fire, 50);
    wound(g, id, 4, SHOOT, .{ .from = g.archer().?.at, .wait = 0 });
    endTurn(g);
    const half = g.pool.get(id + 1).?;
    try std.testing.expectEqual(@as(i32, 8), a.hp);
    try std.testing.expectEqual(@as(i32, 8), half.hp);
    try std.testing.expectEqual(burning.TURNS, a.burn.turns);
    try std.testing.expectEqual(burning.TURNS, half.burn.turns);
    try std.testing.expect(!a.burn.fresh and !half.burn.fresh);
    try std.testing.expectEqual(@as(i16, 50), half.resists.get(.fire));
    endTurn(g);
    try std.testing.expectEqual(@as(i32, 6), a.hp);
    try std.testing.expectEqual(@as(i32, 6), half.hp);
    try std.testing.expectEqual(burning.TURNS - 1, half.burn.turns);
    std.debug.print("burning slime split: both halves retain 50% fire resistance and take 2 on the next turn\n", .{});
}

test "a chill wearing down on a foe's turn shows as that foe's step is drawn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    const rat = g.pool.get(2).?;
    rat.awake = true;
    rat.chill.apply();
    catchUp(g);
    use(g, .wait);
    try std.testing.expectEqual(@as(i32, 24), rat.at.x);
    try std.testing.expectEqual(glacial.TURNS - 1, rat.chill.turns);
    try std.testing.expectEqual(glacial.TURNS, g.pictured[actor.Pool.slot(2)].status.get(.chilled));
    drawnOut(g);
    try std.testing.expectEqual(glacial.TURNS - 1, g.pictured[actor.Pool.slot(2)].status.get(.chilled));
    std.debug.print("chill on a stepping rat: {d} turns shown until its step is drawn, then {d}\n", .{ glacial.TURNS, g.pictured[actor.Pool.slot(2)].status.get(.chilled) });
}

test "a half split off a burning, chilled slime ticks and skips in step with it on its waiting turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = splittable(g, .{ .x = 28, .y = 20 }, false);
    const a = g.pool.get(id).?;
    a.burn = .{ .turns = burning.TURNS };
    a.chill.apply();
    wound(g, id, 4, SHOOT, .{ .from = g.archer().?.at, .wait = 0 });
    endTurn(g);
    const half = g.pool.get(id + 1).?;
    try std.testing.expectEqual(a.hp, half.hp);
    try std.testing.expectEqual(a.burn, half.burn);
    try std.testing.expectEqual(a.chill, half.chill);
    g.st = .{};
    update(g, 0);
    for (g.owed) |o| try std.testing.expect(!o.any());
    std.debug.print("split on a burning, chilled slime: both at {d} hp, burn {d} turns, chill {d} turns phase {d}\n", .{ half.hp, half.burn.turns, half.chill.turns, half.chill.phase });
}

test "a half the gas or a burn splits off on the foes' turn keeps the ticks its slime already took" {
    for ([_]bool{ true, false }) |gassed| {
        const g = try boot(std.testing.allocator);
        defer shut(std.testing.allocator, g);
        arena(g, .{ .x = 20, .y = 20 }, &.{});
        const at = P{ .x = 30, .y = 20 };
        const id = spawnAt(g, .slime, at, false);
        const a = g.pool.get(id).?;
        a.hp = SLIME_HALF + @as(i32, if (gassed) 1 else 3);
        a.burn = .{ .turns = 2 };
        a.chill.apply();
        if (gassed) g.lv.addGas(at, gas.BURST);
        endTurn(g);
        const half = g.pool.get(id + 1).?;
        try std.testing.expect(half.alive);
        try std.testing.expectEqual(a.chill, half.chill);
        try std.testing.expectEqual(a.burn, half.burn);
        std.debug.print("split by {s} on the foes' turn: slime and half chill {d}/{d} phase {d}/{d}, burn {d}/{d}\n", .{ if (gassed) "gas" else "burn", a.chill.turns, half.chill.turns, a.chill.phase, half.chill.phase, a.burn.turns, half.burn.turns });
    }
}

test "a half a burn splits off a slime in clean air into gas takes the gas on its waiting turn" {
    var hp: [2]i32 = undefined;
    for ([_]bool{ false, true }, &hp) |gassed, *h| {
        const g = try boot(std.testing.allocator);
        defer shut(std.testing.allocator, g);
        arena(g, .{ .x = 20, .y = 20 }, &.{});
        const at = P{ .x = 30, .y = 20 };
        const id = spawnAt(g, .slime, at, false);
        const a = g.pool.get(id).?;
        a.hp = SLIME_HALF + 3;
        a.burn = .{ .turns = 2 };
        if (gassed) for (mathx.ALL_DIRS) |d| g.lv.addGas(at.add(d.delta()), gas.GASSED_UP - 1);
        endTurn(g);
        try std.testing.expect(!g.lv.gassy(a.at));
        h.* = g.pool.get(id + 1).?.hp;
    }
    std.debug.print("a half burned off a slime in clean air: {d} hp, into gas {d}\n", .{ hp[0], hp[1] });
    try std.testing.expect(hp[1] < hp[0]);
}

test "juke targets across obstacles, lands instantly and spends mana but no turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const to = P{ .x = 20 + juke.RANGE, .y = 20 };
    const rat = P{ .x = 26, .y = 20 };
    arena(g, from, &.{rat});
    wakeFoes(g);
    g.lv.set(.{ .x = 21, .y = 20 }, .water);
    const clock = g.clock;
    const rng = g.rng;
    press(g, .b);
    try std.testing.expectEqual(Mode.aim, g.mode);
    for (0..juke.RANGE) |_| nudge(g, .e);
    try std.testing.expectEqual(to, g.mark);
    nudge(g, .e);
    try std.testing.expectEqual(to, g.mark);
    try std.testing.expectEqual(heroes.MANA, g.mana);
    press(g, .b);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(to, g.archer().?.at);
    try std.testing.expect(samePx(cellPx(to), heroNow(g).?));
    try std.testing.expectEqual(grid.NO_ONE, g.lv.who(from));
    try std.testing.expectEqual(g.hero, g.lv.who(to));
    try std.testing.expectEqual(rat, g.pool.get(2).?.at);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(rng, g.rng);
    try std.testing.expectEqual(heroes.MANA - juke.COST, g.mana);
    try std.testing.expectEqual(juke.COOLDOWN, g.cooldown.get(.juke));
    try std.testing.expect(g.unsaved);
    var trail: usize = 0;
    for (g.fx.motes) |m| {
        if (m.life > 0 and std.meta.eql(m.col, look.JUKE_TRAIL) and m.p[0] < mathx.centre(from)[0] + 1) trail += 1;
    }
    try std.testing.expect(trail > 0);
    press(g, .b);
    try std.testing.expectEqual(Mode.play, g.mode);
    std.debug.print("Juke moved {d} tiles instantly: {d} mana left, {d} turns cooldown, no enemy or clock advance\n", .{ mathx.dist(from, to), g.mana, g.cooldown.get(.juke) });
}

test "juke cancellation and invalid landings cost nothing; recovery requires turns" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    arena(g, from, &.{});
    const clock = g.clock;
    press(g, .b);
    press(g, .b);
    try std.testing.expectEqual(Mode.aim, g.mode);
    g.lv.putBarrel(.{ .x = 21, .y = 20 });
    nudge(g, .e);
    press(g, .b);
    try std.testing.expectEqual(from, g.archer().?.at);
    press(g, BINDS);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(heroes.MANA, g.mana);
    try std.testing.expectEqual(@as(u8, 0), g.cooldown.get(.juke));
    try std.testing.expectEqual(clock, g.clock);
    press(g, .b);
    nudge(g, .w);
    press(g, .b);
    g.st = .{};
    update(g, 10);
    try std.testing.expectEqual(juke.COOLDOWN, g.cooldown.get(.juke));
    try std.testing.expectEqual(heroes.MANA - juke.COST, g.mana);
    for (0..juke.COOLDOWN) |_| use(g, .wait);
    try std.testing.expectEqual(@as(u8, 0), g.cooldown.get(.juke));
    try std.testing.expectEqual(heroes.MANA - juke.COST + heroes.MANA_REGEN * juke.COOLDOWN, g.mana);
    g.mana = juke.COST - 1;
    press(g, .b);
    try std.testing.expectEqual(Mode.play, g.mode);
    for (0..@as(usize, @intCast(@divExact(heroes.MANA, heroes.MANA_REGEN)))) |_| use(g, .wait);
    try std.testing.expectEqual(heroes.MANA, g.mana);
    g.bar.bind(.{ .set = .secondary, .button = .rb }, .juke);
    pressHolding(g, .rb, &.{.lb});
    nudge(g, .w);
    press(g, .rb);
    try std.testing.expectEqual(P{ .x = 18, .y = 20 }, g.archer().?.at);
    std.debug.print("Juke: free cancel and invalid targets, {d}-turn recovery, mana capped at {d}, secondary binding checked\n", .{ juke.COOLDOWN, heroes.MANA });
}

test "a skill fires from whatever button holds it, and the secondary set only with its modifier held" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.bar.clear(.{ .set = .primary, .button = .x });
    g.bar.clear(.{ .set = .primary, .button = .rb });
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
    wakeFoes(g);
    g.bar.clear(.{ .set = .primary, .button = .y });
    g.bar.clear(.{ .set = .secondary, .button = .x });
    press(g, BINDS);
    try std.testing.expectEqual(Mode.play, g.mode);
    holdingView(g, input.HOLD_S, null);
    try std.testing.expectEqual(Mode.bind, g.mode);
    g.binds.col = Binds.colOf(.y);
    press(g, .a);
    nudge(g, .e);
    press(g, .a);
    try std.testing.expectEqual(@as(?skillbar.Act, skillbar.kit(g.class)[1]), g.bar.at(.{ .set = .primary, .button = .y }));
    g.binds.col = Binds.colOf(.x);
    press(g, .a);
    nudge(g, .s);
    press(g, .a);
    try std.testing.expectEqual(@as(?skillbar.Act, null), g.bar.at(.{ .set = .primary, .button = .x }));
    try std.testing.expectEqual(@as(?skillbar.Act, .shoot), g.bar.at(.{ .set = .secondary, .button = .x }));
    use(g, .wait);
    try std.testing.expectEqual(@as(?skillbar.Act, null), g.bar.at(.{ .set = .secondary, .button = .x }));
    press(g, .b);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(P{ .x = 30, .y = 20 }, g.pool.get(2).?.at);
}

test "a pool longer than the bar wraps into rows the d-pad walks, and the rows shown scroll to hold the cursor" {
    const n = PICK_COLS * 3 + 2;
    const last = n - 1;
    try std.testing.expectEqual(PICK_COLS, pickStep(0, .{ .x = 0, .y = 1 }, n));
    try std.testing.expectEqual(@as(usize, 1), pickStep(PICK_COLS + 1, .{ .x = 0, .y = -1 }, n));
    try std.testing.expectEqual(@as(usize, 1), pickStep(1, .{ .x = 0, .y = -1 }, n));
    try std.testing.expectEqual(last, pickStep(PICK_COLS * 2 + PICK_COLS - 1, .{ .x = 0, .y = 1 }, n));
    try std.testing.expectEqual(@as(usize, 0), pickStep(last, .{ .x = 1, .y = 0 }, n));
    try std.testing.expectEqual(last, pickStep(0, .{ .x = -1, .y = 0 }, n));
    try std.testing.expectEqual(PICK_COLS + 1, pickStep(0, .{ .x = 1, .y = 1 }, n));
    const one_row = PICK_MARGIN + SLOT_GAP;
    for (0..n) |at| {
        const win = pickWindow(0, one_row, n, at);
        try std.testing.expectEqual(@as(usize, 1), win.len);
        try std.testing.expectEqual(at / PICK_COLS, win.from);
    }
    const two_rows = one_row + SLOT_STEP;
    try std.testing.expectEqual(@as(usize, 2), pickWindow(0, two_rows, n, last).len);
    try std.testing.expectEqual(pickRows(n) - 2, pickWindow(0, two_rows, n, last).from);
    try std.testing.expectEqual(@as(usize, 1), pickWindow(two_rows - one_row, two_rows, n, last).len);
    try std.testing.expectEqual(pickRows(n), pickWindow(0, 10_000, n, 0).len);
}

fn holdingView(g: *Game, more_s: f32, a: ?input.Button) void {
    calm(g);
    const was = g.st.down_s.get(BINDS);
    g.st = .{};
    g.st.down.insert(BINDS);
    g.st.down_s.set(BINDS, was + more_s);
    if (a) |b| {
        g.st.pressed.insert(b);
        g.st.down.insert(b);
    }
    update(g, 0);
}

test "View held through an aim opens no bind screen once the shot is confirmed" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.st = .{};
    holdingView(g, input.HOLD_S / 4, .x);
    try std.testing.expectEqual(Mode.aim, g.mode);
    holdingView(g, input.HOLD_S, .x);
    try std.testing.expectEqual(Mode.play, g.mode);
    holdingView(g, TEST_DT, null);
    try std.testing.expectEqual(Mode.play, g.mode);
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
    const id = spawnAt(g, .slime, .{ .x = 21, .y = 20 }, true);
    endTurn(g);
    const slam = actor.row(.slime).blow.strike;
    const lost = actor.row(HERO).hp - g.archer().?.hp;
    std.debug.print("slime slam: {d} hp\n", .{lost});
    try expectWithin(lost, slam.lo, slam.hi);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.pool.get(id).?.at);
}

test "a body faces right until it steps, aims or turns on someone to its left, and straight up or down keeps it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 16, .y = 20 }, .{ .x = 25, .y = 20 } });
    const hero = heroSlot(g).?;
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
    for ([_]f32{ day.NOON, 19.5, 0 }, 0..) |h, i| {
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

test "tight diagonals carry movement sight projectiles melee and gas in all four directions" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    for ([_]mathx.Dir{ .ne, .se, .sw, .nw }) |d| {
        const delta = d.delta();
        const near = from.add(delta);
        const ahead = from.add(delta.scaled(2));
        const far = from.add(delta.scaled(3));
        g.lv = grid.Level.blank();
        for (0..4) |i| g.lv.set(from.add(delta.scaled(@intCast(i))), .floor);
        reset(g, from);
        g.outdoors = false;
        settle(g);
        for ([_]P{ near, ahead, far }) |p| {
            try std.testing.expect(g.lv.isLit(p) and g.lv.isSeen(p));
            try std.testing.expect(bow.aimable(&g.lv, from, p));
        }
        try std.testing.expect(juke.aimable(&g.lv, from, ahead));
        const cone = glacial.cone(&g.lv, from, near);
        try std.testing.expect(cone.has(ahead) and cone.has(far));
        var reverse: [grid.CELLS]bool = @splat(false);
        fov.castInto(&g.lv, far, actor.row(HERO).sight, &reverse);
        try std.testing.expect(reverse[grid.Level.idx(from)]);

        g.lv.set(near, .wall);
        castSight(g, from);
        try std.testing.expect(!g.lv.isLit(ahead) and !g.lv.isLit(far));
        try std.testing.expect(!bow.aimable(&g.lv, from, far));
        try std.testing.expectEqual(@as(usize, 0), bow.fly(&g.lv, from, far).len);
        g.lv.set(near, .floor);
        castSight(g, from);

        const rat = spawnAt(g, .rat, far, false);
        const flight = bow.fly(&g.lv, from, far);
        try std.testing.expectEqual(@as(?bow.Hit, .{ .body = rat }), flight.struck);
        try std.testing.expectEqual(@as(usize, 3), flight.len);
        nudge(g, d);
        try std.testing.expectEqual(near, g.archer().?.at);
        try std.testing.expect(g.pool.get(rat).?.awake);
        use(g, .wait);
        try std.testing.expectEqual(ahead, g.pool.get(rat).?.at);
        const hp = g.archer().?.hp;
        const rat_hp = g.pool.get(rat).?.hp;
        nudge(g, d);
        try std.testing.expectEqual(near, g.archer().?.at);
        try std.testing.expect(g.archer().?.hp < hp);
        try std.testing.expect(g.pool.get(rat).?.hp < rat_hp);
        g.lv.addGas(from, gas.BURST);
        gas.turn(&g.lv, &g.rng);
        try std.testing.expect(g.lv.gasAt(near) > 0);
    }
    std.debug.print("4 tight diagonals: walking, pursuit, melee, sight, arrows, Juke, frost and gas agree\n", .{});
}

test "a step into a wall turns no one and spends no turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    wakeFoes(g);
    g.lv.set(.{ .x = 19, .y = 20 }, .wall);
    nudge(g, .w);
    try std.testing.expectEqual(Facing.right, g.facing[heroSlot(g).?]);
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
    wakeFoes(g);
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
    wakeFoes(g);
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
    try expectWithin(g.gold, GOLD_LO, GOLD_HI);
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

test "the camera shows past the floor only under the hud, keeps the archer clear of it, and centres a small floor" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    begin(g, 4321);
    const world_w = @as(f32, @floatFromInt(grid.W)) * CELL_F;
    const world_h = @as(f32, @floatFromInt(grid.H)) * CELL_F + @as(f32, @floatFromInt(hud.COVER));
    for ([_]P{ .{ .x = WINDOW_W, .y = WINDOW_H }, .{ .x = 2560, .y = 1440 } }) |screen| {
        g.screen = screen;
        for ([_]P{ .{ .x = 0, .y = 0 }, .{ .x = grid.W - 1, .y = grid.H - 1 }, .{ .x = 48, .y = 32 } }) |p| {
            g.archer().?.at = p;
            snapGlide(g);
            const v = camWant(g);
            try std.testing.expect(v.x >= 0 and v.y >= 0);
            try std.testing.expect(v.x + @as(f32, @floatFromInt(screen.x)) <= world_w);
            try std.testing.expect(v.y + @as(f32, @floatFromInt(g.screen.y)) <= world_h);
            const foot = @as(f32, @floatFromInt((p.y + 1) * CELL)) - v.y;
            if (p.y == grid.H - 1) std.debug.print("{d}x{d}: bottom-row archer's foot at {d:.0}, hud top {d}\n", .{ screen.x, screen.y, foot, hud.Layout.of(screen, SKILLS_W).top });
            try std.testing.expect(foot <= @as(f32, @floatFromInt(hud.Layout.of(screen, SKILLS_W).top)));
        }
    }
    g.screen = .{ .x = grid.W * CELL + 200, .y = grid.H * CELL + hud.COVER + 100 };
    const v = camWant(g);
    try std.testing.expectEqual((world_w - @as(f32, @floatFromInt(g.screen.x))) * 0.5, v.x);
    try std.testing.expectEqual((world_h - @as(f32, @floatFromInt(g.screen.y))) * 0.5, v.y);
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
        const hero = heroSlot(g).?;
        var last = [2]f32{ g.glide[hero].now().x, g.cam.x };
        var lo = [2]f32{ std.math.floatMax(f32), std.math.floatMax(f32) };
        var hi = [2]f32{ 0, 0 };
        var on_last: i32 = 0;
        var on_dir: i32 = 0;
        var flips: usize = 0;
        var t: f32 = 0;
        while (t < 2.0) : (t += dt) {
            walkFrame(g, dt, .e);
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

test "water footsteps follow the shown ground unit step once, excluding flying units" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var grounded: usize = 0;
    var flying: usize = 0;
    for (std.enums.values(actor.Kind)) |kind| {
        arena(g, .{ .x = 20, .y = 20 }, &.{});
        const id = if (kind == HERO) g.hero else spawnAt(g, kind, .{ .x = 24, .y = 20 }, false);
        const slot = actor.Pool.slot(id);
        const from = g.pool.get(id).?.at;
        const to = from.add(mathx.Dir.e.delta());
        g.lv.set(from, .shallows);
        g.lv.set(to, .shallows);
        settle(g);
        g.st = .{};
        const initial = g.fx.head;
        const clock = g.clock;
        const rng = g.rng;
        update(g, 0.1);
        try std.testing.expectEqual(initial, g.fx.head);
        stepTo(g, id, to);
        const span = g.glide[slot].span();
        g.glide[slot].t = -0.2;
        update(g, 0.19);
        try std.testing.expectEqual(initial, g.fx.head);
        update(g, 0.01 + span * (SPLASH_AT - 0.1));
        try std.testing.expectEqual(initial, g.fx.head);
        update(g, span * 0.2);
        const emitted = g.fx.head;
        if (actor.row(kind).movement == .ground) {
            grounded += 1;
            try std.testing.expect(emitted != initial);
            const at = middle(g.glide[slot].now());
            for (g.fx.motes) |m| {
                if (m.life <= 0) continue;
                try std.testing.expect(@abs(m.p[0] - at[0]) < fx.SPLASH_R + 0.03);
                try std.testing.expect(@abs(m.p[1] - at[1] - fx.SPLASH_FOOT) < fx.SPLASH_RY + 0.02);
            }
        } else {
            flying += 1;
            try std.testing.expectEqual(initial, emitted);
        }
        update(g, 1);
        try std.testing.expectEqual(emitted, g.fx.head);
        try std.testing.expectEqual(clock, g.clock);
        try std.testing.expectEqual(rng, g.rng);
    }
    try std.testing.expect(grounded > 0 and flying > 0);
    std.debug.print("water footsteps: {d} ground kinds splash once at the shown footfall, {d} flying kind stays dry; no idle effects or simulation changes\n", .{ grounded, flying });
}

test "a long frame that ends a step in shallows and starts the next walk still splashes" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const to = P{ .x = 21, .y = 20 };
    arena(g, from, &.{});
    for (0..4) |dx| g.lv.set(from.add(.{ .x = @intCast(dx), .y = 0 }), .shallows);
    settle(g);
    g.st = .{};
    const slot = heroSlot(g).?;
    const initial = g.fx.head;
    stepTo(g, g.hero, to);
    const span = g.glide[slot].span();
    g.glide[slot].t = span * (SPLASH_AT - 0.05);
    g.busy = span * (1 - SPLASH_AT + 0.05);
    g.pending = .e;
    update(g, span * (1 - SPLASH_AT + 0.1));
    try std.testing.expect(g.archer().?.at.eq(to.add(mathx.Dir.e.delta())));
    try std.testing.expect(g.fx.head != initial);
}

test "water footsteps do not appear on dry ground, hidden steps or melee bumps" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const cases = [_]struct { tile: grid.Tile, hidden: bool = false, bump: bool = false }{
        .{ .tile = .floor },
        .{ .tile = .bridge },
        .{ .tile = .ice },
        .{ .tile = .lava },
        .{ .tile = .shallows, .hidden = true },
        .{ .tile = .shallows, .bump = true },
    };
    for (cases) |case| {
        const from = P{ .x = 20, .y = 20 };
        const to = P{ .x = 21, .y = 20 };
        arena(g, from, &.{});
        g.lv.set(from, .shallows);
        g.lv.set(to, case.tile);
        settle(g);
        g.st = .{};
        const initial = g.fx.head;
        const slot = heroSlot(g).?;
        if (case.bump) {
            g.glide[slot] = g.glide[slot].bumping(to, 0);
        } else {
            stepTo(g, g.hero, to);
        }
        if (case.hidden) @memset(&g.lv.lit, false);
        update(g, g.glide[slot].span());
        try std.testing.expectEqual(initial, g.fx.head);
    }
    std.debug.print("water footsteps: {d} dry, hidden or attacking cases emit no drops\n", .{cases.len});
}

test "every step is one hop that peaks mid-glide and lands as the glide ends, and the ground under it does not bob" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 32 }, &.{.{ .x = 50, .y = 32 }});
    wakeFoes(g);
    g.st = .{};
    const hero = heroSlot(g).?;
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
        walkFrame(g, dt, .e);
        if (!g.archer().?.at.eq(was)) steps += 1;
        was = g.archer().?.at;
        const up = g.glide[hero].lift() * 2 > @as(i32, HOP_PX);
        if (up and !high) hops += 1;
        high = up;
        for (g.glide[0..g.pool.n], 0..) |gl, i| peaks[i] = @max(peaks[i], gl.lift());
        if (g.glide[hero].now().y != ground[0] or g.cam.y != ground[1]) bobbed = true;
    }
    for (0..60) |_| {
        walkFrame(g, dt, null);
    }
    std.debug.print("hop: {d} steps, {d} hops, the archer peaks {d} px and the rat {d} px\n", .{ steps, hops, peaks[hero], peaks[actor.Pool.slot(2)] });
    try std.testing.expect(steps > 5);
    try std.testing.expectEqual(steps, hops);
    try std.testing.expectEqual(@as(i32, HOP_PX), peaks[hero]);
    try std.testing.expectEqual(@as(i32, HOP_PX), peaks[actor.Pool.slot(2)]);
    for (g.glide[0..g.pool.n]) |gl| try std.testing.expectEqual(@as(i32, 0), gl.lift());
    try std.testing.expect(!bobbed);
}

test "a foe stepping into the cell of a body still dying there sets off once that body is no longer drawn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 25, .y = 20 } });
    const cell = P{ .x = 24, .y = 20 };
    const dying = actor.Pool.slot(2);
    const mover = actor.Pool.slot(3);
    _ = g.pool.damage(&g.lv, 2, g.pool.get(2).?.hp);
    const lands: f32 = 0.3;
    strike(g, dying, .{ .from = .{ .x = 20, .y = 20 }, .wait = lands }, cell, true, .{ .body = snap(g, dying) });
    g.pool.move(&g.lv, 3, cell);
    staggerOnly(g, 3);
    var overlap: f32 = 0;
    var t: f32 = 0;
    while (t < 1) : (t += TEST_DT) {
        if (standing(g, dying) and g.glide[mover].done() > 0) overlap += TEST_DT;
        update(g, TEST_DT);
    }
    std.debug.print("a rat dying {d:.2} s out holds the next into its cell: {d:.3} s drawn together\n", .{ lands, overlap });
    try std.testing.expect(overlap <= TEST_TOL);
    try std.testing.expect(g.glide[mover].done() >= 1);
}

test "a way held through closing inspect, a reticle or pause walks nobody until let go or turned" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const dt = TEST_DT;
    const Case = struct { mode: Mode, close: input.Button };
    const cases = [_]Case{
        .{ .mode = .inspect, .close = skillbar.INSPECT },
        .{ .mode = .aim, .close = menu.BACK },
        .{ .mode = .pause, .close = menu.BACK },
    };
    for (cases) |case| {
        arena(g, .{ .x = 20, .y = 32 }, &.{});
        g.st = .{};
        const start = g.archer().?.at;
        g.paused_from = .play;
        g.mark = start;
        if (case.mode == .aim) aiming(g, .a, .juke);
        g.mode = case.mode;
        var t: f32 = 0;
        while (t < 0.6) : (t += dt) {
            walkFrame(g, dt, .e);
        }
        g.st.pressed.insert(case.close);
        update(g, dt);
        g.st.pressed = .initEmpty();
        try std.testing.expectEqual(Mode.play, g.mode);
        t = 0;
        while (t < 1.0) : (t += dt) {
            walkFrame(g, dt, .e);
        }
        try std.testing.expect(g.archer().?.at.eq(start));
        walkFrame(g, dt, null);
        for (0..30) |_| {
            walkFrame(g, dt, .e);
        }
        try std.testing.expect(!g.archer().?.at.eq(start));
    }
    std.debug.print("held walk: {d} screens closed with the way held, none walked till it was let go\n", .{cases.len});
}

test "a way held from play into pause or inspect moves nothing there until let go or turned" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const dt = TEST_DT;
    const Case = struct { open: input.Button, way: mathx.Dir };
    for ([_]Case{ .{ .open = PAUSE, .way = .s }, .{ .open = skillbar.INSPECT, .way = .e } }) |case| {
        arena(g, .{ .x = 20, .y = 20 }, &.{});
        g.st = .{};
        for (0..10) |_| walkFrame(g, dt, case.way);
        g.st.pressed.insert(case.open);
        walkFrame(g, dt, case.way);
        g.st.pressed = .initEmpty();
        try std.testing.expect(g.mode != .play);
        const menu_at = g.pause_menu.at;
        const spot = g.inspecting;
        var t: f32 = 0;
        while (t < 1.0) : (t += dt) walkFrame(g, dt, case.way);
        try std.testing.expectEqual(menu_at, g.pause_menu.at);
        try std.testing.expectEqual(spot, g.inspecting);
        walkFrame(g, dt, null);
        for (0..30) |_| walkFrame(g, dt, case.way);
        try std.testing.expect(g.pause_menu.at != menu_at or !std.meta.eql(spot, g.inspecting));
        g.mode = .play;
    }
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
    wallRow(&g.lv, 19, 21, 29);
    wallRow(&g.lv, 21, 21, 29);
    wakeFoes(g);
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
    wakeFoes(g);
    settle(g);
    nudge(g, .e);
    const t = [_]f32{ g.glide[heroSlot(g).?].t, g.glide[actor.Pool.slot(3)].t, g.glide[actor.Pool.slot(4)].t, g.glide[actor.Pool.slot(2)].t };
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
    wakeFoes(g);
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
    bittenToDeath(g);
    try std.testing.expectEqual(Mode.dead, g.mode);
    const hero = heroSlot(g).?;
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
    wakeFoes(g);
    g.pool.get(2).?.hp = 1;
    g.archer().?.hp = 1;
    g.lv.addGas(.{ .x = 21, .y = 20 }, TEST_GAS);
    use(g, .wait);
    try std.testing.expectEqual(Mode.dead, g.mode);
    try std.testing.expect(g.pool.get(2) != null);
    try std.testing.expectEqual(@as(usize, 0), g.kills);
    try std.testing.expectEqualStrings("Archer dies.", g.log.line(0).?);
}

test "a bite lands on the archer at the height of the biter's bump, from its place in the turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    wakeFoes(g);
    nudge(g, .e);
    const hero = heroSlot(g).?;
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
    wakeFoes(g);
    const cam = g.cam;
    nudge(g, .e);
    const hero = heroSlot(g).?;
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
    try std.testing.expectEqual(Move.kick, leanShown(g, &stoodNow(g), at, .e));
    drawnOut(g);
    try std.testing.expectEqual(Move.step, leanShown(g, &stoodNow(g), at, .e));
}

test "a kick dealt in a frame of play is no further into its bump than its blow is to landing" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    calm(g);
    g.st = .{ .walk = .e };
    update(g, mathx.FRAME_DT);
    const t = g.glide[heroSlot(g).?].t;
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
        wakeFoes(g);
        g.archer().?.hp = actor.row(.rat).blow.strike.hi + 1;
        endTurn(g);
        var kills: usize = 0;
        for (g.owed) |o| {
            if ((o.bit orelse continue).blow == .kill) kills += 1;
        }
        try std.testing.expectEqual(@as(usize, if (g.mode == .dead) 1 else 0), kills);
        if (g.mode != .dead) continue;
        deaths += 1;
        for (g.owed) |o| {
            if ((o.bit orelse continue).blow == .hurt) hurts += 1;
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

test "hidden and offscreen objects keep casting without being drawn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const p = P{ .x = 27, .y = 20 };
    arena(g, .{ .x = 20, .y = 20 }, &.{p});
    const i = actor.Pool.slot(2);
    const view = grid.Box{ .lo = .{ .x = 15, .y = 15 }, .hi = .{ .x = 27, .y = 25 } };
    const cast = view.grown(CAST_MARGIN);
    g.lv.lit[grid.Level.idx(p)] = false;
    g.lv.seen[grid.Level.idx(p)] = false;
    try std.testing.expect(drawnAt(g, i) == null);
    try std.testing.expect(casterAt(g, i, view) == null);
    try std.testing.expectEqual(g.glide[i].now(), casterAt(g, i, cast).?);
    g.split_from[i] = heroSlot(g).?;
    try std.testing.expect(casterAt(g, i, cast) == null);
    g.split_from[i] = null;
    g.pool.items[i].alive = false;
    try std.testing.expect(casterAt(g, i, cast) == null);
    g.lv.putBarrel(p);
    try std.testing.expect(!barrelShownAt(g, p));
    try std.testing.expect(barrelPresent(g, p));
    std.debug.print("hidden actor and barrel still cast within {d} cells of the view; dead actors and unborn splits do not\n", .{CAST_MARGIN});
}

test "the minimap fits in the top right, clear of the hud" {
    for ([_]P{ .{ .x = WINDOW_W, .y = WINDOW_H }, .{ .x = 1920, .y = 1080 }, .{ .x = 2560, .y = 1440 } }) |screen| {
        const o = miniOrigin(screen.x);
        try std.testing.expect(o.x > @divTrunc(screen.x, 2));
        try std.testing.expect(o.y + MINI_H + MINI_FRAME < hud.Layout.of(screen, SKILLS_W).top);
    }
}

/// Seconds of frames till a split-off half in `slot` is drawn, and till what is owed it lands.
fn showsAndLands(g: *Game, slot: usize) struct { shows: f32, lands: f32 } {
    var shows: ?f32 = null;
    var lands: ?f32 = null;
    var t: f32 = 0;
    while ((shows == null or lands == null) and t < 1) : (t += TEST_DT) {
        update(g, TEST_DT);
        if (shows == null and drawn(g, slot)) shows = t;
        if (lands == null and !g.fx.pending(slot)) lands = t;
    }
    return .{ .shows = shows.?, .lands = lands.? };
}

fn corridor(b: *atlas.Bespoke) void {
    var x: i32 = 2;
    while (x <= 12) : (x += 1) b.tile[grid.Level.idx(.{ .x = x, .y = 5 })] = .floor;
}

fn splittable(g: *Game, at: P, awake: bool) u16 {
    const id = spawnAt(g, .slime, at, awake);
    g.pool.get(id).?.hp = SLIME_HALF + 1;
    return id;
}

fn bittenToDeath(g: *Game) void {
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    wakeFoes(g);
    g.archer().?.hp = 1;
    nudge(g, .e);
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
    try std.testing.expect(aboutRate(bursts, 1 - actor.FLIT + actor.FLIT / mathx.ALL_DIRS.len));
}

test "a bloat with no way to the archer still flits a third of its turns" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
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
    try std.testing.expect(aboutRate(moved, actor.FLIT));
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
        use(g, .wait);
        const lost = before - g.archer().?.hp;
        if (first == null and lost > 0) first = turn;
        try std.testing.expectEqual(if (first == null) 0 else per, lost);
        if (lost > 0) try std.testing.expect(g.fx.flashOf(heroSlot(g).?) > 0);
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
    while (g.pool.get(far) != null and waited < 20) : (waited += 1) use(g, .wait);
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
    use(g, .wait);
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
    wakeFoes(g);
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
    const dark = ledge(g);
    castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.lv.isLit(dark));
    g.pool.move(&g.lv, 2, dark);
    staggerOnly(g, 2);
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
    try std.testing.expect(mapAssets(g).barrel);
    const t = framesUntil(g, 0, Gone.f);
    try std.testing.expect(!mapAssets(g).barrel);
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
    wakeFoes(g);
    const low: i32 = @intFromFloat(vignette.LOW * @as(f32, @floatFromInt(actor.row(HERO).hp)));
    g.archer().?.hp = low;
    catchUp(g);
    nudge(g, .e);
    const hero = heroSlot(g).?;
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
    const id = splittable(g, at, false);
    catchUp(g);
    press(g, .x);
    press(g, .x);
    const slime = actor.Pool.slot(id);
    const other = slime + 1;
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.get(id).?.kind);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.items[other].kind);
    try std.testing.expectEqual(actor.Kind.slime, g.pictured[slime].kind);
    try std.testing.expect(mapAssets(g).bodies.contains(.slime));
    try std.testing.expect(drawnAt(g, other) == null);
    try std.testing.expectEqual(fx.Body.of(g.pool.items[other], g.pictured[other].seq), g.pictured[other]);
    try std.testing.expectEqualStrings("The slime splits in two!", g.log.line(0).?);
    const t = framesUntil(g, other, drawn);
    const lands = flown(6);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pictured[slime].kind);
    try std.testing.expect(!mapAssets(g).bodies.contains(.slime));
    try std.testing.expect(mapAssets(g).bodies.contains(.slime_quarter));
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
    use(g, .wait);
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
        wakeFoes(g);
        g.archer().?.hp = 1000;
        g.archer().?.max = 1000;
        var rng = mathx.Rng.init(f);
        for (0..300) |_| {
            if (g.mode == .dead) break;
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
    wakeFoes(g);
    use(g, .wait);
    const hero = heroSlot(g).?;
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
    const id = splittable(g, at, true);
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

test "a half the gas splits off a burning slime on the foes' turn burns no sooner than it shows" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = splittable(g, at, true);
    const a = g.pool.get(id).?;
    a.burn = .{ .turns = 2 };
    for ([_]P{ at, .{ .x = 24, .y = 20 } }) |p| g.lv.addGas(p, TEST_GAS);
    catchUp(g);
    use(g, .wait);
    const half = actor.Pool.slot(id) + 1;
    try std.testing.expect(g.split_from[half] != null and g.fx.pending(half));
    const when = showsAndLands(g, half);
    std.debug.print("a half the gas splits off a burning slime on the foes' turn: shows {d:.3} s in, its burn lands {d:.3} s in\n", .{ when.shows, when.lands });
    try std.testing.expect(when.lands >= when.shows);
}

test "a half an arrow splits off into gas takes the gas on its waiting turn, no sooner than it shows" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = splittable(g, at, true);
    var cells = grid.Cells.around(at, 2);
    while (cells.next()) |p| g.lv.addGas(p, TEST_GAS);
    catchUp(g);
    press(g, .x);
    press(g, .x);
    const half = actor.Pool.slot(id) + 1;
    try std.testing.expect(g.split_from[half] != null);
    const when = showsAndLands(g, half);
    const b = g.pool.items[half];
    std.debug.print("a half split off into gas: shows {d:.3} s in, stung {d:.3} s in, {s} on {d} of {d} hp\n", .{ when.shows, when.lands, actor.row(b.kind).name, b.hp, b.max });
    try std.testing.expect(b.kind != .slime_half or b.hp < b.max);
    try std.testing.expect(when.lands >= when.shows);
}

fn ledge(g: *Game) P {
    wallRow(&g.lv, 21, 18, 26);
    return .{ .x = 22, .y = 22 };
}

fn revealed(g: *Game, slot: usize) bool {
    return g.split_from[slot] == null;
}

test "a half the gas splits off an unlit slime into sight shows as the archer's step lands, not before" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const dark = ledge(g);
    const id = spawnAt(g, .slime_half, dark, true);
    const half = actor.Pool.slot(spawnAt(g, .slime_quarter, .{ .x = 22, .y = 19 }, true));
    const s = actor.Pool.slot(id);
    g.split_from[half] = s;
    g.pool.move(&g.lv, g.hero, .{ .x = 19, .y = 20 });
    castSight(g, .{ .x = 19, .y = 20 });
    try std.testing.expect(!g.lv.isLit(dark) and g.lv.isLit(g.pool.items[half].at));
    g.owed[s].gassed = .{ .kill = false, .after = .{ .body = snap(g, s), .reveals = half } };
    g.order_n = 0;
    stepGlide(g, 0);
    const step = g.glide[heroSlot(g).?].left();
    catchUp(g);
    const t = framesUntil(g, half, revealed);
    std.debug.print("a half split off an unlit slime by the gas: revealed {d:.3} s in, the archer's step lands at {d:.3} s\n", .{ t, step });
    try std.testing.expect(step > 0);
    try std.testing.expectApproxEqAbs(step, t, TEST_TOL);
}

test "a quarter the gas splits off a burning half on its waiting turn burns that turn as its sibling does" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = spawnAt(g, .slime_half, at, true);
    const a = g.pool.get(id).?;
    a.hp = actor.row(.slime_quarter).hp;
    a.burn = .{ .turns = burning.TURNS };
    a.resists.set(.fire, 50);
    a.waits = true;
    g.lv.addGas(at, TEST_GAS);
    catchUp(g);
    use(g, .wait);
    const s = actor.Pool.slot(id);
    const q = s + 1;
    try std.testing.expectEqual(actor.Kind.slime_quarter, g.pool.items[q].kind);
    std.debug.print("a burning half split by the gas on its waiting turn: burn turns left {d} and {d}\n", .{ g.pool.items[s].burn.turns, g.pool.items[q].burn.turns });
    try std.testing.expectEqual(g.pool.items[s].burn.turns, g.pool.items[q].burn.turns);
}

test "a split nobody sees holds no one's walk" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 40, .y = 20 };
    const id = splittable(g, at, false);
    g.lv.addGas(at, TEST_GAS);
    catchUp(g);
    use(g, .wait);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.get(id).?.kind);
    try std.testing.expectEqual(@as(?usize, null), g.split_from[actor.Pool.slot(id) + 1]);
    try std.testing.expect(g.busy <= 0);
}

test "a foe the gas kills as it steps out of sight is drawn stepping out, not gone from where it stood" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const rat = actor.Pool.slot(2);
    const dark = ledge(g);
    castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.lv.isLit(dark));
    g.pool.move(&g.lv, 2, dark);
    _ = g.pool.damage(&g.lv, 2, actor.row(.rat).hp);
    g.owed[rat].gassed = .{ .kill = true, .after = .{ .body = fx.Body.of(g.pool.items[rat], 0) } };
    staggerOnly(g, 2);
    catchUp(g);
    try std.testing.expect(drawnAt(g, rat) != null);
    const alive_shown = g.pictured[rat].hp;
    const t = framesUntil(g, rat, gone);
    std.debug.print("a rat the gas kills stepping out of sight a stagger in: drawn until {d:.3} s on {d} hp, its hop {d:.3} to {d:.3} s\n", .{ t, alive_shown, STAGGER_S, STAGGER_S + GLIDE_S });
    try std.testing.expect(alive_shown > 0);
    try std.testing.expect(t > STAGGER_S and t < STAGGER_S + GLIDE_S);
}

test "a foe the gas kills stepping from dark to dark has its death landed by the time the turn is quiet" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const dark = ledge(g);
    const was = P{ .x = dark.x + 1, .y = dark.y };
    const id = spawnAt(g, .slime, was, true);
    const s = actor.Pool.slot(id);
    castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.lv.isLit(dark) and !g.lv.isLit(was));
    g.pool.move(&g.lv, id, dark);
    _ = g.pool.damage(&g.lv, id, g.pool.items[s].hp);
    g.owed[s].gassed = .{ .kill = true, .after = .{ .body = fx.Body.of(g.pool.items[s], 0) } };
    staggerOnly(g, id);
    catchUp(g);
    var t: f32 = 0;
    while (!quiet(g) and t < 1) : (t += TEST_DT) update(g, TEST_DT);
    update(g, TEST_DT);
    std.debug.print("a slime the gas kills sliding dark to dark: quiet {d:.3} s in, its death still due: {}\n", .{ t, g.fx.pending(s) });
    try std.testing.expect(!g.fx.pending(s));
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
    wakeFoes(g);
    use(g, .wait);
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
    wakeFoes(g);
    const late: f32 = 0.05;
    calm(g);
    g.busy = -1;
    g.st = .{ .walk = .e };
    g.st.step.late = late;
    update(g, 0);
    const t = framesUntil(g, heroSlot(g).?, reddened);
    std.debug.print("a kick due {d:.3} s late: the first bite lands {d:.3} s on\n", .{ late, t });
    try std.testing.expectApproxEqAbs(2 * BUMP_LANDS + STAGGER_S - late, t, TEST_TOL);
}

test "a walk due just before the last turn is drawn out starts as it ends" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const busy: f32 = 0.005;
    const dt: f32 = 0.016;
    const due: f32 = 0.015;
    calm(g);
    g.busy = busy;
    g.st = .{ .walk = .e };
    g.st.step.late = due;
    update(g, dt);
    const t = g.glide[heroSlot(g).?].t;
    std.debug.print("a walk due {d:.3} s ago, the turn drawn out {d:.3} s ago: the step is {d:.3} s in\n", .{ due, dt - busy, t });
    try std.testing.expectApproxEqAbs(dt - busy, t, 1e-5);
}

test "a run left mid-turn keeps the way its foes were turning" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 20 } });
    wakeFoes(g);
    use(g, .wait);
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
    g.fx.strike(wait, .{ .slot = p, .at = mathx.centre(g.pool.items[p].at), .dir = null, .matter = .ooze, .lethal = false, .after = .{ .body = fx.Body.of(g.pool.items[p], 1), .reveals = c } });
    catchUp(g);
    try std.testing.expect(g.split_from[c] != null and g.split_from[d] != null);
    const t = framesUntil(g, d, drawn);
    try std.testing.expectApproxEqAbs(wait, t, TEST_TOL);
    try std.testing.expect(drawnAt(g, c) != null);
}

test "the dead archer's floor restarts only once the death is shown" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    bittenToDeath(g);
    try std.testing.expectEqual(Mode.dead, g.mode);
    g.st = .{};
    g.st.pressed.insert(CONFIRM);
    update(g, 0);
    try std.testing.expectEqual(Mode.dead, g.mode);
    _ = framesUntil(g, 0, deathDrawn);
    press(g, CONFIRM);
    try std.testing.expectEqual(Mode.play, g.mode);
}

test "Menu, B or X leaves the death screen as A does, and none of them pauses it" {
    for (DISMISS) |b| {
        const g = try boot(std.testing.allocator);
        defer shut(std.testing.allocator, g);
        bittenToDeath(g);
        _ = framesUntil(g, 0, deathDrawn);
        press(g, b);
        try std.testing.expectEqual(Mode.play, g.mode);
    }
}

test "the reticle crosses the archer to the far side of a corridor" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 15, .y = 20 } });
    wallRow(&g.lv, 19, 10, 30);
    wallRow(&g.lv, 21, 10, 30);
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
    wakeFoes(g);
    nudge(g, .e);
    try std.testing.expect(g.archer().?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.vignette.alpha());
    const t = framesUntil(g, heroSlot(g).?, reddened);
    std.debug.print("a bite bumped a stagger into the turn reddens the view {d:.3} s in\n", .{t});
    try std.testing.expectApproxEqAbs(STAGGER_S + BUMP_LANDS, t, TEST_TOL);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.addGas(.{ .x = 20, .y = 20 }, TEST_GAS);
    use(g, .wait);
    try std.testing.expect(g.archer().?.hurt());
    try std.testing.expect(framesUntil(g, heroSlot(g).?, reddened) < TEST_TOL);
}

test "gas left to eat at the archer kills it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.addGas(.{ .x = 20, .y = 20 }, TEST_GAS);
    g.archer().?.hp = 1;
    use(g, .wait);
    try std.testing.expectEqual(Mode.dead, g.mode);
    try std.testing.expectEqualStrings("Archer dies.", g.log.line(0).?);
    try std.testing.expect(framesUntil(g, heroSlot(g).?, reddened) < TEST_TOL);
}

test "an unkillable archer keeps 1 hp through gas and bites that would kill it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 } });
    wakeFoes(g);
    g.unkillable = true;
    g.lv.addGas(.{ .x = 20, .y = 20 }, TEST_GAS);
    g.archer().?.hp = 2;
    for (0..20) |_| use(g, .wait);
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
        wakeFoes(g);
        const id = spawnAt(g, .bloat, .{ .x = 21, .y = 20 }, true);
        g.rng = mathx.Rng.init(seed);
        use(g, .wait);
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

test "a node's sky shows its light and its weather out of doors, and neither under a roof" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    const wet: climate.Climate = .{ .light = .bleak, .weather = .drizzle };
    const strand = w.add(.{ .procgen = .{ .floor = .{ .wilds = .{} }, .sky = wet } }).?;
    const cave = w.add(.{ .procgen = .{ .floor = .{ .caves = .{} }, .sky = wet } }).?;
    g.screen = .{ .x = 1920, .y = 1080 };
    for ([_]usize{ strand, cave }) |n| {
        w.start = .{ .node = n, .at = grid.MIDDLE };
        beginWorld(g, w);
        for (0..10) |_| update(g, mathx.FRAME_DT);
        if (n == strand) {
            const bright = sky.brightness(g.light.sky.?);
            const clear = sky.brightness(sky.at(g.hour_shown));
            std.debug.print("a bleak, drizzling wilds at {d:.2}: {d:.2} of a clear noon's light against {d:.2} clear; {d} drops\n", .{ g.hour_shown, bright, clear, g.rain.n });
            try std.testing.expect(bright < clear * 0.9);
            try std.testing.expect(g.rain.n > 0);
        } else {
            try std.testing.expect(g.light.sky == null);
            try std.testing.expectEqual(@as(usize, 0), g.rain.n);
        }
    }
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
    corridor(b);
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
    nudge(g, off.opposite());
    idle(g);
    try std.testing.expectEqual(room, g.node);
    try std.testing.expectEqual(P{ .x = 12, .y = 5 }, g.archer().?.at);
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    try std.testing.expectEqual(slime, g.pool.items[actor.Pool.slot(2)].at);
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
    for ([_]usize{ a, b }) |n| corridor(&w.node[n].plan.bespoke);
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
    try std.testing.expectEqual(Facing.left, g.facing[heroSlot(g).?]);
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
    wakeFoes(g);
    press(g, PAUSE);
    try std.testing.expectEqual(Mode.pause, g.mode);
    press(g, PAUSE);
    try std.testing.expectEqual(Mode.play, g.mode);
    for (std.enums.values(Back)) |back| {
        g.back = back;
        press(g, PAUSE);
        for (0..std.mem.indexOfScalar(PauseRow, PAUSE_ROWS, .back).?) |_| nudge(g, .s);
        press(g, .a);
        try std.testing.expectEqual(@as(?Exit, .back), g.exit);
        try std.testing.expectEqual(Mode.play, g.mode);
        g.exit = null;
    }
    try std.testing.expectEqual(P{ .x = 26, .y = 20 }, g.pool.get(2).?.at);
}

test "a pib's stab bleeds the archer about three times in ten, drawn once the stab lands" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var bled: usize = 0;
    for (0..TRIES) |i| {
        arena(g, .{ .x = 20, .y = 20 }, &.{});
        _ = spawnAt(g, .pib, .{ .x = 21, .y = 20 }, true);
        g.rng = mathx.Rng.init(i);
        use(g, .wait);
        const h = g.archer().?;
        try std.testing.expect(h.hurt());
        if (h.bleed.turns == 0) continue;
        bled += 1;
        try std.testing.expectEqual(bleeding.TURNS, h.bleed.turns);
        try std.testing.expectEqual(@as(u8, 0), g.pictured[heroSlot(g).?].status.get(.bleeding));
        drawnOut(g);
        try std.testing.expectEqual(bleeding.TURNS, g.pictured[heroSlot(g).?].status.get(.bleeding));
    }
    std.debug.print("a pib beside the archer opens a bleed on {d} of {d} stabs\n", .{ bled, TRIES });
    try std.testing.expect(aboutRate(bled, mathx.fraction(actor.row(.pib).blow.strike.bleeds)));
}

test "a bleed costs the archer 1 a turn standing and 2 a turn it steps, and stops after five" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const h = g.archer().?;
    h.bleed = .{ .turns = bleeding.TURNS };
    const full = h.hp;
    use(g, .wait);
    try std.testing.expectEqual(full - bleeding.STILL, h.hp);
    nudge(g, .e);
    try std.testing.expectEqual(full - bleeding.STILL - bleeding.MOVING, h.hp);
    for (0..bleeding.TURNS - 2) |_| use(g, .wait);
    const spent = full - h.hp;
    try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
    try std.testing.expect(std.mem.indexOf(u8, g.log.line(0).?, "stops bleeding") != null);
    use(g, .wait);
    std.debug.print("a {d}-turn bleed, one turn stepped: {d} hp; none after\n", .{ bleeding.TURNS, spent });
    try std.testing.expectEqual(bleeding.STILL * (bleeding.TURNS - 1) + bleeding.MOVING, spent);
    try std.testing.expectEqual(full - spent, h.hp);
}

test "a pib that sees a foe die wakes and runs for a few turns, then comes back; one behind a wall does not" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const hero = P{ .x = 14, .y = 20 };
    arena(g, hero, &.{.{ .x = 19, .y = 20 }});
    wallRow(&g.lv, 22, 15, 25);
    const near = spawnAt(g, .pib, .{ .x = 20, .y = 21 }, false);
    const walled = spawnAt(g, .pib, .{ .x = 19, .y = 24 }, false);
    castSight(g, hero);
    wound(g, 2, actor.row(.rat).hp, SHOOT, .{ .from = hero, .wait = 0.2 });
    const p = g.pool.get(near).?;
    try std.testing.expect(p.awake);
    try std.testing.expectEqual(actor.FLEE_TURNS, p.fright);
    try std.testing.expectEqual(@as(u8, 0), g.pool.get(walled).?.fright);
    try std.testing.expect(std.mem.indexOf(u8, g.log.line(0).?, "flees in terror") != null);
    const speech = &g.fx.speech[actor.Pool.slot(near)];
    const rng = g.rng;
    g.st = .{};
    update(g, 0.1);
    try std.testing.expectEqual(@as(f32, 0), speech.life);
    update(g, 0.11);
    try std.testing.expectEqual(fx.SPEECH_S, speech.life);
    try std.testing.expectEqual(@as(?usize, null), g.fx.speech[actor.Pool.slot(walled)].after);
    try std.testing.expectEqual(@as(f32, 0), g.fx.speech[actor.Pool.slot(walled)].life);
    scare(g, actor.Pool.slot(2));
    try std.testing.expectEqual(@as(?usize, null), speech.after);
    update(g, fx.SPEECH_S);
    try std.testing.expectEqual(@as(f32, 0), speech.life);
    try std.testing.expectEqualDeep(rng, g.rng);
    std.debug.print("pib reaction: {d} phrases, waits for impact, expires after {d:.1}s, no simulation RNG spent\n", .{ fx.FRIGHT_WORDS.len, fx.SPEECH_S });
    var far = mathx.dist(p.at, hero);
    const from = far;
    for (0..actor.FLEE_TURNS) |_| {
        endTurn(g);
        try std.testing.expectEqual(far + 1, mathx.dist(p.at, hero));
        far += 1;
    }
    try std.testing.expectEqual(@as(u8, 0), p.fright);
    endTurn(g);
    std.debug.print("a frightened pib runs from {d} to {d} cells in {d} turns, then turns back to {d}\n", .{ from, far, actor.FLEE_TURNS, mathx.dist(p.at, hero) });
    try std.testing.expect(mathx.dist(p.at, hero) < far);
}

test "a frightened pib in a dead end holds it, and strikes only an archer beside it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const end = P{ .x = 18, .y = 20 };
    const walls = [_]P{ .{ .x = 17, .y = 19 }, .{ .x = 18, .y = 19 }, .{ .x = 19, .y = 19 }, .{ .x = 19, .y = 20 }, .{ .x = 19, .y = 21 }, .{ .x = 18, .y = 21 }, .{ .x = 17, .y = 21 } };
    var moves: usize = 0;
    var strikes: i32 = 0;
    for ([_]P{ .{ .x = 14, .y = 20 }, .{ .x = 17, .y = 20 } }) |hero| {
        arena(g, hero, &.{});
        for (walls) |w| g.lv.set(w, .wall);
        const id = spawnAt(g, .pib, end, true);
        g.pool.get(id).?.fright = actor.FLEE_TURNS;
        const full = g.archer().?.hp;
        for (0..actor.FLEE_TURNS) |_| {
            endTurn(g);
            if (!g.pool.get(id).?.at.eq(end)) moves += 1;
        }
        if (hero.x == 17) strikes = full - g.archer().?.hp else try std.testing.expectEqual(full, g.archer().?.hp);
    }
    std.debug.print("a cornered pib over {d} turns: {d} steps out of its dead end, {d} hp off an archer beside it\n", .{ actor.FLEE_TURNS, moves, strikes });
    try std.testing.expectEqual(@as(usize, 0), moves);
    try std.testing.expect(strikes > 0);
}

fn heroArena(g: *Game, c: heroes.Class, hero: P, rats: []const P) void {
    g.class = c;
    g.bar = skillbar.Bar.of(c);
    arena(g, hero, rats);
}

/// An RNG matching `knock` whose next shield bash stuns, or does not.
fn bashRng(stuns: bool) mathx.Rng {
    const Stuns = struct {
        stuns: bool,
        fn holds(s: @This(), rng: *mathx.Rng) bool {
            _ = bash.roll(rng);
            return bash.procs(rng, 0) == s.stuns;
        }
    };
    return rngWhere(Stuns{ .stuns = stuns });
}

test "each spark that stuns costs a chasing rat its next turn, and mana is spent on confirmation" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    try std.testing.expectEqual(actor.Kind.wizard, g.archer().?.kind);
    const rat = g.pool.get(2).?;
    rat.awake = true;
    toughen(rat);
    for (0..2) |_| {
        press(g, .x);
        try std.testing.expectEqual(Mode.aim, g.mode);
        g.rng = procRng(.spark, 1);
        press(g, .x);
        drawnOut(g);
    }
    const dealt = TEST_HP - rat.hp;
    try std.testing.expect(dealt >= 2 * spark.LIGHTNING_LO and dealt <= 2 * spark.LIGHTNING_HI);
    try std.testing.expectEqual(@as(i32, 26), rat.at.x);
    try std.testing.expectEqual(heroes.MANA - 2 * (spark.COST - heroes.MANA_REGEN), g.mana);
    use(g, .wait);
    try std.testing.expectEqual(@as(i32, 25), rat.at.x);
    std.debug.print("spark: {d} lightning over 2 stunning hits; the rat lost both turns, then walked on\n", .{dealt});
}

test "a knight's shield bash knocks a foe back a tile, and its stun keeps the foe from stepping back in" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    var landed: [2]i32 = undefined;
    for ([_]bool{ true, false }, &landed) |stuns, *x| {
        heroArena(g, .knight, from, &.{.{ .x = 21, .y = 20 }});
        const rat = g.pool.get(2).?;
        rat.awake = true;
        toughen(rat);
        const hp = g.archer().?.hp;
        press(g, .b);
        try std.testing.expectEqual(Mode.aim, g.mode);
        try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mark);
        g.rng = bashRng(stuns);
        press(g, .b);
        const dealt = TEST_HP - rat.hp;
        try expectWithin(dealt, bash.DMG_LO, bash.DMG_HI);
        try std.testing.expectEqual(hp, g.archer().?.hp);
        try std.testing.expectEqual(manaAfter(.shield_bash), g.mana);
        try std.testing.expectEqual(bash.COOLDOWN - 1, g.cooldown.get(.shield_bash));
        x.* = rat.at.x;
        drawnOut(g);
        try std.testing.expect(samePx(cellPx(rat.at), g.glide[actor.Pool.slot(2)].now()));
    }
    try std.testing.expectEqual(@as(i32, 22), landed[0]);
    try std.testing.expectEqual(@as(i32, 21), landed[1]);
    heroArena(g, .knight, from, &.{.{ .x = 21, .y = 20 }});
    g.lv.set(.{ .x = 22, .y = 20 }, .wall);
    press(g, .b);
    g.rng = bashRng(true);
    press(g, .b);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.pool.get(2).?.at);
    std.debug.print("shield bash: stunned rat ends the turn at x {d}, unstunned steps back to x {d}; against a wall it stays\n", .{ landed[0], landed[1] });
}

test "a foe knocked back and stepping in again is drawn on its cell until the bash lands, then knocked the whole tile" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{at});
    const rat = g.pool.get(2).?;
    rat.awake = true;
    toughen(rat);
    press(g, .b);
    g.rng = bashRng(false);
    press(g, .b);
    try std.testing.expectEqual(@as(i32, 21), rat.at.x);
    const gl = &g.glide[actor.Pool.slot(2)];
    try std.testing.expect(samePx(cellPx(at), gl.now()));
    var held: f32 = 0;
    var furthest: f32 = 0;
    var t: f32 = 0;
    while (t < 2 and g.busy > 0) : (t += TEST_DT) {
        update(g, TEST_DT);
        if (samePx(cellPx(at), gl.now())) held = t + TEST_DT;
        furthest = @max(furthest, gl.now().x);
    }
    std.debug.print("knocked rat: still on its cell {d:.3} s in (the bash lands at {d:.3}), knocked to x {d:.1} px of {d}\n", .{ held, BUMP_LANDS, furthest, cellPx(at.add(.{ .x = 1, .y = 0 })).x });
    try std.testing.expect(held + TEST_TOL >= BUMP_LANDS);
    try std.testing.expect(furthest > cellPx(at.add(.{ .x = 1, .y = 0 })).x - 1);
}

test "a cleave strikes only the bodies in its arc as it is swung, not a half split into it by the same swing" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const slime = P{ .x = 21, .y = 19 };
    heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{});
    for ([_]P{ .{ .x = 20, .y = 18 }, .{ .x = 21, .y = 18 }, .{ .x = 22, .y = 18 }, .{ .x = 20, .y = 19 }, .{ .x = 22, .y = 19 }, .{ .x = 22, .y = 20 } }) |w| g.lv.set(w, .wall);
    const id = spawnAt(g, .slime, slime, false);
    g.pool.get(id).?.hp = @divTrunc(actor.row(.slime).hp, 2);
    press(g, .x);
    nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mark);
    press(g, .x);
    var slimes: usize = 0;
    for (g.pool.slice()) |a| {
        if (!a.alive or a.kind == .knight) continue;
        slimes += 1;
        try std.testing.expectEqual(actor.Kind.slime_half, a.kind);
        try std.testing.expectEqual(a.max, a.hp);
    }
    std.debug.print("cleave on a slime that splits into the arc: {d} halves, both whole\n", .{slimes});
    try std.testing.expectEqual(@as(usize, 2), slimes);
}

test "a knight's cleave strikes the three tiles of its arc and nothing outside it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const arc = [_]P{ .{ .x = 21, .y = 19 }, .{ .x = 21, .y = 20 }, .{ .x = 21, .y = 21 } };
    const outside = [_]P{ .{ .x = 19, .y = 20 }, .{ .x = 20, .y = 21 } };
    heroArena(g, .knight, .{ .x = 20, .y = 20 }, &(arc ++ outside));
    toughenFoes(g);
    press(g, .x);
    try std.testing.expectEqual(Mode.aim, g.mode);
    nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mark);
    press(g, .x);
    var hit: usize = 0;
    for (g.pool.slice()[1..], 0..) |a, i| {
        const lost = TEST_HP - a.hp;
        if (i < arc.len) {
            try expectWithin(lost, cleave.DMG_LO, cleave.DMG_HI);
            hit += 1;
        } else try std.testing.expectEqual(@as(i32, 0), lost);
    }
    try std.testing.expectEqual(manaAfter(.cleave), g.mana);
    std.debug.print("cleave: {d} of {d} rats struck, the {d} outside its arc untouched\n", .{ hit, arc.len + outside.len, outside.len });
}

test "a wizard's blink lands further than juke and takes a turn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    heroArena(g, .wizard, from, &.{.{ .x = 30, .y = 20 }});
    const rat = g.pool.get(2).?;
    rat.awake = true;
    const hour = g.clock;
    press(g, .b);
    try std.testing.expectEqual(Mode.aim, g.mode);
    for (0..blink.RANGE + 1) |_| nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 20 + blink.RANGE, .y = 20 }, g.mark);
    press(g, .b);
    try std.testing.expectEqual(g.mark, g.archer().?.at);
    try std.testing.expect(g.glide[actor.Pool.slot(2)].t <= -STAGGER_S + TEST_TOL);
    try std.testing.expect(!std.meta.eql(hour, g.clock));
    try std.testing.expectEqual(@as(i32, 29), rat.at.x);
    try std.testing.expectEqual(manaAfter(.blink), g.mana);
    try std.testing.expectEqual(blink.COOLDOWN - 1, g.cooldown.get(.blink));
    std.debug.print("blink: {d} tiles in a turn; the rat stepped once\n", .{blink.RANGE});
}

test "a flask drink takes a turn, recovers over the next turns, and kills refill its charges" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    const h = g.archer().?;
    h.hp = 1;
    g.mana = 0;
    const hour = g.clock;
    press(g, .rb);
    try std.testing.expect(!std.meta.eql(hour, g.clock));
    const per = firstLifeTick(h.max);
    try std.testing.expectEqual(1 + per, h.hp);
    for (1..flask.TURNS) |_| use(g, .wait);
    try std.testing.expectEqual(1 + flask.lifeOf(h.max), h.hp);
    press(g, .rt);
    for (1..flask.TURNS + 2) |_| use(g, .wait);
    try std.testing.expectEqual(@min(heroes.MANA, flask.MANA_GAIN + heroes.MANA_REGEN * (flask.TURNS + flask.TURNS + 2)), g.mana);
    press(g, .rb);
    press(g, .rb);
    try std.testing.expectEqual(@as(u8, 0), g.flasks.get(.life).uses());
    const hp = h.hp;
    press(g, .rb);
    try std.testing.expectEqual(hp, h.hp);
    try std.testing.expectEqual(@as(u8, 0), g.flasks.get(.life).uses());
    for (0..flask.USE / flask.PER_KILL) |_| fell(g, 2);
    try std.testing.expectEqual(@as(u8, 1), g.flasks.get(.life).uses());
    std.debug.print("life flask: {d} hp over {d} turns on a knight of {d}; empty after {d} drinks; {d} kills refill one\n", .{ flask.lifeOf(h.max), flask.TURNS, h.max, flask.CHARGES / flask.USE, flask.USE / flask.PER_KILL });
}

fn firstLifeTick(max: i32) i32 {
    var f = flask.Flask{};
    f.drink(flask.lifeOf(max));
    return f.tick();
}

test "a flask's heal shows at the turn's end, before a bite that turn lands" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    wakeFoes(g);
    const h = g.archer().?;
    h.hp = 10;
    catchUp(g);
    const hero = heroSlot(g).?;
    press(g, .rb);
    const healed = 10 + firstLifeTick(h.max);
    try std.testing.expect(h.hp < healed);
    var first: ?i32 = null;
    g.st = .{};
    var t: f32 = 0;
    while (t < 1) : (t += TEST_DT) {
        update(g, TEST_DT);
        if (first == null and g.pictured[hero].hp != 10) first = g.pictured[hero].hp;
    }
    std.debug.print("flask heal under a bite: drawn {d} -> {?d} -> {d}\n", .{ 10, first, g.pictured[hero].hp });
    try std.testing.expectEqual(@as(?i32, healed), first);
    try std.testing.expectEqual(h.hp, g.pictured[hero].hp);
}

test "a kill's flask refill shows as the kill is drawn, not as the arrow leaves" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    g.flasks.getPtr(.life).charges = flask.USE - flask.PER_KILL;
    catchUp(g);
    press(g, .x);
    press(g, .x);
    try std.testing.expect(g.pool.get(2) == null);
    try std.testing.expectEqual(@as(u8, 1), g.flasks.get(.life).uses());
    try std.testing.expectEqual(@as(u8, 0), g.flasks_shown.get(.life).uses());
    const Refilled = struct {
        fn f(game: *Game, _: usize) bool {
            return game.flasks_shown.get(.life).uses() == 1;
        }
    };
    const t = framesUntil(g, 0, Refilled.f);
    std.debug.print("a kill 7 cells out refills the drawn flask {d:.3} s in, as the arrow lands at {d:.3} s\n", .{ t, flown(6) });
    try std.testing.expectApproxEqAbs(flown(6), t, TEST_TOL);
}

fn manaAfter(act: skillbar.Act) i32 {
    return heroes.MANA - act.cost() + heroes.MANA_REGEN;
}

fn skipsNext(a: *actor.Actor) void {
    a.chill = .{ .turns = 1, .phase = glacial.CYCLE - 1 };
}

test "a pinning shot holds a chasing rat to its cell for two to four of its turns, and a pinned rat still bites" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const rat = g.pool.get(2).?;
    rat.awake = true;
    toughen(rat);
    pressHolding(g, .a, &.{.lb});
    try std.testing.expectEqual(Mode.aim, g.mode);
    pressHolding(g, .a, &.{.lb});
    const dealt = TEST_HP - rat.hp;
    try expectWithin(dealt, bow.DMG_LO, bow.DMG_HI);
    try std.testing.expectEqual(manaAfter(.pinning_shot), g.mana);
    var held: usize = 1;
    while (rat.at.x == 26 and held < 10) {
        use(g, .wait);
        if (rat.at.x == 26) held += 1;
    }
    try expectWithin(held, pinning.TURNS_LO, pinning.TURNS_HI);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    const biter = g.pool.get(2).?;
    biter.awake = true;
    biter.pin.turns = pinning.TURNS_HI;
    const hp = g.archer().?.hp;
    use(g, .wait);
    try std.testing.expect(g.archer().?.hp < hp);
    try std.testing.expectEqual(@as(i32, 21), biter.at.x);
    std.debug.print("pinning shot: {d} damage, the rat held {d} turns, then walked on; pinned beside the hero it bit for {d}\n", .{ dealt, held, hp - g.archer().?.hp });
}

test "a barbed arrow always opens a bleed on a body it leaves alive" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const rat = g.pool.get(2).?;
    toughen(rat);
    pressHolding(g, .b, &.{.lb});
    try std.testing.expectEqual(Mode.aim, g.mode);
    pressHolding(g, .b, &.{.lb});
    const dealt = TEST_HP - rat.hp;
    try expectWithin(dealt, bow.DMG_LO, bow.DMG_HI);
    try std.testing.expectEqual(bleeding.TURNS, rat.bleed.turns);
    try std.testing.expectEqual(manaAfter(.barbed_arrow), g.mana);
    use(g, .wait);
    try std.testing.expect(TEST_HP - rat.hp > dealt);
    std.debug.print("barbed arrow: {d} damage, a {d}-turn bleed, which bled {d} the next turn\n", .{ dealt, bleeding.TURNS, TEST_HP - rat.hp - dealt });
}

test "a frost nova freezes every foe within two tiles, the same roll for each, and none further" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 22, .y = 22 }, .{ .x = 23, .y = 20 } });
    toughenFoes(g);
    pressHolding(g, .a, &.{.lb});
    const near = TEST_HP - g.pool.get(2).?.hp;
    try expectWithin(near, nova.COLD_LO, nova.COLD_HI);
    try std.testing.expectEqual(near, TEST_HP - g.pool.get(3).?.hp);
    try std.testing.expectEqual(TEST_HP, g.pool.get(4).?.hp);
    try std.testing.expectEqual(manaAfter(.frost_nova), g.mana);
    try std.testing.expectEqual(nova.COOLDOWN - 1, g.cooldown.get(.frost_nova));
    std.debug.print("frost nova: {d} cold to the foes 1 and 2 tiles off, none to the one 3 off\n", .{near});
}

test "a half split into the cell of a body the same blow kills slides out once that body is no longer drawn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const cell = P{ .x = 21, .y = 20 };
    const at = P{ .x = 22, .y = 20 };
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{cell});
    g.pool.get(2).?.hp = 1;
    const id = splittable(g, at, false);
    var ring = grid.Box.around(at, 1).cells();
    while (ring.next()) |p| {
        if (!p.eq(at) and !p.eq(cell)) g.lv.set(p, .wall);
    }
    settle(g);
    pressHolding(g, .a, &.{.lb});
    const dying = actor.Pool.slot(2);
    const half = actor.Pool.slot(id) + 1;
    try std.testing.expect(!g.pool.items[dying].alive);
    try std.testing.expect(g.pool.items[half].at.eq(cell));
    var overlap: f32 = 0;
    var t: f32 = 0;
    g.st = .{};
    while (t < 1) : (t += TEST_DT) {
        update(g, TEST_DT);
        if (standing(g, dying) and drawn(g, half) and g.glide[half].done() > 0) overlap += TEST_DT;
    }
    std.debug.print("a half split into a dying rat's cell: {d:.3} s drawn together\n", .{overlap});
    try std.testing.expect(overlap <= TEST_TOL);
    try std.testing.expect(g.glide[half].done() >= 1);
}

test "a fireball bursts on the first foe it strikes, burning the foes round it alike, and none past its blast" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 26, .y = 20 }, .{ .x = 27, .y = 21 }, .{ .x = 29, .y = 20 } });
    toughenFoes(g);
    press(g, .a);
    try std.testing.expectEqual(Mode.aim, g.mode);
    press(g, .a);
    const struck = TEST_HP - g.pool.get(2).?.hp;
    try expectWithin(struck, fireball.FIRE_LO, fireball.FIRE_HI);
    try std.testing.expectEqual(struck, TEST_HP - g.pool.get(3).?.hp);
    try std.testing.expectEqual(TEST_HP, g.pool.get(4).?.hp);
    try std.testing.expectEqual(manaAfter(.fireball), g.mana);
    std.debug.print("fireball: {d} fire to the struck rat and the one beside it, none to the rat 3 tiles on\n", .{struck});
}

test "chain lightning leaps from the struck foe to two more, each within three tiles of the last" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 26, .y = 21 }, .{ .x = 29, .y = 21 }, .{ .x = 25, .y = 25 } });
    toughenFoes(g);
    pressHolding(g, .x, &.{.lb});
    try std.testing.expectEqual(Mode.aim, g.mode);
    pressHolding(g, .x, &.{.lb});
    var hit: usize = 0;
    for ([_]u16{ 2, 3, 4 }) |id| {
        const dealt = TEST_HP - g.pool.get(id).?.hp;
        try expectWithin(dealt, chain.LIGHTNING_LO, chain.LIGHTNING_HI);
        hit += 1;
    }
    try std.testing.expectEqual(TEST_HP, g.pool.get(5).?.hp);
    try std.testing.expectEqual(manaAfter(.chain_lightning), g.mana);
    std.debug.print("chain lightning: {d} rats struck, the fourth 4 tiles from each left whole\n", .{hit});
}

test "resisted chain lightning still holds play until its last jump" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 26, .y = 21 }, .{ .x = 29, .y = 21 } });
    for (g.pool.slice()[1..]) |*a| a.resists.set(.lightning, 100);
    pressHolding(g, .x, &.{.lb});
    pressHolding(g, .x, &.{.lb});
    const last = flown(g.shot.?.flight.len - 1) + chain.JUMPS * ZAP_S;
    try std.testing.expect(g.busy >= last);
    g.st = .{ .pressed = .initOne(.y) };
    const before = g.clock;
    update(g, last - ZAP_S / 2);
    try std.testing.expectEqual(before, g.clock);
    drawnOut(g);
    try std.testing.expectEqual(@as(usize, 0), g.fx.due_n);
    std.debug.print("resisted chain lightning: {d} jumps hold play for {d:.3} s\n", .{ chain.JUMPS, last });
}

test "a mana shield turns a bite onto mana, the orb dropping as the bite lands, until its turns run out" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    g.pool.get(2).?.awake = true;
    const h = g.archer().?;
    const hp = h.hp;
    pressHolding(g, .b, &.{.lb});
    const after_cast = manaAfter(.mana_shield);
    const bitten = after_cast - g.mana;
    try std.testing.expectEqual(hp, h.hp);
    try expectWithin(bitten, 1, 3);
    try std.testing.expectEqual(ward.TURNS - 1, h.ward.turns);
    try std.testing.expectEqual(after_cast, g.mana + g.mana_held);
    g.st = .{};
    update(g, TEST_DT);
    try std.testing.expectEqual(ward.TURNS, g.pictured[heroSlot(g).?].status.get(.warded));
    try std.testing.expect(g.mana_held > 0);
    drawnOut(g);
    try std.testing.expectEqual(@as(i32, 0), g.mana_held);
    for (1..ward.TURNS) |_| use(g, .wait);
    try std.testing.expectEqual(hp, h.hp);
    try std.testing.expectEqual(@as(u8, 0), h.ward.turns);
    use(g, .wait);
    try std.testing.expect(h.hp < hp);
    std.debug.print("mana shield: a bite of {d} taken from mana, the orb holding till it landed; {d} turns, then the bites drew blood\n", .{ bitten, ward.TURNS });
}

test "mana shield deductions follow each staggered hit" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 20, .y = 21 } });
    wakeFoes(g);
    pressHolding(g, .b, &.{.lb});
    const before = manaAfter(.mana_shield);
    try std.testing.expectEqual(before, g.mana + g.mana_held);
    g.st = .{};
    update(g, BUMP_LANDS + STAGGER_S * 1.5);
    const between = g.mana + g.mana_held;
    try std.testing.expect(between < before);
    try std.testing.expect(between > g.mana);
    drawnOut(g);
    try std.testing.expectEqual(@as(i32, 0), g.mana_held);
    std.debug.print("mana shield: shown mana {d}, {d}, {d} across two hits\n", .{ before, between, g.mana });
}

test "a charge runs the knight down a line to the foe, striking it and knocking it back, but a pinned foe stands" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var stood: [2]i32 = undefined;
    for ([_]bool{ false, true }, &stood) |pinned, *x| {
        heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
        const rat = g.pool.get(2).?;
        toughen(rat);
        skipsNext(rat);
        if (pinned) rat.pin.turns = pinning.TURNS_HI;
        press(g, .a);
        try std.testing.expectEqual(Mode.aim, g.mode);
        try std.testing.expectEqual(P{ .x = 23, .y = 20 }, g.mark);
        press(g, .a);
        try std.testing.expectEqual(P{ .x = 22, .y = 20 }, g.archer().?.at);
        const dealt = TEST_HP - rat.hp;
        try expectWithin(dealt, charge.DMG_LO, charge.DMG_HI);
        try std.testing.expectEqual(manaAfter(.charge), g.mana);
        try std.testing.expectEqual(charge.COOLDOWN - 1, g.cooldown.get(.charge));
        x.* = rat.at.x;
    }
    try std.testing.expectEqual(@as(i32, 24), stood[0]);
    try std.testing.expectEqual(@as(i32, 23), stood[1]);
    std.debug.print("charge: 2 tiles run, the rat knocked to x {d}; pinned, it stood at x {d}\n", .{ stood[0], stood[1] });
}

test "a knocked rat's bleed lands once its knock slide has ended" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
    const rat = g.pool.get(2).?;
    toughen(rat);
    skipsNext(rat);
    rat.bleed.start();
    rat.bleed.fresh = false;
    press(g, .a);
    press(g, .a);
    const i = actor.Pool.slot(2);
    try std.testing.expectEqual(@as(i32, 24), rat.at.x);
    const bled = rat.hp;
    g.st = .{};
    var t: f32 = 0;
    while (g.pictured[i].hp != bled and t < 2) : (t += TEST_DT) update(g, TEST_DT);
    try std.testing.expectEqual(bled, g.pictured[i].hp);
    try std.testing.expect(g.glide[i].left() <= TEST_TOL);
    std.debug.print("knocked and bleeding: the tick landed {d:.3} s in, the slide done\n", .{t});
}

test "bleeding doubles after knockback even if the foe loses its action" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var checked: usize = 0;
    for ([_]bool{ false, true }) |pinned| {
        var hp: [2]i32 = undefined;
        for ([_]bool{ false, true }, &hp) |bleeds, *left| {
            heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
            g.rng = mathx.Rng.init(17);
            const rat = g.pool.get(2).?;
            toughen(rat);
            skipsNext(rat);
            if (pinned) rat.pin.turns = pinning.TURNS_HI;
            if (bleeds) {
                rat.bleed.start();
                rat.bleed.fresh = false;
            }
            press(g, .a);
            press(g, .a);
            left.* = rat.hp;
            try std.testing.expectEqual(@as(i32, if (pinned) 23 else 24), rat.at.x);
            if (bleeds) {
                drawnOut(g);
                skipsNext(rat);
                endTurn(g);
                try std.testing.expectEqual(bleeding.STILL, left.* - rat.hp);
            }
        }
        try std.testing.expectEqual(if (pinned) bleeding.STILL else bleeding.MOVING, hp[0] - hp[1]);
        checked += 1;
    }
    std.debug.print("{d} bleeding cases: a stalled knocked foe moves; a pinned foe stays still\n", .{checked});
}

test "inspect walks the orbs, the slots and the statuses, spends no turn, and backs out by any way back or its own button" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    g.archer().?.bleed.turns = bleeding.TURNS;
    catchUp(g);
    const clock = g.clock;
    press(g, skillbar.INSPECT);
    try std.testing.expectEqual(Mode.inspect, g.mode);
    g.inspecting = .life;
    var walked: usize = 0;
    while (g.inspecting != .mana and walked < 20) : (walked += 1) nudge(g, .e);
    try std.testing.expectEqual(skillbar.SLOTS.len + 1, walked);
    nudge(g, .e);
    try std.testing.expectEqual(Spot.mana, g.inspecting);
    g.inspecting = .{ .slot = 3 };
    nudge(g, .n);
    try std.testing.expectEqual(Spot{ .status = .bleeding }, g.inspecting);
    nudge(g, .s);
    try std.testing.expect(g.inspecting == .slot);
    for ([_]input.Button{ menu.BACK, menu.PAUSE, skillbar.INSPECT }) |out| {
        press(g, out);
        try std.testing.expectEqual(Mode.play, g.mode);
        press(g, skillbar.INSPECT);
        try std.testing.expectEqual(Mode.inspect, g.mode);
    }
    press(g, skillbar.INSPECT);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expect(std.meta.eql(clock, g.clock));
    std.debug.print("inspect: life to mana in {d} steps across {d} slots, up to a status and down again; 3 ways out, no turn spent\n", .{ walked, skillbar.SLOTS.len });
}

test "the mouse over an orb, a slot or a status shows its tooltip while playing, and nothing off the hud" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    g.archer().?.bleed.turns = bleeding.TURNS;
    catchUp(g);
    var buf: [SPOTS_MAX]Part = undefined;
    const spots = spotsOf(g, &buf);
    for (spots) |s| {
        const c = centreOf(s.box);
        g.st.pointer = .{ .x = @intFromFloat(c[0]), .y = @intFromFloat(c[1]) };
        try std.testing.expectEqual(s.spot, hovered(g).?.spot);
    }
    const orb = hud.orbBox(hudLayout(g).life);
    g.st.pointer = .{ .x = @intFromFloat(orb.x + 1), .y = @intFromFloat(orb.y + 1) };
    try std.testing.expectEqual(@as(?Part, null), hovered(g));
    g.st.pointer = .{ .x = 0, .y = 0 };
    try std.testing.expectEqual(@as(?Part, null), hovered(g));
    g.st.pointer = null;
    try std.testing.expectEqual(@as(?Part, null), hovered(g));
    const c = centreOf(spots[1].box);
    g.st.pointer = .{ .x = @intFromFloat(c[0]), .y = @intFromFloat(c[1]) };
    g.mode = .pause;
    try std.testing.expectEqual(@as(?Part, null), hovered(g));
    std.debug.print("hover: {d} hud parts each found at their centre; the orb's corner, the screen's, no mouse and pause show none\n", .{spots.len});
}
