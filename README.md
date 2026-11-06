# table

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Ftable.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

Convert tables between CSV, TSV, Markdown, ASCII and ANSI terminal tables.
`table` detects the input format when it can and reports ambiguity when it
cannot. A [versioned intermediate format](docs/intermediate-format.md) preserves
cell contents and header presence between conversions.

```sh
printf 'name,count\nAlice,2\n' | table --to markdown
# | name | count |
# | --- | --- |
# | Alice | 2 |
```

Rust, Zig, Roc and LuaJIT provide the same CLI. All four pass one shared
acceptance suite and 496 direct output/status/error comparisons on Linux x86-64
and macOS ARM64. Rust remains the checked-in default while broader platform
qualification is completed. Roc is intended to become the default after that
qualification. See
[implementation parity](docs/implementation-parity.md).

## Build and run

Build with `./build` and run the complete current suite with `./test`. Both
require Nix. The build publishes commands in `bin/<PF>/`; on Linux x86-64:

```sh
printf 'name,count\nAlice,2\n' | bin/linux-amd64/table --to markdown
```

The build also publishes `bin/<PF>/tsv-to-ansi-table`, the pinned predecessor's
original command, for existing scripts and its fixed-width streaming mode.

`./build --all-platforms` builds and publishes Linux x86-64 and ARM64, macOS
ARM64, and Windows x86-64 and ARM64, using a suitable native or remote builder. It stops on the
first failure. Native packages include all four implementations; `--all-implementations`
builds that complete native package, and
`--all` combines both scopes. A foreign build is checked by executable header;
native execution remains a separate qualification. `./build --platform PF`
selects one target.

The published default command follows `CANONICAL_IMPL`. For explicit runs, the
Nix installation tree contains `bin/table-rust`, `bin/table-zig`, `bin/table-roc`
and `bin/table-luajit`; for example, after `./build`:

```sh
.nix-out/linux-amd64/release/bin/table-roc --to markdown < data.csv
```

`nix build .#rust`, `.#zig`, `.#roc` and `.#luajit` also expose the corresponding
packages. `./build canonize roc` records a selection without building or changing
installed commands; rerun `./build` to publish it. Windows publication currently
requires the Rust selection and refuses an unqualified alternative. Linux ARM64
non-Rust packages require a native builder. LuaJIT includes its pinned interpreter
and native I/O/Unicode dependency in the Nix closure; it is not a standalone
statically linked executable.

Rust, Zig and Roc Linux executables use static musl builds. LuaJIT uses its
pinned Nix runtime. macOS outputs use the native system runtime. Native Nix build and tests have been exercised
on Linux x86-64 and macOS ARM64. Publication through `./build` has been
exercised on Linux x86-64. Earlier GNU Linux ARM64 converter and predecessor Zig
renderer builds had their headers inspected and each executable
run separately under isolated QEMU. The converter's visual path was also run
under QEMU with an explicit emulator shim for the renderer. Native Linux ARM64 runtime
testing, including the current musl ARM64 output, remains open. The Windows cross-builds bundle
both executables and a renderer in `libexec` without requiring symlink support.
An earlier x86-64 bundle was exercised under isolated Wine, including the
published `bin/mswin-amd64` directory, but not on native Windows. The ARM64
executables have been cross-built and identified as ARM64 PE files, but their
UCRT linker mapping has not been tested on native Windows. The publisher uses
regular executable files and retains the previous Windows publication for
rollback. Bundles include dependency and Unicode license notices.

## Formats and detection

Choose the destination with `--to csv|tsv|markdown|ir|ascii|ansi`. When `--from`
is omitted (or set to `auto`), the converter examines the complete input. It
recognizes a valid IR signature, Markdown table structure, boxed ASCII/ANSI
tables, or a consistent multi-column CSV/TSV parse. Multiple matching formats,
empty input and single-column delimited input require an explicit `--from`.
Detection uses the source alone; the destination does not resolve ambiguity.
Visual input still requires `--allow-lossy`. Use `--from` to override detection
or preserve streaming: autodetection buffers stdin through EOF, while explicit
`--from tsv` retains fixed-width visual streaming. Literal delimiter characters
can make CSV and TSV both plausible, so automatic selection cannot establish
the producer's intended format in every case.

