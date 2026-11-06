const std = @import("std");
const core = @import("core.zig");
const eq = core.eq;
const Bytes = extern struct { data: ?[*]u8, len: usize };
const Process = extern struct { out: Bytes, err: Bytes, status: c_int };
extern fn table_read(*Bytes) c_int;
extern fn table_write(c_int, [*]const u8, usize) c_int;
extern fn table_free(?[*]u8) void;
extern fn table_about() [*:0]const u8;
extern fn table_renderer() [*:0]const u8;
extern fn table_columns() u64;
extern fn table_process([*:0]const u8, [*:null]const ?[*:0]u8, [*]const u8, usize, c_int, *Process) c_int;
extern fn getenv([*:0]const u8) ?[*:0]const u8;
const help = "Usage: table [--from auto|csv|tsv|markdown|ir|ascii|ansi] --to csv|tsv|markdown|ir|ascii|ansi [--header|--no-header]\nInput format is detected when --from is omitted. Ambiguous input requires --from.\nAutodetection buffers stdin; explicit --from tsv retains fixed-width visual streaming.\nVisual output: --widths, --align, --overflow, --terminal-width, --color, --plain, --decimal-separator.\n";
fn output(c: *core.Context, stream: c_int, s: []const u8) !void { if (table_write(stream, s.ptr, s.len) != 0) return c.bad("output write failed"); }
fn input(c: *core.Context) ![]const u8 {
    var bytes: Bytes = .{ .data = null, .len = 0 };
    if (table_read(&bytes) != 0) return c.bad("input read failed"); defer table_free(bytes.data);
    return c.a.dupe(u8, bytes.data.?[0..bytes.len]);
}
fn color() bool { return table_columns() > 0 and getenv("NO_COLOR") == null and (if (getenv("TERM")) |term| !eq(std.mem.span(term), "dumb") else true); }
fn format(s: []const u8) bool { for ([_][]const u8{ "csv", "tsv", "markdown", "ir", "ascii", "ansi" }) |f| { if (eq(s, f)) return true; } return false; }
fn render(c: *core.Context, data: []const u8, inherit: bool, ascii: bool, header: bool, options: []const []const u8) ![]const u8 {
    const program = table_renderer(); var args: std.ArrayList(?[*:0]u8) = .empty;
    try args.append(c.a, try c.a.dupeZ(u8, std.mem.span(program)));
    if (!header) try args.append(c.a, try c.a.dupeZ(u8, "--no-header"));
    if (ascii) try args.append(c.a, try c.a.dupeZ(u8, "--ascii"));
    for (options) |value| try args.append(c.a, try c.a.dupeZ(u8, value));
    try args.append(c.a, null);
    var result: Process = undefined;
    if (table_process(program, @ptrCast(args.items.ptr), data.ptr, data.len, if (inherit) 1 else 0, &result) != 0) return c.bad("cannot start renderer");
    defer { table_free(result.out.data); table_free(result.err.data); }
    if (result.status != 0) {
        if (inherit) return c.bad(try std.fmt.allocPrint(c.a, "renderer exited with exit status: {d}", .{result.status}));
        const err = if (result.err.data) |p| p[0..result.err.len] else "";
        return c.bad(try std.fmt.allocPrint(c.a, "renderer: {s}", .{std.mem.trim(u8, err, " \t\n\r")}));
    }
    return if (result.out.data) |p| c.a.dupe(u8, p[0..result.out.len]) else "";
}
fn run(c: *core.Context, args: []const []const u8) !void {
    var from: []const u8 = "auto"; var to: ?[]const u8 = null; var glyphs: ?[]const u8 = null;
    var header = true; var header_explicit = false; var allow = false; var explicit_color = false;
    var opts: std.ArrayList([]const u8) = .empty; var i: usize = 0;
    while (i < args.len) {
        const raw = args[i]; i += 1; const sep = std.mem.indexOfScalar(u8, raw, '=');
        const key = if (sep) |j| raw[0..j] else raw;
        const valued = eq(key, "--from") or eq(key, "--to") or eq(key, "--visual-glyphs") or eq(key, "--widths") or eq(key, "--align") or eq(key, "--overflow") or eq(key, "--terminal-width") or eq(key, "--color") or eq(key, "--decimal-separator");
        if (valued) {
            var value: []const u8 = undefined;
            if (sep) |j| { value = raw[j + 1 ..]; }
            else { if (i == args.len) return c.bad(try std.fmt.allocPrint(c.a, "{s} requires a value", .{key})); value = args[i]; i += 1; }
            if (eq(key, "--from")) from = value
            else if (eq(key, "--to")) to = value
            else if (eq(key, "--visual-glyphs")) glyphs = value
            else { if (eq(key, "--color")) { explicit_color = true; if (eq(value, "auto")) value = if (color()) "always" else "never"; } try opts.append(c.a, key); try opts.append(c.a, value); }
        } else if (sep == null and eq(key, "--allow-lossy")) allow = true
        else if (sep == null and eq(key, "--header")) { header = true; header_explicit = true; }
        else if (sep == null and eq(key, "--no-header")) { header = false; header_explicit = true; }
        else if (sep == null and eq(key, "--plain")) try opts.append(c.a, key)
        else if (sep == null and eq(key, "--about")) { try output(c, 1, std.mem.span(table_about())); return output(c, 1, "\n"); }
        else if (sep == null and (eq(key, "--help") or eq(key, "-h"))) return output(c, 1, help)
        else return c.bad(try std.fmt.allocPrint(c.a, "unknown option: {s}", .{raw}));
    }
    const destination = to orelse return c.bad("--to is required");
    if (!format(destination)) return c.bad("output formats: csv, tsv, markdown, ir, ascii, ansi");
    const auto = eq(from, "auto"); var data: []const u8 = "";
    if (auto) { data = try input(c); from = try c.detect(data, glyphs); }
    if (!format(from)) return c.bad("input formats: auto, csv, tsv, markdown, ir, ascii, ansi");
    if (header_explicit and !eq(from, "csv") and !eq(from, "tsv")) return c.bad("--header and --no-header apply only to CSV or TSV input");
    const vis = eq(destination, "ascii") or eq(destination, "ansi"); const vin = eq(from, "ascii") or eq(from, "ansi");
    if (vin and !allow) return c.bad("visual input is lossy; pass --allow-lossy to accept padding removal and possible prior clipping");
    if (!vin and (allow or glyphs != null)) return c.bad("--allow-lossy and --visual-glyphs require visual input");
    if (!vis and opts.items.len > 0) return c.bad("display options require ASCII or ANSI output");
    if (vis and !explicit_color) { try opts.append(c.a, "--color"); try opts.append(c.a, if (color()) "always" else "never"); }
    var explicit_width = false; for (opts.items) |o| { if (eq(o, "--terminal-width")) explicit_width = true; }
    if (vis and !eq(from, "tsv") and !explicit_width) {
        const columns: usize = if (getenv("COLUMNS")) |v| std.fmt.parseInt(usize, std.mem.trimStart(u8, std.mem.span(v), " \t\n\r"), 10) catch 0 else 0;
        if (columns == 0 or columns > 10000) { const width = table_columns(); if (width > 0) { try opts.append(c.a, "--terminal-width"); try opts.append(c.a, try std.fmt.allocPrint(c.a, "{d}", .{width})); } }
    }
    if (eq(from, "tsv") and vis and !auto) {
        try output(c, 2, "table: visual output may clip, pad, or sanitize cell contents\n");
        _ = try render(c, "", true, eq(destination, "ascii"), header, opts.items); return;
    }
    if (!auto) data = try input(c);
    const table = try c.parse(from, data, header, glyphs);
    const out = if (vis) blk: {
        try output(c, 2, "table: visual output may clip, pad, or sanitize cell contents\n");
        break :blk try render(c, try c.writeDelimited(table, false, true), false, eq(destination, "ascii"), table.header, opts.items);
    } else try c.write(table, destination);
    try output(c, 1, out);
}
export fn table_main(argc: c_int, argv: [*]const [*:0]const u8) c_int {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit();
    var c: core.Context = .{ .a = arena.allocator() };
    var args: std.ArrayList([]const u8) = .empty;
    var i: usize = 1; while (i < @as(usize, @intCast(argc))) : (i += 1) { args.append(c.a, std.mem.span(argv[i])) catch return 1; }
    run(&c, args.items) catch {
        _ = table_write(2, "table: ", 7); _ = table_write(2, c.message.ptr, c.message.len); _ = table_write(2, "\n", 1); return 1;
    };
    return 0;
}
