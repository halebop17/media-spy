import MediaSpyKit
import SwiftUI

/// Inspector for one file — screens 2a (video), 2c (audio), 2d (many streams).
struct DetailView: View {
    @Environment(AppState.self) private var state
    let item: FileItem

    var body: some View {
        switch item.phase {
        case .analyzing:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Ember.label)
                Text(message)
                    .font(Ember.mono(11))
                    .foregroundStyle(Ember.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let report):
            switch state.inspectorMode {
            case .curated: ReportView(report: report)
            case .allFields: AllFieldsView(report: report)
            }
        }
    }
}

private struct ReportView: View {
    let report: MediaReport

    private var summary: FileSummary { Curated.fileSummary(for: report) }
    private var isAudioOnly: Bool { report.videoTracks.isEmpty && !report.audioTracks.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isAudioOnly {
                    // 2c — no video, the waveform takes the header.
                    WaveformHero(url: report.fileURL)
                    header(thumbnail: false)
                } else {
                    header(thumbnail: true)
                }

                section("GENERAL")
                Card {
                    RowGrid(Curated.generalRows(for: report).map { ($0.label, $0.value) })
                }

                section("STREAMS")
                ForEach(report.videoTracks) { track in
                    VideoCard(track: track)
                }
                ForEach(report.imageTracks) { track in
                    ImageCard(track: track)
                }
                ForEach(Array(report.audioTracks.enumerated()), id: \.element.id) { index, track in
                    AudioCard(
                        track: track,
                        url: report.fileURL,
                        analyzeLevels: isAudioOnly && index == 0
                    )
                }
                if !report.textTracks.isEmpty {
                    SubtitleTable(rows: Curated.subtitleRows(report.textTracks))
                }
            }
            .padding(22)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(Ember.mono(9.5, .semibold))
            .tracking(1.6)
            .foregroundStyle(Ember.label)
            .padding(.top, 2)
    }

    /// File header: adaptive thumbnail (landscape or portrait, content beside
    /// it) + title, path, badges. Static preview only — MediaSpy is an
    /// inspector, not a player.
    private func header(thumbnail: Bool) -> some View {
        // Video, or a still image, drives the preview tile.
        let visual = report.videoTracks.first ?? report.imageTracks.first
        return HStack(alignment: .top, spacing: 16) {
            if thumbnail, let visual {
                ThumbnailView(
                    url: report.fileURL,
                    aspect: aspectRatio(of: visual),
                    caption: summary.resolutionCaption,
                    chip: summary.aspectBadge
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(summary.title)
                    .font(Ember.display(21, .bold))
                    .foregroundStyle(Ember.textPrimary)
                    .lineLimit(2)
                Text(summary.path)
                    .font(Ember.mono(10))
                    .foregroundStyle(Ember.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                FlowBadges(summary: summary)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func aspectRatio(of track: MediaTrack) -> CGFloat {
        let width = track.number("Width") ?? 16
        let height = track.number("Height") ?? 9
        return CGFloat(width / max(height, 1))
    }
}

/// Container/size/duration/… badges, wrapping under narrow widths.
private struct FlowBadges: View {
    let summary: FileSummary

    var body: some View {
        let all: [(String, Color)] =
            [(summary.containerBadge, Ember.videoTint)]
            + summary.badges.map { ($0, Ember.textSecondary) }
            + (summary.hdrBadge.map { [($0, Ember.purple)] } ?? [])

        FlowLayout(spacing: 6) {
            ForEach(Array(all.enumerated()), id: \.offset) { entry in
                Badge(text: entry.element.0, tint: entry.element.1)
            }
        }
    }
}

private struct VideoCard: View {
    let track: MediaTrack

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    KindChip(text: "VIDEO", tint: Ember.videoTint)
                    Text(Curated.videoCodecName(track))
                        .font(Ember.mono(13, .bold))
                        .foregroundStyle(Ember.textPrimary)
                    Text(Curated.videoGeometry(track))
                        .font(Ember.mono(11.5))
                        .foregroundStyle(Ember.textTertiary)
                }

                RowGrid(Curated.videoRows(track).map { ($0.label, $0.value) })

                if let gauge = Curated.bitrateGauge(track) {
                    HStack(spacing: 10) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06))
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Ember.amber, Ember.coral],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                    .frame(width: proxy.size.width * gauge.fill)
                            }
                        }
                        .frame(height: 4)

                        if gauge.tier == .high || gauge.tier == .mastering {
                            Text(gauge.tier.rawValue)
                                .font(Ember.mono(8.5, .bold))
                                .tracking(0.8)
                                .foregroundStyle(Ember.amber)
                                .fixedSize()
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

private struct ImageCard: View {
    let track: MediaTrack

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    KindChip(text: "IMAGE", tint: Ember.coral)
                    Text(Curated.imageCodecName(track))
                        .font(Ember.mono(13, .bold))
                        .foregroundStyle(Ember.textPrimary)
                    Text(Curated.imageGeometry(track))
                        .font(Ember.mono(11.5))
                        .foregroundStyle(Ember.textTertiary)
                }
                RowGrid(Curated.imageRows(track).map { ($0.label, $0.value) })
            }
        }
    }
}

