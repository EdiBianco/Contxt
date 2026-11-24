#!/bin/sh
# Contxt installer. Downloads the latest release with curl, which does not set
# the macOS quarantine flag, so Gatekeeper never shows its "can't be opened" warning.
#   curl -fsSL https://thecontxt.com/install.sh | sh
set -eu

REPO="EdiBianco/Contxt"
DEST="/Applications"

fail() { echo "Contxt install failed: $1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Contxt is for macOS only."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Looking up the latest Contxt release..."
url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | sed -n 's/.*"browser_download_url": *"\([^"]*-macOS\.zip\)".*/\1/p' | head -n 1)"
[ -n "$url" ] || fail "could not find a release download."

echo "Downloading $url"
curl -fL --progress-bar "$url" -o "$tmp/Contxt.zip" || fail "download failed."
ditto -x -k "$tmp/Contxt.zip" "$tmp" || fail "could not unpack the download."
[ -d "$tmp/Contxt.app" ] || fail "the download did not contain Contxt.app."

if pgrep -x Contxt >/dev/null 2>&1; then
  echo "Quitting the running Contxt..."
  pkill -x Contxt || true
  sleep 1
fi

rm -rf "$DEST/Contxt.app" || fail "could not replace $DEST/Contxt.app (try with sudo)."
ditto "$tmp/Contxt.app" "$DEST/Contxt.app" || fail "could not copy to $DEST."
xattr -dr com.apple.quarantine "$DEST/Contxt.app" 2>/dev/null || true

echo "Installed Contxt in $DEST. Opening it..."
open "$DEST/Contxt.app"
