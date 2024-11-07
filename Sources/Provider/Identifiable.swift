//
//  Identifiable.swift
//  Networker
//
//  Created by Twig on 5/10/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation

/// The type under which items are retrieved and persisted.
public typealias Key = String

/// Describes a type that can be uniquely identified by a `Key`.
public protocol Identifiable: Sendable {
    
    /// The key used to uniquely identify the receiver.
    var identifier: Key { get }
}
