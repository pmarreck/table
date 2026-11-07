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

Do not use Python for project code, tests, benchmark adapters or build tooling.
The owner explicitly reaffirmed this constraint on 2026-11-06.

Maintain implementations of the same CLI in Rust, Zig, Roc and LuaJIT. Each must meet
the same documented behavior and platform qualification requirements. Make Roc
the default when it meets those requirements; until then retain the working
Rust default. The three compiled implementations were confirmed by the owner on
2026-11-05; LuaJIT was added on 2026-11-06. Run one shared acceptance suite and
direct behavioral comparisons for all four. Benchmark each with the same CLI
workloads and publish preliminary measurements with their limitations.

Provide a professional, responsive Elm web interface on GitHub Pages. Conversion,
format fingerprinting and rendering run entirely in client-side WebAssembly;
the flake controls the build. Compare Rust and Zig WASM implementations before
selecting the shipped engine. Expose all conversion formats and configuration
through appropriate inputs, including dropdowns for finite choices. Keep raw
output bytes separate from display text: IR displays printable-binary glyphs,
while copy and download use the original bytes. Explain control-character
limitations. Link the site to the source repository and the repository's online
version field back to the site. This direction was requested on 2026-11-07.
