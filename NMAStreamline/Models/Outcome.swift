import Foundation
import SwiftData

/// Represents a clinical outcome extracted from a study.
/// Outcomes can be Primary, Secondary, or "Linker" (shared across treatments).
@Model
final class Outcome {
    var id: UUID
    var study: Study?

    var name: String
    var type: OutcomeType
    var timepoint: String
    var measure: String      // e.g., "Mean ± SD", "OR", "HR"
    var notes: String

    // Whether the AI flagged this as a potential network linker
    var isAILinkerSuggestion: Bool

    // Whether the user confirmed it as a linker
    var isConfirmedLinker: Bool

    init(
        name: String,
        type: OutcomeType = .secondary,
        timepoint: String = "",
        measure: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.timepoint = timepoint
        self.measure = measure
        self.notes = ""
        self.isAILinkerSuggestion = false
        self.isConfirmedLinker = false
    }
}

enum OutcomeType: String, Codable, CaseIterable {
    case primary   = "Primary"
    case secondary = "Secondary"
    case linker    = "Linker"
    case safety    = "Safety / Adverse Event"
    case patientReported = "Patient-Reported"
}
