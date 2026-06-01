#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Adds the eval-recording badge as a top-right overlay. No-op in non-eval
    /// builds — the `#if EVAL_CAPTURE` branch is the only thing that references
    /// `EvalRecordingBadge`, which itself only compiles under that flag.
    @ViewBuilder
    func evalRecordingBadge(topPadding: CGFloat = 14, trailingPadding: CGFloat = 14) -> some View {
        #if EVAL_CAPTURE && canImport(UIKit)
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
