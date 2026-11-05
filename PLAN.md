# PLAN

- [x] Implement and verify a versioned lossless intermediate representation and explicit CSV/TSV conversion (context: docs/intermediate-format.md; done 2026-11-05 11:05 EST; commit 4a0648d).
- [ ] Add Nix-controlled builds, isolated complete tests and platform-specific publication.
- [x] Implement Markdown input and output with explicit escaping and ambiguity rules (done 2026-11-05 11:13 EST; commit 4a0648d).
- [x] Reuse or adapt the prior renderer with compatibility, streaming, width, alignment, Unicode and terminal-safety checks (done 2026-11-05 11:13 EST; commit d3f943c).
- [x] Implement conservative ASCII/ANSI table input with explicit dialect overrides and documented lossy cases (done 2026-11-05 11:13 EST; commit 1632f66).
- [ ] Qualify format pairs, adversarial round trips, performance and supported platform targets.
