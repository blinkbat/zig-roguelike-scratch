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
const raster = @import("../gfx/raster.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const line_icons = @import("../gfx/line_icons.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const input = @import("../core/input.zig");
const book = @import("book.zig");

const P = mathx.P;
pub const Panel = enum { skills, passives };
pub const View = struct { cursor: usize = 0, zoom: f32 = ZOOM_MIN, pan: rl.Vector2 = .{ .x = 0, .y = 0 } };
pub const Loadout = struct { stats: attrs.Attrs, gear: items.Gear };
pub const ZOOM_MIN: f32 = 1;
pub const ZOOM_MAX: f32 = 3.2;
pub const ZOOM_START: f32 = 2.4;
pub const ZOOM_RATE: f32 = 1.7;
/// A press of a zoom button, and a notch of the wheel.
pub const ZOOM_STEP: f32 = 0.4;
pub const ZOOM_WHEEL: f32 = 0.2;
pub const PAN_RATE: f32 = 3.4;
/// Text and controls keep this far inside the canvas.
const INSET: i32 = 20;
const DETAIL_W: f32 = 332;
const PANEL_GAP: f32 = 24;
const CANVAS = rl.Rectangle{ .x = book.AREA.x, .y = book.AREA.y, .width = book.AREA.width - DETAIL_W - PANEL_GAP, .height = book.AREA.height };
const DETAIL = rl.Rectangle{ .x = book.AREA.x + book.AREA.width - DETAIL_W, .y = book.AREA.y, .width = DETAIL_W, .height = book.AREA.height };
const WHEEL_TOP: f32 = 44;
const WHEEL_FOOT: f32 = 44;
const WHEEL = rl.Rectangle{ .x = CANVAS.x + @as(f32, @floatFromInt(INSET)), .y = CANVAS.y + WHEEL_TOP, .width = CANVAS.width - 2 * @as(f32, @floatFromInt(INSET)), .height = CANVAS.height - WHEEL_TOP - WHEEL_FOOT };
const TEXT_X: i32 = @as(i32, @intFromFloat(DETAIL.x)) + INSET;
const TEXT_W: i32 = @as(i32, @intFromFloat(DETAIL.width)) - 2 * INSET;
const CANVAS_RIGHT: i32 = @as(i32, @intFromFloat(CANVAS.x + CANVAS.width)) - INSET;
const CANVAS_LEFT: i32 = @as(i32, @intFromFloat(CANVAS.x)) + INSET;
const CANVAS_TOP: i32 = @intFromFloat(CANVAS.y);
const CANVAS_BOTTOM: i32 = @intFromFloat(CANVAS.y + CANVAS.height);
const DETAIL_TOP: i32 = @intFromFloat(DETAIL.y);
/// The middle of the canvas's foot row under the wheel: legend and zoom.
const FOOT_MID: i32 = CANVAS_BOTTOM - @as(i32, @intFromFloat(WHEEL_FOOT)) / 2;
const LEGEND_STEP: i32 = 140;
const ZOOM_PX: i32 = 28;
const ZOOM_GAP: i32 = 14;
const BUTTON_H: i32 = 34;
const ACTION_Y: i32 = DETAIL_TOP + 408;
const BIND_Y: i32 = DETAIL_TOP + 338;
const REASON_Y: i32 = DETAIL_TOP + 380;
comptime {
    std.debug.assert(BIND_Y + BUTTON_H <= REASON_Y and REASON_Y + font.SMALL <= ACTION_Y);
    std.debug.assert(@as(f32, @floatFromInt(ACTION_Y + BUTTON_H)) <= DETAIL.y + DETAIL.height);
}
const HINT_Y: i32 = CANVAS_BOTTOM + 20;
const HINT_STEP: i32 = 164;
/// In a hint, between one glyph and the next, and past the last before the label.
const HINT_GLYPH_GAP: i32 = 4;
const HINT_LABEL_GAP: i32 = 2;
/// The canvas's title row.
const TITLE_Y: i32 = CANVAS_TOP + 18;
const SKILL_SIZE: i32 = 56;
const SKILL_MID_X: i32 = 372;
const SKILL_STEP_X: i32 = 248;
const SKILL_TOP: i32 = CANVAS_TOP + 86;
const SKILL_STEP_Y: i32 = 126;
/// A diagram of two rows or fewer: its first row's middle and the step between rows.
const SPARSE_TOP: i32 = SKILL_TOP + 40;
const SPARSE_STEP_Y: i32 = 164;
/// Down from a skill tile's middle to its name's top.
const SKILL_NAME_DY: i32 = 46;
/// A link arrow keeps this clear of the name above and the tile below.
const ARROW_CLEAR: i32 = 8;
/// The rank plaque's corner, out from its tile's middle, and its size.
const PLAQUE_AT = P{ .x = 10, .y = 16 };
const PLAQUE_W: i32 = 42;
const PLAQUE_H: i32 = 22;
/// The selected tile's frame, out from the tile.
const SKILL_FOCUS_GROW: f32 = 5;
/// Detail rows: name, rank or kind, description, the earliest rule, and a passive's first grant.
const NAME_Y: i32 = DETAIL_TOP + 22;
const RANK_Y: i32 = DETAIL_TOP + 56;
const DESC_Y: i32 = DETAIL_TOP + 86;
const RULE_MIN_Y: i32 = DETAIL_TOP + 128;
const GRANT_Y: i32 = DETAIL_TOP + 45;
/// Either side of a detail rule, and a caption to its first line.
const RULE_GAP: i32 = 12;
const CAPTION_STEP: i32 = 21;
/// Above a skill's flavor line, under its one-line note, and above the next rank's changes.
const FLAVOR_GAP: i32 = 4;
const NOTE_STEP: i32 = 18;
const NEXT_GAP: i32 = 8;
const BACK = look.rgb(0x0c0e12);
const TILE = look.rgb(0x15171c);
const BORDER = look.rgb(0x34373d);
const LOCKED = look.rgb(0x656773);
const AVAILABLE = look.rgb(0xbcc9ba);
const OWNED = look.UI_GOLD;
const FOCUS = look.UI_FOCUS;
const LINE = look.rgb(0x42413d);
/// A link with one allocated end, or reaching an allocated bridge.
const OPEN_LINE = look.rgb(0x77705a);
const NODE_HIT_GROW: f32 = 3;
const NODE_FOCUS_GROW: f32 = 5;
const NODE_KEEP_IN: f32 = 7;
/// An allocated node's outer ring, and a capstone's inner ring, from its rim.
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

pub fn draw(panel: Panel, face: *const font.Face, sprites: *const look.Sprites, class: hero.Class, growth: *const progress.State, view: View, device: input.Device, loadout: Loadout, surface: menu.Surface) void {
    switch (panel) {
        .skills => drawSkills(face, sprites, class, growth, view.cursor, loadout),
        .passives => {
            drawPassives(face, class, growth, view, surface, device);
            treeHints(face, device);
        },
    }
}

fn hint(face: *const font.Face, x: i32, y: i32, prompts: []const prompt_icon.Prompt, label: [:0]const u8) void {
    var next = x;
    for (prompts) |prompt| next = prompt.drawFrom(face, next, y, font.BODY, 1) + HINT_GLYPH_GAP;
    face.drawMiddle(label, next + HINT_LABEL_GAP, y, font.SMALL, look.DIM);
}

fn treeHints(face: *const font.Face, device: input.Device) void {
    const y = HINT_Y;
    const x = CANVAS_LEFT;
    const keys = input.TreeKeys;
    const pad = device.pad();
    const hints = [_]struct { pad: []const prompt_icon.Prompt, keys: []const prompt_icon.Prompt, label: [:0]const u8 }{
        .{ .pad = &.{.{ .stick = .left }}, .keys = &.{.{ .key = keys.BROWSE_CAPTION }}, .label = "Browse" },
        .{ .pad = &.{.{ .stick = .right }}, .keys = &.{ .{ .key = keys.PAN_CAPTION }, .arrows }, .label = "Pan" },
        .{ .pad = &.{.dpad}, .keys = &.{ .{ .key = keys.ZOOM_OUT_CAPTION }, .{ .key = keys.ZOOM_IN_CAPTION } }, .label = "Zoom" },
        .{ .pad = &.{prompt_icon.Prompt.menuOn(device, keys.PAD_OVERVIEW)}, .keys = &.{.{ .key = keys.OVERVIEW_CAPTION }}, .label = "Overview" },
    };
    for (hints, 0..) |h, i| hint(face, x + @as(i32, @intCast(i)) * HINT_STEP, y, if (pad) h.pad else h.keys, h.label);
}

pub fn actionBox() rl.Rectangle {
    return raster.rect(TEXT_X, ACTION_Y, TEXT_W, BUTTON_H);
}

pub fn bindBox() rl.Rectangle {
    return raster.rect(TEXT_X, BIND_Y, TEXT_W, BUTTON_H);
}

const SKILL_COLUMNS: i32 = blk: {
    var most: i32 = 0;
    for (hero.CLASSES) |c| {
        for (progress.skills(c)) |s| most = @max(most, s.at.x + 1);
    }
    break :blk most;
};

fn skillBox(class: hero.Class, i: usize) rl.Rectangle {
    const skills = progress.skills(class);
    const at = skills[i].at;
    var last: i32 = 0;
    var across: usize = 0;
    for (skills) |s| {
        last = @max(last, s.at.y);
        across += @intFromBool(s.at.y == at.y);
    }
    const x = if (across == 1) SKILL_MID_X else SKILL_MID_X + (2 * at.x - (SKILL_COLUMNS - 1)) * @divExact(SKILL_STEP_X, 2);
    const y = if (last < 2) SPARSE_TOP + at.y * SPARSE_STEP_Y else SKILL_TOP + at.y * SKILL_STEP_Y;
    return raster.rect(x - SKILL_SIZE / 2, y - SKILL_SIZE / 2, SKILL_SIZE, SKILL_SIZE);
}

fn frame(face: *const font.Face, title: [:0]const u8, points: u16) void {
    for ([_]rl.Rectangle{ CANVAS, DETAIL }) |box| {
        rl.drawRectangleRec(box, BACK);
        rl.drawRectangleLinesEx(box, 1, BORDER);
    }
    face.draw(title, CANVAS_LEFT, TITLE_Y, font.SMALL, look.TEXT);
    var line: menu.Note(64) = .{};
    line.say("{d} point{s} available", .{ points, mathx.plural(points) });
    face.draw(line.text(), CANVAS_RIGHT - face.width(line.text(), font.SMALL), TITLE_Y, font.SMALL, if (points > 0) OWNED else look.DIM);
}

const Legend = struct { name: [:0]const u8, color: rl.Color };

fn legendOf(comptime E: type, comptime inkOf: fn (E) rl.Color) [std.enums.values(E).len]Legend {
    var out: [std.enums.values(E).len]Legend = undefined;
    for (std.enums.values(E), &out) |e, *l| l.* = .{ .name = menu.named(e), .color = inkOf(e) };
    return out;
}

/// Where a legend's row sits and how each entry looks; `text` null inks a name as its mark.
const LegendStyle = struct {
    y: i32,
    step: i32,
    mark: enum { ring, square, dot },
    text_dx: i32,
    text: ?rl.Color = null,
};
/// Half a legend mark's width.
const MARK_HALF: i32 = 5;
/// A foot legend entry's left to its name.
const LEGEND_TEXT_DX: i32 = 20;

fn legend(face: *const font.Face, entries: []const Legend, style: LegendStyle) void {
    for (entries, 0..) |l, i| {
        const x = CANVAS_LEFT + @as(i32, @intCast(i)) * style.step;
        const y = style.y;
        switch (style.mark) {
            .ring => ring(.{ .x = @floatFromInt(x + MARK_HALF), .y = @floatFromInt(y) }, @floatFromInt(MARK_HALF - 1), l.color),
            .square => rl.drawRectangleLinesEx(raster.rect(x, y - MARK_HALF, 2 * MARK_HALF + 1, 2 * MARK_HALF + 1), 1, l.color),
            .dot => rl.drawCircle(x + MARK_HALF, y, MARK_HALF, l.color),
        }
        face.drawMiddle(l.name, x + style.text_dx, y, font.SMALL, style.text orelse l.color);
    }
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

    const LEGEND = legendOf(SkillState, ink);
};

fn skillInk(class: hero.Class, growth: *const progress.State, s: progress.Skill) rl.Color {
    return SkillState.of(class, growth, s).ink();
}

/// A skill icon's alpha when it can be learned now, when its parent is unlearned, and when otherwise locked.
const LEARNABLE_A: f32 = 0.8;
const ORPHAN_A: f32 = 0.3;
const LOCKED_A: f32 = 0.55;

fn skillAlpha(class: hero.Class, growth: *const progress.State, s: progress.Skill) f32 {
    return switch (SkillState.of(class, growth, s)) {
        .learned => 1,
        .available => LEARNABLE_A,
        .locked => if (s.parent) |p| (if (growth.unlocked(p)) LOCKED_A else ORPHAN_A) else LOCKED_A,
    };
}

fn drawSkills(face: *const font.Face, sprites: *const look.Sprites, class: hero.Class, growth: *const progress.State, cursor: usize, loadout: Loadout) void {
    frame(face, "CLASS SKILLS", growth.active_points);
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
        if (i == cursor) rl.drawRectangleLinesEx(raster.grown(box, SKILL_FOCUS_GROW), 2, FOCUS);
        line_icons.drawSkill(sprites, s.act, mid.x - line_icons.SKILL_PX / 2, mid.y - line_icons.SKILL_PX / 2, skillAlpha(class, growth, s));
        const plaque = raster.rect(mid.x + PLAQUE_AT.x, mid.y + PLAQUE_AT.y, PLAQUE_W, PLAQUE_H);
        rl.drawRectangleRec(plaque, BACK);
        rl.drawRectangleLinesEx(plaque, 1, ink);
        var rank: menu.Note(16) = .{};
        rank.say("{d}/{d}", .{ growth.ranks.get(s.act), progress.RANKS });
        const pm = raster.middleAt(plaque);
        face.centred(rank.text(), pm.x, pm.y, font.SMALL, ink);
        face.drawMid(s.act.name(), mid.x, mid.y + SKILL_NAME_DY, font.SMALL, if (growth.unlocked(s.act) or i == cursor) look.TEXT else LOCKED);
    }
    legend(face, &SkillState.LEGEND, .{ .y = FOOT_MID, .step = LEGEND_STEP, .mark = .square, .text_dx = LEGEND_TEXT_DX });
    skillDetails(face, class, growth, skills[cursor], loadout);
}

