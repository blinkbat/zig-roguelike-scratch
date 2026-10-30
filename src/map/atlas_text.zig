const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const procgen = @import("procgen.zig");
const actor = @import("../play/actor.zig");
const store = @import("../core/store.zig");
const pack = @import("../play/pack.zig");
const climate = @import("climate.zig");
const atlas = @import("atlas.zig");
const script_text = @import("script_text.zig");
const P = mathx.P;
const Tokens = std.mem.TokenIterator(u8, .scalar);
const Error = atlas.Error;
const COLS = grid.COLS;
const ROWS = grid.ROWS;
const Algo = procgen.Algo;
const Floor = procgen.Floor;
const Kind = procgen.Kind;
const Feature = procgen.Feature;

pub const HEADER = "roguelike-map 1";
const TEXT_CAP: usize = 8 << 20;

pub fn save(self: *atlas.Atlas, alloc: std.mem.Allocator, path: []const u8) !void {
    var text = std.ArrayList(u8).init(alloc);
    defer text.deinit();
    try write(self, text.writer());
    try store.replace(path, text.items);
}

pub fn write(self: *atlas.Atlas, w: anytype) !void {
    try w.print(HEADER ++ "\n" ++ says(.start) ++ "{d} {d} {d}\n", .{ self.start.node, self.start.at.x, self.start.at.y });
    for (self.nodes()) |*nd| {
        switch (nd.plan) {
            .procgen => |*pg| {
                try w.print(says(.node) ++ "{s} {s}\n", .{ @tagName(nd.plan), @tagName(pg.floor) });
                try putArm(w, &pg.floor);
                inline for (GROUPS) |grp| {
                    inline for (grp.knobs) |k| try putKnob(w, k, @field(@field(pg, grp.field), k));
                }
                for (pg.foes.makeups()) |*m| {
                    try w.print(says(.makeup) ++ "{d}", .{m.weight});
                    for (m.kinds()) |k| try w.print(" {s}", .{@tagName(k)});
                    try w.writeByte('\n');
                }
                for (pg.features()) |*ft| {
                    try w.print(says(.feature) ++ "{s}\n", .{@tagName(ft.*)});
                    try putArm(w, ft);
                }
            },
            .bespoke => |*b| {
                try w.print(says(.node) ++ "{s}\n", .{@tagName(nd.plan)});
                for (0..ROWS) |y| {
                    try w.writeAll(says(.row));
                    for (0..COLS) |x| {
                        const i = grid.Level.idx(.{ .x = @intCast(x), .y = @intCast(y) });
                        try w.writeByte(if (b.barrel[i]) grid.BARREL_LETTER else b.tile[i].letter());
                    }
                    try w.writeByte('\n');
                }
                for (b.torches()) |t| try w.print(says(.torch) ++ "{d} {d}\n", .{ t.x, t.y });
                for (b.foes()) |f| try w.print(says(.foe) ++ "{s} {d} {d}\n", .{ @tagName(f.kind), f.at.x, f.at.y });
            },
        }
        if (nd.label.n > 0) try w.print(says(.name) ++ "{s}\n", .{nd.name()});
        try w.print(says(.at) ++ "{d} {d}\n", .{ nd.pos.x, nd.pos.y });
        for (nd.doors()) |d| {
            try w.print(says(.door) ++ "{d} {d}", .{ d.at.x, d.at.y });
            if (d.to) |l| try w.print(" {d} {d}", .{ l.node, l.door });
            try w.writeByte('\n');
        }
    }
    try script_text.write(&self.script, w);
}

pub fn load(self: *atlas.Atlas, alloc: std.mem.Allocator, path: []const u8) !void {
    const text = try std.fs.cwd().readFileAlloc(alloc, path, TEXT_CAP);
    defer alloc.free(text);
    try parse(self, text);
}

