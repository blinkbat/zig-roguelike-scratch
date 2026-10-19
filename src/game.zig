const std = @import("std");
const items = @import("play/items.zig");
const progress = @import("play/progress.zig");
const journal = @import("ui/journal.zig");
const rl = @import("raylib");

const mathx = @import("core/mathx.zig");
const input = @import("core/input.zig");
const grid = @import("map/grid.zig");
const fov = @import("map/fov.zig");
const gen = @import("map/gen.zig");
const carve = @import("map/carve.zig");
const gas = @import("map/gas.zig");
const atlas = @import("map/atlas.zig");
const spar = @import("map/spar.zig");
const editor = @import("edit/editor.zig");
const menu = @import("ui/menu.zig");
const hud = @import("ui/hud.zig");
const book = @import("ui/book.zig");
const heroes = @import("play/hero.zig");
const naming = @import("ui/naming.zig");
const actor = @import("play/actor.zig");
const bow = @import("play/bow.zig");
const damage = @import("play/damage.zig");
const attrs = @import("play/attrs.zig");
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
const climate = @import("map/climate.zig");
const day = @import("map/day.zig");
const lume = @import("map/lume.zig");

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
const TEXT: i32 = font.BODY;
const LINE_W: i32 = authored(2);
const OUTLINE_INSET: i32 = authored(1);
const BODY_BAR_INSET: i32 = authored(6);
const BODY_BAR_H: i32 = authored(4);
const BODY_BAR_LIFT: i32 = authored(2);
const LEAN_PAD: i32 = authored(4);
const TEXT_LEADING: i32 = 6;
const TEXT_LINE: i32 = TEXT + TEXT_LEADING;
const DEAD_TITLE_DY: i32 = -100;
const DEAD_SCORE_DY: i32 = -10;
const SLOT_PX: i32 = 48;
const SLOT_MID: i32 = @divTrunc(SLOT_PX, 2);
const CLEAR_GLYPH: i32 = @divTrunc(SLOT_PX, 2);
const SLOT_GAP: i32 = 8;
const SLOT_STEP: i32 = SLOT_PX + SLOT_GAP;
const CARRIED_A: f32 = 0.35;
const GROUP_GAP: i32 = 16;
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
const CHEST_GOLD_LO: i32 = 18;
const CHEST_GOLD_HI: i32 = 36;
const SHOTS_DIR = "shots";
const SHOTS_MAPS = SHOTS_DIR ++ "/maps";
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
/// Loot rolls on its own stream, so a drop does not shift the fight's rolls.
const LOOT_SALT: u64 = 0x10_07_A11;
/// Reach of Interact: underfoot and the cells beside the hero.
const INTERACT_REACH: i32 = 1;
const NEARBY_MAX = items.GROUND_MAX + grid.Cells.square(INTERACT_REACH);
const NearbyBuf = [NEARBY_MAX]book.Nearby;
/// Ground drops kept free for every foe a node may hold, slime halves included, to drop on dying.
const FOE_DROPS = actor.MAX;
comptime {
    std.debug.assert(items.GROUND_MAX > FOE_DROPS);
}
/// Gold and item marks on the ground, beside each other in their cell.
const GOLD_DX: i32 = authored(-10);
const DROP_DX: i32 = authored(10);
const LOOT_DY: i32 = authored(12);
const LOOT_PX: i32 = authored(24);

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
    log,
    /// Of `skillbar.SLOTS`.
    slot: usize,
    status: fx.Status,
};

pub const Back = enum { title, editor };

pub const Exit = enum { back, quit };

const PAUSE = menu.PAUSE;
const PausePage = enum { main, debug, character };
const PauseRow = enum { resume_, character, debug, back, quit };
const PAUSE_ROWS = std.enums.values(PauseRow);
const DebugRow = enum { restart_map, reveal_map };
const DEBUG_ROWS = std.enums.values(DebugRow);

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

pub const Log = journal.Log;

/// Presentation only: the hit already resolved when this was made.
pub const Shot = struct {
    flight: bow.Flight,
    from: P,
    act: skillbar.Act = .shoot,
    t: f32 = 0,
    trail_t: f32 = 0,

    /// When the missile reaches its last cell, as its hit is presented.
    fn lands(self: *const Shot) f32 {
        return flown(self.flight.len -| 1);
    }

    fn ends(self: *const Shot) f32 {
        return flown(self.flight.len);
    }

    fn position(self: *const Shot, time: f32) [2]f32 {
        const a = mathx.centre(self.from);
        if (self.flight.len == 0) return a;
        const b = mathx.centre(self.flight.path[self.flight.len - 1]);
        const duration = self.lands();
        const k = if (duration > 0) std.math.clamp(time / duration, 0, 1) else 1;
        return mathx.lerp2(a, b, k);
    }

    fn direction(self: *const Shot) [2]f32 {
        const a = mathx.centre(self.from);
        const b = self.position(flown(self.flight.len));
        const len = @max(0.001, mathx.len(b[0] - a[0], b[1] - a[1]));
        return .{ (b[0] - a[0]) / len, (b[1] - a[1]) / len };
    }
};

const TRAIL_PER_CELL: usize = 12;

