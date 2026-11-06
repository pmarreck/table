# Implementation parity

The owner directed the project to provide Rust, Zig and Roc implementations of
the same `table` CLI and to select Roc by default after it qualifies. The Rust
converter is currently the only complete implementation. A language-specific
launcher that delegates conversion to that Rust converter would not establish
an independent implementation. The existing pinned predecessor renderer may be
reused for visual output, subject to the same streaming and compatibility
requirements for each converter.

The [intermediate format](intermediate-format.md), documented CLI behavior and
rejection rules are the common contract. The black-box conformance suite accepts
an executable path and exercises all format pairs, renderer compatibility,
fixed-width streaming, terminal safety and representative errors. The CSV and
Markdown external-oracle scripts also accept an executable path. Each complete
implementation must run these checks, along with the implementation-specific
unit and integration tests needed for its own risks. These checks are a starting
point, not an exhaustive proof of behavioral equivalence.

Each implementation must build through Nix and qualify for the same platform
matrix. Cross-compilation, emulated execution and native execution are distinct
evidence. The pinned predecessor's Roc toolchain does not currently produce its
Windows builds: its host lacks required CRT import libraries. That limitation
must be addressed and tested rather than inferred away. Keep Rust as the default
until Roc meets the same checks, and provide explicit selection once multiple
implementations are available. Maintain existing publication rollback behavior.

The initial Roc and Zig intermediate encoders are partial components. They do
not yet provide the other formats, a CLI, a cross-language decoder, or platform
qualification. Their Nix compiler checks must pass before they are treated as
verified.
