import AppKit
import Foundation
import MWRequest
import OpenCloudKit

public enum UploaderError {
    case unknown
    case cloudKit
    case emptyResult
    case download
    case unsupportedImage
    case resizeImage
    case saveResizedImage
}

extension UploaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknown:
            return "Unknown error"
        case .cloudKit:
            return "CloudKit error"
        case .emptyResult:
            return "Empty result returned"
        case .download:
            return "Error in downloading asset"
        case .unsupportedImage:
            return "Unsupported image file"
        case .resizeImage:
            return "Failed to resize an image"
        case .saveResizedImage:
            return "Failed to save a resized image"
        }
    }
}

public final class Uploader {
    public init() {}

    @discardableResult private func submitRecord(_ record: CKRecord, savePolicy: CKModifyRecordsOperation.RecordSavePolicy, to database: CKDatabase) async throws -> CKRecord {
        let modifyResults = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: savePolicy).saveResults
        guard let modifyResult = modifyResults[record.recordID] else {
            throw UploaderError.emptyResult
        }
        switch modifyResult {
        case .success(let record):
            return record
        case .failure(let error):
            throw error
        }
    }

    private func getRecord(_ recordID: CKRecord.ID, from database: CKDatabase) async throws -> CKRecord {
        let recordFetchResult = try await database.records(for: [recordID])[recordID]
        guard let recordFetchResult else {
            throw UploaderError.emptyResult
        }
        switch recordFetchResult {
        case .success(let record):
            return record
        case .failure(let error):
            throw error
        }
    }

    private func removeItem(_ item: RemoveItem, from database: CKDatabase) async throws {
        print("Attempt to remove an item")
        print("Fetching original item: \(item.id.recordName)")
        let record = try await getRecord(item.id, from: database)
        // Only modify authors and category fields
        record["authors"] = nil
        record["category"] = nil
        print("Uploading modified item: \(item.id.recordName)")
        try await submitRecord(record, savePolicy: .changedKeys, to: database)
    }

    private func createItem(_ item: CreateItem, in database: CKDatabase) async throws {
        print("Attempt to create an item")
        let id: String
        if let idRequirement = item.idRequirement {
            let expectedID = UUID().uuidString
            id = expectedID.replacingCharacters(in: expectedID.startIndex..<(expectedID.index(expectedID.startIndex, offsetBy: idRequirement.count)), with: idRequirement)
        } else {
            id = UUID().uuidString
        }
        let record = CKRecord(recordType: "ResourceItem", recordID: CKRecord.ID(recordName: id))
        print("Downloading cover image")
        let localCoverImageURL = try await download(item.coverImage)
        guard let coverImage = NSImage(contentsOf: localCoverImageURL) else {
            throw UploaderError.unsupportedImage
        }
        guard let resizedImage = coverImage.resized(to: NSSize(width: 600, height: 200)) else {
            throw UploaderError.resizeImage
        }
        let localThumbnailURL = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString))
        guard resizedImage.save(to: localThumbnailURL) else {
            throw UploaderError.saveResizedImage
        }
        print("Downloading addon")
        let localAddonURL = try await download(item.addon)

        let richDescriptionID: CKRecord.ID?
        if let richDescription = item.richDescription {
            richDescriptionID = try await uploadRichDescription(richDescription, to: database)
        } else {
            richDescriptionID = nil
        }

        record["name"] = item.title
        record["description"] = item.description
        record["authors"] = item.authors
        record["category"] = item.category
        record["publishTime"] = item.releaseDate
        record["lastUpdateTime"] = item.lastUpdateDate
        record["objectName"] = item.demoObjectName
        record["type"] = item.type
        record["mainScriptName"] = item.mainScriptName
        record["relatedObjectPaths"] = item.relatedObjectPaths
        record["image"] = CKAsset(fileURL: localCoverImageURL)
        record["thumbnail"] = CKAsset(fileURL: localThumbnailURL)
        record["item"] = CKAsset(fileURL: localAddonURL)
        if let richDescriptionID {
            record["localizedHTMLReferences"] = "{ \"en\": \"\(richDescriptionID.recordName)\" }"
        } else {
            record["localizedHTMLReferences"] = nil
        }
        let createdRecord = try await submitRecord(record, savePolicy: .allKeys, to: database)
        print("Created record: \(createdRecord.recordID.recordName)")
    }

    private func updateItem(_ item: UpdateItem, in database: CKDatabase) async throws {
        print("Attempt to update an item")
        print("Fetching original item: \(item.id.recordName)")
        let record = try await getRecord(item.id, from: database)
        let urls: (localCoverImageURL: URL, localThumbnailImageURL: URL)?
        if let coverImage = item.coverImage {
            print("Downloading cover image")
            let localCoverImageURL = try await download(coverImage)
            guard let coverImage = NSImage(contentsOf: localCoverImageURL) else {
                throw UploaderError.unsupportedImage
            }
            guard let resizedImage = coverImage.resized(to: NSSize(width: 600, height: 200)) else {
                throw UploaderError.resizeImage
            }
            let localThumbnailURL = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString))
            guard resizedImage.save(to: localThumbnailURL) else {
                throw UploaderError.saveResizedImage
            }
            urls = (localCoverImageURL, localThumbnailURL)
        } else {
            urls = nil
        }

        let localAddonURL: URL?
        if let addon = item.addon {
            print("Downloading addon")
            localAddonURL = try await download(addon)
        } else {
            localAddonURL = nil
        }

        if item.removeRichDescription {
            record["localizedHTMLReferences"] = nil
        } else if let richDescription = item.richDescription {
            let richDescriptionID = try await uploadRichDescription(richDescription, to: database)
            record["localizedHTMLReferences"] = "{ \"en\": \"\(richDescriptionID.recordName)\" }"
        }

        if let title = item.title {
            record["name"] = title
        }
        if let description = item.description {
            record["description"] = description
        }
        if let authors = item.authors {
            record["authors"] = authors
        }
        if let category = item.category {
            record["category"] = category
        }
        if let releaseDate = item.releaseDate {
            record["publishTime"] = releaseDate
        }
        if let lastUpdateDate = item.lastUpdateDate {
            record["lastUpdateTime"] = lastUpdateDate
        }
        if let demoObjectName = item.demoObjectName {
            record["objectName"] = demoObjectName
        }
        if let (localCoverImageURL, localThumbnailURL) = urls {
            record["image"] = CKAsset(fileURL: localCoverImageURL)
            record["thumbnail"] = CKAsset(fileURL: localThumbnailURL)
        }
        if let localAddonURL {
            record["item"] = CKAsset(fileURL: localAddonURL)
        }
        if let type = item.type {
            record["type"] = type
        }
        if let mainScriptName = item.mainScriptName {
            record["mainScriptName"] = mainScriptName
        }
        if let relatedObjectPaths = item.relatedObjectPaths {
            record["relatedObjectPaths"] = relatedObjectPaths
        }
        try await submitRecord(record, savePolicy: .changedKeys, to: database)
    }

    private func downloadInternal(_ url: URL) async throws -> URL {
        let data = try await AsyncDataRequestHandler.get(url: url.absoluteString)
        let outputPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        let outputURL = URL(fileURLWithPath: outputPath)
        try data.write(to: outputURL)
        return outputURL
    }

    private func download(_ url: URL) async throws -> URL {
        if url.isFileURL { return url }
        do {
            return try await downloadInternal(url)
        } catch {
            throw UploaderError.download
        }
    }

    private func uploadRichDescription(_ richDescription: RichDescription, to database: CKDatabase) async throws -> CKRecord.ID {
        print("Downloading rich description assets")
        let localCoverImageURL = try await download(richDescription.coverImage.imageURL)
        if NSImage(contentsOf: localCoverImageURL) == nil {
            throw UploaderError.unsupportedImage
        }
        var imageAssets = [CKAsset(fileURL: localCoverImageURL)]
        if let otherImages = richDescription.detailImages {
            for otherImage in otherImages {
                let localOtherImageURL = try await download(otherImage.imageURL)
                if NSImage(contentsOf: localOtherImageURL) == nil {
                    throw UploaderError.unsupportedImage
                }
                imageAssets.append(CKAsset(fileURL: localOtherImageURL))
            }
        }
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        print("Uploading rich description: \(recordID.recordName)")
        let record = CKRecord(recordType: "HTMLResource", recordID: recordID)
        record["data"] = richDescription.html.data(using: .utf8)!
        record["assets"] = imageAssets
        return try await submitRecord(record, savePolicy: .allKeys, to: database).recordID
    }

    private func uploadInternal(_ change: ItemOperation) async throws {
        let db = CKContainer.default().publicCloudDatabase
        switch change {
        case .remove(let item):
            try await removeItem(item, from: db)
        case .update(let item):
            try await updateItem(item, in: db)
        case .create(let item):
            try await createItem(item, in: db)
        }
    }

    public func upload(_ change: ItemOperation) async throws {
        do {
            try await uploadInternal(change)
        } catch {
            if error is CKError {
                throw UploaderError.cloudKit
            }
            if error is UploaderError {
                throw error
            }
            throw UploaderError.unknown
        }
    }
}
