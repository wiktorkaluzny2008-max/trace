//
//  AppLanguage.swift
//  RecoverySignal2
//
//  English or Polish, chosen in Settings. iOS reads an app's language once at
//  launch, so switching saves the choice and closes the app; it reopens in the
//  new language. AI replies (narrative, meal ideas, meal scans) follow it too.
//

import Foundation
import UIKit

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case polish = "pl"

    var id: String { rawValue }

    /// Always shown in its own language so it's recognisable either way.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .polish:  "Polski"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .polish:  "🇵🇱"
        }
    }

    /// The language the app is actually running in right now.
    /// Reads the bundle only, so it's safe from any thread (food search runs off main).
    static var current: AppLanguage {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return preferred.hasPrefix("pl") ? .polish : .english
    }

    /// Saves the choice for the next launch.
    func apply() {
        UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    /// Instruction appended to every AI system prompt.
    static var aiInstruction: String {
        switch current {
        case .english: ""
        case .polish:
            "\n\nWrite every human-readable piece of text in Polish (natural, everyday Polish). Keep JSON keys, numbers and units exactly as specified."
        }
    }
}
