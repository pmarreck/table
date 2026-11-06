//! Conservative format detection from complete input, independent of output.
pub fn detect(input: &[u8], glyphs: Option<&str>) -> Result<&'static str, &'static str> {
    if input.starts_with(b"\x1cT1") {
        crate::decode(input)?;
        return Ok("ir");
    }
    let text = std::str::from_utf8(input).map_err(|_| "input is not UTF-8")?;
    let mut candidates = Vec::new();
    if crate::markdown::parse(text).is_ok() { candidates.push("markdown"); }
    if !text.is_empty() {
        if crate::visual_input::parse(text, false, glyphs).is_ok() {
            candidates.push("ascii");
        } else if crate::visual_input::parse(text, true, glyphs).is_ok() {
            candidates.push("ansi");
        }
    }
    for (format, csv) in [("csv", true), ("tsv", false)] {
        if let Ok(table) = crate::parse_delimited(text, csv, false) {
            if table.rows.first().is_some_and(|row| row.len() > 1) {
                candidates.push(format);
            }
        }
    }
    match candidates.as_slice() {
        [format] => Ok(*format),
        [] => Err("cannot detect input format; specify --from (empty or single-column input needs an explicit format)"),
        _ => Err("ambiguous input format; specify --from csv, tsv, markdown, ir, ascii, or ansi"),
    }
}
