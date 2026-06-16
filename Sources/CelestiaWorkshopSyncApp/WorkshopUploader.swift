import Foundation

/// Top-level "per addon" upload orchestrator. Handles content staging,
/// VDF generation, steamcmd invocation, and returns the new AddonState
/// the caller should persist on success.
struct WorkshopUploader {
    let appID: String
    let steamcmd: SteamCmdRunner

    /// Uploads/updates/hides/unhides one addon based on `action` and
    /// returns the AddonState to persist. Throws on any failure — the
    /// caller bumps failure counters in state.
    func upload(
        addon: WorkshopAddonRecord,
        action: SyncAction,
        priorState: AddonState?,
        contentChecksum: String,
        previewChecksum: String?,
        fieldHashes: [String: String]
    ) async throws -> AddonState {
        let addonType: AddonType = (addon.type == "script") ? .script : .addon
        let visibility: Visibility = (action.steamVisibility == .hidden) ? .hidden : .public
        let changeNote = makeChangeNote(action: action)
        let title = addon.name
        let description = makeWorkshopDescription(addon: addon)

        let staged = try await ContentStaging.stage(addon: addon, addonType: addonType)
        defer { try? FileManager.default.removeItem(at: staged.rootDir) }

        let vdfPath = staged.rootDir.appendingPathComponent("workshopitem.vdf")
        let vdf = buildVdf(
            publishedFileId: priorState?.workshopId,
            contentFolder: staged.contentFolder,
            previewFile: staged.previewFile,
            title: title,
            description: description,
            changeNote: changeNote,
            visibility: visibility
        )
        try vdf.write(to: vdfPath, atomically: true, encoding: .utf8)

        let result = try steamcmd.uploadWorkshopItem(vdfPath: vdfPath, expectedFileId: priorState?.workshopId)

        return AddonState(
            addonId: addon.cloudKitIdentifier,
            workshopId: result.publishedFileId,
            type: addonType,
            visibility: visibility,
            contentChecksum: contentChecksum,
            previewChecksum: previewChecksum,
            fieldHashes: fieldHashes,
            lastUploadedAt: Date(),
            lastFailedAt: nil,
            failureCount: 0
        )
    }

    // MARK: - Helpers

    private func makeWorkshopDescription(addon: WorkshopAddonRecord) -> String {
        var body = addon.description
        let authors = (addon.authors ?? []).filter { !$0.isEmpty }
        if !authors.isEmpty {
            body += "\n\nBy " + authors.joined(separator: ", ")
        }
        let addonID = addon.cloudKitIdentifier
        body += "\n\nhttps://celestia.mobi/resources/item/\(addonID)"
        return body
    }

    private func makeChangeNote(action: SyncAction) -> String {
        switch action {
        case .create:
            return "Initial upload"
        case .skipUnchanged, .skipNotPublishable:
            // Shouldn't happen — caller filters these out — but stay safe.
            return ""
        case .update(let changes):
            return changes.hasAnyChange ? changes.summary : "Updated"
        case .unhide(let changes):
            // The category was restored. Lead with that, then list what
            // actually changed (if anything beyond visibility).
            if changes.hasAnyChange {
                return "Restored — \(changes.summary)"
            }
            return "Restored"
        case .hide:
            return "Hidden — source addon retired"
        }
    }

    private func buildVdf(
        publishedFileId: String?,
        contentFolder: URL,
        previewFile: URL?,
        title: String,
        description: String,
        changeNote: String,
        visibility: Visibility
    ) -> String {
        let visibilityValue: String
        switch visibility {
        case .public: visibilityValue = "0"
        case .hidden: visibilityValue = "2"
        }

        var lines: [String] = []
        lines.append("\"workshopitem\"")
        lines.append("{")
        lines.append("\t\"appid\" \"\(appID)\"")
        if let publishedFileId {
            lines.append("\t\"publishedfileid\" \"\(publishedFileId)\"")
        }
        lines.append("\t\"contentfolder\" \(quoted(contentFolder.path))")
        if let previewFile {
            lines.append("\t\"previewfile\" \(quoted(previewFile.path))")
        }
        lines.append("\t\"title\" \(quoted(title))")
        lines.append("\t\"description\" \(quoted(description))")
        lines.append("\t\"changenote\" \(quoted(changeNote))")
        lines.append("\t\"visibility\" \"\(visibilityValue)\"")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// VDF strings are double-quoted; the only characters needing escaping
    /// are backslash and double-quote.
    private func quoted(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private extension SyncAction {
    /// Helper for code that only cares about the visibility outcome.
    var steamVisibility: Visibility {
        switch self {
        case .hide:                                    return .hidden
        case .create, .update, .unhide,
             .skipUnchanged, .skipNotPublishable:      return .public
        }
    }
}
