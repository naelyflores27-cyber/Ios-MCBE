#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
OUTPUT=${CL_OUTPUT_PATH:-$ROOT/ClientLoader.dylib}
SOURCE_REVISION=${GITHUB_SHA:-$(git -C "$ROOT/.." rev-parse HEAD 2>/dev/null || printf 'unknown')}
BUILD_TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
EXPECTED_ESP_TEST_JS_SHA256=$(shasum -a 256 "$ROOT/scripts/esp_test.js" | awk '{print $1}')
mkdir -p "$(dirname -- "$OUTPUT")"

xcrun --sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDKROOT" \
  -miphoneos-version-min=15.0 \
  -fobjc-arc \
  -DCL_BUILD_REVISION=\"$SOURCE_REVISION\" \
  -DCL_BUILD_TIMESTAMP=\"$BUILD_TIMESTAMP\" \
  -DCL_EXPECTED_ESP_TEST_JS_SHA256=\"$EXPECTED_ESP_TEST_JS_SHA256\" \
  -dynamiclib \
  "$ROOT/ClientLoader.m" \
  "$ROOT/providers/CLProjection.c" \
  "$ROOT/providers/CLEntityProvider.m" \
  "$ROOT/providers/CLEntityTypeRegistry.m" \
  "$ROOT/providers/CLCameraProvider.m" \
  "$ROOT/providers/CLESPOverlay.m" \
  "$ROOT/providers/CLDiagnostics.m" \
  -framework Foundation \
  -framework CoreGraphics \
  -framework QuartzCore \
  -framework UIKit \
  -framework JavaScriptCore \
  -Wl,-install_name,@executable_path/Frameworks/ClientLoader.dylib \
  -o "$OUTPUT"

printf 'Built %s\n' "$OUTPUT"
