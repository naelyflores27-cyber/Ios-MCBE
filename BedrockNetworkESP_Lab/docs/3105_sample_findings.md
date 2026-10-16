# Supplied 3105 Sample Findings

## `MENU SR FFTH.3105`

**Verified:** this is not a ZIP. It begins with `3105PATCH\0bplist00`. Its binary-plist metadata identifies schema 9, `isPasswordProtected=true`, KDF iteration count 250,000, 16-byte salt, 60-byte wrapped-content-key field, 32-byte key fingerprint, and a 509,366-byte encrypted payload. The package ID is retained in the inventory; password/key material is not logged.

**Password attempt:** used only the password supplied for this file. Tested PBKDF2-HMAC-SHA-256/SHA-512/SHA-1 at the declared iteration count, AES-GCM nonce-first/nonce-last layouts, and a finite set of AAD candidates derived from the package ID, schema/AAD version, and container magic. None authenticated the wrapped key (zero valid GCM tags). No plaintext was written or exposed; the password itself is not recorded in logs or manifests.

**Conclusion:** the password itself is not proven wrong. The format’s KDF/cipher/AAD/field encoding is not documented in available files, and the 3105 application/runtime source is unavailable. Without that implementation or format specification, the payload cannot be safely opened. The archive therefore reveals no JavaScript, API calls, hooks, or entity access behavior.

## `assetindexer.YJ~2FW7EkU5pRkVg51NrKyx4LXid8~3D`

**Verified:** UnityPy parses this as a UnityFS bundle whose header reports Unity `2022.3.47f1`. It contains 16 `MonoBehaviour`, five `MonoScript`, one `AssetBundle`, one `GameObject`, and one `Transform`; it contains no `TextAsset`. The script-class records name `RaceData`, `UMATextRecipe`, `UMAMeshAsset`, `UMAAssetIndexer`, and `UmaTPose`, associated with `Assembly-CSharp`/UMA namespaces.

This is serialized Unity game/asset metadata, not a standalone script or Minecraft Bedrock entity API. Combined with the supplied note naming Free Fire, it is evidence for an asset-patching route in a Unity game. It does not prove that the encrypted menu loads code, that it works in Minecraft, or that it exposes Minecraft entities/camera state.

## 3105 route assessment

The sample is useful evidence that a 3105 package can target game assets/files, but it does not change the native-loader conclusion: data replacement and a native `LC_LOAD_DYLIB` loader are different mechanisms. The encrypted menu cannot be evaluated until the 3105 format implementation/specification is provided. The next useful input is the 3105 app/version or its documented package-format implementation; no further password guessing is justified.