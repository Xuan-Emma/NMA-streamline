import SwiftUI
import SwiftData

@main
struct NMAStreamlineApp: App {

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            NMAProject.self,
            Study.self,
            Citation.self,
            Outcome.self,
            ReviewerDecision.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic   // iCloud sync for multi-device screening
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Fallback to local-only if iCloud is unavailable
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            NMACommands()
        }

        // PRISMA window
        Window("PRISMA Flow", id: "prisma") {
            Text("Open a project to view its PRISMA diagram.")
                .padding()
        }

        // Settings scene
        Settings {
            AppSettingsView()
        }
    }
}

// MARK: - App Commands

struct NMACommands: Commands {
    var body: some Commands {
        CommandGroup(after: .importExport) {
            Divider()
            Button("Import Citations…") {
                NotificationCenter.default.post(name: .nmaImportCitations, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let nmaImportCitations = Notification.Name("NMAImportCitations")
}

// MARK: - App Settings

struct AppSettingsView: View {
    @AppStorage("defaultReviewerName") private var defaultReviewerName = ""
    @AppStorage("enableAI") private var enableAI = true
    @AppStorage("aiConfidenceThreshold") private var aiConfidenceThreshold = 0.70

    var body: some View {
        Form {
            Section("Reviewer") {
                LabeledContent("Your Name") {
                    TextField("Used as default Reviewer 1 name", text: $defaultReviewerName)
                }
            }

            Section("AI Assistant") {
                Toggle("Enable AI Screening Hints", isOn: $enableAI)
                LabeledContent("Confidence Threshold") {
                    Slider(value: $aiConfidenceThreshold, in: 0.5...0.99, step: 0.05) {
                        Text(String(format: "%.0f%%", aiConfidenceThreshold * 100))
                    }
                }
                Text("AI suggestions below this confidence level will be shown as 'Uncertain'.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Deduplication") {
                LabeledContent("Fuzzy Match Threshold") {
                    Text("85% similarity (Levenshtein)")
                        .foregroundStyle(.secondary)
                }
                Text("Studies with ≥85% title/author/year similarity are flagged as potential duplicates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .navigationTitle("NMA Streamline Settings")
    }
}
