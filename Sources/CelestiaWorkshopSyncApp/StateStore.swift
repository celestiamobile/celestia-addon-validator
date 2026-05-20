import Foundation

/// Reads and writes the per-addon JSON files and last_run.json under
/// `celestia-steam-workshop-history/`. All paths are resolved relative
/// to the `root` URL passed at construction.
struct StateStore {
    let root: URL

    init(root: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw SyncError.stateDirNotADirectory(path: root.path)
        }
        self.root = root
    }

    private var addonsDir: URL { root.appendingPathComponent("addons", isDirectory: true) }
    private var lastRunPath: URL { root.appendingPathComponent("last_run.json") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func addonStatePath(addonId: String) -> URL {
        addonsDir.appendingPathComponent("\(addonId).json")
    }

    func readAddonState(addonId: String) throws -> AddonState? {
        let path = addonStatePath(addonId: addonId)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        do {
            let data = try Data(contentsOf: path)
            return try Self.decoder.decode(AddonState.self, from: data)
        } catch {
            throw SyncError.malformedStateFile(path: path.path, underlying: error)
        }
    }

    func writeAddonState(_ state: AddonState) throws {
        try FileManager.default.createDirectory(at: addonsDir, withIntermediateDirectories: true)
        let path = addonStatePath(addonId: state.addonId)
        let data = try Self.encoder.encode(state)
        try data.write(to: path, options: Data.WritingOptions.atomic)
    }

    func readLastRun() -> LastRunState? {
        guard FileManager.default.fileExists(atPath: lastRunPath.path) else { return nil }
        return (try? Data(contentsOf: lastRunPath))
            .flatMap { try? Self.decoder.decode(LastRunState.self, from: $0) }
    }

    func writeLastRun(_ state: LastRunState) throws {
        let data = try Self.encoder.encode(state)
        try data.write(to: lastRunPath, options: Data.WritingOptions.atomic)
    }
}
