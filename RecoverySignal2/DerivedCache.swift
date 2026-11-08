//
//  DerivedCache.swift
//  RecoverySignal2
//
//  Remembers expensive results computed from the health history (recovery
//  scores, maintenance, training load…) between redraws.
//
//  SwiftUI re-runs a screen's `body` for many reasons that have nothing to do
//  with the data: an animation frame, a sheet opening, a tab switch, a value
//  typed elsewhere. Today, Trends and Analysis used to recompute models over
//  the whole year of DailyMetrics every time, which made the app lag. Now each
//  result is computed once and reused until the data can actually have changed:
//  any SwiftData save (Health refresh, food log, day tag…) or any settings
//  change (UserDefaults) clears the cache.
//

import Foundation
import SwiftData

@MainActor
enum DerivedCache {
    private final class Box<T> {
        let value: T
        init(_ value: T) { self.value = value }
    }

    private static var store: [String: AnyObject] = [:]
    private static var observers: [NSObjectProtocol] = []

    /// Starts listening for saves and settings changes. Safe to call repeatedly.
    static func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        // Settings live in the standard defaults; the widget's app-group suite
        // is rewritten every minute and doesn't feed any of these results.
        let sources: [(Notification.Name, AnyObject?)] = [(ModelContext.didSave, nil),
                                                          (UserDefaults.didChangeNotification, UserDefaults.standard)]
        for (name, object) in sources {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { _ in
                MainActor.assumeIsolated { invalidate() }
            })
        }
    }

    /// Drops every remembered result; the next redraw recomputes.
    static func invalidate() {
        store.removeAll(keepingCapacity: true)
    }

    /// Returns the remembered result for `key`, computing it on first use.
    /// `inputs` describes the data the result came from (e.g. how many days
    /// a query returned), so a differently-shaped input never reuses it.
    static func value<T>(_ key: String, inputs: some Hashable, _ compute: () -> T) -> T {
        start()
        let fullKey = "\(key)#\(inputs.hashValue)"
        if let box = store[fullKey] as? Box<T> { return box.value }
        let value = compute()
        store[fullKey] = Box(value)
        return value
    }
}

/// What a cached result depends on: the size and span of the days it was
/// computed from. Cheap to build (no per-day reads beyond the two ends).
struct DaysSignature: Hashable {
    let count: Int
    let first: Date?
    let last: Date?

    init(_ days: [DailyMetrics]) {
        count = days.count
        first = days.first?.date
        last = days.last?.date
    }
}
