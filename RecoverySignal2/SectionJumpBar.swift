import SwiftUI

/// A compact, persistent shortcut row for long reading screens.
struct SectionJumpBar: View {
    let sections: [String]
    let proxy: ScrollViewProxy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastJump: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections, id: \.self) { section in
                    Button {
                        if reduceMotion {
                            proxy.scrollTo(section, anchor: .top)
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(section, anchor: .top)
                            }
                        }
                        lastJump = section
                    } label: {
                        Text(LocalizedStringKey(section))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(lastJump == section ? Theme.textPrimary : Theme.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(lastJump == section ? Theme.surfaceRaised : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(lastJump == section ? .isSelected : [])
                    .accessibilityHint("Jump to this section")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .background(Theme.background)
        .sensoryFeedback(.selection, trigger: lastJump)
    }
}
