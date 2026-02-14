import ArgumentParser
import CelestiaAddonValidator
import Foundation
import OpenCloudKit

enum ArgumentError: Error {
    case noAuth
    case noItem
}

extension ArgumentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noAuth:
            return "No authentication method is provided"
        case .noItem:
            return "No item is provided for validation"
        }
    }
}

@main
struct CelestiaAddonValidatorApp: AsyncParsableCommand {
    static let containerID = "iCloud.space.celestia.Celestia"
    static let environment = CKEnvironment.production

    @Flag(help: "Validate the pending record and upload it")
    var upload = false

    @Option(help: "The key file path for CloudKit.")
    var keyFilePath: String?

    @Option(help: "The key ID for CloudKit.")
    var keyID: String?

    @Option(help: "The API token for CloudKit.")
    var apiToken: String?

    @Option(help: "The pending record ID to validate or update from.")
    var recordID: String?

    @Option(help: "The zip file to validate or update from.")
    var zipFilePath: String?

    mutating func run() async throws {
        let config: CKContainerConfig
        if let keyID, let keyFilePath {
            let serverKeyAuth = try CKServerToServerKeyAuth(keyID: keyID, privateKeyFile: keyFilePath)
            config = CKContainerConfig(containerIdentifier: Self.containerID, environment: Self.environment, serverToServerKeyAuth: serverKeyAuth)
        } else if let apiToken {
            config = CKContainerConfig(containerIdentifier: Self.containerID, environment: Self.environment, apiTokenAuth: apiToken)
        } else {
            throw ArgumentError.noAuth
        }

        Validator.configure(config)
        let validator = Validator()
        let change: ItemOperation
        if let recordID {
            change = try await validator.validate(recordID: CKRecord.ID(recordName: recordID))
        } else if let zipFilePath {
            change = try await validator.validate(zipFilePath: zipFilePath)
        } else {
            throw ArgumentError.noItem
        }
        print("Summary:\n\(change.summary)")

        if upload {
            let uploader = Uploader()
            try await uploader.upload(change)
        }
    }
}
