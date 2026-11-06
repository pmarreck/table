# PLAN

- [ ] Complete all four CLIs and run the same acceptance and direct parity suite against Rust, Zig, Roc and LuaJIT.
- [ ] Add LuaJIT to the shared benchmark matrix and publish preliminary four-implementation results in the README.
- [x] Add shared CLI benchmark cases for Rust, Zig and Roc; Rust measurements are unbaselined and complete Zig/Roc executables are still required (done 2026-11-06 08:47 EST; commit 5942f07).
- [x] Register final publication links as Nix GC roots with isolated failure and registry regressions (done 2026-11-06 08:47 EST; commit 5942f07).
- [x] Add conservative stdin format autodetection with explicit ambiguity errors and preserve explicit TSV streaming (done 2026-11-06 08:47 EST; commit 5942f07).
- [ ] Establish a shared, implementation-independent CLI conformance suite and target matrix for Rust, Zig and Roc (context: docs/implementation-parity.md).
- [ ] Implement the complete table CLI in Zig and qualify it against the shared suite and platform matrix.
- [ ] Implement the complete table CLI in Roc and qualify it against the shared suite and platform matrix.
- [ ] Make Roc the default implementation after compatibility and platform qualification, preserving explicit implementation selection.
- [x] Implement and verify a versioned lossless intermediate representation and explicit CSV/TSV conversion (context: docs/intermediate-format.md; done 2026-11-05 11:05 EST; commit 4a0648d).
- [x] Build and publish all five platform targets through Nix with isolated publication tests (done 2026-11-05 12:38 EST; commit c4d0553).
- [ ] Qualify native Linux ARM64 and Windows x86-64/ARM64 runtime behavior, including the ARM64 UCRT mapping.
- [x] Implement Markdown input and output with explicit escaping and ambiguity rules (done 2026-11-05 11:13 EST; commit 4a0648d).
- [x] Reuse or adapt the prior renderer with compatibility, streaming, width, alignment, Unicode and terminal-safety checks (done 2026-11-05 11:13 EST; commit d3f943c).
- [x] Implement conservative ASCII/ANSI table input with explicit dialect overrides and documented lossy cases (done 2026-11-05 11:13 EST; commit 1632f66).
- [x] Expand adversarial format-pair and loss-handling qualification (done 2026-11-05 13:14 EST; commit 89fcca6).
- [x] Include and verify dependency license notices in all distributable bundles (done 2026-11-05 12:38 EST; commit c4d0553).
- [ ] Complete independently reviewed growth, cold-start and memory gates and integrate required checks into ./test (context: docs/performance.md).
