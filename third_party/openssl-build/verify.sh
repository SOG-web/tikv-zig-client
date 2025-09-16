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
