import Foundation

/// Documents are owned sandbox paths: no security-scoped bookmarks or access calls.
/// Apple file coordination lets Files finish coordinated writes before indexing starts.
enum ArchiveFileAccess {
    static func read<T>(_ urls: [URL], perform: () throws -> T) throws -> T {
        #if canImport(Darwin)
        return try withoutActuallyEscaping(perform) { operation in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var result: Result<T, any Error>?
            coordinator.prepare(forReadingItemsAt: urls, options: [], writingItemsAt: [], options: [], error: &coordinationError) { finish in
                defer { finish() }
                // prepare batches presenter notifications; individual coordinated reads
                // are still required to hold the locks for the entire transaction.
                result = Result { try coordinateReads(urls[...], coordinator: coordinator, perform: operation) }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw DocumentsDictionaryError.changingFile }
            return try result.get()
        }
        #else
        return try perform()
        #endif
    }

    #if canImport(Darwin)
    private static func coordinateReads<T>(_ urls: ArraySlice<URL>, coordinator: NSFileCoordinator, perform: () throws -> T) throws -> T {
        guard let url = urls.first else { return try perform() }
        var coordinationError: NSError?
        var result: Result<T, any Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
            result = Result {
                guard coordinatedURL.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
                    throw DocumentsDictionaryError.changingFile
                }
                return try coordinateReads(urls.dropFirst(), coordinator: coordinator, perform: perform)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw DocumentsDictionaryError.changingFile }
        return try result.get()
    }
    #endif

    static func delete(_ url: URL, root: URL) throws {
        #if canImport(Darwin)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Void, any Error>?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            result = Result {
                _ = try ArchiveFileStamp.read(coordinatedURL, root: root)
                try FileManager.default.removeItem(at: coordinatedURL)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw DocumentsDictionaryError.changingFile }
        try result.get()
        #else
        _ = try ArchiveFileStamp.read(url, root: root)
        try FileManager.default.removeItem(at: url)
        #endif
    }
}
