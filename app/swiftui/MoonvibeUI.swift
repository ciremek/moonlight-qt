// SwiftUI shell for Moonvibe (spike).
//
// The Qt backend stays the host process. It pushes state to this module as JSON
// through the C functions exported below (mv_ui_*), and receives user actions
// through the C callbacks passed to mv_ui_show().

import AppKit
import SwiftUI

public typealias MVLaunchCallback = @convention(c) (UnsafePointer<CChar>, Int32) -> Void
public typealias MVQuitCallback = @convention(c) () -> Void

// MARK: - Model

struct MVApp: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct MVComputer: Decodable, Identifiable, Hashable {
    let uuid: String
    let name: String
    let online: Bool
    let paired: Bool
    let runningAppId: Int
    let apps: [MVApp]

    var id: String { uuid }
}

@MainActor
final class MVModel: ObservableObject {
    @Published var computers: [MVComputer] = []
    @Published var selectedComputerId: String?
    @Published var selectedAppId: Int?
    @Published var status: String = ""
    @Published var busy = false

    var launchCallback: MVLaunchCallback?

    var selectedComputer: MVComputer? {
        computers.first { $0.id == selectedComputerId }
    }

    func update(with computers: [MVComputer]) {
        self.computers = computers
        if selectedComputerId == nil || !computers.contains(where: { $0.id == selectedComputerId }) {
            selectedComputerId = computers.first(where: { $0.online && $0.paired })?.id ?? computers.first?.id
        }
    }

    func launch(_ app: MVApp) {
        guard let computer = selectedComputer, computer.online, computer.paired, !busy,
              let launchCallback else { return }
        busy = true
        status = "Lancement de \(app.name)…"
        computer.uuid.withCString { launchCallback($0, Int32(app.id)) }
    }
}

// MARK: - Views

struct MVRootView: View {
    @ObservedObject var model: MVModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedComputerId) {
                Section("Ordinateurs") {
                    ForEach(model.computers) { computer in
                        MVComputerRow(computer: computer)
                            .tag(computer.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let computer = model.selectedComputer {
                MVComputerDetail(model: model, computer: computer)
            } else {
                ContentUnavailableView("Aucun ordinateur",
                                       systemImage: "desktopcomputer",
                                       description: Text("Recherche des PC sur le réseau…"))
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}

struct MVComputerRow: View {
    let computer: MVComputer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(computer.name).font(.system(size: 13, weight: .semibold))
                Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(computer.online ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        if !computer.online { return "Hors ligne" }
        return computer.paired ? "En ligne" : "Non appairé"
    }
}

struct MVComputerDetail: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 18)]

    private var selectedApp: MVApp? {
        computer.apps.first { $0.id == model.selectedAppId } ?? computer.apps.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(computer.apps) { app in
                        MVAppTile(app: app,
                                  selected: app.id == selectedApp?.id,
                                  running: app.id == computer.runningAppId)
                            .onTapGesture(count: 2) { model.launch(app) }
                            .simultaneousGesture(TapGesture().onEnded { model.selectedAppId = app.id })
                    }
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 14) {
                if let app = selectedApp {
                    MVLaunchButton(title: "Lancer \(app.name)", disabled: model.busy || !computer.online || !computer.paired) {
                        model.launch(app)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text("⌃⌥⇧Q quitter le stream").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .navigationTitle(computer.name)
        .navigationSubtitle(computer.online ? (computer.paired ? "En ligne · appairé" : "En ligne · non appairé") : "Hors ligne")
    }
}

struct MVAppTile: View {
    let app: MVApp
    let selected: Bool
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay {
                        Image(systemName: iconName)
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                    }
                if running {
                    Text("En cours")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.85)))
                        .foregroundStyle(.white)
                        .padding(10)
                }
            }
            Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private var iconName: String {
        let lower = app.name.lowercased()
        if lower.contains("steam") { return "gamecontroller" }
        if lower.contains("virtual") || lower.contains("virtuel") { return "plus.rectangle.on.rectangle" }
        if lower.contains("desktop") || lower.contains("bureau") { return "display" }
        return "app.dashed"
    }
}

struct MVLaunchButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) { Label(title, systemImage: "play.fill") }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(disabled)
        } else {
            Button(action: action) { Label(title, systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(disabled)
        }
    }
}

// MARK: - Window

@MainActor
final class MVWindowController: NSObject, NSWindowDelegate {
    static var shared: MVWindowController?

    let model = MVModel()
    let window: NSWindow
    var quitCallback: MVQuitCallback?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Moonvibe"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: MVRootView(model: model))
        window.setFrameAutosaveName("MoonvibeMainWindow")
        window.delegate = self
        if !window.setFrameUsingName("MoonvibeMainWindow") {
            window.center()
        }
    }

    func windowWillClose(_ notification: Notification) {
        quitCallback?()
    }
}

// MARK: - C entry points (called by the Qt host on the main thread)

@_cdecl("mv_ui_show")
public func mvUiShow(_ launch: MVLaunchCallback, _ quit: MVQuitCallback) {
    MainActor.assumeIsolated {
        let controller = MVWindowController.shared ?? MVWindowController()
        MVWindowController.shared = controller
        controller.model.launchCallback = launch
        controller.quitCallback = quit
        NSApp.activate(ignoringOtherApps: true)
        controller.window.makeKeyAndOrderFront(nil)
    }
}

@_cdecl("mv_ui_update_computers")
public func mvUiUpdateComputers(_ json: UnsafePointer<CChar>) {
    let data = Data(String(cString: json).utf8)
    guard let computers = try? JSONDecoder().decode([MVComputer].self, from: data) else { return }
    MainActor.assumeIsolated {
        MVWindowController.shared?.model.update(with: computers)
    }
}

@_cdecl("mv_ui_set_status")
public func mvUiSetStatus(_ text: UnsafePointer<CChar>, _ busy: Bool) {
    let status = String(cString: text)
    MainActor.assumeIsolated {
        guard let model = MVWindowController.shared?.model else { return }
        model.status = status
        model.busy = busy
    }
}

@_cdecl("mv_ui_set_visible")
public func mvUiSetVisible(_ visible: Bool) {
    MainActor.assumeIsolated {
        guard let window = MVWindowController.shared?.window else { return }
        if visible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
        }
    }
}
