//
//  Storage.swift
//  Shared
//
//  Created by Vitalii Malakhovskyi on 7/25/19.
//  Copyright © 2019 Vitalii Malakhovskyi. All rights reserved.
//

import Foundation
import SwiftyMock

// MARK: - Protocol

public protocol Storage {
    func fetch(from url: URL) -> Result<Data, Error>
    func store(data: Data, to url: URL) -> Result<Void, Error>
}

// MARK: - Implementation

final private class StorageImpl: Storage {
    private let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("downloads")
    
    struct CannotConstructLocalPath: Error {
        let triedWith: URL
    }
    
    private func constructLocalPath(from url: URL) -> URL? {
        return url.pathComponents.last.map(root.appendingPathComponent)
    }
    
    func fetch(from url: URL) -> Result<Data, Error> {
        guard let path = constructLocalPath(from: url) else { return .failure(CannotConstructLocalPath(triedWith: url)) }
        return Result { try Data(contentsOf: path) }
    }
    
    func store(data: Data, to url: URL) -> Result<Void, Error> {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
            guard let path = constructLocalPath(from: url) else { return .failure(CannotConstructLocalPath(triedWith: url)) }
            try data.write(to: path)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Factory

public struct StorageFactory {
    public static func new() -> Storage {
        return StorageImpl()
    }
}

// MARK: - Mock

public final class MockStorage: Storage {
    public init() {}
    
    public let fetchCall = FunctionCall<URL, Result<Data, Error>>()
    public func fetch(from url: URL) -> Result<Data, Error> {
        return stubCall(fetchCall, argument: url, defaultValue: .failure(NSError.dummy))
    }
    
    public let storeCall = FunctionCall<(Data, URL), Result<Void, Error>>()
    public func store(data: Data, to url: URL) -> Result<Void, Error> {
        return stubCall(storeCall, argument: (data, url), defaultValue: .failure(NSError.dummy))
    }
}
