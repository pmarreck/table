import Intermediate
import Text
import unicode.Scalar
import unicode.GeneralCategory

Model :: { rows : List(List(Str)), header : Bool }.{
	new : List(List(Str)), Bool -> Try(Model, [Invalid(Str)])
	new = |rows, header| {
		width = (rows.first() ?? []).len()
		if rows.any(|row| row.len() == 0) {
			return Err(Invalid("rows must contain at least one field"))
		}
		if !rows.all(|row| row.len() == width) {
			return Err(Invalid("ragged rows"))
		}
		Ok({ rows, header })
	}
	has_header : Model -> Bool
	has_header = |table| table.header
	columns : Model -> U64
	columns = |table| (table.rows.first() ?? []).len()
	parse : Str, List(U8), Bool, List(Str) -> Try(Model, [Invalid(Str)])
	parse = |format, bytes, header, glyphs| {
		if format == "ir" {
			return decode(bytes)
		}
		text = Str.from_utf8(bytes).map_err(|_| Invalid("input is not UTF-8"))?
		match format {
			"csv" | "tsv" => delimited(bytes, format == "csv", header)
			"markdown" => markdown(text)
			_ => visual(text, format == "ansi", glyphs)
		}
	}
	detect = |bytes, glyphs| {
		if bytes.take_first(3) == [28, 84, 49] {
			_ = decode(bytes)?
			return Ok("ir")
		}
		text = Str.from_utf8(bytes).map_err(|_| Invalid("input is not UTF-8"))?
		var $candidates = []
		if markdown(text).is_ok() {
			$candidates = $candidates.append("markdown")
		}
		if text != "" {
			if visual(text, False, glyphs).is_ok() {
				$candidates = $candidates.append("ascii")
			} else if visual(text, True, glyphs).is_ok() {
				$candidates = $candidates.append("ansi")
			}
		}
		for format in ["csv", "tsv"] {
			match delimited(bytes, format == "csv", False) {
				Ok(table) if columns(table) > 1 => {
					$candidates = $candidates.append(format)
				}
				_ => {}
			}
		}
		match $candidates {
			[format] => Ok(format)
			[] => Err(Invalid("cannot detect input format; specify --from (empty or single-column input needs an explicit format)"))
			_ => Err(Invalid("ambiguous input format; specify --from csv, tsv, markdown, ir, ascii, or ansi"))
		}
	}
	write : Model, Str -> Try(List(U8), [Invalid(Str)])
	write = |table, format| {
		match format {
			"ir" => Intermediate.encode(if table.header Header(table.rows.first() ?? []) else NoHeader, if table.header table.rows.drop_first(1) else table.rows).map_err(
				|err| match err {
					EmptyRow => Invalid("rows must contain at least one field")
					RaggedRows => Invalid("ragged rows")
				},
			)
			"markdown" => write_markdown(table).map_ok(Str.to_utf8)
			_ => write_delimited(table, format == "csv", False).map_ok(Str.to_utf8)
		}
	}
	render_input : Model -> Try(Str, [Invalid(Str)])
	render_input = |table| write_delimited(table, False, True)
}

decode = |bytes| {
	if bytes.take_first(3) != [28, 84, 49] {
		return Err(Invalid("invalid intermediate signature"))
	}
	header = bytes.get(3) == Ok(29)
	var $i = if header 4 else 3
	var $rows = []
	var $row = []
	var $field = []
	var $started = False
	var $done = False
	while !$done {
		byte = bytes.get($i).map_err(|_| Invalid("missing intermediate terminator"))?
		$i = $i + 1
		match byte {
			28 if !$started => {
				if $i != bytes.len() {
					return Err(Invalid("trailing intermediate bytes"))
				}
				$done = True
			}
			28 | 29 => return Err(Invalid("unexpected structural marker"))
			30 | 31 => {
				field = Str.from_utf8($field).map_err(|_| Invalid("invalid UTF-8 field"))?
				$row = $row.append(field)
				$field = []
				if byte == 30 {
					$rows = $rows.append($row)
					$row = []
					$started = False
				} else {
					$started = True
				}
			}
			27 => {
				code = bytes.get($i).map_err(|_| Invalid("incomplete escape"))?
				$i = $i + 1
				value = match code {
					101 => 27
					102 => 28
					103 => 29
					114 => 30
					117 => 31
					_ => return Err(Invalid("invalid escape"))
				}
				$field = $field.append(value)
				$started = True
			}
			_ => {
				$field = $field.append(byte)
				$started = True
			}
		}
	}
	if header and $rows.len() == 0 {
		return Err(Invalid("header marker without row"))
	}
	Model.new($rows, header)
}

