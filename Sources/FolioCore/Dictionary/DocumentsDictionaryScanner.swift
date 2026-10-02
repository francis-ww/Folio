import Foundation

public enum DocumentsDictionaryError: FolioMessageProviding, LocalizedError, Equatable {
    case changingFile, unsafeFile, duplicateNames(String), unpairedResource(String), unreadableFile(String)

    public var message: FolioMessage {
        switch self {
        case .changingFile: FolioMessage("A dictionary file is still changing. Let the copy finish, then scan again.")
        case .unsafeFile: FolioMessage("Only regular dictionary files inside Folio’s Documents folder can be used.")
        case .duplicateNames(let name): FolioMessage("More than one dictionary file is named %@. Give each dictionary a unique filename.", [.text(name)])
        case .unpairedResource(let name): FolioMessage("%@ needs a matching MDX file. Copy both files into Folio’s folder.", [.text(name)])
        case .unreadableFile(let name): FolioMessage("%@ couldn’t be read. Check the file in Files and refresh dictionaries.", [.text(name)])
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

    public func scan(onChange: @escaping @Sendable () async -> Void = {}) async throws -> DocumentsDictionaryScanReport {
        if let scanTask {
            rescanRequested = true
            return try await scanTask.value
        }
        let task = Task {
            var total = DocumentsDictionaryScanReport()
            repeat {
                rescanRequested = false
                let report = try await performScan(onChange: onChange)
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

    private func performScan(onChange: @Sendable () async -> Void) async throws -> DocumentsDictionaryScanReport {
        try Task.checkCancellation()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let dictionaries = Dictionary(grouping: files.filter { $0.pathExtension.lowercased() == "mdx" },
            by: { $0.deletingPathExtension().lastPathComponent.lowercased() })
        let resources = files.filter { $0.pathExtension.lowercased() == "mdd" }
        let priorSnapshots = try await library.documentsSnapshots()
        var report = DocumentsDictionaryScanReport()
        report.discoveredCount = dictionaries.count
        var updated: Set<String> = []
        var snapshots: [String: DocumentsArchiveSnapshot] = [:]
        var companions: [String: [URL]] = [:]

        func failure(_ url: URL, _ error: any Error) {
            ArchiveDiagnostics.report(filename: url.lastPathComponent, error: error)
            report.failures.append(FolioMessage("%@ — %@", [.text(url.lastPathComponent),
                .message(.from(error, fallback: "Failed to parse dictionary"))]))
        }

        for resource in resources {
            let name = resource.deletingPathExtension().lastPathComponent.lowercased()
            let knownOwnerRemoved = priorSnapshots.contains {
                $0.mdd?.filename.lowercased() == resource.lastPathComponent.lowercased() && dictionaries[$0.stem] == nil
            }
            if let stem = DictionaryFilePairing.match(resourceStem: name, dictionaryStems: Array(dictionaries.keys), allowSingleFallback: !knownOwnerRemoved) {
                companions[stem, default: []].append(resource)
            } else { failure(resource, DocumentsDictionaryError.unpairedResource(resource.lastPathComponent)) }
        }
        // All MDX definitions publish before any MDD work, so audio never gates reading.
        for stem in dictionaries.keys.sorted() {
            try Task.checkCancellation()
            guard let urls = dictionaries[stem], let url = urls.first else { continue }
            do {
                guard urls.count == 1 else { throw DocumentsDictionaryError.duplicateNames(stem) }
                let snapshot = try DocumentsArchiveSnapshot(stem: stem, mdx: ArchiveFileStamp.read(url, root: root), mdd: nil)
                if try await library.synchronizeDocumentsDefinitions(snapshot, root: root) {
                    updated.insert(stem)
                    await onChange()
                }
                snapshots[stem] = snapshot
            } catch is CancellationError { throw CancellationError() }
            catch { failure(url, error) }
        }
        for stem in snapshots.keys.sorted() {
            try Task.checkCancellation()
            guard let definition = snapshots[stem] else { continue }
            let candidates = companions[stem] ?? []
            let exact = candidates.filter { $0.deletingPathExtension().lastPathComponent.lowercased() == stem }
            let chosen = exact.count == 1 ? exact.first : candidates.count == 1 ? candidates.first : nil
            if candidates.count > 1 {
                for url in candidates where url != chosen { failure(url, DocumentsDictionaryError.unpairedResource(url.lastPathComponent)) }
                if chosen == nil { continue }
            }
            let filename = chosen ?? root.appendingPathComponent(definition.mdx.filename)
            do {
                let snapshot = try DocumentsArchiveSnapshot(stem: stem, mdx: definition.mdx,
                    mdd: chosen.map { try ArchiveFileStamp.read($0, root: root) })
                if try await library.synchronizeDocumentsResources(snapshot, root: root) {
                    updated.insert(stem)
                    await onChange()
                }
            } catch is CancellationError { throw CancellationError() }
            catch { failure(filename, error) }
        }
        report.updatedCount = updated.count
        report.unchangedCount = snapshots.count - updated.count
        // A missing/unreadable directory throws before this point and cannot erase indexes.
        report.removedCount = try await library.removeMissingDocumentsArchives(presentStems: Set(dictionaries.keys), root: root)
        if report.removedCount > 0 { await onChange() }
        return report
    }
}
