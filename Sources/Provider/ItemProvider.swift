//
//  ItemProvider.swift
//  Networker
//
//  Created by Twig on 5/10/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation
import Combine
import Networking
import Persister

/// Retrieves items from persistence or networking and stores them in persistence.
public final class ItemProvider: Sendable {
    
    /// The policy for how the provider checks the cache and/or the network for items.
    public enum FetchPolicy: Sendable {
        /// Only request from the network if we don't have items in the cache. If items exist in the cache and are expired, it returns items from the cache and the network.
        case returnFromCacheElseNetwork
        
        /// Return items from the cache, then request from the network for updated items.
        case returnFromCacheAndNetwork
    }
    
    private typealias CacheItemsResponse<T: Providable> = (itemContainers: [ItemContainer<T>], partialErrors: [ProviderError.PartialRetrievalFailure])
    
    /// Performs network requests when items cannot be retrieved from persistence.
    public let networkRequestPerformer: NetworkRequestPerformer
    
    /// The cache used to persist / recall previously retrieved items.
    public let cache: Cache?
    
    private let fetchPolicy: FetchPolicy
    private let defaultProviderBehaviors: [ProviderBehavior]
    
    private let lock = NSLock()
    nonisolated(unsafe) private var cancellables = Set<AnyCancellable?>()
    
    /// Creates a new `ItemProvider`.
    /// - Parameters:
    ///   - networkRequestPerformer: Performs network requests when items cannot be retrieved from persistence.
    ///   - cache: The cache used to persist / recall previously retrieved items.
    ///   - fetchPolicy: The policy for how the provider checks the cache and/or the network for items. Defaults to `.returnFromCacheElseNetwork`.
    ///   - defaultProviderBehaviors: Actions to perform before _every_ provider request is performed and / or after _every_ provider request is completed.
    public init(networkRequestPerformer: NetworkRequestPerformer, cache: Cache?, fetchPolicy: FetchPolicy = .returnFromCacheElseNetwork, defaultProviderBehaviors: [ProviderBehavior] = []) {
        self.networkRequestPerformer = networkRequestPerformer
        self.cache = cache
        self.fetchPolicy = fetchPolicy
        self.defaultProviderBehaviors = defaultProviderBehaviors
    }
    
    fileprivate func insertCancellable(cancellable: AnyCancellable?) {
        lock.lock()
        defer { lock.unlock() }
        
        cancellables.insert(cancellable)
    }
    
    fileprivate func removeCancellable(cancellable: AnyCancellable?) {
        lock.lock()
        defer { lock.unlock() }
        
        cancellables.remove(cancellable)
    }
}

extension ItemProvider: Provider {
    
    // MARK: - Provider
    