delimited = |bytes, csv, header| {
	var $rows = []
	var $row = []
	var $field = []
	var $quoted = False
	var $closed = False
	var $started = False
	var $i = 0
	while $i < bytes.len() {
		c = bytes.get($i) ?? 0
		$i = $i + 1
		if $quoted {
			if c == 34 {
				if bytes.get($i) == Ok(34) {
					$i = $i + 1
					$field = $field.append(34)
				} else {
					$quoted = False
					$closed = True
				}
			} else {
				$field = $field.append(c)
			}
		} else if c == (if csv 44 else 9) {
			$row = $row.append(Str.from_utf8_lossy($field))
			$field = []
			$closed = False
			$started = True
		} else if c == 10 or c == 13 {
			if c == 13 {
				if bytes.get($i) != Ok(10) {
					return Err(Invalid("bare carriage return outside quoted field"))
				}
				$i = $i + 1
			}
			$row = $row.append(Str.from_utf8_lossy($field))
			$rows = $rows.append($row)
			$row = []
			$field = []
			$closed = False
			$started = False
		} else if csv and c == 34 {
			if $field.len() > 0 or $closed {
				return Err(Invalid("unexpected quote"))
			}
			$quoted = True
			$started = True
		} else {
			if $closed {
				return Err(Invalid("characters after closing quote"))
			}
			$field = $field.append(c)
			$started = True
		}
	}
	if $quoted {
		return Err(Invalid("unterminated quoted field"))
	}
	if $started or $closed {
		$rows = $rows.append($row.append(Str.from_utf8_lossy($field)))
	}
	Model.new($rows, header and $rows.len() > 0)
}

write_delimited : Model, Bool, Bool -> Try(Str, [Invalid(Str)])
write_delimited = |table, csv, sanitize| {
	var $out = []
	for row in table.rows {
		var $cells = []
		for original in row {
			value = if sanitize sanitize_text(original) else original
			if !csv and !sanitize and value.to_utf8().any(|b| b == 9 or b == 10 or b == 13) {
				return Err(Invalid("TSV cannot represent tabs or newlines in a field"))
			}
			encoded = if csv and value.to_utf8().any(|b| b == 44 or b == 34 or b == 13 or b == 10) {
				"\"${value.split_on("\"") |> Str.join_with("\"\"")}\""
			} else value
			$cells = $cells.append(encoded)
		}
		$out = $out.append(Str.join_with($cells, if csv "," else "\t").concat("\n"))
	}
	Ok(Str.join_with($out, ""))
}

sanitize_text = |s| s.split_on("\t") |> Str.join_with("�") |> Str.split_on("\r") |> Str.join_with("�") |> Str.split_on("\n") |> Str.join_with("�")

punctuation = |b| b >= 33 and b <= 126 and !(b >= 48 and b <= 57) and !(b >= 65 and b <= 90) and !(b >= 97 and b <= 122)

control = |s| s.to_utf8().any(|b| b < 32 or b == 127) or Scalar.iter(s).fold(
	False,
	|bad, v| {
		cp = Scalar.to_u32(v.scalar)
		bad or (cp >= 128 and cp <= 159)
	},
)

md_cells = |line| {
	trimmed = line.trim().to_utf8()
	bytes = if trimmed.first() == Ok(124) trimmed.drop_first(1) else trimmed
	var $row = []
	var $field = []
	var $i = 0
	var $last = False
	while $i < bytes.len() {
		b = bytes.get($i) ?? 0
		$i = $i + 1
		match b {
			92 => {
				next = bytes.get($i) ?? 0
				if punctuation(next) {
					$i = $i + 1
					$field = $field.append(next)
				} else {
					$field = $field.append(b)
				}
				$last = False
			}
			124 => {
				$row = $row.append(Str.from_utf8_lossy($field).trim())
				$field = []
				$last = True
			}
			_ => {
				$field = $field.append(b)
				$last = False
			}
		}
	}
	if !$last {
		$row = $row.append(Str.from_utf8_lossy($field).trim())
	}
	if $row.len() == 0 {
		return Err(Invalid("Markdown row has no cells"))
	}
	Ok($row)
}

