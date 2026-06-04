#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-}"
VERSION="0.1.0"
TAG=""
ASSET=""
DRAFT=false
PRERELEASE=false

usage() {
  cat <<USAGE
Usage: $0 --repo OWNER/REPO --version VERSION --asset PATH [--draft] [--prerelease]

Creates or reuses a GitHub Release and uploads the DMG as a release asset
through the GitHub REST API. This is a fallback for machines without gh.

Environment:
  GITHUB_TOKEN  Personal access token with contents write permission.
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
    --version)
      VERSION="$2"
      shift 2
      ;;
    --asset)
      ASSET="$2"
      shift 2
      ;;
    --draft)
      DRAFT=true
      shift
      ;;
    --prerelease)
      PRERELEASE=true
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

TAG="v$VERSION"

if [[ -z "$REPO" || "$REPO" != */* || -z "$ASSET" ]]; then
  usage
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "error: GITHUB_TOKEN is required." >&2
  exit 2
fi

cd "$ROOT_DIR"

if [[ ! -f "$ASSET" ]]; then
  echo "error: asset not found: $ASSET" >&2
  exit 3
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag "$TAG"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git push origin "$TAG"
else
  echo "warning: no origin remote is configured; skipping tag push." >&2
fi

RELEASE_RESPONSE="$(github_api GET "https://api.github.com/repos/$REPO/releases/tags/$TAG")"
UPLOAD_URL="$(printf '%s' "$RELEASE_RESPONSE" | json_field upload_url)"
HTML_URL="$(printf '%s' "$RELEASE_RESPONSE" | json_field html_url)"

if [[ -z "$UPLOAD_URL" ]]; then
  BODY="Release $TAG for Roon Lyric macOS."
  PAYLOAD="{\"tag_name\":$(json_escape "$TAG"),\"name\":$(json_escape "$TAG"),\"body\":$(json_escape "$BODY"),\"draft\":$DRAFT,\"prerelease\":$PRERELEASE}"
  CREATE_RESPONSE="$(github_api POST "https://api.github.com/repos/$REPO/releases" "$PAYLOAD")"
  UPLOAD_URL="$(printf '%s' "$CREATE_RESPONSE" | json_field upload_url)"
  HTML_URL="$(printf '%s' "$CREATE_RESPONSE" | json_field html_url)"
  if [[ -z "$UPLOAD_URL" ]]; then
    echo "error: failed to create release: $(printf '%s' "$CREATE_RESPONSE" | json_error)" >&2
    exit 4
  fi
fi

UPLOAD_URL="${UPLOAD_URL%%\{*}"
ASSET_NAME="$(basename "$ASSET")"

ASSETS_RESPONSE="$(github_api GET "https://api.github.com/repos/$REPO/releases/tags/$TAG")"
EXISTING_ASSET_ID="$(printf '%s' "$ASSETS_RESPONSE" | /usr/bin/ruby -rjson -e 'data = JSON.parse(STDIN.read); name = ARGV[0]; asset = (data["assets"] || []).find { |item| item["name"] == name }; puts asset["id"] if asset' "$ASSET_NAME")"
if [[ -n "$EXISTING_ASSET_ID" ]]; then
  github_api DELETE "https://api.github.com/repos/$REPO/releases/assets/$EXISTING_ASSET_ID" >/dev/null
fi

UPLOAD_RESPONSE="$(/usr/bin/curl -sS -X POST "$UPLOAD_URL?name=$ASSET_NAME" \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@$ASSET")"

DOWNLOAD_URL="$(printf '%s' "$UPLOAD_RESPONSE" | json_field browser_download_url)"
if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "error: failed to upload asset: $(printf '%s' "$UPLOAD_RESPONSE" | json_error)" >&2
  exit 5
fi

echo "Release: $HTML_URL"
echo "Asset: $DOWNLOAD_URL"
