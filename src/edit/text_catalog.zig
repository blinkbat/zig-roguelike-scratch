const std = @import("std");
const store = @import("../core/store.zig");
const wording = @import("../core/wording.zig");
const input = @import("../core/input.zig");

pub const MAX_TEXT: usize = 4096;
const FILE_CAP = 4 << 20;
const TAG_FILE = "text-tags.json";
const LABEL_FILE = wording.FILE;
pub const Author = enum { unknown, you, ai, mixed };
pub const SaveResult = enum { saved, tags_not_saved };
pub const Entry = struct {
    path: []const u8,
    line: usize,
    text: []const u8,
    author: Author = .unknown,
    editable: bool = true,
    reason: []const u8 = "",
    file: usize,
    start: usize,
    end: usize,
    ordinal: usize,
    alias: ?[]const u8 = null,
    max_len: usize = MAX_TEXT,
};
const Source = struct { path: []const u8, bytes: [:0]const u8 };
const Tag = struct { path: []const u8, ordinal: usize, hash: u64, author: Author };
const Tags = struct { version: u32 = 1, tags: []const Tag };
const TagUpdate = struct { tags: []const Tag, bytes: []const u8, path: []const u8 };
const Token = std.zig.Token;

pub const Catalog = struct {
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    root: []const u8 = "",
    files: std.ArrayListUnmanaged(Source) = .{},
    list: std.ArrayListUnmanaged(Entry) = .{},
    tags: []const Tag = &.{},
    labels: []const u8 = "",
    tags_invalid: bool = false,
    tag_bytes: []const u8 = "",
    warning: []const u8 = "",

    pub fn init(alloc: std.mem.Allocator) Catalog {
        return .{ .alloc = alloc, .arena = std.heap.ArenaAllocator.init(alloc) };
    }

    pub fn deinit(self: *Catalog) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn entries(self: *const Catalog) []const Entry {
        return self.list.items;
    }

    pub fn load(self: *Catalog, root: []const u8) !void {
        var fresh = Catalog.init(self.alloc);
        errdefer fresh.deinit();
        try fresh.readRoot(root);
        self.deinit();
        self.* = fresh;
    }

    fn readRoot(self: *Catalog, root: []const u8) !void {
        const a = self.arena.allocator();
        self.root = try a.dupe(u8, root);
        var project = try std.fs.cwd().openDir(root, .{});
        defer project.close();
        if (project.readFileAlloc(a, TAG_FILE, FILE_CAP)) |bytes| {
            self.tag_bytes = bytes;
            if (std.json.parseFromSlice(Tags, a, bytes, .{ .allocate = .alloc_always })) |parsed| {
                if (parsed.value.version == 1) self.tags = parsed.value.tags else self.tags_invalid = true;
            } else |_| self.tags_invalid = true;
        } else |e| if (e != error.FileNotFound) return e;
        if (self.tags_invalid) self.warning = "Text tags could not be read; existing tags are preserved and text saves without attribution.";
        self.labels = project.readFileAlloc(a, LABEL_FILE, FILE_CAP) catch |e| if (e == error.FileNotFound) "" else return e;
        var source = try project.openDir("src", .{ .iterate = true });
        defer source.close();
        var walker = try source.walk(a);
        defer walker.deinit();
        var paths = std.ArrayList([]const u8).init(a);
        while (try walker.next()) |item| {
            if (item.kind != .file) continue;
            const path = try a.dupe(u8, item.path);
            std.mem.replaceScalar(u8, path, '\\', '/');
            if (included(path)) try paths.append(path);
        }
        std.mem.sort([]const u8, paths.items, {}, struct {
            fn less(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.lessThan(u8, x, y);
            }
        }.less);
        for (paths.items) |path| {
            const bytes = try source.readFileAlloc(a, path, FILE_CAP);
            try self.scan(try std.fmt.allocPrint(a, "src/{s}", .{path}), bytes);
        }
        try self.readMaps(project);
        for (self.list.items) |*entry| {
            if (entry.editable) entry.author = self.authorOf(entry.*);
        }
    }

    fn authorOf(self: *const Catalog, entry: Entry) Author {
        for (self.tags) |tag| {
            if (matches(tag, entry)) return tag.author;
        }
        return .unknown;
    }

    fn readMaps(self: *Catalog, project: std.fs.Dir) !void {
        var maps = project.openDir("maps", .{ .iterate = true }) catch |e| if (e == error.FileNotFound) return else return e;
        defer maps.close();
        const a = self.arena.allocator();
        var walker = try maps.walk(a);
        defer walker.deinit();
        var paths = std.ArrayList([]const u8).init(a);
        while (try walker.next()) |item| {
            if (item.kind != .file or !std.mem.endsWith(u8, item.path, ".map")) continue;
            const path = try a.dupe(u8, item.path);
            std.mem.replaceScalar(u8, path, '\\', '/');
            try paths.append(path);
        }
        std.mem.sort([]const u8, paths.items, {}, struct {
            fn less(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.lessThan(u8, x, y);
            }
        }.less);
        for (paths.items) |path| {
            const bytes = try maps.readFileAlloc(a, path, FILE_CAP);
            try self.scanMap(try std.fmt.allocPrint(a, "maps/{s}", .{path}), bytes);
        }
    }

    fn scanMap(self: *Catalog, path: []const u8, bytes: []const u8) !void {
        const a = self.arena.allocator();
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        var line: usize = 0;
        while (lines.next()) |raw| {
            line += 1;
            const text = std.mem.trim(u8, raw, " \r");
            if (!std.mem.startsWith(u8, text, "name ")) continue;
            const name = std.mem.trim(u8, text[5..], " ");
            if (name.len == 0) continue;
            try self.list.append(a, .{ .path = path, .line = line, .text = try a.dupe(u8, name), .editable = false, .reason = "Rename this node in the map editor", .file = 0, .start = 0, .end = 0, .ordinal = 0 });
        }
    }

    pub fn save(self: *Catalog, index: usize, replacement: []const u8, author: Author) !SaveResult {
        if (index >= self.list.items.len) return error.NoEntry;
        const entry = self.list.items[index];
        if (!entry.editable) return error.ReadOnly;
        if (replacement.len > entry.max_len) return error.TextTooLong;
        try validate(entry.text, replacement);
        const source = self.files.items[entry.file];
        const path = try std.fs.path.join(self.alloc, &.{ self.root, source.path });
        defer self.alloc.free(path);
        const current = try std.fs.cwd().readFileAlloc(self.alloc, path, FILE_CAP);
        defer self.alloc.free(current);
        if (!unchanged(source.bytes, current)) return error.SourceChanged;
        try self.checkTags();
        if (entry.alias) |key| return self.saveAlias(index, key, replacement, author);
        const encoded = try quote(self.alloc, replacement);
        defer self.alloc.free(encoded);
        const bytes = try replaceLiteral(self.alloc, current, entry.start, entry.end, encoded);
        defer self.alloc.free(bytes);
        const tags = try self.prepareTags(entry, replacement, author);
        const a = self.arena.allocator();
        const stored = try a.dupeZ(u8, bytes);
        const value = try a.dupe(u8, replacement);
        try store.replace(path, bytes);
        const result = self.saveTags(tags);
        const delta = @as(isize, @intCast(encoded.len)) - @as(isize, @intCast(entry.end - entry.start));
        self.files.items[entry.file].bytes = stored;
        for (self.list.items, 0..) |*other, i| {
            if (other.file != entry.file) continue;
            if (i == index) {
                other.text = value;
                other.end = other.start + encoded.len;
                other.author = if (result == .saved) author else .unknown;
            } else if (other.start >= entry.end) {
                other.start = @intCast(@as(isize, @intCast(other.start)) + delta);
                other.end = @intCast(@as(isize, @intCast(other.end)) + delta);
            }
        }
        return result;
    }

    fn checkTags(self: *Catalog) !void {
        const path = try std.fs.path.join(self.alloc, &.{ self.root, TAG_FILE });
        defer self.alloc.free(path);
        const current = std.fs.cwd().readFileAlloc(self.alloc, path, FILE_CAP) catch |e| if (e == error.FileNotFound) try self.alloc.dupe(u8, "") else return e;
        defer self.alloc.free(current);
        if (!unchanged(self.tag_bytes, current)) return error.TagsChanged;
    }

    fn saveAlias(self: *Catalog, index: usize, key: []const u8, replacement: []const u8, author: Author) !SaveResult {
        if (std.mem.indexOfAny(u8, replacement, "\r\n\t") != null) return error.SingleLineOnly;
        const entry = self.list.items[index];
        const changed = aliasChanged(entry.text, replacement);
        const path = try std.fs.path.join(self.alloc, &.{ self.root, LABEL_FILE });
        defer self.alloc.free(path);
        const current = std.fs.cwd().readFileAlloc(self.alloc, path, FILE_CAP) catch |e| if (e == error.FileNotFound) try self.alloc.dupe(u8, "") else return e;
        defer self.alloc.free(current);
        if (!unchanged(self.labels, current)) return error.SourceChanged;
        const output = try wording.replace(self.alloc, current, key, replacement);
        defer self.alloc.free(output);
        const tags = try self.prepareTags(entry, replacement, author);
        const a = self.arena.allocator();
        const stored = try a.dupe(u8, output);
        const value = try a.dupe(u8, replacement);
        if (changed) try store.replace(path, output);
        const result = self.saveTags(tags);
        if (changed) self.labels = stored;
        self.list.items[index].text = value;
        self.list.items[index].author = if (result == .saved) author else .unknown;
        return result;
    }

    fn prepareTags(self: *Catalog, entry: Entry, replacement: []const u8, author: Author) !TagUpdate {
        var updated = std.ArrayList(Tag).init(self.alloc);
        defer updated.deinit();
        for (self.tags) |tag| {
            if (tag.ordinal == entry.ordinal and std.mem.eql(u8, tag.path, entry.path)) continue;
            try updated.append(tag);
        }
        try updated.append(.{ .path = entry.path, .ordinal = entry.ordinal, .hash = hash(replacement), .author = author });
        const a = self.arena.allocator();
        return .{
            .tags = try a.dupe(Tag, updated.items),
            .bytes = try std.json.stringifyAlloc(a, Tags{ .tags = updated.items }, .{ .whitespace = .indent_2 }),
            .path = try std.fs.path.join(a, &.{ self.root, TAG_FILE }),
        };
    }

    fn saveTags(self: *Catalog, update: TagUpdate) SaveResult {
        if (self.tags_invalid) return .tags_not_saved;
        store.replace(update.path, update.bytes) catch return .tags_not_saved;
        self.tags = update.tags;
        self.tag_bytes = update.bytes;
        return .saved;
    }

    fn scan(self: *Catalog, path: []const u8, text: []const u8) !void {
        const a = self.arena.allocator();
        const bytes = try a.dupeZ(u8, text);
        const file = self.files.items.len;
        try self.files.append(a, .{ .path = path, .bytes = bytes });
        var tokens = std.ArrayList(Token).init(a);
        var lex = std.zig.Tokenizer.init(bytes);
        while (true) {
            const token = lex.next();
            if (token.tag == .eof) break;
            if (token.tag == .invalid) return error.InvalidSource;
            try tokens.append(token);
        }
        const ts = tokens.items;
        var excluded = try a.alloc(bool, ts.len);
        @memset(excluded, false);
        for (ts, 0..) |token, i| {
            if (token.tag == .keyword_test) {
                var end = i + 1;
                while (end < ts.len and ts[end].tag != .l_brace) : (end += 1) {}
                if (end < ts.len) end = close(ts, end, .l_brace, .r_brace);
                @memset(excluded[i..@min(end + 1, ts.len)], true);
            }
            if (token.tag == .builtin and forbiddenBuiltin(slice(bytes, token)) and i + 1 < ts.len and ts[i + 1].tag == .l_paren) {
                const end = close(ts, i + 1, .l_paren, .r_paren);
                @memset(excluded[i..@min(end + 1, ts.len)], true);
            }
            if (token.tag == .identifier and i + 1 < ts.len and ts[i + 1].tag == .l_paren and technicalCall(bytes, ts, i)) {
                const end = close(ts, i + 1, .l_paren, .r_paren);
                @memset(excluded[i..@min(end + 1, ts.len)], true);
            }
        }
        var ordinal: usize = 0;
        for (ts, 0..) |token, i| {
            if (token.tag != .string_literal) continue;
            const nth = ordinal;
            ordinal += 1;
            if (excluded[i]) continue;
            const decoded = std.zig.string_literal.parseAlloc(a, slice(bytes, token)) catch continue;
            if (!spoken(decoded, bytes, ts, i)) continue;
            const is_input = std.mem.eql(u8, path, "src/core/input.zig");
            const is_keyboard = std.mem.eql(u8, path, "src/ui/naming.zig") and std.mem.eql(u8, declaration(bytes, ts, i) orelse "", "LETTERS");
            const flavor = std.mem.eql(u8, path, "src/play/items.zig") and i >= 2 and ts[i - 1].tag == .equal and std.mem.eql(u8, slice(bytes, ts[i - 2]), "flavor");
            try self.list.append(a, .{
                .path = path,
                .line = lineOf(bytes, token.loc.start),
                .text = decoded,
                .file = file,
                .start = token.loc.start,
                .end = token.loc.end,
                .ordinal = nth,
                .editable = decoded.len <= MAX_TEXT and !is_input and !is_keyboard,
                .reason = if (is_input or is_keyboard) "Input glyph identifiers are tied to controls" else if (decoded.len > MAX_TEXT) "Text exceeds the editor limit" else "",
                .max_len = if (flavor) @import("../play/items.zig").FLAVOR_MAX else MAX_TEXT,
            });
        }
        try self.enumLabels(path, bytes, ts, excluded, file);
    }

    fn enumLabels(self: *Catalog, path: []const u8, bytes: []const u8, ts: []const Token, excluded: []const bool, file: usize) !void {
        const a = self.arena.allocator();
        for (ts, 0..) |token, i| {
            if (token.tag != .keyword_enum or excluded[i]) continue;
            var open = i + 1;
            if (open < ts.len and ts[open].tag == .l_paren) open = close(ts, open, .l_paren, .r_paren) + 1;
            if (open >= ts.len or ts[open].tag != .l_brace) continue;
            const end = close(ts, open, .l_brace, .r_brace);
            const type_name = try enumType(a, path, bytes, ts, i);
            var at = open + 1;
            var field = true;
            while (at < end) : (at += 1) {
                if (ts[at].tag == .keyword_fn or ts[at].tag == .keyword_pub or ts[at].tag == .keyword_const) break;
                if (field and ts[at].tag == .identifier) {
                    const name = slice(bytes, ts[at]);
                    if (name.len > 0 and name[0] != '@' and !std.mem.eql(u8, name, "_")) {
                        const label = try a.dupe(u8, name);
                        wording.format(label, if (type_name) |tn| wording.casing(tn) else .sentence);
                        const key = if (type_name) |tn| try wording.keyAlloc(a, tn, name) else null;
                        const allowed = if (type_name) |tn| wording.allowed(tn, name) else false;
                        try self.list.append(a, .{ .path = path, .line = lineOf(bytes, ts[at].loc.start), .text = if (key) |k| wording.lookup(self.labels, k) orelse label else label, .editable = allowed, .reason = if (allowed) "Display alias; saves to assets/player-labels.txt without renaming code" else "Generated identifier; no editable display alias", .file = file, .start = ts[at].loc.start, .end = ts[at].loc.end, .ordinal = if (key) |k| @truncate(hash(k)) else 0, .alias = if (allowed) key else null });
                    }
                    field = false;
                }
                if (ts[at].tag == .comma) field = true;
                if (ts[at].tag == .l_paren) at = close(ts, at, .l_paren, .r_paren);
                if (ts[at].tag == .l_brace) at = close(ts, at, .l_brace, .r_brace);
            }
        }
    }
};

