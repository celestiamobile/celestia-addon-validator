//
//  Downloader.swift
//  CelestiaAddonValidator
//
//  Created by Levin Li on 3/1/26.
//

import Foundation
import MWRequest

final class Downloader {
    static func download(_ url: URL) async throws -> URL? {
        if url.isFileURL { return url }
        do {
            return try await downloadInternal(url)
        } catch {
            return nil
        }
    }

    private static func downloadInternal(_ url: URL) async throws -> URL {
        let data = try await AsyncDataRequestHandler.get(url: url.absoluteString)
        let outputPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        let outputURL = URL(fileURLWithPath: outputPath)
        try data.write(to: outputURL)
        return outputURL
    }
}
