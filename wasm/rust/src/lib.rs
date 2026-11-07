//! Single-worker owned-buffer ABI; no caller-provided allocation/free pairs.
use std::sync::Mutex;
use table::Table;

#[repr(C)]
struct Column {
    index: u32,
    width: u32,
    alignment: u32,
    overflow: u32,
}
#[repr(C)]
struct Options {
    terminal: u32,
    flags: u32,
    decimal: u32,
    alignment: u32,
    overflow: u32,
    overrides: *const Column,
    count: usize,
}
#[repr(C)]
struct Slice {
    data: *const u8,
    len: usize,
}
#[repr(C)]
struct Row {
    cells: *const Slice,
    len: usize,
}
#[repr(C)]
struct Buffer {
    data: *mut u8,
    len: usize,
}
extern "C" {
    fn table_web_render(
        options: *const Options,
        rows: *const Row,
        count: usize,
        ascii: u32,
        header: u32,
        output: *mut Buffer,
    ) -> u32;
    fn table_web_render_free(output: *mut Buffer);
}
struct State {
    request: Vec<u8>,
    result: Vec<u8>,
    source: u32,
    rows: u32,
    columns: u32,
}
static STATE: Mutex<State> = Mutex::new(State {
    request: Vec::new(),
    result: Vec::new(),
    source: 0,
    rows: 0,
    columns: 0,
});
#[no_mangle]
pub extern "C" fn table_request(length: u32) -> usize {
    let mut s = STATE.lock().unwrap();
    s.result.clear();
    s.source = 0;
    s.rows = 0;
    s.columns = 0;
    s.request.clear();
    if length < 48 || length > 16 * 1024 * 1024 {
        return 0;
    }
    let extra = (length as usize).saturating_sub(s.request.len());
    if s.request.try_reserve(extra).is_err() {
        return 0;
    }
    s.request.resize(length as usize, 0);
    s.request.as_mut_ptr() as usize
}
#[no_mangle]
pub extern "C" fn table_result_ptr() -> usize {
    STATE.lock().unwrap().result.as_ptr() as usize
}
#[no_mangle]
pub extern "C" fn table_result_len() -> usize {
    STATE.lock().unwrap().result.len()
}
#[no_mangle]
pub extern "C" fn table_source() -> u32 {
    STATE.lock().unwrap().source
}
#[no_mangle]
pub extern "C" fn table_rows() -> u32 {
    STATE.lock().unwrap().rows
}
#[no_mangle]
pub extern "C" fn table_columns() -> u32 {
    STATE.lock().unwrap().columns
}
#[no_mangle]
pub extern "C" fn table_run() -> u32 {
    let mut s = STATE.lock().unwrap();
    s.source = 0;
    s.rows = 0;
    s.columns = 0;
    match execute(&s.request) {
        Ok((bytes, source, rows, columns)) => {
            s.result = bytes;
            s.source = source;
            s.rows = rows;
            s.columns = columns;
            0
        }
        Err(message) => {
            s.result = message.into_bytes();
            1
        }
    }
}
fn format(id: u32) -> Result<&'static str, String> {
    match id {
        1 => Ok("csv"),
        2 => Ok("tsv"),
        3 => Ok("markdown"),
        4 => Ok("ascii"),
        5 => Ok("ansi"),
        6 => Ok("ir"),
        _ => Err("invalid browser conversion request".into()),
    }
}
fn source_id(name: &str) -> u32 {
    (1..=6)
        .find(|id| format(*id).as_deref() == Ok(name))
        .unwrap_or(0)
}
fn execute(bytes: &[u8]) -> Result<(Vec<u8>, u32, u32, u32), String> {
    let bad = || "invalid browser conversion request".to_string();
    if bytes.len() < 48 {
        return Err(bad());
    }
    let word = |i: usize| u32::from_le_bytes(bytes[i * 4..i * 4 + 4].try_into().unwrap());
    if word(0) != 0x31574254
        || word(1) > 1
        || word(2) > 6
        || word(3) > 6
        || word(4) & !15 != 0
        || word(9) > 10000
        || word(11) > 8 * 1024 * 1024
    {
        return Err(bad());
    }
    let count = word(9) as usize;
    let glyph_len = word(10) as usize;
    let input_len = word(11) as usize;
    let start = 48 + count * 16;
    if start > bytes.len()
        || glyph_len > bytes.len() - start
        || input_len != bytes.len() - start - glyph_len
    {
        return Err(bad());
    }
    let columns: Vec<Column> = (0..count)
        .map(|i| Column {
            index: word(12 + i * 4),
            width: word(13 + i * 4),
            alignment: word(14 + i * 4),
            overflow: word(15 + i * 4),
        })
        .collect();
    let glyphs =
        std::str::from_utf8(&bytes[start..start + glyph_len]).map_err(|_| "input is not UTF-8")?;
    let glyphs = if glyphs.is_empty() {
        None
    } else {
        Some(glyphs)
    };
    let input = &bytes[start + glyph_len..];
    let source = if word(2) == 0 {
        table::detect::detect(input, glyphs).map_err(str::to_string)?
    } else {
        format(word(2))?
    };
    let text = || std::str::from_utf8(input).map_err(|_| "input is not UTF-8");
    let t: Table = match source {
        "csv" | "tsv" => table::parse_delimited(text()?, source == "csv", word(4) & 1 != 0),
        "markdown" => table::markdown::parse(text()?),
        "ascii" | "ansi" => table::visual_input::parse(text()?, source == "ansi", glyphs),
        "ir" => table::decode(input),
        _ => return Err(bad()),
    }
    .map_err(str::to_string)?;
    let nrows = t.rows.len() as u32;
    let ncols = t.header.iter().chain(&t.rows).next().map_or(0, Vec::len) as u32;
    if word(1) == 0 {
        return Ok((vec![], source_id(source), nrows, ncols));
    }
    if matches!(source, "ascii" | "ansi") && word(4) & 2 == 0 {
        return Err(
            "visual input is lossy; accept padding removal and possible prior clipping to continue"
                .into(),
        );
    }
    let destination = format(word(3))?;
    let output = match destination {
        "ir" => table::encode(&t).map_err(str::to_string)?,
        "csv" | "tsv" => table::write_delimited(&t, destination == "csv")
            .map_err(str::to_string)?
            .into_bytes(),
        "markdown" => table::markdown::write(&t)
            .map_err(str::to_string)?
            .into_bytes(),
        "ascii" | "ansi" => {
            let fields: Vec<Slice> = t
                .header
                .iter()
                .chain(&t.rows)
                .flat_map(|r| {
                    r.iter().map(|s| Slice {
                        data: s.as_ptr(),
                        len: s.len(),
                    })
                })
                .collect();
            let rows: Vec<Row> = (0..t.rows.len() + usize::from(t.header.is_some()))
                .map(|i| Row {
                    cells: fields.as_ptr().wrapping_add(i * ncols as usize),
                    len: ncols as usize,
                })
                .collect();
            let options = Options {
                terminal: word(5),
                flags: word(4),
                decimal: word(6),
                alignment: word(7),
                overflow: word(8),
                overrides: columns.as_ptr(),
                count,
            };
            let mut buffer = Buffer {
                data: std::ptr::null_mut(),
                len: 0,
            };
            // The shared renderer borrows rows/options synchronously. Its buffer
            // is copied before release by that renderer's matching allocator.
            let status = unsafe {
                table_web_render(
                    &options,
                    rows.as_ptr(),
                    rows.len(),
                    u32::from(destination == "ascii"),
                    u32::from(t.header.is_some()),
                    &mut buffer,
                )
            };
            if status != 0 {
                return Err("invalid display options or insufficient table width".into());
            }
            let result = if buffer.len == 0 {
                vec![]
            } else {
                unsafe { std::slice::from_raw_parts(buffer.data, buffer.len) }.to_vec()
            };
            unsafe { table_web_render_free(&mut buffer) };
            result
        }
        _ => return Err(bad()),
    };
    Ok((output, source_id(source), nrows, ncols))
}
