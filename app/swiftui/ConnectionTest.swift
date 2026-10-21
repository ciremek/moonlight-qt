// Connection test: latency, jitter and loss between this Mac and a PC, plus the link the
// Mac uses. Many PCs drop pings (Windows' firewall does by default), so each sample is
// the time to open a TCP connection to Sunshine's HTTP port, which streaming needs open:
// the SYN/SYN-ACK round trip, without any app processing in between.

import CoreWLAN
import Foundation
import Network

struct MVConnectionReport: Equatable {
    /// Round trips that succeeded, in milliseconds.
    let samples: [Double]
    let attempts: Int
    /// "Ethernet", "Wi-Fi 6 GHz · canal 5 · 160 MHz"…, or nil when nothing answered.
    let link: String?

    enum Verdict {
        case excellent, fair, unstable
    }

    var lossPercent: Double { attempts == 0 ? 0 : Double(attempts - samples.count) * 100 / Double(attempts) }
    var averageMs: Double { samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count) }

    /// Mean difference between consecutive samples, as RTP measures jitter.
    var jitterMs: Double {
        guard samples.count > 1 else { return 0 }
        let differences = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
        return differences.reduce(0, +) / Double(differences.count)
    }

    var verdict: Verdict {
        if samples.isEmpty || lossPercent >= 2 || averageMs >= 30 || jitterMs >= 8 { return .unstable }
        if lossPercent == 0 && averageMs < 10 && jitterMs < 2 { return .excellent }
        return .fair
    }
}

@MainActor
final class MVConnectionTester: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var progress = 0.0
    @Published private(set) var report: MVConnectionReport?
    private var task: Task<Void, Never>?

    /// About ten seconds: 40 samples, 250 ms apart.
    private static let sampleCount = 40
    private static let interval: Duration = .milliseconds(250)

    func start(host: String, port: Int) {
        task?.cancel()
        report = nil
        progress = 0
        running = true
        task = Task { [weak self] in
            var samples: [Double] = []
            var attempts = 0
            var wired: Bool?
            for index in 0..<Self.sampleCount {
                guard !Task.isCancelled else { return }
                attempts += 1
                if let (ms, isWired) = await Self.connectTime(host: host, port: port) {
                    samples.append(ms)
                    wired = isWired
                }
                self?.progress = Double(index + 1) / Double(Self.sampleCount)
                try? await Task.sleep(for: Self.interval)
            }
            guard let self, !Task.isCancelled else { return }
            report = MVConnectionReport(samples: samples, attempts: attempts, link: Self.linkDescription(wired: wired))
            running = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        running = false
    }

    /// Time to open a TCP connection, and whether it went over Ethernet. Nil after a second
    /// without an answer, which counts as a lost sample.
    private static func connectTime(host: String, port: Int) async -> (Double, Bool)? {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            let queue = DispatchQueue(label: "io.github.ciremek.Moonvibe.connection-test")
            let once = MVOnce()
            let start = DispatchTime.now().uptimeNanoseconds

            func finish(_ result: (Double, Bool)?) {
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    finish((ms, connection.currentPath?.usesInterfaceType(.wiredEthernet) ?? false))
                case .failed, .waiting, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1) { finish(nil) }
        }
    }

    private static func linkDescription(wired: Bool?) -> String? {
        guard let wired else { return nil }
        if wired { return "Ethernet" }

        guard let channel = CWWiFiClient.shared().interface()?.wlanChannel() else { return "Wi-Fi" }
        let band: String
        switch channel.channelBand {
        case .band2GHz: band = String(localized: "2,4 GHz")
        case .band5GHz: band = "5 GHz"
        case .band6GHz: band = "6 GHz"
        default: return "Wi-Fi"
        }
        let width: String
        switch channel.channelWidth {
        case .width20MHz: width = "20 MHz"
        case .width40MHz: width = "40 MHz"
        case .width80MHz: width = "80 MHz"
        case .width160MHz: width = "160 MHz"
        default: width = ""
        }
        return width.isEmpty
            ? String(localized: "Wi-Fi \(band) · canal \(channel.channelNumber)")
            : String(localized: "Wi-Fi \(band) · canal \(channel.channelNumber) · \(width)")
    }
}

/// Lets exactly one of several racing callbacks through.
private final class MVOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
