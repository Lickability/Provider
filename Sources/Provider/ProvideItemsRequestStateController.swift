//
//  ProvideItemsRequestStateController.swift
//  Provider
//
//  Created by Twig on 8/30/22.
//  Copyright © 2022 Lickability. All rights reserved.
//

import Foundation
import Networking
import Persister
@preconcurrency import Combine

/// A class responsible for representing the state and value of a provider items request being made.
@MainActor
public final class ProvideItemsRequestStateController<Item: Providable>: Sendable {
    
    /// The state of a provider request's lifecycle.
    public enum ProvideItemsRequestState {
        
        /// A request that has not yet been started.
        case notInProgress
        
        /// A request that has been started, but not completed.
        case inProgress
                
        /// A request that has been completed with an associated result.
        case completed(Result<[Item], ProviderError>, Bool)
        
        /// A `Bool` representing if a request is in progress.
        public var isInProgress: Bool {
            switch self {
            case .notInProgress, .completed:
                return false
            case .inProgress:
                return true
            }
        }
        
        /// The completed `LocalizedError`, if one exists.
        public var completedError: LocalizedError? {
            switch self {
            case .notInProgress, .inProgress:
                return nil
            case let .completed(result, _):
                switch result {
                case .success:
                    return nil
                case let .failure(error):
                    switch error {
                    case let .networkError(networkError):
                        return networkError
                    case let .decodingError(error):
                        return error as? LocalizedError
                    case let .partialRetrieval(_, _, providerError):
                        return providerError
                    case let .persistenceError(error):
                        return error
                    }
                }
            }
        }
        
        /// The completed `LocalizedError`, if one exists.
        public var completedErrorInformation: ErrorInformation? {
            switch self {
            case .notInProgress, .inProgress:
                return nil
            case let .completed(result, flag):
                switch result {
                case .success:
                    return nil
                case let .failure(error):
                    switch error {
                    case let .networkError(networkError):
                        return ErrorInformation(error: networkError, flag: flag)
                    case let .decodingError(error):
                        if let error = error as? LocalizedError {
                            return ErrorInformation(error: error as LocalizedError, flag: flag)
                        }
                        
                        return nil
                    case let .partialRetrieval(_, _, providerError):
                        return ErrorInformation(error: providerError, flag: flag)
                    case let .persistenceError(error):
                        return ErrorInformation(error: error, flag: flag)
                    }
                }
            }
        }
                
        /// A list of `Item`s for the completed request `Item` if they exist.
        public var completedItems: [Item]? {
            switch self {
            case .notInProgress, .inProgress:
                return nil
            case let .completed(result, _):
                switch result {
                case let .success(response):
                    return response
                case .failure:
                    return nil
                }
            }
        }
        
        /// A `Bool` indicating if the request has finished successfully.
        public var didSucceed: Bool {
            return completedItems != nil
        }
        
        /// A `Bool` indicating if the request has finished with an error.
        public var didFail: Bool {
            return completedError != nil
        }
    }
    
    /// A `Publisher` that can be subscribed to in order to receive updates about the status of a request.
    public let publisher: AnyPublisher<ProvideItemsRequestState, Never>
    
    private let provider: Provider
    private let providerStatePublisher: PassthroughSubject<ProvideItemsRequestState, Never>
    private var cancellables = Set<AnyCancellable>()
    
    /// Initializes the `ProvideItemsRequestStateController` with the specified parameters.
    /// - Parameter provider: The `Provider` used to provide a response from.
    public init(provider: Provider) {
        self.provider = provider
        self.providerStatePublisher = PassthroughSubject<ProvideItemsRequestState, Never>()
        self.publisher = providerStatePublisher.prepend(.notInProgress).eraseToAnyPublisher()
    }
    
    /// Sends a request with the specified parameters to provide back a list of items.
    /// - Parameters:
    ///   - request: The request to send.
    ///   - decoder: The decoder to use to decode a successful response.
    ///   - scheduler: The scheduler to receive the result on.
    ///   - providerBehaviors: Additional `ProviderBehavior`s to use.
    ///   - requestBehaviors: Additional `RequestBehavior`s to append to the request.
    ///   - allowExpiredItem: A `Bool` indicating if the provider should be allowed to return an expired item.
    ///   - retryCount: The number of retries that should be made, if the request failed.
    ///   - flag: A `Bool` flag that follows the request through completion.
    public func provideItems(request: any ProviderRequest, decoder: ItemDecoder, scheduler: some Scheduler = DispatchQueue.main, providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], allowExpiredItems: Bool = false, retryCount: Int = 2, flag: Bool = false) {
        providerStatePublisher.send(.inProgress)

        provider.provideItems(request: request, decoder: decoder, providerBehaviors: providerBehaviors, requestBehaviors: requestBehaviors, allowExpiredItems: allowExpiredItems)
            .retry(retryCount)
            .mapAsResult()
            .receive(on: scheduler)
            .sink { [providerStatePublisher] result in
                providerStatePublisher.send(.completed(result, flag))
            }
            .store(in: &cancellables)
    }
    
    /// Resets the state of the `providerStatePublisher` and cancels any in flight requests that may be ongoing. Cancellation is not guaranteed, and requests that are near completion may end up finishing, despite being cancelled.
    public func resetState() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        providerStatePublisher.send(.notInProgress)
    }
}
