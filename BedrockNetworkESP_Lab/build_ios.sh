#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
mkdir -p "$ROOT/build"

xcrun --sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDKROOT" \
  -miphoneos-version-min=15.0 \
  -fobjc-arc \
  -fblocks \
  -dynamiclib \
  "$ROOT/native/ExperimentalLoader.m" \
  "$ROOT/native/CameraDataSource.m" \
  "$ROOT/native/ESPOverlay.m" \
  "$ROOT/native/Diagnostics.m" \
  "$ROOT/src/entity/BNEEntityTracker.c" \
  "$ROOT/src/entity/BNEEntitySnapshotProvider.c" \
  "$ROOT/src/projection/BNEProjection.c" \
  "$ROOT/src/common/BNEClock.c" \
  -framework Foundation \
  -framework CoreGraphics \
  -framework QuartzCore \
  -framework UIKit \
  -Wl,-install_name,@executable_path/Frameworks/BedrockNetworkESP_Lab.dylib \
  -o "$ROOT/build/BedrockNetworkESP_Lab.dylib"

printf 'Built %s\n' "$ROOT/build/BedrockNetworkESP_Lab.dylib"