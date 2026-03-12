import SwiftUI
import Charts

/// Displays the PRISMA 2020 flow diagram as a live, auto-updating SwiftUI view.
/// Counts are derived directly from the project's SwiftData store.
struct PRISMAFlowView: View {
    let project: NMAProject

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                title
                flowDiagram
                    .padding()
                exclusionTable
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Title

    private var title: some View {
        VStack(spacing: 4) {
            Text("PRISMA 2020 Flow Diagram")
                .font(.title2.bold())
            Text(project.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Flow diagram boxes

    private var flowDiagram: some View {
        VStack(spacing: 0) {

            // Identification phase
            phaseHeader("Identification")
            HStack(alignment: .top, spacing: 24) {
                prismaBox(
                    title: "Records identified",
                    count: project.totalImported,
                    detail: "from databases and registers",
                    color: .blue
                )
            }

            flowArrow()

            // Screening phase
            phaseHeader("Screening")
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 0) {
                    prismaBox(
                        title: "Records screened",
                        count: project.screenedAbstracts,
                        color: .teal
                    )
                    flowArrow()
                    prismaBox(
                        title: "Reports sought for retrieval",
                        count: project.fullTextRetrieved,
                        color: .teal
                    )
                    flowArrow()
                    prismaBox(
                        title: "Reports assessed for eligibility",
                        count: project.fullTextRetrieved,
                        color: .teal
                    )
                }

                VStack(spacing: 16) {
                    excludedBox(
                        title: "Records excluded",
                        count: project.abstractExcluded + project.duplicatesRemoved,
                        reasons: abstractExclusionSummary
                    )
                    excludedBox(
                        title: "Reports not retrieved",
                        count: 0,
                        reasons: []
                    )
                    excludedBox(
                        title: "Reports excluded",
                        count: project.fullTextExcluded,
                        reasons: fullTextExclusionSummary
                    )
                }
            }

            flowArrow()

            // Included phase
            phaseHeader("Included")
            prismaBox(
                title: "Studies included in review",
                count: project.finalIncluded,
                color: .green,
                isHighlighted: true
            )
        }
    }

    // MARK: - Sub-components

    private func phaseHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private func prismaBox(
        title: String,
        count: Int,
        detail: String = "",
        color: Color = .primary,
        isHighlighted: Bool = false
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Text("\(count)")
                .font(.title.bold())
                .foregroundStyle(color)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(minWidth: 200)
        .background(isHighlighted ? color.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(isHighlighted ? 0.6 : 0.3), lineWidth: isHighlighted ? 2 : 1)
        )
        .cornerRadius(8)
    }

    private func excludedBox(title: String, count: Int, reasons: [(String, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(count)").font(.subheadline.bold()).foregroundStyle(.red)
            }
            ForEach(reasons, id: \.0) { reason, n in
                HStack {
                    Text("• \(reason)").font(.caption)
                    Spacer()
                    Text("\(n)").font(.caption.bold())
                }
            }
        }
        .padding(10)
        .frame(minWidth: 200)
        .background(Color.red.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    private func flowArrow() -> some View {
        Image(systemName: "arrow.down")
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    // MARK: - Exclusion reasons table

    private var exclusionTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Full-Text Exclusion Reasons (PRISMA-N)")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(fullTextExclusionSummary, id: \.0) { reason, count in
                HStack {
                    Text(reason).font(.body)
                    Spacer()
                    Text("\(count)").font(.body.bold())
                }
                Divider()
            }

            if fullTextExclusionSummary.isEmpty {
                Text("No full-text exclusions yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .padding(.bottom)
    }

    // MARK: - Helpers

    private var abstractExclusionSummary: [(String, Int)] {
        let excluded = project.studies.filter { $0.status == .excludedAbstract }
        return exclusionSummary(for: excluded)
    }

    private var fullTextExclusionSummary: [(String, Int)] {
        let excluded = project.studies.filter { $0.status == .excludedFullText }
        return exclusionSummary(for: excluded)
    }

    private func exclusionSummary(for studies: [Study]) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for study in studies {
            let reason = study.primaryExclusionReason?.rawValue ?? "Not specified"
            counts[reason, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }
    }
}
