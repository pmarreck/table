# Intent

Provide a dependable command-line tool named `table` for converting tabular data
between TSV, CSV, Markdown tables, ASCII tables and ANSI terminal tables. It is
for people moving data among terminals, documents, forums and other media.

Supersede the existing `tsv-to-ansi-table` converter while preserving its useful
rendering capabilities and extending them to conversion among all five forms.
Prefer accurate data and explicit limitations over silent loss or guessed results.

The owner proposes an intermediate representation using the ASCII FS, GS, RS and
US control characters to represent table structure, including headers and record
boundaries. Design a precise and unambiguous encoding, including literal control
characters in data, before relying on it.

Use Nix-controlled builds, one complete test entry point, and the shared project
conventions. Treat custom borders, ANSI styling, quoted and multiline cells,
format ambiguity and lossy display transformations as explicit design concerns.

Maintain implementations of the same CLI in Rust, Zig and Roc. Each must meet
the same documented behavior and platform qualification requirements. Make Roc
the default when it meets those requirements; until then retain the working
Rust default. This direction was confirmed by the owner on 2026-11-05.
