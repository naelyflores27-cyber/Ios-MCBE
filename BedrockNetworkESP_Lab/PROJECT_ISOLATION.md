# Project Isolation

**Verified:** experimental files and build outputs live in `BedrockNetworkESP_Lab/`. Per the diagnostic request, source-only instrumentation was added to `ClientLoader/ClientLoader.m`, `ClientLoader/build.sh`, `CLDiagnostics`, and `CLESPOverlay`; the existing menu, feature names, callbacks, and default behaviors are retained. The existing `ClientLoader.dylib`, Minecraft app executable, and 3105 files were not edited or overwritten. The original `ClientLoader.zip` and dylib remain unchanged baselines.

**Verified:** immutable original/binary/archive SHA-256 values are in `tools/original_files.sha256`; intentional diagnostic source changes are tracked separately in `tools/diagnostic_sources.sha256`. From this directory, verify both with:

```sh
sh tools/verify_originals.sh
```

Verification is read-only. `git status --short` should show intended ClientLoader source edits and the lab/workflow changes; the existing `ClientLoader.dylib`, app executable, 3105 payloads, and source archive remain unchanged.

The lab build writes only to this directory's `build/`. The diagnostic ClientLoader build is configured with `CL_OUTPUT_PATH` to write its output into that same build directory rather than replacing `ClientLoader/ClientLoader.dylib`. The IPA tool stages both libraries and a copy of the app into a new output IPA and refuses to overwrite existing output. It does not modify `3105/`, `Payload/`, or `Minecraft-2.3105`. Reinstall the original app and dylib to roll back the diagnostic package.