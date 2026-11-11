const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const skillbar = @import("../play/skillbar.zig");
const sunder = @import("../play/sunder.zig");
const tactics = @import("../play/tactics.zig");
const areas = @import("../play/area.zig");
const fx = @import("../gfx/fx.zig");
const light = @import("../gfx/light.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");
const widgets = @import("widgets.zig");
const panel = @import("panel.zig");
const modals = @import("modals.zig");
const editor = @import("editor.zig");
const Desk = input.Desk;
const P = mathx.P;
const Shot = game.presentation.Shot;

const Group = enum { blows, missiles, gas, footfalls, flames, marks, hero };

const GROUP_NAMES = std.EnumArray(Group, [:0]const u8).init(.{
    .blows = "Blows",
    .missiles = "Missiles",
    .gas = "Gas",
    .footfalls = "Footfalls",
    .flames = "Flames",
    .marks = "Status marks",
    .hero = "Hero",
});

pub const Sample = union(enum) {
    hit: fx.Matter,
    embers,
    drip,
    shimmer,
    whirl,
    arc,
    missile: skillbar.Act,
    net,
    wisps: grid.Gas,
    glowbulb,
    splash,
    dust: grid.Tile,
    juke,
    torch,
    fire_wall,
    mark: fx.Status,
    level_up,

    pub fn group(s: Sample) Group {
        return switch (s) {
            .hit, .embers, .drip, .shimmer, .whirl, .arc => .blows,
            .missile, .net => .missiles,
            .wisps, .glowbulb => .gas,
            .splash, .dust, .juke => .footfalls,
            .torch, .fire_wall => .flames,
            .mark => .marks,
            .level_up => .hero,
        };
    }

    pub fn name(s: Sample) [:0]const u8 {
        return switch (s) {
            .hit => |m| switch (m) {
                inline else => |t| comptime menu.capital(@tagName(t)) ++ " hit",
            },
            .embers => "Embers",
            .drip => "Bleed drip",
            .shimmer => "Shimmer",
            .whirl => "Sweep",
            .arc => "Lightning arc",
            .missile => |a| a.name(),
            .net => "Net",
            .wisps => |gs| switch (gs) {
                inline else => |t| comptime menu.capital(@tagName(t)) ++ " wisps",
            },
            .glowbulb => "Glowbulb burst",
            .splash => "Splash",
            .dust => |t| switch (t) {
                inline else => |k| comptime "Dust on " ++ @tagName(k),
            },
            .juke => skillbar.Act.juke.name(),
            .torch => "Torch",
            .fire_wall => skillbar.Act.fire_wall.name(),
            .mark => |st| st.title(),
            .level_up => "Level up",
        };
    }

    fn ground(s: Sample) grid.Tile {
        return switch (s) {
            .splash => .shallows,
            .dust => |t| t,
            .hit, .embers, .drip, .shimmer, .whirl, .arc, .missile, .net, .wisps, .glowbulb, .juke, .torch, .fire_wall, .mark, .level_up => .floor,
        };
    }

    /// Seconds between showings, a missile's from its landing; null for one that never stops.
    fn period(s: Sample) ?f32 {
        return switch (s) {
            .mark, .torch, .fire_wall => null,
            .missile, .net => MISSILE_REST_S,
            .level_up => fx.LEVEL_UP_S + REST_S,
            .juke => fx.JUKE_S + REST_S,
            .hit, .embers, .drip, .shimmer, .whirl, .arc, .wisps, .glowbulb, .splash, .dust => BURST_S,
        };
    }
};

const SAMPLES = blk: {
    @setEvalBranchQuota(20_000);
    var out: []const Sample = &.{};
    for (std.enums.values(fx.Matter)) |m| out = out ++ &[_]Sample{.{ .hit = m }};
    out = out ++ &[_]Sample{ .embers, .drip, .shimmer, .whirl, .arc };
    for (std.enums.values(skillbar.Act)) |a| {
        if (a.reticle() == .bow) out = out ++ &[_]Sample{.{ .missile = a }};
    }
    out = out ++ &[_]Sample{.net};
    for (std.enums.values(grid.Gas)) |gs| out = out ++ &[_]Sample{.{ .wisps = gs }};
    out = out ++ &[_]Sample{ .glowbulb, .splash };
    for (DUSTED) |t| out = out ++ &[_]Sample{.{ .dust = t }};
    out = out ++ &[_]Sample{ .juke, .torch, .fire_wall };
    for (std.enums.values(fx.Status)) |st| {
        if (fx.Fx.marks(st)) out = out ++ &[_]Sample{.{ .mark = st }};
    }
    out = out ++ &[_]Sample{.level_up};
    break :blk out[0..out.len].*;
};

