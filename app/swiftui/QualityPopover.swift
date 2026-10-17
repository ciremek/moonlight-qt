// Stream quality popover, opened from the toolbar capsule: presets first, details on demand.

import SwiftUI

struct MVQualityPopover: View {
    @ObservedObject var model: MVModel
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Qualité du stream")
                .font(.system(size: 15, weight: .bold))

            VStack(spacing: 8) {
                ForEach(MVPreset.selectable) { preset in
                    MVPresetCard(model: model, preset: preset)
                }
            }

            // A full-width row rather than DisclosureGroup, whose only hit target is the chevron
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(showDetails ? 90 : 0))
                    Text(model.preset == .custom ? "Personnaliser · Perso" : "Personnaliser")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showDetails ? .isSelected : [])

            if showDetails {
                MVQualityDetails(model: model)
            }
        }
        .padding(18)
        .frame(width: 380)
        .onAppear { showDetails = model.preset == .custom }
    }
}

struct MVPresetCard: View {
    @ObservedObject var model: MVModel
    let preset: MVPreset

    private var selected: Bool { model.preset == preset }

    private var summary: String {
        let (width, height) = model.display.resolution(for: preset.resolutionMode, prefs: model.prefs)
        return "\(width)×\(height) · \(model.display.maxFps) i/s · \(preset.bitrateKbps / 1000) Mb/s"
    }

    var body: some View {
        Button {
            model.apply(preset)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? mvAccent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(preset.label).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(summary)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(preset.help)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                ZStack {
                    // Opaque base: the popover is glass, and glass never sits on glass
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selected ? mvAccent.opacity(0.10) : .clear)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? mvAccent.opacity(0.6) : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MVQualityDetails: View {
    @ObservedObject var model: MVModel

    private var fpsOptions: [Int] {
        let options = [30, 60, 90, 120].filter { $0 <= model.display.maxFps }
        return options.contains(model.prefs.fps) ? options : (options + [model.prefs.fps]).sorted()
    }

    /// One entry of the resolution menu: a mode that follows the display, or a fixed size.
    private struct ResolutionChoice: Hashable {
        let mode: MVResolutionMode
        var width = 0
        var height = 0
    }

    private static let fixedSizes = [(1280, 720), (1920, 1080), (2560, 1440), (3840, 2160)]

    private var relativeChoices: [ResolutionChoice] {
        var modes: [MVResolutionMode] = [.native]
        if model.display.hasNotch { modes.append(.safeArea) }
        modes += [.scaled75, .scaled50]
        return modes.map { ResolutionChoice(mode: $0) }
    }

    private var fixedChoices: [ResolutionChoice] {
        var sizes = Self.fixedSizes
        // Keep a custom size set elsewhere (old settings) selectable
        if model.prefs.resolutionMode == .fixed, !sizes.contains(where: { $0 == (model.prefs.width, model.prefs.height) }) {
            sizes.append((model.prefs.width, model.prefs.height))
        }
        return sizes.map { ResolutionChoice(mode: .fixed, width: $0.0, height: $0.1) }
    }

    private var currentChoice: ResolutionChoice {
        model.prefs.resolutionMode == .fixed
            ? ResolutionChoice(mode: .fixed, width: model.prefs.width, height: model.prefs.height)
            : ResolutionChoice(mode: model.prefs.resolutionMode)
    }

    private func label(_ choice: ResolutionChoice) -> String {
        let (width, height) = model.display.resolution(for: choice.mode, prefs: model.prefs)
        let size = "\(width)×\(height)"
        switch choice.mode {
        case .native: return "Natif · \(size)"
        case .safeArea: return "Natif sans encoche · \(size)"
        case .scaled75: return "75 % · \(size)"
        case .scaled50: return "50 % · \(size)"
        case .fixed:
            switch (choice.width, choice.height) {
            case (1280, 720): return "720p · 1280×720"
            case (1920, 1080): return "1080p · 1920×1080"
            case (2560, 1440): return "1440p · 2560×1440"
            case (3840, 2160): return "4K · 3840×2160"
            default: return "Perso · \(choice.width)×\(choice.height)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Résolution").gridColumnAlignment(.trailing)
                    Picker("Résolution", selection: Binding(
                        get: { currentChoice },
                        set: { choice in
                            model.setPrefs {
                                $0.resolutionMode = choice.mode
                                if choice.mode == .fixed {
                                    $0.width = choice.width
                                    $0.height = choice.height
                                }
                            }
                        }
                    )) {
                        Section("Selon ton écran") {
                            ForEach(relativeChoices, id: \.self) { Text(label($0)).tag($0) }
                        }
                        Section("Fixe") {
                            ForEach(fixedChoices, id: \.self) { Text(label($0)).tag($0) }
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Images/s")
                    Picker("Images/s", selection: Binding(
                        get: { model.prefs.fps },
                        set: { fps in model.setPrefs { $0.fps = fps } }
                    )) {
                        ForEach(fpsOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Débit")
                    HStack {
                        Slider(value: Binding(
                            get: { Double(model.prefs.bitrateKbps) / 1000 },
                            set: { value in model.setPrefs { $0.bitrateKbps = Int(value.rounded()) * 1000 } }
                        ), in: 5...150, step: 1)
                        .labelsHidden()
                        .accessibilityLabel("Débit vidéo")
                        .accessibilityValue("\(model.prefs.bitrateKbps / 1000) mégabits par seconde")
                        Text("\(model.prefs.bitrateKbps / 1000) Mb/s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .trailing)
                    }
                }
                GridRow {
                    Text("Affichage")
                    Picker("Affichage", selection: Binding(
                        get: { model.prefs.windowMode },
                        set: { mode in model.setPrefs { $0.windowMode = mode } }
                    )) {
                        ForEach(MVWindowMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            .font(.system(size: 13))

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                MVOptionToggle(title: "V-Sync", isOn: model.prefs.vsync) { value in
                    model.setPrefs { $0.vsync = value }
                }
                MVOptionToggle(title: "HDR", isOn: model.prefs.hdr) { value in
                    model.setPrefs { $0.hdr = value }
                }
                MVOptionToggle(title: "Couper le son du PC", isOn: model.prefs.muteHost) { value in
                    model.setPrefs { $0.muteHost = value }
                }
                MVOptionToggle(title: "Couper l'AWDL", isOn: model.prefs.disableAwdl,
                               help: "Évite les pics de latence Wi-Fi d'AirDrop pendant le stream.") { value in
                    model.setPrefs { $0.disableAwdl = value }
                }
            }
        }
    }
}

struct MVOptionToggle: View {
    let title: String
    let isOn: Bool
    var help: String?
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Toggle(title, isOn: Binding(get: { isOn }, set: onChange))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .help(help ?? "")
    }
}
