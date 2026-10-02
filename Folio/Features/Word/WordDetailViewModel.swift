import Foundation
import Observation
import AVFoundation
import FolioCore

@MainActor @Observable
final class WordDetailViewModel {
    private(set) var entry: DictionaryEntry
    let requestedHeadword: String
    private(set) var results: [DictionaryLookupResult] = []
    private(set) var failures: [DictionarySourceFailure] = []
    private(set) var isLoading = false
    private(set) var selectedSourceID: String?
    private var request = UUID()
    private(set) var isSaving = false
    var error: FolioMessage?
    private let speaker = AVSpeechSynthesizer()
    let audio = OnlinePronunciationPlayer()

    init(entry: DictionaryEntry) { self.entry = entry; requestedHeadword = entry.headword }

    func resolve(using dictionary: any DictionaryRepository) async {
        let current = UUID()
        request = current
        isLoading = true
        error = nil
        defer { if request == current { isLoading = false } }
        do {
            let report = try await dictionary.lookupAll(requestedHeadword)
            try Task.checkCancellation()
            guard request == current else { return }
            results = report.results
            failures = report.failures
            if let selected = results.first(where: { $0.id == selectedSourceID }) ?? results.first { select(selected.id) }
            else { selectedSourceID = nil }
        } catch is CancellationError {} catch {
            guard request == current else { return }
            self.error = FolioMessage.from(error, fallback: "This word couldn’t be opened or saved. Please try again.")
        }
    }

    func select(_ sourceID: String) {
        guard let result = results.first(where: { $0.id == sourceID }) else { return }
        stopSpeaking()
        selectedSourceID = sourceID
        entry = result.entry
    }

    func save(using services: AppServices) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do { try await services.vocabulary.save(entry.vocabularySnapshot); await services.refreshCards() }
        catch { self.error = FolioMessage.from(error, fallback: "This word couldn’t be opened or saved. Please try again.") }
    }

    func pronounce() {
        audio.stop()
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: entry.headword)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        speaker.speak(utterance)
    }

    func pronounce(_ url: URL) { speaker.stopSpeaking(at: .immediate); audio.play(url) }
    func stopSpeaking() { speaker.stopSpeaking(at: .immediate); audio.stop() }
}
