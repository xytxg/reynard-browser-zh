#!/usr/bin/env python3
"""Validate the packaged IPA, including Mach-O load commands (not just codesign output)."""

import json
import plistlib
import re
import struct
import sys
import zipfile
from pathlib import PurePosixPath


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unpack_apple_version(value):
    return value >> 16, (value >> 8) & 0xFF, value & 0xFF


def parse_version(value):
    components = [int(part) for part in str(value).split(".")]
    require(1 <= len(components) <= 3, "Invalid iOS deployment version")
    return tuple((components + [0, 0])[:3])


def check_macho(stream, offset=0, minimum_ios_versions=None):
    stream.seek(offset)
    magic = stream.read(4)
    if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        count = struct.unpack(">I", stream.read(4))[0]
        require(0 < count <= 32, "Invalid universal binary architecture count")
        wide = magic == b"\xca\xfe\xba\xbf"
        records = [stream.read(32 if wide else 20) for _ in range(count)]
        architectures = set()
        for record in records:
            child_offset = struct.unpack_from(">Q" if wide else ">I", record, 8)[0]
            require(child_offset > 0, "Invalid universal binary slice offset")
            architectures.update(
                check_macho(stream, offset + child_offset, minimum_ios_versions)
            )
        return architectures
    if magic not in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
        return set()
    header = stream.read(28 if magic == b"\xcf\xfa\xed\xfe" else 24)
    cpu, _, _, count, size, _ = struct.unpack_from("<6I", header)
    require(count <= 65536 and size <= 16 * 1024 * 1024, "Invalid Mach-O command table")
    commands = stream.read(size)
    require(len(commands) == size, "Truncated Mach-O command table")
    cursor = 0
    for _ in range(count):
        require(cursor + 8 <= len(commands), "Truncated Mach-O command")
        command, length = struct.unpack_from("<II", commands, cursor)
        require(length >= 8 and cursor + length <= len(commands), "Invalid Mach-O command size")
        require(command != 0x1D, "LC_CODE_SIGNATURE remains in an unsigned binary")
        if minimum_ios_versions is not None and command == 0x25:
            require(length >= 16, "Invalid LC_VERSION_MIN_IPHONEOS command")
            minimum_ios_versions.append(
                unpack_apple_version(struct.unpack_from("<I", commands, cursor + 8)[0])
            )
        elif minimum_ios_versions is not None and command == 0x32:
            require(length >= 24, "Invalid LC_BUILD_VERSION command")
            platform, minimum = struct.unpack_from("<II", commands, cursor + 8)
            if platform == 2:  # PLATFORM_IOS; simulator slices are not accepted here.
                minimum_ios_versions.append(unpack_apple_version(minimum))
        cursor += length
    require(cursor == size, "Mach-O command count/size mismatch")
    return {cpu}


def verify(path):
    root = "Payload/Reynard.app/"
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "IPA contains duplicate paths")
        require(archive.testzip() is None, "IPA CRC validation failed")
        for name in names:
            parts = PurePosixPath(name).parts
            require(not name.startswith("/") and ".." not in parts, "Unsafe archive path")
            require(name == "Payload/" or name.startswith(root), "Unexpected IPA root")
            require("_CodeSignature" not in parts and parts[-1] not in (
                "embedded.mobileprovision", "CodeResources"
            ), "Signing metadata remains in IPA")

        app = plistlib.loads(archive.read(root + "Info.plist"))
        require(re.fullmatch(r"\d+(?:\.\d+){0,2}", str(app["CFBundleVersion"])), "Build number is not numeric")
        require(
            parse_version(app["MinimumOSVersion"]) == (15, 0, 0),
            "App deployment target must be iOS 15.0",
        )
        registered_schemes = {
            scheme.lower()
            for url_type in app.get("CFBundleURLTypes", [])
            for scheme in url_type.get("CFBundleURLSchemes", [])
            if isinstance(scheme, str)
        }
        require(
            {"http", "https"}.issubset(registered_schemes),
            "HTTP/HTTPS URL schemes required for default-browser delivery are missing",
        )
        expected_binaries = []
        for bundle in (root, root + "PlugIns/OpenIn.appex/", root + "PlugIns/Reynard Helper.appex/", root + "Frameworks/GeckoView.framework/"):
            info = plistlib.loads(archive.read(bundle + "Info.plist"))
            executable = info["CFBundleExecutable"]
            require(executable and "/" not in executable, "Invalid bundle executable")
            expected_binaries.append(bundle + executable)
            if ".appex/" in bundle:
                require(info["CFBundleIdentifier"].startswith(app["CFBundleIdentifier"] + "."), "Extension bundle ID mismatch")
                require(info["CFBundleVersion"] == app["CFBundleVersion"], "Extension build number mismatch")
        require(root + "Frameworks/XUL" not in names, "Extensionless XUL library remains in IPA")
        expected_binaries.append(root + "Frameworks/XUL.dylib")

        checked = {}
        minimum_ios_by_binary = {}
        for item in archive.infolist():
            if not item.is_dir():
                minimum_ios_versions = []
                with archive.open(item) as stream:
                    architectures = check_macho(stream, minimum_ios_versions=minimum_ios_versions)
                if architectures:
                    checked[item.filename] = architectures
                    minimum_ios_by_binary[item.filename] = minimum_ios_versions
        for name in expected_binaries:
            require(0x0100000C in checked.get(name, set()), "Required arm64 binary is absent: " + name)
            versions = minimum_ios_by_binary.get(name, [])
            require(versions, "Required iOS deployment load command is absent: " + name)
            require(max(versions) <= (15, 0, 0), "A required binary requires newer than iOS 15: " + name)

        chinese = plistlib.loads(archive.read(root + "zh-Hans.lproj/Localizable.strings"))
        require(chinese.get("Pause") == "暂停" and chinese.get("Resume") == "继续下载", "Chinese download controls are missing")
        for catalog in ("AddonLocalizable", "SettingsLocalizable", "InfoPlist"):
            require(root + f"zh-Hans.lproj/{catalog}.strings" in names, "Chinese catalog missing: " + catalog)
        maximum_binary_minimum = max(
            version for name in expected_binaries for version in minimum_ios_by_binary[name]
        )
        return {"version": app["CFBundleShortVersionString"], "build": app["CFBundleVersion"],
                "minimum_ios": app["MinimumOSVersion"], "mach_o_files": len(checked),
                "mach_o_minimum_ios": ".".join(map(str, maximum_binary_minimum)),
                "signing": "unsigned", "chinese": "verified"}


if __name__ == "__main__":
    require(len(sys.argv) == 2, "Usage: verify-unsigned-ipa.py <output.ipa>")
    print(json.dumps(verify(sys.argv[1]), ensure_ascii=False))
