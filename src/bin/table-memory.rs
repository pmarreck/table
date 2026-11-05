//! Counts requested bytes through Rust's global allocator for a complete cycle.
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicBool, AtomicIsize, AtomicUsize, Ordering};
use table::{decode, encode, parse_delimited, write_delimited};

struct Tracked;
static ENABLED: AtomicBool = AtomicBool::new(false);
static LIVE: AtomicIsize = AtomicIsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);
static COUNT: AtomicUsize = AtomicUsize::new(0);

fn change(delta: isize) {
    let current = LIVE.fetch_add(delta, Ordering::SeqCst) + delta;
    if current > 0 { PEAK.fetch_max(current as usize, Ordering::SeqCst); }
}
unsafe impl GlobalAlloc for Tracked {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let result = System.alloc(layout);
        if !result.is_null() && ENABLED.load(Ordering::SeqCst) { change(layout.size() as isize); COUNT.fetch_add(1, Ordering::SeqCst); }
        result
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let result = System.alloc_zeroed(layout);
        if !result.is_null() && ENABLED.load(Ordering::SeqCst) { change(layout.size() as isize); COUNT.fetch_add(1, Ordering::SeqCst); }
        result
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        if ENABLED.load(Ordering::SeqCst) { change(-(layout.size() as isize)); }
        System.dealloc(ptr, layout);
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let result = System.realloc(ptr, layout, new_size);
        if !result.is_null() && ENABLED.load(Ordering::SeqCst) { change(new_size as isize - layout.size() as isize); COUNT.fetch_add(1, Ordering::SeqCst); }
        result
    }
}
#[global_allocator]
static ALLOCATOR: Tracked = Tracked;

fn cycle(input: &str, rows: usize) {
    let parsed = parse_delimited(input, true, false).unwrap();
    let encoded = encode(&parsed).unwrap();
    let decoded = decode(&encoded).unwrap();
    let output = write_delimited(&decoded, true).unwrap();
    assert_eq!(decoded.rows.len(), rows);
    assert_eq!(output, input);
}

fn accounting_canary() {
    let layout = Layout::from_size_align(8, 8).unwrap();
    LIVE.store(0, Ordering::SeqCst);
    PEAK.store(0, Ordering::SeqCst);
    COUNT.store(0, Ordering::SeqCst);
    ENABLED.store(true, Ordering::SeqCst);
    // These operations use valid layouts and every successful allocation is freed.
    let ptr = unsafe { std::alloc::alloc(layout) };
    assert!(!ptr.is_null());
    unsafe { std::ptr::write_volatile(ptr, 1); }
    let ptr = unsafe { std::alloc::realloc(ptr, layout, 16) };
    assert!(!ptr.is_null());
    let retained = LIVE.load(Ordering::SeqCst);
    let peak = PEAK.load(Ordering::SeqCst);
    let count = COUNT.load(Ordering::SeqCst);
    unsafe { std::alloc::dealloc(ptr, Layout::from_size_align(16, 8).unwrap()); }
    let residual = LIVE.load(Ordering::SeqCst);
    ENABLED.store(false, Ordering::SeqCst);
    assert_eq!((retained, peak, count, residual), (16, 16, 2, 0));
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    if args.len() == 2 && args[1] == "--self-test" { accounting_canary(); return; }
    assert_eq!(args.len(), 4, "expected case, sizes and seed");
    assert_eq!(args[1], "csv-ir-memory");
    let sizes: Vec<usize> = args[2].split(',').map(|s| s.parse().expect("invalid size")).collect();
    assert!(!sizes.is_empty() && sizes.iter().all(|&n| n > 0 && n <= 1_000_000));
    let mut rows = Vec::new();
    for n in sizes {
        let input = "alpha,42,\"x,y\"\n".repeat(n);
        for _ in 0..2 { cycle(&input, n); }
        let mut peaks = Vec::new();
        let mut allocations = Vec::new();
        let mut residuals = Vec::new();
        for _ in 0..3 {
            LIVE.store(0, Ordering::SeqCst);
            PEAK.store(0, Ordering::SeqCst);
            COUNT.store(0, Ordering::SeqCst);
            ENABLED.store(true, Ordering::SeqCst);
            cycle(&input, n);
            ENABLED.store(false, Ordering::SeqCst);
            let residual = LIVE.load(Ordering::SeqCst);
            assert!(residual >= 0, "allocator accounting underflow");
            peaks.push(PEAK.load(Ordering::SeqCst));
            allocations.push(COUNT.load(Ordering::SeqCst));
            residuals.push(residual);
        }
        let join = |v: Vec<String>| v.join(",");
        rows.push(format!("{{\"size\":{n},\"samples\":{{\"peak_bytes\":[{}],\"allocation_count\":[{}]}},\"residual_bytes\":[{}]}}", join(peaks.iter().map(usize::to_string).collect()), join(allocations.iter().map(usize::to_string).collect()), join(residuals.iter().map(isize::to_string).collect())));
    }
    println!("{{\"schema\":\"performance-measurement/v1\",\"correct\":true,\"build_mode\":\"release\",\"allocator_coverage\":\"Rust global allocator during CSV/IR cycle; input fixture, OS and C allocations excluded\",\"rows\":[{}]}}", rows.join(","));
}
