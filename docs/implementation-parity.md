# Implementation parity

Rust, Zig, Roc and LuaJIT independently implement the documented conversion
model, intermediate grammar, CSV/TSV and Markdown dialects, visual-table parsing
and source detection. The owner requested the compiled implementations on
2026-11-05 and added LuaJIT on 2026-11-06. No implementation invokes another
converter as its backend. All may invoke the same pinned predecessor renderer
for ASCII/ANSI output. Native helpers shared by Zig and LuaJIT supply OS I/O,
process launch and Unicode properties, not table parsing or conversion.

`./test` builds all four native executables and runs the same twelve CLI
integration tests against each, including streaming before EOF, PTY terminal
width, header flags, failure output and bundled-renderer relocation. Every
implementation also runs the same format-pair, autodetection, external CSV/GFM
oracle and benchmark-fixture checks. A separate corpus compares exit status,
stdout and stderr byte for byte for 496 cases across all four. About output is
validated separately because target ABI/runtime metadata legitimately differs.
Finite agreement is evidence for these cases, not a proof over all possible
inputs. Rust is a comparison reference, while the external parsers and fixed
wire vectors provide separate correctness oracles.

The full shared suite has passed natively on Linux x86-64 and macOS ARM64.
Nix exposes native Linux ARM64 outputs, but those require a native builder and
have not yet run this suite. Rust also retains its Linux ARM64 and Windows
cross-build outputs. The pinned Roc platform does not supply Windows ARM64 host
artifacts and its x86-64 host lacks required CRT import libraries. Zig and LuaJIT
Windows packaging/runtime qualification is also pending. None of those gaps is
silently substituted with a different implementation.

`CANONICAL_IMPL` records the default selection. It remains `rust` until Roc
meets the same wider platform qualification. `./build canonize IMPL` only records
a registered choice; the next successful build updates published commands.
Explicit native executables are `table-rust`, `table-zig`, `table-roc` and
`table-luajit`. Windows publication refuses a non-Rust selection. The native
Nix package includes the interpreter and native library closure for LuaJIT;
its script is not a standalone static binary.

The benchmark matrix and its verified fixtures are shared by all four.
Preliminary Linux measurements at source commit `50e6ab6` are in the README;
all remain unbaselined. They do not establish general language performance or
approval of a performance epoch.
