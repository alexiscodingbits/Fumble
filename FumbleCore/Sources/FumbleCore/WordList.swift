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
}
