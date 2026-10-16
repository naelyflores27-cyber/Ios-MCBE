# Project Isolation

**Verified:** this experiment lives only in `BedrockNetworkESP_Lab/`. No original file was edited, copied over, renamed, or used as an output target. The original workspace was already dirty at inspection: existing project files and archives were untracked by Git, so Git status alone cannot establish their prior contents.

**Verified:** SHA-256 digests for the inspected originals and archives were recorded in `tools/original_files.sha256`. From this directory, verify them with:

```sh
sh tools/verify_originals.sh
```

The checksum manifest includes the existing ClientLoader dylib, loader and packager source/tests, provider files, 3105 settings/plist/script/encrypted patch wrapper, source archives, and supplied app metadata/executable. Verification is read-only. `git status --short` from the workspace root should show the lab directory as new/untracked; it should not show edits within the original files.

The iOS build writes only to this directory's `build/`. The IPA tool reads the original app and `ClientLoader.dylib`, stages both in a temporary copy, and writes a new output IPA; it refuses to overwrite an existing output. It never writes to `ClientLoader/`, `3105/`, `Payload/`, or `Minecraft-2.3105`. Delete this directory to remove the experiment; retain the original paths and their prior checksums.