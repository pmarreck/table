# PLAN

- [ ] Remove all Python project tooling and dependencies while preserving the shared suite, external oracles and benchmark coverage.
- [ ] Measure and explain the Roc ASCII-to-CSV slowdown using the project-approved tooling.
- [x] Complete all four CLIs; the shared suite and 496 direct parity cases pass on Linux x86-64 and macOS ARM64 (done 2026-11-06 09:35 EST; commit f4698fe).
- [x] Add LuaJIT to the shared benchmark matrix and publish all 48 preliminary four-implementation measurements in the README; results remain unbaselined (done 2026-11-06 09:35 EST; commit 50e6ab6).
- [x] Establish one acceptance/parity suite for all four CLIs with explicit platform qualification gaps (context: docs/implementation-parity.md; done 2026-11-06 09:35 EST; commit f4698fe).
- [x] Implement the complete Zig CLI and qualify shared native behavior on Linux x86-64 and macOS ARM64; wider targets remain below (done 2026-11-06 09:35 EST; commit f4698fe).
- [x] Implement the complete Roc CLI and qualify shared native behavior on Linux x86-64 and macOS ARM64; wider targets remain below (done 2026-11-06 09:35 EST; commit f4698fe).
- [ ] Qualify Linux ARM64 and Windows for Zig, Roc and LuaJIT, including the missing Roc Windows host/CRT support (context: docs/implementation-parity.md).
- [ ] Make Roc the default implementation after compatibility and platform qualification, preserving explicit implementation selection.
- [ ] Qualify native Linux ARM64 and Windows x86-64/ARM64 runtime behavior, including the ARM64 UCRT mapping.
- [ ] Complete independently reviewed growth, cold-start and memory gates and integrate required checks into ./test (context: docs/performance.md).
