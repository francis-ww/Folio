import Foundation
import Observation
import AVFoundation
import FolioCore

@MainActor @Observable
final class WordDetailViewModel {
    private(set) var entry: DictionaryEntry
    private(set) var isSaving = false
    var error: String?
    private let speaker = AVSpeechSynthesizer()

    init(entry: DictionaryEntry) { self.entry = entry }

    func resolve(using dictionary: any DictionaryRepository) async {
        guard entry.html.hasPrefix("@@@LINK=") else { return }
        do {
            guard let resolved = try await dictionary.lookup(entry.headword, dictionaryID: entry.dictionaryID) else {
                error = "The linked definition could not be found."
                return
            }
            entry = resolved
        } catch { self.error = error.localizedDescription }
    }

    func save(using services: AppServices) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do { try await services.vocabulary.save(entry); await services.refreshCards() }
        catch { self.error = error.localizedDescription }
    }

    func pronounce() {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: entry.headword)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        speaker.speak(utterance)
    }

    func stopSpeaking() { speaker.stopSpeaking(at: .immediate) }
}
