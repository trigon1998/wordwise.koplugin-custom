#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)",[[:space:]]*$/\1/p' "$repo_root/update_config.lua")"
asset_name="wordwise.koplugin-v${version}.zip"
archive="${1:-$repo_root/dist/$asset_name}"
checksum="${archive}.sha256"

test -f "$archive"
test -f "$checksum"

(
    cd "$(dirname -- "$archive")"
    sha256sum -c "$(basename -- "$checksum")"
)

unzip -t "$archive" >/dev/null

expected="$(
    printf '%s\n' \
        wordwise.koplugin/ \
        wordwise.koplugin/NOTICE.md \
        wordwise.koplugin/README.md \
        wordwise.koplugin/_meta.lua \
        wordwise.koplugin/book_classifier.lua \
        wordwise.koplugin/context_scorer.lua \
        wordwise.koplugin/known_words.lua \
        wordwise.koplugin/main.lua \
        wordwise.koplugin/update_config.lua \
        wordwise.koplugin/wordwise_db.lua \
        wordwise.koplugin/wordwise_updater.lua
)"
actual="$(unzip -Z1 "$archive" | LC_ALL=C sort)"

# Explicit bootstrap regression guard: RC1.3.0 rejects every path outside its
# immutable runtime allow-list.
if unzip -Z1 "$archive" | grep -Fqx "wordwise.koplugin/DATA_MAINTENANCE.md"; then
    echo "Repository-only documentation found in legacy-compatible OTA ZIP" >&2
    exit 1
fi

if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected release contents:" >&2
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
    exit 1
fi

if unzip -Z1 "$archive" | grep -Eiq '(^|/)(databases?|wordwise)/|known_words\.db|\.s?qlite3?$|\.db$'; then
    echo "Database or user-data path found in plugin release" >&2
    exit 1
fi

echo "Plugin release verification: PASS"
