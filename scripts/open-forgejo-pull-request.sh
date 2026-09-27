#!/usr/bin/env bash
set -euo pipefail

# Update an automation branch's existing PR, or create one when none is open.
# The branch must already have been pushed before this script is called.

if [[ $# -ne 2 ]]; then
	printf 'Usage: %s TITLE BODY\n' "$0" >&2
	exit 2
fi

: "${BRANCH:?BRANCH is required}"
: "${FORGEJO_TOKEN:?FORGEJO_TOKEN is required}"

server="${FORGEJO_SERVER_URL:-${GITHUB_SERVER_URL:-}}"
repo="${FORGEJO_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
: "${server:?FORGEJO_SERVER_URL or GITHUB_SERVER_URL is required}"
: "${repo:?FORGEJO_REPOSITORY or GITHUB_REPOSITORY is required}"

title=$1
body=$2
api="$server/api/v1/repos/$repo"
headers=(--header "Authorization: token $FORGEJO_TOKEN")

open_pr=$(curl --fail --silent --get "$api/pulls" \
	"${headers[@]}" \
	--data-urlencode 'state=open' \
	--data-urlencode 'base=main' \
	--data-urlencode 'limit=50' |
	jq -r --arg branch "$BRANCH" 'map(select(.head.ref == $branch))[0].number // empty')

if [[ -n "$open_pr" ]]; then
	printf 'Updated existing Forgejo pull request #%s\n' "$open_pr"
	exit 0
fi

payload=$(jq -cn \
	--arg head "$BRANCH" \
	--arg title "$title" \
	--arg body "$body" \
	'{head: $head, base: "main", title: $title, body: $body}')
curl --fail --silent --show-error --request POST "$api/pulls" \
	"${headers[@]}" \
	--header 'Content-Type: application/json' \
	--data "$payload"
