//
//  PerformanceCore.swift
//  RecoverySignal2
//
//  The maths behind "how will today's session go", with no app types in it so
//  it can be tested on its own. One person, a few dozen sessions: so a small,
//  heavily regularised linear model, and an honest test of whether it beats
//  the obvious guess before anyone is shown a forecast.
//
//  • Ridge regression on standardised features. Ridge shrinks every effect
//    towards zero, which is what you want with little data and noisy labels.
//  • Missing readings are treated as "average" rather than dropping the session.
//  • Forward chaining: to score the model, it is fitted only on sessions before
//    each one it then predicts, the way it would really be used. Never a
//    shuffled split, which would let it peek at the future.
//  • The yardstick is the better of two plain guesses: "same as your last three
//    sessions" and "your long-run average". Beating only the first is too easy,
//    because on pure noise the last three sessions are a poor guess, so a model
//    that has learned nothing can still look good against it. A forecast is
//    only switched on if it beats both.
//

import Foundation

nonisolated enum PerformanceCore {

    struct Fit {
        var means: [Double]
        var sds: [Double]
        var beta: [Double]
        var intercept: Double
        /// Features that had too little variation or too few readings to use.
        var used: [Bool]
    }

    /// Fits ridge regression. Rows are sessions, columns are features; nil is a missing reading.
    static func fit(_ rows: [[Double?]], _ y: [Double], lambda: Double, minCoverage: Double = 0.6) -> Fit? {
        guard let width = rows.first?.count, rows.count == y.count, rows.count >= 8, width > 0 else { return nil }
        let n = Double(rows.count)

        var means = [Double](repeating: 0, count: width)
        var sds = [Double](repeating: 1, count: width)
        var used = [Bool](repeating: false, count: width)
        for j in 0..<width {
            let observed = rows.compactMap { $0[j] }
            guard Double(observed.count) / n >= minCoverage, observed.count >= 8 else { continue }
            let m = observed.reduce(0, +) / Double(observed.count)
            let variance = observed.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(observed.count - 1)
            guard variance > 1e-12 else { continue }
            means[j] = m
            sds[j] = variance.squareRoot()
            used[j] = true
        }
        let columns = (0..<width).filter { used[$0] }
        guard !columns.isEmpty else { return nil }

        let yMean = y.reduce(0, +) / n
        let k = columns.count
        var xtx = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
        var xty = [Double](repeating: 0, count: k)
        for (r, row) in rows.enumerated() {
            let z = columns.map { j in row[j].map { ($0 - means[j]) / sds[j] } ?? 0 }
            for a in 0..<k {
                xty[a] += z[a] * (y[r] - yMean)
                for b in 0..<k { xtx[a][b] += z[a] * z[b] }
            }
        }
        for a in 0..<k { xtx[a][a] += lambda }
        guard let solved = solve(xtx, xty) else { return nil }

        var beta = [Double](repeating: 0, count: width)
        for (index, j) in columns.enumerated() { beta[j] = solved[index] }
        return Fit(means: means, sds: sds, beta: beta, intercept: yMean, used: used)
    }

    /// Standardised value of each feature for one row (0 where missing or unused).
    static func standardised(_ fit: Fit, _ row: [Double?]) -> [Double] {
        (0..<fit.beta.count).map { j in
            guard fit.used[j], let v = row[j] else { return 0 }
            return (v - fit.means[j]) / fit.sds[j]
        }
    }

    static func predict(_ fit: Fit, _ row: [Double?]) -> Double {
        let z = standardised(fit, row)
        return fit.intercept + zip(z, fit.beta).reduce(0) { $0 + $1.0 * $1.1 }
    }

    struct Evaluation {
        let tested: Int
        let modelError: Double
        let baselineError: Double
        /// Spread of the model's misses, for the ± shown with a forecast.
        let residualSD: Double

        var improvement: Double { baselineError > 0 ? 1 - modelError / baselineError : 0 }
    }

    /// Forward-chaining test: fit on everything before each session, predict it, and
    /// compare the miss with the better of two plain guesses: the mean of the
    /// previous three sessions, and the mean of all earlier ones.
    static func evaluate(_ rows: [[Double?]], _ y: [Double], lambda: Double, minTrain: Int = 30) -> Evaluation? {
        guard rows.count > minTrain + 5 else { return nil }
        var modelMisses: [Double] = []
        var recentMisses: [Double] = []
        var averageMisses: [Double] = []
        for i in minTrain..<rows.count {
            guard let f = fit(Array(rows[0..<i]), Array(y[0..<i]), lambda: lambda) else { continue }
            let last3 = y[(i - 3)..<i]
            modelMisses.append(y[i] - predict(f, rows[i]))
            recentMisses.append(y[i] - last3.reduce(0, +) / 3)
            averageMisses.append(y[i] - y[0..<i].reduce(0, +) / Double(i))
        }
        guard modelMisses.count >= 10 else { return nil }
        let mae = { (values: [Double]) in values.map(abs).reduce(0, +) / Double(values.count) }
        let baselineError = min(mae(recentMisses), mae(averageMisses))
        let mean = modelMisses.reduce(0, +) / Double(modelMisses.count)
        let sd = (modelMisses.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(modelMisses.count - 1)).squareRoot()
        return Evaluation(tested: modelMisses.count, modelError: mae(modelMisses), baselineError: baselineError, residualSD: sd)
    }

    /// Pearson correlation over the rows where both values exist; nil under `minPairs`.
    static func correlation(_ xs: [Double?], _ ys: [Double], minPairs: Int = 10) -> (r: Double, n: Int)? {
        let pairs = zip(xs, ys).compactMap { x, y in x.map { ($0, y) } }
        guard pairs.count >= minPairs else { return nil }
        let n = Double(pairs.count)
        let mx = pairs.reduce(0) { $0 + $1.0 } / n
        let my = pairs.reduce(0) { $0 + $1.1 } / n
        let sxy = pairs.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let sxx = pairs.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
        let syy = pairs.reduce(0) { $0 + ($1.1 - my) * ($1.1 - my) }
        guard sxx > 1e-12, syy > 1e-12 else { return nil }
        return (sxy / (sxx * syy).squareRoot(), pairs.count)
    }

    // MARK: Linear solve (Gaussian elimination with partial pivoting)

    private static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var m = a
        var v = b
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { abs(m[$0][col]) < abs(m[$1][col]) }), abs(m[pivot][col]) > 1e-12 else { return nil }
            m.swapAt(col, pivot)
            v.swapAt(col, pivot)
            for row in (col + 1)..<n where row < n {
                let factor = m[row][col] / m[col][col]
                for c in col..<n { m[row][c] -= factor * m[col][c] }
                v[row] -= factor * v[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = v[row]
            for c in (row + 1)..<n where c < n { sum -= m[row][c] * x[c] }
            x[row] = sum / m[row][row]
        }
        return x
    }
}
