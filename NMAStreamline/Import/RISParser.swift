import Foundation

/// Parses RIS (Research Information Systems) formatted bibliography files.
/// Spec: https://en.wikipedia.org/wiki/RIS_(file_format)
struct RISParser {

    /// Parse RIS content string into an array of Citation objects.
    static func parse(_ content: String) -> [Citation] {
        var citations: [Citation] = []
        let lines = content.components(separatedBy: .newlines)

        var currentRecord: [String: [String]] = [:]

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line == "ER  -" || line == "ER  - " {
                // End of record
                if let citation = buildCitation(from: currentRecord) {
                    citations.append(citation)
                }
                currentRecord = [:]
                continue
            }

            // RIS format: "TY  - Journal Article"
            guard line.count >= 6,
                  line[line.index(line.startIndex, offsetBy: 2)...line.index(line.startIndex, offsetBy: 3)] == "  ",
                  line[line.index(line.startIndex, offsetBy: 4)...line.index(line.startIndex, offsetBy: 5)] == "- "
            else {
                // Continuation of previous field (some RIS files wrap long values)
                continue
            }

            let tag = String(line.prefix(2))
            let value = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)

            if !value.isEmpty {
                currentRecord[tag, default: []].append(value)
            }
        }

        // Flush last record if ER was missing
        if !currentRecord.isEmpty, let citation = buildCitation(from: currentRecord) {
            citations.append(citation)
        }

        return citations
    }

    // MARK: - Private

    private static func buildCitation(from record: [String: [String]]) -> Citation? {
        // Must have at least a title
        guard let titleValues = record["TI"] ?? record["T1"],
              let title = titleValues.first, !title.isEmpty
        else { return nil }

        let abstract = (record["AB"] ?? record["N2"])?.joined(separator: " ") ?? ""

        // Authors: AU or A1 tags
        let authorRaw = (record["AU"] ?? record["A1"]) ?? []
        let authors = authorRaw.map { normalizeAuthor($0) }

        // Year from PY, Y1, or DA
        let yearString = (record["PY"] ?? record["Y1"] ?? record["DA"])?.first ?? ""
        let year = Int(yearString.prefix(4))

        let journal = (record["JO"] ?? record["JF"] ?? record["T2"] ?? record["SO"])?.first ?? ""
        let volume  = record["VL"]?.first ?? ""
        let issue   = record["IS"]?.first ?? ""

        let doi  = record["DO"]?.first?.trimmingCharacters(in: .whitespaces)
        let pmid = record["AN"]?.first?.trimmingCharacters(in: .whitespaces)

        // Source database from DB or DP tag
        let dbString = (record["DB"] ?? record["DP"])?.first?.lowercased() ?? ""
        let source = citationSource(from: dbString)

        // Build the pages string from start/end page tags
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
            pmid: pmid
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
