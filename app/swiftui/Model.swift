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

/// Mirrors StreamingPreferences, as carried by the bridge (see SwiftUIShell::pushPrefs()).
struct MVPrefs: Codable, Equatable {
    // Image
    var resolutionMode: MVResolutionMode = .native
    var width = 1920
    var height = 1080
    var fps = 60
    var bitrateKbps = 20000
    var unlockBitrate = false
    var windowMode: MVWindowMode = .borderless
    var vsync = true
    var framePacing = false
    var hdr = false
    // Advanced video
    var yuv444 = false
    var videoCodec = 0
    var videoDecoder = 0
    var renderer = 0
    // Audio
    var audioConfig = 0
    var muteHost = true
    var muteOnFocusLoss = false
    // Keyboard and mouse
    var absoluteMouse = false
    var swapMouseButtons = false
    var reverseScroll = false
    var captureSysKeys = 0
    // Gamepad
    var multiController = true
    var backgroundGamepad = false
    var gamepadMouse = true
    var swapFaceButtons = false
    // Computers and network
    var mdns = true
    var detectNetworkBlocking = true
    var disableAwdl = false
    var quitAppAfter = false
    var gameOptimizations = true
    // Misc
    var keepAwake = true
    var showStats = false
    var connectionWarnings = true
    var configurationWarnings = true
    var richPresence = true

    var maxBitrateMbps: Int { unlockBitrate ? 500 : 150 }
}

// MARK: - Presets

enum MVPreset: String, CaseIterable, Identifiable {
    case fluid, balanced, max, custom
    var id: String { rawValue }

    /// The built-in presets, recognized from the current values.
    static let builtIn: [MVPreset] = [.fluid, .balanced, .max]

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
        case .custom: return "Tes réglages à toi, enregistrés dès que tu les modifies."
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

/// The values saved under the Perso preset.
struct MVCustomPreset: Codable, Equatable {
    var resolutionMode: MVResolutionMode
    var width: Int
    var height: Int
    var fps: Int
    var bitrateKbps: Int

    init(_ prefs: MVPrefs) {
        resolutionMode = prefs.resolutionMode
        width = prefs.width
        height = prefs.height
        fps = prefs.fps
        bitrateKbps = prefs.bitrateKbps
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

// MARK: - Pairing

enum MVPairingStep: Equatable {
    /// Pick a PC found on the network, or add one by address.
    case search
    /// Waiting for the user to type the PIN into Sunshine. The PIN is empty until the host sends it.
    case waiting(computerId: String, pin: String)
    case paired(computerId: String)
    case failed(computerId: String, error: String)
}

struct MVPairingUpdate: Decodable {
    let uuid: String
    let stage: String
    let pin: String?
    let error: String?
}

struct MVAddHostResult: Decodable {
    let success: Bool
    let portBlocking: Bool
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
    /// Opens the settings window, on a given section or where it was left.
    var openSettings: ((MVSettingsSection?) -> Void)?
    @Published var status = ""
    @Published var busy = false
    @Published var errorMessage: String?
    @Published var showPairing = false
    @Published var pairingStep = MVPairingStep.search
    @Published var addingHost = false
    @Published var addHostError: String?
    /// Computer whose running app awaits a quit confirmation in the banner.
    @Published var confirmQuitComputerId: String?
    private var openedPairingForEmptyList = false

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
        MVPreset.builtIn.first { preset in
            prefs.resolutionMode == preset.resolutionMode &&
            prefs.bitrateKbps == preset.bitrateKbps &&
            prefs.fps == display.maxFps
        } ?? .custom
    }

    /// Resolution · frame rate · bitrate a preset streams at, on the current display.
    func summary(for preset: MVPreset) -> String? {
        if preset == .custom {
            guard let custom = customPreset else { return nil }
            var values = prefs
            values.width = custom.width
            values.height = custom.height
            let (width, height) = display.resolution(for: custom.resolutionMode, prefs: values)
            return "\(width)×\(height) · \(custom.fps) i/s · \(custom.bitrateKbps / 1000) Mb/s"
        }
        let (width, height) = display.resolution(for: preset.resolutionMode, prefs: prefs)
        return "\(width)×\(height) · \(display.maxFps) i/s · \(preset.bitrateKbps / 1000) Mb/s"
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
        // No PC yet: start with pairing, once
        if computers.isEmpty, !openedPairingForEmptyList {
            openedPairingForEmptyList = true
            openPairing()
        }
        if selectedComputerId == nil || !computers.contains(where: { $0.id == selectedComputerId }) {
            selectedComputerId = computers.first(where: { $0.online && $0.paired })?.id ?? computers.first?.id
        }
    }

    func update(prefs: MVPrefs) {
        self.prefs = prefs
        // Values set before Perso existed (or in the old UI) become the first Perso
        if customPreset == nil, preset == .custom {
            saveCustomPreset()
        }
    }

    // MARK: Perso preset

    @Published private(set) var customPreset: MVCustomPreset? = {
        guard let data = UserDefaults.standard.data(forKey: "MoonvibeCustomPreset") else { return nil }
        return try? JSONDecoder().decode(MVCustomPreset.self, from: data)
    }()

    /// Saves the current image values as Perso. Called whenever they match no built-in preset,
    /// so tweaking resolution, frame rate or bitrate always lands in Perso.
    private func saveCustomPreset() {
        let custom = MVCustomPreset(prefs)
        guard custom != customPreset else { return }
        customPreset = custom
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: "MoonvibeCustomPreset")
        }
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
        if preset == .custom {
            saveCustomPreset()
        }
        if let data = try? JSONEncoder().encode(updated),
           let object = try? JSONSerialization.jsonObject(with: data) {
            sendAction?(["action": "setPrefs", "prefs": object])
        }
    }

