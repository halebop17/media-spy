import CMediaInfo
import Foundation

/// Errors surfaced by ``MediaInspector``.
public enum MediaInspectorError: Error, Equatable, Sendable {
    /// libmediainfo could not allocate an analysis handle.
    case engineUnavailable
    /// The file could not be opened/parsed (missing, unreadable, or not media).
    case cannotOpen(String)
    /// The engine produced output the parser could not understand.
    case malformedOutput
}

/// Thin RAII wrapper around a single libmediainfo handle.
///
/// Handles are cheap but the C "A" (char*) interface shares string-conversion
/// buffers across handles — concurrent Inform/Option calls clobber each other
/// (verified empirically: parallel inspections deterministically corrupt all
/// but one result). ALL engine work therefore goes through
/// ``MediaInspector``'s serial queue.
final class MediaInfoHandle {
    private let handle: UnsafeMutableRawPointer

    init() throws {
        guard let h = MediaInfoA_New() else { throw MediaInspectorError.engineUnavailable }
        handle = h
        // The "A" (char*) interface is byte-oriented; be explicit that we speak UTF-8.
        _ = option("CharSet", "UTF-8")
    }

    deinit {
        MediaInfoA_Close(handle)
        MediaInfoA_Delete(handle)
    }

    /// Set (or query) an engine option, e.g. `option("Output", "JSON")`.
    @discardableResult
    func option(_ name: String, _ value: String = "") -> String {
        guard let cString = MediaInfoA_Option(handle, name, value) else { return "" }
        return String(cString: cString)
    }

    /// Open a file for analysis. Returns false if the engine rejected it.
    func open(_ path: String) -> Bool {
        MediaInfoA_Open(handle, path) != 0
    }

    /// The formatted report for the currently open file, per the "Output" option.
    func inform() -> String {
        guard let cString = MediaInfoA_Inform(handle, 0) else { return "" }
        return String(cString: cString)
    }
}

/// Analyses media files with libmediainfo and returns structured ``MediaReport``s.
public enum MediaInspector {
    /// Engine version string, e.g. "MediaInfoLib - v26.05" (nil if unavailable).
    public static var engineVersion: String? {
        guard let handle = try? MediaInfoHandle() else { return nil }
        let version = handle.option("Info_Version")
        return version.isEmpty ? nil : version
    }

    /// Serialises every engine call — see ``MediaInfoHandle`` for why this
    /// must be global, not per-handle.
    private static let engineQueue = DispatchQueue(label: "com.mediaspy.mediainfo-engine")

    /// Inspect a file synchronously. Blocking — parses the container on the
    /// calling thread. Safe only when callers never overlap; concurrent code
    /// must use ``inspect(_:)``, which serialises on the engine queue.
    public static func inspectSync(_ url: URL) throws -> MediaReport {
        let handle = try MediaInfoHandle()

        // Full field set as JSON for the structured model…
        handle.option("Complete", "1")
        handle.option("Output", "JSON")
        guard handle.open(url.path) else {
            throw MediaInspectorError.cannotOpen(url.path)
        }
        let json = handle.inform()

        // …and the classic MediaInfo text report (curated field set) for
        // "Copy report" / raw view. Output options apply at Inform time,
        // so one open serves both.
        handle.option("Complete", "0")
        handle.option("Output", "Text")
        let text = handle.inform()

        var tracks = try MediaReportParser.tracks(fromJSON: json)
        guard !tracks.isEmpty else { throw MediaInspectorError.malformedOutput }

        // HEIF stills report one Image track per tile — collapse to one card.
        tracks = collapsingImageTiles(tracks)

        // ImageIO supplies authoritative pixel dimensions + bit depth for stills,
        // and covers formats libmediainfo can't parse at all (e.g. JPEG XL).
        var imageInfo: ImageInfo?
        let hasAV = tracks.contains { $0.kind == .video || $0.kind == .audio || $0.kind == .text }
        let imageIndex = tracks.firstIndex { $0.kind == .image }
        if imageIndex != nil || !hasAV {
            imageInfo = ImageProbe.probe(url)
        }
        if let info = imageInfo {
            if let idx = imageIndex {
                tracks[idx] = enriching(tracks[idx], with: info)
            } else {
                tracks.append(synthesizedImageTrack(from: info, id: tracks.count))
            }
        }

        return MediaReport(
            fileURL: url,
            engineVersion: MediaReportParser.libraryVersion(fromJSON: json),
            tracks: tracks,
            rawJSON: json,
            textReport: text,
            imageInfo: imageInfo
        )
    }

