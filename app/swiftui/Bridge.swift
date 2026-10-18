// Window hosting and C entry points called by the Qt host (see moonvibeui.h).

import AppKit
import SwiftUI

public typealias MVActionCallback = @convention(c) (UnsafePointer<CChar>) -> Void

/// Moonvibe indigo, the accent for selection and the primary action.
let mvAccent = Color(red: 0x4F / 255, green: 0x5B / 255, blue: 0xD5 / 255)

@MainActor
final class MVWindowController: NSObject, NSWindowDelegate {
    static var shared: MVWindowController?

    let model = MVModel()
    let window: NSWindow

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Moonvibe"
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        // Size constraints from SwiftUI's split view feed back into the window's layout pass
        // and trip AppKit's constraint update loop, so the window owns its minimum size instead
        let hostingController = NSHostingController(rootView: MVRootView(model: model).tint(mvAccent))
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: 940, height: 560)
        window.delegate = self
        if !window.setFrameUsingName("MoonvibeHomeWindow") {
            window.center()
        }
        window.setFrameAutosaveName("MoonvibeHomeWindow")
        model.window = window
        model.refreshDisplay()
        model.openSettings = { [unowned model] section in
            MVSettingsWindowController.show(model: model, section: section)
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.sendAction?(["action": "quit"])
    }

    func windowDidChangeScreen(_ notification: Notification) {
        model.refreshDisplay()
    }
}

private func decode<T: Decodable>(_ type: T.Type, from json: UnsafePointer<CChar>) -> T? {
    try? JSONDecoder().decode(type, from: Data(String(cString: json).utf8))
}

@_cdecl("mv_ui_show")
public func mvUiShow(_ action: MVActionCallback) {
    MainActor.assumeIsolated {
        let controller = MVWindowController.shared ?? MVWindowController()
        MVWindowController.shared = controller
        controller.model.sendAction = { payload in
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            json.withCString { action($0) }
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.window.makeKeyAndOrderFront(nil)
    }
}

@_cdecl("mv_ui_update_computers")
public func mvUiUpdateComputers(_ json: UnsafePointer<CChar>) {
    guard let computers = decode([MVComputer].self, from: json) else { return }
    MainActor.assumeIsolated {
        MVWindowController.shared?.model.update(computers: computers)
    }
}

@_cdecl("mv_ui_update_prefs")
public func mvUiUpdatePrefs(_ json: UnsafePointer<CChar>) {
    guard let prefs = decode(MVPrefs.self, from: json) else { return }
    MainActor.assumeIsolated {
        MVWindowController.shared?.model.update(prefs: prefs)
    }
}

private struct MVStatus: Decodable {
    let text: String
    let busy: Bool
    let error: Bool
    let cancellable: Bool
}

@_cdecl("mv_ui_set_status")
public func mvUiSetStatus(_ json: UnsafePointer<CChar>) {
    guard let status = decode(MVStatus.self, from: json) else { return }
    MainActor.assumeIsolated {
        guard let model = MVWindowController.shared?.model else { return }
        model.busy = status.busy
        model.cancellable = status.cancellable
        if status.error {
            model.status = ""
            model.cancelPendingLaunch()
            model.errorMessage = status.text
        } else {
            model.status = status.text
        }
    }
}

@_cdecl("mv_ui_update_pairing")
public func mvUiUpdatePairing(_ json: UnsafePointer<CChar>) {
    guard let update = decode(MVPairingUpdate.self, from: json) else { return }
    MainActor.assumeIsolated {
        MVWindowController.shared?.model.update(pairing: update)
    }
}

@_cdecl("mv_ui_add_host_result")
public func mvUiAddHostResult(_ json: UnsafePointer<CChar>) {
    guard let result = decode(MVAddHostResult.self, from: json) else { return }
    MainActor.assumeIsolated {
        MVWindowController.shared?.model.update(addHost: result)
    }
}

@_cdecl("mv_ui_wake_result")
public func mvUiWakeResult(_ json: UnsafePointer<CChar>) {
    guard let result = decode(MVWakeResult.self, from: json) else { return }
    MainActor.assumeIsolated {
        MVWindowController.shared?.model.update(wakeResult: result)
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
