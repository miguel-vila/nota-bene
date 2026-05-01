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
                ExtractingScreen(flow: flow)
                    .task { await runExtraction() }
            case .extractionFailed:
                ExtractionFailedScreen(
                    flow: flow,
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
                }
            }
        }
        .navigationBarBackButtonHidden(flow.stage != .capture)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if flow.stage == .capture {
                    Button("Change book") { dismiss() }
                }
            }
        }
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
        flow.stage = .submitting
        do {
            try await client.createHighlights(inputs)
            flow.lastError = nil
            flow.reset()
        } catch ReadwiseError.invalidToken {
            flow.lastError = "Readwise token rejected — update it in Settings."
            flow.stage = .review
        } catch {
            flow.lastError = "Submit failed: \(error.localizedDescription)"
            flow.stage = .review
        }
    }
}

private struct CaptureScreen: View {
    @ObservedObject var flow: CaptureFlow
    var onChangeBook: () -> Void
    @State private var captureToken: UUID?
    @State private var pickerItem: PhotosPickerItem?
    @State private var cameraError: String?

    var body: some View {
        ZStack {
            CameraView(
                onCapture: { data in flow.acceptPhoto(data) },
                onError: { cameraError = $0 },
                captureToken: $captureToken
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Text(flow.book.title)
                        .font(.headline)
                        .lineLimit(1)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .onTapGesture { onChangeBook() }
                    Spacer()
                }
                .padding(.top, 12)

                Spacer()

                if let cameraError {
                    Text(cameraError)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.red)
                }

                HStack(spacing: 36) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .padding(14)
                            .background(.ultraThinMaterial, in: Circle())
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

                    Button {
                        captureToken = UUID()
                    } label: {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 4).padding(-6))
                    }

                    Color.clear.frame(width: 50, height: 50)
                }
                .padding(.bottom, 36)
            }
        }
    }
}

private struct PreviewScreen: View {
    @ObservedObject var flow: CaptureFlow

    var body: some View {
        VStack {
            if flow.images.count == 1, let image = UIImage(data: flow.images[0]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else if flow.images.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(flow.images.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                VStack(spacing: 4) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 360)
                                    Text("Page \(index + 1)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            HStack {
                Button("Retake", role: .cancel) { flow.retake() }
                    .buttonStyle(.bordered)
                if flow.canTurnPage {
                    Button {
                        flow.turnPage()
                    } label: {
                        Label("Turn page", systemImage: "book.pages")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button(useButtonTitle) {
                    Task { await flow.startExtraction() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(flow.book.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var useButtonTitle: String {
        flow.images.count > 1 ? "Use \(flow.images.count) photos" : "Use photo"
    }
}

private struct ExtractingScreen: View {
    @ObservedObject var flow: CaptureFlow

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Extracting highlight…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ExtractionFailedScreen: View {
    @ObservedObject var flow: CaptureFlow
    var onRetry: () -> Void
    var onTypeManually: () -> Void
    var onBackToPhoto: () -> Void
    var onBackToBooks: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Extraction failed")
                .font(.title3.weight(.semibold))
            if let message = flow.lastError {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onTypeManually) {
                    Text("Type manually")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                HStack(spacing: 24) {
                    Button("Back to photo", action: onBackToPhoto)
                    Button("Back to books", action: onBackToBooks)
                }
                .buttonStyle(.borderless)
                .font(.footnote)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(flow.book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
