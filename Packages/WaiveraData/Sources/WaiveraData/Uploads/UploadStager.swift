import Foundation

#if canImport(ImageIO)
    import ImageIO
    import UniformTypeIdentifiers
#endif

/// A picked file, checked and copied into app storage, ready to send.
struct StagedUpload: Sendable, Hashable {
    var path: String
    var fileName: String
    var mimeType: String
    var sizeBytes: Int64
}

/// Reads a picked file, checks it with `UploadChecks` and copies (or re-encodes) it for
/// sending (Android `AndroidUploadStager`). Throws `UploadRefused` with the app's reason.
struct UploadStager: Sendable {
    static let fallbackName = "upload"

    func stage(_ picked: PickedFile, into directory: URL) throws -> StagedUpload {
        let (data, name) = try read(picked)
        do {
            return try stage(data, name: name, into: directory)
        } catch let refused as UploadRefused {
            throw UploadRefused(refused.problem, pickedName: name)
        } catch {
            throw UploadRefused(.unreadable, pickedName: name)
        }
    }

    private func stage(_ data: Data, name: String?, into directory: URL) throws -> StagedUpload {
        let type = UploadChecks.sniff(data)
        let output: Data
        let sent: Sniffed
        switch UploadChecks.plan(type, size: Int64(data.count)) {
        case .refuse(let problem):
            throw UploadRefused(problem)
        case .send:
            output = data
            sent = type
        case .reencode:
            guard let jpeg = PhotoReencoder.jpeg(data, maxBytes: UploadChecks.maxBytes) else {
                throw UploadRefused(type == .otherImage ? .unsupported : .tooLarge)
            }
            output = jpeg
            sent = .jpeg
        }
        try UploadFiles.prepare(directory)
        let target = directory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        try UploadFiles.write(output, to: target)
        return StagedUpload(
            path: target.path,
            fileName: UploadChecks.fileName(name, type: sent, fallback: Self.fallbackName),
            mimeType: sent.mimeType,
            sizeBytes: Int64(output.count)
        )
    }

    private func read(_ picked: PickedFile) throws -> (Data, String?) {
        switch picked {
        case .data(let data, let name):
            guard Int64(data.count) <= UploadChecks.maxReadBytes else {
                throw UploadRefused(.tooLarge, pickedName: name)
            }
            return (data, name)
        case .url(let url):
            let name = url.lastPathComponent
            #if os(iOS) || os(macOS)
                // Files from the document picker are outside the sandbox until access starts.
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            #endif
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
            if let size, size > UploadChecks.maxReadBytes { throw UploadRefused(.tooLarge, pickedName: name) }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                throw UploadRefused(.unreadable, pickedName: name)
            }
            guard Int64(data.count) <= UploadChecks.maxReadBytes else {
                throw UploadRefused(.tooLarge, pickedName: name)
            }
            return (data, name)
        }
    }
}

/// Where staged files live: Application Support, out of backups, readable after first unlock so a
/// queued file can still go up when the phone locks.
enum UploadFiles {
    static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )
        #endif
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    static func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
            try data.write(to: url, options: .atomic)
        #endif
    }
}

/// Re-encodes a photo as a JPG under the limit: at most 4096 pixels a side, turned upright, with
/// its metadata (place, camera) left behind, stepping the quality down as Android does.
enum PhotoReencoder {
    static let maxSide = 4_096
    static let qualities: [Double] = [0.88, 0.78, 0.68, 0.58]

    static func jpeg(_ data: Data, maxBytes: Int64) -> Data? {
        #if canImport(ImageIO)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            for quality in qualities {
                let output = NSMutableData()
                guard
                    let destination = CGImageDestinationCreateWithData(
                        output as CFMutableData,
                        UTType.jpeg.identifier as CFString,
                        1,
                        nil
                    )
                else { return nil }
                let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { return nil }
                if Int64(output.length) <= maxBytes { return output as Data }
            }
            return nil
        #else
            return nil
        #endif
    }
}
