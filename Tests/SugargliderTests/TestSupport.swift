import Testing
import Foundation
import Darwin
import Synchronization
@testable import Sugarglider

@Suite(.defaultsCleanup) @MainActor
struct SugargliderTests {
    static func makeSettings(defaults: UserDefaults? = nil,
                             tokens: any TokenStorage = InMemoryTokenStore()) -> AppSettings {
        AppSettings(defaults: defaults ?? makeDefaults(), tokens: tokens)
    }

    static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: DefaultsCleanup.directory.appending(path: UUID().uuidString).path)!
    }
}

/// A suite named by a path keeps its plist at that path, so the tests' suites live in a temporary directory
/// that goes once all tests have run. A named suite is a plist in ~/Library/Preferences that no API removes:
/// dropping the domain leaves an empty file, and cfprefsd rewrites a deleted one seconds later (measured).
/// Every test run used to leave dozens there.
struct DefaultsCleanup: SuiteTrait, TestScoping {
    static let directory: URL = {
        let directory = FileManager.default.temporaryDirectory.appending(path: "SugargliderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @concurrent @Sendable () async throws -> Void) async throws {
        defer { try? FileManager.default.removeItem(at: Self.directory) }
        try await function()
    }
}

extension Trait where Self == DefaultsCleanup {
    static var defaultsCleanup: Self { Self() }
}

/// The real Keychain would prompt, because the test binary's signature changes with every build.
@MainActor
final class InMemoryTokenStore: TokenStorage {
    private(set) var stored: String
    var refuseWrites = false

    init(_ stored: String = "") { self.stored = stored }

    func load() -> String { stored }

    func save(_ token: String) -> Bool {
        guard !refuseWrites else { return false }
        stored = token
        return true
    }
}

/// Answers every connection with the same canned response. A real socket, because `Nightscout`'s
/// private `URLSession` can't be stubbed with a `URLProtocol`. Bound to loopback only, which never
/// triggers the firewall prompt an all-interfaces bind can.
final class LocalHTTPServer: Sendable {
    enum ServerError: Error { case socketFailed, bindFailed, listenFailed }

    let port: UInt16
    private let listener: Int32
    private let requests = Mutex<[String]>([])
    private let isStopped = Atomic(false)

    var baseURL: String { "http://127.0.0.1:\(port)" }
    var requestLines: [String] { requests.withLock { $0 } }

    init(status: Int = 200, json: String) throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw ServerError.socketFailed }

        var reuse: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0  // the OS picks a free port
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { close(listener); throw ServerError.bindFailed }
        guard listen(listener, 8) == 0 else { close(listener); throw ServerError.listenFailed }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        port = UInt16(bigEndian: address.sin_port)
        self.listener = listener

        let response = Self.response(status: status, body: Data(json.utf8))
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                if let line = Self.requestLine(from: client), let self {
                    self.requests.withLock { $0.append(line) }
                }
                Self.send(response, to: client)
                close(client)
            }
        }
    }

    func stop() {
        guard !isStopped.exchange(true, ordering: .relaxed) else { return }
        close(listener)  // makes the serving thread's accept() fail, which ends it
    }

    deinit { stop() }

    private static func response(status: Int, body: Data) -> Data {
        let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Content-Type: application/json\r\n"
            + "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    private static func requestLine(from client: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &buffer, 4096)
        guard count > 0 else { return nil }
        return String(decoding: buffer.prefix(count), as: UTF8.self)
            .split(separator: "\r\n", maxSplits: 1).first.map(String.init)
    }

    private static func send(_ response: Data, to client: Int32) {
        response.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(client, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }
}

/// `ReadingStore` fetches in `Task`s nothing can await, so tests poll for the effect.
@MainActor
func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting for \(what)")
}

/// Rounded the way `Nightscout.fetchEntries` rounds its date filter.
func epochMillis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
}

func reading(_ sgv: Int, direction: String = "Flat", minutesAgo: Double = 0,
             from now: Date = .now) -> Reading {
    Reading(sgv: sgv, direction: direction, date: now.addingTimeInterval(-minutesAgo * 60))
}
