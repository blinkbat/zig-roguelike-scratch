const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const hero = @import("../play/hero.zig");
const progress = @import("../play/progress.zig");
const passives = @import("../play/passives.zig");
const attrs = @import("../play/attrs.zig");
const items = @import("../play/items.zig");
const skillbar = @import("../play/skillbar.zig");
const damage = @import("../play/damage.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const hud = @import("hud.zig");
const menu = @import("menu.zig");
const input = @import("../core/input.zig");

const P = mathx.P;
pub const Panel = enum { skills, passives };
pub const View = struct { cursor: usize = 0, zoom: f32 = 1, pan: rl.Vector2 = .{ .x = 0, .y = 0 } };
pub const Loadout = struct { stats: attrs.Attrs, gear: items.Gear };
pub const ZOOM_MIN: f32 = 1;
pub const ZOOM_MAX: f32 = 3.2;
pub const ZOOM_START: f32 = 2.4;
pub const ZOOM_RATE: f32 = 1.7;
/// A press of a zoom button, and a notch of the wheel.
pub const ZOOM_STEP: f32 = 0.4;
pub const ZOOM_WHEEL: f32 = 0.2;
pub const PAN_RATE: f32 = 3.4;
const CANVAS = look.rect(24, 132, 696, 458);
const DETAIL = look.rect(744, 132, 332, 458);
const WHEEL = look.rect(44, 194, 656, 352);
/// Text and controls keep this far inside the canvas.
const INSET: i32 = 20;
const TEXT_X: i32 = @as(i32, @intFromFloat(DETAIL.x)) + INSET;
const TEXT_W: i32 = @as(i32, @intFromFloat(DETAIL.width)) - 2 * INSET;
const CANVAS_RIGHT: i32 = @as(i32, @intFromFloat(CANVAS.x + CANVAS.width)) - INSET;
const CANVAS_LEFT: i32 = @as(i32, @intFromFloat(CANVAS.x)) + INSET;
/// The middle of the canvas's foot row: legend and zoom.
const FOOT_Y: i32 = 568;
const LEGEND_STEP: i32 = 140;
const ZOOM_PX: i32 = 28;
const ZOOM_GAP: i32 = 14;
const BUTTON_H: i32 = 34;
const ACTION_Y: i32 = 540;
const BIND_Y: i32 = 470;
const REASON_Y: i32 = 512;
const HINT_Y: i32 = 610;
const HINT_STEP: i32 = 164;
/// The canvas's title row.
const TITLE_Y: i32 = 150;
const SKILL_SIZE: i32 = 56;
const SKILL_MID_X: i32 = 372;
const SKILL_STEP_X: i32 = 248;
const SKILL_TOP: i32 = 218;
const SKILL_STEP_Y: i32 = 126;
const BACK = look.rgb(0x0c0e12);
const TILE = look.rgb(0x15171c);
const BORDER = look.rgb(0x34373d);
const LOCKED = look.rgb(0x656773);
const AVAILABLE = look.rgb(0xbcc9ba);
const OWNED = look.UI_GOLD;
const FOCUS = look.UI_FOCUS;
const LINE = look.rgb(0x42413d);

pub fn cellBox(panel: Panel, o: P, class: hero.Class, i: usize, view: View) rl.Rectangle {
    return switch (panel) {
        .skills => skillBox(o, class, i),
        .passives => blk: {
            const layout = wheelLayout(o, view);
            const p = layout.at(i);
            const r = nodeRadius(i, layout.unit) + 3;
            const x = @max(layout.box.x, p.x - r);
            const y = @max(layout.box.y, p.y - r);
            break :blk .{ .x = x, .y = y, .width = @max(0, @min(layout.box.x + layout.box.width, p.x + r) - x), .height = @max(0, @min(layout.box.y + layout.box.height, p.y + r) - y) };
        },
    };
}

pub fn onCanvas(o: P, p: P) bool {
    return look.holds(placed(o, CANVAS), p);
}

pub fn zoomBox(o: P, increase: bool) rl.Rectangle {
    const right = CANVAS_RIGHT - if (increase) 0 else ZOOM_PX + ZOOM_GAP;
    return look.rect(o.x + right - ZOOM_PX, o.y + FOOT_Y - ZOOM_PX / 2, ZOOM_PX, ZOOM_PX);
}

pub fn draw(panel: Panel, face: *const font.Face, sprites: *const look.Sprites, o: P, class: hero.Class, growth: *const progress.State, view: View, device: input.Device, loadout: Loadout, surface: menu.Surface) void {
    switch (panel) {
        .skills => drawSkills(face, sprites, o, class, growth, view.cursor, loadout),
        .passives => {
            drawPassives(face, o, class, growth, view, surface);
            treeHints(face, o, device);
        },
    }
}

fn hint(face: *const font.Face, x: i32, y: i32, prompts: []const look.Prompt, label: [:0]const u8) void {
    var next = x;
    for (prompts) |prompt| {
        const w = prompt.width(face, font.BODY);
        prompt.draw(face, next + @divTrunc(w, 2), y, font.BODY, 1);
        next += w + 4;
    }
    face.draw(label, next + 2, y - 8, font.SMALL, look.DIM);
}

fn treeHints(face: *const font.Face, o: P, device: input.Device) void {
    const y = o.y + HINT_Y;
    const x = o.x + CANVAS_LEFT;
    const keys = input.TreeKeys;
    const pad = device.pad();
    const hints = [_]struct { pad: []const look.Prompt, keys: []const look.Prompt, label: [:0]const u8 }{
        .{ .pad = &.{.{ .stick = .left }}, .keys = &.{.{ .key = keys.BROWSE_CAPTION }}, .label = "Browse" },
        .{ .pad = &.{.{ .stick = .right }}, .keys = &.{ .{ .key = keys.PAN_CAPTION }, .arrows }, .label = "Pan" },
        .{ .pad = &.{.dpad}, .keys = &.{ .{ .key = keys.ZOOM_OUT_CAPTION }, .{ .key = keys.ZOOM_IN_CAPTION } }, .label = "Zoom" },
        .{ .pad = &.{look.Prompt.menuOn(device, keys.PAD_OVERVIEW)}, .keys = &.{.{ .key = keys.OVERVIEW_CAPTION }}, .label = "Overview" },
    };
    for (hints, 0..) |h, i| hint(face, x + @as(i32, @intCast(i)) * HINT_STEP, y, if (pad) h.pad else h.keys, h.label);
}

pub fn actionBox(o: P) rl.Rectangle {
    return look.rect(o.x + TEXT_X, o.y + ACTION_Y, TEXT_W, BUTTON_H);
}

pub fn bindBox(o: P) rl.Rectangle {
    return look.rect(o.x + TEXT_X, o.y + BIND_Y, TEXT_W, BUTTON_H);
}

fn placed(o: P, r: rl.Rectangle) rl.Rectangle {
    var out = r;
    out.x += @floatFromInt(o.x);
    out.y += @floatFromInt(o.y);
    return out;
}

fn skillBox(o: P, class: hero.Class, i: usize) rl.Rectangle {
    const skills = progress.skills(class);
    const at = skills[i].at;
    var last: i32 = 0;
    var across: usize = 0;
    for (skills) |s| {
        last = @max(last, s.at.y);
        across += @intFromBool(s.at.y == at.y);
    }
    const x = if (across == 1) SKILL_MID_X else SKILL_MID_X + (2 * at.x - 1) * @divExact(SKILL_STEP_X, 2);
    const y = if (last < 2) SKILL_TOP + 40 + at.y * 164 else SKILL_TOP + at.y * SKILL_STEP_Y;
    return look.rect(o.x + x - SKILL_SIZE / 2, o.y + y - SKILL_SIZE / 2, SKILL_SIZE, SKILL_SIZE);
}

fn frame(face: *const font.Face, o: P, title: [:0]const u8, points: u16) void {
    for ([_]rl.Rectangle{ CANVAS, DETAIL }) |r| {
        const box = placed(o, r);
        rl.drawRectangleRec(box, BACK);
        rl.drawRectangleLinesEx(box, 1, BORDER);
    }
    face.draw(title, o.x + CANVAS_LEFT, o.y + TITLE_Y, font.SMALL, look.TEXT);
    var line: menu.Note(64) = .{};
    line.say("{d} point{s} available", .{ points, mathx.plural(points) });
    face.draw(line.text(), o.x + CANVAS_RIGHT - face.width(line.text(), font.SMALL), o.y + TITLE_Y, font.SMALL, if (points > 0) OWNED else look.DIM);
}

const Legend = struct { name: [:0]const u8, color: rl.Color };

fn legend(face: *const font.Face, o: P, entries: []const Legend, round: bool) void {
    for (entries, 0..) |l, i| {
        const x = o.x + CANVAS_LEFT + @as(i32, @intCast(i)) * LEGEND_STEP;
        const y = o.y + FOOT_Y;
        if (round) ring(.{ .x = @floatFromInt(x + 5), .y = @floatFromInt(y) }, 4, l.color) else rl.drawRectangleLinesEx(look.rect(x, y - 5, 11, 11), 1, l.color);
        face.centred(l.name, x + 20 + @divTrunc(face.width(l.name, font.SMALL), 2), y, font.SMALL, l.color);
    }
}

pub fn paragraph(face: *const font.Face, text: []const u8, x: i32, y: i32, width: i32, ink: rl.Color) i32 {
    return hud.paragraph(face, text, x, y, width, font.SMALL, font.SMALL + hud.LEADING, ink);
}

fn arrow(from: rl.Rectangle, to: rl.Rectangle, ink: rl.Color) void {
    const a = rl.Vector2{ .x = from.x + from.width / 2, .y = from.y + from.height + 42 };
    const b = rl.Vector2{ .x = to.x + to.width / 2, .y = to.y - 8 };
    const elbow = (a.y + b.y) / 2;
    rl.drawLineEx(a, .{ .x = a.x, .y = elbow }, 1, ink);
    rl.drawLineEx(.{ .x = a.x, .y = elbow }, .{ .x = b.x, .y = elbow }, 1, ink);
    rl.drawLineEx(.{ .x = b.x, .y = elbow }, b, 1, ink);
    rl.drawLineEx(.{ .x = b.x - 4, .y = b.y - 5 }, b, 1, ink);
    rl.drawLineEx(.{ .x = b.x + 4, .y = b.y - 5 }, b, 1, ink);
}

const SkillState = enum {
    learned,
    available,
    locked,

    fn of(class: hero.Class, growth: *const progress.State, s: progress.Skill) SkillState {
        return if (growth.unlocked(s.act)) .learned else if (growth.canLearn(class, s.act)) .available else .locked;
    }

    fn ink(self: SkillState) rl.Color {
        return switch (self) {
            .learned => OWNED,
            .available => AVAILABLE,
            .locked => LOCKED,
        };
    }

    const LEGEND = blk: {
        var out: [std.enums.values(SkillState).len]Legend = undefined;
        for (std.enums.values(SkillState), &out) |s, *l| l.* = .{ .name = menu.named(s), .color = s.ink() };
        break :blk out;
    };
};

fn skillInk(class: hero.Class, growth: *const progress.State, s: progress.Skill) rl.Color {
    return SkillState.of(class, growth, s).ink();
}

fn skillAlpha(class: hero.Class, growth: *const progress.State, s: progress.Skill) f32 {
    if (growth.unlocked(s.act)) return 1;
    if (growth.canLearn(class, s.act)) return 0.8;
    if (s.parent) |p| if (!growth.unlocked(p)) return 0.3;
    return 0.55;
}

fn drawSkills(face: *const font.Face, sprites: *const look.Sprites, o: P, class: hero.Class, growth: *const progress.State, cursor: usize, loadout: Loadout) void {
    frame(face, o, "CLASS SKILLS", growth.active_points);
    const skills = progress.skills(class);
    for (skills, 0..) |s, i| if (s.parent) |parent| {
        for (skills, 0..) |p, j| if (p.act == parent) {
            arrow(skillBox(o, class, j), skillBox(o, class, i), if (growth.unlocked(parent)) OWNED else LINE);
        };
    };
    for (skills, 0..) |s, i| {
        const box = skillBox(o, class, i);
        const mid = look.middleAt(box);
        const ink = skillInk(class, growth, s);
        rl.drawRectangleRec(box, TILE);
        rl.drawRectangleLinesEx(box, 2, ink);
        if (i == cursor) rl.drawRectangleLinesEx(look.grown(box, 5), 2, FOCUS);
        look.drawSkill(sprites, s.act, mid.x - look.SKILL_PX / 2, mid.y - look.SKILL_PX / 2, skillAlpha(class, growth, s));
        const plaque = look.rect(mid.x + 10, mid.y + 16, 42, 22);
        rl.drawRectangleRec(plaque, BACK);
        rl.drawRectangleLinesEx(plaque, 1, ink);
        var rank: menu.Note(16) = .{};
        rank.say("{d}/{d}", .{ growth.ranks.get(s.act), progress.RANKS });
        const pm = look.middleAt(plaque);
        face.centred(rank.text(), pm.x, pm.y, font.SMALL, ink);
        face.drawMid(s.act.name(), mid.x, mid.y + 46, font.SMALL, if (growth.unlocked(s.act) or i == cursor) look.TEXT else LOCKED);
    }
    legend(face, o, &SkillState.LEGEND, false);
    skillDetails(face, o, class, growth, skills[cursor], loadout);
}

fn skillReason(class: hero.Class, growth: *const progress.State, s: progress.Skill, buf: *menu.Note(128)) [:0]const u8 {
    if (growth.ranks.get(s.act) == progress.RANKS) return "Maximum rank reached.";
    if (s.parent) |p| if (!growth.unlocked(p)) {
        buf.say("Learn {s} first.", .{p.name()});
        return buf.text();
    };
    if (growth.active_points < progress.POINT_COST) return "Requires " ++ ACTIVE_COST ++ ".";
    std.debug.assert(growth.canLearn(class, s.act));
    return if (growth.unlocked(s.act)) "Ready to upgrade. Costs " ++ ACTIVE_COST ++ "." else "Ready to learn. Costs " ++ ACTIVE_COST ++ ".";
}

fn drawAction(face: *const font.Face, o: P, label: [:0]const u8, enabled: bool) void {
    const box = actionBox(o);
    rl.drawRectangleRec(box, TILE);
    rl.drawRectangleLinesEx(box, if (enabled) 2 else 1, if (enabled) OWNED else BORDER);
    const mid = look.middleAt(box);
    face.centred(label, mid.x, mid.y, font.BODY, if (enabled) look.TEXT else LOCKED);
}

const Hit = progress.Hit;

fn skillHit(growth: *const progress.State, act: skillbar.Act, loadout: Loadout) ?Hit {
    return growth.hit(loadout.stats, loadout.gear, act);
}

fn hitText(act: skillbar.Act, hit: Hit, text: *menu.Note(128)) [:0]const u8 {
    if (hit.element) |e| {
        if (hit.physical.hi > 0) {
            text.say("Damage: {d}-{d} physical, {d}-{d} {s}", .{ hit.physical.lo, hit.physical.hi, e.lo, e.hi, @tagName(act.element().?) });
        } else {
            text.say("{s} damage: {d}-{d}", .{ menu.named(act.element().?), e.lo, e.hi });
        }
    } else text.say("Physical damage: {d}-{d}", .{ hit.physical.lo, hit.physical.hi });
    return text.text();
}

fn skillDetails(face: *const font.Face, o: P, class: hero.Class, growth: *const progress.State, s: progress.Skill, loadout: Loadout) void {
    const x = o.x + TEXT_X;
    face.draw(s.act.name(), x, o.y + 154, font.HEAD, look.TEXT);
    var rank: menu.Note(64) = .{};
    const learned = growth.unlocked(s.act);
    if (learned) rank.say("Rank {d} of {d}", .{ growth.ranks.get(s.act), progress.RANKS }) else rank.say("Not learned", .{});
    face.draw(rank.text(), x, o.y + 188, font.SMALL, skillInk(class, growth, s));
    var end = paragraph(face, s.act.desc(), x, o.y + 218, TEXT_W, look.TEXT);
    if (s.act.flavor()) |line| end = paragraph(face, line, x, end + 4, TEXT_W, look.DIM);
    var top = @max(o.y + 284, end + 12);
    rl.drawLine(x, top, x + TEXT_W, top, BORDER);
    top += 12;
    face.draw(if (learned) "CURRENT RANK" else "FIRST RANK", x, top, font.SMALL, look.DIM);
    top += 21;
    var text: menu.Note(128) = .{};
    const hit = skillHit(growth, s.act, loadout);
    if (hit) |h| {
        top = paragraph(face, hitText(s.act, h, &text), x, top, TEXT_W, look.TEXT);
        face.draw("Before critical hits and defenses.", x, top, font.SMALL, look.DIM);
        top += 18;
    }
    var usage: [64]u8 = undefined;
    var used = std.io.fixedBufferStream(&usage);
    growth.writeUsage(s.act, used.writer());
    text.say("{s}", .{used.getWritten()});
    text.buf[0] = std.ascii.toUpper(text.buf[0]);
    top = paragraph(face, text.text(), x, top, TEXT_W, look.TEXT);
    const maximum = growth.ranks.get(s.act) == progress.RANKS;
    var next = growth.*;
    if (!maximum) next.ranks.getPtr(s.act).* += 1;
    if (learned and !maximum) {
        top += 8;
        text.say("NEXT RANK  {d}", .{next.ranks.get(s.act)});
        face.draw(text.text(), x, top, font.SMALL, OWNED);
        top += 21;
        const changes = top;
        if (next.damageBonus(s.act) != growth.damageBonus(s.act)) {
            const next_hit = skillHit(&next, s.act, loadout).?;
            if (std.meta.eql(hit.?, next_hit)) {
                text.say("Rank damage bonus: +{d}% (was +{d}%)", .{ next.damageBonus(s.act), growth.damageBonus(s.act) });
            } else _ = hitText(s.act, next_hit, &text);
            top = paragraph(face, text.text(), x, top, TEXT_W, OWNED);
        }
        if (next.cost(s.act) != growth.cost(s.act)) {
            text.say("Mana cost: {d}", .{next.cost(s.act)});
            top = paragraph(face, text.text(), x, top, TEXT_W, OWNED);
        }
        if (next.cooldown(s.act) != growth.cooldown(s.act)) {
            text.say("Cooldown: {d} turns", .{next.cooldown(s.act)});
            top = paragraph(face, text.text(), x, top, TEXT_W, OWNED);
        }
        if (top == changes) face.draw("No further stat changes.", x, top, font.SMALL, look.DIM);
    }
    var reason: menu.Note(128) = .{};
    _ = paragraph(face, skillReason(class, growth, s, &reason), x, o.y + REASON_Y, TEXT_W, if (growth.canLearn(class, s.act)) OWNED else look.DIM);
    drawAction(face, o, if (maximum) "Maximum rank" else if (learned) "Upgrade skill" else "Learn skill", growth.canLearn(class, s.act));
}

const Layout = struct {
    box: rl.Rectangle,
    centre: rl.Vector2,
    unit: f32,

    fn at(self: Layout, i: usize) rl.Vector2 {
        const p = passives.unitPos(i);
        return .{ .x = self.centre.x + p.x * self.unit, .y = self.centre.y + p.y * self.unit };
    }
};

/// How far the wheel centres on the cursor: not at all at the overview, wholly at the closest zoom.
fn pullOf(zoom: f32) f32 {
    return (std.math.clamp(zoom, ZOOM_MIN, ZOOM_MAX) - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN);
}

/// `view.pan` within its zoom's reach, and never taking the view's middle off the wheel.
pub fn clampPan(view: View) rl.Vector2 {
    const limit = 1.6 + 6 * (1 - 1 / view.zoom);
    const reach: f32 = @floatFromInt(passives.RINGS);
    const focus = passives.unitPos(view.cursor);
    const pull = pullOf(view.zoom);
    return .{
        .x = std.math.clamp(std.math.clamp(view.pan.x, -limit, limit) + focus.x * pull, -reach, reach) - focus.x * pull,
        .y = std.math.clamp(std.math.clamp(view.pan.y, -limit, limit) + focus.y * pull, -reach, reach) - focus.y * pull,
    };
}

/// A Character message, over the tree canvas where no button covers it.
pub fn note(face: *const font.Face, o: P, text: [:0]const u8) void {
    face.drawMid(text, o.x + @as(i32, @intFromFloat(CANVAS.x + CANVAS.width / 2)), o.y + TITLE_Y, font.SMALL, look.TEXT);
}

fn wheelLayout(o: P, view: View) Layout {
    const box = placed(o, WHEEL);
    const zoom = std.math.clamp(view.zoom, ZOOM_MIN, ZOOM_MAX);
    const unit = @min(box.width, box.height) / (2 * (@as(f32, @floatFromInt(passives.RINGS)) + 0.63)) * zoom;
    const focus = passives.unitPos(view.cursor);
    const pull = pullOf(zoom);
    var layout = Layout{ .box = box, .unit = unit, .centre = .{
        .x = box.x + box.width / 2 - focus.x * unit * pull,
        .y = box.y + box.height / 2 - focus.y * unit * pull,
    } };
    const selected = layout.at(view.cursor);
    const margin = nodeRadius(view.cursor, unit) + 7;
    layout.centre.x += std.math.clamp(selected.x, box.x + margin, box.x + box.width - margin) - selected.x;
    layout.centre.y += std.math.clamp(selected.y, box.y + margin, box.y + box.height - margin) - selected.y;
    layout.centre.x -= view.pan.x * unit;
    layout.centre.y -= view.pan.y * unit;
    return layout;
}

fn nodeRadius(i: usize, unit: f32) f32 {
    if (i == passives.HUB) return @max(8, unit * 0.26);
    const n = passives.NODES[i];
    if (n.ring == 0) return @max(8, unit * 0.26);
    if (n.seam != null) return @max(8, unit * 0.23);
    return switch (n.tier) {
        .stat => @max(5, unit * 0.15),
        .interest => @max(7, unit * 0.21),
        .capstone => @max(10, unit * 0.30),
    };
}

fn armInk(arm: passives.Arm) rl.Color {
    return switch (arm) {
        .warrior => look.rgb(0x9b7870),
        .rogue => look.rgb(0x82917c),
        .wizard => look.rgb(0x7c89a3),
    };
}

fn armName(arm: passives.Arm) [:0]const u8 {
    return arm.class().title();
}

fn armInitial(arm: passives.Arm) [:0]const u8 {
    return switch (arm) {
        inline else => |a| comptime &[_:0]u8{a.class().title()[0]},
    };
}

const ACTIVE_COST = std.fmt.comptimePrint("{d} active point{s}", .{ progress.POINT_COST, mathx.plural(progress.POINT_COST) });
const PASSIVE_COST = std.fmt.comptimePrint("{d} passive point{s}", .{ progress.POINT_COST, mathx.plural(progress.POINT_COST) });

fn ring(p: rl.Vector2, radius: f32, ink: rl.Color) void {
    rl.drawCircleLines(@intFromFloat(@round(p.x)), @intFromFloat(@round(p.y)), radius, ink);
}

const NodeState = enum {
    allocated,
    reachable,
    distant,

    fn of(growth: *const progress.State, i: usize) NodeState {
        return if (growth.nodes.isSet(i)) .allocated else if (growth.available(i)) .reachable else .distant;
    }

    /// A distant node on the wheel takes its arm's ink; the legend shows it locked.
    fn ink(self: NodeState) rl.Color {
        return switch (self) {
            .allocated => OWNED,
            .reachable => AVAILABLE,
            .distant => LOCKED,
        };
    }

    const LEGEND = blk: {
        var out: [std.enums.values(NodeState).len]Legend = undefined;
        for (std.enums.values(NodeState), &out) |s, *l| l.* = .{ .name = menu.named(s), .color = s.ink() };
        break :blk out;
    };
};

fn nodeInk(growth: *const progress.State, i: usize) rl.Color {
    const state = NodeState.of(growth, i);
    return if (state == .distant) armInk(passives.NODES[i].arm) else state.ink();
}

fn groupInk(g: passives.Group) rl.Color {
    return switch (g) {
        .attribute => look.rgb(0xb3a888),
        .life => look.rgb(0xb24a40),
        .mana => look.rgb(0x5b8bd0),
        .offense => look.rgb(0xc98a3a),
        .defense => look.rgb(0x8d98a4),
    };
}

const GROUP_LEGEND = blk: {
    var out: [std.enums.values(passives.Group).len]Legend = undefined;
    for (std.enums.values(passives.Group), &out) |g, *l| l.* = .{ .name = menu.named(g), .color = groupInk(g) };
    break :blk out;
};
const GROUP_STEP: i32 = 112;

fn grantNote(g: passives.Grant, whole: bool) menu.Note(100) {
    var out: menu.Note(100) = .{};
    var s = std.io.fixedBufferStream(out.buf[0..100]);
    if (whole) g.write(s.writer()) else g.writeAmount(s.writer());
    out.n = s.pos;
    out.buf[out.n] = 0;
    return out;
}

/// Stat labels show from this many pixels per ring, where none overlaps another label or node.
const LABEL_UNIT: f32 = 55;
/// What a TINY character is taken to span when testing label room.
const LABEL_CHAR_PX: f32 = 6.5;
const LABEL_GAP: f32 = 2;

fn labelTop(p: rl.Vector2, r: f32) f32 {
    return p.y + r + LABEL_GAP;
}

fn nodeLabel(face: *const font.Face, n: passives.Node, p: rl.Vector2, r: f32, state: NodeState) void {
    var amount = grantNote(n.grant, false);
    const top: i32 = @intFromFloat(@round(labelTop(p, r)));
    const x: i32 = @intFromFloat(@round(p.x));
    const w = @max(face.width(amount.text(), font.TINY), face.width(n.word(), font.TINY)) + 4;
    rl.drawRectangle(x - @divTrunc(w, 2), top, w, 2 * font.TINY + 1, look.fade(BACK, 0.85));
    face.drawMid(amount.text(), x, top, font.TINY, if (state == .distant) LOCKED else look.TEXT);
    face.drawMid(n.word(), x, top + font.TINY, font.TINY, if (state == .distant) LOCKED else look.DIM);
}

fn passiveLink(layout: Layout, pos: *const Positions, growth: *const progress.State, from: usize, to: usize) void {
    const before = from == passives.HUB or growth.nodes.isSet(from);
    const after = growth.nodes.isSet(to);
    const bridge = from != passives.HUB and passives.NODES[from].seam != null;
    const ink = if (before and after) OWNED else if (before or (bridge and after)) look.rgb(0x77705a) else LINE;
    const a = pos[from];
    const b = pos[to];
    rl.drawLineEx(a, b, if (before and after) 2 else 1, ink);
    if (from != passives.HUB and !bridge) {
        const length = std.math.hypot(b.x - a.x, b.y - a.y);
        const dx = (b.x - a.x) / length;
        const dy = (b.y - a.y) / length;
        const tip = rl.Vector2{ .x = b.x - dx * (nodeRadius(to, layout.unit) + 3), .y = b.y - dy * (nodeRadius(to, layout.unit) + 3) };
        for ([_]f32{ -1, 1 }) |side| rl.drawLineEx(.{ .x = tip.x - dx * 4 - dy * side * 2.5, .y = tip.y - dy * 4 + dx * side * 2.5 }, tip, 1, ink);
    }
}

/// Every node's place on the wheel, and the hub's last.
const Positions = [passives.N + 1]rl.Vector2;

fn drawPassives(face: *const font.Face, o: P, class: hero.Class, growth: *const progress.State, view: View, surface: menu.Surface) void {
    frame(face, o, "PASSIVE TREE", growth.passive_points);
    for (GROUP_LEGEND, 0..) |l, k| {
        const x = o.x + 44 + @as(i32, @intCast(k)) * GROUP_STEP;
        rl.drawCircle(x + 5, o.y + 182, 5, l.color);
        face.draw(l.name, x + 16, o.y + 174, font.SMALL, look.DIM);
    }
    const layout = wheelLayout(o, view);
    var pos: Positions = undefined;
    for (&pos, 0..) |*q, i| q.* = layout.at(i);
    surface.clip(layout.box);
    for (passives.NODES, 0..) |n, i| {
        if (n.ring == 0) passiveLink(layout, &pos, growth, passives.HUB, i);
        if (n.seam != null) continue;
        var buf: [passives.MAX_FEED]usize = undefined;
        for (passives.feeders(i, &buf)) |parent| passiveLink(layout, &pos, growth, parent, i);
    }
    const hub = pos[passives.HUB];
    rl.drawCircleV(hub, nodeRadius(passives.HUB, layout.unit), TILE);
    ring(hub, nodeRadius(passives.HUB, layout.unit), BORDER);
    rl.drawCircleV(hub, 2, OWNED);
    const labelled = layout.unit >= LABEL_UNIT;
    for (passives.NODES, 0..) |n, i| {
        const p = pos[i];
        const r = nodeRadius(i, layout.unit);
        const ink = nodeInk(growth, i);
        const state = NodeState.of(growth, i);
        const fill = groupInk(n.grant.kind.group());
        if (state == .allocated) {
            rl.drawCircleV(p, r, fill);
            ring(p, r + 1, OWNED);
        } else {
            rl.drawCircleV(p, r, TILE);
            rl.drawCircleV(p, r * 0.55, if (state == .distant) look.fade(fill, 0.45) else fill);
        }
        ring(p, r, ink);
        const mark = if (state == .allocated) BACK else ink;
        if (n.tier == .capstone) ring(p, r - 3, mark);
        if (n.ring == 0) {
            face.centred(armInitial(n.arm), @intFromFloat(@round(p.x)), @intFromFloat(@round(p.y)), font.SMALL, if (state == .allocated) BACK else look.TEXT);
        } else if (n.seam) |s| {
            for ([_]f32{ -2, 2 }) |dy| rl.drawLineEx(.{ .x = p.x - 3, .y = p.y + dy }, .{ .x = p.x + 3, .y = p.y + dy }, 1, if (state == .allocated) BACK else armInk(s.to()));
        }
        if (labelled and progress.bonusAt(class, i) != null) nodeLabel(face, n, p, r, state);
    }
    ring(pos[view.cursor], nodeRadius(view.cursor, layout.unit) + 5, FOCUS);
    rl.endScissorMode();
    legend(face, o, &NodeState.LEGEND, true);
    for ([_]bool{ false, true }) |increase| {
        const box = zoomBox(o, increase);
        const enabled = if (increase) view.zoom < ZOOM_MAX else view.zoom > ZOOM_MIN;
        rl.drawRectangleRec(box, TILE);
        rl.drawRectangleLinesEx(box, 1, if (enabled) AVAILABLE else BORDER);
        const mid = look.middleAt(box);
        face.centred(if (increase) "+" else "-", mid.x, mid.y, font.BODY, if (enabled) look.TEXT else LOCKED);
    }
    var zoom: menu.Note(16) = .{};
    zoom.say("{d:.1}x", .{view.zoom});
    const minus: i32 = @intFromFloat(zoomBox(o, false).x);
    face.centred(zoom.text(), minus - ZOOM_GAP - @divTrunc(face.width(zoom.text(), font.SMALL), 2), o.y + FOOT_Y, font.SMALL, look.DIM);
    passiveDetails(face, o, class, growth, view.cursor);
}

fn grantRow(face: *const font.Face, x: i32, y: i32, grant: passives.Grant) i32 {
    var text = grantNote(grant, true);
    return hud.paragraph(face, text.text(), x, y, TEXT_W, font.BODY, font.BODY + hud.LEADING, look.WARD);
}

/// What the grants alone leave unsaid.
fn grantNoteOf(n: passives.Node, origin: bool, out: *menu.Note(128)) ?[:0]const u8 {
    if (n.seam != null) return "Connects both paths. Reach this bridge from either side.";
    if (n.ring == 0 and !origin) return "Another class origin can be allocated directly.";
    for ([_]?passives.Grant{ n.grant, n.bump }) |maybe| {
        const g = maybe orelse continue;
        switch (g.kind) {
            .armour => {
                out.say("Armour reduces physical harm by 1% per point, up to {d}% total.", .{attrs.ARMOUR_MAX});
                return out.text();
            },
            .dodge => {
                out.say("Dodge is capped at {d}%.", .{attrs.DODGE_MAX});
                return out.text();
            },
            .life_on_kill => return "Kills by burning, bleeding or gas do not heal.",
            .cull => return "Applies to every foe a blow damages.",
            .mana_regen => return "Added to the base recovery of 1 mana per turn.",
            .mana_cost => return "Adds to the reduction from skill ranks.",
            .life_flask => return "Increases what each life flask drink recovers.",
            else => {},
        }
    }
    return null;
}

fn passiveDetails(face: *const font.Face, o: P, class: hero.Class, growth: *const progress.State, i: usize) void {
    const n = passives.NODES[i];
    const x = o.x + TEXT_X;
    const allocated = growth.nodes.isSet(i);
    const reachable = growth.available(i);
    const origin = progress.bonusAt(class, i) == null;
    const enabled = growth.canAllocate(i);
    face.draw(if (n.ring == 0) "CLASS ORIGIN" else if (n.seam != null) "BRIDGE NODE" else switch (n.tier) {
        .stat => "STAT NODE",
        .interest => "INTEREST NODE",
        .capstone => "CAPSTONE",
    }, x, o.y + TITLE_Y, font.SMALL, look.DIM);
    var y = o.y + 177;
    if (origin) {
        y = hud.paragraph(face, "No bonus: your class attributes already include it.", x, y, TEXT_W, font.BODY, font.BODY + hud.LEADING, look.TEXT);
    } else {
        y = grantRow(face, x, y, n.grant);
        if (n.bump) |bump| y = grantRow(face, x, y, bump);
    }
    y += 10;
    var path: menu.Note(96) = .{};
    if (n.branch) |branch| {
        path.say("{s}  -  {s} / {s}", .{ n.name, armName(n.arm), branch.name() });
    } else if (n.seam) |s| {
        path.say("{s}  -  {s} / {s} bridge", .{ n.name, armName(s.from()), armName(s.to()) });
    } else {
        path.say("{s}  -  {s} origin", .{ n.name, armName(n.arm) });
    }
    y = paragraph(face, path.text(), x, y, TEXT_W, look.DIM);
    y += 6;
    face.draw(if (origin) "Free class origin" else menu.named(NodeState.of(growth, i)), x, y, font.SMALL, nodeInk(growth, i));
    y += font.SMALL + 14;
    rl.drawLine(x, y, x + TEXT_W, y, BORDER);
    var note_buf: menu.Note(128) = .{};
    if (grantNoteOf(n, origin, &note_buf)) |line| _ = paragraph(face, line, x, y + 12, TEXT_W, look.DIM);
    const reason: []const u8 = if (origin) "Your class starts here for free." else if (allocated) "This passive is already allocated." else if (!reachable) "Allocate a prerequisite first." else if (growth.passive_points < progress.POINT_COST) "Requires " ++ PASSIVE_COST ++ "." else "Ready to allocate. Costs " ++ PASSIVE_COST ++ ".";
    _ = paragraph(face, reason, x, o.y + REASON_Y, TEXT_W, if (enabled) OWNED else look.DIM);
    drawAction(face, o, if (origin) "Class origin" else if (allocated) "Allocated" else "Allocate passive", enabled);
}

test "every class skill stays in its canvas and is reachable by directional selection" {
    var checked: usize = 0;
    for (hero.CLASSES) |class| {
        const skills = progress.skills(class);
        var boxes: [progress.NODES.len]rl.Rectangle = undefined;
        const o = P{ .x = 137, .y = 81 };
        const area = placed(o, CANVAS);
        for (skills, 0..) |_, i| {
            const box = skillBox(o, class, i);
            boxes[i] = box;
            try std.testing.expect(box.x >= area.x and box.y >= area.y);
            try std.testing.expect(box.x + box.width + 24 <= area.x + area.width);
            try std.testing.expect(box.y + box.height + 62 <= area.y + area.height);
            for (boxes[0..i]) |other| {
                const overlaps = box.x < other.x + other.width and other.x < box.x + box.width and
                    box.y < other.y + other.height and other.y < box.y + box.height;
                try std.testing.expect(!overlaps);
            }
        }
        var reached = std.StaticBitSet(progress.NODES.len).initEmpty();
        reached.set(0);
        for (0..skills.len) |_| {
            for (boxes[0..skills.len], 0..) |box, i| {
                if (!reached.isSet(i)) continue;
                for (mathx.ALL_DIRS) |dir| {
                    if (menu.nearest(box, boxes[0..skills.len], dir, @import("book.zig").CELL_ACROSS)) |next| reached.set(next);
                }
            }
        }
        try std.testing.expectEqual(skills.len, reached.count());
        checked += skills.len;
    }
    std.debug.print("class skill diagrams: {d} non-overlapping tiles within their canvas; all reachable in 8 directions\n", .{checked});
}

test "passive diagram fits all nodes and retains its selected node through zoom" {
    const o = P{ .x = 73, .y = 41 };
    const layout = wheelLayout(o, .{});
    for (passives.NODES, 0..) |_, i| {
        const p = layout.at(i);
        const r = nodeRadius(i, layout.unit) + 5;
        try std.testing.expect(p.x - r >= layout.box.x and p.y - r >= layout.box.y);
        try std.testing.expect(p.x + r <= layout.box.x + layout.box.width and p.y + r <= layout.box.y + layout.box.height);
        for (0..i) |j| {
            const other = layout.at(j);
            const distance = std.math.hypot(p.x - other.x, p.y - other.y);
            try std.testing.expect(distance > nodeRadius(i, layout.unit) + nodeRadius(j, layout.unit) + 2);
        }
        for ([_]f32{ 1, 1.4, 1.8, 2.2, 2.6, 3.2 }) |zoom| {
            const view = View{ .cursor = i, .zoom = zoom };
            const zoomed = wheelLayout(o, view);
            const at = zoomed.at(i);
            const radius = nodeRadius(i, zoomed.unit) + 5;
            try std.testing.expect(at.x - radius >= zoomed.box.x and at.y - radius >= zoomed.box.y);
            try std.testing.expect(at.x + radius <= zoomed.box.x + zoomed.box.width and at.y + radius <= zoomed.box.y + zoomed.box.height);
            const hit = cellBox(.passives, o, .knight, i, view);
            try std.testing.expect(hit.width > 0 and hit.height > 0);
            for (0..passives.N) |j| {
                const clipped = cellBox(.passives, o, .knight, j, view);
                if (clipped.width <= 0 or clipped.height <= 0) continue;
                try std.testing.expect(clipped.x >= zoomed.box.x and clipped.y >= zoomed.box.y);
                try std.testing.expect(clipped.x + clipped.width <= zoomed.box.x + zoomed.box.width + 0.001);
                try std.testing.expect(clipped.y + clipped.height <= zoomed.box.y + zoomed.box.height + 0.001);
            }
        }
    }
    std.debug.print("passive diagram: all {d} nodes fit without overlap; selected node and clipped hit targets checked at six zoom levels\n", .{passives.N});
}

fn labelBox(layout: Layout, i: usize) rl.Rectangle {
    const n = passives.NODES[i];
    var amount = grantNote(n.grant, false);
    const chars = @max(amount.text().len, n.word().len);
    const w = @as(f32, @floatFromInt(chars)) * LABEL_CHAR_PX;
    const p = layout.at(i);
    return .{ .x = p.x - w / 2, .y = labelTop(p, nodeRadius(i, layout.unit)), .width = w, .height = 2 * font.TINY };
}

fn labelsClear(unit: f32) bool {
    const layout = Layout{ .box = look.rect(0, 0, 1, 1), .centre = .{ .x = 0, .y = 0 }, .unit = unit };
    for (0..passives.N) |i| {
        const box = labelBox(layout, i);
        for (0..passives.N + 1) |j| {
            const p = layout.at(j);
            const r = nodeRadius(j, unit);
            if (rl.checkCollisionCircleRec(p, r, box)) return false;
            if (j != i and j < passives.N and rl.checkCollisionRecs(box, labelBox(layout, j))) return false;
        }
    }
    return true;
}

test "stat labels show only where none overlaps another label or node" {
    var least: f32 = 10;
    while (!labelsClear(least)) least += 1;
    const o = P{ .x = 0, .y = 0 };
    const start = wheelLayout(o, .{ .zoom = ZOOM_START }).unit;
    const overview = wheelLayout(o, .{ .zoom = ZOOM_MIN }).unit;
    std.debug.print("passive labels: clear from {d:.0} px per ring; shown from {d:.0}; opening view {d:.1}, overview {d:.1}\n", .{ least, LABEL_UNIT, start, overview });
    try std.testing.expect(LABEL_UNIT >= least);
    try std.testing.expect(start >= LABEL_UNIT);
    for ([_]f32{ LABEL_UNIT, LABEL_UNIT * 1.5, 200 }) |unit| try std.testing.expect(labelsClear(unit));
}

test "panning as far as it goes from any node never leaves the canvas empty" {
    const o = P{ .x = 0, .y = 0 };
    var fewest: usize = passives.N;
    for (0..passives.N) |i| {
        for ([_]f32{ 1, 2.2, 3.2 }) |zoom| {
            for ([_][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 }, .{ 1, 0 }, .{ 0, 1 } }) |way| {
                var view = View{ .cursor = i, .zoom = zoom, .pan = .{ .x = way[0] * 100, .y = way[1] * 100 } };
                view.pan = clampPan(view);
                const layout = wheelLayout(o, view);
                var shown: usize = 0;
                for (0..passives.N) |j| {
                    if (rl.checkCollisionPointRec(layout.at(j), layout.box)) shown += 1;
                }
                fewest = @min(fewest, shown);
            }
        }
    }
    std.debug.print("passive pan: at least {d} nodes stay on the canvas at the furthest pan from any node\n", .{fewest});
    try std.testing.expect(fewest > 0);
}