pub fn parse(self: *atlas.Atlas, text: []const u8) Error!void {
    self.* = .{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    const head = std.mem.trimRight(u8, lines.next() orelse return error.NoHeader, "\r");
    if (!std.mem.eql(u8, head, HEADER)) return error.NoHeader;
    var row: usize = 0;
    var own_makeups = false;
    var seen = std.EnumSet(Word).initEmpty();
    var knobbed = KnobSet.initEmpty();
    var featured = FeatureKnobSet.initEmpty();
    var told = try script_text.Reader.of(text);
    while (lines.next()) |raw| {
        const line = std.mem.trimRight(u8, raw, "\r");
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        const word = f.next() orelse continue;
        if (std.meta.stringToEnum(script_text.Word, word)) |sw| {
            try told.take(&self.script, sw, &f);
            if (f.next() != null) return error.BadLine;
            continue;
        }
        const said = std.meta.stringToEnum(Word, word) orelse {
            const pg = try lastProcgen(self);
            if (pg.feature_n > 0) {
                try takeFeatureKnob(&pg.feature[pg.feature_n - 1], word, &f, &featured);
            } else try takeKnob(pg, word, &f, &knobbed);
            if (f.next() != null) return error.BadLine;
            continue;
        };
        if (ONCE.contains(said)) {
            if (seen.contains(said)) return error.BadLine;
            seen.insert(said);
        }
        switch (said) {
            .start => self.start = .{ .node = try int(usize, &f), .at = try cell(&f) },
            .node => {
                const kind = try takeValue(std.meta.Tag(atlas.Plan), &f);
                const plan: atlas.Plan = switch (kind) {
                    .procgen => blk: {
                        const algo = try takeValue(Algo, &f);
                        // Accept and discard seeds from older map files.
                        if (f.peek() != null) _ = try int(u64, &f);
                        break :blk .{ .procgen = .{ .floor = Floor.of(algo) } };
                    },
                    .bespoke => .{ .bespoke = .{} },
                };
                try finished(self, row);
                _ = self.add(plan) orelse return error.TooMany;
                row = 0;
                own_makeups = false;
                seen = seen.intersectWith(ONCE_FILE);
                knobbed = KnobSet.initEmpty();
            },
            .name => {
                if ((try lastNode(self)).rename(f.rest()) != true) return error.BadLine;
                continue;
            },
            .at => {
                const pos = try point(&f);
                if (!atlas.clampPos(pos).eq(pos)) return error.BadLine;
                (try lastNode(self)).pos = pos;
            },
            .door => {
                const nd = try lastNode(self);
                const at = try cell(&f);
                const k = self.addDoor(self.node_n - 1, at) orelse return error.TooMany;
                if (f.peek() != null) nd.door[k].to = .{ .node = try int(usize, &f), .door = try int(usize, &f) };
            },
            .feature => {
                const pg = try lastProcgen(self);
                const k = try takeValue(Kind, &f);
                if (!pg.addFeature(k)) return error.TooMany;
                featured = FeatureKnobSet.initEmpty();
            },
            .makeup => {
                const pg = try lastProcgen(self);
                if (pg.feature_n > 0) return error.BadLine;
                const fo = &pg.foes;
                if (!own_makeups) fo.makeup_n = 0;
                own_makeups = true;
                if (!fo.addMakeup()) return error.TooMany;
                const m = &fo.makeup[fo.makeup_n - 1];
                m.* = .{ .weight = try int(u8, &f), .n = 0 };
                while (f.next()) |name| {
                    const k = std.meta.stringToEnum(actor.Kind, name) orelse return error.BadLine;
                    if (!m.grow()) return error.BadLine;
                    m.kind[m.n - 1] = k;
                }
            },
            .row => {
                const b = try lastBespoke(self);
                const cells = f.next() orelse return error.BadLine;
                if (cells.len != COLS or row == ROWS) return error.BadLine;
                for (cells, 0..) |c, x| {
                    const i = grid.Level.idx(.{ .x = @intCast(x), .y = @intCast(row) });
                    b.barrel[i] = c == grid.BARREL_LETTER;
                    b.tile[i] = grid.groundOf(c) orelse return error.BadLine;
                    if (b.tile[i].isOpened()) return error.BadLine;
                }
                row += 1;
            },
            .torch => if (!(try lastBespoke(self)).torch.add(try cell(&f))) return error.TooMany,
            .foe => {
                const b = try lastBespoke(self);
                const k = try takeValue(actor.Kind, &f);
                if (!k.stocked() or !b.addFoe(.{ .kind = k, .at = try cell(&f) })) return error.BadLine;
            },
        }
        if (f.next() != null) return error.BadLine;
    }
    try finished(self, row);
    if (self.node_n == 0) return error.NoNodes;
    if (!seen.contains(.start)) return error.NoStart;
    for (self.nodes(), 0..) |*nd, n| {
        for (nd.doors(), 0..) |d, k| {
            const l = d.to orelse continue;
            if (l.node >= self.node_n or l.door >= self.node[l.node].door_n) return error.BadLink;
            const here = atlas.Link{ .node = n, .door = k };
            if (l.eq(here)) return error.BadLink;
            const back = self.door(l).to orelse return error.BadLink;
            if (!back.eq(here)) return error.BadLink;
        }
    }
    if (self.start.node >= self.node_n) return error.BadLink;
    if (!self.script.valid(self.node_n)) return error.BadLine;
    for (self.script.folks()) |f| {
        if (!self.folkFits(f.node, f.at)) return error.BadLine;
    }
}

fn finished(self: *atlas.Atlas, rows: usize) Error!void {
    if (self.node_n == 0) return;
    const nd = &self.node[self.node_n - 1];
    switch (nd.plan) {
        .bespoke => |*b| {
            if (rows != ROWS) return error.BadLine;
            for (b.foes()) |f| {
                if (!nd.foeFits(b, f.at, f.kind)) return error.BadLine;
            }
            for (b.torches()) |t| {
                if (!nd.torchFits(b, t)) return error.BadLine;
            }
            for (b.barrel, 0..) |on, i| {
                if (on and !nd.barrelFits(b, grid.Level.of(i))) return error.BadLine;
            }
        },
        .procgen => |*pg| if (!pg.valid()) return error.BadLine,
    }
}

fn lastProcgen(self: *atlas.Atlas) Error!*atlas.Procgen {
    return switch ((try lastNode(self)).plan) {
        .procgen => |*pg| pg,
        .bespoke => error.BadLine,
    };
}

fn lastNode(self: *atlas.Atlas) Error!*atlas.Node {
    if (self.node_n == 0) return error.BadLine;
    return &self.node[self.node_n - 1];
}

fn lastBespoke(self: *atlas.Atlas) Error!*atlas.Bespoke {
    return switch ((try lastNode(self)).plan) {
        .bespoke => |*b| b,
        .procgen => error.BadLine,
    };
}

/// A procgen node's base lines: each named for, and holding, a field of its floor; the foes' and sky's are `GROUPS`.
pub fn floorKnobs(comptime a: Algo) []const []const u8 {
    return armKnobs(Floor, a);
}
const FLOOR_KNOBS_MAX = mostKnobs(Floor);
pub const FOE_KNOBS = knobsOf(pack.Spec, MAKEUP_FIELDS);
pub const SKY_KNOBS = knobsOf(climate.Climate, &.{});
/// Every other line's first word, which no knob may take.
const Word = enum { start, node, name, at, door, makeup, feature, row, torch, foe };
const ONCE_FILE = std.EnumSet(Word).initOne(.start);
const ONCE_NODE = std.EnumSet(Word).initMany(&.{ .name, .at });
const ONCE = ONCE_FILE.unionWith(ONCE_NODE);
/// A feature's lines after its own: each named for, and holding, a field of it.
pub fn featureKnobs(comptime k: Kind) []const []const u8 {
    return armKnobs(Feature, k);
}
const FEATURE_KNOBS_MAX = mostKnobs(Feature);
const FeatureKnobSet = std.StaticBitSet(FEATURE_KNOBS_MAX);
const GROUPS = [_]struct { field: []const u8, knobs: []const []const u8 }{
    .{ .field = "foes", .knobs = FOE_KNOBS },
    .{ .field = "sky", .knobs = SKY_KNOBS },
};
const GROUP_KNOBS = blk: {
    var all: []const []const u8 = &.{};
    for (GROUPS) |grp| all = all ++ grp.knobs;
    break :blk all;
};
/// An algorithm's knobs by place, then each group's in turn after `FLOOR_KNOBS_MAX`.
const KnobSet = std.StaticBitSet(groupBase(GROUPS.len));
const MAKEUP = @tagName(Word.makeup);
/// `pack.Spec`'s makeups, which are lines of their own.
const MAKEUP_FIELDS: []const []const u8 = &.{ MAKEUP, MAKEUP ++ "_n" };

fn says(comptime w: Word) []const u8 {
    return script_text.firstWord(w);
}

/// Each node's `name` line in map text: the node's index, its name and the line it is on, counted from 1.
pub const NodeNames = struct {
    lines: std.mem.SplitIterator(u8, .scalar),
    line: usize = 0,
    node: usize = 0,

    pub const Named = struct { node: usize, name: []const u8, line: usize };

    pub fn of(text: []const u8) NodeNames {
        return .{ .lines = std.mem.splitScalar(u8, text, '\n') };
    }

    pub fn next(self: *NodeNames) ?Named {
        while (self.lines.next()) |raw| {
            self.line += 1;
            const text = std.mem.trim(u8, raw, " \r");
            if (std.mem.startsWith(u8, text, says(.node))) self.node += 1;
            if (!std.mem.startsWith(u8, text, says(.name))) continue;
            const name = std.mem.trim(u8, text[says(.name).len..], " ");
            if (name.len == 0) continue;
            return .{ .node = self.node -| 1, .name = name, .line = self.line };
        }
        return null;
    }
};

comptime {
    @setEvalBranchQuota(1_000_000);
    for (MAKEUP_FIELDS) |m| std.debug.assert(@hasField(pack.Spec, m));
    const words = knobsOf(Word, &.{}) ++ knobsOf(script_text.Word, &.{});
    for (std.enums.values(Algo)) |algo| distinct(floorKnobs(algo) ++ GROUP_KNOBS ++ words);
    for (std.enums.values(Kind)) |kind| distinct(featureKnobs(kind) ++ words);
}

fn distinct(comptime names: []const []const u8) void {
    for (names, 0..) |a, i| {
        for (names[0..i]) |b| std.debug.assert(!std.mem.eql(u8, a, b));
    }
}

fn armKnobs(comptime U: type, comptime tag: std.meta.Tag(U)) []const []const u8 {
    return knobsOf(@FieldType(U, @tagName(tag)), &.{});
}

fn mostKnobs(comptime U: type) usize {
    var most: usize = 0;
    for (std.enums.values(std.meta.Tag(U))) |t| most = @max(most, armKnobs(U, t).len);
    return most;
}

fn knobsOf(comptime T: type, comptime skip: []const []const u8) []const []const u8 {
    @setEvalBranchQuota(100_000);
    comptime var out: []const []const u8 = &.{};
    inline for (std.meta.fields(T)) |f| {
        const skipped = for (skip) |s| {
            if (std.mem.eql(u8, s, f.name)) break true;
        } else false;
        if (!skipped) out = out ++ &[_][]const u8{f.name};
    }
    return out;
}

fn takeKnob(pg: *atlas.Procgen, word: []const u8, f: *Tokens, knobbed: *KnobSet) Error!void {
    if (try takeArm(&pg.floor, word, f, knobbed)) return;
    inline for (GROUPS, 0..) |grp, g| {
        inline for (grp.knobs, 0..) |k, i| {
            if (std.mem.eql(u8, word, k)) return takeOnce(&@field(pg, grp.field), k, comptime groupBase(g) + i, f, knobbed);
        }
    }
    return error.BadLine;
}

fn groupBase(comptime g: usize) usize {
    var at = FLOOR_KNOBS_MAX;
    for (GROUPS[0..g]) |grp| at += grp.knobs.len;
    return at;
}

fn takeFeatureKnob(ft: *Feature, word: []const u8, f: *Tokens, set: *FeatureKnobSet) Error!void {
    if (!try takeArm(ft, word, f, set)) return error.BadLine;
}

fn takeArm(u: anytype, word: []const u8, f: *Tokens, knobbed: anytype) Error!bool {
    switch (u.*) {
        inline else => |*p, t| inline for (comptime armKnobs(@TypeOf(u.*), t), 0..) |k, i| {
            if (std.mem.eql(u8, word, k)) {
                try takeOnce(p, k, i, f, knobbed);
                return true;
            }
        },
    }
    return false;
}

fn putArm(w: anytype, u: anytype) !void {
    switch (u.*) {
        inline else => |*p, t| inline for (comptime armKnobs(@TypeOf(u.*), t)) |k| try putKnob(w, k, @field(p.*, k)),
    }
}

fn takeOnce(owner: anytype, comptime k: []const u8, i: usize, f: *Tokens, knobbed: anytype) Error!void {
    if (knobbed.isSet(i)) return error.BadLine;
    knobbed.set(i);
    @field(owner.*, k) = try takeValue(@TypeOf(@field(owner.*, k)), f);
}

fn putKnob(w: anytype, comptime name: []const u8, v: anytype) !void {
    try w.writeAll(name);
    try putValue(w, v);
    try w.writeByte('\n');
}

/// How many numbers a knob of type `T` holds on its line.
pub fn knobNumbers(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .int, .@"enum" => 1,
        .array => |a| a.len,
        .@"struct" => |s| s.fields.len,
        else => @compileError(@typeName(T) ++ " is no knob"),
    };
}

