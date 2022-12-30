import Foundation
import OpenCloudKit

public enum ValidatorError: Error {
    case noIDOrIncorrectIDProvidedForRemoval
    case incorrectIDRequirementFormat
    case missingFields(fieldName: String)
    case emptyResult
}

extension ValidatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noIDOrIncorrectIDProvidedForRemoval:
            return "No ID or incorrect ID provided for add-on removal"
        case .incorrectIDRequirementFormat:
            return "Incorrect ID requirement format"
        case .missingFields(let fieldName):
            return "Missing fields, field name: \(fieldName)"
        case .emptyResult:
            return "Empty result returned"
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

        let richDescription: RichDescription?
        if let baseContent = record["rich_description_base"] as? String {
            // Parse rich description...
            print("Parsing rich description...")

            guard let coverImageURL = (record["rich_description_cover_image"] as? CKAsset)?.fileURL else {
                throw ValidatorError.missingFields(fieldName: "rich_description_cover_image")
            }
            let notes = record["rich_description_notes"] as? [String]
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

            richDescription = RichDescription(base: baseContent, notes: notes, coverImage: Image(imageURL: coverImageURL, caption: coverImageCaption), detailImages: detailImages.isEmpty ? nil : detailImages, youtubeIDs: youtubeIDs, additionalLeadingHTML: additionalLeadingHTML, additionalTrailingHTML: additionalTrailingHTML)
        } else {
            richDescription = nil
        }

        // Parse main contents...
        print("Parsing main contents...")
        let title = record["title"] as? String
        let description = record["description"] as? String
        let category = record["category"] as? CKRecord.Reference
        let releaseDate = record["release_date"] as? Date
        let lastUpdateDate = record["last_update_date"] as? Date
        let authors = record["authors"] as? [String]
        let addonURL = (record["addon"] as? CKAsset)?.fileURL
        let demoObjectName = record["demo_object_name"] as? String
        let coverImageURL = (record["cover_image"] as? CKAsset)?.fileURL

        if !modifyingExistingAddon {
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
            guard let releaseDate else {
                throw ValidatorError.missingFields(fieldName: "release_date")
            }
            guard let coverImageURL else {
                throw ValidatorError.missingFields(fieldName: "cover_image")
            }
            guard let addonURL else {
                throw ValidatorError.missingFields(fieldName: "addon")
            }
            return .create(item: CreateItem(title: title, category: category, idRequirement: idRequirement, authors: authors, description: description, demoObjectName: demoObjectName, releaseDate: releaseDate, lastUpdateDate: lastUpdateDate, coverImage: coverImageURL, addon: addonURL, richDescription: richDescription))
        }
        guard let idRequirement else {
            throw ValidatorError.missingFields(fieldName: "id_requirement")
        }
        return .update(item: UpdateItem(title: title, category: category, id: CKRecord.ID(recordName: idRequirement), authors: authors, description: description, demoObjectName: demoObjectName, releaseDate: releaseDate, lastUpdateDate: lastUpdateDate, coverImage: coverImageURL, addon: addonURL, richDescription: richDescription))
    }
}
