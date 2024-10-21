//
//  ItemProviderTests.swift
//  ProviderTests
//
//  Created by Michael Liberatore on 8/14/20.
//  Copyright © 2020 Lickability. All rights reserved.
//

import Combine
import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift

import Networking
import Persister

@testable import Provider

class ItemProviderTests: XCTestCase {
    
    private let provider = ItemProvider.configuredProvider(withRootPersistenceURL: FileManager.default.cachesDirectoryURL, memoryCacheCapacity: .unlimited)
    private let expiredProvider: ItemProvider = {
        let networkController = NetworkController()
        let cache = Persister(memoryCache: MemoryCache(capacity: .unlimited, expirationPolicy: .afterInterval(-1)), diskCache: DiskCache(rootDirectoryURL: FileManager.default.cachesDirectoryURL, expirationPolicy: .afterInterval(-1)))
        
        return ItemProvider(networkRequestPerformer: networkController, cache: cache)
    }()
    
    private var cancellables = Set<AnyCancellable>()
    private lazy var itemPath = OHPathForFile("Item.json", type(of: self))!
    private lazy var itemsPath = OHPathForFile("Items.json", type(of: self))!

    override func tearDown() {
        HTTPStubs.removeAllStubs()
        try? provider.cache?.removeAll()
        try? expiredProvider.cache?.removeAll()
        
        super.tearDown()
    }
    
    // MARK: - Item Provider Item Handler Tests

