import MediaSpyKit
import SwiftUI

/// The complete, unfiltered libmediainfo field set for every track, with live
/// search — the power-user "show everything" view (design §12 / MediaInfo's
/// tree view). Reached via the list toggle in the toolbar.
struct AllFieldsView: View {
    let report: MediaReport
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Rectangle().fill(Ember.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(report.tracks) { track in
                        let rows = filteredRows(for: track)
                        if !rows.isEmpty {
                            trackSection(track, rows: rows)
                        }
                    }
                    if allFilteredEmpty {
                        Text("No fields match “\(query)”.")
                            .font(Ember.mono(11))
                            .foregroundStyle(Ember.label)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(22)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Ember.label)
            TextField("Filter \(totalFieldCount) fields…", text: $query)
                .textFieldStyle(.plain)
                .font(Ember.mono(11.5))
                .foregroundStyle(Ember.textPrimary)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Ember.label)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func trackSection(_ track: MediaTrack, rows: [(String, String)]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    KindChip(text: kindLabel(track.kind), tint: tint(for: track.kind))
                    Text("\(rows.count) field\(rows.count == 1 ? "" : "s")")
                        .font(Ember.mono(9.5))
                        .foregroundStyle(Ember.label)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                        if index > 0 { Rectangle().fill(Ember.hairline).frame(height: 1) }
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.0)
                                .font(Ember.mono(10.5))
                                .foregroundStyle(Ember.textTertiary)
                                .frame(width: 230, alignment: .leading)
                                .textSelection(.enabled)
                            Text(row.1)
                                .font(Ember.mono(10.5, .medium))
                                .foregroundStyle(Ember.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    // MARK: - Filtering

    private func filteredRows(for track: MediaTrack) -> [(String, String)] {
        let sorted = track.fields.sorted { $0.key < $1.key }
        guard !query.isEmpty else { return sorted.map { ($0.key, $0.value) } }
        return sorted
            .filter { $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) }
            .map { ($0.key, $0.value) }
    }

    private var allFilteredEmpty: Bool {
        !query.isEmpty && report.tracks.allSatisfy { filteredRows(for: $0).isEmpty }
    }

    private var totalFieldCount: Int {
        report.tracks.reduce(0) { $0 + $1.fields.count }
    }

    private func kindLabel(_ kind: MediaTrack.Kind) -> String {
        switch kind {
        case .general: return "GENERAL"
        case .video: return "VIDEO"
        case .audio: return "AUDIO"
        case .text: return "TEXT"
        case .image: return "IMAGE"
        case .menu: return "MENU"
        case .other(let name): return name.uppercased()
        }
    }

    private func tint(for kind: MediaTrack.Kind) -> Color {
        switch kind {
        case .video: return Ember.videoTint
        case .audio: return Ember.audioTint
        case .text: return Ember.textTint
        default: return Ember.textSecondary
        }
    }
}
