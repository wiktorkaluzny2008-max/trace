//
//  PlateCalculator.swift
//  RecoverySignal2
//
//  Which plates to load per side for a target weight. Greedy from the
//  largest plate down — the standard, simplest way to hit a number with a
//  fixed set of denominations, and gym plates are exactly that kind of set.
//

import SwiftUI

enum PlateCalculator {
    static let standardPlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    static let barWeights: [Double] = [20, 15, 10, 7.5]

    struct Result {
        let perSide: [Double]
        let achieved: Double
        /// How far `achieved` falls short of the target, if the plates on hand can't hit it exactly.
        let shortfall: Double
    }

    static func calculate(target: Double, barWeight: Double, availablePlates: [Double] = standardPlatesKg) -> Result {
        let perSideTarget = max((target - barWeight) / 2, 0)
        var remaining = perSideTarget
        var chosen: [Double] = []
        for plate in availablePlates.sorted(by: >) where plate > 0 {
            while remaining + 0.001 >= plate {
                chosen.append(plate)
                remaining -= plate
            }
        }
        let achieved = barWeight + (perSideTarget - remaining) * 2
        return Result(perSide: chosen, achieved: achieved, shortfall: max(target - achieved, 0))
    }
}

struct PlateCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var target: Double?
    @AppStorage("plateCalc.barWeight") private var barWeight = 20.0

    init(target: Double? = nil) {
        _target = State(initialValue: target)
    }

    private var result: PlateCalculator.Result? {
        guard let target, target > 0 else { return nil }
        return PlateCalculator.calculate(target: target, barWeight: barWeight)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Target weight")
                        Spacer()
                        LiveNumberField("kg", value: $target, fractionDigits: 2)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 90)
                        Text(verbatim: "kg").foregroundStyle(Theme.textTertiary)
                    }
                    Picker("Bar", selection: $barWeight) {
                        ForEach(PlateCalculator.barWeights, id: \.self) { Text(verbatim: "\(DetailFormat.decimal($0)) kg").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if let result {
                    Section {
                        barDiagram(result)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                        if result.perSide.isEmpty {
                            Text("Just the bar.")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        } else {
                            Text(result.perSide.map { DetailFormat.decimal($0) }.joined(separator: " + ") + " kg per side")
                                .font(.system(size: 17, weight: .semibold))
                                .monospacedDigit()
                        }
                        if result.shortfall > 0.01 {
                            Label("Closest with these plates: \(DetailFormat.decimal(result.achieved)) kg — \(DetailFormat.decimal(result.shortfall)) kg short of target.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(Theme.warn)
                        }
                    } header: {
                        Text("Load per side")
                    } footer: {
                        Text("Standard set: 25 · 20 · 15 · 10 · 5 · 2.5 · 1.25 kg.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Plate calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func barDiagram(_ result: PlateCalculator.Result) -> some View {
        let plates = result.perSide.sorted(by: >)
        return HStack(spacing: 1) {
            ForEach(Array(plates.reversed().enumerated()), id: \.offset) { _, plate in plateBlock(plate) }
            Rectangle().fill(Theme.textTertiary).frame(width: 44, height: 8)
            ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in plateBlock(plate) }
        }
    }

    private func plateBlock(_ kg: Double) -> some View {
        let height = 30 + min(kg, 25) * 2.2
        return RoundedRectangle(cornerRadius: 3)
            .fill(plateColor(kg))
            .frame(width: 14, height: height)
            .overlay(alignment: .bottom) {
                Text(DetailFormat.decimal(kg))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            }
    }

    private func plateColor(_ kg: Double) -> Color {
        switch kg {
        case 25: Theme.bad
        case 20: Theme.accent
        case 15: Theme.warn
        case 10: Theme.good
        case 5:  Theme.textSecondary
        default: Theme.textTertiary
        }
    }
}
