import SwiftUI

/// Form to create a new project.
struct NewProjectSheet: View {
    let onSave: (String, String, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var reviewer1 = "Reviewer 1"
    @State private var reviewer2 = "Reviewer 2"
    @State private var blindMode = true
    @State private var showPICO = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Details") {
                    LabeledContent("Title") {
                        TextField("e.g., Antidepressants for MDD", text: $title)
                    }
                }

                Section("Reviewers") {
                    LabeledContent("Reviewer 1") {
                        TextField("Name", text: $reviewer1)
                    }
                    LabeledContent("Reviewer 2") {
                        TextField("Name", text: $reviewer2)
                    }
                    Toggle("Blind Mode", isOn: $blindMode)
                    if blindMode {
                        Text("Decisions are hidden from each reviewer until both have decided.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New NMA Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave(title, reviewer1, reviewer2, blindMode)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

// MARK: - PICO Settings

/// Allows editing PICO criteria stored in the project.
struct PICOSettingsView: View {
    @Bindable var project: NMAProject

    @State private var pico: PICOCriteriaData

    init(project: NMAProject) {
        self.project = project
        self._pico = State(initialValue: project.picoCriteria ?? PICOCriteriaData())
    }

    var body: some View {
        Form {
            Section("Population (P)") {
                TextField("e.g., Adults with major depressive disorder", text: $pico.population)
            }

            Section("Interventions (I)") {
                tokenEditor("Add treatment…", tokens: $pico.intervention)
            }

            Section("Comparators (C)") {
                tokenEditor("Add comparator…", tokens: $pico.comparator)
            }

            Section("Outcomes (O)") {
                tokenEditor("Add outcome…", tokens: $pico.outcomes)
            }

            Section("Study Design") {
                tokenEditor("e.g., RCT", tokens: $pico.studyDesign)
            }

            Section("Additional Criteria") {
                TextEditor(text: $pico.additionalCriteria)
                    .frame(minHeight: 60)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("PICO Criteria & Settings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    project.picoCriteria = pico
                    project.updatedAt = Date()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func tokenEditor(_ placeholder: String, tokens: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(tokens.wrappedValue.indices, id: \.self) { idx in
                    HStack(spacing: 4) {
                        Text(tokens.wrappedValue[idx])
                            .font(.callout)
                        Button {
                            tokens.wrappedValue.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.12))
                    .cornerRadius(16)
                }
            }

            HStack {
                TokenInputField(placeholder: placeholder) { newToken in
                    let trimmed = newToken.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && !tokens.wrappedValue.contains(trimmed) {
                        tokens.wrappedValue.append(trimmed)
                    }
                }
            }
        }
    }
}

// MARK: - Token input field

struct TokenInputField: View {
    let placeholder: String
    let onCommit: (String) -> Void

    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .onSubmit {
                onCommit(text)
                text = ""
            }
    }
}

// MARK: - Flow layout (wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width + spacing > width && rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
