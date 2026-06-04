#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-}"
PRIVATE=false
DESCRIPTION="macOS desktop lyrics companion for Roon"

usage() {
  cat <<USAGE
Usage: $0 --repo OWNER/REPO [--private]

Creates or reuses a GitHub repository through the GitHub REST API, attaches it
as git origin, and pushes main. This is a fallback for machines without gh.

Environment:
  GITHUB_TOKEN  Personal access token with repo creation/write permission.
USAGE
}

json_escape() {
  /usr/bin/ruby -rjson -e 'print ARGV[0].to_json' "$1"
}

github_api() {
  local method="$1"
  local url="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    /usr/bin/curl -sS -X "$method" "$url" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    /usr/bin/curl -sS -X "$method" "$url" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28"
  fi
}

json_field() {
  /usr/bin/ruby -rjson -e 'data = JSON.parse(STDIN.read); value = data.dig(*ARGV); puts value if value' "$@"
}

json_error() {
  /usr/bin/ruby -rjson -e 'data = JSON.parse(STDIN.read); puts(data["message"] || data.inspect)' 2>/dev/null || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --private)
      PRIVATE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$REPO" || "$REPO" != */* ]]; then
  usage
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "error: GITHUB_TOKEN is required." >&2
  exit 2
fi

cd "$ROOT_DIR"

if ! git config --get user.name >/dev/null; then
  echo "error: git user.name is not configured." >&2
  echo "       Run: git config user.name \"Your Name\"" >&2
  exit 3
fi

if ! git config --get user.email >/dev/null; then
  echo "error: git user.email is not configured." >&2
  echo "       Run: git config user.email \"you@example.com\"" >&2
  exit 3
fi

OWNER="${REPO%%/*}"
NAME="${REPO#*/}"
PRIVATE_JSON="$PRIVATE"

echo "Checking GitHub authentication..."
USER_RESPONSE="$(github_api GET "https://api.github.com/user")"
LOGIN="$(printf '%s' "$USER_RESPONSE" | json_field login)"
if [[ -z "$LOGIN" ]]; then
  echo "error: GitHub authentication failed: $(printf '%s' "$USER_RESPONSE" | json_error)" >&2
  exit 4
fi
echo "Authenticated as $LOGIN"

echo "Checking repository $REPO..."
REPO_RESPONSE="$(github_api GET "https://api.github.com/repos/$REPO")"
HTML_URL="$(printf '%s' "$REPO_RESPONSE" | json_field html_url)"

if [[ -z "$HTML_URL" ]]; then
  PAYLOAD="{\"name\":$(json_escape "$NAME"),\"private\":$PRIVATE_JSON,\"description\":$(json_escape "$DESCRIPTION"),\"has_wiki\":false}"
  if [[ "$OWNER" == "$LOGIN" ]]; then
    CREATE_URL="https://api.github.com/user/repos"
  else
    CREATE_URL="https://api.github.com/orgs/$OWNER/repos"
  fi
  CREATE_RESPONSE="$(github_api POST "$CREATE_URL" "$PAYLOAD")"
  HTML_URL="$(printf '%s' "$CREATE_RESPONSE" | json_field html_url)"
  if [[ -z "$HTML_URL" ]]; then
    echo "error: failed to create repository: $(printf '%s' "$CREATE_RESPONSE" | json_error)" >&2
    exit 5
  fi
fi

echo "Repository ready: $HTML_URL"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "https://github.com/$REPO.git"
else
  git remote add origin "https://github.com/$REPO.git"
fi

git branch -M main
git push -u origin main
