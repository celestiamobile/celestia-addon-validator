import Foundation

/// Runs `steamcmd workshop_build_item` against a staged content folder and
/// parses the resulting `PublishedFileId_t` from stdout.
struct SteamCmdRunner {
    let steamcmdPath: URL
    let username: String

    struct UploadResult {
        /// The `PublishedFileId_t` Steam assigned (decimal string).
        let publishedFileId: String
        /// True if this was a fresh "create"; false if an update of an existing item.
        let wasCreated: Bool
    }

    enum RunnerError: Error, LocalizedError {
        case steamcmdFailed(exitCode: Int32, stdout: String, stderr: String)
        case noPublishedFileIdInOutput(stdout: String)

        var errorDescription: String? {
            switch self {
            case .steamcmdFailed(let code, _, let stderr):
                return "steamcmd exited with code \(code)\nstderr: \(stderr.suffix(2000))"
            case .noPublishedFileIdInOutput:
                return "steamcmd succeeded but no PublishedFileId was found in its output"
            }
        }
    }

    /// Invokes `steamcmd +login USER +workshop_build_item VDF +quit` and
    /// returns the (created/updated) PublishedFileId from the stdout.
    func uploadWorkshopItem(vdfPath: URL) throws -> UploadResult {
        let process = Process()
        process.executableURL = steamcmdPath
        process.arguments = [
            "+login", username,
            "+workshop_build_item", vdfPath.path,
            "+quit",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw RunnerError.steamcmdFailed(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }

        return try parsePublishedFileId(stdout: stdout)
    }

    /// steamcmd prints one of:
    ///   "Successfully created item ID 1234567890"
    ///   "Successfully updated item ID 1234567890"
    private func parsePublishedFileId(stdout: String) throws -> UploadResult {
        for line in stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let m = parseLine(trimmed) {
                return m
            }
        }
        throw RunnerError.noPublishedFileIdInOutput(stdout: stdout)
    }

    private func parseLine(_ line: String) -> UploadResult? {
        let createdPrefix = "Successfully created item ID "
        let updatedPrefix = "Successfully updated item ID "
        if line.hasPrefix(createdPrefix) {
            let id = String(line.dropFirst(createdPrefix.count))
                .trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            return id.isEmpty ? nil : UploadResult(publishedFileId: id, wasCreated: true)
        }
        if line.hasPrefix(updatedPrefix) {
            let id = String(line.dropFirst(updatedPrefix.count))
                .trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            return id.isEmpty ? nil : UploadResult(publishedFileId: id, wasCreated: false)
        }
        return nil
    }
}
