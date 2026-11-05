# Performance cases

The first growth case measures a complete CSV parse, intermediate encode and
decode, and CSV write. Expected time and retained data are linear in total
input bytes and fields. Its row-count sweep holds the three-column distribution
constant and validates every complete output against the input after each timed
operation. Each recorded sample sums 64 operations, with validation outside the
timed intervals. `./big_o` runs it on one core and a 12-core affinity set using the
pinned shared profiling engine. Measurements and accepted history live outside
the repository. A new machine is unbaselined until an owner reviews and accepts
a specific observation; an unbaselined result is not a performance pass.

`./mg` measures peak requested bytes, allocation count and residual requested
bytes during the same CSV/IR cycle, using Rust's global allocator. The input
fixture, operating-system allocations and C-library allocations are excluded;
this is not whole-process memory coverage. A canary checks allocation,
reallocation, retained bytes and cleanup accounting. Both probes are initially
unbaselined and are not yet part of `./test`.

These cases do not yet measure the other format paths, streaming behavior,
whole-process memory, or CLI startup independently of its adapter. The complete performance gate and an
independently reviewed baseline remain open work. Finite timing sweeps are not
a proof of asymptotic complexity.

The v2 sweep reported a shape failure at the first size transition. A separate
reverse-order diagnostic showed a smaller transition, suggesting allocator or
warmup state depends on sweep order. The v3 steady-state case warms the largest
fixture before every sweep and warms each size separately; it does not erase the
v2 failure or measure cold, single-command behavior. Cold-start and allocation
growth still require separate cases.

`./bm` currently measures a cold adapter process launching a fresh `table`
process, converting one CSV row to TSV and verifying its complete output before
announcing readiness. The reported startup interval includes the adapter and
child-process startup, conversion, verification and marker delivery; it is not
an isolated measurement of the executable's loader alone. Single-core and
12-core cases start five fresh processes each. Other fixed-workload timing cases
remain to be added.
