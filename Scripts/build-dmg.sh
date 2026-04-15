#!/usr/bin/env bash
# Build a signed, notarized, stapled DMG of the macOS app for distribution.
#
# Requires:
#   - "Developer ID Application: DGR Labs, LLC (2CTUXD4C44)" in the keychain
#   - notarytool keychain profile named "bezelbub" (create with:
#     xcrun notarytool store-credentials bezelbub --apple-id ID --team-id 2CTUXD4C44 --password APP_SPECIFIC_PW)
#
# Usage: Scripts/build-dmg.sh [version]
#   version defaults to MARKETING_VERSION in project.yml

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${1:-$(grep -m1 'MARKETING_VERSION:' project.yml | sed -E 's/.*"(.+)"/\1/')}"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE="$BUILD_DIR/Bezelbub.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_SRC="$BUILD_DIR/dmg-src"
DMG_PATH="$BUILD_DIR/Bezelbub-$VERSION.dmg"
TEAM_ID="2CTUXD4C44"
SIGNING_IDENTITY="Developer ID Application: DGR Labs, LLC ($TEAM_ID)"
NOTARY_PROFILE="bezelbub"

echo "==> Building Bezelbub $VERSION"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving"
xcodebuild archive \
    -project Bezelbub.xcodeproj \
    -scheme Bezelbub \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -quiet

echo "==> Exporting for Developer ID"
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -quiet

APP_PATH="$EXPORT_DIR/Bezelbub.app"
test -d "$APP_PATH" || { echo "App not found at $APP_PATH"; exit 1; }

echo "==> Staging DMG contents"
mkdir -p "$DMG_SRC"
cp -R "$APP_PATH" "$DMG_SRC/"
ln -s /Applications "$DMG_SRC/Applications"

echo "==> Creating DMG"
hdiutil create \
    -volname "Bezelbub $VERSION" \
    -srcfolder "$DMG_SRC" \
    -format UDZO \
    -ov \
    "$DMG_PATH" \
    >/dev/null

echo "==> Signing DMG"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

echo "==> Submitting for notarization (this takes a few minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling notarization"
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying"
spctl --assess --type open --context context:primary-signature "$DMG_PATH"
codesign --verify --deep --strict "$APP_PATH"

ls -lh "$DMG_PATH"
echo "Done: $DMG_PATH"
