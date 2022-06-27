//
//  Decodable+Error.swift
//  Provider
//
//  Created by Daisy Ramos on 6/27/22.
//  Copyright © 2022 Lickability. All rights reserved.
//

import Foundation

/// Extends `DecodingError` to log underlying issues found with mismatched types or keys.
extension DecodingError {

    /// An error log for mapping decodable errors.
    var errorLog: String {
        switch self {
        case let .keyNotFound(key, context):
            let key = "Key '\(key)' not found: \(context.debugDescription)"
            let codingPath = "codingPath: \(context.codingPath)"
            return key.appending(codingPath)
        case let .valueNotFound(value, context):
            let value = "Value '\(value)' not found: \(context.debugDescription)"
            let codingPath = "codingPath: \(context.codingPath)"
            return value.appending(codingPath)
        case let .typeMismatch(type, context):
            let type = "Type '\(type)' mismatch: \(context.debugDescription)"
            let codingPath = "codingPath: \(context.codingPath)"
            return type.appending(codingPath)
        case let .dataCorrupted(context):
            return "data corrupted: \(context.debugDescription)"
        @unknown default: return "Unknown error encountered"
        }
    }
}
