const std = @import("std");
const rl = @import("raylib");

const mathx = @import("core/mathx.zig");
const input = @import("core/input.zig");
const grid = @import("world/grid.zig");
const fov = @import("world/fov.zig");
const gen = @import("world/gen.zig");
const actor = @import("play/actor.zig");
const bow = @import("play/bow.zig");
const pack = @import("play/pack.zig");
const skillbar = @import("play/skillbar.zig");
const look = @import("gfx/look.zig");
const light = @import("gfx/light.zig");
const font = @import("gfx/font.zig");

const P = mathx.P;

pub const WINDOW_W: i32 = 1600;
pub const WINDOW_H: i32 = 900;
pub const CELL: i32 = 64;
const CELL_F: f32 = @floatFromInt(CELL);
const HALF_CELL: i32 = @divTrunc(CELL, 2);
pub const GLYPH: i32 = 60;
pub const CARET: i32 = 30;
const TORCH_GLYPH: i32 = 30;
pub const TEXT: i32 = 20;
const TITLE: i32 = 60;
const LINE_W: i32 = @divTrunc(CELL, 32);
const OUTLINE_INSET: i32 = 1;
const BODY_BAR_INSET: i32 = @divTrunc(CELL, 10);
const BODY_BAR_H: i32 = @divTrunc(CELL, 16);
const BODY_BAR_LIFT: i32 = 2;
const CARET_PAD_X: i32 = 4;
const CARET_PAD_Y: i32 = 2;
pub const HUD_H: i32 = 124;
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
const LOG_LINE: i32 = 26;
const LOG_FADE: f32 = 0.22;
const DEAD_TITLE_DY: i32 = -100;
const DEAD_SCORE_DY: i32 = -10;
const DEAD_HINT_DY: i32 = 30;
const SLOT_PX: i32 = 56;
const SLOT_GAP: i32 = 6;
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
            x += SLOT_PX + SLOT_GAP;
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
const BIND_ROW_H: i32 = TEXT + 6 + SLOT_PX + KEY_GAP + SLOT_TEXT + 24;
const BIND_POP_DY: i32 = 10;
const BIND_INFO_DY: i32 = 8;
pub const MINI: i32 = 3;
pub const MINI_W: i32 = grid.W * MINI;
pub const MINI_H: i32 = grid.H * MINI;
pub const MINI_PAD: i32 = 12;
const MINI_FRAME: i32 = 4;
const MINI_HERO_GROW: i32 = 1;
pub const FOE_GAP: i32 = 12;
pub const SHOT_SEED: u64 = 0x5EED_1234;
pub const GOLD_LO: i32 = 3;
pub const GOLD_HI: i32 = 12;
const SHOTS_DIR = "shots";
const FLIGHT_S: f32 = 0.022;
const CAM_EASE: f32 = 12.0;
/// One walk repeat, so the glides of a held walk join end to end.
const GLIDE_S: f32 = input.Stepper.ARR;
/// Pixels, at the top of each glide's hop.
const HOP_PX: f32 = 10;
/// `gen.build` rolls from the bare seed; without the salt the rats replay the floor's rolls.
const PLAY_SALT: u64 = 0x9E37_79B9_7F4A_7C15;

comptime {
    std.debug.assert(@mod(CELL, look.SPRITE_PX) == 0);
    std.debug.assert(GLYPH <= CELL);
    std.debug.assert(LOG_Y + @as(i32, @intCast(Log.SHOWN)) * LOG_LINE <= HUD_H);
    std.debug.assert(SKILLS_Y + SLOT_PX + KEY_GAP + SLOT_TEXT <= HUD_H);
    std.debug.assert(FOE_GAP > actor.row(.archer).sight);
}

pub const Mode = enum { play, aim, bind, dead };

const Binds = struct {
    row: usize = 0,
    col: usize = 0,
    menu: Menu = .browse,

    const Menu = union(enum) { browse, pick: usize, carry: skillbar.Slot };

    fn slot(b: Binds) skillbar.Slot {
        return .{ .set = b.row, .button = skillbar.SLOTS[b.col] };
    }

    fn move(b: *Binds, d: mathx.Dir) void {
        b.col = wrap(b.col, d.delta().x, skillbar.SLOTS.len);
        b.row = wrap(b.row, d.delta().y, skillbar.SETS);
    }
};

fn wrap(i: usize, by: i32, n: usize) usize {
    return @intCast(@mod(@as(i32, @intCast(i)) + by, @as(i32, @intCast(n))));
}

