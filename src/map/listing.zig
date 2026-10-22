const std = @import("std");
const atlas = @import("atlas.zig");

/// A map file's name, `.map` and all.
const FILE_MAX: usize = 64;
/// A map file's name before `.map`, as `pathFor` makes it.
pub const STEM_MAX = FILE_MAX - atlas.EXT.len;
/// The folders a listed map lies in below `DIR`, names and '/'s.
const FOLDER_MAX: usize = 64;
pub const PATH_MAX = atlas.PREFIX.len + FOLDER_MAX + FILE_MAX;
const ListedPath = [PATH_MAX + 1]u8;

/// The folder below `DIR` a map's path lies in, its '/' kept; none for a path outside `DIR`.
pub fn folderOf(path: []const u8) []const u8 {
    if (!std.mem.startsWith(u8, path, atlas.PREFIX)) return "";
    const rest = path[atlas.PREFIX.len..];
    const end = std.mem.lastIndexOfScalar(u8, rest, '/') orelse return "";
    return rest[0 .. end + 1];
}

/// In `folder`, as `folderOf` gives it.
pub fn pathFor(buf: []u8, folder: []const u8, name: []const u8) ?[]const u8 {
    var stem: [STEM_MAX]u8 = undefined;
    var n: usize = 0;
    for (std.mem.trim(u8, name, " ")) |c| {
        if (n == stem.len) break;
        const k = std.ascii.toLower(c);
        if (!std.ascii.isAlphanumeric(k) and k != '_' and k != ' ') continue;
        stem[n] = if (k == ' ') '_' else k;
        n += 1;
    }
    if (n == 0 or folder.len > FOLDER_MAX) return null;
    return std.fmt.bufPrint(buf, atlas.PREFIX ++ "{s}{s}" ++ atlas.EXT, .{ folder, stem[0..n] }) catch null;
}

/// Folder listing: parent first, then sorted folders and maps; overflow keeps the first `MAX`.
pub const Listing = struct {
    pub const MAX: usize = 128;
    pub const UP = "..";
    const DEPTH_MAX: usize = 8;
    file: [MAX]Listed = undefined,
    n: usize = 0,
    /// The folder listed, below `DIR`: each folder's name and a '/', none at `DIR` itself.
    folder: [FOLDER_MAX]u8 = undefined,
    folder_n: usize = 0,

    pub const Entry = enum { up, folder, map };

    const Listed = struct {
        buf: ListedPath,
        n: usize,
        entry: Entry,

        fn text(l: *const Listed) [:0]const u8 {
            return l.buf[0..l.n :0];
        }

        fn before(_: void, a: Listed, b: Listed) bool {
            if (a.entry != b.entry) return @intFromEnum(a.entry) < @intFromEnum(b.entry);
            return std.mem.lessThan(u8, a.text(), b.text());
        }
    };

    /// A map's file, a folder's path and its '/', or `UP`.
    pub fn at(self: *const Listing, i: usize) [:0]const u8 {
        return self.file[i].text();
    }

    pub fn entry(self: *const Listing, i: usize) Entry {
        return self.file[i].entry;
    }

    /// What its row shows: a map's stem, a folder's name and its '/', or `UP`.
    pub fn label(self: *const Listing, i: usize) []const u8 {
        const p = self.at(i);
        return switch (self.entry(i)) {
            .up => p,
            .folder => p[atlas.PREFIX.len + self.folder_n ..],
            .map => self.stem(i),
        };
    }

    /// A map's file name before `EXT`.
    pub fn stem(self: *const Listing, i: usize) []const u8 {
        const p = self.at(i);
        const from = if (std.mem.lastIndexOfScalar(u8, p, '/')) |k| k + 1 else 0;
        return p[from .. p.len - atlas.EXT.len];
    }

    /// The folder listed, below `DIR`.
    pub fn here(self: *const Listing) []const u8 {
        return self.folder[0..self.folder_n];
    }

    /// Into the folder at `i`, or up from `UP`; false for a map.
    pub fn open(self: *Listing, i: usize) bool {
        switch (self.entry(i)) {
            .map => return false,
            .up => _ = self.up(),
            .folder => {
                const name = self.label(i);
                _ = self.enter(name[0 .. name.len - 1]);
                self.scan();
            },
        }
        return true;
    }

    /// To the folder above; false at `DIR` itself.
    pub fn up(self: *Listing) bool {
        if (self.folder_n == 0) return false;
        const inner = self.folder[0 .. self.folder_n - 1];
        self.folder_n = if (std.mem.lastIndexOfScalar(u8, inner, '/')) |k| k + 1 else 0;
        self.scan();
        return true;
    }

    /// `folder`, as `folderOf` gives it; `DIR` itself if it is not there.
    pub fn scanAt(self: *Listing, folder: []const u8) void {
        self.folder_n = 0;
        if (folder.len <= FOLDER_MAX) {
            @memcpy(self.folder[0..folder.len], folder);
            self.folder_n = folder.len;
        }
        self.scan();
    }

    /// The folder listed; `DIR` itself if that folder is gone.
    pub fn scan(self: *Listing) void {
        self.n = 0;
        if (self.folder_n > 0) self.add(.up, "{s}", .{UP});
        if (!self.gather(null)) {
            if (self.folder_n == 0) return;
            self.folder_n = 0;
            return self.scan();
        }
        self.sort();
    }

    /// Every map in every folder of `DIR`, by path.
    pub fn scanAll(self: *Listing) void {
        self.n = 0;
        self.folder_n = 0;
        _ = self.gather(0);
        self.sort();
    }

    fn fits(self: *const Listing, name: []const u8) bool {
        return self.folder_n + name.len + 1 <= FOLDER_MAX;
    }

    fn enter(self: *Listing, name: []const u8) bool {
        if (!self.fits(name)) return false;
        @memcpy(self.folder[self.folder_n..][0..name.len], name);
        self.folder[self.folder_n + name.len] = '/';
        self.folder_n += name.len + 1;
        return true;
    }

    /// `walking` recursively collects maps from this depth, capped at `DEPTH_MAX`.
    fn gather(self: *Listing, walking: ?usize) bool {
        var buf: [PATH_MAX]u8 = undefined;
        var dir = std.fs.cwd().openDir(self.dirPath(&buf), .{ .iterate = true }) catch return false;
        defer dir.close();
        var it = dir.iterate();
        while (it.next() catch null) |e| {
            if (!shown(e.name)) continue;
            switch (e.kind) {
                .directory => if (walking) |depth| {
                    const was = self.folder_n;
                    if (depth < DEPTH_MAX and self.enter(e.name)) _ = self.gather(depth + 1);
                    self.folder_n = was;
                } else if (self.fits(e.name)) self.add(.folder, atlas.PREFIX ++ "{s}{s}/", .{ self.here(), e.name }),
                .file => if (std.mem.endsWith(u8, e.name, atlas.EXT) and e.name.len <= FILE_MAX) self.add(.map, atlas.PREFIX ++ "{s}{s}", .{ self.here(), e.name }),
                else => {},
            }
        }
        return true;
    }

    pub fn dirPath(self: *const Listing, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, atlas.PREFIX ++ "{s}", .{self.here()}) catch atlas.DIR;
    }

    fn shown(name: []const u8) bool {
        return name.len > 0 and name[0] != '.' and atlas.plain(name);
    }

    fn add(self: *Listing, e: Entry, comptime fmt: []const u8, args: anytype) void {
        var l: Listed = undefined;
        l.entry = e;
        l.n = (std.fmt.bufPrintZ(&l.buf, fmt, args) catch return).len;
        if (self.n < MAX) {
            self.file[self.n] = l;
            self.n += 1;
            return;
        }
        var last: usize = 0;
        for (self.file[1..], 1..) |*o, i| {
            if (Listed.before({}, self.file[last], o.*)) last = i;
        }
        if (Listed.before({}, l, self.file[last])) self.file[last] = l;
    }

    fn sort(self: *Listing) void {
        std.sort.insertion(Listed, self.file[0..self.n], {}, Listed.before);
    }
};

