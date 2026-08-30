//
//  BoundedURLDataLoader.swift
//  Reynard
//
//  Created by OpenAI Codex on 30/8/26.
//

import Foundation

/// Loads small, untrusted HTTP responses without allowing URLSession to buffer an
/// arbitrarily large body in memory. Each instance owns an ephemeral session and
/// is retained by that session until the request completes or is cancelled.
final class BoundedURLDataLoader: NSObject {
    struct LoadedResponse {
        let data: Data
        let response: HTTPURLResponse
    }

    enum LoaderError: Error, Equatable {
        case invalidResponse
        case responseTooLarge
        case emptyResponse
    }

    typealias ResponseValidator = (HTTPURLResponse) -> Bool
    typealias Completion = (Result<LoadedResponse, Error>) -> Void

    private let maximumByteCount: Int
    private let responseValidator: ResponseValidator
    private var completion: Completion?
    private var receivedData = Data()
    private var acceptedResponse: HTTPURLResponse?
    private var session: URLSession?
    private var task: URLSessionDataTask?

    init(
        maximumByteCount: Int,
        timeoutIntervalForRequest: TimeInterval = 15,
        timeoutIntervalForResource: TimeInterval = 30,
        responseValidator: @escaping ResponseValidator,
        completion: @escaping Completion
    ) {
        precondition(maximumByteCount > 0)
        self.maximumByteCount = maximumByteCount
        self.responseValidator = responseValidator
        self.completion = completion
        super.init()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.timeoutIntervalForResource = timeoutIntervalForResource
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    @discardableResult
    func start(with request: URLRequest) -> Self {
        guard task == nil, completion != nil else {
            return self
        }
        task = session?.dataTask(with: request)
        task?.resume()
        return self
    }

    func cancel() {
        task?.cancel()
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let completion else {
            return
        }
        self.completion = nil
        task = nil
        receivedData.removeAll(keepingCapacity: false)
        acceptedResponse = nil
        session?.finishTasksAndInvalidate()
        session = nil
        completion(result)
    }
}

extension BoundedURLDataLoader: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse,
              responseValidator(httpResponse) else {
            completionHandler(.cancel)
            finish(.failure(LoaderError.invalidResponse))
            return
        }

        let expectedLength = httpResponse.expectedContentLength
        guard expectedLength < 0 || expectedLength <= Int64(maximumByteCount) else {
            completionHandler(.cancel)
            finish(.failure(LoaderError.responseTooLarge))
            return
        }

        if expectedLength > 0 {
            receivedData.reserveCapacity(Int(expectedLength))
        }
        acceptedResponse = httpResponse
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard data.count <= maximumByteCount - receivedData.count else {
            dataTask.cancel()
            finish(.failure(LoaderError.responseTooLarge))
            return
        }
        receivedData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else if receivedData.isEmpty {
            finish(.failure(LoaderError.emptyResponse))
        } else if let acceptedResponse {
            finish(.success(LoadedResponse(data: receivedData, response: acceptedResponse)))
        } else {
            finish(.failure(LoaderError.invalidResponse))
        }
    }
}
