import Foundation
import Network

/// Occupies a port (for the test of a busy API port).
final class HTTPBlocker: @unchecked Sendable {
    private var l: NWListener?
    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let l = try NWListener(using: params)
        self.l = l
        l.newConnectionHandler = { $0.cancel() }
        return await withCheckedContinuation { c in
            l.stateUpdateHandler = { if case .ready = $0 { c.resume(returning: l.port!.rawValue) } }
            l.start(queue: .global())
        }
    }
    func stop() { l?.cancel() }
}
