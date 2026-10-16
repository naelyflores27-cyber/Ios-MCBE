# Environment Report

Claims use **Verified**, **Likely**, **Unknown**, or **Blocked** as evidence labels.

| Question | Finding |
|---|---|
| Target app identity in supplied payload | **Verified:** `com.mojang.minecraftpe`, version `1.26.33`, build `1.26.33.01`, minimum iOS `15.0`, read from `Payload/minecraftpe.app/Info.plist`. Executable SHA-256 is recorded in [SOURCE_INVENTORY.md](SOURCE_INVENTORY.md). |
| Version installed on test iPhone | **Unknown:** no device query or device report identifies its installed version. The supplied JavaScript diagnostic is not a native app-version report. |
| Target architecture | **Verified:** supplied executable and existing `ClientLoader.dylib` are Mach-O arm64. **Unknown:** whether the physical device uses arm64e; the binary classification does not establish the device CPU subtype. |
| Current build host | **Verified:** Ubuntu 24.04 container, Linux x86_64; Clang 18.1.1 targets `x86_64-pc-linux-gnu`. `xcrun` is unavailable. |
| iOS dylib build here | **Blocked:** no Xcode, `xcrun`, or iPhoneOS SDK. Both the existing `ClientLoader/build.sh` and lab `build_ios.sh` target arm64/minimum iOS 15.0, but neither can run on this host. |
| Existing native/JS loading | **Verified:** source/README describe a native Objective-C UIKit dylib loaded into the app process; local Documents scripts are evaluated in the loader's JavaScriptCore `JSContext`. Its exported `ClientMenu` bridge does not expose Minecraft's own Script API. |
| Native APIs in existing project | **Verified:** Objective-C Foundation/UIKit/JavaScriptCore APIs are used by the loader. This says nothing about availability of undocumented game internals. |
| Experimental execution mode | **Verified by source:** the lab now defines an in-process Objective-C/UIKit dylib and staged-app load-command package route. **Unknown at runtime:** no lab dylib was built, signed, or loaded on an iPhone. No process hook is used. |
| Test world/server ownership | **Unknown:** no controlled world, server log, or test sequence was supplied. |
| Authorized observable traffic | **Unknown:** no packet capture or test-session network observation is present. No credentials or session secrets were requested or captured. |
| Minecraft Bedrock protocol version | **Unknown:** app build metadata is not the negotiated protocol version. No live handshake was observed. |
| Host architecture support for iOS | **Blocked:** local compiler can build host C tests only; cross-compiling iOS requires Apple SDK/toolchain. |

The top-level `MCPE-iOS-26.33-universal.zip` is verified empty, but the extracted app payload is available. No claim is made about the Minecraft version installed on a device or live runtime behavior.