lines = |s| {
	parts = s.split_on("\n")
	(if parts.last() == Ok("") parts.drop_last(1) else parts).map(
		|line| {
			bytes = line.to_utf8()
			if bytes.last() == Ok(13) Str.from_utf8_lossy(bytes.drop_last(1)) else line
		},
	)
}

markdown = |s| {
	if s == "" {
		return Err(Invalid("Markdown requires a header and delimiter row"))
	}
	ls = lines(s)
	clean = |line| if control(line.split_on("\t") |> Str.join_with("")) Err(Invalid("control character in Markdown row")) else Ok(line)
	header = md_cells(clean(ls.first().map_err(|_| Invalid("missing Markdown header"))?)?)?
	divider = md_cells(clean(ls.get(1).map_err(|_| Invalid("missing Markdown delimiter row"))?)?)?
	if divider.len() != header.len() or !divider.all(
		|s1| {
			b = s1.to_utf8()
			a = if b.first() == Ok(58) b.drop_first(1) else b
			c = if a.last() == Ok(58) a.drop_last(1) else a
			c.len() >= 3 and c.all(|v| v == 45)
		},
	) {
		return Err(Invalid("invalid Markdown delimiter row"))
	}
	var $rows = [header]
	for line in ls.drop_first(2) {
		$rows = $rows.append(md_cells(clean(line)?)?)
	}
	Model.new($rows, True)
}

write_markdown : Model -> Try(Str, [Invalid(Str)])
write_markdown = |table| {
	if !table.header {
		return Err(Invalid("Markdown requires a header"))
	}
	var $out = []
	var $first = True
	for row in table.rows {
		var $cells = []
		for cell in row {
			if cell.trim() != cell or control(cell) {
				return Err(Invalid("Markdown cannot preserve edge whitespace or control characters in a cell"))
			}
			var $bytes = []
			for b in cell.to_utf8() {
				if punctuation(b) {
					$bytes = $bytes.append(92)
				}
				$bytes = $bytes.append(b)
			}
			$cells = $cells.append(" ${Str.from_utf8_lossy($bytes)} |")
		}
		$out = $out.append("|${Str.join_with($cells, "")}\n")
		if $first {
			$out = $out.append("|${Str.join_with(row.map(|_| " --- |"), "")}\n")
			$first = False
		}
	}
	Ok(Str.join_with($out, ""))
}

safe = |s| Scalar.iter(s).fold(
	True,
	|ok, v| {
		cp = Scalar.to_u32(v.scalar)
		category = GeneralCategory.short(GeneralCategory.of_scalar(v.scalar))
		ok and category != "Cc" and category != "Zl" and category != "Zp" and !(category == "Cf" and cp != 0x200c and cp != 0x200d and !(cp >= 0xe0020 and cp <= 0xe007f))
	},
)

scalar_text = |s| Scalar.iter(s).fold([], |out, v| out.append(Scalar.to_str(v.scalar) ?? ""))

strip_sgr = |s, ansi| {
	b = s.to_utf8()
	var $i = 0
	var $out = []
	while $i < b.len() {
		c = b.get($i) ?? 0
		$i = $i + 1
		if c != 27 {
			$out = $out.append(c)
		} else {
			if !ansi or b.get($i) != Ok(91) {
				return Err(Invalid("unsupported terminal escape"))
			}
			$i = $i + 1
			var $count = 0
			while b.get($i) != Ok(109) {
				x = b.get($i) ?? 0
				if $count >= 128 or !(x >= 48 and x <= 57 or x == 59) {
					return Err(Invalid("unsupported terminal escape"))
				}
				$count = $count + 1
				$i = $i + 1
			}
			$i = $i + 1
		}
	}
	Ok(Str.from_utf8_lossy($out))
}

