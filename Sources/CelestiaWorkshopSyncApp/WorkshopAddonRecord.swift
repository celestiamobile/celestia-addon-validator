import CloudKitCodable
import Foundation

/// Local view of the `ResourceItem` CloudKit record, decoded just enough
/// for the Workshop sync. Modeled after `CloudKitAddon` in celestia-server's
/// PushNotification module but kept here to avoid depending on the server
/// codebase.
struct WorkshopAddonRecord: Decodable, CustomCloudKitDecodable, Sendable {
    var cloudKitSystemFields: Data?
    var cloudKitIdentifier: String

    let item: CKAssetDownloadInfo
    let category: CKReferenceInfo?
    let image: CKAssetDownloadInfo?
    let name: String
    let description: String
    let authors: [String]?
    let type: String?
}
