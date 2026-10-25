//
//  Stats.swift
//  RecoverySignal2
//
//  Small statistics toolkit shared by the analytics models. Everything here is
//  a pure function over [Double] so it can be reasoned about (and corrected)
//  without touching HealthKit or SwiftData.
//

import Foundation

enum Stats {

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (n−1). Nil for fewer than two points.
    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        let sumSquares = values.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (sumSquares / Double(values.count - 1)).squareRoot()
    }

    /// Exponentially weighted moving average, oldest value first.
    /// `span` maps to the usual α = 2/(span+1).
    static func ewmaSeries(_ values: [Double], span: Int) -> [Double] {
        guard !values.isEmpty, span > 0 else { return [] }
        let alpha = 2.0 / (Double(span) + 1.0)
        var out: [Double] = []
        var current = values[0]
        out.append(current)
        for value in values.dropFirst() {
            current = alpha * value + (1 - alpha) * current
            out.append(current)
        }
        return out
    }

    static func ewma(_ values: [Double], span: Int) -> Double? {
        ewmaSeries(values, span: span).last
    }

    /// OLS slope of `y` against its own index — i.e. change per step.
    static func slope(_ y: [Double]) -> Double? {
        guard y.count >= 3 else { return nil }
        let x = (0..<y.count).map(Double.init)
        guard let mx = mean(x), let my = mean(y) else { return nil }
        var num = 0.0, den = 0.0
        for i in 0..<y.count {
            num += (x[i] - mx) * (y[i] - my)
            den += (x[i] - mx) * (x[i] - mx)
        }
        guard den != 0 else { return nil }
        return num / den
    }

    static func zScore(_ value: Double, in baseline: [Double]) -> Double? {
        guard let m = mean(baseline), let sd = standardDeviation(baseline), sd > 0 else { return nil }
        return (value - m) / sd
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 3,
              let mx = mean(x), let my = mean(y) else { return nil }
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in 0..<x.count {
            let a = x[i] - mx
            let b = y[i] - my
            num += a * b
            dx += a * a
            dy += b * b
        }
        let den = (dx * dy).squareRoot()
        guard den > 0 else { return nil }
        return num / den
    }

    /// Rank correlation — more robust to the outliers real health data is full of.
    static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 3 else { return nil }
        return pearson(ranks(x), ranks(y))
    }

    /// Ranks with ties averaged.
    static func ranks(_ values: [Double]) -> [Double] {
        let indexed = values.enumerated().sorted { $0.element < $1.element }
        var result = [Double](repeating: 0, count: values.count)
        var i = 0
        while i < indexed.count {
            var j = i
            while j + 1 < indexed.count, indexed[j + 1].element == indexed[i].element { j += 1 }
            let averageRank = Double(i + j) / 2.0 + 1.0
            for k in i...j { result[indexed[k].offset] = averageRank }
            i = j + 1
        }
        return result
    }

    /// Two-tailed p-value for a correlation, via the Fisher z transform.
    /// Approximate, and deliberately treated as exploratory by callers.
    static func correlationPValue(r: Double, n: Int) -> Double? {
        guard n > 3, abs(r) < 1 else { return nil }
        let z = atanh(r) * (Double(n - 3)).squareRoot()
        return 2 * (1 - normalCDF(abs(z)))
    }

    static func normalCDF(_ x: Double) -> Double {
        0.5 * (1 + erf(x / 2.0.squareRoot()))
    }
}
