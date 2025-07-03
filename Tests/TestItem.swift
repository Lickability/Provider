//
//  TestItem.swift
//  ProviderTests
//
//  Created by Ashli Rankin on 1/16/24.
//  Copyright © 2024 Lickability. All rights reserved.
//

import Foundation
import Provider

struct TestItem: Providable, Equatable {
    var identifier: Key { return title }
    
    let title: String
}
