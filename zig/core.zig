const std = @import("std");
const A = std.mem.Allocator;
pub const Row = []const []const u8;
pub const Table = struct { rows: []const Row, header: bool };
extern fn table_next([*]const u8, usize, *i32) c_int;
extern fn table_white(i32) c_int;
extern fn table_safe(i32) c_int;
extern fn table_width([*]const u8, usize) i64;
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub const Context = struct {
    a: A,
    message: []const u8 = "conversion failed",
    pub fn bad(self: *Context, message: []const u8) error{Invalid} { self.message = message; return error.Invalid; }
    fn valid(self: *Context, t: Table) !Table {
        const width = if (t.rows.len > 0) t.rows[0].len else 0;
        for (t.rows) |row| {
            if (row.len == 0) return self.bad("rows must contain at least one field");
            if (row.len != width) return self.bad("ragged rows");
        }
        return t;
    }
    fn own(self: *Context, value: []const u8) ![]const u8 { return self.a.dupe(u8, value); }
    fn trim(self: *Context, s: []const u8, spaces_only: bool) ![]const u8 {
        var start: ?usize = null; var end: usize = 0; var i: usize = 0;
        while (i < s.len) {
            var cp: i32 = 0; const k = table_next(s[i..].ptr, s.len - i, &cp);
            if (k <= 0) return self.bad("input is not UTF-8");
            const n: usize = @intCast(k);
            const white = if (spaces_only) cp == 32 else table_white(cp) != 0;
            if (!white) { if (start == null) start = i; end = i + n; }
            i += n;
        }
        return if (start) |a| s[a..end] else s[0..0];
    }
    pub fn parse(self: *Context, format: []const u8, input: []const u8, header: bool, glyphs: ?[]const u8) !Table {
        if (eq(format, "ir")) return self.decode(input);
        if (!std.unicode.utf8ValidateSlice(input)) return self.bad("input is not UTF-8");
        if (eq(format, "csv") or eq(format, "tsv")) return self.delimited(input, eq(format, "csv"), header);
        if (eq(format, "markdown")) return self.markdown(input);
        return self.visual(input, eq(format, "ansi"), glyphs);
    }
    pub fn detect(self: *Context, input: []const u8, glyphs: ?[]const u8) ![]const u8 {
        if (std.mem.startsWith(u8, input, "\x1cT1")) { _ = try self.decode(input); return "ir"; }
        if (!std.unicode.utf8ValidateSlice(input)) return self.bad("input is not UTF-8");
        var candidates: std.ArrayList([]const u8) = .empty;
        if (self.markdown(input)) |_| { try candidates.append(self.a, "markdown"); } else |_| {}
        if (input.len > 0) {
            if (self.visual(input, false, glyphs)) |_| { try candidates.append(self.a, "ascii"); }
            else |_| { if (self.visual(input, true, glyphs)) |_| { try candidates.append(self.a, "ansi"); } else |_| {} }
        }
        for ([_][]const u8{ "csv", "tsv" }) |f| {
            if (self.delimited(input, eq(f, "csv"), false)) |t| { if (t.rows.len > 0 and t.rows[0].len > 1) try candidates.append(self.a, f); } else |_| {}
        }
        if (candidates.items.len == 0) return self.bad("cannot detect input format; specify --from (empty or single-column input needs an explicit format)");
        if (candidates.items.len > 1) return self.bad("ambiguous input format; specify --from csv, tsv, markdown, ir, ascii, or ansi");
        return candidates.items[0];
    }
    fn field(self: *Context, fields: *std.ArrayList([]const u8), bytes: *std.ArrayList(u8)) !void {
        try fields.append(self.a, try self.own(bytes.items)); bytes.clearRetainingCapacity();
    }
    fn delimited(self: *Context, s: []const u8, csv: bool, header: bool) !Table {
        var rows: std.ArrayList(Row) = .empty; var row: std.ArrayList([]const u8) = .empty; var field_bytes: std.ArrayList(u8) = .empty;
        var quoted = false; var closed = false; var started = false; var i: usize = 0;
        while (i < s.len) {
            const c = s[i]; i += 1;
            if (quoted) {
                if (c == '"') { if (i < s.len and s[i] == '"') { i += 1; try field_bytes.append(self.a, '"'); } else { quoted = false; closed = true; } }
                else try field_bytes.append(self.a, c);
            } else if (c == @as(u8, if (csv) ',' else '\t')) { try self.field(&row, &field_bytes); closed = false; started = true; }
            else if (c == '\n' or c == '\r') {
                if (c == '\r') { if (i == s.len or s[i] != '\n') return self.bad("bare carriage return outside quoted field"); i += 1; }
                try self.field(&row, &field_bytes); try rows.append(self.a, try row.toOwnedSlice(self.a)); closed = false; started = false;
            } else if (csv and c == '"') {
                if (field_bytes.items.len > 0 or closed) return self.bad("unexpected quote"); quoted = true; started = true;
            } else { if (closed) return self.bad("characters after closing quote"); try field_bytes.append(self.a, c); started = true; }
        }
        if (quoted) return self.bad("unterminated quoted field");
        if (started or closed) { try self.field(&row, &field_bytes); try rows.append(self.a, try row.toOwnedSlice(self.a)); }
        return self.valid(.{ .rows = rows.items, .header = header and rows.items.len > 0 });
    }
    fn decode(self: *Context, s: []const u8) !Table {
        if (!std.mem.startsWith(u8, s, "\x1cT1")) return self.bad("invalid intermediate signature");
        const header = s.len > 3 and s[3] == 29; var i: usize = if (header) 4 else 3;
        var rows: std.ArrayList(Row) = .empty; var row: std.ArrayList([]const u8) = .empty; var bytes: std.ArrayList(u8) = .empty; var started = false;
        while (true) {
            if (i == s.len) return self.bad("missing intermediate terminator");
            const b = s[i]; i += 1;
            switch (b) {
                28 => { if (started) return self.bad("unexpected structural marker"); if (i != s.len) return self.bad("trailing intermediate bytes"); break; },
                29 => return self.bad("unexpected structural marker"),
                30, 31 => {
                    if (!std.unicode.utf8ValidateSlice(bytes.items)) return self.bad("invalid UTF-8 field");
                    try self.field(&row, &bytes);
                    if (b == 30) { try rows.append(self.a, try row.toOwnedSlice(self.a)); started = false; } else started = true;
                },
                27 => {
                    if (i == s.len) return self.bad("incomplete escape");
                    const value: u8 = switch (s[i]) { 'e' => 27, 'f' => 28, 'g' => 29, 'r' => 30, 'u' => 31, else => return self.bad("invalid escape") };
                    i += 1; try bytes.append(self.a, value); started = true;
                },
                else => { try bytes.append(self.a, b); started = true; },
            }
        }
        if (header and rows.items.len == 0) return self.bad("header marker without row");
        return self.valid(.{ .rows = rows.items, .header = header });
    }
    pub fn write(self: *Context, t: Table, format: []const u8) ![]const u8 {
        _ = try self.valid(t);
        if (eq(format, "ir")) return @import("intermediate.zig").encode(self.a, .{ .header = if (t.header) t.rows[0] else null, .rows = if (t.header) t.rows[1..] else t.rows });
        if (eq(format, "markdown")) return self.writeMarkdown(t);
        return self.writeDelimited(t, eq(format, "csv"), false);
    }
    pub fn writeDelimited(self: *Context, t: Table, csv: bool, sanitize: bool) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        for (t.rows) |row| {
            for (row, 0..) |cell, j| {
                if (j > 0) try out.append(self.a, if (csv) ',' else '\t');
                const quoted = csv and std.mem.indexOfAny(u8, cell, ",\"\r\n") != null;
                if (!csv and !sanitize and std.mem.indexOfAny(u8, cell, "\t\r\n") != null) return self.bad("TSV cannot represent tabs or newlines in a field");
                if (quoted) try out.append(self.a, '"');
                for (cell) |b| {
                    if (sanitize and (b == 9 or b == 10 or b == 13)) { try out.appendSlice(self.a, "�"); continue; }
                    if (quoted and b == '"') try out.append(self.a, b);
                    try out.append(self.a, b);
                }
                if (quoted) try out.append(self.a, '"');
            }
            try out.append(self.a, '\n');
        }
        return out.items;
    }
    fn cells(self: *Context, line: []const u8) !Row {
        const trimmed = try self.trim(line, false); const body = if (std.mem.startsWith(u8, trimmed, "|")) trimmed[1..] else trimmed;
        var row: std.ArrayList([]const u8) = .empty; var bytes: std.ArrayList(u8) = .empty; var i: usize = 0; var last = false;
        while (i < body.len) {
            const b = body[i]; i += 1;
            switch (b) {
                '\\' => { if (i < body.len and std.ascii.isPunctuation(body[i])) { try bytes.append(self.a, body[i]); i += 1; } else try bytes.append(self.a, b); last = false; },
                '|' => { try row.append(self.a, try self.own(try self.trim(bytes.items, false))); bytes.clearRetainingCapacity(); last = true; },
                else => { try bytes.append(self.a, b); last = false; },
            }
        }
        if (!last) try row.append(self.a, try self.own(try self.trim(bytes.items, false)));
        if (row.items.len == 0) return self.bad("Markdown row has no cells");
        return row.items;
    }
    fn lines(self: *Context, s: []const u8) ![]const []const u8 {
        var result: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, s, '\n'); var offset: usize = 0;
        while (it.next()) |line| {
            if (offset == s.len and line.len == 0) break;
            try result.append(self.a, if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line); offset += line.len + 1;
        }
        return result.items;
    }
    fn control(s: []const u8, allow_tab: bool) bool {
        var i: usize = 0;
        while (i < s.len) { var cp: i32 = 0; const n = table_next(s[i..].ptr, s.len - i, &cp); if (n <= 0) return true;
            if ((cp < 32 and !(allow_tab and cp == 9)) or (cp >= 127 and cp <= 159)) return true;
            i += @intCast(n);
        }
        return false;
    }
    fn markdown(self: *Context, s: []const u8) !Table {
        if (s.len == 0) return self.bad("Markdown requires a header and delimiter row");
        const ls = try self.lines(s);
        if (control(ls[0], true)) return self.bad("control character in Markdown row");
        const header = try self.cells(ls[0]);
        if (ls.len < 2) return self.bad("missing Markdown delimiter row");
        if (control(ls[1], true)) return self.bad("control character in Markdown row");
        const divider = try self.cells(ls[1]);
        if (header.len != divider.len) return self.bad("invalid Markdown delimiter row");
        for (divider) |cell| {
            var b = cell; if (std.mem.startsWith(u8, b, ":")) b = b[1..]; if (std.mem.endsWith(u8, b, ":")) b = b[0 .. b.len - 1];
            if (b.len < 3) return self.bad("invalid Markdown delimiter row"); for (b) |c| { if (c != '-') return self.bad("invalid Markdown delimiter row"); }
        }
        var rows: std.ArrayList(Row) = .empty; try rows.append(self.a, header);
        for (ls[2..]) |line| { if (control(line, true)) return self.bad("control character in Markdown row"); try rows.append(self.a, try self.cells(line)); }
        return self.valid(.{ .rows = rows.items, .header = true });
    }
    fn writeMarkdown(self: *Context, t: Table) ![]const u8 {
        if (!t.header) return self.bad("Markdown requires a header"); var out: std.ArrayList(u8) = .empty;
        for (t.rows, 0..) |row, i| {
            try out.append(self.a, '|');
            for (row) |cell| {
                if (!eq(try self.trim(cell, false), cell) or control(cell, false)) return self.bad("Markdown cannot preserve edge whitespace or control characters in a cell");
                try out.append(self.a, ' '); for (cell) |c| { if (std.ascii.isPunctuation(c)) try out.append(self.a, '\\'); try out.append(self.a, c); }
                try out.appendSlice(self.a, " |");
            }
            try out.append(self.a, '\n');
            if (i == 0) { try out.append(self.a, '|'); for (row) |_| try out.appendSlice(self.a, " --- |"); try out.append(self.a, '\n'); }
        }
        return out.items;
    }
    fn scalars(self: *Context, s: []const u8) ![]const []const u8 {
        var result: std.ArrayList([]const u8) = .empty; var i: usize = 0;
        while (i < s.len) { var cp: i32 = 0; const n = table_next(s[i..].ptr, s.len - i, &cp); if (n <= 0) return self.bad("input is not UTF-8"); const k: usize = @intCast(n); try result.append(self.a, s[i .. i + k]); i += k; }
        return result.items;
    }
    fn safe(s: []const u8) bool {
        var i: usize = 0; while (i < s.len) { var cp: i32 = 0; const n = table_next(s[i..].ptr, s.len - i, &cp); if (n <= 0 or table_safe(cp) == 0) return false; i += @intCast(n); } return true;
    }
    fn border(self: *Context, line: []const u8, edges: []const []const u8, horizontal: []const u8) ![]const usize {
        const c = try self.scalars(line); if (c.len == 0 or !eq(c[0], edges[0])) return self.bad("invalid table border");
        var widths: std.ArrayList(usize) = .empty; var w: usize = 0;
        for (c[1..], 1..) |v, i| {
            if (eq(v, horizontal)) { w += 1; }
            else if ((eq(v, edges[1]) and i + 1 < c.len) or (eq(v, edges[2]) and i + 1 == c.len)) {
                if (w < 3) return self.bad("table border column is too narrow"); try widths.append(self.a, w); w = 0;
            } else return self.bad("invalid table border character");
        }
        if (!eq(c[c.len - 1], edges[2]) or w != 0 or widths.items.len == 0) return self.bad("incomplete table border");
        return widths.items;
    }
    fn visual(self: *Context, source: []const u8, ansi: bool, spec: ?[]const u8) !Table {
        var stripped: std.ArrayList(u8) = .empty; var i: usize = 0;
        while (i < source.len) {
            const b = source[i]; i += 1;
            if (b != 27) { try stripped.append(self.a, b); continue; }
            if (!ansi or i == source.len or source[i] != '[') return self.bad("unsupported terminal escape"); i += 1; var count: usize = 0;
            while (i < source.len and source[i] != 'm') { if (count >= 128 or !(std.ascii.isDigit(source[i]) or source[i] == ';')) return self.bad("unsupported terminal escape"); count += 1; i += 1; }
            if (i == source.len) return self.bad("unsupported terminal escape"); i += 1;
        }
        const s = stripped.items; if (s.len == 0) return .{ .rows = &.{}, .header = false };
        const ls = try self.lines(s); if (ls.len < 3) return self.bad("incomplete visual table");
        var g: []const []const u8 = undefined;
        if (spec) |value| {
            var parts: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, value, ',');
            while (it.next()) |part| {
                const c = try self.scalars(part);
                if (c.len != 1 or !safe(part) or !eq(try self.trim(part, false), part) or table_width(part.ptr, part.len) != 1) return self.bad("custom visual glyphs must be single, safe, one-cell non-whitespace characters other than comma");
                try parts.append(self.a, part);
            }
            if (parts.items.len != 11) return self.bad("custom visual glyphs require 11 comma-separated characters"); g = parts.items;
            for (g[0..9]) |v| { if (eq(v, g[9]) or eq(v, g[10])) return self.bad("custom line, vertical and junction glyphs must be distinct"); }
            if (eq(g[9], g[10])) return self.bad("custom line, vertical and junction glyphs must be distinct");
        } else if (ansi and std.mem.startsWith(u8, ls[0], "┌")) { g = &.{ "┌", "┬", "┐", "├", "┼", "┤", "└", "┴", "┘", "─", "│" }; }
        else if (std.mem.startsWith(u8, ls[0], "+")) { g = &.{ "+", "+", "+", "+", "+", "+", "+", "+", "+", "-", "|" }; }
        else return self.bad("unrecognized visual border; provide explicit glyphs");
        const widths = try self.border(ls[0], g[0..3], g[9]);
        if (!std.mem.eql(usize, widths, try self.border(ls[ls.len - 1], g[6..9], g[9]))) return self.bad("bottom border width mismatch");
        var rows: std.ArrayList(Row) = .empty; var header = false; var divider = false;
        for (ls[1 .. ls.len - 1]) |line| {
            if (std.mem.startsWith(u8, line, g[10])) {
                if (!std.mem.endsWith(u8, line, g[10]) or line.len < 2 * g[10].len) return self.bad("invalid table row boundary");
                const body = line[g[10].len .. line.len - g[10].len]; var row: std.ArrayList([]const u8) = .empty; var it = std.mem.splitSequence(u8, body, g[10]);
                while (it.next()) |field_bytes| try row.append(self.a, field_bytes);
                if (row.items.len != widths.len) return self.bad("ambiguous vertical delimiter in table row");
                for (row.items, 0..) |f, j| {
                    if (!safe(f)) return self.bad("control or unsafe format character in visual cell");
                    if (table_width(f.ptr, f.len) != @as(i64, @intCast(widths[j])) or !std.mem.startsWith(u8, f, " ") or !std.mem.endsWith(u8, f, " ")) return self.bad("table row does not match border widths");
                    row.items[j] = try self.trim(f, true);
                }
                try rows.append(self.a, row.items);
            } else {
                if (divider or rows.items.len != 1 or !std.mem.eql(usize, widths, try self.border(line, g[3..6], g[9]))) return self.bad("ambiguous or misplaced table separator");
                header = true; divider = true;
            }
        }
        if (rows.items.len == 0) return self.bad("visual table has no rows");
        return self.valid(.{ .rows = rows.items, .header = header });
    }
};
