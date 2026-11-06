//! Table model and the versioned, escaped intermediate representation.

const FS: u8 = 0x1c;
const GS: u8 = 0x1d;
const RS: u8 = 0x1e;
const US: u8 = 0x1f;
const ESC: u8 = 0x1b;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Table {
    pub header: Option<Vec<String>>,
    pub rows: Vec<Vec<String>>,
}

impl Table {
    pub fn validate(&self) -> Result<(), &'static str> {
        let mut width = None;
        for row in self.header.iter().chain(&self.rows) {
            if row.is_empty() { return Err("rows must contain at least one field"); }
            match width {
                None => width = Some(row.len()),
                Some(n) if n != row.len() => return Err("ragged rows"),
                Some(_) => (),
            }
        }
        Ok(())
    }
}

pub fn encode(table: &Table) -> Result<Vec<u8>, &'static str> {
    table.validate()?;
    let mut out = vec![FS, b'T', b'1'];
    if let Some(header) = &table.header {
        out.push(GS);
        encode_row(header, &mut out);
    }
    for row in &table.rows { encode_row(row, &mut out); }
    out.push(FS);
    Ok(out)
}

fn encode_row(row: &[String], out: &mut Vec<u8>) {
    for (i, cell) in row.iter().enumerate() {
        if i != 0 { out.push(US); }
        for &b in cell.as_bytes() {
            let escaped = match b {
                ESC => Some(b'e'), FS => Some(b'f'), GS => Some(b'g'),
                RS => Some(b'r'), US => Some(b'u'), _ => None,
            };
            if let Some(code) = escaped { out.push(ESC); out.push(code); }
            else { out.push(b); }
        }
    }
    out.push(RS);
}

pub fn decode(bytes: &[u8]) -> Result<Table, &'static str> {
    if !bytes.starts_with(&[FS, b'T', b'1']) { return Err("invalid intermediate signature"); }
    let mut i = 3;
    let has_header = bytes.get(i) == Some(&GS);
    if has_header { i += 1; }
    let mut rows = Vec::new();
    let mut row = Vec::new();
    let mut field = Vec::new();
    let mut started = false;
    loop {
        let b = *bytes.get(i).ok_or("missing intermediate terminator")?;
        i += 1;
        match b {
            FS if !started => {
                if i != bytes.len() { return Err("trailing intermediate bytes"); }
                break;
            }
            FS | GS => return Err("unexpected structural marker"),
            US | RS => {
                row.push(String::from_utf8(std::mem::take(&mut field)).map_err(|_| "invalid UTF-8 field")?);
                if b == RS { rows.push(std::mem::take(&mut row)); started = false; }
                else { started = true; }
            }
            ESC => {
                let code = *bytes.get(i).ok_or("incomplete escape")?;
                i += 1;
                field.push(match code { b'e' => ESC, b'f' => FS, b'g' => GS, b'r' => RS, b'u' => US, _ => return Err("invalid escape") });
                started = true;
            }
            _ => { field.push(b); started = true; }
        }
    }
    let header = if has_header {
        if rows.is_empty() { return Err("header marker without row"); }
        Some(rows.remove(0))
    } else { None };
    let table = Table { header, rows };
    table.validate()?;
    Ok(table)
}

/// Parse CSV with RFC-style quoting, or unquoted TSV. Both accept LF and CRLF.
pub fn parse_delimited(input: &str, csv: bool, header: bool) -> Result<Table, &'static str> {
    let mut rows = Vec::new();
    let mut row = Vec::new();
    let mut field = String::new();
    let mut chars = input.chars().peekable();
    let mut quoted = false;
    let mut closed = false;
    let mut started = false;
    while let Some(c) = chars.next() {
        if quoted {
            if c == '"' {
                if chars.peek() == Some(&'"') { chars.next(); field.push('"'); }
                else { quoted = false; closed = true; }
            } else { field.push(c); }
            continue;
        }
        let sep = if csv { ',' } else { '\t' };
        if c == sep {
            row.push(std::mem::take(&mut field)); closed = false; started = true;
        } else if c == '\n' || c == '\r' {
            if c == '\r' && chars.next() != Some('\n') { return Err("bare carriage return outside quoted field"); }
            row.push(std::mem::take(&mut field)); rows.push(std::mem::take(&mut row));
            closed = false; started = false;
        } else if csv && c == '"' {
            if !field.is_empty() || closed { return Err("unexpected quote"); }
            quoted = true; started = true;
        } else {
            if closed { return Err("characters after closing quote"); }
            field.push(c); started = true;
        }
    }
    if quoted { return Err("unterminated quoted field"); }
    if started || closed { row.push(field); rows.push(row); }
    let header = if header && !rows.is_empty() { Some(rows.remove(0)) } else { None };
    let table = Table { header, rows };
    table.validate()?;
    Ok(table)
}

pub fn write_delimited(table: &Table, csv: bool) -> Result<String, &'static str> {
    table.validate()?;
    let mut out = String::new();
    for row in table.header.iter().chain(&table.rows) {
        for (i, cell) in row.iter().enumerate() {
            if i != 0 { out.push(if csv { ',' } else { '\t' }); }
            if csv && cell.contains([',', '"', '\r', '\n']) {
                out.push('"');
                for c in cell.chars() { if c == '"' { out.push('"'); } out.push(c); }
                out.push('"');
            } else if !csv && cell.contains(['\t', '\r', '\n']) {
                return Err("TSV cannot represent tabs or newlines in a field");
            } else { out.push_str(cell); }
        }
        out.push('\n');
    }
    Ok(out)
}

pub mod markdown;
pub mod detect;
pub mod visual;
pub mod visual_input;
