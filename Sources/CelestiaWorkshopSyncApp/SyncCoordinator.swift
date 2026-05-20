import CelestiaAddonValidator
import CloudKitCodable
import Foundation
import OpenCloudKit

/// Orchestrates one run of the sync: pulls add-on records from CloudKit,
/// compares each against the state files under `stateDir`, and decides
/// what action to take. In this commit it stops at the decision step and
/// prints a plan — actual Workshop uploads land in the next commit.
struct SyncCoordinator {
    let stateDir: URL
    let steamcmdPath: URL
    let appID: String
    let steamUsername: String
    let dryRun: Bool

    /// CloudKit field names the sync hashes individually so changenotes can
    /// say "updated title, description, authors" rather than just
    /// "metadata changed". Order is stable for hash determinism.
    private static let trackedFields = [
        "name",
        "description",
        "category",
        "authors",
        "type",
    ]

    func run() async throws {
        let store = try StateStore(root: stateDir)
        let previous = store.readLastRun()
        let startedAt = Date()
        print("Run starting at \(startedAt)")
        if let previous {
            print("Previous run completed at \(previous.completedAt)")
        } else {
            print("No previous run state found — first run.")
        }

        let records = try await fetchAddonRecords()
        print("Fetched \(records.count) ResourceItem records from CloudKit")

        var summary = LastRunState(
            completedAt: startedAt,
            scannedAddonCount: records.count,
            uploadedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            hiddenCount: 0,
            unhiddenCount: 0
        )

        let decoder = CloudKitRecordDecoder()
        for record in records {
            guard let addon = try? decoder.decode(WorkshopAddonRecord.self, from: record) else {
                print("[?] failed to decode WorkshopAddonRecord for record \(record.recordID.recordName) — skipping")
                continue
            }
            let addonId = addon.cloudKitIdentifier
            let priorState: AddonState?
            do {
                priorState = try store.readAddonState(addonId: addonId)
            } catch {
                print("[\(addonId)] failed to read state: \(error.localizedDescription) — treating as new")
                priorState = nil
            }

            let contentChecksum = addon.item.fileChecksum
            let previewChecksum = addon.image?.fileChecksum
            let fieldHashes = computeFieldHashes(addon: addon)
            let action = decideAction(
                priorState: priorState,
                categoryIsSet: categoryIsSet,
                contentChecksum: contentChecksum,
                previewChecksum: previewChecksum,
                fieldHashes: fieldHashes
            )

            print("[\(addonId)] \(action.summary) (category=\(categoryIsSet ? "set" : "nil"), checksum=\(String(contentChecksum.prefix(12))))")

            switch action {
            case .skipUnchanged, .skipNotPublishable:
                summary.skippedCount += 1
            case .create, .update, .unhide:
                // TODO(step 2b): perform the Workshop upload via steamcmd.
                // changenote = ChangeSet.summary (or "Initial upload" for create).
                // description = addon.description + "\n\nAuthors: <joined>" when
                // the record has authors.
                summary.uploadedCount += 1
                if case .unhide = action { summary.unhiddenCount += 1 }
            case .hide:
                // TODO(step 2b): flip Workshop visibility to hidden via steamcmd
                summary.hiddenCount += 1
            }
        }

        summary.completedAt = Date()
        if dryRun {
            print("\n[dry-run] would write last_run.json: \(summary)")
        } else {
            // TODO(step 2b): write summary back. Skipping for now since the
            // upload side isn't wired up — bumping last_run on a no-op run
            // would falsely advance the watermark.
            print("\nstep-2a end. last_run.json not written until upload path is wired up.")
        }
    }

    /// Fetches every ResourceItem record in the public DB so we can detect
    /// both publish and unpublish transitions locally. Time-based filtering
    /// would be faster but would miss category→nil transitions on records
    /// that haven't otherwise been touched since the last run.
    private func fetchAddonRecords() async throws -> [CKRecord] {
        let db = CKContainer.default().publicCloudDatabase
        let desiredKeys = [
            "item", "image", "category", "type",
            "name",
            "description",
            "authors",
            "publishTime", "lastUpdateTime",
        ]
        let query = CKQuery(recordType: "ResourceItem", filters: [])

        var records: [CKRecord] = []
        var (recordResults, cursor) = try await db.records(matching: query, desiredKeys: desiredKeys)
        for (_, recordResult) in recordResults {
            if let record = try? recordResult.get() {
                records.append(record)
            }
        }
        while let currentCursor = cursor {
            (recordResults, cursor) = try await db.records(continuingMatchFrom: currentCursor, desiredKeys: desiredKeys)
            for (_, recordResult) in recordResults {
                if let record = try? recordResult.get() {
                    records.append(record)
                }
            }
        }
        return records
    }

    /// Implements the truth table documented in the state repo README.
    private func decideAction(
        priorState: AddonState?,
        categoryIsSet: Bool,
        contentChecksum: String,
        previewChecksum: String?,
        fieldHashes: [String: String]
    ) -> SyncAction {
        switch (categoryIsSet, priorState) {
        case (false, nil):
            return .skipNotPublishable
        case (false, .some(let s)) where s.visibility == .hidden:
            return .skipNotPublishable
        case (false, .some):
            return .hide
        case (true, nil):
            return .create
        case (true, .some(let s)) where s.visibility == .hidden:
            // Unhide always implies re-asserting current content + metadata,
            // so synthesize a ChangeSet that lists everything as "changed"
            // for changenote purposes.
            let changes = computeChanges(
                priorState: s,
                contentChecksum: contentChecksum,
                previewChecksum: previewChecksum,
                fieldHashes: fieldHashes
            )
            return .unhide(changes: changes)
        case (true, .some(let s)):
            let changes = computeChanges(
                priorState: s,
                contentChecksum: contentChecksum,
                previewChecksum: previewChecksum,
                fieldHashes: fieldHashes
            )
            if changes.hasAnyChange { return .update(changes: changes) }
            return .skipUnchanged
        }
    }

    private func computeChanges(
        priorState: AddonState,
        contentChecksum: String,
        previewChecksum: String?,
        fieldHashes: [String: String]
    ) -> ChangeSet {
        var changedFields: [String] = []
        for field in Self.trackedFields {
            let prior = priorState.fieldHashes[field]
            let current = fieldHashes[field]
            if prior != current {
                changedFields.append(field)
            }
        }
        return ChangeSet(
            contentChanged: contentChecksum != priorState.contentChecksum,
            previewChanged: previewChecksum != priorState.previewChecksum,
            changedFieldNames: changedFields
        )
    }

    /// For each tracked field, sha256 its canonical text form. Hashing the
    /// *value* (not the raw CloudKit encoding) keeps the hash stable across
    /// encoding quirks.
    private func computeFieldHashes(addon: WorkshopAddonRecord) -> [String: String] {
        var result: [String: String] = [:]
        for field in Self.trackedFields {
            let canonical = canonicalize(field: field, addon: addon)
            result[field] = sha256(canonical)
        }
        return result
    }

    private func canonicalize(field: String, addon: WorkshopAddonRecord) -> String {
        switch field {
        case "name":
            return addon.name
        case "description":
            return addon.description
        case "category":
            return addon.category?.recordName ?? ""
        case "authors":
            // Sort for stability — different upload order shouldn't bump the hash.
            return (addon.authors ?? []).sorted().joined(separator: "\u{1F}")
        case "type":
            return addon.type ?? ""
        default:
            return ""
        }
    }
}
