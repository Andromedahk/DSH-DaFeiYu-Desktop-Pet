import AppKit
import CoreGraphics

/// Whether the DeepSeek Harness desktop window ("dsh-desktop") is on screen.
///
/// Detection uses the window server's on-screen window list, which needs
/// neither Accessibility nor Screen Recording permission. A minimised, closed,
/// hidden or other-space window is simply absent from that list. Window titles
/// are withheld without Screen Recording permission, so windows are matched by
/// their owning process rather than by title.
enum DSHWindowWatcher {

    enum Presence {
        /// The host app owns at least one normal window that is on screen.
        case visible
        /// The host app is not running, or every one of its windows is
        /// minimised, closed, hidden or on another Space.
        case hidden
        /// The window list could not be read. Never hide the pet on a guess.
        case unknown
    }

    /// `com.deepseek.dsh` is the shipped identifier of `DeepSeek Harness.app`;
    /// the aliases keep older or self-built desktop bundles working.
    static let targetBundleIdentifiers: Set<String> = [
        "com.deepseek.dsh", "com.deepseek.harness", "com.deepseek.desktop",
    ]

    /// Fallback for builds whose bundle identifier is missing or customised.
    static let targetNames: Set<String> = ["dsh-desktop", "dsh desktop", "deepseek harness"]

    /// Smallest window that counts as a real host window; app-owned helper and
    /// status windows are 1×1 or otherwise tiny.
    private static let minimumSize = (width: 80.0, height: 60.0)

    /// True when the desktop host — or this pet — is the frontmost app. The pet
    /// counts as "not lost": grabbing it must not turn its face angry.
    static func isHostForeground() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return true }
        if let own = Bundle.main.bundleIdentifier, front.bundleIdentifier == own { return true }
        if let identifier = front.bundleIdentifier, targetBundleIdentifiers.contains(identifier) {
            return true
        }
        let names = [front.executableURL?.lastPathComponent.lowercased(),
                     front.localizedName?.lowercased()].compactMap { $0 }
        return names.contains { targetNames.contains($0) }
    }

    static func presence(of targets: Set<String> = targetBundleIdentifiers) -> Presence {
        let owners = NSWorkspace.shared.runningApplications.filter { app in
            if let identifier = app.bundleIdentifier, targets.contains(identifier) { return true }
            guard targets == targetBundleIdentifiers else { return false }
            let names = [app.executableURL?.lastPathComponent.lowercased(),
                         app.localizedName?.lowercased()].compactMap { $0 }
            return names.contains { targetNames.contains($0) }
        }
        guard !owners.isEmpty else { return .hidden }
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return .unknown }

        let pids = Set(owners.map { Int($0.processIdentifier) })
        let isVisible = list.contains { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int, pids.contains(pid),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double
            else { return false }
            return width >= minimumSize.width && height >= minimumSize.height
        }
        return isVisible ? .visible : .hidden
    }
}