test "a map file is named from anything typed, and nothing left of it is no name" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings(atlas.DIR ++ "/the_deepcave2" ++ atlas.EXT, pathFor(&buf, "", " The Deep/Cave2! ").?);
    try std.testing.expectEqual(@as(?[]const u8, null), pathFor(&buf, "", "../"));
    try std.testing.expectEqualStrings("qud/", folderOf(atlas.DIR ++ "/qud/qud_strata" ++ atlas.EXT));
    try std.testing.expectEqualStrings("", folderOf(atlas.MAIN));
    try std.testing.expectEqualStrings(atlas.DIR ++ "/qud/bog" ++ atlas.EXT, pathFor(&buf, folderOf(atlas.DIR ++ "/qud/qud_strata" ++ atlas.EXT), "Bog").?);
}

test "the maps folder lists its folders before its maps, and a folder opens with the way back up first" {
    var list = Listing{};
    list.scan();
    try std.testing.expect(list.n > 0 and list.entry(0) == .folder);
    const qud = for (0..list.n) |i| {
        if (std.mem.eql(u8, list.label(i), "qud/")) break i;
    } else return error.NoFolder;
    const top = list.n;
    try std.testing.expect(list.open(qud));
    try std.testing.expectEqualStrings("qud/", list.here());
    try std.testing.expectEqual(Listing.Entry.up, list.entry(0));
    try std.testing.expectEqual(Listing.Entry.map, list.entry(1));
    try std.testing.expect(std.mem.startsWith(u8, list.at(1), atlas.DIR ++ "/qud/qud_"));
    try std.testing.expect(std.mem.startsWith(u8, list.label(1), "qud_"));
    try std.testing.expect(!list.open(1));
    const inside = list.n;
    try std.testing.expect(list.open(0));
    try std.testing.expectEqual(@as(usize, 0), list.here().len);
    try std.testing.expect(!list.up());
    var all = Listing{};
    all.scanAll();
    std.debug.print("{d} rows in {s}, {d} in qud/ with the way up, {d} maps in all\n", .{ top, atlas.DIR, inside, all.n });
    try std.testing.expect(all.n > top);
}
