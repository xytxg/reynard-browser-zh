import Foundation

private enum ZIPTestFailure: Error { case failed(String) }
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ZIPTestFailure.failed(message) }
}

@main
struct AddonPackageSafetyTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Assemble an empty-file ZIP with central directory and manifest.json.
        let valid = root.appendingPathComponent("valid.xpi")
        try zipEntry(name: "manifest.json").write(to: valid)
        try AddonPackageSafety.validate(fileURL: valid)

        for (name, bytes) in [
            ("fake-header.xpi", Data([0x50, 0x4b, 0x03, 0x04])),
            ("traversal.xpi", zipEntry(name: "../manifest.json")),
            ("no-manifest.xpi", zipEntry(name: "README.md")),
            ("invalid-name.xpi", zipEntry(name: "invalid\\path")),
        ] {
            let file = root.appendingPathComponent(name)
            try bytes.write(to: file)
            do {
                try AddonPackageSafety.validate(fileURL: file)
                throw ZIPTestFailure.failed("Accepted invalid ZIP: \(name)")
            } catch AddonPackageSafety.ValidationError.invalidPackage {
                // Expected rejection.
            }
        }
        print("AddonPackageSafetyTests: all tests passed")
    }

    private static func zipEntry(name: String) -> Data {
        let utf8 = Data(name.utf8)
        var local = Data()
        func append16(_ data: inout Data, _ v: UInt16) {
            data.append(UInt8(truncatingIfNeeded: v))
            data.append(UInt8(truncatingIfNeeded: v >> 8))
        }
        func append32(_ data: inout Data, _ v: UInt32) {
            append16(&data, UInt16(truncatingIfNeeded: v))
            append16(&data, UInt16(truncatingIfNeeded: v >> 16))
        }
        append32(&local, 0x04034b50)
        append16(&local, 20); append16(&local, 0); append16(&local, 0)
        append16(&local, 0); append16(&local, 0)
        append32(&local, 0); append32(&local, 0); append32(&local, 0)
        append16(&local, UInt16(utf8.count)); append16(&local, 0)
        local.append(utf8)
        var central = Data()
        append32(&central, 0x02014b50)
        append16(&central, 20); append16(&central, 20)
        append16(&central, 0); append16(&central, 0)
        append16(&central, 0); append16(&central, 0)
        append32(&central, 0); append32(&central, 0); append32(&central, 0)
        append16(&central, UInt16(utf8.count))
        append16(&central, 0); append16(&central, 0)
        append16(&central, 0); append16(&central, 0)
        append32(&central, 0); append32(&central, 0)
        central.append(utf8)
        var footer = Data()
        append32(&footer, 0x06054b50)
        append16(&footer, 0); append16(&footer, 0)
        append16(&footer, 1); append16(&footer, 1)
        append32(&footer, UInt32(central.count))
        append32(&footer, UInt32(local.count))
        append16(&footer, 0)
        return local + central + footer
    }
}