    func apply(_ preset: MVPreset) {
        if preset == .custom {
            guard let custom = customPreset else { return }
            setPrefs {
                $0.resolutionMode = custom.resolutionMode
                $0.width = custom.width
                $0.height = custom.height
                $0.fps = custom.fps
                $0.bitrateKbps = custom.bitrateKbps
            }
            return
        }
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

    func openPairing(for computer: MVComputer? = nil) {
        addHostError = nil
        pairingStep = .search
        showPairing = true
        if let computer { pair(computer) }
    }

    func pair(_ computer: MVComputer) {
        pairingStep = .waiting(computerId: computer.id, pin: "")
        sendAction?(["action": "pair", "uuid": computer.uuid])
    }

    func update(pairing: MVPairingUpdate) {
        switch pairing.stage {
        case "waiting": pairingStep = .waiting(computerId: pairing.uuid, pin: pairing.pin ?? "")
        case "paired": pairingStep = .paired(computerId: pairing.uuid)
        default: pairingStep = .failed(computerId: pairing.uuid, error: pairing.error ?? "L'appairage a échoué.")
        }
    }

    func addHost(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !addingHost else { return }
        addingHost = true
        addHostError = nil
        sendAction?(["action": "addHost", "address": trimmed])
    }

    func update(addHost result: MVAddHostResult) {
        addingHost = false
        if !result.success {
            addHostError = result.portBlocking
                ? "PC injoignable : ton réseau semble bloquer la connexion."
                : "PC introuvable à cette adresse. Vérifie qu'il est allumé et que Sunshine tourne."
        }
    }

    func finishPairing() {
        if case .paired(let computerId) = pairingStep {
            selectedComputerId = computerId
            selectedAppId = nil
        }
        showPairing = false
        pairingStep = .search
    }

    func delete(_ computer: MVComputer) {
        if selectedComputerId == computer.id { selectedComputerId = nil }
        recents.removeAll { $0.computerId == computer.id }
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: Self.recentsKey)
        }
        sendAction?(["action": "deleteHost", "uuid": computer.uuid])
    }

    func cancelLaunch() {
        guard busy else { return }
        sendAction?(["action": "cancel"])
    }

    func wake(_ computer: MVComputer) {
        sendAction?(["action": "wake", "uuid": computer.uuid])
    }

    func quitRunningApp(on computer: MVComputer) {
        confirmQuitComputerId = nil
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
