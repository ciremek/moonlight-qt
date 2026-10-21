// Update check: asks GitHub for Moonvibe's latest release, at launch and twice a day,
// and tells Home when it is newer than this copy. The request carries no personal data,
// and the check can be turned off in Settings.

import Foundation

struct MVUpdate: Equatable {
    let version: String
    let url: URL
}

enum MVUpdateCheck {
    /// UserDefaults key, on by default.
    static let enabledKey = "MoonvibeCheckForUpdates"
    static let interval: Duration = .seconds(12 * 60 * 60)

    private static let latestRelease = URL(string: "https://api.github.com/repos/ciremek/moonvibe/releases/latest")!

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }

    /// The latest release when it is newer than this copy, else nil (including on any error).
    static func fetch() async -> MVUpdate? {
        var request = URLRequest(url: latestRelease, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data)
        else { return nil }

        // Tags look like "moonvibe-v0.4.0"
        let latest = release.tag_name.replacingOccurrences(of: "moonvibe-v", with: "")
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard latest.compare(current, options: .numeric) == .orderedDescending else { return nil }
        return MVUpdate(version: latest, url: release.html_url)
    }
}
