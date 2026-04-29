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
        guard let imageData = flow.imageData else {
            flow.skipExtraction()
            return
        }
        guard let client = state.currentGeminiClient() else {
            flow.lastError = "Gemini key missing — open Settings."
            flow.skipExtraction()
            return
        }
        do {
            let result = try await client.extractHighlight(from: imageData)
            flow.applyExtraction(result)
        } catch GeminiError.invalidKey {
            flow.lastError = "Gemini key rejected — update it in Settings."
            flow.skipExtraction()
        } catch {
            flow.lastError = "Extraction failed: \(error.localizedDescription)"
            flow.skipExtraction()
        }
    }

    private func submit() async {
        guard let client = state.currentReadwiseClient() else {
            flow.lastError = "Readwise key missing — open Settings."
            return
        }
        flow.stage = .submitting
        let input = ReadwiseClient.HighlightInput(
            text: flow.extractedText.trimmingCharacters(in: .whitespacesAndNewlines),
            title: flow.book.title,
            author: flow.book.author,
            pageNumber: flow.parsedPageNumber()
        )
        do {
            try await client.createHighlight(input)
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
            if let data = flow.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            HStack {
                Button("Retake", role: .cancel) { flow.retake() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Use photo") {
                    Task { await flow.startExtraction() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(flow.book.title)
        .navigationBarTitleDisplayMode(.inline)
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
#endif
