//
//  ProviderBehavior.swift
//  Networker
//
//  Created by Twig on 5/9/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation

/// Describes a type that can be used to implement behaviors for provider requests.
public protocol ProviderBehavior: Sendable {
    
    /// Called before a provider request is performed.
    /// - Parameter request: The request that will be made.
    func providerWillProvide(forRequest request: any ProviderRequest)
    
    /// Called when the provider request has completed and an item has been provided.
    /// - Parameters:
    ///   - item: The requested item.
    ///   - request: The request that was performed to retrieve the item.
    func providerDidProvide<Item: Codable>(item: Item, forRequest request: any ProviderRequest)
}

extension Array: ProviderBehavior where Element == ProviderBehavior {
    public func providerWillProvide(forRequest request: any ProviderRequest) {
        forEach { $0.providerWillProvide(forRequest: request) }
    }
    
    public func providerDidProvide<Item: Codable>(item: Item, forRequest request: any ProviderRequest) {
        forEach { $0.providerDidProvide(item: item, forRequest: request) }
    }
}