const DUSTED = [_]grid.Tile{ .dirt, .sand };

comptime {
    for (DUSTED) |t| std.debug.assert(look.stepDust(t) != null);
    for (SAMPLES[1..], SAMPLES[0 .. SAMPLES.len - 1]) |s, before| std.debug.assert(@intFromEnum(s.group()) >= @intFromEnum(before.group()));
}

const SPEEDS = [_]struct { rate: f32, label: [:0]const u8 }{
    .{ .rate = 1, .label = "Full speed" },
    .{ .rate = 0.5, .label = "Half" },
    .{ .rate = 0.25, .label = "Quarter" },
};

const BURST_S: f32 = 1.4;
const REST_S: f32 = 0.6;
const MISSILE_REST_S: f32 = 0.9;
const COLS: i32 = 9;
const ROWS: i32 = 5;
const ORIGIN = P{ .x = 40, .y = 30 };
const MIDDLE = ORIGIN.add(.{ .x = @divTrunc(COLS, 2), .y = @divTrunc(ROWS, 2) });
const SLOT = actor.ActorSlot.fromIndex(0);
const JUKE_SPAN: i32 = 2;
const ARC_SPAN: i32 = 3;
const WALL_CELLS: i32 = @intCast(tactics.FireWall.length(1));
const POOL_A: f32 = 0.35;
const SHADE = look.fade(look.BG, 0.35);
const ZOOMS = [_]f32{ 2, 1 };

fn shotOf(lv: *const grid.Level, act: skillbar.Act, net: bool, round: u32) Shot {
    const from = P{ .x = ORIGIN.x, .y = MIDDLE.y + if (round % 2 == 0) 0 else @divTrunc(ROWS, 2) };
    return .{ .flight = bow.fly(lv, from, LANDING), .from = from, .act = act, .net = net };
}

const LANDING = MIDDLE.add(.{ .x = @divTrunc(COLS, 2) - areas.BURST_MAX, .y = 0 });

fn px(n: i32, cell: f32) f32 {
    return @as(f32, @floatFromInt(n)) * cell;
}

pub const Viewer = struct {
    lv: grid.Level,
    sight: [grid.CELLS]f32,
    effects: fx.Fx = .{},
    shot: ?Shot = null,
    at: usize = 0,
    speed: usize = 0,
    /// Seconds into this showing.
    t: f32 = 0,
    span: ?f32 = null,
    round: u32 = 0,
    due: bool = true,
    list: widgets.Scrolled = .{},
    reveal: bool = true,

    fn reset(v: *Viewer) void {
        v.effects.clear();
        v.shot = null;
        v.t = 0;
        v.round = 0;
        v.due = true;
    }

    pub fn pick(v: *Viewer, i: usize) void {
        if (i == v.at) return;
        v.at = i;
        v.reset();
    }

    pub fn sample(v: *const Viewer) Sample {
        return SAMPLES[v.at];
    }

    pub fn step(v: *Viewer, dt_shown: f32) void {
        const dt = dt_shown * SPEEDS[v.speed].rate;
        if (v.due) {
            v.due = false;
            v.span = v.sample().period();
            v.fire(v.sample());
        }
        if (v.shot) |*sh| {
            if (!sh.fly(&v.effects, &v.lv, dt)) v.shot = null;
        }
        v.effects.step(&v.lv, dt);
        v.t += dt;
        if (v.span) |p| if (v.t >= p) {
            v.t = 0;
            v.round += 1;
            v.due = true;
        };
    }

    fn fire(v: *Viewer, s: Sample) void {
        const mid = mathx.centre(MIDDLE);
        const e = &v.effects;
        switch (s) {
            .hit => |m| e.strike(0, .{ .impact = .{ .actor = .{ .slot = SLOT, .at = MIDDLE, .lethal = v.round % 2 == 1 } }, .dir = .{ 1, 0 }, .matter = m }),
            .embers => e.sting(0, .{ .slot = SLOT, .fire_at = mid }),
            .drip => e.sting(0, .{ .slot = SLOT, .drip = .{ .at = mid, .matter = .blood } }),
            .shimmer => e.shimmerIn(0, .{ .at = mid, .col = look.LIFE }),
            .whirl => e.sweep(0, mid),
            .arc => e.zap(0, .{ .from = mathx.centre(MIDDLE.add(.{ .x = -ARC_SPAN, .y = 0 })), .to = mathx.centre(MIDDLE.add(.{ .x = ARC_SPAN, .y = 0 })) }),
            .missile => |a| v.loose(a, false),
            .net => v.loose(.shoot, true),
            .wisps => |gs| e.puff(0, .{ .at = mid, .ink = look.gasInk(gs) }),
            .glowbulb => e.puff(0, .{ .at = mid, .ink = look.gasInk(.healing), .motes = fx.BURST_WISPS }),
            .splash => e.splash(mid),
            .dust => |t| e.dust(mid, look.stepDust(t).?),
            .juke => e.juke(MIDDLE.add(.{ .x = -JUKE_SPAN, .y = 0 }), MIDDLE.add(.{ .x = JUKE_SPAN, .y = 0 })),
            .level_up => e.levelUp(),
            .torch, .fire_wall, .mark => {},
        }
    }

    fn loose(v: *Viewer, act: skillbar.Act, net: bool) void {
        const sh = shotOf(&v.lv, act, net, v.round);
        v.shot = sh;
        const lands = sh.lands();
        v.span = v.span.? + sh.ends();
        const end = sh.flight.end() orelse return;
        sh.zapInto(&v.effects);
        switch (act) {
            inline else => |a| if (comptime a.reticle() == .bow and a.bursts()) {
                v.effects.burst(lands, .{ .at = end, .area = skillbar.Act.elemental(a).burst(&v.lv, sh.from, end), .element = a.element().? });
            },
        }
    }
};