fn included(path: []const u8) bool {
    if (!std.mem.endsWith(u8, path, ".zig")) return false;
    for ([_][]const u8{ "tests/", "shots.zig", "harness.zig", "atlas_text.zig", "text_catalog.zig", "text_panel.zig" }) |part| {
        if (std.mem.indexOf(u8, path, part) != null) return false;
    }
    if (std.mem.endsWith(u8, path, "tests.zig")) return false;
    for ([_][]const u8{ "game/", "play/", "ui/", "edit/", "map/" }) |prefix| if (std.mem.startsWith(u8, path, prefix)) return true;
    return oneOf(path, &.{ "app.zig", "game.zig", "save.zig", "core/input.zig", "gfx/look.zig" });
}

fn oneOf(value: []const u8, choices: []const []const u8) bool {
    for (choices) |choice| if (std.mem.eql(u8, value, choice)) return true;
    return false;
}

fn enumType(a: std.mem.Allocator, path: []const u8, bytes: []const u8, ts: []const Token, at: usize) !?[]const u8 {
    if (at < 3 or ts[at - 1].tag != .equal or ts[at - 2].tag != .identifier or ts[at - 3].tag != .keyword_const) return null;
    if (!std.mem.startsWith(u8, path, "src/") or !std.mem.endsWith(u8, path, ".zig")) return null;
    var name = std.ArrayList(u8).init(a);
    try name.appendSlice(path[4 .. path.len - 4]);
    std.mem.replaceScalar(u8, name.items, '/', '.');
    for (ts[0..at], 0..) |token, i| {
        if (token.tag != .keyword_struct and token.tag != .keyword_union and token.tag != .keyword_enum) continue;
        var open = i + 1;
        if (open < ts.len and ts[open].tag == .l_paren) open = close(ts, open, .l_paren, .r_paren) + 1;
        if (open >= at or ts[open].tag != .l_brace or close(ts, open, .l_brace, .r_brace) < at) continue;
        if (i < 3 or ts[i - 1].tag != .equal or ts[i - 2].tag != .identifier or ts[i - 3].tag != .keyword_const) return null;
        try name.append('.');
        try name.appendSlice(slice(bytes, ts[i - 2]));
    }
    try name.append('.');
    try name.appendSlice(slice(bytes, ts[at - 2]));
    return try name.toOwnedSlice();
}

