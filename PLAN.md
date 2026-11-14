# PLAN

- [x] Build and compare complete Rust/Zig WASM converters with fingerprinting and the pinned pure renderer; select Rust from 24 verified browser benchmarks, with both candidates passing 70 conformance cases (context: docs/web-wasm-results.json; done 2026-11-07 10:22 EST; commit ab9758a).
- [x] Build a responsive Elm interface with dropdowns, configuration controls, raw/printable IR separation, copy and download; all 36 conversion routes pass desktop/mobile browser checks (done 2026-11-07 10:22 EST; commit ab9758a).
- [x] Verify browser behavior and privacy, publish through GitHub Pages, and link the repository's online version; all 13 live assets match the tested artifact, deployment and Mechatron pass, and the About box links to the site (done 2026-11-07 10:22 EST; commit ab9758a).
- [x] Can Roc be optimized further? Answer: Yes; direct row splitting, printable-ASCII validation and escape-free passthrough cut the one-core ASCII-to-CSV fixture from 41.11 ms to 5.78 ms; all 858 parity cases pass; timings remain unbaselined (context: docs/roc-ascii-performance.md; done 2026-11-06 20:47 EST; commit a7c46aa).
- [x] Remove all Python project tooling and dependencies; LuaJIT harnesses retain the shared suite, independent CSV/GFM oracles and 48 benchmark cases (done 2026-11-06 13:30 EST; commit e98d1a8).
- [x] Why is Roc ASCII-to-CSV slower? Answer: row reconstruction costs about 17 ms of a 39 ms run; Unicode width and safety add about 10 ms and 4 ms in separate ablations; diagnostic bypasses are not shipped (context: docs/roc-ascii-performance.md; done 2026-11-06 13:36 EST; code commit e98d1a8).
- [x] Implement the complete Zig CLI and qualify shared native behavior on Linux x86-64 and macOS ARM64; wider targets remain below (done 2026-11-06 09:35 EST; commit f4698fe).
- [x] Implement the complete Roc CLI and qualify shared native behavior on Linux x86-64 and macOS ARM64; wider targets remain below (done 2026-11-06 09:35 EST; commit f4698fe).
- [ ] Qualify Linux ARM64 and Windows for Zig, Roc and LuaJIT, including the missing Roc Windows host/CRT support (context: docs/implementation-parity.md).
- [ ] Make Roc the default implementation after compatibility and platform qualification, preserving explicit implementation selection.
- [ ] Qualify native Linux ARM64 and Windows x86-64/ARM64 runtime behavior, including the ARM64 UCRT mapping.
- [ ] Owner scheduling required: qualify a scoped Rust 1.100.0 compiler-provider update across native, oracle, cross and WASM routes, including Cargo JSON artifact discovery; preserve existing pins until scheduled (context: docs/plan_context/rust-1.100-assessment.md).
- [ ] Complete independently reviewed growth, cold-start and memory gates and integrate required checks into ./test (context: docs/performance.md).
