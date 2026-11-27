import Foundation
import OpenCloudKit
import XCTest
import ZIPFoundation

@testable import CelestiaAddonValidator
@testable import CelestiaWorkshopSyncApp

final class HookValidationTests: XCTestCase {
    private static let invalidMainScriptNames: [String?] = [
        nil, "", " \n ", "missing.lua", "scripts", "Scripts/main.lua", "scripts/Main.lua",
        "scripts/main.lua/.", "scripts/main.lua/../main.lua", "scripts/main.lua/",
        "scripts//main.lua", "./scripts/main.lua", "scripts/./main.lua",
        "scripts/../scripts/main.lua",
    ]

    func testCloudKitHookSubmissionsRequireAnExistingMainScript() async throws {
        let directory = try makeDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let addon = try makeAddon(in: directory)
        let cover = directory.appendingPathComponent("cover.jpg")
        try Data().write(to: cover)

        try await withHTTPClient { httpClient in
            let validator = Validator(httpClient: httpClient)
            for name in Self.invalidMainScriptNames {
                let record = makeRecord(addon: addon, cover: cover, type: "hook", mainScriptName: name)
                do {
                    _ = try await validator.validate(record: record)
                    XCTFail("Accepted invalid hook main script: \(name ?? "nil")")
                } catch let ValidatorError.invalidMainScriptName(rejectedName) {
                    XCTAssertEqual(rejectedName, name)
                }
            }

            let record = makeRecord(
                addon: addon, cover: cover, type: "hook", mainScriptName: "scripts/main.lua")
            guard case let .create(item) = try await validator.validate(record: record) else {
                return XCTFail("Expected a create operation")
            }
            XCTAssertEqual(item.type, "hook")
            XCTAssertEqual(item.mainScriptName, "scripts/main.lua")
        }
    }

