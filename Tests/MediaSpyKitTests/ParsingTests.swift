import Foundation
import Testing
@testable import MediaSpyKit

// Hermetic tests over a captured libmediainfo JSON shape (trimmed from real
// output). Live-file coverage comes from the mediaspy CLI.

private let sampleJSON = """
{
"creatingLibrary": {"name": "MediaInfoLib", "version": "26.05", "url": "https://mediaarea.net/MediaInfo"},
"media": {
  "@ref": "/tmp/sample.mkv",
  "track": [
    {"@type": "General", "Format": "Matroska", "FileExtension": "mkv",
     "FileSize": "73400320", "FileSize_String": "70.0 MiB",
     "Duration": "9966.000", "Duration_String": "2 h 46 min",
     "OverallBitRate": "54800000", "OverallBitRate_String": "54.8 Mb/s",
     "Encoded_Application": "mkvmerge 84.0", "VideoCount": "1", "AudioCount": "2", "TextCount": "2",
     "extra": {"ErrorDetectionType": "Per level 1"}},
    {"@type": "Video", "Format": "HEVC", "Format_Profile": "Main 10",
     "Format_Level": "5.1", "Format_Tier": "High",
     "Width": "3840", "Height": "2160", "FrameRate": "23.976",
     "BitRate": "48000000", "BitRate_String": "48.0 Mb/s",
     "ChromaSubsampling": "4:2:0", "BitDepth": "10",
     "ScanType": "Progressive", "colour_primaries": "BT.2020",
     "HDR_Format": "SMPTE ST 2086", "HDR_Format_Compatibility": "HDR10",
     "FrameCount": "238944", "Language": "en", "Language_String": "English"},
    {"@type": "Audio", "@typeorder": "1", "Format": "MLP FBA",
     "Format_Commercial_IfAny": "Dolby TrueHD with Dolby Atmos",
     "Channels": "8", "ChannelLayout": "L R C LFE Ls Rs Lb Rb",
     "SamplingRate": "48000", "SamplingRate_String": "48.0 kHz",
     "Language_String": "English", "Default": "Yes", "Title": "Surround 7.1"},
    {"@type": "Audio", "@typeorder": "2", "Format": "AC-3",
     "Format_Commercial_IfAny": "Dolby Digital", "Channels": "2",
     "SamplingRate_String": "48.0 kHz", "Language_String": "English",
     "Title": "Director commentary"},
    {"@type": "Text", "@typeorder": "1", "Format": "PGS", "Language": "en",
     "Language_String": "English", "Default": "Yes", "Title": "Full"},
    {"@type": "Text", "@typeorder": "2", "Format": "UTF-8", "Language": "en",
     "Language_String": "English", "Forced": "Yes", "Title": "Signs & songs (SDH)"}
  ]
}
}
"""

@Suite struct ParsingTests {
    @Test func parsesTrackList() throws {
        let tracks = try MediaReportParser.tracks(fromJSON: sampleJSON)
        #expect(tracks.count == 6)
        #expect(tracks[0].kind == .general)
        #expect(tracks[1].kind == .video)
        #expect(tracks.filter { $0.kind == .audio }.count == 2)
        #expect(tracks.filter { $0.kind == .text }.count == 2)
    }

    @Test func flattensExtraFields() throws {
        let tracks = try MediaReportParser.tracks(fromJSON: sampleJSON)
        #expect(tracks[0]["extra.ErrorDetectionType"] == "Per level 1")
    }

    @Test func readsLibraryVersion() {
        #expect(MediaReportParser.libraryVersion(fromJSON: sampleJSON) == "26.05")
    }

    @Test func fieldFallbackOrder() throws {
        let tracks = try MediaReportParser.tracks(fromJSON: sampleJSON)
        let general = tracks[0]
        #expect(general.value("FileSize_String", "FileSize") == "70.0 MiB")
        #expect(general.value("Missing", "FileSize") == "73400320")
        #expect(general.value("Missing", "AlsoMissing") == nil)
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: MediaInspectorError.malformedOutput) {
            _ = try MediaReportParser.tracks(fromJSON: "not json")
        }
    }
}

