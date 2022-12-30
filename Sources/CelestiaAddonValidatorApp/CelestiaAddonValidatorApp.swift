import ArgumentParser
import CelestiaAddonValidator
import Foundation
import OpenCloudKit

enum ArgumentError: Error {
    case noAuth
}

extension ArgumentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noAuth:
            return "No authentication method is provided"
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

    @Argument(help: "The pending record ID to validate or update from.")
    var recordID: String

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
        let change = try await validator.validate(recordID: CKRecord.ID(recordName: recordID))
        print("Summary:\n\(change.summary)")

        if upload {
            let uploader = Uploader()
            try await uploader.upload(change)
        }
    }
}