fn declaration(bytes: []const u8, ts: []const Token, before: usize) ?[]const u8 {
    var i = before;
    while (i > 0) {
        i -= 1;
        if (ts[i].tag == .keyword_fn or ts[i].tag == .semicolon) return null;
        if (ts[i].tag == .keyword_const or ts[i].tag == .keyword_var) {
            if (i > 0 and (ts[i - 1].tag == .r_bracket or ts[i - 1].tag == .asterisk)) continue;
            if (i + 2 < ts.len and ts[i + 1].tag == .identifier and (ts[i + 2].tag == .equal or ts[i + 2].tag == .colon)) return slice(bytes, ts[i + 1]);
        }
    }
    return null;
}

fn slice(bytes: []const u8, token: Token) []const u8 {
    return bytes[token.loc.start..token.loc.end];
}

fn close(ts: []const Token, at: usize, left: Token.Tag, right: Token.Tag) usize {
    var depth: usize = 0;
    for (ts[at..], at..) |token, i| {
        if (token.tag == left) depth += 1;
        if (token.tag == right) {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return ts.len - 1;
}

fn forbiddenBuiltin(name: []const u8) bool {
    return oneOf(name, &.{ "@import", "@embedFile", "@field", "@hasField", "@hasDecl", "@compileError", "@compileLog", "@panic", "@export", "@extern" });
}

fn technicalCall(bytes: []const u8, ts: []const Token, i: usize) bool {
    const name = slice(bytes, ts[i]);
    if (oneOf(name, &.{ "eql", "startsWith", "endsWith", "indexOf", "indexOfScalar", "lastIndexOfScalar", "hash", "stringToEnum", "expectEqualStrings", "expectError", "getUniformLocation", "loadShaderFromMemory", "capture", "snap", "shootPage", "has", "declares", "declOr" })) return true;
    if (std.mem.eql(u8, name, "print") and i >= 2 and std.mem.eql(u8, slice(bytes, ts[i - 2]), "debug")) return true;
    return false;
}

fn spoken(text: []const u8, bytes: []const u8, ts: []const Token, i: usize) bool {
    if (text.len == 0) return false;
    if (text[0] == '_' and std.mem.indexOfScalar(u8, text, ' ') == null) return false;
    var letters: usize = 0;
    for (text) |c| {
        if (std.ascii.isAlphabetic(c)) letters += 1;
        if (!supported(c)) return false;
    }
    if (letters == 0) return false;
    const decl = declaration(bytes, ts, i) orelse "";
    if (oneOf(decl, &.{ "PROBED", "SYMBOLS", "TTF", "DATA_TTF" }) or std.mem.endsWith(u8, decl, "_FIELDS")) return false;
    if (oneOf(decl, &.{ "VERB", "DONE", "TAKES", "RETAKES", "NAME", "NUMBERS", "SWEEP_VERB" })) return true;
    for ([_][]const u8{ ".zig", ".png", ".ttf", ".map", ".json", "#version", "void main", "uniform ", "layout(", "roguelike-map", "shots/", "assets/", "maps/", "saves/" }) |part| {
        if (std.mem.indexOf(u8, text, part) != null) return false;
    }
    const from = i -| 12;
    var context = false;
    for (ts[from..i]) |token| {
        if (token.tag != .identifier) continue;
        const name = slice(bytes, token);
        if (oneOf(name, &.{ "name", "label", "title", "description", "desc", "tip", "note", "caption", "say", "push", "draw", "drawMid", "drawFit", "button", "buttonOn", "put", "text", "textLine", "line", "bufPrint", "bufPrintZ", "comptimePrint", "verb", "slain", "flavor" })) context = true;
    }
    if (context) return true;
    if (std.mem.indexOfScalar(u8, text, ' ') != null and letters >= 3) return true;
    if (std.ascii.isUpper(text[0])) return true;
    if (i > 0 and ts[i - 1].tag == .keyword_return) return true;
    return false;
}

fn lineOf(bytes: []const u8, at: usize) usize {
    return 1 + std.mem.count(u8, bytes[0..at], "\n");
}

fn hash(text: []const u8) u64 {
    return std.hash.Wyhash.hash(0, text);
}

fn matches(tag: Tag, entry: Entry) bool {
    return tag.ordinal == entry.ordinal and tag.hash == hash(entry.text) and std.mem.eql(u8, tag.path, entry.path);
}

fn unchanged(before: []const u8, current: []const u8) bool {
    return std.mem.eql(u8, before, current);
}

fn aliasChanged(before: []const u8, replacement: []const u8) bool {
    return !std.mem.eql(u8, before, replacement);
}

fn quote(alloc: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    try out.append('"');
    for (text) |c| switch (c) {
        '"', '\\' => {
            try out.append('\\');
            try out.append(c);
        },
        '\n' => try out.appendSlice("\\n"),
        '\r' => try out.appendSlice("\\r"),
        '\t' => try out.appendSlice("\\t"),
        input.GLYPH_OPEN, input.GLYPH_CLOSE => try out.writer().print("\\x{x:0>2}", .{c}),
        else => try out.append(c),
    };
    try out.append('"');
    return out.toOwnedSlice();
}

fn replaceLiteral(alloc: std.mem.Allocator, source: []const u8, start: usize, end: usize, encoded: []const u8) ![]u8 {
    return std.mem.concat(alloc, u8, &.{ source[0..start], encoded, source[end..] });
}

fn protected(text: []const u8, from: usize) ?struct { start: usize, end: usize } {
    var i = from;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '{') {
            if (i + 1 < text.len and text[i + 1] == '{') return .{ .start = i, .end = i + 2 };
            const end = std.mem.indexOfScalarPos(u8, text, i + 1, '}') orelse return .{ .start = i, .end = text.len };
            return .{ .start = i, .end = end + 1 };
        }
        if (c == '}') return .{ .start = i, .end = i + if (i + 1 < text.len and text[i + 1] == '}') @as(usize, 2) else 1 };
        if (c == input.GLYPH_OPEN) {
            const end = std.mem.indexOfScalarPos(u8, text, i + 1, input.GLYPH_CLOSE) orelse return .{ .start = i, .end = text.len };
            return .{ .start = i, .end = end + 1 };
        }
        if (c == input.GLYPH_CLOSE) return .{ .start = i, .end = i + 1 };
    }
    return null;
}

