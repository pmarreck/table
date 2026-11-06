## Version 1 intermediate encoder. This module is not yet a complete CLI.
Intermediate :: [].{
	encode : [NoHeader, Header(List(Str))], List(List(Str)) -> Try(List(U8), [EmptyRow, RaggedRows])
	encode = |header, rows| {
		all_rows = match header {
			NoHeader => rows
			Header(row) => [row].concat(rows)
		}
		if !all_rows.all(|row| row.len() > 0) { return Err(EmptyRow) }
		width = match all_rows.first() {
			Ok(row) => row.len()
			Err(_) => 0
		}
		if !all_rows.all(|row| row.len() == width) { return Err(RaggedRows) }
		var $output = [28.U8, 84, 49]
		match header {
			NoHeader => {}
			Header(_) => { $output = $output.append(29) }
		}
		for row in all_rows {
			var $first = True
			for field in row {
				if !$first { $output = $output.append(31) }
				$first = False
				for byte in field.to_utf8() {
					code = match byte {
						27 => 101
						28 => 102
						29 => 103
						30 => 114
						31 => 117
						_ => 0
					}
					if code == 0 { $output = $output.append(byte) } else {
						$output = $output.append(27).append(code)
					}
				}
			}
			$output = $output.append(30)
		}
		Ok($output.append(28))
	}
}

expect Intermediate.encode(NoHeader, []) == Ok([28, 84, 49, 28])
expect Intermediate.encode(Header(["h", ""]), [["界", "x"]]) == Ok([28, 84, 49, 29, 104, 31, 30, 231, 149, 140, 31, 120, 30, 28])
expect Intermediate.encode(NoHeader, [[Str.from_utf8_lossy([0, 27, 28, 29, 30, 31])]]) == Ok([28, 84, 49, 0, 27, 101, 27, 102, 27, 103, 27, 114, 27, 117, 30, 28])
expect Intermediate.encode(Header([]), []) == Err(EmptyRow)
expect Intermediate.encode(Header(["a"]), [["a", "b"]]) == Err(RaggedRows)
