# PLAN

- [x] Build and compare complete Rust/Zig WASM converters with fingerprinting and the pinned pure renderer; select Rust from 24 verified browser benchmarks, with both candidates passing 70 conformance cases (context: docs/web-wasm-results.json; done 2026-11-07 10:22 EST; commit ab9758a).
- [x] Build a responsive Elm interface with dropdowns, configuration controls, raw/printable IR separation, copy and download; all 36 conversion routes pass desktop/mobile browser checks (done 2026-11-07 10:22 EST; commit ab9758a).
- [x] Verify browser behavior and privacy, publish through GitHub Pages, and link the repository's online version; all 13 live assets match the tested artifact, deployment and Mechatron pass, and the About box links to the site (done 2026-11-07 10:22 EST; commit ab9758a).
- [ ] Qualify Linux ARM64 and Windows for Zig, Roc and LuaJIT, including the missing Roc Windows host/CRT support (context: docs/implementation-parity.md).
- [ ] Make Roc the default implementation after compatibility and platform qualification, preserving explicit implementation selection.
- [ ] Qualify native Linux ARM64 and Windows x86-64/ARM64 runtime behavior, including the ARM64 UCRT mapping.
- [ ] Qualify the owner-authorized Rust 1.100.0 compiler-provider update across native, oracle, cross and WASM routes, including Cargo JSON artifact discovery (context: docs/plan_context/rust-1.100-assessment.md).
- [ ] Complete independently reviewed growth, cold-start and memory gates and integrate required checks into ./test (context: docs/performance.md).
