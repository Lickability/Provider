//
//  ItemProviderTests+Async.swift
//  ProviderTests
//
//  Created by Ashli Rankin on 1/16/24.
//  Copyright © 2024 Lickability. All rights reserved.
//

import Combine
import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift

import Networking
import Persister

@testable import Provider

@MainActor
final class ItemProviderTests_Async: XCTestCase {

    private let cacheElseNetworkProvider = ItemProvider.configuredProvider(withRootPersistenceURL: FileManager.default.cachesDirectoryURL, memoryCacheCapacity: .unlimited)
    private let cacheAndNetworkProvider = ItemProvider.configuredProvider(withRootPersistenceURL: FileManager.default.cachesDirectoryURL, memoryCacheCapacity: .unlimited, fetchPolicy: .returnFromCacheAndNetwork)

    private let expiredProvider: ItemProvider = {
        let networkController = NetworkController()
        let cache = Persister(memoryCache: MemoryCache(capacity: .unlimited, expirationPolicy: .afterInterval(-1)), diskCache: DiskCache(rootDirectoryURL: FileManager.default.cachesDirectoryURL, expirationPolicy: .afterInterval(-1)))
        
        return ItemProvider(networkRequestPerformer: networkController, cache: cache)
    }()
    
    private var cancellables = Set<AnyCancellable>()
    private lazy var itemPath = OHPathForFile("Item.json", type(of: self))!
    private lazy var itemsPath = OHPathForFile("Items.json", type(of: self))!
    private lazy var datesPath = OHPathForFile("Dates.json", type(of: self))!
    
    override func tearDown() async throws {
        HTTPStubs.removeAllStubs()
        try? cacheElseNetworkProvider.cache?.removeAll()
        try? cacheAndNetworkProvider.cache?.removeAll()
        try? expiredProvider.cache?.removeAll()
    }
    
    // MARK: - Async Provide Items Async Stream Tests
    
    func testProvideItemsCacheElseNetworkProvider() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        let testItemResult: AsyncStream<Result<[TestItem], ProviderError>> = await cacheElseNetworkProvider.asyncProvideItems(request: request, decoder: JSONDecoder(), providerBehaviors: [], requestBehaviors: [])
        
        for try await result in testItemResult {
            switch result {
            case let .success(testItems):
                XCTAssertEqual(testItems.count, 3)
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
        }
    }
    
    func testProvideItemsDoesNotReturnPartialResponseUponFailureForExpiredItems() async {
        let request = TestProviderRequest()
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        let result : AsyncStream<Result<[TestItem], ProviderError>> = await expiredProvider.asyncProvideItems(request: request)
        
        for await _ in result {
            try? self.expiredProvider.cache?.remove(forKey: "Hello 2")
            HTTPStubs.removeStub(originalStub)
            
            stub(condition: { _ in true}) { _ in
                fixture(filePath: self.itemPath, headers: nil)
            }
            
            let expiredResult : AsyncStream<Result<[TestItem], ProviderError>> = await expiredProvider.asyncProvideItems(request: request)
            
            for await result in expiredResult {
                switch result {
                case .success:
                    XCTFail("Should have received a decoding error.")
                case let .failure(error):
                    switch error {
                    case .decodingError:
                       break
                    default: XCTFail("Should have received a decoding error.")
                    }
                }
            }
        }
    }
    
    func testProvideItemsReturnsPartialResponseUponFailureCacheElseNetwork() async {
        let request = TestProviderRequest()
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        let resultOne :  AsyncStream<Result<[TestItem], ProviderError>> = await cacheElseNetworkProvider.asyncProvideItems(request: request)
       
        for await _ in resultOne {
            try? self.cacheElseNetworkProvider.cache?.remove(forKey: "Hello 2")
            
            HTTPStubs.removeStub(originalStub)
            
            stub(condition: { _ in true}) { _ in
                fixture(filePath: self.itemPath, headers: nil)
            }
            
            let secondResult: AsyncStream<Result<[TestItem], ProviderError>> = await cacheElseNetworkProvider.asyncProvideItems(request: request)
            
            for await secondResult in secondResult {
                switch secondResult {
                case .success:
                    XCTFail("Should have received a partial retrieval failure.")
                case let .failure(error):
                    switch error {
                    case let .partialRetrieval(retrievedItems, persistenceErrors, error):
                        let expectedItemIDs = ["Hello 1", "Hello 3"]
                        
                        XCTAssertEqual(retrievedItems.map { $0.identifier }, expectedItemIDs)
                        XCTAssertEqual(persistenceErrors.count, 1)
                        XCTAssertEqual(persistenceErrors.first?.key, "Hello 2")
                        
                        guard case ProviderError.decodingError = error else {
                            XCTFail("Incorrect error received.")
                            return
                        }
                        
                        guard let persistenceError = persistenceErrors.first?.persistenceError, case PersistenceError.noValidDataForKey = persistenceError else {
                            XCTFail("Incorrect error received.")
                            return
                        }
                    default:
                        XCTFail("Should have received a partial retrieval error. But got \(error)")
                    }
                }
            }
        }
    }
    
