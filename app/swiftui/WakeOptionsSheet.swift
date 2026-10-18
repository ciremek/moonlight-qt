// Wake options sheet: the MAC address the magic packet targets, and a target to wake
// the PC from outside its network.

import SwiftUI

struct MVWakeOptionsSheet: View {
    @ObservedObject var model: MVModel
    let computer: MVComputer
    @State private var mac: String
    @State private var address: String
    @State private var port: String

    init(model: MVModel, computer: MVComputer) {
        _model = ObservedObject(wrappedValue: model)
        self.computer = computer
        let options = model.wakeOptions[computer.id] ?? MVWakeOptions()
        // Shows the address in use, so clearing the field goes back to the reported one
        _mac = State(initialValue: options.mac.isEmpty ? computer.mac : options.mac)
        _address = State(initialValue: options.address)
        _port = State(initialValue: String(options.port))
    }

    private var trimmedMac: String { mac.trimmingCharacters(in: .whitespaces) }
    private var trimmedAddress: String { address.trimmingCharacters(in: .whitespaces) }
    private var portValue: Int? { Int(port.trimmingCharacters(in: .whitespaces)).flatMap { (1...65535).contains($0) ? $0 : nil } }

    private var macValid: Bool { trimmedMac.isEmpty || MVWakeOptions.normalizedMac(trimmedMac) != nil }
    private var portValid: Bool { trimmedAddress.isEmpty || portValue != nil }

    private var macHelp: String {
        computer.mac.isEmpty
            ? "Sur le PC : ipconfig /all, ligne « Adresse physique »."
            : "Détectée sur le PC : \(computer.mac)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MVSheetHeader(title: "Réveil \(mvOf(computer.name))",
                          subtitle: "Le Wake-on-LAN doit être activé dans le BIOS du PC.")

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Adresse MAC")
                TextField("AA:BB:CC:DD:EE:FF", text: $mac)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13).monospaced())
                    .accessibilityLabel("Adresse MAC")
                if macValid {
                    caption(macHelp)
                } else {
                    error("Format attendu : AA:BB:CC:DD:EE:FF.")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Hors de chez toi")
                HStack(spacing: 6) {
                    TextField("IP ou nom DDNS, ex. monpc.freeboxos.fr", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Adresse hors de chez toi")
                    Text("port").font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("9", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .disabled(trimmedAddress.isEmpty)
                        .accessibilityLabel("Port")
                }
                if portValid {
                    caption("Facultatif. Ta box doit rediriger ce port UDP vers le PC.")
                } else {
                    error("Le port va de 1 à 65535.")
                }
            }

            HStack {
                Spacer()
                Button("Annuler") { model.wakeOptionsComputerId = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    model.setWakeOptions(MVWakeOptions(mac: trimmedMac, address: trimmedAddress,
                                                       port: portValue ?? MVWakeOptions().port),
                                         for: computer)
                    model.wakeOptionsComputerId = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!macValid || !portValid)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func error(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(mvDanger)
            .fixedSize(horizontal: false, vertical: true)
    }
}
