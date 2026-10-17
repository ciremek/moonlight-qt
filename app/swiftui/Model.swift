// State of the SwiftUI shell, fed by the Qt host through the bridge (Bridge.swift).

import AppKit
import SwiftUI

// MARK: - Data from the host

struct MVApp: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let boxArt: String

    /// Short description under well-known Sunshine/Apollo apps.
    var subtitle: String? {
        let lower = name.lowercased()
        if lower.contains("virtual") || lower.contains("virtuel") { return "Écran dédié au stream" }
        if lower.contains("desktop") || lower.contains("bureau") { return "Tout l'écran du PC" }
        if lower.contains("big picture") || lower == "steam" { return "Big Picture" }
        return nil
    }

    var symbolName: String {
        let lower = name.lowercased()
        if lower.contains("virtual") || lower.contains("virtuel") { return "plus.rectangle.on.rectangle" }
        if lower.contains("desktop") || lower.contains("bureau") { return "display" }
        if lower.contains("steam") { return "gamecontroller" }
        return "app.dashed"
    }
}

struct MVComputer: Decodable, Identifiable, Hashable {
    let uuid: String
    let name: String
    let online: Bool
    let paired: Bool
    let canWake: Bool
    let runningAppId: Int
    let apps: [MVApp]

    var id: String { uuid }

    var statusText: String {
        if !online { return "Hors ligne" }
        return paired ? "En ligne · appairé" : "En ligne · non appairé"
    }

    var runningApp: MVApp? { apps.first { $0.id == runningAppId } }
}

/// Mirrors StreamingPreferences::ResolutionMode.
enum MVResolutionMode: Int, Codable {
    case fixed = 0, native, safeArea, scaled75, scaled50
}

/// Mirrors StreamingPreferences::WindowMode.
enum MVWindowMode: Int, Codable, CaseIterable, Identifiable {
    case fullscreen = 0, borderless, windowed
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .fullscreen: return "Plein écran"
        case .borderless: return "Fenêtre sans bordure"
        case .windowed: return "Fenêtre"
        }
    }
}

struct MVPrefs: Codable, Equatable {
    var resolutionMode: MVResolutionMode = .native
    var width = 1920
    var height = 1080
    var fps = 60
    var bitrateKbps = 20000
    var windowMode: MVWindowMode = .borderless
    var vsync = true
    var framePacing = false
    var hdr = false
    var muteHost = true
    var disableAwdl = false
}

// MARK: - Presets

enum MVPreset: String, CaseIterable, Identifiable {
    case fluid, balanced, max, custom
    var id: String { rawValue }

    static let selectable: [MVPreset] = [.fluid, .balanced, .max]

    var label: String {
        switch self {
        case .fluid: return "Fluide"
        case .balanced: return "Équilibré"
        case .max: return "Max"
        case .custom: return "Perso"
        }
    }

    var help: String {
        switch self {
        case .fluid: return "Latence minimale, idéal en Wi-Fi."
        case .balanced: return "Le bon compromis pour ton écran."
        case .max: return "Natif, net comme jamais. Câble ou Wi-Fi 6 conseillé."
        case .custom: return "Tes propres réglages."
        }
    }

    var resolutionMode: MVResolutionMode {
        switch self {
        case .fluid: return .scaled50
        case .balanced: return .scaled75
        case .max, .custom: return .native
        }
    }

    var bitrateKbps: Int {
        switch self {
        case .fluid: return 40_000
        case .balanced: return 80_000
        case .max, .custom: return 144_000
        }
    }
}

// MARK: - Display info

/// Native panel resolution and refresh rate of the screen hosting the window.
struct MVDisplay: Equatable {
    var nativeWidth = 1920
    var nativeHeight = 1080
    var safeAreaHeight = 1080
    var maxFps = 60
    /// Global top-left corner in CoreGraphics coordinates, as the Qt host expects.
    var origin = CGPoint.zero

    var hasNotch: Bool { safeAreaHeight != nativeHeight }

    static func of(_ screen: NSScreen?) -> MVDisplay {
        guard let screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return MVDisplay() }

        let displayId = CGDirectDisplayID(number.uint32Value)
        var display = MVDisplay()
        display.origin = CGDisplayBounds(displayId).origin
        display.maxFps = max(screen.maximumFramesPerSecond, 30)

        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(displayId, options) as? [CGDisplayMode]) ?? []
        // kDisplayModeNativeFlag
        if let native = modes.first(where: { $0.ioFlags & 0x0200_0000 != 0 }) {
            display.nativeWidth = native.pixelWidth
            display.nativeHeight = native.pixelHeight
        }

        display.safeAreaHeight = display.nativeHeight
        if screen.safeAreaInsets.top > 0, screen.frame.height > 0 {
            let ratio = (screen.frame.height - screen.safeAreaInsets.top) / screen.frame.height
            display.safeAreaHeight = Int((CGFloat(display.nativeHeight) * ratio).rounded())
        }
        return display
    }

    /// Resolution the stream will use for a given mode, matching Session::applyAutoResolution().
    func resolution(for mode: MVResolutionMode, prefs: MVPrefs) -> (Int, Int) {
        switch mode {
        case .fixed: return (prefs.width, prefs.height)
        case .native: return (nativeWidth, nativeHeight)
        case .safeArea: return (nativeWidth, safeAreaHeight)
        case .scaled75: return ((nativeWidth * 75 / 100) & ~7, (nativeHeight * 75 / 100) & ~7)
        case .scaled50: return ((nativeWidth * 50 / 100) & ~7, (nativeHeight * 50 / 100) & ~7)
        }
    }
}