fn skillReason(class: hero.Class, growth: *const progress.State, s: progress.Skill, buf: *menu.Note(128)) [:0]const u8 {
    if (growth.maxed(s.act)) return "Maximum rank reached.";
    if (s.parent) |p| if (!growth.unlocked(p)) {
        buf.say("Learn {s} first.", .{p.name()});
        return buf.text();
    };
    if (growth.active_points < progress.POINT_COST) return ACTIVE.requires;
    std.debug.assert(growth.canLearn(class, s.act));
    return if (growth.unlocked(s.act)) ACTIVE.ready("upgrade") else ACTIVE.ready("learn");
}

fn drawAction(face: *const font.Face, label: [:0]const u8, enabled: bool) void {
    const box = actionBox();
    rl.drawRectangleRec(box, TILE);
    menu.outline(box, enabled, OWNED, BORDER);
    const mid = raster.middleAt(box);
    face.centred(label, mid.x, mid.y, font.BODY, if (enabled) look.TEXT else LOCKED);
}

const Hit = progress.Hit;

fn skillHit(growth: *const progress.State, act: skillbar.Act, loadout: Loadout) ?Hit {
    return growth.hit(loadout.stats, loadout.gear, act);
}

fn hitText(act: skillbar.Act, hit: Hit, text: *menu.Note(128)) [:0]const u8 {
    if (hit.element) |e| {
        if (hit.physical.hi > 0) {
            text.say(damage.MIXED_FMT, .{ hit.physical.lo, hit.physical.hi, e.lo, e.hi, @tagName(act.element().?) });
        } else {
            text.say(damage.ELEMENT_FMT, .{ menu.named(act.element().?), e.lo, e.hi });
        }
    } else text.say(damage.PHYSICAL_FMT, .{ hit.physical.lo, hit.physical.hi });
    return text.text();
}

