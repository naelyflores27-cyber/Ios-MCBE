# Source Inventory

## Workspace inputs

| Path | Observation | SHA-256 |
|---|---|---|
| `ClientLoader/ClientLoader.m` | Objective-C loader, bridge, and overlay lifecycle | `86433df0178f107d9026822024380c63eef03d702faffad237548995772a25cf` |
| `ClientLoader/providers/CLEntityProvider.h` | Snapshot API | `6af36c724445ccdd8ea3872178fe979a13edbfb43d1b4d79776f2554b41de690` |
| `ClientLoader/providers/CLEntityProvider.m` | Snapshot validation/cache; no producer | `70d79835a24a40e08a490739fa6deea9f729dde503c745235e24186c1d115482` |
| `ClientLoader/providers/CLCameraProvider.h` | Matrix publication/projection API | `d4769143a32c8efdb6c218c29337e04148c016542d099a58813652ad7a6aa2b7` |
| `ClientLoader/providers/CLCameraProvider.m` | Externally-published matrix; unavailable until supplied | `3d02e5bddba573cb006f157b1855fcdc7e816ab5e1da5b5ad2af3bf3861f8163` |
| `ClientLoader/providers/CLProjection.c` | Portable column-major AABB projection | `fe3a104f8982059a5b94a156542f965138995f41cba186be1b07e5a38dfa8e47` |
| `ClientLoader/providers/CLESPOverlay.m` | Snapshot-driven UIKit renderer | `f62e7bf80a448afc5de8b672207bb238083dded9dd07e14469a017aea0b2b6a8` |
| `ClientLoader/scripts/esp_test.js` | Synthetic/live toggles and diagnostics action | `c733b58b9299e69031a326d2102c596882ffe12e2653c3ed5e0c98f9e54d30bc` |
| `ClientLoader/ClientLoader.dylib` | Existing arm64 dylib | `4d09d14053bda35232fbd097ebfb58b66e2a42013f870ca5387d10040ee7049a` |
| `ClientLoader/package_ipa.py` | Existing arm64 Mach-O load-command and IPA staging helper reused by lab | `0303d838624a6e133a9537eff862f0257403f89e1c321e5b4589bfe5f285a52f` |
| `ClientLoader/test_package_ipa.py` | Existing helper tests | `178d8adaeab46c2d28b88dfe0d87d59ef553e8ffbda56569b89aaac603db4c5a` |
| `3105/Patches/Minecraft/settings.json` | 3105 patch workspace settings | `a2e8f7e85a1cb4c95d3837982cbf97e12e442eb29f8785127851cd875f46043d` |
| `3105/Patches/Minecraft/.3105-project.plist` | Binary plist: schema 4, project ID, display name only | `c571057bb287753b63809310d9eb71b6e1b6224eb0954ca666c71f6b917c697d` |
| `3105/Patches/Minecraft/3105-project-example.plist.txt` | Explicitly speculative format example | `862c4e7f2c8e29e20a85719d3fab28f53e8947bdc97d12a7889d67152340b2f9` |
| `3105/.../Documents/ClientLoader/scripts/client.js` | 3105 patch payload script | `b869e917d13dd3f4fbbef116fbf05451b4134db90b652584fb6e5256fa064946` |
| `ClientLoader.zip` | Source archive; root contains ClientLoader source | `2a8bec654ee37fec427d5ccf75360c320df46e3eb222f30309716ad6d8bbc0d6` |
| `3105.zip` | Archive root contains a 3105 patch tree | `432697f92f6b7ae7229c45238748e33a676284ea5cb09f4847cdc2378b1a1985` |
| `Minecraft-2.3105` | 812-byte `3105PATCH` wrapper; schema 9, password-protected, 403-byte encrypted payload. Payload content/runtime semantics not inspected. | `d5ff3111e2d52fe4f0c40b7c43cb9acaac3f5abf141164c5e805b306e59819f9` |
| `MCPE-iOS-26.33-universal.zip` | **Empty file** (SHA-256 is empty-content digest) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `Payload/minecraftpe.app/minecraftpe` | Mach-O arm64 executable | `8bb6a94e457972d3ea47b9716e51a5cc4fc9e5a915ebfb6b35d277cd4a9628f0` |
| `Payload/minecraftpe.app/Info.plist` | App identity metadata | `d18ba871ccc6b88f027c0ad184a7a082645d7345fe2ba8d463c8b98650f7b283` |

The existing entity registry is type metadata, not a list of spawned entities. `ChunkCaptureDiagnostic.json` labels itself `diagnostic_only`; its entity state is `not_captured`, and candidate entity/camera bridge calls were unavailable and not invoked.

## Existing structure and behavior inspected

- `ClientLoader/ClientLoader.m`, `ClientLoader/build.sh`, and `ClientLoader/README.md` for dylib loading, JavaScriptCore isolation, build flags, and installation flow.
- `ClientLoader/providers/CLEntityProvider.*`, `CLCameraProvider.*`, `CLProjection.*`, `CLESPOverlay.*`, and `CLDiagnostics.*` for snapshot, camera, projection, rendering, and diagnostics behavior.
- `ClientLoader/scripts/esp_test.js`, `ClientLoader/generated/entity_registry.json`, and the matching 3105 patch tree.
- `ClientLoader/research/bedrock-ios-1.26.33-static-analysis.md` for bounded binary findings. It reports no verified entity accessor, camera matrix source, or safe update hook; type names and Script API binding strings are not callable APIs.
- `ClientLoader.zip`, `3105.zip`, the extracted `Payload/minecraftpe.app`, and `ChunkCaptureDiagnostic.json`.

The 3105 patch metadata does not establish the installed app version. The encrypted `Minecraft-2.3105` payload cannot be inspected from the available inputs, and the named game archive is empty; the extracted app payload is the available binary evidence.

## Experimental implementation

- `native/ExperimentalLoader.m`: separate dylib constructor, active-window attachment, lifecycle, and 15 FPS snapshot refresh.
- `native/ESPOverlay.*`: touch-through overlay, fresh entity/camera gating, exact type filtering, max distance, labels, and provisional bounds.
- `native/CameraDataSource.*`, `native/WorldToScreen.h`: validated camera snapshot publication and projection adapter; no game camera producer.
- `src/entity/BNEEntityTracker.*`, `BNEEntitySnapshotProvider.*`, `src/projection/BNEProjection.*`, `src/common/BNEClock.*`: normalized event tracker, synchronized snapshots, projection, and monotonic clock.
- `tools/package_experimental_ipa.py`: stages the existing ClientLoader and a distinct lab dylib using the original packager's Mach-O helper.
- `build_ios.sh`: arm64/iOS 15 dylib build target; not executable on the current Linux host.