    @discardableResult public func provide<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], handlerQueue: DispatchQueue = .main, allowExpiredItem: Bool = false, itemHandler: @escaping (Result<Item, ProviderError>) -> Void) -> AnyCancellable? {
        
        var cancellable: AnyCancellable?
        cancellable = provide(request: request,
                     decoder: decoder,
                     providerBehaviors: providerBehaviors,
                     requestBehaviors: requestBehaviors,
                     allowExpiredItem: allowExpiredItem)
            .receive(on: handlerQueue)
            .sink(receiveCompletion: { [weak self] result in
                switch result {
                case let .failure(error):
                    itemHandler(.failure(error))
                case .finished:
                    break
                }
                self?.removeCancellable(cancellable: cancellable)
            }, receiveValue: { (item: Item) in
                itemHandler(.success(item))
            })
        
        self.insertCancellable(cancellable: cancellable)
        
        return cancellable
    }
    
    @discardableResult public func provideItems<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], handlerQueue: DispatchQueue = .main, allowExpiredItems: Bool = false, itemsHandler: @escaping (Result<[Item], ProviderError>) -> Void) -> AnyCancellable? {
        var cancellable: AnyCancellable?
        cancellable = provideItems(request: request,
                     decoder: decoder,
                     providerBehaviors: providerBehaviors,
                     requestBehaviors: requestBehaviors,
                     allowExpiredItems: allowExpiredItems)
            .receive(on: handlerQueue)
            .sink(receiveCompletion: { [weak self] result in
                switch result {
                case let .failure(error):
                    itemsHandler(.failure(error))
                case .finished:
                    break
                }
                self?.removeCancellable(cancellable: cancellable)
            }, receiveValue: { (items: [Item]) in
                itemsHandler(.success(items))
            })
        
        self.insertCancellable(cancellable: cancellable)
        return cancellable
    }
    
    public func provide<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], allowExpiredItem: Bool = false) -> AnyPublisher<Item, ProviderError> {
        
        let cachePublisher: Result<ItemContainer<Item>?, ProviderError>.Publisher = itemCachePublisher(for: request)
        
        let networkPublisher: AnyPublisher<Item, ProviderError> = itemNetworkPublisher(for: request, behaviors: requestBehaviors, decoder: decoder)
        
        let providerPublisher = cachePublisher
            .flatMap { [fetchPolicy] item -> AnyPublisher<Item, ProviderError> in
                if let item = item {
                    let itemPublisher = Just(item)
                        .map { $0.item }
                        .setFailureType(to: ProviderError.self)
                        .eraseToAnyPublisher()
                    
                    let isItemExpired = item.expirationDate.map { $0 < Date() } == true
                    let cachedItemAndNetworkPublisher = itemPublisher.merge(with: networkPublisher).eraseToAnyPublisher()
                    
                    switch fetchPolicy {
                    case .returnFromCacheElseNetwork:
                        if isItemExpired {
                            if allowExpiredItem {
                                return cachedItemAndNetworkPublisher
                            } else {
                                return networkPublisher
                            }
                        } else {
                            return itemPublisher
                        }
                    case .returnFromCacheAndNetwork:
                        if !allowExpiredItem && isItemExpired {
                            return networkPublisher
                        } else {
                            return cachedItemAndNetworkPublisher
                        }
                    }
                } else {
                    return networkPublisher
                }
            }
        
        return providerPublisher
                .handleEvents(receiveSubscription: { _ in
                    providerBehaviors.providerWillProvide(forRequest: request)
                }, receiveOutput: { item in
                    providerBehaviors.providerDidProvide(item: item, forRequest: request)
                })
                .eraseToAnyPublisher()
    }
    
    private func itemCachePublisher<Item: Providable>(for request: any ProviderRequest) -> Result<ItemContainer<Item>?, ProviderError>.Publisher {
        let cachePublisher: Result<ItemContainer<Item>?, ProviderError>.Publisher
        
        if !request.ignoresCachedContent, let persistenceKey = request.persistenceKey {
            cachePublisher = Just<ItemContainer<Item>?>(try? self.cache?.read(forKey: persistenceKey))
                .setFailureType(to: ProviderError.self)
        } else {
            cachePublisher = Just<ItemContainer<Item>?>(nil)
                .setFailureType(to: ProviderError.self)
        }
        
        return cachePublisher
    }
    
    private func itemNetworkPublisher<Item: Providable>(for request: any ProviderRequest, behaviors: [RequestBehavior], decoder: ItemDecoder) -> AnyPublisher<Item, ProviderError> {
        return networkRequestPerformer.send(request, scheduler: DispatchQueue.main, requestBehaviors: behaviors)
            .mapError { ProviderError.networkError($0) }
            .unpackData(errorTransform: { _ in ProviderError.networkError(.noData) })
            .decodeItem(decoder: decoder, errorTransform: { ProviderError.decodingError($0) })
            .handleEvents(receiveOutput: { [weak self] item in
                if let persistenceKey = request.persistenceKey {
                    try? self?.cache?.write(item: item, forKey: persistenceKey)
                }
            })
            .eraseToAnyPublisher()
    }
    
    public func provideItems<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], allowExpiredItems: Bool = false) -> AnyPublisher<[Item], ProviderError> {
        
        let cachePublisher: Result<CacheItemsResponse<Item>?, ProviderError>.Publisher = itemsCachePublisher(for: request)
        let networkPublisher: AnyPublisher<[Item], ProviderError> = itemsNetworkPublisher(for: request, behaviors: requestBehaviors, decoder: decoder)
        
        let providerPublisher = cachePublisher
            .flatMap { [fetchPolicy] response -> AnyPublisher<[Item], ProviderError> in
                if let response = response {
                    let itemContainers = response.itemContainers
                    
                    let itemPublisher = Just(itemContainers.map { $0.item })
                        .setFailureType(to: ProviderError.self)
                        .eraseToAnyPublisher()
                    
                    let itemsAreExpired = itemContainers.first?.expirationDate.map { $0 < Date() } == true
                    
                    if !response.partialErrors.isEmpty {
                        return networkPublisher
                            .mapError { providerError in
                                if !itemsAreExpired || (itemsAreExpired && allowExpiredItems) {
                                    return ProviderError.partialRetrieval(retrievedItems: response.itemContainers.map { $0.item }, persistenceFailures: response.partialErrors, providerError: providerError)
                                } else {
                                    return providerError
                                }
                            }
                            .eraseToAnyPublisher()
                    }
                    
                    let cachedItemsAndNetworkPublisher = itemPublisher.merge(with: networkPublisher).eraseToAnyPublisher()
                    
                    switch fetchPolicy {
                    case .returnFromCacheElseNetwork:
                        if itemsAreExpired {
                            if allowExpiredItems {
                                return cachedItemsAndNetworkPublisher
                            } else {
                                return networkPublisher
                            }
                        } else {
                            return itemPublisher
                        }
                    case .returnFromCacheAndNetwork:
                        if !allowExpiredItems && itemsAreExpired {
                            return networkPublisher
                        } else {
                            return cachedItemsAndNetworkPublisher
                        }
                    }
                } else {
                    return networkPublisher
                }
        }
        
        return providerPublisher
                .handleEvents(receiveSubscription: { _ in
                    providerBehaviors.providerWillProvide(forRequest: request)
                }, receiveOutput: { item in
                    providerBehaviors.providerDidProvide(item: item, forRequest: request)
                })
                .eraseToAnyPublisher()
    }
    
    public func asyncProvide<Item: Providable>(request: any ProviderRequest, decoder: any ItemDecoder = JSONDecoder(), providerBehaviors: [any ProviderBehavior] = [], requestBehaviors: [any Networking.RequestBehavior] = []) async -> AsyncStream<Result<Item, ProviderError>> {
        var cancellable: AnyCancellable?
        return AsyncStream { [weak self] continuation in
            cancellable =  self?.provide(request: request, decoder: decoder, providerBehaviors: providerBehaviors, requestBehaviors: requestBehaviors, allowExpiredItem: false)
                .sink { completion in
                    switch completion {
                    case .finished: break
                    case let .failure(error):
                        continuation.yield(.failure(error))
                    }
                    continuation.finish()
                } receiveValue: { item in
                    continuation.yield(.success(item))
                }
            self?.insertCancellable(cancellable: cancellable)
        }
    }
    
    public func asyncProvideItems<Item: Providable>(request: any ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [any ProviderBehavior] = [], requestBehaviors: [any Networking.RequestBehavior] = []) async -> AsyncStream<Result<[Item], ProviderError>> {
        var cancellable: AnyCancellable?
        return AsyncStream { [weak self] continuation in
            cancellable =  self?.provideItems(request: request, decoder: decoder, providerBehaviors: providerBehaviors, requestBehaviors: requestBehaviors, allowExpiredItems: false)
                .sink { completion in
                    switch completion {
                    case let .failure(error):
                        continuation.yield(.failure(error))
                    case .finished: break
                    }
                    continuation.finish()
                } receiveValue: { items in
                    continuation.yield(.success(items))
                }
            self?.insertCancellable(cancellable: cancellable)
        }
    }
    
    private func itemsCachePublisher<Item: Providable>(for request: any ProviderRequest) -> Result<CacheItemsResponse<Item>?, ProviderError>.Publisher {
        let cachePublisher: Result<CacheItemsResponse<Item>?, ProviderError>.Publisher
        
        if !request.ignoresCachedContent, let persistenceKey = request.persistenceKey {
            cachePublisher = Just<CacheItemsResponse<Item>?>(try? self.cache?.readItems(forKey: persistenceKey))
                .setFailureType(to: ProviderError.self)
        } else {
            cachePublisher = Just<CacheItemsResponse<Item>?>(nil)
                .setFailureType(to: ProviderError.self)
        }
        
        return cachePublisher
    }
    
    private func itemsNetworkPublisher<Item: Providable>(for request: any ProviderRequest, behaviors: [RequestBehavior], decoder: ItemDecoder) -> AnyPublisher<[Item], ProviderError> {
        
        return networkRequestPerformer.send(request, scheduler: DispatchQueue.main, requestBehaviors: behaviors)
            .mapError { ProviderError.networkError($0) }
            .unpackData(errorTransform: { _ in ProviderError.networkError(.noData) })
            .decodeItems(decoder: decoder, errorTransform: { ProviderError.decodingError($0) })
            .handleEvents(receiveOutput: { [weak self] items in
                if let persistenceKey = request.persistenceKey {
                    self?.cache?.writeItems(items, forKey: persistenceKey)
                }
            })
            .eraseToAnyPublisher()
    }
}

