//
//  BoundedZipArchive.swift
//  Reynard
//
//  reynard-browser-zh: limits for reading untrusted ZIP files through
//  ZIPFoundation. Upstream replaced the hand-written ZipArchiveReader with
//  ZIPFoundation; ZIPFoundation itself does not cap entry counts or the
//  amount of data a deflate stream may produce, so every caller that reads
//  an untrusted archive goes through these checks.
//

import Foundation
import ZIPFoundation

nonisolated enum BoundedZipArchive {
    nonisolated struct Limits: Sendable {
        /// Largest archive file accepted, in bytes.
        let maximumArchiveSize: UInt64
        /// Largest number of central directory entries accepted.
        let maximumEntryCount: Int
        /// Largest uncompressed size of a single entry that is read.
        let maximumEntrySize: UInt64
        /// Largest total uncompressed size of all entries that are read.
        let maximumTotalSize: UInt64
    }

    nonisolated enum Failure: Error, Sendable {
        case invalidArchive
        case limitExceeded
        case invalidEntry(String)
    }

    /// Add-on (XPI) icons: the same limits the fork's former ZipArchiveReader used.
    static let addonIconLimits = Limits(
        maximumArchiveSize: 128 * 1024 * 1024,
        maximumEntryCount: 4096,
        maximumEntrySize: 8 * 1024 * 1024,
        maximumTotalSize: 8 * 1024 * 1024
    )

    /// Opens a regular local file as a read-only archive after checking its size.
    static func open(_ url: URL, limits: Limits) throws -> Archive {
        guard url.isFileURL, !url.path.contains("\0"),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0 else {
            throw Failure.invalidArchive
        }
        guard UInt64(fileSize) <= limits.maximumArchiveSize else {
            throw Failure.limitExceeded
        }
        do {
            return try Archive(url: url, accessMode: .read)
        } catch {
            throw Failure.invalidArchive
        }
    }

    /// Lists the archive entries, refusing archives with too many entries.
    static func entries(
        of archive: Archive,
        limits: Limits,
        checkCancellation: () throws -> Void = {}
    ) throws -> [Entry] {
        var entries: [Entry] = []
        for entry in archive {
            try checkCancellation()
            guard entries.count < limits.maximumEntryCount else {
                throw Failure.limitExceeded
            }
            entries.append(entry)
        }
        return entries
    }

    /// Returns the first regular file entry with exactly this path, after the
    /// entry count limit has been checked.
    static func fileEntry(at path: String, in archive: Archive, limits: Limits) throws -> Entry? {
        guard isSafeEntryPath(path) else {
            return nil
        }
        return try entries(of: archive, limits: limits).first {
            $0.type == .file && $0.path == path
        }
    }

    /// Relative path without absolute prefixes, backslashes, control
    /// characters or `..` components.
    static func isSafeEntryPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    /// Streams one file entry to `consumer`, enforcing the declared size, the
    /// per-entry limit, the remaining total budget and the CRC-32 checksum.
    /// `totalSize` is increased by the bytes produced.
    @discardableResult
    static func extract(
        _ entry: Entry,
        from archive: Archive,
        limits: Limits,
        totalSize: inout UInt64,
        validatePath: Bool = true,
        checkCancellation: () throws -> Void = {},
        consumer: (Data) throws -> Void
    ) throws -> UInt64 {
        guard entry.type == .file, !validatePath || isSafeEntryPath(entry.path) else {
            throw Failure.invalidEntry(entry.path)
        }
        let declaredSize = entry.uncompressedSize
        guard declaredSize <= limits.maximumEntrySize,
              totalSize <= limits.maximumTotalSize,
              declaredSize <= limits.maximumTotalSize - totalSize else {
            throw Failure.limitExceeded
        }

        var produced: UInt64 = 0
        let checksum: CRC32
        do {
            checksum = try archive.extract(entry, skipCRC32: false) { chunk in
                try checkCancellation()
                let count = UInt64(chunk.count)
                // A deflate stream can expand beyond the size stored in the
                // central directory; stop as soon as it does.
                guard count <= declaredSize - produced else {
                    throw Failure.invalidEntry(entry.path)
                }
                produced += count
                try consumer(chunk)
            }
        } catch let failure as Failure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.invalidEntry(entry.path)
        }

        guard produced == declaredSize, checksum == entry.checksum else {
            throw Failure.invalidEntry(entry.path)
        }
        totalSize += produced
        return produced
    }

    /// Reads one small file entry into memory.
    static func data(of entry: Entry, from archive: Archive, limits: Limits) throws -> Data {
        var total: UInt64 = 0
        var data = Data()
        data.reserveCapacity(Int(min(entry.uncompressedSize, limits.maximumEntrySize)))
        try extract(entry, from: archive, limits: limits, totalSize: &total) { data.append($0) }
        return data
    }
}
