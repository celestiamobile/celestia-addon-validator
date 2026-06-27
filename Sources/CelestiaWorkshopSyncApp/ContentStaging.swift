import AsyncRequest
import CloudKitCodable
import Foundation
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
        addonType: AddonType,
        httpClient: any RequestClient
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
        let zipData = try await downloadAssetData(addon.item, httpClient: httpClient)
        let zipPath = rootDir.appendingPathComponent("item.zip")
        try zipData.write(to: zipPath)
        try FileManager.default.unzipItem(at: zipPath, to: uuidDir)
        try? FileManager.default.removeItem(at: zipPath)

        // 3. Download the preview image (if any) outside the content folder.
        //    Steam validates the file extension against the actual bytes,
        //    so the extension has to reflect the real format — we can't
        //    blindly use ".jpg".
        var previewFile: URL?
        if let image = addon.image {
            let previewData = try await downloadAssetData(image, httpClient: httpClient)
            let ext = imageExtension(forBytes: previewData)
            let preview = rootDir.appendingPathComponent("preview.\(ext)")
            try previewData.write(to: preview)
            previewFile = preview
        }

        return Staged(
            rootDir: rootDir,
            contentFolder: contentFolder,
            previewFile: previewFile
        )
    }

    private static func downloadAssetData(_ info: CKAssetDownloadInfo, httpClient: any RequestClient) async throws -> Data {
        // OpenCloudKit's CKAssetDownloadInfo.url is a plain HTTPS URL on
        // Steam's CDN side, no extra auth needed beyond the URL itself.
        return try await AsyncDataRequestHandler.get(url: info.url.absoluteString, httpClient: httpClient)
    }

    /// Sniff the file format from the first few bytes and return the
    /// extension Steam expects. Steam Workshop preview images accept
    /// JPG, PNG, GIF, and BMP. Anything unrecognized falls back to JPG
    /// (Steam may still reject, but it's our most likely correct guess).
    private static func imageExtension(forBytes data: Data) -> String {
        let head = data.prefix(8)
        let bytes = Array(head)
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "jpg"
        }
        if bytes.count >= 8,
           bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
           bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A {
            return "png"
        }
        if bytes.count >= 4, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38 {
            return "gif"
        }
        if bytes.count >= 2, bytes[0] == 0x42, bytes[1] == 0x4D {
            return "bmp"
        }
        return "jpg"
    }

    private static func makeTempDir(prefix: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
