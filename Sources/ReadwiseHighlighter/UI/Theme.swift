#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

public enum Theme {
    public enum Palette {
        public static let bg = Color(hex: 0xFBF7EE)
        public static let bgAlt = Color(hex: 0xF3ECDC)
        public static let surface = Color.white
        public static let ink = Color(hex: 0x1A1714)
        public static let inkSoft = Color(hex: 0x5A5147)
        public static let muted = Color(hex: 0x8A7E6A)
        public static let line = Color(hex: 0xE8DEC9)
        public static let lineSoft = Color(hex: 0xEFE7D4)
        public static let accent = Color(hex: 0xFFF066)
        public static let danger = Color(hex: 0xB54A3A)
        public static let dangerBg = Color(hex: 0xFDE8E2)
        public static let success = Color(hex: 0x3A6E3A)
        public static let cameraBg = Color(hex: 0x0D0C0A)
        public static let cameraSurface = Color(hex: 0x1A1814)
        public static let pageBg = Color(hex: 0xE8DCC4)
        public static let noteInk = Color(hex: 0x5A3A20)

        public static let coverPalette: [Color] = [
            Color(hex: 0xC9B48A),
            Color(hex: 0x8A6F4A),
            Color(hex: 0x4A5A4A),
            Color(hex: 0xA45A3A)
        ]
    }

    public enum Typography {
        public static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }

        public static func serifItalic(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif).italic()
        }

        public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        public static func handwritten(_ size: CGFloat) -> Font {
            .custom("Caveat-Regular", size: size)
        }

        public static let display = serif(38, weight: .regular)
        public static let title = serif(30, weight: .regular)
        public static let subhead = serif(26, weight: .regular)
        public static let bodySerif = serif(15, weight: .regular)
        public static let navTitle = sans(15, weight: .semibold)
        public static let button = sans(16, weight: .semibold)
        public static let listPrimary = sans(15, weight: .medium)
        public static let listSecondary = sans(13, weight: .regular)
    }

    public enum Layout {
        public static let screenPadding: CGFloat = 20
        public static let setupPadding: CGFloat = 28
        public static let cardRadius: CGFloat = 14
        public static let smallCardRadius: CGFloat = 12
        public static let chipRadius: CGFloat = 10
        public static let pageChipRadius: CGFloat = 6
        public static let primaryButtonHeight: CGFloat = 54
        public static let secondaryButtonHeight: CGFloat = 50
        public static let segmentedHeight: CGFloat = 38
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Section label

public struct SectionLabel: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.mono(10, weight: .medium))
            .tracking(1.4)
            .foregroundStyle(Theme.Palette.muted)
    }
}

// MARK: - Highlighter swipe (yellow accent behind text)

public struct HighlightSwipe: View {
    let text: String
    let font: Font
    let color: Color
    let foreground: Color

    public init(
        _ text: String,
        font: Font,
        color: Color = Theme.Palette.accent,
        foreground: Color = Theme.Palette.ink
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.foreground = foreground
    }

    public var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foreground)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                color
                    .rotationEffect(.degrees(-1.5))
                    .padding(.vertical, 2)
            )
    }
}

// MARK: - Buttons