fn flown(n: usize) f32 {
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
        const lands = flown(shot_.flight.len - 1);
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
    /// Retain mid-hop height when a new step starts.
    from_lift: f32 = 0,
    /// Pixels toward what a melee blow strikes, at the bump's height; null for a step.
    bump: ?rl.Vector2 = null,
    /// The glide still drawn while this one waits its turn.
    prior: ?Prior = null,

    /// Prior motion, offset by `ahead` seconds.
    const Prior = struct {
        from: rl.Vector2,
        to: P,
        gait: look.Gait,
        from_lift: f32,
        bump: ?rl.Vector2,
        ahead: f32,

        fn copy(dst: anytype, src: anytype) void {
            inline for (std.meta.fields(Prior)) |f| {
                if (comptime !std.mem.eql(u8, f.name, "ahead")) @field(dst, f.name) = @field(src, f.name);
            }
        }
    };

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
            Prior.copy(&was, self);
            was.ahead = self.t - t;
            prior = was;
        }
        return .{ .from = then.now(), .to = p, .t = t, .gait = self.gait, .from_lift = then.height(), .prior = prior };
    }

    fn waiting(self: Glide) ?Glide {
        if (self.t >= 0) return null;
        const p = self.prior orelse return null;
        var gl = Glide{ .from = undefined, .to = undefined, .t = self.t + p.ahead, .gait = undefined };
        Prior.copy(&gl, p);
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
        return self.from.lerp(cellPx(self.to), k);
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

const Bite = union(enum) { hurt: fx.After, kill: fx.After, burst: fx.After, miss };

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

const Flasks = std.EnumArray(flask.Kind, flask.Flask);

pub const Game = struct {
    mode: Mode = .play,
    paused_from: Mode = .play,
    pause_menu: menu.Menu = .{},
    pause_page: PausePage = .main,
    character: book.Book = .{},
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
    gold_taken: ?P = null,
    /// `xpLevels` as of the last drawn turn, and the bar easing toward it.
    xp_aim: f32 = 0,
    xp_shown: f32 = 0,
    /// `growth` and `gold` as of the last drawn turn, for the character book.
    growth_shown: progress.State = .{},
    gold_shown: i32 = 0,
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
    /// Map pixels, eased toward the hero. Nothing in the simulation reads it.
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
    /// Living foes at turn start, nearest first; also their presentation order.
    order: [actor.MAX]u16 = undefined,
    order_n: usize = 0,
    /// Seconds until the last turn's slowest glide, arrow or flash ends; a walk waits for it.
    busy: f32 = 0,
    /// The latest walk or skill asked for while `busy`.
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
    collectGold(g, h.at);
    noticeItems(g, h.at);
    g.unsaved = true;
    freshTurn(g);
    settle(g);
}

fn rollOf(run: u64, n: usize) u64 {
    return std.hash.Wyhash.hash(run, std.mem.asBytes(&n));
}

fn leadsTo(g: *const Game, p: P) ?atlas.Link {
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
    enter(g, l.node, g.map.?.door(l).at);
    g.pending = walk;
    g.facing[hero] = facing;
    var title: [atlas.TITLE_MAX]u8 = undefined;
    g.log.say("Entered {s}.", .{g.map.?.node[l.node].title(l.node, &title)});
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

fn restart(g: *Game) void {
    if (g.map) |w| beginMap(g, w) else begin(g, freshSeed());
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
    toDefaults(g, &.{ "kills", "gold", "mana_held", "flasks", "flasks_shown", "cooldown", "stepped", "log", "mode" });
    g.inventory = .{};
    g.ground = .{};
    g.growth = progress.State.of(g.class);
    g.bar = g.growth.bar(g.class);
    g.loot_rng = mathx.Rng.init(g.seed ^ LOOT_SALT);
    settleXp(g);
    g.mana = manaMax(g);
    g.vignette.clear();
}

fn freshTurn(g: *Game) void {
    toDefaults(g, &.{ "shot", "travel", "order_n", "busy", "pending", "lead", "owed", "split_from", "turning", "displaced", "gold_taken" });
    g.fx.clear();
    g.cloud.clear();
}

fn settle(g: *Game) void {
    g.art_ready = false;
    castSight(g, g.heroActor().?.at);
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

const Move = enum { kick, open, step, blocked };

fn heroMove(g: *Game, d: mathx.Dir) Move {
    const h = g.heroActor() orelse return .blocked;
    if (opensChest(g, h.at, d)) return .open;
    if (g.lv.taken(h.at.add(d.delta())) and g.lv.passOk(h.at, d)) return .kick;
    return if (g.lv.stepOk(h.at, d, g.hero)) .step else .blocked;
}

fn opensChest(g: *const Game, from: P, d: mathx.Dir) bool {
    return g.lv.at(from.add(d.delta())).opened() != null;
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
    const h = g.heroActor() orelse return;
    const to = h.at.add(d.delta());
    switch (heroMove(g, d)) {
        .kick => {
            const w = g.lv.who(to);
            const s = heroBump(g, h.at, to, late);
            switch (g.class) {
                inline else => |c| {
                    const blow = comptime actor.row(c.kind()).blow.strike;
                    if (w != grid.NO_ONE) wound(g, w, heroRoll(g, .melee, if (g.inventory.gear.weapon(.melee)) |b| b.roll(&g.rng) else blow.roll(&g.rng)), blow.verb, s) else smash(g, to, blow.verb, s);
                },
            }
            g.lead = s.wait;
        },
        .open => if (!openChest(g, to)) return,
        .step => heroTo(g, to),
        .blocked => return,
    }
    turnToward(g, g.hero, d.delta().x);
    endTurn(g);
}

/// `late` seconds into the bump; the hit lands at its apex.
fn heroBump(g: *Game, from: P, at: P, late: f32) Stroke {
    const i = heroSlot(g).?;
    _ = glideHeld(g, i, g.glide[i].bumping(at, late));
    return .{ .from = from, .wait = BUMP_LANDS - late };
}

fn heroTo(g: *Game, to: P) void {
    g.pool.move(&g.lv, g.hero, to);
    collectGold(g, to);
    noticeItems(g, to);
    g.stepped = true;
    g.travel = leadsTo(g, to);
}

fn openAim(g: *Game, by: input.Button, act: skillbar.Act) void {
    const h = g.heroActor() orelse return;
    aimAt(g, by, act, h.at, bow.pick(&g.lv, &g.pool, h.at));
}

fn openLeap(g: *Game, by: input.Button, act: skillbar.Act) void {
    const h = g.heroActor() orelse return;
    g.mark = h.at;
    aiming(g, by, act);
}

fn openSwing(g: *Game, by: input.Button, act: skillbar.Act) void {
    const h = g.heroActor() orelse return;
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

const Blocked = enum { cooling, mana, empty, locked };

fn blocked(g: *const Game, act: skillbar.Act, flasks: *const Flasks, mana: i32) ?Blocked {
    if (!g.growth.unlocked(act)) return .locked;
    if (g.cooldown.get(act) > 0) return .cooling;
    if (act.flaskOf()) |k| {
        if (!flasks.get(k).full()) return .empty;
    }
    if (mana < g.growth.cost(act)) return .mana;
    return null;
}

fn heroAttrs(g: *const Game) attrs.Attrs {
    return g.inventory.gear.stats(g.growth.attributes(g.class));
}

fn syncStats(g: *Game) void {
    const h = g.heroActor() orelse return;
    h.max = heroAttrs(g).life();
    h.hp = @min(h.hp, h.max);
    g.mana = @min(g.mana, manaMax(g));
    settleNow(g, heroSlot(g).?);
}

fn skillAttrs(g: *const Game, act: skillbar.Act) attrs.Attrs {
    var a = heroAttrs(g);
    if (act.style()) |s| a.damage_bonus.getPtr(s).* += g.growth.damageBonus(act);
    return a;
}

fn manaMax(g: *const Game) i32 {
    return heroAttrs(g).mana();
}

fn gainMana(g: *Game, n: i32) void {
    g.mana = @min(manaMax(g), g.mana + n);
}

fn manaShown(g: *const Game) i32 {
    return @min(manaMax(g), g.mana + g.mana_held);
}

fn ready(g: *Game, act: skillbar.Act) bool {
    if (!quiet(g)) return false;
    switch (blocked(g, act, &g.flasks, g.mana) orelse return true) {
        .cooling => {
            const left = g.cooldown.get(act);
            g.log.say("{s} is ready in {d} turn{s}.", .{ act.name(), left, plural(left) });
        },
        .mana => g.log.say("{s} needs {d} mana.", .{ act.name(), g.growth.cost(act) }),
        .empty => g.log.say("{s} is empty.", .{act.name()}),
        .locked => g.log.say("{s} is not learned.", .{act.name()}),
    }
    return false;
}

fn spend(g: *Game, act: skillbar.Act) void {
    g.mana -= g.growth.cost(act);
    g.cooldown.set(act, g.growth.cooldown(act));
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
    g.glide[heroSlot(g).?] = Glide.rest(g.heroActor().?);
    turnToward(g, g.hero, to.x - from.x);
    if (act.teleports()) {
        g.fx.shimmer(mathx.centre(from), look.WARD);
        g.fx.shimmer(mathx.centre(to), look.WARD);
    } else g.fx.juke(from, to);
    if (g.travel != null) holdUntil(g, fx.JUKE_S);
    g.unsaved = true;
    castSight(g, to);
    if (act.free()) return;
    g.lead = 0;
    endTurn(g);
}

/// Its recovery starts at the end of the turn the drink takes.
fn drink(g: *Game, act: skillbar.Act, k: flask.Kind) void {
    const h = g.heroActor() orelse return;
    spend(g, act);
    g.flasks.getPtr(k).drink(switch (k) {
        .life => flask.lifeOf(h.max),
        .mana => flask.MANA_GAIN,
    });
    g.flasks_shown.set(k, g.flasks.get(k));
    g.fx.shimmer(mathx.centre(h.at), switch (k) {
        .life => look.LIFE,
        .mana => look.WARD,
    });
    g.log.push(.recovery, "{s} drinks a {s} flask.", .{ g.name.text(), @tagName(k) });
    endTurn(g);
}

fn recover(g: *Game) void {
    const h = g.heroActor() orelse return;
    const hp = h.hp;
    gainMana(g, heroes.MANA_REGEN);
    for (std.enums.values(flask.Kind)) |k| {
        const n = g.flasks.getPtr(k).tick();
        switch (k) {
            .life => h.hp = @min(h.max, h.hp + n),
            .mana => gainMana(g, n),
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
    const h = g.heroActor() orelse return;
    spend(g, act);
    g.log.say("{s} casts {s}.", .{ g.name.text(), act.name() });
    if (comptime act.surrounds()) {
        const s = Stroke{ .from = h.at, .wait = CAST_S };
        holdUntil(g, s.wait);
        areaHit(g, act, h.at, M.around(&g.lv, h.at), s, null, false);
        g.lead = s.wait;
    } else if (comptime act.wards()) {
        h.ward.raise();
        g.fx.shimmer(mathx.centre(h.at), look.WARD);
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

/// Snapshot targets before damage so newborn slime halves are not hit twice.
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
    const h = g.heroActor() orelse return;
    var near = bow.Nearest{ .from = h.at };
    var empty = bow.Nearest{ .from = h.at };
    var cells = grid.Cells.around(h.at, act.reach());
    while (cells.next()) |p| {
        if (act.aimable(&g.lv, h.at, p)) {
            if (g.lv.who(p) != grid.NO_ONE) near.offer(p) else empty.offer(p);
        }
    }
    aimAt(g, by, act, h.at, near.best orelse empty.best);
}

fn rush(g: *Game, from: P, act: skillbar.Act) void {
    switch (act) {
        inline else => |a| if (comptime a.reticle() != .rush) unreachable else {
            const M = skillbar.Act.skill(a);
            const d = M.wayTo(from, g.mark).?;
            const occupied = g.lv.who(g.mark) != grid.NO_ONE;
            const stop = if (occupied) M.stop(from, g.mark) else g.mark;
            const i = heroSlot(g).?;
            heroTo(g, stop);
            const s = Stroke{ .from = stop, .wait = glideHeld(g, i, g.glide[i].toward(stop, 0)) };
            if (occupied) knock(g, a, d, s);
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

const KitBuf = [skillbar.ACTS.len]skillbar.Act;

fn bindStep(g: *Game) void {
    const b = &g.binds;
    const here = b.slot();
    var kit_buf: KitBuf = undefined;
    const kit = g.growth.kit(g.class, &kit_buf);
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

/// Over the hero's own cell, so the reticle reaches the far side of a corridor.
fn nudgeAim(g: *Game, d: mathx.Dir) void {
    const h = g.heroActor() orelse return;
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
    const h = g.heroActor() orelse return;
    const act = g.aim_act;
    if (!ready(g, act)) return;
    const reticle = act.reticle().?;
    if (!aimable(g, h.at, g.mark)) {
        switch (reticle) {
            .bow => g.log.say("Can't shoot there.", .{}),
            .leap => g.log.say("{s} needs a visible, empty landing within {d} tiles.", .{ act.name(), act.reach() }),
            .swing => g.log.say("Nothing to strike there.", .{}),
            .rush => g.log.say("{s} needs a clear straight line {d} to {d} tiles away.", .{ act.name(), act.nearest(), act.reach() }),
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
    g.shot = .{ .flight = f, .from = from, .act = act };
    holdUntil(g, g.shot.?.ends());
    const s = Stroke{ .from = from, .wait = g.shot.?.lands(), .fire = act.element() == .fire };
    if (act.element() == .lightning and f.len > 0) g.fx.zap(@max(0, s.wait - ZAP_S), .{ .from = mathx.centre(from), .to = mathx.centre(f.path[f.len - 1]) });
    g.lead = s.wait;
    if (f.struck) |hit| switch (act) {
        inline else => |a| if (comptime a.reticle() != .bow) unreachable else if (comptime a.bursts()) burstHit(g, a, hit, f.impact().?, s) else switch (hit) {
            .body => |id| if (comptime a.chains())
                chainHit(g, a, id, s)
            else if (comptime !a.afflicts()) blk: {
                comptime std.debug.assert(a.element() == null);
                break :blk wound(g, id, heroArrow(g, a, true).physical(), SHOOT, s);
            } else arrowHit(g, id, heroArrow(g, a, true), a, s),
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
        arrowHit(g, id, heroArrow(g, act, true), act, .{ .from = from, .wait = wait });
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
            sweep(g, a, s)
        else if (comptime a.knocks())
            knock(g, a, d, s)
        else
            @compileError(@tagName(a) ++ " swings at nothing"),
    }
    turnToward(g, g.hero, d.delta().x);
    g.lead = s.wait;
    endTurn(g);
}

/// Snapshot arc targets before damage so newborn slime halves are spared.
fn sweep(g: *Game, comptime act: skillbar.Act, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const arc = M.arc(&g.lv, s.from, g.mark);
    var struck: [M.WIDTH]u16 = undefined;
    for (arc.slice(), struck[0..arc.n]) |p, *w| w.* = g.lv.who(p);
    const raw = rawFor(g, act, true);
    for (arc.slice(), struck[0..arc.n]) |p, w| {
        if (w != grid.NO_ONE) wound(g, w, heroScaled(g, act, raw).physical(), M.VERB, s) else smash(g, p, M.VERB, s);
    }
}

fn knock(g: *Game, comptime act: skillbar.Act, d: mathx.Dir, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const to = s.from.add(d.delta());
    const id = g.lv.who(to);
    if (id == grid.NO_ONE) return smash(g, to, M.VERB, s);
    const a = g.pool.get(id).?;
    const r = heroSkill(g, act);
    const takes = if (comptime act.afflicts()) afflicted(g, a, M, r.dmg < a.hp, 0) else false;
    wound(g, id, r, M.VERB, s);
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

/// Roll status before nonlethal damage so split halves inherit it.
fn afflicted(g: *Game, a: *actor.Actor, comptime M: type, lands: bool, resist: i16) bool {
    const takes = lands and M.procs(&g.rng, resist);
    if (takes) M.afflict(a, &g.rng);
    return takes;
}

const SHOOT = bow.VERB;
const IT_DIES = " It dies.";

const Roll = struct { dmg: i32, crit: bool = false };
const Rolled = struct {
    blow: damage.Damage,
    crit: bool = false,

    fn physical(h: Rolled) Roll {
        return .{ .dmg = h.blow.physical, .crit = h.crit };
    }
};

/// The crit is drawn after the damage it scales.
fn scaled(rng: *mathx.Rng, by: attrs.Attrs, comptime style: attrs.Style, hit: damage.Damage) Rolled {
    const crit = by.crits(rng);
    return .{ .blow = by.blow(style, hit, crit, rng), .crit = crit };
}

fn heroRoll(g: *Game, comptime style: attrs.Style, raw: i32) Roll {
    return scaled(&g.rng, heroAttrs(g), style, .{ .physical = raw }).physical();
}

fn heroSkill(g: *Game, comptime act: skillbar.Act) Roll {
    return heroArrow(g, act, true).physical();
}

fn heroArrow(g: *Game, comptime act: skillbar.Act, body: bool) Rolled {
    return heroScaled(g, act, rawFor(g, act, body));
}

/// A raw `act` roll scaled by the hero's attributes and its rank, with its crit.
fn heroScaled(g: *Game, comptime act: skillbar.Act, raw: damage.Damage) Rolled {
    return scaled(&g.rng, skillAttrs(g, act), comptime act.style().?, raw);
}

/// A bow replaces an arrow's physical roll; any other weapon adds to its skill's.
const SkillBases = struct {
    skill: ?damage.Base,
    weapon: ?damage.Base = null,
    element: ?damage.Base,

    fn physical(b: SkillBases) damage.Base {
        var out = damage.Base{ .lo = 0, .hi = 0 };
        for ([_]?damage.Base{ b.skill, b.weapon }) |maybe| if (maybe) |p| {
            out.lo += p.lo;
            out.hi += p.hi;
        };
        return out;
    }
};

fn basesOf(gear: *const items.Gear, act: skillbar.Act) SkillBases {
    const bases = act.bases();
    var out = SkillBases{ .skill = bases.physical, .element = bases.element };
    const style = act.style() orelse return out;
    if (gear.weapon(style)) |weapon| {
        if (style == .ranged) out.skill = weapon else out.weapon = weapon;
    }
    return out;
}

fn basesFor(g: *const Game, act: skillbar.Act) SkillBases {
    return basesOf(&g.inventory.gear, act);
}

/// Physical before elemental, preserving the seeded shot sequence; without `body`, no physical.
fn rollRaw(rng: *mathx.Rng, comptime act: skillbar.Act, bases: SkillBases, body: bool) damage.Damage {
    var raw = damage.Damage{};
    if (body) for ([_]?damage.Base{ bases.skill, bases.weapon }) |maybe| {
        if (maybe) |b| raw.physical += b.roll(rng);
    };
    if (comptime act.element()) |element| raw.elements.set(element, bases.element.?.roll(rng));
    return raw;
}

fn rawFor(g: *Game, comptime act: skillbar.Act, body: bool) damage.Damage {
    return rollRaw(&g.rng, act, basesFor(g, act), body);
}

fn arrowHit(g: *Game, id: u16, hit: Rolled, comptime act: skillbar.Act, s: Stroke) void {
    const M = skillbar.Act.skill(act);
    const el = comptime act.element();
    const a = g.pool.get(id) orelse return;
    const dealt = hit.blow.total(a.resists);
    const at = a.at;
    const name = actor.row(a.kind).name;
    const lands = if (el) |e| hit.blow.afflicts(a.resists, e, a.hp) else dealt < a.hp;
    const takes = afflicted(g, a, M, lands, if (el) |e| a.resists.get(e) else 0);
    if (dealt > 0) wound(g, id, .{ .dmg = dealt, .crit = hit.crit }, M.VERB, s);
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
    g.fx.burst(s.wait, .{ .at = at, .area = area, .element = act.element().? });
    const raw = rawFor(g, act, direct != null);
    if (barrel) smash(g, at, barrelVerb(act), s);
    for (struck.slice()) |id| {
        var hit = raw;
        if (direct != id) hit.physical = 0;
        arrowHit(g, id, heroScaled(g, act, hit), act, s);
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

fn glideHeld(g: *Game, slot: usize, gl: Glide) f32 {
    g.glide[slot] = gl;
    holdUntil(g, gl.left());
    return gl.left();
}

fn smash(g: *Game, p: P, comptime verb: []const u8, s: Stroke) void {
    if (!g.lv.breakBarrel(p)) return;
    g.log.push(.loot, "{s} " ++ verb ++ " the barrel. It drops {d} gold.", .{ g.name.text(), loot(g, p, GOLD_LO, GOLD_HI) });
    strike(g, null, s, p, true, null);
}

fn openChest(g: *Game, p: P) bool {
    const opened = g.lv.at(p).opened() orelse return false;
    if (!groundRoom(g)) return false;
    g.lv.set(p, opened);
    const added = g.ground.add(.{ .item = items.roll(&g.loot_rng), .at = p });
    std.debug.assert(added);
    g.log.push(.loot, "{s} opens the chest: {d} gold and an item.", .{ g.name.text(), loot(g, p, CHEST_GOLD_LO, CHEST_GOLD_HI) });
    return true;
}

fn groundRoom(g: *Game) bool {
    if (g.ground.room(FOE_DROPS)) return true;
    g.character.message.say("Ground full", .{});
    g.log.say("Ground full: collect an item first.", .{});
    return false;
}

fn loot(g: *Game, at: P, lo: i32, hi: i32) i32 {
    const gold = g.rng.range(lo, hi);
    const added = g.ground.gold(at, gold);
    std.debug.assert(added);
    return gold;
}

fn collectGold(g: *Game, at: P) void {
    const amount = g.ground.collect(at);
    if (amount == 0) return;
    g.gold_taken = at;
    g.gold +|= amount;
    g.log.push(.loot, "{s} picks up {d} gold.", .{ g.name.text(), amount });
    g.unsaved = true;
}

fn noticeItems(g: *Game, at: P) void {
    for (g.ground.drops[0..g.ground.n]) |drop| {
        if (drop.at.eq(at)) g.log.push(.loot, "{s} steps over {s}.", .{ g.name.text(), drop.item.name() });
    }
}

fn wound(g: *Game, id: u16, r: Roll, comptime verb: []const u8, s: Stroke) void {
    const a = g.pool.get(id) orelse return;
    const kind = a.kind;
    const at = a.at;
    const i = actor.Pool.slot(id);
    const name = actor.row(kind).name;
    const h = hurt(g, id, r.dmg);
    const lethal = h.lethal;
    sayAs(g, .damage, at, "{s} " ++ verb ++ " the {s}{s} for {d}.{s}", .{ g.name.text(), name, if (r.crit) " critically" else "", r.dmg, if (lethal) IT_DIES else "" });
    strike(g, i, s, at, lethal, afterBlow(g, id, h));
    if (lethal) fell(g, id);
}

fn afterBlow(g: *Game, id: u16, h: Hurt) fx.After {
    const other = if (h.lethal) null else split(g, id);
    return .{ .body = snap(g, actor.Pool.slot(id)), .reveals = other, .mana = h.mana };
}

/// Split halves become visible only when the splitting blow lands.
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
    const levels = g.growth.gain(progress.xpOf(kind));
    const points = levels * progress.POINTS_PER_LEVEL;
    if (levels > 0) g.log.push(.progress, "Level {d}: +{d} passive, +{d} active points.", .{ g.growth.level, points, points });
    if (g.loot_rng.percent(items.DROP_PERCENT)) {
        const added = g.ground.add(.{ .item = items.roll(&g.loot_rng), .at = at, .source = id });
        std.debug.assert(added);
    }
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
    sayAs(g, .status, at, fmt, args);
}

/// Logged only if `at` is in sight.
fn sayAs(g: *Game, kind: journal.Kind, at: P, comptime fmt: []const u8, args: anytype) void {
    if (g.lv.isLit(at)) g.log.push(kind, fmt, args);
}

fn heroDies(g: *Game) void {
    g.log.push(.danger, "{s} dies.", .{g.name.text()});
    g.mode = .dead;
}

/// Brogue turn order; recast sight after carried enemy lights move.
fn endTurn(g: *Game) void {
    const h = g.heroActor() orelse return;
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
    if (g.heroActor()) |a| {
        if (a.ward.turns > 0) {
            a.ward.wear();
            const hero = heroSlot(g).?;
            g.owed[hero].worn = .{ .body = snap(g, hero) };
        }
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

/// Mark a tick consumed; split halves inherit the parent's consumed ticks.
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
        g.log.push(.danger, said.hero, .{ g.name.text(), h.dmg });
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
    const h = g.heroActor() orelse return;
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

/// The strike's damage, or null when the hero dodges it; the dodge is drawn first.
fn bite(rng: *mathx.Rng, by: attrs.Attrs, s: actor.Strike) ?i32 {
    if (by.dodges(rng)) return null;
    return s.roll(rng);
}

fn reach(g: *Game, id: u16, row: actor.Row) void {
    const i = actor.Pool.slot(id);
    switch (row.blow) {
        .strike => |s| {
            const dmg = bite(&g.rng, heroAttrs(g), s) orelse {
                g.log.say("{s} dodges the {s}.", .{ g.name.text(), row.name });
                g.owed[i].bit = .miss;
                return;
            };
            const h = hurt(g, g.hero, heroAttrs(g).physical(dmg, &g.rng));
            const lethal = h.lethal;
            g.log.push(.danger, "The {s} {s} {s} for {d}.", .{ row.name, s.verb, g.name.text(), h.dmg });
            if (!lethal and h.dmg > 0 and bleeding.procs(&g.rng, s.bleeds)) {
                const b = &g.heroActor().?.bleed;
                g.log.say("{s} {s}!", .{ g.name.text(), if (b.turns == 0) bleeding.TAKES else "bleeds anew" });
                b.start();
            }
            const after = afterBlow(g, g.hero, h);
            g.owed[i].bit = if (lethal) .{ .kill = after } else .{ .hurt = after };
            if (lethal) heroDies(g);
        },
        .burst => {
            const a = g.pool.get(id).?.*;
            _ = g.pool.damage(&g.lv, id, a.hp);
            g.owed[i].bit = .{ .burst = .{ .body = snap(g, i) } };
            fell(g, id);
        },
    }
}

fn camAxis(centre: f32, view: f32, map: f32) f32 {
    if (view >= map) return (map - view) * 0.5;
    return std.math.clamp(centre - view * 0.5, 0, map - view);
}

/// Dead bodies remain until their killing blow, flash and glide finish.
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
    const hero = heroSlot(g).?;
    const warded = g.owed[hero].worn;
    g.owed[hero].worn = null;
    const archer_done = stagger(g, g.hero, late, g.lead orelse 0, &next);
    g.lead = null;
    var part: [actor.MAX]f32 = @splat(archer_done);
    for (g.order[0..g.order_n]) |id| part[actor.Pool.slot(id)] = stagger(g, id, late, archer_done, &next);
    for (g.owed[0..g.pool.n], 0..) |*o, i| {
        if (!o.any()) continue;
        const start = if (g.split_from[i]) |p| @max(archer_done, part[p]) else archer_done;
        part[i] = stagger(g, actor.Pool.idOf(i), late, start, &next);
    }
    if (warded) |c| g.fx.settle(std.mem.max(f32, part[0..g.pool.n]), .{ .slot = hero, .after = c });
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

/// Completion time; unplaced bodies wait for the hero and knockback slide.
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
    if (bit) |b| switch (b) {
        .hurt, .kill => |after| strike(g, hero, .{ .from = a.at, .wait = hits }, hero_at, b == .kill, after),
        .burst => |after| strike(g, i, .{ .from = hero_at, .wait = hits }, a.at, true, after),
        .miss => {},
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
        strike(g, s.slot, .{ .from = at, .wait = lands, .fire = fire }, at, true, h.after);
    } else if (in_view) {
        var shown = s;
        shown.after = h.after;
        sting(g, lands, shown);
    } else g.fx.settle(lands, .{ .slot = s.slot, .after = h.after });
}

const Walk = struct { d: mathx.Dir, late: f32 };
const Queued = union(enum) { walk: mathx.Dir, skill: Use, interact };

pub fn quiet(g: *const Game) bool {
    return g.busy <= PACE_SLACK;
}

/// A held walk repeating does not displace a queued action.
fn queueWalk(g: *Game, d: mathx.Dir) void {
    if (g.pending) |q| {
        if (q != .walk) return;
    }
    g.pending = .{ .walk = d };
}

/// With anything near, the press is Interact's, not its button's skill, and waits for quiet like one.
fn queueInteract(g: *Game) bool {
    if (!g.st.interact or !anyNearby(g)) return false;
    g.pending = .interact;
    return true;
}

fn interacted(g: *Game) bool {
    if (queueInteract(g) and !quiet(g)) return true;
    const q = g.pending orelse return false;
    if (q != .interact or !quiet(g)) return false;
    g.pending = null;
    return openNearby(g);
}

fn skillDue(g: *Game) ?Use {
    if (usedSkill(g)) |u| g.pending = .{ .skill = u };
    const q = g.pending orelse return null;
    if (q != .skill or !quiet(g)) return null;
    g.pending = null;
    return q.skill;
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
    const q = g.pending orelse return null;
    if (q != .walk or !quiet(g)) return null;
    g.pending = null;
    return .{ .d = q.walk, .late = sinceQuiet(g) };
}

/// Seconds since the last turn was drawn out.
fn sinceQuiet(g: *const Game) f32 {
    return @max(0, -g.busy);
}

/// Advance presentation before new actions so their effects start at the correct delay.
pub fn update(g: *Game, dt: f32) void {
    if (!g.st.focused) holdWalk(g);
    if (g.mode == .play or g.mode == .aim or g.mode == .inspect) {
        if (g.st.pointer) |p| {
            if (look.holds(journal.box(g.screen), p) and g.st.scroll != 0) g.log.move(g.st.scroll);
        }
    }
    const death_drawn = deathShown(g);
    g.busy -= dt;
    if (quiet(g)) {
        g.log.release();
        g.gold_taken = null;
        drawnTurn(g);
    }
    for (g.glide[0..g.pool.n]) |*gl| gl.t += dt;
    g.fx.step(&g.lv, dt);
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
    stepTurning(g, dt);
    var late: f32 = 0;
    const was = g.mode;
    const was_page = g.pause_page;
    const was_binds = std.meta.activeTag(g.binds.menu);
    if (g.mode == .play and g.st.hit(PAUSE)) {
        openPause(g);
    } else switch (g.mode) {
        .play => {
            if (g.travel) |l| {
                if (queueInteract(g)) {} else if (usedSkill(g)) |u| {
                    g.pending = .{ .skill = u };
                } else if (g.st.walk) |d| queueWalk(g, d);
                if (quiet(g)) goThrough(g, l);
            } else if (interacted(g)) {} else if (g.st.long(BINDS)) {
                g.st.spend(BINDS);
                g.pending = null;
                openBinds(g);
            } else if (g.st.hit(skillbar.INSPECT)) {
                g.pending = null;
                g.mode = .inspect;
            } else if (skillDue(g)) |u| {
                useSkill(g, u);
            } else if (paced(g)) |w| {
                late = w.late;
                heroStep(g, w.d, w.late);
            }
        },
        .aim => {
            if (closed(&g.st)) {
                g.mode = .play;
            } else if (g.st.hit(CONFIRM)) {
                confirmAim(g);
            } else if (g.st.walk) |d| {
                nudgeAim(g, d);
            }
        },
        .bind => bindStep(g),
        .inspect => inspectStep(g),
        .dead => if (death_drawn and dismissed(&g.st)) {
            if (g.permadeath) g.exit = .back else restart(g);
        },
        .pause => pauseStep(g),
    }
    if (g.mode != .play) g.st.spend(BINDS);
    if (was != g.mode or was_page != g.pause_page or was_binds != std.meta.activeTag(g.binds.menu)) holdWalk(g);
    stepGlide(g, late);
    catchUp(g);
    splashSteps(g);
    stepVignette(g, dt);
    const want = camWant(g);
    const k = mathx.easing(dt, CAM_EASE);
    g.cam = g.cam.lerp(want, k);
    g.hour_shown = day.wrapHour(g.hour_shown + day.toward(g.hour_shown, g.clock.hour()) * mathx.easing(dt, HOUR_EASE));
    g.xp_shown = mathx.ease(g.xp_shown, g.xp_aim, mathx.easing(dt, XP_EASE), 1);
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
    const w = g.map orelse return .{};
    return w.node[g.node].sky();
}

/// Per second, how fast the sky drawn catches the hour a turn moved on.
const HOUR_EASE: f32 = 4;
/// Per second, how fast the experience bar fills toward a drawn turn's experience.
const XP_EASE: f32 = 2;

/// Levels gained so far, the current one's progress as the fraction.
fn xpLevels(g: *const Game) f32 {
    const xp: f32 = @floatFromInt(g.growth.xp);
    const needed: f32 = @floatFromInt(g.growth.needed());
    return @as(f32, @floatFromInt(g.growth.level - 1)) + xp / needed;
}

fn drawnTurn(g: *Game) void {
    g.growth_shown = g.growth;
    g.gold_shown = g.gold;
    g.xp_aim = xpLevels(g);
}

fn settleXp(g: *Game) void {
    drawnTurn(g);
    g.xp_shown = g.xp_aim;
}

pub fn holdWalk(g: *Game) void {
    g.st.holdWalk();
    g.pending = null;
}

fn openPause(g: *Game) void {
    g.paused_from = g.mode;
    g.pause_menu = .{};
    g.pause_page = .main;
    g.mode = .pause;
    g.pending = null;
}

fn drawGold(g: *const Game, c: Cam, at: P) void {
    g.face.centred("$", c.sx(at) + HALF_CELL + GOLD_DX, c.sy(at) + HALF_CELL + LOOT_DY, LOOT_PX, look.RETICLE);
}

fn dropShown(g: *const Game, drop: items.Drop) bool {
    if (!g.lv.isLit(drop.at)) return false;
    if (drop.source == grid.NO_ONE) return true;
    const i = actor.Pool.slot(drop.source);
    return g.pictured[i].down();
}

fn withinReach(from: P, p: P) bool {
    return mathx.dist(from, p) <= INTERACT_REACH;
}

fn nearbyOf(g: *Game, out: *NearbyBuf) []const book.Nearby {
    const h = g.heroActor() orelse return out[0..0];
    var n: usize = 0;
    for (g.ground.drops[0..g.ground.n], 0..) |drop, i| {
        if (!withinReach(h.at, drop.at) or !dropShown(g, drop)) continue;
        out[n] = .{ .kind = .loot, .index = i, .at = drop.at, .item = drop.item };
        n += 1;
    }
    var cells = grid.Cells.around(h.at, INTERACT_REACH);
    while (cells.next()) |p| {
        if (!g.lv.isLit(p)) continue;
        const chest = g.lv.at(p).opened() != null;
        if (!chest and leadsTo(g, p) == null) continue;
        out[n] = .{ .kind = if (chest) .chest else .door, .at = p };
        n += 1;
    }
    return out[0..n];
}

fn anyNearby(g: *Game) bool {
    var nearby: NearbyBuf = undefined;
    return nearbyOf(g, &nearby).len > 0;
}

fn bookView(g: *Game, nearby: *NearbyBuf) book.View {
    const now = quiet(g);
    const growth = if (now) &g.growth else &g.growth_shown;
    return .{ .class = g.class, .name = g.name.text(), .inventory = &g.inventory, .growth = growth, .base = growth.attributes(g.class), .gold = if (now) g.gold else g.gold_shown, .nearby = nearbyOf(g, nearby) };
}

fn openNearby(g: *Game) bool {
    if (!anyNearby(g)) return false;
    g.character.open();
    g.character.choose(.nearby);
    g.character.direct = true;
    g.paused_from = .play;
    g.pause_page = .character;
    g.mode = .pause;
    holdWalk(g);
    return true;
}

fn itemFailed(g: *Game, err: items.Failure) void {
    g.character.message.say("{s}", .{items.caption(err)});
}

fn notYet(g: *Game) void {
    g.character.message.say("Not until the turn ends", .{});
}

fn characterCommand(g: *Game, command: book.Command) void {
    if (command == .close) {
        if (g.character.direct) g.mode = .play else pauseBackTo(g, .character);
        return;
    }
    if (!quiet(g)) return notYet(g);
    switch (command) {
        .passive => |i| {
            if (!g.growth.allocate(i)) return;
            g.log.push(.progress, "{s} +{d}.", .{ menu.named(progress.NODES[i].bonus), progress.NODES[i].amount });
            syncStats(g);
            g.unsaved = true;
            return;
        },
        .skill => |act| {
            const unlocked = g.growth.unlocked(act);
            if (!g.growth.learn(g.class, act)) return;
            g.log.push(.progress, "{s}: rank {d}.", .{ act.name(), g.growth.ranks.get(act) });
            if (!unlocked) if (g.bar.firstEmpty()) |slot| g.bar.bind(slot, act);
            g.unsaved = true;
            return;
        },
        else => {},
    }
    if (g.travel != null) return notYet(g);
    const h = g.heroActor() orelse return;
    const base = g.growth.attributes(g.class);
    switch (command) {
        .close, .passive, .skill => unreachable,
        .equip => |e| {
            g.inventory.equip(e.index, e.slot, base) catch |err| {
                itemFailed(g, err);
                return;
            };
            g.log.push(.loot, "Equipped {s}: {s}.", .{ g.inventory.gear.slots.get(e.slot).?.name(), e.slot.name() });
        },
        .unequip => |s| {
            g.inventory.unequip(s, base) catch |err| {
                itemFailed(g, err);
                return;
            };
            g.log.push(.loot, "Unequipped {s}.", .{s.name()});
        },
        .drop => |i| {
            if (i >= g.inventory.n) return;
            if (!groundRoom(g)) return;
            const added = g.ground.add(.{ .item = g.inventory.bag[i], .at = h.at });
            std.debug.assert(added);
            g.log.push(.loot, "Dropped {s}.", .{g.inventory.remove(i).name()});
        },
        .pickup => |i| {
            if (i >= g.ground.n or !withinReach(h.at, g.ground.drops[i].at) or !dropShown(g, g.ground.drops[i])) return;
            if (!g.ground.take(i, &g.inventory)) {
                itemFailed(g, error.Full);
                return;
            }
            g.log.push(.loot, "Picked up {s}.", .{g.inventory.bag[g.inventory.n - 1].name()});
        },
        .open_chest => |p| {
            if (!withinReach(h.at, p) or !g.lv.isLit(p) or g.lv.at(p).opened() == null) return;
            if (!openChest(g, p)) return;
        },
        .travel => |p| {
            if (!withinReach(h.at, p) or !g.lv.isLit(p) or (!g.lv.vacant(p) and !p.eq(h.at))) return;
            if (leadsTo(g, p) == null) return;
            if (p.eq(h.at)) g.travel = leadsTo(g, p) else heroTo(g, p);
        },
    }
    syncStats(g);
    g.mode = .play;
    holdWalk(g);
    endTurn(g);
}

fn pauseStep(g: *Game) void {
    if (g.pause_page == .character) {
        var nearby: NearbyBuf = undefined;
        if (g.character.step(&g.st, g.screen, bookView(g, &nearby))) |command| characterCommand(g, command);
        return;
    }
    if (menu.backed(&g.st)) {
        if (g.pause_page == .debug) pauseBackTo(g, .debug) else g.mode = g.paused_from;
        return;
    }
    if (g.pause_page == .debug) {
        const i = g.pause_menu.step(&g.st, DEBUG_ROWS.len) orelse return;
        switch (DEBUG_ROWS[i]) {
            .restart_map => restart(g),
            .reveal_map => toggleReveal(g),
        }
        return;
    }
    const i = g.pause_menu.step(&g.st, PAUSE_ROWS.len) orelse return;
    switch (PAUSE_ROWS[i]) {
        .resume_ => g.mode = g.paused_from,
        .character => {
            g.character.open();
            g.pause_page = .character;
        },
        .debug => {
            g.pause_page = .debug;
            g.pause_menu = .{};
        },
        .back => {
            g.mode = g.paused_from;
            g.exit = .back;
        },
        .quit => {
            g.mode = g.paused_from;
            g.exit = .quit;
        },
    }
}

fn pauseBackTo(g: *Game, row: PauseRow) void {
    g.pause_page = .main;
    g.pause_menu.at = @intFromEnum(row);
}

fn toggleReveal(g: *Game) void {
    g.light.reveal(&g.lv, !g.light.reveal_map);
    g.mini.stale = true;
}

fn terrainSeen(g: *const Game, p: P) bool {
    return g.light.remembers(&g.lv, p);
}

fn pauseLabel(g: *const Game, r: PauseRow) [:0]const u8 {
    return switch (r) {
        .resume_ => "Resume",
        .debug, .character, .quit => menu.named(r),
        .back => switch (g.back) {
            .title => "Title",
            .editor => "Back to the editor",
        },
    };
}

pub fn veil(g: *const Game) void {
    rl.drawRectangle(0, 0, g.screen.x, g.screen.y, look.VEIL);
}

fn drawPause(g: *Game) void {
    veil(g);
    if (g.pause_page == .character) {
        var nearby: NearbyBuf = undefined;
        g.character.draw(&g.face, &g.sprites, g.screen, bookView(g, &nearby));
        return;
    }
    if (g.pause_page == .debug) {
        var rows: [DEBUG_ROWS.len][]const u8 = undefined;
        for (DEBUG_ROWS, &rows) |r, *l| l.* = switch (r) {
            .restart_map => comptime menu.titled(@tagName(DebugRow.restart_map)),
            .reveal_map => menu.toggle(comptime menu.titled(@tagName(DebugRow.reveal_map)), g.light.reveal_map),
        };
        menu.draw(g.face, g.screen, comptime menu.caps(menu.named(PauseRow.debug)), &rows, g.pause_menu.at, null);
        return;
    }
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

/// Reveal split halves at impact, after their parent becomes visible.
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

/// Read the slot even after death so the lethal hit still reddens the view.
fn stepVignette(g: *Game, dt: f32) void {
    const max = heroAttrs(g).life();
    const i = heroSlot(g) orelse return g.vignette.step(dt, 0, max, max);
    g.vignette.step(dt, g.fx.flashOf(i), g.pictured[i].hp, g.pictured[i].max);
}

/// The hero's middle as drawn, cells: the carried light glides with the body.
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

    fn corner(c: Cam, p: P) P {
        return .{ .x = c.sx(p), .y = c.sy(p) };
    }

    fn mid(c: Cam, p: P) P {
        return c.corner(p).add(.{ .x = HALF_CELL, .y = HALF_CELL });
    }

    fn box(c: Cam, p: P) rl.Rectangle {
        return look.rect(c.sx(p), c.sy(p), CELL, CELL);
    }

    /// The map's top-left on screen.
    fn origin(c: Cam) [2]f32 {
        return .{ @floatFromInt(-c.x), @floatFromInt(-c.y) };
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
    rl.drawRectangleLinesEx(look.grown(c.box(p), @floatFromInt(-OUTLINE_INSET)), @floatFromInt(LINE_W), col);
}

fn fillCell(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangleRec(c.box(p), col);
}

/// Barrels stay remembered until the hero's visible breaking blow lands.
fn barrelShownAt(g: *Game, p: P) bool {
    return terrainSeen(g, p) and barrelPresent(g, p);
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
    rl.drawRectangle(x, y, mathx.filled(v, max, w), h, fill);
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
        return .{ .s = c.corner(p), .mid = mid, .shine = if (casting) g.light.onCaster(mid, false) else g.light.onBody(mid, false) };
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
        g.light.drawBody(t, spriteRect(t, s.x, s.y), left, mid, shine, flash, .{ 0, 0 });
    } else drawGlyph(g, l.ch, s.x, s.y, shine.drawn(l.fg, flash));
}

const Stood = std.StaticBitSet(grid.CELLS);

fn drawGroundPass(g: *Game, c: Cam, beds: *const dual.Beds, stood: *const Stood, mirror: ?look.Mirrors) void {
    const x = std.math.clamp(-c.x, 0, g.screen.x);
    const y = std.math.clamp(-c.y, 0, g.screen.y);
    const right = std.math.clamp(grid.W * CELL - c.x, 0, g.screen.x);
    const bottom = std.math.clamp(grid.H * CELL - c.y, 0, g.screen.y);
    rl.beginScissorMode(x, y, right - x, bottom - y);
    defer rl.endScissorMode();
    const water: ?look.WaterView = if (g.light.glintTexture()) |glints| if (g.light.mapTexture()) |tex| .{
        .screen = .{ @floatFromInt(g.screen.x), @floatFromInt(g.screen.y) },
        .visibility = tex,
        .glints = glints,
        .mirror = mirror,
    } else null else null;
    g.sprites.drawGround(beds, c.origin(), CELL_F, water);
    var cells = grid.Cells.of(beds.lo, beds.hi);
    while (cells.next()) |p| {
        if (!terrainSeen(g, p)) continue;
        const here = g.lv.at(p);
        if (look.glyphGround(here, &g.sprites)) inkCell(g, c, p, here, stood);
        if (g.lv.doorAt(p) != null) drawGlyph(g, look.DOOR.ch, c.sx(p), c.sy(p), look.DOOR.fg);
    }
}

/// At full light, what stands on the seen cells from `lo` up to `hi`, over the shadows cast on the ground.
fn drawSolidPass(g: *Game, c: Cam, lo: P, hi: P, stood: *const Stood) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        if (!terrainSeen(g, p)) continue;
        const here = g.lv.at(p);
        if (!look.standsOver(here)) continue;
        if (g.sprites.tileAt(&g.lv, p)) |t| {
            drawSprite(t, c.sx(p), c.sy(p));
            continue;
        }
        if (look.tileBg(here)) |bg| fillCell(c, p, bg);
        inkCell(g, c, p, here, stood);
    }
}

fn inkCell(g: *Game, c: Cam, p: P, here: grid.Tile, stood: *const Stood) void {
    if (shownAt(g, stood, p)) return;
    const m = c.mid(p);
    look.inkTile(&g.face, here, m.x, m.y, GLYPH);
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

fn mirrorAt(foot: f32) void {
    rl.gl.rlPushMatrix();
    rl.gl.rlTranslatef(0, 2 * foot, 0);
    rl.gl.rlScalef(1, -1, 1);
}

/// Where a glyph figure, with no art to measure, stands within its cell.
const GLYPH_FOOT: f32 = 0.8;

fn footOf(g: *const Game, tex: ?rl.Texture2D, s: P) f32 {
    const t = tex orelse return @as(f32, @floatFromInt(s.y)) + CELL_F * GLYPH_FOOT;
    return g.light.footY(t, spriteRect(t, s.x, s.y));
}

fn drawMirrored(g: *Game, tex: ?rl.Texture2D, l: look.Look, stands: P, s: P, left: bool, mid: [2]f32, shine: *const light.Shine, flash: f32) void {
    const foot = footOf(g, tex, stands);
    const top = if (tex) |t| g.light.topY(t, spriteRect(t, s.x, s.y)) else @as(f32, @floatFromInt(s.y + HALF_CELL - @divTrunc(GLYPH, 2)));
    const bounds = mirrorFade(g, foot, top, footOf(g, tex, s));
    mirrorAt(foot);
    defer rl.gl.rlPopMatrix();
    if (tex) |t| {
        g.light.drawBody(t, spriteRect(t, s.x, s.y), left, mid, shine, flash, bounds);
    } else {
        const fading = g.light.beginMirrorFade(bounds);
        defer if (fading) rl.endShaderMode();
        drawGlyph(g, l.ch, s.x, s.y, shine.drawn(l.fg, flash));
    }
}

fn mirrorFade(g: *const Game, foot: f32, top: f32, bottom: f32) [2]f32 {
    const screen: f32 = @floatFromInt(g.screen.y);
    return .{ screen - 2 * foot + top, screen - 2 * foot + mathx.lerpF(top, bottom, 0.7) };
}

fn drawBody(g: *Game, b: *const Shown, mirrored: bool) void {
    const tex = g.sprites.body(b.pic.kind);
    const l = look.body(b.pic.kind);
    const flash = g.fx.flashOf(b.slot);
    if (mirrored) drawMirrored(g, tex, l, b.s, b.lifted, b.left, b.mid, &b.shine, flash) else drawFigure(g, tex, l, b.lifted, b.left, b.mid, &b.shine, flash);
}

fn drawBarrel(g: *Game, b: *const Prop, mirrored: bool) void {
    if (mirrored) drawMirrored(g, g.sprites.barrel, look.BARREL, b.s, b.s, false, b.mid, &b.shine, 0) else drawFigure(g, g.sprites.barrel, look.BARREL, b.s, false, b.mid, &b.shine, 0);
}

fn drawMirrorScenery(g: *Game, c: Cam, view: grid.Box, memory: bool) void {
    var cells = view.grown(CAST_MARGIN).cells();
    while (cells.next()) |p| {
        if (!terrainSeen(g, p)) continue;
        const kind = g.lv.at(p);
        if (look.standsOver(kind)) {
            if (g.sprites.tileAt(&g.lv, p)) |t| {
                const rect = spriteRect(t, c.sx(p), c.sy(p));
                const foot = footOf(g, t, c.corner(p));
                mirrorAt(foot);
                const fading = g.light.beginMirrorFade(mirrorFade(g, foot, g.light.topY(t, rect), foot));
                defer if (fading) rl.endShaderMode();
                const tint = if (memory) rl.Color.white else g.light.onBody(mathx.centre(p), false).tint(rl.Color.white);
                look.stretch(t, rect, tint);
                rl.gl.rlPopMatrix();
            }
        }
        if (barrelPresent(g, p)) {
            var b = Prop.at(g, c, p, false);
            if (memory) b.shine = .{ .ambient = @splat(1) };
            drawBarrel(g, &b, true);
        }
    }
}

fn drawMirrorTorches(g: *Game, c: Cam, flames: []const light.Flame, memory: bool) void {
    for (flames) |f| {
        const foot = f.foot * CELL_F - @as(f32, @floatFromInt(c.y));
        const top = f.at[1] * CELL_F - @as(f32, @floatFromInt(c.y + authored(20)));
        mirrorAt(foot);
        const fading = g.light.beginMirrorFade(mirrorFade(g, foot, top, foot));
        defer if (fading) rl.endShaderMode();
        drawFlame(g, c, f, if (memory or !g.lv.isLit(mathx.cellOf(f.at))) 0 else flameLit(f));
        rl.gl.rlPopMatrix();
    }
}

fn flameLit(f: light.Flame) f32 {
    return f.lit * @min(1, f.glow);
}

fn drawFlame(g: *Game, c: Cam, f: light.Flame, lit: f32) void {
    const x = mathx.roundTiesUp(f.at[0] * CELL_F) - c.x;
    const y = mathx.roundTiesUp(f.at[1] * CELL_F) - c.y;
    g.fx.drawTorch(@floatFromInt(x), @floatFromInt(y), CELL_F, f.at[0] * 0.73 + f.at[1] * 0.37, lit, f.memory);
}

fn drawMirrors(g: *Game, c: Cam, view: grid.Box, bodies: []const Shown, flames: []const light.Flame) ?look.Mirrors {
    if (!g.sprites.beginMirror(g.screen, g.framebuffer, true)) return null;
    drawMirrorScenery(g, c, view, true);
    drawMirrorTorches(g, c, flames, true);
    if (!g.sprites.beginMirror(g.screen, g.framebuffer, false)) {
        rl.gl.rlEnableBackfaceCulling();
        return null;
    }
    drawMirrorScenery(g, c, view, false);
    for (bodies) |*b| drawBody(g, b, true);
    drawMirrorTorches(g, c, flames, false);
    return g.sprites.endMirror(g.framebuffer);
}

fn drawMap(g: *Game) void {
    effectLights(g);
    const c = Cam.of(g);
    const view = viewBox(g, c);
    const lo = view.lo;
    const hi = view.hi;
    const aim_from: ?P = if (g.mode != .aim) null else if (g.heroActor()) |a| a.at else null;

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
    var flame_buf: [grid.MAX_TORCHES]light.Flame = undefined;
    const flames = g.light.flames(&g.lv, &flame_buf);
    var beds: dual.Beds = undefined;
    beds.fill(&g.lv, lo, hi, !g.light.reveal_map);
    const mirror = if (beds.shown.intersectWith(look.REFLECTIVE).count() > 0) drawMirrors(g, c, view, bodies, flames) else null;
    drawGroundPass(g, c, &beds, &stood, mirror);
    for (g.ground.coins[0..g.ground.coin_n]) |pile| {
        if (!g.lv.isLit(pile.at) or barrelPresent(g, pile.at)) continue;
        drawGold(g, c, pile.at);
    }
    if (g.gold_taken) |p| {
        const hero = heroSlot(g).?;
        if (g.glide[hero].left() > 0 and g.lv.isLit(p)) drawGold(g, c, p);
    }
    for (g.ground.drops[0..g.ground.n]) |drop| {
        if (!dropShown(g, drop)) continue;
        g.face.centred("*", c.sx(drop.at) + HALF_CELL + DROP_DX, c.sy(drop.at) + HALF_CELL + LOOT_DY, LOOT_PX, if (drop.item.magical()) look.WARD else look.TEXT);
    }
    _ = shadowPass(g, c, view, g.framebuffer);
    g.cloud.draw(&g.lv, view, -c.x, -c.y, CELL);
    drawSolidPass(g, c, lo, hi, &stood);
    const o = c.origin();
    g.fx.draw(o[0], o[1], CELL_F);
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
                    for (area.slice()) |p| {
                        if (terrainSeen(g, p)) fillCell(c, p, look.aimArea(a));
                    }
                },
            }
        }
        switch (g.aim_act) {
            inline else => |a| if (comptime a.sweeps()) {
                const arc = skillbar.Act.skill(a).arc(&g.lv, from, g.mark);
                for (arc.slice()) |p| fillCell(c, p, look.AIM_PATH);
            },
        }
    }

    var barrels = Barrels.of(g, c, lo, hi);
    while (barrels.next()) |b| drawBarrel(g, &b, false);
    for (bodies) |*b| {
        const at = b.lifted;
        drawBody(g, b, false);
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

    drawTorches(g, c, flames);
    g.fx.drawGlow(&g.lv, &g.light.sight, o[0], o[1], CELL_F);
    if (g.light.sky) |k| g.rain.draw(weatherNow(g), &g.light.sight, o[0], o[1], CELL_F, PX_SCALE, sky.brightness(k));

    for (bodies) |*b| {
        if (!b.pic.kind.foe() or !b.pic.hurt()) continue;
        const y_bar = b.s.y + CELL - BODY_BAR_H - BODY_BAR_LIFT;
        bar(b.s.x + BODY_BAR_INSET, y_bar, CELL - BODY_BAR_INSET * 2, BODY_BAR_H, b.pic.hp, b.pic.max, look.BG, look.LIFE);
    }

    if (aim_from) |from| outline(c, g.mark, if (aimable(g, from, g.mark)) look.RETICLE else look.RETICLE_BLOCKED);
    if (g.mode == .play and g.st.lean) drawLean(g, c, &stood);

    if (g.shot) |s| {
        const at = s.position(s.t);
        if (g.lv.isLit(mathx.cellOf(at))) fx.drawMissile(at, s.direction(), s.act, s.t, o[0], o[1], CELL_F);
    }
    for (bodies) |*b| {
        g.fx.drawSpeech(&g.face, b.slot, b.lifted.x, b.lifted.y, CELL_F, b.shine.sight);
    }
}

fn effectLights(g: *Game) void {
    g.fx.illuminate(&g.lv, g.light);
    if (g.shot) |s| {
        if (fx.missileLight(s.position(s.t), s.act)) |source| g.light.emit(&g.lv, source);
    }
    for (0..g.pool.n) |i| {
        const at = drawnAt(g, i) orelse continue;
        const pic = g.pictured[i];
        if (pic.down()) continue;
        const s = for (std.enums.values(fx.Status)) |s| {
            if (STATUS_GLOWS.get(s) != null and pic.status.get(s) > 0) break s;
        } else continue;
        const glow = STATUS_GLOWS.get(s).?;
        const mid = middle(at);
        const flicker = 1 - STATUS_FLICKER + STATUS_FLICKER * @sin(g.fx.seconds.at() * STATUS_FLICKER_HZ + @as(f32, @floatFromInt(i)));
        g.light.emit(&g.lv, .{ .at = .{ mid[0], mid[1], light.BODY_Z }, .col = s.ink(), .radius = glow.radius, .gain = glow.gain * flicker });
    }
}

const StatusGlow = struct { radius: f32, gain: f32 };
/// The first status a body has, in `fx.Status` order, lights it.
const STATUS_GLOWS = std.EnumArray(fx.Status, ?StatusGlow).init(.{
    .bleeding = null,
    .burning = .{ .radius = 2, .gain = 0.55 },
    .chilled = null,
    .pinned = null,
    .warded = .{ .radius = 1.5, .gain = 0.25 },
});
const STATUS_FLICKER: f32 = 0.1;
const STATUS_FLICKER_HZ: f32 = 11;

/// Over the light map, so each flame is its own light; a remembered one stays drawn, dim and unlit.
fn drawTorches(g: *Game, c: Cam, flames: []const light.Flame) void {
    for (flames) |f| drawFlame(g, c, f, flameLit(f));
    const o = c.origin();
    g.light.drawGlows(flames, o[0], o[1], CELL_F);
}

/// Movement hints follow presented occupants, including deaths still being drawn.
fn leanShown(g: *Game, stood: *const Stood, from: P, d: mathx.Dir) Move {
    if (opensChest(g, from, d)) return .open;
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
            .step, .open => look.LEAN_OPEN,
            .blocked => look.LEAN_BLOCKED,
        };
        outline(c, p, col);
        if (g.lv.walkable(p) and !shownAt(g, stood, p)) {
            const m = c.mid(p);
            look.drawDirection(button, m.x, m.y, LEAN_GLYPH, col);
            continue;
        }
        const inset = LEAN_PAD + @divTrunc(LEAN_MARK, 2);
        const dx: i32 = if (d.delta().x > 0) CELL - inset else inset;
        const dy: i32 = if (d.delta().y > 0) CELL - inset else inset;
        look.drawDirection(button, c.sx(p) + dx, c.sy(p) + dy, LEAN_MARK, col);
    }
}

/// One texel per cell, enlarged by `MINI`; requires a live GL context.
const Minimap = struct {
    tex: ?rl.Texture2D = null,
    px: [grid.CELLS]rl.Color = undefined,
    /// Set by `castSight` and `toggleReveal`, the only changes to what it shows.
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
    rl.drawRectangleRec(look.grown(look.rect(o.x + p.x * MINI, o.y + p.y * MINI, MINI, MINI), @floatFromInt(grow)), col);
}

fn drawMinimap(g: *Game) void {
    const o = miniOrigin(g.screen.x);
    const map = look.rect(o.x, o.y, MINI_W, MINI_H);
    look.hudPanelIn(&g.sprites, look.grown(map, @floatFromInt(MINI_FRAME)), look.MINI_BG, look.LIT);
    if (g.mini.tex) |t| {
        if (g.mini.stale) {
            for (&g.mini.px, &g.lv.tile, &g.lv.seen, &g.lv.lit) |*c, tile, seen, lit| c.* = if (seen or g.light.reveal_map) look.mini(tile, lit) else rl.Color.blank;
            rl.updateTexture(t, &g.mini.px);
            g.mini.stale = false;
        }
        look.stretch(t, map, look.LIT);
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
        rl.drawRectangleLinesEx(look.grown(look.rect(x, y, SLOT_PX, SLOT_PX), @floatFromInt(-SLOT_EDGE_INSET)), @floatFromInt(LINE_W), look.fade(edge, a));
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
    const mana = manaShown(g);
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
            .faded = if (s) |v| blocked(g, v.act, &g.flasks_shown, mana) != null else false,
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
            var kit_buf: KitBuf = undefined;
            const kit = g.growth.kit(g.class, &kit_buf);
            const picks = picksOf(kit);
            shown = pickAct(kit, pick);
            const win = pickWindow(y0 + BIND_TITLE, pop_y, picks, pick);
            const cols: i32 = @intCast(@min(picks, PICK_COLS));
            const w = cols * SLOT_STEP - SLOT_GAP;
            const px = std.math.clamp(cursor.x + @divTrunc(SLOT_PX - w, 2), x0, x0 + SKILLS_W - w);
            const py = pop_y - @as(i32, @intCast(win.len - 1)) * SLOT_STEP;
            const h = @as(i32, @intCast(win.len)) * SLOT_STEP - SLOT_GAP;
            rl.drawRectangleRec(look.grown(look.rect(px, py, w, h), @floatFromInt(SLOT_GAP)), look.PICK_BG);
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
        var desc: [menu.NOTE_MAX * 2 + 1]u8 = undefined;
        textMid(g, describe(g, a, &desc), info_y + TEXT_LINE, TEXT, look.DIM);
    } else if (b.menu == .pick) {
        textMid(g, "Clear slot", info_y, TEXT, look.TEXT);
    }
}

/// Its description, then its mana, turn and cooldown at the hero's rank.
fn describe(g: *const Game, act: skillbar.Act, buf: []u8) [:0]const u8 {
    var s = std.io.fixedBufferStream(buf[0 .. buf.len - 1]);
    const w = s.writer();
    w.writeAll(act.desc()) catch {};
    var sep: []const u8 = " ";
    const cost = g.growth.cost(act);
    if (cost > 0) {
        w.print("{s}{d} mana", .{ sep, cost }) catch {};
        sep = ", ";
    }
    if (act.free()) {
        w.print("{s}no turn cost", .{sep}) catch {};
        sep = ", ";
    }
    const cooldown = g.growth.cooldown(act);
    if (cooldown > 0) {
        w.print("{s}{d}-turn cooldown", .{ sep, cooldown }) catch {};
        sep = ", ";
    }
    if (sep.len > 1) w.writeAll(".") catch {};
    const n = s.getWritten().len;
    buf[n] = 0;
    return buf[0..n :0];
}

const Life = struct { hp: i32, max: i32 };

fn lifeShown(g: *const Game) Life {
    const h = heroShown(g) orelse return .{ .hp = 0, .max = heroAttrs(g).life() };
    return .{ .hp = h.hp, .max = h.max };
}

fn drawHud(g: *Game) void {
    const layout = hudLayout(g);
    hud.frame(layout, &g.sprites);
    const life = lifeShown(g);
    hud.resources(layout, &g.face, life.hp, life.max, manaShown(g), manaMax(g));
    drawSkills(g, layout);
    hud.experience(layout, g.xp_shown - @floor(g.xp_shown));
    if (heroShown(g)) |h| hud.statuses(layout, &g.sprites, &g.face, h.status);
}

const Part = struct { spot: Spot, box: rl.Rectangle };
const ORBS = 2;
const SPOTS_MAX = ORBS + skillbar.SLOTS.len + @typeInfo(hud.Shown).array.len + 1;

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
    std.debug.assert(n == ORBS + skillbar.SLOTS.len);
    if (heroShown(g)) |h| {
        var buf: hud.Shown = undefined;
        const shown = hud.shownStatuses(h.status, &buf);
        for (shown, 0..) |s, k| {
            out[n] = .{ .spot = .{ .status = s }, .box = hud.statusBox(layout, shown.len, k) };
            n += 1;
        }
    }
    out[n] = .{ .spot = .log, .box = journal.box(g.screen) };
    n += 1;
    return out[0..n];
}

fn spotAt(spots: []const Part, s: Spot) ?Part {
    for (spots) |x| {
        if (std.meta.eql(x.spot, s)) return x;
    }
    return null;
}

/// Inspect leans on rows: the orbs and slots sit side by side.
const INSPECT_ACROSS: f32 = 2;

fn toward(spots: []const Part, from: Part, d: mathx.Dir) ?Spot {
    var boxes: [SPOTS_MAX]rl.Rectangle = undefined;
    for (spots, boxes[0..spots.len]) |s, *b| b.* = s.box;
    const i = menu.nearest(from.box, boxes[0..spots.len], d, INSPECT_ACROSS) orelse return null;
    return spots[i].spot;
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
    if (here.spot == .log and d.delta().y != 0 and d.delta().x == 0) {
        g.log.move(-d.delta().y);
        return;
    }
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
    const at = look.vec(p);
    var buf: [SPOTS_MAX]Part = undefined;
    for (spotsOf(g, &buf)) |s| {
        const over = if (round(s.spot)) rl.checkCollisionPointCircle(at, look.middle(s.box), s.box.width / 2) else rl.checkCollisionPointRec(at, s.box);
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
    if (here.spot == .log) return;
    var title_buf: [TIP_TITLE_MAX]u8 = undefined;
    var body_buf: [menu.NOTE_MAX * 2]u8 = undefined;
    const tip = tipOf(g, here.spot, &title_buf, &body_buf);
    hud.tooltip(&g.face, hudLayout(g), g.screen, here.box, tip.title, tip.body);
}

const Tip = struct { title: [:0]const u8, body: []const u8 };
const TIP_TITLE_MAX: usize = 64;

fn tipOf(g: *const Game, s: Spot, title_buf: []u8, body_buf: []u8) Tip {
    return switch (s) {
        .log => .{ .title = "Events", .body = "" },
        .life => blk: {
            const life = lifeShown(g);
            break :blk .{
                .title = hud.LIFE,
                .body = std.fmt.bufPrint(body_buf, "Current|{d}\nMaximum|{d}\nPhysical reduction|{d}%\nDodge|{d}%", .{ life.hp, life.max, heroAttrs(g).reduction(), heroAttrs(g).dodge() }) catch "",
            };
        },
        .mana => .{
            .title = hud.MANA,
            .body = std.fmt.bufPrint(body_buf, "Current|{d}\nMaximum|{d}\nRecovery / turn|{d}", .{ manaShown(g), manaMax(g), heroes.MANA_REGEN }) catch "",
        },
        .slot => |i| blk: {
            const v = slotShown(g, i) orelse break :blk .{ .title = "Empty", .body = "Skill|Unbound" };
            const act = v.act;
            var body = std.io.fixedBufferStream(body_buf);
            const w = body.writer();
            if (act == .secondary) break :blk .{ .title = act.name(), .body = std.fmt.bufPrint(body_buf, "While held|Secondary skill set\nTurns|{d}", .{act.turns()}) catch "" };
            w.print("Rank|{d}\nMana|{d}\nCooldown|{d}\nTurns|{d}", .{ g.growth.ranks.get(act), g.growth.cost(act), g.growth.cooldown(act), act.turns() }) catch {};
            if (act.reticle() != null) w.print("\nRange|{d}", .{act.reach()}) catch {};
            if (act.style()) |style| {
                const bases = basesFor(g, act);
                const by = skillAttrs(g, act);
                const physical = bases.physical();
                if (physical.hi > 0) {
                    const span = by.span(style, physical);
                    w.print("\nPhysical|{d}-{d}", .{ span.lo, span.hi }) catch {};
                }
                if (bases.element) |b| {
                    const span = by.span(style, b);
                    w.print("\n{s}|{d}-{d}", .{ menu.named(act.element().?), span.lo, span.hi }) catch {};
                }
            }
            if (v.drinks) |n|
                w.print("\nDrinks left|{d}", .{n}) catch {}
            else if (v.cooling > 0)
                w.print("\nReady in|{d}", .{v.cooling}) catch {};
            break :blk .{ .title = act.name(), .body = body.getWritten() };
        },
        .status => |st| blk: {
            const turns = if (heroShown(g)) |h| h.status.get(st) else 0;
            break :blk .{
                .title = std.fmt.bufPrintZ(title_buf, "{s}, {d} turn{s}", .{ st.title(), turns, plural(turns) }) catch st.title(),
                .body = switch (st) {
                    .bleeding => std.fmt.bufPrint(body_buf, "Damage / still|{d}\nDamage / moving|{d}", .{ bleeding.STILL, bleeding.MOVING }) catch "",
                    .burning => std.fmt.bufPrint(body_buf, "Fire / turn|{d}\nResistance|Applies", .{burning.PER_TURN}) catch "",
                    .chilled => std.fmt.bufPrint(body_buf, "Skipped action|1 in {d}", .{glacial.CYCLE}) catch "",
                    .pinned => "Movement|Prevented\nAdjacent attacks|Allowed",
                    .warded => "Damage taken|Mana before life",
                },
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
    drawMap(g);
    g.vignette.draw(g.screen.x, g.screen.y);
    drawMinimap(g);
    drawHud(g);
    journal.draw(&g.face, &g.sprites, g.screen, &g.log);
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
    g.st.context = switch (g.mode) {
        .play => .play,
        .aim => .target,
        .bind, .dead, .pause, .inspect => .menu,
    };
    g.st.sets = g.mode == .inspect;
    g.st.modifier = g.bar.modifier;
    g.st.aimed = if (g.mode == .aim) g.aim_by else null;
    g.st.update(dt);
    syncScreen(g, g.st.fullscreen);
    update(g, dt);
    prepare(g);
    g.st.modifier = g.bar.modifier;
    rl.beginDrawing();
    drawFrame(g);
    rl.endDrawing();
}

/// Capture a render target: raylib guarantees its batch flush at `endTextureMode`.
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

    arena(g, .{ .x = 20, .y = 20 }, &.{});
    grassOver(&g.lv);
    const chest_at = P{ .x = 21, .y = 20 };
    g.lv.set(chest_at, .chest);
    g.lv.putBarrel(.{ .x = 23, .y = 20 });
    settle(g);
    try capture(g, target, SHOTS_DIR ++ "/chest-closed.png");
    heroStep(g, .e, 0);
    drawnOut(g);
    if (g.lv.at(chest_at) != .chest_open or g.ground.coin_n != 1) return error.ChestUnopened;
    try capture(g, target, SHOTS_DIR ++ "/chest-open.png");

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
    g.rng = procRng(g, .burning_arrow, 1);
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
    g.rng = procRng(g, .glacial_shot, 3);
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

    try shootEffects(g, target);

    poseFright(g);
    if (speechLeft(g) <= fx.SPEECH_FADE_S) return error.FrightUnspoken;
    try capture(g, target, SHOTS_DIR ++ "/pib-fright.png");
    update(g, speechLeft(g) - fx.SPEECH_FADE_S / 2);
    try capture(g, target, SHOTS_DIR ++ "/pib-fright-fade.png");

    poseGas(g);
    try capture(g, target, SHOTS_DIR ++ "/gas.png");

    openPause(g);
    try capture(g, target, SHOTS_DIR ++ "/pause.png");
    g.pause_menu.at = @intFromEnum(PauseRow.debug);
    press(g, CONFIRM);
    try capture(g, target, SHOTS_DIR ++ "/debug.png");
    g.mode = g.paused_from;

    poseWaterSteps(g);
    try capture(g, target, SHOTS_DIR ++ "/water-steps.png");

    for ([_]struct { hour: f32, outdoors: bool, path: [:0]const u8 }{
        .{ .hour = day.NOON, .outdoors = true, .path = SHOTS_DIR ++ "/water-mirrors-day.png" },
        .{ .hour = NIGHT, .outdoors = true, .path = SHOTS_DIR ++ "/water-mirrors-night.png" },
        .{ .hour = day.NOON, .outdoors = false, .path = SHOTS_DIR ++ "/water-mirrors-torch.png" },
    }) |study| {
        poseWaterMirrors(g, study.hour, study.outdoors);
        try capture(g, target, study.path);
    }
    try checkWaterMirrors(g, target);
    try checkMapEdge(g, target);

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
        .{ .hour = NIGHT, .path = SHOTS_DIR ++ "/shadows-hidden-moon.png" },
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
            try w.load(std.heap.c_allocator, atlas.mapPath(SHOT_BIOME));
            beginMapAt(g, w, w.start, SHOT_SEED);
            try capture(g, target, SHOTS_DIR ++ "/biome.png");
        }
        {
            try w.load(std.heap.c_allocator, atlas.START);
            beginMapAt(g, w, w.start, SHOT_SEED);
            for (0..RAIN_FRAMES) |_| update(g, mathx.FRAME_DT);
            try capture(g, target, SHOTS_DIR ++ "/strand.png");
            const seen = g.lv.seen;
            const lit = g.lv.lit;
            toggleReveal(g);
            try capture(g, target, SHOTS_DIR ++ "/map-revealed.png");
            toggleReveal(g);
            if (!std.mem.eql(bool, &seen, &g.lv.seen) or !std.mem.eql(bool, &lit, &g.lv.lit)) return error.RevealChangedSight;
            try checkWaterSurface(g);
            try shootWater(g, target);
        }
        {
            try w.load(std.heap.c_allocator, atlas.mapPath(SHOT_OUTDOOR));
            for (SHOT_HOURS) |s| {
                beginMapAt(g, w, w.start, SHOT_SEED);
                g.lv.seen = @splat(false);
                g.clock = day.Clock.at(s.hour);
                settle(g);
                try capture(g, target, s.path);
            }
            inline for ([_]f32{ 8.5, day.NOON, DUSK, day.DEAD_OF_NIGHT }) |hour| {
                beginMapAt(g, w, w.start, SHOT_SEED);
                g.clock = day.Clock.at(hour);
                settle(g);
                g.light.sky = sky.under(hour, .bleak);
                try capture(g, target, SHOTS_DIR ++ "/bleak-" ++ std.fmt.comptimePrint("{d:.1}", .{hour}) ++ ".png");
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
    try shootCharacter(g);

    const entry = naming.Entry{ .name = heroes.Name.of("Arwen"), .row = 2, .col = 4 };
    rl.beginTextureMode(target);
    rl.clearBackground(look.BG);
    var title: [naming.TITLE_MAX]u8 = undefined;
    naming.draw(&entry, g.face, g.screen, naming.titleOf(heroes.DEFAULT, &title));
    rl.endTextureMode();
    try exportTarget(target, SHOTS_DIR ++ "/name.png");
}

fn shootCharacter(g: *Game) !void {
    const w = try std.heap.c_allocator.create(atlas.Atlas);
    defer std.heap.c_allocator.destroy(w);
    defer g.map = null;
    const screen = g.screen;
    defer g.screen = screen;
    g.screen = .{ .x = 1280, .y = 720 };
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    spar.author(w, .slime);
    g.class = heroes.DEFAULT;
    beginMapAt(g, w, w.start, SHOT_SEED);
    _ = g.growth.gain(100);
    _ = g.inventory.add(.{ .kind = .cap, .mods = .{ .{ .kind = .life, .value = 3 }, null } });
    try g.inventory.equip(0, .helm, g.growth.attributes(g.class));
    _ = g.inventory.add(.{ .kind = .bow, .mods = .{ .{ .kind = .dexterity, .value = 2 }, null } });
    try g.inventory.equip(0, .right_hand, g.growth.attributes(g.class));
    _ = g.inventory.add(.{ .kind = .helmet, .mods = .{ .{ .kind = .life, .value = 6 }, .{ .kind = .mana, .value = 10 } } });
    _ = g.inventory.add(.{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 3 }, null } });
    _ = g.inventory.add(.{ .kind = .leather });
    _ = g.ground.add(.{ .item = .{ .kind = .amulet }, .at = g.heroActor().?.at });
    g.log.push(.event, "Archer enters the old ruins.", .{});
    g.log.push(.damage, "Archer shoots the rat for 3.", .{});
    g.log.push(.danger, "The rat bites Archer for 2.", .{});
    g.log.push(.recovery, "Archer recovers 4 life.", .{});
    g.log.push(.loot, "Archer picks up 8 gold.", .{});
    g.log.push(.event, "Archer opens the chest.", .{});
    g.log.push(.loot, "Picked up Iron helm.", .{});
    g.log.push(.progress, "Level 3: +2 passive, +2 active points.", .{});
    g.log.push(.damage, "Archer shoots the slime for 4.", .{});
    g.log.push(.danger, "The slime hits Archer for 2.", .{});
    noticeItems(g, g.heroActor().?.at);
    syncStats(g);
    drawnOut(g);
    g.back = .editor;
    try capture(g, target, SHOTS_DIR ++ "/arena.png");
    openPause(g);
    g.pause_menu.at = @intFromEnum(PauseRow.character);
    press(g, CONFIRM);
    inline for (book.PAGES) |page| {
        g.character.choose(page);
        g.character.tabs = false;
        if (page == .passives) g.character.cursor = progress.start(g.class);
        if (page == .equipment) g.character.cursor = @intFromEnum(items.Slot.helm);
        try capture(g, target, SHOTS_DIR ++ "/character-" ++ @tagName(page) ++ ".png");
    }
    g.character.choose(.inventory);
    g.character.tabs = false;
    press(g, CONFIRM);
    press(g, CONFIRM);
    try capture(g, target, SHOTS_DIR ++ "/character-confirm.png");
    g.character.prompt = null;
    g.mode = .play;
    _ = openNearby(g);
    try capture(g, target, SHOTS_DIR ++ "/character-nearby.png");
    g.mode = .play;
    try capture(g, target, SHOTS_DIR ++ "/event-log.png");
}

fn shootEffects(g: *Game, target: rl.RenderTexture2D) !void {
    inline for (.{
        .{ heroes.Class.wizard, skillbar.Act.spark },
        .{ heroes.Class.wizard, skillbar.Act.fireball },
        .{ heroes.Class.wizard, skillbar.Act.chain_lightning },
        .{ heroes.Class.wizard, skillbar.Act.frost_nova },
        .{ heroes.Class.wizard, skillbar.Act.blink },
        .{ heroes.Class.wizard, skillbar.Act.mana_shield },
        .{ heroes.Class.archer, skillbar.Act.burning_arrow },
        .{ heroes.Class.archer, skillbar.Act.glacial_shot },
    }) |study| {
        const act = study[1];
        const from = P{ .x = 20, .y = 20 };
        heroArena(g, study[0], from, &.{});
        var cells = grid.Cells.of(.{ .x = 13, .y = 13 }, .{ .x = 33, .y = 28 });
        while (cells.next()) |p| g.lv.set(p, .grass);
        wallRow(&g.lv, 17, 18, 29);
        @import("map/procgen.zig").reshape(&g.lv);
        for ([_]P{ .{ .x = 23, .y = 20 }, .{ .x = 24, .y = 19 }, .{ .x = 24, .y = 21 }, .{ .x = 22, .y = 21 } }) |at| _ = spawnAt(g, .slime, at, false);
        toughenFoes(g);
        g.clock = day.Clock.at(day.DEAD_OF_NIGHT);
        settle(g);
        const directory = SHOTS_DIR ++ "/fx-" ++ @tagName(act);
        try std.fs.cwd().makePath(directory);
        try capture(g, target, directory ++ "/before.png");
        useSkill(g, boundTo(g, act));
        if (act.reticle()) |reticle| {
            g.mark = if (reticle == .leap) .{ .x = 22, .y = 20 } else .{ .x = 23, .y = 20 };
            confirmAim(g);
        }
        g.st = .{};
        var previous: f32 = 0;
        inline for ([_]f32{ 0.012, 0.028, 0.05, 0.09, 0.16, 0.26 }, 0..) |t, i| {
            update(g, t - previous);
            previous = t;
            try capture(g, target, directory ++ "/" ++ std.fmt.comptimePrint("{d}", .{i}) ++ ".png");
        }
    }
    g.class = heroes.DEFAULT;
    g.bar = skillbar.Bar.of(g.class);
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
    const studies = [_]struct { screen: P, hp: i32, mana: i32, xp: f32 = 0, device: input.Device, path: [:0]const u8, ailing: bool = false, bind: ?[:0]const u8 = null }{
        .{ .screen = .{ .x = 1280, .y = 720 }, .hp = 100, .mana = 100, .xp = 0.95, .device = .keys, .path = SHOTS_DIR ++ "/hud-full-1280.png", .bind = SHOTS_DIR ++ "/hud-bind-720.png" },
        .{ .screen = .{ .x = 1280, .y = 720 }, .hp = 75, .mana = 60, .xp = 0.62, .device = .ps5, .path = SHOTS_DIR ++ "/hud-ps5-1280.png", .bind = SHOTS_DIR ++ "/hud-bind-ps5.png" },
        .{ .screen = .{ .x = 1600, .y = 900 }, .hp = 50, .mana = 35, .xp = 0.37, .device = .xbox, .path = SHOTS_DIR ++ "/hud-partial-1600.png", .ailing = true },
        .{ .screen = .{ .x = 1920, .y = 1080 }, .hp = 10, .mana = 0, .xp = 0.08, .device = .keys, .path = SHOTS_DIR ++ "/hud-critical-1920.png" },
        .{ .screen = .{ .x = 1600, .y = 900 }, .hp = 0, .mana = 0, .device = .keys, .path = SHOTS_DIR ++ "/hud-empty-1600.png" },
    };
    for (studies) |study| {
        g.screen = study.screen;
        poseForest(g);
        g.bar = skillbar.Bar.of(g.class);
        g.st = .{ .device = study.device, .modifier = g.bar.modifier };
        const body = &g.pictured[heroSlot(g).?];
        body.hp = mathx.percentOf(body.max, study.hp);
        g.mana = mathx.percentOf(manaMax(g), study.mana);
        g.xp_shown = study.xp;
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
const DUSK: f32 = 19.3;
const NIGHT: f32 = 22.5;
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
    wound(g, 2, .{ .dmg = actor.row(.rat).hp }, SHOOT, .{ .from = hero, .wait = wait });
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

fn poseWaterMirrors(g: *Game, hour: f32, outdoors: bool) void {
    arena(g, .{ .x = 24, .y = 20 }, &.{.{ .x = 27, .y = 21 }});
    grassOver(&g.lv);
    var cells = grid.Cells.of(.{ .x = 17, .y = 18 }, .{ .x = 33, .y = 26 });
    while (cells.next()) |p| g.lv.set(p, if (p.y >= 23) .water else .shallows);
    for ([_]i32{ 19, 20, 21, 28, 29 }) |x| g.lv.set(.{ .x = x, .y = 17 }, .shrub);
    g.lv.set(.{ .x = 31, .y = 20 }, .boulder);
    g.lv.putBarrel(.{ .x = 21, .y = 21 });
    _ = spawnAt(g, .wizard, .{ .x = 25, .y = 23 }, false);
    _ = spawnAt(g, .slime, .{ .x = 29, .y = 22 }, false);
    wallRow(&g.lv, 17, 23, 26);
    g.lv.addTorch(.{ .x = 24, .y = 17 });
    studyLit(g, outdoors, hour);
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
    studyLit(g, outdoors, hour);
}

fn studyLit(g: *Game, outdoors: bool, hour: f32) void {
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

fn waterSample(g: *Game, target: rl.RenderTexture2D, beds: *const dual.Beds, view: ?look.WaterView, origin: [2]f32) !rl.Image {
    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color.blank);
    g.sprites.drawGround(beds, origin, CELL_F, view);
    rl.endTextureMode();
    return readTarget(target);
}

fn shootWater(g: *Game, target: rl.RenderTexture2D) !void {
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/water-reflections");
    g.st = .{};
    const FRAMES = 40;
    const EVERY = 6;
    const before = g.light.t.at();
    const minute = g.clock;
    for (0..FRAMES) |i| {
        for (0..EVERY) |_| update(g, mathx.FRAME_DT);
        var path: [80]u8 = undefined;
        try capture(g, target, try std.fmt.bufPrintZ(&path, SHOTS_DIR ++ "/water-reflections/{d:0>2}.png", .{i}));
    }
    const elapsed = g.light.t.at() - before;
    if (elapsed < FRAMES * EVERY * mathx.FRAME_DT - 0.01 or !std.meta.eql(minute, g.clock)) return error.WaterIdleClock;
    std.debug.print("water reflections idle play: {d:.2} seconds in {d} rendered frames, no turn spent\n", .{ elapsed, FRAMES });
}

const CAMERA_SHIFT = P{ .x = 16, .y = 8 };

fn checkWaterSurface(g: *Game) !void {
    const BANDS = [_]grid.Tile{ .water, .shallows, .grass };
    const BAND = 4;
    const ROWS = 2;
    const Band = struct {
        fn of(x: i32) ?usize {
            const in_band = @mod(x, BAND * CELL);
            if (in_band < HALF_CELL or in_band >= BAND * CELL - HALF_CELL) return null;
            return @intCast(@divTrunc(x, BAND * CELL));
        }
    };
    const width = BANDS.len * BAND * CELL;
    const height = ROWS * CELL;
    const target = try rl.loadRenderTexture(width, height);
    defer rl.unloadRenderTexture(target);
    const mirror = try rl.loadRenderTexture(width, height);
    defer rl.unloadRenderTexture(mirror);
    rl.beginTextureMode(mirror);
    rl.clearBackground(look.rgb(0x1010ff));
    rl.drawRectangle(0, CELL, width, CELL, look.rgb(0xff1010));
    rl.endTextureMode();
    var lv = grid.Level.blank();
    for (&lv.tile, 0..) |*t, i| {
        const x: usize = @intCast(grid.Level.of(i).x);
        t.* = BANDS[@min(x / BAND, BANDS.len - 1)];
    }
    var beds: dual.Beds = undefined;
    beds.fill(&lv, .{ .x = 0, .y = 0 }, .{ .x = BANDS.len * BAND, .y = ROWS }, false);
    var sight: [grid.CELLS]rl.Color = @splat(.{ .r = 128, .g = 128, .b = 128, .a = 0 });
    for (sight[0..grid.COLS]) |*pixel| pixel.a = 255;
    const visibility = look.clamped(look.rgba(&sight, grid.W, grid.H), .point) orelse return error.WaterVisibilityMissing;
    defer rl.unloadTexture(visibility);
    const gleam = look.canvas(grid.W, grid.H, look.rgb(0x302010), .point) orelse return error.WaterGlintsMissing;
    defer rl.unloadTexture(gleam);
    const dark = look.canvas(1, 1, rl.Color.black, .point) orelse return error.WaterGlintsMissing;
    defer rl.unloadTexture(dark);
    const blank = look.canvas(1, 1, rl.Color.blank, .point) orelse return error.WaterMirrorMissing;
    defer rl.unloadTexture(blank);
    const plain = try waterSample(g, target, &beds, null, .{ 0, 0 });
    defer rl.unloadImage(plain);
    var view = look.WaterView{ .screen = .{ width, height }, .visibility = visibility, .glints = dark };
    const still = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(still);
    view.glints = gleam;
    const first = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(first);
    if (!rl.exportImage(first, SHOTS_DIR ++ "/water-glints.png")) return error.ExportFailed;
    view.glints = dark;
    view.mirror = .{ .live = mirror.texture, .memory = blank };
    const second = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(second);
    if (!rl.exportImage(second, SHOTS_DIR ++ "/water-mirror-mask.png")) return error.ExportFailed;
    var glinted = [_]usize{0} ** BANDS.len;
    var reflected = [_]usize{0} ** BANDS.len;
    var fixed: usize = 0;
    var y: i32 = 0;
    while (y < height) : (y += 1) {
        var x: i32 = 0;
        while (x < width) : (x += 1) {
            const base = rl.getImageColor(plain, x, y);
            if (!std.meta.eql(base, rl.getImageColor(still, x, y))) return error.WaterSurfaceChanged;
            const a = rl.getImageColor(first, x, y);
            const b = rl.getImageColor(second, x, y);
            if (a.a != base.a or b.a != base.a) return error.WaterAlphaChanged;
            const band = Band.of(x) orelse continue;
            if (y >= CELL or band == 2) {
                if (!std.meta.eql(base, a) or !std.meta.eql(base, b)) return error.WaterOutsideSurface;
                fixed += 1;
            } else {
                if (!std.meta.eql(base, a)) glinted[band] += 1;
                if (!std.meta.eql(base, b)) {
                    if (b.b <= b.r) return error.WaterMirrorUpsideDown;
                    reflected[band] += 1;
                }
            }
        }
    }
    for (0..2) |i| {
        if (glinted[i] < 100 or reflected[i] < 100) return error.WaterReflectionMissing;
    }
    view.mirror = .{ .live = blank, .memory = mirror.texture };
    const memory = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(memory);
    var remembered = [_]usize{0} ** BANDS.len;
    y = 0;
    while (y < height) : (y += 1) {
        var x: i32 = 0;
        while (x < width) : (x += 1) {
            const base = rl.getImageColor(plain, x, y);
            const m = rl.getImageColor(memory, x, y);
            if (m.a != base.a) return error.WaterAlphaChanged;
            const band = Band.of(x) orelse continue;
            if (y < CELL or band == 2) {
                if (!std.meta.eql(base, m)) return error.WaterOutsideSurface;
            } else if (!std.meta.eql(base, m)) {
                if (@as(i32, m.r) - base.r <= @as(i32, m.b) - base.b) return error.WaterMirrorUpsideDown;
                remembered[band] += 1;
            }
        }
    }
    for (remembered[0..2]) |count| {
        if (count < 100) return error.WaterMemoryMissing;
    }
    view.glints = gleam;
    view.mirror = null;
    const shift = CAMERA_SHIFT;
    const shifted = try waterSample(g, target, &beds, view, .{ -shift.x, -shift.y });
    defer rl.unloadImage(shifted);
    var compared: usize = 0;
    y = 0;
    while (y < height - shift.y) : (y += 1) {
        var x: i32 = 0;
        while (x < width - shift.x) : (x += 1) {
            const a = rl.getImageColor(first, x + shift.x, y + shift.y);
            const b = rl.getImageColor(shifted, x, y);
            if (@abs(@as(i32, a.r) - b.r) > 1 or @abs(@as(i32, a.g) - b.g) > 1 or @abs(@as(i32, a.b) - b.b) > 1 or a.a != b.a) return error.WaterMovesWithCamera;
            compared += 1;
        }
    }
    std.debug.print("smooth water GPU: glints {d}/{d}, live mirrors {d}/{d}, remembered mirrors {d}/{d}; {d} grass/memory pixels exclude live effects, {d} camera samples agree; static art and alpha preserved\n", .{ glinted[0], glinted[1], reflected[0], reflected[1], remembered[0], remembered[1], fixed, compared });
}

fn checkMapEdge(g: *Game, target: rl.RenderTexture2D) !void {
    arena(g, .{ .x = 24, .y = grid.H - 4 }, &.{});
    grassOver(&g.lv);
    for (0..grid.W) |x| g.lv.set(.{ .x = @intCast(x), .y = grid.H - 1 }, .grass);
    studyLit(g, true, day.NOON);
    const edge = @divTrunc(g.screen.y, 2);
    g.cam.y = @floatFromInt(grid.H * CELL - edge);
    prepare(g);
    var compared: usize = 0;
    for ([_]bool{ true, false }) |visible| {
        @memset(&g.lv.lit, visible);
        g.light.settle(&g.lv);
        rl.beginTextureMode(target);
        g.framebuffer = target.id;
        rl.clearBackground(look.BG);
        drawMap(g);
        rl.endTextureMode();
        g.framebuffer = 0;
        try exportTarget(target, if (visible) SHOTS_DIR ++ "/map-bottom-edge.png" else SHOTS_DIR ++ "/map-bottom-memory.png");
        const img = try readTarget(target);
        defer rl.unloadImage(img);
        var y = edge;
        while (y < edge + CELL) : (y += 1) {
            var x: i32 = 0;
            while (x < g.screen.x) : (x += 1) {
                const pixel = rl.getImageColor(img, x, y);
                if (pixel.r != look.BG.r or pixel.g != look.BG.g or pixel.b != look.BG.b) return error.MapEdgeOverhang;
                compared += 1;
            }
        }
    }
    std.debug.print("map bottom GPU: {d} pixels beyond lit and remembered terrain stay clear\n", .{compared});
}

fn checkWaterMirrors(g: *Game, target: rl.RenderTexture2D) !void {
    const original = try readTarget(g.sprites.mirror orelse return error.WaterMirrorMissing);
    defer rl.unloadImage(original);
    const camera = g.cam;
    const shift = CAMERA_SHIFT;
    g.cam.x += @floatFromInt(shift.x);
    g.cam.y += @floatFromInt(shift.y);
    drawInto(g, target);
    const moved = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(moved);
    var compared: usize = 0;
    var reflected: usize = 0;
    var y: i32 = 0;
    while (y < original.height - shift.y) : (y += 1) {
        var x: i32 = 0;
        while (x < original.width - shift.x) : (x += 1) {
            const a = rl.getImageColor(original, x + shift.x, y + shift.y);
            const b = rl.getImageColor(moved, x, y);
            if (a.a > 0) reflected += 1;
            if (!std.meta.eql(a, b)) return error.WaterMirrorCameraDrift;
            compared += 1;
        }
    }
    if (reflected < 100) return error.WaterMirrorEmpty;
    g.cam = camera;
    @memset(&g.lv.lit, false);
    g.light.settle(&g.lv);
    try capture(g, target, SHOTS_DIR ++ "/water-mirrors-memory.png");
    const memory = try readTarget(g.sprites.mirror_memory.?);
    defer rl.unloadImage(memory);
    const dim = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(dim);
    const actors = g.pool.n;
    g.pool.n = 0;
    defer g.pool.n = actors;
    drawInto(g, target);
    const empty = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(empty);
    var remembered: usize = 0;
    y = 0;
    while (y < memory.height) : (y += 1) {
        var x: i32 = 0;
        while (x < memory.width) : (x += 1) {
            if (rl.getImageColor(memory, x, y).a > 0) remembered += 1;
            if (!std.meta.eql(rl.getImageColor(dim, x, y), rl.getImageColor(empty, x, y))) return error.WaterMirrorRevealsHidden;
        }
    }
    if (remembered < 100) return error.WaterMemoryMissing;
    @memset(&g.lv.seen, false);
    g.light.settle(&g.lv);
    rl.beginTextureMode(target);
    g.framebuffer = target.id;
    const c = Cam.of(g);
    var flame_buf: [grid.MAX_TORCHES]light.Flame = undefined;
    _ = drawMirrors(g, c, viewBox(g, c), &.{}, g.light.flames(&g.lv, &flame_buf));
    rl.endTextureMode();
    g.framebuffer = 0;
    for ([_]rl.RenderTexture2D{ g.sprites.mirror.?, g.sprites.mirror_memory.? }) |t| {
        const hidden = try readTarget(t);
        defer rl.unloadImage(hidden);
        y = 0;
        while (y < hidden.height) : (y += 1) {
            var x: i32 = 0;
            while (x < hidden.width) : (x += 1) {
                if (rl.getImageColor(hidden, x, y).a != 0) return error.WaterMirrorRevealsHidden;
            }
        }
    }
    std.debug.print("water mirror GPU: {d} live and {d} remembered pixels; {d} camera samples agree; hidden bodies and unexplored scenery absent\n", .{ reflected, remembered, compared });
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
            const map_x = x + c.x;
            const map_y = y + c.y;
            if (!visible or map_x >= (HIDDEN_SHADOW_X + 1) * CELL) leaked += 1;
            if (map_x < (HIDDEN_SHADOW_X - 2) * CELL or map_x >= HIDDEN_SHADOW_X * CELL) continue;
            for (std.enums.values(Hidden)) |k| {
                const row = HIDDEN_SHADOW_ROWS.get(k);
                if (map_y >= (row - 1) * CELL and map_y < (row + 2) * CELL) hits.getPtr(k).* += 1;
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
/// Warm up rain so the Strand capture includes both drops and splashes.
const RAIN_FRAMES: usize = 90;
const SHOT_OUTDOOR = "wilds";
const SHOT_HOURS = [_]struct { hour: f32, path: [:0]const u8 }{
    .{ .hour = 7.0, .path = SHOTS_DIR ++ "/dawn.png" },
    .{ .hour = day.NOON, .path = SHOTS_DIR ++ "/noon.png" },
    .{ .hour = 16.5, .path = SHOTS_DIR ++ "/day.png" },
    .{ .hour = DUSK, .path = SHOTS_DIR ++ "/dusk.png" },
    .{ .hour = 22, .path = SHOTS_DIR ++ "/early-night.png" },
    .{ .hour = day.DEAD_OF_NIGHT, .path = SHOTS_DIR ++ "/night.png" },
    .{ .hour = 4, .path = SHOTS_DIR ++ "/late-night.png" },
};

fn overviews(g: *Game, w: *atlas.Atlas) !void {
    const target = try rl.loadRenderTexture(grid.W * OVERVIEW_CELL, grid.H * OVERVIEW_CELL);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_MAPS);
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
        const name = try std.fmt.bufPrintZ(&buf, SHOTS_MAPS ++ "/{s}.png", .{list.stem(i)});
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
        const was = g.heroActor().?.at;
        t.reset();
        g.st.walk = g.st.step.tick(dt, 1, d.heading(), input.Stepper.SETTLE);
        update(g, dt);
        sim[i] = t.lap();
        drawInto(g, target);
        draw[i] = t.read();
        const tried = g.st.walk != null and g.pending == null;
        if (tried and g.heroActor() != null and g.heroActor().?.at.eq(was)) d = mathx.ALL_DIRS[rng.below(mathx.ALL_DIRS.len)];
    }
    for ([_][]u64{ &sim, &draw }, [_][]const u8{ "update", "draw" }) |xs, name| {
        std.mem.sort(u64, xs, {}, std.sort.asc(u64));
        var sum: u64 = 0;
        for (xs) |x| sum += x;
        std.debug.print("{s}: mean {d:.3} ms, p99 {d:.3} ms, max {d:.3} ms\n", .{ name, ms(sum / xs.len), ms(xs[xs.len * 99 / 100]), ms(xs[xs.len - 1]) });
    }
    try benchAssets(g);
    try benchEffects(g, target);
    poseWaterMirrors(g, day.NOON, true);
    drawInto(g, target);
    var water_timer = try std.time.Timer.start();
    for (0..BENCH_FRAMES / 6) |_| drawInto(g, target);
    std.debug.print("smooth water with mirrors and glints: {d:.3} ms mean draw over {d} frames\n", .{ ms(water_timer.read() / (BENCH_FRAMES / 6)), BENCH_FRAMES / 6 });
}

fn benchEffects(g: *Game, target: rl.RenderTexture2D) !void {
    poseGas(g);
    const frames = BENCH_FRAMES / 6;
    for ([_]usize{ 0, 8, 32 }) |count| {
        g.fx.clear();
        for (0..count) |i| {
            const at = mathx.centre(.{ .x = 15 + @as(i32, @intCast(i % 8)), .y = 14 + @as(i32, @intCast(i / 8)) });
            g.fx.glow(at, look.FIRE, .{ .radius = fx.EMBER_GLOW.radius, .gain = fx.EMBER_GLOW.gain, .life = 1 });
        }
        drawInto(g, target);
        var timer = try std.time.Timer.start();
        for (0..frames) |_| drawInto(g, target);
        std.debug.print("effects {d}: {d:.3} ms mean draw over {d} frames\n", .{ count, ms(timer.read() / frames), frames });
    }
}

fn benchAssets(g: *Game) !void {
    const alloc = std.heap.c_allocator;
    const w = try alloc.create(atlas.Atlas);
    defer alloc.destroy(w);
    defer g.map = null;
    inline for ([_][]const u8{ SHOT_OUTDOOR, SHOT_BIOME, SHOT_OUTDOOR }) |name| {
        try w.load(alloc, atlas.mapPath(name));
        beginMapAt(g, w, w.start, SHOT_SEED);
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
    const h = g.heroActor() orelse return;
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
    wound(g, rat, .{ .dmg = bow.DMG_LO }, SHOOT, .{ .from = h.at, .wait = 0 });
    settle(g);
}

fn arena(g: *Game, hero: P, rats: []const P) void {
    g.lv = grid.openFloor();
    reset(g, hero);
    for (progress.skills(g.class)) |s| g.growth.ranks.set(s.act, 1);
    g.bar = skillbar.Bar.of(g.class);
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

/// An RNG matching `confirmAim` that afflicts the first `procs` body hits, the direct one first.
fn procRng(g: *const Game, comptime act: skillbar.Act, procs: usize) mathx.Rng {
    const Procs = struct {
        by: attrs.Attrs,
        bases: SkillBases,
        n: usize,
        fn holds(p: @This(), rng: *mathx.Rng) bool {
            var raw = rollRaw(rng, act, p.bases, true);
            for (0..p.n) |_| {
                _ = scaled(rng, p.by, comptime act.style().?, raw);
                if (!skillbar.Act.arrow(act).procs(rng, 0)) return false;
                raw.physical = 0;
            }
            return true;
        }
    };
    return rngWhere(Procs{ .by = skillAttrs(g, act), .bases = basesFor(g, act), .n = procs });
}

test "skills cannot start a second turn while the first is still being drawn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const clock = g.clock;
    const hp = g.heroActor().?.hp;
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
        try std.testing.expectEqual(hp, g.heroActor().?.hp);
        try std.testing.expectEqual(manaMax(g), g.mana);
        try std.testing.expectEqual(act, g.pending.?.skill.act);
    }
    g.pending = null;
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
    return aboutRateOf(hits, TRIES, rate);
}

const RATE_TOL: f32 = 0.08;

fn aboutRateOf(hits: usize, of: usize, rate: f32) bool {
    const got = @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(of));
    return @abs(got - rate) < RATE_TOL;
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

fn expectDamage(g: *const Game, comptime act: skillbar.Act, dealt: i32, ranges: []const [2]i32) !void {
    const a = heroAttrs(g);
    const style = comptime act.style().?;
    var lo: i32 = 0;
    var hi: i32 = 0;
    for (ranges) |r| {
        lo += a.dealt(style, r[0], false).least();
        hi += a.dealt(style, r[1], true).most();
    }
    try expectWithin(dealt, lo, hi);
}

/// An RNG under which the next strikes by `kind` land, or are dodged, as `lands` says.
fn bitesRng(g: *const Game, comptime kind: actor.Kind, lands: []const bool) mathx.Rng {
    const s = comptime actor.row(kind).blow.strike;
    std.debug.assert(lands.len <= 1 or s.bleeds == 0);
    const Bites = struct {
        by: attrs.Attrs,
        lands: []const bool,

        fn holds(b: @This(), rng: *mathx.Rng) bool {
            for (b.lands) |l| {
                if ((bite(rng, b.by, s) != null) != l) return false;
            }
            return true;
        }
    };
    return rngWhere(Bites{ .by = heroAttrs(g), .lands = lands });
}

fn meleeThenBites(g: *const Game, count: usize) mathx.Rng {
    const Sequence = struct {
        by: attrs.Attrs,
        strike: actor.Strike,
        n: usize,
        fn holds(s: @This(), rng: *mathx.Rng) bool {
            const raw = s.strike.roll(rng);
            _ = scaled(rng, s.by, .melee, .{ .physical = raw });
            for (0..s.n) |_| if (bite(rng, s.by, actor.row(.rat).blow.strike) == null) return false;
            return true;
        }
    };
    return rngWhere(Sequence{ .by = heroAttrs(g), .strike = g.class.strike(), .n = count });
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

fn walkFor(g: *Game, secs: f32, d: ?mathx.Dir) void {
    var t: f32 = 0;
    while (t < secs) : (t += TEST_DT) walkFrame(g, TEST_DT, d);
}

fn pressWalking(g: *Game, b: input.Button, d: ?mathx.Dir) void {
    g.st.pressed.insert(b);
    walkFrame(g, TEST_DT, d);
    g.st.pressed = .initEmpty();
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
    g.mana = manaMax(g);
    pressHolding(g, .x, &.{.lb});
    try std.testing.expectEqual(Mode.aim, g.mode);
    press(g, .b);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(manaMax(g), g.mana);
    pressHolding(g, .x, &.{.lb});
    g.mark = g.heroActor().?.at;
    press(g, CONFIRM);
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(manaMax(g), g.mana);
    g.mark = .{ .x = 26, .y = 20 };
    g.rng = procRng(g, .glacial_shot, 1);
    press(g, CONFIRM);
    const direct = g.pool.get(2).?;
    const splash = g.pool.get(3).?;
    const dealt = TEST_HP - direct.hp;
    try expectDamage(g, .glacial_shot, dealt, &.{ .{ bow.DMG_LO, bow.DMG_HI }, .{ glacial.COLD_LO, glacial.COLD_HI } });
    try expectDamage(g, .glacial_shot, TEST_HP - splash.hp, &.{.{ glacial.COLD_LO, glacial.COLD_HI }});
    for ([_]u16{ 4, 5, 6 }) |id| try std.testing.expectEqual(TEST_HP, g.pool.get(id).?.hp);
    try std.testing.expectEqual(@as(u8, 0), g.pool.get(6).?.chill.turns);
    try std.testing.expectEqual(manaAfter(g, .glacial_shot), g.mana);
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
    press(g, CONFIRM);
    try expectDamage(g, .glacial_shot, actor.row(.rat).hp - near.hp, &.{.{ bow.DMG_LO, bow.DMG_HI }});
    try std.testing.expectEqual(@as(u8, 0), near.chill.turns);
    try std.testing.expectEqual(actor.row(.rat).hp, g.pool.get(3).?.hp);
    arena(g, from, &.{.{ .x = 26, .y = 20 }});
    toughenFoes(g);
    const barrel = P{ .x = 24, .y = 20 };
    g.lv.putBarrel(barrel);
    pressHolding(g, .x, &.{.lb});
    press(g, CONFIRM);
    try std.testing.expect(!g.lv.hasBarrel(barrel));
    try std.testing.expect(g.ground.coin_n > 0);
    const splash = TEST_HP - g.pool.get(2).?.hp;
    try expectDamage(g, .glacial_shot, splash, &.{.{ glacial.COLD_LO, glacial.COLD_HI }});
    arena(g, from, &.{.{ .x = 26, .y = 21 }});
    pressHolding(g, .x, &.{.lb});
    g.mark = .{ .x = 25, .y = 20 };
    press(g, CONFIRM);
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
    press(g, CONFIRM);
    const lost = TEST_HP - g.pool.get(far).?.hp;
    try expectDamage(g, .glacial_shot, lost, &.{.{ glacial.COLD_LO, glacial.COLD_HI }});
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
    const hp = g.heroActor().?.hp;
    use(g, .wait);
    try std.testing.expectEqual(hp, g.heroActor().?.hp);
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
    burstHit(g, .glacial_shot, .{ .body = id }, a.at, .{ .from = g.heroActor().?.at, .wait = 0.2 });
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
    g.rng = procRng(g, .burning_arrow, 1);
    const clock = g.clock;
    press(g, .a);
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expectEqual(manaMax(g), g.mana);
    press(g, .b);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(manaMax(g), g.mana);
    press(g, .a);
    press(g, .a);
    const dealt = TEST_HP - rat.hp;
    try expectDamage(g, .burning_arrow, dealt, &.{ .{ bow.DMG_LO, bow.DMG_HI }, .{ burning.FIRE_LO, burning.FIRE_HI } });
    try std.testing.expectEqual(manaAfter(g, .burning_arrow), g.mana);
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
    std.debug.print("Burning Arrow: {d} on hit, then {d} over {d} later turns; mana {d}, flames delayed until impact\n", .{ dealt, before - after, burning.TURNS, manaAfter(g, .burning_arrow) });
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
    g.mana = manaMax(g);
    press(g, .a);
    g.mark = g.pool.get(3).?.at;
    press(g, .a);
    try expectDamage(g, .burning_arrow, actor.row(.rat).hp - rat.hp, &.{.{ bow.DMG_LO, bow.DMG_HI }});
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
    wound(g, id, .{ .dmg = 4 }, SHOOT, .{ .from = g.heroActor().?.at, .wait = 0 });
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
    wound(g, id, .{ .dmg = 4 }, SHOOT, .{ .from = g.heroActor().?.at, .wait = 0 });
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
    try std.testing.expectEqual(manaMax(g), g.mana);
    press(g, CONFIRM);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(to, g.heroActor().?.at);
    try std.testing.expect(samePx(cellPx(to), heroNow(g).?));
    try std.testing.expectEqual(grid.NO_ONE, g.lv.who(from));
    try std.testing.expectEqual(g.hero, g.lv.who(to));
    try std.testing.expectEqual(rat, g.pool.get(2).?.at);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(rng, g.rng);
    try std.testing.expectEqual(manaMax(g) - juke.COST, g.mana);
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
    press(g, CONFIRM);
    try std.testing.expectEqual(Mode.aim, g.mode);
    g.lv.putBarrel(.{ .x = 21, .y = 20 });
    nudge(g, .e);
    press(g, CONFIRM);
    try std.testing.expectEqual(from, g.heroActor().?.at);
    press(g, BINDS);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(manaMax(g), g.mana);
    try std.testing.expectEqual(@as(u8, 0), g.cooldown.get(.juke));
    try std.testing.expectEqual(clock, g.clock);
    press(g, .b);
    nudge(g, .w);
    press(g, CONFIRM);
    g.st = .{};
    update(g, 10);
    try std.testing.expectEqual(juke.COOLDOWN, g.cooldown.get(.juke));
    try std.testing.expectEqual(manaMax(g) - juke.COST, g.mana);
    for (0..juke.COOLDOWN) |_| use(g, .wait);
    try std.testing.expectEqual(@as(u8, 0), g.cooldown.get(.juke));
    try std.testing.expectEqual(manaMax(g) - juke.COST + heroes.MANA_REGEN * juke.COOLDOWN, g.mana);
    g.mana = juke.COST - 1;
    press(g, .b);
    try std.testing.expectEqual(Mode.play, g.mode);
    for (0..@as(usize, @intCast(@divExact(manaMax(g), heroes.MANA_REGEN)))) |_| use(g, .wait);
    try std.testing.expectEqual(manaMax(g), g.mana);
    g.bar.bind(.{ .set = .secondary, .button = .rb }, .juke);
    pressHolding(g, .rb, &.{.lb});
    nudge(g, .w);
    press(g, CONFIRM);
    try std.testing.expectEqual(P{ .x = 18, .y = 20 }, g.heroActor().?.at);
    std.debug.print("Juke: free cancel and invalid targets, {d}-turn recovery, mana capped at {d}, secondary binding checked\n", .{ juke.COOLDOWN, manaMax(g) });
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
    press(g, CONFIRM);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expect(g.pool.get(2).?.hurt());
}

test "every targeted slot uses standard confirmation in both skill sets" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var checked: usize = 0;
    for (skillbar.SETS) |set| {
        for (skillbar.SLOTS) |by| {
            arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
            toughen(g.pool.get(2).?);
            g.bar = skillbar.Bar.of(.archer);
            const modifier: input.Button = if (by == .lb) .rt else .lb;
            g.bar.bind(.{ .set = .primary, .button = modifier }, .secondary);
            g.bar.bind(.{ .set = set, .button = by }, .shoot);
            const clock = g.clock;
            if (set == .secondary) pressHolding(g, by, &.{modifier}) else press(g, by);
            try std.testing.expectEqual(Mode.aim, g.mode);
            try std.testing.expectEqual(clock, g.clock);
            try std.testing.expectEqual(set, g.aim_set);
            if (by != CONFIRM and by != BACK) {
                press(g, by);
                try std.testing.expectEqual(Mode.aim, g.mode);
                try std.testing.expectEqual(clock, g.clock);
                try std.testing.expect(!g.pool.get(2).?.hurt());
            }
            press(g, CONFIRM);
            try std.testing.expectEqual(Mode.play, g.mode);
            try std.testing.expect(g.pool.get(2).?.hurt());
            try std.testing.expectEqual(clock.minute + day.TURN_MINUTES, g.clock.minute);
            checked += 1;
        }
    }
    std.debug.print("{d} targeted bindings: opening spends nothing, standard confirm fires once, secondary selection survives modifier release\n", .{checked});
}

test "standard back controls cancel skills opened with B for every class" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var checked: usize = 0;
    for (std.enums.values(heroes.Class)) |class| {
        for ([_]input.Button{ BACK, PAUSE, BINDS }) |back| {
            heroArena(g, class, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
            const clock = g.clock;
            const mana = g.mana;
            const cooldown = g.cooldown;
            const at = g.heroActor().?.at;
            press(g, .b);
            try std.testing.expectEqual(Mode.aim, g.mode);
            press(g, back);
            try std.testing.expectEqual(Mode.play, g.mode);
            try std.testing.expectEqual(clock, g.clock);
            try std.testing.expectEqual(mana, g.mana);
            try std.testing.expectEqual(cooldown, g.cooldown);
            try std.testing.expectEqual(at, g.heroActor().?.at);
            try std.testing.expect(!g.pool.get(2).?.hurt());
            checked += 1;
        }
    }
    std.debug.print("{d} B-opened targeting cases cancel without moving, damage, mana, cooldown or turns\n", .{checked});
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
    holdingView(g, input.HOLD_S, CONFIRM);
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
        const h = g.heroActor().?;
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
        if (contact == null and mathx.dist(r.at, g.heroActor().?.at) == 1) contact = turn;
    }
    const lost = actor.row(HERO).hp - g.heroActor().?.hp;
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
    const lost = actor.row(HERO).hp - g.heroActor().?.hp;
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
    try std.testing.expect(g.mark.x < g.heroActor().?.at.x);
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
        try std.testing.expectEqual(near, g.heroActor().?.at);
        try std.testing.expect(g.pool.get(rat).?.awake);
        use(g, .wait);
        try std.testing.expectEqual(ahead, g.pool.get(rat).?.at);
        const hp = g.heroActor().?.hp;
        const rat_hp = g.pool.get(rat).?.hp;
        g.rng = meleeThenBites(g, 1);
        nudge(g, d);
        try std.testing.expectEqual(near, g.heroActor().?.at);
        try std.testing.expect(g.heroActor().?.hp < hp);
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

test "X opens aim on the nearest rat and nothing is spent until standard confirmation" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 27, .y = 20 }, .{ .x = 23, .y = 22 } });
    press(g, .x);
    try std.testing.expectEqual(Mode.aim, g.mode);
    try std.testing.expectEqual(P{ .x = 23, .y = 22 }, g.mark);
    try std.testing.expect(!g.pool.get(3).?.awake);
    try std.testing.expect(!g.pool.get(3).?.hurt());
    press(g, CONFIRM);
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
    press(g, CONFIRM);
    const r = g.pool.get(2).?;
    try std.testing.expect(r.awake and r.hp > 0 and r.hp <= actor.row(.rat).hp - bow.DMG_LO);
    try std.testing.expectEqual(@as(i32, 26), r.at.x);
    press(g, .x);
    press(g, CONFIRM);
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
    std.debug.print("kicked barrel: {d} gold on the ground\n", .{g.ground.coins[0].amount});
    try std.testing.expect(!g.lv.hasBarrel(at));
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    try expectWithin(g.ground.coins[0].amount, GOLD_LO, GOLD_HI);
    try std.testing.expectEqual(P{ .x = 20, .y = 20 }, g.heroActor().?.at);
    nudge(g, .e);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    try expectWithin(g.gold, GOLD_LO, GOLD_HI);
    try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
}

test "a chest opens for gold once when approached, without a strike, and stays open" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    arena(g, from, &.{});
    g.lv.set(at, .chest);
    const minute = g.clock.minute;
    try std.testing.expectEqual(Move.open, heroMove(g, .e));
    try std.testing.expect(!g.lv.walkable(at));
    nudge(g, .e);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    try std.testing.expectEqual(from, g.heroActor().?.at);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    try expectWithin(g.ground.coins[0].amount, CHEST_GOLD_LO, CHEST_GOLD_HI);
    try std.testing.expect(CHEST_GOLD_LO > GOLD_HI);
    try std.testing.expect(g.glide[heroSlot(g).?].bump == null);
    const gold = g.ground.coins[0].amount;
    drawnOut(g);
    nudge(g, .e);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    nudge(g, .w);
    nudge(g, .e);
    try std.testing.expectEqual(gold, g.gold);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    std.debug.print("chest opened without attacking: {d} gold once, one turn, stays open on return\n", .{gold});
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
    press(g, CONFIRM);
    try std.testing.expect(!g.lv.hasBarrel(at));
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    try std.testing.expect(g.ground.coins[0].amount >= GOLD_LO);
}

test "the camera shows past the floor only under the hud, keeps the archer clear of it, and centres a small floor" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    begin(g, 4321);
    const map_w = @as(f32, @floatFromInt(grid.W)) * CELL_F;
    const map_h = @as(f32, @floatFromInt(grid.H)) * CELL_F + @as(f32, @floatFromInt(hud.COVER));
    for ([_]P{ .{ .x = WINDOW_W, .y = WINDOW_H }, .{ .x = 2560, .y = 1440 } }) |screen| {
        g.screen = screen;
        for ([_]P{ .{ .x = 0, .y = 0 }, .{ .x = grid.W - 1, .y = grid.H - 1 }, .{ .x = 48, .y = 32 } }) |p| {
            g.heroActor().?.at = p;
            snapGlide(g);
            const v = camWant(g);
            try std.testing.expect(v.x >= 0 and v.y >= 0);
            try std.testing.expect(v.x + @as(f32, @floatFromInt(screen.x)) <= map_w);
            try std.testing.expect(v.y + @as(f32, @floatFromInt(g.screen.y)) <= map_h);
            const foot = @as(f32, @floatFromInt((p.y + 1) * CELL)) - v.y;
            if (p.y == grid.H - 1) std.debug.print("{d}x{d}: bottom-row archer's foot at {d:.0}, hud top {d}\n", .{ screen.x, screen.y, foot, hud.Layout.of(screen, SKILLS_W).top });
            try std.testing.expect(foot <= @as(f32, @floatFromInt(hud.Layout.of(screen, SKILLS_W).top)));
        }
    }
    g.screen = .{ .x = grid.W * CELL + 200, .y = grid.H * CELL + hud.COVER + 100 };
    const v = camWant(g);
    try std.testing.expectEqual((map_w - @as(f32, @floatFromInt(g.screen.x))) * 0.5, v.x);
    try std.testing.expectEqual((map_h - @as(f32, @floatFromInt(g.screen.y))) * 0.5, v.y);
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
    g.pending = .{ .walk = .e };
    update(g, span * (1 - SPLASH_AT + 0.1));
    try std.testing.expect(g.heroActor().?.at.eq(to.add(mathx.Dir.e.delta())));
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
    var was = g.heroActor().?.at;
    while (t < 1.5) : (t += dt) {
        walkFrame(g, dt, .e);
        if (!g.heroActor().?.at.eq(was)) steps += 1;
        was = g.heroActor().?.at;
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
        const start = g.heroActor().?.at;
        g.paused_from = .play;
        g.mark = start;
        if (case.mode == .aim) aiming(g, .a, .juke);
        g.mode = case.mode;
        walkFor(g, 0.6, .e);
        g.st.pressed.insert(case.close);
        update(g, dt);
        g.st.pressed = .initEmpty();
        try std.testing.expectEqual(Mode.play, g.mode);
        walkFor(g, 1, .e);
        try std.testing.expect(g.heroActor().?.at.eq(start));
        walkFrame(g, dt, null);
        for (0..30) |_| {
            walkFrame(g, dt, .e);
        }
        try std.testing.expect(!g.heroActor().?.at.eq(start));
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
        pressWalking(g, case.open, case.way);
        try std.testing.expect(g.mode != .play);
        const menu_at = g.pause_menu.at;
        const spot = g.inspecting;
        walkFor(g, 1, case.way);
        try std.testing.expectEqual(menu_at, g.pause_menu.at);
        try std.testing.expectEqual(spot, g.inspecting);
        walkFrame(g, dt, null);
        for (0..30) |_| walkFrame(g, dt, case.way);
        try std.testing.expect(g.pause_menu.at != menu_at or !std.meta.eql(spot, g.inspecting));
        g.mode = .play;
    }
}

test "a way held into or out of the character page moves nothing there until let go" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const dt = TEST_DT;
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.st = .{};
    openPause(g);
    g.pause_menu.at = @intFromEnum(PauseRow.character);
    for (0..10) |_| walkFrame(g, dt, .s);
    g.pause_menu.at = @intFromEnum(PauseRow.character);
    pressWalking(g, menu.CONFIRM, .s);
    try std.testing.expectEqual(PausePage.character, g.pause_page);
    walkFor(g, 1, .s);
    try std.testing.expect(g.character.tabs);
    pressWalking(g, menu.BACK, .s);
    try std.testing.expectEqual(PausePage.main, g.pause_page);
    walkFor(g, 1, .s);
    try std.testing.expectEqual(@as(usize, @intFromEnum(PauseRow.character)), g.pause_menu.at);
    std.debug.print("held walk: the character page and the pause menu it returns to stayed put with the way held\n", .{});
}

test "a way held into or out of the skill picker moves neither cursor until let go" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.st = .{};
    openBinds(g);
    for (0..10) |_| walkFrame(g, TEST_DT, .e);
    pressWalking(g, CHANGE, .e);
    const picked = g.binds.menu.pick;
    const slot = g.binds.slot();
    walkFor(g, 1, .e);
    try std.testing.expectEqual(picked, g.binds.menu.pick);
    pressWalking(g, menu.BACK, .e);
    try std.testing.expect(g.binds.menu == .browse);
    walkFor(g, 1, .e);
    try std.testing.expectEqual(slot, g.binds.slot());
    std.debug.print("held walk: the skill picker and the slot it returns to stayed put with the way held\n", .{});
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
    const at = g.heroActor().?.at;
    g.st = .{ .walk = .e };
    update(g, 0);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    g.st = .{};
    var waited: f32 = 0;
    while (g.heroActor().?.at.eq(at) and waited < 1) : (waited += TEST_DT) update(g, TEST_DT);
    std.debug.print("a walk pressed mid-turn steps {d:.3} s later\n", .{waited});
    try std.testing.expect(!g.heroActor().?.at.eq(at));
    try std.testing.expectApproxEqAbs(STAGGER_S * 2 + SLIDE_S, waited, TEST_TOL);
}

test "an arrow's rat flashes when the arrow gets there, not when the hit resolves" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    press(g, .x);
    press(g, CONFIRM);
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
    press(g, CONFIRM);
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
    press(g, CONFIRM);
    const rat = actor.Pool.slot(2);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(2));
    try std.testing.expect(drawnAt(g, rat) != null);
    const t = framesUntil(g, rat, gone);
    const lands = flown(bow.RANGE - 1);
    std.debug.print("a rat an arrow kills {d} cells out is drawn {d:.3} s on; the arrow lands at {d:.3} s\n", .{ bow.RANGE, t, lands });
    try std.testing.expectApproxEqAbs(lands + fx.FLASH_S, t, TEST_TOL);
}

test "a long frame finishes a killing flash before the next turn is ready" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    press(g, .x);
    press(g, CONFIRM);
    g.st = .{};
    update(g, g.busy + 0.01);
    try std.testing.expect(quiet(g));
    try std.testing.expect(drawnAt(g, actor.Pool.slot(2)) == null);
    std.debug.print("long frame: killing flash finished when play becomes ready\n", .{});
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
    g.heroActor().?.hp = 1;
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
    try std.testing.expect(g.heroActor().?.hurt());
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
    g.rng = meleeThenBites(g, 1);
    nudge(g, .e);
    const hero = heroSlot(g).?;
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.pool.get(2).?.hurt() and g.heroActor().?.hurt());
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
        g.heroActor().?.hp = actor.row(.rat).blow.strike.hi + 1;
        endTurn(g);
        var kills: usize = 0;
        for (g.owed) |o| {
            if ((o.bit orelse continue) == .kill) kills += 1;
        }
        try std.testing.expectEqual(@as(usize, if (g.mode == .dead) 1 else 0), kills);
        if (g.mode != .dead) continue;
        deaths += 1;
        for (g.owed) |o| {
            if ((o.bit orelse continue) == .hurt) hurts += 1;
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
        try std.testing.expectEqual(c.corner(p), c.px(cellPx(p)));
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
    g.heroActor().?.hp = 1;
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
        try std.testing.expect(!g.heroActor().?.hurt());
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
    press(g, CONFIRM);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(id));
    try std.testing.expectEqual(@as(usize, 1), g.kills);
    const per = gas.harm(actor.row(HERO).hp);
    var first: ?usize = null;
    for (1..11) |turn| {
        const before = g.heroActor().?.hp;
        use(g, .wait);
        const lost = before - g.heroActor().?.hp;
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
    press(g, CONFIRM);
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
    press(g, CONFIRM);
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
    press(g, CONFIRM);
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
    press(g, CONFIRM);
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
    press(g, CONFIRM);
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
    g.heroActor().?.hp = low;
    catchUp(g);
    g.rng = bitesRng(g, .rat, &.{true});
    nudge(g, .e);
    const hero = heroSlot(g).?;
    try std.testing.expect(g.heroActor().?.hp < low);
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
    press(g, CONFIRM);
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
    press(g, CONFIRM);
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
        g.heroActor().?.hp = 1000;
        g.heroActor().?.max = 1000;
        var rng = mathx.Rng.init(f);
        for (0..300) |_| {
            if (g.mode == .dead) break;
            const n = g.pool.n;
            press(g, .x);
            if (g.mode == .aim) press(g, CONFIRM) else nudge(g, mathx.ALL_DIRS[rng.below(mathx.ALL_DIRS.len)]);
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
    const hp = g.heroActor().?.hp;
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
    press(g, CONFIRM);
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
    press(g, CONFIRM);
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
    g.rng = meleeThenBites(g, 2);
    update(g, 0);
    const t = framesUntil(g, heroSlot(g).?, reddened);
    std.debug.print("a kick due {d:.3} s late: the first bite lands {d:.3} s on\n", .{ late, t });
    try std.testing.expectApproxEqAbs(2 * BUMP_LANDS + STAGGER_S - late, t, TEST_TOL);
}

test "a flask pressed mid-walk is drunk once the step is drawn, ahead of the held walk" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    arena(g, at, &.{});
    g.heroActor().?.hp -= 5;
    const by = boundTo(g, .life_flask);
    g.busy = GLIDE_S;
    g.st = .{ .walk = .e, .pressed = .initOne(by.by), .down = .initOne(by.by) };
    if (by.set == .secondary) g.st.down.insert(g.bar.modifier.?);
    update(g, 0);
    try std.testing.expectEqual(skillbar.Act.life_flask, g.pending.?.skill.act);
    g.st = .{ .walk = .e };
    update(g, 0);
    try std.testing.expectEqual(skillbar.Act.life_flask, g.pending.?.skill.act);
    const clock = g.clock;
    g.st = .{ .walk = .e };
    update(g, GLIDE_S + mathx.FRAME_DT);
    try std.testing.expect(g.pending == null);
    try std.testing.expectEqual(flask.CHARGES / flask.USE - 1, g.flasks.get(.life).uses());
    try std.testing.expect(!std.meta.eql(clock, g.clock));
    try std.testing.expect(g.heroActor().?.at.eq(at));
    std.debug.print("flask queued behind a held walk: drunk on the first quiet frame, hero still at {d},{d}\n", .{ at.x, at.y });
}

test "losing focus discards a queued walk while the current turn finishes drawing" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    arena(g, at, &.{});
    g.busy = GLIDE_S;
    g.st = .{ .walk = .e };
    update(g, 0);
    try std.testing.expectEqual(@as(?Queued, .{ .walk = .e }), g.pending);
    const minute = g.clock.minute;
    g.st = .{ .focused = false };
    update(g, GLIDE_S + mathx.FRAME_DT);
    try std.testing.expect(quiet(g) and g.pending == null);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    try std.testing.expectEqual(minute, g.clock.minute);
    g.st = .{};
    update(g, mathx.FRAME_DT);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    std.debug.print("focus loss: queued walk discarded, presentation finishes, no extra turn on return\n", .{});
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
    try std.testing.expect(g.heroActor().?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.vignette.alpha());
    const t = framesUntil(g, heroSlot(g).?, reddened);
    std.debug.print("a bite bumped a stagger into the turn reddens the view {d:.3} s in\n", .{t});
    try std.testing.expectApproxEqAbs(STAGGER_S + BUMP_LANDS, t, TEST_TOL);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.addGas(.{ .x = 20, .y = 20 }, TEST_GAS);
    use(g, .wait);
    try std.testing.expect(g.heroActor().?.hurt());
    try std.testing.expect(framesUntil(g, heroSlot(g).?, reddened) < TEST_TOL);
}

test "gas left to eat at the archer kills it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.addGas(.{ .x = 20, .y = 20 }, TEST_GAS);
    g.heroActor().?.hp = 1;
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
    g.heroActor().?.hp = 2;
    for (0..20) |_| use(g, .wait);
    std.debug.print("an unkillable archer after 20 turns in gas between two rats: {d} hp\n", .{g.heroActor().?.hp});
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(@as(i32, 1), g.heroActor().?.hp);
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
        beginMap(g, w);
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
    beginMap(g, w);
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    _ = g.pool.damage(&g.lv, g.hero, 5);
    nudge(g, .e);
    nudge(g, .e);
    try std.testing.expect(g.travel != null);
    idle(g);
    try std.testing.expectEqual(cave, g.node);
    try std.testing.expectEqual(P{ .x = 30, .y = 30 }, g.heroActor().?.at);
    try std.testing.expectEqual(actor.row(HERO).hp - 5, g.heroActor().?.hp);
    try std.testing.expect(g.pool.n > 1);
    try std.testing.expect(g.visits[room].ground.gold(.{ .x = 12, .y = 5 }, 17));
    const off = found: for ([_]bool{ false, true }) |diagonal| {
        for (mathx.ALL_DIRS) |d| {
            if (d.diagonal() == diagonal and g.lv.stepOk(g.heroActor().?.at, d, g.hero)) break :found d;
        }
    } else return error.DoorWalledIn;
    nudge(g, off);
    nudge(g, off.opposite());
    idle(g);
    try std.testing.expectEqual(room, g.node);
    try std.testing.expectEqual(@as(i32, 17), g.gold);
    try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
    try std.testing.expectEqual(P{ .x = 12, .y = 5 }, g.heroActor().?.at);
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
    beginMap(g, w);
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
    try std.testing.expect(!g.heroActor().?.at.eq(.{ .x = 11, .y = 5 }));
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

test "the character screens return through pause without changing the fight or consuming turns" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const clock = g.clock;
    const hp = g.heroActor().?.hp;
    const mana = g.mana;
    press(g, PAUSE);
    g.pause_menu.at = @intFromEnum(PauseRow.character);
    press(g, CONFIRM);
    try std.testing.expectEqual(PausePage.character, g.pause_page);
    g.character.page = .inventory;
    g.character.cursor = 8;
    g.character.tabs = false;
    press(g, CONFIRM);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(hp, g.heroActor().?.hp);
    try std.testing.expectEqual(mana, g.mana);
    try std.testing.expectEqual(P{ .x = 26, .y = 20 }, g.pool.items[1].at);
    press(g, PAUSE);
    try std.testing.expect(g.character.tabs);
    try std.testing.expectEqual(PausePage.character, g.pause_page);
    press(g, PAUSE);
    try std.testing.expectEqual(PausePage.main, g.pause_page);
    try std.testing.expectEqual(Mode.pause, g.mode);
    press(g, PAUSE);
    try std.testing.expectEqual(Mode.play, g.mode);
    std.debug.print("character screens: empty inventory confirmed without a turn or combat change; back closes one layer at a time\n", .{});
}

test "an arena restart restores its selected opponent and hero" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const map = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(map);
    spar.author(map, .bloat);
    beginMap(g, map);
    _ = g.pool.damage(&g.lv, 2, 100);
    _ = g.pool.damage(&g.lv, g.hero, 3);
    g.mana = 0;
    restart(g);
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    try std.testing.expectEqual(actor.Kind.bloat, g.pool.items[1].kind);
    try std.testing.expect(g.pool.items[1].alive);
    try std.testing.expectEqual(actor.row(HERO).hp, g.heroActor().?.hp);
    try std.testing.expectEqual(manaMax(g), g.mana);
    try std.testing.expectEqual(spar.HERO, g.heroActor().?.at);
    std.debug.print("arena retry: bloat and hero restored at their starting positions with full resources\n", .{});
}

