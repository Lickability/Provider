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
public final class ItemProvider {
    
    /// Performs network requests when items cannot be retrieved from persistence.
    public let networkRequestPerformer: NetworkRequestPerformer
    
    /// The cache used to persist / recall previously retrieved items.
    public let cache: Cache?
    
    private let defaultProviderBehaviors: [ProviderBehavior]
    private let providerQueue = DispatchQueue(label: "ProviderQueue", attributes: .concurrent)
    
    /// Creates a new `ItemProvider`.
    /// - Parameters:
    ///   - networkRequestPerformer: Performs network requests when items cannot be retrieved from persistence.
    ///   - cache: The cache used to persist / recall previously retrieved items.
    ///   - defaultProviderBehaviors: Actions to perform before _every_ provider request is performed and / or after _every_ provider request is completed.
    public init(networkRequestPerformer: NetworkRequestPerformer, cache: Cache?, defaultProviderBehaviors: [ProviderBehavior]) {
        self.networkRequestPerformer = networkRequestPerformer
        self.cache = cache
        self.defaultProviderBehaviors = defaultProviderBehaviors
    }
}

extension ItemProvider: Provider {
    
    // MARK: - Provider
    
    public func provide<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], completionQueue: DispatchQueue, completion: @escaping (Result<Item, ProviderError>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(ProviderError.noStrongReferenceToProvider))
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            providerBehaviors.providerWillProvide(forRequest: request)
            
            if let cachedItem: Item = try? self.cache?.read(forKey: request.persistenceKey) {
                completionQueue.async { completion(.success(cachedItem)) }
                
                providerBehaviors.providerDidProvide(item: cachedItem, forRequest: request)
            } else {
                self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors) { [weak self] (result: Result<NetworkResponse, NetworkError>) in
                    switch result {
                    case let .success(response):
                        if let data = response.data {
                            do {
                                let item = try decoder.decode(Item.self, from: data)
                                try self?.cache?.write(item: item, forKey: request.persistenceKey)
                                completionQueue.async { completion(.success(item)) }
                                
                                providerBehaviors.providerDidProvide(item: item, forRequest: request)
                            } catch {
                                completionQueue.async { completion(.failure(ProviderError.decodingError(error))) }
                            }
                        } else {
                            completionQueue.async { completion(.failure(.networkError(.noData)))}
                        }
                    case let .failure(error):
                        completionQueue.async { completion(.failure(.networkError(error))) }
                    }
                }
            }
        }
    }
    
    public func provideItems<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], completionQueue: DispatchQueue = .main, completion: @escaping (Result<[Item], ProviderError>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(ProviderError.noStrongReferenceToProvider))
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            providerBehaviors.providerWillProvide(forRequest: request)
            
            
            //let items =
            
            if let cachedItems: [Item] = try? self.cache?.readItems(forKey: request.persistenceKey), !cachedItems.isEmpty {
                completionQueue.async { completion(.success(cachedItems)) }
                
                providerBehaviors.providerDidProvide(item: cachedItems, forRequest: request)
            } else {
                self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors) { [weak self] (result: Result<NetworkResponse, NetworkError>) in
                    switch result {
                    case let .success(response):
                        if let data = response.data {
                            do {
                                let items = try decoder.decode([Item].self, from: data)
                                self?.cache?.writeItems(items, forKey: request.persistenceKey)
                                completionQueue.async { completion(.success(items)) }
                                
                                providerBehaviors.providerDidProvide(item: items, forRequest: request)
                            } catch {
                                completionQueue.async { completion(.failure(ProviderError.decodingError(error))) }
                            }
                        } else {
                            completionQueue.async { completion(.failure(.networkError(.noData))) }
                        }
                    case let .failure(error):
                        completionQueue.async { completion(.failure(.networkError(error))) }
                    }
                }
            }
        }
    }
        
    public func provide<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior]) -> AnyPublisher<Item, ProviderError> {
        
        return Just<Item?>(try? self.cache?.read(forKey: request.persistenceKey))
            .setFailureType(to: ProviderError.self)
            .flatMap { item -> AnyPublisher<Item, ProviderError> in
                if let item = item {
                    return Just(item)
                        .setFailureType(to: ProviderError.self)
                        .eraseToAnyPublisher()
                } else {
                    return self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors)
                        .mapError { ProviderError.networkError($0) }
                        .tryCompactMap { $0.data }
                        .mapError { _ in ProviderError.networkError(.noData) }
                        .tryMap { try decoder.decode(Item.self, from: $0) }
                        .mapError { ProviderError.decodingError($0) }
                        .handleEvents(receiveOutput: { [weak self] item in
                            try? self?.cache?.write(item: item, forKey: request.persistenceKey)
                        })
                        .eraseToAnyPublisher()
                }
            }
            .handleEvents(receiveSubscription: { _ in
                providerBehaviors.providerWillProvide(forRequest: request)
            }, receiveOutput: { item in
                providerBehaviors.providerDidProvide(item: item, forRequest: request)
            })
            .subscribe(on: providerQueue)
            .eraseToAnyPublisher()
    }
    
    public func provideItems<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior]) -> AnyPublisher<[Item], ProviderError> {
        
        return Just<[Item]?>(try? self.cache?.readItems(forKey: request.persistenceKey))
            .setFailureType(to: ProviderError.self)
            .flatMap { items -> AnyPublisher<[Item], ProviderError> in
                if let items = items {
                    return Just(items)
                        .setFailureType(to: ProviderError.self)
                        .eraseToAnyPublisher()
                } else {
                    return self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors)
                        .mapError { ProviderError.networkError($0) }
                        .tryCompactMap { $0.data }
                        .mapError { _ in ProviderError.networkError(.noData) }
                        .tryMap { try decoder.decode([Item].self, from: $0) }
                        .mapError { ProviderError.decodingError($0) }
                        .handleEvents(receiveOutput: { [weak self] items in
                            self?.cache?.writeItems(items, forKey: request.persistenceKey)
                        })
                        .eraseToAnyPublisher()
                }
            }
            .handleEvents(receiveSubscription: { _ in
                providerBehaviors.providerWillProvide(forRequest: request)
            }, receiveOutput: { item in
                providerBehaviors.providerDidProvide(item: item, forRequest: request)
            })
            .subscribe(on: providerQueue)
            .eraseToAnyPublisher()
    }
}

