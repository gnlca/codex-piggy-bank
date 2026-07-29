#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Codex Piggy Bank"
VERSION="1.0.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/ReleaseDerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$DIST_DIR/Codex-Piggy-Bank-$VERSION-universal.dmg"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"
ENTITLEMENTS_PATH="$ROOT_DIR/Configuration/CodexPiggyBank.entitlements"

SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-codex-piggy-bank-notary}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Manca DEVELOPER_ID_APPLICATION." >&2
  echo "Esempio: export DEVELOPER_ID_APPLICATION='Developer ID Application: Nome (TEAMID)'" >&2
  exit 1
fi

if ! security find-identity -p codesigning -v | grep -F "$SIGNING_IDENTITY" >/dev/null; then
  echo "L’identità '$SIGNING_IDENTITY' non è presente nel Portachiavi." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Il profilo notarytool '$NOTARY_PROFILE' non è configurato o non è valido." >&2
  echo "Crealo con: xcrun notarytool store-credentials '$NOTARY_PROFILE'" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$ROOT_DIR/CodexPiggyBank.xcodeproj" \
  -scheme CodexPiggyBank \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE" 2>&1 \
  | grep -Fq "com.apple.security.personal-information.calendars"
lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -q "arm64"
lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -q "x86_64"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign \
  --force \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

echo "Creato: $DMG_PATH"
