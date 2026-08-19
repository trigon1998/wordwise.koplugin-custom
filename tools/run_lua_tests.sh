#!/usr/bin/env bash
set -euo pipefail

run_test() {
    local test_file="$1"
    local output

    output="$(npx --yes --package=fengari-node-cli fengari "$test_file" 2>&1)"
    printf '%s\n' "$output"
    if ! grep -Fq "tests: PASS" <<<"$output"; then
        echo "Lua test did not emit its PASS marker: $test_file" >&2
        return 1
    fi
}

run_test tests/test_main.lua
run_test tests/test_db.lua
run_test tests/test_updater.lua
