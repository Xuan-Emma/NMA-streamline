import Foundation
import SwiftData

/// Records a single reviewer's screening decision on a Study.
@Model
final class ReviewerDecision {
    var id: UUID
    var study: Study?

    /// 1 = first reviewer, 2 = second reviewer
    var reviewerIndex: Int
    var reviewerName: String
    var decision: ScreeningDecision
    var exclusionReason: ExclusionReason?
    var notes: String
    var decidedAt: Date
    var screeningStage: ScreeningStage

    init(
        reviewerIndex: Int,
        reviewerName: String,
        decision: ScreeningDecision,
        notes: String = "",
        exclusionReason: ExclusionReason? = nil,
        stage: ScreeningStage = .abstract
    ) {
        self.id = UUID()
        self.reviewerIndex = reviewerIndex
        self.reviewerName = reviewerName
        self.decision = decision
        self.notes = notes
        self.exclusionReason = exclusionReason
        self.decidedAt = Date()
        self.screeningStage = stage
    }
}

enum ScreeningDecision: String, Codable, CaseIterable {
    case include = "Include"
    case exclude = "Exclude"
    case maybe   = "Maybe"
    case pending = "Pending"
}

enum ScreeningStage: String, Codable, CaseIterable {
    case abstract  = "Abstract"
    case fullText  = "Full-Text"
}
