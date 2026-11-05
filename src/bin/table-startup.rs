//! Measure adapter startup plus a fresh CLI conversion to its first verified output.
use std::io::{self, Write};
use std::process::{Command, Stdio};

fn valid(output: &[u8]) -> bool { output == b"name\tcount\nAlice\t2\n" }

fn main() {
    let args: Vec<_> = std::env::args().collect();
    assert_eq!(args.len(), 4, "expected case, size and seed");
    assert!(matches!(args[1].as_str(), "startup-1" | "startup-12"));
    assert_eq!(args[2], "1");
    let current = std::env::current_exe().expect("cannot locate startup adapter");
    let root = current.parent().and_then(std::path::Path::parent).expect("cannot locate package");
    let binary = root.join("bin").join(format!("table{}", std::env::consts::EXE_SUFFIX));
    let mut child = Command::new(binary).args(["--from", "csv", "--to", "tsv"])
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().expect("cannot start table");
    child.stdin.take().unwrap().write_all(b"name,count\nAlice,2\n").unwrap();
    let result = child.wait_with_output().expect("cannot wait for table");
    assert!(result.status.success(), "table failed: {}", String::from_utf8_lossy(&result.stderr));
    assert!(valid(&result.stdout), "table produced unexpected output");
    println!("performance-ready/v1");
    io::stdout().flush().unwrap();
    println!("{{\"schema\":\"performance-measurement/v1\",\"correct\":true,\"build_mode\":\"release\",\"phase\":\"adapter start through fresh table conversion\",\"rows\":[{{\"size\":1,\"samples\":{{}}}}]}}");
}

#[cfg(test)]
mod tests {
    use super::valid;
    #[test]
    fn oracle_rejects_missing_reordered_or_extra_output() {
        assert!(valid(b"name\tcount\nAlice\t2\n"));
        assert!(!valid(b"name\tcount\n"));
        assert!(!valid(b"Alice\t2\nname\tcount\n"));
        assert!(!valid(b"name\tcount\nAlice\t2\nextra\n"));
    }
}
