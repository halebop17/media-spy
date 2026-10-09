import Foundation

/// Renders a ``MediaReport`` as a self-contained, Ember-themed HTML document.
///
/// Used by the Quick Look preview extension (data-based `QLPreviewReply`), and
/// available as a nicer alternative to libmediainfo's built-in HTML export.
/// Pure — no SwiftUI/AppKit — so it lives in the Kit and is reused everywhere.
public enum HTMLReport {
    public static func page(for report: MediaReport) -> String {
        let summary = Curated.fileSummary(for: report)
        var body = ""

        // Header: title, path, badges.
        body += "<header>"
        body += "<h1>\(esc(summary.title))</h1>"
        body += "<p class=\"path\">\(esc(summary.path))</p>"
        body += "<div class=\"badges\">"
        body += badge(summary.containerBadge, accent: true)
        for text in summary.badges { body += badge(text) }
        if let hdr = summary.hdrBadge { body += badge(hdr, kind: "hdr") }
        if let aspect = summary.aspectBadge { body += badge(aspect) }
        body += "</div></header>"

        // General.
        body += card(chip: nil, kindClass: "general", title: "GENERAL", subtitle: nil,
                     rows: Curated.generalRows(for: report))

        // Video / Image / Audio / Text streams.
        for track in report.videoTracks {
            body += card(chip: "VIDEO", kindClass: "video",
                         title: Curated.videoCodecName(track),
                         subtitle: Curated.videoGeometry(track),
                         rows: Curated.videoRows(track))
        }
        for track in report.imageTracks {
            body += card(chip: "IMAGE", kindClass: "image",
                         title: Curated.imageCodecName(track),
                         subtitle: Curated.imageGeometry(track),
                         rows: Curated.imageRows(track))
        }
        for track in report.audioTracks {
            body += card(chip: "AUDIO", kindClass: "audio",
                         title: Curated.audioCodecName(track),
                         subtitle: Curated.audioHeadline(track),
                         rows: Curated.audioRows(track))
        }
        if !report.textTracks.isEmpty {
            body += subtitleCard(Curated.subtitleRows(report.textTracks))
        }

        if let version = report.engineVersion {
            body += "<footer>MediaInfoLib \(esc(version)) · MediaSpy</footer>"
        }

        return document(body: body)
    }

    // MARK: - Building blocks

    private static func card(chip: String?, kindClass: String, title: String,
                             subtitle: String?, rows: [CuratedRow]) -> String {
        guard !rows.isEmpty else { return "" }
        var head = "<div class=\"card-head\">"
        if let chip { head += "<span class=\"chip \(kindClass)\">\(esc(chip))</span>" }
        head += "<span class=\"card-title\">\(esc(title))</span>"
        if let subtitle { head += "<span class=\"card-sub\">\(esc(subtitle))</span>" }
        head += "</div>"

        var grid = "<div class=\"grid\">"
        for row in rows {
            grid += "<div class=\"field\"><div class=\"label\">\(esc(row.label))</div>"
            grid += "<div class=\"value\">\(esc(row.value))</div></div>"
        }
        grid += "</div>"
        return "<section class=\"card\">\(head)\(grid)</section>"
    }

    private static func subtitleCard(_ rows: [Curated.SubtitleRow]) -> String {
        var out = "<section class=\"card\"><div class=\"card-head\">"
        out += "<span class=\"chip text\">TEXT</span>"
        out += "<span class=\"card-sub\">\(rows.count) subtitle stream\(rows.count == 1 ? "" : "s")</span></div>"
        out += "<table><thead><tr><th>#</th><th>LANGUAGE</th><th>FORMAT</th><th>TITLE</th><th>FLAGS</th></tr></thead><tbody>"
        for row in rows {
            let flags = row.flags.map { "<span class=\"flag \($0.lowercased())\">\($0)</span>" }.joined()
            out += "<tr><td class=\"idx\">\(row.index)</td><td>\(esc(row.language))</td>"
            out += "<td class=\"dim\">\(esc(row.format))</td><td class=\"dim\">\(esc(row.title))</td>"
            out += "<td class=\"flags\">\(flags)</td></tr>"
        }
        out += "</tbody></table></section>"
        return out
    }

