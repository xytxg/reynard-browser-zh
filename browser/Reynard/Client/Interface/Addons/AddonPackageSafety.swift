//
//  AddonPackageSafety.swift
//  Reynard
//
//  Created by OpenAI Codex on 30/8/26.
//

import Foundation

enum AddonPackageSafety {
    private static let maximumPackageSize = 128 * 1024 * 1024
    private static let zipSignatures: Set<[UInt8]> = [
        [0x50, 0x4B, 0x03, 0x04],
        [0x50, 0x4B, 0x05, 0x06],
        [0x50, 0x4B, 0x07, 0x08],
    ]

    enum ValidationError: LocalizedError {
        case invalidPackage

        var errorDescription: String? {
            return NSLocalizedString(
                "The selected add-on package is invalid or too large.",
                comment: ""
            )
        }
    }

    static func validate(fileURL: URL) throws {
        guard fileURL.isFileURL,
              let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
              ),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumPackageSize,
              let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            throw ValidationError.invalidPackage
        }
        defer { fileHandle.closeFile() }

        let signature = [UInt8](fileHandle.readData(ofLength: 4))
        guard zipSignatures.contains(signature) else {
            throw ValidationError.invalidPackage
        }
    }
}