/// Picker cell 0 clears the slot; the rest are the acts in order.
fn pickOf(a: ?skillbar.Act) usize {
    const act = a orelse return 1;
    return 1 + (std.mem.indexOfScalar(skillbar.Act, skillbar.ACTS, act) orelse 0);
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

fn cellPx(p: P) rl.Vector2 {
    return .{ .x = @floatFromInt(p.x * CELL), .y = @floatFromInt(p.y * CELL) };
}

/// Presentation only: the body already stands on `to`.
pub const Glide = struct {
    from: rl.Vector2,
    to: P,
    t: f32,
    /// Where a step taken mid-hop left the body, so it hops on from there instead of dropping to the floor.
    from_lift: f32 = 0,

    fn still(p: P) Glide {
        return .{ .from = cellPx(p), .to = p, .t = GLIDE_S };
    }

    fn toward(self: Glide, p: P, t: f32) Glide {
        return .{ .from = self.now(), .to = p, .t = t, .from_lift = self.height() };
    }

    fn done(self: Glide) f32 {
        return @min(1.0, self.t / GLIDE_S);
    }

    fn now(self: Glide) rl.Vector2 {
        const k = self.done();
        const to = cellPx(self.to);
        return .{ .x = mathx.lerpF(self.from.x, to.x, k), .y = mathx.lerpF(self.from.y, to.y, k) };
    }

    fn height(self: Glide) f32 {
        const k = self.done();
        return self.from_lift * (1 - k) + HOP_PX * 4 * k * (1 - k);
    }

    /// Pixels above the ground the body is drawn; its shadow, bar, light and the camera stay on the ground.
    fn lift(self: Glide) i32 {
        return mathx.roundTiesUp(self.height());
    }
};

pub const Facing = enum { right, left };

pub const Game = struct {
    mode: Mode = .play,
    lv: grid.Level,
    pool: actor.Pool = .{},
    hero: u16 = grid.NO_ONE,
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
    /// The window's size this frame; it changes when fullscreen is toggled.
    screen: P = .{ .x = WINDOW_W, .y = WINDOW_H },
    shot: ?Shot = null,
    /// Indexed by pool slot.
    glide: [actor.MAX]Glide = undefined,
    /// Indexed by pool slot. Presentation only: the last way a body stepped, struck or aimed across.
    facing: [actor.MAX]Facing = @splat(.right),
    sprites: look.Sprites = .{},
    face: font.Face = .{},
    light: *light.Light,
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
    const g = try alloc.create(Game);
    g.* = .{
        .lv = grid.Level.blank(),
        .rng = mathx.Rng.init(1),
        .light = l,
        .flow = undefined,
        .queue = undefined,
    };
    return g;
}

pub fn shut(alloc: std.mem.Allocator, g: *Game) void {
    alloc.destroy(g.light);
    alloc.destroy(g);
}

pub fn begin(g: *Game, seed: u64) void {
    g.seed = seed;
    g.rng = mathx.Rng.init(seed ^ PLAY_SALT);
    const floor = gen.build(&g.lv, seed);
    reset(g, floor.start);
    pack.place(&g.lv, &g.pool, &g.rng, floor.start, FOE_GAP);
    settle(g);
    g.log.say("{d} rats and {d} slimes somewhere on this floor. Seed {d}.", .{ tally(g, .rat).total, tally(g, .slime).total, seed });
}

fn reset(g: *Game, hero: P) void {
    g.pool = .{};
    g.hero = g.pool.spawn(&g.lv, actor.Actor.of(.archer, hero));
    g.kills = 0;
    g.gold = 0;
    g.shot = null;
    g.log = .{};
    g.mode = .play;
}

fn settle(g: *Game) void {
    castSight(g, g.archer().?.at);
    snapGlide(g);
    g.facing = @splat(.right);
    g.cam = camWant(g);
    g.light.settle(&g.lv);
    g.light.carrier = carrierAt(g);
}

fn freshSeed() u64 {
    return @bitCast(std.time.milliTimestamp());
}

fn castSight(g: *Game, from: P) void {
    fov.cast(&g.lv, from, actor.row(.archer).sight);
}

const Tally = struct { left: usize = 0, total: usize = 0 };

fn tally(g: *Game, kind: actor.Kind) Tally {
    var t = Tally{};
    for (g.pool.slice()) |a| {
        if (a.kind != kind) continue;
        t.total += 1;
        if (a.alive) t.left += 1;
    }
    return t;
}

const Move = enum { kick, step, blocked };

fn heroMove(g: *Game, d: mathx.Dir) Move {
    const h = g.archer() orelse return .blocked;
    if (g.lv.taken(h.at.add(d.delta())) and g.lv.passOk(h.at, d)) return .kick;
    return if (g.lv.stepOk(h.at, d, g.hero)) .step else .blocked;
}

fn turnToward(g: *Game, id: u16, dx: i32) void {
    if (dx != 0) g.facing[actor.Pool.slot(id)] = if (dx < 0) .left else .right;
}

fn heroStep(g: *Game, d: mathx.Dir) void {
    const h = g.archer() orelse return;
    const to = h.at.add(d.delta());
    turnToward(g, g.hero, d.delta().x);
    switch (heroMove(g, d)) {
        .kick => {
            const r = actor.row(.archer);
            const w = g.lv.who(to);
            if (w != grid.NO_ONE) wound(g, w, g.rng.range(r.hit_lo, r.hit_hi), KICK) else smash(g, to, KICK);
        },
        .step => g.pool.move(&g.lv, g.hero, to),
        .blocked => return,
    }
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
        const a = g.bar.at(.{ .set = 1, .button = b }) orelse continue;
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

fn openBinds(g: *Game) void {
    g.binds.menu = .browse;
    g.mode = .bind;
}

fn bindStep(g: *Game) void {
    const b = &g.binds;
    const here = b.slot();
    switch (b.menu) {
        .browse => {
            if (g.st.hit(.b) or g.st.hit(.view)) {
                g.mode = .play;
            } else if (g.st.hit(.a)) {
                b.menu = if (g.bar.at(here) != null) .{ .carry = here } else .{ .pick = pickOf(null) };
            } else if (g.st.hit(.x)) {
                b.menu = .{ .pick = pickOf(g.bar.at(here)) };
            } else if (g.st.hit(.y)) {
                g.bar.clear(here);
            } else if (g.st.walk) |d| {
                b.move(d);
            }
        },
        .pick => |i| {
            if (g.st.hit(.b)) {
                b.menu = .browse;
            } else if (g.st.hit(.a)) {
                if (i == 0) g.bar.clear(here) else g.bar.bind(here, skillbar.ACTS[i - 1]);
                b.menu = .browse;
            } else if (g.st.walk) |d| {
                b.menu = .{ .pick = wrap(i, d.delta().x, PICKS) };
            }
        },
        .carry => |from| {
            if (g.st.hit(.b)) {
                b.menu = .browse;
            } else if (g.st.hit(.a)) {
                g.bar.swap(from, here);
                b.menu = .browse;
            } else if (g.st.walk) |d| {
                b.move(d);
            }
        },
    }
}

fn nudgeAim(g: *Game, d: mathx.Dir) void {
    const h = g.archer() orelse return;
    const to = g.mark.add(d.delta());
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
    if (f.struck) |hit| switch (hit) {
        .body => |id| wound(g, id, g.rng.range(bow.DMG_LO, bow.DMG_HI), SHOOT),
        .barrel => |p| smash(g, p, SHOOT),
    } else g.log.say("Your arrow finds nothing.", .{});
    endTurn(g);
}

const SHOOT = "You shoot";
const KICK = "You kick";

fn smash(g: *Game, p: P, comptime verb: []const u8) void {
    if (!g.lv.breakBarrel(p)) return;
    const gold = g.rng.range(GOLD_LO, GOLD_HI);
    g.gold += gold;
    g.log.say(verb ++ " the barrel. It breaks: {d} gold.", .{gold});
}

fn wound(g: *Game, id: u16, dmg: i32, comptime verb: []const u8) void {
    const name = actor.row((g.pool.get(id) orelse return).kind).name;
    if (!g.pool.damage(&g.lv, id, dmg)) {
        g.log.say(verb ++ " the {s} for {d}.", .{ name, dmg });
        return;
    }
    g.kills += 1;
    g.log.say(verb ++ " the {s} for {d}. It dies.", .{ name, dmg });
    const kind = g.pool.items[actor.Pool.slot(id)].kind;
    if (tally(g, kind).left == 0) g.log.say("The last {s} is dead.", .{name});
}

fn endTurn(g: *Game) void {
    const h = g.archer() orelse return;
    castSight(g, h.at);
    _ = grid.distances(&g.lv, h.at, &g.flow, &g.queue);
    for (0..g.pool.n) |i| {
        const id = actor.Pool.idOf(i);
        if (id == g.hero) continue;
        foeTurn(g, id);
        if (g.mode == .dead) return;
    }
}

fn foeTurn(g: *Game, id: u16) void {
    const r = g.pool.get(id) orelse return;
    const h = g.archer() orelse return;
    const row = actor.row(r.kind);
    if (!r.awake) {
        if (!fov.sees(&g.lv, r.at, h.at, row.sight)) return;
        r.awake = true;
        turnToward(g, id, h.at.x - r.at.x);
        g.log.say("A {s} notices you.", .{row.name});
        return;
    }
    if (mathx.dirTo(r.at, h.at)) |d| {
        if (g.lv.passOk(r.at, d)) {
            turnToward(g, id, d.delta().x);
            const dmg = g.rng.range(row.hit_lo, row.hit_hi);
            g.log.say("The {s} {s} you for {d}.", .{ row.name, row.strikes, dmg });
            if (g.pool.damage(&g.lv, g.hero, dmg)) {
                g.log.say("You die.", .{});
                g.mode = .dead;
            }
            return;
        }
    }
    const step = actor.chase(&g.lv, r.at, id, &g.flow) orelse return;
    turnToward(g, id, step.delta().x);
    g.pool.move(&g.lv, id, r.at.add(step.delta()));
}

fn camAxis(centre: f32, view: f32, world: f32) f32 {
    if (view >= world) return (world - view) * 0.5;
    return std.math.clamp(centre - view * 0.5, 0, world - view);
}

fn heroNow(g: *Game) ?rl.Vector2 {
    if (g.archer() == null) return null;
    return g.glide[actor.Pool.slot(g.hero)].now();
}

fn camWant(g: *Game) rl.Vector2 {
    const at = heroNow(g) orelse return g.cam;
    const half: f32 = @floatFromInt(HALF_CELL);
    return .{
        .x = camAxis(at.x + half, @floatFromInt(g.screen.x), @floatFromInt(grid.W * CELL)),
        .y = camAxis(at.y + half, @floatFromInt(g.viewH()), @floatFromInt(grid.H * CELL)),
    };
}

fn snapGlide(g: *Game) void {
    for (g.pool.slice(), 0..) |a, i| g.glide[i] = Glide.still(a.at);
}

/// A body that moved this frame starts gliding as of when its step was due, not from this frame.
fn stepGlide(g: *Game, dt: f32) void {
    const late = g.st.late();
    for (g.pool.slice(), 0..) |a, i| {
        const gl = &g.glide[i];
        gl.t += dt;
        if (!gl.to.eq(a.at)) gl.* = gl.toward(a.at, late);
    }
}

pub fn update(g: *Game, dt: f32) void {
    switch (g.mode) {
        .play => {
            if (g.st.hit(.view)) {
                openBinds(g);
            } else if (usedSkill(g)) |u| {
                useSkill(g, u);
            } else if (g.st.walk) |d| {
                heroStep(g, d);
            }
        },
        .aim => {
            if (g.st.hit(g.aim_by)) {
                confirmAim(g);
            } else if (g.st.hit(.b) or g.st.hit(.view)) {
                g.mode = .play;
            } else if (g.st.walk) |d| {
                nudgeAim(g, d);
            }
        },
        .bind => bindStep(g),
        .dead => if (g.st.hit(.a)) begin(g, freshSeed()),
    }
    stepGlide(g, dt);
    if (g.shot) |*s| {
        s.t += dt;
        if (s.cell() == null) g.shot = null;
    }
    const want = camWant(g);
    const k = 1.0 - @exp(-dt * CAM_EASE);
    g.cam.x = mathx.lerpF(g.cam.x, want.x, k);
    g.cam.y = mathx.lerpF(g.cam.y, want.y, k);
    g.light.step(&g.lv, dt);
    g.light.carrier = carrierAt(g);
}

/// The archer's middle as drawn, cells: the carried light glides with the body.
fn carrierAt(g: *Game) ?[2]f32 {
    return middle(heroNow(g) orelse return null);
}

fn middle(v: rl.Vector2) [2]f32 {
    return .{ v.x / CELL_F + 0.5, v.y / CELL_F + 0.5 };
}

fn drawGlyph(g: *Game, ch: u8, sx: i32, sy: i32, col: rl.Color) void {
    glyphAt(g, ch, sx + HALF_CELL, sy + HALF_CELL, GLYPH, col);
}

fn textMid(g: *Game, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    g.face.text(s, @divTrunc(g.screen.x - g.face.width(s, size), 2), y, size, col);
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
    rl.drawTexturePro(t, look.whole(t), spriteRect(t, sx, sy), .{ .x = 0, .y = 0 }, 0, look.LIT);
}

/// Centred on `(cx, cy)`.
fn glyphAt(g: *Game, ch: u8, cx: i32, cy: i32, size: i32, col: rl.Color) void {
    const s = [_:0]u8{ch};
    g.face.draw(&s, cx - @divTrunc(g.face.width(&s, size), 2), cy - @divTrunc(size, 2), size, col);
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

fn inView(g: *Game, a: actor.Actor) bool {
    return a.alive and g.lv.isLit(a.at);
}

fn standsShownAt(g: *Game, p: P) bool {
    return (g.lv.isLit(p) and g.lv.who(p) != grid.NO_ONE) or (g.lv.isSeen(p) and g.lv.hasBarrel(p));
}

fn bar(x: i32, y: i32, w: i32, h: i32, hp: i32, max: i32, back: rl.Color) void {
    rl.drawRectangle(x, y, w, h, back);
    rl.drawRectangle(x, y, @divTrunc(w * @max(0, hp), max), h, look.LIFE);
}

const Shown = struct {
    a: actor.Actor,
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

fn barrelsIn(g: *Game, c: Cam, lo: P, hi: P, out: *[gen.MAX_BARRELS]Prop) []const Prop {
    var n: usize = 0;
    var y = lo.y;
    while (y < hi.y) : (y += 1) {
        var x = lo.x;
        while (x < hi.x) : (x += 1) {
            const p = P{ .x = x, .y = y };
            if (n == out.len or !g.lv.hasBarrel(p) or !g.lv.isSeen(p)) continue;
            const mid = middle(cellPx(p));
            out[n] = .{ .s = .{ .x = c.sx(p), .y = c.sy(p) }, .mid = mid, .shine = g.light.onBody(mid, false) };
            n += 1;
        }
    }
    return out[0..n];
}

/// At full light, over the seen cells from `lo` up to `hi`.
fn drawTerrain(g: *Game, c: Cam, lo: P, hi: P, kind: grid.Tile, arrow_at: ?P) void {
    var y = lo.y;
    while (y < hi.y) : (y += 1) {
        var x = lo.x;
        while (x < hi.x) : (x += 1) {
            const p = P{ .x = x, .y = y };
            if (!g.lv.isSeen(p) or g.lv.at(p) != kind) continue;
            if (g.sprites.tileAt(&g.lv, p)) |t| {
                drawSprite(t, c.sx(p), c.sy(p));
                continue;
            }
            if (kind == .floor) fillCell(c, p, look.FLOOR_BG);
            if (standsShownAt(g, p)) continue;
            if (arrow_at) |a| {
                if (a.eq(p)) continue;
            }
            const l = look.tile(kind);
            drawGlyph(g, l.ch, c.sx(p), c.sy(p), l.fg);
        }
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
    for (g.pool.slice(), 0..) |a, i| {
        if (!inView(g, a)) continue;
        const at = g.glide[i].now();
        const mid = middle(at);
        shown[n] = .{
            .a = a,
            .slot = i,
            .s = c.px(at),
            .mid = mid,
            .left = g.facing[i] == .left,
            .shine = g.light.onBody(mid, actor.Pool.idOf(i) == g.hero),
        };
        n += 1;
    }
    const bodies = shown[0..n];
    var props: [gen.MAX_BARRELS]Prop = undefined;
    const barrels = barrelsIn(g, c, lo, hi, &props);

    drawTerrain(g, c, lo, hi, .floor, arrow_at);
    if (g.sprites.barrel) |t| {
        for (barrels) |b| g.light.drawShadows(t, spriteRect(t, b.s.x, b.s.y), false, b.mid, b.shine);
    }
    for (bodies) |b| {
        const t = g.sprites.body(b.a.kind) orelse continue;
        g.light.drawShadows(t, spriteRect(t, b.s.x, b.s.y), b.left, b.mid, b.shine);
    }
    drawTerrain(g, c, lo, hi, .wall, arrow_at);
    g.light.bake(&g.lv, lo, hi);
    g.light.drawMap(-c.x, -c.y, CELL);

    if (aim_from) |from| {
        var ay = lo.y;
        while (ay < hi.y) : (ay += 1) {
            var ax = lo.x;
            while (ax < hi.x) : (ax += 1) {
                const p = P{ .x = ax, .y = ay };
                if (bow.aimable(&g.lv, from, p)) fillCell(c, p, look.AIM_REACH);
            }
        }
        const f = bow.fly(&g.lv, from, g.mark);
        for (f.path[0..f.len]) |p| fillCell(c, p, look.AIM_PATH);
    }

    for (barrels) |b| {
        if (g.sprites.barrel) |t| {
            g.light.drawBody(t, spriteRect(t, b.s.x, b.s.y), false, b.mid, b.shine);
        } else {
            drawGlyph(g, look.BARREL.ch, b.s.x, b.s.y, b.shine.tint(look.BARREL.fg));
        }
    }

    for (bodies) |b| {
        const y = b.s.y - g.glide[b.slot].lift();
        if (g.sprites.body(b.a.kind)) |t| {
            g.light.drawBody(t, spriteRect(t, b.s.x, y), b.left, b.mid, b.shine);
        } else {
            const l = look.body(b.a.kind);
            drawGlyph(g, l.ch, b.s.x, y, b.shine.tint(l.fg));
        }
    }

    drawTorches(g, c);

    for (bodies) |b| {
        if (!b.a.foe() or !b.a.hurt()) continue;
        const y_bar = b.s.y + CELL - BODY_BAR_H - BODY_BAR_LIFT;
        bar(b.s.x + BODY_BAR_INSET, y_bar, CELL - BODY_BAR_INSET * 2, BODY_BAR_H, b.a.hp, actor.row(b.a.kind).hp, look.BG);
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
        glyphAt(g, look.TORCH.ch, x, y, TORCH_GLYPH, look.TORCH_DIM);
        glyphAt(g, look.TORCH.ch, x, y, TORCH_GLYPH, look.fade(look.TORCH.fg, f.sight * @min(1, f.glow)));
    }
    g.light.drawGlows(flames, @floatFromInt(-c.x), @floatFromInt(-c.y), CELL_F);
}

fn drawLean(g: *Game, c: Cam) void {
    const h = g.archer() orelse return;
    for (input.DPAD) |button| {
        const d = input.leanOf(button);
        const p = h.at.add(d.delta());
        const col = switch (heroMove(g, d)) {
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

pub fn miniOrigin(screen_w: i32) P {
    return .{ .x = screen_w - MINI_W - MINI_PAD, .y = MINI_PAD };
}

fn miniDot(o: P, p: P, grow: i32, col: rl.Color) void {
    rl.drawRectangle(o.x + p.x * MINI - grow, o.y + p.y * MINI - grow, MINI + grow * 2, MINI + grow * 2, col);
}

fn drawMinimap(g: *Game) void {
    const o = miniOrigin(g.screen.x);
    const f = MINI_FRAME;
    rl.drawRectangle(o.x - f, o.y - f, MINI_W + f * 2, MINI_H + f * 2, look.MINI_BG);
    rl.drawRectangleLines(o.x - f, o.y - f, MINI_W + f * 2, MINI_H + f * 2, look.EDGE);
    for (0..grid.CELLS) |i| {
        if (!g.lv.seen[i]) continue;
        miniDot(o, grid.Level.of(i), 0, look.mini(g.lv.tile[i], g.lv.lit[i]));
    }
    for (g.pool.slice()) |a| {
        if (!a.foe() or !inView(g, a)) continue;
        miniDot(o, a.at, 0, look.MINI_FOE);
    }
    if (g.archer()) |h| miniDot(o, h.at, MINI_HERO_GROW, look.MINI_HERO);
    const c = Cam.of(g);
    const vx = o.x + @divTrunc(c.x * MINI, CELL);
    const vy = o.y + @divTrunc(c.y * MINI, CELL);
    rl.drawRectangleLines(vx, vy, @divTrunc(g.screen.x * MINI, CELL), @divTrunc(g.viewH() * MINI, CELL), look.MINI_VIEW);
}

const HINT_PLAY = input.LEAN_CAPTION ++ "+" ++ input.MOVE_CAPTION ++ " diagonal   " ++ input.Button.view.caption() ++ " bind skills";

fn skillsX(g: *Game) i32 {
    return @divTrunc(g.screen.x - SKILLS_W, 2);
}

const SlotLook = struct { act: ?skillbar.Act, key: ?input.Button, edge: rl.Color, faded: bool = false };

fn drawSlot(g: *Game, x: i32, y: i32, s: SlotLook) void {
    const a: f32 = if (s.faded) 0.35 else 1;
    rl.drawRectangle(x, y, SLOT_PX, SLOT_PX, look.fade(if (s.act == null) look.SLOT_EMPTY else look.SLOT_BG, a));
    rl.drawRectangleLinesEx(.{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(SLOT_PX),
        .height = @floatFromInt(SLOT_PX),
    }, @floatFromInt(LINE_W), look.fade(s.edge, a));
    if (s.act) |act| {
        const l = look.skill(act);
        glyphAt(g, l.ch, x + @divTrunc(SLOT_PX, 2), y + @divTrunc(SLOT_PX, 2), SLOT_GLYPH, look.fade(l.fg, a));
    }
    const k = (s.key orelse return).caption();
    g.face.draw(k, x + @divTrunc(SLOT_PX - g.face.width(k, SLOT_TEXT), 2), y + SLOT_PX + KEY_GAP, SLOT_TEXT, look.fade(look.DIM, a));
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
    var buf: [128]u8 = undefined;
    const b = g.binds;
    const x0 = skillsX(g);
    const y0 = @divTrunc(g.viewH(), 2) + BIND_TOP_DY;
    rl.drawRectangle(0, 0, g.screen.x, g.viewH(), look.VEIL);
    textMid(g, "BIND SKILLS", y0, BIND_TITLE, look.TEXT);
    var cursor = P{ .x = 0, .y = 0 };
    for (0..skillbar.SETS) |s| {
        const ry = y0 + BIND_ROWS_DY + @as(i32, @intCast(s)) * BIND_ROW_H;
        g.face.text(skillbar.SET_NAMES[s], x0, ry, TEXT, look.DIM);
        const sy = ry + TEXT + 6;
        for (skillbar.SLOTS, SLOT_XS, 0..) |key, dx, i| {
            const here = s == b.row and i == b.col;
            const carried = switch (b.menu) {
                .carry => |from| from.set == s and from.button == key,
                else => false,
            };
            if (here) cursor = .{ .x = x0 + dx, .y = sy };
            drawSlot(g, x0 + dx, sy, .{
                .act = g.bar.at(.{ .set = s, .button = key }),
                .key = key,
                .edge = if (here) look.SLOT_CURSOR else look.EDGE,
                .faded = carried,
            });
        }
    }
    const info_y = y0 + BIND_ROWS_DY + @as(i32, @intCast(skillbar.SETS)) * BIND_ROW_H + BIND_INFO_DY;
    var shown: ?skillbar.Act = g.bar.at(b.slot());
    var legend: [:0]const u8 = if (shown == null) "A select skill   X select skill   B close" else "A pick up   X change skill   Y remove   B close";
    switch (b.menu) {
        .browse => {},
        .carry => |from| {
            shown = g.bar.at(from);
            legend = "A put down   B cancel";
            if (shown) |a| drawSlot(g, cursor.x, cursor.y - SLOT_PX - BIND_POP_DY, .{ .act = a, .key = from.button, .edge = look.SLOT_CURSOR });
        },
        .pick => |pick| {
            legend = "A bind   B back";
            shown = if (pick == 0) null else skillbar.ACTS[pick - 1];
            const w = @as(i32, @intCast(PICKS)) * (SLOT_PX + SLOT_GAP) - SLOT_GAP;
            const px = cursor.x + @divTrunc(SLOT_PX - w, 2);
            const py = cursor.y - SLOT_PX - BIND_POP_DY;
            for (0..PICKS) |i| {
                const x = px + @as(i32, @intCast(i)) * (SLOT_PX + SLOT_GAP);
                const edge = if (i == pick) look.SLOT_CURSOR else if (i == 0) look.SLOT_CLEAR else look.EDGE;
                drawSlot(g, x, py, .{ .act = if (i == 0) null else skillbar.ACTS[i - 1], .key = null, .edge = edge });
                if (i == 0) glyphAt(g, 'x', x + @divTrunc(SLOT_PX, 2), py + @divTrunc(SLOT_PX, 2), @divTrunc(SLOT_PX, 2), look.SLOT_CLEAR);
            }
        },
    }
    if (shown) |a| {
        textMid(g, a.name(), info_y, TEXT, look.TEXT);
        textMid(g, a.desc(), info_y + LOG_LINE, TEXT, look.DIM);
    } else if (b.menu == .pick) {
        textMid(g, "Clear slot", info_y, TEXT, look.TEXT);
    }
    const hold = if (g.bar.modifier) |m| std.fmt.bufPrintZ(&buf, "Hold {s} for the Secondary Skill Set", .{m.caption()}) catch "" else "No button holds the Secondary Skill Set";
    textMid(g, hold, info_y + LOG_LINE * 2, TEXT, look.DIM);
    textMid(g, legend, info_y + LOG_LINE * 4, TEXT, look.DIM);
}

fn drawHud(g: *Game) void {
    const top = g.viewH();
    rl.drawRectangle(0, top, g.screen.x, HUD_H, look.BG);
    rl.drawRectangle(0, top, g.screen.x, HUD_EDGE, look.EDGE);

    var buf: [128]u8 = undefined;
    const max = actor.row(.archer).hp;
    const hp = if (g.archer()) |h| h.hp else 0;
    const bar_y = top + BAR_Y;
    bar(HUD_PAD, bar_y, BAR_W, BAR_H, hp, max, look.LIFE_BG);
    g.face.text(std.fmt.bufPrintZ(&buf, "HP {d}/{d}", .{ @max(0, hp), max }) catch "", HUD_PAD + BAR_TEXT_X, bar_y + @divTrunc(BAR_H - TEXT, 2), TEXT, look.TEXT);
    const r = tally(g, .rat);
    const s = tally(g, .slime);
    const foes = std.fmt.bufPrintZ(&buf, "Rats {d}/{d}   Slimes {d}/{d}", .{ r.left, r.total, s.left, s.total }) catch "";
    g.face.text(foes, HUD_PAD, top + TALLY_Y, TEXT, look.DIM);
    const gold_x = HUD_PAD + g.face.width(foes, TEXT) + TALLY_GAP;
    g.face.text(std.fmt.bufPrintZ(&buf, "Gold {d}", .{g.gold}) catch "", gold_x, top + TALLY_Y, TEXT, look.COIN);
    const hint: [:0]const u8 = if (g.mode == .aim)
        std.fmt.bufPrintZ(&buf, "{s} shoot   {s} cancel   {s} aim", .{ g.aim_by.caption(), input.Button.b.caption(), input.MOVE_CAPTION }) catch ""
    else
        HINT_PLAY;
    g.face.text(hint, HUD_PAD, top + HINT_Y, TEXT, look.DIM);
    drawSkills(g, top);

    const log_x = skillsX(g) + SKILLS_W + HUD_PAD * 2;
    for (0..Log.SHOWN) |row| {
        const back = Log.SHOWN - 1 - row;
        const l = g.log.line(back) orelse continue;
        const a = 1.0 - @as(f32, @floatFromInt(back)) * LOG_FADE;
        g.face.text(l, log_x, top + LOG_Y + @as(i32, @intCast(row)) * LOG_LINE, TEXT, look.fade(look.TEXT, a));
    }
}

fn drawDead(g: *Game) void {
    var buf: [128]u8 = undefined;
    const mid = @divTrunc(g.viewH(), 2);
    rl.drawRectangle(0, 0, g.screen.x, g.viewH(), look.VEIL);
    textMid(g, "YOU DIED", mid + DEAD_TITLE_DY, TITLE, look.LIFE);
    textMid(g, std.fmt.bufPrintZ(&buf, "{d} foes killed. Seed {d}.", .{ g.kills, g.seed }) catch "", mid + DEAD_SCORE_DY, TEXT, look.TEXT);
    textMid(g, comptime input.Button.a.caption() ++ "  new floor", mid + DEAD_HINT_DY, TEXT, look.DIM);
}

pub fn drawFrame(g: *Game) void {
    rl.clearBackground(look.BG);
    drawWorld(g);
    drawMinimap(g);
    drawHud(g);
    if (g.mode == .bind) drawBinds(g);
    if (g.mode == .dead) drawDead(g);
}

fn withGame(flags: rl.ConfigFlags, title: [:0]const u8, comptime body: fn (*Game) void) void {
    const alloc = std.heap.c_allocator;
    rl.setConfigFlags(flags);
    rl.initWindow(WINDOW_W, WINDOW_H, title);
    defer rl.closeWindow();
    const g = boot(alloc) catch |e| {
        std.debug.print("boot FAILED ({s})\n", .{@errorName(e)});
        return;
    };
    defer shut(alloc, g);
    g.sprites = look.Sprites.load();
    defer g.sprites.unload();
    g.face = font.Face.load();
    defer g.face.unload();
    const figures = g.sprites.figures();
    g.light.load(&figures);
    defer g.light.unload();
    body(g);
}

pub fn play() void {
    withGame(.{ .vsync_hint = true }, "roguelike", loop);
}

fn loop(g: *Game) void {
    begin(g, freshSeed());
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        g.st.update(dt);
        if (g.st.fullscreen) rl.toggleBorderlessWindowed();
        g.screen = .{ .x = rl.getScreenWidth(), .y = rl.getScreenHeight() };
        update(g, dt);
        rl.beginDrawing();
        drawFrame(g);
        rl.endDrawing();
    }
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
    g.binds.col = 2;
    g.binds.menu = .{ .pick = pickOf(g.bar.at(g.binds.slot())) };
    capture(g, target, SHOTS_DIR ++ "/bind.png");
}

const POSE_TORCH = P{ .x = 20, .y = 10 };

fn poseTorch(g: *Game) void {
    arena(g, .{ .x = 20, .y = 15 }, &.{ .{ .x = 17, .y = 12 }, .{ .x = 23, .y = 13 } });
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

fn capture(g: *Game, target: rl.RenderTexture2D, path: [:0]const u8) void {
    drawInto(g, target);
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
        if (g.st.walk != null and g.archer() != null and g.archer().?.at.eq(was)) d = mathx.ALL_DIRS[rng.below(mathx.ALL_DIRS.len)];
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
        if (d < POSE_NEAR or d > POSE_FAR or !bow.aimable(&g.lv, h.at, p) or g.lv.who(p) != grid.NO_ONE) continue;
        g.pool.move(&g.lv, rat, p);
        break;
    }
    wound(g, rat, bow.DMG_LO, SHOOT);
    settle(g);
}

fn arena(g: *Game, hero: P, rats: []const P) void {
    g.lv = grid.openFloor();
    reset(g, hero);
    for (rats) |r| _ = g.pool.spawn(&g.lv, actor.Actor.of(.rat, r));
    settle(g);
}

fn press(g: *Game, a: input.Button) void {
    g.st = .{};
    g.st.pressed.insert(a);
    update(g, 0);
}

fn nudge(g: *Game, d: mathx.Dir) void {
    g.st = .{ .walk = d };
    update(g, 0);
}

fn pressHolding(g: *Game, a: input.Button, held: []const input.Button) void {
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
    g.bar.clear(.{ .set = 0, .button = .x });
    g.bar.bind(.{ .set = 1, .button = .rb }, .shoot);
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
    g.bar.bind(.{ .set = 1, .button = .y }, .shoot);
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
    g.binds.col = std.mem.indexOfScalar(input.Button, &skillbar.SLOTS, .y).?;
    press(g, .a);
    nudge(g, .e);
    press(g, .a);
    try std.testing.expectEqual(@as(?skillbar.Act, skillbar.ACTS[1]), g.bar.at(.{ .set = 0, .button = .y }));
    g.binds.col = std.mem.indexOfScalar(input.Button, &skillbar.SLOTS, .x).?;
    press(g, .a);
    nudge(g, .s);
    press(g, .a);
    try std.testing.expectEqual(@as(?skillbar.Act, null), g.bar.at(.{ .set = 0, .button = .x }));
    try std.testing.expectEqual(@as(?skillbar.Act, .shoot), g.bar.at(.{ .set = 1, .button = .x }));
    press(g, .y);
    try std.testing.expectEqual(@as(?skillbar.Act, null), g.bar.at(.{ .set = 1, .button = .x }));
    press(g, .b);
    try std.testing.expectEqual(Mode.play, g.mode);
    try std.testing.expectEqual(P{ .x = 30, .y = 20 }, g.pool.get(2).?.at);
}

test "a new floor has every pack placed, no foe in sight or on a barrel" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    for (0..40) |i| {
        begin(g, 0xF00D +% i *% 7919);
        const r = tally(g, .rat);
        const s = tally(g, .slime);
        try std.testing.expect(r.left == r.total and s.left == s.total);
        try std.testing.expect(r.total + s.total >= pack.PER_FLOOR);
        const h = g.archer().?;
        for (g.pool.slice()[1..]) |a| {
            try std.testing.expect(!g.lv.isLit(a.at));
            try std.testing.expect(!g.lv.hasBarrel(a.at));
            try std.testing.expect(mathx.dist(a.at, h.at) >= FOE_GAP);
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
    const lost = actor.row(.archer).hp - g.archer().?.hp;
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
    const row = actor.row(.slime);
    const lost = actor.row(.archer).hp - g.archer().?.hp;
    std.debug.print("slime slam: {d} hp\n", .{lost});
    try std.testing.expect(lost >= row.hit_lo and lost <= row.hit_hi);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.pool.get(id).?.at);
}

test "a body faces right until it steps, aims or turns on someone to its left, and straight up or down keeps it" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 16, .y = 20 }, .{ .x = 25, .y = 20 } });
    const hero = actor.Pool.slot(g.hero);
    for (g.facing[0..g.pool.n]) |f| try std.testing.expectEqual(Facing.right, f);
    nudge(g, .w);
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
    try std.testing.expect(r.awake and r.hp > 0 and r.hp <= 3);
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
    for ([_]P{ .{ .x = 1600, .y = 900 }, .{ .x = 2560, .y = 1440 } }) |screen| {
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

test "rats land on the floor as the floor is, not where its own rolls put the rooms" {
    const g = try boot(std.testing.allocator);
    defer shut(std.testing.allocator, g);
    const inRoom = struct {
        fn f(fl: gen.Floor, p: P) bool {
            for (fl.rooms[0..fl.room_n]) |r| {
                if (p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h) return true;
            }
            return false;
        }
    }.f;
    var lv: grid.Level = undefined;
    var rats: usize = 0;
    var rats_in: usize = 0;
    var open: usize = 0;
    var open_in: usize = 0;
    for (0..200) |i| {
        const seed: u64 = 0x1234 +% i *% 104729;
        begin(g, seed);
        const f = gen.build(&lv, seed);
        for (g.pool.slice()[1..]) |a| {
            rats += 1;
            if (inRoom(f, a.at)) rats_in += 1;
        }
        for (0..grid.CELLS) |c| {
            const p = grid.Level.of(c);
            if (!lv.walkable(p) or lv.hasBarrel(p) or mathx.dist(p, f.start) < FOE_GAP) continue;
            open += 1;
            if (inRoom(f, p)) open_in += 1;
        }
    }
    const want = open_in * 100 / open;
    const got = rats_in * 100 / rats;
    std.debug.print("200 floors: {d}% of the open floor a rat may take is in a room, {d}% of rats are\n", .{ want, got });
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
    const dt: f32 = 1.0 / 240.0;
    var peaks = [_]i32{0} ** actor.MAX;
    var steps: usize = 0;
    var hops: usize = 0;
    var high = false;
    const ground = [2]f32{ g.glide[hero].now().y, g.cam.y };
    var bobbed = false;
    var t: f32 = 0;
    while (t < 1.5) : (t += dt) {
        g.st.walk = g.st.step.tick(dt, 1, mathx.Dir.e.heading(), input.Stepper.SETTLE);
        update(g, dt);
        if (g.st.walk != null) steps += 1;
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
    var gl = Glide.still(.{ .x = 5, .y = 5 });
    gl = gl.toward(.{ .x = 6, .y = 5 }, 0);
    var worst: f32 = 0;
    var t: f32 = 0;
    const dt: f32 = 1.0 / 240.0;
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
    for ([_]P{ .{ .x = 1600, .y = 900 }, .{ .x = 1920, .y = 1080 }, .{ .x = 2560, .y = 1440 } }) |screen| {
        const o = miniOrigin(screen.x);
        try std.testing.expect(o.x > @divTrunc(screen.x, 2));
        try std.testing.expect(o.y + MINI_H + MINI_FRAME < screen.y - HUD_H);
    }
}
