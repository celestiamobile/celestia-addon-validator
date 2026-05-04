import Foundation
import ImageIO
import OpenCloudKit
import ZIPFoundation
import CelestiaCatalogParser

public enum ValidatorError: Error {
    case noIDOrIncorrectIDProvidedForRemoval
    case incorrectIDRequirementFormat
    case missingFields(fieldName: String)
    case richDescriptionRemovalConflict
    case richDescriptionRemovalOnCreate
    case emptyResult
    case fileManager
    case unzipping
    case cloudKit(error: Error)
    case incorrectRecordFieldType
    case network
    case badDemoObject(supportedPaths: [String])
    case badType(type: String)
    case changeTypeOfExisting
    case badRecordType(type: String)
    case nonPowerOfTwoTexture(path: String, width: Int, height: Int)
    case nonASCIIFileName(path: String)
    case invalidTexture(path: String)
    case invalidText(fieldName: String)
    case invalidDate(text: String, fieldName: String)
    case invalidInt(text: String, fieldName: String)
}

extension ValidatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noIDOrIncorrectIDProvidedForRemoval:
            return "No ID or incorrect ID provided for add-on removal"
        case .incorrectIDRequirementFormat:
            return "Incorrect ID requirement format"
        case let .missingFields(fieldName):
            return "Missing fields, field name: \(fieldName)"
        case .emptyResult:
            return "Empty result returned"
        case .fileManager:
            return "File manager error"
        case .unzipping:
            return "Error unzipping item"
        case .richDescriptionRemovalConflict:
            return "Rich description should be empty when remove_rich_description is on"
        case .richDescriptionRemovalOnCreate:
            return "remove_rich_description should not be on when creating an item"
        case let .cloudKit(error):
            return "CloudKit error: \(error)"
        case .incorrectRecordFieldType:
            return "Incorrect record field type found"
        case .network:
            return "Network error"
        case let .badDemoObject(supportedPaths):
            return "Bad demo object name, should be one of \(supportedPaths) or their ancestors"
        case let .badType(type):
            return "Type should be either script or addon, got \(type)"
        case .changeTypeOfExisting:
            return "Cannot change type of an existing item"
        case let .badRecordType(type):
            return "Bad record type, got \(type)"
        case let .nonPowerOfTwoTexture(path, width, height):
            return "Texture \(path) has non-power-of-two dimensions: \(width)x\(height)"
        case let .nonASCIIFileName(path):
            return "File has non-ASCII characters in name: \(path)"
        case let .invalidTexture(path):
            return "Invalid texture file: \(path)"
        case let .invalidText(fieldName):
            return "Invalid text in \(fieldName)"
        case let .invalidDate(text, fieldName):
            return "Invalid date in \(fieldName): \(text)"
        case let .invalidInt(text, fieldName):
            return "Invalid integer value in \(fieldName): \(text)"
        }
    }
}

public final class Validator {
    public init() {}

    public static func configure(_ config: CKContainerConfig) {
        CloudKit.shared.configure(with: CKConfig(containers: [config]))
    }

    public func validate(recordID: CKRecord.ID) async throws -> ItemOperation {
        let db = CKContainer.default().publicCloudDatabase
        let recordFetchResult = try await db.records(for: [recordID])[recordID]
        guard let recordFetchResult else {
            throw UploaderError.emptyResult
        }
        switch recordFetchResult {
        case .success(let record):
            return try await validate(record: record)
        case .failure(let error):
            throw error
        }
    }

