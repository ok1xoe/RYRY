import Foundation
import Network

/// Obsadí port (pro test obsazeného portu API).
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
