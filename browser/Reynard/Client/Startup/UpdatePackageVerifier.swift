//
//  UpdatePackageVerifier.swift
//  Reynard
//
//  Created by OpenAI Codex on 30/8/26.
//

import CryptoKit
import Foundation

enum UpdatePackageVerificationError: LocalizedError {
    case invalidSize
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidSize:
            return NSLocalizedString("The downloaded update has an unexpected file size.", comment: "")
        case .checksumMismatch:
            return NSLocalizedString("The downloaded update failed SHA-256 verification.", comment: "")
        }
    }
}

enum UpdatePackageVerifier {
    static func verify(fileURL: URL, expectedSize: Int64, expectedSHA256: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.int64Value == expectedSize else {
            throw UpdatePackageVerificationError.invalidSize
        }

        guard try sha256(fileURL: fileURL) == expectedSHA256.lowercased() else {
            throw UpdatePackageVerificationError.checksumMismatch
        }
    }

    private static func sha256(fileURL: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { fileHandle.closeFile() }

        var hasher = SHA256()
        while true {
            let data = fileHandle.readData(ofLength: 1024 * 1024)
            guard !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
