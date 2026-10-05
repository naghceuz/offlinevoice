#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_APP="$BUILD_DIR/Build/Products/Release/OfflineVoice.app"
DIST_DIR="$ROOT_DIR/dist"
# Stage and build the DMG under $TMPDIR, not inside the repo: hdiutil hands the
# copy to the diskimages-helper system process, which has no access to
# TCC-protected folders (Desktop, Documents, …) and fails with "Operation not
# permitted" when the checkout lives there.
DMG_STAGING="${TMPDIR:-/tmp}/offlinevoice-dmg-staging"
ENTITLEMENTS="$ROOT_DIR/Resources/OfflineVoice.entitlements"

# Distribution signing is opt-in via env vars so a checkout with no Apple
# Developer ID still builds a working ad-hoc DMG.
#   DEVELOPER_ID_IDENTITY  e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE         keychain profile from `xcrun notarytool store-credentials`
#                          (omit to sign + staticly verify but skip notarization)
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# A Developer ID build is the release artifact: it goes to dist/release/ and is
# published as a GitHub Release asset (the website's /api/download redirects
# there — the DMG is far too large for Vercel's upload limit now that the speech
# model ships inside the app). An ad-hoc (unsigned) build goes to a separate
# local-preview path so it can never be mistaken for the release.
if [[ -n "$DEVELOPER_ID_IDENTITY" ]]; then
  OUTPUT_DIR="$DIST_DIR/release"
  DMG_PATH="$OUTPUT_DIR/OfflineVoice-mac.dmg"
else
  OUTPUT_DIR="$DIST_DIR/local-preview"
  DMG_PATH="$OUTPUT_DIR/OfflineVoice-unsigned.dmg"
fi

cd "$ROOT_DIR"

# Build order: verified model files → regenerate the project → build. The model
# is bundled as a folder reference, so it must be on disk before the build.
"$ROOT_DIR/scripts/fetch-models.sh"
xcodegen generate

xcodebuild \
  -project OfflineVoice.xcodeproj \
  -scheme OfflineVoice \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build

if [[ ! -d "$RELEASE_APP" ]]; then
  echo "Release app was not produced at $RELEASE_APP" >&2
  exit 1
fi

mkdir -p "$DIST_DIR" "$OUTPUT_DIR"
rm -rf "$DMG_STAGING" "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$DMG_STAGING"

cp -R "$RELEASE_APP" "$DMG_STAGING/OfflineVoice.app"
STAGED_APP="$DMG_STAGING/OfflineVoice.app"
ln -s /Applications "$DMG_STAGING/Applications"

# sherpa-onnx's "static" xcframeworks still carry stub .framework bundles that
# Xcode embeds, although the code is linked statically and the main binary
# never loads them (otool -L lists no reference). One of them (onnxruntime)
# even contains a self-referential symlink (Versions/A/A -> A) that makes
# `codesign --verify --deep` fail. Strip every embedded framework the binary
# does not actually link against.
MAIN_BIN="$STAGED_APP/Contents/MacOS/OfflineVoice"
for fw in "$STAGED_APP"/Contents/Frameworks/*.framework; do
  [[ -d "$fw" ]] || continue
  name="$(basename "$fw" .framework)"
  if otool -L "$MAIN_BIN" | grep -q "/$name.framework/"; then
    echo "==> Keeping embedded framework $name.framework (linked)"
  else
    echo "==> Removing unreferenced embedded framework $name.framework"
    rm -rf "$fw"
  fi
done
rmdir "$STAGED_APP/Contents/Frameworks" 2>/dev/null || true

if [[ -f "$ROOT_DIR/Resources/OfflineVoice.icns" ]]; then
  cp "$ROOT_DIR/Resources/OfflineVoice.icns" "$DMG_STAGING/.VolumeIcon.icns"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$DMG_STAGING"
  fi
fi

if [[ -n "$DEVELOPER_ID_IDENTITY" ]]; then
  echo "==> Developer ID signing with Hardened Runtime"
  # Sign nested code (frameworks / dylibs) inner-to-outer before the .app so the
  # outer signature is valid without the deprecated --deep flag.
  while IFS= read -r -d '' nested; do
    codesign --force --options runtime --timestamp \
      --sign "$DEVELOPER_ID_IDENTITY" "$nested"
  done < <(find "$STAGED_APP/Contents/Frameworks" \
    \( -name "*.framework" -o -name "*.dylib" \) -print0 2>/dev/null || true)

  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVELOPER_ID_IDENTITY" "$STAGED_APP"

  echo "==> Verifying app signature"
  codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
  spctl -a -t exec -vv "$STAGED_APP" || echo "(spctl will pass once notarized)"
else
  echo "==> No DEVELOPER_ID_IDENTITY set; ad-hoc signing (unsigned preview build)"
  echo "    This is a local, UNSIGNED preview and will NOT be published."
  echo "    Output goes to $DMG_PATH (the website download is left untouched)."
  # Ad-hoc signing helps local unsigned builds open consistently. It is not notarization.
  codesign --force --deep --sign - "$STAGED_APP"
fi

# Versioned volume name ("OfflineVoice 0.5.0"): clearer in Finder, and a bare
# "OfflineVoice" mount point was once left in a state where hdiutil could no
# longer mount it ("Operation not permitted") after an interrupted run.
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$STAGED_APP/Contents/Info.plist")"
DMG_TMP="${TMPDIR:-/tmp}/offlinevoice-$(basename "$DMG_PATH")"
rm -f "$DMG_TMP"
hdiutil create \
  -volname "OfflineVoice $APP_VERSION" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_TMP"
mv -f "$DMG_TMP" "$DMG_PATH"

if [[ -n "$DEVELOPER_ID_IDENTITY" ]]; then
  echo "==> Signing DMG"
  codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$DMG_PATH"

  if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "==> Submitting DMG for notarization (this can take a few minutes)"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl -a -t open --context context:primary-signature -vv "$DMG_PATH" || true
  else
    echo "==> NOTARY_PROFILE not set; skipping notarization + stapling."
    echo "    Gatekeeper will still block this DMG on other Macs until notarized."
  fi
fi

# Write a bare filename (not an absolute path) so `shasum -c` works from any
# checkout or machine, not just the one that produced the DMG.
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")
echo "Created $DMG_PATH"
