import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Shows the list of studies for a project, grouped by status.
/// Includes import and screening controls.
struct StudyListView: View {
    let project: NMAProject
    @Binding var selectedStudy: Study?
    @ObservedObject var importManager: ImportManager
    @Binding var navigationSelection: NavigationItem?

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var statusFilter: StudyStatus? = nil
    @State private var showImporter = false
    @State private var showDuplicates = false
    @State private var showScreening = false
    @State private var importError: Error?
    @State private var showImportError = false
    @State private var selectedDuplicateMatch: DuplicateMatch?

    var filteredStudies: [Study] {
        project.studies.filter { study in
            let matchesStatus = statusFilter == nil || study.status == statusFilter
            let matchesSearch = searchText.isEmpty
                || study.title.localizedCaseInsensitiveContains(searchText)
                || study.firstAuthor.localizedCaseInsensitiveContains(searchText)
            return matchesStatus && matchesSearch
        }
        .sorted { ($0.year ?? 0) > ($1.year ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            studyList
        }
        .searchable(text: $searchText, prompt: "Search title or author…")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.init(filenameExtension: "ris")!,
                                  .init(filenameExtension: "bib")!,
                                  UTType.xml],
            allowsMultipleSelection: true
        ) { result in
            Task {
                switch result {
                case .success(let urls):
                    for url in urls {
                        do {
                            try await importManager.importFile(url: url, into: project, context: modelContext)
                        } catch {
                            importError = error
                            showImportError = true
                        }
                    }
                case .failure(let error):
                    importError = error
                    showImportError = true
                }
            }
        }
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK") {}
        } message: {
            Text(importError?.localizedDescription ?? "Unknown error")
        }
        .sheet(isPresented: $showScreening) {
            let vm = ScreeningViewModel(
                project: project,
                reviewerIndex: 1,
                stage: .abstract,
                context: modelContext
            )
            ScreeningView(viewModel: vm)
        }
        .sheet(item: $selectedDuplicateMatch) { match in
            MergeWorkspaceView(match: match) { action in
                try? importManager.resolve(match, action: action, context: modelContext)
            }
        }
        .sheet(isPresented: $showDuplicates) {
            DuplicateListView(
                matches: importManager.pendingDuplicates,
                onSelect: { selectedDuplicateMatch = $0 }
            )
        }
        .toolbar { listToolbar }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            // Status filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterPill(nil, label: "All (\(project.studies.count))")
                    ForEach(StudyStatus.allCases, id: \.self) { status in
                        let count = project.studies.filter { $0.status == status }.count
                        if count > 0 {
                            filterPill(status, label: "\(status.rawValue) (\(count))")
                        }
                    }
                }
                .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func filterPill(_ status: StudyStatus?, label: String) -> some View {
        Button(label) {
            statusFilter = (statusFilter == status ? nil : status)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(statusFilter == status ? .blue : .secondary)
    }

    // MARK: - Study list

    private var studyList: some View {
        List(filteredStudies, id: \.id, selection: $selectedStudy) { study in
            studyRow(study)
                .tag(study)
        }
    }

    private func studyRow(_ study: Study) -> some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(statusColor(study.status))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(study.title)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if !study.firstAuthor.isEmpty {
                        Text(study.firstAuthor).font(.caption).foregroundStyle(.secondary)
                    }
                    if let year = study.year {
                        Text(String(year)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let citation = study.primaryCitation {
                        Text(citation.source.rawValue).font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            // Conflict indicator
            if study.hasConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            // AI suggestion badge
            Text(study.status.rawValue)
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(statusColor(study.status).opacity(0.15))
                .foregroundStyle(statusColor(study.status))
                .cornerRadius(6)
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem {
            Button { showImporter = true } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
        }
        ToolbarItem {
            Button { showScreening = true } label: {
                Label("Screen", systemImage: "checkmark.rectangle.stack")
            }
            .disabled(project.studies.filter { $0.status == .unscreened }.isEmpty)
        }
        ToolbarItem {
            Button { showDuplicates = true } label: {
                Label("Duplicates (\(importManager.pendingDuplicates.count))",
                      systemImage: "doc.on.doc")
            }
            .disabled(importManager.pendingDuplicates.isEmpty)
        }
    }
}

// MARK: - Duplicate list helper view

struct DuplicateListView: View {
    let matches: [DuplicateMatch]
    let onSelect: (DuplicateMatch) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(matches, id: \.primary.id) { match in
                Button {
                    onSelect(match)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.primary.title).font(.body).lineLimit(2)
                        HStack {
                            Text(match.matchType.rawValue).font(.caption).foregroundStyle(.secondary)
                            Text("·")
                            Text(String(format: "%.0f%% similar", match.similarity * 100))
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Pending Duplicates (\(matches.count))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
