import Foundation

actor LocalEvidenceStore {
    private struct Manifest: Codable {
        let schemaVersion: Int
        var assets: [CapturedEvidence]
    }

    private let rootURL: URL
    private let assetsURL: URL
    private let manifestURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = rootURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "MemoedEvidence", directoryHint: .isDirectory)
        self.rootURL = baseURL
        self.assetsURL = baseURL.appending(path: "Assets", directoryHint: .isDirectory)
        self.manifestURL = baseURL.appending(path: "manifest.json", directoryHint: .notDirectory)
    }

    func loadAssets() throws -> [CapturedEvidence] {
        try prepareDirectories()
        return try readManifest().assets.sorted { $0.capturedAt > $1.capturedAt }
    }

    func evidence(id: UUID) throws -> CapturedEvidence? {
        try prepareDirectories()
        return try readManifest().assets.first { $0.id == id }
    }

    func importData(
        _ data: Data,
        kind: CapturedEvidenceKind,
        fileExtension: String,
        originalFilename: String,
        mediaTypeIdentifier: String,
        capturedAt: Date = .now,
        assertedAt: Date? = nil,
        sourceGroupID: String? = nil
    ) throws -> CapturedEvidence {
        try prepareDirectories()
        let id = UUID()
        let safeExtension = Self.safeFileExtension(fileExtension, fallback: kind == .photo ? "jpg" : "m4a")
        let filename = "\(id.uuidString).\(safeExtension)"
        let destination = assetsURL.appending(path: filename, directoryHint: .notDirectory)
        try data.write(to: destination, options: [.atomic])
        try protectItem(at: destination)

        let asset = CapturedEvidence(
            id: id,
            kind: kind,
            capturedAt: capturedAt,
            assertedAt: assertedAt,
            sourceGroupID: sourceGroupID,
            originalFilename: originalFilename,
            relativePath: filename,
            mediaTypeIdentifier: mediaTypeIdentifier,
            state: .queued,
            ocrBlocks: [],
            transcriptSpans: [],
            failureCode: nil
        )
        var manifest = try readManifest()
        manifest.assets.append(asset)
        try writeManifest(manifest)
        return asset
    }

    func importFile(
        at sourceURL: URL,
        kind: CapturedEvidenceKind,
        originalFilename: String,
        mediaTypeIdentifier: String,
        capturedAt: Date = .now,
        assertedAt: Date? = nil,
        sourceGroupID: String? = nil
    ) throws -> CapturedEvidence {
        let data = try Data(contentsOf: sourceURL)
        return try importData(
            data,
            kind: kind,
            fileExtension: sourceURL.pathExtension,
            originalFilename: originalFilename,
            mediaTypeIdentifier: mediaTypeIdentifier,
            capturedAt: capturedAt,
            assertedAt: assertedAt,
            sourceGroupID: sourceGroupID
        )
    }

    func update(_ asset: CapturedEvidence) throws {
        try prepareDirectories()
        var manifest = try readManifest()
        guard let index = manifest.assets.firstIndex(where: { $0.id == asset.id }) else {
            throw StoreError.assetNotFound
        }
        manifest.assets[index] = asset
        try writeManifest(manifest)
    }

    func data(for asset: CapturedEvidence) throws -> Data {
        try Data(contentsOf: assetURL(for: asset))
    }

    func assetURL(for asset: CapturedEvidence) -> URL {
        assetsURL.appending(path: asset.relativePath, directoryHint: .notDirectory)
    }

    func delete(_ asset: CapturedEvidence) throws {
        try prepareDirectories()
        var manifest = try readManifest()
        manifest.assets.removeAll { $0.id == asset.id }
        let fileURL = assetURL(for: asset)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try writeManifest(manifest)
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try protectItem(at: rootURL)
        try protectItem(at: assetsURL)
    }

    private func readManifest() throws -> Manifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return Manifest(schemaVersion: 1, assets: [])
        }
        let data = try Data(contentsOf: manifestURL)
        return try Self.decoder.decode(Manifest.self, from: data)
    }

    private func writeManifest(_ manifest: Manifest) throws {
        let data = try Self.encoder.encode(manifest)
        try data.write(to: manifestURL, options: [.atomic])
        try protectItem(at: manifestURL)
    }

    private func protectItem(at url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private static func safeFileExtension(_ value: String, fallback: String) -> String {
        let candidate = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return candidate.isEmpty ? fallback : String(candidate.prefix(8))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    enum StoreError: Error {
        case assetNotFound
    }
}
