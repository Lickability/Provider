//
//  FetchPolicy.swift
//  Provider
//
//  Created by Michael Amundsen on 6/30/25.
//  Copyright © 2025 Lickability. All rights reserved.
//

import Foundation

/// The policy for how the provider checks the cache and/or the network for items.
public enum FetchPolicy: Sendable {
    
    /// Only request from the network if we don't have items in the cache. If items exist in the cache and are expired, it returns items from the cache and the network.
    case returnFromCacheElseNetwork
    
    /// Return items from the cache, then request from the network for updated items.
    case returnFromCacheAndNetwork
}
