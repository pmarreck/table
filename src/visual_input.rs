use crate::Table;
use utf8proc_sys::{utf8proc_category, utf8proc_charwidth, utf8proc_grapheme_break_stateful};

#[derive(Clone, Copy)]
struct Glyphs { top: [char; 3], middle: [char; 3], bottom: [char; 3], horizontal: char, vertical: char }
const ASCII: Glyphs = Glyphs { top: ['+', '+', '+'], middle: ['+', '+', '+'], bottom: ['+', '+', '+'], horizontal: '-', vertical: '|' };
const UNICODE: Glyphs = Glyphs { top: ['┌', '┬', '┐'], middle: ['├', '┼', '┤'], bottom: ['└', '┴', '┘'], horizontal: '─', vertical: '│' };

fn custom(spec: &str) -> Result<Glyphs, &'static str> {
    let chars: Vec<char> = spec.split(',').map(|part| {
        let mut c = part.chars();
        match (c.next(), c.next()) {
            (Some(ch), None) if ch != ',' && !ch.is_whitespace() && !unsafe_control(ch) && display_width(part) == 1 => Ok(ch),
            _ => Err("custom visual glyphs must be single, safe, one-cell non-whitespace characters other than comma"),
        }
    }).collect::<Result<_, _>>()?;
    if chars.len() != 11 { return Err("custom visual glyphs require 11 comma-separated characters"); }
    let glyphs = Glyphs { top: [chars[0], chars[1], chars[2]], middle: [chars[3], chars[4], chars[5]], bottom: [chars[6], chars[7], chars[8]], horizontal: chars[9], vertical: chars[10] };
    if chars[..9].contains(&glyphs.horizontal) || chars[..9].contains(&glyphs.vertical) || glyphs.horizontal == glyphs.vertical { return Err("custom line, vertical and junction glyphs must be distinct"); }
    Ok(glyphs)
}

fn strip_sgr(input: &str, ansi: bool) -> Result<String, &'static str> {
    let mut out = String::new();
    let mut chars = input.chars();
    while let Some(c) = chars.next() {
        if c != '\x1b' { out.push(c); continue; }
        if !ansi || chars.next() != Some('[') { return Err("unsupported terminal escape"); }
        let mut count = 0;
        loop {
            match chars.next() {
                Some('m') => break,
                Some(c) if (c.is_ascii_digit() || c == ';') && count < 128 => count += 1,
                _ => return Err("unsupported terminal escape"),
            }
        }
    }
    Ok(out)
}

fn border(line: &str, edges: [char; 3], horizontal: char) -> Result<Vec<usize>, &'static str> {
    let mut c = line.chars().peekable();
    if c.next() != Some(edges[0]) { return Err("invalid table border"); }
    let mut widths = Vec::new();
    let mut width = 0;
    while let Some(ch) = c.next() {
        if ch == horizontal { width += 1; }
        else if (ch == edges[1] && c.peek().is_some()) || (ch == edges[2] && c.peek().is_none()) {
            if width < 3 { return Err("table border column is too narrow"); }
            widths.push(width); width = 0;
        } else { return Err("invalid table border character"); }
    }
    if !line.ends_with(edges[2]) || width != 0 || widths.is_empty() { return Err("incomplete table border"); }
    Ok(widths)
}

fn data_row(line: &str, widths: &[usize], vertical: char) -> Result<Vec<String>, &'static str> {
    let line = line.strip_prefix(vertical).and_then(|s| s.strip_suffix(vertical)).ok_or("invalid table row boundary")?;
    let fields: Vec<&str> = line.split(vertical).collect();
    if fields.len() != widths.len() { return Err("ambiguous vertical delimiter in table row"); }
    let mut result = Vec::new();
    for (field, width) in fields.into_iter().zip(widths) {
        if field.chars().any(unsafe_control) { return Err("control or unsafe format character in visual cell"); }
        if display_width(field) != *width || !field.starts_with(' ') || !field.ends_with(' ') { return Err("table row does not match border widths"); }
        result.push(field.trim_matches(' ').to_owned());
    }
    Ok(result)
}

// Match the pinned predecessor's Unicode 17 segmentation and width policy.
fn unsafe_control(ch: char) -> bool {
    let cp = ch as i32;
    // char is a valid Unicode scalar accepted by utf8proc.
    let category = unsafe { utf8proc_category(cp).0 };
    matches!(category, 24..=26) || (category == 27 && cp != 0x200c && cp != 0x200d && !(0xe0020..=0xe007f).contains(&cp))
}

fn display_width(input: &str) -> usize {
    let (mut total, mut previous, mut state, mut cells) = (0, 0, 0, 0);
    for (offset, ch) in input.char_indices() {
        let cp = ch as i32;
        // Scalars are valid and the break state belongs to this ordered scan.
        unsafe {
            if offset > 0 && utf8proc_grapheme_break_stateful(previous, cp, &mut state) {
                total += cells;
                cells = 0;
            }
            let category = utf8proc_category(cp).0;
            let mut width = if matches!(category, 6 | 8 | 27) { 0 } else { utf8proc_charwidth(cp).max(0) as usize };
            if cp == 0xfe0f || cp == 0x20e3 || (0x1f1e6..=0x1f1ff).contains(&cp) { width = 2; }
            cells = cells.max(width);
        }
        previous = cp;
    }
    total + cells
}

pub fn parse(input: &str, ansi: bool, glyph_spec: Option<&str>) -> Result<Table, &'static str> {
    let input = strip_sgr(input, ansi)?;
    if input.is_empty() { return Ok(Table { header: None, rows: vec![] }); }
    let lines: Vec<&str> = input.split_terminator('\n').map(|line| line.strip_suffix('\r').unwrap_or(line)).collect();
    if lines.len() < 3 { return Err("incomplete visual table"); }
    let glyphs = match glyph_spec {
        Some(spec) => custom(spec)?,
        None if ansi && lines[0].starts_with(UNICODE.top[0]) => UNICODE,
        None if lines[0].starts_with(ASCII.top[0]) => ASCII,
        None => return Err("unrecognized visual border; provide explicit glyphs"),
    };
    let widths = border(lines[0], glyphs.top, glyphs.horizontal)?;
    if border(lines[lines.len() - 1], glyphs.bottom, glyphs.horizontal)? != widths { return Err("bottom border width mismatch"); }
    let mut rows = Vec::new();
    let mut header = None;
    let mut divider = false;
    for line in &lines[1..lines.len() - 1] {
        if line.starts_with(glyphs.vertical) {
            rows.push(data_row(line, &widths, glyphs.vertical)?);
        } else {
            if divider || rows.len() != 1 || border(line, glyphs.middle, glyphs.horizontal)? != widths { return Err("ambiguous or misplaced table separator"); }
            header = Some(rows.remove(0));
            divider = true;
        }
    }
    if header.is_none() && rows.is_empty() { return Err("visual table has no rows"); }
    let table = Table { header, rows };
    table.validate()?;
    Ok(table)
}
