# Roc ASCII input performance

Before the optimization in `a7c46aa`, the main measured cost was rebuilding every
row as a list of single-scalar strings, joining it back together and then
splitting it into cells. Unicode width calculation and safety checks added
further cost. Direct splitting and a guarded ASCII path now remove most of that
work for printable ASCII. These measurements describe these implementations and
fixtures, rather than a general comparison between languages.

## Experiment

The experiment used the ASCII-to-CSV fixture from `./bm`: 4,096 data rows,
two columns, seven display cells per padded field, plus a header and borders.
The complete CSV output was checked on every launch. Code came from `e98d1a8`,
with the pinned Roc compiler `2026-10-12-2664a27`, `--opt=speed`, and the
Linux x86-64 musl target. Diagnostic binaries were built by Nix derivation
overrides, retaining the compiler's check and test steps.

Each diagnostic changed only `roc/Model.roc`:

- **Byte width:** replace `Text.width(field)` with `field.to_utf8().len()`
  at the visual-cell width check. This is valid for the fixture's printable
  ASCII cells and deliberately unsuitable for general Unicode input.
- **Omit safety:** remove the `if !safe(field)` rejection block for visual
  cells. This deliberately removes a required input validation check.
- **Split rows directly:** replace the row's `scalar_text`, boundary checks
  and join/split with `parts = line.split_on(v)`, require its first and last
  parts to be empty, then use `parts.drop_first(1).drop_last(1)` as fields.
- **Combined:** apply all three changes together.

Original binaries ran before and after each series to check for drift. The
shared profiling engine enforced one-core and 12-core affinity settings.
Each case used five fresh child processes, a verified warmup outside timing,
adapter GC outside timing, complete-output validation, and binary SHA-256
checks. Timing includes launch, conversion, pipe transfer and exit. Seed was
`20261106`. Adapter startup, fixture generation, validation and hashing are
excluded. No hardware scheduling policy was changed.

## Results

Median milliseconds, from five samples per cell:

| Diagnostic | One core | 12-core affinity |
|---|---:|---:|
| Original, before | 38.69 | 39.17 |
| Byte width | 29.07 | 30.28 |
| Omit safety | 34.86 | 36.41 |
| Split rows directly | 21.64 | 24.60 |
| Combined | 7.89 | 6.80 |
| Original, after | 38.51 | 40.30 |

Direct row splitting removed about 17 ms in the one-core series. Byte width
removed about 10 ms, and omitting safety removed about 4 ms when tested
separately. Combined, the three changes removed about 31 ms. Differences are
end-to-end counterfactual measurements, not additive samples from a profiler;
compiler and allocation interactions can change their effects in combination.
The full CLI matrix measured Roc startup at 0.84 ms on one core, so startup
does not explain the roughly 39 ms ASCII conversion time.

