#!/bin/bash
set -e

APP_NAME="CacheCleaner"
DMG_NAME="CacheCleaner-1.0"
SOURCE_DIR="$HOME/CacheCleaner"
DMG_DIR="$SOURCE_DIR/dmg-contents"
DMG_PATH="$SOURCE_DIR/$DMG_NAME.dmg"

echo "Creating DMG for $APP_NAME..."

# Clean up previous builds
rm -rf "$DMG_DIR"
rm -f "$DMG_PATH"

# Create DMG contents directory
mkdir -p "$DMG_DIR"

# Copy app to DMG contents
cp -r "$SOURCE_DIR/$APP_NAME.app" "$DMG_DIR/"

# Create symlink to Applications
ln -s /Applications "$DMG_DIR/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# Clean up
rm -rf "$DMG_DIR"

echo ""
echo "✓ DMG created: $DMG_PATH"
echo ""
ls -lh "$DMG_PATH"