test "Debug reveal toggles map terrain without spending turns or changing explored cells" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const far = P{ .x = 60, .y = 40 };
    arena(g, .{ .x = 20, .y = 20 }, &.{far});
    const seen = g.lv.seen;
    const lit = g.lv.lit;
    const clock = g.clock;
    const rng = g.rng;
    try std.testing.expect(!terrainSeen(g, far));
    press(g, PAUSE);
    for (0..@intFromEnum(PauseRow.debug)) |_| nudge(g, .s);
    press(g, CONFIRM);
    try std.testing.expectEqual(PausePage.debug, g.pause_page);
    try std.testing.expectEqual(Mode.pause, g.mode);
    nudge(g, .s);
    for ([_]bool{ true, false }) |enabled| {
        press(g, CONFIRM);
        try std.testing.expectEqual(enabled, g.light.reveal_map);
        try std.testing.expectEqual(enabled, terrainSeen(g, far));
        try std.testing.expectEqual(@as(f32, if (enabled) 1 else 0), g.light.memory[grid.Level.idx(far)]);
        try std.testing.expectEqualSlices(bool, &seen, &g.lv.seen);
        try std.testing.expectEqualSlices(bool, &lit, &g.lv.lit);
        try std.testing.expectEqual(clock, g.clock);
        try std.testing.expectEqual(rng, g.rng);
        try std.testing.expect(drawnAt(g, actor.Pool.slot(2)) == null);
    }
    press(g, BACK);
    try std.testing.expectEqual(PausePage.main, g.pause_page);
    try std.testing.expectEqual(Mode.pause, g.mode);
    press(g, PAUSE);
    try std.testing.expectEqual(Mode.play, g.mode);
    std.debug.print("Debug reveal: on/off restores fog, all {d} exploration cells unchanged; back exits one menu at a time\n", .{grid.CELLS});
}

