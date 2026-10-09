import MediaSpyKit
import SwiftUI

/// Window chrome + sidebar (2+ files) + detail. Screens 2a/2b of the design.
struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Rectangle().fill(Ember.hairline).frame(height: 1)

            HStack(spacing: 0) {
                // Sidebar only once there is something to switch between (2b).
                if state.items.count > 1 {
                    SidebarView()
                    Rectangle().fill(Ember.hairline).frame(width: 1)
                }

                Group {
                    if let item = state.selectedItem {
                        DetailView(item: item)
                            .id(item.url)
                    } else {
                        EmptyStateView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ember.window)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter { $0.isFileURL }
            guard !files.isEmpty else { return false }
            state.add(files)
            return true
        }
        .preferredColorScheme(.dark)
    }

    /// Custom bar under the hidden system title bar: centered filename,
    /// actions on the right. Traffic lights overlay the leading edge.
    private var titleBar: some View {
        ZStack {
            Text(state.selectedItem?.url.lastPathComponent ?? "MediaSpy")
                .font(Ember.mono(11, .medium))
                .foregroundStyle(Ember.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 460)

            HStack(spacing: 2) {
                Spacer()
                if state.selectedItem?.report != nil {
                    barButton(
                        state.inspectorMode == .curated ? "list.bullet.rectangle" : "square.grid.2x2",
                        help: state.inspectorMode == .curated ? "Show all fields" : "Show summary"
                    ) {
                        state.inspectorMode = state.inspectorMode == .curated ? .allFields : .curated
                    }
                    barButton("doc.on.doc", help: "Copy MediaInfo report") { state.copyReport() }
                    Menu {
                        ForEach(MediaInspector.ExportFormat.allCases, id: \.self) { format in
                            Button("Export as \(format.displayName)…") { state.export(as: format) }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Ember.textTertiary)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Export report…")
                }
                barButton("plus", help: "Add files… (⌘O)") { state.openPanel() }
            }
            .padding(.trailing, 12)
        }
        .frame(height: 40)
    }

    private func barButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ember.textTertiary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(state.items.count) FILES · 1 SELECTED")
                .font(Ember.mono(9, .semibold))
                .tracking(1.2)
                .foregroundStyle(Ember.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(state.items) { item in
                        SidebarRow(item: item, selected: item.url == state.selectedItem?.url)
                            .onTapGesture { state.selection = item.url }
                            .contextMenu {
                                Button("Remove") { state.remove(item.url) }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            Text("Drop files to add\nor ⌘O to open")
                .font(Ember.mono(9.5))
                .foregroundStyle(Ember.label)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Ember.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .padding(10)
        }
        .frame(width: 218)
        .background(Ember.window)
    }
}

private struct SidebarRow: View {
    let item: FileItem
    let selected: Bool

    private var icon: (symbol: String, tint: Color) {
        guard let report = item.report else { return ("doc", Ember.textTertiary) }
        if !report.videoTracks.isEmpty { return ("film", Ember.videoTint) }
        if !report.imageTracks.isEmpty { return ("photo", Ember.textTint) }
        if !report.audioTracks.isEmpty { return ("waveform", Ember.audioTint) }
        return ("doc", Ember.textTertiary)
    }

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.05))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: icon.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(icon.tint)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(Ember.mono(10.5, .medium))
                    .foregroundStyle(selected ? Ember.textPrimary : Ember.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(Ember.mono(9))
                    .foregroundStyle(Ember.label)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Color.white.opacity(0.06) : .clear)
        )
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Ember.amber)
                    .frame(width: 2, height: 22)
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let ext = item.url.pathExtension.uppercased()
        switch item.phase {
        case .analyzing: return "\(ext) · analyzing…"
        case .failed: return "\(ext) · unreadable"
        case .ready(let report):
            let size = report.general?.value("FileSize_String", "FileSize") ?? ""
            return size.isEmpty ? ext : "\(ext) · \(size)"
        }
    }
}

struct EmptyStateView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Ember.label)
            Text("Drop media files here")
                .font(Ember.display(15, .semibold))
                .foregroundStyle(Ember.textSecondary)
            Text("video · audio · any container — or press ⌘O")
                .font(Ember.mono(10.5))
                .foregroundStyle(Ember.label)
        }
        .frame(maxWidth: 420, maxHeight: 260)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Ember.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .frame(maxWidth: 420, maxHeight: 260)
        )
        .contentShape(Rectangle())
        .onTapGesture { state.openPanel() }
    }
}
