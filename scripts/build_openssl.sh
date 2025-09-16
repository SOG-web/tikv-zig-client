#!/bin/bash

# Copyright 2021 TiKV Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

# Script to build OpenSSL locally for TiKV client-zig
# This ensures consistent OpenSSL builds across different systems

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OPENSSL_SRC_DIR="$PROJECT_ROOT/third_party/_openssl_src"
OPENSSL_BUILD_DIR="$PROJECT_ROOT/third_party/openssl-build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if OpenSSL source exists
if [[ ! -d "$OPENSSL_SRC_DIR" ]]; then
    log_error "OpenSSL source not found at $OPENSSL_SRC_DIR"
    log_info "Please run: git clone --depth 1 --branch openssl-3.1.4 https://github.com/openssl/openssl.git third_party/_openssl_src"
    exit 1
fi

# Check for required tools
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed"
        return 1
    fi
}

log_info "Checking required tools..."
check_tool "make" || exit 1
check_tool "perl" || exit 1

# Detect platform and set configuration
PLATFORM=$(uname -s)
ARCH=$(uname -m)

case "$PLATFORM" in
    "Darwin")
        if [[ "$ARCH" == "arm64" ]]; then
            CONFIG_TARGET="darwin64-arm64-cc"
        else
            CONFIG_TARGET="darwin64-x86_64-cc"
        fi
        ;;
    "Linux")
        if [[ "$ARCH" == "x86_64" ]]; then
            CONFIG_TARGET="linux-x86_64"
        elif [[ "$ARCH" == "aarch64" ]]; then
            CONFIG_TARGET="linux-aarch64"
        else
            CONFIG_TARGET="linux-generic64"
        fi
        ;;
    *)
        log_warn "Unknown platform $PLATFORM, using generic configuration"
        CONFIG_TARGET="Configure"
        ;;
esac

log_info "Building OpenSSL for $PLATFORM ($ARCH) using target: $CONFIG_TARGET"

# Create build directory
mkdir -p "$OPENSSL_BUILD_DIR"

# Clean previous build if it exists
if [[ -f "$OPENSSL_SRC_DIR/Makefile" ]]; then
    log_info "Cleaning previous build..."
    cd "$OPENSSL_SRC_DIR"
    make clean || true
fi

# Configure OpenSSL
log_info "Configuring OpenSSL..."
cd "$OPENSSL_SRC_DIR"

# OpenSSL configuration options:
# --prefix: Install location
# --openssldir: OpenSSL configuration directory
# no-shared: Build static libraries only
# no-tests: Skip building tests (faster build)
# -fPIC: Position independent code (required for static linking in some cases)
# -O3: Optimize for speed
./Configure "$CONFIG_TARGET" \
    --prefix="$OPENSSL_BUILD_DIR" \
    --openssldir="$OPENSSL_BUILD_DIR/ssl" \
    no-shared \
    no-tests \
    -fPIC \
    -O3

# Build OpenSSL
log_info "Building OpenSSL (this may take a few minutes)..."
make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Install to build directory
log_info "Installing OpenSSL to $OPENSSL_BUILD_DIR..."
make install_sw

# Verify installation
if [[ -f "$OPENSSL_BUILD_DIR/lib/libssl.a" && -f "$OPENSSL_BUILD_DIR/lib/libcrypto.a" ]]; then
    log_info "OpenSSL build completed successfully!"
    log_info "Libraries installed at: $OPENSSL_BUILD_DIR/lib/"
    log_info "Headers installed at: $OPENSSL_BUILD_DIR/include/"
    
    # Show library sizes
    log_info "Library sizes:"
    ls -lh "$OPENSSL_BUILD_DIR/lib/"*.a
    
    # Show OpenSSL version
    if [[ -f "$OPENSSL_BUILD_DIR/bin/openssl" ]]; then
        OPENSSL_VERSION=$("$OPENSSL_BUILD_DIR/bin/openssl" version)
        log_info "Built version: $OPENSSL_VERSION"
    fi
else
    log_error "OpenSSL build failed - libraries not found"
    exit 1
fi

# Create a simple verification script
cat > "$OPENSSL_BUILD_DIR/verify.sh" << 'EOF'
#!/bin/bash
# Simple verification that OpenSSL libraries are working
echo "Verifying OpenSSL installation..."

OPENSSL_DIR="$(dirname "$0")"

if [[ -f "$OPENSSL_DIR/lib/libssl.a" && -f "$OPENSSL_DIR/lib/libcrypto.a" ]]; then
    echo "✓ Static libraries found"
else
    echo "✗ Static libraries missing"
    exit 1
fi

if [[ -d "$OPENSSL_DIR/include/openssl" ]]; then
    echo "✓ Headers found"
else
    echo "✗ Headers missing"
    exit 1
fi

if [[ -f "$OPENSSL_DIR/bin/openssl" ]]; then
    VERSION=$("$OPENSSL_DIR/bin/openssl" version)
    echo "✓ OpenSSL version: $VERSION"
else
    echo "✗ OpenSSL binary missing"
    exit 1
fi

echo "OpenSSL installation verified successfully!"
EOF

chmod +x "$OPENSSL_BUILD_DIR/verify.sh"

log_info "Build complete! Run '$OPENSSL_BUILD_DIR/verify.sh' to verify the installation."
log_info "You can now run 'zig build' to compile the project with local OpenSSL."
