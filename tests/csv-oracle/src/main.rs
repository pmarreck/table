//! Independent CSV reader. The oracle emits length-delimited fields and rows.
use std::io::{self, Write};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let stdin = io::stdin();
    let mut reader = csv::ReaderBuilder::new()
        .has_headers(false)
        .from_reader(stdin.lock());
    let mut out = io::BufWriter::new(io::stdout().lock());
    for record in reader.byte_records() {
        for field in &record? {
            write!(out, "F{}:", field.len())?;
            out.write_all(field)?;
        }
        out.write_all(b"R")?;
    }
    out.flush()?;
    Ok(())
}
