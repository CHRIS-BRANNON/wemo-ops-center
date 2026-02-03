#!/bin/bash

# 1. SETUP CORRECT DIRECTORY CONTEXT
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "========================================="
echo "   WEMO OPS - MASTER BUILDER (LINUX)     "
echo "   Working Directory: $SCRIPT_DIR"
echo "========================================="

# 2. SYSTEM DEPENDENCIES
echo "[1/5] Checking System Dependencies..."
sudo apt-get update
# Added 'xclip' here. Pyperclip requires it on Linux to access the clipboard.
sudo apt-get install -y python3-tk python3-venv python3-pip network-manager xclip

# 3. SETUP VIRTUAL ENVIRONMENT
echo "[2/5] Setting up Isolated Build Environment..."

if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi

source .venv/bin/activate

# Install libraries (ADDED 'pyperclip' HERE)
echo "   > Installing Python libraries..."
pip install --upgrade pip
pip install pyinstaller customtkinter pywemo requests pyperclip

# 4. BUILD BINARIES
echo "[3/5] Building Binaries..."

rm -rf build/ dist/ *.spec

# Build GUI
echo "   > Compiling GUI..."
# Added --hidden-import pyperclip just to be safe
pyinstaller --noconfirm --onefile --windowed \
    --name "WemoOps" \
    --distpath ./dist \
    --workpath ./build \
    --collect-all customtkinter \
    --hidden-import pywemo \
    --hidden-import pyperclip \
    wemo_ops_linux.py

# Build Service
echo "   > Compiling Service..."
pyinstaller --noconfirm --onefile --noconsole \
    --name "wemo_service" \
    --distpath ./dist \
    --workpath ./build \
    --hidden-import pywemo \
    wemo_service_linux.py

deactivate

# 5. ORGANIZE INSTALLER
echo "[4/5] Organizing Installer Files..."
INSTALLER_DIR="$SCRIPT_DIR/dist/WemoOps_Installer"
mkdir -p "$INSTALLER_DIR"

if [ -f "dist/WemoOps" ]; then
    mv dist/WemoOps "$INSTALLER_DIR/"
else
    echo "ERROR: WemoOps binary failed to build."
    exit 1
fi

if [ -f "dist/wemo_service" ]; then
    mv dist/wemo_service "$INSTALLER_DIR/"
else
    echo "ERROR: wemo_service binary failed to build."
    exit 1
fi

# 6. CREATE INSTALL SCRIPT
echo "[5/5] Creating Install Script..."

cat > "$INSTALLER_DIR/install.sh" <<'EOF'
#!/bin/bash
APP_DIR="$HOME/.local/share/WemoOps"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
SYSTEMD_DIR="$HOME/.config/systemd/user"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Installing Wemo Ops..."

# 1. Create Directories
mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$SYSTEMD_DIR"

# 2. Install Binaries
cp "$DIR/WemoOps" "$BIN_DIR/"
cp "$DIR/wemo_service" "$APP_DIR/"
chmod +x "$BIN_DIR/WemoOps"
chmod +x "$APP_DIR/wemo_service"

# 3. Create Desktop Shortcut
cat > "$DESKTOP_DIR/WemoOps.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Wemo Ops Center
Exec=$BIN_DIR/WemoOps
Icon=utilities-terminal
Terminal=false
Categories=Utility;
DESKTOP

update-desktop-database "$DESKTOP_DIR" 2>/dev/null

# 4. Create Systemd Service
cat > "$SYSTEMD_DIR/wemo_ops.service" <<SERVICE
[Unit]
Description=Wemo Ops Automation Service
After=network.target

[Service]
ExecStart=$APP_DIR/wemo_service
Restart=on-failure
StandardOutput=null
StandardError=journal

[Install]
WantedBy=default.target
SERVICE

# 5. Enable Service
systemctl --user daemon-reload
systemctl --user enable --now wemo_ops.service

echo "=========================================="
echo "Success! Installation Complete."
echo "=========================================="
EOF

chmod +x "$INSTALLER_DIR/install.sh"

echo "========================================="
echo "   BUILD COMPLETE"
echo "========================================="
