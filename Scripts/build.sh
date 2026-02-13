#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="BrightBar"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
VERSION="1.0.0"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   Building $APP_NAME v$VERSION       ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ───────────────────────────────────────────
# 1. Build with Swift Package Manager
# ───────────────────────────────────────────
echo "→ Compiling (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

EXECUTABLE="$BUILD_DIR/release/$APP_NAME"

if [ ! -f "$EXECUTABLE" ]; then
    EXECUTABLE=$(find "$BUILD_DIR" -name "$APP_NAME" -type f -perm +111 | grep release | head -1)
    if [ -z "$EXECUTABLE" ]; then
        echo "✗ Could not find built executable"
        exit 1
    fi
fi
echo "  ✓ Compiled: $EXECUTABLE"

# ───────────────────────────────────────────
# 2. Create .app bundle
# ───────────────────────────────────────────
echo "→ Creating app bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Copy app icon
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "  ✓ App icon included"
fi

# Copy entitlements (embedded for reference)
if [ -f "$PROJECT_DIR/Entitlements/BrightBar.entitlements" ]; then
    ENTITLEMENTS="$PROJECT_DIR/Entitlements/BrightBar.entitlements"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "  ✓ Bundle: $APP_BUNDLE"

# ───────────────────────────────────────────
# 3. Ad-hoc code sign
# ───────────────────────────────────────────
echo "→ Code signing (ad-hoc)..."

SIGN_FLAGS="--force --deep --options runtime"

if [ -n "${ENTITLEMENTS:-}" ]; then
    codesign $SIGN_FLAGS --entitlements "$ENTITLEMENTS" --sign - "$APP_BUNDLE"
else
    codesign $SIGN_FLAGS --sign - "$APP_BUNDLE"
fi

echo "  ✓ Signed (ad-hoc)"

# ───────────────────────────────────────────
# 4. Create DMG
# ───────────────────────────────────────────
echo "→ Creating DMG..."

# Clean previous DMG
rm -f "$DMG_PATH"

# Create temporary folder for DMG contents
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app into staging
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" \
    2>&1 | grep -v "^$"

# Clean staging
rm -rf "$DMG_STAGING"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1 | xargs)
echo "  ✓ DMG: $DMG_PATH ($DMG_SIZE)"

# ───────────────────────────────────────────
# Done
# ───────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║   Build complete!                    ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  App:  $APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
echo ""
echo "  Run:     open \"$APP_BUNDLE\""
echo "  Install: open \"$DMG_PATH\"  →  drag to Applications"
echo ""
