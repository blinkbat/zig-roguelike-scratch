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
pub const ZOOM_START: f32 = 2.2;
pub const ZOOM_RATE: f32 = 1.7;
pub const PAN_RATE: f32 = 3.4;
const CANVAS = look.rect(24, 132, 696, 458);
const DETAIL = look.rect(744, 132, 332, 458);
const WHEEL = look.rect(44, 194, 656, 352);
const TEXT_X: i32 = 764;
const TEXT_W: i32 = 292;
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
    return look.rect(o.x + @as(i32, if (increase) 664 else 622), o.y + 551, 28, 28);
}

pub fn draw(panel: Panel, face: *const font.Face, sprites: *const look.Sprites, o: P, class: hero.Class, growth: *const progress.State, view: View, focused: bool, device: input.Device, loadout: Loadout, surface: menu.Surface) void {
    switch (panel) {
        .skills => drawSkills(face, sprites, o, class, growth, view.cursor, focused, loadout),
        .passives => {
            drawPassives(face, o, class, growth, view, focused, surface);
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
    const y = o.y + 602;
    if (device.pad()) {
        const st = input.State{ .device = device };
        hint(face, o.x + 44, y, &.{.{ .stick = .left }}, "Browse");
        hint(face, o.x + 208, y, &.{.{ .stick = .right }}, "Pan");
        hint(face, o.x + 372, y, &.{.dpad}, "Zoom");
        hint(face, o.x + 536, y, &.{look.Prompt.menuOf(&st, .inspect)}, "Overview");
    } else {
        hint(face, o.x + 44, y, &.{.{ .key = "WASD" }}, "Browse");
        hint(face, o.x + 208, y, &.{ .{ .key = input.Desk.SHIFT_NAME }, .arrows }, "Pan");
        hint(face, o.x + 372, y, &.{ .{ .key = "-" }, .{ .key = "+" } }, "Zoom");
        hint(face, o.x + 536, y, &.{.{ .key = "Home" }}, "Overview");
    }
}

pub fn actionBox(o: P) rl.Rectangle {
    return look.rect(o.x + TEXT_X, o.y + 538, TEXT_W, 36);
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
    face.draw(title, o.x + 44, o.y + 150, font.SMALL, look.TEXT);
    var line: menu.Note(64) = .{};
    line.say("{d} point{s} available", .{ points, if (points == 1) @as([]const u8, "") else "s" });
    face.drawMid(line.text(), o.x + 598, o.y + 150, font.SMALL, if (points > 0) OWNED else look.DIM);
}

fn paragraph(face: *const font.Face, text: []const u8, x: i32, y: i32, width: i32, ink: rl.Color) i32 {
    var buf: [hud.TIP_LINES_MAX][hud.TIP_COLS_MAX + 1]u8 = undefined;
    var lines: [hud.TIP_LINES_MAX][:0]const u8 = undefined;
    const count = hud.wrap(face, text, font.SMALL, width, &buf, &lines);
    for (lines[0..count], 0..) |line, i| face.draw(line, x, y + @as(i32, @intCast(i)) * 20, font.SMALL, ink);
    return y + @as(i32, @intCast(count)) * 20;
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

fn skillInk(class: hero.Class, growth: *const progress.State, s: progress.Skill) rl.Color {
    return if (growth.unlocked(s.act)) OWNED else if (growth.canLearn(class, s.act)) AVAILABLE else LOCKED;
}

fn skillAlpha(class: hero.Class, growth: *const progress.State, s: progress.Skill) f32 {
    if (growth.unlocked(s.act)) return 1;
    if (growth.canLearn(class, s.act)) return 0.8;
    if (s.parent) |p| if (!growth.unlocked(p)) return 0.3;
    return 0.55;
}

fn drawSkills(face: *const font.Face, sprites: *const look.Sprites, o: P, class: hero.Class, growth: *const progress.State, cursor: usize, focused: bool, loadout: Loadout) void {
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
        if (focused and i == cursor) rl.drawRectangleLinesEx(look.grown(box, 5), 2, FOCUS);
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
    skillLegend(face, o);
    skillDetails(face, o, class, growth, skills[cursor], focused, loadout);
}

fn skillLegend(face: *const font.Face, o: P) void {
    const legends = [_]struct { name: [:0]const u8, color: rl.Color }{
        .{ .name = "Learned", .color = OWNED },
        .{ .name = "Available", .color = AVAILABLE },
        .{ .name = "Locked", .color = LOCKED },
    };
    for (legends, 0..) |l, i| {
        const x = o.x + 112 + @as(i32, @intCast(i)) * 182;
        rl.drawRectangleLinesEx(look.rect(x, o.y + 563, 11, 11), 1, l.color);
        face.draw(l.name, x + 20, o.y + 561, font.SMALL, l.color);
    }
}

fn skillReason(class: hero.Class, growth: *const progress.State, s: progress.Skill, buf: *menu.Note(128)) [:0]const u8 {
    if (growth.ranks.get(s.act) == progress.RANKS) return "Maximum rank reached.";
    if (s.parent) |p| if (!growth.unlocked(p)) {
        buf.say("Learn {s} first.", .{p.name()});
        return buf.text();
    };
    if (growth.active_points == 0) return "Requires 1 active point.";
    std.debug.assert(growth.canLearn(class, s.act));
    return if (growth.unlocked(s.act)) "Ready to upgrade. Costs 1 active point." else "Ready to learn. Costs 1 active point.";
}

fn drawAction(face: *const font.Face, o: P, label: [:0]const u8, enabled: bool, focused: bool) void {
    const box = actionBox(o);
    rl.drawRectangleRec(box, TILE);
    rl.drawRectangleLinesEx(box, if (enabled and focused) 2 else 1, if (enabled) OWNED else BORDER);
    const mid = look.middleAt(box);
    face.centred(label, mid.x, mid.y, font.BODY, if (enabled) look.TEXT else LOCKED);
}

const Hit = struct { physical: damage.Span, element: ?damage.Span };

fn skillHit(growth: *const progress.State, act: skillbar.Act, loadout: Loadout) ?Hit {
    const attack = act.attack() orelse return null;
    const bases = act.equippedBases(loadout.gear);
    const by = growth.skillAttrs(loadout.stats, loadout.gear, act);
    const style = loadout.gear.scaling(attack);
    return .{ .physical = by.span(style, bases.physical()), .element = if (bases.element) |b| by.span(style, b) else null };
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

fn skillDetails(face: *const font.Face, o: P, class: hero.Class, growth: *const progress.State, s: progress.Skill, focused: bool, loadout: Loadout) void {
    const x = o.x + TEXT_X;
    face.draw(s.act.name(), x, o.y + 154, font.HEAD, look.TEXT);
    var rank: menu.Note(64) = .{};
    const learned = growth.unlocked(s.act);
    if (learned) rank.say("Rank {d} of {d}", .{ growth.ranks.get(s.act), progress.RANKS }) else rank.say("Not learned", .{});
    face.draw(rank.text(), x, o.y + 188, font.SMALL, skillInk(class, growth, s));
    const end = paragraph(face, s.act.desc(), x, o.y + 218, TEXT_W, look.TEXT);
    var top = @max(o.y + 284, end + 12);
    rl.drawLine(x, top, x + TEXT_W, top, BORDER);
    top += 12;
    face.draw(if (learned) "CURRENT RANK" else "FIRST RANK", x, top, 16, look.DIM);
    top += 21;
    var text: menu.Note(128) = .{};
    const hit = skillHit(growth, s.act, loadout);
    if (hit) |h| {
        top = paragraph(face, hitText(s.act, h, &text), x, top, TEXT_W, look.TEXT);
        face.draw("Before critical hits and defenses.", x, top, 16, look.DIM);
        top += 18;
    }
    var usage: menu.Note(64) = .{};
    const turn: []const u8 = if (s.act.turns() == 0) "Free action" else "1 turn";
    if (growth.cost(s.act) > 0) usage.say("{d} mana / {s}", .{ growth.cost(s.act), turn }) else usage.say("{s}", .{turn});
    if (growth.cooldown(s.act) > 0) text.say("{s} / {d}-turn cooldown", .{ usage.text(), growth.cooldown(s.act) }) else text.say("{s}", .{usage.text()});
    top = paragraph(face, text.text(), x, top, TEXT_W, look.TEXT);
    const maximum = growth.ranks.get(s.act) == progress.RANKS;
    var next = growth.*;
    if (!maximum) next.ranks.getPtr(s.act).* += 1;
    if (learned and !maximum) {
        top += 8;
        text.say("NEXT RANK  {d}", .{next.ranks.get(s.act)});
        face.draw(text.text(), x, top, 16, OWNED);
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
    _ = paragraph(face, skillReason(class, growth, s, &reason), x, o.y + 499, TEXT_W, if (growth.canLearn(class, s.act)) OWNED else look.DIM);
    drawAction(face, o, if (maximum) "Maximum rank" else if (learned) "Upgrade skill" else "Learn skill", growth.canLearn(class, s.act), focused);
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

fn wheelLayout(o: P, view: View) Layout {
    const box = placed(o, WHEEL);
    const zoom = std.math.clamp(view.zoom, ZOOM_MIN, ZOOM_MAX);
    const unit = @min(box.width, box.height) / (2 * (@as(f32, @floatFromInt(passives.RINGS)) + 0.63)) * zoom;
    const focus = passives.unitPos(view.cursor);
    const pull = (zoom - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN);
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
    return switch (arm) {
        .warrior => "Knight",
        .rogue => "Archer",
        .wizard => "Wizard",
    };
}

fn ring(p: rl.Vector2, radius: f32, ink: rl.Color) void {
    rl.drawCircleLines(@intFromFloat(@round(p.x)), @intFromFloat(@round(p.y)), radius, ink);
}

fn nodeInk(growth: *const progress.State, i: usize) rl.Color {
    if (growth.nodes.isSet(i)) return OWNED;
    if (growth.available(i)) return AVAILABLE;
    return armInk(passives.NODES[i].arm);
}

fn passiveLink(layout: Layout, growth: *const progress.State, from: usize, to: usize) void {
    const before = from == passives.HUB or growth.nodes.isSet(from);
    const after = growth.nodes.isSet(to);
    const bridge = from != passives.HUB and passives.NODES[from].seam != null;
    const ink = if (before and after) OWNED else if (before or (bridge and after)) look.rgb(0x77705a) else LINE;
    const a = layout.at(from);
    const b = layout.at(to);
    rl.drawLineEx(a, b, if (before and after) 2 else 1, ink);
    if (from != passives.HUB and !bridge) {
        const length = std.math.hypot(b.x - a.x, b.y - a.y);
        const dx = (b.x - a.x) / length;
        const dy = (b.y - a.y) / length;
        const tip = rl.Vector2{ .x = b.x - dx * (nodeRadius(to, layout.unit) + 3), .y = b.y - dy * (nodeRadius(to, layout.unit) + 3) };
        for ([_]f32{ -1, 1 }) |side| rl.drawLineEx(.{ .x = tip.x - dx * 4 - dy * side * 2.5, .y = tip.y - dy * 4 + dx * side * 2.5 }, tip, 1, ink);
    }
}

fn drawPassives(face: *const font.Face, o: P, class: hero.Class, growth: *const progress.State, view: View, focused: bool, surface: menu.Surface) void {
    frame(face, o, "PASSIVE TREE", growth.passive_points);
    face.draw("Small: stat   Medium: interest   Double: capstone", o.x + 44, o.y + 174, 16, look.DIM);
    const layout = wheelLayout(o, view);
    surface.clip(layout.box);
    for (passives.NODES, 0..) |n, i| {
        if (n.ring == 0) passiveLink(layout, growth, passives.HUB, i);
        var buf: [passives.MAX_FEED]usize = undefined;
        for (passives.feeders(i, &buf)) |parent| {
            if (n.seam != null) continue;
            passiveLink(layout, growth, parent, i);
        }
    }
    const hub = layout.at(passives.HUB);
    rl.drawCircleV(hub, nodeRadius(passives.HUB, layout.unit), TILE);
    ring(hub, nodeRadius(passives.HUB, layout.unit), BORDER);
    rl.drawCircleV(hub, 2, OWNED);
    for (passives.NODES, 0..) |n, i| {
        const p = layout.at(i);
        const r = nodeRadius(i, layout.unit);
        const ink = nodeInk(growth, i);
        const allocated = growth.nodes.isSet(i);
        rl.drawCircleV(p, r, if (allocated) look.rgb(0x3e3526) else TILE);
        ring(p, r, ink);
        if (n.tier == .capstone) ring(p, r - 3, ink);
        if (n.ring == 0) {
            face.centred(switch (n.arm) {
                .warrior => "K",
                .rogue => "A",
                .wizard => "W",
            }, @intFromFloat(@round(p.x)), @intFromFloat(@round(p.y)), 16, ink);
        } else if (n.seam) |s| {
            for ([_]f32{ -2, 2 }) |dy| rl.drawLineEx(.{ .x = p.x - 3, .y = p.y + dy }, .{ .x = p.x + 3, .y = p.y + dy }, 1, if (allocated) OWNED else armInk(s.to()));
        } else if (allocated) {
            const a = rl.Vector2{ .x = p.x - 3, .y = p.y };
            const b = rl.Vector2{ .x = p.x - 1, .y = p.y + 2 };
            rl.drawLineEx(a, b, 1, OWNED);
            rl.drawLineEx(b, .{ .x = p.x + 3, .y = p.y - 2 }, 1, OWNED);
        } else if (growth.available(i)) {
            rl.drawCircleV(p, 2, AVAILABLE);
        }
    }
    if (focused) ring(layout.at(view.cursor), nodeRadius(view.cursor, layout.unit) + 5, FOCUS);
    rl.endScissorMode();
    passiveLegend(face, o);
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
    face.centred(zoom.text(), o.x + 587, o.y + 565, font.SMALL, look.DIM);
    passiveDetails(face, o, class, growth, view.cursor, focused);
}

fn passiveLegend(face: *const font.Face, o: P) void {
    const legends = [_]struct { name: [:0]const u8, color: rl.Color }{
        .{ .name = "Allocated", .color = OWNED },
        .{ .name = "Reachable", .color = AVAILABLE },
        .{ .name = "Distant", .color = LOCKED },
    };
    for (legends, 0..) |l, i| {
        const x = o.x + 66 + @as(i32, @intCast(i)) * 163;
        ring(.{ .x = @floatFromInt(x), .y = @floatFromInt(o.y + 568) }, 4, l.color);
        face.draw(l.name, x + 13, o.y + 561, font.SMALL, l.color);
    }
}

fn grantRow(face: *const font.Face, o: P, y: i32, grant: passives.Grant) void {
    var text: menu.Note(100) = .{};
    if (grant.kind == .armour) {
        text.say("+{d}% physical damage reduction", .{grant.amount});
    } else text.say("+{d}{s} {s}", .{ grant.amount, if (grant.isPercent()) @as([]const u8, "%") else " to", grant.label() });
    _ = paragraph(face, text.text(), o.x + TEXT_X, o.y + y, TEXT_W, look.WARD);
}

fn passiveDetails(face: *const font.Face, o: P, class: hero.Class, growth: *const progress.State, i: usize, focused: bool) void {
    const n = passives.NODES[i];
    const x = o.x + TEXT_X;
    const allocated = growth.nodes.isSet(i);
    const reachable = growth.available(i);
    const origin = i == progress.start(class);
    const enabled = reachable and growth.passive_points > 0;
    face.draw(if (n.ring == 0) "CLASS ORIGIN" else if (n.seam != null) "BRIDGE NODE" else switch (n.tier) {
        .stat => "STAT NODE",
        .interest => "INTEREST NODE",
        .capstone => "CAPSTONE",
    }, x, o.y + 150, 16, look.DIM);
    face.draw(n.name, x, o.y + 177, font.HEAD, look.TEXT);
    var path: menu.Note(96) = .{};
    if (n.branch) |branch| {
        path.say("{s} / {s}", .{ armName(n.arm), branch.name() });
    } else if (n.seam) |s| {
        path.say("{s} / {s} bridge", .{ armName(s.from()), armName(s.to()) });
    } else {
        path.say("{s} origin", .{armName(n.arm)});
    }
    face.draw(path.text(), x, o.y + 214, font.SMALL, armInk(n.arm));
    face.draw(if (origin) "Free class origin" else if (allocated) "Allocated" else if (reachable) "Reachable" else "Distant", x, o.y + 247, font.BODY, nodeInk(growth, i));
    rl.drawLine(x, o.y + 283, x + TEXT_W, o.y + 283, BORDER);
    face.draw("BONUSES", x, o.y + 304, 16, look.DIM);
    if (origin) {
        _ = paragraph(face, "Class attributes already include this starting point. No extra bonus is added here.", x, o.y + 334, TEXT_W, look.TEXT);
    } else {
        grantRow(face, o, 334, n.grant);
        if (n.bump) |bump| grantRow(face, o, 366, bump);
    }
    if (n.tier == .capstone) {
        _ = paragraph(face, "Branch capstone. Grants the listed bonuses when allocated.", x, o.y + 417, TEXT_W, look.DIM);
    } else if (n.seam != null) {
        _ = paragraph(face, "Connects both paths. Reach this bridge from either side.", x, o.y + 417, TEXT_W, look.DIM);
    } else if (n.ring == 0 and !origin) {
        _ = paragraph(face, "Another class origin can be allocated directly.", x, o.y + 417, TEXT_W, look.DIM);
    } else if (n.grant.kind == .armour) {
        var armour: menu.Note(128) = .{};
        armour.say("Armour reduces physical harm by 1% per point, up to {d}% total.", .{attrs.ARMOUR_MAX});
        _ = paragraph(face, armour.text(), x, o.y + 417, TEXT_W, look.DIM);
    }
    const reason: []const u8 = if (origin) "Your class starts here for free." else if (allocated) "This passive is already allocated." else if (!reachable) "Allocate a prerequisite first." else if (growth.passive_points == 0) "Requires 1 passive point." else "Ready to allocate. Costs 1 passive point.";
    _ = paragraph(face, reason, x, o.y + 499, TEXT_W, if (enabled) OWNED else look.DIM);
    drawAction(face, o, if (origin) "Class origin" else if (allocated) "Allocated" else "Allocate passive", enabled, focused);
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
                    if (menu.nearest(box, boxes[0..skills.len], dir, 2)) |next| reached.set(next);
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
