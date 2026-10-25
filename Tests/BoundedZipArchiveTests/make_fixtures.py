#!/usr/bin/env python3
"""Writes malformed and valid ZIP fixtures for BoundedZipArchiveTests."""

import os
import struct
import sys
import zipfile


def patch_u32(data, signature, offset, value, expected=None):
    index = data.find(signature)
    assert index >= 0, signature
    if expected is not None:
        assert struct.unpack_from("<I", data, index + offset)[0] == expected
    struct.pack_into("<I", data, index + offset, value)


def main(directory):
    os.makedirs(directory, exist_ok=True)
    path = lambda name: os.path.join(directory, name)

    with zipfile.ZipFile(path("ok.zip"), "w") as archive:
        archive.writestr("icons/a.png", b"A" * 3000, compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr("b.txt", b"hello", compress_type=zipfile.ZIP_STORED)
        archive.writestr("../b.txt", b"evil", compress_type=zipfile.ZIP_STORED)

    with zipfile.ZipFile(path("big.zip"), "w") as archive:
        archive.writestr("big.bin", b"\0" * 10000, compress_type=zipfile.ZIP_DEFLATED)

    with zipfile.ZipFile(path("many.zip"), "w") as archive:
        for index in range(20):
            archive.writestr(f"f{index}", b"x")

    # Deflate bomb: 1 MiB of zeros whose headers claim 100 bytes.
    real_size = 1 << 20
    with zipfile.ZipFile(path("bomb.zip"), "w") as archive:
        archive.writestr("x.bin", b"\0" * real_size, compress_type=zipfile.ZIP_DEFLATED)
    data = bytearray(open(path("bomb.zip"), "rb").read())
    patch_u32(data, b"PK\x03\x04", 22, 100, real_size)
    patch_u32(data, b"PK\x01\x02", 24, 100, real_size)
    open(path("bomb.zip"), "wb").write(data)

    with zipfile.ZipFile(path("crc.zip"), "w") as archive:
        archive.writestr("b.txt", b"hello", compress_type=zipfile.ZIP_STORED)
    data = bytearray(open(path("crc.zip"), "rb").read())
    patch_u32(data, b"PK\x03\x04", 14, 0xDEADBEEF)
    patch_u32(data, b"PK\x01\x02", 16, 0xDEADBEEF)
    open(path("crc.zip"), "wb").write(data)

    open(path("notzip.zip"), "wb").write(b"not a zip file at all" * 10)


if __name__ == "__main__":
    main(sys.argv[1])