pub fn supported(c: u8) bool {
    return (c >= 32 and c < 127) or c == '\n' or c == '\r' or c == '\t' or c == input.GLYPH_OPEN or c == input.GLYPH_CLOSE;
}

pub fn validate(before: []const u8, after: []const u8) !void {
    if (after.len > MAX_TEXT) return error.TextTooLong;
    if (std.mem.trim(u8, after, " \r\n\t").len == 0) return error.EmptyText;
    for (after) |c| {
        if (!supported(c)) return error.UnsupportedCharacter;
    }
    var x: usize = 0;
    var y: usize = 0;
    while (true) {
        const a = protected(before, x);
        const b = protected(after, y);
        if (a == null and b == null) return;
        if (a == null or b == null) return error.ProtectedTokensChanged;
        if (!std.mem.eql(u8, before[a.?.start..a.?.end], after[b.?.start..b.?.end])) return error.ProtectedTokensChanged;
        x = a.?.end;
        y = b.?.end;
    }
}

test "text catalog excludes tests technical calls and imports while retaining prose labels and generated names" {
    var c = Catalog.init(std.testing.allocator);
    defer c.deinit();
    try c.scan("src/play/example.zig", "const x = @import(\"Other.zig\");\nconst DESCRIPTION = \"Deals {d} damage\";\nconst Kind = enum { short_bow, staff };\nfn label() []const u8 { return \"Inventory\"; }\nfn compare() void { _ = std.mem.eql(u8, x, \"Internal Name\"); std.debug.print(\"Console only\", .{}); }\ntest \"Not a label\" { const y = \"Test prose\"; }\n");
    try std.testing.expectEqual(@as(usize, 4), c.entries().len);
    try std.testing.expectEqualStrings("Deals {d} damage", c.entries()[0].text);
    try std.testing.expectEqual(@as(usize, 2), c.entries()[0].line);
    try std.testing.expectEqualStrings("Inventory", c.entries()[1].text);
    try std.testing.expect(!c.entries()[2].editable);
    try std.testing.expectEqualStrings("Short bow", c.entries()[2].text);
    std.debug.print("text catalog: 2 editable strings, 2 generated labels, imports/test bodies/technical calls excluded\n", .{});
}

