import Foundation

/// One analysed media file: the parsed track list plus the raw engine outputs.
public struct MediaReport: Sendable, Equatable {
    public let fileURL: URL
    /// libmediainfo version that produced this report (from the JSON envelope).
    public let engineVersion: String?
    /// All tracks in file order — General first, then Video/Audio/Text/Menu…
    public let tracks: [MediaTrack]
    /// Complete JSON output (`Complete=1`) — backs the "all fields" view.
    public let rawJSON: String
    /// Classic MediaInfo text report — backs "Copy report".
    public let textReport: String
    /// ImageIO facts for stills (dimensions/bit depth), when the file is an image.
    public let imageInfo: ImageInfo?

    public init(fileURL: URL, engineVersion: String?, tracks: [MediaTrack], rawJSON: String, textReport: String, imageInfo: ImageInfo? = nil) {
        self.fileURL = fileURL
        self.engineVersion = engineVersion
        self.tracks = tracks
        self.rawJSON = rawJSON
        self.textReport = textReport
        self.imageInfo = imageInfo
    }

    public var general: MediaTrack? { tracks.first { $0.kind == .general } }
    public var videoTracks: [MediaTrack] { tracks.filter { $0.kind == .video } }
    public var audioTracks: [MediaTrack] { tracks.filter { $0.kind == .audio } }
    public var textTracks: [MediaTrack] { tracks.filter { $0.kind == .text } }
    public var menuTracks: [MediaTrack] { tracks.filter { $0.kind == .menu } }
    public var imageTracks: [MediaTrack] { tracks.filter { $0.kind == .image } }
}

/// One stream/track as reported by libmediainfo: a kind plus a flat bag of
/// string fields (nested "extra" fields are flattened with an "extra." prefix).
public struct MediaTrack: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable, Hashable {
        case general, video, audio, text, image, menu
        case other(String)

        init(typeString: String) {
            switch typeString {
            case "General": self = .general
            case "Video": self = .video
            case "Audio": self = .audio
            case "Text": self = .text
            case "Image": self = .image
            case "Menu": self = .menu
            default: self = .other(typeString)
            }
        }
    }

    /// Position in the file's track list (stable identity within one report).
    public let id: Int
    public let kind: Kind
    public let fields: [String: String]

    public init(id: Int, kind: Kind, fields: [String: String]) {
        self.id = id
        self.kind = kind
        self.fields = fields
    }

    public subscript(key: String) -> String? {
        guard let value = fields[key], !value.isEmpty else { return nil }
        return value
    }

    /// First non-empty value among `keys`, in order — the standard way to
    /// read fields that have pretty `_String` variants with raw fallbacks.
    public func value(_ keys: String...) -> String? {
        for key in keys {
            if let value = self[key] { return value }
        }
        return nil
    }

    /// Numeric field access (libmediainfo emits numbers as strings).
    public func number(_ keys: String...) -> Double? {
        for key in keys {
            if let value = self[key], let number = Double(value) { return number }
        }
        return nil
    }

    /// True when a flag field is set ("Yes"), e.g. Default/Forced on subtitles.
    public func flag(_ key: String) -> Bool {
        self[key] == "Yes"
    }
}

/// Parses libmediainfo's JSON output (`{"creatingLibrary":…, "media":{"track":[…]}}`).
enum MediaReportParser {
    static func libraryVersion(fromJSON json: String) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let library = root["creatingLibrary"] as? [String: Any]
        else { return nil }
        return library["version"] as? String
    }

    static func tracks(fromJSON json: String) throws -> [MediaTrack] {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let media = root["media"] as? [String: Any],
            let rawTracks = media["track"] as? [[String: Any]]
        else { throw MediaInspectorError.malformedOutput }

        return rawTracks.enumerated().map { index, raw in
            var fields: [String: String] = [:]
            fields.reserveCapacity(raw.count)
            for (key, value) in raw where !key.hasPrefix("@") {
                flatten(value, into: &fields, key: key)
            }
            let type = raw["@type"] as? String ?? ""
            return MediaTrack(id: index, kind: .init(typeString: type), fields: fields)
        }
    }

    /// Values are almost always strings; "extra" nests one object deep.
    /// Anything else is stringified defensively.
    private static func flatten(_ value: Any, into fields: inout [String: String], key: String) {
        switch value {
        case let string as String:
            fields[key] = string
        case let nested as [String: Any]:
            for (nestedKey, nestedValue) in nested {
                flatten(nestedValue, into: &fields, key: "\(key).\(nestedKey)")
            }
        case let array as [Any]:
            fields[key] = array.map { "\($0)" }.joined(separator: " / ")
        default:
            fields[key] = "\(value)"
        }
    }
}