fn putValue(w: anytype, v: anytype) !void {
    const T = @TypeOf(v);
    switch (@typeInfo(T)) {
        .int => try w.print(" {d}", .{v}),
        .@"enum" => try w.print(" {s}", .{@tagName(v)}),
        .array => for (v) |x| try putValue(w, x),
        .@"struct" => inline for (std.meta.fields(T)) |f| try putValue(w, @field(v, f.name)),
        else => @compileError(@typeName(T) ++ " is no knob"),
    }
}

fn takeValue(comptime T: type, f: *Tokens) Error!T {
    switch (@typeInfo(T)) {
        .int => return int(T, f),
        .@"enum" => {
            const value = try script_text.value(T, f);
            if (T == grid.Tile and value.isOpened()) return error.BadLine;
            return value;
        },
        .array => |a| {
            var out: T = undefined;
            for (&out) |*x| x.* = try takeValue(a.child, f);
            return out;
        },
        .@"struct" => {
            var out: T = undefined;
            inline for (std.meta.fields(T)) |fl| @field(out, fl.name) = try takeValue(fl.type, f);
            return out;
        },
        else => @compileError(@typeName(T) ++ " is no knob"),
    }
}

const int = script_text.int;
const point = script_text.point;
const cell = script_text.cell;

test "node names are read with their node and line, blank names skipped" {
    var it = NodeNames.of("roguelike-map 1\nnode bespoke\nname First room\r\nnode procgen wilds\nname   \nnode procgen open\n  name  Third  \n");
    const want = [_]NodeNames.Named{ .{ .node = 0, .name = "First room", .line = 3 }, .{ .node = 2, .name = "Third", .line = 7 } };
    for (want) |w| {
        const got = it.next().?;
        try std.testing.expectEqual(w.node, got.node);
        try std.testing.expectEqualStrings(w.name, got.name);
        try std.testing.expectEqual(w.line, got.line);
    }
    try std.testing.expect(it.next() == null);
    std.debug.print("node names: {d} named nodes of 3 read with node index and line\n", .{want.len});
}

