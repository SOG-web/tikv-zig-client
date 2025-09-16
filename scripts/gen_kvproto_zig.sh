#!/usr/bin/env bash
set -euo pipefail

exec zig build gen-proto "$@"

# Generate Zig protobuf files from kvproto using zig-protobuf library
# This replaces the C upb generation with pure Zig protobuf implementation
#
# Usage:
#   scripts/gen_kvproto_zig.sh
#
# The script will:
# 1. Use zig build to invoke the protobuf generation step
# 2. Generate .zig files in src/proto/ directory
# 3. Clean up any gogoproto/rustproto annotations that cause issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KVPROTO_SRC="$PROJECT_ROOT/third_party/_kvproto_src"
PROTO_DIR="$KVPROTO_SRC/proto"
INCLUDE_DIR="$KVPROTO_SRC/include"
OUT_DIR="$PROJECT_ROOT/src/proto"

if [[ ! -d "$PROTO_DIR" ]]; then
  echo "kvproto proto dir not found: $PROTO_DIR" >&2
  exit 1
fi

echo "Generating Zig protobuf files from kvproto..."
echo "Source: $PROTO_DIR"
echo "Output: $OUT_DIR"

# Clean output directory
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Create temporary directory for cleaned proto files
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Cleaning proto files in temporary directory: $TMP_DIR"

# Copy protos to temp and strip gogoproto custom options to keep protoc happy
cp "$PROTO_DIR"/*.proto "$TMP_DIR"/
if [[ -d "$INCLUDE_DIR" ]]; then
  mkdir -p "$TMP_DIR/include"
  cp -R "$INCLUDE_DIR"/* "$TMP_DIR/include"/
fi

# Remove imports/options for gogoproto and rustproto to keep protoc happy.
# We do per-line edits to avoid breaking multi-line constructs.
# - delete lines containing gogo.proto or rustproto.proto
# - delete lines starting with option *(gogoproto...) or option *(rustproto...)
# - remove inline [ ... gogoproto ... ] option blocks on a single line
sed -i '' -e '/gogo\.proto/d' -e '/rustproto\.proto/d' "$TMP_DIR"/*.proto || true
# macOS sed uses basic regex; use character class for literal '(' and portable whitespace class
sed -i '' \
  -e '/^[[:space:]]*option[[:space:]]*[(]gogoproto/d' \
  -e '/^[[:space:]]*option[[:space:]]*[(]rustproto/d' \
  "$TMP_DIR"/*.proto || true
perl -pe 's/\[[^\]]*gogoproto[^\]]*\]//g' -i "$TMP_DIR"/*.proto
# Remove any remaining lines containing (gogoproto...) or (rustproto...)
perl -ni -e 'print unless /\(gogoproto/ || /\(rustproto/' "$TMP_DIR"/*.proto

# Also clean include files if they exist
if [[ -d "$TMP_DIR/include" ]]; then
  find "$TMP_DIR/include" -name "*.proto" -exec sed -i '' -e '/gogo\.proto/d' -e '/rustproto\.proto/d' {} \; || true
  find "$TMP_DIR/include" -name "*.proto" -exec sed -i '' \
    -e '/^[[:space:]]*option[[:space:]]*[(]gogoproto/d' \
    -e '/^[[:space:]]*option[[:space:]]*[(]rustproto/d' {} \; || true
  find "$TMP_DIR/include" -name "*.proto" -exec perl -pe 's/\[[^\]]*gogoproto[^\]]*\]//g' -i {} \;
  find "$TMP_DIR/include" -name "*.proto" -exec perl -ni -e 'print unless /\(gogoproto/ || /\(rustproto/' {} \;
fi

echo "Running zig build gen-proto to generate Zig protobuf files..."

# Change to project root and run the generation
cd "$PROJECT_ROOT"

# Run the protobuf generation step
# This will use the zig-protobuf library to generate .zig files
zig build gen-proto

echo "Generated Zig protobuf files in: $OUT_DIR"
echo "Files generated:"
find "$OUT_DIR" -name "*.zig" -type f | sort

echo "Zig protobuf generation completed successfully!"
