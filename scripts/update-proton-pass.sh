#!/usr/bin/env bash
set -euo pipefail

package_file=modules/packages/proton-pass.nix
release_url=https://proton.me/download/PassDesktop/linux/x64/version.json

release_json=$(curl -fsSL "$release_url")
latest_version=$(jq -er '[.Releases[] | select(.CategoryName == "Stable")][0].Version' <<<"$release_json")
latest_url=$(jq -er \
  --arg version "$latest_version" \
  '.Releases[] | select(.CategoryName == "Stable" and .Version == $version) | .File[] | select(.Identifier == ".deb (Ubuntu/Debian)") | .Url' \
  <<<"$release_json")
current_version=$(sed -n 's/^  version = "\([^"]*\)";$/\1/p' "$package_file")
if [[ -z "$current_version" ]]; then
  printf 'Could not read the pinned Proton Pass version from %s\n' "$package_file" >&2
  exit 1
fi
if [[ "$latest_version" == "$current_version" ]]; then
  printf 'Proton Pass is already current (%s).\n' "$current_version"
  exit 0
fi

hash=$(nix store prefetch-file --json "$latest_url" | jq -er '.hash')
version_count=$(grep -c '^  version = "[^"]*";$' "$package_file")
hash_count=$(grep -c '^    hash = "sha256-[^"]*";$' "$package_file")
if [[ "$version_count" != 1 || "$hash_count" != 1 ]]; then
  printf 'Expected one version and one hash in %s; found %s and %s.\n' \
    "$package_file" "$version_count" "$hash_count" >&2
  exit 1
fi
sed -i \
  -e "s|^  version = \"[^\"]*\";|  version = \"$latest_version\";|" \
  -e "s|^    hash = \"sha256-[^\"]*\";|    hash = \"$hash\";|" \
  "$package_file"

printf 'Updated Proton Pass from %s to %s.\n' "$current_version" "$latest_version"
