//
//  UserDataMigration.swift
//  Reynard
//
//  Created by Minh Ton on 17/5/26.
//

import Foundation

final class UserDataMigration {
    static let shared = UserDataMigration()
    
    private let fileManager: FileManager
    private let documentsDirectoryURL: URL
    private let applicationSupportDirectoryURL: URL
    
    private var documentsAppDataDirectoryURL: URL {
        documentsDirectoryURL.appendingPathComponent("AppData", isDirectory: true)
    }
    
    private var documentsDDIDirectoryURL: URL {
        documentsDirectoryURL.appendingPathComponent("DDI", isDirectory: true)
    }
    
    private var applicationSupportAppDataDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("AppData", isDirectory: true)
    }
    
    private var applicationSupportDDIDirectoryURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent("DDI", isDirectory: true)
    }
    
    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let documentsDirectoryURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            self.documentsDirectoryURL = documentsDirectoryURL
        } else {
            NSLog("UserDataMigration: Documents directory is unavailable; legacy migration will be skipped")
            self.documentsDirectoryURL = fileManager.temporaryDirectory
                .appendingPathComponent("ReynardRecovery/Documents", isDirectory: true)
        }

        if let applicationSupportDirectoryURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        } else {
            NSLog("UserDataMigration: Application Support is unavailable; using temporary recovery storage")
            self.applicationSupportDirectoryURL = fileManager.temporaryDirectory
                .appendingPathComponent("ReynardRecovery/ApplicationSupport", isDirectory: true)
        }
    }
    
    func run() {
        migrateAppDataToApplicationSupport()
        migrateDDIToApplicationSupport()
        removeLegacyUserAgentOverride()
    }
    
    // MARK: - Store Migration (0.4.0)
    private func migrateAppDataToApplicationSupport() {
        let sourceURL = documentsAppDataDirectoryURL
        let destinationURL = applicationSupportAppDataDirectoryURL
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }
        
        do {
            try removeLegacyStoreFolders(in: sourceURL)
            try fileManager.createDirectory(at: applicationSupportDirectoryURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try mergeDirectoryContents(from: sourceURL, into: destinationURL)
            } else {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
        } catch {
            NSLog("UserDataMigration: AppData migration failed: %@", error.localizedDescription)
            return
        }

        if fileManager.fileExists(atPath: sourceURL.path) {
            NSLog("UserDataMigration: legacy AppData remains after migration")
        }
    }
    
    private func migrateDDIToApplicationSupport() {
        let sourceURL = documentsDDIDirectoryURL
        let destinationURL = applicationSupportDDIDirectoryURL
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }
        
        do {
            try fileManager.createDirectory(at: applicationSupportDirectoryURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try mergeDirectoryContents(from: sourceURL, into: destinationURL)
            } else {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
        } catch {
            NSLog("UserDataMigration: DDI migration failed: %@", error.localizedDescription)
            return
        }

        if fileManager.fileExists(atPath: sourceURL.path) {
            NSLog("UserDataMigration: legacy DDI remains after migration")
        }
    }
    
    private func removeLegacyUserAgentOverride() {
        try? fileManager.removeItem(
            at: documentsDirectoryURL.appendingPathComponent("ua-override.json", isDirectory: false)
        )
    }
    
    private func removeLegacyStoreFolders(in appDataDirectoryURL: URL) throws {
        for folderName in ["TabManagement", "Favicons"] {
            let folderURL = appDataDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
            if fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.removeItem(at: folderURL)
            }
        }
    }

    private func mergeDirectoryContents(from sourceURL: URL, into destinationURL: URL) throws {
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let sourceItems = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        for sourceItemURL in sourceItems {
            let destinationItemURL = destinationURL.appendingPathComponent(
                sourceItemURL.lastPathComponent,
                isDirectory: false
            )
            guard fileManager.fileExists(atPath: destinationItemURL.path) else {
                try fileManager.moveItem(at: sourceItemURL, to: destinationItemURL)
                continue
            }

            let sourceIsDirectory = try sourceItemURL.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory == true
            let destinationIsDirectory = try destinationItemURL.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory == true
            if sourceIsDirectory && destinationIsDirectory {
                try mergeDirectoryContents(from: sourceItemURL, into: destinationItemURL)
            } else {
                // Application Support is the active store. Remove only the stale
                // duplicate after confirming that an active destination exists.
                try fileManager.removeItem(at: sourceItemURL)
            }
        }

        if (try fileManager.contentsOfDirectory(atPath: sourceURL.path)).isEmpty {
            try fileManager.removeItem(at: sourceURL)
        }
    }
}