fn skillDetails(face: *const font.Face, class: hero.Class, growth: *const progress.State, s: progress.Skill, loadout: Loadout) void {
    const x = TEXT_X;
    face.engraved(s.act.name(), x, NAME_Y, font.HEAD, look.TEXT);
    var rank: menu.Note(64) = .{};
    const learned = growth.unlocked(s.act);
    if (learned) rank.say("Rank {d} of {d}", .{ growth.ranks.get(s.act), progress.RANKS }) else rank.say("Not learned", .{});
    face.draw(rank.text(), x, RANK_Y, font.SMALL, skillInk(class, growth, s));
    var desc: menu.Note(256) = .{};
    s.act.describe(desc.writer(), loadout.gear.perks(growth.perks()));
    const end = paragraph(face, desc.text(), x, DESC_Y, TEXT_W, look.TEXT);
    var top: i32 = @max(RULE_MIN_Y, end + RULE_GAP);
    rl.drawLine(x, top, x + TEXT_W, top, BORDER);
    top += RULE_GAP;
    face.draw(if (learned) "CURRENT RANK" else "FIRST RANK", x, top, font.SMALL, look.DIM);
    top += CAPTION_STEP;
    var text: menu.Note(128) = .{};
    const hit = skillHit(growth, s.act, loadout);
    if (hit) |h| {
        top = paragraph(face, hitText(s.act, h, &text), x, top, TEXT_W, look.TEXT);
        face.draw("Before critical hits and defenses.", x, top, font.SMALL, look.DIM);
        top += NOTE_STEP;
    }
    text.clear();
    growth.writeUsage(s.act, text.writer());
    text.buf[0] = std.ascii.toUpper(text.buf[0]);
    top = paragraph(face, text.text(), x, top, TEXT_W, look.TEXT);
    const maximum = growth.maxed(s.act);
    var next = growth.*;
    if (!maximum) next.ranks.getPtr(s.act).* += 1;
    if (learned and !maximum) {
        top += NEXT_GAP;
        text.say("NEXT RANK  {d}", .{next.ranks.get(s.act)});
        face.draw(text.text(), x, top, font.SMALL, OWNED);
        top += CAPTION_STEP;
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
            const cd = next.cooldown(s.act);
            text.say("Cooldown: {d} turn{s}", .{ cd, mathx.plural(cd) });
            top = paragraph(face, text.text(), x, top, TEXT_W, OWNED);
        }
        if (top == changes) {
            face.draw("No further stat changes.", x, top, font.LABEL, look.DIM);
            top += NOTE_STEP;
        }
    }
    if (s.act.flavor()) |line| _ = face.paragraph(line, x, top + FLAVOR_GAP, TEXT_W, font.LABEL, look.DIM);
    var reason: menu.Note(128) = .{};
    _ = paragraph(face, skillReason(class, growth, s, &reason), x, REASON_Y, TEXT_W, if (growth.canLearn(class, s.act)) OWNED else look.DIM);
    drawAction(face, if (maximum) "Maximum rank" else if (learned) "Upgrade skill" else "Learn skill", growth.canLearn(class, s.act));
}

