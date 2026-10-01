import Foundation

/// A pool of common English words for drill generation.
///
/// Deliberately real words, not keybr-style pseudo-random letter soup — the whole premise of
/// Fumble is that you should practise the things you actually type. The generator weights this
/// pool toward your weak keys and transitions (see `DrillGenerator`), so a drill is real words,
/// skewed toward the ones that exercise your specific weaknesses.
///
/// Kept lowercase and apostrophe-free-ish; a few contractions are included because they carry
/// awkward transitions worth drilling.
public enum WordList {
    public static let common: [String] = [
        "the", "and", "for", "you", "that", "with", "this", "have", "from", "they",
        "will", "would", "there", "their", "what", "about", "which", "when", "make",
        "like", "time", "just", "know", "take", "into", "year", "your", "good", "some",
        "them", "other", "than", "then", "look", "only", "come", "over", "think", "also",
        "back", "after", "work", "first", "well", "even", "want", "because", "these",
        "give", "most", "very", "through", "where", "much", "before", "right", "should",
        "people", "little", "world", "still", "between", "under", "while", "might",
        "never", "again", "another", "around", "however", "against", "during", "without",
        "place", "great", "small", "large", "different", "following", "public", "point",
        "system", "program", "question", "government", "company", "number", "group",
        "problem", "important", "several", "example", "himself", "against", "nothing",
        "something", "everything", "together", "although", "already", "always", "become",
        "change", "control", "develop", "family", "figure", "friend", "happen", "letter",
        "listen", "matter", "member", "moment", "money", "month", "morning", "mother",
        "nature", "office", "order", "other", "paper", "parent", "person", "picture",
        "power", "problem", "reason", "result", "school", "second", "series", "service",
        "simple", "single", "social", "special", "student", "study", "subject", "summer",
        "table", "teacher", "themselves", "thought", "though", "toward", "trouble",
        "understand", "water", "whether", "window", "within", "writer", "yellow",
        "quick", "brown", "jumps", "lazy", "zebra", "quartz", "phoenix", "rhythm",
        "syntax", "vector", "matrix", "buffer", "kernel", "thread", "socket", "server",
        "client", "object", "method", "return", "import", "export", "struct", "public",
        "static", "value", "index", "array", "string", "double", "boolean", "switch",
        "extend", "filter", "reduce", "append", "prefix", "suffix", "encode", "decode",
        "commit", "branch", "merge", "rebase", "config", "deploy", "verify", "assert",
        "wizard", "oxygen", "jacket", "vivid", "amazing", "buzzing", "fabric", "galaxy",
        "hazard", "injury", "jockey", "kayak", "liquid", "mimic", "nozzle", "puzzle",
        "query", "quirk", "vortex", "wobble", "yacht", "zephyr", "acknowledge", "beyond",
    ]

    /// Regional spelling for the English word pool. Persisted by raw value.
    public enum Spelling: String, CaseIterable, Sendable, Identifiable {
        case us, uk
        public var id: String { rawValue }
        public var title: String { self == .us ? "US English" : "UK English" }
    }

    /// The large common-English pool for the adaptive trainer's natural-words blending and the
    /// weak-spot drills. ~11k words from SCOWL (see `WordListData`) plus hand-picked q/z/x/j
    /// words, so rare-letter lessons find real words instead of pseudo-word soup.
    ///
    /// Strictly lowercase a–z — no apostrophes or accents — because the trainer filters it
    /// against the unlocked-letter set character by character, and a stray apostrophe would
    /// silently exclude a word forever. Regional spellings are split so a UK user never gets
    /// "color" and a US user never gets "colour": each variant is core + its own spellings.
    public static func english(spelling: Spelling) -> [String] {
        switch spelling {
        case .us: return englishUS
        case .uk: return englishUK
        }
    }

    /// Default pool where no preference is known.
    public static var english: [String] { englishUS }

    private static let core = split(WordListData.core)
    private static let englishUS = core + split(WordListData.us)
    private static let englishUK = core + split(WordListData.uk)

    private static func split(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
