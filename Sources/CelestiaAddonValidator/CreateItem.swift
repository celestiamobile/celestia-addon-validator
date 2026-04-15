import Foundation
import OpenCloudKit

public struct CreateItem {
    let title: String
    let category: CKRecord.Reference
    let idRequirement: String?
    let authors: [String]
    let description: String
    let demoObjectName: String?
    let coverImage: URL
    let addon: URL
    let richDescription: RichDescription?
    let type: String
    let mainScriptName: String?
    let relatedObjectPaths: [String]?
    let dependencies: [CKRecord.Reference]?
}
