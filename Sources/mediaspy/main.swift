import Foundation
import MediaSpyKit

// mediaspy — headless inspector. M1 verification harness for MediaSpyKit and
// future Quick Action helper. Renders the same curated content the app UI shows.
//
//   mediaspy <file>…            curated summary (what the app renders)
//   mediaspy --json <file>…     full JSON (Complete=1) from libmediainfo
//   mediaspy --text <file>…     classic MediaInfo text report

let arguments = Array(CommandLine.arguments.dropFirst())

enum OutputMode { case curated, json, text, xml, html, preview }

var mode: OutputMode = .curated
var paths: [String] = []
var concurrent = false

for argument in arguments {
    switch argument {
    case "--json": mode = .json
    case "--text": mode = .text
    case "--xml": mode = .xml
    case "--html": mode = .html
    case "--preview": mode = .preview   // Ember HTML — the Quick Look content
    case "--concurrent": concurrent = true
    case "--help", "-h":
        print("usage: mediaspy [--json|--text|--xml|--html|--preview|--concurrent] <file>…")
        exit(0)
    default:
        paths.append(argument)
    }
}

// Stress harness: inspect all files at once, as the app does.
if concurrent {
    let results = await withTaskGroup(of: String.self) { group in
        for path in paths {
            group.addTask {
                do {
                    let report = try await MediaInspector.inspect(URL(fileURLWithPath: path))
                    return "OK    \(report.tracks.count) tracks  \(path)"
                } catch {
                    return "FAIL  \(error)  \(path)"
                }
            }
        }
        var lines: [String] = []
        for await line in group { lines.append(line) }
        return lines.sorted()
    }
    results.forEach { print($0) }
    exit(results.contains { $0.hasPrefix("FAIL") } ? 1 : 0)
}

guard !paths.isEmpty else {
    FileHandle.standardError.write(Data("usage: mediaspy [--json|--text] <file>…\n".utf8))
    exit(64)
}

func label(_ row: CuratedRow, width: Int = 14) -> String {
    "  \(row.label.padding(toLength: width, withPad: " ", startingAt: 0))\(row.value)"
}

var failures = 0

for path in paths {
    let url = URL(fileURLWithPath: path)
    let report: MediaReport
    do {
        report = try MediaInspector.inspectSync(url)
    } catch {
        FileHandle.standardError.write(Data("error: \(path): \(error)\n".utf8))
        failures += 1
        continue
    }

    switch mode {
    case .json:
        print(report.rawJSON)
        continue
    case .text:
        print(report.textReport)
        continue
    case .xml, .html:
        let format: MediaInspector.ExportFormat = mode == .xml ? .xml : .html
        if let rendered = try? MediaInspector.renderSync(url, as: format) {
            print(rendered)
        }
        continue
    case .preview:
        print(HTMLReport.page(for: report))
        continue
    case .curated:
        break
    }

    let summary = Curated.fileSummary(for: report)

    print("━━━ \(summary.title)")
    print("    \(summary.path)")
    var badges = [summary.containerBadge] + summary.badges
    if let hdr = summary.hdrBadge { badges.append(hdr) }
    if let aspect = summary.aspectBadge { badges.append(aspect) }
    if let caption = summary.resolutionCaption { badges.append(caption) }
    print("    [\(badges.joined(separator: "] ["))]")
    print("")

    let generalRows = Curated.generalRows(for: report)
    if !generalRows.isEmpty {
        print("  GENERAL")
        for row in generalRows { print(label(row)) }
        print("")
    }

    for track in report.videoTracks {
        print("  VIDEO   \(Curated.videoCodecName(track))  \(Curated.videoGeometry(track))")
        for row in Curated.videoRows(track) { print(label(row)) }
        if let gauge = Curated.bitrateGauge(track) {
            let filled = Int(gauge.fill * 24)
            let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 24 - filled)
            print("  \(bar)  \(gauge.tier.rawValue)")
        }
        print("")
    }

    for track in report.imageTracks {
        print("  IMAGE   \(Curated.imageCodecName(track))  \(Curated.imageGeometry(track))")
        for row in Curated.imageRows(track) { print(label(row)) }
        print("")
    }

    for track in report.audioTracks {
        print("  AUDIO   \(Curated.audioCodecName(track))  \(Curated.audioHeadline(track))")
        for row in Curated.audioRows(track) { print(label(row)) }
        print("")
    }

    let subtitles = Curated.subtitleRows(report.textTracks)
    if !subtitles.isEmpty {
        print("  TEXT    \(subtitles.count) subtitle stream\(subtitles.count == 1 ? "" : "s")")
        for row in subtitles {
            let flags = row.flags.isEmpty ? "" : "  [\(row.flags.joined(separator: "] ["))]"
            let title = row.title.isEmpty ? "" : "  \(row.title)"
            print("    \(String(format: "%2d", row.index))  \(row.language.padding(toLength: 12, withPad: " ", startingAt: 0))\(row.format.padding(toLength: 8, withPad: " ", startingAt: 0))\(title)\(flags)")
        }
        print("")
    }

    if let engine = report.engineVersion {
        print("  — MediaInfoLib \(engine)")
        print("")
    }
}

exit(failures == 0 ? 0 : 1)
