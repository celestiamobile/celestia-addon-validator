import Foundation

/// Orchestrates one run of the sync: pulls add-on records from CloudKit,
/// compares each against the state files in `stateDir`, and re-uploads any
/// that have changed via `steamcmd`. Real implementation lands in the next
/// commit — this is the structural stub.
struct SyncCoordinator {
    let stateDir: URL
    let steamcmdPath: URL
    let appID: String
    let steamUsername: String
    let dryRun: Bool

    func run() async throws {
        // TODO: implement in next commit
        //   1. Load last_run.json from stateDir
        //   2. Query CloudKit ResourceItem records (publishTime/lastUpdateTime > lastRun)
        //   3. For each record:
        //      a. Read addons/<recordName>.json (may not exist)
        //      b. Compare CKAsset fileChecksum to stored contentHash
        //      c. Compute metadataHash over name/type/category/etc.
        //      d. If anything differs, download the asset, stage workshop
        //         content matching the description.json schema, generate a
        //         workshopitem.vdf, invoke steamcmd, capture PublishedFileId
        //      e. Write addons/<recordName>.json
        //   4. Write last_run.json with stats
        print("[CelestiaWorkshopSyncApp] stub run() — nothing wired up yet.")
        print("  stateDir:      \(stateDir.path)")
        print("  steamcmdPath:  \(steamcmdPath.path)")
        print("  appID:         \(appID)")
        print("  steamUsername: \(steamUsername)")
        print("  dryRun:        \(dryRun)")
    }
}
