//
//  SearchCompletion.swift
//  Reynard
//
//  Created by Minh Ton on 11/6/26.
//

import Foundation

final class SearchCompletion {
    private static let maximumResponseSize = 512 * 1024
    private static let maximumQueryLength = 256
    private static let maximumSuggestionLength = 256
    private static let maximumSuggestionCount = 20

    enum Provider: String, CaseIterable {
        case google
        case yahoo
        case bing
        case duckduckgo
        case ecosia
        case startpage
    }
    
    let provider: Provider
    
    init(provider: Provider = .google) {
        self.provider = provider
    }
    
    func fetchCompletions(
        for query: String,
        completion: @escaping ([String]) -> Void
    ) -> BoundedURLDataLoader? {
        let boundedQuery = String(query.prefix(Self.maximumQueryLength))
        guard let url = provider.url(for: boundedQuery),
              let expectedHost = url.host?.lowercased() else {
            completion([])
            return nil
        }
        
        let task = BoundedURLDataLoader(
            maximumByteCount: Self.maximumResponseSize,
            timeoutIntervalForRequest: 8,
            timeoutIntervalForResource: 12,
            responseValidator: { response in
                guard (200...299).contains(response.statusCode),
                      let finalURL = response.url else {
                    return false
                }
                return finalURL.scheme?.lowercased() == "https" &&
                finalURL.host?.lowercased() == expectedHost
            },
            completion: { result in
                guard let loadedResponse = try? result.get() else {
                    if case .failure(let error) = result {
                        let nsError = error as NSError
                        if nsError.domain == NSURLErrorDomain,
                           nsError.code == NSURLErrorCancelled {
                            return
                        }
                    }
                    completion([])
                    return
                }

                completion(Self.parse(
                    data: loadedResponse.data,
                    response: loadedResponse.response
                ))
            }
        )
        task.start(with: URLRequest(url: url))
        return task
    }
}

extension SearchCompletion.Provider {
    var name: String {
        switch self {
        case .google: return "Google"
        case .yahoo: return "Yahoo"
        case .bing: return "Bing"
        case .duckduckgo: return "DuckDuckGo"
        case .ecosia: return "Ecosia"
        case .startpage: return "Startpage"
        }
    }
}

private extension SearchCompletion.Provider {
    func url(for query: String) -> URL? {
        let endpoint: String
        let queryItems: [URLQueryItem]
        switch self {
        case .google:
            endpoint = "https://www.google.com/complete/search"
            queryItems = [
                URLQueryItem(name: "client", value: "firefox"),
                URLQueryItem(name: "q", value: query),
            ]
        case .yahoo:
            endpoint = "https://search.yahoo.com/sugg/chrome"
            queryItems = [
                URLQueryItem(name: "output", value: "fxjson"),
                URLQueryItem(name: "command", value: query),
            ]
        case .bing:
            endpoint = "https://api.bing.com/osjson.aspx"
            queryItems = [URLQueryItem(name: "query", value: query)]
        case .duckduckgo:
            endpoint = "https://duckduckgo.com/ac/"
            queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "list"),
            ]
        case .ecosia:
            endpoint = "https://ac.ecosia.org/autocomplete"
            queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "list"),
            ]
        case .startpage:
            endpoint = "https://www.startpage.com/osuggestions"
            queryItems = [URLQueryItem(name: "q", value: query)]
        }
        
        var components = URLComponents(string: endpoint)
        components?.queryItems = queryItems
        return components?.url
    }
}

private extension SearchCompletion {
    static func parse(data: Data?, response: URLResponse?) -> [String] {
        guard let data,
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let payload = decodePayload(data: data, response: response),
              payload.count > 1,
              let suggestions = payload[1] as? [Any] else {
            return []
        }
        
        return suggestions.prefix(maximumSuggestionCount).compactMap { value in
            guard let suggestion = value as? String else {
                return nil
            }
            
            let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return String(trimmed.prefix(maximumSuggestionLength))
        }
    }
    
    static func decodePayload(data: Data, response: URLResponse) -> [Any]? {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return payload
        }
        
        guard let encodingName = response.textEncodingName,
              let encoding = String.Encoding.ianaCharacterSetName(encodingName),
              let text = String(data: data, encoding: encoding),
              let utf8Data = text.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONSerialization.jsonObject(with: utf8Data) as? [Any]
    }
}