test "a map saves and loads back the same" {
    const a = try atlas.testAtlas();
    defer std.testing.allocator.destroy(a);
    const room = a.add(.{ .bespoke = .{} }).?;
    const cave = a.add(.{ .procgen = .{} }).?;
    const pg = &a.node[cave].plan.procgen;
    pg.floor.rooms.size = .{ .x = 50, .y = 40 };
    pg.floor.rooms.torches = 20;
    const wood = a.add(.{ .procgen = .{ .floor = .{ .wilds = .{ .thicket = 30, .strays = 7 } } } }).?;
    const wpg = &a.node[wood].plan.procgen;
    _ = wpg.addFeature(.river);
    wpg.feature[0].river.fill = .lava;
    wpg.feature[0].river.width = 5;
    _ = wpg.addFeature(.setpiece);
    wpg.feature[1].setpiece.piece = .graveyard;
    pg.foes.apart = 6;
    pg.foes.makeup_n = 2;
    pg.foes.makeup[1] = pack.Makeup.of(&.{ .bloat, .rat });
    pg.foes.makeup[1].weight = 3;
    const b = &a.node[room].plan.bespoke;
    var floor = grid.Box.sized(.{ .x = 3, .y = 3 }, 9, 6).cells();
    while (floor.next()) |p| b.tile[grid.Level.idx(p)] = .floor;
    b.barrel[grid.Level.idx(.{ .x = 4, .y = 4 })] = true;
    _ = b.torch.add(.{ .x = 6, .y = 2 });
    _ = b.addFoe(.{ .kind = .slime, .at = .{ .x = 9, .y = 6 } });
    const d0 = a.addDoor(room, .{ .x = 11, .y = 5 }).?;
    const d1 = a.addDoor(cave, .{ .x = 0, .y = 30 }).?;
    a.link(.{ .node = room, .door = d0 }, .{ .node = cave, .door = d1 });
    a.start = .{ .node = room, .at = .{ .x = 5, .y = 5 } };
    try std.testing.expectEqual(@as(?bool, true), a.node[cave].rename("  The Deep Cave "));
    try std.testing.expectEqual(@as(?bool, false), a.node[cave].rename("The Deep Cave"));
    try std.testing.expectEqual(@as(?bool, null), a.node[room].rename("a name far too long to keep"));
    a.node[room].pos = .{ .x = -40, .y = 310 };

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try a.write(buf.writer());
    const back = try atlas.testAtlas();
    defer std.testing.allocator.destroy(back);
    try back.parse(buf.items);
    var again = std.ArrayList(u8).init(std.testing.allocator);
    defer again.deinit();
    try back.write(again.writer());
    std.debug.print("a two-node map is {d} bytes of text\n", .{buf.items.len});
    try std.testing.expectEqualStrings(buf.items, again.items);
    try std.testing.expectEqual(@as(?atlas.Link, .{ .node = cave, .door = d1 }), back.node[room].door[d0].to);
    const bpg = &back.node[cave].plan.procgen;
    try std.testing.expect(std.meta.eql(pg.floor, bpg.floor));
    try std.testing.expect(std.meta.eql(a.node[wood].plan.procgen, back.node[wood].plan.procgen));
    try std.testing.expectEqual(grid.Tile.lava, back.node[wood].plan.procgen.feature[0].river.fill);
    try std.testing.expectEqual(@as(i32, 6), bpg.foes.apart);
    try std.testing.expectEqual(@as(usize, 2), bpg.foes.makeup_n);
    try std.testing.expectEqual(@as(u8, 3), bpg.foes.makeup[1].weight);
    try std.testing.expectEqualSlices(actor.Kind, &.{ .bloat, .rat }, bpg.foes.makeup[1].kinds());
    try std.testing.expectEqualStrings("The Deep Cave", back.node[cave].name());
    try std.testing.expectEqual(P{ .x = -40, .y = 310 }, back.node[room].pos);
    try std.testing.expectEqual(atlas.GRAPH_STEP.x, back.node[cave].pos.x);
}

