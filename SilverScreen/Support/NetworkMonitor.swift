//
//  NetworkMonitor.swift
//  SilverScreen
//
//  Whether the device can reach the network, so screens can say they're offline
//  and retry by themselves when the connection comes back.
//

import Foundation
import Network

/// A stream of "the device has a usable network path" values. The OS boundary that
/// `NetworkMonitor` reads, so tests can drive connectivity without a real radio.
protocol NetworkPathSource: Sendable {
    /// Emits the current reachability first, then each change.
    func updates() -> AsyncStream<Bool>
}

/// The live source: `NWPathMonitor` on its own queue.
struct SystemNetworkPathSource: NetworkPathSource {
    func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "SilverScreen.NetworkMonitor"))
        }
    }
}

/// App-wide connectivity, shared through the SwiftUI environment.
///
/// Starts optimistic (`isOnline == true`) so nothing flashes an offline banner before the
/// first path update arrives. `reconnections` goes up by one each time the device comes
/// back online, which screens showing an offline error watch to retry on their own.
@Observable @MainActor
final class NetworkMonitor {
    private(set) var isOnline = true
    /// Count of offline → online transitions since launch.
    private(set) var reconnections = 0

    @ObservationIgnored private let source: any NetworkPathSource
    @ObservationIgnored private var task: Task<Void, Never>?

    init(source: any NetworkPathSource = SystemNetworkPathSource()) {
        self.source = source
    }

    /// Begins listening. Calling it again is a no-op.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    /// Applies each update from the source until it finishes or the task is cancelled.
    func run() async {
        for await online in source.updates() {
            apply(online)
        }
    }

    /// Records a reachability value; exposed for tests that drive it directly.
    func apply(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        if online {
            reconnections += 1
        }
    }

    isolated deinit {
        task?.cancel()
    }
}
