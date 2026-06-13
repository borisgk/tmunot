#!/bin/bash
set -e

REPO="borisgk/tmunot"

# 1. Require Root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (e.g. use sudo)"
  exit 1
fi

echo "Updating system and installing dependencies..."
apt-get update
apt-get install -y curl tar libvips-dev libexif-dev libsqlite3-dev

echo "Fetching latest release from GitHub..."
# Get the download URL for the latest release asset
LATEST_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep "browser_download_url.*tmunot-linux-x86_64.tar.gz" | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
    echo "Could not find a valid download URL for the latest release."
    exit 1
fi

echo "Downloading $LATEST_URL..."
TMP_DIR=$(mktemp -d)
curl -sL "$LATEST_URL" -o "$TMP_DIR/tmunot.tar.gz"

echo "Extracting binary..."
tar -xzf "$TMP_DIR/tmunot.tar.gz" -C "$TMP_DIR"
install -m 755 "$TMP_DIR/tmunot" "/usr/local/bin/tmunot"

rm -rf "$TMP_DIR"

echo "Creating service user and directories..."
id -u tmunot &>/dev/null || useradd -r -s /usr/sbin/nologin -d /var/lib/tmunot -U tmunot

mkdir -p /etc/tmunot
mkdir -p /var/lib/tmunot
chown tmunot:tmunot /etc/tmunot /var/lib/tmunot

CONFIG_FILE="/etc/tmunot/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Generating default config at $CONFIG_FILE..."
    cat > "$CONFIG_FILE" << 'EOF'
{
    "backend": "vips",
    "quality": 85,
    "gallery_thumbnail_height": 200,
    "input_directory": "/var/lib/tmunot/in",
    "db_dir": "/var/lib/tmunot/db",
    "originals_dir": "/var/lib/tmunot/orig",
    "previews_dir": "/var/lib/tmunot/prev",
    "thumbnails_dir": "/var/lib/tmunot/thumb",
    "hover_previews_dir": "/var/lib/tmunot/hover",
    "outputs": [
        { "name": "small", "target_width": 300, "target_height": 300 },
        { "name": "large", "target_width": 1200, "target_height": 1200 }
    ]
}
EOF
    mkdir -p /var/lib/tmunot/in /var/lib/tmunot/db /var/lib/tmunot/orig /var/lib/tmunot/prev /var/lib/tmunot/thumb /var/lib/tmunot/hover
    chown -R tmunot:tmunot /var/lib/tmunot
    chown tmunot:tmunot "$CONFIG_FILE"
fi

echo "Setting up systemd service..."
cat > /etc/systemd/system/tmunot.service << 'EOF'
[Unit]
Description=tmunot server
After=network.target

[Service]
Type=simple
User=tmunot
Group=tmunot
WorkingDirectory=/var/lib/tmunot
ExecStart=/usr/local/bin/tmunot
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting tmunot service..."
systemctl daemon-reload
systemctl enable tmunot
systemctl restart tmunot

echo "Deployment complete! You can check the status with: systemctl status tmunot"
