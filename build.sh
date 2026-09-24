#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> [1/6] Building universal helper binaries (device_helper & airtraffic_host)..."
make clean
make all

APP_NAME="FaceLift"
APP_VERSION="${APP_VERSION:-1.0.1}"
# SIGN_IDENTITY: "-" keeps the current ad-hoc signing for local development.
# Set it to "Developer ID Application: ..." (or let CI set it) to sign for
# distribution. NOTARIZE=1 additionally notarizes and staples when the
# App Store Connect API key env vars (ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID)
# are present.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARIZE="${NOTARIZE:-0}"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
BIN_DIR="${RESOURCES_DIR}/bin"
LIB_DIR="${RESOURCES_DIR}/lib"

echo "==> [2/6] Scaffolding ${APP_NAME}.app bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$BIN_DIR" "$LIB_DIR"

# Write Info.plist (APP_VERSION expands from the environment; CI sets it from
# the git tag so the bundle version always matches the release.)
cat << EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>FaceLift</string>
    <key>CFBundleIdentifier</key>
    <string>com.jetems.facelift</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FaceLift</string>
    <key>CFBundleDisplayName</key>
    <string>FaceLift</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>11</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "==> [3/6] Bundling universal tools & libraries..."
# Copy App Icon
if [ -f "dmg_assets/AppIcon.icns" ]; then
    cp "dmg_assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Copy universal device_helper and airtraffic_host. Device discovery and log
# streaming both run through device_helper, which talks to MobileDevice.framework
# directly, so the bundle needs no libimobiledevice tooling.
cp build/device_helper "$BIN_DIR/"
cp build/airtraffic_host "$BIN_DIR/"

# Copy python backend scripts
cp apply_card_skin.py "$RESOURCES_DIR/"
cp facelift.py "$RESOURCES_DIR/"
cp facelift_backend.py "$RESOURCES_DIR/"
cp card_assets.py "$RESOURCES_DIR/"
cp Resources/DefaultPasscodePoster.png "$RESOURCES_DIR/"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$RESOURCES_DIR/"

# A bundle without these cannot talk to a device at all, so fail here instead
# of shipping an app that reports "No iPhone found" for every user.
for tool in device_helper airtraffic_host; do
    if [ ! -x "${BIN_DIR}/${tool}" ]; then
        echo "ERROR: ${BIN_DIR}/${tool} is missing from the bundle." >&2
        exit 1
    fi
done

echo "==> [4/6] Compiling universal Swift binary (arm64 + x86_64)..."
# A macOS 26+ SDK is required to compile the Liquid Glass UI (glassEffect and
# friends ship in MacOSX26/27 SDKs); the binary still targets macOS 14 at
# runtime via availability checks.
if [ -z "${SWIFT_SDK:-}" ]; then
    SWIFT_SDK="$(xcrun --sdk macosx --show-sdk-path)"
    CLT_SWIFTUI_SDK=""
    for sdk in MacOSX27.sdk MacOSX26.sdk; do
        if [ -d "/Library/Developer/CommandLineTools/SDKs/$sdk" ]; then
            CLT_SWIFTUI_SDK="/Library/Developer/CommandLineTools/SDKs/$sdk"
            break
        fi
    done
    if [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -n "$CLT_SWIFTUI_SDK" ]; then
        SWIFT_SDK="$CLT_SWIFTUI_SDK"
    fi
fi
SWIFT_SOURCES=$(find App Model Workspaces -name '*.swift' | sort)
swiftc -sdk "$SWIFT_SDK" -O -parse-as-library -target arm64-apple-macosx14.0 $SWIFT_SOURCES -o build/FaceLift_arm64
swiftc -sdk "$SWIFT_SDK" -O -parse-as-library -target x86_64-apple-macosx14.0 $SWIFT_SOURCES -o build/FaceLift_x86_64
lipo -create -output "${MACOS_DIR}/FaceLift" build/FaceLift_arm64 build/FaceLift_x86_64
chmod +x "${MACOS_DIR}/FaceLift"

echo "==> [5/6] Setting permissions and signing ${APP_NAME}.app bundle..."
chmod -R 755 "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true
if [ "$SIGN_IDENTITY" != "-" ]; then
    echo "    Signing with: $SIGN_IDENTITY (Hardened Runtime)"
    # Nested Mach-O helpers must be signed before the enclosing bundle.
    for helper in "$BIN_DIR"/*; do
        codesign --force --options runtime --timestamp \
            --sign "$SIGN_IDENTITY" "$helper"
    done
    codesign --force --deep --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
    if [ "$NOTARIZE" = "1" ]; then
        echo "    Notarizing ${APP_NAME}.app..."
        NOTARY_ZIP="build/${APP_NAME}-notary.zip"
        ditto -c -k --keepParent "$APP_DIR" "$NOTARY_ZIP"
        xcrun notarytool submit "$NOTARY_ZIP" \
            --key "$ASC_KEY_PATH" \
            --key-id "$ASC_KEY_ID" \
            --issuer "$ASC_ISSUER_ID" \
            --wait
        rm -f "$NOTARY_ZIP"
        xcrun stapler staple "$APP_DIR"
    fi
else
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> [6/6] Generating styled DMG (${APP_NAME}.dmg)..."
DMG_STAGING="/tmp/facelift_dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"

rm -f "build/${APP_NAME}.dmg"

if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "FaceLift" \
        --background "dmg_assets/background_700.png" \
        --window-pos 200 120 \
        --window-size 700 460 \
        --icon-size 110 \
        --icon "FaceLift.app" 175 220 \
        --hide-extension "FaceLift.app" \
        --app-drop-link 525 220 \
        --add-file "README.txt" "dmg_assets/README.txt" 350 360 \
        --filesystem APFS \
        --overwrite \
        "build/${APP_NAME}.dmg" \
        "$DMG_STAGING"
else
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname "FaceLift" -srcfolder "$DMG_STAGING" -ov -format UDZO "build/${APP_NAME}.dmg"
fi

# Note: Apple's stapler only supports .app bundles and .pkg installers, not
# raw disk images. The app inside was already stapled before packaging, and
# Gatekeeper reads that ticket once the DMG is mounted.

echo "============================================================"
echo "🎉 SUCCESS: build/${APP_NAME}.dmg is ready!"
echo "============================================================"
