import Foundation

final class MockOllama: URLProtocol {
    static var failures = 0
    static var models = ["qwen3:4b"]
    static var warmupOK = true
    static var requests: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.requests.append(path)
        if Self.failures > 0 {
            Self.failures -= 1
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return
        }
        let body: [String: Any] = path == "/api/tags"
            ? ["models": Self.models.map { ["name": $0] }]
            : ["done": Self.warmupOK]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct RuntimeChecks {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOllama.self]
        let session = URLSession(configuration: config)
        let external = LocalRuntime(session: session, installations: [])
        var progress: [String] = []
        try await external.start { progress.append($0) }
        precondition(progress.last == "Loading Qwen3…")
        precondition(MockOllama.requests == ["/api/tags", "/api/generate"])
        external.stop() // No child process exists when reusing a running server.

        MockOllama.models = []
        do { try await external.start(); fatalError("Missing model accepted") }
        catch LocalRuntime.StartupError.missingModel {}
        MockOllama.models = ["qwen3:4b"]
        MockOllama.warmupOK = false
        do { try await external.start(); fatalError("Invalid warmup accepted") }
        catch LocalRuntime.StartupError.warmupFailed {}
        MockOllama.warmupOK = true
        MockOllama.failures = 1
        do { try await external.start(); fatalError("Missing installation accepted") }
        catch LocalRuntime.StartupError.missingOllama {}

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let executable = temp.appendingPathComponent("ollama")
        let marker = temp.appendingPathComponent("launched")
        // No network service is launched; the fixture records the real Process environment.
        try "#!/bin/sh\nprintf '%s\\n' \"$1\" \"$OLLAMA_HOST\" \"$OLLAMA_MODELS\" > '\(marker.path)'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let runtime = LocalRuntime(session: session, installations: [.init(executable: executable, models: temp)])
        MockOllama.failures = 1
        try await runtime.start()
        let launched = try String(contentsOf: marker, encoding: .utf8)
        precondition(launched == "serve\n127.0.0.1:11434\n\(temp.path)\n")
        runtime.stop()
        print("PASS: existing server reuse, startup discovery, loopback environment, model preload, missing installation/model and warmup failure")
    }
}
