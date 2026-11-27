import Foundation
import OpenCloudKit
import XCTest
import ZIPFoundation

@testable import CelestiaAddonValidator

final class ResourceLinkTests: XCTestCase {
    func testRejectsDirectResourceURLsInTextAndHTML() throws {
        for text in [
            "https://celestia.mobi/resources/item/ADDON",
            "https://celestia.mobi/resources/guide/GUIDE",
            #"See <a href="https://celestia.mobi/resources/item?item=ADDON">this add-on</a>."#,
            #"See <a href='https://celestia.mobi/resources/guide?guide=GUIDE'>this guide</a>."#,
            "\u{53C2}\u{7167}: https://celestia.mobi/resources/item/ADDON?lang=ja#details",
            "HTTPS://CELESTIA.MOBI:443/resources/GUIDE/GUIDE",
            "http://celestia.mobi/resources/item/ADDON",
            "See (https://celestia.mobi/resources/guide/GUIDE).",
            "https://user@celestia.mobi/resources/item/ADDON",
            "https://celestia.mobi/resources/%67uide/GUIDE",
            "https://example.com followed by https://celestia.mobi/resources/item/ADDON",
        ] {
            XCTAssertThrowsError(
                try Validator.validateResourceLinks(in: text, fieldName: "description")
            ) { error in
                guard case let ValidatorError.directResourceURL(_, fieldName, replacement) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(fieldName, "description")
                XCTAssertTrue(replacement.hasPrefix("celaddon://") || replacement.hasPrefix("celguide://"))
                XCTAssertTrue(error.localizedDescription.contains("description"))
            }
        }
    }

    func testAllowsNativeURLsAndUnrelatedWebURLs() throws {
        for text in [
            #"See <a href="celaddon://item?item=ADDON">this add-on</a>."#,
            #"See <a href="celguide://guide?guide=GUIDE">this guide</a>."#,
            "https://celestia.mobi/resources/category?category=CATEGORY",
            "https://celestia.mobi/resources/items",
            "https://celestia.mobi/resources/guidelines",
            "https://celestia.mobi.example.com/resources/item/ADDON",
            "https://example.com/resources/guide/GUIDE",
        ] {
            XCTAssertNoThrow(try Validator.validateResourceLinks(in: text, fieldName: "description"))
        }
    }

    func testCloudKitSubmissionsRejectStringAndListFieldsBeforeDownloading() async throws {
        try await withHTTPClient { httpClient in
            let validator = Validator(httpClient: httpClient)
            for field in [
                "description", "original_url", "rich_description_base",
                "rich_description_notes", "rich_description_cover_image_caption",
                "rich_description_detail_image_captions",
                "rich_description_additional_leading", "rich_description_additional_trailing",
            ] {
                let record = CKRecord(recordType: "Pending", recordID: CKRecord.ID(recordName: "test"))
                let text = #"See <a href="https://celestia.mobi/resources/guide/GUIDE">this guide</a>."#
                if field == "rich_description_notes" || field == "rich_description_detail_image_captions" {
                    record[field] = ["Unrelated text", text]
                } else {
                    record[field] = text
                }
                do {
                    _ = try await validator.validate(record: record)
                    XCTFail("Accepted a direct resource link in \(field)")
                } catch let ValidatorError.directResourceURL(_, fieldName, replacement) {
                    XCTAssertEqual(fieldName, field)
                    XCTAssertEqual(replacement, "celguide://guide?guide=<ID>")
                }
            }
        }
    }

    func testZIPSubmissionsRejectPlainTextAndRichDescriptionFiles() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { XCTAssertNoThrow(try fm.removeItem(at: directory)) }

        try await withHTTPClient { httpClient in
            let validator = Validator(httpClient: httpClient)
            for (index, field) in [
                "description.txt", "rich_description/base.txt", "rich_description/notes.txt",
                "rich_description/cover_image.txt", "rich_description/additional_leading.html",
                "rich_description/additional_trailing.html",
            ].enumerated() {
                let source = directory.appendingPathComponent("submission-\(index)")
                try fm.createDirectory(
                    at: source.appendingPathComponent("rich_description"),
                    withIntermediateDirectories: true)
                try Data("Plain description".utf8).write(to: source.appendingPathComponent("description.txt"))
                try Data("Rich description".utf8).write(to: source.appendingPathComponent("rich_description/base.txt"))
                try Data().write(to: source.appendingPathComponent("rich_description/cover_image.jpg"))
                let text = #"See <a href="https://celestia.mobi/resources/item/ADDON">this add-on</a>."#
                try Data(text.utf8).write(to: source.appendingPathComponent(field))
                let archive = directory.appendingPathComponent("submission-\(index).zip")
                try fm.zipItem(at: source, to: archive, shouldKeepParent: false)
                do {
                    _ = try await validator.validate(zipFilePath: archive.path)
                    XCTFail("Accepted a direct resource link in \(field)")
                } catch let ValidatorError.directResourceURL(_, fieldName, replacement) {
                    XCTAssertEqual(fieldName, (field as NSString).lastPathComponent)
                    XCTAssertEqual(replacement, "celaddon://item?item=<ID>")
                }
            }
        }
    }
}
