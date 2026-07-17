import Crypto
import Foundation

/// Mints a read-only Azure Blob service SAS URL for a single blob, signed with
/// the storage account key (HMAC-SHA256). No Azure SDK is required; this
/// implements the string-to-sign for API version 2020-12-06 and later. See:
/// https://learn.microsoft.com/rest/api/storageservices/create-service-sas
///
/// The submit-addon page uploads the zip to Azure and records only the blob name
/// in the pull request, so CI mints its own short-lived download SAS here instead
/// of a long-lived credential being committed to the public repository.
public enum AzureBlobSAS {
    public static let accountName = "celestiaaddons"
    public static let containerName = "pending"
    public static let apiVersion = "2022-11-02"

    public enum SASError: Error {
        case invalidAccountKey
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()

    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Returns the full `https://…/blob?<sas>` URL granting read access on
    /// `blobName` until `expiry`, signed with the base64-encoded `accountKey`.
    public static func readURL(blobName: String, accountKey: String, expiry: Date) throws -> String {
        let permissions = "r"
        let signedStart = dateFormatter.string(from: Date().addingTimeInterval(-5 * 60))
        let signedExpiry = dateFormatter.string(from: expiry)
        let signedResource = "b"
        let signedProtocol = "https"
        let canonicalizedResource = "/blob/\(accountName)/\(containerName)/\(blobName)"

        // String-to-sign for service SAS, version 2020-12-06 and later.
        let stringToSign = [
            permissions,          // signedPermissions
            signedStart,          // signedStart
            signedExpiry,         // signedExpiry
            canonicalizedResource,
            "",                   // signedIdentifier
            "",                   // signedIP
            signedProtocol,       // signedProtocol
            apiVersion,           // signedVersion
            signedResource,       // signedResource
            "",                   // signedSnapshotTime
            "",                   // signedEncryptionScope
            "",                   // rscc  (Cache-Control)
            "",                   // rscd  (Content-Disposition)
            "",                   // rsce  (Content-Encoding)
            "",                   // rscl  (Content-Language)
            "",                   // rsct  (Content-Type)
        ].joined(separator: "\n")

        guard let keyData = Data(base64Encoded: accountKey) else {
            throw SASError.invalidAccountKey
        }
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: keyData)
        )
        let signatureBase64 = Data(signature).base64EncodedString()

        let query = [
            "sv=\(encode(apiVersion))",
            "sr=\(signedResource)",
            "sp=\(encode(permissions))",
            "st=\(encode(signedStart))",
            "se=\(encode(signedExpiry))",
            "spr=\(signedProtocol)",
            "sig=\(encode(signatureBase64))",
        ].joined(separator: "&")

        let baseURL = "https://\(accountName).blob.core.windows.net/\(containerName)/\(blobName)"
        return "\(baseURL)?\(query)"
    }
}
