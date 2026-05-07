#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?usage: Scripts/create-github-release.sh <version>}"
TAG="v$VERSION"
ZIP_PATH="$ROOT_DIR/dist/Borea-$VERSION-macOS.zip"

command -v gh >/dev/null 2>&1 || {
  echo "error: GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
}

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/package-release.sh" "$VERSION"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag "$TAG"
fi

git push origin "$TAG"

gh release create "$TAG" "$ZIP_PATH" \
  --title "Borea $VERSION" \
  --generate-notes
