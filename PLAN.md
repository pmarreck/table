# PLAN

- [x] Implement and verify a versioned lossless intermediate representation and explicit CSV/TSV conversion (context: docs/intermediate-format.md; done 2026-11-05 11:05 EST; commit 4a0648d).
- [ ] Complete five-platform Nix publication and native runtime qualification, including Windows ARM64 and isolated complete tests.
- [x] Implement Markdown input and output with explicit escaping and ambiguity rules (done 2026-11-05 11:13 EST; commit 4a0648d).
- [x] Reuse or adapt the prior renderer with compatibility, streaming, width, alignment, Unicode and terminal-safety checks (done 2026-11-05 11:13 EST; commit d3f943c).
- [x] Implement conservative ASCII/ANSI table input with explicit dialect overrides and documented lossy cases (done 2026-11-05 11:13 EST; commit 1632f66).
- [ ] Expand adversarial format-pair and loss-handling qualification.
- [ ] Include and verify dependency license notices in all distributable bundles.
- [ ] Complete independently reviewed growth, cold-start and memory gates and integrate required checks into ./test (context: docs/performance.md).
