# Build Notes

## Offline tracker and projection tests

Requirements: a C11 compiler (`clang` or `cc`), `make`, and the standard math library. No third-party packages are used.

```sh
make test
```

This builds test executables under `build/` inside this experiment. The commands use `-Wall -Wextra -Werror`; successful tests do not imply an iOS build or live data source.

## Experimental iOS dylib

On macOS with Xcode and the iPhoneOS SDK installed, run from the workspace root:

```sh
sh BedrockNetworkESP_Lab/build_ios.sh
```

The output is `BedrockNetworkESP_Lab/build/BedrockNetworkESP_Lab.dylib`, with install name `@executable_path/Frameworks/BedrockNetworkESP_Lab.dylib`, arm64, and minimum iOS 15.0. **Not built in this session:** this host is Linux and has no `xcrun`/iPhoneOS SDK.

## Existing iOS build configuration

**Verified by source inspection:** `ClientLoader/build.sh` invokes `xcrun --sdk iphoneos clang`, targets `-arch arm64`, uses `-miphoneos-version-min=15.0`, Objective-C ARC, and emits a dynamic library linked against Foundation, CoreGraphics, QuartzCore, UIKit, and JavaScriptCore. Existing bundled dylib is arm64. **Blocked in this host:** `xcrun` and the iPhoneOS SDK are absent, so no iOS dylib was built here.

The experimental IPA packager is self-contained and writes only a new output IPA and temporary staging files under that output directory. It takes `ClientLoader.dylib` as a binary input and refuses to overwrite an existing IPA. It does not import or change ClientLoader source, sign an app, or install on a device.

After building on macOS/Xcode, stage a new unsigned package with:

```sh
python3 BedrockNetworkESP_Lab/tools/package_experimental_ipa.py \
	--app Payload/minecraftpe.app \
	--client-loader ClientLoader/ClientLoader.dylib \
	--experimental-loader BedrockNetworkESP_Lab/build/BedrockNetworkESP_Lab.dylib \
	--output BedrockNetworkESP_Lab/build/Minecraft-ESP-Lab-unsigned.ipa
```

Sign the copied executable and embedded dylibs before device installation. The two-load-command package test uses synthetic Mach-O fixtures; it does not prove iOS signing or runtime compatibility.