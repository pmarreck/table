# Remaining platform qualification

The owner authorized emulation on November 20, 2026 because native Linux ARM64
and Windows ARM64 environments are unavailable for now. Native qualification
remains deferred. Emulation results must be labeled explicitly and cannot be
reported as native runtime evidence.

The project exposes Linux ARM64 Rust, Zig, Roc and LuaJIT cross-builds. LuaJIT
includes its ARM64 interpreter and native helper through the Nix runtime
closure. PRoot and QEMU provide transparent target execution, including renderer
subprocesses, inside the canonical Nix check sandbox. PRoot is an execution
adapter, not a confinement boundary. The canonical Nix daemon must have
sandboxing enabled; that setting was verified for qualification. The internal
adapter requires the Nix build environment and checks that immutable-input
writes and permission changes through PRoot's host-root alias fail. It does not
provide a standalone sandbox. No global executable handler registration is
required.

QEMU and PRoot are test-only dependencies: QEMU supplies ARM64 CPU execution,
and PRoot dispatches target renderer subprocesses without replacing the public
CLIs or registering host handlers. The existing test sources and external
oracles are reused. The Rust CLI harness and LuaJIT runner are built for ARM64:
the native Rust harness crashed under PRoot, and the native Lua runner produced
mixed-architecture loader errors. These tools are not added to the converter's
runtime closure.

The emulated Lua test runner uses `-joff` after an allocator abort was observed
with its JIT enabled. This workaround does not establish the abort's cause.
The LuaJIT converter runs in a separate process with its normal JIT behavior;
the runner flag is not passed to it. The emulated test-runner timings are not
benchmark observations.

Allocator aborts also occurred with runner JIT disabled, with PRoot's seccomp
acceleration disabled, and with separate PRoot sessions per consumer. None of
those changes alone resolved the failure. The current configuration selects
the pinned static-musl QEMU user emulator by exact path and rejects a dynamic
emulator before execution. This bypasses Nix's build-input splicing, which
otherwise selected the dynamic host QEMU package. Each complete consumer runs
once in a fresh PRoot session, with plain ptrace tracing; parity still compares
all four implementations in one unchanged corpus. The enclosing Nix sandbox
remains the isolation boundary. The initial static-emulator run completed the
Rust, Zig and Roc suites, then exposed a LuaJIT renderer-launch diagnostic
difference. Its shared suite and the final parity corpus were not reached.

A separate C-only observer reproduced the behavior without LuaJIT: spawning
the same non-executable file returned `EACCES` natively, but reported spawn
success followed by child exit 127 under ARM64 emulation. This is an allowed
[spawn failure behavior](https://man7.org/linux/man-pages/man3/posix_spawn.3.html),
which exposed an assumption in the shared process helper. The helper now checks
execute permission with effective credentials before spawning. This normalizes
predictable permission failures while preserving genuine child exit statuses;
it does not classify every possible execution failure or eliminate races.
The unchanged relocation regression failed before this correction and passed
afterward. On November 25, the full `./test` suite passed, including all twelve
CLI tests and the shared acceptance checks for each ARM64 implementation, plus
all 858 byte-for-byte parity cases across the four ARM64 CLIs. Native Linux,
WASM and browser checks also passed. This qualifies the tested emulation
configuration; native ARM64 remains deferred.

The same twelve CLI acceptance tests and shared format/oracle/parity suites
are used. The acceptance harness and LuaJIT runner execute on the emulated
ARM64 CPU; the external oracles run on the host CPU. Both visual-output
comparisons use the actual ARM64 renderer and test streaming before EOF.
The relocation test deliberately installs an invalid renderer and checks that
it is selected. Target architecture checks cover the CLI harness, LuaJIT runner,
three compiled CLIs, LuaJIT interpreter and FFI helper, and renderer. A failing-main canary
verifies that a surviving successful descendant cannot mask failure through
PRoot's last-tracee exit-status behavior. These runs provide compatibility
evidence, not performance measurements.

The adapter passed independent source review, conditional on the full suite.
Early runs caught an incorrect Rust executable name and an invalid assumption
about Nix mount flags. Those preflight issues were corrected, but the November
20 qualification unit reached its enforced 30-minute execution limit before
completion. On November 25, the owner requested that all outstanding work be
added, committed and pushed. Verification resumed under the existing 30-minute,
16-GiB limit. That unit ended within the limit with the relocation test still
failing. The owner then explicitly authorized continuing to get everything
passing and pushed; a further bounded unit diagnosed and corrected the process
helper assumption and completed the full suite within the execution budget.

Windows x86-64 Rust, Zig and LuaJIT packages cross-build. The pinned Roc
basic-cli 0.25.0 Windows host still fails to link its required CRT support.
Using only the newer runtime with that older host leaves an unresolved
`__GSHandlerCheck`; this is not repaired with a security stub. A whole-platform
upgrade was tested with basic-cli 0.28.1 and Roc nightly
`2026-11-13-03dce41`, its matching published compiler. The compiler crashes
with SIGSEGV in `post-check boxy_lowering` while checking this application,
before either native or Windows compilation. The working compiler/platform
pins are retained. That newer platform also lacks a Windows ARM64 host, so
resolving its compiler crash alone would not qualify Windows ARM64.

There is no provisioned Windows ARM64 emulator image/runtime in the available
environment. Read-only investigation found a cached Linux ARM64 Wine 11.0
minimal package in the pinned Nixpkgs. Running that through QEMU and PRoot is
a candidate for Windows ARM64 PE execution without a Windows VM image. It has
not been fetched or tested; the next step is a sandboxed runtime smoke test
followed by the shared suites under a separately bounded qualification job.
Cross-linking Rust's ARM64 UCRT, synchronization and unwind
libraries establishes construction only. Windows ARM64 runtime qualification
and a matching Roc host remain required before the current default-selection
condition can be fulfilled. The project continues to use Rust by default and
preserves explicit implementation selection.

For a suspected LuaJIT runtime defect, first reproduce it independently of the
converter, then try the latest pinned upstream LuaJIT revision before reporting
the bug. Report it upstream if it still reproduces there. The renderer-launch
case above required no LuaJIT version change because its C-only reproduction
isolated the behavior below the LuaJIT boundary.