fn create(alloc: std.mem.Allocator) !*Viewer {
    const v = try alloc.create(Viewer);
    v.* = .{ .lv = grid.openFloor(), .sight = @splat(1) };
    v.lv.lit = @splat(true);
    return v;
}

fn viewer(ed: *editor.Editor) !*Viewer {
    if (ed.effects == null) ed.effects = try create(ed.alloc);
    const v = ed.effects.?;
    v.reset();
    v.reveal = true;
    return v;
}

pub fn open(ed: *editor.Editor) void {
    _ = viewer(ed) catch return ed.say("The effects viewer could not open (out of memory)", .{});
    ed.ask(.effects);
}

pub fn keys(ed: *editor.Editor) void {
    const v = ed.effects orelse return;
    const d = &ed.desk;
    if (d.nav != 0) {
        v.pick(mathx.wrap(v.at, d.nav, SAMPLES.len));
        v.reveal = true;
    }
    if (d.enter) v.reset();
    if (d.wheel != 0) v.list.wheel(d.mouse, d.notch());
}

const LIST_W: i32 = 320;
const HEADER_STEP: i32 = widgets.HEADING_H + widgets.GAP;
const SPEED_W: i32 = 150;
pub const TITLE = "Effects";

pub fn draw(ed: *editor.Editor, g: *game.Game) void {
    const v = ed.effects orelse return;
    const page = widgets.pageFrame(&g.face, g.screen, TITLE);
    const f = page.frame;
    widgets.titleHint(&g.face, f, TITLE, modals.PICKS_ONE ++ menu.SEP ++ Desk.ENTER_CAPTION ++ " replays" ++ menu.SEP ++ modals.CLOSES);
    const col = page.column();
    const list = raster.rect(col.left(), f.y, LIST_W, page.bottom - f.y);
    drawList(ed, g, v, list);
    const x = widgets.besides(col.left(), LIST_W, f.y, page.bottom);
    const room = P{ .x = col.left() + col.inner() - x, .y = page.bottom - f.y - widgets.TITLE - widgets.GAP - widgets.ROW_STEP };
    const cell = stageCell(room);
    widgets.textFace(&g.face).draw(v.sample().name(), x, f.y, widgets.TITLE, look.TEXT);
    const stage = raster.rect(x, f.y + widgets.TITLE + widgets.GAP, @intFromFloat(px(COLS, cell)), @intFromFloat(px(ROWS, cell)));
    drawStage(g, v, stage, cell);
    widgets.outline(stage);
    var controls = widgets.Lay{ .x = x, .y = @as(i32, @intFromFloat(stage.y + stage.height)) + widgets.GAP };
    for (SPEEDS, 0..) |s, i| {
        if (editor.modalButton(ed, g, controls.take(SPEED_W), s.label, v.speed == i, true, "How fast the stage plays")) v.speed = i;
    }
    if (editor.modalButton(ed, g, controls.take(SPEED_W), widgets.keyed("Replay", Desk.ENTER_CAPTION), false, true, "Start it again")) v.reset();
    modals.backButton(ed, g, f, page.bottom - widgets.ROW_H, "Close");
}

