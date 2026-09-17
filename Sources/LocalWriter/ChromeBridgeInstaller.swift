import Foundation

/// Installs only the bridge for LocalWriter's stable, public extension ID.
enum ChromeBridgeInstaller {
    static let extensionID = "pkcahnmnafkepdcfepmbnboaadnbkhnl"
    static func install(executable: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let files = FileManager.default
        let support = home.appendingPathComponent("Library/Application Support")
        let directory = support.appendingPathComponent("LocalWriter/NativeMessaging")
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent("LocalWriterBridge")
        // Atomic replacement prevents an interrupted update leaving a partial host.
        let temporary = directory.appendingPathComponent(".bridge-" + UUID().uuidString)
        defer { try? files.removeItem(at: temporary) }
        try files.copyItem(at: executable, to: temporary)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        if files.fileExists(atPath: binary.path) { _ = try files.replaceItemAt(binary, withItemAt: temporary) }
        else { try files.moveItem(at: temporary, to: binary) }
        let launcher = directory.appendingPathComponent("localwriter-native-host")
        let quoted = "'" + binary.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        try "#!/bin/sh\nexec \(quoted) --native-messaging \"$@\"\n".write(to: launcher, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        let hosts = support.appendingPathComponent("Google/Chrome/NativeMessagingHosts")
        try files.createDirectory(at: hosts, withIntermediateDirectories: true)
        let manifest = hosts.appendingPathComponent("com.johnbgood.localwriter.json")
        let definition: [String: Any] = ["name": "com.johnbgood.localwriter", "description": "LocalWriter local model bridge", "path": launcher.path, "type": "stdio", "allowed_origins": ["chrome-extension://\(extensionID)/"]]
        try JSONSerialization.data(withJSONObject: definition, options: [.prettyPrinted, .sortedKeys]).write(to: manifest, options: [.atomic])
        return manifest
    }
}
