#!/usr/bin/env bash
set -euo pipefail

# The upstream export is intentionally a rolling release. Keep its content
# hash in the Nix module, but provide one repeatable update path for CI and
# maintainers when the upstream release changes.
url='https://github.com/catppuccin/userstyles/releases/download/all-userstyles-export/import.json'
file='modules/home-manager/programs/browsers.nix'
mode="${1:-check}"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl --fail --location --silent --show-error "$url" --output "$tmp"
hash=$(nix hash file --sri "$tmp")
current=$(perl -ne 'if (/catppuccinUserstylesExport/) { $seen = 1 } elsif ($seen && /hash = "([^"]+)"/) { print "$1\n"; exit }' "$file")

if [[ "$mode" == check ]]; then
	if [[ "$current" != "$hash" ]]; then
		printf 'Catppuccin userstyles hash is stale. Expected: %s\n' "$hash" >&2
		printf 'Run: %s --update\n' "$0" >&2
		exit 1
	fi
	exit 0
fi

if [[ "$mode" != --update ]]; then
	printf 'Usage: %s [check|--update]\n' "$0" >&2
	exit 2
fi

export hash
perl -0pi -e 's/(catppuccinUserstylesExport.*?hash = ")[^"]+/$1$ENV{hash}/s' "$file"
