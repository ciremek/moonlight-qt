#!/bin/bash
# Download Sparkle, the framework behind Moonvibe's updates, into libs/sparkle:
# a pinned release, checked against its SHA-256 before it is unpacked.
# Run it once after cloning, and again when VERSION changes.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
TARGET=libs/sparkle

DOWNLOAD=$(mktemp -d)
trap 'rm -rf "$DOWNLOAD"' EXIT
ARCHIVE=$DOWNLOAD/Sparkle-$VERSION.tar.xz

echo "Downloading Sparkle $VERSION"
curl -fsSL -o "$ARCHIVE" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
echo "$SHA256  $ARCHIVE" | shasum -a 256 -c - >/dev/null || { echo "Sparkle's checksum doesn't match!" 1>&2; exit 1; }

rm -rf "$TARGET"
mkdir -p "$TARGET"
tar -xJf "$ARCHIVE" -C "$TARGET"
echo "Sparkle $VERSION is in $TARGET"
