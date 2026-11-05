# table

`table` is an in-progress command-line converter for tabular formats. The current
slice supports CSV, TSV, Markdown pipe tables and the project's [versioned
intermediate representation](docs/intermediate-format.md). ASCII and ANSI visual output use the predecessor renderer. Visual table input
is supported for a conservative subset and requires explicit loss acceptance.

Build with `./build` and run the complete current suite with `./test`. Both
require Nix. The build publishes commands in `bin/<PF>/`; on Linux x86-64:

```sh
printf 'name,count\nAlice,2\n' | bin/linux-amd64/table --from csv --to markdown
```

The build also publishes `bin/<PF>/tsv-to-ansi-table`, the pinned predecessor's
original command, for existing scripts and its fixed-width streaming mode.

`./build --all-platforms` builds and publishes the three declared Unix targets,
using a suitable native or remote builder; it stops on the first
failure. `--all-implementations` selects the sole Rust implementation, and
`--all` combines both scopes. A foreign build is checked by executable header;
native execution remains a separate qualification.

The Unix host build is dynamically linked to its Nix store runtime and is
not a standalone distribution. Native Nix build and tests have been exercised
on Linux x86-64 and macOS ARM64. Publication through `./build` has been
exercised on Linux x86-64.
The Linux ARM64 converter and renderer have been cross-built and their
executable headers inspected; native runtime testing remains open. The
cross-build uses the predecessor's Zig renderer. The experimental
`nix build .#windows-amd64-cross` output bundles both Windows executables and a
renderer in `libexec` without requiring symlink support. It has been exercised
under isolated Wine, but not on native Windows; publication under `bin/<PF>`
is not implemented for Windows. Windows ARM64 is not packaged: the pinned Nix
package set marks its Rust cross target unsupported.

Both formats must be specified: `csv`, `tsv`, `markdown`, `ir`, `ascii`, or `ansi`. CSV and TSV
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
absence means no header. In ANSI mode, SGR color sequences are discarded; other
escape sequences are rejected. ASCII mode rejects all escape sequences.

Custom input borders can be specified as 11 comma-separated single, safe,
one-cell Unicode characters (excluding whitespace and comma), in this order: top left, top join, top
right, middle left, middle join, middle right, bottom left, bottom join, bottom
right, horizontal, vertical. For example, `--visual-glyphs '*,*,*,*,*,*,*,*,*,~,!'`.
Horizontal, vertical and junction glyphs must be distinct from one another.
An input cell containing the vertical separator is rejected as ambiguous.

The Nix suite exercises all 36 format pairs on unclipped, unambiguous data,
checks CSV against Python's standard-library parser using control characters and
randomized cells, and runs the pinned predecessor's CLI checks for headers, options, colors, glyphs
and fixed-width streaming against the compatibility executable. These checks
are not a claim that visual tables recover clipped or padded source data.