test "text edits preserve escapes format arguments control glyphs and source bytes" {
    const a = std.testing.allocator;
    const value = "Take \"bow\"\\stash\n{s} \x1eEnter\x1f";
    const encoded = try quote(a, value);
    defer a.free(encoded);
    const decoded = try std.zig.string_literal.parseAlloc(a, encoded);
    defer a.free(decoded);
    try std.testing.expectEqualStrings(value, decoded);
    try validate("Take {s} with \x1eEnter\x1f", "Pick up {s}: \x1eEnter\x1f");
    try std.testing.expectError(error.ProtectedTokensChanged, validate("Take {s}", "Take {d}"));
    try std.testing.expectError(error.ProtectedTokensChanged, validate("Take {s}", "Take {s} {d}"));
    try std.testing.expectError(error.ProtectedTokensChanged, validate("\x1eEnter\x1f", "Enter"));
    try std.testing.expectError(error.UnsupportedCharacter, validate("Bow", "B\xc3\xb6w"));
    try std.testing.expectError(error.UnsupportedCharacter, validate("Bow", "Bow\x7f"));
    for (32..127) |byte| try std.testing.expect(supported(@intCast(byte)));
    try std.testing.expect(supported(input.GLYPH_OPEN) and supported(input.GLYPH_CLOSE));
    const source = "\xef\xbb\xbfconst name = \"Bow\";\r\n";
    const start = std.mem.indexOf(u8, source, "\"Bow\"").?;
    const changed = try replaceLiteral(a, source, start, start + 5, "\"Longbow\"");
    defer a.free(changed);
    try std.testing.expectEqualStrings("\xef\xbb\xbfconst name = \"Longbow\";\r\n", changed);
    try std.testing.expect(!unchanged(source, changed));
    try std.testing.expect(unchanged(source, source));
    std.debug.print("text edits: escaped literal round trip, 4 invalid changes refused, BOM/CRLF preserved and full-file conflict detected\n", .{});
}

