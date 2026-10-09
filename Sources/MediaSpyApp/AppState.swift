import AppKit
import MediaSpyKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// One opened file and its (eventual) analysis.
struct FileItem: Identifiable, Equatable {
    enum Phase: Equatable {
        case analyzing
        case ready(MediaReport)
        case failed(String)
    }

    let url: URL
    var phase: Phase = .analyzing

    var id: URL { url }
    var report: MediaReport? {
        if case .ready(let report) = phase { return report }
        return nil
    }
}

/// Curated inspector cards vs. the complete raw field list.
enum InspectorMode {
    case curated, allFields
}

@MainActor
@Observable
final class AppState {
    /// Single app-wide state so the Finder Service handler (an NSObject on
    /// NSApp.servicesProvider) and the SwiftUI window share one instance.
    static let shared = AppState()

    var items: [FileItem] = []
    var selection: URL?
    var inspectorMode: InspectorMode = .curated

    var selectedItem: FileItem? {
        guard let selection else { return items.first }
        return items.first { $0.url == selection }
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(FileItem(url: url))
            if selection == nil { selection = url }
            Task { await analyze(url) }
        }
        if urls.count == 1, let only = urls.first { selection = only }
    }

    func remove(_ url: URL) {
        items.removeAll { $0.url == url }
        if selection == url { selection = items.first?.url }
    }

    private func analyze(_ url: URL) async {
        let phase: FileItem.Phase
        do {
            phase = .ready(try await MediaInspector.inspect(url))
        } catch {
            phase = .failed("Could not read this file as media.")
        }
        if let index = items.firstIndex(where: { $0.url == url }) {
            items[index].phase = phase
        }
    }

    // MARK: - Commands

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .audio, .audiovisualContent, .data]
        if panel.runModal() == .OK {
            add(panel.urls)
        }
    }

    func copyReport() {
        guard let report = selectedItem?.report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.textReport, forType: .string)
    }

    /// Export the selected file's report in a MediaInfo-parity format.
    func export(as format: MediaInspector.ExportFormat) {
        guard let item = selectedItem, let report = item.report else { return }
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = item.url.deletingPathExtension().lastPathComponent
            + ".mediainfo." + format.fileExtension

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                let text: String
                switch format {
                // rawJSON is already the Complete=1 JSON `render` would produce.
                case .json: text = report.rawJSON
                // Text/XML/HTML render fresh so exports carry the full field set
                // (the cached textReport is the abbreviated Complete=0 report).
                case .text, .xml, .html: text = try await MediaInspector.render(item.url, as: format)
                }
                try Data(text.utf8).write(to: destination)
            } catch {
                presentError("Couldn’t export the report.", error)
            }
        }
    }

    private func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
