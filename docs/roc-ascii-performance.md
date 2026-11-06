# Roc ASCII input performance

The main measured cost is rebuilding every row as a list of single-scalar
strings, joining it back together and then splitting it into cells. Unicode
width calculation and safety checks add further cost. These are costs of the
current implementation and its dependencies; the measurements do not establish
a general comparison between languages.

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

In [Model.roc](../roc/Model.roc), `scalar_text` constructs the row list;
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

## Optimization direction

Direct row splitting is the first candidate to qualify against the full
shared suite. A guarded printable-ASCII fast path could then avoid general
Unicode property and grapheme work, retaining the Unicode fallback and all
control-character rejection rules. These optimizations have not been shipped.

SIMD and compiler auto-vectorization were considered. Eliminating intermediate
lists and unnecessary Unicode work takes priority based on these measurements;
vectorization work is deferred. No generated-code inspection was performed,
and the results make no claim that the compiler missed vectorization.