test "fresh map text refuses opened containers in terrain and generator choices" {
    const a = try atlas.testAtlas();
    defer std.testing.allocator.destroy(a);
    const head = HEADER ++ "\nstart 0 5 5\n";
    const features = [_][]const u8{
        "feature scatter\ntile chest_open\n",
        "feature scatter\non chest_open\n",
        "feature lake\nfill chest_open\n",
        "feature river\nfill chest_open\n",
        "feature border\ntile chest_open\n",
    };
    inline for (features) |feature| try std.testing.expectError(error.BadLine, a.parse(head ++ "node procgen open\n" ++ feature));
    const rows = ("row " ++ "." ** COLS ++ "\n") ** (ROWS - 1);
    try std.testing.expectError(error.BadLine, a.parse(head ++ "node bespoke\nrow O" ++ "." ** (COLS - 1) ++ "\n" ++ rows));
    try a.parse(head ++ "node bespoke\nrow C" ++ "." ** (COLS - 1) ++ "\n" ++ rows);
    try std.testing.expectEqual(grid.Tile.chest, a.node[0].plan.bespoke.tile[0]);
    try a.parse(head ++ "node procgen open\nfeature scatter\ntile chest\n");
    try std.testing.expectEqual(grid.Tile.chest, a.node[0].plan.procgen.feature[0].scatter.tile);
    std.debug.print("fresh map text: 6 opened-container inputs refused; closed chests preserved in terrain and scatter\n", .{});
}

