import AsyncRequest
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
    let httpClient: any RequestClient
    /// 0 = unlimited. Otherwise cap actual uploads this run; useful for
    /// staging the first bulk sync without committing to 2000+ hits.
    let limit: Int

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

        let uploader = WorkshopUploader(
            appID: appID,
            steamcmd: SteamCmdRunner(steamcmdPath: steamcmdPath, username: steamUsername),
            httpClient: httpClient
        )

        let decoder = CloudKitRecordDecoder()
        var actionedCount = 0
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
            let categoryIsSet = addon.category != nil
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
                continue
            case .create, .update, .unhide, .hide:
                break
            }

            if limit > 0 && actionedCount >= limit {
                print("[\(addonId)] reached --limit \(limit), stopping further uploads this run")
                summary.skippedCount += 1
                continue
            }
            actionedCount += 1

            if dryRun {
                print("  [dry-run] would upload via steamcmd")
                bumpCounters(&summary, for: action)
                continue
            }

            do {
                let newState = try await uploader.upload(
                    addon: addon,
                    action: action,
                    priorState: priorState,
                    contentChecksum: contentChecksum,
                    previewChecksum: previewChecksum,
                    fieldHashes: fieldHashes
                )
                try store.writeAddonState(newState)
                bumpCounters(&summary, for: action)
            } catch {
                summary.failedCount += 1
                print("[\(addonId)] upload failed: \(error.localizedDescription)")

                // If steamcmd created an item but failed during content upload,
                // save partial state so the next run retries as an update
                // instead of creating another orphan.
                let partialId: String? = (error as? SteamCmdRunner.RunnerError)?.partialPublishedFileId
                if let workshopId = partialId ?? priorState?.workshopId {
                    let failedState = AddonState(
                        addonId: addonId,
                        workshopId: workshopId,
                        type: (addon.type == "script") ? .script : .addon,
                        visibility: .public,
                        contentChecksum: "",
                        previewChecksum: nil,
                        fieldHashes: [:],
                        lastUploadedAt: priorState?.lastUploadedAt ?? Date.distantPast,
                        lastFailedAt: Date(),
                        failureCount: (priorState?.failureCount ?? 0) + 1
                    )
                    try? store.writeAddonState(failedState)
                    if partialId != nil && priorState == nil {
                        print("[\(addonId)] saved partial state with workshopId \(workshopId) to prevent orphan on retry")
                    }
                }
                // Otherwise (no prior state, no workshopId parsed) just drop —
                // next run will retry from scratch.
            }
        }

        summary.completedAt = Date()
        if dryRun {
            print("\n[dry-run] would write last_run.json: \(summary)")
        } else {
            try store.writeLastRun(summary)
            print("\nWrote last_run.json: \(summary)")
        }
    }

    private func bumpCounters(_ summary: inout LastRunState, for action: SyncAction) {
        switch action {
        case .create, .update:
            summary.uploadedCount += 1
        case .unhide:
            summary.uploadedCount += 1
            summary.unhiddenCount += 1
        case .hide:
            summary.hiddenCount += 1
        case .skipUnchanged, .skipNotPublishable:
            break
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
        let changedFields = fieldHashes
            .filter { priorState.fieldHashes[$0.key] != $0.value }
            .map { $0.key }
            .sorted()
        return ChangeSet(
            contentChanged: contentChecksum != priorState.contentChecksum,
            previewChanged: previewChecksum != priorState.previewChecksum,
            changedFieldNames: changedFields
        )
    }

    /// Per-field sha256 over a canonical text form. Hashing the *value*
    /// (not the raw CloudKit encoding) keeps the hash stable across
    /// encoding quirks.
    private func computeFieldHashes(addon: WorkshopAddonRecord) -> [String: String] {
        // `authors` is sorted so a reordering by the publisher doesn't bump the hash.
        let authors = (addon.authors ?? []).sorted().joined(separator: "\u{1F}")
        return [
            "name":        sha256(addon.name),
            "description": sha256(addon.description),
            "category":    sha256(addon.category?.recordName ?? ""),
            "authors":     sha256(authors),
            "type":        sha256(addon.type ?? ""),
        ]
    }
}