extension ItemProvider {
    
    /// Creates an `ItemProvider` configured with a `Persister` (memory and disk cache) and `NetworkController`.
    /// - Parameters:
    ///   - persistenceURL: The location on disk in which items are persisted. Defaults to the Application Support directory.
    ///   - memoryCacheCapacity: The capacity of the LRU memory cache. Defaults to a limited capacity of 100 items.
    public static func configuredProvider(withRootPersistenceURL persistenceURL: URL = FileManager.default.applicationSupportDirectoryURL, memoryCacheCapacity: CacheCapacity = .limited(numberOfItems: 100), fetchPolicy: ItemProvider.FetchPolicy = .returnFromCacheElseNetwork) -> ItemProvider {
        let memoryCache = MemoryCache(capacity: memoryCacheCapacity)
        let diskCache = DiskCache(rootDirectoryURL: persistenceURL)
        let persister = Persister(memoryCache: memoryCache, diskCache: diskCache)
        
        return ItemProvider(networkRequestPerformer: NetworkController(), cache: persister, fetchPolicy: fetchPolicy, defaultProviderBehaviors: [])
    }
}

extension FileManager {
    public var applicationSupportDirectoryURL: URL! { //swiftlint:disable:this implicitly_unwrapped_optional
        return urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}

private extension Cache {
    func readItems<Item: Codable>(forKey key: Key) throws -> ([ItemContainer<Item>], [ProviderError.PartialRetrievalFailure]) {
        guard let itemIDsContainer: ItemContainer<[String]> = try read(forKey: key) else {
            throw PersistenceError.noValidDataForKey
        }
        
        var failedItemErrors: [ProviderError.PartialRetrievalFailure] = []
        let validItems: [ItemContainer<Item>] = itemIDsContainer.item.compactMap { key in
            let fallbackError = ProviderError.PartialRetrievalFailure(key: key, persistenceError: .noValidDataForKey)

            do {
                if let container: ItemContainer<Item> = try read(forKey: key) {
                    return container
                }
                
                failedItemErrors.append(fallbackError)
                return nil
            } catch {
                if let persistenceError = error as? PersistenceError {
                    let retrievalError = ProviderError.PartialRetrievalFailure(key: key, persistenceError: persistenceError)

                    failedItemErrors.append(retrievalError)
                } else {
                    failedItemErrors.append(fallbackError)
                }
                
                return nil
            }
        }
        
        return (validItems, failedItemErrors)
    }
    