const Layout = struct {
    box: rl.Rectangle,
    centre: rl.Vector2,
    unit: f32,

    /// Whether anything drawn within `margin` of the span from `a` to `b` can reach the clipped box.
    fn shows(self: Layout, a: rl.Vector2, b: rl.Vector2, margin: f32) bool {
        return @max(a.x, b.x) + margin >= self.box.x and @min(a.x, b.x) - margin <= self.box.x + self.box.width and
            @max(a.y, b.y) + margin >= self.box.y and @min(a.y, b.y) - margin <= self.box.y + self.box.height;
    }

    fn at(self: Layout, i: usize) rl.Vector2 {
        const p = passives.unitPos(i);
        return .{ .x = self.centre.x + p.x * self.unit, .y = self.centre.y + p.y * self.unit };
    }
};

/// How far the wheel centres on the cursor: not at all at the overview, wholly at the closest zoom.
fn pullOf(zoom: f32) f32 {
    return (std.math.clamp(zoom, ZOOM_MIN, ZOOM_MAX) - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN);
}

/// Rings the pan reaches at the overview, and how many more it gains as the zoom closes in.
const PAN_REACH: f32 = 1.6;
const PAN_REACH_ZOOMED: f32 = 6;
/// Rings of room the overview leaves past the outermost.
const WHEEL_MARGIN: f32 = 0.63;

