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
    
    override func tearDown() async throws {
        HTTPStubs.removeAllStubs()
        try? provider.cache?.removeAll()
        try? expiredProvider.cache?.removeAll()
    }
    
    // MARK: - Async Provide Items Tests
    
    func testProvideItems() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        let result: Result<[TestItem], ProviderError> = await provider.asyncProvideItems(request: request)
        
        switch result {
        case let .success(items):
            XCTAssertEqual(items.count, 3)
        case let .failure(error):
            XCTFail("There should be no error: \(error)")
        }
    }
    
    func testProvideItemsReturnsPartialResponseUponFailure() async {
        let request = TestProviderRequest()
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }

        let _ : Result<[TestItem], ProviderError> = await provider.asyncProvideItems(request: request)
        
        try? self.provider.cache?.remove(forKey: "Hello 2")
        HTTPStubs.removeStub(originalStub)
        
        stub(condition: { _ in true}) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        let secondResult: Result<[TestItem], ProviderError> = await provider.asyncProvideItems(request: request)
       
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
                
            default: XCTFail("Should have received a partial retrieval error.")
            }
        }
    }
    
    func testProvideItemsDoesNotReturnPartialResponseUponFailureForExpiredItems() async {
        let request = TestProviderRequest()
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        let _ : Result<[TestItem], ProviderError> = await expiredProvider.asyncProvideItems(request: request)
        
        try? self.expiredProvider.cache?.remove(forKey: "Hello 2")
        HTTPStubs.removeStub(originalStub)
        
        stub(condition: { _ in true}) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        let expiredResult : Result<[TestItem], ProviderError> = await expiredProvider.asyncProvideItems(request: request)
        
        switch expiredResult {
        case .success:
            XCTFail("Should have received a decoding error.")
        case let .failure(error):
            switch error {
            case .decodingError: break
            default: XCTFail("Should have received a decoding error.")
            }
        }
    }
    
    func testProvideItemsFailure() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
        }
        
        let result : Result<[TestItem], ProviderError> = await provider.asyncProvideItems(request: request)
        switch result {
        case .success:
            XCTFail("There should be an error.")
        case .failure: break
        }
    }
    
    // MARK: - Async Provide Item Tests
    
    func testProvideItem() async {
        let request = TestProviderRequest()
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        let result: Result<TestItem, ProviderError> = await provider.asyncProvide(request: request)
        
        switch result {
        case .success: break
        case let .failure(error):
            XCTFail("There should be no error: \(error)")
        }
    }
    
    func testProvideItemReturnsCachedResult() async {
        let request = TestProviderRequest()
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        let result: Result<TestItem, ProviderError> = await provider.asyncProvide(request: request)
        
        switch result {
        case .success:
            HTTPStubs.removeStub(originalStub)
            
            stub(condition: { _ in true }) { _ in
                fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
            }
            
            let result: Result<TestItem, ProviderError> = await provider.asyncProvide(request: request)
            switch result {
            case .success:
                break
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
            
        case let .failure(error):
            XCTFail("There should be no error: \(error)")
        }
    }
    
    func testProvideItemFailure() async {
        let request = TestProviderRequest()
    
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
        }
        
        let result: Result<TestItem, ProviderError> = await provider.asyncProvide(request: request)
        switch result {
        case .success:
            XCTFail("There should be an error.")
        case .failure: break
        }
    }
}
