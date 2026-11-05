//! In-process growth probes; the shared runner supplies sizes and records history.
use std::hint::black_box;
use std::time::Instant;
use table::{decode, encode, parse_delimited, write_delimited};

#[derive(Clone, Copy)]
enum Case { CsvIr, Markdown, VisualInput }

#[cfg(unix)]
fn cpu_time() -> Option<u128> {
    let mut time = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // The output pointer is valid and the process CPU clock is monotonic.
    assert_eq!(unsafe { libc::clock_gettime(libc::CLOCK_PROCESS_CPUTIME_ID, &mut time) }, 0, "process CPU clock unavailable");
    assert!(time.tv_sec >= 0 && time.tv_nsec >= 0);
    Some(time.tv_sec as u128 * 1_000_000_000 + time.tv_nsec as u128)
}

#[cfg(not(unix))]
fn cpu_time() -> Option<u128> { None }

fn fixture(case: Case, rows: usize) -> (String, String) {
    match case {
        Case::CsvIr => {
            let source = "alpha,42,\"x,y\"\n".repeat(rows);
            (source.clone(), source)
        }
        Case::Markdown => {
            let source = "| name | count |\n| --- | --- |\n".to_owned() + &"| alpha | 42 |\n".repeat(rows);
            (source.clone(), source)
        }
        Case::VisualInput => {
            let source = "+-------+----+\n| name  | n  |\n+-------+----+\n".to_owned() + &"| alpha | 42 |\n".repeat(rows) + "+-------+----+\n";
            let expected = "name\tn\n".to_owned() + &"alpha\t42\n".repeat(rows);
            (source, expected)
        }
    }
}

fn roundtrip(case: Case, input: &str) -> (String, usize) {
    match case {
        Case::CsvIr => {
            let parsed = parse_delimited(black_box(input), true, false).unwrap();
            let wire = encode(black_box(&parsed)).unwrap();
            let restored = decode(black_box(&wire)).unwrap();
            let output = write_delimited(black_box(&restored), true).unwrap();
            (output, restored.rows.len())
        }
        Case::Markdown => {
            let table = table::markdown::parse(black_box(input)).unwrap();
            let output = table::markdown::write(black_box(&table)).unwrap();
            (output, table.rows.len())
        }
        Case::VisualInput => {
            let table = table::visual_input::parse(black_box(input), false, None).unwrap();
            let output = write_delimited(black_box(&table), false).unwrap();
            (output, table.rows.len())
        }
    }
}

fn correct(expected: &str, actual: &str, expected_rows: usize, actual_rows: usize) -> bool {
    expected == actual && expected_rows == actual_rows
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    assert_eq!(args.len(), 4, "expected case, sizes and seed");
    let case = match args[1].as_str() {
        "csv-ir-1" | "csv-ir-12" => Case::CsvIr,
        "markdown-1" | "markdown-12" => Case::Markdown,
        "visual-input-1" | "visual-input-12" => Case::VisualInput,
        _ => panic!("unknown performance case"),
    };
    let sizes: Vec<usize> = args[2].split(',').map(|s| s.parse().expect("invalid size")).collect();
    assert!(!sizes.is_empty() && sizes.iter().all(|&n| n > 0 && n <= 1_000_000));
    // Warm the actual path at the largest size before measuring any size so
    // allocator state does not depend on sweep order. This is steady-state work.
    let max = *sizes.iter().max().unwrap();
    let (warm_input, warm_expected) = fixture(case, max);
    for _ in 0..64 {
        let (output, rows) = roundtrip(case, &warm_input);
        assert!(correct(&warm_expected, &output, max, rows));
    }
    let mut rows = Vec::new();
    for n in sizes {
        let (input, expected) = fixture(case, n);
        let mut samples = Vec::new();
        let mut cpu_samples = Vec::new();
        for iteration in 0..8 {
            let mut elapsed = 0;
            let mut cpu_elapsed = 0;
            let mut cpu_available = false;
            for _ in 0..64 {
                let before_cpu = cpu_time();
                let start = Instant::now();
                let (output, rows) = roundtrip(case, &input);
                elapsed += start.elapsed().as_nanos();
                if let (Some(before), Some(after)) = (before_cpu, cpu_time()) {
                    cpu_elapsed += after.checked_sub(before).expect("process CPU clock moved backward");
                    cpu_available = true;
                }
                // Check all rows and bytes outside the timed region.
                assert!(correct(&expected, &output, n, rows));
            }
            if iteration >= 3 {
                assert!(elapsed > 0, "clock resolution insufficient");
                samples.push(elapsed);
                if cpu_available {
                    assert!(cpu_elapsed > 0, "process CPU clock resolution insufficient");
                    cpu_samples.push(cpu_elapsed);
                }
            }
        }
        let values = samples.iter().map(u128::to_string).collect::<Vec<_>>().join(",");
        let cpu = if cpu_samples.is_empty() { String::new() } else { format!(",\"cpu_ns\":[{}]", cpu_samples.iter().map(u128::to_string).collect::<Vec<_>>().join(",")) };
        rows.push(format!("{{\"size\":{n},\"samples\":{{\"wall_ns\":[{values}]{cpu}}}}}"));
    }
    println!("{{\"schema\":\"performance-measurement/v1\",\"correct\":true,\"build_mode\":\"release\",\"allocator_coverage\":\"not measured\",\"clock\":\"monotonic wall and process CPU where available; sums of 64 in-process operations\",\"warmup\":\"64 full operations at largest size, then 192 at each size\",\"rows\":[{}]}}", rows.join(","));
}

#[cfg(test)]
mod tests {
    use super::{correct, fixture, roundtrip, Case};
    #[test]
    fn oracle_rejects_missing_altered_and_extra_work() {
        let expected = "a,1\nb,2\n";
        assert!(correct(expected, expected, 2, 2));
        assert!(!correct(expected, "a,1\n", 2, 1));
        assert!(!correct(expected, "b,2\na,1\n", 2, 2));
        assert!(!correct(expected, "a,1\nb,2\nx,3\n", 2, 3));
        assert!(!correct(expected, expected, 2, 1));
    }
    #[test]
    fn fixtures_exercise_each_case() {
        for case in [Case::CsvIr, Case::Markdown, Case::VisualInput] {
            let (input, expected) = fixture(case, 3);
            let (actual, rows) = roundtrip(case, &input);
            assert!(correct(&expected, &actual, 3, rows));
        }
    }
}
