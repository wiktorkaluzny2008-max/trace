//
//  SwipeToDelete.swift
//  RecoverySignal2
//
//  Swipe a row left or right to delete it, like Mail — for rows that live in
//  a ScrollView rather than a List. A short swipe reveals a Delete button;
//  a long swipe deletes straight away.
//

import SwiftUI

struct SwipeToDelete: ViewModifier {
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @State private var crossedThreshold = false
    @State private var startOffset: CGFloat = 0

    private let revealWidth: CGFloat = 76
    private let deleteThreshold: CGFloat = 150

    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .offset(x: offset)
            .background {
                GeometryReader { geo in
                    ZStack(alignment: offset > 0 ? .leading : .trailing) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.bad)
                        Button(action: delete) {
                            Label("Delete", systemImage: "trash.fill")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: max(abs(offset), revealWidth), height: geo.size.height)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(crossedThreshold ? 1.2 : 1)
                    }
                    .opacity(offset == 0 ? 0 : 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        // Only horizontal swipes; vertical drags keep scrolling.
                        guard isDragging || abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        if !isDragging {
                            isDragging = true
                            startOffset = offset   // continue from a revealed button
                        }
                        offset = startOffset + value.translation.width
                        let crossed = abs(offset) > deleteThreshold
                        if crossed != crossedThreshold {
                            crossedThreshold = crossed
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        }
                    }
                    .onEnded { value in
                        guard isDragging else { return }
                        isDragging = false
                        if abs(offset) > deleteThreshold || abs(value.predictedEndTranslation.width) > 320 {
                            delete()
                        } else if abs(offset) > revealWidth * 0.6 {
                            withAnimation(.snappy) { offset = offset > 0 ? revealWidth : -revealWidth }
                        } else {
                            withAnimation(.snappy) { offset = 0 }
                        }
                        crossedThreshold = false
                    }
            )
            .onTapGesture {
                if offset != 0 { withAnimation(.snappy) { offset = 0 } }
            }
    }

    private func delete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy(duration: 0.25)) {
            offset = offset >= 0 ? 600 : -600
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.snappy) { onDelete() }
        }
    }
}

extension View {
    func swipeToDelete(_ onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(onDelete: onDelete))
    }
}
