#!/usr/bin/env bash
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE
unset GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
unset GIT_TEMPLATE_DIR
git() { command git -c core.hooksPath=/dev/null "$@"; }
script=$PWD/scripts/build-provenance
scratch=$(mktemp -d "${TMPDIR:?}/table-provenance.XXXXXXXX")
trap 'cd /; rm -rf -- "$scratch"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git init -q -b yolo "$scratch/repo"
cd "$scratch/repo"
git config user.name 'Provenance fixture'
git config user.email 'fixture@example.invalid'
commit_file() { printf '%s\n' "$1" > "$1"; git add -- "$1"; git commit -qm "$1"; }
commit_file a
base=$(git rev-parse HEAD)
git checkout -qb topic
commit_file b
topic=$(git rev-parse HEAD)
bash "$script" . | jq -e --arg base "$base" --arg commit "$topic" '.available and .primary_base==$base and .commit==$commit and .count==1 and (.dirty|not)' >/dev/null
git checkout -q yolo
commit_file c
git merge -q --no-ff topic -m merge
merged=$(git rev-parse HEAD)
bash "$script" . | jq -e --arg base "$merged" '.primary_base==$base and .commit==$base and .count==4 and (.dirty|not)' >/dev/null
# Repository environment inherited from a caller must not redirect the helper.
GIT_DIR="$scratch/nonexistent.git" GIT_WORK_TREE="$scratch/empty" GIT_INDEX_FILE="$scratch/alien-index" \
    bash "$script" . | jq -e --arg commit "$merged" '.commit==$commit and .count==4' >/dev/null
# A merged topic commit is not on the primary first-parent line.
git checkout -q topic
bash "$script" . | jq -e --arg base "$base" '.primary_base==$base and .count==1' >/dev/null
git checkout -qb next yolo
commit_file e
bash "$script" . | jq -e --arg base "$merged" '.primary_base==$base and .count==4' >/dev/null
printf dirty >> e
bash "$script" . | jq -e '.dirty' >/dev/null
git checkout -q yolo --force
git clone -q --depth 1 "file://$scratch/repo" "$scratch/shallow"
bash "$script" "$scratch/shallow" | jq -e '.available==false' >/dev/null
mkdir "$scratch/empty"
bash "$script" "$scratch/empty" | jq -e '.available==false' >/dev/null
printf 'build provenance: primary, topic, merged ancestry, dirty and shallow cases passed\n'
