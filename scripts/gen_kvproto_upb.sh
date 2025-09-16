#!/usr/bin/env bash
set -euo pipefail

# Generate C sources/headers from kvproto (release-7.1) using upb's protoc plugin
# and vendor them into third_party/kvproto-upb/gen for Zig to build/link.
#
# Usage:
#   scripts/gen_kvproto_upb.sh \
#     --kvproto /path/to/kvproto \
#     --plugin /path/to/protoc-gen-upb \
#     --wkt /usr/local/include
#
# Flags:
#   --kvproto   Path to kvproto repo root (checked out at release-7.1)
#   --plugin    Path to protoc-gen-upb binary
#   --wkt       Protobuf include dir containing google/protobuf/*.proto
#   --plugin-minitable  (optional) path to protoc-gen-upb_minitable; if provided, will also
#                       generate descriptor.upb_minitable.h for upb reflection bootstrap
#   --out       (optional) output dir [default: third_party/kvproto-upb/gen]
#
# Notes:
# - We strip gogoproto annotations to avoid requiring gogoproto extensions.
# - We generate from kvproto/proto/*.proto and kvproto/include/google/api/*.proto.
# - Vendor the upb runtime sources/headers under third_party/kvproto-upb/upb.

KVPROTO=""
PLUGIN=""
WKT=""
OUT_DIR="third_party/kvproto-upb/gen"
PLUGIN_MINITABLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kvproto) KVPROTO="$2"; shift; shift ;;

    --plugin) PLUGIN="$2"; shift; shift ;;

    --wkt) WKT="$2"; shift; shift ;;

    --out) OUT_DIR="$2"; shift; shift ;;
    --plugin-minitable) PLUGIN_MINITABLE="$2"; shift; shift ;;

    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$KVPROTO" || -z "$PLUGIN" || -z "$WKT" ]]; then
  echo "Missing required flag(s)." >&2
  echo "See header of this script for usage." >&2
  exit 1
fi

KV_PROTO_DIR="$KVPROTO/proto"
KV_INCLUDE_DIR="$KVPROTO/include"

if [[ ! -d "$KV_PROTO_DIR" ]]; then
  echo "kvproto proto dir not found: $KV_PROTO_DIR" >&2
  exit 1
fi

# Ensure output directory exists
mkdir -p "$OUT_DIR"


TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Copy protos to temp and strip gogoproto custom options to keep protoc happy
cp "$KV_PROTO_DIR"/*.proto "$TMP_DIR"/
if [[ -d "$KV_INCLUDE_DIR" ]]; then
  mkdir -p "$TMP_DIR/include"
  cp -R "$KV_INCLUDE_DIR"/* "$TMP_DIR/include"/
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

# Prepare include paths: prefer kvproto's include over WKT to avoid duplicates
INCLUDES=("-I$TMP_DIR/include" "-I$TMP_DIR" "-I$WKT")

# Store original directory for absolute path calculations
ORIG_DIR="$(pwd)"

# Generate kvproto include protos (eg. eraftpb.proto) so that transitive includes resolve.
if compgen -G "$TMP_DIR/include/*.proto" > /dev/null; then
  pushd "$TMP_DIR/include" >/dev/null
  # Build list excluding google/* which we handled separately below
  shopt -s nullglob
  inc_protos=( *.proto )
  shopt -u nullglob
  if (( ${#inc_protos[@]} > 0 )); then
    # Convert to absolute path since we're in a different directory
    ABS_OUT_DIR="$ORIG_DIR/$OUT_DIR"
    if [[ -n "$PLUGIN_MINITABLE" ]]; then
      protoc "${INCLUDES[@]}" \
        --plugin=protoc-gen-upb="$PLUGIN" \
        --plugin=protoc-gen-upb_minitable="$PLUGIN_MINITABLE" \
        --upb_out="$ABS_OUT_DIR" \
        --upb_minitable_out="$ABS_OUT_DIR" \
        "${inc_protos[@]}"
    else
      protoc "${INCLUDES[@]}" \
        --plugin=protoc-gen-upb="$PLUGIN" \
        --upb_out="$ABS_OUT_DIR" \
        "${inc_protos[@]}"
    fi
  fi
  popd >/dev/null
fi

# Generate upb C for core kvproto messages (+ minitable headers if plugin provided)
if [[ -n "$PLUGIN_MINITABLE" ]]; then
  protoc "${INCLUDES[@]}" \
    --plugin=protoc-gen-upb="$PLUGIN" \
    --plugin=protoc-gen-upb_minitable="$PLUGIN_MINITABLE" \
    --upb_out="$OUT_DIR" \
    --upb_minitable_out="$OUT_DIR" \
    "$TMP_DIR"/*.proto
else
  protoc "${INCLUDES[@]}" \
    --plugin=protoc-gen-upb="$PLUGIN" \
    --upb_out="$OUT_DIR" \
    "$TMP_DIR"/*.proto
fi

# Generate for google/api protos if present (annotations/http)
if compgen -G "$TMP_DIR/include/google/api/*.proto" > /dev/null; then
  # Run protoc with canonical proto names relative to include root to avoid duplicate symbol definitions.
  pushd "$TMP_DIR/include" >/dev/null
  # Convert to absolute path since we're in a different directory  
  ABS_OUT_DIR="$ORIG_DIR/$OUT_DIR"
  if [[ -n "$PLUGIN_MINITABLE" ]]; then
    protoc "${INCLUDES[@]}" \
      --plugin=protoc-gen-upb="$PLUGIN" \
      --plugin=protoc-gen-upb_minitable="$PLUGIN_MINITABLE" \
      --upb_out="$ABS_OUT_DIR" \
      --upb_minitable_out="$ABS_OUT_DIR" \
      google/api/*.proto
  else
    protoc "${INCLUDES[@]}" \
      --plugin=protoc-gen-upb="$PLUGIN" \
      --upb_out="$ABS_OUT_DIR" \
      google/api/*.proto
  fi
  popd >/dev/null
fi

# Generate descriptor headers required by upb reflection runtime.
# We generate both upb and (optionally) upb_minitable outputs.
if [[ -f "$WKT/google/protobuf/descriptor.proto" ]]; then
  mkdir -p "$OUT_DIR/google/protobuf"
  pushd "$WKT" >/dev/null
  # Convert to absolute path since we're in a different directory
  ABS_OUT_DIR="$ORIG_DIR/$OUT_DIR"
  # upb headers
  protoc -I"$WKT" \
    --plugin=protoc-gen-upb="$PLUGIN" \
    --upb_out="$ABS_OUT_DIR" \
    google/protobuf/descriptor.proto
  # upb_minitable headers (if plugin provided)
  if [[ -n "$PLUGIN_MINITABLE" ]]; then
    protoc -I"$WKT" \
      --plugin=protoc-gen-upb_minitable="$PLUGIN_MINITABLE" \
      --upb_minitable_out="$ABS_OUT_DIR" \
      google/protobuf/descriptor.proto
  fi
  popd >/dev/null
fi

echo "Generated C sources in: $OUT_DIR"
