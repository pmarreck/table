# PLAN

- [x] Qualify all four Linux ARM64 CLIs under emulation with the same 12 CLI tests, shared acceptance checks and 858 parity cases in ./test (context: docs/plan_context/platform-qualification.md; done 2026-11-25 18:43 EST; commit 8cdc321).
- [ ] Qualify Windows for Zig, Roc and LuaJIT, including the missing Roc Windows host/CRT support (context: docs/plan_context/platform-qualification.md).
- [ ] Make Roc the default implementation after compatibility and platform qualification, preserving explicit implementation selection.
- [ ] Qualify native Linux ARM64 and Windows x86-64/ARM64 runtime behavior, including the ARM64 UCRT mapping; native ARM64 is deferred by the owner while only emulators are available (context: docs/plan_context/platform-qualification.md).
- [x] Qualify Rust 1.100.0 across native, oracle, cross and WASM routes with Cargo JSON discovery; all seven exact-commit CI targets pass (context: docs/plan_context/rust-1.100-assessment.md; done 2026-11-20 14:08 EST; commit 37f7618).
- [x] Add independently reviewed allocation-growth, zero-residual and performance-inventory controls to ./test on Linux amd64 and macOS ARM64 (context: docs/performance.md; done 2026-11-20 14:08 EST; commit 37f7618).
- [ ] Complete independently reviewed growth, cold-start and memory gates and integrate required checks into ./test (context: docs/performance.md).
