import Foundation

/// The menu captures its target when opened, so clicking it cannot affect a different app.
public struct AppAvailability {
    public struct Target: Equatable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }
    public private(set) var target: Target?
    public private(set) var excluded: Set<String>
    public init(excluded: Set<String> = []) { self.excluded = excluded }
    public mutating func capture(_ target: Target?) { self.target = target }
    public var isEnabled: Bool { target.map { !excluded.contains($0.id) } ?? false }
    public var actionTitle: String {
        guard let target else { return "Select an app to enable or disable" }
        return "\(isEnabled ? "Disable" : "Enable") for \(target.name)"
    }
    public var statusTitle: String {
        guard let target else { return "No app selected" }
        return "\(isEnabled ? "Enabled" : "Disabled") for \(target.name)"
    }
    public mutating func toggle() {
        guard let target else { return }
        if !excluded.insert(target.id).inserted { excluded.remove(target.id) }
    }
}