    func testProvideItem() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        provider.provide(request: request) { (result: Result<TestItem, ProviderError>) in
            switch result {
            case .success: break
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
        
    func testProvideItemReturnsCachedResult() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        provider.provide(request: request) { (result: Result<TestItem, ProviderError>) in
            switch result {
            case .success:
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true }) { _ in
                    fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
                }
                
                self.provider.provide(request: request) { (result: Result<TestItem, ProviderError>) in
                    switch result {
                    case .success:
                        break
                    case let .failure(error):
                        XCTFail("There should be no error: \(error)")
                    }
                    
                    expectation.fulfill()
                }
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemReturnsExpiredItemInBothCompletions() {
        let request = TestProviderRequest()
        let expectation = self.expectation(description: "The item will be returned in both closures.")
        expectation.expectedFulfillmentCount = 2
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        expiredProvider.provide(request: request) { (result: Result<TestItem, ProviderError>) in
            self.expiredProvider.provide(request: request, allowExpiredItem: true, itemHandler: { (result: Result<TestItem, ProviderError>) in
                switch result {
                case .success: expectation.fulfill()
                case .failure: break
                }
                
            })
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemFailure() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
        }
        
        provider.provide(request: request) { (result: Result<TestItem, ProviderError>) in
            switch result {
            case .success:
                XCTFail("There should be an error.")
                expectation.fulfill()
            case .failure:
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItems() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The items will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        provider.provideItems(request: request) { (result: Result<[TestItem], ProviderError>) in
            switch result {
            case let .success(items):
                XCTAssertEqual(items.count, 3)
                expectation.fulfill()
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsReturnsCachedResult() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        provider.provideItems(request: request) { (result: Result<[TestItem], ProviderError>) in
            switch result {
            case .success:
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true }) { _ in
                    fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
                }
                
                self.provider.provideItems(request: request) { (result: Result<[TestItem], ProviderError>) in
                    switch result {
                    case let .success(items):
                        XCTAssertEqual(items.count, 3)
                    case let .failure(error):
                        XCTFail("There should be no error: \(error)")
                    }
                    
                    expectation.fulfill()
                }
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsReturnsExpiredItemInBothCompletions() {
        let request = TestProviderRequest()
        let expectation = self.expectation(description: "The items will be returned in both closures.")
        expectation.expectedFulfillmentCount = 2
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }

        expiredProvider.provideItems(request: request) { (result: Result<[TestItem], ProviderError>) in
            self.expiredProvider.provideItems(request: request, allowExpiredItems: true, itemsHandler: { (result: Result<[TestItem], ProviderError>) in
                switch result {
                case let .success(items): XCTAssertEqual(items.count, 3)
                case .failure: XCTFail("This should not have failed.")
                }
                
                expectation.fulfill()
            })
        }
        
        wait(for: [expectation], timeout: 2)
    }

    func testProvideItemsReturnsPartialResponseUponFailure() {
        let request = TestProviderRequest()
        let expectation = self.expectation(description: "The provider will return a partial response.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }

        provider.provideItems(request: request) { (result: Result<[TestItem], ProviderError>) in
            
            try? self.provider.cache?.remove(forKey: "Hello 2")
            HTTPStubs.removeStub(originalStub)
            
            stub(condition: { _ in true}) { _ in
                fixture(filePath: self.itemPath, headers: nil)
            }
            
            self.provider.provideItems(request: request) { (result: Result<[TestItem], ProviderError>) in
                switch result {
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
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsDoesNotReturnPartialResponseUponFailureForExpiredItems() {
        let request = TestProviderRequest()
        let expectation = self.expectation(description: "The provider will return a partial response.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }

        expiredProvider.provideItems(request: request) { (result: Result<[TestItem], ProviderError>) in
            
            try? self.expiredProvider.cache?.remove(forKey: "Hello 2")
            HTTPStubs.removeStub(originalStub)
            
            stub(condition: { _ in true}) { _ in
                fixture(filePath: self.itemPath, headers: nil)
            }
            
            self.expiredProvider.provideItems(request: request) { (result: Result<[TestItem], ProviderError>) in
                switch result {
                case .success:
                    XCTFail("Should have received a decoding error.")
                case let .failure(error):
                    switch error {
                    case .decodingError: break
                    default: XCTFail("Should have received a decoding error.")
                    }
                }
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsFailure() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
        }
        
        provider.provideItems(request: request) { (result: Result<[TestItem], ProviderError>) in
            switch result {
            case .success:
                XCTFail("There should be an error.")
                expectation.fulfill()
            case .failure:
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemSkipsCacheOnPostRequest() {
        let key = "TestPostKey"
        let request = TestPostProviderRequest(key: key)
        
        let expectation = self.expectation(description: "The item will exist.")
        
        let testItem = TestItem(title: "Title")
        try? provider.cache?.write(item: testItem, forKey: key)
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("Item.json", type(of: self))!, headers: nil)
        }

        provider.provide(request: request) { (result: Result<TestItem, ProviderError>) in
            switch result {
            case let .success(item):
                XCTAssertNotEqual(item.title, testItem.title)
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    // MARK: - Item Provider Publisher Tests
    
    func testProvideItemPublisher() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        provider.provide(request: request)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { _ in }, receiveValue: { (item: TestItem) in
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemPublisherFailure() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        expectation.assertForOverFulfill = false
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
        }
        
        provider.provide(request: request)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { _ in expectation.fulfill() }, receiveValue: { (item: TestItem) in
                XCTFail("There should be no item.")
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemPublisherReturnsCachedResult() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        provider.provide(request: request)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .handleEvents(receiveOutput: { (_: TestItem) in
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true }) { _ in
                    fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
                }
            })
            .flatMap { _ -> AnyPublisher<TestItem, ProviderError> in
                self.provider.provide(request: request)
            }
            .sink(receiveCompletion: { _ in }, receiveValue: { (item: TestItem) in
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemPublisherPublishesExpiredItem() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        expectation.expectedFulfillmentCount = 2
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemPath, headers: nil)
        }
        
        expiredProvider.provide(request: request)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .flatMap { (_: TestItem) -> AnyPublisher<TestItem, ProviderError> in
                return self.expiredProvider.provide(request: request, allowExpiredItem: true)
            }
            .sink(receiveCompletion: { _ in }, receiveValue: { (item: TestItem) in
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsPublisher() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        provider.provideItems(request: request)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { _ in }, receiveValue: { (items: [TestItem]) in
                XCTAssertEqual(items.count, 3)
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsPublisherFailure() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
        }
        
        provider.provideItems(request: request)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { _ in expectation.fulfill() }, receiveValue: { (items: [TestItem]) in
                XCTFail("There should be no items.")
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsPublisherReturnsCachedResult() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        provider.provideItems(request: request)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .handleEvents(receiveOutput: { (_: [TestItem]) in
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true }) { _ in
                    fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
                }
            })
            .flatMap { _ -> AnyPublisher<[TestItem], ProviderError> in
                self.provider.provideItems(request: request)
            }
            .sink(receiveCompletion: { _ in }, receiveValue: { (items: [TestItem]) in
                XCTAssertEqual(items.count, 3)
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsPublisherPublishesExpiredItems() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        expectation.expectedFulfillmentCount = 2
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }
        
        expiredProvider.provideItems(request: request)
            .receive(on: DispatchQueue.main)
            .flatMap { (_: [TestItem]) -> AnyPublisher<[TestItem], ProviderError> in
                return self.expiredProvider.provideItems(request: request, allowExpiredItems: true)
            }
            .sink(receiveCompletion: { _ in }, receiveValue: { (items: [TestItem]) in
                XCTAssertEqual(items.count, 3)
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsPublisherReturnsPartialResponseUponFailure() {
        let request = TestProviderRequest()
        let expectation = self.expectation(description: "The provider will return a partial response.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }

        provider.provideItems(request: request)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { _ in
                try? self.provider.cache?.remove(forKey: "Hello 2")
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true}) { _ in
                    fixture(filePath: self.itemPath, headers: nil)
                }
            })
            .flatMap { (_: [TestItem]) -> AnyPublisher<[TestItem], ProviderError> in
                self.provider.provideItems(request: request, allowExpiredItems: true)
            }
            .sink(receiveCompletion: { result in
                switch result {
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
                        
                    default: XCTFail("This should have resulted in a partial retrieval.")
                    }
                case .finished:
                    XCTFail("This should not have finished.")
                }
                
                expectation.fulfill()
            }, receiveValue: { (_: [TestItem]) in
                XCTFail("No values should have been received.")
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsPublisherDoesNotReturnPartialResponseUponFailureForExpiredItems() {
        let request = TestProviderRequest()
        let expectation = self.expectation(description: "The provider will return a partial response.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: self.itemsPath, headers: nil)
        }

        expiredProvider.provideItems(request: request)
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { _ in
                try? self.expiredProvider.cache?.remove(forKey: "Hello 2")
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true}) { _ in
                    fixture(filePath: self.itemPath, headers: nil)
                }
            })
            .flatMap { (_: [TestItem]) -> AnyPublisher<[TestItem], ProviderError> in
                self.expiredProvider.provideItems(request: request)
            }
            .sink(receiveCompletion: { result in
                switch result {
                case let .failure(error):
                    switch error {
                    case .decodingError: break
                    default:
                        XCTFail("This should have resulted in a decoding error.")
                    }
                case .finished:
                    XCTFail("This should not have finished.")
                }
                
                expectation.fulfill()
            }, receiveValue: { (items: [TestItem]) in
                XCTFail("No values should have been received.")
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
}
