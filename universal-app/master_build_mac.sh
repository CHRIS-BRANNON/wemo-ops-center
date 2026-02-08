#!/bin/bash

# ==============================================================================
#  WEMO OPS - MASTER BUILDER (macOS Universal)
#  Version: 5.1.4-App
# ==============================================================================

# --- CRITICAL: Stop immediately if any command fails ---
set -e

# --- CONFIGURATION ---
APP_NAME="WemoOps"
SAFE_NAME="wemo-ops"
VERSION="5.1.4"
IDENTIFIER="com.qrussell.wemoops"
CLIENT_SCRIPT="wemo_ops_universal.py"
SERVER_SCRIPT="wemo_server.py"

# Paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$SCRIPT_DIR/build_mac"
DIST_DIR="$SCRIPT_DIR/dist"
STAGING_DIR="$BUILD_DIR/staging"
ROOT_DIR="$STAGING_DIR/root"
SCRIPTS_DIR="$STAGING_DIR/scripts"

# Clean start
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"

echo "========================================="
echo "   WEMO OPS - MAC PACKAGER (.PKG)        "
echo "   Version: $VERSION (Universal 2)"
echo "========================================="

# 1. CHECK SYSTEM PREREQUISITES
echo "[1/6] Checking Build Tools..."

if ! command -v python3 &> /dev/null; then
    echo "❌ ERROR: python3 not found."
    echo "👉 ACTION: Install Xcode Command Line Tools or Homebrew Python."
    exit 1
fi

if ! command -v pkgbuild &> /dev/null; then
    echo "❌ ERROR: pkgbuild not found. Are you on macOS?"
    exit 1
fi

# 2. COMPILE BINARIES
echo "[2/6] Compiling Binaries..."

# Setup Venv
python3 -m venv "$BUILD_DIR/venv"
source "$BUILD_DIR/venv/bin/activate"

# Install Dependencies
echo "   > Installing Python libraries..."
pip install --upgrade pip --quiet
pip install "pywemo>=2.1.1" customtkinter requests pyinstaller pyperclip Pillow flask qrcode waitress --quiet

# A. Build Client (WemoOps.app)
echo "   > Compiling Client ($CLIENT_SCRIPT)..."
# FIX: Added --target-arch universal2 for Intel + Apple Silicon support
pyinstaller --noconfirm --onefile --windowed \
    --name "$APP_NAME" \
    --target-arch universal2 \
    --icon "images/app_icon.ico" \
    --collect-all customtkinter \
    --collect-all pillow \
    --hidden-import pywemo \
    --hidden-import pyperclip \
    --hidden-import qrcode \
    --hidden-import PIL \
    --hidden-import PIL._tkinter_finder \
    --hidden-import PIL.ImageTk \
    "$CLIENT_SCRIPT" >/dev/null

# B. Build Server (Binary)
echo "   > Compiling Server ($SERVER_SCRIPT)..."
# FIX: Added --target-arch universal2
pyinstaller --noconfirm --onefile --noconsole \
    --name "wemo_service" \
    --target-arch universal2 \
    --hidden-import pywemo \
    --hidden-import flask \
    --hidden-import waitress \
    "$SERVER_SCRIPT" >/dev/null

deactivate

# 3. PREPARE INSTALLATION STRUCTURE
echo "[3/6] Staging Files..."

# Define install paths inside the package
# We install to /Applications/WemoOps to keep client & service together
APP_INSTALL_DIR="$ROOT_DIR/Applications/$APP_NAME"
mkdir -p "$APP_INSTALL_DIR"

# Move artifacts
mv "dist/$APP_NAME.app" "$ROOT_DIR/Applications/"
mv "dist/wemo_service" "$APP_INSTALL_DIR/"

# 4. CREATE LAUNCH AGENT (AUTO-START)
echo "[4/6] Creating LaunchAgent Service..."

mkdir -p "$ROOT_DIR/Library/LaunchAgents"
PLIST_PATH="$ROOT_DIR/Library/LaunchAgents/$IDENTIFIER.service.plist"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$IDENTIFIER.service</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/$APP_NAME/wemo_service</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/$SAFE_NAME.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/$SAFE_NAME.err.log</string>
</dict>
</plist>
EOF

# 5. PREPARE POST-INSTALL SCRIPTS
echo "[5/6] Creating Post-Install Scripts..."
mkdir -p "$SCRIPTS_DIR"

cat > "$SCRIPTS_DIR/postinstall" <<EOF
#!/bin/bash
# WemoOps Post-Install Script

SERVICE_PLIST="/Library/LaunchAgents/$IDENTIFIER.service.plist"
USER_ID=\$(id -u \$USER)

echo "Setting permissions..."
chmod +x "/Applications/$APP_NAME/wemo_service"
chmod -R 755 "/Applications/$APP_NAME.app"

echo "Loading Service..."
# Unload if running
launchctl bootout gui/\$USER_ID/com.qrussell.wemoops.service 2>/dev/null || true
# Load new plist
launchctl bootstrap gui/\$USER_ID "$SERVICE_PLIST" 2>/dev/null || true

echo "Installation Complete."
exit 0
EOF

chmod +x "$SCRIPTS_DIR/postinstall"

# 6. BUILD PACKAGE
echo "[6/6] Building .pkg Installer..."

# Build component package
pkgbuild --root "$ROOT_DIR" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --scripts "$SCRIPTS_DIR" \
         --install-location "/" \
         "$BUILD_DIR/WemoOps_Component.pkg" >/dev/null

# Build product archive (Final Installer)
productbuild --distribution "distribution.xml" \
             --package-path "$BUILD_DIR" \
             "$DIST_DIR/${APP_NAME}_${VERSION}_macOS_Universal.pkg" 2>/dev/null || \
             # Fallback if no distribution.xml matches
             mv "$BUILD_DIR/WemoOps_Component.pkg" "$DIST_DIR/${APP_NAME}_${VERSION}_macOS_Universal.pkg"

echo ""
echo "========================================="
echo "   SUCCESS! Installer Ready:"
echo "   $DIST_DIR/${APP_NAME}_${VERSION}_macOS_Universal.pkg"
echo "========================================="