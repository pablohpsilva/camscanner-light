#!/usr/bin/env bash
# Download and install the prebuilt dartcv4 macOS arm64 native library
# required for running opencv_dart unit tests on a macOS host (no device).
#
# Usage:
#   bash scripts/setup-cv-host-test.sh
#
# Then run tests with:
#   export DARTCV_LIB_PATH=/tmp/dartcv_lib/lib/libdartcv.dylib
#   export DYLD_LIBRARY_PATH=/tmp/dartcv_lib/lib:$DYLD_LIBRARY_PATH
#   cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_test.dart

set -euo pipefail

DARTCV_VERSION="4.12.0.2"
INSTALL_DIR="/tmp/dartcv_lib"

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  TARBALL="libdartcv-macos-arm64.tar.gz"
elif [ "$ARCH" = "x86_64" ]; then
  TARBALL="libdartcv-macos-x64.tar.gz"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

if [ -f "$INSTALL_DIR/lib/libdartcv.dylib" ]; then
  echo "libdartcv.dylib already present at $INSTALL_DIR/lib/libdartcv.dylib"
  echo "Run with: export DARTCV_LIB_PATH=$INSTALL_DIR/lib/libdartcv.dylib"
  exit 0
fi

echo "Downloading dartcv4 $DARTCV_VERSION macOS $ARCH..."
mkdir -p "$INSTALL_DIR"
curl -fsSL \
  "https://github.com/rainyl/dartcv/releases/download/${DARTCV_VERSION}/${TARBALL}" \
  -o "$INSTALL_DIR/dartcv.tar.gz"

tar -xzf "$INSTALL_DIR/dartcv.tar.gz" -C "$INSTALL_DIR"
rm "$INSTALL_DIR/dartcv.tar.gz"

echo "Done. Run tests with:"
echo "  export DARTCV_LIB_PATH=$INSTALL_DIR/lib/libdartcv.dylib"
echo "  export DYLD_LIBRARY_PATH=$INSTALL_DIR/lib:\$DYLD_LIBRARY_PATH"
echo "  cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_test.dart"
