//
//  FoodIcon.swift
//  RecoverySignal2
//
//  The blue "verified" tick for foods with reference-database values.
//

import SwiftUI

extension FoodItem {
    /// Values from a national reference database (Swiss FSVO, USDA FoodData
    /// Central) rather than a crowd-sourced label, a typical-value guess, an AI
    /// estimate or a hand entry.
    var isVerified: Bool { source == .swiss || source == .usda }
}

/// Blue seal for foods with verified reference values.
struct VerifiedTick: View {
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size))
            .foregroundStyle(Theme.accent)
            .accessibilityLabel(Text("Verified values"))
    }
}
