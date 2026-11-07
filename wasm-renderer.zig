//! Shared pinned renderer, without process, filesystem or terminal access.
const std = @import("std");
const p = @import("wasm/protocol.zig");
// Supplied from the locked renderer flake inside the Nix derivation.
const engine = @import("web-renderer/engine.zig");
const Config = @TypeOf(@as(engine.Engine, undefined).config);
const Align = @typeInfo(@TypeOf(@as(Config, undefined).alignments)).pointer.child;
const Overflow = @typeInfo(@TypeOf(@as(Config, undefined).overflow)).pointer.child;
const a = std.heap.c_allocator;
export fn table_web_render(raw: *const p.RenderOptions, input: [*]const p.Row, count: usize, ascii: u32, header: u32, output: *p.Buffer) u32 {
    output.* = .{};
    render(raw, input[0..count], ascii != 0, header != 0, output) catch |err| return switch (err) {
        error.OutOfMemory => 10,
        error.TooNarrow => 7,
        error.TooManyColumnOptions => 6,
        else => 2,
    };
    return 0;
}
fn render(raw: *const p.RenderOptions, input: []const p.Row, ascii: bool, header: bool, output: *p.Buffer) !void {
    if (raw.terminal == 0 or raw.terminal > 10000 or raw.decimal > 2 or raw.alignment > 3 or raw.overflow > 4) return error.InvalidOptions;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const rows = try scratch.alloc([]const []const u8, input.len);
    for (input, rows) |r, *dest| {
        const cells = try scratch.alloc([]const u8, r.len);
        for (r.cells[0..r.len], cells) |cell, *value| value.* = cell.data[0..cell.len];
        dest.* = cells;
    }
    const columns = if (rows.len > 0) rows[0].len else 0;
    const widths = try scratch.alloc(usize, columns);
    const alignments = try scratch.alloc(Align, columns);
    const overflow = try scratch.alloc(Overflow, columns);
    const aligns = [_]Align{ .auto, .left, .right, .center };
    const modes = [_]Overflow{ .auto, .truncate_left, .truncate_right, .prefix_ellipsis, .suffix_ellipsis };
    @memset(widths, 0);
    @memset(alignments, aligns[raw.alignment]);
    @memset(overflow, modes[raw.overflow]);
    for (raw.overrides[0..raw.count]) |column| {
        if (column.index >= columns or column.width > 10000) return error.TooManyColumnOptions;
        widths[column.index] = column.width;
        if (column.alignment != std.math.maxInt(u32)) {
            if (column.alignment > 3) return error.InvalidOptions;
            alignments[column.index] = aligns[column.alignment];
        }
        if (column.overflow != std.math.maxInt(u32)) {
            if (column.overflow > 4) return error.InvalidOptions;
            overflow[column.index] = modes[column.overflow];
        }
    }
    const config: Config = .{ .terminal = raw.terminal, .ascii = ascii, .no_header = !header, .plain = raw.flags & 4 != 0, .color = if (raw.flags & 8 != 0) .always else .never, .decimal = ([_][]const u8{ ".", ",", "٫" })[raw.decimal], .widths = widths, .alignments = alignments, .overflow = overflow };
    const result = try engine.renderTable(a, config, rows);
    output.* = .{ .data = if (result.len == 0) null else @constCast(result.ptr), .len = result.len };
}
export fn table_web_render_free(output: *p.Buffer) void {
    if (output.data) |data| a.free(data[0..output.len]);
    output.* = .{};
}
