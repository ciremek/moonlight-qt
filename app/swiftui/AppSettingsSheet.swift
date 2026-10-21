// App settings sheet: the tile's look, the quality the app streams at, and the Mac apps
// its streams open and quit.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MVAppSettingsSheet: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer
    let app: MVApp
    @State private var settings: MVAppSettings

    /// Tile icons to pick from: games, genres and a few useful apps.
    private static let symbols = [
        "gamecontroller", "gamecontroller.fill", "desktopcomputer", "display",
        "plus.rectangle.on.rectangle", "app.dashed", "sparkles", "flame.fill",
        "bolt.fill", "crown.fill", "trophy.fill", "shield.fill",
        "target", "scope", "figure.run", "car.fill",
        "airplane", "soccerball", "basketball.fill", "puzzlepiece.fill",
        "dice.fill", "cube.fill", "theatermasks.fill", "wand.and.stars",
        "globe.europe.africa.fill", "map.fill", "music.note", "film.fill",
        "tv.fill", "headphones", "moon.stars.fill", "star.fill",
    ]

    init(model: MVModel, computer: MVComputer, app: MVApp) {
        _model = ObservedObject(wrappedValue: model)
        self.computer = computer
        self.app = app
        _settings = State(initialValue: model.settings(of: app, on: computer))
    }

    private var currentSymbol: String { settings.symbol ?? app.symbolName }

    var body: some View {
        VStack(spacing: 0) {
            MVSheetHeader(title: "Réglages \(mvOf(app.name))")
                .padding(.horizontal, 24)
                .padding(.top, 22)

            Form {
                Section("Apparence") {
                    HStack(alignment: .top, spacing: 20) {
                        MVAppTile(app: app, settings: settings, selected: false, highlighted: false,
                                  running: false, enabled: true)
                            .frame(width: 120)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 12) {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8),
                                      alignment: .leading, spacing: 4) {
                                ForEach(Self.symbols, id: \.self) { symbol in
                                    symbolButton(symbol)
                                }
                            }
                            HStack(spacing: 6) {
                                colorButton(nil)
                                ForEach(MVTileColor.allCases) { colorButton($0) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("Qualité", selection: $settings.preset) {
                        Text("Comme d'habitude").tag(MVPreset?.none)
                        ForEach(MVPreset.builtIn) { preset in
                            Text(preset.label).tag(MVPreset?.some(preset))
                        }
                        if model.customPreset != nil {
                            Text(MVPreset.custom.label).tag(MVPreset?.some(.custom))
                        }
                    }
                } header: {
                    Text("Qualité")
                } footer: {
                    if let preset = settings.preset, let summary = model.summary(for: preset) {
                        Text(summary).monospacedDigit()
                    }
                }

                Section {
                    ForEach(settings.openApps, id: \.self) { path in
                        appRow(path)
                    }
                    Button {
                        chooseApps()
                    } label: {
                        Label("Ajouter une app…", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Toggle("Les quitter à la fin du stream", isOn: $settings.quitOpenedApps)
                        .disabled(settings.openApps.isEmpty)
                        .help("Seulement celles que Moonvibe a ouvertes : une app déjà lancée reste ouverte.")
                } header: {
                    Text("Apps à ouvrir sur ce Mac")
                } footer: {
                    Text("Elles s'ouvrent au lancement du stream, en arrière-plan.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Réinitialiser") { settings = MVAppSettings() }
                    .disabled(settings.isEmpty)
                Spacer()
                Button("Annuler") { model.appSettingsTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    model.setSettings(settings, of: app, on: computer)
                    model.appSettingsTarget = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 640)
    }

    private func symbolButton(_ symbol: String) -> some View {
        let selected = symbol == currentSymbol
        return Button {
            // The guessed icon stays automatic, so it follows a renamed app
            settings.symbol = symbol == app.symbolName ? nil : symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? mvAccent.opacity(0.15) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? mvAccentForeground : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func colorButton(_ color: MVTileColor?) -> some View {
        let selected = settings.color == color
        return Button {
            settings.color = color
        } label: {
            Circle()
                .fill(color?.color ?? Color.secondary.opacity(0.25))
                .frame(width: 20, height: 20)
                .overlay {
                    if color == nil {
                        Image(systemName: "nosign").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? mvAccentForeground : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(color?.label ?? "Sans couleur")
        .accessibilityLabel(color?.label ?? "Sans couleur")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func appRow(_ path: String) -> some View {
        let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        return HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(name)
            Spacer()
            Button {
                settings.openApps.removeAll { $0 == path }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Retirer \(name)")
            .accessibilityLabel("Retirer \(name)")
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ajouter"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !settings.openApps.contains(url.path) {
            settings.openApps.append(url.path)
        }
    }
}
