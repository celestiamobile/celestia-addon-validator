import Foundation

/// On-disk state for one add-on in `celestia-steam-workshop-history/addons/<id>.json`.
struct AddonState: Codable, Sendable {
    var addonId: String
    var workshopId: String
    var type: AddonType
    var visibility: Visibility

    /// CloudKit asset checksum of the `item` asset — the actual zip content.
    var contentChecksum: String

    /// CloudKit asset checksum of the `image` asset (Workshop preview).
    /// Nil if the source record has no image.
    var previewChecksum: String?

    /// Per-field hashes of metadata text fields. Keys are stable identifiers
    /// (e.g. "name", "description"), values are sha256 prefixes. Letting the
    /// sync diff field-by-field is what allows the changenote to say
    /// "updated title and category" rather than just "metadata changed".
    var fieldHashes: [String: String]

    var lastUploadedAt: Date
    var lastFailedAt: Date?
    var failureCount: Int
}

enum AddonType: String, Codable, Sendable {
    case addon
    case script
}

enum Visibility: String, Codable, Sendable {
    case `public`
    case hidden
}

/// On-disk state for `last_run.json` at the state-dir root.
struct LastRunState: Codable, Sendable {
    var completedAt: Date
    var scannedAddonCount: Int
    var uploadedCount: Int
    var skippedCount: Int
    var failedCount: Int
    var hiddenCount: Int
    var unhiddenCount: Int
}

/// Decision the sync coordinator made for one add-on this run.
enum SyncAction: Sendable {
    /// CloudKit category is set, no prior state → create a new Workshop item.
    case create
    /// CloudKit category is set, prior state had visibility=public, hashes match → nothing to do.
    case skipUnchanged
    /// CloudKit category is set, hashes differ → re-upload content/metadata.
    case update(changes: ChangeSet)
    /// CloudKit category is set, prior state was hidden → flip visibility public, then update.
    case unhide(changes: ChangeSet)
    /// CloudKit category is nil, prior state was public → flip visibility hidden.
    case hide
    /// CloudKit category is nil, no prior state OR already hidden → nothing to do.
    case skipNotPublishable
}

extension SyncAction {
    var summary: String {
        switch self {
        case .create:                  return "create"
        case .skipUnchanged:           return "skip (unchanged)"
        case .update(let changes):     return "update — \(changes.summary)"
        case .unhide(let changes):     return "unhide — \(changes.summary)"
        case .hide:                    return "hide"
        case .skipNotPublishable:      return "skip (not publishable)"
        }
    }
}

/// Describes the diff between prior state and the current CloudKit record.
/// Drives both the upload decision and the human-readable changenote.
struct ChangeSet: Sendable, Equatable {
    var contentChanged: Bool
    var previewChanged: Bool
    /// Field-name (e.g. "name", "description") → "old → new" debug string,
    /// kept only for surface-level diagnostics. Actual hashes live in
    /// AddonState.fieldHashes; what's in the ChangeSet is the *list* of
    /// changed field names sufficient for the changenote.
    var changedFieldNames: [String]

    var hasAnyChange: Bool {
        contentChanged || previewChanged || !changedFieldNames.isEmpty
    }

    /// "content", "preview image", "title", etc. — natural language for the
    /// Steam Workshop changenote.
    var summary: String {
        var parts: [String] = []
        if contentChanged { parts.append("content") }
        if previewChanged { parts.append("preview image") }
        for field in changedFieldNames {
            parts.append(Self.displayName(for: field))
        }
        if parts.isEmpty { return "no changes" }
        return "Updated " + parts.joined(separator: ", ")
    }

    private static func displayName(for fieldKey: String) -> String {
        switch fieldKey {
        case "name":        return "title"
        case "description": return "description"
        case "category":    return "category"
        case "authors":     return "authors"
        case "type":        return "type"
        default:            return fieldKey
        }
    }
}

enum SyncError: Error, LocalizedError {
    case stateDirNotADirectory(path: String)
    case malformedStateFile(path: String, underlying: Error)
    case unsupportedAddonType(value: String)

    var errorDescription: String? {
        switch self {
        case .stateDirNotADirectory(let path):
            return "stateDir does not exist or is not a directory: \(path)"
        case .malformedStateFile(let path, let underlying):
            return "Malformed state file \(path): \(underlying)"
        case .unsupportedAddonType(let value):
            return "Unsupported add-on type: \(value)"
        }
    }
}
