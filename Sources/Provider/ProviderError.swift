//
//  ProviderError.swift
//  Networker
//
//  Created by Twig on 5/16/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Networking
import Persister

/// Possible errors encountered while attempting to provide items.
public enum ProviderError: Error {
    
    public struct PartialRetrievalPersistenceError {
        let key: String
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
    
    /// There was no strong reference kept to the `Provider`.
    case noStrongReferenceToProvider
    
    
    case partialRetrieval(retrievedItems: [Providable], persistenceErrors: [PartialRetrievalPersistenceError], networkError: NetworkError)
}