/// `view.pan` within its zoom's reach, and never taking the view's middle off the wheel.
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

/// A Character message, over the tree canvas where no button covers it.
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

fn nodeRadius(i: usize, unit: f32) f32 {
    if (passives.NODES[i].ring == 0) return @max(8, unit * 0.26);
    const n = passives.NODES[i];
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

/// What a pool's point costs, said when short of it and when ready to spend it.
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

    fn ink(self: NodeState) rl.Color {
        return switch (self) {
            .allocated => OWNED,
            .reachable => AVAILABLE,
            .distant => LOCKED,
        };
    }
};

fn nodeInk(state: NodeState, arm: passives.Arm) rl.Color {
    return if (state == .distant) look.fade(armInk(arm), 0.55) else state.ink();
}

fn passiveLink(layout: Layout, pos: *const Positions, growth: *const progress.State, from: usize, to: usize) void {
    const before = growth.nodes.isSet(from);
    const after = growth.nodes.isSet(to);
    const bridge = passives.NODES[from].seam != null;
    const ink = if (before and after) OWNED else if (before or (bridge and after)) OPEN_LINE else look.fade(LINE, 0.65);
    const a = pos[from];
    const b = pos[to];
    if (!layout.shows(a, b, 2)) return;
    rl.drawLineEx(a, b, if (before and after) 2 else 1, ink);
}

