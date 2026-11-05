use crate::Table;

fn punctuation(c: char) -> bool { c.is_ascii_punctuation() }

// Parse raw table-cell source; Markdown inline markup is deliberately not evaluated.
fn cells(line: &str) -> Result<Vec<String>, &'static str> {
    let trimmed = line.trim();
    let body = trimmed.strip_prefix('|').unwrap_or(trimmed);
    let mut result = Vec::new();
    let mut cell = String::new();
    let mut chars = body.chars().peekable();
    let mut last_delimiter = false;
    while let Some(c) = chars.next() {
        match c {
            '\\' => {
                match chars.peek().copied() {
                    Some(next) if punctuation(next) => { chars.next(); cell.push(next); }
                    _ => cell.push('\\'),
                }
                last_delimiter = false;
            }
            '|' => { result.push(cell.trim().to_owned()); cell.clear(); last_delimiter = true; }
            _ => { cell.push(c); last_delimiter = false; }
        }
    }
    if !last_delimiter { result.push(cell.trim().to_owned()); }
    if result.is_empty() { return Err("Markdown row has no cells"); }
    Ok(result)
}

fn delimiter(cell: &str) -> bool {
    let inner = cell.strip_prefix(':').unwrap_or(cell);
    let inner = inner.strip_suffix(':').unwrap_or(inner);
    inner.len() >= 3 && inner.bytes().all(|b| b == b'-')
}

pub fn parse(input: &str) -> Result<Table, &'static str> {
    if input.is_empty() { return Err("Markdown requires a header and delimiter row"); }
    let mut lines = input.split_terminator('\n');
    fn clean(line: &str) -> Result<&str, &'static str> {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if line.contains('\r') || line.chars().any(|c| c.is_control() && c != '\t') { return Err("control character in Markdown row"); }
        Ok(line)
    }
    let header = cells(clean(lines.next().ok_or("missing Markdown header")?)?)?;
    let divider = cells(clean(lines.next().ok_or("missing Markdown delimiter row")?)?)?;
    if divider.len() != header.len() || !divider.iter().all(|c| delimiter(c)) { return Err("invalid Markdown delimiter row"); }
    let mut rows = Vec::new();
    for line in lines { rows.push(cells(clean(line)?)?); }
    let table = Table { header: Some(header), rows };
    table.validate()?;
    Ok(table)
}

pub fn write(table: &Table) -> Result<String, &'static str> {
    table.validate()?;
    let header = table.header.as_ref().ok_or("Markdown requires a header")?;
    let mut output = String::new();
    fn row(out: &mut String, row: &[String]) -> Result<(), &'static str> {
        out.push('|');
        for cell in row {
            if cell.trim() != cell || cell.chars().any(char::is_control) { return Err("Markdown cannot preserve edge whitespace or control characters in a cell"); }
            out.push(' ');
            for c in cell.chars() { if punctuation(c) { out.push('\\'); } out.push(c); }
            out.push_str(" |");
        }
        out.push('\n');
        Ok(())
    }
    row(&mut output, header)?;
    output.push('|');
    for _ in header { output.push_str(" --- |"); }
    output.push('\n');
    for r in &table.rows { row(&mut output, r)?; }
    Ok(output)
}
