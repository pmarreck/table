use crate::Table;
use std::io::Write;
use std::process::{Command, Stdio};
use std::thread;

fn renderer_path() -> Result<std::path::PathBuf, String> {
    let executable = std::env::current_exe().map_err(|e| format!("cannot locate table executable: {e}"))?;
    let directory = executable.parent().ok_or("cannot locate executable directory")?;
    let root = directory.parent().ok_or("cannot locate installation directory")?;
    let name = if cfg!(windows) { "tsv-to-ansi-table.exe" } else { "tsv-to-ansi-table" };
    let adjacent = directory.join("libexec").join(name);
    if adjacent.is_file() { return Ok(adjacent); }
    let bundled = root.join("libexec").join(name);
    if bundled.is_file() { return Ok(bundled); }
    option_env!("TABLE_RENDERER").map(std::path::PathBuf::from).ok_or_else(|| "renderer not configured at build time".into())
}

/// The predecessor can consume TSV directly and stream fixed-width layouts.
pub fn render_tsv(ascii: bool, header: bool, options: &[String]) -> Result<(), String> {
    let renderer = renderer_path()?;
    let mut command = Command::new(renderer);
    if !header { command.arg("--no-header"); }
    if ascii { command.arg("--ascii"); }
    let status = command.args(options).stdin(Stdio::inherit()).stdout(Stdio::inherit())
        .stderr(Stdio::inherit()).status().map_err(|e| format!("cannot start renderer: {e}"))?;
    if status.success() { Ok(()) } else { Err(format!("renderer exited with {status}")) }
}

/// Delegate display layout and sanitization to the pinned predecessor renderer.
pub fn render(table: &Table, ascii: bool, options: &[String]) -> Result<Vec<u8>, String> {
    table.validate().map_err(str::to_owned)?;
    let renderer = renderer_path()?;
    let mut input = String::new();
    for row in table.header.iter().chain(&table.rows) {
        for (i, cell) in row.iter().enumerate() {
            if i > 0 { input.push('\t'); }
            // These bytes delimit the predecessor's input protocol. Other controls
            // remain in the field and are sanitized by its text-safety policy.
            for c in cell.chars() { input.push(if matches!(c, '\t' | '\r' | '\n') { '�' } else { c }); }
        }
        input.push('\n');
    }
    let mut command = Command::new(renderer);
    if table.header.is_none() { command.arg("--no-header"); }
    if ascii { command.arg("--ascii"); }
    command.args(options).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = command.spawn().map_err(|e| format!("cannot start renderer: {e}"))?;
    let mut stdin = child.stdin.take().ok_or("renderer stdin unavailable")?;
    let writer = thread::spawn(move || stdin.write_all(input.as_bytes()));
    let output = child.wait_with_output().map_err(|e| format!("renderer failed: {e}"))?;
    let write_result = writer.join().map_err(|_| "renderer input thread failed")?;
    if !output.status.success() { return Err(format!("renderer: {}", String::from_utf8_lossy(&output.stderr).trim())); }
    write_result.map_err(|e| format!("renderer input failed: {e}"))?;
    Ok(output.stdout)
}
