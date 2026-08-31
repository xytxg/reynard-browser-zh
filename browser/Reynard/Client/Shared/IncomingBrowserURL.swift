//
//  IncomingBrowserURL.swift
//  Reynard
//
//  Created by OpenAI Codex on 29/8/26.
//

import Foundation

enum IncomingBrowserURL {
    nonisolated static func resolve(_ incomingURL: URL) -> URL? {
        if URLUtils.isWebURL(incomingURL) {
            return incomingURL
        }

        guard incomingURL.scheme?.lowercased() == "reynard",
              let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
              let wrappedValue = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let wrappedURL = URL(string: wrappedValue),
              URLUtils.isWebURL(wrappedURL) else {
            return nil
        }

        return wrappedURL
    }

    nonisolated static func firstResolvedURL(in incomingURLs: [URL]) -> URL? {
        return incomingURLs
            .compactMap(resolve)
            .sorted { $0.absoluteString < $1.absoluteString }
            .first
    }
}
