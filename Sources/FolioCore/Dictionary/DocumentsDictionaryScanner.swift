import Foundation

public enum DocumentsDictionaryError: FolioMessageProviding, LocalizedError, Equatable {
    case changingFile, unsafeFile, duplicateNames(String), unpairedResource(String)

    public var message: FolioMessage {
        switch self {
        case .changingFile: FolioMessage("A dictionary file is still changing. Let the copy finish, then scan again.")
        case .unsafeFile: FolioMessage("Only regular dictionary files inside Folio’s Documents folder can be used.")
        case .duplicateNames(let name): FolioMessage("More than one dictionary file is named %@. Give each dictionary a unique filename.", [.text(name)])
        case .unpairedResource(let name): FolioMessage("%@ needs a matching MDX file. Copy both files into Folio’s folder.", [.text(name)])
        }
    }
    public var errorDescription: String? { message.englishDescription }
}

/// File metadata only: scanning never reads an archive into memory or hashes its contents.
struct ArchiveFileStamp: Codable, Equatable, Sendable {
    let filename: String
    let size: UInt64
    let modified: Date
    let inode: UInt64

    static func read(_ url: URL, root: URL) throws -> Self {
        guard url.isFileURL, url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath() == root.resolvingSymlinksInPath(),
              url.resolvingSymlinksInPath().deletingLastPathComponent() == root.resolvingSymlinksInPath() else {
            throw DocumentsDictionaryError.unsafeFile
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { throw DocumentsDictionaryError.unsafeFile }
        return Self(filename: url.lastPathComponent, size: size.uint64Value, modified: modified,
                    inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0)
    }
}

struct DocumentsArchiveSnapshot: Codable, Equatable, Sendable {
    let stem: String
    let mdx: ArchiveFileStamp
    let mdd: ArchiveFileStamp?

    func urls(in root: URL) -> [URL] { [mdx.filename, mdd?.filename].compactMap { $0 }.map { root.appendingPathComponent($0) } }

    func isCurrent(in root: URL) throws -> Bool {
        guard try ArchiveFileStamp.read(root.appendingPathComponent(mdx.filename), root: root) == mdx else { return false }
        if let mdd { return try ArchiveFileStamp.read(root.appendingPathComponent(mdd.filename), root: root) == mdd }
        return true
    }
}

public struct DocumentsDictionaryScanReport: Sendable {
    public var discoveredCount = 0
    public var updatedCount = 0
    public var removedCount = 0
    public var unchangedCount = 0
    public var failures: [FolioMessage] = []
    public var hasChanges: Bool { updatedCount > 0 || removedCount > 0 }
}

/// Owns the app's Documents directory. Parses one pair at a time on DictionaryLibrary's
/// background actor. Requests during a scan share its task and trigger a final metadata pass.
public actor DocumentsDictionaryScanner {
    public let root: URL
    private let library: DictionaryLibrary
    private var scanTask: Task<DocumentsDictionaryScanReport, any Error>?
    private var rescanRequested = false

    public init(root: URL, library: DictionaryLibrary) throws {
        self.root = root.standardizedFileURL
        self.library = library
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func scan() async throws -> DocumentsDictionaryScanReport {
        if let scanTask {
            rescanRequested = true
            return try await scanTask.value
        }
        let task = Task {
            var total = DocumentsDictionaryScanReport()
            repeat {
                rescanRequested = false
                let report = try await performScan()
                total.discoveredCount = report.discoveredCount
                total.updatedCount += report.updatedCount
                total.removedCount += report.removedCount
                total.unchangedCount = report.unchangedCount
                total.failures = report.failures
            } while rescanRequested
            return total
        }
        scanTask = task
        defer { scanTask = nil }
        return try await task.value
    }

    public func removeDictionary(id: String) async throws {
        // Do not delete files out from under an active indexing transaction.
        _ = try await scanTask?.value
        if let snapshot = try await library.documentsSnapshot(sourceID: id) {
            for url in snapshot.urls(in: root) where FileManager.default.fileExists(atPath: url.path) {
                try ArchiveFileAccess.delete(url, root: root)
            }
        }
        try await library.removeSource(id: id)
    }

    private func performScan() async throws -> DocumentsDictionaryScanReport {
        try Task.checkCancellation()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var groups: [String: [URL]] = [:]
        for url in files where ["mdx", "mdd"].contains(url.pathExtension.lowercased()) {
            groups[url.deletingPathExtension().lastPathComponent.lowercased(), default: []].append(url)
        }
        var report = DocumentsDictionaryScanReport()
        var presentStems: Set<String> = []
        for stem in groups.keys.sorted() {
            try Task.checkCancellation()
            let urls = groups[stem] ?? []
            let mdx = urls.filter { $0.pathExtension.lowercased() == "mdx" }
            let mdd = urls.filter { $0.pathExtension.lowercased() == "mdd" }
            if !mdx.isEmpty { presentStems.insert(stem); report.discoveredCount += 1 }
            do {
                guard mdx.count <= 1, mdd.count <= 1 else { throw DocumentsDictionaryError.duplicateNames(stem) }
                guard let dictionary = mdx.first else {
                    throw DocumentsDictionaryError.unpairedResource(mdd.first?.lastPathComponent ?? stem)
                }
                let snapshot = try DocumentsArchiveSnapshot(stem: stem, mdx: ArchiveFileStamp.read(dictionary, root: root),
                    mdd: mdd.first.map { try ArchiveFileStamp.read($0, root: root) })
                if try await library.synchronizeDocumentsArchive(snapshot, root: root) { report.updatedCount += 1 }
                else { report.unchangedCount += 1 }
            } catch is CancellationError { throw CancellationError() }
            catch {
                report.failures.append(FolioMessage("%@ — %@", [.text(mdx.first?.lastPathComponent ?? mdd.first?.lastPathComponent ?? stem),
                    .message(.from(error, fallback: "This dictionary couldn’t be indexed. Check the file and scan again."))]))
            }
        }
        // Only sources previously managed by this scanner are removed. Older imports are retained.
        report.removedCount = try await library.removeMissingDocumentsArchives(presentStems: presentStems, root: root)
        return report
    }
}