    /// Inspect a file off the calling actor (safe from the main thread and
    /// safe to call concurrently — inspections are serialised internally).
    public static func inspect(_ url: URL) async throws -> MediaReport {
        try await withCheckedThrowingContinuation { continuation in
            engineQueue.async {
                continuation.resume(with: Result { try inspectSync(url) })
            }
        }
    }

    /// Blocking inspect that is nonetheless safe to call from multiple threads:
    /// the work runs on the shared engine queue, so concurrent callers can't
    /// clobber libmediainfo's shared string buffers (see ``MediaInfoHandle``).
    /// For synchronous contexts that can't `await` — e.g. a Quick Look
    /// extension's completion-handler entry point.
    public static func inspectSerialized(_ url: URL) throws -> MediaReport {
        try engineQueue.sync { try inspectSync(url) }
    }

    /// A libmediainfo output rendering, for export/"Copy report" parity with
    /// MediaInfo's own File ▸ Export.
    public enum ExportFormat: String, CaseIterable, Sendable {
        case text = "Text"
        case json = "JSON"
        case xml = "XML"
        case html = "HTML"

        /// libmediainfo's `Output` option value.
        var engineOption: String { rawValue }
        public var fileExtension: String {
            switch self {
            case .text: return "txt"
            case .json: return "json"
            case .xml: return "xml"
            case .html: return "html"
            }
        }
        public var displayName: String {
            switch self {
            case .text: return "Text"
            case .json: return "JSON"
            case .xml: return "XML"
            case .html: return "HTML"
            }
        }
    }

    /// Render a file's report in one of MediaInfo's export formats.
    /// Uses the complete field set, matching MediaInfo's exports.
    public static func renderSync(_ url: URL, as format: ExportFormat) throws -> String {
        let handle = try MediaInfoHandle()
        handle.option("Complete", "1")
        handle.option("Output", format.engineOption)
        guard handle.open(url.path) else { throw MediaInspectorError.cannotOpen(url.path) }
        return handle.inform()
    }

    /// Async, serialised render (safe to call concurrently). See ``renderSync``.
    public static func render(_ url: URL, as format: ExportFormat) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            engineQueue.async {
                continuation.resume(with: Result { try renderSync(url, as: format) })
            }
        }
    }
}

// MARK: - Still-image track normalisation

/// HEIF stills expose one Image track per tile (plus a "Grid"); keep just the
/// first so the report shows a single image, not dozens.
private func collapsingImageTiles(_ tracks: [MediaTrack]) -> [MediaTrack] {
    let imageIDs = tracks.filter { $0.kind == .image }.map(\.id)
    guard imageIDs.count > 1, let keep = imageIDs.first else { return tracks }
    return tracks.compactMap { track in
        guard track.kind == .image else { return track }
        guard track.id == keep else { return nil }
        // A single tile's StreamSize is meaningless for the assembled image —
        // the file-level size badge already carries the real total.
        let fields = track.fields.filter { !$0.key.hasPrefix("StreamSize") }
        return MediaTrack(id: track.id, kind: .image, fields: fields)
    }
}

/// Merge ImageIO facts into a libmediainfo Image track. Pixel dimensions are
/// taken from ImageIO (authoritative for the assembled image, esp. HEIF tiles);
/// bit depth / color model fill only where libmediainfo was silent.
private func enriching(_ track: MediaTrack, with info: ImageInfo) -> MediaTrack {
    var fields = track.fields
    fields["Width"] = String(info.width)
    fields["Height"] = String(info.height)
    if fields["BitDepth"] == nil, let depth = info.bitDepth { fields["BitDepth"] = String(depth) }
    if fields["ColorSpace"] == nil, let model = info.colorModel { fields["ColorSpace"] = model }
    if let name = info.formatName { fields["DisplayFormat"] = name }
    return MediaTrack(id: track.id, kind: .image, fields: fields)
}

/// Build an Image track purely from ImageIO for formats libmediainfo can't
/// parse (e.g. JPEG XL).
private func synthesizedImageTrack(from info: ImageInfo, id: Int) -> MediaTrack {
    var fields: [String: String] = ["Width": String(info.width), "Height": String(info.height)]
    if let depth = info.bitDepth { fields["BitDepth"] = String(depth) }
    if let model = info.colorModel { fields["ColorSpace"] = model }
    if let name = info.formatName {
        fields["DisplayFormat"] = name
        fields["Format"] = name
    }
    return MediaTrack(id: id, kind: .image, fields: fields)
}