test "text attribution requires matching source literal position and content" {
    const e = Entry{ .path = "src/app.zig", .line = 10, .text = "Start", .file = 0, .start = 0, .end = 7, .ordinal = 3 };
    var tag = Tag{ .path = e.path, .ordinal = e.ordinal, .hash = hash(e.text), .author = .you };
    try std.testing.expect(matches(tag, e));
    tag.ordinal += 1;
    try std.testing.expect(!matches(tag, e));
    tag.ordinal = e.ordinal;
    tag.hash = hash("Quit");
    try std.testing.expect(!matches(tag, e));
    tag.hash = hash(e.text);
    tag.path = "src/ui/book.zig";
    try std.testing.expect(!matches(tag, e));
    std.debug.print("text tags: exact attribution restored; changed position, content and source remain unknown\n", .{});
}

test "text tag preparation shares source and alias upserts without mutating loaded attribution" {
    var c = Catalog.init(std.testing.allocator);
    defer c.deinit();
    const entry = Entry{ .path = "src/app.zig", .line = 10, .text = "Start", .file = 0, .start = 0, .end = 7, .ordinal = 3 };
    const existing = [_]Tag{
        .{ .path = entry.path, .ordinal = entry.ordinal, .hash = hash(entry.text), .author = .ai },
        .{ .path = entry.path, .ordinal = 4, .hash = hash("Quit"), .author = .you },
    };
    c.tags = &existing;
    c.tag_bytes = "unchanged snapshot";
    const update = try c.prepareTags(entry, "Begin", .mixed);
    try std.testing.expectEqual(@as(usize, 2), update.tags.len);
    try std.testing.expectEqual(@as(usize, 4), update.tags[0].ordinal);
    try std.testing.expectEqual(hash("Begin"), update.tags[1].hash);
    try std.testing.expectEqual(Author.mixed, update.tags[1].author);
    const parsed = try std.json.parseFromSlice(Tags, std.testing.allocator, update.bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqualDeep(update.tags, parsed.value.tags);
    try std.testing.expectEqual(Author.ai, c.tags[0].author);
    c.tags_invalid = true;
    try std.testing.expectEqual(SaveResult.tags_not_saved, c.saveTags(update));
    try std.testing.expectEqualStrings("unchanged snapshot", c.tag_bytes);
    try std.testing.expectEqual(Author.ai, c.tags[0].author);
    std.debug.print("text tags: shared upsert prepared independently; malformed file blocks tag commit and preserves loaded attribution\n", .{});
}

test "text catalog protects reflection controls and item flavor length while finding short verbs" {
    var c = Catalog.init(std.testing.allocator);
    defer c.deinit();
    try c.scan("src/play/items.zig", "const SPECS = .{ .flavor = \"Old words.\" };\n");
    try std.testing.expectEqual(@as(usize, @import("../play/items.zig").FLAVOR_MAX), c.entries()[0].max_len);
    try std.testing.expectError(error.TextTooLong, c.save(0, "x" ** (@import("../play/items.zig").FLAVOR_MAX + 1), .you));
    try c.scan("src/ui/naming.zig", "const LETTERS = [_][]const u8{ \"ABCDEFGHIJKLM\", \"NOPQRSTUVWXYZ\" };\n");
    try std.testing.expect(!c.entries()[1].editable and !c.entries()[2].editable);
    const n = c.entries().len;
    try c.scan("src/play/example.zig", "const VERB = \"shoots\";\nconst s = .{ .verb = \"bites\" };\nconst name = @tagName(k) ++ \"_bonus\";\nconst PROBED = .{ \"BASE\", \"KIND\" };\n");
    try std.testing.expectEqual(n + 2, c.entries().len);
    try std.testing.expect(!aliasChanged("Burning Arrow", "Burning Arrow"));
    try std.testing.expect(aliasChanged("Burning Arrow", "Flaming Arrow"));
    try c.scanMap("maps/start.map", "roguelike-map 1\nnode procgen wilds\nname The Strand\n");
    const entry = c.entries()[c.entries().len - 1];
    try std.testing.expect(!entry.editable);
    try std.testing.expectEqualStrings("The Strand", entry.text);
    try std.testing.expectEqual(@as(usize, 3), entry.line);
    std.debug.print("text catalog: bounded item flavor, 2 protected keyboard rows, 2 short verbs, reflection exclusions, tag-only aliases and map-name provenance checked\n", .{});
}
