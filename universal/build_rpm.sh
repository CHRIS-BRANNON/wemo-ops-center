#!/bin/bash

# --- CRITICAL: Stop immediately if any command fails ---
set -e

# --- CONFIGURATION ---
APP_NAME="WemoOps"
SAFE_NAME="wemo-ops"
VERSION="4.2.6"      # Updated to match Python script
RELEASE="1"
ARCH="x86_64"
SUMMARY="Wemo Ops Center - Automation and Provisioning Tool"
MAIN_SCRIPT="wemo_ops_universal.py"
SERVICE_SCRIPT="wemo_service_universal.py"

# 1. SETUP PATHS
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

RPM_TOP_DIR="$SCRIPT_DIR/dist/rpm_build"
INSTALL_DIR="/opt/$APP_NAME"

echo "========================================="
echo "   WEMO OPS - RPM PACKAGER (.RPM)        "
echo "   Version: $VERSION-$RELEASE"
echo "========================================="

# 2. CHECK SYSTEM PREREQUISITES
echo "[1/5] Checking Build Tools..."

if ! command -v rpmbuild &> /dev/null; then
    echo "❌ ERROR: 'rpmbuild' not found."
    echo "👉 ACTION: Run 'sudo dnf install rpm-build rpmdevtools'"
    exit 1
fi

# Force Python 3.11 (Required for PyWemo)
if command -v python3.11 &> /dev/null; then
    PYTHON_BIN="python3.11"
else
    echo "❌ ERROR: Python 3.11 is required but not found."
    echo "👉 ACTION: Run 'sudo dnf install python3.11 python3.11-devel'"
    exit 1
fi
echo "   > Using Python: $PYTHON_BIN"

# 3. COMPILE BINARIES
echo "[2/5] Compiling Binaries..."

# Clean old environment
if [ -d ".venv" ]; then
    rm -rf .venv
fi

# Create Virtual Env
$PYTHON_BIN -m venv .venv
source .venv/bin/activate

# Install dependencies (Fail script if this fails)
echo "   > Installing Python libraries..."
pip install --upgrade pip
pip install "pywemo>=2.1.1" customtkinter requests pyinstaller pyperclip pystray Pillow

