import Foundation

/// Parses PubMed XML export files (PubmedArticleSet format).
final class PubMedXMLParser: NSObject, XMLParserDelegate {

    private var citations: [Citation] = []

    // Current record state
    private var currentTitle    = ""
    private var currentAbstract = ""
    private var currentAuthors: [String] = []
    private var currentYear: Int?
    private var currentJournal  = ""
    private var currentVolume   = ""
    private var currentIssue    = ""
    private var currentPages    = ""
    private var currentDOI: String?
    private var currentPMID: String?
    private var currentNCT: String?

    // XML parsing state
    private var currentElement         = ""
    private var currentLastName        = ""
    private var currentForeName        = ""
    private var insideAbstract         = false
    private var abstractTexts: [String] = []
    /// Accumulates character data for the current AbstractText section.
    /// XMLParser may invoke foundCharacters multiple times per element;
    /// we buffer here and flush on didEndElement to avoid truncated abstracts.
    private var currentAbstractSection = ""

    // MARK: - Public API

    static func parse(_ data: Data) -> [Citation] {
        let instance = PubMedXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = instance
        parser.parse()
        return instance.citations
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        switch elementName {
        case "PubmedArticle":
            resetCurrentRecord()
        case "AbstractText":
            insideAbstract = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch currentElement {
        case "ArticleTitle":
            // Use space-aware concatenation in case XMLParser splits the text
            // of one element across multiple foundCharacters calls.
            currentTitle = currentTitle.isEmpty ? trimmed : currentTitle + " " + trimmed
        case "AbstractText":
            // Accumulate into a section buffer; flushed to abstractTexts on
            // didEndElement so that multi-call splits don't create extra entries.
            currentAbstractSection = currentAbstractSection.isEmpty
                ? trimmed
                : currentAbstractSection + " " + trimmed
        case "LastName":
            currentLastName += trimmed
        case "ForeName", "Initials":
            if currentForeName.isEmpty { currentForeName += trimmed }
        case "Year":
            if currentYear == nil { currentYear = Int(trimmed) }
        case "Title", "ISOAbbreviation":
            if currentJournal.isEmpty { currentJournal += trimmed }
        case "Volume":
            currentVolume += trimmed
        case "Issue":
            currentIssue += trimmed
        case "MedlinePgn":
            currentPages += trimmed
        case "ArticleId":
            // handled in didEndElement based on IdType attribute
            break
        case "PMID":
            if currentPMID == nil { currentPMID = trimmed }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Author":
            if !currentLastName.isEmpty {
                let author = currentForeName.isEmpty ? currentLastName
                             : "\(currentLastName), \(currentForeName)"
                currentAuthors.append(author)
            }
            currentLastName = ""
            currentForeName = ""

        case "AbstractText":
            // Flush the accumulated section text into the abstract parts array.
            if !currentAbstractSection.isEmpty {
                abstractTexts.append(currentAbstractSection)
                currentAbstractSection = ""
            }
            insideAbstract = false

        case "PubmedArticle":
            // Build and store citation
            currentAbstract = abstractTexts.joined(separator: " ")
            let citation = Citation(
                title: currentTitle,
                abstract: currentAbstract,
                authors: currentAuthors,
                year: currentYear,
                journal: currentJournal,
                source: .pubmed,
                doi: currentDOI,
                pmid: currentPMID
            )
            citation.volume = currentVolume
            citation.issue = currentIssue
            citation.pages = currentPages
            citation.nctID = currentNCT
            citations.append(citation)

        default:
            break
        }
    }

    // MARK: - Private

    private func resetCurrentRecord() {
        currentTitle          = ""
        currentAbstract       = ""
        currentAuthors        = []
        currentYear           = nil
        currentJournal        = ""
        currentVolume         = ""
        currentIssue          = ""
        currentPages          = ""
        currentDOI            = nil
        currentPMID           = nil
        currentNCT            = nil
        currentLastName       = ""
        currentForeName       = ""
        abstractTexts         = []
        currentAbstractSection = ""
    }
}

// MARK: - CitationParser conformance

extension PubMedXMLParser: CitationParser {
    var supportedExtensions: [String] { ["xml"] }

    func parse(data: Data) -> [Citation] {
        PubMedXMLParser.parse(data)
    }
}
