//
//  Item.swift
//  Stirling Money
//
//  Created by Shane Church on 11/1/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
