#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-}"
VISIBILITY="--public"

usage() {
  cat <<USAGE
Usage: $0 --repo OWNER/REPO [--private]

This script checks GitHub CLI authentication, creates the GitHub repository
when needed, attaches it as origin, and pushes the current main branch.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --private)
      VISIBILITY="--private"
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

if [[ -z "$REPO" ]]; then
  usage
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: GitHub CLI (gh) is not installed." >&2
  echo "       Install it with: brew install gh" >&2
  exit 2
fi

cd "$ROOT_DIR"

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Starting browser login..."
  gh auth login -h github.com -p https -w
fi

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

if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "GitHub repository exists: $REPO"
else
  gh repo create "$REPO" "$VISIBILITY" --source=. --remote=origin --description "macOS desktop lyrics companion for Roon" --disable-wiki
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "https://github.com/$REPO.git"
fi

git branch -M main
git push -u origin main
