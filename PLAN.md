# PLAN

- [x] Implement and verify a versioned lossless intermediate representation and explicit CSV/TSV conversion (context: docs/intermediate-format.md; done 2026-11-05 11:05 EST; commit 4a0648d).
- [ ] Add Nix-controlled builds, isolated complete tests and platform-specific publication.
- [ ] Implement Markdown input and output with explicit escaping and ambiguity rules.
- [ ] Reuse or adapt the prior renderer with compatibility, streaming, width, alignment, Unicode and terminal-safety checks.
- [ ] Implement conservative ASCII/ANSI table input with explicit dialect overrides and documented lossy cases.
- [ ] Qualify format pairs, adversarial round trips, performance and supported platform targets.