CSV and TSV
treat the first row as a header by default; `--no-header` treats it as data.
IR carries header presence. CSV and TSV do not, so choose the same header
option when reading them back. Input must be UTF-8 and rectangular. CSV accepts
quoted fields and embedded newlines; TSV rejects embedded tabs and newlines
when writing. Empty input represents no rows; a blank line represents one empty
cell. CRLF and LF record endings are accepted.

Markdown requires a header and delimiter row. Input reads table-cell source,
not rendered inline Markdown: it removes surrounding cell whitespace and
backslash escapes on ASCII punctuation, but does not interpret emphasis,
links, entities, HTML or code spans. It therefore does not reconstruct the
rendered text of arbitrary Markdown. Output escapes ASCII punctuation to keep
cell contents literal and rejects cells with leading or trailing whitespace or
control characters. Headerless tables, multiline cells and those whitespace
cases cannot be represented by this Markdown dialect. Column alignment is not
preserved.

Input is currently buffered in memory. CSV, TSV and IR can contain arbitrary
cell contents, including terminal control sequences; do not display untrusted
output directly in a terminal. Visual output will require a separate terminal
sanitization policy.

## Terminal tables

ASCII and ANSI output delegate to a pinned build of the predecessor's Rust
renderer. They retain its width, alignment, overflow, glyph and color behavior;
for example `--widths 20,10 --align left,right --overflow truncate,auto`.
`--terminal-width`, `--color`, `--plain` and `--decimal-separator` are also
accepted. `TSV_TO_ANSI_TABLE_GLYPHS` retains the predecessor's documented
custom-glyph syntax. Display formats are lossy: cells may be clipped, padded
or sanitized. Embedded tab and line breaks become replacement characters, and
other terminal controls are sanitized by the renderer. A warning accompanies
visual output. For TSV input the converter connects the predecessor directly to stdin and
stdout; when all widths are fixed, it streams rows before EOF. A malformed
late row may follow output already written. Other input formats buffer input
and rendered output. Terminal width selection uses `--terminal-width`, then
`COLUMNS`, then the parent terminal width, with an 80-column fallback. Parent
terminal width detection for buffered input is implemented on Unix.

Visual input requires `--allow-lossy`, because padding is stripped and prior
clipping or replacement cannot be undone. For example:

```sh
table --from ansi --to csv --allow-lossy < displayed-table.txt
```

The reader accepts boxed tables with the predecessor's ASCII or Unicode border
profiles and exact display-cell column boundaries. Unicode input uses the same
pinned Unicode 17 grapheme and width policy as the predecessor renderer. Extra separators, inconsistent widths, missing borders and ambiguous
row separators are errors. A separator after the first row marks a header; its
absence means no header. ANSI mode discards SGR sequences consisting of ESC,
`[`, decimal parameters separated by semicolons, and `m`; other escape forms,
including colon-form SGR, are rejected. ASCII mode rejects all escape sequences.

Custom input borders can be specified as 11 comma-separated single, safe,
one-cell Unicode characters (excluding whitespace and comma), in this order: top left, top join, top
right, middle left, middle join, middle right, bottom left, bottom join, bottom
right, horizontal, vertical. For example, `--visual-glyphs '*,*,*,*,*,*,*,*,*,~,!'`.
Horizontal, vertical and junction glyphs must be distinct from one another.
An input cell containing the vertical separator is rejected as ambiguous.