    func writeItems<Item: Providable>(_ items: [Item], forKey key: Key) {
        items.forEach { item in
            try? write(item: item, forKey: item.identifier)
        }
        
        let itemIdentifiers = items.compactMap { $0.identifier }
        try? write(item: itemIdentifiers, forKey: key)
    }
}

private func <(lhs: Date?, rhs: Date) -> Bool {
    if let lhs = lhs {
        return lhs < rhs
    }
    
    return false
}

private extension Publisher {
    
    func unpackData(errorTransform: @escaping (Error) -> Failure) -> Publishers.FlatMap<AnyPublisher<Data, ProviderError>, Self> where Failure == ProviderError, Self.Output == NetworkResponse {
        
        return flatMap {
            Just($0)
                .tryCompactMap { $0.data }
                .mapError { errorTransform($0) }
                .eraseToAnyPublisher()
        }
    }
    
    func decodeItem<Item: Providable>(decoder: ItemDecoder, errorTransform: @escaping (Error) -> Failure) -> Publishers.FlatMap<AnyPublisher<Item, ProviderError>, Self> where Failure == ProviderError, Self.Output == Data {

        return flatMap {
            Just($0)
                .tryMap { try decoder.decode(Item.self, from: $0) }
                .mapError { errorTransform($0) }
                .eraseToAnyPublisher()
        }
    }
    
    func decodeItems<Item: Providable>(decoder: ItemDecoder, errorTransform: @escaping (Error) -> Failure) -> Publishers.FlatMap<AnyPublisher<[Item], ProviderError>, Self> where Failure == ProviderError, Self.Output == Data {

        return flatMap {
            Just($0)
                .tryMap { try decoder.decode([Item].self, from: $0) }
                .mapError { errorTransform($0) }
                .eraseToAnyPublisher()
        }
    }
}
