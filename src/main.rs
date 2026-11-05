use std::io::{self, Read, Write};
use table::{decode, encode, parse_delimited, write_delimited};

fn run() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let mut from = None;
    let mut to = None;
    let mut header = true;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--from" => from = Some(args.next().ok_or("--from requires a value")?),
            "--to" => to = Some(args.next().ok_or("--to requires a value")?),
            "--header" => header = true,
            "--no-header" => header = false,
            "--about" => { println!("table {} — Convert tabular data; PF={}{}", env!("CARGO_PKG_VERSION"), platform(), variant()); return Ok(()); }
            "-h" | "--help" => { println!("Usage: table --from csv|tsv|markdown|ir --to csv|tsv|markdown|ir [--header|--no-header]\nReads stdin; first CSV/TSV row is a header by default. IR carries header metadata."); return Ok(()); }
            _ => return Err(format!("unknown option: {arg}")),
        }
    }
    let from = from.ok_or("--from is required")?;
    let to = to.ok_or("--to is required")?;
    if !["csv", "tsv", "markdown", "ir"].contains(&from.as_str()) || !["csv", "tsv", "markdown", "ir"].contains(&to.as_str()) { return Err("formats currently supported: csv, tsv, markdown, ir".into()); }
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).map_err(|e| e.to_string())?;
    let table = match from.as_str() {
        "ir" => decode(&input),
        "markdown" => table::markdown::parse(std::str::from_utf8(&input).map_err(|_| "input is not UTF-8")?),
        "csv" | "tsv" => parse_delimited(std::str::from_utf8(&input).map_err(|_| "input is not UTF-8")?, from == "csv", header),
        _ => unreachable!(),
    }.map_err(str::to_owned)?;
    let output = match to.as_str() {
        "ir" => encode(&table),
        "markdown" => table::markdown::write(&table).map(String::into_bytes),
        "csv" | "tsv" => write_delimited(&table, to == "csv").map(String::into_bytes),
        _ => unreachable!(),
    }.map_err(str::to_owned)?;
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
