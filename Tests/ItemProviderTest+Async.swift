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
    
    func testProvideItemsStream() async {
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
    
    func testProvideItemsDoesNotReturnPartialResponseUponFailureForExpiredItemsStream() async {
        let request = TestProviderRequest()
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        let _ : AsyncStream<Result<[TestItem], ProviderError>> = await expiredProvider.asyncProvideItems(request: request)
        
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
                case .decodingError: break
                default: XCTFail("Should have received a decoding error.")
                }
            }
        }
    }
    
    func testProvideItemsFailureStream() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
        }
        
        let result : AsyncStream<Result<[TestItem], ProviderError>> = await cacheElseNetworkProvider.asyncProvideItems(request: request)
        for await result in result {
            switch result {
            case .success:
                XCTFail("There should be an error.")
            case .failure: break
            }
        }
        
    }
    
    // MARK: - Async Provide Item Async Stream Tests
    
    func testProvideItemStream() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        let result: AsyncStream<Result<TestItem, ProviderError>> = await cacheElseNetworkProvider.asyncProvide(request: request)
        
        for await result in result {
            switch result {
            case .success: break
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
        }
    }
    
    func testProvideItemReturnsCachedResultStream() async {
        let request = TestProviderRequest()
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        let result: AsyncStream<Result<TestItem, ProviderError>> = await cacheElseNetworkProvider.asyncProvide(request: request)
        
        for await result in result {
            switch result {
            case .success:
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true }) { _ in
                    fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
                }
                
                let result: AsyncStream<Result<TestItem, ProviderError>> = await cacheElseNetworkProvider.asyncProvide(request: request)
                for await result in result {
                    switch result {
                    case .success:
                        break
                    case let .failure(error):
                        XCTFail("There should be no error: \(error)")
                    }
                }
                
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
        }
    }
    
    func testProvideItemFailureStream() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
        }
        
        let result: AsyncStream<Result<TestItem, ProviderError>> = await cacheElseNetworkProvider.asyncProvide(request: request)
        
        for await result in result {
            switch result {
            case .success:
                XCTFail("There should be an error.")
            case .failure: break
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
            case .success:
                return
            case .failure(let error):
                XCTFail("Expected success from cache but got error: \(error)")
            }
        }
    }
}
