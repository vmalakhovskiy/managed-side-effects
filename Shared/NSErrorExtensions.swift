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
