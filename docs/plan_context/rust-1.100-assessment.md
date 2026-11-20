# Rust 1.100 assessment

The owner authorized implementation on 2026-11-20. The assessment below records
the pre-upgrade state. Qualification results are recorded separately; its earlier
scheduling hold no longer applies.

Assessed November 13, 2026 against `dad577d`. This records a proposed maintenance
upgrade, not authorization to change compiler pins. No 1.100 build or runtime
qualification was performed at that time. The following sections preserve that
assessment; implementation evidence follows at the end.

## Selected toolchains

Nix evaluation of each package's `nativeBuildInputs` confirms the following.
Package versions and the compiler's own version output are distinguished below.

| Route | Compiler provider | Selected Rust | Cargo evidence |
|---|---|---|---|
| Native Linux amd64 CLI and Rust test/benchmark binaries | Pinned Nixpkgs static Rust platform | 1.97.1 | Package 1.97.1; executable reports 1.97.0 |
| Native Linux arm64 CLI | Same Nixpkgs static platform | 1.97.1 | Package metadata 1.97.1; not executed on arm64 |
| Native macOS arm64 CLI | Pinned Nixpkgs Rust platform | 1.97.1 | Package metadata 1.97.1; not executed on macOS |
| Independent CSV test oracle | Pinned Nixpkgs Rust platform | 1.97.1 | Package 1.97.1; executable reports 1.97.0 |
| Linux arm64 cross build | Nixpkgs cross Rust platform | 1.97.1 | Host Cargo reports 1.97.0 |
| Windows amd64 cross build | Nixpkgs MinGW Rust platform | 1.97.1 | Host Cargo reports 1.97.0 |
| Windows arm64 cross build | Explicit rust-overlay minimal toolchain | 1.97.1 | Host Cargo reports 1.97.1 |
| Browser WASM, `wasm32-wasip1` | Separate explicit rust-overlay minimal toolchain | 1.97.1 | Host Cargo reports 1.97.1 |

The Linux rustc probes report `8bab26f4f`; both Cargo providers report commit
`c980f4866`, despite the differing displayed patch versions. Cross-target compiler
selection is not evidence of native target execution. The flake declares no
devShell, and there is no project Rust toolchain file. An ambient editor or shell
compiler is therefore not a supported, pinned development route. None of the
three local Cargo manifests declares `rust-version`; edition 2021 is not an MSRV.
The implicit `nix develop` package fallback is a symlink-join bundle with no
Rust/Cargo native build inputs, so it does not establish a development compiler.

The locked rust-overlay does **not** expose `stable."1.100.0"`. Merely changing
the two explicit 1.97.1 strings would fail and would leave the native, oracle,
Linux-cross and Windows-amd64 routes on the older Nixpkgs compiler anyway.
The separately pinned predecessor renderer also uses its own Rust platform;
retain that dependency pin during a local toolchain qualification.

## Compatibility review

