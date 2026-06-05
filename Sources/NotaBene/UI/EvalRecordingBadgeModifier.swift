#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Adds the eval-recording badge as a top-right overlay. No-op in Release
    /// builds — the `#if DEBUG` branch is the only thing that references
    /// `EvalRecordingBadge`, which itself only compiles under DEBUG.
    @ViewBuilder
    func evalRecordingBadge(topPadding: CGFloat = 14, trailingPadding: CGFloat = 14) -> some View {
        #if DEBUG && canImport(UIKit)
        self.overlay(alignment: .topTrailing) {
            EvalRecordingBadge()
                .padding(.top, topPadding)
                .padding(.trailing, trailingPadding)
        }
        #else
        self
        #endif
    }
}

#endif
