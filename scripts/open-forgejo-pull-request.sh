#!/usr/bin/env bash
set -euo pipefail

# Update an automation branch's existing PR, or create one when none is open.
# The branch must already have been pushed before this script is called.

if [[ $# -ne 2 ]]; then
	printf 'Usage: %s TITLE BODY\n' "$0" >&2
	exit 2
fi

: "${BRANCH:?BRANCH is required}"
token="${FORGEJO_TOKEN:-${GITHUB_TOKEN:-${RENOVATE_TOKEN:-}}}"
: "${token:?FORGEJO_TOKEN, GITHUB_TOKEN, or RENOVATE_TOKEN is required}"

server="${FORGEJO_SERVER_URL:-${GITHUB_SERVER_URL:-}}"
repo="${FORGEJO_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
: "${server:?FORGEJO_SERVER_URL or GITHUB_SERVER_URL is required}"
: "${repo:?FORGEJO_REPOSITORY or GITHUB_REPOSITORY is required}"
server=${server%/}

title=$1
body=$2
if [[ -n "${FORGEJO_API_URL:-}" ]]; then
	api="${FORGEJO_API_URL%/}/repos/$repo"
elif [[ -n "${GITHUB_API_URL:-}" && -z "${FORGEJO_SERVER_URL:-}" ]]; then
	api="${GITHUB_API_URL%/}/repos/$repo"
else
	api="$server/api/v1/repos/$repo"
fi
headers=(--header "Authorization: token $token")

find_open_pr() {
	curl --fail --silent --show-error --retry 3 --retry-all-errors --get "$api/pulls" \
		"${headers[@]}" \
		--data-urlencode 'state=open' \
		--data-urlencode 'base=main' \
		--data-urlencode 'limit=50' |
		jq -r --arg branch "$BRANCH" 'map(select(.head.ref == $branch))[0].number // empty'
}

open_pr=$(find_open_pr)

if [[ -n "$open_pr" ]]; then
	printf 'Pull request #%s already exists for %s\n' "$open_pr" "$BRANCH"
	exit 0
fi

payload=$(jq -cn \
	--arg head "$BRANCH" \
	--arg title "$title" \
	--arg body "$body" \
	'{head: $head, base: "main", title: $title, body: $body}')
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT
http_code=$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' --request POST "$api/pulls" \
	"${headers[@]}" \
	--header 'Content-Type: application/json' \
	--data "$payload")

if [[ "$http_code" =~ ^2 ]]; then
	cat "$response_file" | jq -r '"Created pull request #\(.number)"'
	exit 0
fi

# A concurrent workflow can create the same PR after our initial lookup.
# Re-query after a conflict and treat it as success only if that PR exists.
if [[ "$http_code" == 409 ]]; then
	open_pr=$(find_open_pr)
	if [[ -n "$open_pr" ]]; then
		printf 'Pull request #%s was created concurrently\n' "$open_pr"
		exit 0
	fi
fi

printf 'Failed to create pull request (HTTP %s):\n' "$http_code" >&2
jq -r '.message // .' "$response_file" >&2
exit 1
