#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

mode=${1:-all}
if [[ "$mode" != all && "$mode" != --nix-only ]]; then
	printf 'Usage: %s [--nix-only]\n' "$0" >&2
	exit 2
fi

find . -name '*.nix' ! -name 'hardware-configuration.generated.nix' -print0 |
	xargs --null --no-run-if-empty nixfmt --check
statix check . --ignore 'hosts/*/hardware-configuration.generated.nix' --format=stderr
deadnix .

if [[ "$mode" == all ]]; then
	find . -type f -name '*.sh' -print0 |
		xargs --null --no-run-if-empty shellcheck -x
	find . \( -path '*/installer/*.sh' -o -name 'install.sh' \) -print0 |
		xargs --null --no-run-if-empty shfmt -i 2 -ci -d

	markdownlint-cli2 '**/*.md'
	prettier --check '**/*.md'
fi

fails=0

while IFS= read -r -d '' file; do
	if grep -nP '"[a-z][a-z0-9]*\.[a-z][a-z0-9.]*"\s*=' "$file" 2>/dev/null; then
		printf 'Quoted nested attribute found in %s\n' "$file" >&2
		fails=1
	fi
done < <(find . -name '*.nix' \
	! -name 'browsers.nix' \
	! -name 'lint.nix' \
	! -name 'gaming.nix' \
	! -path '*/hardware-configuration.generated.nix' \
	-print0)

while IFS= read -r -d '' file; do
	if ! head -5 "$file" | grep -q '^#'; then
		printf 'Missing Nix module purpose header: %s\n' "$file" >&2
		fails=1
	fi
done < <(find . -name '*.nix' \
	! -name 'default.nix' \
	! -path '*/packages/*' \
	! -path '*/hardware-configuration.generated.nix' \
	-print0)

if [[ "$mode" == all ]]; then
	while IFS= read -r -d '' file; do
		if ! head -20 "$file" | grep -q '^# [^#]'; then
			printf 'Missing Markdown H1: %s\n' "$file" >&2
			fails=1
		fi
		if grep -n '^#$' "$file" 2>/dev/null; then
			printf 'Empty Markdown heading: %s\n' "$file" >&2
			fails=1
		fi
		fences=$(grep -c '^```' "$file" 2>/dev/null || true)
		if ((fences % 2 != 0)); then
			printf 'Unbalanced Markdown fences: %s\n' "$file" >&2
			fails=1
		fi
	done < <(find . -name '*.md' -print0)
fi

exit "$fails"
