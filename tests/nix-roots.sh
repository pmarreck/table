#!/usr/bin/env bash
set -euo pipefail
scratch=$(mktemp -d "${TMPDIR:?}/table-nix-roots.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
store="local?root=$scratch/store"
printf 'root fixture\n' > "$scratch/fixture"
product=$(nix-store --store "$store" --option build-users-group '' --add "$scratch/fixture")
# Use the real Nix registry in a disposable store, not the host store or daemon.
nix-store --store "$store" --option build-users-group '' --add-root "$scratch/release" --indirect -r "$product" >/dev/null
nix-store --store "$store" --option build-users-group '' --query --roots "$product" > "$scratch/roots"
grep -Fxq "$scratch/release -> $product" "$scratch/roots"
# Replacement must retain the stable root path for the new output.
printf 'replacement\n' > "$scratch/fixture"
replacement=$(nix-store --store "$store" --option build-users-group '' --add "$scratch/fixture")
nix-store --store "$store" --option build-users-group '' --add-root "$scratch/release" --indirect -r "$replacement" >/dev/null
nix-store --store "$store" --option build-users-group '' --query --roots "$replacement" > "$scratch/roots"
grep -Fxq "$scratch/release -> $replacement" "$scratch/roots"
