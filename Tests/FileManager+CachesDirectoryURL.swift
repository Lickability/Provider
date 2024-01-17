//
//  FileManager+CachesDirectoryURL.swift
//  ProviderTests
//
//  Created by Ashli Rankin on 1/16/24.
//  Copyright © 2024 Lickability. All rights reserved.
//

import Foundation

extension FileManager {
    
    /// The caches directory `URL`.
    var cachesDirectoryURL: URL! { //swiftlint:disable:this implicitly_unwrapped_optional
        return urls(for: .cachesDirectory, in: .userDomainMask).first
    }
}