    private static func badge(_ text: String, accent: Bool = false, kind: String? = nil) -> String {
        let cls = accent ? "badge accent" : (kind.map { "badge \($0)" } ?? "badge")
        return "<span class=\"\(cls)\">\(esc(text))</span>"
    }

    // MARK: - Escaping & shell

    private static func esc(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func document(body: String) -> String {
        // Ember tokens mirrored from the app theme. SF Mono / SF Pro via the
        // system font stack — no external fonts (QL sandbox can't fetch them).
        """
        <!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root{color-scheme:dark;}
        *{margin:0;padding:0;box-sizing:border-box;}
        body{background:#17120f;color:#eaded2;
          font-family:ui-monospace,"SF Mono",Menlo,monospace;
          font-size:12px;line-height:1.4;padding:22px;-webkit-font-smoothing:antialiased;}
        h1{font-family:ui-rounded,-apple-system,system-ui,sans-serif;
          font-size:22px;font-weight:700;letter-spacing:-.01em;margin-bottom:5px;color:#eaded2;}
        .path{font-size:10px;color:#857468;margin-bottom:12px;word-break:break-all;}
        .badges,.flags{display:flex;flex-wrap:wrap;gap:6px;}
        .badge{font-size:10.5px;font-weight:500;color:#c9bcb0;
          padding:3px 8px;border:1px solid rgba(255,255,255,.08);
          border-radius:5px;background:rgba(255,255,255,.04);}
        .badge.accent{color:#f2a93b;border-color:rgba(242,169,59,.3);}
        .badge.hdr{color:#b583ff;border-color:rgba(181,131,255,.3);}
        .card{background:#1e1815;border:1px solid rgba(255,255,255,.07);
          border-radius:10px;padding:14px;margin-top:16px;}
        .card-head{display:flex;align-items:center;gap:10px;margin-bottom:12px;flex-wrap:wrap;}
        .chip{font-size:9px;font-weight:700;letter-spacing:.08em;
          padding:3px 7px;border-radius:4px;}
        .chip.video{color:#f2a93b;background:rgba(242,169,59,.14);}
        .chip.audio{color:#b583ff;background:rgba(181,131,255,.14);}
        .chip.text{color:#f26d5b;background:rgba(242,109,91,.14);}
        .chip.image{color:#f26d5b;background:rgba(242,109,91,.14);}
        .card-title{font-size:13px;font-weight:700;color:#eaded2;}
        .card-sub{font-size:11.5px;color:#9a8878;}
        .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:14px;}
        .label{font-size:9px;font-weight:600;letter-spacing:.08em;color:#857468;margin-bottom:3px;}
        .value{font-size:12px;font-weight:500;color:#eaded2;word-break:break-word;}
        table{width:100%;border-collapse:collapse;}
        th{font-size:8.5px;font-weight:600;letter-spacing:.1em;color:#857468;
          text-align:left;padding:6px 8px 6px 0;}
        td{font-size:10.5px;padding:7px 8px 7px 0;border-top:1px solid rgba(255,255,255,.07);}
        td.idx{color:#857468;width:24px;}
        td.dim{color:#9a8878;}
        .flag{font-size:8px;font-weight:700;padding:2px 5px;border-radius:3px;margin-right:4px;}
        .flag.default{color:#f2a93b;background:rgba(242,169,59,.13);}
        .flag.forced{color:#f26d5b;background:rgba(242,109,91,.13);}
        .flag.sdh{color:#b583ff;background:rgba(181,131,255,.13);}
        footer{margin-top:18px;font-size:9px;color:#6a5b50;}
        </style></head><body>\(body)</body></html>
        """
    }
}
