import SwiftUI

// Ember design tokens, extracted from design/MediaSpy Ember.dc.html.
// Fonts: the canvas uses Space Grotesk + IBM Plex Mono (Google/OFL); we map
// onto SF Pro + SF Mono for a zero-bundling native build — same structure
// (display face for titles, mono for data). Revisit in M4 if pixel-exact
// typography matters.
enum Ember {
    // Backgrounds (warm near-black)
    static let window = Color(hex: 0x17120F)
    static let panel = Color(hex: 0x1E1815)
    static let panelRaised = Color(hex: 0x241D19)
    static let hairline = Color.white.opacity(0.07)

    // Text
    static let textPrimary = Color(hex: 0xEADED2)
    static let textSecondary = Color(hex: 0xC9BCB0)
    static let textTertiary = Color(hex: 0x9A8878)
    static let label = Color(hex: 0x857468)

    // Accents
    static let amber = Color(hex: 0xF2A93B)
    static let coral = Color(hex: 0xF26D5B)
    static let purple = Color(hex: 0xB583FF)

    // Stream-kind tints
    static let videoTint = amber
    static let audioTint = purple
    static let textTint = coral

    // Type scale
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Tiny uppercase mono field label ("BIT RATE").
struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Ember.mono(9, .semibold))
            .tracking(0.8)
            .foregroundStyle(Ember.label)
    }
}

/// Stream-kind chip ("VIDEO" / "AUDIO" / "TEXT").
struct KindChip: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(Ember.mono(9, .bold))
            .tracking(0.8)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Neutral metadata badge ("157 MiB", "1 min 7 s").
struct Badge: View {
    let text: String
    var tint: Color = Ember.textSecondary
    var body: some View {
        Text(text)
            .font(Ember.mono(10.5, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Ember.hairline))
    }
}

/// Card container matching the Ember panel style.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Ember.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ember.hairline))
    }
}

/// Label/value grid used inside all detail cards.
struct RowGrid: View {
    let rows: [String: String]
    let order: [String]

    init(_ curated: [(String, String)]) {
        // Tolerate (rather than trap on) a repeated label — last value wins,
        // and `order` is de-duplicated so the grid stays 1:1 with the dict.
        rows = Dictionary(curated, uniquingKeysWith: { _, last in last })
        var seen = Set<String>()
        order = curated.map(\.0).filter { seen.insert($0).inserted }
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), alignment: .topLeading)],
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(order, id: \.self) { label in
                VStack(alignment: .leading, spacing: 3) {
                    FieldLabel(text: label)
                    Text(rows[label] ?? "")
                        .font(Ember.mono(12, .medium))
                        .foregroundStyle(Ember.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
