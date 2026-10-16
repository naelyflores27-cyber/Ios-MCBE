#!/usr/bin/env python3
"""Stage an unsigned IPA with both the existing and experimental arm64 dylibs."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(WORKSPACE / "ClientLoader"))

from package_ipa import add_dylib_load_command, validate_loader  # noqa: E402

CLIENT_LOADER_NAME = "ClientLoader.dylib"
EXPERIMENTAL_LOADER_NAME = "BedrockNetworkESP_Lab.dylib"
EXPERIMENTAL_INSTALL_NAME = (
    "@executable_path/Frameworks/" + EXPERIMENTAL_LOADER_NAME
)


def make_experimental_ipa(
    app_dir: Path, client_loader: Path, experimental_loader: Path, output: Path
) -> None:
    app_dir = app_dir.resolve()
    client_loader = client_loader.resolve()
    experimental_loader = experimental_loader.resolve()
    output = output.resolve()
    if not app_dir.is_dir() or app_dir.suffix != ".app":
        raise ValueError("--app must name an expanded .app directory")
    if not (app_dir / "Info.plist").is_file() or not (app_dir / "minecraftpe").is_file():
        raise ValueError("--app must contain Info.plist and minecraftpe")
    if not client_loader.is_file() or not experimental_loader.is_file():
        raise ValueError("both input dylibs must exist")
    if client_loader == experimental_loader:
        raise ValueError("ClientLoader and experimental dylibs must be distinct files")
    if output.exists():
        raise ValueError(f"refusing to overwrite existing output: {output}")
    validate_loader(client_loader)
    validate_loader(experimental_loader)
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="bne-ipa-", dir=output.parent) as temporary:
        temporary_root = Path(temporary)
        payload = temporary_root / "Payload"
        payload.mkdir()
        staged_app = payload / app_dir.name
        shutil.copytree(app_dir, staged_app, symlinks=True)

        frameworks = staged_app / "Frameworks"
        frameworks.mkdir(exist_ok=True)
        shutil.copy2(client_loader, frameworks / CLIENT_LOADER_NAME)
        shutil.copy2(experimental_loader, frameworks / EXPERIMENTAL_LOADER_NAME)

        executable = staged_app / "minecraftpe"
        add_dylib_load_command(
            executable, "@executable_path/Frameworks/" + CLIENT_LOADER_NAME
        )
        add_dylib_load_command(executable, EXPERIMENTAL_INSTALL_NAME)

        staged_output = temporary_root / output.name
        with zipfile.ZipFile(staged_output, "w", compression=zipfile.ZIP_STORED) as archive:
            for directory, subdirectories, filenames in os.walk(payload):
                subdirectories.sort()
                filenames.sort()
                directory_path = Path(directory)
                for name in subdirectories:
                    item = directory_path / name
                    if not item.is_symlink():
                        archive.writestr(
                            item.relative_to(temporary_root).as_posix() + "/", b""
                        )
                for name in filenames:
                    item = directory_path / name
                    if item.is_symlink():
                        info = zipfile.ZipInfo(item.relative_to(temporary_root).as_posix())
                        info.create_system = 3
                        info.external_attr = 0o120777 << 16
                        archive.writestr(info, os.readlink(item).encode())
                        continue
                    relative = item.relative_to(temporary_root).as_posix()
                    info = zipfile.ZipInfo.from_file(item, relative)
                    info.compress_type = zipfile.ZIP_STORED
                    with item.open("rb") as source, archive.open(info, "w") as target:
                        shutil.copyfileobj(source, target, length=1024 * 1024)
        os.replace(staged_output, output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--client-loader", required=True, type=Path)
    parser.add_argument("--experimental-loader", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        make_experimental_ipa(
            args.app, args.client_loader, args.experimental_loader, args.output
        )
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"package_experimental_ipa.py: {error}", file=sys.stderr)
        return 1
    print(f"Created unsigned IPA: {args.output}")
    print("The copied app executable and both dylibs must be signed before installation.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())