test "Debug restart begins the map anew and clears visited nodes" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const map = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(map);
    map.* = .{};
    _ = map.add(.{ .procgen = .{} });
    _ = map.add(.{ .procgen = .{} });
    beginMapAt(g, map, .{ .node = 1, .at = grid.MIDDLE }, 12);
    g.visited.set(1);
    g.gold = 99;
    g.heroActor().?.hp = 1;
    press(g, PAUSE);
    for (0..@intFromEnum(PauseRow.debug)) |_| nudge(g, .s);
    press(g, CONFIRM);
    try std.testing.expectEqual(PausePage.debug, g.pause_page);
    press(g, CONFIRM);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(map.start.node, g.node);
    try std.testing.expectEqual(@as(usize, 0), g.visited.count());
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    try std.testing.expectEqual(heroRow(g).hp, g.heroActor().?.hp);
    try std.testing.expect(g.seed != 12);
    std.debug.print("Debug restart: returns to map start, rerolls seed, restores hero and clears visited nodes and gold\n", .{});
}

test "a pib's landed stab bleeds the archer about three times in ten, drawn once the stab lands" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var bled: usize = 0;
    var landed: usize = 0;
    for (0..TRIES) |i| {
        arena(g, .{ .x = 20, .y = 20 }, &.{});
        _ = spawnAt(g, .pib, .{ .x = 21, .y = 20 }, true);
        g.rng = mathx.Rng.init(i);
        use(g, .wait);
        const h = g.heroActor().?;
        if (!h.hurt()) {
            try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
            continue;
        }
        landed += 1;
        if (h.bleed.turns == 0) continue;
        bled += 1;
        try std.testing.expectEqual(bleeding.TURNS, h.bleed.turns);
        try std.testing.expectEqual(@as(u8, 0), g.pictured[heroSlot(g).?].status.get(.bleeding));
        drawnOut(g);
        try std.testing.expectEqual(bleeding.TURNS, g.pictured[heroSlot(g).?].status.get(.bleeding));
    }
    std.debug.print("a pib beside the archer: {d} stabs, {d} landed, {d} bleeds\n", .{ TRIES, landed, bled });
    try std.testing.expect(landed > 0 and landed < TRIES);
    try std.testing.expect(aboutRateOf(bled, landed, mathx.fraction(actor.row(.pib).blow.strike.bleeds)));
}

