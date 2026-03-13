import Foundation

/// Parses RIS (Research Information Systems) formatted bibliography files.
/// Supports three citation formats:
///   - Standard RIS (e.g. `TI  - Some Title`)
///   - EndNote Tagged (e.g. `%T Some Title`)
///   - Embase/Scopus RIS with non-standard tags (e.g. `T1  - Some Title`, `N2  - Abstract`)
struct RISParser {

    // Matches tag lines from all three supported formats.
    // Capture groups:
    //   1 – character(s) after `%` for EndNote-style tags  (e.g. `T` in `%T Some Title`)
    //   2 – tag name for RIS/Embase-style tags              (e.g. `TI` in `TI  - Some Title`)
    //   3 – the field value that follows the tag
    private static let tagRegex = try! NSRegularExpression(
        pattern: #"^(?:%([A-Z0-9@%]{1,2})\s+|([A-Z0-9]{2,4})\s*-\s*)(.*)$"#
    )

    /// Maps variant tags from all supported formats to a single canonical internal key,
    /// so that buildCitation only needs to look up one key per field.
    private static let tagNormalizationMap: [String: String] = [
        // Title variants
        "%T": "TI", "T1": "TI", "CT": "TI", "BT": "TI",
        // Author variants
        "%A": "AU", "A1": "AU",
        // Year variants
        "%D": "PY", "Y1": "PY",
        // Journal variants
        "%J": "JO", "T2": "JO", "JF": "JO",
        // Abstract variants
        "%X": "AB", "N2": "AB",
        // Volume variants
        "%V": "VL",
        // Issue variants
        "%N": "IS",
        // DOI variants (DI is used by Web of Science / Embase exports)
        "DI": "DO",
        // Source/DB provider tag
        "DP": "DB",
        // Record-type tag: %0 (EndNote) normalised alongside TY (RIS)
        "%0": "TY",
    ]

    // ClinicalTrials.gov identifiers are always "NCT" followed by exactly 8 digits.
    private static let nctIDRegex = try! NSRegularExpression(pattern: #"NCT\d{8}"#)

    /// Parse RIS content string into an array of Citation objects.
    static func parse(_ content: String) -> [Citation] {
        var citations: [Citation] = []
        let lines = content.components(separatedBy: .newlines)

        var currentRecord: [String: [String]] = [:]
        var lastTag: String? = nil

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // End-of-record marker
            if line.hasPrefix("ER  -") || line == "ER" {
                if !currentRecord.isEmpty, let citation = buildCitation(from: currentRecord) {
                    citations.append(citation)
                }
                currentRecord = [:]
                lastTag = nil
                continue
            }

            // Try to match a tag line
            let nsRange = NSRange(line.startIndex..., in: line)
            if let match = tagRegex.firstMatch(in: line, range: nsRange) {
                // Group 1: character(s) after `%` in EndNote style
                // Group 2: tag name in RIS style
                // Group 3: value
                let endnoteTag: String? = Range(match.range(at: 1), in: line).map { "%" + line[$0] }
                let risTag: String?     = Range(match.range(at: 2), in: line).map { String(line[$0]) }
                let value: String       = Range(match.range(at: 3), in: line)
                    .map { String(line[$0]).trimmingCharacters(in: .whitespaces) } ?? ""

                let rawTag = endnoteTag ?? risTag ?? ""
                let canonicalTag = tagNormalizationMap[rawTag] ?? rawTag

                // TY (standard RIS) and %0 (EndNote) both normalise to "TY" and mark the
                // start of a new record. Flush any prior accumulated data before resetting.
                if canonicalTag == "TY" && !currentRecord.isEmpty {
                    if let citation = buildCitation(from: currentRecord) {
                        citations.append(citation)
                    }
                    currentRecord = [:]
                    lastTag = nil
                }

                if !value.isEmpty {
                    currentRecord[canonicalTag, default: []].append(value)
                }
                lastTag = canonicalTag

            } else if !line.isEmpty, let tag = lastTag {
                // Multi-line continuation (common in Embase long abstracts):
                // append the line content to the last value of the current tag.
                if var values = currentRecord[tag], !values.isEmpty {
                    values[values.count - 1] += " " + line
                    currentRecord[tag] = values
                }
            }
        }

        // Flush last record if ER  - was missing
        if !currentRecord.isEmpty, let citation = buildCitation(from: currentRecord) {
            citations.append(citation)
        }

        return citations
    }

    // MARK: - Private

    private static func buildCitation(from record: [String: [String]]) -> Citation? {
        // Must have at least a title (all title variants normalised to "TI")
        guard let titleValues = record["TI"],
              let title = titleValues.first, !title.isEmpty
        else { return nil }

        // Abstract (all variants normalised to "AB")
        let abstract = record["AB"]?.joined(separator: " ") ?? ""

        // Authors (all variants normalised to "AU")
        let authors = (record["AU"] ?? []).map { normalizeAuthor($0) }

        // Year (all variants normalised to "PY")
        let yearString = (record["PY"] ?? record["DA"])?.first ?? ""
        let year = Int(yearString.prefix(4))

        // Journal (all variants normalised to "JO")
        let journal = (record["JO"] ?? record["SO"])?.first ?? ""

        let volume = record["VL"]?.first ?? ""
        let issue  = record["IS"]?.first ?? ""

        // DOI: standard DO plus DI (normalised to DO above)
        let doi = record["DO"]?.first?.trimmingCharacters(in: .whitespaces)

        // PMID: from AN tag
        let pmid = record["AN"]?.first?.trimmingCharacters(in: .whitespaces)

        // NCT ID: search the N1 notes field for a ClinicalTrials.gov identifier
        // (ClinicalTrials.gov identifiers are always "NCT" followed by exactly 8 digits)
        let nctID: String? = {
            let notes = (record["N1"] ?? []).joined(separator: " ")
            let nsNotes = notes as NSString
            let match = nctIDRegex.firstMatch(in: notes, range: NSRange(location: 0, length: nsNotes.length))
            return match.flatMap { Range($0.range, in: notes).map { String(notes[$0]) } }
        }()

        // Source database from DB tag (DP normalised to DB above)
        let dbString = record["DB"]?.first?.lowercased() ?? ""
        let source = citationSource(from: dbString)

        // Pages from SP/EP tags
        let pages: String = {
            if let sp = record["SP"]?.first, let ep = record["EP"]?.first {
                return "\(sp)-\(ep)"
            }
            return record["SP"]?.first ?? ""
        }()

        let citation = Citation(
            title: title,
            abstract: abstract,
            authors: authors,
            year: year,
            journal: journal,
            source: source,
            doi: doi,
            pmid: pmid,
            nctID: nctID
        )
        citation.volume = volume
        citation.issue = issue
        citation.pages = pages
        citation.rawImportData = record.description

        return citation
    }

    private static func normalizeAuthor(_ raw: String) -> String {
        // RIS authors are typically "Last, First" – keep as-is
        raw.trimmingCharacters(in: .whitespaces)
    }

    private static func citationSource(from db: String) -> CitationSource {
        if db.contains("pubmed") || db.contains("medline") { return .pubmed }
        if db.contains("embase") { return .embase }
        if db.contains("cochrane") { return .cochrane }
        if db.contains("cinahl") { return .cinahl }
        if db.contains("scopus") { return .scopus }
        if db.contains("web of science") || db.contains("wos") { return .webOfScience }
        return .other
    }
}
