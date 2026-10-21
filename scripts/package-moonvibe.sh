#!/bin/bash
# Build Moonvibe and package it as a self-contained DMG for Apple Silicon Macs,
# with the Sparkle appcast that announces it: build/release/Moonvibe-<version>.dmg
# and build/release/appcast.xml, both for the version's GitHub release.
#
# Without a Developer ID, the app is signed ad hoc: Gatekeeper asks the user to
# confirm the first launch (see README.md). Updates are verified with EdDSA
# instead: sign_update signs the DMG and the appcast with the private key in
# the login Keychain, which only the maintainer has.
#
# The DMG window (background, icon positions, volume icon) comes from dmgbuild,
# which the first run installs from PyPI into build/dmgbuild-env. Its layout is
# in scripts/dmg: settings.py, and make-background.swift for the background.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

VERSION=$(cat app/moonvibe-version.txt)
RELEASE_DIR=build/release
DMG=$RELEASE_DIR/Moonvibe-$VERSION.dmg

# The bundle is staged outside the source tree: in a folder synced by iCloud
# Drive, the file provider keeps tagging bundles with extended attributes
# that codesign rejects
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
APP=$STAGING/Moonvibe.app

fail()
{
    echo "$1" 1>&2
    exit 1
}

./build-mac.sh

echo "Staging Moonvibe $VERSION"
# macdeployqt rewrites the bundle in place, so it works on a copy: the dev
# build keeps linking against Homebrew's Qt
cp -R build/app/Moonvibe.app "$STAGING/"
xattr -cr "$APP"

# No QML modules: the SwiftUI shell loads no QML, which only serves the
# command line modes and the MOONVIBE_QML fallback of development builds.
# Homebrew splits Qt into one prefix per module and links every framework
# into /opt/homebrew/lib, which lets macdeployqt resolve what plugins need.
echo "Bundling Qt"
macdeployqt "$APP" -libpath=/opt/homebrew/lib || fail "macdeployqt failed!"

# Plugins Moonvibe never uses, whose Qt modules (QtPdf, QtVirtualKeyboard)
# macdeployqt can't resolve
rm -f "$APP/Contents/PlugIns/imageformats/libqpdf.dylib"
rm -rf "$APP/Contents/PlugIns/platforminputcontexts"

# Sparkle's XPC services only serve sandboxed apps
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/XPCServices" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"

# A library's own install name (otool -D) doesn't matter for loading: only
# the libraries it loads must come from the bundle
echo "Checking that nothing still loads from Homebrew"
while IFS= read -r -d '' binary; do
    file "$binary" | grep -q "Mach-O" || continue
    ownName=$(otool -D "$binary" | tail -n +2)
    if otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -v -x -F "${ownName:-none}" | grep -q "^/opt/homebrew/"; then
        otool -L "$binary" | grep "/opt/homebrew/" 1>&2
        fail "$binary still loads libraries from Homebrew"
    fi
done < <(find "$APP" -type f -print0)

echo "Signing ad hoc"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP" || fail "Signing failed!"
codesign --verify --deep --strict "$APP" || fail "Signature check failed!"

echo "Creating the DMG"
# dmgbuild, pinned, in a virtual environment of its own under build/
DMGBUILD_ENV=build/dmgbuild-env
if [ ! -x "$DMGBUILD_ENV/bin/dmgbuild" ]; then
    python3 -m venv "$DMGBUILD_ENV" || fail "Couldn't create the dmgbuild environment"
    "$DMGBUILD_ENV/bin/pip" install --quiet --disable-pip-version-check dmgbuild==1.6.5 || fail "Couldn't install dmgbuild"
fi
mkdir -p "$RELEASE_DIR"
"$DMGBUILD_ENV/bin/dmgbuild" -s scripts/dmg/settings.py \
    -D app="$APP" -D background=scripts/dmg/background.tiff -D volume_icon=app/moonvibe.icns \
    "Moonvibe $VERSION" "$DMG" || fail "dmgbuild failed!"

# The release notes are the version's CHANGELOG.md section. sign_update may ask
# for access to the key in the login Keychain.
echo "Creating the appcast"
SPARKLE_BIN=libs/sparkle/bin
APPCAST=$RELEASE_DIR/appcast.xml
rm -f "$APPCAST"
ENCLOSURE=$("$SPARKLE_BIN/sign_update" "$DMG") || fail "Couldn't sign the DMG: is Sparkle's key in the login Keychain?"
MINIMUM_MACOS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")
python3 -I scripts/make-appcast.py "$VERSION" \
    "https://github.com/ciremek/moonvibe/releases/download/moonvibe-v$VERSION/Moonvibe-$VERSION.dmg" \
    "$ENCLOSURE" "$MINIMUM_MACOS" CHANGELOG.md > "$STAGING/appcast.xml" || fail "Couldn't create the appcast"
"$SPARKLE_BIN/sign_update" "$STAGING/appcast.xml" >/dev/null || fail "Couldn't sign the appcast"
cp "$STAGING/appcast.xml" "$APPCAST"

echo "Built: $(pwd)/$DMG"
echo "Built: $(pwd)/$APPCAST"
echo "Attach both to the moonvibe-v$VERSION release: Moonvibe reads the appcast of the latest release"
