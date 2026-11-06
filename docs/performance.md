# Performance cases

`./bm` declares the same six CLI workloads for Rust, Zig, Roc and LuaJIT: one-row
startup, CSV to TSV, CSV to IR, Markdown to CSV, ASCII input to CSV, and CSV
autodetection. The conversion cases use 4,096 rows. Each case launches five
fresh processes and records monotonic wall time from launch through collected
output and exit, excluding output verification. Startup uses the same interval
with one row; LuaJIT adapter startup is excluded. Process startup is fresh,
but filesystem caches are not flushed. Each complete output is checked against
an independently constructed fixture. The child binary's SHA-256 is recorded
and checked throughout each invocation. Timings still include process scheduling
and pipe transfer. The supplied binaries must be optimized builds.

The default suite requires all four complete CLIs. Missing implementations
are a preflight error, never a skipped or passing case. Use
`./bm --implementation rust` for an explicit subset, or supply absolute executable
paths through `TABLE_BENCHMARK_RUST`, `TABLE_BENCHMARK_ZIG`,
`TABLE_BENCHMARK_ROC` and `TABLE_BENCHMARK_LUAJIT`. Existing implementation names do not establish that their
ports are complete. Historical comparisons are separate per implementation,
workload and core count; these are fixed-workload observations, not memory or
growth gates. Source and toolchain provenance still needs review when accepting
externally supplied executables.

The autodetection case detects CSV, parses it and writes canonical CSV with a
complete-output oracle. Expected time is linear in bytes and fields for this
fixture family. It does not measure every detection candidate or ambiguity
path; its observations and baseline remain pending.

The growth cases measure CSV parse, intermediate encode and decode, and CSV
write; Markdown parse and write; and visual-table parse and TSV write. Expected
time and retained data are linear in total input bytes and fields. Each row-count
sweep holds its column distribution constant and validates every complete output
against a separately constructed expected result after each timed operation.
Each recorded sample sums 64 operations, with validation outside the timed
intervals. `./big_o` runs each case on one core and a 12-core affinity set using
the pinned shared profiling engine. Measurements and accepted history live
outside the repository. A new machine is unbaselined until an owner reviews and
accepts a specific observation; an unbaselined result is not a performance pass.
The correctness suite compares the adapter's declared case names against the
manifest and requires both affinity configurations for each. This detects
missing manifest entries for declared cases, not unmeasured code paths.

`./mg` measures peak requested bytes, allocation count and residual requested
bytes during the same CSV/IR cycle, using Rust's global allocator. The input
fixture, operating-system allocations and C-library allocations are excluded;
this is not whole-process memory coverage. A canary checks allocation,
reallocation, retained bytes and cleanup accounting. Both probes are initially
unbaselined and are not yet part of `./test`.

These cases do not yet measure terminal rendering, streaming behavior,
whole-process memory, or CLI startup independently of its adapter. The complete performance gate and an
independently reviewed baseline remain open work. Finite timing sweeps are not
a proof of asymptotic complexity.

The v2 sweep reported a shape failure at the first size transition. A separate
reverse-order diagnostic showed a smaller transition, suggesting allocator or
warmup state depends on sweep order. The v3 steady-state case warms the largest
fixture before every sweep and warms each size separately; it does not erase the
v2 failure or measure cold, single-command behavior. The v4 CSV case retains
that warmup after the adapter was extended to other formats. Cold-start and
allocation growth are measured separately as described above, with their own
coverage limits.

The historical `startup-1` and `startup-12` cases in the manifest measure a cold
adapter launching a fresh `table` process and announcing readiness after verified
output. They include adapter startup and marker delivery. The current `./bm`
selects the implementation-prefixed cases described above, which exclude adapter
startup. Their definitions and histories remain separate.

The v1 visual-input case reported a shape failure in the 12-core-affinity run,
with uneven samples at 4,096 rows. A reverse-order diagnostic had a smaller
transition; neither observation establishes the cause. The v2 cases also
record process CPU time on Unix, outside the wall-clock interval boundaries, to
help distinguish computation from scheduling delay. Wall time remains the gated
metric. The v1 failure remains part of the measurement history.

On 2026-11-06, all 12 Rust CLI cases were measured at commit `5942f07`.
Each completed with verified output and an `UNBASELINED` verdict; no baseline
was accepted. The full-suite preflight correctly refused the missing complete
Zig and Roc executables. These observations do not establish relative speed
among the implementations.

At source commit `50e6ab6`, all 48 CLI cases were measured with seed `20261106`.
The same expected-output fixtures were verified for all four implementations.
All observations are UNBASELINED. Rust and Roc CSV/TSV 12-core cases used the
runner's one permitted retry. Selected five-sample medians are published in the
README without private host or filesystem metadata; immutable observations and
retry diagnostics remain in external history.

The LuaJIT/libuv adapter replaces the original adapter under separate
`v2-luajit-adapter` case definitions. It reuses the pinned profiling engine's
process runner. Fixture construction, complete-output validation and SHA-256
checks remain outside each timed interval. Earlier observations retain their
original definitions and are not compared across this measurement change.

At code commit `e98d1a8`, the complete 48-case suite was rerun with this adapter
and seed `20261106`. Adapter warmup and two full adapter GC collections occur
outside each timed child launch. There were 45 UNBASELINED cases and three
INCONCLUSIVE cases: one-core Zig startup, CSV/TSV and CSV/IR. Each inconclusive
case exhausted its one permitted retry because of sample variation; the other
cases used one attempt. Every measured output passed verification. The README
publishes medians only for the valid observations. Exit status 3 reports these
unbaselined/inconclusive outcomes, rather than a passed performance gate.

The [Roc ASCII diagnosis](roc-ascii-performance.md) uses separate diagnostic
definitions and a separate external history project. Disabled-check experiments
are not production candidates or accepted performance baselines.
