import SwiftUI
import PDFKit

/// Detail view for a single Study, showing citations, decisions, outcomes,
/// and an embedded PDF viewer.
struct StudyDetailView: View {
    @Bindable var study: Study
    let project: NMAProject

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var showPDFImporter = false
    @State private var exclusionReason: ExclusionReason?

    var body: some View {
        VStack(spacing: 0) {
            headerArea
            Divider()
            TabView(selection: $selectedTab) {
                abstractTab
                    .tabItem { Label("Abstract", systemImage: "text.alignleft") }
                    .tag(0)

                outcomesTab
                    .tabItem { Label("Outcomes", systemImage: "list.bullet.rectangle") }
                    .tag(1)

                decisionsTab
                    .tabItem { Label("Decisions", systemImage: "person.2") }
                    .tag(2)

                pdfTab
                    .tabItem { Label("Full Text", systemImage: "doc.richtext") }
                    .tag(3)
            }
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(study.title)
                    .font(.headline)
                    .lineLimit(3)

                if let citation = study.primaryCitation {
                    HStack(spacing: 10) {
                        if !citation.authors.isEmpty {
                            Text(citation.authors.prefix(3).joined(separator: ", ") +
                                 (citation.authors.count > 3 ? " et al." : ""))
                        }
                        if let year = citation.year { Text(String(year)) }
                        if !citation.journal.isEmpty { Text(citation.journal).italic() }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if let doi = citation.doi {
                            Link("DOI", destination: URL(string: "https://doi.org/\(doi)")!)
                                .font(.caption)
                        }
                        if let pmid = citation.pmid {
                            Link("PubMed", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")!)
                                .font(.caption)
                        }
                    }
                }
            }

            Spacer()

            // Status badge
            VStack(spacing: 6) {
                statusBadge(study.status)
                if study.hasConflict {
                    Label("Conflict", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func statusBadge(_ status: StudyStatus) -> some View {
        Menu {
            ForEach(StudyStatus.allCases, id: \.self) { s in
                Button(s.rawValue) { study.status = s }
            }
        } label: {
            Text(status.rawValue)
                .font(.subheadline.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor(status).opacity(0.15))
                .foregroundStyle(statusColor(status))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(statusColor(status).opacity(0.4), lineWidth: 1)
                )
        }
    }

    private func statusColor(_ status: StudyStatus) -> Color {
        switch status {
        case .included, .includedAbstract, .includedFullText: return .green
        case .excludedAbstract, .excludedFullText: return .red
        case .duplicate: return .orange
        case .maybe: return .yellow
        case .unscreened: return .gray
        }
    }

    // MARK: - Tabs

    private var abstractTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let abstract = study.primaryCitation?.abstract, !abstract.isEmpty {
                    Text(abstract)
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                } else {
                    Text("No abstract available.")
                        .foregroundStyle(.secondary)
                }

                // Citations list
                if study.citations.count > 1 {
                    Divider()
                    Text("All Reports (\(study.citations.count))")
                        .font(.subheadline.bold())
                    ForEach(study.citations, id: \.id) { citation in
                        citationRow(citation)
                    }
                }
            }
            .padding()
        }
    }

    private func citationRow(_ citation: Citation) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(citation.title).font(.body).lineLimit(2)
                Text(citation.formattedCitation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if citation.isPrimary {
                Text("Primary").font(.caption2.bold())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }

    private var outcomesTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Outcomes").font(.headline).padding()
                Spacer()
                Button("Add Outcome") {
                    let outcome = Outcome(name: "New Outcome")
                    study.outcomes.append(outcome)
                    modelContext.insert(outcome)
                    try? modelContext.save()
                }
                .buttonStyle(.bordered)
                .padding()
            }
            Divider()
            List {
                ForEach(study.outcomes, id: \.id) { outcome in
                    outcomeRow(outcome)
                }
                .onDelete { offsets in
                    for idx in offsets {
                        modelContext.delete(study.outcomes[idx])
                    }
                    try? modelContext.save()
                }
            }
        }
    }

    private func outcomeRow(_ outcome: Outcome) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(outcome.name).font(.body)
                if !outcome.timepoint.isEmpty {
                    Text("Timepoint: \(outcome.timepoint)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                if outcome.isAILinkerSuggestion {
                    Label("AI: Linker", systemImage: "wand.and.stars")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
                if outcome.isConfirmedLinker {
                    Label("Linker", systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(outcome.type.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(outcomeTypeColor(outcome.type).opacity(0.15))
                    .foregroundStyle(outcomeTypeColor(outcome.type))
                    .cornerRadius(4)
            }
        }
    }

    private func outcomeTypeColor(_ type: OutcomeType) -> Color {
        switch type {
        case .primary: return .blue
        case .secondary: return .teal
        case .linker: return .orange
        case .safety: return .red
        case .patientReported: return .purple
        }
    }

    private var decisionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                decisionCard(study.decision1, reviewerName: project.reviewer1Name, index: 1)
                decisionCard(study.decision2, reviewerName: project.reviewer2Name, index: 2)

                if study.hasConflict {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("These decisions conflict and require adjudication.")
                            .font(.body)
                    }
                    .padding()
                    .background(.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    private func decisionCard(_ decision: ReviewerDecision?, reviewerName: String, index: Int) -> some View {
        GroupBox {
            if let d = decision {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(reviewerName, systemImage: "person.fill")
                            .font(.subheadline.bold())
                        Spacer()
                        decisionLabel(d.decision)
                    }
                    if let reason = d.exclusionReason {
                        LabeledContent("Reason", value: reason.rawValue).font(.caption)
                    }
                    if !d.notes.isEmpty {
                        Text(d.notes).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(d.decidedAt.formatted(.dateTime.day().month().year().hour().minute()))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                HStack {
                    Label(reviewerName, systemImage: "person.fill")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func decisionLabel(_ d: ScreeningDecision) -> some View {
        Group {
            switch d {
            case .include: Label("Include", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .exclude: Label("Exclude", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            case .maybe:   Label("Maybe",   systemImage: "questionmark.circle.fill").foregroundStyle(.orange)
            case .pending: Label("Pending", systemImage: "clock").foregroundStyle(.gray)
            }
        }
        .font(.subheadline.bold())
    }

    private var pdfTab: some View {
        VStack {
            if let path = study.primaryCitation?.pdfPath,
               let url = URL(string: path),
               let document = PDFDocument(url: url) {
                PDFKitView(document: document)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No PDF attached")
                        .foregroundStyle(.secondary)
                    Button("Attach PDF…") { showPDFImporter = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .fileImporter(
                    isPresented: $showPDFImporter,
                    allowedContentTypes: [.pdf]
                ) { result in
                    if case .success(let url) = result {
                        study.primaryCitation?.pdfPath = url.absoluteString
                        try? modelContext.save()
                    }
                }
            }
        }
    }
}

// MARK: - PDFKit SwiftUI wrapper

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}