test "a bleed costs the archer 1 a turn standing and 2 a turn it steps, and stops after five" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{});
    const h = g.heroActor().?;
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
    wound(g, 2, .{ .dmg = actor.row(.rat).hp }, SHOOT, .{ .from = hero, .wait = 0.2 });
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
        const full = g.heroActor().?.hp;
        for (0..actor.FLEE_TURNS) |_| {
            endTurn(g);
            if (!g.pool.get(id).?.at.eq(end)) moves += 1;
        }
        if (hero.x == 17) strikes = full - g.heroActor().?.hp else try std.testing.expectEqual(full, g.heroActor().?.hp);
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

test "ground pressure preserves closed chest rewards and reserves every possible foe drop" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    arena(g, at, &.{});
    const chest = at.add(.{ .x = 1, .y = 0 });
    g.lv.set(chest, .chest);
    for (0..items.GROUND_MAX - actor.MAX) |_| try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    const before = g.clock;
    const rng = g.loot_rng;
    heroStep(g, .e, 0);
    try std.testing.expectEqualDeep(before, g.clock);
    try std.testing.expectEqualDeep(rng, g.loot_rng);
    try std.testing.expect(g.lv.at(chest).opened() != null);
    for (0..actor.MAX) |_| try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expectEqual(items.GROUND_MAX, g.ground.n);
    std.debug.print("full ground: chest and turn untouched, {d} foe rewards reserved\n", .{actor.MAX});
}

