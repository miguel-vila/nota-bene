#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct RootView: View {
    @EnvironmentObject private var state: AppState

    public init() {}

    public var body: some View {
        switch state.phase {
        case .setup:
            SetupView()
        case .ready:
            BookSelectionView()
        }
    }
}
#endif