public struct PrimaryButtonStyle: ButtonStyle {
    var background: Color = Theme.Palette.ink
    var foreground: Color = Theme.Palette.bg
    var height: CGFloat = Theme.Layout.primaryButtonHeight
    var enabled: Bool = true

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.button)
            .foregroundStyle(enabled ? foreground : Theme.Palette.muted)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .fill(enabled ? background : Theme.Palette.line)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = Theme.Layout.secondaryButtonHeight

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.sans(15, weight: .medium))
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .stroke(Theme.Palette.line, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public struct GlassButtonStyle: ButtonStyle {
    var height: CGFloat = Theme.Layout.secondaryButtonHeight
    var fullWidth: Bool = true

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.sans(15, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : 18)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .fill(Color.white.opacity(0.08))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public struct GhostButtonStyle: ButtonStyle {
    var foreground: Color = Theme.Palette.inkSoft

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.sans(14, weight: .regular))
            .foregroundStyle(foreground)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

// MARK: - Card container

public struct ThemedCard<Content: View>: View {
    let padding: EdgeInsets
    let content: () -> Content

    public init(
        padding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .stroke(Theme.Palette.line, lineWidth: 1)
            )
    }
}

// MARK: - Themed text field (single line, keychain-style)

public struct ThemedTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var monospaced: Bool = true

    public init(_ placeholder: String, text: Binding<String>, secure: Bool = false, monospaced: Bool = true) {
        self.placeholder = placeholder
        self._text = text
        self.secure = secure
        self.monospaced = monospaced
    }

    public var body: some View {
        HStack(spacing: 10) {
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(monospaced ? Theme.Typography.mono(13) : Theme.Typography.sans(15))
            .foregroundStyle(Theme.Palette.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
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
}

// MARK: - Cover thumbnail with monogram fallback

public struct CoverThumbnail: View {
    let title: String
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    public init(title: String, url: URL? = nil, width: CGFloat = 36, height: CGFloat = 50) {
        self.title = title
        self.url = url
        self.width = width
        self.height = height
    }

    private var monogram: String {
        guard let first = title.unicodeScalars.first(where: { CharacterSet.letters.contains($0) }) else {
            return "?"
        }
        return String(first).uppercased()
    }

    private var coverColor: Color {
        let hash = abs(title.hashValue)
        return Theme.Palette.coverPalette[hash % Theme.Palette.coverPalette.count]
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(coverColor)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        monogramView
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                monogramView
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.18), radius: 1, x: 1, y: 1)
        .overlay(
            // subtle inset on right edge for "spine" feel
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        )
    }

    private var monogramView: some View {
        Text(monogram)
            .font(.system(size: width * 0.5, weight: .semibold, design: .serif).italic())
            .foregroundStyle(.white.opacity(0.95))
    }
}

// MARK: - Page mock (CSS-drawn book page recreated as SwiftUI)

public struct PageMockView: View {
    var pageNumber: Int = 87
    var showHighlight: Bool = true
    var showNote: Bool = true

    public init(pageNumber: Int = 87, showHighlight: Bool = true, showNote: Bool = true) {
        self.pageNumber = pageNumber
        self.showHighlight = showHighlight
        self.showNote = showNote
    }

    private let lineWidths: [CGFloat] = [
        1.00, 0.94, 0.98, 0.90, 1.00,
        0.96, 0.92, 0.88, 0.95, 0.40,
        1.00, 0.93, 0.97, 0.89, 0.70
    ]

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .topLeading) {
                Theme.Palette.pageBg

                // top-left gradient
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.6), Color.clear],
                            center: .center, startRadius: 0, endRadius: w * 0.45
                        )
                    )
                    .frame(width: w * 0.9, height: h * 0.6)
                    .position(x: w * 0.3, y: h * 0.2)

                // bottom-right warm shadow
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0x503214, opacity: 0.18), Color.clear],
                            center: .center, startRadius: 0, endRadius: w * 0.5
                        )
                    )
                    .frame(width: w * 0.9, height: h * 0.6)
                    .position(x: w * 0.8, y: h * 0.9)

                // page number
                Text("· \(pageNumber) ·")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Color(hex: 0x5A4A30))
                    .padding(.top, 18)
                    .padding(.trailing, 22)
                    .frame(width: w, alignment: .trailing)

                // body lines
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lineWidths.enumerated()), id: \.offset) { idx, ratio in
                        let isHighlighted = showHighlight && (idx == 4 || idx == 5 || idx == 6)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color(hex: 0x5A4A30, opacity: 0.78))
                                .frame(height: 7)
                                .frame(width: (w - 44) * ratio, alignment: .leading)
                            if isHighlighted {
                                Color(hex: 0xFFE650, opacity: 0.55)
                                    .frame(height: 11)
                                    .frame(width: (w - 44) * ratio + 6, alignment: .leading)
                                    .offset(x: -3, y: 0)
                                    .blendMode(.multiply)
                                    .rotationEffect(.degrees(-1))
                            }
                        }
                        .padding(.top, idx == 10 ? 8 : 0)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 56)

                if showNote {
                    Text("cf. Hayek?")
                        .font(.custom("Caveat-Regular", size: 11))
                        .foregroundStyle(Theme.Palette.noteInk)
                        .frame(width: 70, alignment: .leading)
                        .rotationEffect(.degrees(-4))
                        .position(x: w - 36, y: 195)
                }
            }
        }
    }
}

// MARK: - Reticle corners

public struct ReticleCorners: View {
    var color: Color = .white
    var size: CGFloat = 22
    var lineWidth: CGFloat = 2
    var inset: CGFloat = 14

    public init(
        color: Color = .white,
        size: CGFloat = 22,
        lineWidth: CGFloat = 2,
        inset: CGFloat = 14
    ) {
        self.color = color
        self.size = size
        self.lineWidth = lineWidth
        self.inset = inset
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                corner(.topLeading).position(x: inset + size / 2, y: inset + size / 2)
                corner(.topTrailing).position(x: w - inset - size / 2, y: inset + size / 2)
                corner(.bottomLeading).position(x: inset + size / 2, y: h - inset - size / 2)
                corner(.bottomTrailing).position(x: w - inset - size / 2, y: h - inset - size / 2)
            }
        }
    }

    private func corner(_ alignment: Alignment) -> some View {
        Path { path in
            switch alignment {
            case .topLeading:
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size, y: 0))
            case .topTrailing:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
            case .bottomLeading:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size, y: size))
            case .bottomTrailing:
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size, y: size))
                path.addLine(to: CGPoint(x: size, y: 0))
            default:
                break
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter))
        .frame(width: size, height: size)
    }
}

// MARK: - Helpers

extension View {
    public func themedScreen() -> some View {
        background(Theme.Palette.bg.ignoresSafeArea())
    }
}
#endif
