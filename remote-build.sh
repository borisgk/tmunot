borisk@94.130.150.151

#!/usr/bin/env bash
set -e

# --- Configuration ---
TARGET_HOST="borisk@94.130.150.151"
TARGET_DIR="~/tmunot-build"
# ---------------------

echo "🚀 Syncing source code to $TARGET_HOST..."

# Efficiently sync source files, skipping local ARM caches and git history
rsync -avz --delete \
    --exclude='.git/' \
    --exclude='.zig-cache/' \
    --exclude='zig-out/' \
    --exclude='.zig-cache-x86/' \
    --exclude='zig-out-x86/' \
    --exclude='photos' \
    --exclude='databases' \
    ./ "$TARGET_HOST:$TARGET_DIR/"

echo "⚡ Triggering native x86_64 build on remote host..."

ssh "$TARGET_HOST" << EOF
    # Ensure the build directory exists and navigate into it
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"
    
    # Check for jq (required to parse the Zig nightly index)
    if ! command -v jq &> /dev/null; then
        echo "🔧 Installing jq via pacman..."
        sudo pacman -S --noconfirm jq
    fi

    # Automatically provision/update Zig Nightly cleanly if missing
    if ! command -v zig &> /dev/null; then
        echo "📥 Zig not found. Installing latest Zig Nightly..."
        TARBALL_URL=\$(curl -s https://ziglang.org/download/index.json | jq -r '.master."x86_64-linux".tarball')
        
        # Clean up any botched previous installations
        sudo rm -rf /usr/local/bin/zig
        sudo mkdir -p /opt/zig
        sudo rm -rf /opt/zig/*
        
        # Extract safely to /opt/zig and symlink the executable
        curl -L "\$TARBALL_URL" | sudo tar -xJ --strip-components=1 -C /opt/zig
        sudo ln -sf /opt/zig/zig /usr/local/bin/zig
    fi

    echo "🔬 System compiler version: \$(zig version)"

    echo "📦 Running native optimized build..."
    zig build -Doptimize=ReleaseSafe
EOF

echo "✅ Success! Binary built natively on $TARGET_HOST."
