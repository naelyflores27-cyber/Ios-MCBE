# Compatibility

| Component | Status |
|---|---|
| Host C11 tests | **Verified:** Clang 18.1.1 on Ubuntu x86_64, strict warnings enabled |
| Supplied game app payload | **Verified:** Minecraft iOS 1.26.33, build 1.26.33.01, arm64 executable, minimum iOS 15.0 |
| Installed iPhone app/device | **Unknown:** no device query/report |
| Negotiated Bedrock protocol | **Unknown:** no session handshake/capture |
| Passive packet decoding | **Unknown / not implemented** |
| Lab iOS dylib build in this host | **Blocked:** no `xcrun` or iPhoneOS SDK |
| Lab native loader/overlay source | **Implemented, not device-tested:** arm64 dylib configured for iOS 15.0; requires signing and actual device validation |
| Camera source and live in-game boxes | **Unavailable:** camera adapter and live entity producer are not implemented |
| 3105 native-dylib loading | **Unverified/not supported by evidence:** local patch contains only app Documents data, no loader or dylib path |

Do not apply packet layouts, server API versions, private structures, or offsets based on the app version alone. The supplied `MCPE-iOS-26.33-universal.zip` is empty; the extracted payload is the only local binary evidence. Any future production source must fail closed on unsupported version/protocol rather than silently decode with stale assumptions.