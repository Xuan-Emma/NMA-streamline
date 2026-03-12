import Foundation

/// Parses BibTeX (.bib) bibliography files.
/// Handles @article, @inproceedings, @misc, etc.
struct BibParser {

    static func parse(_ content: String) -> [Citation] {
        var citations: [Citation] = []

        // Split into entry blocks: @TYPE{key, ...}
        let entryPattern = #"@\w+\s*\{[^@]+"#
        guard let regex = try? NSRegularExpression(pattern: entryPattern, options: [.dotMatchesLineSeparators]) else {
            return citations
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            let block = nsContent.substring(with: match.range)
            if let citation = parseBibEntry(block) {
                citations.append(citation)
            }
        }

        return citations
    }

    // MARK: - Private

    private static func parseBibEntry(_ block: String) -> Citation? {
        // Extract entry type and key
        let headerPattern = #"@(\w+)\s*\{([^,]+),"#
        guard let headerRegex = try? NSRegularExpression(pattern: headerPattern),
              let headerMatch = headerRegex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block))
        else { return nil }

        // Extract all field = {value} or field = "value" pairs
        let fields = extractFields(from: block)

        guard let title = fields["title"], !title.isEmpty else { return nil }

        let abstract = fields["abstract"] ?? ""
        let year = fields["year"].flatMap { Int($0) }
        let journal = fields["journal"] ?? fields["booktitle"] ?? ""
        let volume  = fields["volume"] ?? ""
        let issue   = fields["number"] ?? ""
        let pages   = fields["pages"] ?? ""
        let doi     = fields["doi"]
        let pmid    = fields["pmid"] ?? fields["pubmed_id"]
        let url     = fields["url"]

        let authorsRaw = fields["author"] ?? ""
        let authors = parseAuthors(authorsRaw)

        let citation = Citation(
            title: cleanBrackets(title),
            abstract: cleanBrackets(abstract),
            authors: authors,
            year: year,
            journal: cleanBrackets(journal),
            source: .other,
            doi: doi,
            pmid: pmid
        )
        citation.volume = volume
        citation.issue = issue
        citation.pages = pages
        if let url = url { citation.rawImportData = "url=\(url)" }

        return citation
    }

    /// Extract key = {value} or key = "value" pairs from a BibTeX block.
    private static func extractFields(from block: String) -> [String: String] {
        var fields: [String: String] = [:]

        // Pattern: word = {balanced braces} or word = "..."
        let fieldPattern = #"(\w+)\s*=\s*(?:\{((?:[^{}]|\{[^{}]*\})*)\}|"([^"]*)")"#
        guard let regex = try? NSRegularExpression(pattern: fieldPattern, options: [.dotMatchesLineSeparators]) else {
            return fields
        }

        let nsBlock = block as NSString
        let matches = regex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length))

        for match in matches {
            let key = nsBlock.substring(with: match.range(at: 1)).lowercased()
            let value: String
            if match.range(at: 2).location != NSNotFound {
                value = nsBlock.substring(with: match.range(at: 2))
            } else if match.range(at: 3).location != NSNotFound {
                value = nsBlock.substring(with: match.range(at: 3))
            } else {
                continue
            }
            fields[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return fields
    }

    /// Parse "Last, First and Last2, First2" BibTeX author strings.
    private static func parseAuthors(_ raw: String) -> [String] {
        raw.components(separatedBy: " and ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Remove LaTeX curly braces from a string.
    private static func cleanBrackets(_ s: String) -> String {
        s.replacingOccurrences(of: "{", with: "")
         .replacingOccurrences(of: "}", with: "")
    }
}