// MARK: - Recent sessions

struct MVRecent: Codable, Identifiable, Hashable {
    let computerId: String
    let computerName: String
    let appId: Int
    let appName: String
    let date: Date

    var id: String { "\(computerId):\(appId)" }

    var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "hier" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }
}

// MARK: - Model

@MainActor
final class MVModel: ObservableObject {
    @Published var computers: [MVComputer] = []
    @Published var selectedComputerId: String?
    @Published var selectedAppId: Int?
    @Published private(set) var prefs = MVPrefs()
    @Published var display = MVDisplay()
    @Published var recents: [MVRecent] = []
    @Published var search = ""
    @Published var showQuality = false
    @Published var status = ""
    @Published var busy = false
    @Published var errorMessage: String?

    var sendAction: (([String: Any]) -> Void)?
    weak var window: NSWindow?

    private static let recentsKey = "MoonvibeRecents"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.recentsKey),
           let decoded = try? JSONDecoder().decode([MVRecent].self, from: data) {
            recents = decoded
        }
    }

    // MARK: Derived state

    var selectedComputer: MVComputer? { computers.first { $0.id == selectedComputerId } }

    var filteredComputers: [MVComputer] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return computers }
        return computers.filter { computer in
            computer.name.localizedCaseInsensitiveContains(query) ||
            computer.apps.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    func visibleApps(of computer: MVComputer) -> [MVApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !computer.name.localizedCaseInsensitiveContains(query) else { return computer.apps }
        return computer.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// The user's pick, else the app running on the PC (to resume it), else the first one.
    func selectedApp(of computer: MVComputer) -> MVApp? {
        let apps = visibleApps(of: computer)
        return apps.first { $0.id == selectedAppId }
            ?? apps.first { $0.id == computer.runningAppId }
            ?? apps.first
    }

    var preset: MVPreset {
        MVPreset.selectable.first { preset in
            prefs.resolutionMode == preset.resolutionMode &&
            prefs.bitrateKbps == preset.bitrateKbps &&
            prefs.fps == display.maxFps
        } ?? .custom
    }

    var streamResolution: (Int, Int) { display.resolution(for: prefs.resolutionMode, prefs: prefs) }

    var qualitySummary: String {
        let (width, height) = streamResolution
        return "\(width)×\(height) · \(prefs.fps) i/s · \(prefs.bitrateKbps / 1000) Mb/s"
    }

    func canLaunch(on computer: MVComputer) -> Bool {
        computer.online && computer.paired && !busy
    }

    // MARK: Updates from the host

    func update(computers: [MVComputer]) {
        self.computers = computers
        if selectedComputerId == nil || !computers.contains(where: { $0.id == selectedComputerId }) {
            selectedComputerId = computers.first(where: { $0.online && $0.paired })?.id ?? computers.first?.id
        }
    }

    func update(prefs: MVPrefs) {
        self.prefs = prefs
    }

    func refreshDisplay() {
        display = MVDisplay.of(window?.screen ?? NSScreen.main)
    }

    // MARK: Actions

    func setPrefs(_ change: (inout MVPrefs) -> Void) {
        var updated = prefs
        change(&updated)
        guard updated != prefs else { return }
        prefs = updated
        if let data = try? JSONEncoder().encode(updated),
           let object = try? JSONSerialization.jsonObject(with: data) {
            sendAction?(["action": "setPrefs", "prefs": object])
        }
    }

    func apply(_ preset: MVPreset) {
        guard preset != .custom else { return }
        setPrefs {
            $0.resolutionMode = preset.resolutionMode
            $0.bitrateKbps = preset.bitrateKbps
            $0.fps = display.maxFps
        }
    }

    func launch(_ app: MVApp, on computer: MVComputer) {
        guard canLaunch(on: computer) else { return }
        refreshDisplay()
        busy = true
        status = "Connexion à \(computer.name)…"
        rememberRecent(app, on: computer)
        sendAction?([
            "action": "launch",
            "uuid": computer.uuid,
            "appId": app.id,
            "displayX": Int(display.origin.x),
            "displayY": Int(display.origin.y),
        ])
    }

    func launch(_ recent: MVRecent) {
        guard let computer = computers.first(where: { $0.id == recent.computerId }),
              let app = computer.apps.first(where: { $0.id == recent.appId }) else { return }
        selectedComputerId = computer.id
        selectedAppId = app.id
        launch(app, on: computer)
    }

    func cancelLaunch() {
        guard busy else { return }
        sendAction?(["action": "cancel"])
    }

    func wake(_ computer: MVComputer) {
        sendAction?(["action": "wake", "uuid": computer.uuid])
    }

    func quitRunningApp(on computer: MVComputer) {
        status = "Fermeture de l'app en cours sur \(computer.name)…"
        sendAction?(["action": "quitApp", "uuid": computer.uuid])
    }

    func moveSelection(by offset: Int, in computer: MVComputer) {
        let apps = visibleApps(of: computer)
        guard !apps.isEmpty else { return }
        let current = apps.firstIndex { $0.id == selectedApp(of: computer)?.id } ?? 0
        let next = min(max(current + offset, 0), apps.count - 1)
        selectedAppId = apps[next].id
    }

    private func rememberRecent(_ app: MVApp, on computer: MVComputer) {
        let recent = MVRecent(computerId: computer.id, computerName: computer.name,
                              appId: app.id, appName: app.name, date: Date())
        recents.removeAll { $0.id == recent.id }
        recents.insert(recent, at: 0)
        recents = Array(recents.prefix(5))
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: Self.recentsKey)
        }
    }
}