In the original [Model.roc](https://github.com/pmarreck/table/blob/e98d1a8/roc/Model.roc), `scalar_text` constructs the row list;
`safe` queries Unicode categories per scalar. In [Text.roc](../roc/Text.roc),
`Text.width` materializes grapheme slices and computes width using category,
emoji and East Asian width properties. The Rust parser splits borrowed row
strings directly and scans widths through utf8proc. The experiments isolate
the cost of the Roc paths as a whole, without attributing time to individual
Unicode library functions or to the remaining work.

All 12 diagnostic observations were UNBASELINED with one attempt each. Raw
samples, source provenance and binary hashes remain in external profiling
history under project `table-roc-ascii-diagnosis`, with separate
`roc-ascii-csv-diagnostic-<variant>-v1` definitions. No baseline was accepted.
The disabled-check binaries remain diagnostic artifacts outside the repository
and are not published converters.

## Production optimization

Commit `a7c46aa` changes the production parser without removing required checks:

- Split each row on its vertical separator and validate the resulting boundary
  parts directly, avoiding the per-scalar string list and reconstruction.
- Check every field byte once for the inclusive range 32–126. Only those fields
  use their byte length as display width. Other fields retain the original
  Unicode safety and grapheme-width functions. All fields still require correct
  border widths and ASCII-space padding.
- Return escape-free input directly from the SGR filter. Inputs containing ESC
  retain the existing strict escape parser. UTF-8 validation remains mandatory.
- Reuse the field's byte list for validation and padding removal.

The shared suite now includes 858 direct parity cases. Added cases exhaust all
ASCII cell bytes in both visual modes, cover malformed and Unicode boundaries,
and place mixed Unicode after ASCII prefixes around common scan lengths. The
same acceptance suite runs against Rust, Zig, Roc and LuaJIT. A lone-separator
diagnostic mismatch found in Roc and LuaJIT was corrected to match Rust and Zig.

The full four-implementation benchmark matrix was refreshed using the same
fixture definitions, seed, pinned compiler and measurement adapter. All 48
observations were UNBASELINED with verified output and one attempt each. The
original Roc executable was measured before and after that matrix as a drift
control. Each cell below is median milliseconds for **one-core / 12-core
affinity**, from five fresh CLI processes:

| Workload | Original before | Optimized | Original recheck |
|---|---:|---:|---:|
| Startup | 0.658 / 1.017 | 0.690 / 0.976 | 0.674 / 0.903 |
| CSV → TSV | 4.828 / 5.154 | 4.895 / 5.321 | 6.196 / 5.202 |
| CSV → IR | 3.571 / 3.858 | 3.638 / 5.797 | 3.541 / 3.809 |
| Markdown → CSV | 10.189 / 10.475 | 10.034 / 10.381 | 9.954 / 10.851 |
| ASCII → CSV | 41.105 / 42.802 | 5.778 / 7.106 | 38.095 / 38.370 |
| Autodetect CSV | 9.673 / 9.668 | 8.937 / 10.000 | 9.205 / 10.225 |

ASCII conversion improved about 7.1× against the initial one-core measurement,
or about 6.6× against the original binary's recheck. The 12-core-affinity
measurements improved about 5.4–6.0×. Shared-host drift remains visible, and
affinity to 12 cores does not mean these algorithms use 12 threads. These are
end-to-end fixed-workload observations, not accepted historical baselines or
growth/memory qualification. All 72 observations from this batch remain in
external history; earlier observations and inconclusive results are preserved.

The 12-core-affinity CSV/IR observation increased from 3.858 ms to 5.797 ms in
that matrix. A first follow-up ran original IR, original ASCII, optimized IR and
optimized ASCII in each of three rounds:

| Round | Original IR | Optimized IR | Original ASCII | Optimized ASCII |
|---|---:|---:|---:|---:|
| 1 | 3.775 | 4.754 | 41.329 | 6.376 |
| 2 | 4.312 | 4.665 | 44.693 | 6.848 |
| 3 | 5.251 | 5.354 | 43.018 | 6.444 |

The optimized IR runs followed a much longer ASCII workload each time, creating
an ordering confound. These observations are retained, but do not isolate the
effect on IR performance. The original and optimized IR medians also drifted
within the series. No claim of improved IR performance follows from this pass.

A subsequent check separated the workloads and used the order original,
optimized, optimized, original, original, optimized, optimized, original for
each workload under 12-core affinity. The ranges below contain four
five-sample medians per binary; they are not confidence intervals:

| Workload | Original range, ms | Optimized range, ms |
|---|---:|---:|
| CSV → IR | 3.789–4.459 | 3.928–4.116 |
| ASCII → CSV | 37.723–38.939 | 6.108–6.186 |

The initial large IR gap did not repeat under this balanced ordering, and the
ASCII improvement persisted at roughly 6×. This does not establish an IR
speedup or exclude smaller effects under other conditions. All 16 observations
were UNBASELINED with verified output. One original-binary IR observation used
the engine's one permitted retry; all others used one attempt. Both follow-up
series remain in external history, and no baseline was accepted.

SIMD and compiler auto-vectorization were considered. This pass removes
intermediate lists and unnecessary Unicode work, reusing string-search and
split primitives under the pinned LLVM speed build. Inspection of the linked
x86-64 musl `memchr` showed bounded word-at-a-time scanning; that does not
establish which operations in the parser are vectorized. No manual ISA-specific
code was added. Further vectorization work is deferred pending another hot-path
profile.
