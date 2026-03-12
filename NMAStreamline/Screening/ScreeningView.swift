import SwiftUI
import SwiftData

/// Main screening view — shows the current abstract with AI hints and
/// keyboard-driven navigation (J: Include, K: Exclude, L: Maybe, U: Undo).
struct ScreeningView: View {
    @ObservedObject var viewModel: ScreeningViewModel
    @State private var showExclusionPicker = false
    @State private var selectedExclusionReason: ExclusionReason?
    @State private var reviewerNotes = ""

    var body: some View {
        if viewModel.queue.isEmpty {
            emptyStateView
        } else if viewModel.currentIndex >= viewModel.queue.count {
            completionView
        } else {
            mainScreeningLayout
                .sheet(isPresented: $viewModel.showConflictResolution) {
                    if let study = viewModel.conflictStudy {
                        ConflictResolutionView(
                            study: study,
                            project: viewModel.project,
                            onResolve: { winnerIdx in
                                viewModel.resolveConflict(winnerIndex: winnerIdx)
                            }
                        )
                    }
                }
        }
    }

    // MARK: - Main layout

    private var mainScreeningLayout: some View {
        HSplitView {
            // Left: Abstract panel
            abstractPanel
                .frame(minWidth: 400)

            // Right: AI suggestion panel
            aiPanel
                .frame(width: 280)
        }
        .toolbar { screeningToolbar }
        .focusable()
        .onKeyPress { press in
            viewModel.handleKeyPress(String(press.characters))
            return .handled
        }
    }

    // MARK: - Abstract panel

    private var abstractPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Progress bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Screening Progress")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.undoStack.count) / \(viewModel.queue.count + viewModel.undoStack.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: viewModel.progress)
                }
                .padding(.horizontal)

                Divider()

                if let study = viewModel.currentStudy {
                    studyCard(study)
                }

                // Action buttons
                actionBar

            }
            .padding(.vertical)
        }
    }

    private func studyCard(_ study: Study) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            // Title
            Text(study.title)
                .font(.title3).bold()
                .padding(.horizontal)

            // Meta info
            if let citation = study.primaryCitation {
                HStack(spacing: 12) {
                    Label(citation.firstAuthor.isEmpty ? "Unknown" : citation.firstAuthor,
                          systemImage: "person")
                    if let year = citation.year {
                        Label(String(year), systemImage: "calendar")
                    }
                    Label(citation.source.rawValue, systemImage: "square.stack")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }

            Divider()

            // Abstract
            Text(study.abstract.isEmpty ? "No abstract available." : study.abstract)
                .font(.body)
                .lineSpacing(4)
                .padding(.horizontal)
                .textSelection(.enabled)

            // AI-extracted outcomes ghost tags
            if let suggestion = viewModel.currentAISuggestion,
               !suggestion.extractedOutcomes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Outcomes detected by AI", systemImage: "wand.and.stars")
                        .font(.caption).foregroundStyle(.purple)
                    FlowLayout(spacing: 6) {
                        ForEach(suggestion.extractedOutcomes, id: \.self) { outcome in
                            outcomeTag(outcome, isLinker: suggestion.potentialLinkerOutcomes.contains(outcome))
                        }
                    }
                }
                .padding()
                .background(.purple.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Reviewer notes
            GroupBox("Notes") {
                TextEditor(text: $reviewerNotes)
                    .frame(minHeight: 60)
                    .font(.body)
            }
            .padding(.horizontal)
        }
    }

    private func outcomeTag(_ outcome: String, isLinker: Bool) -> some View {
        HStack(spacing: 4) {
            if isLinker {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text(outcome.capitalized)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isLinker ? .orange.opacity(0.15) : .blue.opacity(0.10))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isLinker ? .orange.opacity(0.4) : .blue.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.include()
            } label: {
                Label("Include  ⌨ J", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("j", modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                showExclusionPicker = true
            } label: {
                Label("Exclude  ⌨ K", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("k", modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Button {
                viewModel.maybe()
            } label: {
                Label("Maybe  ⌨ L", systemImage: "questionmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("l", modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button {
                viewModel.undo()
            } label: {
                Label("Undo  ⌨ U", systemImage: "arrow.uturn.backward.circle")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("u", modifiers: [])
            .buttonStyle(.bordered)
            .disabled(viewModel.undoStack.isEmpty)
        }
        .padding(.horizontal)
        .popover(isPresented: $showExclusionPicker) {
            exclusionReasonPicker
        }
    }

    private var exclusionReasonPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Exclusion Reason")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(ExclusionReason.allCases, id: \.self) { reason in
                Button(reason.rawValue) {
                    viewModel.exclude(reason: reason)
                    showExclusionPicker = false
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - AI panel

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("AI Assistant", systemImage: "brain")
                    .font(.headline)
                Spacer()
                if viewModel.isLoadingAI {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding()

            Divider()

            if let suggestion = viewModel.currentAISuggestion {
                aiSuggestionPanel(suggestion)
            } else {
                Text("Configure PICO criteria in Project Settings to enable AI screening hints.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Spacer()
        }
        .background(.background.secondary)
    }

    private func aiSuggestionPanel(_ suggestion: AIScreeningSuggestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Recommendation badge
                HStack {
                    recommendationBadge(suggestion.recommendation)
                    Text(String(format: "%.0f%% confidence", suggestion.confidence * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)

                // Reasoning
                if !suggestion.reasoning.isEmpty {
                    GroupBox("Analysis") {
                        Text(suggestion.reasoning)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                }

                // PICO flags
                if !suggestion.picoFlags.isEmpty {
                    GroupBox("PICO Issues") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(suggestion.picoFlags.indices, id: \.self) { idx in
                                let flag = suggestion.picoFlags[idx]
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: flag.isCritical ? "exclamationmark.triangle.fill" : "info.circle")
                                        .foregroundStyle(flag.isCritical ? .red : .orange)
                                        .font(.caption)
                                    Text(flag.issue)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Linker outcomes
                if !suggestion.potentialLinkerOutcomes.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Potential Linker Outcomes", systemImage: "link.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            ForEach(suggestion.potentialLinkerOutcomes, id: \.self) { outcome in
                                Text("• \(outcome.capitalized)")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

            }
            .padding(.vertical)
        }
    }

    private func recommendationBadge(_ rec: AIScreeningSuggestion.Recommendation) -> some View {
        Group {
            switch rec {
            case .include:
                Label("Suggest Include", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .exclude:
                Label("Suggest Exclude", systemImage: "xmark.seal.fill")
                    .foregroundStyle(.red)
            case .uncertain:
                Label("Uncertain", systemImage: "questionmark.diamond.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption.bold())
        .padding(6)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var screeningToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("\(viewModel.remainingCount) remaining")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("Stage: \(viewModel.stage.rawValue)") {
                Button("Abstract Screening") { /* switch stage */ }
                Button("Full-Text Screening") { /* switch stage */ }
            }
        }
    }

    // MARK: - Empty / completion states

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Studies to Screen",
            systemImage: "tray",
            description: Text("Import citations first, then return to start screening.")
        )
    }

    private var completionView: some View {
        ContentUnavailableView(
            "Screening Complete",
            systemImage: "checkmark.circle.fill",
            description: Text("All \(viewModel.undoStack.count) studies have been reviewed in this pass.")
        )
    }
}
