import CloudKitCodable
import Foundation
import MWRequest
import ZIPFoundation

/// Builds the Workshop content folder layout the Celestia Steam client
/// expects (matches patch 0002 in celestia-steam):
///
///     <staged>/
///     ├── description.json    { "id": "<addonId>", "type": "addon"|"script" }
///     └── <addonId>/          unzipped content from the source asset
///         └── …
///
/// The preview image (if any) is staged *outside* the content folder so
/// Steam's preview upload doesn't double-package it as content.
struct ContentStaging {
    /// Result of one staging run. The caller is responsible for removing
    /// `rootDir` when finished.
    struct Staged {
        let rootDir: URL
        let contentFolder: URL
        let previewFile: URL?
    }

    /// Downloads the addon's `item` zip + optional `image` preview from
    /// CloudKit and lays them out under a fresh temp dir.
    static func stage(
        addon: WorkshopAddonRecord,
        addonType: AddonType
    ) async throws -> Staged {
        let rootDir = try makeTempDir(prefix: "celestia-workshop-staging-")
        let contentFolder = rootDir.appendingPathComponent("content", isDirectory: true)
        try FileManager.default.createDirectory(at: contentFolder, withIntermediateDirectories: true)

        // 1. Write description.json at the content root.
        let description = [
            "id": addon.cloudKitIdentifier,
            "type": addonType.rawValue,
        ]
        let descriptionData = try JSONSerialization.data(
            withJSONObject: description,
            options: [.prettyPrinted, .sortedKeys]
        )
        try descriptionData.write(to: contentFolder.appendingPathComponent("description.json"))

        // 2. Download the content zip and unzip it into the UUID subdir.
        let uuidDir = contentFolder.appendingPathComponent(addon.cloudKitIdentifier, isDirectory: true)
        try FileManager.default.createDirectory(at: uuidDir, withIntermediateDirectories: true)
        let zipData = try await downloadAssetData(addon.item)
        let zipPath = rootDir.appendingPathComponent("item.zip")
        try zipData.write(to: zipPath)
        try FileManager.default.unzipItem(at: zipPath, to: uuidDir)
        try? FileManager.default.removeItem(at: zipPath)

        // 3. Download the preview image (if any) outside the content folder.
        var previewFile: URL?
        if let image = addon.image {
            let previewData = try await downloadAssetData(image)
            let preview = rootDir.appendingPathComponent("preview.jpg")
            try previewData.write(to: preview)
            previewFile = preview
        }

        return Staged(
            rootDir: rootDir,
            contentFolder: contentFolder,
            previewFile: previewFile
        )
    }

    private static func downloadAssetData(_ info: CKAssetDownloadInfo) async throws -> Data {
        // OpenCloudKit's CKAssetDownloadInfo.url is a plain HTTPS URL on
        // Steam's CDN side, no extra auth needed beyond the URL itself.
        return try await AsyncDataRequestHandler.get(url: info.url.absoluteString)
    }

    private static func makeTempDir(prefix: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
