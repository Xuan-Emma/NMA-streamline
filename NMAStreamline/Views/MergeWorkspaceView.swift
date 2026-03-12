import SwiftUI

/// Merge workspace: side-by-side comparison of two suspected duplicate citations
/// with merge / keep-both / discard controls.
struct MergeWorkspaceView: View {
    let match: DuplicateMatch
    let onResolve: (DuplicateResolutionAction) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Match info banner
                matchBanner

                Divider()

                // Side-by-side comparison
                HSplitView {
                    citationPanel(match.primary, label: "Primary Record", accent: .blue)
                    citationPanel(match.duplicate, label: "Potential Duplicate", accent: .orange)
                }

                Divider()

                // Action buttons
                actionBar
            }
            .navigationTitle("Merge Workspace")
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Match banner

    private var matchBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.on.doc.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Potential Duplicate Detected")
                    .font(.headline)
                Text("Match type: \(match.matchType.rawValue)  ·  Similarity: \(String(format: "%.0f%%", match.similarity * 100))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.08))
    }

    // MARK: - Citation panel

    private func citationPanel(_ citation: Citation, label: String, accent: Color) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Panel header
                Text(label)
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.12))

                // Fields comparison
                Group {
                    fieldRow("Title", citation.title)
                    fieldRow("Authors", citation.authors.joined(separator: "; "))
                    fieldRow("Year", citation.year.map(String.init) ?? "—")
                    fieldRow("Journal", citation.journal)
                    fieldRow("DOI", citation.doi ?? "—")
                    fieldRow("PMID", citation.pmid ?? "—")
                    fieldRow("NCT ID", citation.nctID ?? "—")
                    fieldRow("Source", citation.source.rawValue)
                }
                .padding(.horizontal)

                Divider()

                // Abstract
                VStack(alignment: .leading, spacing: 6) {
                    Text("Abstract").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(citation.abstract.isEmpty ? "(No abstract)" : citation.abstract)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
                .padding()
            }
        }
    }

    private func fieldRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value.isEmpty ? "—" : value)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            Spacer()

            Button {
                onResolve(.mergeIntoPrimary)
                dismiss()
            } label: {
                Label("Merge into Primary", systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .help("Move all citations from the duplicate to the primary record and mark the duplicate study as Duplicate.")

            Button {
                onResolve(.discardDuplicate)
                dismiss()
            } label: {
                Label("Discard Duplicate", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .help("Mark the duplicate as excluded without merging.")

            Button {
                onResolve(.keepBoth)
                dismiss()
            } label: {
                Label("Keep Both", systemImage: "checkmark.rectangle.stack")
            }
            .buttonStyle(.bordered)
            .help("Keep both records. Use this if they represent different publications of the same study that you want to track separately.")

            Spacer()
        }
        .padding()
    }
}
