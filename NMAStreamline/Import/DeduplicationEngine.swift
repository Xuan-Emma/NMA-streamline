import Foundation

/// Result of deduplication analysis on a pair of citations.
struct DuplicateMatch {
    enum MatchType: String {
        case exactDOI    = "Exact DOI"
        case exactPMID   = "Exact PMID"
        case exactNCT    = "Exact NCT ID"
        case fuzzyTitle  = "Fuzzy Title + Year + Author"
    }

    let primary: Citation
    let duplicate: Citation
    let matchType: MatchType
    let similarity: Double    // 0.0 – 1.0 (1.0 = exact)
}

/// Multi-pass deduplication engine.
/// Pass 1: Exact identifier matching (DOI, PMID, NCT ID).
/// Pass 2: Fuzzy matching using Levenshtein distance on Title + Year + First Author.
actor DeduplicationEngine {

    // MARK: - Configuration

    /// Minimum weighted similarity (0–1) to flag a pair as a potential duplicate.
    /// Default: 0.85. Adjust in Settings to trade precision vs. recall.
    var fuzzyThreshold: Double = 0.85

    /// Run all deduplication passes against a list of citations.
    /// Returns groups of matches. Within each group the first element is the
    /// "primary" record; the rest are candidates for merging/discarding.
    func findDuplicates(in citations: [Citation]) -> [DuplicateMatch] {
        var matches: [DuplicateMatch] = []
        var processedIDs = Set<UUID>()

        // Pass 1: Exact identifier matches
        matches += exactPass(citations, processed: &processedIDs)

        // Pass 2: Fuzzy matches on remaining records
        let remaining = citations.filter { !processedIDs.contains($0.id) }
        matches += fuzzyPass(remaining)

        return matches
    }

    // MARK: - Pass 1: Exact identifier matching

    private func exactPass(_ citations: [Citation], processed: inout Set<UUID>) -> [DuplicateMatch] {
        var matches: [DuplicateMatch] = []

        var byDOI:  [String: Citation] = [:]
        var byPMID: [String: Citation] = [:]
        var byNCT:  [String: Citation] = [:]

        for citation in citations {
            if let doi = normalize(citation.doi), !doi.isEmpty {
                if let existing = byDOI[doi] {
                    matches.append(DuplicateMatch(
                        primary: existing,
                        duplicate: citation,
                        matchType: .exactDOI,
                        similarity: 1.0
                    ))
                    processed.insert(citation.id)
                } else {
                    byDOI[doi] = citation
                }
            }

            if let pmid = normalize(citation.pmid), !pmid.isEmpty {
                if let existing = byPMID[pmid] {
                    if !processed.contains(citation.id) {
                        matches.append(DuplicateMatch(
                            primary: existing,
                            duplicate: citation,
                            matchType: .exactPMID,
                            similarity: 1.0
                        ))
                        processed.insert(citation.id)
                    }
                } else {
                    byPMID[pmid] = citation
                }
            }

            if let nct = normalize(citation.nctID), !nct.isEmpty {
                if let existing = byNCT[nct] {
                    if !processed.contains(citation.id) {
                        matches.append(DuplicateMatch(
                            primary: existing,
                            duplicate: citation,
                            matchType: .exactNCT,
                            similarity: 1.0
                        ))
                        processed.insert(citation.id)
                    }
                } else {
                    byNCT[nct] = citation
                }
            }
        }

        return matches
    }

    // MARK: - Pass 2: Fuzzy matching

    private func fuzzyPass(_ citations: [Citation]) -> [DuplicateMatch] {
        var matches: [DuplicateMatch] = []
        var alreadyMatched = Set<UUID>()

        for i in 0..<citations.count {
            let a = citations[i]
            if alreadyMatched.contains(a.id) { continue }

            for j in (i + 1)..<citations.count {
                let b = citations[j]
                if alreadyMatched.contains(b.id) { continue }

                let similarity = combinedSimilarity(a, b)

                if similarity >= fuzzyThreshold {
                    matches.append(DuplicateMatch(
                        primary: a,
                        duplicate: b,
                        matchType: .fuzzyTitle,
                        similarity: similarity
                    ))
                    alreadyMatched.insert(b.id)
                }
            }
        }

        return matches
    }

    // MARK: - Similarity scoring

    /// Weighted similarity:  60% title, 20% year, 20% first author.
    private func combinedSimilarity(_ a: Citation, _ b: Citation) -> Double {
        let titleSim  = normalizedLevenshtein(normalizeTitle(a.title), normalizeTitle(b.title))

        let yearSim: Double = {
            switch (a.year, b.year) {
            case let (y1?, y2?): return y1 == y2 ? 1.0 : (abs(y1 - y2) == 1 ? 0.5 : 0.0)
            default: return 0.5   // unknown year – don't penalise
            }
        }()

        let authorSim = normalizedLevenshtein(
            normalizeAuthor(a.firstAuthor),
            normalizeAuthor(b.firstAuthor)
        )

        return 0.60 * titleSim + 0.20 * yearSim + 0.20 * authorSim
    }

    // MARK: - Levenshtein distance

    /// Returns similarity in [0, 1] where 1 = identical.
    func normalizedLevenshtein(_ s1: String, _ s2: String) -> Double {
        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        let dist = levenshteinDistance(s1, s2)
        let maxLen = max(s1.count, s2.count)
        return 1.0 - Double(dist) / Double(maxLen)
    }

    func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count, n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
                }
            }
        }
        return dp[m][n]
    }

    // MARK: - Normalisation helpers

    private func normalize(_ s: String?) -> String? {
        s?.trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
    }

    private func normalizeTitle(_ t: String) -> String {
        t.lowercased()
         .components(separatedBy: .punctuationCharacters).joined(separator: " ")
         .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func normalizeAuthor(_ a: String) -> String {
        // Keep only last name for comparison
        a.components(separatedBy: ",").first?
          .trimmingCharacters(in: .whitespaces).lowercased() ?? a.lowercased()
    }
}
