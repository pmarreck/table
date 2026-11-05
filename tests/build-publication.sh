#!/usr/bin/env bash
set -euo pipefail
scratch=$(mktemp -d "${TMPDIR:?}/table-publication.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/project" "$scratch/tools" "$scratch/product/bin" "$scratch/product/libexec"
cp build "$scratch/project/build"
cat > "$scratch/tools/uname" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == -s ]]; then echo Linux; else echo x86_64; fi
STUB
cat > "$scratch/tools/file" <<'STUB'
#!/usr/bin/env bash
if [[ ${BAD_HEADER:-0} == 1 ]]; then echo 'foreign executable';
else case "$2" in *linux-arm64*) echo 'ELF 64-bit LSB executable, ARM aarch64' ;; *macos-arm64*) echo 'Mach-O 64-bit executable arm64' ;; *mswin-amd64*) echo 'PE32+ executable for MS Windows, x86-64' ;; *) echo 'ELF 64-bit LSB executable, x86-64' ;; esac; fi
STUB
cat > "$scratch/tools/nix" <<'STUB'
#!/usr/bin/env bash
[[ ${FAIL_BUILD:-0} != 1 ]] || exit 1
[[ $1 == build && $2 == --out-link ]]
printf '%s\n' "$4" >> "$BUILD_LOG"
ln -s "$FAKE_PRODUCT" "$3"
STUB
export REAL_PERL="$(command -v perl)"
cat > "$scratch/tools/perl" <<'STUB'
#!/usr/bin/env bash
if [[ ${FAIL_INSTALL:-0} == 1 && ${3:-} == *'.mswin-amd64-candidate.'* && ${4:-} == */bin/mswin-amd64 ]]; then exit 1; fi
exec "$REAL_PERL" "$@"
STUB
cat > "$scratch/product/bin/table" <<'STUB'
#!/usr/bin/env bash
printf 'table 0.1.0; PF=linux-amd64 VARIANT=gnu\n'
STUB
for script in "$scratch/project/build" "$scratch/tools/"* "$scratch/product/bin/table"; do
    sed -i "1c#!$(command -v bash)" "$script"
done
chmod +x "$scratch/tools/"* "$scratch/product/bin/table"
cp "$scratch/product/bin/table" "$scratch/product/bin/tsv-to-ansi-table"
cp "$scratch/product/bin/table" "$scratch/product/bin/table.exe"
cp "$scratch/product/bin/table" "$scratch/product/bin/tsv-to-ansi-table.exe"
cp "$scratch/product/bin/table" "$scratch/product/libexec/tsv-to-ansi-table.exe"
export PATH="$scratch/tools:$PATH" FAKE_PRODUCT="$scratch/product" BUILD_LOG="$scratch/build.log"
cd "$scratch/project"
./build
[[ $(readlink bin/linux-amd64/table) == ../../.nix-out/linux-amd64/release/bin/table ]]
[[ $(readlink bin/linux-amd64/tsv-to-ansi-table) == ../../.nix-out/linux-amd64/release/bin/tsv-to-ansi-table ]]
[[ $(readlink .nix-out/linux-amd64/release) == "$scratch/product" ]]
# An existing recognized selection remains untouched if Nix or verification fails.
ln -sfn /nix/store/previous-table .nix-out/linux-amd64/release
if FAIL_BUILD=1 ./build; then echo 'failed build was accepted' >&2; exit 1; fi
[[ $(readlink .nix-out/linux-amd64/release) == /nix/store/previous-table ]]
if BAD_HEADER=1 ./build; then echo 'foreign header was accepted' >&2; exit 1; fi
[[ $(readlink .nix-out/linux-amd64/release) == /nix/store/previous-table ]]
# Never overwrite a file the publisher does not own.
unlink bin/linux-amd64/table
printf 'keep me\n' > bin/linux-amd64/table
if ./build; then echo 'unrecognized command was replaced' >&2; exit 1; fi
[[ $(cat bin/linux-amd64/table) == 'keep me' ]]
unlink bin/linux-amd64/table
ln -s ../../.nix-out/linux-amd64/release/bin/table bin/linux-amd64/table
./build --all
grep -Fxq '.#linux-arm64-cross' "$BUILD_LOG"
grep -Fxq '.#packages.aarch64-darwin.default' "$BUILD_LOG"
grep -Fxq '.#packages.x86_64-linux.windows-amd64-cross' "$BUILD_LOG"
for pf in linux-arm64 macos-arm64; do
    [[ $(readlink "bin/$pf/table") == "../../.nix-out/$pf/release/bin/table" ]]
    [[ $(readlink "bin/$pf/tsv-to-ansi-table") == "../../.nix-out/$pf/release/bin/tsv-to-ansi-table" ]]
done
[[ $(readlink bin/linux-amd64/table) == ../../.nix-out/linux-amd64/release/bin/table ]]
[[ -f bin/mswin-amd64/table.exe && ! -L bin/mswin-amd64/table.exe ]]
[[ -f bin/mswin-amd64/tsv-to-ansi-table.exe && ! -L bin/mswin-amd64/tsv-to-ansi-table.exe ]]
[[ -f bin/mswin-amd64/libexec/tsv-to-ansi-table.exe && ! -L bin/mswin-amd64/libexec/tsv-to-ansi-table.exe ]]
# The selected published Windows files survive failure and unknown files block replacement.
ln -sfn /nix/store/previous-windows .nix-out/mswin-amd64/release
before=$(cksum bin/mswin-amd64/table.exe)
if FAIL_BUILD=1 ./build --platform mswin-amd64; then echo 'failed Windows build was accepted' >&2; exit 1; fi
[[ $(cksum bin/mswin-amd64/table.exe) == "$before" ]]
if FAIL_INSTALL=1 ./build --platform mswin-amd64; then echo 'failed Windows installation was accepted' >&2; exit 1; fi
[[ $(cksum bin/mswin-amd64/table.exe) == "$before" ]]
[[ $(readlink .nix-out/mswin-amd64/release) == /nix/store/previous-windows ]]
mkdir .nix-out/mswin-amd64/.publish-lock
if ./build --platform mswin-amd64; then echo 'concurrent publication was accepted' >&2; exit 1; fi
rmdir .nix-out/mswin-amd64/.publish-lock
[[ $(cksum bin/mswin-amd64/table.exe) == "$before" ]]
printf 'preserve\n' > bin/mswin-amd64/unrecognized
if ./build --platform mswin-amd64; then echo 'unknown Windows file was replaced' >&2; exit 1; fi
[[ $(cat bin/mswin-amd64/unrecognized) == preserve ]]
