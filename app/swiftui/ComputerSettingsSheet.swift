// PC settings sheet: its name, the addresses Moonvibe reaches it on, and how to wake it.

import SwiftUI

struct MVComputerSettingsSheet: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer

    /// An address added by hand, as edited in the sheet.
    private struct AddressRow: Identifiable {
        let id = UUID()
        var text: String
        var label: String
    }

    @State private var name: String
    @State private var rows: [AddressRow]
    @State private var mac: String
    @State private var wakeAddress: String
    @State private var wakePort: String

    init(model: MVModel, computer: MVComputer) {
        _model = ObservedObject(wrappedValue: model)
        self.computer = computer
        _name = State(initialValue: computer.name)
        _rows = State(initialValue: computer.addresses.filter { $0.kind == "manual" }.map {
            AddressRow(text: $0.text, label: model.addressLabel($0.text, of: computer) ?? "")
        })
        let options = model.wakeOptions[computer.id] ?? MVWakeOptions()
        // Shows the address in use, so clearing the field goes back to the reported one
        _mac = State(initialValue: options.mac.isEmpty ? computer.mac : options.mac)
        _wakeAddress = State(initialValue: options.address)
        _wakePort = State(initialValue: String(options.port))
    }

    private var detectedAddresses: [MVAddress] { computer.addresses.filter { $0.kind != "manual" } }
    private var addedTexts: [String] {
        rows.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedMac: String { mac.trimmingCharacters(in: .whitespaces) }
    private var trimmedWakeAddress: String { wakeAddress.trimmingCharacters(in: .whitespaces) }
    private var wakePortValue: Int? {
        Int(wakePort.trimmingCharacters(in: .whitespaces)).flatMap { (1...65535).contains($0) ? $0 : nil }
    }
    private var macValid: Bool { trimmedMac.isEmpty || MVWakeOptions.normalizedMac(trimmedMac) != nil }
    private var wakePortValid: Bool { trimmedWakeAddress.isEmpty || wakePortValue != nil }

    var body: some View {
        VStack(spacing: 0) {
            MVSheetHeader(title: "Réglages \(mvOf(computer.name))")
                .padding(.horizontal, 24)
                .padding(.top, 22)

            Form {
                Section {
                    TextField("Nom", text: $name)
                }

                Section("Adresses détectées") {
                    if detectedAddresses.isEmpty {
                        Text("Aucune pour l'instant").foregroundStyle(.secondary)
                    }
                    ForEach(detectedAddresses, id: \.self) { address in
                        LabeledContent {
                            if address.active { MVActiveBadge() }
                        } label: {
                            Text(address.text).monospaced()
                            Text(address.kindLabel)
                        }
                    }
                }

                Section {
                    ForEach($rows) { $row in
                        addressRow($row)
                    }
                    Button {
                        rows.append(AddressRow(text: "", label: ""))
                    } label: {
                        Label("Ajouter une adresse", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Adresses ajoutées")
                } footer: {
                    Text("Moonvibe essaie le réseau local en premier quand ce Mac y est, puis les autres adresses.")
                }

                Section {
                    TextField("Adresse MAC", text: $mac, prompt: Text("AA:BB:CC:DD:EE:FF"))
                        .monospaced()
                        .help(computer.mac.isEmpty
                              ? "Sur le PC : ipconfig /all, ligne « Adresse physique »."
                              : "Détectée sur le PC : \(computer.mac).")
                    LabeledContent("Hors de chez toi") {
                        HStack(spacing: 6) {
                            TextField("Adresse hors de chez toi", text: $wakeAddress,
                                      prompt: Text("IP ou nom DDNS"))
                                .labelsHidden()
                            TextField("Port", text: $wakePort, prompt: Text("9"))
                                .labelsHidden()
                                .frame(width: 56)
                                .disabled(trimmedWakeAddress.isEmpty)
                        }
                    }
                    .help("Facultatif. Ta box doit rediriger ce port UDP vers le PC.")
                } header: {
                    Text("Réveil")
                } footer: {
                    if !macValid {
                        Text("Format attendu : AA:BB:CC:DD:EE:FF.").foregroundStyle(mvDanger)
                    } else if !wakePortValid {
                        Text("Le port va de 1 à 65535.").foregroundStyle(mvDanger)
                    } else {
                        Text("Le Wake-on-LAN doit être activé dans le BIOS du PC.")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Annuler") { model.computerSettingsId = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || !macValid || !wakePortValid)
            }
            .padding(16)
        }
        .frame(width: 540, height: 640)
    }

    @ViewBuilder
    private func addressRow(_ row: Binding<AddressRow>) -> some View {
        let text = row.wrappedValue.text.trimmingCharacters(in: .whitespaces)
        let active = computer.addresses.contains { $0.kind == "manual" && $0.active && $0.text == text }
        HStack(spacing: 8) {
            TextField("Adresse", text: row.text, prompt: Text("IP ou nom, ex. 100.91.39.119"))
                .labelsHidden()
                .monospaced()
                .onSubmit { model.testAddress(text, on: computer) }
            TextField("Étiquette", text: row.label, prompt: Text(MVAddress.autoLabel(for: text) ?? "Étiquette"))
                .labelsHidden()
                .frame(width: 110)
            if active {
                MVActiveBadge()
            } else {
                MVAddressTestStatus(test: model.addressTest(text, of: computer)) {
                    model.testAddress(text, on: computer)
                }
                .disabled(text.isEmpty)
            }
            Button {
                rows.removeAll { $0.id == row.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Retirer cette adresse")
            .accessibilityLabel(text.isEmpty ? Text("Retirer cette adresse") : Text("Retirer \(text)"))
        }
    }

    private func save() {
        model.rename(computer, to: trimmedName)

        let initial = computer.addresses.filter { $0.kind == "manual" }.map(\.text)
        if addedTexts != initial {
            model.setUserAddresses(addedTexts, for: computer)
        }
        var labels: [String: String] = [:]
        for row in rows {
            labels[row.text.trimmingCharacters(in: .whitespaces)] = row.label.trimmingCharacters(in: .whitespaces)
        }
        model.setAddressLabels(labels, for: computer)

        model.setWakeOptions(MVWakeOptions(mac: trimmedMac, address: trimmedWakeAddress,
                                           port: wakePortValue ?? MVWakeOptions().port),
                             for: computer)
        model.computerSettingsId = nil
    }
}

/// The address the PC answers on right now.
private struct MVActiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(mvOnline).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("Utilisée").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .fixedSize()
        .help("Le PC répond sur cette adresse en ce moment")
    }
}

/// A Test button, then the outcome of the check.
private struct MVAddressTestStatus: View {
    let test: MVAddressTest?
    let action: () -> Void

    var body: some View {
        switch test {
        case nil:
            Button("Tester", action: action)
                .controlSize(.small)
                .help("Vérifie que ce PC répond à cette adresse")
        case .testing:
            ProgressView().controlSize(.small).frame(width: 20)
                .accessibilityLabel("Test en cours")
        case .ok:
            icon("checkmark.circle.fill", color: mvOnline, help: "C'est bien ce PC qui répond")
        case .otherComputer:
            icon("exclamationmark.triangle.fill", color: .orange, help: "Un autre PC répond à cette adresse")
        case .unreachable:
            icon("wifi.exclamationmark", color: .secondary, help: "Injoignable pour l'instant, elle reste enregistrée")
        case .invalid:
            icon("xmark.octagon.fill", color: mvDanger, help: "Ce n'est pas une adresse valide")
        }
    }

    private func icon(_ name: String, color: Color, help: LocalizedStringKey) -> some View {
        Button(action: action) {
            Image(systemName: name).foregroundStyle(color)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
        .frame(width: 20)
    }
}
