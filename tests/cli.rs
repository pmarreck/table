use std::io::Write;
use std::process::{Command, Stdio};

fn invoke(args: &[&str], input: &[u8]) -> std::process::Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_table"))
        .args(args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped())
        .spawn().unwrap();
    if let Err(error) = child.stdin.take().unwrap().write_all(input) {
        // A command that rejects its arguments may exit before consuming stdin.
        assert_eq!(error.kind(), std::io::ErrorKind::BrokenPipe);
    }
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

#[test]
fn visual_output_matches_predecessor() {
    let input = b"Name\tCount\nAlice\t12\nBob\t2\n";
    let result = invoke(&["--from", "tsv", "--to", "ascii", "--color", "never", "--terminal-width", "80"], input);
    let mut predecessor = Command::new(env!("TABLE_RENDERER")).args(["--ascii", "--color", "never", "--terminal-width", "80"])
        .stdin(Stdio::piped()).stdout(Stdio::piped()).spawn().unwrap();
    predecessor.stdin.take().unwrap().write_all(input).unwrap();
    let expected = predecessor.wait_with_output().unwrap();
    assert!(expected.status.success());
    assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
    assert_eq!(result.stdout, expected.stdout);
}

#[test]
fn visual_output_sanitizes_untrusted_controls() {
    let result = invoke(&["--from", "csv", "--to", "ansi", "--color", "never"], b"name\n\"evil\x1b[31m\nnext\"\n");
    assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
    assert!(!result.stdout.contains(&0x1b));
    assert!(String::from_utf8(result.stdout).unwrap().contains('�'));
}

#[test]
fn visual_input_requires_explicit_lossy_acceptance() {
    let input = b"+------+---+\n| name | n |\n+------+---+\n| A    | 2 |\n+------+---+\n";
    let denied = invoke(&["--from", "ascii", "--to", "csv"], input);
    assert!(!denied.status.success());
    assert!(denied.stdout.is_empty());
    let accepted = invoke(&["--from", "ascii", "--to", "csv", "--allow-lossy"], input);
    assert!(accepted.status.success(), "{}", String::from_utf8_lossy(&accepted.stderr));
    assert_eq!(accepted.stdout, b"name,n\nA,2\n");
}

#[test]
fn unicode_visual_output_can_be_read_when_not_clipped() {
    let source = "name,value\n界,e\u{301}\n".as_bytes();
    let rendered = invoke(&["--from", "csv", "--to", "ansi", "--terminal-width", "80", "--color", "always"], source);
    assert!(rendered.status.success(), "{}", String::from_utf8_lossy(&rendered.stderr));
    assert!(rendered.stdout.contains(&0x1b));
    let restored = invoke(&["--from", "ansi", "--to", "csv", "--allow-lossy"], &rendered.stdout);
    assert!(restored.status.success(), "{}", String::from_utf8_lossy(&restored.stderr));
    assert_eq!(restored.stdout, source);
}

#[test]
fn fixed_width_tsv_visual_output_streams_before_eof() {
    use std::io::{BufRead, BufReader};
    use std::sync::mpsc;
    use std::time::Duration;
    let mut child = Command::new(env!("CARGO_BIN_EXE_table"))
        .args(["--from", "tsv", "--to", "ascii", "--widths", "5,5", "--color", "never"])
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let stdout = child.stdout.take().unwrap();
    let (tx, rx) = mpsc::channel();
    let reader = std::thread::spawn(move || {
        let mut line = String::new();
        let mut reader = BufReader::new(stdout);
        let result = loop {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => break Ok(0),
                Ok(n) if line.contains("Alice") && line.contains("12") => break Ok(n),
                Ok(_) => (),
                Err(error) => break Err(error),
            }
        };
        let _ = tx.send((result, line));
        let _ = std::io::copy(&mut reader, &mut std::io::sink());
    });
    stdin.write_all(b"Name\tCount\nAlice\t12\n").unwrap();
    let observed = rx.recv_timeout(Duration::from_secs(10));
    if observed.is_err() { child.kill().unwrap(); }
    drop(stdin);
    let status = child.wait().unwrap();
    reader.join().unwrap();
    let (result, line) = observed.expect("no output before EOF");
    assert!(result.unwrap() > 0);
    assert!(line.contains("Alice") && line.contains("12"));
    assert!(status.success());
}

