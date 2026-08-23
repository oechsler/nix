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

output_dir="$repo_dir/installer-output"
out_link="$output_dir/nixos-installer.iso"
mkdir -p "$output_dir"
rm -f "$out_link"

printf 'Building %s...\n' "$output"
nix build --show-trace ".#packages.${system}.${output}" --out-link "$out_link"

printf 'ISO: %s\n' "$(readlink -f "$out_link")"
