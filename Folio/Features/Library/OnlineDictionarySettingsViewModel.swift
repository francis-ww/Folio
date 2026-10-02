import Foundation
import Observation
import FolioCore

@MainActor @Observable
final class OnlineDictionarySettingsViewModel {
    var appKey = ""
    var appSecret = ""
    var api: YoudaoAPI = .translation
    private(set) var isConfigured = false
    private(set) var isWorking = false
    private(set) var status: FolioMessage?
    var error: FolioMessage?

    func load(_ store: any OnlineDictionarySettingsStore) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let value = try await store.configuration()
            appKey = value.credentials?.appKey ?? ""
            appSecret = value.credentials?.appSecret ?? ""
            api = value.api
            isConfigured = value.credentials?.isValid == true
        } catch { self.error = FolioMessage.from(error, fallback: "Your online dictionary settings couldn’t be updated. Please try again.") }
    }

    func save(_ services: AppServices) async {
        guard !isWorking else { return }
        let key = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !secret.isEmpty else { error = FolioMessage("Enter both your App Key and App Secret, or remove the saved keys."); return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.onlineSettings.update(.init(credentials: .init(appKey: key, appSecret: secret), api: api))
            appKey = key; appSecret = secret; isConfigured = true
            status = FolioMessage("Keys saved securely on this device.")
            services.libraryRevision += 1
        } catch { self.error = FolioMessage.from(error, fallback: "Your online dictionary settings couldn’t be updated. Please try again.") }
    }

    func remove(_ services: AppServices) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.onlineSettings.update(.init())
            appKey = ""; appSecret = ""; api = .translation; isConfigured = false
            status = FolioMessage("Saved keys removed.")
            services.libraryRevision += 1
        } catch { self.error = FolioMessage.from(error, fallback: "Your online dictionary settings couldn’t be updated. Please try again.") }
    }
}