test "a map file with a one-way link, a door linked to itself, a stray word, a far box or a number not written plainly is refused" {
    const a = try atlas.testAtlas();
    defer std.testing.allocator.destroy(a);
    const head = HEADER ++ "\nstart 0 5 5\n";
    const bad = [_][]const u8{
        head ++ "node procgen rooms\ndoor 5 5 1 0\nnode procgen rooms\ndoor 5 5\n",
        head ++ "node procgen rooms\ndoor 5 5 0 0\n",
        head ++ "node procgen rooms 1 2\n",
        head ++ "node procgen rooms deep\n",
        head ++ "node procgen rooms\nat 0 0\nnode procgen rooms\nat -2147483648 0\nnode procgen rooms\n",
        head ++ "node bespoke\nrow " ++ "#" ** COLS ++ "\n",
        head ++ "node procgen rooms\nsize 20 20\nroom_w 5 30\n",
        head ++ "node procgen rooms\nmakeup 0 rat\n",
        head ++ "node procgen rooms\nmakeup 1 slime_half\n",
        head ++ "node procgen rooms\nmakeup 1\n",
        head ++ "node procgen rooms\napart 99\n",
        head ++ "node bespoke\n" ++ ("row " ++ "#" ** COLS ++ "\n") ** ROWS ++ "foe rat 3 3\n",
        head ++ "node bespoke\n" ++ ("row " ++ "." ** COLS ++ "\n") ** ROWS ++ "foe slime_half 3 3\n",
        head ++ "node bespoke\n" ++ ("row " ++ "#" ** COLS ++ "\n") ** ROWS ++ "torch 3 3\n",
        head ++ "node bespoke\n" ++ ("row " ++ "." ** COLS ++ "\n") ** ROWS ++ "torch 3 3\n",
        head ++ "node bespoke\n" ++ ("row " ++ "0" ** COLS ++ "\n") ** ROWS ++ "door 3 3\n",
        head ++ "start 0 6 6\nnode procgen rooms\n",
        head ++ "node procgen rooms\nname A\nname B\n",
        head ++ "node procgen rooms\nname   \n",
        head ++ "node procgen rooms\nat 0 0\nat 1 1\n",
        head ++ "node procgen rooms\napart 4\napart 5\n",
        head ++ "node procgen wilds\nrooms 4\n",
        head ++ "node procgen rooms\nthicket 40\n",
        head ++ "node procgen wilds\nthicket 99\n",
        head ++ "node procgen wilds\nfeature river\nthicket 40\n",
        head ++ "node procgen wilds\nfeature river\nwidth 3\nwidth 4\n",
        head ++ "node procgen wilds\nfeature river\nmakeup 1 rat\n",
        head ++ "node procgen wilds\nfeature canal\n",
        head ++ "node procgen wilds\nfeature river\nfill moss\n",
        HEADER ++ "\nnode procgen rooms\n",
        head ++ "node procgen rooms\nat +1 0\n",
        head ++ "node procgen rooms\nat 0_1 0\n",
        head ++ "node procgen rooms\nat 01 0\n",
        head ++ "node procgen rooms\nat -0 0\n",
    };
    for (bad) |t| try std.testing.expect(std.meta.isError(a.parse(t)));
    try a.parse(head ++ "node procgen rooms 1790812916605\n");
    try a.parse(head ++ "node bespoke\n" ++ ("row " ++ "#" ** COLS ++ "\n") ** 4 ++ "row " ++ "." ** COLS ++ "\n" ++ ("row " ++ "#" ** COLS ++ "\n") ** (ROWS - 5) ++ "torch 3 3\n");
    try std.testing.expectEqual(@as(usize, 1), a.node[0].plan.bespoke.torch.n);
    try a.parse(head ++ "node procgen rooms\n  name  Deep  Cave\n");
    try std.testing.expectEqualStrings("Deep  Cave", a.node[0].name());
    try a.parse(head ++ "node procgen rooms\nat 0 0\napart 4\nnode procgen rooms\nat 1 1\napart 5\n");
    try a.parse(head ++ "node procgen wilds\nthicket 50\nsmooth 2\nstrays 0\npacks 4\n");
    try std.testing.expectEqual(50, a.node[0].plan.procgen.floor.wilds.thicket);
    try a.parse(head ++ "node procgen caves\nfill 50\nfeature lake\nfill lava\ncount 2\nfeature river\nwidth 2\n");
    const pg = &a.node[0].plan.procgen;
    try std.testing.expectEqual(@as(usize, 2), pg.feature_n);
    try std.testing.expectEqual(grid.Tile.lava, pg.feature[0].lake.fill);
    try std.testing.expectEqual(@as(u8, 2), pg.feature[1].river.width);
}

