import Foundation

// Curated presentation layer — maps libmediainfo fields onto the rows,
// summaries, and badges the Ember design shows. Shared by the app UI and
// the CLI so both render the same content.

/// One labelled value in a detail card ("BIT RATE" → "19.4 Mb/s").
public struct CuratedRow: Sendable, Equatable, Identifiable {
    public let label: String
    public let value: String
    public var id: String { label }

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// File-level header content (title, badges, stream composition).
public struct FileSummary: Sendable, Equatable {
    public let title: String
    public let path: String
    /// e.g. "QuickTime · MOV", "MPEG-4", "Matroska · MKV", "WAV · PCM"
    public let containerBadge: String
    /// e.g. ["157 MiB", "1 min 7 s", "19.7 Mb/s overall", "1 video · 1 audio"]
    public let badges: [String]
    /// e.g. "HDR10" when the video stream carries HDR metadata.
    public let hdrBadge: String?
    /// e.g. "16:9", "9:16" — for the thumbnail caption / aspect chip.
    public let aspectBadge: String?
    /// e.g. "3840×2160 · UHD" — thumbnail caption.
    public let resolutionCaption: String?
}

/// Bits-per-pixel-derived gauge shown under video streams.
public struct BitrateGauge: Sendable, Equatable {
    public enum Tier: String, Sendable {
        case mastering = "MASTERING QUALITY"
        case high = "HIGH BITRATE"
        case balanced = "BALANCED"
        case low = "LOW BITRATE"
    }

    /// 0…1 fill fraction for the bar.
    public let fill: Double
    public let tier: Tier
}

public enum Curated {
    // MARK: - File summary

    public static func fileSummary(for report: MediaReport) -> FileSummary {
        let general = report.general
        let url = report.fileURL

        // H1 is always the filename (per design); embedded Title tags are
        // often junk (upload IDs) and belong in the General card instead.
        let title = general?["FileName"] ?? url.deletingPathExtension().lastPathComponent
        let ext = (general?["FileExtension"] ?? url.pathExtension).uppercased()
        // .mov reports Format "MPEG-4" with profile "QuickTime" — surface the
        // profile as the container name people actually recognise.
        let formatName = general?["Format_Profile"] == "QuickTime" ? "QuickTime" : (general?["Format"] ?? "")
        let container = containerName(formatName, ext: ext)

        var badges: [String] = []
        if let size = general?.value("FileSize_String", "FileSize") { badges.append(size) }
        if let duration = general?.value("Duration_String", "Duration") { badges.append(duration) }
        if let rate = general?.value("OverallBitRate_String", "OverallBitRate") {
            badges.append("\(commaGroup(rate)) overall")
        }
        if let composition = streamComposition(report) { badges.append(composition) }

        // Video or (for stills) the image track drives the preview geometry.
        let visual = report.videoTracks.first ?? report.imageTracks.first
        return FileSummary(
            title: title,
            path: general?["CompleteName"] ?? url.path,
            containerBadge: container,
            badges: badges,
            hdrBadge: report.videoTracks.first.flatMap(hdrName),
            aspectBadge: visual.flatMap(aspectRatio),
            resolutionCaption: visual.flatMap(resolutionCaption)
        )
    }

