//! Owned request/result ABI. JS may write only the request buffer until run().
const std = @import("std");
const core = @import("zig/core.zig");
const p = @import("wasm/protocol.zig");
const a = std.heap.c_allocator;
extern fn table_web_render(*const p.RenderOptions, [*]const p.Row, usize, u32, u32, *p.Buffer) u32;
extern fn table_web_render_free(*p.Buffer) void;
var request: std.ArrayList(u8) = .empty;
var result: []const u8 = "";
var detected: u32 = 0;
var row_count: u32 = 0;
var column_count: u32 = 0;
export fn table_request(length: u32) usize {
    clear();
    request.clearRetainingCapacity();
    if (length < 48 or length > 16 * 1024 * 1024) return 0;
    request.resize(a, length) catch return 0;
    return @intFromPtr(request.items.ptr);
}
fn clear() void {
    if (result.len > 0) a.free(result);
    result = "";
    detected = 0;
    row_count = 0;
    column_count = 0;
}
export fn table_result_ptr() usize {
    return @intFromPtr(result.ptr);
}
export fn table_result_len() usize {
    return result.len;
}
export fn table_source() u32 {
    return detected;
}
export fn table_rows() u32 {
    return row_count;
}
export fn table_columns() u32 {
    return column_count;
}
export fn table_run() u32 {
    clear();
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var ctx: core.Context = .{ .a = arena.allocator() };
    execute(&ctx) catch |err| {
        const message = if (err == error.Invalid) ctx.message else if (err == error.OutOfMemory) "not enough memory for this conversion" else "invalid browser conversion request";
        result = a.dupe(u8, message) catch "";
        return 1;
    };
    return 0;
}
fn execute(ctx: *core.Context) !void {
    const r = try p.parse(ctx.a, request.items);
    if (!std.unicode.utf8ValidateSlice(r.glyphs)) return ctx.bad("input is not UTF-8");
    const glyphs = if (r.glyphs.len > 0) r.glyphs else null;
    const source = if (r.source == 0) try ctx.detect(r.input, glyphs) else try p.format(r.source);
    detected = p.formatId(source);
    const t = try ctx.parse(source, r.input, r.options.flags & 1 != 0, glyphs);
    row_count = @intCast(t.rows.len - @as(usize, if (t.header) 1 else 0));
    column_count = @intCast(if (t.rows.len > 0) t.rows[0].len else 0);
    if (r.operation == 0) return;
    if ((core.eq(source, "ascii") or core.eq(source, "ansi")) and r.options.flags & 2 == 0) return ctx.bad("visual input is lossy; accept padding removal and possible prior clipping to continue");
    const destination = try p.format(r.destination);
    if (core.eq(destination, "ascii") or core.eq(destination, "ansi")) {
        const rows = try ctx.a.alloc(p.Row, t.rows.len);
        for (rows, t.rows) |*dest, row| {
            const cells = try ctx.a.alloc(p.Slice, row.len);
            for (cells, row) |*cell, value| cell.* = .{ .data = value.ptr, .len = value.len };
            dest.* = .{ .cells = cells.ptr, .len = cells.len };
        }
        var buffer: p.Buffer = .{};
        const status = table_web_render(&r.options, rows.ptr, rows.len, @intFromBool(core.eq(destination, "ascii")), @intFromBool(t.header), &buffer);
        defer table_web_render_free(&buffer);
        if (status != 0) return ctx.bad("invalid display options or insufficient table width");
        result = try a.dupe(u8, if (buffer.data) |data| data[0..buffer.len] else "");
    } else result = try a.dupe(u8, try ctx.write(t, destination));
}
