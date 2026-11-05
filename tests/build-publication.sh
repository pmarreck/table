#!/usr/bin/env bash
set -euo pipefail
scratch=$(mktemp -d "${TMPDIR:?}/table-publication.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/project" "$scratch/tools" "$scratch/product/bin"
cp build "$scratch/project/build"
cat > "$scratch/tools/uname" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == -s ]]; then echo Linux; else echo x86_64; fi
STUB
cat > "$scratch/tools/file" <<'STUB'
#!/usr/bin/env bash
if [[ ${BAD_HEADER:-0} == 1 ]]; then echo 'foreign executable'; else echo 'ELF 64-bit LSB executable, x86-64'; fi
STUB
cat > "$scratch/tools/nix" <<'STUB'
#!/usr/bin/env bash
[[ ${FAIL_BUILD:-0} != 1 ]] || exit 1
[[ $1 == build && $2 == --out-link ]]
ln -s "$FAKE_PRODUCT" "$3"
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
export PATH="$scratch/tools:$PATH" FAKE_PRODUCT="$scratch/product"
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
