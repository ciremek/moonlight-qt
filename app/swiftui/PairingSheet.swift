// Pairing sheet: find a PC, show the PIN to type into Sunshine, confirm.

import AppKit
import SwiftUI

struct MVPairingSheet: View {
    @ObservedObject var model: MVModel

    var body: some View {
        Group {
            switch model.pairingStep {
            case .search:
                MVPairingSearch(model: model)
            case .waiting(let computerId, let pin):
                MVPairingPin(model: model, computer: computer(computerId), pin: pin)
            case .paired(let computerId):
                MVPairingDone(model: model, computer: computer(computerId))
            case .failed(let computerId, let error):
                MVPairingFailed(model: model, computer: computer(computerId), error: error)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func computer(_ id: String) -> MVComputer? {
        model.computers.first { $0.id == id }
    }
}

private struct MVSheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 20, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Step 1: search

struct MVPairingSearch: View {
    @ObservedObject var model: MVModel
    @State private var address = ""

    private var candidates: [MVComputer] {
        model.computers.filter { $0.online && !$0.paired }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MVSheetHeader(title: "Ajouter un ordinateur",
                          subtitle: "Moonvibe cherche les PC qui font tourner Sunshine ou Apollo sur ton réseau.")

            VStack(alignment: .leading, spacing: 0) {
                Text("Sur ton réseau")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(candidates) { computer in
                        HStack(spacing: 10) {
                            Image(systemName: "desktopcomputer").font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(computer.name).font(.system(size: 13, weight: .semibold))
                                Text("Prêt à appairer").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Appairer") { model.pair(computer) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        Divider().padding(.leading, 12)
                    }
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Recherche en cours…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Ou ajoute-le à la main")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Adresse IP ou nom, ex. 192.168.1.53", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.addHost(address) }
                    Button {
                        model.addHost(address)
                    } label: {
                        if model.addingHost {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Ajouter")
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || model.addingHost)
                }
                if let error = model.addHostError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xB42318))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("Annuler") { model.showPairing = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

// MARK: - Step 2: PIN

struct MVPairingPin: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer?
    let pin: String
    @State private var copied = false

    private var name: String { computer?.name ?? "ton PC" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MVSheetHeader(title: "Appairer \(name)",
                          subtitle: "Saisis ce code sur \(name) pour autoriser ce Mac.")

            HStack(spacing: 10) {
                ForEach(Array(paddedPin.enumerated()), id: \.offset) { _, digit in
                    Text(String(digit))
                        .font(.system(size: 42, weight: .bold).monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Code \(pin.map(String.init).joined(separator: " "))")

            VStack(alignment: .leading, spacing: 8) {
                MVPairingInstruction(number: 1, text: "Sur \(name), ouvre Sunshine : **localhost:47990**, onglet **PIN**.")
                MVPairingInstruction(number: 2, text: "Saisis le code et un nom pour ce Mac.")
            }

            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("En attente de \(name)…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copié" : "Copier le code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pin, forType: .string)
                    copied = true
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(pin.isEmpty)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))

            HStack {
                Link("Sunshine n'est pas installé ?", destination: URL(string: "https://github.com/LizardByte/Sunshine")!)
                    .font(.system(size: 12))
                Spacer()
                Button("Annuler") { model.pairingStep = .search }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var paddedPin: [Character] {
        let digits = Array(pin)
        return digits.isEmpty ? Array(repeating: "·", count: 4) : digits
    }
}

private struct MVPairingInstruction: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(mvAccent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(mvAccent.opacity(0.14)))
            Text(text).font(.system(size: 13))
        }
    }
}

// MARK: - Step 3: paired

struct MVPairingDone: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer?

    private var appsText: String {
        let names = computer?.apps.map(\.name) ?? []
        switch names.count {
        case 0: return "Ses apps arrivent dans un instant."
        case 1: return "\(names[0]) est disponible."
        default: return names.dropLast().joined(separator: ", ") + " et \(names.last!) sont disponibles."
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(hex: 0x28B44B))
            Text("\(computer?.name ?? "Ton PC") est prêt")
                .font(.system(size: 20, weight: .bold))
            Text(appsText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            MVPrimaryButton(title: "C'est parti", busy: false, disabled: false) {
                model.finishPairing()
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Errors

struct MVPairingFailed: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer?
    let error: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: 0xB42318))
                Text("L'appairage n'a pas abouti")
                    .font(.system(size: 20, weight: .bold))
            }
            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Annuler") { model.pairingStep = .search }
                    .keyboardShortcut(.cancelAction)
                if let computer {
                    Button("Réessayer") { model.pair(computer) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