border = |line, edges, horizontal| {
	c = scalar_text(line)
	if c.first() != edges.get(0) {
		return Err(Invalid("invalid table border"))
	}
	var $widths = []
	var $w = 0
	for i in 1..<c.len() {
		x = c.get(i) ?? ""
		if x == horizontal {
			$w = $w + 1
		} else if (Ok(x) == edges.get(1) and i + 1 < c.len()) or (Ok(x) == edges.get(2) and i + 1 == c.len()) {
			if $w < 3 {
				return Err(Invalid("table border column is too narrow"))
			}
			$widths = $widths.append($w)
			$w = 0
		} else {
			return Err(Invalid("invalid table border character"))
		}
	}
	if c.last() != edges.get(2) or $w != 0 or $widths.len() == 0 {
		return Err(Invalid("incomplete table border"))
	}
	Ok($widths)
}

visual = |source, ansi, spec| {
	s = strip_sgr(source, ansi)?
	if s == "" {
		return Model.new([], False)
	}
	ls = lines(s)
	if ls.len() < 3 {
		return Err(Invalid("incomplete visual table"))
	}
	g = match spec {
		[value] => {
			parts = value.split_on(",")
			if !parts.all(|v| scalar_text(v).len() == 1 and v != "," and v.trim() == v and v != "" and safe(v) and Text.width(v) == 1) {
				return Err(Invalid("custom visual glyphs must be single, safe, one-cell non-whitespace characters other than comma"))
			}
			if parts.len() != 11 {
				return Err(Invalid("custom visual glyphs require 11 comma-separated characters"))
			}
			if parts.take_first(9).any(|v| Ok(v) == parts.get(9) or Ok(v) == parts.get(10)) or parts.get(9) == parts.get(10) {
				return Err(Invalid("custom line, vertical and junction glyphs must be distinct"))
			}
			parts
		}
		_ => {
			start = scalar_text(ls.first() ?? "").first() ?? ""
			if ansi and start == "┌" ["┌", "┬", "┐", "├", "┼", "┤", "└", "┴", "┘", "─", "│"] else if start == "+" ["+", "+", "+", "+", "+", "+", "+", "+", "+", "-", "|"] else return Err(Invalid("unrecognized visual border; provide explicit glyphs"))
		}
	}
	widths = border(ls.first() ?? "", g.take_first(3), g.get(9) ?? "")?
	if widths != border(ls.last() ?? "", g.drop_first(6).take_first(3), g.get(9) ?? "")? {
		return Err(Invalid("bottom border width mismatch"))
	}
	var $rows = []
	var $header = False
	var $divider = False
	v = g.get(10) ?? ""
	for line in ls.drop_first(1).drop_last(1) {
		c = scalar_text(line)
		if c.first() == Ok(v) {
			if c.last() != Ok(v) {
				return Err(Invalid("invalid table row boundary"))
			}
			fields = Str.join_with(c.drop_first(1).drop_last(1), "").split_on(v)
			if fields.len() != widths.len() {
				return Err(Invalid("ambiguous vertical delimiter in table row"))
			}
			var $row = []
			for i in 0..<fields.len() {
				field = fields.get(i) ?? ""
				if !safe(field) {
					return Err(Invalid("control or unsafe format character in visual cell"))
				}
				if Ok(Text.width(field)) != widths.get(i) or field.to_utf8().first() != Ok(32) or field.to_utf8().last() != Ok(32) {
					return Err(Invalid("table row does not match border widths"))
				}
				var $start = 0
				b = field.to_utf8()
				var $end = b.len()
				while $start < $end and b.get($start) == Ok(32) {
					$start = $start + 1
				}
				while $end > $start and b.get($end - 1) == Ok(32) {
					$end = $end - 1
				}
				$row = $row.append(Str.from_utf8_lossy(b.drop_first($start).take_first($end - $start)))
			}
			$rows = $rows.append($row)
		} else {
			if $divider or $rows.len() != 1 or widths != border(line, g.drop_first(3).take_first(3), g.get(9) ?? "")? {
				return Err(Invalid("ambiguous or misplaced table separator"))
			}
			$header = True
			$divider = True
		}
	}
	if $rows.len() == 0 {
		return Err(Invalid("visual table has no rows"))
	}
	Model.new($rows, $header)
}
