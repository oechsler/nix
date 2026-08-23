#!/usr/bin/env bash
# Build the graphical NixOS installer ISO containing all hosts.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
system="x86_64-linux"
output="installerIso"

usage() {
  cat <<'EOF'
Usage: ./build-iso.sh

Builds one graphical installer ISO containing all prebuilt hosts.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

out_link="$repo_dir/result"
# Replace the previous generated Nix output link or directory.
rm -rf "$out_link"

printf 'Building graphical multi-host installer ISO...\n'
nix build --show-trace ".#packages.${system}.${output}" --out-link "$out_link"

printf 'Build output: %s\n' "$(readlink -f "$out_link")"
printf 'ISO image: %s\n' "$out_link/iso/"
