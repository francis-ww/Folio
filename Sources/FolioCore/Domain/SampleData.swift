import Foundation

/// Original sample definitions; no licensed dictionary content is bundled.
public enum SampleData {
    public static let entries: [DictionaryEntry] = [
        .init(id: "sample-serendipity", headword: "serendipity", pronunciation: "/ˌser.ənˈdɪp.ə.ti/", partOfSpeech: "noun",
              summary: "The unexpected discovery of something lovely while looking for something else.",
              example: "Finding that little bookshop was a moment of pure serendipity."),
        .init(id: "sample-ephemeral", headword: "ephemeral", pronunciation: "/ɪˈfem.ər.əl/", partOfSpeech: "adjective",
              summary: "Lasting only a short time; here for a moment, then gone.",
              example: "The garden held the ephemeral beauty of the first snow."),
        .init(id: "sample-resonance", headword: "resonance", pronunciation: "/ˈrez.ən.əns/", partOfSpeech: "noun",
              summary: "A deep, lingering sound, or the feeling that an idea connects with you.",
              example: "Her words had a quiet resonance long after the conversation ended."),
        .init(id: "sample-solace", headword: "solace", pronunciation: "/ˈsɒl.ɪs/", partOfSpeech: "noun",
              summary: "Comfort found in a person, place, or small familiar ritual.",
              example: "He found solace in the rhythm of his morning walks."),
        .init(id: "sample-lucid", headword: "lucid", pronunciation: "/ˈluː.sɪd/", partOfSpeech: "adjective",
              summary: "Clear enough to understand easily, or able to think clearly.",
              example: "She offered a lucid explanation of a difficult idea."),
        .init(id: "sample-liminal", headword: "liminal", pronunciation: "/ˈlɪm.ɪ.nəl/", partOfSpeech: "adjective",
              summary: "At a threshold between one place, time, or state and another.",
              example: "Dawn is a liminal hour, suspended between darkness and light."),
        .init(id: "sample-mellifluous", headword: "mellifluous", pronunciation: "/məˈlɪf.lu.əs/", partOfSpeech: "adjective",
              summary: "Flowing smoothly and pleasantly, especially when describing a voice.",
              example: "A mellifluous voice drifted from the open window."),
        .init(id: "sample-intrepid", headword: "intrepid", pronunciation: "/ɪnˈtrep.ɪd/", partOfSpeech: "adjective",
              summary: "Ready to explore or act despite uncertainty and difficulty.",
              example: "The intrepid hikers followed the trail into the mist.")
    ]

    public static func cards(at date: Date = .now) -> [VocabularyCard] {
        entries.prefix(3).enumerated().map { index, entry in
            VocabularyCard(entry: entry, memory: MemoryState(due: date.addingTimeInterval(Double(-index * 60))))
        }
    }
}
