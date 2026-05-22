#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

struct SuccessScreen: View {
    @ObservedObject var flow: CaptureFlow
    var onCaptureAnother: () -> Void
    var onDone: () -> Void
    @State private var entered: Bool = false

    var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                savedChipStack
                    .frame(width: 260, height: 130)

                HeadlineWithSwipe(
                    prefix: "",
                    accent: countLabel,
                    suffix: " saved.",
                    font: Theme.Typography.serif(30),
                    lineSpacing: 2
                )
                .multilineTextAlignment(.center)
                .padding(.top, 32)
                .padding(.horizontal, 32)

                Text("On their way to your Readwise library.")
                    .font(Theme.Typography.serif(15))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .padding(.top, 12)

                Spacer()

                VStack(spacing: 8) {
                    Button(action: onCaptureAnother) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera")
                            Text("Capture another")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Done", action: onDone)
                        .buttonStyle(GhostButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 38)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.05)) {
                entered = true
            }
        }
    }

    private var countLabel: String {
        let n = flow.lastSavedHighlights.count
        return "\(n) highlight\(n == 1 ? "" : "s")"
    }

    private var savedChipStack: some View {
        let items = Array(flow.lastSavedHighlights.prefix(2).enumerated())
        return ZStack {
            ForEach(items, id: \.offset) { idx, hi in
                savedChip(hi)
                    .rotationEffect(.degrees(idx == 0 ? -3 : 2))
                    .offset(x: idx == 0 ? -12 : 6, y: idx == 0 ? -10 : 8)
                    .scaleEffect(entered ? 1 : 0.7)
                    .opacity(entered ? 1 : 0)
                    .zIndex(Double(idx))
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.7).delay(Double(idx) * 0.08),
                        value: entered
                    )
            }
            if items.isEmpty {
                savedChip(CaptureFlow.EditableHighlight(text: "Saved."))
            }
        }
    }

    private func savedChip(_ highlight: CaptureFlow.EditableHighlight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Palette.success)
                Text(headerLabel(for: highlight))
                    .font(Theme.Typography.mono(9, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Theme.Palette.muted)
            }
            Text(highlight.trimmedText)
                .font(Theme.Typography.serif(12))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Theme.Palette.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)
    }

    private func headerLabel(for highlight: CaptureFlow.EditableHighlight) -> String {
        if let p = highlight.parsedPageNumber() {
            return "SAVED · P.\(p)"
        }
        return "SAVED"
    }
}
#endif
