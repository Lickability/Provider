//
//  TestProviderRequest.swift
//  ProviderTests
//
//  Created by Ashli Rankin on 1/16/24.
//  Copyright © 2024 Lickability. All rights reserved.
//

import Foundation
import Provider

struct TestProviderRequest: ProviderRequest {
    
    let persistenceKey: Key?
    var baseURL: URL { URL(string: "https://www.google.com")! }
    var path: String { "" }

    init(key: Key = "TestExample") {
        self.persistenceKey = key
    }
}