fn testChangedKnobs(v: anytype) @TypeOf(v) {
    const T = @TypeOf(v);
    return switch (@typeInfo(T)) {
        .int => v +| 1,
        .@"enum" => if (T == grid.Tile) v else blk: {
            const values = std.enums.values(T);
            const i = std.mem.indexOfScalar(T, values, v).?;
            break :blk values[(i + 1) % values.len];
        },
        .array => blk: {
            var out = v;
            for (&out) |*x| x.* = testChangedKnobs(x.*);
            break :blk out;
        },
        .@"struct" => blk: {
            var out = v;
            inline for (std.meta.fields(T)) |f| @field(out, f.name) = testChangedKnobs(@field(out, f.name));
            break :blk out;
        },
        .@"union" => switch (v) {
            inline else => |p, tag| @unionInit(T, @tagName(tag), testChangedKnobs(p)),
        },
        else => @compileError("unsupported test knob " ++ @typeName(T)),
    };
}

test "map text round-trips every floor and feature with default and changed knobs" {
    const a = try atlas.testAtlas();
    defer std.testing.allocator.destroy(a);
    const back = try atlas.testAtlas();
    defer std.testing.allocator.destroy(back);
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    var again = std.ArrayList(u8).init(std.testing.allocator);
    defer again.deinit();
    var checked: usize = 0;
    for ([_]bool{ false, true }) |changed| {
        for (std.enums.values(Algo)) |algo| {
            for (std.enums.values(Kind)) |kind| {
                a.* = .{};
                const n = a.add(.{ .procgen = .{ .floor = Floor.of(algo) } }).?;
                const pg = &a.node[n].plan.procgen;
                try std.testing.expect(pg.addFeature(kind));
                if (changed) {
                    pg.floor = testChangedKnobs(pg.floor).fit();
                    pg.feature[0] = testChangedKnobs(pg.feature[0]).fit();
                    pg.sky = .{ .light = .bleak, .weather = .drizzle };
                    pg.foes.apart = 7;
                    pg.foes.makeup_n = 1;
                    pg.foes.makeup[0] = pack.Makeup.of(&.{ .bandit_crossbowman, .rat, .slime });
                    pg.foes.makeup[0].weight = 4;
                }
                try std.testing.expect(pg.valid());
                buf.clearRetainingCapacity();
                try a.write(buf.writer());
                try back.parse(buf.items);
                try std.testing.expectEqualDeep(pg.*, back.node[n].plan.procgen);
                try std.testing.expectEqualDeep(a.start, back.start);
                again.clearRetainingCapacity();
                try back.write(again.writer());
                try std.testing.expectEqualStrings(buf.items, again.items);
                checked += 1;
            }
        }
    }
    try std.testing.expectEqual(2 * std.enums.values(Algo).len * std.enums.values(Kind).len, checked);
    std.debug.print("map serialization: {d} floor/feature/default-or-changed cases preserve plans, climate, pack makeup and canonical text\n", .{checked});
}

