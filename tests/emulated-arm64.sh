#!/usr/bin/env bash
# Executed only inside the Nix check sandbox. PRoot supplies CPU dispatch,
# not confinement. The package's native acceptance harness remains unchanged.
set -uo pipefail
[[ $# == 9 ]] || { echo 'emulated-arm64: expected harness, four CLIs, renderer, two oracles and Lua runner' >&2; exit 2; }
harness=$1 rust=$2 zig=$3 roc=$4 lua=$5 renderer=$6 csv=$7 markdown=$8 runner=$9
[[ -n ${NIX_BUILD_TOP:-} && -n ${TABLE_EMULATION_READONLY:-} && -n ${TABLE_EMULATION_LUA_CPATH:-} && -n ${TABLE_EMULATION_QEMU:-} ]] || {
    echo 'emulated-arm64: run through the sandboxed Nix check, not directly' >&2; exit 1;
}
for binary in "$1" "$2" "$3" "$4" "$6" "$9"; do
    file -Lb "$binary" | grep -q 'ARM aarch64' || { echo "wrong target architecture: $binary" >&2; exit 1; }
done
lua=$5
interpreter=$(head -1 "$lua") || exit 1
interpreter=${interpreter#\#!}
helper=$(sed -n 's/.*native="\([^"]*\)".*/\1/p' "$lua") || exit 1
for binary in "$interpreter" "$helper"; do
    file -Lb "$binary" | grep -q 'ARM aarch64' || { echo "wrong LuaJIT target architecture: $binary" >&2; exit 1; }
done
proot --version || exit 1
file -Lb "$TABLE_EMULATION_QEMU" | grep -Eq 'statically linked|static-pie linked' || exit 1
"$TABLE_EMULATION_QEMU" --version || exit 1
# PRoot reports its last tracee's status, which can mask a failed main process.
# Capture the actual command status before its surviving descendants finish.
run_traced() {
    local receipt status=0
    receipt=$(mktemp "$TMPDIR/table-proot-status.XXXXXXXX") || return 1
    PROOT_NO_SECCOMP=1 timeout --kill-after=5s 600s proot -q "$TABLE_EMULATION_QEMU" bash -c '
        receipt=$1; shift
        set +e
        "$@"
        result=$?
        printf "%s\n" "$result" > "$receipt" || exit 1
        exit "$result"
    ' table-proot "$receipt" "$@" || status=$?
    [[ -s "$receipt" ]] || { echo 'missing emulation completion receipt' >&2; return 1; }
    local actual
    actual=$(cat "$receipt") || return 1
    [[ $actual =~ ^[0-9]+$ && $actual -le 255 ]] || return 1
    if [[ $actual != 0 ]]; then return "$actual"; fi
    return "$status"
}
status=0
run_traced bash -c '(sleep 0.1; exit 0) & exit 23' || status=$?
[[ $status == 23 ]] || { echo 'emulation masked a failed main process' >&2; exit 1; }
run_traced bash -c '
    log=$TMPDIR/table-emulation-immutable-input.log
    for target in "$1" "/host-rootfs$1"; do
        stat -c "%a %u %g %n" "$target" >> "$log" || exit 1
        if { printf changed >> "$target"; } 2>> "$log"; then exit 1; fi
        if chmod u+w "$target" 2>> "$log"; then exit 1; fi
        value=$(cat "$target") || exit 1
        [[ $value == table-emulation-readonly ]] || exit 1
    done
    printf writable > "$TMPDIR/table-emulation-private-write" || exit 1
    value=$(cat "$TMPDIR/table-emulation-private-write") || exit 1
    [[ $value == writable ]]
' table-emulation-canary "$TABLE_EMULATION_READONLY" || exit "$?"
for binary in "$rust" "$zig" "$roc" "$lua"; do
    run_traced env TABLE_TEST_BINARY="$binary" "$harness" --test-threads=1 || exit "$?"
    run_traced env LUA_CPATH="$TABLE_EMULATION_LUA_CPATH;;" "$runner" -joff tests/shared.lua "$binary" "$renderer" "$csv" "$markdown" || exit "$?"
done
run_traced env LUA_CPATH="$TABLE_EMULATION_LUA_CPATH;;" "$runner" -joff tests/parity.lua "$rust" "$zig" "$roc" "$lua" || exit "$?"
echo 'Linux ARM64 emulated acceptance passed; native qualification remains deferred.'
