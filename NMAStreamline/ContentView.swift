import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Main content view with a three-column NavigationSplitView:
/// Sidebar → Project List  |  Detail → Study List  |  Inspector → Study / AI
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NMAProject.updatedAt, order: .reverse) private var projects: [NMAProject]

    @State private var selectedProject: NMAProject?
    @State private var selectedStudy: Study?
    @State private var navigationSelection: NavigationItem? = .studies
    @State private var showNewProjectSheet = false
    @State private var showImportSheet = false
    @State private var importManager = ImportManager()

    var body: some View {
        NavigationSplitView {
            // SIDEBAR
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } content: {
            // CONTENT (study list / detail based on selection)
            if let project = selectedProject {
                contentColumn(project: project)
            } else {
                ContentUnavailableView("Select a Project", systemImage: "folder")
            }
        } detail: {
            // INSPECTOR
            if let study = selectedStudy, let project = selectedProject {
                StudyDetailView(study: study, project: project)
            } else if let project = selectedProject {
                projectOverview(project)
            } else {
                ContentUnavailableView("Select a Study", systemImage: "doc.text.magnifyingglass")
            }
        }
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet { title, r1, r2, blind in
                createProject(title: title, r1: r1, r2: r2, blind: blind)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedProject) {
            Section("Projects") {
                ForEach(projects) { project in
                    NavigationLink(value: project) {
                        projectRow(project)
                    }
                }
            }
        }
        .navigationTitle("NMA Streamline")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewProjectSheet = true } label: {
                    Label("New Project", systemImage: "plus")
                }
            }
        }
    }

    private func projectRow(_ project: NMAProject) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.title).font(.body)
            HStack(spacing: 8) {
                Text("\(project.totalImported) records")
                    .font(.caption).foregroundStyle(.secondary)
                if project.duplicatesRemoved > 0 {
                    Text("· \(project.duplicatesRemoved) dupes")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Content column

    private func contentColumn(project: NMAProject) -> some View {
        StudyListView(
            project: project,
            selectedStudy: $selectedStudy,
            importManager: importManager,
            navigationSelection: $navigationSelection
        )
        .navigationTitle(project.title)
    }

    // MARK: - Project overview (shown in inspector when no study selected)

    private func projectOverview(_ project: NMAProject) -> some View {
        TabView {
            PRISMAFlowView(project: project)
                .tabItem { Label("PRISMA", systemImage: "chart.bar.doc.horizontal") }

            NetworkGeometryView(project: project)
                .tabItem { Label("Network", systemImage: "point.3.connected.trianglepath.dotted") }

            PICOSettingsView(project: project)
                .tabItem { Label("PICO / Settings", systemImage: "gear") }
        }
    }

    // MARK: - Actions

    private func createProject(title: String, r1: String, r2: String, blind: Bool) {
        let project = NMAProject(
            title: title,
            reviewer1Name: r1,
            reviewer2Name: r2,
            blindMode: blind
        )
        modelContext.insert(project)
        try? modelContext.save()
        selectedProject = project
    }
}

// MARK: - Navigation items

enum NavigationItem: String, CaseIterable {
    case studies    = "Studies"
    case screening  = "Screening"
    case duplicates = "Duplicates"
    case prisma     = "PRISMA"
    case network    = "Network"
}