The Nix suite exercises all 36 format pairs on unclipped, unambiguous data,
checks CSV against the independent Rust `csv` crate using control characters and
randomized cells, checks rendered Markdown with the GFM reference parser, and
runs the pinned predecessor's CLI checks for headers, options, colors, glyphs
and fixed-width streaming against the compatibility executable. These checks
are not a claim that visual tables recover clipped or padded source data.

## Tests and benchmarks

`./test` is the complete current correctness suite, built through Nix. Every
implementation runs the same 12 CLI integration tests, format-pair checks,
autodetection checks, independent CSV and GFM Markdown oracles, and benchmark
fixture checks. The direct parity corpus compares stdout, stderr and exit status
for 496 cases, including malformed input and randomized quoted/control-character
cells. `--about` is checked separately because ABI/runtime metadata can differ.
Finite tests establish agreement for those cases, not a universal proof. The CI
manifest builds the Linux checks, Linux ARM64 cross target, macOS ARM64 package
and both Windows targets from the exact pushed commit. Native Windows and Linux
ARM64 runtime qualification remains open; cross-builds and emulator results are
separate evidence.

`./bm` measures the same six workloads for all four implementations with
one-core and 12-core affinity settings. It requires every selected executable,
checks complete output before accepting each timing, and records binary hashes.
Use `./bm --implementation rust|zig|roc|luajit` for an explicit subset. The
`TABLE_BENCHMARK_RUST`, `TABLE_BENCHMARK_ZIG`, `TABLE_BENCHMARK_ROC` and
`TABLE_BENCHMARK_LUAJIT` variables can select other optimized executables.

### Preliminary measurements

Measured on Linux x86-64 using code from commit `e98d1a8`, seed `20261106`, with
the pinned optimized toolchains and LuaJIT benchmark adapter. Each cell is the median milliseconds for **one-core /
12-core affinity**, from five fresh CLI processes. Startup converts one data row;
the other workloads use 4,096 data rows. Timing includes process launch, conversion,
pipe transfer and exit; fixture construction and verification are excluded.

| Workload | Rust | Zig | Roc | LuaJIT |
|---|---:|---:|---:|---:|
| Startup | 0.67 / 0.95 | noisy / 1.05 | 0.84 / 0.66 | 1.97 / 1.80 |
| CSV → TSV | 5.35 / 2.21 | noisy / 1.70 | 4.95 / 4.77 | 12.25 / 12.55 |
| CSV → IR | 5.19 / 2.14 | noisy / 1.98 | 3.84 / 3.49 | 14.18 / 13.27 |
| Markdown → CSV | 5.90 / 2.80 | 5.69 / 2.63 | 10.13 / 10.63 | 56.00 / 61.16 |
| ASCII → CSV | 11.54 / 4.69 | 6.06 / 3.17 | 40.11 / 38.97 | 47.85 / 51.29 |
| Autodetect CSV | 11.04 / 6.41 | 3.07 / 3.93 | 9.34 / 9.28 | 25.70 / 29.96 |

Of 48 cases, 45 are **UNBASELINED**. The three one-core Zig cases marked
**noisy** remained **INCONCLUSIVE** after the runner's one permitted retry;
their timings are omitted. All measured outputs passed verification. The
12-core setting is an affinity set, not a claim
that these algorithms use 12 threads. Shared-host scheduling and runtime/JIT
startup affect these observations. They compare these implementations and
fixtures, not the languages generally; no baseline was automatically accepted.

Roc's ASCII input cost comes largely from rebuilding each row as character
strings before splitting it, plus Unicode safety and display-width work.
[Diagnostic measurements](docs/roc-ascii-performance.md) isolate those costs;
the diagnostic bypasses are not part of the shipped converter.

`./big_o` and `./mg` currently measure Rust input growth and allocator usage.
See [performance cases](docs/performance.md) for coverage and remaining gates.

## License

[MIT](LICENSE). Bundles include notices for the predecessor renderer, its
dependencies and Unicode data.