test "new runs gate class skills; underfoot and adjacent loot commit exactly one turn; gold collects on movement" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    for (heroes.CLASSES) |c| {
        g.class = c;
        begin(g, 123);
        for (progress.skills(c)) |s| try std.testing.expectEqual(s.initial, g.growth.unlocked(s.act));
        for (skillbar.SETS) |set| for (skillbar.SLOTS) |button| {
            if (g.bar.at(.{ .set = set, .button = button })) |act| try std.testing.expect(g.growth.unlocked(act));
        };
    }
    heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    const at = g.heroActor().?.at;
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .cap, .mods = .{ .{ .kind = .life, .value = 6 }, null } }, .at = at }));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = at.add(.{ .x = 1, .y = 0 }) }));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .boots }, .at = at.add(.{ .x = 2, .y = 0 }) }));
    const clock = g.clock;
    g.st = .{ .interact = true, .pressed = .initOne(CONFIRM) };
    update(g, 0);
    try std.testing.expectEqual(Mode.pause, g.mode);
    try std.testing.expect(g.character.prompt == null);
    try std.testing.expectEqual(clock, g.clock);
    var nearby: NearbyBuf = undefined;
    try std.testing.expectEqual(@as(usize, 2), nearbyOf(g, &nearby).len);
    characterCommand(g, .{ .pickup = 0 });
    try std.testing.expectEqual(clock.minute + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(@as(usize, 1), g.inventory.n);
    drawnOut(g);
    const hp = g.heroActor().?.hp;
    const minute = g.clock.minute;
    characterCommand(g, .{ .equip = .{ .index = 0, .slot = .helm } });
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(hp, g.heroActor().?.hp);
    try std.testing.expectEqual(hp + 6, g.heroActor().?.max);
    drawnOut(g);
    try std.testing.expect(g.ground.gold(at.add(.{ .x = 1, .y = 0 }), 17));
    const before = g.clock.minute;
    nudge(g, .e);
    try std.testing.expectEqual(@as(i32, 17), g.gold);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(@as(usize, 1), g.ground.n - 1);
    std.debug.print("progression: 3 starter kits, underfoot/adjacent menu, one-turn item actions, no equip healing, automatic gold\n", .{});
}

