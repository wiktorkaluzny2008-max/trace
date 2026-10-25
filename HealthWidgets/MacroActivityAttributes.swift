//
//  MacroActivityAttributes.swift
//  HealthWidgets (widget extension)
//
//  Must stay identical to the definition in the app's MacroLiveActivity.swift.
//

import Foundation
import ActivityKit

nonisolated struct MacroActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var caloriesEaten: Int
        var caloriesTarget: Int
        var proteinEaten: Int
        var proteinTarget: Int
        var carbsEaten: Int = 0
        var carbsTarget: Int = 0
        var fatEaten: Int = 0
        var fatTarget: Int = 0
        var bedtime: Date? = nil
        var updatedAt: Date
    }

    var goalLabel: String
}
