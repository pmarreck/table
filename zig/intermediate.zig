//! Version 1 intermediate-format encoder. This is not yet a complete CLI.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Row = []const []const u8;

pub const Table = struct {
    header: ?Row,
    rows: []const Row,
};

fn appendRow(allocator: Allocator, out: *std.ArrayList(u8), row: Row, width: *?usize) !void {
    if (row.len == 0) return error.EmptyRow;
    if (width.*) |n| {
        if (row.len != n) return error.RaggedRows;
    } else width.* = row.len;
    for (row, 0..) |field, i| {
        if (!std.unicode.utf8ValidateSlice(field)) return error.InvalidUtf8;
        if (i != 0) try out.append(allocator, 0x1f);
        for (field) |byte| {
            const code: ?u8 = switch (byte) {
                0x1b => 'e', 0x1c => 'f', 0x1d => 'g', 0x1e => 'r', 0x1f => 'u',
                else => null,
            };
            if (code) |escaped| {
                try out.append(allocator, 0x1b);
                try out.append(allocator, escaped);
            } else try out.append(allocator, byte);
        }
    }
    try out.append(allocator, 0x1e);
}

/// The caller owns the returned bytes. Fields remain owned by the caller.
pub fn encode(allocator: Allocator, table: Table) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "\x1cT1");
    var width: ?usize = null;
    if (table.header) |row| {
        try out.append(allocator, 0x1d);
        try appendRow(allocator, &out, row, &width);
    }
    for (table.rows) |row| try appendRow(allocator, &out, row, &width);
    try out.append(allocator, 0x1c);
    return out.toOwnedSlice(allocator);
}

test "canonical wire vectors preserve empty cells and reserved bytes" {
    const a = std.testing.allocator;
    const empty = try encode(a, .{ .header = null, .rows = &.{} });
    defer a.free(empty);
    try std.testing.expectEqualStrings("\x1cT1\x1c", empty);
    const result = try encode(a, .{ .header = &.{ "h", "" }, .rows = &.{&.{ "\x1b\x1c\x1d\x1e\x1f", "界" }} });
    defer a.free(result);
    try std.testing.expectEqualStrings("\x1cT1\x1dh\x1f\x1e\x1be\x1bf\x1bg\x1br\x1bu\x1f界\x1e\x1c", result);
}

test "encoding rejects invalid model" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.EmptyRow, encode(a, .{ .header = &.{}, .rows = &.{} }));
    try std.testing.expectError(error.RaggedRows, encode(a, .{ .header = &.{"a"}, .rows = &.{&.{ "a", "b" }} }));
    try std.testing.expectError(error.InvalidUtf8, encode(a, .{ .header = &.{"\xff"}, .rows = &.{} }));
}