fn stageCell(room: P) f32 {
    for (ZOOMS) |z| {
        const cell = game.CELL_F * z;
        if (px(COLS, cell) <= @as(f32, @floatFromInt(room.x)) and px(ROWS, cell) <= @as(f32, @floatFromInt(room.y))) return cell;
    }
    return game.CELL_F * ZOOMS[ZOOMS.len - 1];
}

fn drawList(ed: *editor.Editor, g: *game.Game, v: *Viewer, box: rl.Rectangle) void {
    const scroll = v.list.at(box);
    if (v.reveal) {
        v.reveal = false;
        scroll.reveal(rowTop(v.at), widgets.ROW_H);
    }
    const top = scroll.begin(&ed.clip);
    const x: i32 = @intFromFloat(box.x);
    const w: i32 = @intFromFloat(box.width);
    var last: ?Group = null;
    for (SAMPLES, 0..) |s, i| {
        const y = top + rowTop(i);
        if (opens(&last, s)) widgets.heading(&g.face, GROUP_NAMES.get(s.group()), x, y - HEADER_STEP + widgets.GAP);
        if (widgets.flatButton(ed.controls(), &g.face, widgets.row(x, y, w - widgets.SCROLL_W - widgets.GAP), s.name(), look.TEXT, i == v.at, true, true, null)) v.pick(i);
    }
    scroll.close(&ed.clip, top + rowTop(SAMPLES.len - 1) + widgets.ROW_H, 0);
}

fn opens(last: *?Group, s: Sample) bool {
    if (last.* == s.group()) return false;
    last.* = s.group();
    return true;
}

fn rowTop(i: usize) i32 {
    var y: i32 = 0;
    var last: ?Group = null;
    for (SAMPLES[0 .. i + 1]) |s| {
        if (opens(&last, s)) y += HEADER_STEP;
        y += widgets.ROW_H;
    }
    return y - widgets.ROW_H;
}

fn drawStage(g: *game.Game, v: *Viewer, stage: rl.Rectangle, cell: f32) void {
    const s = v.sample();
    widgets.scissor(stage);
    defer rl.endScissorMode();
    const o = [2]f32{ stage.x - px(ORIGIN.x, cell), stage.y - px(ORIGIN.y, cell) };
    var cells = grid.Cells.of(ORIGIN, ORIGIN.add(.{ .x = COLS, .y = ROWS }));
    while (cells.next()) |p| panel.swatch(g, s.ground(), widgets.cellRect(o, p, cell));
    rl.drawRectangleRec(stage, SHADE);
    if (s == .fire_wall) {
        for (0..WALL_CELLS) |k| {
            const p = MIDDLE.add(.{ .x = @as(i32, @intCast(k)) - @divTrunc(WALL_CELLS, 2), .y = 0 });
            const r = widgets.cellRect(o, p, cell);
            var kin = game.scene.Kin.initEmpty();
            if (k > 0) kin.insert(.w);
            if (k + 1 < WALL_CELLS) kin.insert(.e);
            game.scene.drawFlames(&v.effects, r.x, r.y, cell, grid.Level.idx(p), kin, 1);
        }
    }
    drawPools(v, s, o, cell);
    const body = widgets.cellRect(o, MIDDLE, cell);
    const hero_at = mathx.centre(MIDDLE);
    if (s == .level_up) v.effects.level_up.drawBeam(hero_at, o[0], o[1], cell);
    v.effects.draw(o[0], o[1], cell);
    switch (s) {
        .mark, .level_up => panel.bodyFigure(g, actor.HERO, body),
        .torch => v.effects.drawTorch(body.x + cell / 2, body.y + cell / 2, cell, 0, 1, 1),
        .hit, .embers, .drip, .shimmer, .whirl, .arc, .missile, .net, .wisps, .glowbulb, .splash, .dust, .juke, .fire_wall => {},
    }
    v.effects.drawGlow(&v.lv, &v.sight, o[0], o[1], cell);
    if (v.shot) |*sh| if (sh.t >= 0) game.scene.drawFlight(sh, o, cell);
    switch (s) {
        .mark => |st| v.effects.drawStatus(st, .{ .x = body.x, .y = body.y, .cell = cell, .seed = 0, .ink = st.ink(), .alpha = 1, .stacks = sunder.MOST }),
        .level_up => {
            v.effects.level_up.drawSparks(hero_at, o[0], o[1], cell);
            v.effects.level_up.drawText(hero_at, &g.face, o[0], o[1], cell);
        },
        .hit, .embers, .drip, .shimmer, .whirl, .arc, .missile, .net, .wisps, .glowbulb, .splash, .dust, .juke, .torch, .fire_wall => {},
    }
}

