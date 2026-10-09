import Cocoa
import Quartz  // umbrella exposing QuickLookUI.QLPreviewingController on macOS
import SwiftUI
import MediaSpyKit

/// Quick Look preview for media files — renders a compact, Ember-themed SwiftUI
/// report (built from MediaSpyKit's Curated data layer) via NSHostingController.
/// Native SwiftUI rather than a WKWebView, which doesn't paint reliably inside a
/// sandboxed QL extension.
///
/// Note: macOS prefers its built-in AV preview for .mp4/.mov/.wav and may shadow
/// this; it reliably appears for .mkv and other containers with no native preview.
final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 640))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // `url` is sandbox-readable here; libmediainfo opens it by path.
                // Serialised: QL may prepare several previews concurrently in one
                // extension process, and libmediainfo's char* buffers are shared.
                let report = try MediaInspector.inspectSerialized(url)
                DispatchQueue.main.async {
                    let host = NSHostingController(rootView: QLReportView(report: report))
                    host.view.frame = self.view.bounds
                    host.view.autoresizingMask = [.width, .height]
                    self.addChild(host)
                    self.view.addSubview(host.view)
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async { handler(error) }
            }
        }
    }
}
