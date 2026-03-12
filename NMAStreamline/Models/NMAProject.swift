import Foundation
import SwiftData

/// Top-level container for a systematic review / NMA project.
@Model
final class NMAProject {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    // PICO criteria used for AI-assisted screening
    var picoCriteria: PICOCriteriaData?

    // Reviewer names (up to 2)
    var reviewer1Name: String
    var reviewer2Name: String
    var blindMode: Bool

    @Relationship(deleteRule: .cascade, inverse: \Study.project)
    var studies: [Study]

    init(
        title: String,
        reviewer1Name: String = "Reviewer 1",
        reviewer2Name: String = "Reviewer 2",
        blindMode: Bool = true
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.reviewer1Name = reviewer1Name
        self.reviewer2Name = reviewer2Name
        self.blindMode = blindMode
        self.studies = []
    }

    // MARK: - Computed PRISMA counts

    var totalImported: Int { studies.count }

    var duplicatesRemoved: Int {
        studies.filter { $0.status == .duplicate }.count
    }

    var screenedAbstracts: Int {
        studies.filter { $0.status != .duplicate }.count
    }

    var abstractExcluded: Int {
        studies.filter { $0.status == .excludedAbstract }.count
    }

    var fullTextRetrieved: Int {
        studies.filter { $0.status == .includedAbstract }.count
    }

    var fullTextExcluded: Int {
        studies.filter { $0.status == .excludedFullText }.count
    }

    var finalIncluded: Int {
        studies.filter { $0.status == .included }.count
    }
}
