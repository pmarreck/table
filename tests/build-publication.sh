#!/usr/bin/env bash
set -euo pipefail
scratch=$(mktemp -d "${TMPDIR:?}/table-publication.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/project" "$scratch/tools"
cp build "$scratch/project/build"
cat > "$scratch/tools/uname" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == -s ]]; then echo Linux; else echo x86_64; fi
STUB
cat > "$scratch/tools/file" <<'STUB'
#!/usr/bin/env bash
if [[ ${BAD_HEADER:-0} == 1 ]]; then echo 'foreign executable';
else case "$2" in *linux-arm64*) echo 'ELF 64-bit LSB executable, ARM aarch64' ;; *macos-arm64*) echo 'Mach-O 64-bit executable arm64' ;; *mswin-amd64*) echo 'PE32+ executable for MS Windows, x86-64' ;; *mswin-arm64*) echo 'PE32+ executable for MS Windows, ARM64' ;; *) echo 'ELF 64-bit LSB executable, x86-64' ;; esac; fi
STUB
cat > "$scratch/tools/nix" <<'STUB'
#!/usr/bin/env bash
[[ ${FAIL_BUILD:-0} != 1 ]] || exit 1
[[ $1 == build && $2 == --out-link ]]
printf '%s\n' "$4" >> "$BUILD_LOG"
ln -s "$FAKE_PRODUCT" "$3"
STUB
cat > "$scratch/tools/nix-store" <<'STUB'
#!/usr/bin/env bash
[[ $1 == --add-root && $3 == --indirect && $4 == -r && $5 == "$FAKE_PRODUCT" ]]
[[ ${FAIL_ROOT:-0} != 1 ]] || exit 1
ln -sfn "$5" "$2"
printf '%s\n' "$2" >> "$ROOT_LOG"
STUB
export REAL_PERL="$(command -v perl)"
cat > "$scratch/tools/perl" <<'STUB'
#!/usr/bin/env bash
if [[ ${FAIL_INSTALL:-0} == 1 && ${3:-} == *'.mswin-amd64-candidate.'* && ${4:-} == */bin/mswin-amd64 ]]; then exit 1; fi
exec "$REAL_PERL" "$@"
STUB
for script in "$scratch/project/build" "$scratch/tools/"*; do
    sed -i "1c#!$(command -v bash)" "$script"
done
chmod +x "$scratch/tools/"*
export PATH="$scratch/tools:$PATH" FAKE_PRODUCT="${TEST_PUBLICATION_FIXTURE:?}" BUILD_LOG="$scratch/build.log" ROOT_LOG="$scratch/roots.log"
cd "$scratch/project"
./build
[[ $(readlink bin/linux-amd64/table) == ../../.nix-out/linux-amd64/release/bin/table ]]
[[ $(readlink bin/linux-amd64/tsv-to-ansi-table) == ../../.nix-out/linux-amd64/release/bin/tsv-to-ansi-table ]]
[[ $(readlink .nix-out/linux-amd64/release) == "$FAKE_PRODUCT" ]]
grep -Fxq "$PWD/.nix-out/linux-amd64/release" "$ROOT_LOG"
# An existing recognized selection remains untouched if Nix or verification fails.
ln -sfn /nix/store/previous-table .nix-out/linux-amd64/release
if FAIL_BUILD=1 ./build; then echo 'failed build was accepted' >&2; exit 1; fi
[[ $(readlink .nix-out/linux-amd64/release) == /nix/store/previous-table ]]
if FAIL_ROOT=1 ./build; then echo 'failed root registration was accepted' >&2; exit 1; fi
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
grep -Fxq '.#packages.x86_64-linux.windows-arm64-cross' "$BUILD_LOG"
for pf in linux-arm64 macos-arm64; do
    grep -Fxq "$PWD/.nix-out/$pf/release" "$ROOT_LOG"
    [[ $(readlink "bin/$pf/table") == "../../.nix-out/$pf/release/bin/table" ]]
    [[ $(readlink "bin/$pf/tsv-to-ansi-table") == "../../.nix-out/$pf/release/bin/tsv-to-ansi-table" ]]