const Positions = [passives.N]rl.Vector2;

fn drawPassives(face: *const font.Face, class: hero.Class, growth: *const progress.State, view: View, surface: menu.Surface, device: input.Device) void {
    rl.drawRectangleRec(CANVAS, BACK);
    rl.drawRectangleLinesEx(CANVAS, 1, BORDER);
    rl.drawLine(@intFromFloat(DETAIL.x), DETAIL_TOP, @intFromFloat(DETAIL.x), CANVAS_BOTTOM, BORDER);
    var points: menu.Note(64) = .{};
    points.say("{d} point{s} available", .{ growth.passive_points, mathx.plural(growth.passive_points) });
    face.draw(points.text(), CANVAS_LEFT, TITLE_Y, font.SMALL, if (growth.passive_points > 0) OWNED else look.DIM);
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
        if (!layout.shows(p, p, r + NODE_FOCUS_GROW)) continue;
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
            for ([_]f32{ -2, 2 }) |dy| rl.drawLineEx(.{ .x = p.x - 3, .y = p.y + dy }, .{ .x = p.x + 3, .y = p.y + dy }, 1, if (state == .allocated) BACK else armInk(s.to()));
        }
    }
    ring(pos[view.cursor], nodeRadius(view.cursor, layout.unit) + NODE_FOCUS_GROW, FOCUS);
    rl.endScissorMode();
    for ([_]bool{ false, true }) |increase| {
        const box = zoomBox(increase);
        const enabled = if (increase) view.zoom < ZOOM_MAX else view.zoom > ZOOM_MIN;
        rl.drawRectangleRec(box, TILE);
        rl.drawRectangleLinesEx(box, 1, if (enabled) AVAILABLE else BORDER);
        const mid = raster.middleAt(box);
        face.centred(if (increase) "+" else "-", mid.x, mid.y, font.BODY, if (enabled) look.TEXT else LOCKED);
    }
    menu.action(face, overviewBox(), if (device.pad()) prompt_icon.Prompt.menuOn(device, input.TreeKeys.PAD_OVERVIEW) else .{ .key = input.TreeKeys.OVERVIEW_CAPTION }, "Overview");
    passiveDetails(face, class, growth, view.cursor);
}

