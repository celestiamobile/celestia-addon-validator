import Foundation
import OpenCloudKit

public struct UpdateItem {
    let title: String?
    let category: CKRecord.Reference?
    let id: CKRecord.ID
    let authors: [String]?
    let description: String?
    let demoObjectName: String?
    let releaseDate: Date?
    let lastUpdateDate: Date?
    let coverImage: URL?
    let addon: URL?
    let richDescription: RichDescription?
    let type: String?
    let mainScriptName: String?
    let removeRichDescription: Bool
    let relatedObjectPaths: [String]?
}