The [official release notes](https://doc.rust-lang.org/releases.html#version-11000-2026-11-12)
identify all-edition inference changes, new intermediate artifact layout,
Unicode 18 standard-library tables, a WASI SDK update and Windows gnullvm linking
changes. Their relevance here is an assessment, not a demonstrated regression:

- `flake.nix` discovers the reusable CLI acceptance executable with
  `target/<triple>/release/deps/cli-*`. This reaches into Cargo's intermediate
  layout. Replace that discovery with JSON `compiler-artifact` records before
  relying on the upgraded compiler. Audit custom WASM and Windows installation
  paths too; do not assume every final release path changed.
- No local `Infallible` references or overlapping implementations were found.
  The never-type fallback still needs compilation checks on edition 2021.
  The CSV oracle's `Box<dyn Error>`, closures and inferred collection types
  deserve targeted diagnostic review if compilation fails.
- Rust Markdown parsing/writing uses `trim` and `is_control`; custom visual
  glyphs use `is_whitespace`. Check those policies against the other three
  implementations and the pinned utf8proc Unicode 17 policy. No changed
  character behavior has been established by this assessment.
- Retain WASI preview 1. Exercise the packaged Rust and Zig modules through
  the JavaScript consumer: new runtime imports or C-linking requirements must
  remain compatible with the restricted browser WASI host and shared Zig renderer.
- Recheck Windows arm64 static unwind linkage with the existing Zig/UCRT
  adapter. Its outstanding native runtime qualification is not resolved by
  changing Rust versions.
- No configured Rustfmt, Clippy or custom deny-lint gate was found. Establish
  their current diagnostics before proposing new policy; do not hide a newly
  configured or newly failing diagnostic. Keep the global-allocation counter's
  canary and cleanup checks when evaluating compiler-generated changes.

## Proposed scope and scheduling

Owner scheduling is required. Use the next dedicated maintenance window after
the current platform-parity priorities, preferably before accepting performance
baselines. This assessment does not start that work or a fleet rebuild.

1. Record a current 1.97 baseline through the canonical Nix build and complete
   `./test`; previous green evidence is historical, not a fresh baseline run.
2. Update only the compiler-provider input needed for 1.100.0. Select a common
   version for all local Rust routes while retaining their target-specific
   platforms, C toolchains and standard libraries. Keep Nixpkgs, the predecessor,
   Zig, Roc, LuaJIT, Cargo lockfiles and editions pinned unless an actual blocker
   requires a separately explained change. Do not invent or raise an MSRV.
3. Replace intermediate-path discovery with Cargo JSON artifacts and check
   compatibility of the old Nix Rust build/install hooks with Cargo 1.100.
4. Qualify Linux amd64 plus WASM first using `nix build` and full `./test`:
   shared CLI acceptance/parity and independent oracles, both WASM candidates,
   browser conversion routes, raw IR copy/download and memory reuse. Run the
   relevant format/lint diagnostics without weakening existing checks.
5. Coordinate serial remaining targets with Mechatron: macOS arm64 native,
   Linux arm64 cross, and both Windows cross builds. Preserve the distinction
   between builds and native execution. Native Windows/Linux-arm64 access and
   Roc's Windows host/CRT support remain existing qualification blockers.
6. Review ABI consumers, refreshed performance observations and WASM size before
   promotion. Existing measurements remain historical and unbaselined; no
   automatic acceptance or Roc-default change accompanies this upgrade.

Overall: a reasonable maintenance candidate, with provider availability and
Cargo artifact discovery as concrete preparation work. Source inspection alone
does not qualify Rust 1.100.0 for shipping.

## Qualification on November 20, 2026

The compiler provider is now rust-overlay revision
`8bbfc858c7b85f5e6ed6d6cc201ffcee1bb08a9b`, selecting Rust/Cargo 1.100.0
through one toolchain function for all local native, oracle, cross and WASM
routes. Nixpkgs, the predecessor renderer, Zig, Roc, LuaJIT, editions and Cargo
lockfiles retain their earlier pins. The predecessor retains its own compiler.
The `libc` dependency is now explicitly Unix-only, matching its actual uses and
resolving Cargo's new Windows unused-dependency diagnostic.

Native Linux amd64 and macOS ARM64 pass the same twelve CLI tests per
implementation, independent CSV/GFM oracles and all 858 parity cases. Both
WASM modules pass 70 conformance cases, including memory reuse and malformed
input; the Elm browser checks pass all 36 conversion routes and the mobile,
clipboard, raw IR and local-only computation checks. `./test` passes, as do all
seven existing Mechatron target attributes. These are local/remote Nix build
results, separate from the subsequent exact-commit CI result.

Cargo JSON artifact messages now locate the shared CLI acceptance harness,
Rust WASM module and Windows ARM64 executables. Diagnostics remain visible via
`json-render-diagnostics`. The existing Nix final-install hooks also pass with
Cargo's new intermediate layout.

The downloaded compiler exposed the static stdenv's unqualified `-static`
C-link flag leaking into GNU-host build scripts. The build removes that flag
for static-target Cargo invocations, supplies the host ELF interpreter, and
retains explicit target `+crt-static`. The installed Linux Rust executable is
checked as static or static PIE.

Windows ARM64 additionally requires the synchronization API import contract and
a static LLVM unwinder. Both come from the already pinned Zig 0.16.0 sources:
the import definition supplies the synchronization library, and an explicit
archive includes the SEH unwinder, register support and both level-one C
interfaces. No placeholder unwind or security handlers are used. The existing
UCRT mapping remains. The cross-build passes; native Windows ARM64 execution is
still required and is not established by these link checks.

Build wrappers now supply Git-aware revision metadata, with complete-history
first-parent base selection, full-ancestry counting and a separate dirty flag.
Native About output, the web footer and provenance JSON use the same identity.
Missing or shallow Git history explicitly reports unavailable provenance.
Independent review found an inherited-Git-index isolation error in the fixture;
the corrected test proves that an external disposable index stays untouched.

The bounded allocation-growth/cleanup controls are independently reviewed and
required by `./test`. Fresh historical performance approval remains separate;
older published measurements still describe their original toolchains. Roc's
default promotion and the wider native platform qualifications remain open.
