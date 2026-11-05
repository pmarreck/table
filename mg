#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
package=$(nix build --no-link --print-out-paths .#default)
profiler=$(nix build --no-link --print-out-paths .#profiling-tool)
export PATH="$package/libexec:$PATH"
export PERFORMANCE_HISTORY_URL="${PERFORMANCE_HISTORY_URL:-file://${XDG_STATE_HOME:-$HOME/.local/state}/performance-history}"
exec "$profiler/bin/performance-profile" run --mode mg "$@"
