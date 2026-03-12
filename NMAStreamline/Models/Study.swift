import Foundation
import SwiftData

/// Represents a unique clinical study (a trial/study entity).
/// Multiple citations/reports may link to the same Study.
@Model
final class Study {
    var id: UUID
    var title: String
    var year: Int?
    var status: StudyStatus
    var primaryExclusionReason: ExclusionReason?
    var customExclusionNote: String

    // The project this study belongs to
    var project: NMAProject?

    @Relationship(deleteRule: .cascade, inverse: \Citation.study)
    var citations: [Citation]

    @Relationship(deleteRule: .cascade, inverse: \Outcome.study)
    var outcomes: [Outcome]

    // Reviewer decisions
    @Relationship(deleteRule: .cascade, inverse: \ReviewerDecision.study)
    var decisions: [ReviewerDecision]

    // Links to parent study (for multi-report linking)
    var parentStudyID: UUID?

    init(title: String, year: Int? = nil) {
        self.id = UUID()
        self.title = title
        self.year = year
        self.status = .unscreened
        self.customExclusionNote = ""
        self.citations = []
        self.outcomes = []
        self.decisions = []
    }

    // MARK: - Convenience

    var primaryCitation: Citation? {
        citations.first(where: { $0.isPrimary }) ?? citations.first
    }

    /// Returns the abstract from the primary citation.
    var abstract: String {
        primaryCitation?.abstract ?? ""
    }

    /// Returns first author from the primary citation.
    var firstAuthor: String {
        primaryCitation?.firstAuthor ?? ""
    }

    var doi: String? { primaryCitation?.doi }
    var pmid: String? { primaryCitation?.pmid }
    var nctID: String? { primaryCitation?.nctID }

    // MARK: - Dual-review helpers

    var decision1: ReviewerDecision? {
        decisions.first(where: { $0.reviewerIndex == 1 })
    }

    var decision2: ReviewerDecision? {
        decisions.first(where: { $0.reviewerIndex == 2 })
    }

    var hasConflict: Bool {
        guard let d1 = decision1, let d2 = decision2 else { return false }
        return d1.decision != d2.decision
    }
}

// MARK: - Enums

enum StudyStatus: String, Codable, CaseIterable {
    case unscreened       = "Unscreened"
    case includedAbstract = "Included (Abstract)"
    case excludedAbstract = "Excluded (Abstract)"
    case includedFullText = "Included (Full-Text)"
    case excludedFullText = "Excluded (Full-Text)"
    case included         = "Included"
    case duplicate        = "Duplicate"
    case maybe            = "Maybe"

    var color: String {
        switch self {
        case .unscreened:        return "gray"
        case .includedAbstract, .includedFullText, .included: return "green"
        case .excludedAbstract, .excludedFullText:             return "red"
        case .duplicate:         return "orange"
        case .maybe:             return "yellow"
        }
    }
}

enum ExclusionReason: String, Codable, CaseIterable {
    // Abstract-stage exclusions
    case wrongPopulation      = "Wrong Population (P)"
    case wrongIntervention    = "Wrong Intervention (I)"
    case wrongComparator      = "Wrong Comparator (C)"
    case wrongOutcome         = "Wrong Outcome (O)"
    case wrongStudyDesign     = "Wrong Study Design"
    case notRCT               = "Not an RCT"
    case animalStudy          = "Animal Study"
    case duplicate            = "Duplicate"
    case notEnglish           = "Not in English"

    // Full-text exclusions (PRISMA-N required)
    case fullTextUnavailable  = "Full Text Unavailable"
    case wrongDuration        = "Wrong Duration"
    case wrongDose            = "Wrong Dose"
    case conferencePoster     = "Conference Poster (No Data)"
    case retracted            = "Retracted"
    case other                = "Other"
}
