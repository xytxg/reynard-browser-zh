"""Packaging regression tests. Tiny synthetic bundles are fixtures, not installable IPAs."""
import importlib.util
import io
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "ipa_validator", Path(__file__).resolve().parents[1] / "tools/release/verify-unsigned-ipa.py"
)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def packed_version(version):
    major, minor, patch = version
    return (major << 16) | (minor << 8) | patch


def macho(signed=False, minimum_ios=(15, 0, 0), sdk=(27, 0, 0)):
    build_version = struct.pack(
        "<6I", 0x32, 24, 2, packed_version(minimum_ios), packed_version(sdk), 0
    )
    signature = struct.pack("<4I", 0x1D, 16, 48, 8) if signed else b""
    commands = build_version + signature
    return struct.pack(
        "<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 1 + int(signed), len(commands), 0, 0
    ) + commands


class UnsignedIPATests(unittest.TestCase):
    def fixture(self):
        root = "Payload/Reynard.app/"
        info = {"CFBundleIdentifier": "test.Reynard", "CFBundleExecutable": "Reynard",
                "CFBundleVersion": "42", "CFBundleShortVersionString": "0.11.0", "MinimumOSVersion": "15.0",
                "CFBundleURLTypes": [{"CFBundleURLSchemes": ["reynard", "http", "https"]}]}
        entries = {root + "Info.plist": plistlib.dumps(info), root + "Reynard": macho(), root + "Frameworks/XUL": macho()}
        for name in ("PlugIns/OpenIn.appex", "PlugIns/Reynard Helper.appex", "Frameworks/GeckoView.framework"):
            child = dict(info, CFBundleIdentifier="test.Reynard.child", CFBundleExecutable="Executable")
            entries[root + name + "/Info.plist"] = plistlib.dumps(child)
            entries[root + name + "/Executable"] = macho()
        for catalog in ("Localizable", "AddonLocalizable", "SettingsLocalizable", "InfoPlist"):
            entries[root + "zh-Hans.lproj/" + catalog + ".strings"] = plistlib.dumps({"Pause": "暂停", "Resume": "继续下载"})
        return entries

    def verify_entries(self, entries):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fixture.zip"
            with zipfile.ZipFile(path, "w") as archive:
                for name, data in entries.items():
                    archive.writestr(name, data)
            return validator.verify(path)

    def test_unsigned_header(self):
        minimum_versions = []
        self.assertEqual(
            validator.check_macho(io.BytesIO(macho()), minimum_ios_versions=minimum_versions),
            {0x0100000C},
        )
        self.assertEqual(minimum_versions, [(15, 0, 0)])

    def test_signed_header_rejected(self):
        with self.assertRaisesRegex(ValueError, "LC_CODE_SIGNATURE"):
            validator.check_macho(io.BytesIO(macho(signed=True)))

    def test_complete_fixture(self):
        self.assertEqual(self.verify_entries(self.fixture())["mach_o_files"], 5)

    def test_missing_browser_url_scheme_rejected(self):
        entries = self.fixture()
        info_path = "Payload/Reynard.app/Info.plist"
        info = plistlib.loads(entries[info_path])
        info["CFBundleURLTypes"] = [{"CFBundleURLSchemes": ["reynard"]}]
        entries[info_path] = plistlib.dumps(info)
        with self.assertRaisesRegex(ValueError, "HTTP/HTTPS URL schemes"):
            self.verify_entries(entries)

    def test_missing_extension_rejected(self):
        entries = self.fixture()
        del entries["Payload/Reynard.app/PlugIns/OpenIn.appex/Executable"]
        with self.assertRaisesRegex(ValueError, "arm64 binary"):
            self.verify_entries(entries)

    def test_newer_binary_deployment_target_rejected(self):
        entries = self.fixture()
        entries["Payload/Reynard.app/Reynard"] = macho(minimum_ios=(16, 0, 0))
        with self.assertRaisesRegex(ValueError, "newer than iOS 15"):
            self.verify_entries(entries)

    def test_manifest_deployment_target_rejected(self):
        entries = self.fixture()
        info_path = "Payload/Reynard.app/Info.plist"
        info = plistlib.loads(entries[info_path])
        info["MinimumOSVersion"] = "13.0"
        entries[info_path] = plistlib.dumps(info)
        with self.assertRaisesRegex(ValueError, "must be iOS 15.0"):
            self.verify_entries(entries)

    def test_nested_signature_rejected(self):
        entries = self.fixture()
        entries["Payload/Reynard.app/Frameworks/XUL"] = macho(signed=True)
        with self.assertRaisesRegex(ValueError, "LC_CODE_SIGNATURE"):
            self.verify_entries(entries)

    def test_wrong_language_rejected(self):
        entries = self.fixture()
        entries["Payload/Reynard.app/zh-Hans.lproj/Localizable.strings"] = plistlib.dumps({"Pause": "Pause"})
        with self.assertRaisesRegex(ValueError, "Chinese download controls"):
            self.verify_entries(entries)

    def test_provisioning_profile_rejected(self):
        entries = self.fixture()
        entries["Payload/Reynard.app/embedded.mobileprovision"] = b"profile"
        with self.assertRaisesRegex(ValueError, "Signing metadata"):
            self.verify_entries(entries)


if __name__ == "__main__":
    unittest.main()
