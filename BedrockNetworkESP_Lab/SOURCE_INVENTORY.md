# Source Inventory

## Workspace inputs

| Path | Observation | SHA-256 |
|---|---|---|
| `ClientLoader/ClientLoader.m` | Existing Objective-C loader/UI with diagnostic-only bridge/script/lifecycle instrumentation | `f6f3ed1547e19297be117dc36de1ab1b50491ecc3b3ae2f1052bf20e896ca666` |
| `ClientLoader/build.sh` | Existing arm64 build script with optional separate output path and build identity macros | `24bd9ecec49e36bd027b00007214f173fd57f9e6062f2b04fcfea0c484689ba2` |
| `ClientLoader/providers/CLEntityProvider.h` | Snapshot API | `6af36c724445ccdd8ea3872178fe979a13edbfb43d1b4d79776f2554b41de690` |
| `ClientLoader/providers/CLEntityProvider.m` | Snapshot validation/cache; no producer | `70d79835a24a40e08a490739fa6deea9f729dde503c745235e24186c1d115482` |
| `ClientLoader/providers/CLCameraProvider.h` | Matrix publication/projection API | `d4769143a32c8efdb6c218c29337e04148c016542d099a58813652ad7a6aa2b7` |
| `ClientLoader/providers/CLCameraProvider.m` | Externally-published matrix; unavailable until supplied | `3d02e5bddba573cb006f157b1855fcdc7e816ab5e1da5b5ad2af3bf3861f8163` |
| `ClientLoader/providers/CLProjection.c` | Portable column-major AABB projection | `fe3a104f8982059a5b94a156542f965138995f41cba186be1b07e5a38dfa8e47` |
| `ClientLoader/providers/CLESPOverlay.m` | Existing renderer with frame/rejection/draw counters and fixture-source refusal | `744497f525d60797f1a39f0c10218d44e7593f6a6d467c430f55d57caa87b0f0` |
| `ClientLoader/providers/CLDiagnostics.m` | Runtime export and bounded event metrics, with post-write verification | `0353ca253c184b0d809a98a54c263999b96f4ea685884a43b6021444dbc9ed06` |
| `ClientLoader/scripts/esp_test.js` | Synthetic/live toggles and diagnostics action | `c733b58b9299e69031a326d2102c596882ffe12e2653c3ed5e0c98f9e54d30bc` |
| `ClientLoader/ClientLoader.dylib` | Existing arm64 dylib | `4d09d14053bda35232fbd097ebfb58b66e2a42013f870ca5387d10040ee7049a` |
| `ClientLoader/package_ipa.py` | Inspected as existing load-command implementation; lab no longer imports it | `0303d838624a6e133a9537eff862f0257403f89e1c321e5b4589bfe5f285a52f` |
| `ClientLoader/test_package_ipa.py` | Existing packaging tests inspected; separate lab tests exercise the lab packager | `178d8adaeab46c2d28b88dfe0d87d59ef553e8ffbda56569b89aaac603db4c5a` |
| `3105/Patches/Minecraft/settings.json` | 3105 patch workspace settings | `a2e8f7e85a1cb4c95d3837982cbf97e12e442eb29f8785127851cd875f46043d` |
| `3105/Patches/Minecraft/.3105-project.plist` | Binary plist: schema 4, project ID, display name only | `c571057bb287753b63809310d9eb71b6e1b6224eb0954ca666c71f6b917c697d` |
| `3105/Patches/Minecraft/3105-project-example.plist.txt` | Explicitly speculative format example | `862c4e7f2c8e29e20a85719d3fab28f53e8947bdc97d12a7889d67152340b2f9` |
| `3105/.../Documents/ClientLoader/scripts/client.js` | 3105 patch payload script | `b869e917d13dd3f4fbbef116fbf05451b4134db90b652584fb6e5256fa064946` |
| `ClientLoader.zip` | Source archive; root contains ClientLoader source | `2a8bec654ee37fec427d5ccf75360c320df46e3eb222f30309716ad6d8bbc0d6` |
| `3105.zip` | Archive root contains a 3105 patch tree | `432697f92f6b7ae7229c45238748e33a676284ea5cb09f4847cdc2378b1a1985` |
| `MENU SR FFTH.3105` and `freefire/MENU SR FFTH.3105` | Byte-identical schema-9 password-protected `3105PATCH`; authenticated decryption attempts failed | `0ae403262693e0a4fcff4602afdae33864579424cc728527010f35cc7002ecc5` |
| `freefire/assetindexer.YJ~2FW7EkU5pRkVg51NrKyx4LXid8~3D` | UnityFS bundle, Unity `2022.3.47f1`; UnityPy inventory recorded in `docs/3105_sample_findings.md` | `93b6b6dc40ec6ad8f2550329f0297ed1bcf7d9902f8cf2539dd2629864952b1d` |
| `freefire/info.txt` | User description of the 3105 sample; not treated as implementation evidence | `88df3065efb1c5207f99e02541808cbafc5ce1e74210cb9731e5ae1e512792e1` |
| `freefire/info.txt` | User-provided description/password note | `88df3065efb1c5207f99e02541808cbafc5ce1e74210cb9731e5ae1e512792e1` |
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

The 3105 metadata does not establish the installed app version. The two menu copies are byte-identical and remain encrypted; the companion asset bundle is Unity/Free Fire data, not a Bedrock API. The extracted app payload identifies the static-analysis target; the installed device build remains unknown.

## Experimental implementation

- `native/ExperimentalLoader.m`: separate dylib constructor, active-window retries, lifecycle, and 15 FPS snapshot refresh.
- `native/Diagnostics.*`: bounded rotated JSONL logs, loaded-image/JS bridge probes, startup/ESP/game-data/network/symbol/build reports, session correlation, and verified file writes.
- `native/ESPOverlay.*`: touch-through overlay, fresh entity/camera gating, exact type filtering, max distance, labels, and provisional bounds.
- `native/CameraDataSource.*`, `native/WorldToScreen.h`: validated camera snapshot publication and projection adapter; no game camera producer.
- `src/entity/BNEEntityTracker.*`, `BNEEntitySnapshotProvider.*`, `src/projection/BNEProjection.*`, `src/common/BNEClock.*`: normalized event tracker, synchronized snapshots, projection, and monotonic clock.
- `tools/package_experimental_ipa.py`, `tools/bne_macho.py`: self-contained package staging and arm64 Mach-O load-command helpers; existing ClientLoader is only a binary input.
- `build_ios.sh`: arm64/iOS 15 dylib build target; not executable on the current Linux host.