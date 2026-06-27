import ArgumentParser
import CelestiaAddonValidator
import Foundation
import OpenCloudKit

enum SyncArgumentError: Error {
    case noAuth
}

extension SyncArgumentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noAuth:
            return "No authentication method is provided"
        }
    }
}

@main
struct CelestiaWorkshopSyncApp: AsyncParsableCommand {
    static let containerID = "iCloud.space.celestia.Celestia"
    static let environment = CKEnvironment.production

    @Option(help: "The key file path for CloudKit (server-to-server auth).")
    var keyFilePath: String?

    @Option(help: "The key ID for CloudKit (server-to-server auth).")
    var keyID: String?

    @Option(help: "The API token for CloudKit (alternative to key file).")
    var apiToken: String?

    @Option(help: "Path to the celestia-steam-workshop-history checkout.")
    var stateDir: String

    @Option(help: "Path to the steamcmd executable.")
    var steamcmdPath: String

    @Option(help: "Steam App ID for the Workshop items.")
    var appID: String

    @Option(help: "Steam username that owns the Workshop items (cached session must already be in place).")
    var steamUsername: String

    @Flag(help: "Compute changes but do not upload to Steam Workshop or write state files.")
    var dryRun = false

    @Option(help: "Maximum number of items to actually upload this run. 0 = no cap. Useful for staging the first bulk sync.")
    var limit: Int = 0

    mutating func run() async throws {
        let config: CKContainerConfig
        if let keyID, let keyFilePath {
            let serverKeyAuth = try CKServerToServerKeyAuth(keyID: keyID, privateKeyFile: keyFilePath)
            config = CKContainerConfig(containerIdentifier: Self.containerID, environment: Self.environment, serverToServerKeyAuth: serverKeyAuth)
        } else if let apiToken {
            config = CKContainerConfig(containerIdentifier: Self.containerID, environment: Self.environment, apiTokenAuth: apiToken)
        } else {
            throw SyncArgumentError.noAuth
        }
        CloudKit.shared.configure(with: CKConfig(containers: [config]))

        try await withHTTPClient { httpClient in
            let coordinator = SyncCoordinator(
                stateDir: URL(fileURLWithPath: stateDir),
                steamcmdPath: URL(fileURLWithPath: steamcmdPath),
                appID: appID,
                steamUsername: steamUsername,
                dryRun: dryRun,
                httpClient: httpClient,
                limit: limit
            )
            try await coordinator.run()
        }
    }
}
