import Foundation
#if canImport(OSLog)
import OSLog
#endif

enum ArchiveDiagnostics {
    static func report(filename: String, error: any Error) {
        let message = FolioMessage.from(error, fallback: "Failed to parse dictionary").englishDescription
        let system = error as NSError
        let detail = "\(filename): \(message) [\(system.domain):\(system.code)]"
        #if canImport(OSLog)
        Logger(subsystem: "app.folio", category: "MDict").error("\(detail, privacy: .public)")
        #else
        print("Folio MDict: \(detail)")
        #endif
    }
}
