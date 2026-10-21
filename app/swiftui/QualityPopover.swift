// Stream quality popover, opened from the toolbar capsule: presets first, details on demand.

import AppKit
import SwiftUI

struct MVQualityPopover: View {
    @ObservedObject var model: MVModel
    @State private var showDetails = false
    @Namespace private var presetSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Qualité du stream")
                .font(.system(size: 15, weight: .bold))

            VStack(spacing: 8) {
                ForEach(MVPreset.allCases) { preset in
                    MVPresetCard(model: model, preset: preset, selection: presetSelection)
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
                    Text("Personnaliser")
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

            Button("Tous les réglages…") {
                model.showQuality = false
                model.openSettings?(.image)
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(18)
        .frame(width: 380)
        .onAppear { showDetails = model.preset == .custom }
    }
}

struct MVPresetCard: View {
    @ObservedObject var model: MVModel
    let preset: MVPreset
    /// Shared by the cards: the highlight glides to the picked one.
    let selection: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selected: Bool { model.preset == preset }

    private var summary: String {
        model.summary(for: preset) ?? String(localized: "Pas encore enregistré")
    }

    var body: some View {
        Button {
            withAnimation(.mvGlide) { model.apply(preset) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? mvAccentForeground : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(preset.label).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(summary)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(12)
            .background {
                ZStack {
                    // Opaque base: the popover is glass, and glass never sits on glass
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    if selected {
                        highlight
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var highlight: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let mark = shape.fill(mvAccent.opacity(0.10))
            .overlay(shape.strokeBorder(mvAccentForeground.opacity(0.6), lineWidth: 1.5))
        if reduceMotion {
            mark
        } else {
            mark.matchedGeometryEffect(id: "preset", in: selection)
        }
    }
}

struct MVQualityDetails: View {
    @ObservedObject var model: MVModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Résolution").gridColumnAlignment(.trailing)
                    MVResolutionPicker(model: model)
                        .labelsHidden()
                }
                GridRow {
                    Text("Images/s")
                    MVFpsPicker(model: model)
                        .labelsHidden()
                }
                GridRow {
                    Text("Débit")
                    MVBitrateSlider(model: model)
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
    let title: LocalizedStringKey
    let isOn: Bool
    var help: LocalizedStringKey?
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
                .accessibilityHidden(true)
            Spacer()
            Toggle(title, isOn: Binding(get: { isOn }, set: onChange))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .help(help ?? "")
    }
}
