use std::io::{self, IsTerminal, Read, Write};
use table::{decode, encode, parse_delimited, write_delimited};

fn run() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let mut from = None;
    let mut to = None;
    let mut header = true;
    let mut visual_options = Vec::new();
    let mut explicit_color = false;
    let mut allow_lossy = false;
    let mut glyphs = None;
    while let Some(arg) = args.next() {
        let (key, inline) = match arg.split_once('=') { Some((key, value)) => (key, Some(value.to_owned())), None => (arg.as_str(), None) };
        match key {
            "--visual-glyphs" => {
                glyphs = Some(match inline { Some(v) => v, None => args.next().ok_or("--visual-glyphs requires a value")? });
            }
            "--allow-lossy" if inline.is_none() => allow_lossy = true,
            "--from" | "--to" => {
                let value = match inline { Some(v) => v, None => args.next().ok_or_else(|| format!("{key} requires a value"))? };
                if key == "--from" { from = Some(value); } else { to = Some(value); }
            }
            "--widths" | "--align" | "--overflow" | "--terminal-width" | "--color" | "--decimal-separator" => {
                let mut value = match inline { Some(v) => v, None => args.next().ok_or_else(|| format!("{key} requires a value"))? };
                if key == "--color" && value == "auto" { value = if auto_color() { "always" } else { "never" }.into(); }
                visual_options.push(key.to_owned()); visual_options.push(value);
                if key == "--color" { explicit_color = true; }
            }
            "--plain" if inline.is_none() => visual_options.push(key.to_owned()),
            "--header" if inline.is_none() => header = true,
            "--no-header" if inline.is_none() => header = false,
            "--about" if inline.is_none() => { println!("table {} — Convert tabular data; PF={}{}", env!("CARGO_PKG_VERSION"), platform(), variant()); return Ok(()); }
            "-h" | "--help" if inline.is_none() => { println!("Usage: table --from csv|tsv|markdown|ir|ascii|ansi --to csv|tsv|markdown|ir|ascii|ansi [--header|--no-header]\nVisual output: --widths, --align, --overflow, --terminal-width, --color, --plain, --decimal-separator."); return Ok(()); }
            _ => return Err(format!("unknown option: {arg}")),
        }
    }
    let from = from.ok_or("--from is required")?;
    let to = to.ok_or("--to is required")?;
    if !["csv", "tsv", "markdown", "ir", "ascii", "ansi"].contains(&from.as_str()) { return Err("input formats: csv, tsv, markdown, ir, ascii, ansi".into()); }
    if !["csv", "tsv", "markdown", "ir", "ascii", "ansi"].contains(&to.as_str()) { return Err("output formats: csv, tsv, markdown, ir, ascii, ansi".into()); }
    let visual = to == "ascii" || to == "ansi";
    let visual_input = from == "ascii" || from == "ansi";
    if visual_input && !allow_lossy { return Err("visual input is lossy; pass --allow-lossy to accept padding removal and possible prior clipping".into()); }
    if !visual_input && (allow_lossy || glyphs.is_some()) { return Err("--allow-lossy and --visual-glyphs require visual input".into()); }
    if !visual && !visual_options.is_empty() { return Err("display options require ASCII or ANSI output".into()); }
    if visual && !explicit_color {
        let color = auto_color();
        visual_options.extend(["--color".into(), if color { "always" } else { "never" }.into()]);
    }
    if from == "tsv" && visual {
        eprintln!("table: visual output may clip, pad, or sanitize cell contents");
        return table::visual::render_tsv(to == "ascii", header, &visual_options);
    }
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).map_err(|e| e.to_string())?;
    let table = match from.as_str() {
        "ir" => decode(&input),
        "ascii" | "ansi" => table::visual_input::parse(std::str::from_utf8(&input).map_err(|_| "input is not UTF-8")?, from == "ansi", glyphs.as_deref()),
        "markdown" => table::markdown::parse(std::str::from_utf8(&input).map_err(|_| "input is not UTF-8")?),
        "csv" | "tsv" => parse_delimited(std::str::from_utf8(&input).map_err(|_| "input is not UTF-8")?, from == "csv", header),
        _ => unreachable!(),
    }.map_err(str::to_owned)?;
    let output = match to.as_str() {
        "ir" => encode(&table).map_err(str::to_owned)?,
        "markdown" => table::markdown::write(&table).map(String::into_bytes).map_err(str::to_owned)?,
        "csv" | "tsv" => write_delimited(&table, to == "csv").map(String::into_bytes).map_err(str::to_owned)?,
        "ascii" | "ansi" => {
            eprintln!("table: visual output may clip, pad, or sanitize cell contents");
            table::visual::render(&table, to == "ascii", &visual_options)?
        }
        _ => unreachable!(),
    };
    io::stdout().write_all(&output).map_err(|e| e.to_string())
}
fn main() { if let Err(e) = run() { eprintln!("table: {e}"); std::process::exit(1); } }

fn platform() -> &'static str {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("linux", "x86_64") => "linux-amd64",
        ("linux", "aarch64") => "linux-arm64",
        ("macos", "aarch64") => "macos-arm64",
        ("windows", "x86_64") => "mswin-amd64",
        ("windows", "aarch64") => "mswin-arm64",
        _ => "unsupported",
    }
}
fn variant() -> &'static str {
    if cfg!(all(target_os = "linux", target_env = "gnu")) { " VARIANT=gnu" }
    else if cfg!(all(target_os = "linux", target_env = "musl")) { " VARIANT=musl" }
    else { "" }
}

fn auto_color() -> bool {
    io::stdout().is_terminal() && std::env::var_os("NO_COLOR").is_none() && std::env::var("TERM").ok().as_deref() != Some("dumb")
}
