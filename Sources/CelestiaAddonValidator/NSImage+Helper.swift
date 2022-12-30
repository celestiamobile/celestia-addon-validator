import AppKit

extension NSImage {
    func resized(to size: NSSize) -> NSImage? {
        let currentSize = self.size
        let ratio = max(size.width / currentSize.width, size.height / currentSize.height)
        let newSize = NSSize(width: ratio * currentSize.width, height: ratio * currentSize.height)
        if let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(newSize.width), pixelsHigh: Int(newSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) {
            bitmapRep.size = newSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            draw(in: NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height), from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()

            let resizedImage = NSImage(size: newSize)
            resizedImage.addRepresentation(bitmapRep)
            return resizedImage
        }
        return nil
    }

    func save(to url: URL, fileType: NSBitmapImageRep.FileType = .jpeg) -> Bool {
        guard let tiffRepresentation = tiffRepresentation else { return false }
        do {
            try NSBitmapImageRep(data: tiffRepresentation)?
                .representation(using: fileType, properties: [:])?
                .write(to: url)
            return true
        } catch {
            return false
        }
    }
}
