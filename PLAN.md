# PLAN

- [x] Complete all four CLIs; the shared suite and 496 direct parity cases pass on Linux x86-64 and macOS ARM64 (done 2026-11-06 09:35 EST; commit f4698fe).
- [x] Add LuaJIT to the shared benchmark matrix and publish all 48 preliminary four-implementation measurements in the README; results remain unbaselined (done 2026-11-06 09:35 EST; commit 50e6ab6).
- [x] Add shared CLI benchmark cases for Rust, Zig and Roc; Rust measurements are unbaselined and complete Zig/Roc executables are still required (done 2026-11-06 08:47 EST; commit 5942f07).
- [x] Register final publication links as Nix GC roots with isolated failure and registry regressions (done 2026-11-06 08:47 EST; commit 5942f07).
- [x] Add conservative stdin format autodetection with explicit ambiguity errors and preserve explicit TSV streaming (done 2026-11-06 08:47 EST; commit 5942f07).
- [x] Establish one acceptance/parity suite for all four CLIs with explicit platform qualification gaps (context: docs/implementation-parity.md; done 2026-11-06 09:35 EST; commit f4698fe).
- [x] Implement the complete Zig CLI and qualify shared native behavior on Linux x86-64 and macOS ARM64; wider targets remain below (done 2026-11-06 09:35 EST; commit f4698fe).
- [x] Implement the complete Roc CLI and qualify shared native behavior on Linux x86-64 and macOS ARM64; wider targets remain below (done 2026-11-06 09:35 EST; commit f4698fe).
- [ ] Qualify Linux ARM64 and Windows for Zig, Roc and LuaJIT, including the missing Roc Windows host/CRT support (context: docs/implementation-parity.md).
- [ ] Make Roc the default implementation after compatibility and platform qualification, preserving explicit implementation selection.
- [ ] Qualify native Linux ARM64 and Windows x86-64/ARM64 runtime behavior, including the ARM64 UCRT mapping.
- [x] Expand adversarial format-pair and loss-handling qualification (done 2026-11-05 13:14 EST; commit 89fcca6).
- [x] Include and verify dependency license notices in all distributable bundles (done 2026-11-05 12:38 EST; commit c4d0553).
- [ ] Complete independently reviewed growth, cold-start and memory gates and integrate required checks into ./test (context: docs/performance.md).