fn grantRow(face: *const font.Face, x: i32, y: i32, grant: passives.Grant) i32 {
    var text: menu.Note(100) = .{};
    grant.write(text.writer());
    return face.paragraph(text.text(), x, y, TEXT_W, font.BODY, look.TEXT);
}

/// What the grants alone leave unsaid.
fn grantNoteOf(n: passives.Node, out: *menu.Note(128)) ?[:0]const u8 {
    if (n.seam != null) return "Connects both paths. Reach this bridge from either side.";
    if (n.ring == 0) return "Another class origin can be allocated directly.";
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
            .mana_regen => return std.fmt.comptimePrint("Added to the base recovery of {d} mana per {d} turns.", .{ hero.MANA_REGEN, hero.MANA_REGEN_TURNS }),
            .mana_cost => return "Adds to the reduction from skill ranks.",
            .life_flask => return "Increases what each life flask drink recovers.",
            else => {},
        }
    }
    return null;
}

fn passiveDetails(face: *const font.Face, class: hero.Class, growth: *const progress.State, i: usize) void {
    const n = passives.NODES[i];
    const x = TEXT_X;
    const state = NodeState.of(growth, i);
    const origin = progress.bonusAt(class, i) == null;
    const enabled = growth.canAllocate(i);
    face.draw(if (n.ring == 0) armName(n.arm) else n.name, x, TITLE_Y, font.SMALL, look.DIM);
    var y: i32 = GRANT_Y;
    if (origin) {
        face.draw("Starting point", x, y, font.BODY, look.TEXT);
        return;
    }
    y = grantRow(face, x, y, n.grant);
    if (n.bump) |bump| y = grantRow(face, x, y, bump);
    var note_buf: menu.Note(128) = .{};
    if (grantNoteOf(n, &note_buf)) |line| _ = paragraph(face, line, x, y + RULE_GAP, TEXT_W, look.DIM);
    if (state == .allocated) {
        face.draw("Allocated", x, ACTION_Y, font.BODY, OWNED);
        return;
    }
    const reason: []const u8 = switch (state) {
        .allocated => unreachable,
        .distant => "Allocate a preceding node first.",
        .reachable => if (enabled) PASSIVE.cost else PASSIVE.requires,
    };
    _ = paragraph(face, reason, x, REASON_Y, TEXT_W, if (enabled) OWNED else look.DIM);
    drawAction(face, "Allocate", enabled);
}

test "every class skill stays in its canvas and is reachable by directional selection" {
    var checked: usize = 0;
    for (hero.CLASSES) |class| {
        const skills = progress.skills(class);
        var boxes: [skillbar.ACTS.len]rl.Rectangle = undefined;
        const area = CANVAS;
        const plaque_over: f32 = @floatFromInt(PLAQUE_AT.x + PLAQUE_W - SKILL_SIZE / 2);
        const name_foot: f32 = @floatFromInt(SKILL_NAME_DY + font.SMALL - SKILL_SIZE / 2);
        const legend_top: f32 = @floatFromInt(FOOT_MID - font.SMALL / 2);
        for (skills, 0..) |_, i| {
            const box = skillBox(class, i);
            boxes[i] = box;
            try std.testing.expect(box.x >= area.x and box.y >= area.y);
            try std.testing.expect(box.x + box.width + plaque_over <= area.x + area.width);
            try std.testing.expect(box.y + box.height + name_foot <= legend_top);
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
        checked += skills.len;
    }
    std.debug.print("class skill diagrams: {d} non-overlapping tiles within their canvas; all reachable in 8 directions\n", .{checked});
}

/// Every zoom a button press reaches from the overview, the closest and the opening one.
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
        const r = nodeRadius(i, layout.unit) + NODE_FOCUS_GROW;
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
            const radius = nodeRadius(i, zoomed.unit) + NODE_FOCUS_GROW;
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
    std.debug.print("passive diagram: all {d} nodes fit without overlap; selected node and clipped hit targets checked at {d} zoom levels\n", .{ passives.N, TEST_ZOOMS.len });
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
    std.debug.print("passive pan: at least {d} nodes stay on the canvas at the furthest pan from any node\n", .{fewest});
    try std.testing.expect(fewest > 0);
}
