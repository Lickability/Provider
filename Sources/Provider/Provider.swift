//
//  Provider.swift
//  Networker
//
//  Created by Twig on 5/6/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation
import Combine
import Networking
import Persister

/// Represents the type of an instance that can be retrieved by a `Provider`.
public typealias Providable = Codable & Identifiable & Sendable

/// Describes a type that can retrieve items from persistence or networking and store them in persistence.
public protocol Provider: Sendable {
    
    /// Attempts to retrieve an item using the provided request, checking persistence first where possible and falling back to the network. If the network is used, the item will be persisted upon success. If `allowExpiredItem` is true, and an expired item exists, the `itemHandler` will first be called with the expired item, and then called again with the result of the network request.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the item from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the item wasn’t successfully retrieved from persistence.
    ///   - handlerQueue: The queue on which to call the `itemHandler`.
    ///   - allowExpiredItem: Allows the provider to return an expired item from the cache. If an expired item is returned, the completion will be called for both the expired item, and the item retrieved from the network when available.
    ///   - itemHandler: The closure called upon completing the request that provides the desired item or the error that occurred when attempting to retrieve it.
    /// - Returns: Returns a `AnyCancellable` that lets you cancel the request.
    @discardableResult func provide<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], handlerQueue: DispatchQueue, allowExpiredItem: Bool, itemHandler: @escaping (Result<Item, ProviderError>) -> Void) -> AnyCancellable?
    
    /// Attempts to retrieve an array of items using the provided request, checking persistence first where possible and falling back to the network. If the network is used, the items will be persisted upon success. If `allowExpiredItems` is true, and the expired items exist, the `itemHandler` will first be called with the expired items, and then called again with the result of the network request.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the items from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into an array of the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the items weren’t successfully retrieved from persistence.
    ///   - handlerQueue: The queue on which to call the `itemsHandler`.
    ///   - allowExpiredItems: Allows the provider to return expired items from the cache. If expired items are returned, the completion will be called for both the expired items, and the items retrieved from the network when available.
    ///   - itemsHandler: The closure called upon completing the request that provides the desired items or the error that occurred when attempting to retrieve them.
    /// - Returns: Returns a `AnyCancellable` that lets you cancel the request.
    @discardableResult func provideItems<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], handlerQueue: DispatchQueue, allowExpiredItems: Bool, itemsHandler: @escaping (Result<[Item], ProviderError>) -> Void) -> AnyCancellable?
    
    /// Produces a publisher which, when subscribed to, attempts to retrieve an item using the provided request, checking persistence first where possible and falling back to the network. If the network is used, the item will be persisted upon success.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the items from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into an array of the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the items weren’t successfully retrieved from persistence.
    ///   - allowExpiredItem: Allows the publisher to publish an expired item from the cache. If an expired item is published, this publisher will then also publish an up to date item from the network when it is available.
    func provide<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], allowExpiredItem: Bool) -> AnyPublisher<Item, ProviderError>
    
    /// Produces a publisher which, when subscribed to, attempts to retrieve an array of items using the provided request, checking persistence first where possible and falling back to the network. If the network is used, the items will be persisted upon success.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the items from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into an array of the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the items weren’t successfully retrieved from persistence.
    ///   - allowExpiredItems: Allows the publisher to publish expired items from the cache. If expired items are published, this publisher will then also publish up to date results from the network when they are available.
    func provideItems<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], allowExpiredItems: Bool) -> AnyPublisher<[Item], ProviderError>
    
    /// Returns a stream of a single item.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the items from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into an array of the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the items weren’t successfully retrieved from persistence.
    ///   - allowExpiredItem: Allows the provider to return an expired item from the cache. If an expired item is returned, the completion will be called for both the expired item, and the item retrieved from the network when available.
    /// - Returns: An async steam which emits an item or an error.
    func asyncProvide<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], allowExpiredItem: Bool) async -> AsyncStream<Result<Item, ProviderError>>
    
    /// Returns a stream of items.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the items from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into an array of the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the items weren’t successfully retrieved from persistence.
    ///   - allowExpiredItem: Allows the provider to return an expired item from the cache. If an expired item is returned, the completion will be called for both the expired item, and the item retrieved from the network when available.
    /// - Returns: An async steam which emits a collection of items or an error.
    func asyncProvideItems<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], allowExpiredItems: Bool) async -> AsyncStream<Result<[Item], ProviderError>>
}
