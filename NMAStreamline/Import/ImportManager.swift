import Foundation
import SwiftData
import UniformTypeIdentifiers

/// High-level import manager that coordinates file parsing, Study creation,
/// and deduplication.
@MainActor
final class ImportManager: ObservableObject {

    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var importSummary: ImportSummary?
    @Published var pendingDuplicates: [DuplicateMatch] = []

    private let deduplicationEngine = DeduplicationEngine()

    /// Registered parsers, consulted in order when selecting a parser for a
    /// given file extension.  Add new `CitationParser` conformances here to
    /// support additional formats without modifying `importFile`.
    private let parsers: [any CitationParser] = [
        RISParser(),
        BibParser(),
        PubMedXMLParser(),
    ]

    // MARK: - Public API

    /// Import a file at the given URL into the project.
    func importFile(url: URL, into project: NMAProject, context: ModelContext) async throws {
        isImporting = true
        importProgress = 0
        defer { isImporting = false }

        let ext = url.pathExtension.lowercased()
        guard let parser = parsers.first(where: { $0.supportedExtensions.contains(ext) }) else {
            throw ImportError.unsupportedFormat(ext)
        }

        let data = try Data(contentsOf: url)
        let citations = parser.parse(data: data)

        importProgress = 0.3

        // Wrap each citation in a Study
        var newStudies: [Study] = []
        for citation in citations {
            let study = Study(title: citation.title, year: citation.year)
            citation.isPrimary = true
            study.citations.append(citation)
            newStudies.append(study)
        }

        importProgress = 0.5

        // Run deduplication against all existing + new citations
        let allCitations = project.studies.flatMap { $0.citations } + citations
        let matches = await deduplicationEngine.findDuplicates(in: allCitations)

        importProgress = 0.8

        // Insert new studies into project
        for study in newStudies {
            project.studies.append(study)
            context.insert(study)
        }

        try context.save()

        importProgress = 1.0

        pendingDuplicates = matches
        importSummary = ImportSummary(
            totalImported: citations.count,
            duplicatesFound: matches.count,
            source: url.lastPathComponent
        )
    }

    /// Resolve a duplicate match: merge secondary into primary, or keep both.
    func resolve(_ match: DuplicateMatch, action: DuplicateResolutionAction,
                 context: ModelContext) throws {
        switch action {
        case .mergeIntoPrimary:
            // Move all citations from duplicate's study into primary's study
            if let dupStudy = match.duplicate.study,
               let primStudy = match.primary.study {
                for citation in dupStudy.citations {
                    citation.study = primStudy
                    primStudy.citations.append(citation)
                }
                dupStudy.status = .duplicate
            }

        case .keepBoth:
            break   // do nothing

        case .discardDuplicate:
            if let dupStudy = match.duplicate.study {
                dupStudy.status = .duplicate
            }
        }

        try context.save()

        pendingDuplicates.removeAll { $0.duplicate.id == match.duplicate.id }
    }
}

// MARK: - Supporting types

struct ImportSummary {
    let totalImported: Int
    let duplicatesFound: Int
    let source: String
}

enum DuplicateResolutionAction {
    case mergeIntoPrimary
    case keepBoth
    case discardDuplicate
}

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file format: .\(ext). Please use .ris, .bib, or .xml."
        case .parseError(let msg):
            return "Parse error: \(msg)"
        }
    }
}
