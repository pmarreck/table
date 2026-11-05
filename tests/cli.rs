use std::io::Write;
use std::process::{Command, Stdio};

fn invoke(args: &[&str], input: &[u8]) -> std::process::Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_table"))
        .args(args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped())
        .spawn().unwrap();
    child.stdin.take().unwrap().write_all(input).unwrap();
    child.wait_with_output().unwrap()
}

#[test]
fn csv_to_ir_to_tsv_preserves_fields() {
    let ir = invoke(&["--from", "csv", "--to", "ir"], b"name,value\n\"Doe, Jane\",\"a\"\"b\"\n");
    assert!(ir.status.success(), "{}", String::from_utf8_lossy(&ir.stderr));
    let tsv = invoke(&["--from", "ir", "--to", "tsv"], &ir.stdout);
    assert!(tsv.status.success(), "{}", String::from_utf8_lossy(&tsv.stderr));
    assert_eq!(tsv.stdout, b"name\tvalue\nDoe, Jane\ta\"b\n");
}

#[test]
fn unrepresentable_output_fails_without_partial_stdout() {
    let result = invoke(&["--from", "csv", "--to", "tsv"], b"head\n\"line\nline\"\n");
    assert!(!result.status.success());
    assert!(result.stdout.is_empty());
    assert!(!result.stderr.is_empty());
}

#[test]
fn about_describes_compiled_platform_not_environment() {
    let output = Command::new(env!("CARGO_BIN_EXE_table"))
        .arg("--about").env("PF", "wrong").env("VARIANT", "wrong").output().unwrap();
    assert!(output.status.success());
    let text = String::from_utf8(output.stdout).unwrap();
    assert_eq!(text.lines().count(), 1);
    assert!(text.contains("PF="));
    assert!(!text.contains("wrong"));
}
