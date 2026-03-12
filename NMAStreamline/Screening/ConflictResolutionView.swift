import SwiftUI

/// Adjudication view shown when two reviewers disagree on a study.
struct ConflictResolutionView: View {
    let study: Study
    let project: NMAProject
    let onResolve: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var adjudicatorNotes = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                Divider()
                HSplitView {
                    reviewerPanel(reviewerIndex: 1)
                    reviewerPanel(reviewerIndex: 2)
                }
                Divider()
                footerView
            }
            .navigationTitle("Conflict Resolution")
            .navigationSubtitle(study.title)
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Reviewer Disagreement")
                    .font(.headline)
                Text("Both reviewers must agree, or an adjudicator must decide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.08))
    }

    // MARK: - Reviewer panels

    private func reviewerPanel(reviewerIndex: Int) -> some View {
        let decision = reviewerIndex == 1 ? study.decision1 : study.decision2
        let name = reviewerIndex == 1 ? project.reviewer1Name : project.reviewer2Name

        return VStack(alignment: .leading, spacing: 12) {

            // Reviewer header
            HStack {
                Label(name, systemImage: reviewerIndex == 1 ? "person.fill" : "person.fill.2")
                    .font(.headline)
                Spacer()
                if let d = decision {
                    decisionBadge(d.decision)
                } else {
                    Text("Not decided")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(reviewerIndex == 1 ? Color.blue.opacity(0.08) : Color.purple.opacity(0.08))

            // Decision details
            if let d = decision {
                VStack(alignment: .leading, spacing: 8) {
                    if let reason = d.exclusionReason {
                        LabeledContent("Exclusion Reason", value: reason.rawValue)
                            .font(.subheadline)
                    }
                    if !d.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(d.notes).font(.body)
                        }
                    }
                    Text("Decided: \(d.decidedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            Divider()

            // Abstract (same for both, side by side for context)
            ScrollView {
                Text(study.abstract)
                    .font(.body)
                    .lineSpacing(4)
                    .padding()
                    .textSelection(.enabled)
            }
        }
    }

    private func decisionBadge(_ decision: ScreeningDecision) -> some View {
        Group {
            switch decision {
            case .include:
                Label("Include", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .exclude:
                Label("Exclude", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            case .maybe:
                Label("Maybe", systemImage: "questionmark.circle.fill").foregroundStyle(.orange)
            case .pending:
                Label("Pending", systemImage: "clock.fill").foregroundStyle(.gray)
            }
        }
        .font(.subheadline.bold())
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text("Adjudicator Notes")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("Enter rationale for the final decision…", text: $adjudicatorNotes)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(spacing: 8) {
                Text("Accept decision of:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        onResolve(1)
                        dismiss()
                    } label: {
                        Label("Reviewer 1 (\(project.reviewer1Name))",
                              systemImage: "person.fill")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button {
                        onResolve(2)
                        dismiss()
                    } label: {
                        Label("Reviewer 2 (\(project.reviewer2Name))",
                              systemImage: "person.fill.2")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