    public func validate(zipFilePath: String) async throws -> ItemOperation {
        let temporaryDirectoryPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: temporaryDirectoryPath, withIntermediateDirectories: true)
        } catch {
            throw ValidatorError.fileManager
        }
        do {
            try fm.unzipItem(at: URL(fileURLWithPath: zipFilePath), to: URL(fileURLWithPath: temporaryDirectoryPath))
        } catch {
            throw ValidatorError.unzipping
        }
        var basePath = temporaryDirectoryPath
        var contents = [String]()
        while true {
            do {
                contents = try fm.contentsOfDirectory(atPath: basePath)
            } catch {
                throw ValidatorError.fileManager
            }
            if contents.count == 1 {
                var isDir: ObjCBool = false
                // Real content might be one level inside the zip
                let potentialPath = (basePath as NSString).appendingPathComponent(contents[0])
                if fm.fileExists(atPath: potentialPath, isDirectory: &isDir), isDir.boolValue, contents[0] != "rich_description" {
                    basePath = potentialPath
                } else {
                    break
                }
            } else {
                break
            }
        }
        return try await validateDirectory(basePath)
    }

    private func validateDirectory(_ path: String) async throws -> ItemOperation {
        let category = try readString(directoryPath: path, filename: "category.txt")
        let idRequirement = try readString(directoryPath: path, filename: "id_requirement.txt") ?? readString(directoryPath: path, filename: "id.txt")
        if let category, (category.isEmpty || category == "remove") {
            // This is a remove operation, should only check id_requirement
            guard let idRequirement, idRequirement.count == UUID().uuidString.count else {
                throw ValidatorError.noIDOrIncorrectIDProvidedForRemoval
            }
            // TODO: we could check the ID is valid or not by fetch the add-on
            return .remove(item: RemoveItem(id: CKRecord.ID(recordName: idRequirement)))
        }
        let authors = try readStringList(directoryPath: path, filename: "authors.txt")
        let releaseDate = try readDate(directoryPath: path, filename: "release_date.txt")
        let demoObjectName = try readString(directoryPath: path, filename: "demo_object_name.txt")
        let type = try readString(directoryPath: path, filename: "type.txt")
        let mainScriptName = try readString(directoryPath: path, filename: "main_script_name.txt")
        let title = try readString(directoryPath: path, filename: "title.txt")
        let description = try readString(directoryPath: path, filename: "description.txt")
        let rank = try readInt(directoryPath: path, filename: "rank.txt")
        let potentialAddonPath = (path as NSString).appendingPathComponent("addon.zip")
        let fm = FileManager.default
        let addonURL = fm.fileExists(atPath: potentialAddonPath) ? URL(fileURLWithPath: potentialAddonPath) : nil

        let potentialCoverImagePath = (path as NSString).appendingPathComponent("cover_image.jpg")
        let coverImageURL = fm.fileExists(atPath: potentialCoverImagePath) ? URL(fileURLWithPath: potentialCoverImagePath) : nil

        let modifyingExistingAddon: Bool
        if let idRequirement {
            if idRequirement.count == UUID().uuidString.count {
                modifyingExistingAddon = true
            } else {
                guard idRequirement.allSatisfy({ character in "0123456789ABCDEF".contains(where: { $0 == character }) }) else {
                    throw ValidatorError.incorrectIDRequirementFormat
                }
                guard idRequirement.count <= UUID().uuidString.split(separator: "-")[0].count else {
                    throw ValidatorError.incorrectIDRequirementFormat
                }
                modifyingExistingAddon = false
            }
        } else {
            modifyingExistingAddon = false
        }

        let richDescriptionDirectory = (path as NSString).appendingPathComponent("rich_description")
        var isDirectory: ObjCBool = false
        let richDescription: RichDescription?
        let removeRichDescription = try readString(directoryPath: path, filename: "remove_rich_description.txt") == "remove"
        if fm.fileExists(atPath: richDescriptionDirectory, isDirectory: &isDirectory), isDirectory.boolValue {
            if removeRichDescription {
                throw ValidatorError.richDescriptionRemovalConflict
            }
            let baseContent = try readString(directoryPath: richDescriptionDirectory, filename: "base.txt")!
            let noteType = try readString(directoryPath: richDescriptionDirectory, filename: "note_type.txt")
            let notes = try readStringList(directoryPath: richDescriptionDirectory, filename: "notes.txt")
            let richCoverImagePath = (richDescriptionDirectory as NSString).appendingPathComponent("cover_image.jpg")
            let richCoverText = try readString(directoryPath: richDescriptionDirectory, filename: "cover_image.txt")
            guard fm.fileExists(atPath: richCoverImagePath) else {
                throw ValidatorError.missingFields(fieldName: "rich_description/cover_image.jpg")
            }
            let youtubeIDs = try readStringList(directoryPath: richDescriptionDirectory, filename: "youtube_ids.txt")
            var images = [Image]()
            while true {
                let imagePath = (richDescriptionDirectory as NSString).appendingPathComponent("detail_image_\(images.count).jpg")
                if !fm.fileExists(atPath: imagePath) {
                    break
                }
                let caption = try readString(directoryPath: richDescriptionDirectory, filename: "detail_image_\(images.count).txt")
                images.append(Image(imageURL: URL(fileURLWithPath: imagePath), caption: caption))
            }
            let additionalLeadingHTML = try readString(directoryPath: richDescriptionDirectory, filename: "additional_leading.html")
            let additionalTrailingHTML = try readString(directoryPath: richDescriptionDirectory, filename: "additional_trailing.html")

            richDescription = RichDescription(base: baseContent, notes: notes, noteType: noteType, coverImage: Image(imageURL: URL(fileURLWithPath: richCoverImagePath), caption: richCoverText), detailImages: images.isEmpty ? nil : images, youtubeIDs: youtubeIDs, additionalLeadingHTML: additionalLeadingHTML, additionalTrailingHTML: additionalTrailingHTML)
        } else {
            richDescription = nil
        }

        let dependencies = try readStringList(directoryPath: path, filename: "dependencies.txt")
        if let dependencies {
            try await validateDependencies(dependencies)
        }

        if !modifyingExistingAddon {
            guard !removeRichDescription else {
                throw ValidatorError.richDescriptionRemovalOnCreate
            }
            guard let title else {
                throw ValidatorError.missingFields(fieldName: "title.txt")
            }
            guard let description else {
                throw ValidatorError.missingFields(fieldName: "description.txt")
            }
            guard let category else {
                throw ValidatorError.missingFields(fieldName: "category.txt")
            }
            guard let authors else {
                throw ValidatorError.missingFields(fieldName: "authors.txt")
            }
            guard let coverImageURL else {
                throw ValidatorError.missingFields(fieldName: "cover_image.jpg")
            }
            guard let addonURL else {
                throw ValidatorError.missingFields(fieldName: "addon.zip")
            }
            guard let type, ["addon", "script"].contains(type) else {
                throw ValidatorError.badType(type: type ?? "none")
            }
            let (relatedObjectPaths, needsUpdateRelatedObjectPaths) = try await validateAddonContents(location: .local(url: addonURL))
            if let demoObjectName, !relatedObjectPaths.contains(where: { demoObjectName == $0 || $0.hasPrefix("\(demoObjectName)/") }) {
                throw ValidatorError.badDemoObject(supportedPaths: relatedObjectPaths)
            }
            return .create(
                item: CreateItem(
                    title: title,
                    category: CKRecord.Reference(recordID: CKRecord.ID(recordName: category), action: .none),
                    idRequirement: idRequirement,
                    authors: authors,
                    description: description,
                    demoObjectName: demoObjectName,
                    coverImage: coverImageURL,
                    addon: addonURL,
                    richDescription: richDescription,
                    type: type,
                    mainScriptName: mainScriptName,
                    relatedObjectPaths: needsUpdateRelatedObjectPaths ? relatedObjectPaths : nil,
                    dependencies: dependencies?.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .none) },
                    rank: rank
                )
            )
        }

        let removeDependencies = try readString(directoryPath: path, filename: "remove_dependencies.txt") == "remove"
        guard let idRequirement else {
            throw ValidatorError.missingFields(fieldName: "id_requirement.txt")
        }
        let categoryReference: CKRecord.Reference?
        if let category, !category.isEmpty {
            categoryReference = CKRecord.Reference(recordID: CKRecord.ID(recordName: category), action: .none)
        } else {
            categoryReference = nil
        }

        guard type == nil || type == "none" else {
            throw ValidatorError.changeTypeOfExisting
        }

        let relatedObjectPaths: [String]
        let needsUpdateRelatedObjectPaths: Bool
        if let addonURL {
            (relatedObjectPaths, needsUpdateRelatedObjectPaths) = try await validateAddonContents(location: .local(url: addonURL))
        } else {
            (relatedObjectPaths, needsUpdateRelatedObjectPaths) = try await validateAddonContents(location: .remote(id: idRequirement))
        }
        if let demoObjectName, !relatedObjectPaths.contains(where: { demoObjectName == $0 || $0.hasPrefix("\(demoObjectName)/") }) {
            throw ValidatorError.badDemoObject(supportedPaths: relatedObjectPaths)
        }
        return .update(
            item: UpdateItem(
                title: title,
                category: categoryReference,
                id: CKRecord.ID(recordName: idRequirement),
                authors: authors,
                description: description,
                demoObjectName: demoObjectName,
                coverImage: coverImageURL,
                addon: addonURL,
                richDescription: richDescription,
                mainScriptName: mainScriptName,
                removeRichDescription: removeRichDescription,
                relatedObjectPaths: needsUpdateRelatedObjectPaths ? relatedObjectPaths : nil,
                dependencies: dependencies?.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .none) },
                removeDependencies: removeDependencies,
                rank: rank
            )
        )
    }

    private enum AddonLocation {
        case local(url: URL)
        case remote(id: String)
    }

    private func validateDependencies(_ dependencies: [String]) async throws {
        let db = CKContainer.default().publicCloudDatabase
        let recordIds = dependencies.map({ CKRecord.ID(recordName: $0) })
        var recordResults: [CKRecord.ID : Result<CKRecord, Error>]
        do {
            recordResults = try await db.records(for: recordIds, desiredKeys: [])
        } catch {
            throw ValidatorError.cloudKit(error: error)
        }
        for (_, result) in recordResults {
            switch result {
            case let .success(record):
                guard record.recordType == "ResourceItem" else {
                    throw ValidatorError.badRecordType(type: record.recordType)
                }
            case let .failure(error):
                throw ValidatorError.cloudKit(error: error)
            }
        }
    }

    private func validateAddonContents(location: AddonLocation) async throws -> ([String], Bool) {
        let addonURL: URL
        switch location {
        case let .local(url):
            if url.isFileURL {
                addonURL = url
            } else {
                guard let downloadedURL = try await Downloader.download(url) else {
                    throw ValidatorError.network
                }
                addonURL = downloadedURL
            }
        case let .remote(id):
            let db = CKContainer.default().publicCloudDatabase
            let recordId = CKRecord.ID(recordName: id)
            let recordResult: Result<CKRecord, Error>?
            do {
                recordResult = try await db.records(for: [recordId], desiredKeys: ["item", "relatedObjectPaths"])[recordId]
            } catch {
                throw ValidatorError.cloudKit(error: error)
            }
            guard let recordResult else {
                throw ValidatorError.emptyResult
            }
            switch recordResult {
            case let .success(record):
                if let relatedObjectPaths = record["relatedObjectPaths"] as? [String] {
                    return (relatedObjectPaths, false)
                }

                guard let addon = record["item"] as? CKAsset else {
                    throw ValidatorError.incorrectRecordFieldType
                }
                guard let url = try await Downloader.download(addon.fileURL) else {
                    throw ValidatorError.network
                }
                addonURL = url
            case let .failure(error):
                throw ValidatorError.cloudKit(error: error)
            }
        }

        let fm = FileManager.default
        let temporaryDirectoryPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        do {
            try fm.unzipItem(at: addonURL, to: URL(fileURLWithPath: temporaryDirectoryPath))
        } catch {
            throw ValidatorError.unzipping
        }

        let targetExtensions: Set<String> = ["dsc", "stc", "ssc"]
        let textureImageExtensions: Set<String> = ["jpg", "jpeg", "png"]
        guard let enumerator = fm.enumerator(atPath: temporaryDirectoryPath) else {
            throw ValidatorError.fileManager
        }
        var catalogFiles = [String]()
        while let relativePath = enumerator.nextObject() as? String {
            let ext = (relativePath as NSString).pathExtension.lowercased()
            if targetExtensions.contains(ext) {
                catalogFiles.append((temporaryDirectoryPath as NSString).appendingPathComponent(relativePath))
            }

            let pathComponents = relativePath.components(separatedBy: "/")
            let directoryComponents = pathComponents.dropLast()
            let fileName = pathComponents.last ?? ""
            let isUnderTextures = directoryComponents.contains("textures")
            let isUnderModels = directoryComponents.contains("models")
            let isUnderData = directoryComponents.contains("data")
            let isCatalogFile = targetExtensions.contains(ext)

            // Validate ASCII filenames for catalog files and files under models/textures/data
            if (isCatalogFile || isUnderTextures || isUnderModels || isUnderData) && !fileName.isEmpty {
                if !fileName.allSatisfy({ $0.isASCII }) {
                    throw ValidatorError.nonASCIIFileName(path: relativePath)
                }
            }

            // Validate texture image dimensions are power of two
            if isUnderTextures && textureImageExtensions.contains(ext) {
                let fullPath = (temporaryDirectoryPath as NSString).appendingPathComponent(relativePath)
                let url = URL(fileURLWithPath: fullPath)
                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as NSDictionary?,
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                    throw ValidatorError.invalidTexture(path: relativePath)
                }
                if !width.isPowerOfTwo || !height.isPowerOfTwo {
                    throw ValidatorError.nonPowerOfTwoTexture(path: relativePath, width: width, height: height)
                }
            }
        }

        var objectPaths = [String]()
        for catalogFile in catalogFiles {
            guard let data = fm.contents(atPath: catalogFile),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }
            objectPaths.append(contentsOf: CatalogObjectPathExtractor.extractObjectPaths(from: content).objectPaths)
        }
        let filtered = Array(Set(objectPaths))
        return (filtered, filtered.count < 50)
    }

    public func validate(record: CKRecord) async throws -> ItemOperation {
        let remove = record["remove"] as? Bool
        let idRequirement = record["id_requirement"] as? String
        if let remove, remove {
            // This is a remove operation, should only check id_requirement
            print("Parsing remove item...")
            guard let idRequirement, idRequirement.count == UUID().uuidString.count else {
                throw ValidatorError.noIDOrIncorrectIDProvidedForRemoval
            }
            // TODO: we could check the ID is valid or not by fetch the add-on
            return .remove(item: RemoveItem(id: CKRecord.ID(recordName: idRequirement)))
        }
        let modifyingExistingAddon: Bool
        if let idRequirement {
            if idRequirement.count == UUID().uuidString.count {
                modifyingExistingAddon = true
            } else {
                guard idRequirement.allSatisfy({ character in "0123456789ABCDEF".contains(where: { $0 == character }) }) else {
                    throw ValidatorError.incorrectIDRequirementFormat
                }
                guard idRequirement.count <= UUID().uuidString.split(separator: "-")[0].count else {
                    throw ValidatorError.incorrectIDRequirementFormat
                }
                modifyingExistingAddon = false
            }
        } else {
            modifyingExistingAddon = false
        }

        let removeRichDescription = record["remove_rich_description"] as? Bool ?? false
        let richDescription: RichDescription?
        if let baseContent = record["rich_description_base"] as? String {
            if removeRichDescription {
                throw ValidatorError.richDescriptionRemovalConflict
            }

            // Parse rich description...
            print("Parsing rich description...")

            guard let coverImageURL = (record["rich_description_cover_image"] as? CKAsset)?.fileURL else {
                throw ValidatorError.missingFields(fieldName: "rich_description_cover_image")
            }
            let notes = record["rich_description_notes"] as? [String]
            let noteType = record["rich_description_note_type"] as? String
            let coverImageCaption = record["rich_description_cover_image_caption"] as? String
            let youtubeIDs = record["rich_description_youtube_ids"] as? [String]
            let additionalLeadingHTML = record["rich_description_additional_leading"] as? String
            let additionalTrailingHTML = record["rich_description_additional_trailing"] as? String
            let detailCoverImageCaptions = record["rich_description_detail_image_captions"] as? [String]
            let detailCoverImages = record["rich_description_detail_images"] as? [CKAsset]

            var detailImages: [Image] = []
            if let detailCoverImages {
                for (index, detailCoverImage) in detailCoverImages.enumerated() {
                    if let detailCoverImageCaptions, detailCoverImageCaptions.count > index {
                        detailImages.append(Image(imageURL: detailCoverImage.fileURL, caption: detailCoverImageCaptions[index]))
                    } else {
                        detailImages.append(Image(imageURL: detailCoverImage.fileURL, caption: nil))
                    }
                }
            }

            richDescription = RichDescription(base: baseContent, notes: notes, noteType: noteType, coverImage: Image(imageURL: coverImageURL, caption: coverImageCaption), detailImages: detailImages.isEmpty ? nil : detailImages, youtubeIDs: youtubeIDs, additionalLeadingHTML: additionalLeadingHTML, additionalTrailingHTML: additionalTrailingHTML)
        } else {
            richDescription = nil
        }

        // Parse main contents...
        print("Parsing main contents...")
        let title = record["title"] as? String
        let description = record["description"] as? String
        let category = record["category"] as? CKRecord.Reference
        let authors = record["authors"] as? [String]
        let addonURL = (record["addon"] as? CKAsset)?.fileURL
        let demoObjectName = record["demo_object_name"] as? String
        let type = record["type"] as? String
        let mainScriptName = record["main_script_name"] as? String
        let coverImageURL = (record["cover_image"] as? CKAsset)?.fileURL
        let rank = record["rank"] as? Int

        let dependencies = record["dependencies"] as? [String]
        if let dependencies {
            try await validateDependencies(dependencies)
        }

        if !modifyingExistingAddon {
            guard !removeRichDescription else {
                throw ValidatorError.richDescriptionRemovalOnCreate
            }
            guard let title else {
                throw ValidatorError.missingFields(fieldName: "title")
            }
            guard let description else {
                throw ValidatorError.missingFields(fieldName: "description")
            }
            guard let category else {
                throw ValidatorError.missingFields(fieldName: "category")
            }
            guard let authors else {
                throw ValidatorError.missingFields(fieldName: "authors")
            }
            guard let coverImageURL else {
                throw ValidatorError.missingFields(fieldName: "cover_image")
            }
            guard let addonURL else {
                throw ValidatorError.missingFields(fieldName: "addon")
            }
            guard let type, ["addon", "script"].contains(type) else {
                throw ValidatorError.badType(type: type ?? "none")
            }
            let (relatedObjectPaths, needsUpdateRelatedObjectPaths) = try await validateAddonContents(location: .local(url: addonURL))
            if let demoObjectName, !relatedObjectPaths.contains(where: { demoObjectName == $0 || $0.hasPrefix("\(demoObjectName)/") }) {
                throw ValidatorError.badDemoObject(supportedPaths: relatedObjectPaths)
            }
            return .create(
                item: CreateItem(
                    title: title,
                    category: category,
                    idRequirement: idRequirement,
                    authors: authors,
                    description: description,
                    demoObjectName: demoObjectName,
                    coverImage: coverImageURL,
                    addon: addonURL,
                    richDescription: richDescription,
                    type: type,
                    mainScriptName: mainScriptName,
                    relatedObjectPaths: needsUpdateRelatedObjectPaths ? relatedObjectPaths : nil,
                    dependencies:  dependencies?.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .none) },
                    rank: rank
                )
            )
        }
        guard let idRequirement else {
            throw ValidatorError.missingFields(fieldName: "id_requirement")
        }

        guard type == nil || type == "none" else {
            throw ValidatorError.changeTypeOfExisting
        }

        let relatedObjectPaths: [String]
        let needsUpdateRelatedObjectPaths: Bool
        if let addonURL {
            (relatedObjectPaths, needsUpdateRelatedObjectPaths) = try await validateAddonContents(location: .local(url: addonURL))
        } else {
            (relatedObjectPaths, needsUpdateRelatedObjectPaths) = try await validateAddonContents(location: .remote(id: idRequirement))
        }

        if let demoObjectName, !relatedObjectPaths.contains(where: { demoObjectName == $0 || $0.hasPrefix("\(demoObjectName)/") }) {
            throw ValidatorError.badDemoObject(supportedPaths: relatedObjectPaths)
        }

        let removeDependencies = record["remove_dependencies"] as? Bool ?? false
        return .update(
            item: UpdateItem(
                title: title,
                category: category,
                id: CKRecord.ID(recordName: idRequirement),
                authors: authors,
                description: description,
                demoObjectName: demoObjectName,
                coverImage: coverImageURL,
                addon: addonURL,
                richDescription: richDescription,
                mainScriptName: mainScriptName,
                removeRichDescription: removeRichDescription,
                relatedObjectPaths: needsUpdateRelatedObjectPaths ? relatedObjectPaths : nil,
                dependencies: dependencies?.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .none) },
                removeDependencies: removeDependencies,
                rank: rank
            )
        )
    }
}

