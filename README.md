# table

`table` is an in-progress command-line converter for tabular formats. The current
slice supports CSV, TSV, Markdown pipe tables and the project's [versioned
intermediate representation](docs/intermediate-format.md). ASCII/ANSI table
conversion and compatibility with `tsv-to-ansi-table` are not implemented yet.

Build with `./build` and run the complete current suite with `./test`. Both
require Nix. The build publishes a command in `bin/<PF>/`; on Linux x86-64:

```sh
printf 'name,count\nAlice,2\n' | bin/linux-amd64/table --from csv --to markdown
```

The current host build is dynamically linked to its Nix store runtime and is
not a standalone distribution. Native build and test have been exercised on
Linux x86-64 only. The flake declares Linux ARM64 and macOS ARM64 packages;
those targets have not yet been qualified. Windows packaging remains open.

Both formats must be specified: `csv`, `tsv`, `markdown`, or `ir`. CSV and TSV
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
