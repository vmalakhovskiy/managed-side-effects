//
//  Downloader.swift
//  Shared
//
//  Created by Vitalii Malakhovskyi on 7/25/19.
//  Copyright © 2019 Vitalii Malakhovskyi. All rights reserved.
//

import Foundation
import SwiftyMock

// MARK: - Protocol

public protocol Downloader {
    func download(from url: URL, completion: @escaping (Result<Data, Error>) -> ())
}

// MARK: - Implementation

final private class DownloaderImpl: Downloader {
    let session = URLSession(configuration: .default)
    
    func download(from url: URL, completion: @escaping (Result<Data, Error>) -> ()) {
        let task = session.dataTask(with: url) { (data, _, error) in
            switch (data, error) {
            case (.none, let error?):
                completion(.failure(error))
                
            case (let data?, .none):
                completion(.success(data))
                
            default:
                struct UndefinedResponse: Error {}
                completion(.failure(UndefinedResponse()))
            }
        }
        task.resume()
    }
}

// MARK: - Factory

public struct DownloaderFactory {
    public static func new() -> Downloader {
        return DownloaderImpl()
    }
}

// MARK: - Mock

public final class MockDownloader: Downloader {
    public init() {}
    
    public let downloadCall = FunctionCall<(URL, (Result<Data, Error>) -> ()), Void>()
    public func download(from url: URL, completion: @escaping (Result<Data, Error>) -> ()) {
        return stubCall(downloadCall, argument: (url, completion), defaultValue: ())
    }
}