#[test]
fn all_format_pairs_preserve_unambiguous_unclipped_data() {
    let csv = b"name,value\n\"A, B\",12\nZ,3\n";
    let formats = ["csv", "tsv", "markdown", "ir", "ascii", "ansi"];
    for from in formats {
        let initial = invoke(&["--from", "csv", "--to", from], csv);
        assert!(initial.status.success(), "csv -> {from}: {}", String::from_utf8_lossy(&initial.stderr));
        for to in formats {
            let mut args = vec!["--from", from, "--to", to];
            if from == "ascii" || from == "ansi" { args.push("--allow-lossy"); }
            let converted = invoke(&args, &initial.stdout);
            assert!(converted.status.success(), "{from} -> {to}: {}", String::from_utf8_lossy(&converted.stderr));
            let mut back = vec!["--from", to, "--to", "csv"];
            if to == "ascii" || to == "ansi" { back.push("--allow-lossy"); }
            let result = invoke(&back, &converted.stdout);
            assert!(result.status.success(), "{from} -> {to} -> csv: {}", String::from_utf8_lossy(&result.stderr));
            assert_eq!(result.stdout, csv, "{from} -> {to} -> csv");
        }
    }
}

#[cfg(unix)]
#[test]
fn buffered_visual_output_uses_parent_terminal_width() {
    use std::fs::File;
    use std::io::Read;
    use std::os::fd::FromRawFd;
    for (columns, explicit, expected) in [(None, None, 20), (Some("30"), None, 30), (Some("30"), Some("14"), 14), (Some("bad"), None, 20)] {
    let mut master = -1;
    let mut slave = -1;
    let mut size = libc::winsize { ws_row: 24, ws_col: 20, ws_xpixel: 0, ws_ypixel: 0 };
    // The output descriptors and initial size refer to private test PTY state.
    let rc = unsafe { libc::openpty(&mut master, &mut slave, std::ptr::null_mut(), std::ptr::null_mut(), &mut size) };
    assert_eq!(rc, 0, "could not create test PTY: {}", std::io::Error::last_os_error());
    let mut master = unsafe { File::from_raw_fd(master) };
    let slave = unsafe { File::from_raw_fd(slave) };
    let mut command = Command::new(env!("CARGO_BIN_EXE_table"));
    command.args(["--from", "csv", "--to", "ascii", "--color", "never"]);
    if let Some(value) = columns { command.env("COLUMNS", value); } else { command.env_remove("COLUMNS"); }
    if let Some(value) = explicit { command.args(["--terminal-width", value]); }
    let mut child = command.stdin(Stdio::piped()).stdout(Stdio::from(slave)).stderr(Stdio::piped()).spawn().unwrap();
    drop(command);
    let reader = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        // Linux PTY masters may return EIO, rather than EOF, after the slave closes.
        if let Err(error) = master.read_to_end(&mut bytes) { assert_eq!(error.raw_os_error(), Some(libc::EIO)); }
        bytes
    });
    child.stdin.take().unwrap().write_all(b"name\nabcdefghijklmnopqrstuvwxyz0123456789\n").unwrap();
    let result = child.wait_with_output().unwrap();
    assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
    let bytes = reader.join().unwrap();
    let text = String::from_utf8(bytes).unwrap();
    assert!(text.contains("..."), "expected clipping: {text:?}");
    let actual = text.lines().map(|line| line.trim_end_matches('\r').len()).max().unwrap();
    assert_eq!(actual, expected, "wrong terminal width: {text:?}");
    }
}

#[test]
fn installed_renderer_is_selected_relative_to_executable() {
    use std::fs;
    let root = std::env::temp_dir().join(format!("table-relocation-{}-{}", std::process::id(), std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
    fs::create_dir(&root).unwrap();
    struct Cleanup(std::path::PathBuf);
    impl Drop for Cleanup { fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); } }
    let _cleanup = Cleanup(root.clone());
    fs::create_dir(root.join("bin")).unwrap();
    fs::create_dir(root.join("libexec")).unwrap();
    let suffix = std::env::consts::EXE_SUFFIX;
    let binary = root.join("bin").join(format!("table{suffix}"));
    fs::copy(env!("CARGO_BIN_EXE_table"), &binary).unwrap();
    // A deliberately invalid bundled renderer must be selected ahead of the
    // valid Nix build-time fallback, causing an observable launch failure.
    fs::write(root.join("libexec").join(format!("tsv-to-ansi-table{suffix}")), b"not an executable").unwrap();
    let output = Command::new(binary).args(["--from", "csv", "--to", "ansi"])
        .stdin(Stdio::null()).output().unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("cannot start renderer"));
}