test "walking over items logs each item once per arrival without picking it up" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.name = heroes.Name.of("Arwen");
    g.log = .{};
    const at = P{ .x = 21, .y = 20 };
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .cap }, .at = at }));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .boots }, .at = .{ .x = 22, .y = 20 } }));
    const before = g.clock.minute;
    nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 2), g.log.n);
    try std.testing.expectEqualStrings("Arwen steps over Leather cap.", g.log.line(1).?);
    try std.testing.expectEqualStrings("Arwen steps over Copper ring.", g.log.line(0).?);
    try std.testing.expectEqual(@as(usize, 2), g.log.held);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(@as(usize, 3), g.ground.n);
    try std.testing.expectEqual(@as(usize, 0), g.inventory.n);
    drawnOut(g);
    try std.testing.expectEqual(@as(usize, 0), g.log.held);
    for (0..30) |_| update(g, TEST_DT);
    try std.testing.expectEqual(@as(usize, 2), g.log.n);
    g.lv.set(.{ .x = 22, .y = 20 }, .wall);
    nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 2), g.log.n);
    nudge(g, .w);
    nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 4), g.log.n);
    std.debug.print("underfoot loot: 2 items named per arrival, no idle/blocked repeats, no pickup or extra turn\n", .{});
}

test "interact pressed mid-turn waits for quiet instead of queuing its button's skill; the turn's log lines wait too" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = g.heroActor().?.at }));
    g.busy = GLIDE_S;
    g.log.say("Said as the turn resolved.", .{});
    g.st = .{ .interact = true, .pressed = .initOne(CONFIRM), .down = .initOne(CONFIRM) };
    update(g, 0);
    try std.testing.expectEqual(@as(?Queued, .interact), g.pending);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(@as(usize, 1), g.log.held);
    g.st = .{ .walk = .e };
    update(g, 0);
    try std.testing.expectEqual(@as(?Queued, .interact), g.pending);
    g.st = .{};
    update(g, GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(Mode.pause, g.mode);
    try std.testing.expectEqual(book.Page.nearby, g.character.page);
    try std.testing.expectEqual(@as(usize, 0), g.log.held);
    std.debug.print("interact mid-turn: queued, opened nearby on the quiet frame; held log line released then\n", .{});
}

test "the experience bar holds a turn's experience until the turn is drawn, then fills toward it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.busy = GLIDE_S;
    _ = g.growth.gain(progress.xpOf(.rat) * 3);
    update(g, 0);
    try std.testing.expectEqual(@as(f32, 0), g.xp_shown);
    update(g, GLIDE_S + mathx.FRAME_DT);
    const aim = xpLevels(g);
    try std.testing.expect(g.xp_shown > 0 and g.xp_shown < aim);
    var t: f32 = 0;
    while (g.xp_shown != aim and t < 5) : (t += TEST_DT) update(g, TEST_DT);
    std.debug.print("experience bar: {d:.3} of a level drawn {d:.2} s after the turn\n", .{ g.xp_shown, t });
    try std.testing.expect(t > 1 and t < 5);
}

