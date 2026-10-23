const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const day = @import("../map/day.zig");
const actor = @import("../play/actor.zig");
const chronicle = @import("../play/chronicle.zig");
const obituary = @import("../play/obituary.zig");
const ossuary = @import("../play/ossuary.zig");
const skillbar = @import("../play/skillbar.zig");
const game = @import("../game.zig");
const skills = @import("skills.zig");

fn bound(g: *const game.Game, act: skillbar.Act) bool {
    for (skillbar.SETS) |s| {
        if (g.bar.buttonOf(s, act) != null) return true;
    }
    return false;
}

/// Why a bound `act` could not be used now, `.unbound` when it is not on the bar.
fn readiness(g: *const game.Game, act: skillbar.Act) enum { ready, mana, other, unbound } {
    if (!bound(g, act)) return .unbound;
    const why = skills.blocked(g, act, &g.sim.flasks, g.sim.mana) orelse return .ready;
    return if (why == .mana) .mana else .other;
}

/// The hero as a turn begins, for the chronicle; a stunned turn readies nothing.
pub fn turnStart(g: *const game.Game) chronicle.Start {
    const h = g.sim.pool.items[g.sim.heroSlot().?];
    const s = chronicle.Start{ .hp = h.hp, .max = h.max };
    if (h.clock.owes()) return s;
    const ward = readiness(g, chronicle.WARD);
    var out = s;
    out.flask = readiness(g, chronicle.FLASK) == .ready;
    out.ward = ward == .ready;
    out.starved = ward == .mana;
    return out;
}

const IN = "in ";

/// "in the Warrens": a map's node title, its leading article lowered.
fn placeOf(g: *const game.Game, out: *[IN.len + atlas.TITLE_MAX]u8) []const u8 {
    const w = g.sim.map orelse return "on a nameless floor";
    var title: [atlas.TITLE_MAX]u8 = undefined;
    const t = w.node[g.sim.node].title(g.sim.node, &title);
    const s = std.fmt.bufPrint(out, IN ++ "{s}", .{t}) catch unreachable;
    if (std.mem.startsWith(u8, t, "The ")) s[IN.len] = 't';
    return s;
}

/// The dead hero's bones and summary, said as the chronicle saw the death.
pub fn of(g: *const game.Game) ossuary.Entry {
    const s = &g.sim;
    const h = s.pool.items[s.heroSlot().?];
    var e = ossuary.Entry{
        .name = s.name,
        .class = s.class,
        .level = s.growth.level,
        .kills = @intCast(@min(s.kills, std.math.maxInt(u32))),
        .gold = s.gold,
        .renown = obituary.renown(.{ .kills = s.kills, .level = s.growth.level, .gold = s.gold, .places = s.visited.count() + @intFromBool(!s.visited.isSet(s.node)) }),
        .seed = s.seed,
    };
    var buf: [chronicle.KEPT]chronicle.Turn = undefined;
    const turns = s.chronicle.recent(chronicle.RECENT, &buf);
    const killer = if (turns.len > 0) turns[turns.len - 1].lastHurt() else null;
    const k = killer orelse {
        var said: [ossuary.SUMMARY_MAX]u8 = undefined;
        e.say(std.fmt.bufPrint(&said, "{} died.", .{obituary.Titled{ .name = s.name.text(), .class = s.class }}) catch "");
        return e;
    };
    var place: [IN.len + atlas.TITLE_MAX]u8 = undefined;
    var beside: usize = 0;
    var open: usize = 0;
    for (mathx.ALL_DIRS) |d| {
        const to = h.at.add(d.delta());
        const who = s.lv.who(to);
        if (who != grid.NO_ONE) {
            const a = s.pool.items[actor.Pool.slot(who)];
            if (a.alive and a.foe()) beside += 1;
        }
        if (s.lv.stepOk(h.at, d, grid.NO_ONE)) open += 1;
    }
    const ctx = obituary.Context{
        .name = s.name.text(),
        .class = s.class,
        .killer = k,
        .place = placeOf(g, &place),
        .night = s.outdoors and !day.arc(s.clock.hour()).day,
        .level = s.growth.level,
        .short = s.growth.needed() -| s.growth.xp,
        .needed = s.growth.needed(),
        .points = s.growth.passive_points +| s.growth.active_points,
        .beside = beside,
        .open = open,
        .turns = turns,
        .milestone = s.chronicle.milestone,
    };
    e.say(obituary.write(&ctx).text());
    return e;
}

/// Writes the dead hero's epitaph, and entombs it if the hall has room for its renown.
pub fn inscribe(g: *game.Game) void {
    var e = of(g);
    if (g.hall) |hall| if (hall.qualifies(e.renown)) {
        e.sayEntombed();
        _ = hall.entomb(e);
    };
    g.epitaph = e;
}
