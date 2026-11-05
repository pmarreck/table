//! In-process growth probe; the shared runner supplies sizes and records history.
use std::hint::black_box;
use std::time::Instant;
use table::{decode, encode, parse_delimited, write_delimited};

fn roundtrip(input: &str) -> (String, usize) {
    let parsed = parse_delimited(black_box(input), true, false).unwrap();
    let wire = encode(black_box(&parsed)).unwrap();
    let restored = decode(black_box(&wire)).unwrap();
    let output = write_delimited(black_box(&restored), true).unwrap();
    (output, restored.rows.len())
}

fn correct(expected: &str, actual: &str, expected_rows: usize, actual_rows: usize) -> bool {
    expected == actual && expected_rows == actual_rows
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    assert_eq!(args.len(), 4, "expected case, sizes and seed");
    assert!(matches!(args[1].as_str(), "csv-ir-1" | "csv-ir-12"));
    let sizes: Vec<usize> = args[2].split(',').map(|s| s.parse().expect("invalid size")).collect();
    assert!(!sizes.is_empty() && sizes.iter().all(|&n| n > 0 && n <= 1_000_000));
    // Warm the actual path at the largest size before measuring any size so
    // allocator state does not depend on sweep order. This is steady-state work.
    let max = *sizes.iter().max().unwrap();
    let warm_input = "alpha,42,\"x,y\"\n".repeat(max);
    for _ in 0..64 {
        let (output, rows) = roundtrip(&warm_input);
        assert!(correct(&warm_input, &output, max, rows));
    }
    let mut rows = Vec::new();
    for n in sizes {
        let input = "alpha,42,\"x,y\"\n".repeat(n);
        let mut samples = Vec::new();
        for iteration in 0..8 {
            let mut elapsed = 0;
            for _ in 0..64 {
                let start = Instant::now();
                let (output, rows) = roundtrip(&input);
                elapsed += start.elapsed().as_nanos();
                // Check all rows and bytes outside the timed region.
                assert!(correct(&input, &output, n, rows));
            }
            if iteration >= 3 { samples.push(elapsed.max(1)); }
        }
        let values = samples.iter().map(u128::to_string).collect::<Vec<_>>().join(",");
        rows.push(format!("{{\"size\":{n},\"samples\":{{\"wall_ns\":[{values}]}}}}"));
    }
    println!("{{\"schema\":\"performance-measurement/v1\",\"correct\":true,\"build_mode\":\"release\",\"allocator_coverage\":\"not measured\",\"clock\":\"monotonic wall, sum of 64 in-process round trips\",\"warmup\":\"64 full round trips at largest size, then 192 at each size\",\"rows\":[{}]}}", rows.join(","));
}

#[cfg(test)]
mod tests {
    use super::correct;
    #[test]
    fn oracle_rejects_missing_altered_and_extra_work() {
        let expected = "a,1\nb,2\n";
        assert!(correct(expected, expected, 2, 2));
        assert!(!correct(expected, "a,1\n", 2, 1));
        assert!(!correct(expected, "b,2\na,1\n", 2, 2));
        assert!(!correct(expected, "a,1\nb,2\nx,3\n", 2, 3));
        assert!(!correct(expected, expected, 2, 1));
    }
}