extension ItemProvider {
    
    /// Creates an `ItemProvider` configured with a `Persister` (memory and disk cache) and `NetworkController`.
    /// - Parameters:
    ///   - persistenceURL: The location on disk in which items are persisted. Defaults to the Application Support directory.
    ///   - memoryCacheCapacity: The capacity of the LRU memory cache. Defaults to a limited capacity of 100 items.
    public static func configuredProvider(withRootPersistenceURL persistenceURL: URL = FileManager.default.applicationSupportDirectoryURL, memoryCacheCapacity: CacheCapacity = .limited(numberOfItems: 100)) -> ItemProvider {
        let memoryCache = MemoryCache(capacity: memoryCacheCapacity)
        let diskCache = DiskCache(rootDirectoryURL: persistenceURL)
        let persister = Persister(memoryCache: memoryCache, diskCache: diskCache)
        
        return ItemProvider(networkRequestPerformer: NetworkController(), cache: persister, defaultProviderBehaviors: [])
    }
}

extension FileManager {
    public var applicationSupportDirectoryURL: URL! { //swiftlint:disable:this implicitly_unwrapped_optional
        return urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}

private extension Cache {
    func readItems<Item: Codable>(forKey key: Key) throws -> [Item] { // return items and `PartialRetrievalPersistenceError`, maybe in a tuple.
        guard let itemIDs: [String] = try read(forKey: key) else {
            throw PersistenceError.noValidDataForKey
        }
        
        var failedItemIDs: [String] = [] // make these `PartialRetrievalPersistenceError`s, not strings
        let items: [Item] = itemIDs.compactMap { key in
            do {
                guard let item: Item = try read(forKey: key) else {
                    failedItemIDs.append(key)
                    return nil
                }
                
                return item
            } catch {
                failedItemIDs.append(key)
                return nil
            }
        }
        
        
        return items
    }
    
    func writeItems<Item: Providable>(_ items: [Item], forKey key: Key) {
        items.forEach { item in
            try? write(item: item, forKey: item.identifier)
        }
        
        let itemIdentifiers = items.compactMap { $0.identifier }
        try? write(item: itemIdentifiers, forKey: key)
    }
}
