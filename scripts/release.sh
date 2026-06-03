#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, and publish a Flick release.
# Usage: ./scripts/release.sh v1.0.0
#
# Required env:
#   DEVELOPMENT_TEAM          10-character Apple Team ID
#
# Notarization (pick one):
#   APPLE_API_KEY_ID + APPLE_API_ISSUER_ID + APPLE_API_KEY_P8
#   NOTARY_KEYCHAIN_PROFILE   e.g. "flick-notary" (see scripts/SETUP.md)
#
# Sparkle signing (pick one):
#   SPARKLE_PRIVATE_KEY       EdDSA private key file contents (CI)
#   (default)                 Sparkle private key in login Keychain (local)
#
# Optional:
#   SKIP_GH_RELEASE=1         Build artifacts only; do not create a GitHub release
#   SKIP_NOTARIZE=1           Skip notarytool (local unsigned smoke builds)

VERSION_TAG="${1:?Usage: ./scripts/release.sh v1.0.0}"
VERSION="${VERSION_TAG#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your 10-character Apple Team ID}"

BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Flick.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/exportOptions.plist"
UPDATES_DIR="$BUILD_DIR/updates"
SPARKLE_DIR="$BUILD_DIR/sparkle"
SPARKLE_VERSION="2.9.2"

APP="$EXPORT_PATH/Flick.app"
ZIP_NAME="Flick-${VERSION}.zip"
ZIP_PATH="$UPDATES_DIR/$ZIP_NAME"
DMG_PATH="$BUILD_DIR/Flick.dmg"
APPCAST_PATH="$ROOT/appcast.xml"

mkdir -p "$BUILD_DIR" "$EXPORT_PATH" "$UPDATES_DIR" "$SPARKLE_DIR"

sed "s/__DEVELOPMENT_TEAM__/${DEVELOPMENT_TEAM}/g" "$ROOT/scripts/exportOptions.plist" > "$EXPORT_OPTIONS"

echo "==> Resolving Swift packages"
xcodebuild -project Flick.xcodeproj -scheme Flick -resolvePackageDependencies -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages"

echo "==> Downloading Sparkle release tools ${SPARKLE_VERSION}"
SPARKLE_TAR="$SPARKLE_DIR/Sparkle-${SPARKLE_VERSION}.tar.xz"
if [[ ! -f "$SPARKLE_TAR" ]]; then
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" -o "$SPARKLE_TAR"
fi
tar -xJf "$SPARKLE_TAR" -C "$SPARKLE_DIR"
SPARKLE_BIN="$SPARKLE_DIR/bin"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"

echo "==> Archiving Flick (Release)"
xcodebuild -project Flick.xcodeproj -scheme Flick -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  archive

echo "==> Exporting Developer ID app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo "==> Creating Sparkle update zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"

sparkle_sign() {
  local file="$1"
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    echo "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$file"
  else
    "$SIGN_UPDATE" "$file"
  fi
}

echo "==> Sparkle-signing update archive"
sparkle_sign "$ZIP_PATH"

notarize_file() {
  local file="$1"
  if [[ "${SKIP_NOTARIZE:-}" == "1" ]]; then
    echo "Skipping notarization for $file"
    return 0
  fi

  local submission_id
  if [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" && -n "${APPLE_API_KEY_P8:-}" ]]; then
    local api_key_path="$BUILD_DIR/AuthKey.p8"
    printf '%s' "$APPLE_API_KEY_P8" > "$api_key_path"
    submission_id="$(
      xcrun notarytool submit "$file" --wait \
        --key "$api_key_path" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" \
        | awk '/id: / { print $2; exit }'
    )"
  elif [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    submission_id="$(
      xcrun notarytool submit "$file" --wait \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
        | awk '/id: / { print $2; exit }'
    )"
  else
    echo "Set APPLE_API_* env vars or NOTARY_KEYCHAIN_PROFILE for notarization." >&2
    exit 1
  fi

  echo "Notarized $file (id: $submission_id)"
  xcrun stapler staple "$file"
}

echo "==> Notarizing update zip"
notarize_file "$ZIP_PATH"

echo "==> Creating install DMG"
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "Flick" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 96 \
    --icon "Flick.app" 140 180 \
    --hide-extension "Flick.app" \
    --app-drop-link 400 180 \
    "$DMG_PATH" \
    "$DMG_STAGING" >/dev/null
else
  hdiutil create -volname "Flick" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
fi

echo "==> Notarizing DMG"
notarize_file "$DMG_PATH"

if [[ "${SKIP_GH_RELEASE:-}" == "1" ]]; then
  echo "Built:"
  echo "  $APP"
  echo "  $ZIP_PATH"
  echo "  $DMG_PATH"
  exit 0
fi

echo "==> Creating GitHub release ${VERSION_TAG}"
gh release create "$VERSION_TAG" \
  --repo "rasmushauschild/flick" \
  --title "Flick ${VERSION}" \
  --generate-notes \
  "$DMG_PATH" \
  "$ZIP_PATH"

RELEASE_ZIP_URL="$(gh release view "$VERSION_TAG" --repo "rasmushauschild/flick" --json assets -q ".assets[] | select(.name == \"${ZIP_NAME}\") | .url")"
if [[ -z "$RELEASE_ZIP_URL" ]]; then
  echo "Could not resolve GitHub release asset URL for ${ZIP_NAME}" >&2
  exit 1
fi

echo "==> Generating appcast entry"
APPCAST_WORK="$BUILD_DIR/appcast-work"
rm -rf "$APPCAST_WORK"
mkdir -p "$APPCAST_WORK"
cp "$ZIP_PATH" "$APPCAST_WORK/"

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" --ed-key-file - "$APPCAST_WORK"
else
  "$GENERATE_APPCAST" "$APPCAST_WORK"
fi

GENERATED_APPCAST="$APPCAST_WORK/appcast.xml"
if [[ ! -f "$GENERATED_APPCAST" ]]; then
  echo "generate_appcast did not produce appcast.xml" >&2
  exit 1
fi

python3 - "$GENERATED_APPCAST" "$APPCAST_PATH" "$RELEASE_ZIP_URL" "$VERSION" <<'PY'
import sys
import xml.etree.ElementTree as ET

generated_path, target_path, enclosure_url, version = sys.argv[1:5]
ns = {
    "sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle",
}
ET.register_namespace("sparkle", ns["sparkle"])
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")

generated = ET.parse(generated_path)
new_item = generated.find("./channel/item")
if new_item is None:
    raise SystemExit("No item found in generated appcast")

enclosure = new_item.find("enclosure")
if enclosure is not None:
    enclosure.set("url", enclosure_url)

target = ET.parse(target_path)
channel = target.getroot().find("channel")
if channel is None:
    raise SystemExit("No channel in target appcast")

for old in channel.findall("item"):
    old_version = old.find("title")
    if old_version is not None and old_version.text == f"Flick {version}":
        channel.remove(old)

channel.append(new_item)
target.write(target_path, encoding="utf-8", xml_declaration=True)
PY

echo "Updated $APPCAST_PATH"
echo "Release ${VERSION_TAG} is ready. Commit appcast.xml and push to main."
