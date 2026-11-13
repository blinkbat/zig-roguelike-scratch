const sprite = @import("../gfx/sprites.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const hero = @import("../play/hero.zig");
const progress = @import("../play/progress.zig");
const tactics = @import("../play/tactics.zig");
const passives = @import("../play/passives.zig");
const attrs = @import("../play/attrs.zig");
const Gear = @import("../play/gear.zig").Gear;
const skillbar = @import("../play/skillbar.zig");
const damage = @import("../play/damage.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const line_icons = @import("../gfx/line_icons.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const input = @import("../core/input.zig");
const AREA = @import("character_layout.zig").AREA;

const P = mathx.P;
pub const Panel = enum { skills, passives };
pub const View = struct { cursor: usize = 0, zoom: f32 = ZOOM_MIN, pan: rl.Vector2 = .{ .x = 0, .y = 0 }, focused: bool = true };
const Loadout = struct { stats: attrs.Attrs, gear: Gear, readied: progress.Readied = .{} };
pub const ZOOM_MIN: f32 = 1;
pub const ZOOM_MAX: f32 = 3.2;
pub const ZOOM_START: f32 = 2.4;
pub const ZOOM_RATE: f32 = 1.7;
pub const ZOOM_STEP: f32 = 0.4;
pub const ZOOM_WHEEL: f32 = 0.2;
pub const PAN_RATE: f32 = 3.4;
const INSET: i32 = 20;
const DETAIL_W: f32 = 332;
const PANEL_GAP: f32 = 24;
const CANVAS = rl.Rectangle{ .x = AREA.x, .y = AREA.y, .width = AREA.width - DETAIL_W - PANEL_GAP, .height = AREA.height };
const DETAIL = rl.Rectangle{ .x = AREA.x + AREA.width - DETAIL_W, .y = AREA.y, .width = DETAIL_W, .height = AREA.height };
const WHEEL_TOP: f32 = 44;
const WHEEL_FOOT: f32 = 44;
const WHEEL = rl.Rectangle{ .x = CANVAS.x + @as(f32, @floatFromInt(INSET)), .y = CANVAS.y + WHEEL_TOP, .width = CANVAS.width - 2 * @as(f32, @floatFromInt(INSET)), .height = CANVAS.height - WHEEL_TOP - WHEEL_FOOT };
const TEXT_X: i32 = raster.left(DETAIL) + INSET;
const TEXT_W: i32 = raster.width(DETAIL) - 2 * INSET;
const CANVAS_RIGHT: i32 = raster.right(CANVAS) - INSET;
const CANVAS_LEFT: i32 = raster.left(CANVAS) + INSET;
const CANVAS_TOP: i32 = raster.top(CANVAS);
const CANVAS_BOTTOM: i32 = raster.bottom(CANVAS);
const DETAIL_TOP: i32 = raster.top(DETAIL);
const FOOT_MID: i32 = CANVAS_BOTTOM - @as(i32, @intFromFloat(WHEEL_FOOT)) / 2;
const ZOOM_PX: i32 = 28;
const ZOOM_GAP: i32 = 14;
const BUTTON_H: i32 = 34;
const ACTION_FOOT_GAP: i32 = 8;
const REASON_GAP: i32 = 10;
const BIND_GAP: i32 = 8;
const DETAIL_BOTTOM: i32 = raster.bottom(DETAIL);
const ACTION_Y: i32 = DETAIL_BOTTOM - ACTION_FOOT_GAP - BUTTON_H;
const REASON_Y: i32 = ACTION_Y - REASON_GAP - font.SMALL;
const BIND_Y: i32 = REASON_Y - BIND_GAP - BUTTON_H;
const TITLE_Y: i32 = CANVAS_TOP + 18;
const SKILL_SIZE: i32 = 56;
const SKILL_MID_X: i32 = 372;
const SKILL_STEP_X: i32 = 140;
const SKILL_TOP: i32 = CANVAS_TOP + 86;
const SKILL_STEP_Y: i32 = 126;
const SPARSE_TOP: i32 = SKILL_TOP + 40;
const SPARSE_STEP_Y: i32 = 164;
const SKILL_NAME_DY: i32 = 46;
const ARROW_CLEAR: i32 = 8;
const PLAQUE_AT = P{ .x = 10, .y = 16 };
const PLAQUE_W: i32 = 42;
const PLAQUE_H: i32 = font.SMALL + 6;
const FOCUS_GROW: f32 = 5;
const NAME_Y: i32 = DETAIL_TOP + 22;
const RANK_Y: i32 = DETAIL_TOP + 56;
const DESC_Y: i32 = DETAIL_TOP + 86;
const RULE_MIN_Y: i32 = DETAIL_TOP + 128;
const GRANT_Y: i32 = DETAIL_TOP + 45;
const RULE_GAP: i32 = 12;
const CAPTION_STEP: i32 = font.SMALL_LINE + 1;
const NEXT_GAP: i32 = 8;
const BACK = look.rgb(0x0c0e12);
const TILE = look.rgb(0x15171c);
const BORDER = look.rgb(0x34373d);
const LOCKED = look.rgb(0x9698a3);
const AVAILABLE = look.rgb(0xbcc9ba);
const OWNED = look.UI_GOLD;
const FOCUS = look.UI_FOCUS;
const LINE = look.rgb(0x42413d);
const OPEN_LINE = look.rgb(0x77705a);
const NODE_HIT_GROW: f32 = 3;
const NODE_KEEP_IN: f32 = 7;
const OWNED_RING: f32 = 1;
const CAPSTONE_RING: f32 = 3;

pub fn cellBox(panel: Panel, class: hero.Class, i: usize, view: View) rl.Rectangle {
    return switch (panel) {
        .skills => skillBox(class, i),
        .passives => blk: {
            const layout = wheelLayout(view);
            const p = layout.at(i);
            const r = nodeRadius(i, layout.unit) + NODE_HIT_GROW;
            const x = @max(layout.box.x, p.x - r);
            const y = @max(layout.box.y, p.y - r);
            break :blk .{ .x = x, .y = y, .width = @max(0, @min(layout.box.x + layout.box.width, p.x + r) - x), .height = @max(0, @min(layout.box.y + layout.box.height, p.y + r) - y) };
        },
    };
}

pub fn onCanvas(p: P) bool {
    return raster.holds(CANVAS, p);
}

pub fn zoomBox(increase: bool) rl.Rectangle {
    const right = CANVAS_RIGHT - if (increase) 0 else ZOOM_PX + ZOOM_GAP;
    return raster.rect(right - ZOOM_PX, FOOT_MID - ZOOM_PX / 2, ZOOM_PX, ZOOM_PX);
}

pub fn overviewBox() rl.Rectangle {
    return raster.rect(CANVAS_LEFT, FOOT_MID - ZOOM_PX / 2, menu.ACTION_BOX.x, ZOOM_PX);
}

pub fn draw(panel: Panel, face: *const font.Face, sprites: *const sprite.Sprites, class: hero.Class, growth: *const progress.State, view: View, device: input.Device, loadout: Loadout, surface: menu.Surface) void {
    switch (panel) {
        .skills => drawSkills(face, sprites, class, growth, view, loadout),
        .passives => drawPassives(face, class, growth, view, surface, device),
    }
}

const OVERVIEW = "Overview";

fn overviewPrompt(device: input.Device) prompt_icon.Prompt {
    return if (device.pad()) prompt_icon.Prompt.menuOn(device, input.TreeKeys.PAD_OVERVIEW) else .{ .key = input.TreeKeys.OVERVIEW_CAPTION };
}

pub fn action(panel: Panel, class: hero.Class, growth: *const progress.State, i: usize) ?bool {
    return switch (panel) {
        .skills => blk: {
            const act = progress.skills(class)[i].act;
            break :blk if (progress.basic(act)) null else growth.canLearn(class, act);
        },
        .passives => if (growth.nodes.isSet(i)) null else growth.canAllocate(i),
    };
}

pub fn actionBox() rl.Rectangle {
    return raster.rect(TEXT_X, ACTION_Y, TEXT_W, BUTTON_H);
}

pub fn bindBox() rl.Rectangle {
    return raster.rect(TEXT_X, BIND_Y, TEXT_W, BUTTON_H);
}

fn skillBox(class: hero.Class, i: usize) rl.Rectangle {
    const skills = progress.skills(class);
    const at = skills[i].at;
    var last: i32 = 0;
    var columns: i32 = 0;
    var across: usize = 0;
    for (skills) |s| {
        last = @max(last, s.at.y);
        columns = @max(columns, s.at.x + 1);
        across += @intFromBool(s.at.y == at.y);
    }
    const x = if (across == 1) SKILL_MID_X else SKILL_MID_X + (2 * at.x - (columns - 1)) * @divExact(SKILL_STEP_X, 2);
    const y = if (last < 2) SPARSE_TOP + at.y * SPARSE_STEP_Y else SKILL_TOP + at.y * SKILL_STEP_Y;
    return raster.rect(x - SKILL_SIZE / 2, y - SKILL_SIZE / 2, SKILL_SIZE, SKILL_SIZE);
}

fn frame(face: *const font.Face, points: u16) void {
    backdrop(CANVAS);
    backdrop(DETAIL);
    drawPoints(face, points, true);
}

fn backdrop(box: rl.Rectangle) void {
    menu.boxed(box, BACK, BORDER);
}

fn button(face: *const font.Face, box: rl.Rectangle, label: [:0]const u8, enabled: bool, on_width: f32, on_ink: rl.Color) void {
    rl.drawRectangleRec(box, TILE);
    rl.drawRectangleLinesEx(box, if (enabled) on_width else 1, if (enabled) on_ink else BORDER);
    const mid = raster.middleAt(box);
    face.centred(label, mid.x, mid.y, font.BODY, if (enabled) look.TEXT else LOCKED);
}

fn drawPoints(face: *const font.Face, points: u16, right: bool) void {
    var line: menu.Note(64) = .{};
    line.say("{d} point{s} available", .{ points, mathx.plural(points) });
    const x = if (right) CANVAS_RIGHT - face.width(line.text(), font.SMALL) else CANVAS_LEFT;
    face.draw(line.text(), x, TITLE_Y, font.SMALL, if (points > 0) OWNED else look.DIM);
}

fn paragraph(face: *const font.Face, text: []const u8, x: i32, y: i32, width: i32, ink: rl.Color) i32 {
    return face.paragraph(text, x, y, width, font.SMALL, ink);
}

fn arrow(from: rl.Rectangle, to: rl.Rectangle, ink: rl.Color) void {
    const from_mid = raster.middle(from);
    const a = rl.Vector2{ .x = from_mid.x, .y = from_mid.y + @as(f32, @floatFromInt(SKILL_NAME_DY + font.SMALL + ARROW_CLEAR)) };
    const b = rl.Vector2{ .x = raster.middle(to).x, .y = to.y - @as(f32, @floatFromInt(ARROW_CLEAR)) };
    const elbow = (a.y + b.y) / 2;
    rl.drawLineEx(a, .{ .x = a.x, .y = elbow }, 1, ink);
    rl.drawLineEx(.{ .x = a.x, .y = elbow }, .{ .x = b.x, .y = elbow }, 1, ink);
    rl.drawLineEx(.{ .x = b.x, .y = elbow }, b, 1, ink);
    rl.drawLineEx(.{ .x = b.x - ARROW_HEAD.x, .y = b.y - ARROW_HEAD.y }, b, 1, ink);
    rl.drawLineEx(.{ .x = b.x + ARROW_HEAD.x, .y = b.y - ARROW_HEAD.y }, b, 1, ink);
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
};

fn skillInk(class: hero.Class, growth: *const progress.State, s: progress.Skill) rl.Color {
    return SkillState.of(class, growth, s).ink();
}

const LEARNABLE_A: f32 = 0.8;
const ORPHAN_A: f32 = 0.3;
const LOCKED_A: f32 = 0.55;
const DISTANT_A: f32 = 0.55;
const CLOSED_LINE_A: f32 = 0.65;
const ARROW_HEAD = rl.Vector2{ .x = 4, .y = 5 };
const SEAM_MARK = rl.Vector2{ .x = 3, .y = 2 };

fn skillAlpha(class: hero.Class, growth: *const progress.State, s: progress.Skill) f32 {
    return switch (SkillState.of(class, growth, s)) {
        .learned => 1,
        .available => LEARNABLE_A,
        .locked => if (s.parent) |p| (if (growth.unlocked(p)) LOCKED_A else ORPHAN_A) else LOCKED_A,
    };
}

fn drawSkills(face: *const font.Face, sprites: *const sprite.Sprites, class: hero.Class, growth: *const progress.State, view: View, loadout: Loadout) void {
    const cursor = view.cursor;
    frame(face, growth.active_points);
    const skills = progress.skills(class);
    for (skills, 0..) |s, i| if (s.parent) |parent| {
        for (skills, 0..) |p, j| if (p.act == parent) {
            arrow(skillBox(class, j), skillBox(class, i), if (growth.unlocked(parent)) OWNED else LINE);
        };
    };
    for (skills, 0..) |s, i| {
        const box = skillBox(class, i);
        const mid = raster.middleAt(box);
        const ink = skillInk(class, growth, s);
        rl.drawRectangleRec(box, TILE);
        rl.drawRectangleLinesEx(box, 2, ink);
        if (i == cursor and view.focused) rl.drawRectangleLinesEx(raster.grown(box, FOCUS_GROW), 2, FOCUS);
        line_icons.drawSkill(sprites, s.act, mid.x - line_icons.SKILL_PX / 2, mid.y - line_icons.SKILL_PX / 2, skillAlpha(class, growth, s));
        const plaque = raster.rect(mid.x + PLAQUE_AT.x, mid.y + PLAQUE_AT.y, PLAQUE_W, PLAQUE_H);
        menu.boxed(plaque, BACK, ink);
        var rank: menu.Note(16) = .{};
        if (progress.basic(s.act)) rank.say("Basic", .{}) else rank.say("{d}/{d}", .{ growth.ranks.get(s.act), progress.rankLimit(s.act) });
        const pm = raster.middleAt(plaque);
        face.centred(rank.text(), pm.x, pm.y, font.SMALL, ink);
        face.drawMid(s.act.name(), mid.x, mid.y + SKILL_NAME_DY, font.SMALL, if (growth.unlocked(s.act) or i == cursor) look.TEXT else LOCKED);
    }
    skillDetails(face, class, growth, cursor, loadout);
}

fn skillReason(class: hero.Class, growth: *const progress.State, s: progress.Skill, buf: *Prose) ?[:0]const u8 {
    if (progress.basic(s.act) or growth.maxed(s.act)) return null;
    if (s.parent) |p| if (!growth.unlocked(p)) {
        buf.say("Learn {s} first.", .{p.name()});
        return buf.text();
    };
    if (growth.active_points < progress.POINT_COST) return ACTIVE.requires;
    std.debug.assert(growth.canLearn(class, s.act));
    return if (growth.unlocked(s.act)) ACTIVE.ready("upgrade") else ACTIVE.ready("learn");
}

fn drawAction(face: *const font.Face, label: [:0]const u8, enabled: bool) void {
    button(face, actionBox(), label, enabled, 2, OWNED);
}

const Hit = progress.Hit;
const Prose = menu.Note(128);

fn skillHit(growth: *const progress.State, act: skillbar.Act, loadout: Loadout) ?Hit {
    return growth.preparedHit(loadout.stats, loadout.gear, act, loadout.readied);
}

fn hitText(act: skillbar.Act, hit: Hit, text: *Prose) [:0]const u8 {
    if (hit.element) |e| {
        if (hit.physical.hi > 0) {
            text.say(damage.MIXED_FMT, .{ hit.physical.lo, hit.physical.hi, e.lo, e.hi, menu.word(act.element().?) });
        } else {
            text.say(damage.ELEMENT_FMT, .{ menu.named(act.element().?), e.lo, e.hi });
        }
    } else if (hit.imbued) |f| {
        text.say(damage.MIXED_FMT, .{ hit.physical.lo, hit.physical.hi, f.lo, f.hi, menu.word(tactics.Imbue.IMBUES) });
        return text.text();
    } else text.say(damage.PHYSICAL_FMT, .{ hit.physical.lo, hit.physical.hi });
    if (hit.imbued) |f| text.writer().print(damage.ADDED_FMT, .{ f.lo, f.hi, menu.word(tactics.Imbue.IMBUES) }) catch {};
    return text.text();
}

fn skillDetails(face: *const font.Face, class: hero.Class, growth: *const progress.State, cursor: usize, loadout: Loadout) void {
    const s = progress.skills(class)[cursor];
    const x = TEXT_X;
    face.engraved(s.act.name(), x, NAME_Y, font.HEAD, look.TEXT);
    var rank: menu.Note(64) = .{};
    const learned = growth.unlocked(s.act);
    if (progress.basic(s.act)) rank.say("Basic attack", .{}) else if (learned) rank.say("Rank {d} of {d}", .{ growth.ranks.get(s.act), progress.rankLimit(s.act) }) else rank.say("Not learned", .{});
    face.draw(rank.text(), x, RANK_Y, font.SMALL, skillInk(class, growth, s));
    var desc: menu.Note(256) = .{};
    s.act.describe(desc.writer(), loadout.gear.draughtsOver(growth.perks()), s.act.reachWith(loadout.gear.bounding()));
    const end = paragraph(face, desc.text(), x, DESC_Y, TEXT_W, look.TEXT);
    var top: i32 = @max(RULE_MIN_Y, end + RULE_GAP);
    rl.drawLine(x, top, x + TEXT_W, top, BORDER);
    top += RULE_GAP;
    face.draw(if (progress.basic(s.act)) "ATTACK" else if (learned) "CURRENT RANK" else "FIRST RANK", x, top, font.SMALL, look.DIM);
    top += CAPTION_STEP;
    var text: Prose = .{};
    const hit = skillHit(growth, s.act, loadout);
    if (hit) |h| {
        top = paragraph(face, hitText(s.act, h, &text), x, top, TEXT_W, look.TEXT);
    }
    text.clear();
    const quicker = loadout.gear.quicker();
    growth.writeUsage(s.act, quicker, text.writer());
    text.buf[0] = std.ascii.toUpper(text.buf[0]);
    top = paragraph(face, text.text(), x, top, TEXT_W, look.TEXT);
    text.clear();
    growth.writeRank(s.act, text.writer());
    if (text.n > 0) top = paragraph(face, text.text(), x, top, TEXT_W, look.TEXT);
    const maximum = growth.maxed(s.act);
    var next = growth.*;
    if (!maximum) next.ranks.getPtr(s.act).* += 1;
    var ranked: Prose = .{};
    next.writeRank(s.act, ranked.writer());
    const mana_changes = next.cost(s.act) != growth.cost(s.act);
    const damage_changes = next.damageBonus(s.act) != growth.damageBonus(s.act);
    const cooldown_changes = next.cooldown(s.act, quicker) != growth.cooldown(s.act, quicker);
    if (learned and !maximum and (ranked.n > 0 or mana_changes or damage_changes or cooldown_changes)) {
        top += NEXT_GAP;
        text.say("NEXT RANK  {d}", .{next.ranks.get(s.act)});
        face.draw(text.text(), x, top, font.SMALL, OWNED);
        top += CAPTION_STEP;
        if (ranked.n > 0) top = paragraph(face, ranked.text(), x, top, TEXT_W, OWNED);
        if (damage_changes) {
            const next_hit = skillHit(&next, s.act, loadout).?;
            if (std.meta.eql(hit.?, next_hit)) {
                text.say("Rank damage bonus: +{d}% (was +{d}%)", .{ next.damageBonus(s.act), growth.damageBonus(s.act) });
            } else _ = hitText(s.act, next_hit, &text);
            if (mana_changes) text.writer().print("; {d} mana", .{next.cost(s.act)}) catch {};
            top = paragraph(face, text.text(), x, top, TEXT_W, OWNED);
        }
        const mana_separate = mana_changes and !damage_changes;
        if (mana_separate or cooldown_changes) {
            const cd = next.cooldown(s.act, quicker);
            if (mana_separate and cooldown_changes) {
                text.say("Mana: {d}; cooldown: {d} turn{s}", .{ next.cost(s.act), cd, mathx.plural(cd) });
            } else if (mana_separate) {
                text.say("Mana cost: {d}", .{next.cost(s.act)});
            } else text.say("Cooldown: {d} turn{s}", .{ cd, mathx.plural(cd) });
            top = paragraph(face, text.text(), x, top, TEXT_W, OWNED);
        }
    }
    var reason: Prose = .{};
    if (skillReason(class, growth, s, &reason)) |why| _ = paragraph(face, why, x, REASON_Y, TEXT_W, if (growth.canLearn(class, s.act)) OWNED else look.DIM);
    if (action(.skills, class, growth, cursor)) |enabled| drawAction(face, if (maximum) "Maximum rank" else if (learned) "Upgrade skill" else "Learn skill", enabled);
}

const Layout = struct {
    box: rl.Rectangle,
    centre: rl.Vector2,
    unit: f32,

    fn shows(self: Layout, a: rl.Vector2, b: rl.Vector2, margin: f32) bool {
        return @max(a.x, b.x) + margin >= self.box.x and @min(a.x, b.x) - margin <= self.box.x + self.box.width and
            @max(a.y, b.y) + margin >= self.box.y and @min(a.y, b.y) - margin <= self.box.y + self.box.height;
    }

    fn at(self: Layout, i: usize) rl.Vector2 {
        const p = passives.unitPos(i);
        return .{ .x = self.centre.x + p.x * self.unit, .y = self.centre.y + p.y * self.unit };
    }
};

fn pullOf(zoom: f32) f32 {
    return (std.math.clamp(zoom, ZOOM_MIN, ZOOM_MAX) - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN);
}

const PAN_REACH: f32 = 1.6;
const PAN_REACH_ZOOMED: f32 = 6;
const WHEEL_MARGIN: f32 = 0.63;

pub fn clampPan(view: View) rl.Vector2 {
    const limit = PAN_REACH + PAN_REACH_ZOOMED * (1 - 1 / view.zoom);
    const reach: f32 = @floatFromInt(passives.RINGS);
    const focus = passives.unitPos(view.cursor);
    const pull = pullOf(view.zoom);
    return .{
        .x = std.math.clamp(std.math.clamp(view.pan.x, -limit, limit) + focus.x * pull, -reach, reach) - focus.x * pull,
        .y = std.math.clamp(std.math.clamp(view.pan.y, -limit, limit) + focus.y * pull, -reach, reach) - focus.y * pull,
    };
}

pub fn drag(view: View, delta: rl.Vector2) rl.Vector2 {
    var moved = view;
    const unit = wheelLayout(view).unit;
    moved.pan.x -= delta.x / unit;
    moved.pan.y -= delta.y / unit;
    return clampPan(moved);
}

pub fn note(face: *const font.Face, text: [:0]const u8) void {
    face.drawMid(text, raster.middleAt(CANVAS).x, TITLE_Y, font.SMALL, look.TEXT);
}

fn wheelLayout(view: View) Layout {
    const box = WHEEL;
    const zoom = std.math.clamp(view.zoom, ZOOM_MIN, ZOOM_MAX);
    const unit = @min(box.width, box.height) / (2 * (@as(f32, @floatFromInt(passives.RINGS)) + WHEEL_MARGIN)) * zoom;
    const focus = passives.unitPos(view.cursor);
    const pull = pullOf(zoom);
    const mid = raster.middle(box);
    var layout = Layout{ .box = box, .unit = unit, .centre = .{
        .x = mid.x - focus.x * unit * pull,
        .y = mid.y - focus.y * unit * pull,
    } };
    const selected = layout.at(view.cursor);
    const margin = nodeRadius(view.cursor, unit) + NODE_KEEP_IN;
    layout.centre.x += std.math.clamp(selected.x, box.x + margin, box.x + box.width - margin) - selected.x;
    layout.centre.y += std.math.clamp(selected.y, box.y + margin, box.y + box.height - margin) - selected.y;
    layout.centre.x -= view.pan.x * unit;
    layout.centre.y -= view.pan.y * unit;
    return layout;
}

const NodeSize = struct { least: f32, share: f32 };
const ORIGIN_SIZE = NodeSize{ .least = 8, .share = 0.26 };
const SEAM_SIZE = NodeSize{ .least = 8, .share = 0.23 };
const TIER_SIZE = std.EnumArray(passives.Tier, NodeSize).init(.{
    .stat = .{ .least = 5, .share = 0.15 },
    .interest = .{ .least = 7, .share = 0.21 },
    .capstone = .{ .least = 10, .share = 0.30 },
});

fn nodeRadius(i: usize, unit: f32) f32 {
    const n = passives.NODES[i];
    const size = if (n.ring == 0) ORIGIN_SIZE else if (n.seam != null) SEAM_SIZE else TIER_SIZE.get(n.tier);
    return @max(size.least, unit * size.share);
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

fn Price(comptime pool: []const u8) type {
    return struct {
        const cost = std.fmt.comptimePrint("{d} {s} point{s}", .{ progress.POINT_COST, pool, mathx.plural(progress.POINT_COST) });
        const requires = "Requires " ++ cost ++ ".";
        fn ready(comptime verb: []const u8) [:0]const u8 {
            return "Ready to " ++ verb ++ ". Costs " ++ cost ++ ".";
        }
    };
}
const ACTIVE = Price("active");
const PASSIVE = Price("passive");

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

    fn standing(self: NodeState) SkillState {
        return switch (self) {
            .allocated => .learned,
            .reachable => .available,
            .distant => .locked,
        };
    }

    fn ink(self: NodeState) rl.Color {
        return self.standing().ink();
    }
};

fn nodeInk(state: NodeState, arm: passives.Arm) rl.Color {
    return if (state == .distant) look.fade(armInk(arm), DISTANT_A) else state.ink();
}

fn passiveLink(layout: Layout, pos: *const Positions, growth: *const progress.State, from: usize, to: usize) void {
    const before = growth.nodes.isSet(from);
    const after = growth.nodes.isSet(to);
    const bridge = passives.NODES[from].seam != null;
    const ink = if (before and after) OWNED else if (before or (bridge and after)) OPEN_LINE else look.fade(LINE, CLOSED_LINE_A);
    const a = pos[from];
    const b = pos[to];
    if (!layout.shows(a, b, 2)) return;
    rl.drawLineEx(a, b, if (before and after) 2 else 1, ink);
}

const Positions = [passives.N]rl.Vector2;

fn drawPassives(face: *const font.Face, class: hero.Class, growth: *const progress.State, view: View, surface: menu.Surface, device: input.Device) void {
    backdrop(CANVAS);
    rl.drawLine(raster.left(DETAIL), DETAIL_TOP, raster.left(DETAIL), CANVAS_BOTTOM, BORDER);
    drawPoints(face, growth.passive_points, false);
    const layout = wheelLayout(view);
    var pos: Positions = undefined;
    for (&pos, 0..) |*q, i| q.* = layout.at(i);
    surface.clip(layout.box);
    for (passives.NODES, 0..) |n, i| {
        if (n.seam != null) continue;
        var buf: [passives.MAX_FEED]usize = undefined;
        for (passives.feeders(i, &buf)) |parent| passiveLink(layout, &pos, growth, parent, i);
    }
    for (passives.NODES, 0..) |n, i| {
        const p = pos[i];
        const r = nodeRadius(i, layout.unit);
        if (!layout.shows(p, p, r + FOCUS_GROW)) continue;
        const state = NodeState.of(growth, i);
        const ink = nodeInk(state, n.arm);
        if (state == .allocated) {
            rl.drawCircleV(p, r, armInk(n.arm));
            ring(p, r + OWNED_RING, OWNED);
        } else {
            rl.drawCircleV(p, r, TILE);
        }
        ring(p, r, ink);
        const mark = if (state == .allocated) BACK else ink;
        if (n.tier == .capstone) ring(p, r - CAPSTONE_RING, mark);
        if (n.ring == 0) {
            face.centred(armInitial(n.arm), @intFromFloat(@round(p.x)), @intFromFloat(@round(p.y)), font.SMALL, if (state == .allocated) BACK else look.TEXT);
        } else if (n.seam) |s| {
            for ([_]f32{ -SEAM_MARK.y, SEAM_MARK.y }) |dy| rl.drawLineEx(.{ .x = p.x - SEAM_MARK.x, .y = p.y + dy }, .{ .x = p.x + SEAM_MARK.x, .y = p.y + dy }, 1, if (state == .allocated) BACK else armInk(s.to()));
        }
    }
    if (view.focused) ring(pos[view.cursor], nodeRadius(view.cursor, layout.unit) + FOCUS_GROW, FOCUS);
    rl.endScissorMode();
    for ([_]bool{ false, true }) |increase| {
        const enabled = if (increase) view.zoom < ZOOM_MAX else view.zoom > ZOOM_MIN;
        button(face, zoomBox(increase), if (increase) "+" else "-", enabled, 1, AVAILABLE);
    }
    menu.action(face, overviewBox(), overviewPrompt(device), OVERVIEW);
    passiveDetails(face, class, growth, view.cursor);
}

fn grantRow(face: *const font.Face, x: i32, y: i32, grant: passives.Grant) i32 {
    var text: menu.Note(100) = .{};
    grant.write(text.writer());
    return face.paragraph(text.text(), x, y, TEXT_W, font.BODY, look.TEXT);
}

fn grantNoteOf(n: passives.Node) ?[:0]const u8 {
    for ([_]?passives.Grant{ n.grant, n.bump }) |maybe| {
        const g = maybe orelse continue;
        if (g.kind == .life_on_kill) return "From blows only.";
    }
    return null;
}

fn passiveDetails(face: *const font.Face, class: hero.Class, growth: *const progress.State, i: usize) void {
    const n = passives.NODES[i];
    const x = TEXT_X;
    const state = NodeState.of(growth, i);
    const origin = progress.bonusAt(class, i) == null;
    face.draw(if (n.ring == 0) armName(n.arm) else n.name, x, TITLE_Y, font.SMALL, look.DIM);
    var y: i32 = GRANT_Y;
    if (origin) {
        face.draw("Starting point", x, y, font.BODY, look.TEXT);
        return;
    }
    y = grantRow(face, x, y, n.grant);
    if (n.bump) |bump| y = grantRow(face, x, y, bump);
    if (grantNoteOf(n)) |line| _ = paragraph(face, line, x, y + RULE_GAP, TEXT_W, look.DIM);
    const enabled = action(.passives, class, growth, i) orelse {
        face.draw("Allocated", x, ACTION_Y, font.BODY, OWNED);
        return;
    };
    const reason: []const u8 = switch (state) {
        .allocated => unreachable,
        .distant => "Allocate a preceding node first.",
        .reachable => if (enabled) PASSIVE.cost else PASSIVE.requires,
    };
    _ = paragraph(face, reason, x, REASON_Y, TEXT_W, if (enabled) OWNED else look.DIM);
    drawAction(face, "Allocate", enabled);
}

test "every class skill stays in its canvas and is reachable by directional selection" {
    for (hero.CLASSES) |class| {
        const skills = progress.skills(class);
        var boxes: [skillbar.ACTS.len]rl.Rectangle = undefined;
        const area = CANVAS;
        const plaque_over: f32 = @floatFromInt(PLAQUE_AT.x + PLAQUE_W - SKILL_SIZE / 2);
        const name_foot: f32 = @floatFromInt(SKILL_NAME_DY + font.SMALL - SKILL_SIZE / 2);
        const footer_top: f32 = @floatFromInt(FOOT_MID - font.SMALL / 2);
        for (skills, 0..) |_, i| {
            const box = skillBox(class, i);
            boxes[i] = box;
            try std.testing.expect(box.x >= area.x and box.y >= area.y);
            try std.testing.expect(box.x + box.width + plaque_over <= area.x + area.width);
            try std.testing.expect(box.y + box.height + name_foot <= footer_top);
            for (boxes[0..i]) |other| {
                const overlaps = box.x < other.x + other.width and other.x < box.x + box.width and
                    box.y < other.y + other.height and other.y < box.y + box.height;
                try std.testing.expect(!overlaps);
            }
        }
        var reached = std.StaticBitSet(skillbar.ACTS.len).initEmpty();
        reached.set(0);
        for (0..skills.len) |_| {
            for (boxes[0..skills.len], 0..) |box, i| {
                if (!reached.isSet(i)) continue;
                for (mathx.ALL_DIRS) |dir| {
                    if (menu.nearest(box, boxes[0..skills.len], dir)) |next| reached.set(next);
                }
            }
        }
        try std.testing.expectEqual(skills.len, reached.count());
    }
}

const TEST_ZOOMS = blk: {
    var out: []const f32 = &.{ ZOOM_START, ZOOM_MAX };
    var z: f32 = ZOOM_MIN;
    while (z < ZOOM_MAX) : (z += ZOOM_STEP) out = out ++ &[_]f32{z};
    break :blk out[0..out.len].*;
};

test "passive diagram fits all nodes and retains its selected node through zoom" {
    const layout = wheelLayout(.{});
    for (passives.NODES, 0..) |_, i| {
        const p = layout.at(i);
        const r = nodeRadius(i, layout.unit) + FOCUS_GROW;
        try std.testing.expect(p.x - r >= layout.box.x and p.y - r >= layout.box.y);
        try std.testing.expect(p.x + r <= layout.box.x + layout.box.width and p.y + r <= layout.box.y + layout.box.height);
        for (0..i) |j| {
            const other = layout.at(j);
            const distance = mathx.len(p.x - other.x, p.y - other.y);
            try std.testing.expect(distance > nodeRadius(i, layout.unit) + nodeRadius(j, layout.unit) + 2);
        }
        for (TEST_ZOOMS) |zoom| {
            const view = View{ .cursor = i, .zoom = zoom };
            const zoomed = wheelLayout(view);
            const at = zoomed.at(i);
            const radius = nodeRadius(i, zoomed.unit) + FOCUS_GROW;
            try std.testing.expect(at.x - radius >= zoomed.box.x and at.y - radius >= zoomed.box.y);
            try std.testing.expect(at.x + radius <= zoomed.box.x + zoomed.box.width and at.y + radius <= zoomed.box.y + zoomed.box.height);
            const hit = cellBox(.passives, .knight, i, view);
            try std.testing.expect(hit.width > 0 and hit.height > 0);
            for (0..passives.N) |j| {
                const clipped = cellBox(.passives, .knight, j, view);
                if (clipped.width <= 0 or clipped.height <= 0) continue;
                try std.testing.expect(clipped.x >= zoomed.box.x and clipped.y >= zoomed.box.y);
                try std.testing.expect(clipped.x + clipped.width <= zoomed.box.x + zoomed.box.width + 0.001);
                try std.testing.expect(clipped.y + clipped.height <= zoomed.box.y + zoomed.box.height + 0.001);
            }
        }
    }
}

test "panning as far as it goes from any node never leaves the canvas empty" {
    var fewest: usize = passives.N;
    for (0..passives.N) |i| {
        for ([_]f32{ ZOOM_MIN, ZOOM_START, ZOOM_MAX }) |zoom| {
            for ([_][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 }, .{ 1, 0 }, .{ 0, 1 } }) |way| {
                var view = View{ .cursor = i, .zoom = zoom, .pan = .{ .x = way[0] * 100, .y = way[1] * 100 } };
                view.pan = clampPan(view);
                const layout = wheelLayout(view);
                var shown: usize = 0;
                for (0..passives.N) |j| {
                    if (rl.checkCollisionPointRec(layout.at(j), layout.box)) shown += 1;
                }
                fewest = @min(fewest, shown);
            }
        }
    }
    try std.testing.expect(fewest > 0);
}
