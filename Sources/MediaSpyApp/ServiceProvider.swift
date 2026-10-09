import AppKit
import MediaSpyKit

/// Backs the "Get Media Info" right-click Finder Service declared in Info.plist
/// (NSServices). Finder hands the selected files to the app as file URLs on the
/// pasteboard; we open them in the inspector. Registered on `NSApp.servicesProvider`
/// by ``AppDelegate``.
final class MediaInfoServiceProvider: NSObject {
    /// Selector must equal NSMessage ("getMediaInfo") + the implicit ":userData:error:".
    @objc func getMediaInfo(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard
            let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL],
            !urls.isEmpty
        else {
            error.pointee = "No files were provided." as NSString
            return
        }
        // Handler runs off the main thread — hop to main to touch UI/state.
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            AppState.shared.add(urls)
        }
    }
}
