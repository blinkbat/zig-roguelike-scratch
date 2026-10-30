const std = @import("std");
const store = @import("../core/store.zig");
const wording = @import("../core/wording.zig");
const input = @import("../core/input.zig");
const atlas = @import("../map/atlas.zig");
const atlas_text = @import("../map/atlas_text.zig");

pub const MAX_TEXT: usize = 4096;
const FILE_CAP = atlas_text.TEXT_CAP;
const TAG_FILE = "text-tags.json";
const LABEL_FILE = wording.FILE;
const SRC = "src/";
const ZIG = ".zig";
pub const Author = enum { unknown, you, ai, mixed };
pub const SaveResult = enum { saved, tags_not_saved };
pub const Entry = struct {
    path: []const u8,
    line: usize,
    text: []const u8,
    category: []const u8 = "",
    owner: []const u8 = "",
    role: []const u8 = "",
    context: []const u8 = "",
    author: Author = .unknown,
    editable: bool = true,
    reason: []const u8 = "",
    file: usize,
    start: usize,
    end: usize,
    ordinal: usize,
    alias: ?[]const u8 = null,
    text_owned: bool = false,

    fn replaceText(self: *Entry, alloc: std.mem.Allocator, text: []const u8) void {
        if (self.text_owned) alloc.free(self.text);
        self.text = text;
        self.text_owned = true;
    }
};
const Source = struct {
    path: []const u8,
    bytes: [:0]const u8,
    bytes_owned: bool = false,

    fn replaceBytes(self: *Source, alloc: std.mem.Allocator, bytes: [:0]const u8) void {
        if (self.bytes_owned) alloc.free(self.bytes);
        self.bytes = bytes;
        self.bytes_owned = true;
    }
};
const Tag = struct { path: []const u8, ordinal: usize, hash: u64, author: Author };
const Tags = struct { version: u32 = 1, tags: []const Tag };
const TagUpdate = struct {
    tags: []const Tag,
    bytes: []const u8,
    path: []const u8,

    fn deinit(self: *TagUpdate, alloc: std.mem.Allocator) void {
        alloc.free(self.tags);
        alloc.free(self.bytes);
        alloc.free(self.path);
    }
};
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
    tags_owned: bool = false,
    labels_owned: bool = false,
    warning: []const u8 = "",
    skills: ?[]const SkillSource = null,

    pub fn init(alloc: std.mem.Allocator) Catalog {
        return .{ .alloc = alloc, .arena = std.heap.ArenaAllocator.init(alloc) };
    }

    pub fn deinit(self: *Catalog) void {
        for (self.files.items) |source| if (source.bytes_owned) self.alloc.free(source.bytes);
        for (self.list.items) |entry| if (entry.text_owned) self.alloc.free(entry.text);
        if (self.tags_owned) {
            self.alloc.free(self.tags);
            self.alloc.free(self.tag_bytes);
        }
        if (self.labels_owned) self.alloc.free(self.labels);
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
        for (try sortedFiles(a, source, included)) |path| {
            const bytes = try source.readFileAlloc(a, path, FILE_CAP);
            try self.scan(try std.fmt.allocPrint(a, SRC ++ "{s}", .{path}), bytes);
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
        var maps = project.openDir(atlas.DIR, .{ .iterate = true }) catch |e| if (e == error.FileNotFound) return else return e;
        defer maps.close();
        const a = self.arena.allocator();
        for (try sortedFiles(a, maps, isMap)) |path| {
            const bytes = try maps.readFileAlloc(a, path, FILE_CAP);
            try self.scanMap(try std.fmt.allocPrint(a, atlas.PREFIX ++ "{s}", .{path}), bytes);
        }
    }

    fn scanMap(self: *Catalog, path: []const u8, bytes: []const u8) !void {
        const a = self.arena.allocator();
        var names = atlas_text.NodeNames.of(bytes);
        while (names.next()) |n| {
            try self.list.append(a, .{ .path = path, .line = n.line, .text = try a.dupe(u8, n.name), .category = "Maps", .owner = try std.fmt.allocPrint(a, "{s} (node {d})", .{ n.name, n.node }), .role = "Name", .context = try std.fmt.allocPrint(a, "{s}.node[{d}].name", .{ path, n.node }), .editable = false, .reason = "Rename this node in the map editor", .file = 0, .start = 0, .end = 0, .ordinal = 0 });
        }
    }

    pub fn save(self: *Catalog, index: usize, replacement: []const u8, author: Author) !SaveResult {
        if (index >= self.list.items.len) return error.NoEntry;
        const entry = self.list.items[index];
        if (!entry.editable) return error.ReadOnly;
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
        var tags = try self.prepareTags(entry, replacement, author);
        defer tags.deinit(self.alloc);
        const stored = try self.alloc.dupeZ(u8, bytes);
        errdefer self.alloc.free(stored);
        const value = try self.alloc.dupe(u8, replacement);
        errdefer self.alloc.free(value);
        try store.replace(path, bytes);
        const result = self.saveTags(&tags);
        const delta = @as(isize, @intCast(encoded.len)) - @as(isize, @intCast(entry.end - entry.start));
        self.files.items[entry.file].replaceBytes(self.alloc, stored);
        for (self.list.items, 0..) |*other, i| {
            if (other.file != entry.file) continue;
            if (i == index) {
                other.replaceText(self.alloc, value);
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
        const current = try self.readOrEmpty(path);
        defer self.alloc.free(current);
        if (!unchanged(self.tag_bytes, current)) return error.TagsChanged;
    }

    fn readOrEmpty(self: *Catalog, path: []const u8) ![]u8 {
        return std.fs.cwd().readFileAlloc(self.alloc, path, FILE_CAP) catch |e| if (e == error.FileNotFound) try self.alloc.dupe(u8, "") else return e;
    }

    fn saveAlias(self: *Catalog, index: usize, key: []const u8, replacement: []const u8, author: Author) !SaveResult {
        if (!oneLine(replacement)) return error.SingleLineOnly;
        const entry = self.list.items[index];
        const changed = aliasChanged(entry.text, replacement);
        const path = try std.fs.path.join(self.alloc, &.{ self.root, LABEL_FILE });
        defer self.alloc.free(path);
        const current = try self.readOrEmpty(path);
        defer self.alloc.free(current);
        if (!unchanged(self.labels, current)) return error.SourceChanged;
        const output = try wording.replace(self.alloc, current, key, replacement);
        defer self.alloc.free(output);
        var tags = try self.prepareTags(entry, replacement, author);
        defer tags.deinit(self.alloc);
        const stored = if (changed) try self.alloc.dupe(u8, output) else self.labels;
        errdefer if (changed) self.alloc.free(stored);
        const value = try self.alloc.dupe(u8, replacement);
        errdefer self.alloc.free(value);
        if (changed) try store.replace(path, output);
        const result = self.saveTags(&tags);
        if (changed) {
            self.replaceLabels(stored);
        }
        self.list.items[index].replaceText(self.alloc, value);
        self.list.items[index].author = if (result == .saved) author else .unknown;
        return result;
    }

    fn replaceLabels(self: *Catalog, labels: []const u8) void {
        if (self.labels_owned) self.alloc.free(self.labels);
        self.labels = labels;
        self.labels_owned = true;
    }

    fn prepareTags(self: *Catalog, entry: Entry, replacement: []const u8, author: Author) !TagUpdate {
        var updated = std.ArrayList(Tag).init(self.alloc);
        defer updated.deinit();
        for (self.tags) |tag| {
            if (tag.ordinal == entry.ordinal and std.mem.eql(u8, tag.path, entry.path)) continue;
            try updated.append(tag);
        }
        try updated.append(.{ .path = entry.path, .ordinal = entry.ordinal, .hash = hash(replacement), .author = author });
        const tags = try updated.toOwnedSlice();
        errdefer self.alloc.free(tags);
        const bytes = try std.json.stringifyAlloc(self.alloc, Tags{ .tags = tags }, .{ .whitespace = .indent_2 });
        errdefer self.alloc.free(bytes);
        return .{
            .tags = tags,
            .bytes = bytes,
            .path = try std.fs.path.join(self.alloc, &.{ self.root, TAG_FILE }),
        };
    }

    fn saveTags(self: *Catalog, update: *TagUpdate) SaveResult {
        if (self.tags_invalid) return .tags_not_saved;
        store.replace(update.path, update.bytes) catch return .tags_not_saved;
        self.acceptTags(update);
        return .saved;
    }

    fn acceptTags(self: *Catalog, update: *TagUpdate) void {
        if (self.tags_owned) {
            self.alloc.free(self.tags);
            self.alloc.free(self.tag_bytes);
        }
        self.tags = update.tags;
        self.tag_bytes = update.bytes;
        self.tags_owned = true;
        update.tags = &.{};
        update.bytes = "";
    }

    fn scan(self: *Catalog, path: []const u8, text: []const u8) !void {
        const a = self.arena.allocator();
        const bytes = try a.dupeZ(u8, text);
        const file = self.files.items.len;
        try self.files.append(a, .{ .path = path, .bytes = bytes });
        const ts = try tokenize(a, bytes);
        for (ts) |token| if (token.tag == .invalid) return error.InvalidSource;
        if (self.skills == null) self.skills = try skillSources(a, @embedFile("../play/skillbar.zig"));
        var contexts = try ContextScan.init(a, path, bytes, ts, self.skills.?);
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
            try contexts.step(i);
            if (token.tag != .string_literal) continue;
            const nth = ordinal;
            ordinal += 1;
            if (excluded[i]) continue;
            const decoded = std.zig.string_literal.parseAlloc(a, slice(bytes, token)) catch continue;
            if (!spoken(decoded, bytes, ts, i)) continue;
            const is_input = inputSource(path);
            const is_keyboard = std.mem.eql(u8, path, "src/ui/naming.zig") and std.mem.eql(u8, declaration(bytes, ts, i) orelse "", "LETTERS");
            const semantic = try contexts.describe();
            try self.list.append(a, .{
                .path = path,
                .line = lineOf(bytes, token.loc.start),
                .text = decoded,
                .category = semantic.category,
                .owner = semantic.owner,
                .role = semantic.role,
                .context = semantic.context,
                .file = file,
                .start = token.loc.start,
                .end = token.loc.end,
                .ordinal = nth,
                .editable = decoded.len <= MAX_TEXT and !is_input and !is_keyboard,
                .reason = if (is_input or is_keyboard) "Input glyph identifiers are tied to controls" else if (decoded.len > MAX_TEXT) "Text exceeds the editor limit" else "",
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
                        const identity = key orelse try std.fmt.allocPrint(a, "{s}.{s}", .{ path, name });
                        try self.list.append(a, .{ .path = path, .line = lineOf(bytes, ts[at].loc.start), .text = if (key) |k| try a.dupe(u8, wording.lookup(self.labels, k) orelse label) else label, .category = try categoryOf(a, path), .owner = try humanize(a, name), .role = "Display name", .context = identity, .editable = allowed, .reason = if (allowed) "Display alias; saves to " ++ LABEL_FILE ++ " without renaming code" else "Generated identifier; no editable display alias", .file = file, .start = ts[at].loc.start, .end = ts[at].loc.end, .ordinal = if (key) |k| @truncate(hash(k)) else 0, .alias = if (allowed) key else null });
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
    if (!std.mem.endsWith(u8, path, ZIG)) return false;
    for ([_][]const u8{ "tests/", "shots.zig", "harness.zig", "atlas_text.zig", "script_text.zig", "text_catalog.zig", "text_panel.zig" }) |part| {
        if (std.mem.indexOf(u8, path, part) != null) return false;
    }
    if (std.mem.endsWith(u8, path, "tests.zig")) return false;
    for ([_][]const u8{ "game/", "play/", "ui/", "edit/", "map/" }) |prefix| if (std.mem.startsWith(u8, path, prefix)) return true;
    return oneOf(path, &INPUT_SOURCES) or oneOf(path, &.{ "app.zig", "game.zig", "save.zig", "save_data.zig", "gfx/look.zig", "gfx/fx.zig" });
}

const INPUT_SOURCES = [_][]const u8{ "core/input.zig", "core/input_bindings.zig", "core/input_names.zig" };

fn inputSource(path: []const u8) bool {
    return std.mem.startsWith(u8, path, SRC) and oneOf(path[SRC.len..], &INPUT_SOURCES);
}

fn isMap(path: []const u8) bool {
    return std.mem.endsWith(u8, path, atlas.EXT);
}

/// Every file under `dir` that `keep` takes, '/' between its folders, in order.
fn sortedFiles(a: std.mem.Allocator, dir: std.fs.Dir, comptime keep: fn ([]const u8) bool) ![]const []const u8 {
    var walker = try dir.walk(a);
    defer walker.deinit();
    var paths = std.ArrayList([]const u8).init(a);
    while (try walker.next()) |item| {
        if (item.kind != .file) continue;
        const path = try a.dupe(u8, item.path);
        std.mem.replaceScalar(u8, path, '\\', '/');
        if (keep(path)) try paths.append(path);
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn less(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.lessThan(u8, x, y);
        }
    }.less);
    return paths.items;
}

fn oneOf(value: []const u8, choices: []const []const u8) bool {
    for (choices) |choice| if (std.mem.eql(u8, value, choice)) return true;
    return false;
}

const SkillSource = struct { scope: []const u8, name: []const u8 };

fn tokenize(a: std.mem.Allocator, bytes: [:0]const u8) ![]const Token {
    var tokens = std.ArrayList(Token).init(a);
    var lex = std.zig.Tokenizer.init(bytes);
    while (true) {
        const token = lex.next();
        if (token.tag == .eof) break;
        try tokens.append(token);
    }
    return tokens.items;
}

fn skillSources(a: std.mem.Allocator, bytes: [:0]const u8) ![]const SkillSource {
    const ts = try tokenize(a, bytes);
    var imports = std.StringHashMap([]const u8).init(a);
    for (ts, 0..) |t, i| {
        if (t.tag != .keyword_const or i + 6 >= ts.len) continue;
        if (ts[i + 2].tag != .equal or !std.mem.eql(u8, slice(bytes, ts[i + 3]), "@import") or ts[i + 5].tag != .string_literal) continue;
        const path = try std.zig.string_literal.parseAlloc(a, slice(bytes, ts[i + 5]));
        if (std.mem.indexOfScalar(u8, path, '/') != null or !std.mem.endsWith(u8, path, ".zig")) continue;
        try imports.put(slice(bytes, ts[i + 1]), try std.fmt.allocPrint(a, "play.{s}", .{path[0 .. path.len - 4]}));
    }
    var result = std.ArrayList(SkillSource).init(a);
    var braces = std.ArrayList(usize).init(a);
    for (ts, 0..) |t, i| {
        if (t.tag == .l_brace) {
            try braces.append(i);
            continue;
        }
        if (t.tag == .r_brace) {
            _ = braces.pop();
            continue;
        }
        if (t.tag != .identifier or !std.mem.eql(u8, slice(bytes, t), "module") or i == 0 or i + 2 >= ts.len or braces.items.len == 0) continue;
        if (ts[i - 1].tag != .period or ts[i + 1].tag != .equal) continue;
        const module = imports.get(slice(bytes, ts[i + 2])) orelse continue;
        const open = braces.items[braces.items.len - 1];
        if (open < 4 or ts[open - 1].tag != .period or ts[open - 2].tag != .equal or ts[open - 3].tag != .identifier or ts[open - 4].tag != .period) continue;
        const name = slice(bytes, ts[open - 3]);
        const scope = if (i + 4 < ts.len and ts[i + 3].tag == .period and ts[i + 4].tag == .identifier)
            try std.fmt.allocPrint(a, "{s}.{s}", .{ module, slice(bytes, ts[i + 4]) })
        else
            module;
        try result.append(.{ .scope = scope, .name = try humanize(a, name) });
    }
    return result.toOwnedSlice();
}

fn humanize(a: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(a);
    for (value, 0..) |c, i| {
        if (c == '_') {
            try out.append(' ');
        } else {
            if (i > 0 and std.ascii.isUpper(c) and std.ascii.isLower(value[i - 1])) try out.append(' ');
            try out.append(if (i == 0) std.ascii.toUpper(c) else std.ascii.toLower(c));
        }
    }
    return out.toOwnedSlice();
}

fn moduleOf(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    const start: usize = if (std.mem.startsWith(u8, path, SRC)) SRC.len else 0;
    const end = if (std.mem.endsWith(u8, path, ZIG)) path.len - ZIG.len else path.len;
    const module = try a.dupe(u8, path[start..end]);
    std.mem.replaceScalar(u8, module, '/', '.');
    return module;
}

fn categoryOf(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (inputSource(path)) return "Input";
    if (std.mem.eql(u8, path, "src/save_data.zig")) return "Save";
    if (std.mem.startsWith(u8, path, "src/edit/")) return "Editor";
    if (std.mem.startsWith(u8, path, "src/map/")) return "Maps";
    if (std.mem.startsWith(u8, path, "src/ui/")) return "Interface";
    if (std.mem.eql(u8, path, "src/play/items.zig")) return "Items";
    if (std.mem.eql(u8, path, "src/play/skillbar.zig")) return "Skills";
    if (std.mem.eql(u8, path, "src/gfx/fx.zig")) return "Effects";
    const base = std.fs.path.basename(path);
    return humanize(a, if (std.mem.endsWith(u8, base, ZIG)) base[0 .. base.len - ZIG.len] else base);
}

fn textRole(name: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(name, "description") or std.ascii.eqlIgnoreCase(name, "desc")) return "Description";
    if (std.ascii.eqlIgnoreCase(name, "name")) return "Name";
    if (std.ascii.eqlIgnoreCase(name, "title")) return "Title";
    if (std.ascii.eqlIgnoreCase(name, "label") or std.ascii.eqlIgnoreCase(name, "caption")) return "Label";
    if (std.ascii.eqlIgnoreCase(name, "tip")) return "Tooltip";
    if (std.ascii.eqlIgnoreCase(name, "status")) return "Status";
    if (oneOf(name, &ACTION_WORDS)) return "Action wording";
    if (std.mem.eql(u8, name, FRIGHT_WORDS)) return "Fright speech";
    return null;
}

const ACTION_WORDS = [_][]const u8{ "VERB", "DONE", "TAKES", "RETAKES", "SWEEP_VERB" };
const FRIGHT_WORDS = "FRIGHT_WORDS";

const Semantic = struct { category: []const u8, owner: []const u8, role: []const u8, context: []const u8 };
const Scope = struct {
    name: []const u8,
    end: usize,
    kind: enum { declaration, function, member, call },
    display: ?[]const u8 = null,
};

const ContextScan = struct {
    a: std.mem.Allocator,
    bytes: []const u8,
    ts: []const Token,
    pairs: []usize,
    scopes: std.ArrayList(Scope),
    module: []const u8,
    category: []const u8,
    skills: []const SkillSource,

    fn init(a: std.mem.Allocator, path: []const u8, bytes: []const u8, ts: []const Token, skills: []const SkillSource) !ContextScan {
        const pairs = try a.alloc(usize, ts.len);
        for (pairs, 0..) |*p, i| p.* = i;
        var stack = std.ArrayList(usize).init(a);
        for (ts, 0..) |t, i| switch (t.tag) {
            .l_paren, .l_brace, .l_bracket => try stack.append(i),
            .r_paren, .r_brace, .r_bracket => if (stack.pop()) |open| {
                pairs[open] = i;
                pairs[i] = open;
            },
            else => {},
        };
        return .{ .a = a, .bytes = bytes, .ts = ts, .pairs = pairs, .scopes = std.ArrayList(Scope).init(a), .module = try moduleOf(a, path), .category = try categoryOf(a, path), .skills = skills };
    }

    fn expressionEnd(s: *const ContextScan, from: usize) usize {
        var i = from;
        while (i < s.ts.len) : (i += 1) {
            switch (s.ts[i].tag) {
                .comma, .semicolon, .r_brace, .r_paren, .r_bracket => return i -| 1,
                .l_brace, .l_paren, .l_bracket => i = s.pairs[i],
                else => {},
            }
        }
        return s.ts.len -| 1;
    }

    fn rowName(s: *const ContextScan, from: usize, end: usize) !?[]const u8 {
        var open = from;
        while (open <= end and open < s.ts.len and s.ts[open].tag != .l_brace) : (open += 1) {
            if (s.ts[open].tag == .l_paren) return null;
        }
        if (open > end or open >= s.ts.len) return null;
        var i = open + 1;
        while (i + 3 < s.pairs[open]) : (i += 1) {
            if (s.ts[i].tag == .period and std.mem.eql(u8, slice(s.bytes, s.ts[i + 1]), "name") and s.ts[i + 2].tag == .equal and s.ts[i + 3].tag == .string_literal) {
                const name = std.zig.string_literal.parseAlloc(s.a, slice(s.bytes, s.ts[i + 3])) catch return null;
                return if (name.len > 0) name else null;
            }
            if (oneOfToken(s.ts[i].tag, &.{ .l_brace, .l_paren, .l_bracket })) i = s.pairs[i];
        }
        return null;
    }

    fn step(s: *ContextScan, i: usize) !void {
        while (s.scopes.items.len > 0 and s.scopes.items[s.scopes.items.len - 1].end < i) _ = s.scopes.pop();
        const ts = s.ts;
        if (oneOfToken(ts[i].tag, &.{ .keyword_const, .keyword_var }) and (i == 0 or !oneOfToken(ts[i - 1].tag, &.{ .r_bracket, .asterisk })) and i + 2 < ts.len and ts[i + 1].tag == .identifier and oneOfToken(ts[i + 2].tag, &.{ .equal, .colon })) {
            try s.scopes.append(.{ .name = slice(s.bytes, ts[i + 1]), .end = s.expressionEnd(i + 2), .kind = .declaration });
        } else if (ts[i].tag == .keyword_fn and i + 2 < ts.len and ts[i + 1].tag == .identifier and ts[i + 2].tag == .l_paren) {
            var body = s.pairs[i + 2] + 1;
            while (body < ts.len and !oneOfToken(ts[body].tag, &.{ .l_brace, .semicolon })) : (body += 1) {
                if (oneOfToken(ts[body].tag, &.{ .l_paren, .l_bracket })) body = s.pairs[body];
            }
            try s.scopes.append(.{ .name = slice(s.bytes, ts[i + 1]), .end = if (body < ts.len) s.pairs[body] else ts.len -| 1, .kind = .function });
        } else if (ts[i].tag == .period and (i == 0 or !oneOfToken(ts[i - 1].tag, &.{ .identifier, .r_paren, .r_bracket })) and i + 2 < ts.len and ts[i + 1].tag == .identifier and ts[i + 2].tag == .equal) {
            const end = s.expressionEnd(i + 3);
            try s.scopes.append(.{ .name = slice(s.bytes, ts[i + 1]), .end = end, .kind = .member, .display = try s.rowName(i + 3, end) });
        } else if (ts[i].tag == .identifier and i > 0 and oneOfToken(ts[i - 1].tag, &.{ .l_brace, .comma }) and i + 1 < ts.len and ts[i + 1].tag == .colon) {
            const end = s.expressionEnd(i + 2);
            var at = i + 2;
            while (at <= end and ts[at].tag != .equal) : (at += 1) {
                if (oneOfToken(ts[at].tag, &.{ .l_brace, .l_paren, .l_bracket })) at = s.pairs[at];
            }
            if (at <= end) try s.scopes.append(.{ .name = slice(s.bytes, ts[i]), .end = end, .kind = .member });
        } else if (ts[i].tag == .l_paren and i > 0 and ts[i - 1].tag == .identifier and (i < 2 or ts[i - 2].tag != .keyword_fn)) {
            var start = i - 1;
            while (start >= 2 and ts[start - 1].tag == .period and ts[start - 2].tag == .identifier) start -= 2;
            try s.scopes.append(.{ .name = s.bytes[ts[start].loc.start..ts[i - 1].loc.end], .end = s.pairs[i], .kind = .call });
        }
    }

    fn describe(s: *const ContextScan) !Semantic {
        var identity = std.ArrayList(u8).init(s.a);
        try identity.appendSlice(s.module);
        var owner: ?[]const u8 = null;
        var role: []const u8 = "Text";
        var call: ?[]const u8 = null;
        var category = s.category;
        var skill_owner: ?[]const u8 = null;
        for (s.skills) |skill| if (std.mem.eql(u8, skill.scope, s.module)) {
            skill_owner = skill.name;
        };
        for (s.scopes.items) |scope| {
            if (scope.kind == .call) {
                call = scope.name;
                continue;
            }
            try identity.append('.');
            try identity.appendSlice(scope.name);
            call = null;
            for (s.skills) |skill| if (std.mem.eql(u8, skill.scope, identity.items)) {
                skill_owner = skill.name;
            };
            if (scope.display) |display| owner = display else if (textRole(scope.name)) |r| {
                role = r;
            } else owner = try humanize(s.a, scope.name);
        }
        if (skill_owner) |name| {
            category = "Skills";
            owner = name;
        }
        if (owner == null) {
            const dot = std.mem.lastIndexOfScalar(u8, s.module, '.') orelse 0;
            owner = try humanize(s.a, s.module[if (dot > 0) dot + 1 else 0..]);
        }
        if (call) |name| {
            try identity.appendSlice(" > ");
            try identity.appendSlice(name);
        }
        return .{ .category = category, .owner = owner.?, .role = role, .context = try identity.toOwnedSlice() };
    }
};

fn oneOfToken(tag: Token.Tag, choices: []const Token.Tag) bool {
    for (choices) |choice| if (tag == choice) return true;
    return false;
}

fn enumType(a: std.mem.Allocator, path: []const u8, bytes: []const u8, ts: []const Token, at: usize) !?[]const u8 {
    if (at < 3 or ts[at - 1].tag != .equal or ts[at - 2].tag != .identifier or ts[at - 3].tag != .keyword_const) return null;
    if (!std.mem.startsWith(u8, path, SRC) or !std.mem.endsWith(u8, path, ZIG)) return null;
    var name = std.ArrayList(u8).init(a);
    try name.appendSlice(try moduleOf(a, path));
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
    if (oneOf(name, &.{ "eql", "startsWith", "endsWith", "indexOf", "indexOfScalar", "lastIndexOfScalar", "hash", "stringToEnum", "expectEqualStrings", "expectError", "getUniformLocation", "loadShaderFromMemory", "capture", "snap", "shootPage", "has", "declares" })) return true;
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
    if (oneOf(decl, &ACTION_WORDS) or oneOf(decl, &.{ "NAME", "NUMBERS", FRIGHT_WORDS })) return true;
    for ([_][]const u8{ ".zig", ".png", ".ttf", atlas.EXT, ".json", "#version", "void main", "uniform ", "layout(", "roguelike-map", "shots/", "assets/", atlas.PREFIX, "saves/" }) |part| {
        if (std.mem.indexOf(u8, text, part) != null) return false;
    }
    const from = i -| 12;
    var context = false;
    for (ts[from..i]) |token| {
        if (token.tag != .identifier) continue;
        const name = slice(bytes, token);
        if (oneOf(name, &.{ "name", "label", "title", "description", "desc", "tip", "note", "caption", "say", "push", "draw", "drawMid", "drawFit", "button", "buttonOn", "put", "text", "line", "bufPrint", "bufPrintZ", "comptimePrint", "verb", "slain" })) context = true;
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

pub fn oneLine(s: []const u8) bool {
    return std.mem.indexOfAny(u8, s, "\r\n\t") == null;
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

test "text catalog semantic context separates table rows skill containers calls and enum identities" {
    var c = Catalog.init(std.testing.allocator);
    defer c.deinit();
    try c.scan("src/play/items.zig",
        \\const SPECS = make(.{
        \\ .war_bow = .{ .desc = "Far away.", .name = "War bow" },
        \\ .tome = .{ .name = "Tome", .desc = "Old words." },
        \\});
    );
    try std.testing.expectEqual(@as(usize, 4), c.entries().len);
    const bow = c.entries()[0];
    try std.testing.expectEqualStrings("Items", bow.category);
    try std.testing.expectEqualStrings("War bow", bow.owner);
    try std.testing.expectEqualStrings("Description", bow.role);
    try std.testing.expectEqualStrings("play.items.SPECS.war_bow.desc", bow.context);
    try std.testing.expectEqualStrings("Tome", c.entries()[3].owner);
    try std.testing.expectEqualStrings("play.items.SPECS.tome.desc", c.entries()[3].context);
    try std.testing.expectEqual(@as(usize, 3), c.entries()[3].ordinal);
    try c.scan("src/play/tactics.zig",
        \\pub const ArcaneBarrier = struct {
        \\ pub const DESCRIPTION = "Raise a wall.";
        \\ pub const STATUS = "Draw a line.";
        \\};
        \\pub const Guard = struct { pub const DESCRIPTION = "Brace."; };
    );
    try std.testing.expectEqualStrings("Skills", c.entries()[4].category);
    try std.testing.expectEqualStrings("Arcane barrier", c.entries()[4].owner);
    try std.testing.expectEqualStrings("Description", c.entries()[4].role);
    try std.testing.expectEqualStrings("Status", c.entries()[5].role);
    try std.testing.expectEqualStrings("play.tactics.ArcaneBarrier.STATUS", c.entries()[5].context);
    try std.testing.expectEqualStrings("Guard", c.entries()[6].owner);
    try c.scan("src/play/ward.zig", "pub const DESCRIPTION = fmt.comptimePrint(\"Drain {d} mana.\", .{5});\n");
    try std.testing.expectEqualStrings("Mana shield", c.entries()[7].owner);
    try std.testing.expectEqualStrings("Description", c.entries()[7].role);
    try std.testing.expectEqualStrings("play.ward.DESCRIPTION > fmt.comptimePrint", c.entries()[7].context);
    try c.scan("src/game/character.zig", "const Panel = struct { fn draw() void { ui.button(\"Take all\"); } };\n");
    try std.testing.expectEqualStrings("Draw", c.entries()[8].owner);
    try std.testing.expectEqualStrings("Text", c.entries()[8].role);
    try std.testing.expectEqualStrings("game.character.Panel.draw > ui.button", c.entries()[8].context);
    c.labels = "play.skillbar.Act.arcane_barrier\tStone wall\n";
    try c.scan("src/play/skillbar.zig", "pub const Act = enum { arcane_barrier };\n");
    const alias = c.entries()[9];
    try std.testing.expectEqualStrings("Stone wall", alias.text);
    try std.testing.expectEqualStrings("Skills", alias.category);
    try std.testing.expectEqualStrings("Arcane barrier", alias.owner);
    try std.testing.expectEqualStrings("play.skillbar.Act.arcane_barrier", alias.context);
    try std.testing.expectEqualStrings("Display name", alias.role);
    try std.testing.expect(alias.editable);
    try std.testing.expectEqualStrings(alias.context, alias.alias.?);
    try c.scan("src/ui/example.zig", "const Dialog = struct { title: []const u8 = \"Welcome\", }; const NAME: []const u8 = \"Typed name\";\n");
    try std.testing.expectEqualStrings("ui.example.Dialog.title", c.entries()[10].context);
    try std.testing.expectEqualStrings("Dialog", c.entries()[10].owner);
    try std.testing.expectEqualStrings("Title", c.entries()[10].role);
    try std.testing.expectEqualStrings("ui.example.NAME", c.entries()[11].context);
    for (c.entries()) |e| try std.testing.expect(e.category.len > 0 and e.owner.len > 0 and e.role.len > 0 and e.context.len > 0);
    std.debug.print("text catalog: table rows, skill module/container names, exact call context, typed fields and enum alias identity checked across 12 entries\n", .{});
}

test "text catalog skill registry context follows named rows with module in any member order" {
    var c = Catalog.init(std.testing.allocator);
    defer c.deinit();
    c.skills = try skillSources(c.arena.allocator(),
        \\const tactics = @import("tactics.zig");
        \\const ward = @import("ward.zig");
        \\const SKILLS = .{
        \\ .arcane_barrier = .{ .reticle = .ground, .module = tactics.ArcaneBarrier },
        \\ .mana_shield = .{ .reticle = choose(.{ .shape = .ground }), .module = ward },
        \\ .guard = .{ .module = tactics.Guard, .reticle = .ground },
        \\ .wait = .{ .reticle = .ground, .module = null },
        \\};
    );
    try std.testing.expectEqual(@as(usize, 3), c.skills.?.len);
    try c.scan("src/play/tactics.zig", "const ArcaneBarrier = struct { const DESCRIPTION = \"Raise a wall.\"; }; const Guard = struct { const DESCRIPTION = \"Stand firm.\"; };\n");
    try c.scan("src/play/ward.zig", "const DESCRIPTION = \"Drain mana.\";\n");
    try std.testing.expectEqualStrings("Skills", c.entries()[0].category);
    try std.testing.expectEqualStrings("Arcane barrier", c.entries()[0].owner);
    try std.testing.expectEqualStrings("play.tactics.ArcaneBarrier.DESCRIPTION", c.entries()[0].context);
    try std.testing.expectEqualStrings("Guard", c.entries()[1].owner);
    try std.testing.expectEqualStrings("Mana shield", c.entries()[2].owner);
    std.debug.print("text skill registry: reticle-first, nested reticle expression, module-first and null module keep 3 correct skill owners\n", .{});
}

test "text catalog finds all fright speech and gives maps nonempty semantic provenance" {
    var c = Catalog.init(std.testing.allocator);
    defer c.deinit();
    try std.testing.expect(included("gfx/fx.zig"));
    try c.scan("src/gfx/fx.zig", "pub const FRIGHT_WORDS = [_][:0]const u8{ \"Eek!\", \"Ah!\", \"[snorts]\", \"[squeals]\" };\n");
    try std.testing.expectEqual(@as(usize, 4), c.entries().len);
    for (c.entries()) |e| {
        try std.testing.expectEqualStrings("Effects", e.category);
        try std.testing.expectEqualStrings("Fright speech", e.role);
        try std.testing.expectEqualStrings("gfx.fx.FRIGHT_WORDS", e.context);
        try std.testing.expect(e.owner.len > 0 and e.editable);
    }
    try c.scanMap("maps/test.map", "node bespoke\nname First room\nnode procgen wilds\nname Second room\n");
    try std.testing.expectEqualStrings("First room (node 0)", c.entries()[4].owner);
    try std.testing.expectEqualStrings("Maps", c.entries()[5].category);
    try std.testing.expectEqualStrings("Name", c.entries()[5].role);
    try std.testing.expectEqualStrings("maps/test.map.node[1].name", c.entries()[5].context);
    std.debug.print("text catalog: 4 fright utterances including lowercase bracketed speech, 2 named map nodes checked\n", .{});
}

test "text catalog indexes live item skill and speech sources with complete metadata" {
    var c = Catalog.init(std.testing.allocator);
    defer c.deinit();
    try c.scan("src/play/items.zig", @embedFile("../play/items.zig"));
    try c.scan("src/play/tactics.zig", @embedFile("../play/tactics.zig"));
    try c.scan("src/gfx/fx.zig", @embedFile("../gfx/fx.zig"));
    var bow = false;
    var barrier = false;
    var speech: usize = 0;
    for (c.entries()) |e| {
        try std.testing.expect(e.category.len > 0 and e.owner.len > 0 and e.role.len > 0 and e.context.len > 0);
        if (std.mem.eql(u8, e.context, "play.items.SPECS.war_bow.name")) {
            bow = true;
            try std.testing.expectEqualStrings("War bow", e.owner);
            try std.testing.expectEqualStrings("Name", e.role);
        }
        if (std.mem.eql(u8, e.context, "play.tactics.ArcaneBarrier.DESCRIPTION")) {
            barrier = true;
            try std.testing.expectEqualStrings("Skills", e.category);
            try std.testing.expectEqualStrings("Arcane barrier", e.owner);
        }
        if (std.mem.eql(u8, e.context, "gfx.fx.FRIGHT_WORDS")) speech += 1;
    }
    try std.testing.expect(bow and barrier);
    try std.testing.expectEqual(@import("../gfx/fx.zig").FRIGHT_WORDS.len, speech);
    std.debug.print("text catalog: {d} live entries have nonempty metadata; item/skill context and all {d} fright utterances found\n", .{ c.entries().len, speech });
}

test "text catalog retains moved input captions and save wording under their original categories" {
    var catalog = Catalog.init(std.testing.allocator);
    defer catalog.deinit();
    for ([_][]const u8{ "core/input_bindings.zig", "core/input_names.zig", "save_data.zig" }) |source| {
        try std.testing.expect(included(source));
    }
    try catalog.scan("src/core/input_bindings.zig", "pub const CAPTION = \"A shortcut caption\";");
    try catalog.scan("src/core/input_names.zig", "pub const CAPTION = \"A device caption\";");
    try catalog.scan("src/save_data.zig", "pub const CAPTION = \"a generated floor\";");
    try std.testing.expectEqual(@as(usize, 3), catalog.entries().len);
    for (catalog.entries()[0..2]) |entry| {
        try std.testing.expectEqualStrings("Input", entry.category);
        try std.testing.expect(!entry.editable);
    }
    try std.testing.expectEqualStrings("Save", catalog.entries()[2].category);
    try catalog.scan("src/play/ossuary.zig", @embedFile("../play/ossuary.zig"));
    for (catalog.entries()[3..]) |entry| {
        try std.testing.expect(!std.mem.eql(u8, entry.text, "n") and !std.mem.eql(u8, entry.text, "summary_n"));
    }
    std.debug.print("text catalog: 3 moved sources retain categories and input caption protections\n", .{});
}

test "character page aliases retain their saved keys after moving the view type" {
    const Page = @import("../ui/character_view.zig").Page;
    const labels = "ui.book.Page.equipment\tOutfitting\n";
    var c = Catalog.init(std.testing.allocator);
    defer c.deinit();
    c.labels = labels;
    try c.scan("src/ui/character_view.zig", @embedFile("../ui/character_view.zig"));
    var pages: usize = 0;
    for (c.entries()) |entry| {
        if (!std.mem.startsWith(u8, entry.context, "ui.book.Page.")) continue;
        try std.testing.expect(entry.editable);
        try std.testing.expectEqualStrings(entry.context, entry.alias.?);
        if (std.mem.eql(u8, entry.context, "ui.book.Page.equipment")) try std.testing.expectEqualStrings("Outfitting", entry.text);
        pages += 1;
    }
    try std.testing.expectEqual(std.enums.values(Page).len, pages);
    try std.testing.expectEqualStrings("Outfitting", comptime wording.displayAliasIn(labels, @typeName(Page), "equipment").?);
    std.debug.print("character wording: all {d} page aliases remain editable and the moved runtime type reads the original saved key\n", .{pages});
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

test "text catalog repeated snapshot replacements keep live memory bounded without file writes" {
    var memory = std.heap.DebugAllocator(.{ .enable_memory_limit = true }){};
    defer _ = memory.deinit();
    const alloc = memory.allocator();
    var live: [2]usize = @splat(0);
    {
        var c = Catalog.init(alloc);
        defer c.deinit();
        var source: [80 * 1024]u8 = @splat(' ');
        const declaration_ = "const NAME = \"Start\";\n";
        @memcpy(source[0..declaration_.len], declaration_);
        try c.scan("src/ui/example.zig", &source);
        for (0..128) |i| {
            const value = if (i % 2 == 0) "Begin" else "Again";
            const author: Author = if (i % 2 == 0) .you else .mixed;
            var update = try c.prepareTags(c.entries()[0], value, author);
            c.acceptTags(&update);
            update.deinit(alloc);
            @memcpy(source[c.entries()[0].start + 1 ..][0..value.len], value);
            c.files.items[0].replaceBytes(alloc, try alloc.dupeZ(u8, &source));
            c.list.items[0].replaceText(alloc, try alloc.dupe(u8, value));
            c.replaceLabels(try alloc.dupe(u8, "play.skillbar.Act.guard\tBlock\n"));
            const before_failure = memory.total_requested_bytes;
            c.tags_invalid = true;
            var discarded = try c.prepareTags(c.entries()[0], "Later", .ai);
            try std.testing.expectEqual(SaveResult.tags_not_saved, c.saveTags(&discarded));
            discarded.deinit(alloc);
            c.tags_invalid = false;
            try std.testing.expectEqual(before_failure, memory.total_requested_bytes);
            try std.testing.expectEqual(author, c.authorOf(c.entries()[0]));
            try std.testing.expectEqualStrings(value, c.entries()[0].text);
            try std.testing.expectEqualStrings(&source, c.files.items[0].bytes);
            if (i < live.len) live[i] = memory.total_requested_bytes else try std.testing.expectEqual(live[i % live.len], memory.total_requested_bytes);
        }
    }
    try std.testing.expectEqual(@as(usize, 0), memory.total_requested_bytes);
    std.debug.print("text catalog: 128 source/text/tag/label replacements stay at {d}-{d} live bytes, rejected tags release preparation, teardown frees all\n", .{ live[0], live[1] });
}

test "text catalog display entries keep independent text when label snapshots are replaced" {
    const alloc = std.testing.allocator;
    var c = Catalog.init(alloc);
    defer c.deinit();
    c.replaceLabels(try alloc.dupe(u8, "play.skillbar.Act.guard\tBrace\nplay.skillbar.Act.secondary\tAlternate\n"));
    try c.scan("src/play/skillbar.zig", "pub const Act = enum { guard, secondary };\n");
    c.replaceLabels(try alloc.dupe(u8, "play.skillbar.Act.guard\tBlock\n"));
    try std.testing.expectEqualStrings("Brace", c.entries()[0].text);
    try std.testing.expectEqualStrings("Alternate", c.entries()[1].text);
    try std.testing.expect(c.entries()[0].editable and !c.entries()[1].editable);
    std.debug.print("text catalog: editable and read-only display entries retain independent text across label replacement\n", .{});
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
    var update = try c.prepareTags(entry, "Begin", .mixed);
    defer update.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), update.tags.len);
    try std.testing.expectEqual(@as(usize, 4), update.tags[0].ordinal);
    try std.testing.expectEqual(hash("Begin"), update.tags[1].hash);
    try std.testing.expectEqual(Author.mixed, update.tags[1].author);
    const parsed = try std.json.parseFromSlice(Tags, std.testing.allocator, update.bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqualDeep(update.tags, parsed.value.tags);
    try std.testing.expectEqual(Author.ai, c.tags[0].author);
    c.tags_invalid = true;
    try std.testing.expectEqual(SaveResult.tags_not_saved, c.saveTags(&update));
    try std.testing.expectEqualStrings("unchanged snapshot", c.tag_bytes);
    try std.testing.expectEqual(Author.ai, c.tags[0].author);
    std.debug.print("text tags: shared upsert prepared independently; malformed file blocks tag commit and preserves loaded attribution\n", .{});
}

test "text catalog protects reflection controls while finding short verbs" {
    var c = Catalog.init(std.testing.allocator);
    defer c.deinit();
    try c.scan("src/ui/naming.zig", "const LETTERS = [_][]const u8{ \"ABCDEFGHIJKLM\", \"NOPQRSTUVWXYZ\" };\n");
    try std.testing.expect(!c.entries()[0].editable and !c.entries()[1].editable);
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
    std.debug.print("text catalog: 2 protected keyboard rows, 2 short verbs, reflection exclusions, tag-only aliases and map-name provenance checked\n", .{});
}
