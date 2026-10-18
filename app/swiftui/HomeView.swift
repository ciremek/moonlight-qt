// Home window: sidebar (search, computers, recents), app grid and launch bar.

import AppKit
import SwiftUI

extension Color {
    /// A color that follows the window's light/dark appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// One neutral tile color: indigo is kept for the selection so it stands out.
private let tileFill = Color(light: NSColor(hex: 0xEEF0F4), dark: NSColor(hex: 0x2B2D34))

/// The accent as text, icons and outlines. mvAccent stays the fill under white text,
/// but lacks contrast against dark backgrounds, hence a lighter shade there.
let mvAccentForeground = Color(light: NSColor(hex: 0x4F5BD5), dark: NSColor(hex: 0x8C96F2))
/// Destructive actions and errors as text and icons, readable in both appearances.
let mvDanger = Color(light: NSColor(hex: 0xB42318), dark: NSColor(hex: 0xFF7B72))
/// Destructive buttons, a fill under white text.
let mvDangerFill = Color(hex: 0xB42318)
/// Online and running dots, always next to a text that says the same.
let mvOnline = Color(hex: 0x28B44B)
/// The running badge, a fill under white text.
let mvRunningFill = Color(hex: 0x1E7E36)

/// "de" before a name, elided before a vowel: "d'AZATOTH", "de Steam".
func mvOf(_ name: String) -> String {
    let first = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first
    return first.map { "aeiou".contains($0) } == true ? "d'\(name)" : "de \(name)"
}

// MARK: - Root

struct MVRootView: View {
    @ObservedObject var model: MVModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            MVSidebar(model: model, searchFocused: $searchFocused)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            MVDetail(model: model)
        }
        .frame(minWidth: 940, minHeight: 560)
        .background {
            // Keyboard shortcuts without visible controls
            Group {
                Button("Rechercher") { searchFocused = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Réglages") { model.openSettings?(nil) }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Annuler") { model.cancelLaunch() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!model.busy || !model.cancellable)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $model.showPairing) {
            MVPairingSheet(model: model)
        }
        .sheet(isPresented: Binding(
            get: { model.wakeOptionsComputerId != nil },
            set: { if !$0 { model.wakeOptionsComputerId = nil } }
        )) {
            if let computer = model.computers.first(where: { $0.id == model.wakeOptionsComputerId }) {
                MVWakeOptionsSheet(model: model, computer: computer)
            }
        }
        .alert("Lancement impossible", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Sidebar

struct MVSidebar: View {
    @ObservedObject var model: MVModel
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        List(selection: $model.selectedComputerId) {
            Section("Ordinateurs") {
                ForEach(model.filteredComputers) { computer in
                    MVComputerRow(computer: computer, waking: model.isWaking(computer))
                        .tag(computer.id)
                }
                Button {
                    model.openPairing()
                } label: {
                    Label("Ajouter un ordinateur…", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .selectionDisabled()
            }

            if !model.recents.isEmpty {
                Section("Récents") {
                    ForEach(model.recents) { recent in
                        Button {
                            model.launch(recent)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(recent.appName).font(.system(size: 13))
                                    Text("\(recent.computerName) · \(recent.dateText)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "clock")
                            }
                        }
                        .buttonStyle(.plain)
                        .selectionDisabled()
                        .help("Relancer \(recent.appName) sur \(recent.computerName)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            MVSearchField(text: $model.search, focused: searchFocused)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    model.openSettings?(nil)
                } label: {
                    Label("Réglages", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

struct MVSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher", text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
            if text.isEmpty {
                MVKeycap("⌘K")
            } else {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Effacer la recherche")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.6)))
    }
}

struct MVComputerRow: View {
    let computer: MVComputer
    let waking: Bool

    private var stateText: String {
        if computer.online { return computer.paired ? "En ligne" : "Non appairé" }
        return waking ? "Réveil en cours…" : "Hors ligne"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer").font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(computer.name).font(.system(size: 13, weight: .semibold))
                Text(stateText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(computer.online ? mvOnline : waking ? Color.orange : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }
}

extension View {
    /// Soft fade where content scrolls under the toolbar (Liquid Glass, macOS 26+).
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

struct MVKeycap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(.tertiary, lineWidth: 0.5))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

// MARK: - Detail

struct MVDetail: View {
    @ObservedObject var model: MVModel

    var body: some View {
        Group {
            if let computer = model.selectedComputer {
                MVComputerHome(model: model, computer: computer)
            } else {
                ContentUnavailableView {
                    Label("Aucun ordinateur", systemImage: "desktopcomputer")
                } description: {
                    Text("Les PC de ton réseau qui font tourner Sunshine ou Apollo apparaissent ici.")
                } actions: {
                    Button("Ajouter un ordinateur…") { model.openPairing() }
                }
            }
        }
    }
}

struct MVComputerHome: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer
    @FocusState private var gridFocused: Bool
    @State private var confirmDelete = false

    private let tileMinWidth: CGFloat = 140
    private let spacing: CGFloat = 18

    var body: some View {
        let apps = model.visibleApps(of: computer)
        let selected = model.selectedApp(of: computer)

        VStack(spacing: 0) {
            if !computer.online || !computer.paired {
                MVComputerBanner(model: model, computer: computer)
            } else if let running = computer.runningApp {
                MVRunningBanner(model: model, computer: computer, app: running)
            }

            GeometryReader { geometry in
                let columnCount = max(1, Int((geometry.size.width - 48 + spacing) / (tileMinWidth + spacing)))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinWidth, maximum: 180), spacing: spacing)],
                                  alignment: .leading, spacing: spacing) {
                            ForEach(apps) { app in
                                MVAppTile(app: app,
                                          selected: app.id == selected?.id && gridFocused,
                                          highlighted: app.id == selected?.id,
                                          running: app.id == computer.runningAppId,
                                          enabled: computer.online && computer.paired)
                                    .onTapGesture(count: 2) { model.requestLaunch(app, on: computer) }
                                    .simultaneousGesture(TapGesture().onEnded {
                                        model.selectedAppId = app.id
                                        gridFocused = true
                                    })
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { model.requestLaunch(app, on: computer) }
                                    .accessibilityHint(computer.online ? "Lance l'app" : "Réveille le PC, puis lance l'app")
                            }
                        }
                    }
                    .padding(24)
                }
                .softTopScrollEdge()
                .focusable()
                .focused($gridFocused)
                .focusEffectDisabled()
                .onMoveCommand { direction in
                    switch direction {
                    case .left: model.moveSelection(by: -1, in: computer)
                    case .right: model.moveSelection(by: 1, in: computer)
                    case .up: model.moveSelection(by: -columnCount, in: computer)
                    case .down: model.moveSelection(by: columnCount, in: computer)
                    @unknown default: break
                    }
                }
            }

            MVLaunchBar(model: model, computer: computer, app: selected)
        }
        .navigationTitle(computer.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                MVQualityButton(model: model)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Réveiller") { model.wake(computer) }
                        .disabled(!model.canWake(computer) || model.isWaking(computer))
                    Button("Options de réveil…") { model.wakeOptionsComputerId = computer.id }
                    if let running = computer.runningApp {
                        Button("Quitter \(running.name)…") { model.confirmQuitComputerId = computer.id }
                    }
                    Divider()
                    Button("Supprimer \(computer.name)…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .help("Plus d'actions")
                .accessibilityLabel("Plus d'actions")
            }
        }
        .background {
            // ⌘1, ⌘2, ⌘3 launch the first apps
            Group {
                ForEach(Array(apps.prefix(3).enumerated()), id: \.element.id) { index, app in
                    Button("Lancer \(app.name)") { model.requestLaunch(app, on: computer) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .onAppear { gridFocused = true }
        .confirmationDialog("Supprimer \(computer.name) de Moonvibe ?", isPresented: $confirmDelete) {
            Button("Supprimer", role: .destructive) { model.delete(computer) }
        } message: {
            Text("Il faudra l'appairer à nouveau pour streamer.")
        }
    }
}

struct MVComputerBanner: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer

    var body: some View {
        HStack(spacing: 12) {
            if computer.online {
                icon("lock")
                message("\(computer.name) n'est pas appairé")
                Spacer(minLength: 8)
                Button("Appairer") { model.openPairing(for: computer) }
                    .controlSize(.large)
                    .fixedSize()
            } else {
                switch model.wakeStates[computer.id] {
                case .waking(let since):
                    ProgressView().controlSize(.small).frame(width: 22)
                        .accessibilityHidden(true)
                    message("Réveil \(mvOf(computer.name))…",
                            model.appLaunchingAfterWake(on: computer).map { "\($0.name) se lance dès qu'il répond." })
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(since)).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                    Button("Annuler") { model.cancelWake(computer) }
                        .controlSize(.large)
                        .fixedSize()
                case .noAnswer:
                    icon("exclamationmark.triangle.fill", color: .orange)
                    message("\(computer.name) ne répond pas",
                            "Vérifie le Wake-on-LAN dans son BIOS et son adresse MAC.")
                    Spacer(minLength: 8)
                    Button("Options de réveil…") { model.wakeOptionsComputerId = computer.id }
                        .controlSize(.large)
                        .fixedSize()
                    Button("Réessayer") { model.wake(computer) }
                        .controlSize(.large)
                        .fixedSize()
                case .failed:
                    icon("exclamationmark.triangle.fill", color: mvDanger)
                    message("Réveil impossible", "Vérifie que ce Mac est connecté au réseau.")
                    Spacer(minLength: 8)
                    Button("Réessayer") { model.wake(computer) }
                        .controlSize(.large)
                        .fixedSize()
                case nil:
                    icon("moon.zzz")
                    if model.canWake(computer) {
                        message("\(computer.name) est hors ligne")
                        Spacer(minLength: 8)
                        Button("Réveiller") { model.wake(computer) }
                            .controlSize(.large)
                            .fixedSize()
                    } else {
                        message("\(computer.name) est hors ligne",
                                "Ajoute son adresse MAC pour le réveiller à distance.")
                        Spacer(minLength: 8)
                        Button("Options de réveil…") { model.wakeOptionsComputerId = computer.id }
                            .controlSize(.large)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.4))
    }

    private func icon(_ name: String, color: Color = .secondary) -> some View {
        Image(systemName: name)
            .font(.system(size: 18))
            .foregroundStyle(color)
            .frame(width: 22)
            .accessibilityHidden(true)
    }

    // Two lines at most and first claim on the width, like the running banner
    private func message(_ title: String, _ detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
    }
}

struct MVRunningBanner: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer
    let app: MVApp

    var body: some View {
        let switchTarget = model.confirmSwitch.flatMap { pending in
            pending.computerId == computer.id ? computer.apps.first { $0.id == pending.appId } : nil
        }
        let confirming = model.confirmQuitComputerId == computer.id || switchTarget != nil

        HStack(spacing: 12) {
            if let target = switchTarget {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(mvDanger)
                    .accessibilityHidden(true)
                // Two lines at most, and first claim on the width: an unbounded height here
                // let the text grow one word per line and push the whole window off screen
                Text("Quitter **\(app.name)** pour lancer \(target.name) ? Le travail non enregistré sera perdu.")
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Button("Annuler") { model.confirmSwitch = nil }
                    .fixedSize()
                Button("Quitter et lancer", role: .destructive) { model.quitAndLaunch(target, on: computer) }
                    .tint(mvDangerFill)
                    .buttonStyle(.borderedProminent)
                    .fixedSize()
            } else if confirming {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(mvDanger)
                    .accessibilityHidden(true)
                Text("Quitter **\(app.name)** sur \(computer.name) ? Le travail non enregistré sera perdu.")
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Button("Annuler") { model.confirmQuitComputerId = nil }
                    .fixedSize()
                Button("Quitter", role: .destructive) { model.quitRunningApp(on: computer) }
                    .tint(mvDangerFill)
                    .buttonStyle(.borderedProminent)
                    .fixedSize()
            } else {
                Circle().fill(mvOnline).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text("**\(app.name)** tourne sur \(computer.name)")
                    .font(.system(size: 13))
                Spacer()
                Button("Quitter l'app") { model.confirmQuitComputerId = computer.id }
                    .disabled(model.busy)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background((confirming ? mvDanger : mvOnline).opacity(0.08))
        .animation(.easeInOut(duration: 0.15), value: confirming)
    }
}

struct MVAppTile: View {
    let app: MVApp
    let selected: Bool
    let highlighted: Bool
    let running: Bool
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(highlighted ? mvAccent.opacity(0.12) : tileFill)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay { artwork }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(highlighted ? mvAccentForeground : .clear, lineWidth: 3)
                            .opacity(selected ? 1 : 0.55)
                    }

                if running {
                    Text("En cours")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(mvRunningFill))
                        .padding(10)
                }
            }
            Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .saturation(enabled ? 1 : 0)
        .opacity(enabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    // Icon + tint, as in the design. Sunshine's box art is portrait poster art that
    // gets cropped badly in 4:3 tiles, so it stays unused until the tiles get a poster mode.
    private var artwork: some View {
        Image(systemName: app.symbolName)
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(.primary.opacity(0.75))
    }
}

// MARK: - Toolbar quality capsule

struct MVQualityButton: View {
    @ObservedObject var model: MVModel

    var body: some View {
        Button {
            model.showQuality.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(mvAccentForeground).frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text("\(model.preset.label) · \(model.qualitySummary)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
        }
        .help("Qualité du stream")
        .popover(isPresented: $model.showQuality, arrowEdge: .bottom) {
            MVQualityPopover(model: model)
        }
    }
}

// MARK: - Launch bar

struct MVLaunchBar: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer
    let app: MVApp?

    var body: some View {
        HStack(spacing: 14) {
            if let app {
                primaryButton(for: app)
                    .fixedSize()
                    .help("Pendant le stream : ⌃⌥⇧Q pour quitter, ⌃⌥⇧S pour les stats, ⌃⌥⇧Z pour libérer la souris")
            }

            Text(model.busy && model.cancellable ? "\(model.status)  ·  esc pour annuler" : model.status)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private func primaryButton(for app: MVApp) -> some View {
        if !computer.online, model.canWake(computer), computer.paired {
            // Picking another app while the PC wakes up switches the app it launches
            let waitingForWake = model.appLaunchingAfterWake(on: computer)?.id == app.id
            MVPrimaryButton(title: "Réveiller et lancer \(app.name)",
                            systemImage: "power",
                            busy: waitingForWake || model.busy,
                            disabled: waitingForWake || !model.canWakeAndLaunch(on: computer)) {
                model.requestLaunch(app, on: computer)
            }
        } else {
            let resuming = app.id == computer.runningAppId
            MVPrimaryButton(title: "\(resuming ? "Reprendre" : "Lancer") \(app.name)",
                            busy: model.busy,
                            disabled: !model.canLaunch(on: computer)) {
                model.requestLaunch(app, on: computer)
            }
        }
    }
}

struct MVPrimaryButton: View {
    let title: String
    var systemImage = "play.fill"
    let busy: Bool
    let disabled: Bool
    let action: () -> Void

    private var label: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title).fontWeight(.semibold)
        }
        .padding(.horizontal, 6)
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(disabled)
        } else {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(disabled)
        }
    }
}
