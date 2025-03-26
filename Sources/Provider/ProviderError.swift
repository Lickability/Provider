//
//  ProviderError.swift
//  Networker
//
//  Created by Twig on 5/16/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation
import Networking
import Persister

/// Possible errors encountered while attempting to provide items.
public indirect enum ProviderError: LocalizedError, Sendable {
    
    // MARK: - ProviderError
    
    /// A struct that represents a failure when retrieving an individual item during a request for multiple items.
    public struct PartialRetrievalFailure: Sendable {
        
        /// They key for the item that failed to be retrieved.
        let key: String
        
        /// The error that occurred when attempting to retrieve the item from persistence.
        let persistenceError: PersistenceError
    }

    /// An underlying networking error occurred.
    /// - Parameter error: The error that occurred with the network request.
    case networkError(_ error: NetworkError)
    
    /// An underlying persistence error occurred.
    /// - Parameter error: The error that occurred while performing cache read/write operations.
    case persistenceError(_ error: PersistenceError)
    
    /// An underlying decoding error occurred.
    /// - Parameter error: The error that occurred while decoding.
    case decodingError(_ error: Error)
    
    /// A request to retrieve multiple items ended in failure. This error provides a partial response in the event that we were able to retrieve some of the requested items from the cache.
    /// - Parameters:
    ///   - retrievedItems: A list of items that were able to be retrieved, that represent a partial list of the requested items.
    ///   - persistenceFailures: The errors that occurred while attempting to retrieve items from persistence.
    ///   - providerError: The error that occurred when trying to retrieve the complete list of items from the network.
    case partialRetrieval(retrievedItems: [Providable], persistenceFailures: [PartialRetrievalFailure], providerError: ProviderError)
    
    // MARK: - LocalizedError
    
    public var errorDescription: String? {
        switch self {
        case let .networkError(error):
            return error.errorDescription
        case let .persistenceError(error):
            return error.errorDescription
        case .decodingError:
            return NSLocalizedString("Network Error Occurred", comment: "The title of an error alert shown when there is no valid data or no response from the server.")
        case let .partialRetrieval(_, _, providerError):
            return providerError.errorDescription
        }
    }
    
    public var failureReason: String? {
        switch self {
        case let .networkError(error):
            return error.failureReason
        case let .persistenceError(error):
            return error.failureReason
        case .decodingError:
            return NSLocalizedString("The server’s data was not able to be read.", comment: "A failure reason for an error during decoding.")
        case let .partialRetrieval(_, _, providerError):
            return providerError.failureReason
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case let .networkError(error):
            return error.recoverySuggestion
        case let .persistenceError(error):
            return error.recoverySuggestion
        case .decodingError:
            return nil
        case let .partialRetrieval(_, _, providerError):
            return providerError.recoverySuggestion
        }
    }
}
