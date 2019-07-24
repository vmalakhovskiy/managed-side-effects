//
//  Common.swift
//  Shared
//
//  Created by Vitalii Malakhovskyi on 7/23/19.
//  Copyright © 2019 Vitalii Malakhovskyi. All rights reserved.
//

import Foundation

public extension NSError {
    static var dummy: NSError {
        return NSError(domain: "", code: 0, userInfo: nil)
    }
}

public struct Request {
    public typealias Completion = (Result<Data, Error>) -> ()
    public typealias Cancel = () -> ()
    public let perform: (@escaping Completion) -> Cancel
}

extension Request {
    public static func download(url: URL) -> Request {
        return Request { completion in
            let task = URLSession(configuration: .default).dataTask(with: url) { (data, _, error) in
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
            return { task.cancel() }
        }
    }
}