fn drawPools(v: *const Viewer, s: Sample, o: [2]f32, cell: f32) void {
    var buf: [game.scene.EFFECT_SOURCES + 1]light.Emission = undefined;
    const mid = mathx.centre(MIDDLE);
    const shot: ?*const game.presentation.Shot = if (v.shot) |*sh| sh else null;
    var n = game.scene.effectSources(&v.effects, if (s == .level_up) mid else null, shot, buf[0..game.scene.EFFECT_SOURCES]).len;
    switch (s) {
        .mark => |st| if (st.emission(mid, v.effects.statusFlicker(0))) |e| std.debug.assert(mathx.push(light.Emission, &buf, &n, e)),
        .hit, .embers, .drip, .shimmer, .whirl, .arc, .missile, .net, .wisps, .glowbulb, .splash, .dust, .juke, .torch, .fire_wall, .level_up => {},
    }
    rl.beginBlendMode(.additive);
    defer rl.endBlendMode();
    for (buf[0..n]) |e| {
        const at = rl.Vector2{ .x = o[0] + e.at[0] * cell, .y = o[1] + e.at[1] * cell };
        rl.drawCircleGradient(@intFromFloat(at.x), @intFromFloat(at.y), e.radius * cell, look.fade(e.col, @min(1, e.gain * POOL_A)), rl.Color.blank);
    }
}

/// DEV ONLY.
pub fn pose(ed: *editor.Editor, want: Sample, seconds: f32) !void {
    const v = try viewer(ed);
    v.at = mathx.indexOfEql(Sample, &SAMPLES, want).?;
    v.speed = 0;
    var t: f32 = 0;
    while (t < seconds) : (t += POSE_STEP) v.step(POSE_STEP);
    ed.modal = .effects;
}

const POSE_STEP = mathx.FRAME_DT;
/// Ten seconds of frames: longer than any showing twice over.
const POSE_MOST: usize = 600;

test "every effect sample plays for two showings without leaving the stage's level changed" {
    const v = try create(std.testing.allocator);
    defer std.testing.allocator.destroy(v);
    const before = v.lv.tile;
    for (SAMPLES, 0..) |s, i| {
        v.pick(i);
        if (i == 0) v.reset();
        var steps: usize = 0;
        while (steps < POSE_MOST and (s.period() == null or v.round < 2)) : (steps += 1) v.step(POSE_STEP);
        try std.testing.expect(s.period() == null or v.round == 2);
    }
    try std.testing.expectEqualSlices(grid.Tile, &before, &v.lv.tile);
    var groups: usize = 0;
    var last: ?Group = null;
    for (SAMPLES) |s| {
        if (last != s.group()) groups += 1;
        last = s.group();
    }
    try std.testing.expectEqual(std.enums.values(Group).len, groups);
}

test "a missile sample lands its burst where its flight ends, as play does" {
    const v = try create(std.testing.allocator);
    defer std.testing.allocator.destroy(v);
    var bursting: usize = 0;
    for (SAMPLES, 0..) |s, i| {
        const a = switch (s) {
            .missile => |a| a,
            else => continue,
        };
        v.pick(i);
        v.reset();
        v.step(0);
        try std.testing.expect(v.shot.?.flight.len > 1);
        if (a.bursts()) {
            bursting += 1;
            try std.testing.expect(v.effects.impacts.count() > 0);
        }
    }
    try std.testing.expect(bursting > 0);
}
