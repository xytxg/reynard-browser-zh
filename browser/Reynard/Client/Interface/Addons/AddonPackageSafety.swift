//
//  AddonPackageSafety.swift
//  Reynard
//
//  Archive preflight for untrusted WebExtension packages.
//

import Foundation

enum AddonPackageSafety {
    private static let maximumPackageSize: Int64 = 128 * 1024 * 1024
    private static let maximumUnpackedSize: UInt64 = 512 * 1024 * 1024
    private static let maximumEntries = 20_000
    private static let maximumDirectorySize = 32 * 1024 * 1024

    enum ValidationError: LocalizedError {
        case invalidPackage

        var errorDescription: String? {
            NSLocalizedString("The selected add-on package is invalid or too large.", comment: "")
        }
    }

    // This does not replace Gecko's add-on signature and permission checks.
    // It rejects malformed and suspicious archives before passing them to Gecko.
    static func validate(fileURL: URL) throws {
        guard fileURL.isFileURL,
              let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size > 0, Int64(size) <= maximumPackageSize else {
            throw ValidationError.invalidPackage
        }
        do {
            try validateZip(fileURL: fileURL, size: UInt64(size))
        } catch {
            throw ValidationError.invalidPackage
        }
    }

    private static func uint16(_ data: Data, _ index: Int) -> UInt16 {
        UInt16(data[index]) | UInt16(data[index + 1]) << 8
    }

    private static func uint32(_ data: Data, _ index: Int) -> UInt32 {
        UInt32(uint16(data, index)) | UInt32(uint16(data, index + 2)) << 16
    }

    private static func validateZip(fileURL: URL, size: UInt64) throws {
        let fh = try FileHandle(forReadingFrom: fileURL)
        defer { fh.closeFile() }

        // EOCD is the last 22 bytes plus up to 65,535 bytes of ZIP comment.
        let tailSize = Int(min(size, 65_557))
        try fh.seek(toOffset: size - UInt64(tailSize))
        let tail = fh.readData(ofLength: tailSize)
        guard tail.count == tailSize, tailSize >= 22 else { throw ValidationError.invalidPackage }

        var endRecord: Int?
        for offset in stride(from: tail.count - 22, through: 0, by: -1) {
            guard uint32(tail, offset) == 0x06054b50 else { continue }
            let commentSize = Int(uint16(tail, offset + 20))
            if offset + 22 + commentSize == tail.count {
                endRecord = offset
                break
            }
        }
        guard let endRecord,
              uint16(tail, endRecord + 4) == 0,
              uint16(tail, endRecord + 6) == 0,
              uint16(tail, endRecord + 8) == uint16(tail, endRecord + 10) else {
            throw ValidationError.invalidPackage
        }
        let totalEntries = Int(uint16(tail, endRecord + 10))
        let directorySize = Int(uint32(tail, endRecord + 12))
        let directoryOffset = UInt64(uint32(tail, endRecord + 16))
        guard totalEntries > 0, totalEntries <= maximumEntries,
              directorySize > 0, directorySize <= maximumDirectorySize,
              directoryOffset + UInt64(directorySize) <= size - UInt64(tailSize) + UInt64(endRecord) else {
            throw ValidationError.invalidPackage
        }

        try fh.seek(toOffset: directoryOffset)
        let directory = fh.readData(ofLength: directorySize)
        guard directory.count == directorySize else { throw ValidationError.invalidPackage }
        var cursor = 0
        var totalUnpacked: UInt64 = 0
        var foundManifest = false
        for _ in 0..<totalEntries {
            guard cursor + 46 <= directory.count,
                  uint32(directory, cursor) == 0x02014b50 else {
                throw ValidationError.invalidPackage
            }
            let flags = uint16(directory, cursor + 8)
            let method = uint16(directory, cursor + 10)
            let compressed = uint32(directory, cursor + 20)
            let unpacked = uint32(directory, cursor + 24)
            let nameLength = Int(uint16(directory, cursor + 28))
            let extraLength = Int(uint16(directory, cursor + 30))
            let commentLength = Int(uint16(directory, cursor + 32))
            let localOffset = UInt64(uint32(directory, cursor + 42))
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard flags & 0x1 == 0, method == 0 || method == 8,
                  compressed != UInt32.max, unpacked != UInt32.max,
                  nameLength > 0, next <= directory.count, localOffset < directoryOffset,
                  let name = String(data: directory[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8),
                  !name.hasPrefix("/"), !name.contains("\\"),
                  !name.unicodeScalars.contains(where: { $0.value < 0x20 }),
                  !name.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
                throw ValidationError.invalidPackage
            }
            totalUnpacked += UInt64(unpacked)
            guard totalUnpacked <= maximumUnpackedSize else { throw ValidationError.invalidPackage }
            if name == "manifest.json" { foundManifest = true }
            cursor = next
        }
        guard cursor == directory.count, foundManifest else { throw ValidationError.invalidPackage }
    }
}
