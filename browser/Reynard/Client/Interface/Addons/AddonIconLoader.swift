//
//  AddonIconLoader.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import ImageIO
import UIKit
import ZIPFoundation

enum AddonIconLoader {
    private static let maximumIconDataSize = 8 * 1024 * 1024
    private static let maximumSVGDataSize = 2 * 1024 * 1024

    static func loadImage(from iconURLString: String?, targetSize: CGSize) -> UIImage? {
        guard targetSize.width > 0,
              targetSize.height > 0,
              targetSize.width <= 2048,
              targetSize.height <= 2048,
              let iconURLString,
              let url = URL(string: iconURLString),
              let data = loadData(from: url) else {
            return nil
        }
        
        if iconURLString.lowercased().hasSuffix(".svg") {
            guard data.count <= maximumSVGDataSize else {
                return nil
            }
            return SVGIconRenderer.render(data: data, size: targetSize)
        }
        
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                imageSource,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(
                        ceil(max(targetSize.width, targetSize.height) * 3)
                    ),
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
              ) else {
            return nil
        }
        return resizedImage(from: UIImage(cgImage: cgImage), targetSize: targetSize)
    }
    
    private static func loadData(from url: URL) -> Data? {
        switch url.scheme?.lowercased() {
        case "file":
            return localFileData(from: url, maximumSize: maximumIconDataSize)
        case "jar":
            return jarEntryData(from: url)
        default:
            return nil
        }
    }
    
    private static func jarEntryData(from url: URL) -> Data? {
        let absoluteString = url.absoluteString
        guard absoluteString.hasPrefix("jar:") else {
            return nil
        }
        
        let jarString = String(absoluteString.dropFirst(4))
        let components = jarString.components(separatedBy: "!/")
        guard components.count == 2,
              let archiveURL = URL(string: components[0]),
              archiveURL.isFileURL,
              let archive = try? BoundedZipArchive.open(
                archiveURL,
                limits: BoundedZipArchive.addonIconLimits
              ),
              let entry = try? BoundedZipArchive.fileEntry(
                at: components[1],
                in: archive,
                limits: BoundedZipArchive.addonIconLimits
              ) else {
            return nil
        }

        // Size, inflation and CRC-32 limits are enforced while streaming.
        return try? BoundedZipArchive.data(
            of: entry,
            from: archive,
            limits: BoundedZipArchive.addonIconLimits
        )
    }

    private static func localFileData(from url: URL, maximumSize: Int) -> Data? {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= maximumSize else {
            return nil
        }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }
    
    private static func resizedImage(from image: UIImage, targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
