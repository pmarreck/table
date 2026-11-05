# PLAN

- [x] Implement and verify a versioned lossless intermediate representation and explicit CSV/TSV conversion (context: docs/intermediate-format.md; done 2026-11-05 11:05 EST; commit 4a0648d).
- [x] Build and publish all five platform targets through Nix with isolated publication tests (done 2026-11-05 12:38 EST; commit c4d0553).
- [ ] Qualify native Linux ARM64 and Windows x86-64/ARM64 runtime behavior, including the ARM64 UCRT mapping.
- [x] Implement Markdown input and output with explicit escaping and ambiguity rules (done 2026-11-05 11:13 EST; commit 4a0648d).
- [x] Reuse or adapt the prior renderer with compatibility, streaming, width, alignment, Unicode and terminal-safety checks (done 2026-11-05 11:13 EST; commit d3f943c).
- [x] Implement conservative ASCII/ANSI table input with explicit dialect overrides and documented lossy cases (done 2026-11-05 11:13 EST; commit 1632f66).
- [ ] Expand adversarial format-pair and loss-handling qualification.
- [x] Include and verify dependency license notices in all distributable bundles (done 2026-11-05 12:38 EST; commit c4d0553).
- [ ] Complete independently reviewed growth, cold-start and memory gates and integrate required checks into ./test (context: docs/performance.md).
