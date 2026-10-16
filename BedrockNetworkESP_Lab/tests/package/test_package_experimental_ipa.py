import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from package_experimental_ipa import (  # noqa: E402
    CLIENT_LOADER_NAME,
    EXPERIMENTAL_INSTALL_NAME,
    EXPERIMENTAL_LOADER_NAME,
    make_experimental_ipa,
)

MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
LC_LOAD_DYLIB = 0x0000000C
LC_SEGMENT_64 = 0x00000019
HEADER_SIZE = 32


def minimal_macho(file_type=2):
    section_offset = 4096
    segment_size = 72 + 80
    data = bytearray(section_offset + 64)
    struct.pack_into(
        "<IiiIIIII", data, 0, MH_MAGIC_64, CPU_TYPE_ARM64, 0,
        file_type, 1, segment_size, 0, 0
    )
    struct.pack_into("<II", data, HEADER_SIZE, LC_SEGMENT_64, segment_size)
    struct.pack_into("<I", data, HEADER_SIZE + 64, 1)
    struct.pack_into("<I", data, HEADER_SIZE + 72 + 48, section_offset)
    return bytes(data)


def dylib_paths(data):
    _, _, _, _, command_count, command_bytes, _, _ = struct.unpack_from(
        "<IiiIIIII", data
    )
    offset = HEADER_SIZE
    paths = []
    for _ in range(command_count):
        command, size = struct.unpack_from("<II", data, offset)
        if command == LC_LOAD_DYLIB:
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            name = data[offset + name_offset : offset + size].split(b"\0", 1)[0]
            paths.append(name.decode())
        offset += size
    assert offset == HEADER_SIZE + command_bytes
    return paths


class ExperimentalPackageTests(unittest.TestCase):
    def test_stages_two_dylibs_without_modifying_original_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "minecraftpe.app"
            (app / "Frameworks").mkdir(parents=True)
            (app / "Info.plist").write_bytes(b"plist")
            executable = app / "minecraftpe"
            executable.write_bytes(minimal_macho())
            original_executable = executable.read_bytes()

            client_loader = root / CLIENT_LOADER_NAME
            client_loader.write_bytes(minimal_macho(file_type=6))
            experimental_loader = root / EXPERIMENTAL_LOADER_NAME
            experimental_loader.write_bytes(minimal_macho(file_type=6))
            output = root / "lab.ipa"
            make_experimental_ipa(app, client_loader, experimental_loader, output)

            self.assertEqual(executable.read_bytes(), original_executable)
            with zipfile.ZipFile(output) as archive:
                prefix = "Payload/minecraftpe.app/"
                packaged_executable = archive.read(prefix + "minecraftpe")
                self.assertEqual(
                    archive.read(prefix + "Frameworks/" + CLIENT_LOADER_NAME),
                    client_loader.read_bytes(),
                )
                self.assertEqual(
                    archive.read(prefix + "Frameworks/" + EXPERIMENTAL_LOADER_NAME),
                    experimental_loader.read_bytes(),
                )
            self.assertEqual(
                dylib_paths(packaged_executable),
                [
                    "@executable_path/Frameworks/" + CLIENT_LOADER_NAME,
                    EXPERIMENTAL_INSTALL_NAME,
                ],
            )


if __name__ == "__main__":
    unittest.main()