const std = @import("std");
pub const Override = extern struct { index: u32, width: u32, alignment: u32, overflow: u32 };
pub const RenderOptions = extern struct {
    terminal: u32,
    flags: u32,
    decimal: u32,
    alignment: u32,
    overflow: u32,
    overrides: [*]const Override,
    count: usize,
};
pub const Slice = extern struct { data: [*]const u8, len: usize };
pub const Row = extern struct { cells: [*]const Slice, len: usize };
pub const Buffer = extern struct { data: ?[*]u8 = null, len: usize = 0 };
pub const Request = struct {
    operation: u32,
    source: u32,
    destination: u32,
    options: RenderOptions,
    glyphs: []const u8,
    input: []const u8,
};
pub fn format(id: u32) ![]const u8 {
    return switch (id) {
        1 => "csv",
        2 => "tsv",
        3 => "markdown",
        4 => "ascii",
        5 => "ansi",
        6 => "ir",
        else => error.InvalidRequest,
    };
}
pub fn formatId(name: []const u8) u32 {
    for (1..7) |i| if (std.mem.eql(u8, format(@intCast(i)) catch unreachable, name)) return @intCast(i);
    return 0;
}
pub fn parse(a: std.mem.Allocator, bytes: []const u8) !Request {
    if (bytes.len < 48 or bytes.len > 16 * 1024 * 1024) return error.InvalidRequest;
    var words: [12]u32 = undefined;
    for (&words, 0..) |*word, i| word.* = std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little);
    if (words[0] != 0x31574254 or words[1] > 1 or words[2] > 6 or words[3] > 6 or words[4] & ~@as(u32, 15) != 0 or words[9] > 10000 or words[11] > 8 * 1024 * 1024) return error.InvalidRequest;
    const count: usize = words[9];
    const glyph_len: usize = words[10];
    const input_len: usize = words[11];
    if (48 + count * 16 > bytes.len or glyph_len > bytes.len - 48 - count * 16 or input_len != bytes.len - 48 - count * 16 - glyph_len) return error.InvalidRequest;
    const overrides = try a.alloc(Override, count);
    for (overrides, 0..) |*column, i| {
        const p = bytes[48 + i * 16 ..];
        column.* = .{ .index = std.mem.readInt(u32, p[0..4], .little), .width = std.mem.readInt(u32, p[4..8], .little), .alignment = std.mem.readInt(u32, p[8..12], .little), .overflow = std.mem.readInt(u32, p[12..16], .little) };
    }
    const start = 48 + count * 16;
    return .{ .operation = words[1], .source = words[2], .destination = words[3], .options = .{ .terminal = words[5], .flags = words[4], .decimal = words[6], .alignment = words[7], .overflow = words[8], .overrides = overrides.ptr, .count = count }, .glyphs = bytes[start .. start + glyph_len], .input = bytes[start + glyph_len ..] };
}
