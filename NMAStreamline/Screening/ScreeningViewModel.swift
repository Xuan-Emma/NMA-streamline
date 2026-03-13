import Foundation
import SwiftData
import Combine

/// View model for the abstract / full-text screening workflow.
/// Manages keyboard navigation, dual-review logic, pre-fetching, and AI hints.
@MainActor
final class ScreeningViewModel: ObservableObject {

    // MARK: - State

    @Published var currentIndex: Int = 0
    @Published var queue: [Study] = []
    @Published var currentAISuggestion: AIScreeningSuggestion?
    @Published var isLoadingAI = false
    @Published var showConflictResolution = false
    @Published var conflictStudy: Study?
    @Published var undoStack: [UndoItem] = []

    var project: NMAProject
    var reviewerIndex: Int    // 1 or 2
    var stage: ScreeningStage
    private let context: ModelContext
    private let ai: any AIAssistantProtocol

    // Pre-fetch cache: next N abstracts with AI suggestions
    private var prefetchCache: [UUID: AIScreeningSuggestion] = [:]
    private let prefetchAhead = 10

    // MARK: - Init

    init(
        project: NMAProject,
        reviewerIndex: Int,
        stage: ScreeningStage = .abstract,
        context: ModelContext,
        ai: any AIAssistantProtocol = RuleBasedAIAssistant()
    ) {
        self.project = project
        self.reviewerIndex = reviewerIndex
        self.stage = stage
        self.context = context
        self.ai = ai
        self.queue = buildQueue()
    }

    // MARK: - Queue management

    private func buildQueue() -> [Study] {
        project.studies.filter { study in
            switch stage {
            case .abstract:
                return study.status == .unscreened && existingDecision(for: study) == nil
            case .fullText:
                return study.status == .includedAbstract && existingDecision(for: study) == nil
            }
        }
    }

    var currentStudy: Study? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var progress: Double {
        let total = queue.count + undoStack.count
        guard total > 0 else { return 1.0 }
        return Double(undoStack.count) / Double(total)
    }

    var remainingCount: Int { max(0, queue.count - currentIndex) }

    // MARK: - Decision recording

    func include() { record(decision: .include, reason: nil) }
    func exclude(reason: ExclusionReason? = nil) { record(decision: .exclude, reason: reason) }
    func maybe() { record(decision: .maybe, reason: nil) }

    func record(decision: ScreeningDecision, reason: ExclusionReason?) {
        guard let study = currentStudy else { return }

        let reviewerName = reviewerIndex == 1 ? project.reviewer1Name : project.reviewer2Name
        let reviewerDecision = ReviewerDecision(
            reviewerIndex: reviewerIndex,
            reviewerName: reviewerName,
            decision: decision,
            exclusionReason: reason,
            stage: stage
        )
        study.decisions.append(reviewerDecision)
        context.insert(reviewerDecision)

        // Update study status if both reviewers decided
        updateStudyStatus(study)

        undoStack.append(UndoItem(study: study, decision: reviewerDecision))
        try? context.save()

        advance()
    }

    /// Keyboard shortcut: J = Include, K = Exclude, L = Maybe, U = Undo
    func handleKeyPress(_ key: String) {
        switch key.uppercased() {
        case "J": include()
        case "K": exclude()
        case "L": maybe()
        case "U": undo()
        default: break
        }
    }

    func undo() {
        guard let item = undoStack.popLast() else { return }
        // Remove the decision
        item.study.decisions.removeAll { $0.id == item.decision.id }
        context.delete(item.decision)
        try? context.save()

        // Re-queue the study
        if currentIndex > 0 { currentIndex -= 1 }
        refreshQueue()
    }

    private func advance() {
        prefetchCache.removeValue(forKey: currentStudy?.id ?? UUID())
        currentIndex += 1
        loadAISuggestion()
        triggerPrefetch()
    }

    private func refreshQueue() {
        queue = buildQueue()
    }

    // MARK: - Status update (dual-review)