done
[[ $(readlink bin/linux-amd64/table) == ../../.nix-out/linux-amd64/release/bin/table ]]
[[ -f bin/mswin-amd64/table.exe && ! -L bin/mswin-amd64/table.exe ]]
[[ -f bin/mswin-amd64/tsv-to-ansi-table.exe && ! -L bin/mswin-amd64/tsv-to-ansi-table.exe ]]
[[ -f bin/mswin-amd64/libexec/tsv-to-ansi-table.exe && ! -L bin/mswin-amd64/libexec/tsv-to-ansi-table.exe ]]
[[ -f bin/mswin-amd64/THIRD_PARTY_LICENSES.txt && ! -L bin/mswin-amd64/THIRD_PARTY_LICENSES.txt ]]
[[ -f bin/mswin-arm64/table.exe && ! -L bin/mswin-arm64/table.exe ]]
[[ -f bin/mswin-arm64/libexec/tsv-to-ansi-table.exe && ! -L bin/mswin-arm64/libexec/tsv-to-ansi-table.exe ]]
[[ -f bin/mswin-arm64/THIRD_PARTY_LICENSES.txt && ! -L bin/mswin-arm64/THIRD_PARTY_LICENSES.txt ]]
# The selected published Windows files survive failure and unknown files block replacement.
before=$(cksum bin/mswin-amd64/table.exe)
for pf in mswin-amd64 mswin-arm64; do grep -Fxq "$PWD/.nix-out/$pf/release" "$ROOT_LOG"; done
if FAIL_ROOT=1 ./build --platform mswin-amd64; then echo 'failed Windows root registration was accepted' >&2; exit 1; fi
[[ $(cksum bin/mswin-amd64/table.exe) == "$before" ]]
if FAIL_BUILD=1 ./build --platform mswin-amd64; then echo 'failed Windows build was accepted' >&2; exit 1; fi
[[ $(cksum bin/mswin-amd64/table.exe) == "$before" ]]
if FAIL_INSTALL=1 ./build --platform mswin-amd64; then echo 'failed Windows installation was accepted' >&2; exit 1; fi
[[ $(cksum bin/mswin-amd64/table.exe) == "$before" ]]
[[ $(readlink .nix-out/mswin-amd64/release) == "$FAKE_PRODUCT" ]]
mkdir .nix-out/mswin-amd64/.publish-lock
if ./build --platform mswin-amd64; then echo 'concurrent publication was accepted' >&2; exit 1; fi
rmdir .nix-out/mswin-amd64/.publish-lock
[[ $(cksum bin/mswin-amd64/table.exe) == "$before" ]]
chmod u+w bin/mswin-amd64/table.exe
printf 'changed\n' >> bin/mswin-amd64/table.exe
changed=$(cksum bin/mswin-amd64/table.exe)
if ./build --platform mswin-amd64; then echo 'modified Windows executable was replaced' >&2; exit 1; fi
[[ $(cksum bin/mswin-amd64/table.exe) == "$changed" ]]
cp "$FAKE_PRODUCT/bin/table.exe" bin/mswin-amd64/table.exe
chmod u+w bin/mswin-amd64/THIRD_PARTY_LICENSES.txt
printf 'changed\n' >> bin/mswin-amd64/THIRD_PARTY_LICENSES.txt
if ./build --platform mswin-amd64; then echo 'modified Windows notices were replaced' >&2; exit 1; fi
cp "$FAKE_PRODUCT/share/licenses/table/THIRD_PARTY_LICENSES.txt" bin/mswin-amd64/THIRD_PARTY_LICENSES.txt
printf 'preserve\n' > bin/mswin-amd64/unrecognized
if ./build --platform mswin-amd64; then echo 'unknown Windows file was replaced' >&2; exit 1; fi
[[ $(cat bin/mswin-amd64/unrecognized) == preserve ]]