private struct AudioCard: View {
    let track: MediaTrack
    let url: URL
    /// Decode real levels only for the primary stream of audio-only files (2c).
    let analyzeLevels: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    KindChip(text: "AUDIO", tint: Ember.audioTint)
                    Text(Curated.audioCodecName(track))
                        .font(Ember.mono(13, .bold))
                        .foregroundStyle(Ember.textPrimary)
                    Text(Curated.audioHeadline(track))
                        .font(Ember.mono(11.5))
                        .foregroundStyle(Ember.textTertiary)
                }

                if analyzeLevels {
                    ChannelMeters(url: url)
                } else {
                    // Embedded streams get a decorative pattern — decoding
                    // every container here isn't worth the I/O (see plan §12).
                    DecorativeWaveform(seed: track.id, tint: Ember.audioTint)
                        .frame(height: 34)
                }

                RowGrid(Curated.audioRows(track).map { ($0.label, $0.value) })
            }
        }
    }
}

private struct SubtitleTable: View {
    let rows: [Curated.SubtitleRow]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    KindChip(text: "TEXT", tint: Ember.textTint)
                    Text("\(rows.count) subtitle stream\(rows.count == 1 ? "" : "s")")
                        .font(Ember.mono(11.5))
                        .foregroundStyle(Ember.textTertiary)
                }
                .padding(.bottom, 10)

                gridHeader
                ForEach(rows) { row in
                    Rectangle().fill(Ember.hairline).frame(height: 1)
                    gridRow(row)
                }
            }
        }
    }

    private var gridHeader: some View {
        HStack(spacing: 0) {
            cell("#", width: 30)
            cell("LANGUAGE", width: 110)
            cell("FORMAT", width: 80)
            Text("TITLE").font(Ember.mono(8.5, .semibold)).tracking(1).foregroundStyle(Ember.label)
            Spacer()
            Text("FLAGS").font(Ember.mono(8.5, .semibold)).tracking(1).foregroundStyle(Ember.label)
        }
        .padding(.vertical, 6)
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(Ember.mono(8.5, .semibold))
            .tracking(1)
            .foregroundStyle(Ember.label)
            .frame(width: width, alignment: .leading)
    }

    private func gridRow(_ row: Curated.SubtitleRow) -> some View {
        HStack(spacing: 0) {
            Text("\(row.index)")
                .font(Ember.mono(10.5))
                .foregroundStyle(Ember.label)
                .frame(width: 30, alignment: .leading)
            Text(row.language)
                .font(Ember.mono(11, .medium))
                .foregroundStyle(Ember.textPrimary)
                .frame(width: 110, alignment: .leading)
            Text(row.format)
                .font(Ember.mono(10.5))
                .foregroundStyle(Ember.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(row.title)
                .font(Ember.mono(10.5))
                .foregroundStyle(Ember.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(row.flags, id: \.self) { flag in
                    Text(flag)
                        .font(Ember.mono(8, .bold))
                        .tracking(0.6)
                        .foregroundStyle(flagTint(flag))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(flagTint(flag).opacity(0.13), in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .padding(.vertical, 7)
    }

    private func flagTint(_ flag: String) -> Color {
        switch flag {
        case "DEFAULT": return Ember.amber
        case "FORCED": return Ember.coral
        default: return Ember.purple
        }
    }
}

/// Minimal wrapping HStack for badges.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(proposal: proposal, subviews: subviews).positions
        for (subview, position) in zip(subviews, positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(cursor)
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, cursor.x - spacing)
        }
        return (CGSize(width: totalWidth, height: cursor.y + rowHeight), positions)
    }
}
