import Foundation
import SwiftData

/// A bibliographic citation / report linked to a Study.
/// Multiple citations can belong to the same Study (e.g., a trial with
/// a primary paper + conference poster).
@Model
final class Citation {
    var id: UUID
    var study: Study?

    // Bibliographic fields
    var title: String
    var abstract: String
    var authors: [String]
    var year: Int?
    var journal: String
    var volume: String
    var issue: String
    var pages: String

    // Identifiers
    var doi: String?
    var pmid: String?
    var nctID: String?
    var embaseID: String?

    // Source database
    var source: CitationSource

    // Whether this is the "primary" report for the study
    var isPrimary: Bool

    // Full text
    var pdfPath: String?
    var fullTextNotes: String

    // AI-generated tags
    var aiTags: [String]

    // Raw import data (for debugging)
    var rawImportData: String

    init(
        title: String,
        abstract: String = "",
        authors: [String] = [],
        year: Int? = nil,
        journal: String = "",
        source: CitationSource = .other,
        doi: String? = nil,
        pmid: String? = nil,
        nctID: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.abstract = abstract
        self.authors = authors
        self.year = year
        self.journal = journal
        self.volume = ""
        self.issue = ""
        self.pages = ""
        self.doi = doi
        self.pmid = pmid
        self.nctID = nctID
        self.source = source
        self.isPrimary = true
        self.fullTextNotes = ""
        self.aiTags = []
        self.rawImportData = ""
    }

    var firstAuthor: String {
        authors.first ?? ""
    }

    var formattedCitation: String {
        let authString = authors.prefix(3).joined(separator: ", ")
        let suffix = authors.count > 3 ? " et al." : ""
        let yearStr = year.map { " (\($0))" } ?? ""
        return "\(authString)\(suffix)\(yearStr). \(title). \(journal)."
    }
}

enum CitationSource: String, Codable, CaseIterable {
    case pubmed    = "PubMed"
    case embase    = "Embase"
    case cochrane  = "Cochrane"
    case cinahl    = "CINAHL"
    case scopus    = "Scopus"
    case webOfScience = "Web of Science"
    case clinicalTrials = "ClinicalTrials.gov"
    case manual    = "Manual Entry"
    case other     = "Other"
}