    private func updateStudyStatus(_ study: Study) {
        let d1 = study.decisions.first(where: { $0.reviewerIndex == 1 && $0.screeningStage == stage })
        let d2 = study.decisions.first(where: { $0.reviewerIndex == 2 && $0.screeningStage == stage })

        guard let dec1 = d1 else { return }

        if let dec2 = d2 {
            // Both reviewers have decided
            if dec1.decision == dec2.decision {
                applyConsensusDecision(dec1.decision, reason: dec1.exclusionReason, to: study)
            } else {
                // Conflict — flag for adjudication
                conflictStudy = study
                showConflictResolution = true
            }
        } else if reviewerIndex == 1 && !project.blindMode {
            // Single reviewer mode OR non-blind first reviewer
            applyConsensusDecision(dec1.decision, reason: dec1.exclusionReason, to: study)
        }
    }

    private func applyConsensusDecision(_ decision: ScreeningDecision, reason: ExclusionReason? = nil, to study: Study) {
        switch (decision, stage) {
        case (.include, .abstract): study.status = .includedAbstract
        case (.exclude, .abstract):
            study.status = .excludedAbstract
            if let reason { study.primaryExclusionReason = reason }
        case (.include, .fullText): study.status = .included
        case (.exclude, .fullText):
            study.status = .excludedFullText
            if let reason { study.primaryExclusionReason = reason }
        case (.maybe, _): study.status = .maybe
        default: break
        }
    }

    func resolveConflict(winnerIndex: Int, reason: ExclusionReason? = nil) {
        guard let study = conflictStudy else { return }
        let winnerDecision = winnerIndex == 1 ? study.decision1 : study.decision2
        if let d = winnerDecision {
            // Use the explicitly supplied reason; fall back to the winning reviewer's reason.
            applyConsensusDecision(d.decision, reason: reason ?? d.exclusionReason, to: study)
        }
        try? context.save()
        showConflictResolution = false
        conflictStudy = nil
    }

    // MARK: - AI integration

    func loadAISuggestion() {
        guard let study = currentStudy,
              let pico = project.picoCriteria else {
            currentAISuggestion = nil
            return
        }

        // Use cache if available
        if let cached = prefetchCache[study.id] {
            currentAISuggestion = cached
            return
        }

        isLoadingAI = true
        // Capture PersistentIdentifier (Sendable) and UUID instead of the model
        // object so that Swift 6 isolation rules are satisfied.
        let persistentID = study.persistentModelID
        let studyUUID    = study.id
        Task { [weak self] in
            guard let self else { return }
            // Re-fetch the model inside the task from the main-actor context.
            guard let fetchedStudy = try? self.context.model(for: persistentID) as? Study else {
                self.isLoadingAI = false
                return
            }
            let citation   = fetchedStudy.primaryCitation ?? Citation(title: fetchedStudy.title)
            let suggestion = await self.ai.suggest(for: citation, pico: pico)
            // Only apply if the queue has not moved on since we started.
            if self.currentStudy?.id == studyUUID {
                self.currentAISuggestion = suggestion
            }
            self.isLoadingAI = false
        }
    }

    private func triggerPrefetch() {
        guard let pico = project.picoCriteria else { return }
        let start = currentIndex + 1
        let end = min(start + prefetchAhead, queue.count)
        guard start < end else { return }

        // Capture Sendable value types (UUID + Strings) instead of @Model objects
        // to comply with Swift 6 strict-concurrency requirements.
        let studiesToPrefetch: [(id: UUID, title: String, abstract: String)] =
            (start..<end).compactMap { idx in
                let study = queue[idx]
                guard prefetchCache[study.id] == nil else { return nil }
                let citation = study.primaryCitation
                return (study.id,
                        citation?.title ?? study.title,
                        citation?.abstract ?? "")
            }

        guard !studiesToPrefetch.isEmpty else { return }

        // Snapshot ai to avoid accessing a @MainActor-isolated property
        // from inside a Task.detached (Swift 6 strict concurrency).
        let aiAssistant = ai
        Task.detached(priority: .background) { [weak self, pico] in
            for item in studiesToPrefetch {
                // Build a lightweight, non-persisted citation for the AI.
                let tempCitation = Citation(title: item.title, abstract: item.abstract)
                if let suggestion = await aiAssistant.suggest(for: tempCitation, pico: pico) {
                    await MainActor.run { self?.prefetchCache[item.id] = suggestion }
                }
            }
        }
    }

    // MARK: - Helpers

    private func existingDecision(for study: Study) -> ReviewerDecision? {
        study.decisions.first(where: {
            $0.reviewerIndex == reviewerIndex && $0.screeningStage == stage
        })
    }
}

// MARK: - Supporting types

struct UndoItem {
    let study: Study
    let decision: ReviewerDecision
}
