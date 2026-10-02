import Foundation
import GRDB

private struct PendingDictionaryIndex {
    let id: String
    let stem: String
    var title: String
    var definition: MDictIndexDatabase?
    var resource: MDictIndexDatabase?
    var entryCount = 0
    var resourceCount = 0
}

private struct DictionaryIndexPublication: Sendable {
    let id: String
    let stem: String
    let title: String
    let definitionFile: String?
    let resourceFile: String?
    let entryCount: Int
    let resourceCount: Int
}

extension DictionaryLibrary {
    /// Staging transactions contain at most 1,000 keywords/definitions, then yield.
    /// Publication only swaps small source metadata; failed selected batches retain old indexes.
    public func importArchives(_ urls: [URL]) async throws {
        try await importArchives(urls, preservingResources: false, stemOverride: nil, onPublish: nil)
    }

    func importArchives(_ urls: [URL], preservingResources: Bool, stemOverride: String?,
                        onPublish: (@Sendable (Database) throws -> Void)?) async throws {
        try Task.checkCancellation()
        let previous = importTask
        let request = UUID()
        importRequest = request
        let task = Task {
            _ = try? await previous?.value
            try Task.checkCancellation()
            try await performImport(urls, preservingResources: preservingResources, stemOverride: stemOverride, onPublish: onPublish)
        }
        importTask = task
        defer { if importRequest == request { importTask = nil } }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func performImport(_ urls: [URL], preservingResources: Bool, stemOverride: String?,
                               onPublish: (@Sendable (Database) throws -> Void)?) async throws {
        let existing = try sources().filter { !$0.isSample }
        var pending: [String: PendingDictionaryIndex] = [:]
        var stagedFiles: [String] = []
        var identities: [MDictArchiveIdentity] = []
        var inspecting: URL?
        var published = false
        defer { if !published { removeIndexFiles(stagedFiles) } }
        let ordered = urls.sorted { $0.pathExtension.lowercased() == "mdx" && $1.pathExtension.lowercased() != "mdx" }
        do {
            for url in ordered {
                inspecting = url
                try Task.checkCancellation()
                let ext = url.pathExtension.lowercased()
                guard ext == "mdx" || ext == "mdd" else { throw MDictError.unsupported("the .\(ext) file type") }
                let identity = try MDictArchiveIdentity.capture(url)
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                let stem: String
                if let stemOverride { stem = stemOverride }
                else if ext == "mdx" { stem = name }
                else {
                    let candidates = Array(Set(existing.map(\.filename) + Array(pending.keys)))
                    guard let match = DictionaryFilePairing.match(resourceStem: name, dictionaryStems: candidates) else { throw MDictError.missingDictionary }
                    stem = match
                }
                let source = existing.first { $0.filename == stem }
                var target = pending[stem] ?? PendingDictionaryIndex(id: source?.id ?? UUID().uuidString.lowercased(), stem: stem, title: source?.title ?? stem)
                let filename = UUID().uuidString.lowercased() + ".sqlite"
                let index = try MDictIndexDatabase(url: indexRoot.appendingPathComponent(filename))
                stagedFiles.append(filename)
                // Resource keys/blocks go straight into their final staged SQLite file.
                let reader = try ArchiveFileAccess.read([url]) { try MDictReader(url: url, resourceArchive: ext == "mdd", index: ext == "mdd" ? index : nil) }
                var more = true
                while more {
                    more = try archiveAutoreleasePool {
                        try ArchiveFileAccess.read([url]) { try identity.checkCurrent(); return try reader.indexNextBatch() }
                    }
                    await Task.yield()
                }
                if ext == "mdx" {
                    var number = 0
                    more = true
                    while more {
                        more = try archiveAutoreleasePool {
                            try ArchiveFileAccess.read([url]) {
                                try identity.checkCurrent()
                                return try index.write { db in
                                    try reader.readRecordBatch { headword, data in
                                        guard let html = String(data: data, encoding: reader.header.encoding) else { throw MDictError.malformed("definition encoding") }
                                        let cleaned = html.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
                                        let entry = DictionaryEntry(id: "\(target.id):\(number)", dictionaryID: target.id, headword: headword,
                                            summary: Self.summary(cleaned), html: cleaned)
                                        try db.execute(sql: "INSERT INTO entries(id, headword, payload) VALUES (?, ?, ?)",
                                            arguments: [entry.id, headword, try JSONEncoder().encode(entry)])
                                        try db.execute(sql: "INSERT INTO entries_fts(rowid, headword) VALUES (?, ?)", arguments: [db.lastInsertedRowID, headword])
                                        number += 1
                                    }
                                }
                            }
                        }
                        await Task.yield()
                    }
                    target.definition = index; target.entryCount = number; target.title = reader.header.title
                } else {
                    try index.write { db in
                        try db.execute(sql: "INSERT OR REPLACE INTO metadata(name, value) VALUES ('archive', ?)", arguments: [try JSONEncoder().encode(identity)])
                    }
                    target.resource = index
                    target.resourceCount = try index.read { db in try Int.fetchOne(db, sql: "SELECT count(DISTINCT text) FROM keys") ?? 0 }
                }
                try ArchiveFileAccess.read([url]) { try identity.checkCurrent() }
                identities.append(identity)
                pending[stem] = target
            }
        } catch {
            if !(error is CancellationError) { ArchiveDiagnostics.report(filename: inspecting?.lastPathComponent ?? "", error: error) }
            throw error
        }
        try Task.checkCancellation()
        let publications = pending.values.map {
            DictionaryIndexPublication(id: $0.id, stem: $0.stem, title: $0.title, definitionFile: $0.definition?.url.lastPathComponent,
                resourceFile: $0.resource?.url.lastPathComponent, entryCount: $0.entryCount, resourceCount: $0.resourceCount)
        }
        var replacedFiles: [String] = []
        try ArchiveFileAccess.read(urls) {
            for identity in identities { try identity.checkCurrent() }
            try withLibraryWrite { db in
                for target in publications {
                    let old = try Row.fetchOne(db, sql: "SELECT * FROM sources WHERE id = ?", arguments: [target.id])
                    if old == nil {
                        try db.execute(sql: "INSERT INTO sources(id, title, filename) VALUES (?, ?, ?)", arguments: [target.id, target.title, target.stem])
                    }
                    if let definition = target.definitionFile {
                        if let oldFile: String = old?["definitionIndex"] { replacedFiles.append(oldFile) }
                        try db.execute(sql: "DELETE FROM entries WHERE dictionaryID = ?", arguments: [target.id])
                        try db.execute(sql: "UPDATE sources SET title = ?, definitionIndex = ?, indexedEntries = ? WHERE id = ?",
                            arguments: [target.title, definition, target.entryCount, target.id])
                    }
                    if let resource = target.resourceFile {
                        if let oldFile: String = old?["resourceIndex"] { replacedFiles.append(oldFile) }
                        try db.execute(sql: "DELETE FROM resources WHERE dictionaryID = ?", arguments: [target.id])
                        try db.execute(sql: "UPDATE sources SET resourceIndex = ?, indexedResources = ? WHERE id = ?",
                            arguments: [resource, target.resourceCount, target.id])
                    } else if target.definitionFile != nil && !preservingResources {
                        if let oldFile: String = old?["resourceIndex"] { replacedFiles.append(oldFile) }
                        try db.execute(sql: "DELETE FROM resources WHERE dictionaryID = ?", arguments: [target.id])
                        try db.execute(sql: "UPDATE sources SET resourceIndex = NULL, indexedResources = 0 WHERE id = ?", arguments: [target.id])
                    }
                }
                try onPublish?(db)
                try Task.checkCancellation()
            }
        }
        published = true
        for target in pending.values {
            if let definition = target.definition { indexCache[definition.url.lastPathComponent] = definition }
            if let resource = target.resource { indexCache[resource.url.lastPathComponent] = resource }
        }
        removeIndexFiles(replacedFiles)
    }
}
