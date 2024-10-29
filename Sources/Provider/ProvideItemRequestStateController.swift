//
//  ProvideItemRequestStateController.swift
//  Provider
//
//  Created by Twig on 8/30/22.
//  Copyright © 2022 Lickability. All rights reserved.
//

import Foundation
import Networking
import Persister
@preconcurrency import Combine

/// A class responsible for representing the state and value of a provider item request being made.
public final class ProvideItemRequestStateController<Item: Providable>: Sendable {
    
    /// The state of a provider request's lifecycle.
    public enum ProvideItemRequestState {
        
        /// A request that has not yet been started.
        case notInProgress
        
        /// A request that has been started, but not completed.
        case inProgress
        
        /// A request that has been completed with an associated result.
        case completed(Result<Item, ProviderError>)
                
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
            case let .completed(result):
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
        
        /// The `Item` for a completed request if one exists.
        public var completedItem: Item? {
            switch self {
            case .notInProgress, .inProgress:
                return nil
            case let .completed(result):
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
            return completedItem != nil
        }
        
        /// A `Bool` indicating if the request has finished with an error.
        public var didFail: Bool {
            return completedError != nil
        }
    }
    
    /// A `Publisher` that can be subscribed to in order to receive updates about the status of a request.
    public let publisher: AnyPublisher<ProvideItemRequestState, Never>
    
    private let provider: Provider
    private let providerStatePublisher: PassthroughSubject<ProvideItemRequestState, Never>
    private let cancellablesQueue = DispatchQueue(label: "com.lickability.Provider.ProvideItemRequestStateController.cancellable.queue")
    nonisolated(unsafe) private var cancellables = Set<AnyCancellable>()
    
    /// Initializes the `ProvideItemRequestStateController` with the specified parameters.
    /// - Parameter provider: The `Provider` used to provide a response from.
    public init(provider: Provider) {
        self.provider = provider
        self.providerStatePublisher = PassthroughSubject<ProvideItemRequestState, Never>()
        self.publisher = providerStatePublisher.prepend(.notInProgress).eraseToAnyPublisher()
    }
            
    /// Sends a request with the specified parameters to provide back an item.
    /// - Parameters:
    ///   - request: The request to send.
    ///   - decoder: The decoder to use to decode a successful response.
    ///   - scheduler: The scheduler to receive the result on.
    ///   - providerBehaviors: Additional `ProviderBehavior`s to use.
    ///   - requestBehaviors: Additional `RequestBehavior`s to append to the request.
    ///   - allowExpiredItem: A `Bool` indicating if the provider should be allowed to return an expired item.
    ///   - retryCount: The number of retries that should be made, if the request failed.
    @MainActor
    public func provide(request: any ProviderRequest, decoder: ItemDecoder, scheduler: some Scheduler = DispatchQueue.main, providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], allowExpiredItem: Bool = false, retryCount: Int = 2) {
        providerStatePublisher.send(.inProgress)

        let cancellable = provider.provide(request: request, decoder: decoder, providerBehaviors: providerBehaviors, requestBehaviors: requestBehaviors, allowExpiredItem: allowExpiredItem)
            .retry(retryCount)
            .mapAsResult()
            .receive(on: scheduler)
            .sink { [providerStatePublisher] result in
                providerStatePublisher.send(.completed(result))
            }
        
        _ = cancellablesQueue.sync {
            cancellables.insert(cancellable)
        }
    }
        
    /// Resets the state of the `providerStatePublisher` and cancels any in flight requests that may be ongoing. Cancellation is not guaranteed, and requests that are near completion may end up finishing, despite being cancelled.
    public func resetState() {
        cancellablesQueue.sync {
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
        }

        providerStatePublisher.send(.notInProgress)
    }
}
