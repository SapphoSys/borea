#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$ROOT_DIR/.build/Borea.app"
ZIP_PATH="$DIST_DIR/Borea-$VERSION-macOS.zip"

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/build-app.sh"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Packaged $ZIP_PATH"