# Clean previous builds
rm -rf dist/rpm_build
rm -f dist/*.rpm

# Build GUI
echo "   > Compiling GUI ($MAIN_SCRIPT)..."
pyinstaller --noconfirm --onefile --windowed \
    --name "$APP_NAME" \
    --collect-all customtkinter \
    --hidden-import pywemo \
    --hidden-import pyperclip \
    --hidden-import pystray \
    --hidden-import PIL \
    "$MAIN_SCRIPT" >/dev/null

# Build Service
echo "   > Compiling Service ($SERVICE_SCRIPT)..."
pyinstaller --noconfirm --onefile --noconsole \
    --name "wemo_service" \
    --hidden-import pywemo \
    --hidden-import pystray \
    --hidden-import PIL \
    "$SERVICE_SCRIPT" >/dev/null

deactivate

# Verify binaries exist
if [ ! -f "dist/$APP_NAME" ] || [ ! -f "dist/wemo_service" ]; then
    echo "❌ ERROR: Compilation failed. Binaries are missing in 'dist/'."
    exit 1
fi

# 4. PREPARE RPM DIRECTORY STRUCTURE
echo "[3/5] Setting up RPM Build Tree..."
mkdir -p "$RPM_TOP_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

SOURCE_DIR="$RPM_TOP_DIR/SOURCES/$SAFE_NAME-$VERSION"
mkdir -p "$SOURCE_DIR"

# Copy binaries
cp "dist/$APP_NAME" "$SOURCE_DIR/"
cp "dist/wemo_service" "$SOURCE_DIR/"

# Copy icon if available
if [ -f "images/app_icon.ico" ]; then
    cp "images/app_icon.ico" "$SOURCE_DIR/"
fi

# Create source tarball
cd "$RPM_TOP_DIR/SOURCES"
tar -czf "$SAFE_NAME-$VERSION.tar.gz" "$SAFE_NAME-$VERSION"
cd "$SCRIPT_DIR"

# 5. GENERATE SPEC FILE
echo "[4/5] Generating .spec file..."
cat > "$RPM_TOP_DIR/SPECS/$SAFE_NAME.spec" <<EOF
# --- PYINSTALLER FIXES ---
%define debug_package %{nil}
%define _enable_debug_packages 0
%define _build_id_links none
# -------------------------

Name:           $SAFE_NAME
Version:        $VERSION
Release:        $RELEASE%{?dist}
Summary:        $SUMMARY
License:        Proprietary
Group:          Applications/System
Source0:        %{name}-%{version}.tar.gz
BuildArch:      $ARCH
AutoReqProv:    no

# --- RUNTIME DEPENDENCIES ---
# We stick to standard repos to ensure installation succeeds
Requires:       python3, python3-tkinter, fontconfig
Requires:       liberation-sans-fonts

%description
Wemo Ops Center is a tool for provisioning and automating Wemo smart devices.

%prep
%setup -q

%build
# Binaries are pre-built

%install
# Create directories
mkdir -p %{buildroot}$INSTALL_DIR
mkdir -p %{buildroot}$INSTALL_DIR/images
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/lib/systemd/user

# Install Binaries to /opt
install -m 755 $APP_NAME %{buildroot}$INSTALL_DIR/$APP_NAME
install -m 755 wemo_service %{buildroot}$INSTALL_DIR/wemo_service

# Install Icon
if [ -f app_icon.ico ]; then
    install -m 644 app_icon.ico %{buildroot}$INSTALL_DIR/images/app_icon.ico
fi

# --- WRAPPER SCRIPT (Fixes VMware/ESXi Display Issues) ---
# Instead of a symlink, we create a script that sets the display fix variable
cat > %{buildroot}/usr/bin/$APP_NAME <<WRAPPER
#!/bin/bash
export XLIB_SKIP_ARGB_VISUALS=1
exec $INSTALL_DIR/$APP_NAME "\$@"
WRAPPER
chmod 755 %{buildroot}/usr/bin/$APP_NAME
# ---------------------------------------------------------

# Desktop Entry (Applications Menu)
cat > %{buildroot}/usr/share/applications/$APP_NAME.desktop <<ENTRY
[Desktop Entry]
Type=Application
Name=Wemo Ops Center
Comment=Manage and Automate Wemo Devices
Exec=/usr/bin/$APP_NAME
Icon=utilities-terminal
Terminal=false
Categories=Utility;Network;
ENTRY

# Systemd Service File
cat > %{buildroot}/usr/lib/systemd/user/wemo_service.service <<SERVICE
[Unit]
Description=Wemo Ops Automation Service
After=network.target

[Service]
ExecStart=$INSTALL_DIR/wemo_service
Restart=on-failure
StandardOutput=null
StandardError=journal

[Install]
WantedBy=default.target
SERVICE

%files
$INSTALL_DIR
/usr/bin/$APP_NAME
/usr/share/applications/$APP_NAME.desktop
/usr/lib/systemd/user/wemo_service.service

%post
update-desktop-database &> /dev/null || :
echo "--------------------------------------------------------"
echo "✅ Wemo Ops installed successfully!"
echo ""
echo "   👉 Run from terminal:  WemoOps"
echo "   👉 Run from menu:      Applications > Utilities > Wemo Ops Center"
echo "   👉 Enable service:     systemctl --user enable --now wemo_service"
echo "--------------------------------------------------------"

%preun
systemctl --user stop wemo_service &> /dev/null || :
systemctl --user disable wemo_service &> /dev/null || :

%postun
update-desktop-database &> /dev/null || :
rm -rf $INSTALL_DIR

%changelog
* $(date "+%a %b %d %Y") Quentin Russell <user@example.com> - $VERSION-$RELEASE
- Release $VERSION
EOF

# 6. BUILD RPM
echo "[5/5] Running rpmbuild..."
rpmbuild --define "_topdir $RPM_TOP_DIR" -bb "$RPM_TOP_DIR/SPECS/$SAFE_NAME.spec"

# Cleanup and Move
mv "$RPM_TOP_DIR/RPMS/$ARCH/"*.rpm dist/
rm -rf "$RPM_TOP_DIR"

echo "========================================="
echo "   SUCCESS! RPM Ready in dist/ folder:"
ls dist/*.rpm
echo "========================================="