# PLAN log

Completed PLAN.md items retired by plan-retire, oldest retirement first.

## Retired 2026-11-06

- [x] [PLAN] Implement and verify a versioned lossless intermediate representation and explicit CSV/TSV conversion (context: docs/intermediate-format.md; done 2026-11-05 11:05 EST; commit 4a0648d).
- [x] [PLAN] Build and publish all five platform targets through Nix with isolated publication tests (done 2026-11-05 12:38 EST; commit c4d0553).
- [x] [PLAN] Implement Markdown input and output with explicit escaping and ambiguity rules (done 2026-11-05 11:13 EST; commit 4a0648d).
- [x] [PLAN] Reuse or adapt the prior renderer with compatibility, streaming, width, alignment, Unicode and terminal-safety checks (done 2026-11-05 11:13 EST; commit d3f943c).
- [x] [PLAN] Implement conservative ASCII/ANSI table input with explicit dialect overrides and documented lossy cases (done 2026-11-05 11:13 EST; commit 1632f66).
- [x] [PLAN] Add shared CLI benchmark cases for Rust, Zig and Roc; Rust measurements are unbaselined and complete Zig/Roc executables are still required (done 2026-11-06 08:47 EST; commit 5942f07).
- [x] [PLAN] Register final publication links as Nix GC roots with isolated failure and registry regressions (done 2026-11-06 08:47 EST; commit 5942f07).
- [x] [PLAN] Add conservative stdin format autodetection with explicit ambiguity errors and preserve explicit TSV streaming (done 2026-11-06 08:47 EST; commit 5942f07).
- [x] [PLAN] Expand adversarial format-pair and loss-handling qualification (done 2026-11-05 13:14 EST; commit 89fcca6).
- [x] [PLAN] Include and verify dependency license notices in all distributable bundles (done 2026-11-05 12:38 EST; commit c4d0553).
- [x] [PLAN] Complete all four CLIs; the shared suite and 496 direct parity cases pass on Linux x86-64 and macOS ARM64 (done 2026-11-06 09:35 EST; commit f4698fe).
- [x] [PLAN] Add LuaJIT to the shared benchmark matrix and publish all 48 preliminary four-implementation measurements in the README; results remain unbaselined (done 2026-11-06 09:35 EST; commit 50e6ab6).
- [x] [PLAN] Establish one acceptance/parity suite for all four CLIs with explicit platform qualification gaps (context: docs/implementation-parity.md; done 2026-11-06 09:35 EST; commit f4698fe).

## Retired 2026-11-20

- [x] [PLAN] Can Roc be optimized further? Answer: Yes; direct row splitting, printable-ASCII validation and escape-free passthrough cut the one-core ASCII-to-CSV fixture from 41.11 ms to 5.78 ms; all 858 parity cases pass; timings remain unbaselined (context: docs/roc-ascii-performance.md; done 2026-11-06 20:47 EST; commit a7c46aa).
- [x] [PLAN] Remove all Python project tooling and dependencies; LuaJIT harnesses retain the shared suite, independent CSV/GFM oracles and 48 benchmark cases (done 2026-11-06 13:30 EST; commit e98d1a8).
- [x] [PLAN] Why is Roc ASCII-to-CSV slower? Answer: row reconstruction costs about 17 ms of a 39 ms run; Unicode width and safety add about 10 ms and 4 ms in separate ablations; diagnostic bypasses are not shipped (context: docs/roc-ascii-performance.md; done 2026-11-06 13:36 EST; code commit e98d1a8).
- [x] [PLAN] Implement the complete Zig CLI and qualify shared native behavior on Linux x86-64 and macOS ARM64; wider targets remain below (done 2026-11-06 09:35 EST; commit f4698fe).
- [x] [PLAN] Implement the complete Roc CLI and qualify shared native behavior on Linux x86-64 and macOS ARM64; wider targets remain below (done 2026-11-06 09:35 EST; commit f4698fe).
