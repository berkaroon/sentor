#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/Sentor.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$DIST_DIR/Sentor.dmg"
DOWNLOADS_DMG="$HOME/Downloads/Sentor.dmg"

cd "$PROJECT_DIR"

echo "1) Building release binary..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/Sentor"
if [ ! -f "$BIN_PATH" ]; then
  echo "Error: Release binary not found at $BIN_PATH"
  exit 1
fi

echo "2) Assembling Sentor.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/Sentor"
chmod +x "$MACOS_DIR/Sentor"
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$PROJECT_DIR/Assets/sentor-logo-1024.png" "$RESOURCES_DIR/sentor-logo.png"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Sentor</string>
    <key>CFBundleDisplayName</key>
    <string>Sentor</string>
    <key>CFBundleIdentifier</key>
    <string>com.sentor.macos</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>Sentor</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF

echo "3) Ad-hoc codesigning Sentor.app..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --verbose "$APP_DIR"

echo "4) Creating Sentor.dmg..."
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_DIR" "$STAGING_DIR/Sentor.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "Sentor" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

if [ -d "$HOME/Downloads" ]; then
  echo "5) Copying Sentor.dmg to Downloads..."
  cp "$DMG_PATH" "$DOWNLOADS_DMG"
fi

echo "Done: $APP_DIR, $DMG_PATH"