test "a map's folk and script save with it, and folk off open bespoke floor are refused" {
    const a = try atlas.testAtlas();
    defer std.testing.allocator.destroy(a);
    const room = a.add(.{ .bespoke = .{} }).?;
    const b = &a.node[room].plan.bespoke;
    var floor = grid.Box.sized(.{ .x = 3, .y = 3 }, 9, 6).cells();
    while (floor.next()) |p| b.tile[grid.Level.idx(p)] = .floor;
    _ = b.addFoe(.{ .kind = .rat, .at = .{ .x = 9, .y = 4 } });
    a.start = .{ .node = room, .at = .{ .x = 4, .y = 4 } };
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try a.write(buf.writer());
    const bare = buf.items.len;
    try buf.appendSlice(script_text.SAMPLE);
    const back = try atlas.testAtlas();
    defer std.testing.allocator.destroy(back);
    try back.parse(buf.items);
    var again = std.ArrayList(u8).init(std.testing.allocator);
    defer again.deinit();
    try back.write(again.writer());
    try std.testing.expectEqualStrings(buf.items, again.items);
    try std.testing.expectEqual(@as(u8, 2), back.script.folk_n);
    for ([_][]const u8{ "folk 0 1 1 -\n", "folk 0 9 4 -\n", "folk 0 3 3 -\nfolk 0 3 3 -\n" }) |extra| {
        buf.shrinkRetainingCapacity(bare);
        try buf.appendSlice(extra);
        try std.testing.expectError(error.BadLine, back.parse(buf.items));
    }
    std.debug.print("map script: {d} script bytes round-trip with the map; folk on a wall, a foe or each other refused\n", .{script_text.SAMPLE.len});
}

test "map text accepts exact node feature and door limits and refuses the next entry" {
    const a = try atlas.testAtlas();
    defer std.testing.allocator.destroy(a);
    const head = HEADER ++ "\nstart 0 5 5\n";
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try buf.appendSlice(head);
    for (0..atlas.MAX_NODES) |_| try buf.appendSlice("node procgen open\n");
    try a.parse(buf.items);
    try std.testing.expectEqual(atlas.MAX_NODES, a.node_n);
    try buf.appendSlice("node procgen open\n");
    try std.testing.expectError(error.TooMany, a.parse(buf.items));

    buf.clearRetainingCapacity();
    try buf.appendSlice(head ++ "node procgen open\n");
    for (0..atlas.MAX_FEATURES) |_| try buf.appendSlice("feature scatter\n");
    try a.parse(buf.items);
    try std.testing.expectEqual(atlas.MAX_FEATURES, a.node[0].plan.procgen.feature_n);
    try buf.appendSlice("feature scatter\n");
    try std.testing.expectError(error.TooMany, a.parse(buf.items));

    buf.clearRetainingCapacity();
    try buf.appendSlice(head ++ "node procgen open\n");
    for (0..grid.MAX_DOORS) |i| try buf.writer().print("door {d} 5\n", .{i});
    try a.parse(buf.items);
    try std.testing.expectEqual(grid.MAX_DOORS, a.node[0].door_n);
    try buf.writer().print("door {d} 5\n", .{grid.MAX_DOORS});
    try std.testing.expectError(error.TooMany, a.parse(buf.items));
    std.debug.print("map limits: {d} nodes, {d} features and {d} doors accepted exactly; 3 excess entries refused\n", .{ atlas.MAX_NODES, atlas.MAX_FEATURES, grid.MAX_DOORS });
}
