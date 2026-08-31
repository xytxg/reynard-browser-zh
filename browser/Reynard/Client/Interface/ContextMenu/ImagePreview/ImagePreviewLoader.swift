//
//  ImagePreviewLoader.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

struct ImagePreviewLoader {
    private static let maximumSourceDataSize = 20 * 1024 * 1024
    private static let maximumDataURLLength = 28 * 1024 * 1024
    private static let maximumPreviewPixelSize = 2048

    static func image(from url: URL) async -> UIImage? {
        if url.isFileURL {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ),
            values.isRegularFile == true,
            let fileSize = values.fileSize,
            fileSize >= 0,
            fileSize <= maximumSourceDataSize,
            let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                return nil
            }
            return decodedPreview(from: data)
        }

        if url.scheme?.lowercased() == "data" {
            return imageFromDataURL(url.absoluteString)
        }

        guard URLUtils.isWebURL(url) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let loader = BoundedURLDataLoader(
                maximumByteCount: maximumSourceDataSize,
                responseValidator: { response in
                    guard response.statusCode == 200,
                          let finalURL = response.url else {
                        return false
                    }
                    return URLUtils.isWebURL(finalURL)
                },
                completion: { result in
                    continuation.resume(returning: try? decodedPreview(from: result.get().data))
                }
            )
            loader.start(with: URLRequest(url: url))
        }
    }

    private static func imageFromDataURL(_ value: String) -> UIImage? {
        guard value.utf8.count <= maximumDataURLLength,
              let commaIndex = value.firstIndex(of: ",") else {
            return nil
        }
        
        let payload = value[value.index(after: commaIndex)...]
        let data: Data?
        if value[..<commaIndex].lowercased().contains(";base64") {
            data = Data(base64Encoded: String(payload))
        } else {
            data = String(payload).removingPercentEncoding?.data(using: .utf8)
        }
        
        guard let data,
              data.count <= maximumSourceDataSize else {
            return nil
        }
        return decodedPreview(from: data)
    }

    private static func decodedPreview(from data: Data) -> UIImage? {
        guard let prepared = ImageUtils.prepareJPEGImage(
            from: data,
            maximumPixelSize: maximumPreviewPixelSize
        ) else {
            return nil
        }
        return UIImage(data: prepared.data)
    }
}