    /// "1 video · 1 audio", "1 video · 2 audio · 10 text", "1 audio stream"…
    public static func streamComposition(_ report: MediaReport) -> String? {
        var parts: [String] = []
        let counts: [(Int, String)] = [
            (report.videoTracks.count, "video"),
            (report.audioTracks.count, "audio"),
            (report.textTracks.count, "text"),
            (report.imageTracks.count, "image"),
        ]
        for (count, name) in counts where count > 0 {
            parts.append("\(count) \(name)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    // MARK: - General card

    public static func generalRows(for report: MediaReport) -> [CuratedRow] {
        guard let track = report.general else { return [] }
        var rows: [CuratedRow] = []

        if let format = track.value("Format_String", "Format") {
            let profile = track["Format_Profile"]
            rows.append(.init("FORMAT", profile.map { "\(format) (\($0))" } ?? format))
        }
        if let size = track.value("FileSize_String", "FileSize") { rows.append(.init("FILE SIZE", size)) }
        if let duration = track.value("Duration_String", "Duration") { rows.append(.init("DURATION", duration)) }
        if let rate = track.value("OverallBitRate_String", "OverallBitRate") { rows.append(.init("OVERALL RATE", commaGroup(rate))) }
        if let mode = track.value("OverallBitRate_Mode_String", "OverallBitRate_Mode") { rows.append(.init("RATE MODE", mode)) }
        if let app = track.value("Encoded_Application_String", "Encoded_Application") { rows.append(.init("WRITING APP", app)) }
        if let producer = track["Producer"] { rows.append(.init("PRODUCER", producer)) }
        if let date = track.value("Encoded_Date", "Tagged_Date", "File_Modified_Date") {
            rows.append(.init("ENCODED", shortDate(date)))
        }
        if let rawBrand = track["CodecID"] {
            // CodecID can carry trailing padding ("qt  ") and the compatible
            // list usually repeats the brand — show the first *different* one.
            let brand = rawBrand.trimmingCharacters(in: .whitespaces)
            let sibling = track["CodecID_Compatible"]?
                .split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0 != brand && !$0.isEmpty }
            rows.append(.init("BRAND", sibling.map { "\(brand) · \($0)" } ?? brand))
        }
        if let composition = streamComposition(report) {
            let total = report.tracks.count - 1 // excluding General
            rows.append(.init("STREAMS", total > 3 ? "\(total) total" : composition))
        }
        if let title = track.value("Title", "Movie") { rows.append(.init("TITLE", title)) }
        if let description = track["Description"] { rows.append(.init("DESCRIPTION", description)) }

        return rows
    }

    // MARK: - Video card

    /// "H.264 · AVC" / "H.265 · HEVC" / "Apple ProRes 422 HQ" — headline codec name.
    public static func videoCodecName(_ track: MediaTrack) -> String {
        let format = track["Format"] ?? "?"
        switch format {
        case "AVC": return "H.264 · AVC"
        case "HEVC": return "H.265 · HEVC"
        case "ProRes":
            let profile = track["Format_Profile"].map { " \($0)" } ?? ""
            return "Apple ProRes\(profile)"
        case "MPEG-4 Visual": return "MPEG-4 Visual"
        default: return format
        }
    }

    /// "1080×1920 · 9:16 · 25 fps" — headline geometry summary.
    public static func videoGeometry(_ track: MediaTrack) -> String {
        var parts: [String] = []
        if let width = track["Width"], let height = track["Height"] {
            parts.append("\(width)×\(height)")
        }
        if let aspect = aspectRatio(track) { parts.append(aspect) }
        if let fps = track["FrameRate"] {
            parts.append("\(trimNumber(fps)) fps")
        }
        return parts.joined(separator: " · ")
    }

    public static func videoRows(_ track: MediaTrack) -> [CuratedRow] {
        var rows: [CuratedRow] = []

        if let rate = track.value("BitRate_String", "BitRate", "BitRate_Nominal_String") { rows.append(.init("BIT RATE", commaGroup(rate))) }
        if let profile = profileAtLevel(track) { rows.append(.init("PROFILE", profile)) }

        var chroma: [String] = []
        if let subsampling = track["ChromaSubsampling"] { chroma.append(subsampling) }
        if let depth = track["BitDepth"] { chroma.append("\(depth)-bit") }
        if !chroma.isEmpty { rows.append(.init("CHROMA", chroma.joined(separator: " · "))) }

        if let scan = track.value("ScanType_String", "ScanType") { rows.append(.init("SCAN", scan)) }
        if let color = track.value("colour_primaries", "matrix_coefficients") { rows.append(.init("COLOR", color)) }
        if let hdr = hdrName(track) { rows.append(.init("HDR", hdr)) }

        if let encoding = encodingSummary(track) { rows.append(.init("ENCODING", encoding)) }
        if let language = track.value("Language_String", "Language") { rows.append(.init("LANGUAGE", language)) }
        if let frames = track["FrameCount"] { rows.append(.init("FRAMES", groupDigits(frames))) }

        return rows
    }

    /// "Main@L4.1", "Main 10@L5.1@High" — classic MediaInfo profile@level@tier.
    /// (Newer MediaInfoLib splits these into separate JSON fields.)
    static func profileAtLevel(_ track: MediaTrack) -> String? {
        guard var profile = track["Format_Profile"] else { return nil }
        if let level = track["Format_Level"] { profile += "@L\(level)" }
        if let tier = track["Format_Tier"] { profile += "@\(tier)" }
        return profile
    }

    /// "CABAC · 4 ref" for AVC; encoder library name otherwise.
    static func encodingSummary(_ track: MediaTrack) -> String? {
        var parts: [String] = []
        if track.flag("Format_Settings_CABAC") { parts.append("CABAC") }
        if let refFrames = track["Format_Settings_RefFrames"] { parts.append("\(refFrames) ref") }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return track.value("Encoded_Library_Name", "Format_Settings")
    }

    /// Bits-per-pixel gauge; nil when bitrate/geometry are unknown.
    public static func bitrateGauge(_ track: MediaTrack) -> BitrateGauge? {
        guard
            // Tiers are calibrated for modern codecs; animated GIF (a Video
            // track since libmediainfo 26.10) would always read "mastering".
            track["Format"] != "GIF",
            let bitRate = track.number("BitRate", "BitRate_Nominal"),
            let width = track.number("Width"),
            let height = track.number("Height"),
            let fps = track.number("FrameRate"),
            bitRate > 0, width > 0, height > 0, fps > 0
        else { return nil }

        let bitsPerPixel = bitRate / (width * height * fps)
        let tier: BitrateGauge.Tier =
            bitsPerPixel >= 0.8 ? .mastering :
            bitsPerPixel >= 0.2 ? .high :
            bitsPerPixel >= 0.04 ? .balanced : .low
        // Log-ish mapping so consumer (0.05) and mastering (1+) rates both read.
        let fill = min(1.0, max(0.06, (log10(bitsPerPixel) + 2.0) / 2.5))
        return BitrateGauge(fill: fill, tier: tier)
    }

    // MARK: - Audio card

    /// "AAC LC" / "PCM (Little / Signed)" / "TrueHD Atmos" — headline codec name.
    public static func audioCodecName(_ track: MediaTrack) -> String {
        let format = track["Format"] ?? "?"
        var name = format
        if let features = track["Format_AdditionalFeatures"], features != format {
            name = "\(format) \(features)"
        }
        // Commercial names cover the Dolby/DTS family ("Dolby TrueHD with
        // Dolby Atmos" → shown compactly).
        if let commercial = track["Format_Commercial_IfAny"] {
            switch commercial {
            case "Dolby TrueHD with Dolby Atmos": name = "TrueHD Atmos"
            case "Dolby Digital Plus with Dolby Atmos": name = "E-AC-3 Atmos"
            case "Dolby Digital": name = "AC-3"
            default: name = commercial
            }
        }
        if format == "PCM" {
            var settings: [String] = []
            if let endianness = track["Format_Settings_Endianness"] { settings.append(endianness) }
            if let sign = track["Format_Settings_Sign"] { settings.append(sign) }
            if !settings.isEmpty { name = "PCM (\(settings.joined(separator: " / ")))" }
        }
        return name
    }

    /// "48.0 kHz · 2 ch · 317 kb/s" — headline summary next to the codec name.
    public static func audioHeadline(_ track: MediaTrack) -> String {
        var parts: [String] = []
        if let sampling = track.value("SamplingRate_String", "SamplingRate") { parts.append(sampling) }
        if let channels = track["Channels"] { parts.append("\(channels) ch") }
        if let rate = track.value("BitRate_String", "BitRate") { parts.append(rate) }
        return commaGroup(parts.joined(separator: " · "))
    }

    public static func audioRows(_ track: MediaTrack) -> [CuratedRow] {
        var rows: [CuratedRow] = []

        if let rate = track.value("BitRate_String", "BitRate") {
            let mode = track["BitRate_Mode"]
            rows.append(.init("BIT RATE", commaGroup(mode.map { "\(rate) \($0)" } ?? rate)))
        }
        if let sampling = track.value("SamplingRate_String", "SamplingRate") { rows.append(.init("SAMPLE RATE", sampling)) }
        if let depth = track["BitDepth"] { rows.append(.init("BIT DEPTH", "\(depth) bits")) }
        if let channels = track["Channels"] {
            let layout = channelLayoutName(track)
            rows.append(.init("CHANNELS", layout.map { "\(channels) · \($0)" } ?? channels))
        }
        if track["Format"] == "PCM" {
            var endian: [String] = []
            if let endianness = track["Format_Settings_Endianness"] { endian.append(endianness) }
            if let sign = track["Format_Settings_Sign"] { endian.append(sign) }
            if !endian.isEmpty { rows.append(.init("ENDIAN", endian.joined(separator: " / "))) }
        }
        if let language = track.value("Language_String", "Language") { rows.append(.init("LANGUAGE", language)) }
        if let title = track["Title"] { rows.append(.init("TITLE", title)) }

        return rows
    }

    /// "Stereo", "5.1", "7.1", "Mono" — friendly channel-layout name.
    static func channelLayoutName(_ track: MediaTrack) -> String? {
        if let positions = track["ChannelPositions_String2"] ?? track["ChannelLayout"] {
            // "2/0/0" style from _String2; layout strings like "L R" otherwise.
            switch positions {
            case "2/0/0", "L R": return "Stereo"
            case "1/0/0", "C": return "Mono"
            case "3/2/0.1", "3/2.1": return "5.1"
            case "3/4/0.1", "3/4.1": return "7.1"
            default: break
            }
        }
        guard let channels = track.number("Channels") else { return nil }
        switch Int(channels) {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return nil
        }
    }

    // MARK: - Image card (stills: JPEG, PNG, HEIC, …)

    /// "JPEG" / "PNG" / "HEIC" / "JPEG XL" — headline format name.
    public static func imageCodecName(_ track: MediaTrack) -> String {
        track.value("DisplayFormat", "Format_Commercial", "Format") ?? "Image"
    }

    /// "489 × 475 · 1:1" — headline geometry summary.
    public static func imageGeometry(_ track: MediaTrack) -> String {
        var parts: [String] = []
        if let width = track["Width"], let height = track["Height"] {
            parts.append("\(width) × \(height)")
        }
        if let aspect = aspectRatio(track) { parts.append(aspect) }
        return parts.joined(separator: " · ")
    }

    public static func imageRows(_ track: MediaTrack) -> [CuratedRow] {
        var rows: [CuratedRow] = []
        if let width = track["Width"], let height = track["Height"] {
            rows.append(.init("RESOLUTION", "\(width) × \(height)"))
        }
        if let depth = track["BitDepth"] { rows.append(.init("BIT DEPTH", "\(depth)-bit")) }
        if let space = track["ColorSpace"] { rows.append(.init("COLOR SPACE", space)) }
        if let subsampling = track["ChromaSubsampling"] { rows.append(.init("CHROMA", subsampling)) }

        if let compression = track.value("Compression_Mode_String", "Compression_Mode") {
            rows.append(.init("COMPRESSION", compression))
        }
        if let size = track.value("StreamSize_String1", "StreamSize_String") {
            rows.append(.init("STREAM SIZE", commaGroup(size)))
        }
        return rows
    }

    // MARK: - Text (subtitle) table

    public struct SubtitleRow: Sendable, Equatable, Identifiable {
        public let id: Int
        public let index: Int
        public let language: String
        public let format: String
        public let title: String
        public let flags: [String]  // DEFAULT / FORCED / SDH
    }

    public static func subtitleRows(_ tracks: [MediaTrack]) -> [SubtitleRow] {
        tracks.enumerated().map { position, track in
            var flags: [String] = []
            if track.flag("Default") { flags.append("DEFAULT") }
            if track.flag("Forced") { flags.append("FORCED") }
            let title = track["Title"] ?? ""
            if title.localizedCaseInsensitiveContains("SDH")
                || title.localizedCaseInsensitiveContains("hearing") {
                flags.append("SDH")
            }
            return SubtitleRow(
                id: track.id,
                index: position + 1,
                language: track.value("Language_String", "Language") ?? "—",
                format: subtitleFormatName(track),
                title: title,
                flags: flags
            )
        }
    }

    static func subtitleFormatName(_ track: MediaTrack) -> String {
        switch track["Format"] {
        case "UTF-8", "SubRip": return "SRT"
        case "PGS": return "PGS"
        case let format?: return format
        case nil: return "—"
        }
    }

    // MARK: - Shared helpers

    /// "QuickTime · MOV", "Matroska · MKV", "MPEG-4", "WAV · PCM"…
    static func containerName(_ format: String, ext: String) -> String {
        switch format {
        case "Wave": return "WAV · PCM"
        case "MPEG-4" where ext == "MP4": return "MPEG-4"
        case "": return ext
        default:
            return format.caseInsensitiveCompare(ext) == .orderedSame ? format : "\(format) · \(ext)"
        }
    }

    /// Snap width/height to a friendly aspect like "16:9" / "9:16" / "21:9".
    public static func aspectRatio(_ track: MediaTrack) -> String? {
        guard
            let width = track.number("Width"),
            let height = track.number("Height"),
            width > 0, height > 0
        else { return nil }
        let ratio = width / height
        let known: [(String, Double)] = [
            ("21:9", 21.0 / 9.0), ("2.39:1", 2.39), ("16:9", 16.0 / 9.0),
            ("3:2", 1.5), ("4:3", 4.0 / 3.0), ("1:1", 1.0),
            ("3:4", 0.75), ("2:3", 2.0 / 3.0), ("9:16", 9.0 / 16.0),
        ]
        for (name, value) in known where abs(ratio - value) / value < 0.02 {
            return name
        }
        // Fall back to the reported display aspect ratio, else the decimal.
        return track["DisplayAspectRatio_String"] ?? String(format: "%.2f:1", ratio)
    }

    /// "3840×2160 · UHD" — thumbnail caption with a resolution class.
    static func resolutionCaption(_ track: MediaTrack) -> String? {
        guard let width = track.number("Width"), let height = track.number("Height") else { return nil }
        let dims = "\(Int(width))×\(Int(height))"
        let longEdge = max(width, height)
        let className: String? =
            longEdge >= 7000 ? "8K" :
            longEdge >= 5000 ? "5K+" :
            longEdge >= 3800 ? "UHD" :
            longEdge >= 2500 ? "QHD" : nil
        return className.map { "\(dims) · \($0)" } ?? dims
    }

    /// "HDR10", "Dolby Vision"… from HDR metadata fields.
    static func hdrName(_ track: MediaTrack) -> String? {
        guard track["HDR_Format"] != nil else { return nil }
        if let compatibility = track["HDR_Format_Compatibility"] {
            // e.g. "HDR10" / "HDR10 / HDR10"
            return compatibility.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if let commercial = track["HDR_Format_Commercial"] { return commercial }
        return "HDR"
    }

    /// Extract the calendar date from a MediaInfo date field. The zone marker
    /// appears as a prefix in classic output ("UTC 2015-08-07 12:00:00") and as
    /// a suffix in some builds ("2026-02-19 03:47:23 UTC"), so pull the first
    /// YYYY-MM-DD run rather than blindly truncating.
    static func shortDate(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        if let match = isoDateRegex.firstMatch(in: raw, range: range),
           let r = Range(match.range, in: raw) {
            return String(raw[r])
        }
        return raw.trimmingCharacters(in: .whitespaces)
    }

    private static let isoDateRegex = try! NSRegularExpression(
        pattern: "[0-9]{4}-[0-9]{2}-[0-9]{2}"
    )

    /// "23.976000" → "23.976"; "25.000" → "25".
    static func trimNumber(_ raw: String) -> String {
        guard raw.contains(".") else { return raw }
        var trimmed = raw
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    /// "1675" → "1,675" (comma digit grouping).
    static func groupDigits(_ raw: String) -> String {
        guard let number = Int(raw) else { return raw }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? raw
    }

    /// libmediainfo groups thousands with spaces ("1 536 kb/s"); we render them
    /// with commas ("1,536 kb/s"). Only spaces *between digits* are converted —
    /// the space before a unit ("536 kb/s") is preserved.
    static func commaGroup(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return digitGroupingRegex.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: "$1,$2"
        )
    }

    private static let digitGroupingRegex = try! NSRegularExpression(
        pattern: "([0-9])[ \\u00A0\\u202F]([0-9])"
    )
}
