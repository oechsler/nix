#!/usr/bin/env bash
set -euo pipefail

package_file=modules/packages/spotify.nix
repository_url=https://repository.spotify.com/pool/non-free/s/spotify-client/

latest_file=$(
  curl -fsSL "$repository_url" |
    grep -oE 'spotify-client_[0-9][^"<> ]*_amd64\.deb' |
    sort -Vu |
    tail -n 1
)
if [[ -z "$latest_file" ]]; then
  printf 'Could not find a Spotify amd64 Debian package at %s\n' "$repository_url" >&2
  exit 1
fi

latest_version=${latest_file#spotify-client_}
latest_version=${latest_version%_amd64.deb}
current_version=$(sed -n 's/^  version = "\([^"]*\)";$/\1/p' "$package_file")
if [[ -z "$current_version" ]]; then
  printf 'Could not read the pinned Spotify version from %s\n' "$package_file" >&2
  exit 1
fi
if [[ "$latest_version" == "$current_version" ]]; then
  printf 'Spotify is already current (%s).\n' "$current_version"
  exit 0
fi

package_url="${repository_url}${latest_file}"
hash=$(nix store prefetch-file --json "$package_url" | jq -er '.hash')
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

printf 'Updated Spotify from %s to %s.\n' "$current_version" "$latest_version"
