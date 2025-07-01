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

    private let provider = ItemProvider.configuredProvider(withRootPersistenceURL: FileManager.default.cachesDirectoryURL, memoryCacheCapacity: .unlimited)

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
        try? provider.cache?.removeAll()
        try? expiredProvider.cache?.removeAll()
    }
    
    // MARK: - Async Provide Items Async Stream Tests
    
    func testProvideItemsStream() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        let testItemResult: AsyncStream<Result<[TestItem], ProviderError>> = await provider.asyncProvideItems(request: request, decoder: JSONDecoder(), providerBehaviors: [], requestBehaviors: [])
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
        
        let result : AsyncStream<Result<[TestItem], ProviderError>> = await provider.asyncProvideItems(request: request)
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
        
        let result: AsyncStream<Result<TestItem, ProviderError>> = await provider.asyncProvide(request: request)
        
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
        
        let result: AsyncStream<Result<TestItem, ProviderError>> = await provider.asyncProvide(request: request)
        
        for await result in result {
            switch result {
            case .success:
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true }) { _ in
                    fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
                }
                
                let result: AsyncStream<Result<TestItem, ProviderError>> = await provider.asyncProvide(request: request)
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
        
        let result: AsyncStream<Result<TestItem, ProviderError>> = await provider.asyncProvide(request: request)
        
        for await result in result {
            switch result {
            case .success:
                XCTFail("There should be an error.")
            case .failure: break
            }
        }
    }
}
