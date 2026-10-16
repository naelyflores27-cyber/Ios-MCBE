#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
SOURCE_REVISION=${GITHUB_SHA:-$(git -C "$ROOT/.." rev-parse HEAD 2>/dev/null || printf 'unknown')}
BUILD_TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
EXPECTED_GAME_BUILD=${BNE_EXPECTED_GAME_BUILD:-1.26.33.01}
EXPECTED_ESP_TEST_JS_SHA256=${BNE_EXPECTED_ESP_TEST_JS_SHA256:-c733b58b9299e69031a326d2102c596882ffe12e2653c3ed5e0c98f9e54d30bc}
if [[ -f "$ROOT/../ClientLoader/scripts/esp_test.js" ]]; then
  EXPECTED_ESP_TEST_JS_SHA256=$(shasum -a 256 "$ROOT/../ClientLoader/scripts/esp_test.js" | awk '{print $1}')
fi
mkdir -p "$ROOT/build"

xcrun --sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDKROOT" \
  -miphoneos-version-min=15.0 \
  -fobjc-arc \
  -fblocks \
  -DBNE_BUILD_REVISION=\"$SOURCE_REVISION\" \
  -DBNE_BUILD_TIMESTAMP=\"$BUILD_TIMESTAMP\" \
  -DBNE_EXPECTED_GAME_BUILD=\"$EXPECTED_GAME_BUILD\" \
  -DBNE_EXPECTED_ESP_TEST_JS_SHA256=\"$EXPECTED_ESP_TEST_JS_SHA256\" \
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

python3 "$ROOT/tools/write_build_manifest.py" \
  --dylib "$ROOT/build/BedrockNetworkESP_Lab.dylib" \
  --revision "$SOURCE_REVISION" \
  --built-at "$BUILD_TIMESTAMP" \
  --expected-game-build "$EXPECTED_GAME_BUILD" \
  --output "$ROOT/build/BuildManifest.json"

printf 'Built %s\n' "$ROOT/build/BedrockNetworkESP_Lab.dylib"