import Foundation

struct ConfigurationLoadResult {
    var bindings: [GestureBinding]
    var settings: AppSettings
    var discardedBindings: Int
    var message: String?
}

final class ConfigurationStore {
    static let schemaVersion = 1

    let directoryURL: URL
    let configurationURL: URL
    let backupURL: URL

    init(baseDirectory: URL? = nil) {
        let root = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        directoryURL = root.appendingPathComponent("Flowpad", isDirectory: true)
        configurationURL = directoryURL.appendingPathComponent("configuration.json")
        backupURL = directoryURL.appendingPathComponent("configuration.backup.json")
    }

    func load() -> ConfigurationLoadResult {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return ConfigurationLoadResult(bindings: [], settings: .init(), discardedBindings: 0, message: nil)
        }

        do {
            let data = try Data(contentsOf: configurationURL)
            let decoded = try decoder.decode(PersistedConfiguration.self, from: data)
            let bindings = decoded.bindings.compactMap(\.value)
            let discarded = decoded.bindings.count - bindings.count

            if decoded.schemaVersion > Self.schemaVersion {
                return ConfigurationLoadResult(
                    bindings: bindings,
                    settings: decoded.settings,
                    discardedBindings: discarded,
                    message: "This configuration was created by a newer Flowpad version."
                )
            }

            if discarded > 0 {
                try? quarantine(data: data, label: "invalid-bindings")
            }

            return ConfigurationLoadResult(
                bindings: deduplicated(bindings),
                settings: decoded.settings,
                discardedBindings: discarded,
                message: discarded == 0 ? nil : "Ignored \(discarded) invalid binding(s); the rest were loaded."
            )
        } catch {
            if let data = try? Data(contentsOf: configurationURL) {
                try? quarantine(data: data, label: "unreadable")
            }
            return ConfigurationLoadResult(
                bindings: [],
                settings: .init(),
                discardedBindings: 0,
                message: "The configuration could not be read. A quarantined copy was preserved."
            )
        }
    }

    func save(bindings: [GestureBinding], settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: configurationURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: configurationURL, to: backupURL)
        }

        let configuration = PersistedConfiguration(
            schemaVersion: Self.schemaVersion,
            bindings: bindings.map { FailableDecodable($0) },
            settings: settings
        )
        let data = try encoder.encode(configuration)
        try data.write(to: configurationURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func deduplicated(_ bindings: [GestureBinding]) -> [GestureBinding] {
        var seen = Set<GestureID>()
        return bindings.filter { seen.insert($0.gestureID).inserted }
    }

    private func quarantine(data: Data, label: String) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directoryURL.appendingPathComponent("quarantine-\(label)-\(stamp).json")
        try data.write(to: url, options: .atomic)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder { JSONDecoder() }
}
