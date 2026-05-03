#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import PhotosUI

public struct CaptureFlowContainer: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var flow: CaptureFlow
    @Environment(\.dismiss) private var dismiss

    public init(book: Book) {
        _flow = StateObject(wrappedValue: CaptureFlow(book: book))
    }

    public var body: some View {
        ZStack {
            switch flow.stage {
            case .capture:
                CaptureScreen(flow: flow) { dismiss() }
            case .preview:
                PreviewScreen(flow: flow)
            case .extracting:
                ExtractingScreen(flow: flow, providerLabel: state.provider.label, model: state.currentModel)
                    .task { await runExtraction() }
            case .extractionFailed:
                ExtractionFailedScreen(
                    flow: flow,
                    providerLabel: state.provider.label,
                    onRetry: { flow.retryExtraction() },
                    onTypeManually: { flow.skipExtraction() },
                    onBackToPhoto: { flow.backToPreview() },
                    onBackToBooks: { dismiss() }
                )
            case .review, .submitting:
                ReviewView(flow: flow) {
                    await submit()
                } onCancel: {
                    flow.reset()
                } onChangeBook: {
                    dismiss()
                }
            case .saved:
                SuccessScreen(
                    flow: flow,
                    onCaptureAnother: { flow.reset() },
                    onDone: { dismiss() }
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func runExtraction() async {
        guard !flow.images.isEmpty else {
            flow.skipExtraction()
            return
        }
        let providerLabel = state.provider.label
        guard let extractor = state.currentExtractor() else {
            flow.failExtraction("\(providerLabel) key missing — open Settings.")
            return
        }
        do {
            let result = try await extractor.extractHighlights(fromImages: flow.images, mimeType: "image/jpeg")
            flow.applyExtraction(result)
        } catch ExtractionError.invalidKey {
            flow.failExtraction("\(providerLabel) key rejected — update it in Settings.")
        } catch ExtractionError.requestFailed(let status, let body) {
            let detail = state.debugMode ? "\n\n\(body.isEmpty ? "(empty body)" : body)" : ""
            flow.failExtraction("\(providerLabel) returned HTTP \(status).\(detail)")
        } catch ExtractionError.missingContent(let payload) {
            let detail = state.debugMode ? "\n\nResponse:\n\(payload.isEmpty ? "(empty)" : payload)" : ""
            flow.failExtraction("\(providerLabel) response had no extractable content.\(detail)")
        } catch ExtractionError.decoding(let reason, let payload) {
            let detail = state.debugMode ? "\n\nResponse:\n\(payload.isEmpty ? "(empty)" : payload)" : ""
            flow.failExtraction("Couldn't parse \(providerLabel) response: \(reason).\(detail)")
        } catch {
            flow.failExtraction("Extraction failed: \(error.localizedDescription)")
        }
    }

    private func submit() async {
        guard let client = state.currentReadwiseClient() else {
            flow.lastError = "Readwise key missing — open Settings."
            return
        }
        let inputs = flow.savableHighlights.map {
            ReadwiseClient.HighlightInput(
                text: $0.trimmedText,
                title: flow.book.title,
                author: flow.book.author,
                pageNumber: $0.parsedPageNumber(),
                note: $0.noteForSubmission
            )
        }
        guard !inputs.isEmpty else { return }
        let snapshot = flow.savableHighlights
        flow.stage = .submitting
        do {
            try await client.createHighlights(inputs)
            flow.lastError = nil
            flow.markSaved(snapshot)
        } catch ReadwiseError.invalidToken {
            flow.lastError = "Readwise token rejected — update it in Settings."
            flow.stage = .review
        } catch ReadwiseError.requestFailed(let status, let body) {
            let detail = state.debugMode ? "\n\n\(body.isEmpty ? "(empty body)" : body)" : ""
            flow.lastError = "Readwise returned HTTP \(status).\(detail)"
            flow.stage = .review
        } catch {
            flow.lastError = "Submit failed: \(error.localizedDescription)"
            flow.stage = .review
        }
    }
}

// MARK: - Capture screen

private struct CaptureScreen: View {
    @ObservedObject var flow: CaptureFlow
    var onChangeBook: () -> Void
    @State private var captureToken: UUID?
    @State private var pickerItem: PhotosPickerItem?
    @State private var cameraError: String?

    var body: some View {
        ZStack {
            Theme.Palette.cameraBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                viewport
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer()

                if let cameraError {
                    Text(cameraError)
                        .font(Theme.Typography.sans(13))
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.red)
                        .padding(.bottom, 12)
                }

                bottomControls
                    .padding(.horizontal, 40)
                    .padding(.bottom, 56)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button { onChangeBook() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()

            Button { onChangeBook() } label: {
                HStack(spacing: 8) {
                    Text("book·")
                        .font(.system(size: 12, weight: .regular, design: .serif).italic())
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(flow.book.title)
                        .font(Theme.Typography.sans(13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Color.white.opacity(0.12), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
            // balance the back button's width
            Color.clear.frame(width: 36, height: 36)
        }
        .frame(height: 48)
    }

    private var viewport: some View {
        ZStack(alignment: .topLeading) {
            CameraView(
                onCapture: { data in flow.acceptPhoto(data) },
                onError: { cameraError = $0 },
                captureToken: $captureToken
            )
            .background(Theme.Palette.cameraSurface)

            ReticleCorners()

            if flow.images.count > 0 {
                pageCountChip
                    .padding(.leading, 14)
                    .padding(.top, 14)
            }

            VStack {
                Spacer()
                Text("Frame the highlighted lines in the whole page.\nInclude the page number if you want to capture it.")
                    .font(.system(size: 13, weight: .regular, design: .serif).italic())
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var pageCountChip: some View {
        Text("PAGE \(flow.images.count + 1) / \(CaptureFlow.maxPagesPerCapture)")
            .font(Theme.Typography.mono(11))
            .tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var bottomControls: some View {
        HStack {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .onChange(of: pickerItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self) {
                        flow.acceptPhoto(data)
                    }
                    pickerItem = nil
                }
            }

            Spacer()

            Button {
                captureToken = UUID()
            } label: {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4)
                    Circle().fill(Color.white).padding(8)
                }
                .frame(width: 76, height: 76)
            }
            .buttonStyle(.plain)

            Spacer()

            // Symmetric placeholder for layout balance
            Color.clear.frame(width: 48, height: 48)
        }
    }
}

// MARK: - Preview screen

private struct PreviewScreen: View {
    @ObservedObject var flow: CaptureFlow

    var body: some View {
        ZStack {
            Theme.Palette.cameraBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                photoStack
                    .padding(.horizontal, 20)
                    .padding(.top, 32)

                Spacer()

                actions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 38)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Text("Review capture")
                .font(Theme.Typography.sans(16, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Text("\(flow.images.count) OF \(CaptureFlow.maxPagesPerCapture) PAGES")
                .font(Theme.Typography.mono(11))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(height: 48)
    }

    private var photoStack: some View {
        ZStack {
            if flow.images.count > 1, let secondData = flow.images.last,
               let secondImage = UIImage(data: secondData) {
                Image(uiImage: secondImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(0.7)
                    .rotationEffect(.degrees(-2))
                    .offset(x: -8, y: 6)
            }
            if let firstData = flow.images.first, let firstImage = UIImage(data: firstData) {
                Image(uiImage: firstImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 18)
            }
        }
        .frame(height: 480)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { flow.retake() } label: {
                    Label("Retake", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(GlassButtonStyle())
                if flow.canTurnPage {
                    Button { flow.turnPage() } label: {
                        Label("Turn page", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            Button {
                Task { await flow.startExtraction() }
            } label: {
                HStack(spacing: 6) {
                    Text(useTitle)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle(
                background: Theme.Palette.accent,
                foreground: Theme.Palette.ink
            ))
        }
    }

    private var useTitle: String {
        flow.images.count > 1 ? "Use these \(flow.images.count) pages" : "Use this page"
    }
}

// MARK: - Extracting screen

private struct ExtractingScreen: View {
    @ObservedObject var flow: CaptureFlow
    let providerLabel: String
    let model: String
    @State private var scanProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                SectionLabel("Reading · \(providerLabel) \(modelShort)")
                    .padding(.top, 28)

                Spacer().frame(height: 36)

                ZStack(alignment: .topLeading) {
                    photoCard
                    scanLine
                }
                .frame(width: 240, height: 320)
                .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 14)

                Spacer().frame(height: 56)

                HeadlineWithSwipe(
                    prefix: "Reading the ",
                    accent: "marked passages",
                    suffix: "…",
                    font: Theme.Typography.serif(22),
                    lineSpacing: 4
                )
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

                Text(subText)
                    .font(Theme.Typography.mono(13))
                    .foregroundStyle(Theme.Palette.muted)
                    .padding(.top, 10)

                Spacer()

                Button("Cancel") { flow.backToPreview() }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.bottom, 44)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                scanProgress = 1
            }
        }
    }

    private var modelShort: String {
        // Keep label compact: show last component after "/" or "-"
        if let last = model.split(separator: "-").last { return String(last) }
        return model
    }

    private var subText: String {
        let count = flow.images.count
        return "~3s · \(count) page\(count == 1 ? "" : "s")"
    }

    private var photoCard: some View {
        Group {
            if let data = flow.images.first, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                PageMockView()
            }
        }
        .frame(width: 240, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var scanLine: some View {
        LinearGradient(
            colors: [Color.clear, Theme.Palette.accent.opacity(0.55), Color.clear],
            startPoint: .top, endPoint: .bottom
        )
        .frame(width: 240, height: 36)
        .overlay(
            Rectangle()
                .fill(Theme.Palette.ink.opacity(0.5))
                .frame(height: 1)
        )
        .offset(y: scanProgress * (320 - 36))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Failed screen

private struct ExtractionFailedScreen: View {
    @ObservedObject var flow: CaptureFlow
    let providerLabel: String
    var onRetry: () -> Void
    var onTypeManually: () -> Void
    var onBackToPhoto: () -> Void
    var onBackToBooks: () -> Void

    var body: some View {
        ZStack {
            Theme.Palette.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(Theme.Palette.dangerBg)
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.danger)
                }
                .frame(width: 44, height: 44)
                .padding(.top, 28)

                Text("The model couldn't read the photo.")
                    .font(Theme.Typography.serif(26))
                    .kerning(-0.4)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.top, 18)

                Text(subtitle)
                    .font(Theme.Typography.serif(15))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineSpacing(3)
                    .padding(.top, 10)

                if let detail = flow.lastError, !detail.isEmpty {
                    errorCard(detail)
                        .padding(.top, 22)
                }

                Spacer()

                actions
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
    }

    private var subtitle: String {
        "\(providerLabel) failed to extract a highlight from your photo. This usually clears in a moment."
    }

    private func errorCard(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView {
                Text(detail)
                    .font(Theme.Typography.mono(11))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.chipRadius)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.chipRadius)
                .stroke(Theme.Palette.line, lineWidth: 1)
        )
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try again")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            failedSecondary("Type manually", hint: "Skip extraction", action: onTypeManually)
            failedSecondary("Back to photo", hint: "Retake or turn page", action: onBackToPhoto)
            failedSecondary("Back to books", hint: "Cancel this capture", action: onBackToBooks)
        }
    }

    private func failedSecondary(_ title: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.sans(14, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(hint)
                        .font(Theme.Typography.sans(11))
                        .foregroundStyle(Theme.Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.smallCardRadius)
                    .stroke(Theme.Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
#endif