test "a level reached exactly empties the bar, and the book shows it only once the turn is drawn" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.busy = GLIDE_S;
    _ = g.growth.gain(@intCast(g.growth.needed()));
    g.gold += 7;
    update(g, 0);
    var nearby: NearbyBuf = undefined;
    const held = bookView(g, &nearby);
    try std.testing.expectEqual(@as(u16, 1), held.growth.level);
    try std.testing.expectEqual(@as(i32, 0), held.gold);
    var t: f32 = 0;
    while (g.xp_shown != xpLevels(g) and t < 10) : (t += TEST_DT) update(g, TEST_DT);
    try std.testing.expectEqual(@as(f32, 1), g.xp_shown);
    try std.testing.expectEqual(@as(u16, 2), bookView(g, &nearby).growth.level);
    try std.testing.expectEqual(@as(i32, 7), bookView(g, &nearby).gold);
    std.debug.print("exact level-up: bar fill {d} after {d:.2} s\n", .{ g.xp_shown - @floor(g.xp_shown), t });
}

test "interact during door travel stays an interaction on arrival" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    const a = w.add(.{ .bespoke = .{} }).?;
    const b = w.add(.{ .bespoke = .{} }).?;
    for ([_]usize{ a, b }) |n| corridor(&w.node[n].plan.bespoke);
    const da = w.addDoor(a, .{ .x = 2, .y = 5 }).?;
    const db = w.addDoor(b, .{ .x = 11, .y = 5 }).?;
    w.link(.{ .node = a, .door = da }, .{ .node = b, .door = db });
    w.start = .{ .node = a, .at = .{ .x = 3, .y = 5 } };
    beginMapAt(g, w, w.start, 123);
    nudge(g, .w);
    const minute = g.clock.minute;
    try std.testing.expect(g.travel != null);
    g.st = .{ .interact = true, .pressed = .initOne(CONFIRM) };
    update(g, 0);
    try std.testing.expectEqual(@as(?Queued, .interact), g.pending);
    g.st = .{ .walk = .w };
    update(g, 0);
    try std.testing.expectEqual(@as(?Queued, .interact), g.pending);
    g.st = .{};
    update(g, GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.node);
    update(g, mathx.FRAME_DT);
    try std.testing.expectEqual(Mode.pause, g.mode);
    try std.testing.expectEqual(book.Page.nearby, g.character.page);
    try std.testing.expectEqual(minute, g.clock.minute);
    std.debug.print("door interact: survives travel and walking repeats, opens nearby without an extra turn\n", .{});
}

test "charge retreats down an empty line and passive and skill allocations spend points without turns" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{});
    const clock = g.clock;
    g.growth = progress.State.of(.knight);
    _ = g.growth.gain(40);
    for (progress.NODES, 0..) |_, i| if (g.growth.available(i)) {
        characterCommand(g, .{ .passive = i });
        break;
    };
    try std.testing.expectEqual(@as(u16, 0), g.growth.passive_points);
    characterCommand(g, .{ .skill = .cleave });
    try std.testing.expectEqual(@as(u8, 1), g.growth.ranks.get(.cleave));
    try std.testing.expectEqual(@as(u16, 0), g.growth.active_points);
    try std.testing.expectEqual(clock, g.clock);
    drawnOut(g);
    use(g, .charge);
    try std.testing.expectEqual(Mode.aim, g.mode);
    g.mark = .{ .x = 17, .y = 20 };
    confirmAim(g);
    try std.testing.expectEqual(P{ .x = 17, .y = 20 }, g.heroActor().?.at);
    try std.testing.expectEqual(clock.minute + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(manaAfter(g, .charge), g.mana);
    std.debug.print("charge: empty retreat landing; allocations consume points and no turn\n", .{});
}

test "attribute damage and critical rolls reach melee, arrows, mixed arrows and resisted spells" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const cases = .{
        .{ heroes.Class.knight, skillbar.Act.charge },
        .{ heroes.Class.archer, skillbar.Act.shoot },
        .{ heroes.Class.archer, skillbar.Act.burning_arrow },
        .{ heroes.Class.wizard, skillbar.Act.spark },
    };
    const seeds = 64;
    inline for (cases) |c| {
        var criticals: usize = 0;
        for (0..seeds) |seed| {
            heroArena(g, c[0], .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
            const target = g.pool.get(2).?;
            toughen(target);
            target.resists = .initFill(50);
            g.rng = mathx.Rng.init(seed);
            var expected_rng = g.rng;
            var raw = damage.Damage{};
            switch (c[1]) {
                .charge => raw.physical = charge.BASE.roll(&expected_rng),
                .shoot, .burning_arrow => {
                    raw.physical = bow.BASE.roll(&expected_rng);
                    if (c[1] == .burning_arrow) raw.elements.set(burning.ELEMENT, burning.BASE.roll(&expected_rng));
                },
                .spark => raw.elements.set(spark.ELEMENT, spark.BASE.roll(&expected_rng)),
                else => unreachable,
            }
            const critical = c[0].attrs().crits(&expected_rng);
            criticals += @intFromBool(critical);
            const expected = c[0].attrs().blow(comptime c[1].style().?, raw, critical, &expected_rng).total(target.resists);
            use(g, c[1]);
            try std.testing.expectEqual(Mode.aim, g.mode);
            confirmAim(g);
            try std.testing.expectEqual(expected, TEST_HP - target.hp);
        }
        try std.testing.expect(criticals > 0 and criticals < seeds);
        std.debug.print("{s}: {d} exact damage checks, {d} criticals, resistance applied after scaling\n", .{ c[1].name(), seeds, criticals });
    }
}

test "live skill tables include equipped damage, ranks and the actual targeting range" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.inventory.gear.slots.set(.right_hand, .{ .kind = .bow });
    g.growth.ranks.set(.shoot, 3);
    g.bar.bind(.{ .set = .primary, .button = skillbar.SLOTS[0] }, .shoot);
    var title: [TIP_TITLE_MAX]u8 = undefined;
    var body: [menu.NOTE_MAX * 2]u8 = undefined;
    const tip = tipOf(g, .{ .slot = 0 }, &title, &body);
    try std.testing.expect(std.mem.indexOf(u8, tip.body, "Range|9") != null);
    try std.testing.expect(std.mem.indexOf(u8, tip.body, "Physical|3-8") != null);
    try std.testing.expectEqual(@as(i32, 1), skillbar.Act.cleave.reach());
    g.bar.bind(.{ .set = .primary, .button = skillbar.SLOTS[0] }, .secondary);
    try std.testing.expect(std.mem.indexOf(u8, tipOf(g, .{ .slot = 0 }, &title, &body).body, "Turns|0") != null);
    std.debug.print("live tooltips: equipment, rank damage, bow/swing ranges and modifier turn cost checked\n", .{});
}

test "dodging spends the foe turn without damage, bleeding or mana shield loss" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    var checked: usize = 0;
    for (heroes.CLASSES) |c| {
        for ([_]bool{ false, true }) |warded| {
            for ([_]bool{ false, true }) |dodged| {
                heroArena(g, c, .{ .x = 20, .y = 20 }, &.{});
                _ = spawnAt(g, .pib, .{ .x = 21, .y = 20 }, true);
                const h = g.heroActor().?;
                if (warded) h.ward.raise();
                const hp = h.hp;
                const clock = g.clock;
                g.rng = bitesRng(g, .pib, &.{!dodged});
                use(g, .wait);
                try std.testing.expect(!std.meta.eql(clock, g.clock));
                if (dodged) {
                    try std.testing.expectEqual(hp, h.hp);
                    try std.testing.expectEqual(manaMax(g), g.mana);
                    try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
                } else if (warded) {
                    try std.testing.expectEqual(hp, h.hp);
                    try std.testing.expect(g.mana < manaMax(g));
                } else try std.testing.expect(h.hp < hp);
                g.st = .{};
                update(g, TEST_DT);
                try std.testing.expect(g.busy > 0);
                drawnOut(g);
                try std.testing.expectEqual(h.hp, g.pictured[heroSlot(g).?].hp);
                try std.testing.expectEqual(g.mana, manaShown(g));
                if (dodged) try std.testing.expectEqual(@as(f32, 0), g.fx.flashOf(heroSlot(g).?));
                checked += 1;
            }
        }
    }
    std.debug.print("dodge: {d} class/hit/shield cases, misses still animate and spend the foe turn\n", .{checked});
}

/// An RNG matching `knock` whose next shield bash stuns, or does not.
fn bashRng(stuns: bool) mathx.Rng {
    const Stuns = struct {
        stuns: bool,
        fn holds(s: @This(), rng: *mathx.Rng) bool {
            _ = scaled(rng, heroes.Class.knight.attrs(), .melee, rollRaw(rng, .shield_bash, basesOf(&.{}, .shield_bash), true));
            return bash.procs(rng, 0) == s.stuns;
        }
    };
    return rngWhere(Stuns{ .stuns = stuns });
}

test "each spark that stuns costs a chasing rat its next turn, and mana is spent on confirmation" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    try std.testing.expectEqual(actor.Kind.wizard, g.heroActor().?.kind);
    const rat = g.pool.get(2).?;
    rat.awake = true;
    toughen(rat);
    for (0..2) |_| {
        press(g, .x);
        try std.testing.expectEqual(Mode.aim, g.mode);
        g.rng = procRng(g, .spark, 1);
        press(g, CONFIRM);
        drawnOut(g);
    }
    const dealt = TEST_HP - rat.hp;
    try expectDamage(g, .spark, dealt, &.{ .{ spark.LIGHTNING_LO, spark.LIGHTNING_HI }, .{ spark.LIGHTNING_LO, spark.LIGHTNING_HI } });
    try std.testing.expectEqual(@as(i32, 26), rat.at.x);
    try std.testing.expectEqual(manaMax(g) - 2 * (spark.COST - heroes.MANA_REGEN), g.mana);
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
        const hp = g.heroActor().?.hp;
        press(g, .a);
        try std.testing.expectEqual(Mode.aim, g.mode);
        try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mark);
        g.rng = bashRng(stuns);
        press(g, CONFIRM);
        const dealt = TEST_HP - rat.hp;
        try expectDamage(g, .shield_bash, dealt, &.{.{ bash.DMG_LO, bash.DMG_HI }});
        try std.testing.expectEqual(hp, g.heroActor().?.hp);
        try std.testing.expectEqual(manaAfter(g, .shield_bash), g.mana);
        try std.testing.expectEqual(bash.COOLDOWN - 1, g.cooldown.get(.shield_bash));
        x.* = rat.at.x;
        drawnOut(g);
        try std.testing.expect(samePx(cellPx(rat.at), g.glide[actor.Pool.slot(2)].now()));
    }
    try std.testing.expectEqual(@as(i32, 22), landed[0]);
    try std.testing.expectEqual(@as(i32, 21), landed[1]);
    heroArena(g, .knight, from, &.{.{ .x = 21, .y = 20 }});
    g.lv.set(.{ .x = 22, .y = 20 }, .wall);
    press(g, .a);
    g.rng = bashRng(true);
    press(g, CONFIRM);
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
    press(g, .a);
    g.rng = bashRng(false);
    press(g, CONFIRM);
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
    press(g, CONFIRM);
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
    press(g, CONFIRM);
    var hit: usize = 0;
    for (g.pool.slice()[1..], 0..) |a, i| {
        const lost = TEST_HP - a.hp;
        if (i < arc.len) {
            try expectDamage(g, .cleave, lost, &.{.{ cleave.DMG_LO, cleave.DMG_HI }});
            hit += 1;
        } else try std.testing.expectEqual(@as(i32, 0), lost);
    }
    try std.testing.expectEqual(manaAfter(g, .cleave), g.mana);
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
    press(g, CONFIRM);
    try std.testing.expectEqual(g.mark, g.heroActor().?.at);
    try std.testing.expect(g.glide[actor.Pool.slot(2)].t <= -STAGGER_S + TEST_TOL);
    try std.testing.expect(!std.meta.eql(hour, g.clock));
    try std.testing.expectEqual(@as(i32, 29), rat.at.x);
    try std.testing.expectEqual(manaAfter(g, .blink), g.mana);
    try std.testing.expectEqual(blink.COOLDOWN - 1, g.cooldown.get(.blink));
    std.debug.print("blink: {d} tiles in a turn; the rat stepped once\n", .{blink.RANGE});
}

test "a flask drink takes a turn, recovers over the next turns, and kills refill its charges" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    const h = g.heroActor().?;
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
    try std.testing.expectEqual(@min(manaMax(g), flask.MANA_GAIN + heroes.MANA_REGEN * (flask.TURNS + flask.TURNS + 2)), g.mana);
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
    const h = g.heroActor().?;
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
    press(g, CONFIRM);
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

fn manaAfter(g: *const Game, act: skillbar.Act) i32 {
    return manaMax(g) - g.growth.cost(act) + heroes.MANA_REGEN;
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
    try expectDamage(g, .pinning_shot, dealt, &.{.{ bow.DMG_LO, bow.DMG_HI }});
    try std.testing.expectEqual(manaAfter(g, .pinning_shot), g.mana);
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
    const hp = g.heroActor().?.hp;
    g.rng = bitesRng(g, .rat, &.{true});
    use(g, .wait);
    try std.testing.expect(g.heroActor().?.hp < hp);
    try std.testing.expectEqual(@as(i32, 21), biter.at.x);
    std.debug.print("pinning shot: {d} damage, the rat held {d} turns, then walked on; pinned beside the hero it bit for {d}\n", .{ dealt, held, hp - g.heroActor().?.hp });
}

test "a barbed arrow always opens a bleed on a body it leaves alive" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const rat = g.pool.get(2).?;
    toughen(rat);
    pressHolding(g, .b, &.{.lb});
    try std.testing.expectEqual(Mode.aim, g.mode);
    press(g, CONFIRM);
    const dealt = TEST_HP - rat.hp;
    try expectDamage(g, .barbed_arrow, dealt, &.{.{ bow.DMG_LO, bow.DMG_HI }});
    try std.testing.expectEqual(bleeding.TURNS, rat.bleed.turns);
    try std.testing.expectEqual(manaAfter(g, .barbed_arrow), g.mana);
    use(g, .wait);
    try std.testing.expect(TEST_HP - rat.hp > dealt);
    std.debug.print("barbed arrow: {d} damage, a {d}-turn bleed, which bled {d} the next turn\n", .{ dealt, bleeding.TURNS, TEST_HP - rat.hp - dealt });
}

test "a frost nova freezes every foe within two tiles, critical and rounded for each apart, and none further" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const seeds = 32;
    var apart: usize = 0;
    for (0..seeds) |seed| {
        heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 22, .y = 22 }, .{ .x = 23, .y = 20 } });
        toughenFoes(g);
        g.rng = mathx.Rng.init(seed);
        pressHolding(g, .a, &.{.lb});
        const near = TEST_HP - g.pool.get(2).?.hp;
        const off = TEST_HP - g.pool.get(3).?.hp;
        try expectDamage(g, .frost_nova, near, &.{.{ nova.COLD_LO, nova.COLD_HI }});
        try expectDamage(g, .frost_nova, off, &.{.{ nova.COLD_LO, nova.COLD_HI }});
        apart += @intFromBool(near != off);
        try std.testing.expectEqual(TEST_HP, g.pool.get(4).?.hp);
        try std.testing.expectEqual(manaAfter(g, .frost_nova), g.mana);
        try std.testing.expectEqual(nova.COOLDOWN - 1, g.cooldown.get(.frost_nova));
    }
    try std.testing.expect(apart > 0);
    std.debug.print("frost nova: {d} of {d} casts struck the foes 1 and 2 tiles off differently, none to the one 3 off\n", .{ apart, seeds });
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

test "a fireball bursts on the first foe it strikes, burning the foes round it, and none past its blast" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 26, .y = 20 }, .{ .x = 27, .y = 21 }, .{ .x = 29, .y = 20 } });
    toughenFoes(g);
    press(g, .a);
    try std.testing.expectEqual(Mode.aim, g.mode);
    press(g, .a);
    const struck = TEST_HP - g.pool.get(2).?.hp;
    try expectDamage(g, .fireball, struck, &.{.{ fireball.FIRE_LO, fireball.FIRE_HI }});
    try expectDamage(g, .fireball, TEST_HP - g.pool.get(3).?.hp, &.{.{ fireball.FIRE_LO, fireball.FIRE_HI }});
    try std.testing.expectEqual(TEST_HP, g.pool.get(4).?.hp);
    try std.testing.expectEqual(manaAfter(g, .fireball), g.mana);
    std.debug.print("fireball: {d} fire to the struck rat, {d} to the one beside it, none to the rat 3 tiles on\n", .{ struck, TEST_HP - g.pool.get(3).?.hp });
}

test "chain lightning leaps from the struck foe to two more, each within three tiles of the last" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 26, .y = 21 }, .{ .x = 29, .y = 21 }, .{ .x = 25, .y = 25 } });
    toughenFoes(g);
    pressHolding(g, .x, &.{.lb});
    try std.testing.expectEqual(Mode.aim, g.mode);
    press(g, CONFIRM);
    var hit: usize = 0;
    for ([_]u16{ 2, 3, 4 }) |id| {
        const dealt = TEST_HP - g.pool.get(id).?.hp;
        try expectDamage(g, .chain_lightning, dealt, &.{.{ chain.LIGHTNING_LO, chain.LIGHTNING_HI }});
        hit += 1;
    }
    try std.testing.expectEqual(TEST_HP, g.pool.get(5).?.hp);
    try std.testing.expectEqual(manaAfter(g, .chain_lightning), g.mana);
    std.debug.print("chain lightning: {d} rats struck, the fourth 4 tiles from each left whole\n", .{hit});
}

test "resisted chain lightning still holds play until its last jump" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 26, .y = 21 }, .{ .x = 29, .y = 21 } });
    for (g.pool.slice()[1..]) |*a| a.resists.set(.lightning, 100);
    pressHolding(g, .x, &.{.lb});
    press(g, CONFIRM);
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
    const h = g.heroActor().?;
    const hp = h.hp;
    g.rng = bitesRng(g, .rat, &.{true});
    pressHolding(g, .b, &.{.lb});
    const after_cast = manaAfter(g, .mana_shield);
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
    g.rng = bitesRng(g, .rat, &.{true});
    use(g, .wait);
    try std.testing.expect(h.hp < hp);
    std.debug.print("mana shield: a bite of {d} taken from mana, the orb holding till it landed; {d} turns, then the bites drew blood\n", .{ bitten, ward.TURNS });
}

test "mana shield deductions follow each staggered hit" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 20, .y = 21 } });
    wakeFoes(g);
    g.rng = bitesRng(g, .rat, &.{ true, true });
    pressHolding(g, .b, &.{.lb});
    const before = manaAfter(g, .mana_shield);
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

test "a mana shield's last turn stays drawn until the foes' moves of that turn are" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    wakeFoes(g);
    const h = g.heroActor().?;
    h.ward.turns = 1;
    g.st = .{};
    update(g, TEST_DT);
    const hero = heroSlot(g).?;
    try std.testing.expectEqual(@as(u8, 1), g.pictured[hero].status.get(.warded));
    use(g, .wait);
    try std.testing.expectEqual(@as(i32, 1), mathx.dist(g.pool.get(2).?.at, h.at));
    try std.testing.expectEqual(@as(u8, 0), h.ward.turns);
    try std.testing.expect(g.busy > 0);
    try std.testing.expectEqual(@as(u8, 1), g.pictured[hero].status.get(.warded));
    drawnOut(g);
    try std.testing.expectEqual(@as(u8, 0), g.pictured[hero].status.get(.warded));
    std.debug.print("mana shield: last turn drawn through the rat's step, gone after\n", .{});
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
        press(g, .b);
        try std.testing.expectEqual(Mode.aim, g.mode);
        try std.testing.expectEqual(P{ .x = 23, .y = 20 }, g.mark);
        press(g, .a);
        try std.testing.expectEqual(P{ .x = 22, .y = 20 }, g.heroActor().?.at);
        const dealt = TEST_HP - rat.hp;
        try expectDamage(g, .charge, dealt, &.{.{ charge.DMG_LO, charge.DMG_HI }});
        try std.testing.expectEqual(manaAfter(g, .charge), g.mana);
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
    press(g, .b);
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
            press(g, .b);
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
    g.heroActor().?.bleed.turns = bleeding.TURNS;
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
    g.heroActor().?.bleed.turns = bleeding.TURNS;
    catchUp(g);
    var buf: [SPOTS_MAX]Part = undefined;
    const spots = spotsOf(g, &buf);
    for (spots) |s| {
        g.st.pointer = look.middleAt(s.box);
        try std.testing.expectEqual(s.spot, hovered(g).?.spot);
    }
    const orb = hud.orbBox(hudLayout(g).life);
    g.st.pointer = .{ .x = @intFromFloat(orb.x + 1), .y = @intFromFloat(orb.y + 1) };
    try std.testing.expectEqual(@as(?Part, null), hovered(g));
    g.st.pointer = .{ .x = 0, .y = 0 };
    try std.testing.expectEqual(@as(?Part, null), hovered(g));
    g.st.pointer = null;
    try std.testing.expectEqual(@as(?Part, null), hovered(g));
    g.st.pointer = look.middleAt(spots[1].box);
    g.mode = .pause;
    try std.testing.expectEqual(@as(?Part, null), hovered(g));
    std.debug.print("hover: {d} hud parts each found at their centre; the orb's corner, the screen's, no mouse and pause show none\n", .{spots.len});
}
