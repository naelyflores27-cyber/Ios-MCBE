"""Bounded arm64 Mach-O helpers used only by the experimental IPA packager."""

from __future__ import annotations

import struct
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
MH_EXECUTE = 2
MH_DYLIB = 6
CPU_TYPE_ARM64 = 0x0100000C
LC_LOAD_DYLIB = 0x0000000C
LC_SEGMENT_64 = 0x00000019
HEADER_SIZE = 32


class MachOError(ValueError):
    pass


def _read_header(data: bytes) -> tuple[int, int, int, int]:
    if len(data) < HEADER_SIZE:
        raise MachOError("Mach-O is shorter than its 64-bit header")
    magic, cpu_type, _, file_type, command_count, command_bytes, _, _ = struct.unpack_from(
        "<IiiIIIII", data
    )
    if magic != MH_MAGIC_64:
        raise MachOError("expected little-endian 64-bit Mach-O")
    if cpu_type != CPU_TYPE_ARM64:
        raise MachOError("expected arm64 Mach-O")
    command_end = HEADER_SIZE + command_bytes
    if command_end > len(data):
        raise MachOError("Mach-O load-command table extends past end of file")
    return file_type, command_count, command_bytes, command_end


def _commands(data: bytes, command_count: int, command_bytes: int):
    offset = HEADER_SIZE
    limit = HEADER_SIZE + command_bytes
    for _ in range(command_count):
        if offset + 8 > limit:
            raise MachOError("truncated Mach-O load command")
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > limit:
            raise MachOError("invalid Mach-O load-command size")
        yield offset, command, size
        offset += size
    if offset != limit:
        raise MachOError("load-command sizes do not match header")


def _first_section_offset(data: bytes, command_count: int, command_bytes: int) -> int:
    section_offsets = []
    for offset, command, size in _commands(data, command_count, command_bytes):
        if command != LC_SEGMENT_64:
            continue
        if size < 72:
            raise MachOError("truncated LC_SEGMENT_64 command")
        section_count = struct.unpack_from("<I", data, offset + 64)[0]
        if 72 + section_count * 80 > size:
            raise MachOError("truncated Mach-O section table")
        for index in range(section_count):
            section_offset = offset + 72 + index * 80
            file_offset = struct.unpack_from("<I", data, section_offset + 48)[0]
            if file_offset:
                section_offsets.append(file_offset)
    if not section_offsets:
        raise MachOError("could not locate first Mach-O section")
    return min(section_offsets)


def add_dylib_load_command(executable: Path, install_name: str) -> bool:
    data = bytearray(executable.read_bytes())
    file_type, command_count, command_bytes, command_end = _read_header(data)
    if file_type != MH_EXECUTE:
        raise MachOError("target Mach-O is not an executable")
    if not install_name or "\0" in install_name:
        raise MachOError("invalid dylib install name")

    encoded_name = install_name.encode("utf-8") + b"\0"
    command_size = (24 + len(encoded_name) + 7) & ~7
    for offset, command, size in _commands(data, command_count, command_bytes):
        if command != LC_LOAD_DYLIB:
            continue
        name_offset = struct.unpack_from("<I", data, offset + 8)[0]
        if name_offset < 24 or name_offset >= size:
            raise MachOError("invalid dylib-name offset")
        existing = bytes(data[offset + name_offset : offset + size]).split(b"\0", 1)[0]
        if existing.decode("utf-8", errors="replace") == install_name:
            return False

    first_section = _first_section_offset(data, command_count, command_bytes)
    if command_end + command_size > first_section:
        raise MachOError("not enough Mach-O header padding for dylib load command")
    load_command = struct.pack(
        "<IIIIII", LC_LOAD_DYLIB, command_size, 24, 0, 0x10000, 0x10000
    ) + encoded_name
    load_command += b"\0" * (command_size - len(load_command))
    data[command_end : command_end + command_size] = load_command
    struct.pack_into("<I", data, 16, command_count + 1)
    struct.pack_into("<I", data, 20, command_bytes + command_size)
    executable.write_bytes(data)
    return True


def validate_loader(loader: Path) -> None:
    file_type, _, _, _ = _read_header(loader.read_bytes())
    if file_type != MH_DYLIB:
        raise MachOError("loader must be an arm64 dynamic library")