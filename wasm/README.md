# Browser conversion core

Both WASM candidates reuse the existing conversion models. A common Zig object
links the locked predecessor's pure renderer, making ASCII/ANSI rendering
independent of processes or a terminal. Nix stages the declared renderer's
`zig/` directory as `web-renderer/` while building `wasm-renderer.zig`.
No neighboring checkout or host cache supplies source.

`native/io.c` builds with `TABLE_UNICODE_ONLY` for portable Unicode primitives.
Rust uses the same pinned utf8proc through its existing library dependency.
All conversion and rendering execute inside WASM. JavaScript supplies only
transport, a restricted WASI adapter, presentation and browser interactions.

The single-worker ABI owns both buffers. Call `table_request(length)`, write the
complete request into the returned region, then call `table_run()`. Request
storage must not be retained across resize. Result storage belongs to the
engine until the next request/run, so consumers copy it immediately. No caller
can free arbitrary addresses. Results contain either complete output bytes or
an error string, distinguished by the returned status.

Requests use 12 little-endian u32 words: TBW1 magic, operation (0 inspect/1
convert), source ID, destination ID, flags, terminal width, decimal index,
alignment index, overflow index, override count, glyph byte length and input
byte length. Overrides are four u32 words (column index, width, alignment,
overflow), followed by UTF-8 custom glyphs and input bytes. IDs 1–6 are CSV,
TSV, Markdown, ASCII, ANSI and IR; source 0 requests fingerprinting. Flags are
header=1, accept visual loss=2, plain=4 and color=8. Per-column alignment and
overflow use UINT32_MAX to inherit the default. Other fields are validated.

The browser copies result bytes before another request can overwrite them.
Printable IR is a separate presentation; clipboard and downloads use raw data.
The WASM host grants no filesystem, subprocess or network capabilities.
