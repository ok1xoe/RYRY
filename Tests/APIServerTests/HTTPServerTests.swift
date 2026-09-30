import Foundation
import Testing
@testable import APIServer

/// A raw TCP connection over POSIX sockets (tests keep-alive and malformed requests).
func rawExchange(port: UInt16, host: String = "127.0.0.1", send: [String], readFor: Double = 0.5) -> String? {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET); addr.sin_port = port.bigEndian
    inet_pton(AF_INET, host, &addr.sin_addr)
    let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    guard ok == 0 else { return nil }
    var tv = timeval(tv_sec: 0, tv_usec: Int32(readFor * 1e6))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    for s in send { _ = s.withCString { Darwin.send(fd, $0, strlen($0), 0) } }
    var out = Data(); var buf = [UInt8](repeating: 0, count: 65536)
    while true { let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; out.append(buf, count: n) }
    return String(decoding: out, as: UTF8.self)
}

func echoServer(maxBody: Int = 1 << 20) -> HTTPServer {
    HTTPServer(host: "127.0.0.1", port: 0, maxBody: maxBody) { req in
        HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("echo:\(req.method) \(req.path) \(String(decoding: req.body, as: UTF8.self))".utf8))
    }
}

@Test func handlesPostAndKeepAlive() async throws {
    let s = echoServer()
    let port = try await s.start()
    defer { s.stop() }
    let r = rawExchange(port: port, send: [
        "POST /RPC2 HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhello",
        "POST /b HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc",
    ]) ?? ""
    #expect(r.contains("echo:POST /RPC2 hello"))
    #expect(r.contains("echo:POST /b abc"))
    #expect(r.components(separatedBy: "HTTP/1.1 200").count == 3)
}

@Test func worksWithURLSession() async throws {
    let s = echoServer()
    let port = try await s.start()
    defer { s.stop() }
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/RPC2")!)
    req.httpMethod = "POST"; req.httpBody = Data("xyz".utf8)
    let (d, resp) = try await URLSession.shared.data(for: req)
    #expect((resp as? HTTPURLResponse)?.statusCode == 200)
    #expect(String(decoding: d, as: UTF8.self) == "echo:POST /RPC2 xyz")
}

// Review Focus 1
@Test func rejectsOversizedAndMalformed() async throws {
    let s = echoServer(maxBody: 100)
    let port = try await s.start()
    defer { s.stop() }
    #expect(rawExchange(port: port, send: ["POST / HTTP/1.1\r\nContent-Length: 100000000\r\n\r\n"])?.contains("413") == true)
    #expect(rawExchange(port: port, send: ["POST / HTTP/1.1\r\n\r\n"])?.contains("411") == true)
    #expect(rawExchange(port: port, send: ["GARBAGE\r\n\r\n"])?.contains("400") == true)
    // the server stays alive
    #expect(rawExchange(port: port, send: ["POST / HTTP/1.1\r\nContent-Length: 2\r\n\r\nok"])?.contains("echo:POST / ok") == true)
}

// Review Focus 4
@Test func busyPortIsError() async throws {
    let a = echoServer()
    let port = try await a.start()
    defer { a.stop() }
    let b = HTTPServer(host: "127.0.0.1", port: port) { _ in HTTPResponse(status: 200, headers: [:], body: Data()) }
    await #expect(throws: (any Error).self) { _ = try await b.start() }
}

// Review Focus 5: listens on the loopback only
@Test func bindsLoopbackOnly() async throws {
    let s = echoServer()
    let port = try await s.start()
    defer { s.stop() }
    // find a non-local IPv4 address of the machine
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return }
    defer { freeifaddrs(ifaddr) }
    var ip: String?
    var p = ifaddr
    while let a = p {
        if let sa = a.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
            var host = [CChar](repeating: 0, count: 64)
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, 64, nil, 0, NI_NUMERICHOST)
            let h = String(cString: host)
            if !h.hasPrefix("127.") { ip = h; break }
        }
        p = a.pointee.ifa_next
    }
    guard let ip else { return }                           // a machine with no network
    #expect(rawExchange(port: port, host: ip, send: ["POST / HTTP/1.1\r\nContent-Length: 1\r\n\r\nx"]) == nil)
}
