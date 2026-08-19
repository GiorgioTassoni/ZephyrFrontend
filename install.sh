#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/build/linux/x64/release/bundle" ]; then
    APP_DIR="$SCRIPT_DIR/build/linux/x64/release/bundle"
else
    APP_DIR="$SCRIPT_DIR"
fi

ICON_SRC="$APP_DIR/data/flutter_assets/References/Zephyr.png"
if [ ! -f "$ICON_SRC" ]; then
    ICON_SRC="$SCRIPT_DIR/References/Zephyr.png"
fi

echo "Installing Zephyr from $APP_DIR..."

# 1. Ensure user directories exist
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/icons/hicolor/512x512/apps"
mkdir -p "$HOME/.local/bin"

# 2. Copy icon to user icon theme
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$HOME/.local/share/icons/hicolor/512x512/apps/com.giorgiotassoni.zephyr.png"
    cp "$ICON_SRC" "$HOME/.local/share/icons/hicolor/512x512/apps/zephyr.png"
fi

# 3. Create .desktop file
cat << EOF > "$HOME/.local/share/applications/com.giorgiotassoni.zephyr.desktop"
[Desktop Entry]
Version=1.0
Name=Zephyr
GenericName=Music Player
Comment=Self-hosted Music Streaming Player
Exec="$APP_DIR/frontend" %u
Icon=com.giorgiotassoni.zephyr
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;Music;
MimeType=x-scheme-handler/zephyr;
StartupWMClass=com.giorgiotassoni.zephyr
EOF

chmod +x "$HOME/.local/share/applications/com.giorgiotassoni.zephyr.desktop"

# 4. Optional CLI command link in ~/.local/bin/zephyr
ln -sf "$APP_DIR/frontend" "$HOME/.local/bin/zephyr"

# 5. Refresh desktop and icon database
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
gtk-update-icon-cache "$HOME/.local/share/icons/hicolor/" 2>/dev/null || true

echo "✓ Zephyr installed successfully!"
echo "You can now launch Zephyr from your Application Menu or by typing 'zephyr'."
