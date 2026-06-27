//
//  Downloader.swift
//  CelestiaAddonValidator
//
//  Created by Levin Li on 3/1/26.
//

import AsyncRequest
import Foundation

final class Downloader {
    static func download(_ url: URL, httpClient: any RequestClient) async throws -> URL? {
        if url.isFileURL { return url }
        do {
            return try await downloadInternal(url, httpClient: httpClient)
        } catch {
            return nil
        }
    }

    private static func downloadInternal(_ url: URL, httpClient: any RequestClient) async throws -> URL {
        let data = try await AsyncDataRequestHandler.get(url: url.absoluteString, httpClient: httpClient)
        let outputPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        let outputURL = URL(fileURLWithPath: outputPath)
        try data.write(to: outputURL)
        return outputURL
    }
}
