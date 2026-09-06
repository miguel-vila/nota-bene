#if DEBUG && canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// "REC · EVAL" capsule shown top-right on every capture-flow screen while an
/// eval-recording streak is active: the master flag (`evalCaptureEnabled`) is
/// on AND the per-capture choice (`AppState.evalRecordThisCapture`, remembered
/// across captures within a session) is on. Static, no animation.
///
/// The whole file compiles out of Release builds, so it can never render in
/// a shipped binary.
struct EvalRecordingBadge: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(EvalPreferenceKey.evalCaptureEnabled) private var masterEnabled: Bool = false

    var body: some View {
        if masterEnabled && state.evalRecordThisCapture {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                Text("REC · EVAL")
                    .font(Theme.Typography.mono(11))
                    .tracking(0.4)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Eval capture recording")
        }
    }
}

#endif
