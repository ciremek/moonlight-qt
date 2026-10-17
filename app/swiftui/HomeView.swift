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
                Button("Réglages") { model.showQuality.toggle() }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Annuler") { model.cancelLaunch() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!model.busy)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $model.showPairing) {
            MVPairingSheet(model: model)
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
                    MVComputerRow(computer: computer)
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
                    model.showQuality = true
                } label: {
                    Label("Réglages", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                Spacer()
                MVKeycap("⌘,")
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer").font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(computer.name).font(.system(size: 13, weight: .semibold))
                Text(computer.online ? (computer.paired ? "En ligne" : "Non appairé") : "Hors ligne")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(computer.online ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .help(computer.online ? "En ligne" : "Hors ligne")
                .accessibilityElement()
                .accessibilityLabel(computer.online ? "En ligne" : "Hors ligne")
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
                    Text("Moonvibe cherche les PC qui font tourner Sunshine ou Apollo sur ton réseau.")
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
                                    .onTapGesture(count: 2) { model.launch(app, on: computer) }
                                    .simultaneousGesture(TapGesture().onEnded {
                                        model.selectedAppId = app.id
                                        gridFocused = true
                                    })
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
                        .disabled(!computer.canWake || computer.online)
                    if let running = computer.runningApp {
                        Button("Quitter \(running.name)…") { model.confirmQuitComputerId = computer.id }
                    }
                    Divider()
                    Button("Supprimer \(computer.name)…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .help("Plus d'actions")
            }
        }
        .background {
            // ⌘1, ⌘2, ⌘3 launch the first apps
            Group {
                ForEach(Array(apps.prefix(3).enumerated()), id: \.element.id) { index, app in
                    Button("Lancer \(app.name)") { model.launch(app, on: computer) }
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
            Text("Il faudra l'appairer à nouveau pour streamer. L'app Moonlight officielle n'est pas concernée.")
        }
    }
}

struct MVComputerBanner: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: computer.online ? "lock" : "moon.zzz")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(computer.online ? "\(computer.name) n'est pas appairé" : "\(computer.name) est hors ligne")
                    .font(.system(size: 13, weight: .semibold))
                Text(computer.online
                     ? "Appaire ce Mac une fois pour pouvoir streamer."
                     : "Allume le PC ou réveille-le à distance.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !computer.online && computer.canWake {
                Button("Réveiller") { model.wake(computer) }
                    .controlSize(.large)
            } else if computer.online && !computer.paired {
                Button("Appairer") { model.openPairing(for: computer) }
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.4))
    }
}

struct MVRunningBanner: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer
    let app: MVApp

    var body: some View {
        let confirming = model.confirmQuitComputerId == computer.id

        HStack(spacing: 12) {
            if confirming {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: 0xB42318))
                Text("Quitter **\(app.name)** sur \(computer.name) ? Le travail non enregistré sera perdu.")
                    .font(.system(size: 13))
                Spacer()
                Button("Annuler") { model.confirmQuitComputerId = nil }
                Button("Quitter", role: .destructive) { model.quitRunningApp(on: computer) }
                    .tint(Color(hex: 0xB42318))
                    .buttonStyle(.borderedProminent)
            } else {
                Circle().fill(Color(hex: 0x28B44B)).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text("**\(app.name)** tourne sur \(computer.name)")
                    .font(.system(size: 13))
                Spacer()
                Button("Quitter l'app") { model.confirmQuitComputerId = computer.id }
                    .disabled(model.busy)
                    .help("Ferme \(app.name) sur le PC")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background((confirming ? Color(hex: 0xB42318) : Color(hex: 0x28B44B)).opacity(0.08))
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
                            .strokeBorder(highlighted ? mvAccent : .clear, lineWidth: 3)
                            .opacity(selected ? 1 : 0.55)
                    }

                if running {
                    Text("En cours")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: 0x28B44B)))
                        .padding(10)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let subtitle = app.subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .saturation(enabled ? 1 : 0)
        .opacity(enabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
        .accessibilityHint("Double-clic pour lancer")
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
                Circle().fill(mvAccent).frame(width: 7, height: 7)
                Text("\(model.preset.label) · \(model.qualitySummary)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
        }
        .help("Qualité du stream (⌘,)")
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
                let resuming = app.id == computer.runningAppId
                MVPrimaryButton(title: "\(resuming ? "Reprendre" : "Lancer") \(app.name)",
                                busy: model.busy,
                                disabled: !model.canLaunch(on: computer)) {
                    model.launch(app, on: computer)
                }
                .fixedSize()
                .help("Pendant le stream : ⌃⌥⇧Q pour quitter, ⌃⌥⇧S pour les stats, ⌃⌥⇧Z pour libérer la souris")
            }

            Text(model.busy ? "\(model.status)  ·  esc pour annuler" : model.status)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Divider() }
    }
}

struct MVPrimaryButton: View {
    let title: String
    let busy: Bool
    let disabled: Bool
    let action: () -> Void

    private var label: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "play.fill")
            }
            Text(title).fontWeight(.semibold)
            Text("↩").font(.system(size: 11, weight: .medium)).opacity(0.7)
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
