#!/bin/bash

# ==============================================================================
#  WEMO OPS - MASTER BUILDER (RPM / Linux)
#  Version: 5.1.0
# ==============================================================================

APP_NAME="wemo-ops"
APP_VERSION="5.1.0"
CLIENT_SCRIPT="wemo_ops_universal.py"
SERVER_SCRIPT="wemo_server.py"
BUILD_DIR="build_rpm"
RPM_ROOT="${BUILD_DIR}/rpmbuild"

# --- 1. CHECK REQUIREMENTS ---
echo "[1/6] Checking System Tools..."
if ! command -v python3 &> /dev/null; then
    echo "? Error: python3 is required."
    exit 1
fi
if ! command -v rpmbuild &> /dev/null; then
    echo "? Error: rpmbuild is required. (Try: sudo dnf install rpm-build)"
    exit 1
fi

# --- 2. SETUP BUILD ENVIRONMENT ---
echo "[2/6] Setting up Virtual Environment..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
python3 -m venv "$BUILD_DIR/venv"
source "$BUILD_DIR/venv/bin/activate"

# --- 3. INSTALL DEPENDENCIES ---
echo "[3/6] Installing Python Libraries..."
pip install --upgrade pip
pip install "pywemo>=2.1.1" customtkinter requests pyinstaller pyperclip Pillow flask qrcode waitress

# --- 4. COMPILE BINARIES ---
echo "[4/6] Compiling Binaries with PyInstaller..."

# Build Client (GUI)
pyinstaller --noconfirm --noconsole --onefile \
    --name "wemo-ops-client" \
    --collect-all customtkinter \
    --hidden-import pywemo \
    --hidden-import pyperclip \
    --hidden-import qrcode \
    --hidden-import PIL \
    "$CLIENT_SCRIPT"

# Build Server (Service)
pyinstaller --noconfirm --noconsole --onefile \
    --name "wemo-ops-server" \
    --hidden-import pywemo \
    --hidden-import flask \
    --hidden-import waitress \
    "$SERVER_SCRIPT"

# Move binaries to build area
mkdir -p "$BUILD_DIR/bin"
mv dist/wemo-ops-client "$BUILD_DIR/bin/"
mv dist/wemo-ops-server "$BUILD_DIR/bin/"

# --- 5. PREPARE RPM STRUCTURE ---
echo "[5/6] Generating RPM Configs..."

# Create RPM Directory Tree
mkdir -p "$RPM_ROOT"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# A. Create Systemd Service File
cat <<EOF > "$BUILD_DIR/wemo-ops-server.service"
[Unit]
Description=Wemo Ops Automation Server
After=network.target

[Service]
ExecStart=/opt/WemoOps/wemo-ops-server
WorkingDirectory=/opt/WemoOps
Restart=always
User=root
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

# B. Create Desktop Entry (Shortcut)
cat <<EOF > "$BUILD_DIR/wemo-ops.desktop"
[Desktop Entry]
Name=Wemo Ops Center
Comment=Wemo Automation Dashboard
Exec=/opt/WemoOps/wemo-ops-client
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Utility;Network;
EOF

# C. Create RPM Spec File
cat <<EOF > "$RPM_ROOT/SPECS/$APP_NAME.spec"
Name:       $APP_NAME
Version:    $APP_VERSION
Release:    1%{?dist}
Summary:    Wemo Automation Client and Server
License:    Proprietary
URL:        https://github.com/qrussell/wemo-ops-center
BuildArch:  x86_64

%description
Wemo Ops is a complete automation suite for Belkin Wemo devices.
Includes a background automation server and a desktop dashboard.

%prep
# No prep needed, binaries are pre-compiled

%build
# No build needed

%install
mkdir -p %{buildroot}/opt/WemoOps
mkdir -p %{buildroot}/usr/lib/systemd/system
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/bin

# Install Binaries
install -m 755 $PWD/$BUILD_DIR/bin/wemo-ops-client %{buildroot}/opt/WemoOps/wemo-ops-client
install -m 755 $PWD/$BUILD_DIR/bin/wemo-ops-server %{buildroot}/opt/WemoOps/wemo-ops-server

# Install Service
install -m 644 $PWD/$BUILD_DIR/wemo-ops-server.service %{buildroot}/usr/lib/systemd/system/wemo-ops-server.service

# Install Desktop Shortcut
install -m 644 $PWD/$BUILD_DIR/wemo-ops.desktop %{buildroot}/usr/share/applications/wemo-ops.desktop

# Create Symlinks for CLI access
ln -sf /opt/WemoOps/wemo-ops-client %{buildroot}/usr/bin/wemo-ops
ln -sf /opt/WemoOps/wemo-ops-server %{buildroot}/usr/bin/wemo-server

%files
/opt/WemoOps/wemo-ops-client
/opt/WemoOps/wemo-ops-server
/usr/lib/systemd/system/wemo-ops-server.service
/usr/share/applications/wemo-ops.desktop
/usr/bin/wemo-ops
/usr/bin/wemo-server

%post
# Reload systemd to recognize the new service
systemctl daemon-reload
# Enable it by default (optional, user can enable manually if preferred)
systemctl enable wemo-ops-server
echo "Wemo Ops installed. Start server with: sudo systemctl start wemo-ops-server"

%preun
# Stop service before uninstall
if [ \$1 -eq 0 ]; then
    systemctl stop wemo-ops-server
    systemctl disable wemo-ops-server
fi

%clean
rm -rf %{buildroot}
EOF

# --- 6. BUILD RPM ---
echo "[6/6] Building RPM Package..."
rpmbuild -bb --define "_topdir $PWD/$RPM_ROOT" "$RPM_ROOT/SPECS/$APP_NAME.spec"

echo ""
echo "========================================================"
echo "   BUILD COMPLETE!"
echo "   RPM File Location:"
find "$RPM_ROOT/RPMS" -name "*.rpm"
echo "========================================================"