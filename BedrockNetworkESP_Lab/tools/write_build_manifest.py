#!/usr/bin/env python3
"""Create a checksum-bound manifest for an experimental iOS dylib build."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
from pathlib import Path


def write_manifest(dylib: Path, revision: str, built_at: str,
                   expected_game_build: str, output: Path,
                   client_loader: Path | None = None,
                   expected_script: Path | None = None) -> None:
    data = dylib.read_bytes()
    expected_script_hash = (
        hashlib.sha256(expected_script.read_bytes()).hexdigest()
        if expected_script is not None and expected_script.is_file()
        else "c733b58b9299e69031a326d2102c596882ffe12e2653c3ed5e0c98f9e54d30bc"
    )
    manifest = {
        "schemaVersion": 1,
        "sourceRevision": revision,
        "buildTimestampUTC": built_at,
        "artifact": dylib.name,
        "artifactBytes": len(data),
        "artifactSHA256": hashlib.sha256(data).hexdigest(),
        "targetArchitecture": "arm64",
        "minimumIOS": "15.0",
        "expectedMinecraftBuild": expected_game_build,
        "expectedBuildIsDeviceVerified": False,
        "expectedESPTestScriptSHA256": expected_script_hash,
        "hostPlatform": platform.platform(),
        "compiledFeatures": [
            "bounded-jsonl-native-diagnostics",
            "startup-and-lifecycle-reports",
            "source-independent-entity-tracker",
            "touch-through-overlay",
            "camera-source-validation",
            "no-live-network-decoder",
            "no-undocumented-game-hook",
        ],
    }
    manifest["companionDiagnosticLoader"] = None
    if client_loader is not None:
        companion = client_loader.read_bytes()
        manifest["companionDiagnosticLoader"] = {
            "artifact": client_loader.name,
            "artifactBytes": len(companion),
            "artifactSHA256": hashlib.sha256(companion).hexdigest(),
            "installName": "@executable_path/Frameworks/ClientLoader.dylib",
        }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dylib", required=True, type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--built-at", required=True)
    parser.add_argument("--expected-game-build", required=True)
    parser.add_argument("--client-loader", type=Path)
    parser.add_argument("--expected-esp-script", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    write_manifest(args.dylib, args.revision, args.built_at,
                   args.expected_game_build, args.output, args.client_loader,
                   args.expected_esp_script)
    print(f"Wrote build manifest: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())