import ArgumentParser
import CelestiaAddonValidator
import OpenCloudKit

@main
struct CelestiaAddonValidatorApp: AsyncParsableCommand {
    static let containerID = "iCloud.space.celestia.Celestia"
    static let environment = CKEnvironment.production

    @Flag(help: "Validate the pending record and upload it")
    var upload = false

    @Argument(help: "The key file path for CloudKit.")
    var keyFilePath: String

    @Argument(help: "The key ID for CloudKit.")
    var keyID: String

    @Argument(help: "The pending record ID to validate or update from.")
    var recordID: String

    mutating func run() async throws {
        let serverKeyAuth = try CKServerToServerKeyAuth(keyID: keyID, privateKeyFile: keyFilePath)
        let config = CKContainerConfig(containerIdentifier: Self.containerID, environment: Self.environment, serverToServerKeyAuth: serverKeyAuth)
        Validator.configure(config)
        let validator = Validator()
        let change = try await validator.validate(recordID: CKRecord.ID(recordName: recordID))
        if upload {
            let uploader = Uploader()
            try await uploader.upload(change)
        }
    }
}