    func testProvideItemsFailureCacheElseNetworkProvider() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
        }
        
        let result : AsyncStream<Result<[TestItem], ProviderError>> = await cacheElseNetworkProvider.asyncProvideItems(request: request)
        
        for await result in result {
            switch result {
            case .success:
                XCTFail("There should be an error.")
            case let .failure(error):
                switch error {
                case .networkError, .partialRetrieval, .persistenceError:
                    XCTFail("Expected decoding error.")
                case .decodingError:
                    break
                }
            }
        }
    }
    
    func testAsyncProvideItemsWithCustomDecoder() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.datesPath, headers: nil)
        }
        
        // Test first to ensure failure when not providing a custom decoder.
        let result1: AsyncStream<Result<[TestDateContainer], ProviderError>> = await cacheElseNetworkProvider.asyncProvideItems(request: request)
        
        for await result1 in result1 {
            switch result1 {
            case .success:
                XCTFail("Decoding should fail due to incorrect date format")
            case let .failure(error):
                switch error {
                case .decodingError:
                    break
                default:
                    XCTFail("An unexpected, non-decoding error occurred: \(error)")
                }
            }
        }
        
        
        // Now test the same file with our custom decoder.
        let customDecoder = JSONDecoder()
        customDecoder.dateDecodingStrategy = .iso8601
        let result2: AsyncStream<Result<[TestDateContainer], ProviderError>> = await cacheElseNetworkProvider.asyncProvideItems(request: request, decoder: customDecoder)
        
        for await result2 in result2 {
            switch result2 {
            case let .success(dateContainers):
                XCTAssertEqual(dateContainers.count, 2)
            case let .failure(error):
                XCTFail("An unexpected error occurred: \(error)")
            }
        }
    }
    
    // MARK: - CacheAndNetworkProvider Tests
    
    func testProvideItem() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        let result: AsyncStream<Result<TestItem, ProviderError>> = await cacheAndNetworkProvider.asyncProvide(request: request)
        
        for await result in result {
            switch result {
            case let .success(item):
                XCTAssertEqual(item, TestItem(title: "Hello"))
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
        }
    }
    
    func testReturnsCachedItemThenNetworkFailureOnSubsequentRequest() async {
        let request = TestProviderRequest()

        let validStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }

        let initialStream: AsyncStream<Result<TestItem, ProviderError>> = await cacheAndNetworkProvider.asyncProvide(request: request)
        var didCacheItem = false

        for await result in initialStream {
            switch result {
            case .success:
                didCacheItem = true
            case .failure(let error):
                XCTFail("Unexpected failure during initial request: \(error)")
            }
        }

        XCTAssertTrue(didCacheItem, "Expected to cache item after successful fetch")

        HTTPStubs.removeStub(validStub)
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
        }

        let secondStream: AsyncStream<Result<TestItem, ProviderError>> = await cacheAndNetworkProvider.asyncProvide(request: request)
        
        var results = [Result<TestItem, ProviderError>]()

        for await result in secondStream {
            results.append(result)
        }

        guard results.count >= 2 else {
            XCTFail("Expected both a cached response and a network response")
            return
        }

        switch results[0] {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected cached success, but got error: \(error)")
        }

        switch results[1] {
        case .success:
            XCTFail("Expected network failure, but got success instead")
        case .failure:
            break
        }
    }
    
    func testProvideItemFailureStreamNoCachedItems() async {
        let request = TestProviderRequest()
        
        try? cacheAndNetworkProvider.cache?.removeAll()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
        }
        
        let result: AsyncStream<Result<TestItem, ProviderError>> = await cacheAndNetworkProvider.asyncProvide(request: request)
        
        for await result in result {
            switch result {
            case .success:
                XCTFail("There should be an error.")
            case let .failure(error):
                switch error {
                case .networkError, .partialRetrieval, .persistenceError:
                    XCTFail("Expected decoding error.")
                case .decodingError:
                    break
                }
            }
        }
    }
    
    func testProviderReturnsThreeTestItemsSuccessfully() async {
        let request = TestProviderRequest()

        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }

        let resultStream: AsyncStream<Result<[TestItem], ProviderError>> = await cacheAndNetworkProvider.asyncProvideItems(request: request, decoder: JSONDecoder(), providerBehaviors: [], requestBehaviors: [])

        var receivedItems: [TestItem]? = nil

        for try await result in resultStream {
            switch result {
            case .success(let items):
                receivedItems = items
            case .failure(let error):
                XCTFail("Expected success but got error: \(error)")
            }
        }

        XCTAssertEqual(receivedItems?.count, 3, "Expected exactly 3 test items")
    }
    
    func testCachePreservesValidResultWhenNetworkReturnsInvalidResponse() async {
        let request = TestProviderRequest()

        let validStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }

        let initialStream: AsyncStream<Result<TestItem, ProviderError>> = await cacheAndNetworkProvider.asyncProvide(request: request)

        var didReceiveValidResponse = false

        for await result in initialStream {
            switch result {
            case .success:
                didReceiveValidResponse = true
            case .failure(let error):
                XCTFail("Expected success but got error: \(error)")
            }
        }

        XCTAssertTrue(didReceiveValidResponse, "Should have received a valid response initially")

        HTTPStubs.removeStub(validStub)

        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
        }

        let invalidStream: AsyncStream<Result<TestItem, ProviderError>> = await cacheAndNetworkProvider.asyncProvide(request: request)

        var didReceiveFailure = false

        for await result in invalidStream {
            switch result {
            case .success:
                break
            case .failure:
                didReceiveFailure = true
            }
        }

        XCTAssertTrue(didReceiveFailure, "Should have received a failure from the invalid network response")

        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }

        let finalStream: AsyncStream<Result<TestItem, ProviderError>> = await cacheAndNetworkProvider.asyncProvide(request: request)

        for await result in finalStream {
            switch result {
            case let .success(item):
                XCTAssertEqual(item, TestItem(title: "Hello"))
            case .failure(let error):
                XCTFail("Expected success from cache but got error: \(error)")
            }
        }
    }
    
    func testProvideItemsReturnsPartialResponseUponFailureCacheAndNetwork() async {
        let request = TestProviderRequest()
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        let resultOne :  AsyncStream<Result<[TestItem], ProviderError>> = await cacheAndNetworkProvider.asyncProvideItems(request: request)
       
        for await _ in resultOne {
            try? self.cacheAndNetworkProvider.cache?.remove(forKey: "Hello 2")
            
            HTTPStubs.removeStub(originalStub)
            
            stub(condition: { _ in true}) { _ in
                fixture(filePath: self.itemPath, headers: nil)
            }
            
            let secondResult: AsyncStream<Result<[TestItem], ProviderError>> = await cacheAndNetworkProvider.asyncProvideItems(request: request)
            
            for await secondResult in secondResult {
                switch secondResult {
                case .success:
                    XCTFail("Should have received a partial retrieval failure.")
                case let .failure(error):
                    switch error {
                    case let .partialRetrieval(retrievedItems, persistenceErrors, error):
                        let expectedItemIDs = ["Hello 1", "Hello 3"]
                        
                        XCTAssertEqual(retrievedItems.map { $0.identifier }, expectedItemIDs)
                        XCTAssertEqual(persistenceErrors.count, 1)
                        XCTAssertEqual(persistenceErrors.first?.key, "Hello 2")
                        
                        guard case ProviderError.decodingError = error else {
                            XCTFail("Incorrect error received.")
                            return
                        }
                        
                        guard let persistenceError = persistenceErrors.first?.persistenceError, case PersistenceError.noValidDataForKey = persistenceError else {
                            XCTFail("Incorrect error received.")
                            return
                        }
                    case let .decodingError(error):
                        XCTFail("Should have received a partial retrieval error. But got \(error)")
                    case let .networkError(error):
                        XCTFail("Should have received a partial retrieval error. But got \(error)")
                    case let .persistenceError(error):
                        XCTFail("Should have received a partial retrieval error. But got \(error)")
                    }
                }
            }
        }
    }
}
