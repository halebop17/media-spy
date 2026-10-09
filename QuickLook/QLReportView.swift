import SwiftUI
import MediaSpyKit

// Self-contained Ember-themed report for the Quick Look preview. Mirrors the
// app's look with an inline mini-palette (the app's design system lives in the
// app target; this keeps the extension independent). Data comes entirely from
// MediaSpyKit's public Curated API.

private enum QL {
    static let window = Color(red: 0x17 / 255, green: 0x12 / 255, blue: 0x0F / 255)
    static let panel = Color(red: 0x1E / 255, green: 0x18 / 255, blue: 0x15 / 255)
    static let hairline = Color.white.opacity(0.07)
    static let text = Color(red: 0xEA / 255, green: 0xDE / 255, blue: 0xD2 / 255)
    static let dim = Color(red: 0x9A / 255, green: 0x88 / 255, blue: 0x78 / 255)
    static let label = Color(red: 0x85 / 255, green: 0x74 / 255, blue: 0x68 / 255)
    static let amber = Color(red: 0xF2 / 255, green: 0xA9 / 255, blue: 0x3B / 255)
    static let purple = Color(red: 0xB5 / 255, green: 0x83 / 255, blue: 0xFF / 255)
    static let coral = Color(red: 0xF2 / 255, green: 0x6D / 255, blue: 0x5B / 255)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct QLReportView: View {
    let report: MediaReport

    private var summary: FileSummary { Curated.fileSummary(for: report) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                card(chip: nil, tint: QL.dim, title: "GENERAL", subtitle: nil,
                     rows: Curated.generalRows(for: report))
                ForEach(report.videoTracks) { t in
                    card(chip: "VIDEO", tint: QL.amber, title: Curated.videoCodecName(t),
                         subtitle: Curated.videoGeometry(t), rows: Curated.videoRows(t))
                }
                ForEach(report.imageTracks) { t in
                    card(chip: "IMAGE", tint: QL.coral, title: Curated.imageCodecName(t),
                         subtitle: Curated.imageGeometry(t), rows: Curated.imageRows(t))
                }
                ForEach(report.audioTracks) { t in
                    card(chip: "AUDIO", tint: QL.purple, title: Curated.audioCodecName(t),
                         subtitle: Curated.audioHeadline(t), rows: Curated.audioRows(t))
                }
                let subs = Curated.subtitleRows(report.textTracks)
                if !subs.isEmpty { subtitleCard(subs) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(QL.window)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(QL.text)
                .lineLimit(2)
            Text(summary.path)
                .font(QL.mono(9.5))
                .foregroundStyle(QL.label)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                badge(summary.containerBadge, tint: QL.amber)
                ForEach(summary.badges.prefix(4), id: \.self) { badge($0, tint: QL.dim) }
                if let hdr = summary.hdrBadge { badge(hdr, tint: QL.purple) }
            }
            .padding(.top, 2)
        }
    }

    private func card(chip: String?, tint: Color, title: String, subtitle: String?,
                      rows: [CuratedRow]) -> some View {
        Group {
            if rows.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        if let chip {
                            Text(chip).font(QL.mono(9, .bold)).tracking(0.7)
                                .foregroundStyle(tint)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                        }
                        Text(title).font(QL.mono(12.5, .bold)).foregroundStyle(QL.text)
                        if let subtitle {
                            Text(subtitle).font(QL.mono(11)).foregroundStyle(QL.dim)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .topLeading)],
                              alignment: .leading, spacing: 12) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label).font(QL.mono(8.5, .semibold)).tracking(0.6)
                                    .foregroundStyle(QL.label)
                                Text(row.value).font(QL.mono(11.5, .medium)).foregroundStyle(QL.text)
                            }
                        }
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QL.panel, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(QL.hairline))
            }
        }
    }

    private func subtitleCard(_ rows: [Curated.SubtitleRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("TEXT").font(QL.mono(9, .bold)).tracking(0.7).foregroundStyle(QL.coral)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(QL.coral.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                Text("\(rows.count) subtitle stream\(rows.count == 1 ? "" : "s")")
                    .font(QL.mono(11)).foregroundStyle(QL.dim)
            }
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text("\(row.index)").font(QL.mono(10)).foregroundStyle(QL.label).frame(width: 18, alignment: .leading)
                    Text(row.language).font(QL.mono(10.5, .medium)).foregroundStyle(QL.text).frame(width: 90, alignment: .leading)
                    Text(row.format).font(QL.mono(10)).foregroundStyle(QL.dim).frame(width: 60, alignment: .leading)
                    Text(row.title).font(QL.mono(10)).foregroundStyle(QL.dim).lineLimit(1)
                    Spacer(minLength: 4)
                    ForEach(row.flags, id: \.self) { f in
                        Text(f).font(QL.mono(8, .bold)).foregroundStyle(QL.amber)
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background(QL.amber.opacity(0.13), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QL.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(QL.hairline))
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(QL.mono(10, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(QL.hairline))
    }
}
