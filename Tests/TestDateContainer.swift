//
//  TestDateContainer.swift
//  ProviderTests
//
//  Created by Michael Liberatore on 4/1/25.
//  Copyright © 2025 Lickability. All rights reserved.
//

import Foundation
import Provider

struct TestDateContainer: Providable {
    let identifier: String
    let startDate: Date
    let endDate: Date
}