extension Validator {
    private func readString(directoryPath: String, filename: String) throws -> String? {
        let file = (directoryPath as NSString).appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: file) {
            return nil
        }

        let contents: Data
        do {
            contents = try Data(contentsOf: URL(fileURLWithPath: file))
        } catch {
            throw ValidatorError.invalidText(fieldName: filename)
        }

        guard let string = String(data: contents, encoding: .utf8) else {
            throw ValidatorError.invalidText(fieldName: filename)
        }
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readStringList(directoryPath: String, filename: String) throws -> [String]? {
        guard let string = try readString(directoryPath: directoryPath, filename: filename) else {
            return nil
        }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n").map({ String($0) }).filter { !$0.isEmpty }
    }

    private func readDate(directoryPath: String, filename: String) throws -> Date? {
        guard let string = try readString(directoryPath: directoryPath, filename: filename) else {
            return nil
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "GMT")
        guard let date = dateFormatter.date(from: string) else {
            throw ValidatorError.invalidDate(text: string, fieldName: filename)
        }
        return date
    }

    private func readInt(directoryPath: String, filename: String) throws -> Int? {
        guard let string = try readString(directoryPath: directoryPath, filename: filename) else {
            return nil
        }
        guard let int = Int(string) else {
            throw ValidatorError.invalidInt(text: string, fieldName: filename)
        }
        return int
    }
}

private extension Int {
    var isPowerOfTwo: Bool {
        self > 0 && (self & (self - 1)) == 0
    }
}
