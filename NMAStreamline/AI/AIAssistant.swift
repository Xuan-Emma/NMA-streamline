import Foundation

/// AI screening suggestion produced for a single citation.
struct AIScreeningSuggestion {
    enum Recommendation {
        case include, exclude, uncertain
    }

    let recommendation: Recommendation
    let confidence: Double        // 0.0 – 1.0
    let reasoning: String
    let picoFlags: [PICOFlag]
    let extractedOutcomes: [String]
    let potentialLinkerOutcomes: [String]
}

struct PICOFlag {
    enum Component { case population, intervention, comparator, outcome, studyDesign }
    let component: Component
    let issue: String
    let isCritical: Bool
}

// MARK: - Protocol

/// Abstract interface for a local AI assistant.
/// Concrete implementations can use CoreML, MLX-Swift, or a rule-based engine.
protocol AIAssistantProtocol: Actor {
    func isAvailable() async -> Bool
    func suggest(
        for citation: Citation,
        pico: PICOCriteriaData
    ) async -> AIScreeningSuggestion?

    func extractOutcomes(from abstract: String) async -> [String]
    func identifyLinkerOutcomes(
        outcomes: [String],
        networkInterventions: [String]
    ) async -> [String]
}

// MARK: - Rule-based fallback implementation

/// A fast, offline, rule-based AI assistant that works without a loaded LLM.
/// It uses keyword matching against the PICO criteria and is always available.
actor RuleBasedAIAssistant: AIAssistantProtocol {

    func isAvailable() async -> Bool { true }

    func suggest(
        for citation: Citation,
        pico: PICOCriteriaData
    ) async -> AIScreeningSuggestion? {
        let text = (citation.title + " " + citation.abstract).lowercased()
        var flags: [PICOFlag] = []
        var confidence = 0.5

        // --- Study design check ---
        let designKeywords = pico.studyDesign.map { $0.lowercased() }
        let hasDesign = designKeywords.isEmpty ||
            designKeywords.contains(where: { text.contains($0) })

        if !hasDesign {
            flags.append(PICOFlag(
                component: .studyDesign,
                issue: "No mention of required study design: \(pico.studyDesign.joined(separator: "/"))",
                isCritical: true
            ))
        }

        // --- Intervention check ---
        let interventions = pico.intervention.map { $0.lowercased() }
        let hasIntervention = interventions.isEmpty ||
            interventions.contains(where: { text.contains($0) })

        if !hasIntervention {
            flags.append(PICOFlag(
                component: .intervention,
                issue: "No mention of target interventions",
                isCritical: true
            ))
        }

        // --- Population check ---
        let population = pico.population.lowercased()
        let hasPopulation = population.isEmpty || text.contains(population) ||
            population.components(separatedBy: " ").allSatisfy { text.contains($0) }

        if !hasPopulation {
            flags.append(PICOFlag(
                component: .population,
                issue: "Population mismatch: '\(pico.population)' not clearly stated",
                isCritical: false
            ))
        }

        // --- Outcome check ---
        let outcomeTerms = pico.outcomes.map { $0.lowercased() }
        let hasOutcome = outcomeTerms.isEmpty ||
            outcomeTerms.contains(where: { text.contains($0) })

        if !hasOutcome {
            flags.append(PICOFlag(
                component: .outcome,
                issue: "No mention of relevant outcomes",
                isCritical: false
            ))
        }

        // --- Determine recommendation ---
        let criticalFails = flags.filter { $0.isCritical }.count
        let recommendation: AIScreeningSuggestion.Recommendation
        if criticalFails >= 2 {
            recommendation = .exclude
            confidence = 0.75
        } else if criticalFails == 1 {
            recommendation = .uncertain
            confidence = 0.55
        } else if flags.isEmpty {
            recommendation = .include
            confidence = 0.70
        } else {
            recommendation = .uncertain
            confidence = 0.50
        }

        // --- Outcome extraction ---
        let extracted = await extractOutcomes(from: citation.abstract)

        // --- Linker identification ---
        let linkers = await identifyLinkerOutcomes(
            outcomes: extracted,
            networkInterventions: pico.intervention + pico.comparator
        )

        let reasoning = flags.isEmpty
            ? "Abstract appears to meet PICO criteria."
            : flags.map { "• \($0.component): \($0.issue)" }.joined(separator: "\n")

        return AIScreeningSuggestion(
            recommendation: recommendation,
            confidence: confidence,
            reasoning: reasoning,
            picoFlags: flags,
            extractedOutcomes: extracted,
            potentialLinkerOutcomes: linkers
        )
    }

    func extractOutcomes(from abstract: String) async -> [String] {
        // Simple heuristic: look for common outcome-related terms
        let outcomePatterns = [
            "mortality", "survival", "response rate", "remission",
            "progression", "adverse event", "quality of life", "pain",
            "blood pressure", "hemoglobin", "hba1c", "ldl", "hdl",
            "cardiovascular", "stroke", "hospitalization", "relapse",
            "overall survival", "progression-free survival", "event-free survival"
        ]

        let lower = abstract.lowercased()
        return outcomePatterns.filter { lower.contains($0) }
    }

    func identifyLinkerOutcomes(
        outcomes: [String],
        networkInterventions: [String]
    ) async -> [String] {
        // Linkers are outcomes that could connect treatments via indirect comparisons.
        // Heuristic: any outcome that is objective and measurable is a potential linker.
        let linkerKeywords = ["survival", "mortality", "response", "remission", "progression", "hba1c"]
        return outcomes.filter { outcome in
            linkerKeywords.contains(where: { outcome.contains($0) })
        }
    }
}

// MARK: - CoreML / MLX stub

/// Placeholder for a full LLM-powered assistant using CoreML or MLX-Swift.
/// Replace `RuleBasedAIAssistant` with this class once a model is bundled.
actor CoreMLAIAssistant: AIAssistantProtocol {
    // MARK: - Configuration

    /// The name of the CoreML compiled model bundle (without `.mlmodelc` extension).
    /// Update this constant when bundling a different model.
    static let modelBundleName = "NMAScreener"

    // Model loading state
    private var isModelLoaded = false

    func isAvailable() async -> Bool {
        // Check if the CoreML model is present in the bundle
        let modelURL = Bundle.main.url(
            forResource: Self.modelBundleName,
            withExtension: "mlmodelc"
        )
        return modelURL != nil
    }

    func suggest(for citation: Citation, pico: PICOCriteriaData) async -> AIScreeningSuggestion? {
        // TODO: Implement CoreML / MLX-Swift inference
        // 1. Build prompt from citation.title + citation.abstract + pico.promptDescription
        // 2. Run inference via MLX-Swift or CoreML pipeline
        // 3. Parse structured JSON response
        // For now, delegate to rule-based assistant
        let fallback = RuleBasedAIAssistant()
        return await fallback.suggest(for: citation, pico: pico)
    }

    func extractOutcomes(from abstract: String) async -> [String] {
        let fallback = RuleBasedAIAssistant()
        return await fallback.extractOutcomes(from: abstract)
    }

    func identifyLinkerOutcomes(outcomes: [String], networkInterventions: [String]) async -> [String] {
        let fallback = RuleBasedAIAssistant()
        return await fallback.identifyLinkerOutcomes(outcomes: outcomes, networkInterventions: networkInterventions)
    }
}