    func testZIPHookSubmissionsRequireAnExistingMainScript() async throws {
        let directory = try makeDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let addon = try makeAddon(in: directory)

        try await withHTTPClient { httpClient in
            let validator = Validator(httpClient: httpClient)
            for (index, name) in (Self.invalidMainScriptNames + ["scripts/main.lua"]).enumerated() {
                let source = directory.appendingPathComponent("submission-\(index)")
                try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
                for (field, value) in [
                    "title.txt": "Hook", "description.txt": "Hook description",
                    "category.txt": "category", "authors.txt": "Author", "type.txt": "hook",
                ] {
                    try Data(value.utf8).write(to: source.appendingPathComponent(field))
                }
                if let name {
                    try Data(name.utf8).write(to: source.appendingPathComponent("main_script_name.txt"))
                }
                try Data().write(to: source.appendingPathComponent("cover_image.jpg"))
                try FileManager.default.copyItem(at: addon, to: source.appendingPathComponent("addon.zip"))
                let archive = directory.appendingPathComponent("submission-\(index).zip")
                try FileManager.default.zipItem(at: source, to: archive, shouldKeepParent: false)

                do {
                    let operation = try await validator.validate(zipFilePath: archive.path)
                    guard name == "scripts/main.lua", case let .create(item) = operation else {
                        return XCTFail("Accepted invalid hook main script: \(name ?? "nil")")
                    }
                    XCTAssertEqual(item.type, "hook")
                    XCTAssertEqual(item.mainScriptName, name)
                } catch let ValidatorError.invalidMainScriptName(rejectedName) {
                    XCTAssertNotEqual(name, "scripts/main.lua")
                    XCTAssertEqual(rejectedName, name?.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    func testOtherTypesDoNotRequireMainScripts() async throws {
        let directory = try makeDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let addon = try makeAddon(in: directory)
        let cover = directory.appendingPathComponent("cover.jpg")
        try Data().write(to: cover)

        try await withHTTPClient { httpClient in
            let validator = Validator(httpClient: httpClient)
            for type in ["addon", "script"] {
                let record = makeRecord(addon: addon, cover: cover, type: type, mainScriptName: nil)
                guard case let .create(item) = try await validator.validate(record: record) else {
                    return XCTFail("Expected a create operation")
                }
                XCTAssertEqual(item.type, type)
                XCTAssertNil(item.mainScriptName)
            }
        }
    }

    func testHookMainScriptCannotEscapeAddonDirectory() throws {
        let directory = try makeDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let root = directory.appendingPathComponent("addon")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("outside.lua")
        try Data("return {}".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.lua"), withDestinationURL: outside)

        for name in ["../outside.lua", outside.path, "link.lua"] {
            XCTAssertThrowsError(try Validator.validateHookScript(mainScriptName: name, directory: root)) { error in
                guard case let ValidatorError.invalidMainScriptName(rejectedName) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(rejectedName, name)
            }
        }
    }

    func testWorkshopUploaderRejectsHooksBeforeDownloadingOrRunningSteamcmd() async throws {
        let addon = try JSONDecoder().decode(WorkshopAddonRecord.self, from: Data(
            """
            {
                "cloudKitIdentifier": "hook",
                "item": {"url": "https://example.invalid/hook.zip", "size": 0, "fileChecksum": ""},
                "name": "Hook",
                "description": "Hook description",
                "type": "hook"
            }
            """.utf8))
        try await withHTTPClient { httpClient in
            let uploader = WorkshopUploader(
                appID: "test",
                steamcmd: SteamCmdRunner(steamcmdPath: URL(fileURLWithPath: "/nonexistent/steamcmd"), username: "test"),
                httpClient: httpClient)
            do {
                _ = try await uploader.upload(
                    addon: addon, action: .create, priorState: nil,
                    contentChecksum: "", previewChecksum: nil, fieldHashes: [:])
                XCTFail("Uploaded a hook to Workshop")
            } catch let SyncError.unsupportedAddonType(value) {
                XCTAssertEqual(value, "hook")
            }
        }
    }

    func testAddonArchivesRejectSymbolicLinksForAllTypes() async throws {
        let directory = try makeDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let original = try makeAddon(in: directory)
        try FileManager.default.removeItem(at: original)
        let source = directory.appendingPathComponent("content")
        try FileManager.default.createSymbolicLink(
            atPath: source.appendingPathComponent("hook.lua").path,
            withDestinationPath: "scripts/Main.lua")
        try FileManager.default.zipItem(at: source, to: original, shouldKeepParent: false)
        let cover = directory.appendingPathComponent("cover.jpg")
        try Data().write(to: cover)

        try await withHTTPClient { httpClient in
            let validator = Validator(httpClient: httpClient)
            for type in ["addon", "script", "hook"] {
                let record = makeRecord(
                    addon: original, cover: cover, type: type, mainScriptName: "scripts/main.lua")
                do {
                    _ = try await validator.validate(record: record)
                    XCTFail("Accepted a symbolic link in a \(type) archive")
                } catch let ValidatorError.symbolicLink(path) {
                    XCTAssertEqual(path, "hook.lua")
                }
            }
        }
    }

    func testSubmissionArchivesRejectFileDirectoryAndDanglingSymbolicLinks() async throws {
        let directory = try makeDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }

        try await withHTTPClient { httpClient in
            let validator = Validator(httpClient: httpClient)
            for (index, target) in ["main.lua", "scripts", "missing.lua"].enumerated() {
                let source = directory.appendingPathComponent("submission-\(index)")
                try FileManager.default.createDirectory(
                    at: source.appendingPathComponent("scripts"), withIntermediateDirectories: true)
                try Data("return {}".utf8).write(to: source.appendingPathComponent("main.lua"))
                try FileManager.default.createSymbolicLink(
                    atPath: source.appendingPathComponent("link").path, withDestinationPath: target)
                let archive = directory.appendingPathComponent("submission-\(index).zip")
                try FileManager.default.zipItem(at: source, to: archive, shouldKeepParent: false)
                do {
                    _ = try await validator.validate(zipFilePath: archive.path)
                    XCTFail("Accepted a symbolic link to \(target)")
                } catch let ValidatorError.symbolicLink(path) {
                    XCTAssertEqual(path, "link")
                }
            }
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeAddon(in directory: URL) throws -> URL {
        let source = directory.appendingPathComponent("content")
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data("return {}".utf8).write(to: source.appendingPathComponent("scripts/main.lua"))
        let archive = directory.appendingPathComponent("addon.zip")
        try FileManager.default.zipItem(at: source, to: archive, shouldKeepParent: false)
        return archive
    }

    private func makeRecord(addon: URL, cover: URL, type: String, mainScriptName: String?) -> CKRecord {
        let record = CKRecord(recordType: "Pending", recordID: CKRecord.ID(recordName: "test"))
        record["title"] = "Hook"
        record["description"] = "Hook description"
        record["category"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: "category"), action: .none)
        record["authors"] = ["Author"]
        record["cover_image"] = CKAsset(fileURL: cover)
        record["addon"] = CKAsset(fileURL: addon)
        record["type"] = type
        record["main_script_name"] = mainScriptName
        return record
    }
}
