# Build Notes

## Offline tracker and projection tests

Requirements: a C11 compiler (`clang` or `cc`), `make`, and the standard math library. No third-party packages are used.

```sh
make test
```

This builds test executables under `build/` inside this experiment. The commands use `-Wall -Wextra -Werror`; successful tests do not imply an iOS build or live data source.

## Diagnostic dylib pair

The hosted `build-bedrock-network-esp-lab.yml` workflow builds two arm64 libraries: `ClientLoader-diagnostic.dylib` (existing UI/bridge with diagnostic and console logging) and `BedrockNetworkESP_Lab.dylib` (the separate diagnostic overlay/data-source boundary). The ClientLoader build uses `CL_OUTPUT_PATH`, so it does not overwrite `ClientLoader/ClientLoader.dylib`. The hosted checkout must include the ClientLoader build sources and `scripts/esp_test.js` so it can compile the source and embed its expected script hash.

On macOS with Xcode and the iPhoneOS SDK installed, run from the workspace root:

```sh
CL_OUTPUT_PATH="$PWD/BedrockNetworkESP_Lab/build/ClientLoader-diagnostic.dylib" \
	sh ClientLoader/build.sh
sh BedrockNetworkESP_Lab/build_ios.sh
```

The lab output has install name `@executable_path/Frameworks/BedrockNetworkESP_Lab.dylib`; the diagnostic ClientLoader output retains install name `@executable_path/Frameworks/ClientLoader.dylib`. Both target arm64 and minimum iOS 15.0. This Linux host cannot build the current source because `xcrun`/iPhoneOS SDK are unavailable; the previously downloaded binary predates this diagnostic implementation.

## Existing iOS build configuration

**Verified by source inspection:** `ClientLoader/build.sh` invokes `xcrun --sdk iphoneos clang`, targets `-arch arm64`, uses `-miphoneos-version-min=15.0`, Objective-C ARC, and emits a dynamic library linked against Foundation, CoreGraphics, QuartzCore, UIKit, and JavaScriptCore. Existing bundled dylib is arm64. **Blocked in this host:** `xcrun` and the iPhoneOS SDK are absent, so no iOS dylib was built here.

The experimental IPA packager is self-contained and writes only a new output IPA and temporary staging files under that output directory. It takes the separately built diagnostic ClientLoader and lab dylib as inputs and refuses to overwrite an existing IPA. It does not modify the supplied app bundle or sign/install the result.

After building on macOS/Xcode, stage a new unsigned package with:

```sh
python3 BedrockNetworkESP_Lab/tools/package_experimental_ipa.py \
	--app Payload/minecraftpe.app \
	--client-loader BedrockNetworkESP_Lab/build/ClientLoader-diagnostic.dylib \
	--experimental-loader BedrockNetworkESP_Lab/build/BedrockNetworkESP_Lab.dylib \
	--output BedrockNetworkESP_Lab/build/Minecraft-ESP-Lab-unsigned.ipa
```

The workflow artifact includes both libraries, `BuildManifest.json`, and `SHA256SUMS`. After installing the signed IPA, retrieve `Documents/ClientLoader/ClientLoader.log`, `BedrockNetworkESP_Lab.log`, and JSON reports under `Documents/ClientLoader/exports/` and `exports/BedrockNetworkESP_Lab/`. Sign the copied executable and embedded dylibs before device installation. Synthetic package tests do not prove signing, loading, or device compatibility.