@Suite struct CuratedTests {
    private func report() throws -> MediaReport {
        MediaReport(
            fileURL: URL(fileURLWithPath: "/tmp/sample.mkv"),
            engineVersion: "26.05",
            tracks: try MediaReportParser.tracks(fromJSON: sampleJSON),
            rawJSON: sampleJSON,
            textReport: ""
        )
    }

    @Test func fileSummaryBadges() throws {
        let summary = Curated.fileSummary(for: try report())
        #expect(summary.containerBadge == "Matroska · MKV")
        #expect(summary.badges.contains("70.0 MiB"))
        #expect(summary.badges.contains("2 h 46 min"))
        #expect(summary.badges.contains("54.8 Mb/s overall"))
        #expect(summary.badges.contains("1 video · 2 audio · 2 text"))
        #expect(summary.hdrBadge == "HDR10")
        #expect(summary.aspectBadge == "16:9")
        #expect(summary.resolutionCaption == "3840×2160 · UHD")
    }

    @Test func videoPresentation() throws {
        let video = try #require(try report().videoTracks.first)
        #expect(Curated.videoCodecName(video) == "H.265 · HEVC")
        #expect(Curated.videoGeometry(video) == "3840×2160 · 16:9 · 23.976 fps")

        let rows = Curated.videoRows(video)
        #expect(rows.contains(.init("PROFILE", "Main 10@L5.1@High")))
        #expect(rows.contains(.init("CHROMA", "4:2:0 · 10-bit")))
        #expect(rows.contains(.init("HDR", "HDR10")))
        #expect(rows.contains(.init("FRAMES", "238,944")))

        let gauge = try #require(Curated.bitrateGauge(video))
        #expect(gauge.tier == .high)  // 48 Mb/s UHD ≈ 0.24 bpp
    }

    @Test func noBitrateGaugeForAnimatedGIF() {
        let gif = MediaTrack(id: 0, kind: .video, fields: [
            "Format": "GIF", "BitRate": "1833000", "Width": "450", "Height": "252", "FrameRate": "10",
        ])
        #expect(Curated.bitrateGauge(gif) == nil)
    }

    @Test func audioPresentation() throws {
        let audio = try report().audioTracks
        #expect(Curated.audioCodecName(audio[0]) == "TrueHD Atmos")
        #expect(Curated.audioCodecName(audio[1]) == "AC-3")
        let rows = Curated.audioRows(audio[0])
        #expect(rows.contains(.init("CHANNELS", "8 · 7.1")))
    }

    @Test func subtitleFlags() throws {
        let rows = Curated.subtitleRows(try report().textTracks)
        #expect(rows.count == 2)
        #expect(rows[0].format == "PGS")
        #expect(rows[0].flags == ["DEFAULT"])
        #expect(rows[1].format == "SRT")
        #expect(rows[1].flags == ["FORCED", "SDH"])
    }

    @Test func shortDateHandlesPrefixAndSuffixZone() {
        // Classic MediaInfo puts the zone first; some builds put it last.
        #expect(Curated.shortDate("UTC 2015-08-07 12:00:00") == "2015-08-07")
        #expect(Curated.shortDate("2026-02-19 03:47:23 UTC") == "2026-02-19")
        #expect(Curated.shortDate("2026-02-19") == "2026-02-19")
    }

    @Test func aspectSnapping() {
        let portrait = MediaTrack(id: 0, kind: .video, fields: ["Width": "1080", "Height": "1920"])
        #expect(Curated.aspectRatio(portrait) == "9:16")
        let scope = MediaTrack(id: 0, kind: .video, fields: ["Width": "3840", "Height": "1608"])
        #expect(Curated.aspectRatio(scope) == "2.39:1")
    }
}
