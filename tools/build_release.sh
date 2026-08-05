#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)",[[:space:]]*$/\1/p' "$repo_root/update_config.lua")"

if [[ -z "$version" ]]; then
    echo "Could not read version from update_config.lua" >&2
    exit 1
fi

asset_name="wordwise.koplugin-v${version}.zip"
dist_dir="$repo_root/dist"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

plugin_dir="$temporary_dir/wordwise.koplugin"
mkdir -p "$plugin_dir" "$dist_dir"

# Keep this set compatible with the fixed RC1.3.0 updater allow-list.
# Repository-only documentation must not be added here.
release_files=(
    _meta.lua
    main.lua
    wordwise_db.lua
    known_words.lua
    context_scorer.lua
    book_classifier.lua
    wordwise_updater.lua
    update_config.lua
    README.md
    NOTICE.md
)

for file in "${release_files[@]}"; do
    cp "$repo_root/$file" "$plugin_dir/$file"
done

rm -f "$dist_dir/$asset_name" "$dist_dir/$asset_name.sha256"
(
    cd "$temporary_dir"
    zip -X -q -r "$dist_dir/$asset_name" wordwise.koplugin
)
(
    cd "$dist_dir"
    sha256sum "$asset_name" > "$asset_name.sha256"
)

printf '%s\n' "$dist_dir/$asset_name" "$dist_dir/$asset_name.sha256"
